//============================================================================
//  vax_core.v - r-vax system for MiSTer (replaces sbi.v of the original board).
//
//      cpu --- vcache (aligner) --- mmu --- vax_io --+-- vax_cache (M10K) --- vax_sdram --- 32 MB
//                                                    |
//                                                    +-- vax_sbi: SBIA 0 --- SBI --+-- RH780 (vax_mba)
//                                                                                  |   RP07 0, 1 (vax_rp07)
//                                                                                  +-- DW780 (vax_uba)
//                                                                                      Unibus: empty
//
//  The RP07s' disks are images on the SD card, served by the HPS (hps_io's
//  block devices 0 and 1; the dk_* ports).
//
//  A second master (the HPS program loader or the power-on memory test) can
//  take the SDRAM over while the CPU is held in reset; dma_en switches the
//  controller between the two. The cache is reset with the CPU, so whatever
//  that master writes is visible afterwards.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_core #(
	parameter CLK_HZ   = 50000000,
	parameter CACHEIDX = 10,         // 2^CACHEIDX lines of 16 bytes
	parameter TSCALE   = 1           // disk mechanical times / TSCALE (simulation)
) (
	input             clk,
	input             rst_mem,       // SDRAM controller reset (power-up only)
	input             rst_cpu,       // CPU and cache reset
	output            mem_ready,
	input       [1:0] rdphase,      // SDRAM read capture phase

	// second bus master (loader / memory test), active while rst_cpu is held
	input             dma_en,
	input             dma_req,
	input             dma_we,
	input      [22:0] dma_adr,
	input      [31:0] dma_dat,
	input       [3:0] dma_sel,
	output            dma_done,
	output     [31:0] dma_rdat,
	output      [1:0] dma_ridx,
	output            dma_rstb,

	// console serial lines
	input             tti_rx,
	output            tto_tx,
	input             halt_req,      // console halt request (Ctrl+P, OSD): one clock
	input             con_boot,      // the console begins a bootstrap: one clock

	// fault finding (OSD), taken at processor initialization:
	// <0> cache off, <1> translation buffer off
	input       [1:0] diag,

	// performance counters
	output            stat_hit,
	output            stat_miss,
	output            cpu_halted,

	// SDRAM (split data bus)
	output     [12:0] sd_a,
	output      [1:0] sd_ba,
	output            sd_ncs,
	output            sd_nras,
	output            sd_ncas,
	output            sd_nwe,
	output            sd_dqml,
	output            sd_dqmh,
	output     [15:0] sd_dq_o,
	output            sd_dq_oe,
	input      [15:0] sd_dq_i,

	// disk images: hps_io block devices 0 and 1 (RP07 units 0 and 1)
	output     [31:0] dk_lba0,
	output     [31:0] dk_lba1,
	output      [1:0] dk_rd,
	output      [1:0] dk_wr,
	input       [1:0] dk_ack,
	input       [8:0] dk_buff_addr,
	input       [7:0] dk_buff_dout,
	input             dk_buff_wr,
	output      [7:0] dk_buff_din0,
	output      [7:0] dk_buff_din1,
	input       [1:0] img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output            disk_active
);

	/* CPU */
	wire        mcheck;
	wire        io_err;
	wire  [4:0] io_ipl, pamm_rd;
	wire [31:0] io_mstat2, io_mear;
	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire        cpu_write, cpu_stb, cpu_ack;
	wire        cpu_pmem;
	wire  [1:0] cpu_size;
	wire        cpu_wint, cpu_probe, cpu_con;
	wire  [1:0] cpu_mode;
	wire        mmu_flt, mmu_tnv, mmu_prog;
	wire [31:0] mmu_va;
	wire  [2:0] mmu_par;
	wire        ipr_we;
	wire  [6:0] ipr_adr;
	wire [31:0] ipr_dat;

	cpu cpu (
		.clk        (clk),
		.rst        (rst_cpu),

		.CPU_ADR_O  (cpu_addr),
		.CPU_DAT_O  (cpu_wdata),
		.CPU_WE_O   (cpu_write),
		.CPU_STB_O  (cpu_stb),
		.CPU_DAT_I  (cpu_rdata),
		.CPU_ACK_I  (cpu_ack),

		.CPU_SIZE_O (cpu_size),
		.CPU_PMEM_O (cpu_pmem),

		.CPU_WINT_O (cpu_wint),
		.CPU_PROBE_O(cpu_probe),
		.CPU_MODE_O (cpu_mode),
		.CPU_CON_O  (cpu_con),
		.CPU_MMF_I  (mmu_flt),
		.MMU_VA_I   (mmu_va),
		.MMU_PAR_I  (mmu_par),
		.MMU_TNV_I  (mmu_tnv),
		.MMU_PROG_I (mmu_prog),
		.IPR_WE_O   (ipr_we),
		.IPR_ADR_O  (ipr_adr),
		.IPR_DAT_O  (ipr_dat),

		.tto_tx     (tto_tx),
		.tti_rx     (tti_rx),
		.halt_req   (halt_req),
		.con_boot   (con_boot),
		.cpu_halted (cpu_halted),
		.cpu_mcheck (mcheck),

		.IO_ERR_I   (io_err),
		.IO_MSTAT2_I(io_mstat2),
		.IO_MEAR_I  (io_mear),
		.IO_IPL_I   (io_ipl),
		.PAMM_I     (pamm_rd)
	);

	/* alignment unit: splits unaligned/partial accesses into longwords */
	wire        va_write, va_stb, va_ack;
	wire [31:0] va_addr, va_wdata, va_rdata;
	wire  [3:0] va_sel;

	vcache vcache (
		.clk        (clk),
		.rst        (rst_cpu),

		.IN_STB_I   (cpu_stb),
		.IN_ADR_I   (cpu_addr),
		.IN_DAT_I   (cpu_wdata),
		.IN_WE_I    (cpu_write),
		.IN_DAT_O   (cpu_rdata),
		.IN_ACK_O   (cpu_ack),

		.in_passthru(cpu_pmem),
		.in_sz      (cpu_size),
		.in_mcheck  (mcheck),
		.in_flt     (mmu_flt),

		.UT_STB_O   (va_stb),
		.UT_ADR_O   (va_addr),
		.UT_DAT_O   (va_wdata),
		.UT_SEL_O   (va_sel),
		.UT_WE_O    (va_write),
		.UT_DAT_I   (va_rdata),
		.UT_ACK_I   (va_ack)
	);

	/* memory management: translation buffer, page table walks, faults */
	wire        bus_write, bus_stb, bus_ack;
	wire [31:0] bus_addr, bus_wdata, bus_rdata;
	wire  [3:0] bus_sel;

	mmu mmu (
		.clk        (clk),
		.rst        (rst_cpu),

		.IN_STB_I   (va_stb),
		.IN_WE_I    (va_write),
		.IN_ADR_I   (va_addr),
		.IN_DAT_I   (va_wdata),
		.IN_SEL_I   (va_sel),
		.IN_DAT_O   (va_rdata),
		.IN_ACK_O   (va_ack),

		.cpu_stb    (cpu_stb),
		.in_pmem    (cpu_pmem),
		.in_wint    (cpu_wint),
		.in_probe   (cpu_probe),
		.in_mode    (cpu_mode),
		.in_con     (cpu_con),
		.in_mcheck  (mcheck),
		.tb_off     (diag[1]),

		.ipr_we     (ipr_we),
		.ipr_adr    (ipr_adr),
		.ipr_dat    (ipr_dat),

		.flt        (mmu_flt),
		.flt_va     (mmu_va),
		.flt_par    (mmu_par),
		.flt_tnv    (mmu_tnv),
		.progress   (mmu_prog),
		.mapen_o    (),

		.UT_STB_O   (bus_stb),
		.UT_WE_O    (bus_write),
		.UT_ADR_O   (bus_addr),
		.UT_DAT_O   (bus_wdata),
		.UT_SEL_O   (bus_sel),
		.UT_DAT_I   (bus_rdata),
		.UT_ACK_I   (bus_ack)
	);

	/*
	 * Behind the MMU: installed memory (the cache) and the 8600's I/O
	 * side (vax_io.v, vax_sbi.v).
	 */
	wire        mem_stb, mem_we, mem_ack;
	wire [31:0] mem_adr, mem_wdat, mem_rdat;
	wire [21:0] mem_pre;
	wire  [3:0] mem_sel;

	vax_io #(.CLK_HZ(CLK_HZ), .MEMMB(32), .TSCALE(TSCALE)) io (
		.clk      (clk),
		.rst      (rst_cpu),

		.stb      (bus_stb),
		.we       (bus_write),
		.adr      (bus_addr),
		.wdat     (bus_wdata),
		.sel      (bus_sel),
		.rdat     (bus_rdata),
		.ack      (bus_ack),

		.ipr_we   (ipr_we),
		.ipr_adr  (ipr_adr),
		.ipr_dat  (ipr_dat),
		.pamm_rd  (pamm_rd),

		.m_stb    (mem_stb),
		.m_we     (mem_we),
		.m_adr    (mem_adr),
		.m_pre    (mem_pre),
		.m_wdat   (mem_wdat),
		.m_sel    (mem_sel),
		.m_rdat   (mem_rdat),
		.m_ack    (mem_ack),

		.io_err   (io_err),
		.io_mstat2(io_mstat2),
		.io_mear  (io_mear),
		.io_ipl   (io_ipl),

		.sd_lba0      (dk_lba0),
		.sd_lba1      (dk_lba1),
		.sd_rd        (dk_rd),
		.sd_wr        (dk_wr),
		.sd_ack       (dk_ack),
		.sd_buff_addr (dk_buff_addr),
		.sd_buff_dout (dk_buff_dout),
		.sd_buff_wr   (dk_buff_wr),
		.sd_buff_din0 (dk_buff_din0),
		.sd_buff_din1 (dk_buff_din1),
		.img_mounted  (img_mounted),
		.img_readonly (img_readonly),
		.img_size     (img_size),
		.disk_active  (disk_active),
		// the Unibus: no devices on it yet
		.ub_a     (),
		.ub_c     (),
		.ub_d     (),
		.ub_msyn  (),
		.ub_ssyn  (1'b0),
		.ub_rd    (16'd0),
		.dv_npr   (1'b0),
		.dv_npg   (),
		.dv_a     (18'd0),
		.dv_c     (2'd0),
		.dv_d     (16'd0),
		.dv_msyn  (1'b0),
		.dv_ssyn  (),
		.dv_rd    (),
		.ub_br    (4'd0),
		.ub_bg    (),
		.ub_intr  (1'b0),
		.ub_vec   (16'd0),
		.ub_init  ()
	);

	/* memory: 32 MB at physical 0x00000000-0x01FFFFFF */

	wire        c_req, c_we;
	wire [22:0] c_adr;
	wire [31:0] c_dat;
	wire  [3:0] c_sel;

	/* SDRAM port arbitration nets (driven below) */
	wire        m_busy;
	wire        cache_done, cache_rstb;
	wire        m_done;
	wire [31:0] m_rdat;
	wire  [1:0] m_ridx;
	wire        m_rstb;

	vax_cache #(.IDXB(CACHEIDX), .AB(23)) cache (
		.clk      (clk),
		.rst      (rst_cpu),

		.STB_I    (mem_stb),
		.ADR_I    (mem_adr),
		.PRE_I    (mem_pre),
		.DIS_I    (diag[0]),
		.DAT_I    (mem_wdat),
		.SEL_I    (mem_sel),
		.WE_I     (mem_we),
		.DAT_O    (mem_rdat),
		.ACK_O    (mem_ack),

		.req      (c_req),
		.req_we   (c_we),
		.req_adr  (c_adr),
		.req_dat  (c_dat),
		.req_sel  (c_sel),
		.req_done (cache_done),
		.rd_dat   (m_rdat),
		.rd_idx   (m_ridx),
		.rd_stb   (cache_rstb),

		.stat_hit (stat_hit),
		.stat_miss(stat_miss)
	);

	/*
	 * SDRAM port arbitration: the loader/memory test or the cache.
	 * The owner is latched when the controller accepts the request, so a
	 * transaction that was already in flight when dma_en changed still
	 * acknowledges the master that started it instead of the new one.
	 */
	wire        m_req = dma_en ? dma_req : c_req;
	wire        m_we  = dma_en ? dma_we  : c_we;
	wire [22:0] m_adr = dma_en ? dma_adr : c_adr;
	wire [31:0] m_dat = dma_en ? dma_dat : c_dat;
	wire  [3:0] m_sel = dma_en ? dma_sel : c_sel;

	reg         own_dma;
	initial     own_dma = 1'b0;
	always @(posedge clk)
		if (!m_busy) own_dma <= dma_en;      // latched with the request

	assign dma_done = own_dma & m_done;
	assign dma_rdat = m_rdat;
	assign dma_ridx = m_ridx;
	assign dma_rstb = own_dma & m_rstb;

	assign cache_done = ~own_dma & m_done;
	assign cache_rstb = ~own_dma & m_rstb;

	vax_sdram #(.CLK_HZ(CLK_HZ)) sdram (
		.clk      (clk),
		.rst      (rst_mem),
		.ready    (mem_ready),
		.rdphase  (rdphase),
		.busy     (m_busy),

		.req      (m_req),
		.req_we   (m_we),
		.req_adr  (m_adr),
		.req_dat  (m_dat),
		.req_sel  (m_sel),
		.req_done (m_done),
		.rd_dat   (m_rdat),
		.rd_idx   (m_ridx),
		.rd_stb   (m_rstb),

		.sd_a     (sd_a),
		.sd_ba    (sd_ba),
		.sd_ncs   (sd_ncs),
		.sd_nras  (sd_nras),
		.sd_ncas  (sd_ncas),
		.sd_nwe   (sd_nwe),
		.sd_dqml  (sd_dqml),
		.sd_dqmh  (sd_dqmh),
		.sd_dq_o  (sd_dq_o),
		.sd_dq_oe (sd_dq_oe),
		.sd_dq_i  (sd_dq_i)
	);


endmodule

`default_nettype wire

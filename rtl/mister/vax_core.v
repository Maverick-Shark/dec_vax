//============================================================================
//  vax_core.v - r-vax system for MiSTer (replaces sbi.v of the original board).
//
//      cpu --- vcache (aligner) --- mmu --+-- vax_cache (M10K) --- vax_sdram --- 32 MB
//                                         |
//                                         +-- SBI / DW780 / RH780 register stubs
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
	parameter CACHEIDX = 10          // 2^CACHEIDX lines of 16 bytes
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
	input      [15:0] sd_dq_i
);

	/* CPU */
	wire        mcheck;
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
		.cpu_halted (cpu_halted),
		.cpu_mcheck (mcheck)
	);

	/* alignment unit: splits unaligned/partial accesses into longwords */
	wire        va_write, va_stb, va_ack;
	wire [31:0] va_addr, va_wdata, va_rdata;

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
		.UT_WE_O    (va_write),
		.UT_DAT_I   (va_rdata),
		.UT_ACK_I   (va_ack)
	);

	/* memory management: translation buffer, page table walks, faults */
	wire        bus_write, bus_stb, bus_ack;
	wire [31:0] bus_addr, bus_wdata, bus_rdata;

	mmu mmu (
		.clk        (clk),
		.rst        (rst_cpu),

		.IN_STB_I   (va_stb),
		.IN_WE_I    (va_write),
		.IN_ADR_I   (va_addr),
		.IN_DAT_I   (va_wdata),
		.IN_DAT_O   (va_rdata),
		.IN_ACK_O   (va_ack),

		.cpu_stb    (cpu_stb),
		.in_pmem    (cpu_pmem),
		.in_wint    (cpu_wint),
		.in_probe   (cpu_probe),
		.in_mode    (cpu_mode),
		.in_con     (cpu_con),
		.in_mcheck  (mcheck),

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
		.UT_DAT_I   (bus_rdata),
		.UT_ACK_I   (bus_ack)
	);

	/*
	 * SBI adapter stubs (from sbi.v): SBIA configuration and silo registers,
	 * DW780 Unibus adapter (TR3) and RH780 Massbus adapter (TR8) configuration
	 * registers. Enough for the adapter probes done by VMB and the r-vax test
	 * software; there is no real I/O behind them yet.
	 */
	reg         sbia_ack;
	reg  [31:0] sbia_reg, sbi_fs, sbi_tmo;
	wire        sbia_addressed      = bus_addr[29] & ~bus_addr[25];
	wire        sbia_regs           = (bus_addr[20:18] == 3'b010);
	wire        sbia_regs_addressed = bus_stb && sbia_addressed && sbia_regs;
	wire        tr03_addressed      = (bus_addr[16:13] == 4'b0011);
	wire        tr08_addressed      = (bus_addr[16:13] == 4'b1000);
	wire        sbi0_tr03_addressed = bus_stb && sbia_addressed && tr03_addressed;
	wire        sbi0_tr08_addressed = bus_stb && sbia_addressed && tr08_addressed;

	initial begin
		sbia_ack = 1'b0;
		sbia_reg = 32'd0;
		sbi_fs   = 32'd0;
		sbi_tmo  = 32'd0;
	end

	always @(posedge clk) begin
		sbia_reg <= 32'd0;
		if (!bus_stb)
			sbia_ack <= 1'b0;
		if (sbia_regs_addressed) begin
			if (bus_addr[6:2] == 5'b00000)
				sbia_reg <= 32'h00400010;
			if (bus_addr[6:2] == 5'b01111) begin
				if (bus_write)
					sbi_fs <= bus_wdata & 32'h03140000;
				sbia_reg <= sbi_fs;
			end
			if (bus_addr[6:2] == 5'b01110)
				sbia_reg <= sbi_tmo;
			sbia_ack <= 1'b1;
		end
		if (sbi0_tr03_addressed) begin
			if (bus_addr[12:0] == 13'd0)
				sbia_reg <= 32'h00010028;   // UBA + INIT DONE
			sbia_ack <= 1'b1;
		end
		if (sbi0_tr08_addressed) begin
			if (bus_addr[12:0] == 13'd0)
				sbia_reg <= 32'h00000020;   // MBA
			sbia_ack <= 1'b1;
		end
	end

	always @(posedge clk)
		if (mcheck & sbia_addressed)
			sbi_tmo <= {4'h2, bus_addr[29:2]};

	/* memory: 32 MB at physical 0x00000000-0x01FFFFFF */
	wire        mem_hit = ~|bus_addr[31:25];
	wire [31:0] cache_rdata;
	wire        cache_ack;

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

		.STB_I    (bus_stb & mem_hit),
		.ADR_I    (bus_addr),
		.DAT_I    (bus_wdata),
		.WE_I     (bus_write),
		.DAT_O    (cache_rdata),
		.ACK_O    (cache_ack),

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

	assign bus_rdata = cache_rdata | sbia_reg;
	assign bus_ack   = cache_ack | sbia_ack;

endmodule

`default_nettype wire

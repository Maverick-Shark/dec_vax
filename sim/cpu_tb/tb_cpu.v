// tb_cpu.v - CPU-level test bench for r-vax: cpu -> vcache -> mmu -> memory.
//
// No SDRAM, video or console terminal: the C++ driver (tb_cpu.cpp) loads a
// program straight into the memory array, starts the CPU at a given PC and
// dumps registers and memory when it halts. Used to compare the RTL with
// a VAX 8600 reference simulator on small test programs (tests/mmu).
//
// Disks: the RH780 at TR 8 with two RP07 drives; the C++ driver serves
// their images (DISK0, DISK1) the way the HPS does on the board.
//
// Unibus: the DW780 at TR 3 with a test device on its Unibus (ubdev.v,
// registers at 777400): device registers, interrupts and device DMA.
//
// Memory: 32 MB at physical 0. Every access takes MEMLAT clocks; addresses
// beyond the memory and I/O space are never acknowledged, so they end in the
// CPU's bus-timeout machine check like on the real board.

`default_nettype none

module tb_cpu #(
	parameter MEMLAT = 2,
	parameter TSCALE = 16           // the disks' mechanical times / 16
) (
	input         clk,
	input         rst,
	output        halted,
	input         tb_off,           // the MMU's translation buffer off (taken at reset)

	// the disk images, played by the C++ driver as the HPS would
	output [31:0] sd_lba0,
	output [31:0] sd_lba1,
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input   [1:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	input         sd_buff_wr,
	output  [7:0] sd_buff_din0,
	output  [7:0] sd_buff_din1,
	input   [1:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size
);

	wire        mcheck;
	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire        cpu_write, cpu_stb, cpu_ack;
	wire        cpu_pmem;
	wire  [1:0] cpu_size;
	wire        tto_tx;
	wire        cpu_wint, cpu_probe, cpu_con;
	wire  [1:0] cpu_mode;
	wire        mmu_flt, mmu_tnv, mmu_prog;
	wire [31:0] mmu_va;
	wire  [2:0] mmu_par;
	wire        ipr_we;
	wire  [6:0] ipr_adr;
	wire [31:0] ipr_dat;

	wire        io_err;
	wire  [4:0] io_ipl, pamm_rd;
	wire [31:0] io_mstat2, io_mear;

	cpu cpu (
		.clk        (clk),
		.rst        (rst),
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
		.tti_rx     (1'b1),
		.halt_req   (1'b0),
		.con_boot   (1'b0),
		.TODR_LD_I  (1'b0),
		.TODR_I     (32'd0),
		.cpu_halted (halted),
		.cpu_mcheck (mcheck),
		.IO_ERR_I   (io_err),
		.IO_MSTAT2_I(io_mstat2),
		.IO_MEAR_I  (io_mear),
		.IO_IPL_I   (io_ipl),
		.PAMM_I     (pamm_rd)
	);

	wire        va_write, va_stb, va_ack;
	wire [31:0] va_addr, va_wdata, va_rdata;
	wire  [3:0] va_sel;

	vcache vcache (
		.clk        (clk),
		.rst        (rst),
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

	wire        bus_write, bus_stb, bus_ack;
	wire [31:0] bus_addr, bus_wdata, bus_rdata;
	wire  [3:0] bus_sel;

	mmu mmu (
		.clk        (clk),
		.rst        (rst),
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
		.tb_off     (tb_off),
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

	// ---------------------------------------------- I/O side (vax_io.v)
	wire        mem_stb, mem_we;
	wire [31:0] mem_adr, mem_wdat, mem_rdat;
	wire  [3:0] mem_sel;
	wire        mem_ack;
	// the Unibus (the DW780's) and the test device on it
	wire [17:0] ub_a, dv_a;
	wire  [1:0] ub_c, dv_c;
	wire [15:0] ub_d, ub_rd, dv_d, dv_rd, ub_vec;
	wire        ub_msyn, ub_ssyn, dv_npr, dv_npg, dv_msyn, dv_ssyn;
	wire  [3:0] ub_br, ub_bg;
	wire        ub_intr, ub_init;

	vax_io #(.CLK_HZ(50000000), .MEMMB(32), .TSCALE(TSCALE)) io (
		.clk      (clk),
		.rst      (rst),
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
		.m_pre    (),
		.m_wdat   (mem_wdat),
		.m_sel    (mem_sel),
		.m_rdat   (mem_rdat),
		.m_ack    (mem_ack),
		.io_err   (io_err),
		.io_mstat2(io_mstat2),
		.io_mear  (io_mear),
		.io_ipl   (io_ipl),
		.sd_lba0  (sd_lba0),
		.sd_lba1  (sd_lba1),
		.sd_rd    (sd_rd),
		.sd_wr    (sd_wr),
		.sd_ack   (sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_wr  (sd_buff_wr),
		.sd_buff_din0(sd_buff_din0),
		.sd_buff_din1(sd_buff_din1),
		.img_mounted (img_mounted),
		.img_readonly(img_readonly),
		.img_size    (img_size),
		.disk_active (),
		.ub_a     (ub_a),
		.ub_c     (ub_c),
		.ub_d     (ub_d),
		.ub_msyn  (ub_msyn),
		.ub_ssyn  (ub_ssyn),
		.ub_rd    (ub_rd),
		.dv_npr   (dv_npr),
		.dv_npg   (dv_npg),
		.dv_a     (dv_a),
		.dv_c     (dv_c),
		.dv_d     (dv_d),
		.dv_msyn  (dv_msyn),
		.dv_ssyn  (dv_ssyn),
		.dv_rd    (dv_rd),
		.ub_br    (ub_br),
		.ub_bg    (ub_bg),
		.ub_intr  (ub_intr),
		.ub_vec   (ub_vec),
		.ub_init  (ub_init)
	);

	// a test device on the DW780's Unibus (cpu_tb/ubdev.v), at 777400
	ubdev ubd (
		.clk     (clk),
		.rst     (rst),
		.ub_a    (ub_a),
		.ub_c    (ub_c),
		.ub_d    (ub_d),
		.ub_msyn (ub_msyn),
		.ub_ssyn (ub_ssyn),
		.ub_rd   (ub_rd),
		.dv_npr  (dv_npr),
		.dv_npg  (dv_npg),
		.dv_a    (dv_a),
		.dv_c    (dv_c),
		.dv_d    (dv_d),
		.dv_msyn (dv_msyn),
		.dv_ssyn (dv_ssyn),
		.dv_rd   (dv_rd),
		.ub_br   (ub_br),
		.ub_bg   (ub_bg),
		.ub_intr (ub_intr),
		.ub_vec  (ub_vec),
		.ub_init (ub_init)
	);

	// ---------------------------------------------------------- memory
	// 32 MB, as in the full system and the reference simulator's runs
	reg  [31:0] mem [0:(1<<23)-1];
	reg  [31:0] rdat;
	reg         ack;
	reg   [3:0] cnt;

	assign mem_rdat = (mem_stb && ack) ? rdat : 32'd0;
	assign mem_ack  = mem_stb && ack;

	// statistics for the driver
	reg  [31:0] nread, nwrite;

	initial begin
		ack = 1'b0; cnt = 0; nread = 0; nwrite = 0;
	end

	always @(posedge clk) begin
		if (!mem_stb) begin
			ack <= 1'b0;
			cnt <= 0;
		end else if (!ack) begin
			cnt <= cnt + 1'b1;
			if (cnt == MEMLAT - 1) begin
				if (mem_we) begin
					if (mem_sel[0]) mem[mem_adr[24:2]][7:0]   <= mem_wdat[7:0];
					if (mem_sel[1]) mem[mem_adr[24:2]][15:8]  <= mem_wdat[15:8];
					if (mem_sel[2]) mem[mem_adr[24:2]][23:16] <= mem_wdat[23:16];
					if (mem_sel[3]) mem[mem_adr[24:2]][31:24] <= mem_wdat[31:24];
					nwrite <= nwrite + 1;
				end else begin
					rdat <= mem[mem_adr[24:2]];
					nread <= nread + 1;
				end
				ack <= 1'b1;
			end
		end
	end

endmodule

`default_nettype wire

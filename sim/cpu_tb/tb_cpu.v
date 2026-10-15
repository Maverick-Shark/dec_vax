// tb_cpu.v - CPU-level test bench for r-vax: cpu -> vcache -> mmu -> memory.
//
// No SDRAM, video or console terminal: the C++ driver (tb_cpu.cpp) loads a
// program straight into the memory array, starts the CPU at a given PC and
// dumps registers and memory when it halts. Used to compare the RTL with
// simh's vax8600 on small test programs (tests/mmu).
//
// Memory: 8 MB at physical 0. Every access takes MEMLAT clocks; addresses
// beyond the memory and I/O space are never acknowledged, so they end in the
// CPU's bus-timeout machine check like on the real board.

`default_nettype none

module tb_cpu #(
	parameter MEMLAT = 2
) (
	input         clk,
	input         rst,
	output        halted
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
		.cpu_halted (halted),
		.cpu_mcheck (mcheck)
	);

	wire        va_write, va_stb, va_ack;
	wire [31:0] va_addr, va_wdata, va_rdata;

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
		.UT_WE_O    (va_write),
		.UT_DAT_I   (va_rdata),
		.UT_ACK_I   (va_ack)
	);

	wire        bus_write, bus_stb, bus_ack;
	wire [31:0] bus_addr, bus_wdata, bus_rdata;

	mmu mmu (
		.clk        (clk),
		.rst        (rst),
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

	// ---------------------------------------------------------- memory
	reg  [31:0] mem [0:(1<<21)-1];
	reg  [31:0] rdat;
	reg         ack;
	reg   [3:0] cnt;
	wire        hit = (bus_addr[31:23] == 9'd0);

	assign bus_rdata = (bus_stb && ack) ? rdat : 32'd0;
	assign bus_ack   = bus_stb && ack;

	// statistics for the driver
	reg  [31:0] nread, nwrite;

	initial begin
		ack = 1'b0; cnt = 0; nread = 0; nwrite = 0;
	end

	always @(posedge clk) begin
		if (!bus_stb) begin
			ack <= 1'b0;
			cnt <= 0;
		end else if (hit && !ack) begin
			cnt <= cnt + 1'b1;
			if (cnt == MEMLAT - 1) begin
				if (bus_write) begin
					mem[bus_addr[22:2]] <= bus_wdata;
					nwrite <= nwrite + 1;
				end else begin
					rdat <= mem[bus_addr[22:2]];
					nread <= nread + 1;
				end
				ack <= 1'b1;
			end
		end
	end

endmodule

`default_nettype wire

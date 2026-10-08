//============================================================================
//  vax_core.v - r-vax system for MiSTer (replaces sbi.v of the original board).
//
//  cpu -> vcache -> { SBIA/UBA/MBA register stubs, 32 MB SDRAM }
//
//  Differences with sbi.v:
//   * MiSTer SDRAM controller (vax_sdram.v), 32 MB instead of 16 MB.
//   * Separate resets: the SDRAM controller is initialised once at power-up,
//     the CPU can be reset (OSD reset, program download) independently.
//   * Second bus master port for the program loader (HPS ioctl download).
//     While ldr_active is high the loader owns the memory; the CPU must be
//     held in reset by the caller.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_core #(
	parameter CLK_HZ = 50000000
) (
	input             clk,
	input             rst_mem,      // SDRAM controller reset (power-up only)
	input             rst_cpu,      // CPU reset
	output            mem_ready,

	// program loader port (longword address, byte enables)
	input             ldr_active,
	input             ldr_stb,
	input      [22:0] ldr_adr,
	input       [3:0] ldr_sel,
	input      [31:0] ldr_dat,
	output            ldr_ack,

	// console serial lines (8N1, `CLKPERBIT clocks per bit)
	input             tti_rx,
	output            tto_tx,

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

		.tto_tx     (tto_tx),
		.tti_rx     (tti_rx),
		.cpu_mcheck (mcheck)
	);

	/* alignment unit: splits unaligned/partial accesses into longwords */
	wire        bus_write, bus_stb, bus_ack;
	wire [31:0] bus_addr, bus_wdata, bus_rdata;

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

		.UT_STB_O   (bus_stb),
		.UT_ADR_O   (bus_addr),
		.UT_DAT_O   (bus_wdata),
		.UT_WE_O    (bus_write),
		.UT_DAT_I   (bus_rdata),
		.UT_ACK_I   (bus_ack)
	);

	/*
	 * SBI adapter stubs (copied from sbi.v): SBIA registers, DW780 (TR3)
	 * and RH780 (TR8) configuration registers, enough for the probes done
	 * by the r-vax test software. I/O space starts at 0x20000000.
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
	wire        mem_hit  = ~|bus_addr[31:25];
	wire [31:0] mem_rdata;
	wire        mem_ack;

	wire        m_stb = ldr_active ? ldr_stb : (bus_stb & mem_hit);
	wire        m_we  = ldr_active ? 1'b1    : bus_write;
	wire  [3:0] m_sel = ldr_active ? ldr_sel : 4'b1111;
	wire [22:0] m_adr = ldr_active ? ldr_adr : bus_addr[24:2];
	wire [31:0] m_dat = ldr_active ? ldr_dat : bus_wdata;

	vax_sdram #(.CLK_HZ(CLK_HZ)) sdram (
		.clk      (clk),
		.rst      (rst_mem),
		.ready    (mem_ready),

		.STB_I    (m_stb),
		.WE_I     (m_we),
		.SEL_I    (m_sel),
		.ADR_I    (m_adr),
		.DAT_I    (m_dat),
		.DAT_O    (mem_rdata),
		.ACK_O    (mem_ack),

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

	assign ldr_ack   = ldr_active & mem_ack;
	assign bus_rdata = (ldr_active ? 32'd0 : mem_rdata) | sbia_reg;
	assign bus_ack   = (~ldr_active & mem_ack) | sbia_ack;

endmodule

`default_nettype wire

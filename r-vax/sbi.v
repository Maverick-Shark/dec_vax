/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    	15:54:19 04/01/2018
// Design Name: 	nvax
// Module Name:    	sbi 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
// `define HALFCLOCK

`include "opcodes.vh"

/*
 * The memory address bus is 32 bit, 32 bit wide.
 */

module sbi (
	input		clkin,
	input		n_rst,
`ifdef notdef
	input		n_pfail,
`endif

	output		sdram_clk,
	output		sdram_cke,
	output		sdram_cs,
	output		sdram_ras,
	output		sdram_cas,
	output		sdram_we,
	output		sdram_udqm,
	output		sdram_ldqm,
	output [11:0]	sdram_addr,
	output [1:0]	sdram_ba,
	inout  [15:0]	sdram_data,

	output		buzzer,

	input		tti_rx,
	output		tto_tx
);

`ifdef HALFCLOCK
defparam console.tti.CLKPERBIT = 2604;
defparam console.tto.CLKPERBIT = 2604;
	reg clk;
	always @(posedge clkin)
		clk <= !clk;
`else
	wire clk;
	assign clk = clkin;
`endif
	/*
	 * Wiring:
	 * - cpu
	 * cpu_* -> data from cpu to mmu (before conditional)
	 * mmu_f_cpu_* -> data to mmu from cpu (after conditional)
	 * - mmu
	 * mmu_2_pc_* -> data from mmu to pcache (before conditional)
	 * pc_f_mmu_* -> data to pcache from mmu (after conditional)
	 * - pcache
	 * pc_2_mem_* -> data from pcache to memory (before conditional)
	 * mem_f_pc_* -> data to memory from pcache (after conditional)
	 */

	wire rst;
	assign rst = !n_rst;

	assign buzzer = 1;

`ifdef DBGCNT
	reg [7:0]	dcount;
	initial dcount = 0;
//	always @(posedge clk)
//		dcount <= dcount + 1;
`endif

	/* wires from CPU */
	wire mcheck;
	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire cpu_write, cpu_stb, cpu_ack;
	wire cpu_pmem;
	wire [1:0] cpu_size;

	cpu cpu(
		.clk(clk),
		.rst(rst),

		.CPU_ADR_O(cpu_addr),
		.CPU_DAT_O(cpu_wdata),
		.CPU_WE_O(cpu_write),
		.CPU_STB_O(cpu_stb),
		.CPU_DAT_I(cpu_rdata),
		.CPU_ACK_I(cpu_ack),

		.CPU_SIZE_O(cpu_size),

		.CPU_PMEM_O(cpu_pmem),

`ifdef DBGCNT
		.dcount(dcount),
`endif
		.tto_tx(tto_tx),
		.tti_rx(tti_rx),
		.cpu_mcheck(mcheck)
	);

	/* wires between mmu and pcache */
	wire mmu_to_sw_write, mmu_to_sw_stb, sw_to_pc_write, sw_to_pc_stb;
	wire pc_to_mmu_ack;
	wire [31:0] mmu_to_sw_addr, sw_to_pc_addr;
	wire [31:0] mmu_to_sw_wdata, sw_to_pc_wdata, pc_to_mmu_rdata;

	vcache vcache(
		.clk(clk),
		.rst(rst),

		.IN_STB_I(cpu_stb),
		.IN_ADR_I(cpu_addr),
		.IN_DAT_I(cpu_wdata),
		.IN_WE_I(cpu_write),
		.IN_DAT_O(cpu_rdata),
		.IN_ACK_O(cpu_ack),

		.in_passthru(cpu_pmem),
		.in_sz(cpu_size),

		.in_mcheck(mcheck),

//		.ut_sz(),

`ifdef DBGCNT
		.dcount(dcount),
`endif
		.UT_STB_O(mmu_to_sw_stb),
		.UT_ADR_O(mmu_to_sw_addr),
		.UT_DAT_O(mmu_to_sw_wdata),
		.UT_WE_O(mmu_to_sw_write),
		.UT_DAT_I(pc_to_mmu_rdata),
		.UT_ACK_I(pc_to_mmu_ack)
	);

	/*
	 * SBIA adapter.
	 */
	wire		sbia_addressed, sbia_regs_addressed, sbia_regs;
	wire		tr03_addressed, sbi0_tr03_addressed;
	wire		tr08_addressed, sbi0_tr08_addressed;
	reg		sbia_ack;
	reg [31:0]	sbia_reg, sbi_fs, sbi_tmo;
	assign sbia_addressed = mmu_to_sw_addr[29] & ~mmu_to_sw_addr[25];
	assign sbia_regs = (mmu_to_sw_addr[20:18] == 3'b010);
	assign sbia_regs_addressed =
	    mmu_to_sw_stb && sbia_addressed && sbia_regs;
	assign tr03_addressed = (mmu_to_sw_addr[16:13] == 4'b0011);
	assign tr08_addressed = (mmu_to_sw_addr[16:13] == 4'b1000);
	assign sbi0_tr03_addressed = 
	    mmu_to_sw_stb && sbia_addressed & tr03_addressed;
	assign sbi0_tr08_addressed = 
	    mmu_to_sw_stb && sbia_addressed & tr08_addressed;

	always @(posedge clk) begin
		sbia_reg <= 0;
		if (mmu_to_sw_stb == 0)
			sbia_ack <= 0;
//if (mmu_to_sw_addr[29] && mmu_to_sw_stb)
//$fdisplay(32'h80000002, "io_addr: addr %x regs %x access %d write %d\r", mmu_to_sw_addr, sbia_regs, sbia_regs_addressed, mmu_to_sw_write);
		/* SBIA0 registers */
		if (sbia_regs_addressed) begin
			if (mmu_to_sw_addr[6:2] == 5'b0)
				sbia_reg <= 32'h00400010;
			if (mmu_to_sw_addr[6:2] == 5'b01111) begin
//$fdisplay(32'h80000002, "SBIFS: wr %d addr %x wdata %x rdata %x", mmu_to_sw_write, mmu_to_sw_addr, mmu_to_sw_wdata, sbi_fs);
				if (mmu_to_sw_write)
					sbi_fs <= mmu_to_sw_wdata & 32'h03140000;
				sbia_reg <= sbi_fs;
			end
			if (mmu_to_sw_addr[6:2] == 5'b01110) begin
				sbia_reg <= sbi_tmo;
			end
			sbia_ack <= 1;
		end
		/* Unibus (DW780) internal registers */
		if (sbi0_tr03_addressed) begin
			if (mmu_to_sw_addr[12:0] == 13'b0)
				sbia_reg <= 32'h00010028; // UBA+INIT DONE
			sbia_ack <= 1;
		end
		/* Massbus (RH780) internal registers */
		if (sbi0_tr08_addressed) begin
			if (mmu_to_sw_addr[12:0] == 13'b0)
				sbia_reg <= 32'h00000020; // MBA
			sbia_ack <= 1;
		end
	end

	always @(posedge clk)
		if (mcheck & sbia_addressed)
			sbi_tmo <= { 4'h2, mmu_to_sw_addr[29:2] };




	/* switch pcache input between console and mmu */
	assign sw_to_pc_addr = mmu_to_sw_addr;
	assign sw_to_pc_write = mmu_to_sw_write;
	assign sw_to_pc_wdata = mmu_to_sw_wdata;
	assign sw_to_pc_stb = mmu_to_sw_stb;

	/* wires between mem and pcache */
	wire pc_to_sw_write, pc_to_sw_stb, sw_to_mem_write, sw_to_mem_stb;
	wire mem_to_pc_ack;
	wire [31:0] pc_to_sw_addr, sw_to_mem_addr;
	wire [31:0] pc_to_sw_wdata, sw_to_mem_wdata, mem_to_pc_rdata;

	assign pc_to_sw_addr = sw_to_pc_addr;
	assign pc_to_sw_wdata = sw_to_pc_wdata;
	assign pc_to_sw_write = sw_to_pc_write;
	assign pc_to_sw_stb = sw_to_pc_stb;
	assign pc_to_mmu_rdata = mem_to_pc_rdata | sbia_reg;
	assign pc_to_mmu_ack = mem_to_pc_ack | sbia_ack;

	/* switch mem input between console and pcache */
	assign sw_to_mem_addr = pc_to_sw_addr;
	assign sw_to_mem_write = pc_to_sw_write;
	assign sw_to_mem_wdata = pc_to_sw_wdata;
	assign sw_to_mem_stb = pc_to_sw_stb;

	/*
	 * Ram 16MB (4MLW).  22 bits addr (21-0) * 32 bits data.
	 */
	sdram sdram(
		.clk(clk),
		.rst(rst),

		.sdram_clk(sdram_clk),
		.sdram_cke(sdram_cke),
		.sdram_cs(sdram_cs),
		.sdram_ras(sdram_ras),
		.sdram_cas(sdram_cas),
		.sdram_we(sdram_we),
		.sdram_udqm(sdram_udqm),
		.sdram_ldqm(sdram_ldqm),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba),
		.sdram_data(sdram_data),

`ifdef DBGCNT
		.dcount(dcount),
`endif
		.ADR_I(sw_to_mem_addr[23:2]),		// i
		.WE_I(sw_to_mem_write),		// i
		.DAT_I(sw_to_mem_wdata),		// i
		.STB_I(~|sw_to_mem_addr[31:24] & sw_to_mem_stb), // i
		.DAT_O(mem_to_pc_rdata),		// o
		.ACK_O(mem_to_pc_ack)		// o
	);

endmodule

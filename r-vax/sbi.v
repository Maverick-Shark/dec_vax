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
	wire cpu_pmem, cpu_tto_tx;
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
		.tto_tx(cpu_tto_tx),
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

	wire		qbus_stb, qbus_ack, qb_tto_tx;
	wire [31:0]	qbus_wdata;
	assign	qbus_stb = (mmu_to_sw_addr[31:28] == 4'h2)  & mmu_to_sw_stb;

	/*
	 * Qbus controller.
	 */
	qbus qbus(
		.clk(clk),
		.rst(rst),

		.STB_I(qbus_stb),
		.ADR_I(mmu_to_sw_addr[27:0]),
		.DAT_I(mmu_to_sw_wdata),
		.WE_I(mmu_to_sw_write),
		.DAT_O(qbus_wdata),
		.ACK_O(qbus_ack),

		.tti_rx(tti_rx),
		.tto_tx(qb_tto_tx)
	);
	assign tto_tx = /* qb_tto_tx& */ cpu_tto_tx;


	/* switch pcache input between console and mmu */
	assign sw_to_pc_addr = mmu_to_sw_addr;
	assign sw_to_pc_write = mmu_to_sw_write;
	assign sw_to_pc_wdata = mmu_to_sw_wdata;
	assign sw_to_pc_stb = mmu_to_sw_stb;

	/* wires between mem and pcache */
	wire pc_to_sw_write, pc_to_sw_stb, sw_to_mem_write, sw_to_mem_stb;
	wire mem_to_pc_ack, rom_to_pc_ack;
	wire [31:0] pc_to_sw_addr, sw_to_mem_addr, rom_to_pc_rdata;
	wire [31:0] pc_to_sw_wdata, sw_to_mem_wdata, mem_to_pc_rdata;

	assign pc_to_sw_addr = sw_to_pc_addr;
	assign pc_to_sw_wdata = sw_to_pc_wdata;
	assign pc_to_sw_write = sw_to_pc_write;
	assign pc_to_sw_stb = sw_to_pc_stb;
	assign pc_to_mmu_rdata = mem_to_pc_rdata | qbus_wdata | rom_to_pc_rdata;
	assign pc_to_mmu_ack = mem_to_pc_ack | qbus_ack | rom_to_pc_ack;

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

	wire		rom_stb;
	assign rom_stb = &sw_to_mem_addr[31:28] & sw_to_mem_stb;

//always @(posedge clk) begin
//	if (rom_stb)
//		$fdisplay(32'h80000002, "ROM: adr %x ack %d data %x\r", sw_to_mem_addr, rom_to_pc_ack, rom_to_pc_rdata);
//end

`ifdef notdef
	mcode mcode(
		.clk(clk),

		.ADR_I(sw_to_mem_addr[10:2]),
		.STB_I(rom_stb),
		.DAT_O(rom_to_pc_rdata),
		.ACK_O(rom_to_pc_ack)
	);
`endif

endmodule

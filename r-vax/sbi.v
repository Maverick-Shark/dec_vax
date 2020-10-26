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

	wire brk, rst;
	assign rst = !n_rst | brk;

	assign buzzer = 1;

	/* wires from CPU */
	wire halted, mcheck;
	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire cpu_write, cpu_stb, cpu_ack, cpu_cyc;
	wire cpu_pmem;
	wire [1:0] cpu_size;

	/* cpu - console wires */
	wire cont, step;
	wire [31:0] con_cpu_addr, con_cpu_wdata, con_cpu_rdata;
	wire con_cpu_cyc, con_cpu_write, con_cpu_stb, con_cpu_ack;
	wire con_cpu_vmem, con_cpu_pmem, con_cpu_ipr, con_cpu_reg;
	wire con_tto_tx;

	cpu cpu(
		.clk(clk),
		.rst(rst),

		.CON_CYC_I(con_cpu_cyc),
		.CON_ADR_I(con_cpu_addr),
		.CON_WE_I(con_cpu_write),
		.CON_DAT_I(con_cpu_wdata),
		.CON_STB_I(con_cpu_stb),
		.CON_DAT_O(con_cpu_rdata),
		.CON_ACK_O(con_cpu_ack),

		.con_reg(con_cpu_reg),
		.con_ipr(con_cpu_ipr),
		.con_pmem(con_cpu_pmem),
		.con_vmem(con_cpu_vmem),

		.CPU_CYC_O(cpu_cyc),
		.CPU_ADR_O(cpu_addr),
		.CPU_DAT_O(cpu_wdata),
		.CPU_WE_O(cpu_write),
		.CPU_STB_O(cpu_stb),
		.CPU_DAT_I(cpu_rdata),
		.CPU_ACK_I(cpu_ack),

		.CPU_SIZE_O(cpu_size),

		.CPU_PMEM_O(cpu_pmem),

		.cpu_mcheck(mcheck),

		.step(step),
		.cont(cont),
		.halted(halted)
	);

	/* wires between mmu and pcache */
	wire mmu_to_sw_write, mmu_to_sw_stb, sw_to_pc_write, sw_to_pc_stb;
	wire pc_to_mmu_ack;
	wire [29:0] mmu_to_sw_addr, sw_to_pc_addr;
	wire [31:0] mmu_to_sw_wdata, sw_to_pc_wdata, pc_to_mmu_rdata;

	vcache vcache(
		.clk(clk),
		.rst(rst),

		.IN_CYC_I(cpu_cyc),
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

//		.UT_CYC_O(),
		.UT_STB_O(mmu_to_sw_stb),
		.UT_ADR_O(mmu_to_sw_addr),
		.UT_DAT_O(mmu_to_sw_wdata),
		.UT_WE_O(mmu_to_sw_write),
		.UT_DAT_I(pc_to_mmu_rdata),
		.UT_ACK_I(pc_to_mmu_ack)
	);

	wire		qbus_cyc, qbus_ack;
	wire		dl11_tx;
	wire [31:0]	qbus_wdata;
	assign	qbus_cyc = mmu_to_sw_addr[29];
	assign tto_tx = dl11_tx & con_tto_tx;

	/*
	 * Qbus controller.
	 */
	qbus qbus(
		.clk(clk),
		.rst(rst),

		.CYC_I(qbus_cyc),
		.STB_I(mmu_to_sw_stb),
		.ADR_I(mmu_to_sw_addr[27:0]),
		.DAT_I(mmu_to_sw_wdata),
		.WE_I(mmu_to_sw_write),
		.DAT_O(qbus_wdata),
		.ACK_O(qbus_ack),

		.tto_tx(dl11_tx)
	);


	/* switch pcache input between console and mmu */
	assign sw_to_pc_addr = mmu_to_sw_addr;
	assign sw_to_pc_write = mmu_to_sw_write;
	assign sw_to_pc_wdata = mmu_to_sw_wdata;
	assign sw_to_pc_stb = mmu_to_sw_stb;

	/* wires between mem and pcache */
	wire pc_to_sw_write, pc_to_sw_stb, sw_to_mem_write, sw_to_mem_stb;
	wire mem_to_pc_ack;
/* verilator lint_off UNUSED */
	wire [29:0] pc_to_sw_addr, sw_to_mem_addr;
/* verilator lint_on UNUSED */
	wire [31:0] pc_to_sw_wdata, sw_to_mem_wdata, mem_to_pc_rdata;

`ifdef notdef
	pcache pcache(
		.clk(clk),
		.rst(rst),

		.f_mmu_addr(sw_to_pc_addr),
		.f_mmu_wdata(sw_to_pc_wdata),
		.f_mmu_write(sw_to_pc_write),
		.f_mmu_stb(sw_to_pc_stb),
		.f_mmu_rdata(pc_to_mmu_rdata),
		.f_mmu_ack(pc_to_mmu_ack),

		.t_mem_addr(pc_to_sw_addr),
		.t_mem_wdata(pc_to_sw_wdata),
		.t_mem_write(pc_to_sw_write),
		.t_mem_stb(pc_to_sw_stb),
		.t_mem_rdata(mem_to_pc_rdata),
		.t_mem_ack(mem_to_pc_ack)
	);
`else
	assign pc_to_sw_addr = sw_to_pc_addr;
	assign pc_to_sw_wdata = sw_to_pc_wdata;
	assign pc_to_sw_write = sw_to_pc_write;
	assign pc_to_sw_stb = sw_to_pc_stb;
	assign pc_to_mmu_rdata = mem_to_pc_rdata | qbus_wdata;
	assign pc_to_mmu_ack = mem_to_pc_ack | qbus_ack;
`endif

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
		
		.CYC_I(~|sw_to_mem_addr[29:24]),
		.ADR_I(sw_to_mem_addr[23:2]),		// i
		.WE_I(sw_to_mem_write),		// i
		.DAT_I(sw_to_mem_wdata),		// i
		.STB_I(sw_to_mem_stb),		// i
		.DAT_O(mem_to_pc_rdata),		// o
		.ACK_O(mem_to_pc_ack)		// o
	);

	console console(
		.clk(clk),
		.rst(rst),

		.halted(halted),	// Handle commands
		.break_o(brk),	// want to halt
		.cont(cont),
		.step(step),

		.CYC_O(con_cpu_cyc),
		.ADR_O(con_cpu_addr),
		.WE_O(con_cpu_write),
		.DAT_O(con_cpu_wdata),
		.STB_O(con_cpu_stb),
		.DAT_I(con_cpu_rdata),
		.ACK_I(con_cpu_ack),

		.con_reg(con_cpu_reg),
		.con_ipr(con_cpu_ipr),
		.con_pmem(con_cpu_pmem),
		.con_vmem(con_cpu_vmem),

		.tti_rx(tti_rx),
		.tto_tx(con_tto_tx)
	);

endmodule

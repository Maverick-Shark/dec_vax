/*	$Id$	*/
`timescale 1ns / 1ps
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
/*
 * The memory address bus is 30 bit, 32 bit wide.
 * It is shared with IPR addressing, only difference is that the strobe
 * signal is separate, the rest is the same.
 */

// `include "ipr.v"

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

	wire brk;
	assign rst = !n_rst | brk;

	reg buzz;
	assign buzzer = 1;

	/* common control wires */
	wire reqhalt;		// CPU halt requested

	/* backplane logic */
//	assign reqhalt = brk | rst /* | cpu_halt */;


	/* wires from mmu to direct mem */
	wire [23:2] mmu_addr, mmu_wdata;
	wire mmu_write, mmu_stb;

	/* wires from console */
	wire con_mem;	/* console references (direct) memory */
	wire [31:0] con_addr, con_wdata, con_rdata;
	wire con_write, con_stb, con_reg;
	wire cont, step;
	
	/* wires to/from direct mem */
	wire pmem_write, pmem_stb, pmem_ack;
	wire [23:2] pmem_addr;
	wire [31:0] pmem_wdata, pmem_rdata;

	/* switch pmem input between console and mmu */
	assign pmem_addr = con_mem ? con_addr[23:2] : mmu_addr;
	assign pmem_write = con_mem ? con_write : mmu_write;
	assign pmem_wdata = con_mem ? con_wdata : mmu_wdata;
	assign pmem_stb = con_mem ? con_stb : mmu_stb;

	/* wires from CPU */
	wire [31:0] reg_rdata, pc;
	wire reg_ack;
	wire halted;		// CPU is halted

	assign reg_stb = con_reg ? con_stb : 0;

	/* signals to console from mem or reg */
	assign con_rdata = con_reg ? reg_rdata : pmem_rdata;
	assign con_ack = con_reg ? reg_ack : pmem_ack;

	cpu cpu(
		.clk(clk),
		.rst(rst),

		.reg_addr(con_addr[3:0]),
		.reg_wdata(con_wdata),
		.reg_write(con_write),
		.reg_stb(reg_stb),
		.reg_rdata(reg_rdata),
		.reg_ack(reg_ack),

		.step(step),
		.cont(cont),
		.halted(halted),

		.pc(pc)
	);

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
		
		.pmem_addr(pmem_addr),		// i
		.pmem_write(pmem_write),	// i
		.pmem_wdata(pmem_wdata),	// i
		.pmem_stb(pmem_stb),		// i
		.pmem_rdata(pmem_rdata),	// o
		.pmem_ack(pmem_ack)		// o
	);


	console console(
		.clk(clk),
		.rst(rst),

		.halted(halted),	// Handle commands
		.break_o(brk),	// want to halt
		.cont(cont),
		.step(step),

		.conaddr(con_addr),
		.conwrite(con_write),
		.conwdata(con_wdata),
		.conready(con_stb),
		.conrdata(con_rdata),
		.convalid(con_ack),

		.con_mem(con_mem),
		.con_reg(con_reg),

		.pc(pc),

		.tti_rx(tti_rx),
		.tto_tx(tto_tx)
	);

endmodule

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

`ifdef notdef
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
`endif

	output		buzzer,

	input		tti_rx,
	output		tto_tx
);

`ifdef HALFCLOCK
defparam tti.CLKPERBIT = 2604;
defparam tto.CLKPERBIT = 2604;
	reg clk;
	always @(posedge clkin)
		clk <= !clk;
`else
	wire clk;
	assign clk = clkin;
`endif

	assign rst = !n_rst;

	reg buzz;
	assign buzzer = 1;
	assign halted = 1;

	/* common control wires */
	wire reqhalt;		// CPU halt requested
//	wire halted;		// CPU is halted
	wire brk;

	/* backplane logic */
	assign reqhalt = brk | rst /* | cpu_halt */;
	assign running = !halted;

	console console(
		.clk(clk),
		.rst(rst),

		.halted_i(halted),	// Handle commands
		.break_o(brk),	// want to halt

		.tti_rx(tti_rx),
		.tto_tx(tto_tx)
	);

endmodule

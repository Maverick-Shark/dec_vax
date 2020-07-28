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
	assign buzzer = buzz;

	wire [7:0] tti_data, tto_data;
	wire tto_done, tti_done;

	assign tto_data = tti_data;

	reg ttos, ttic, ttoc;
	assign tto_start = ttos;
	assign tti_clear = ttic;
	assign tto_clear = ttoc;

	always @(posedge clk) begin
		if (tti_done) begin
			ttos <= 1;
			ttic <= 1;
			if (tti_data == "B")
				buzz <= 1;
			else if (tti_data == "b")
				buzz <= 0;
		end else if (tto_done) begin
			ttoc <= 1;
		end else begin
			ttos <= 0;
			ttoc <= 0;
			ttic <= 0;
		end
	end

	tti tti(
		.clk(clk),
		.iorst(rst),

		.clear_i(tti_clear),	// clears done
		.done_o(tti_done),	// set when a char is received
					// also signals rx interrupt
		.outdata_o(tti_data),	// data [7:0] valid when done is set
		.gotbreak_o(tti_break),	// break received

		.tti_rx(tti_rx)
	);

	tto tto(
		.clk(clk),
		.iorst(rst),

		.start_i(tto_start),	// starts transmission of buffer
		.clear_i(tto_clear),	// clears done
		.busy_o(tto_busy),	// set while sending
		.done_o(tto_done),	// set when done

		.data_i(tto_data),	// send buffer, loaded at start

		.tto_tx(tto_tx)
	);

endmodule

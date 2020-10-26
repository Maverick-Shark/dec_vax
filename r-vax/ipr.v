/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none
/*
 * IPR storage/handling module.
 */

`include "ipr.vh"

module ipr(
	input		clk,

	input		CYC_I,
	input		STB_I,
	input [31:0]	ADR_I,
	input [31:0]	DAT_I,
	input		WE_I,
	output [31:0]	DAT_O,
	output		ACK_O
);

	reg [31:0]	out_data;
	reg		out_ack;

	reg [31:0]	iprmem [63:0];

initial iprmem[62] = 32'h0A000006;

	assign DAT_O = CYC_I ? out_data : 32'b0;
	assign ACK_O = CYC_I ? out_ack : 0;

	wire memenb = (~|ADR_I[31:6]) & CYC_I & STB_I;

	always @(posedge clk) begin
		if (memenb) begin
			if (WE_I)
				iprmem[ADR_I[5:0]] <= DAT_I;
			out_data <= iprmem[ADR_I[5:0]];
			out_ack <= 1;
		end else
			out_ack <= 0;
//		if (<enableB>)
//			<output_dataB> <= iprmem[ADR_I[5:0]];
	end

endmodule

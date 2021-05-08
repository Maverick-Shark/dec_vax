/*      $Id$       */
`timescale 1ns / 1ps
`default_nettype none


`include "aluops.vh"

module alu(
	input		clk,

	input [3:0]	op,

	input [31:0]	left,
	input [31:0]	right,

	output		cry,
	output		zero,
	output [31:0]	result
);

	reg [31:0]	res;
	reg		Ctmp;

	always @(op, left, right)
		case (op)
		`ALU_PLUS: { Ctmp, res } = { 1'b0, left } + { 1'b0, right };
		`ALU_MINUS: { Ctmp, res } = { 1'b0, left } - { 1'b0, right };
		`ALU_BIS: res = left | right;
		`ALU_BIC: res = ~left & right;
		`ALU_AND: res = left & right;
		default: res = 0;
		endcase


	assign result = res;
	assign cry = Ctmp;
	assign zero = ~|res;


endmodule

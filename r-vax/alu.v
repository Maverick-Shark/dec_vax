/*      $Id$       */
`timescale 1ns / 1ps
`default_nettype none


`include "aluops.vh"

module alu(
	input		clk,

	input [3:0]	op,

	input [31:0]	left,
	input [31:0]	right,

	input		stb,
	output		ack,

	output		neg,
	output		ovf,
	output		cry,
	output		zero,
	output [31:0]	result
);

	reg [31:0]	res;
	reg		Ctmp;
	reg [5:0]	shlcnt;
	reg		state, done, quick;
	reg [31:0]	shldata;
	wire		topbit;

parameter BEGIN=0;
parameter SHIFT=1;

	always @(op, left, right, shldata)
		case (op)
		`ALU_PLUS: { Ctmp, res } = { 1'b0, left } + { 1'b0, right };
		`ALU_MINUS: { Ctmp, res } = { 1'b0, left } - { 1'b0, right };
		`ALU_BIS: res = left | right;
		`ALU_BIC: res = ~left & right;
		`ALU_AND: res = left & right;
		`ALU_XOR: res = left ^ right;
		`ALU_SHL, `ALU_SHR, `ALU_ASR: res = shldata;
		default: res = 0;
		endcase

	assign topbit = (op == `ALU_SHR) ? 0 : shldata[31];
	always @(posedge clk) begin
//if (stb|done)$fdisplay(32'h80000002, "CLK: stb %d ack %d\r", stb, ack);
		if (stb == 0) begin
			state <= BEGIN;
			done <= 0;
		end else
		case (state)
		BEGIN: if (stb) begin
//$fdisplay(32'h80000002, "begin: op %d right %d left %x\r", op, right, left);
			shlcnt <= right[5:0];
			shldata <= left;
			state <= SHIFT;
		end
		SHIFT: begin
//$fdisplay(32'h80000002, "shift: shlcnt %d shldata %x\r", shlcnt, shldata);
			if (~|shlcnt) begin
				done <= 1;
			end else begin
				shlcnt <= shlcnt - 1;
				if (op == `ALU_SHL)
					shldata <= { shldata[30:0], 1'b0 };
				else
					shldata <= { topbit, shldata[31:1] };
			end 
		end
		endcase
	end

	always @(op)
		case (op)
		`ALU_PLUS, `ALU_MINUS, `ALU_BIS, `ALU_BIC, `ALU_AND,
		    `ALU_XOR: quick = 1;
		`ALU_SHL, `ALU_SHR, `ALU_ASR: quick = 0;
		default: quick = 1;
		endcase

	assign ack = stb ? (quick ? 1 : done) : 0;

	assign result = res;
	assign cry = Ctmp;
	assign neg = res[31];
	assign zero = ~|res;
	assign ovf = op == `ALU_PLUS ?
	    (left[31] == right[31]) && (left[31] != res[31]) :
	    (left[31] ^ right[31]) && (left[31] ^ res[31]);


endmodule

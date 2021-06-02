/*      $Id$       */
`timescale 1ns / 1ps
`default_nettype none


`include "aluops.vh"

module alu(
	input		clk,

	input [3:0]	op,

	input [31:0]	left,
	input [31:0]	right,

	input		use8,
	input		use16,

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
	reg		state, done, quick, dstate;
	reg [31:0]	shldata;
	wire		topbit;
	wire		t_ovf, t_ovf8, t_ovf16, mul_z, mul_v, mul_n;
	wire		isdone;

	wire signed [31:0] s_left, s_right;
	reg signed [63:0] s_res;

	assign s_left = left;
	assign s_right = right;
parameter BEGIN=0;
parameter SHIFT=1;

	wire [31:0]	q, r;
	wire		divbusy;
	reg		divstart, divdone;

	div div(
		.clock(clk),
		.dividend(right),
		.divisor(left),
		.start(divstart),

		.q(q),
		.r(r),
		.busy(divbusy)
	);
	always @(posedge clk) begin
		if (stb == 0) begin
			divdone <= 0;
			divstart <= 0;
			dstate <= BEGIN;
		end else
		case (dstate)
		BEGIN: if (stb) begin
//$fdisplay(32'h80000002, "DIV0: divbusy %d q %x ack %d quick %d op %d", divbusy, q, ack, quick, op);
			divstart <= 1;
			if (divbusy)
				dstate <= SHIFT;
		end
		SHIFT: begin
//$fdisplay(32'h80000002, "DIV: divbusy %d q %x", divbusy, q);
			divstart <= 0;
			if (divbusy == 0)
				divdone <= 1;
		end
		endcase
	end

	always @(*)
		case (op)
		`ALU_PLUS: { Ctmp, res } = { 1'b0, left } + { 1'b0, right };
		`ALU_MINUS: { Ctmp, res } = { 1'b0, left } - { 1'b0, right };
		`ALU_BIS: res = left | right;
		`ALU_BIC: res = ~left & right;
		`ALU_AND: res = left & right;
		`ALU_XOR: res = left ^ right;
		`ALU_SHL, `ALU_SHR, `ALU_ASR: res = shldata;
		`ALU_MUL: s_res = s_left * s_right;
		`ALU_DIV: res = q;
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
		`ALU_SHL, `ALU_SHR, `ALU_ASR, `ALU_DIV: quick = 0;
		default: quick = 1;
		endcase

	
	assign isdone = op == `ALU_DIV ? divdone : done;
	assign ack = stb ? (quick ? 1 : isdone) : 0;

	assign result = op == `ALU_MUL ? s_res[31:0] : res;
	assign cry = Ctmp;
	assign mul_n = use8 ? s_res[7] : use16 ? s_res[15] : s_res[31];
	assign neg = op == `ALU_MUL ? mul_n :
		use8 ? res[7] : use16 ? res[15] : res[31];
	assign mul_z = use8 ? ~|s_res[7:0] : use16 ?
		~|s_res[15:0] : ~|s_res[31:0];
	assign zero = op == `ALU_MUL ?  mul_z :
		use8 ? ~|res[7:0] : use16 ? ~|res[15:0] : ~|res;
	assign mul_v = use8 ? s_res[15:8] != {8{s_res[7]}} :
		use16 ? s_res[31:16] != {16{s_res[15]}} :
		s_res[63:32] != {32{s_res[31]}};
		
	assign t_ovf8 = op == `ALU_PLUS ?
	    (left[7] == right[7]) && (left[7] != res[7]) :
	    (left[7] ^ right[7]) && (left[7] ^ res[7]);
	assign t_ovf16 = op == `ALU_PLUS ?
	    (left[15] == right[15]) && (left[15] != res[15]) :
	    (left[15] ^ right[15]) && (left[15] ^ res[15]);
	assign t_ovf = op == `ALU_PLUS ?
	    (left[31] == right[31]) && (left[31] != res[31]) :
	    (left[31] ^ right[31]) && (left[31] ^ res[31]);
	assign ovf = op == `ALU_MUL ? mul_v :
		use8 ? t_ovf8 : use16 ? t_ovf16 : t_ovf;


endmodule

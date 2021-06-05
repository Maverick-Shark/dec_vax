/*	$Id$	*/

`timescale 1ns / 1ps
`default_nettype none
module div(
	input clock,
	input [31:0] dividend,
	input [31:0] divisor,
	input start,

	output [31:0] q,
	output [31:0] r,
	output reg busy
);

	reg [5:0]	count;
	reg [31:00]	reg_q;
	reg [31:00]	reg_r;
	reg [31:00]	reg_b;
	reg		r_sign;
	wire [32:0] 	sub_add;

	assign sub_add = r_sign ? ({reg_r, reg_q[31]} + {1'b0, reg_b}) :
			({reg_r, reg_q[31]} - {1'b0 , reg_b});
	assign r = r_sign ? reg_r + reg_b : reg_r;
	assign q = reg_q;

	initial count = 0;
	initial busy = 0;
	
	always @(posedge clock) begin
		if(start)begin
			reg_r <= 32'b0;
			r_sign <= 0;
			reg_q <= dividend;
			reg_b <= divisor;
			count <= 0;
			busy <= 1;
		end else if(busy) begin
			r_sign <= sub_add[32];
			reg_r <= sub_add[31:0];
			reg_q <= {reg_q[30:0], ~sub_add[32]};
			count <= count+1;
			if (count == 31)
				busy <= 0;
		end
	end
endmodule
 

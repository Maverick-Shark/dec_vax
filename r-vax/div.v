/*
 * Copyright (c) 2021 Anders Magnusson (ragge@tethuvudet.se).
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


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
 

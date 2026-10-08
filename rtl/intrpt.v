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


module intrpt(
	input [31:0]	intl,
	input [4:0]	ipl,

	output		intrq,
	output [4:0]	intlvl
);
	wire		b4, b3, b2, b1, b0;
	wire [15:0]	x16;
	wire [7:0]	x8;
	wire [3:0]	x4;
	wire [5:0]	iplsum;

	/*
	 * Combinatorial network to find highest interrupt requested.
	 */
	assign b4 = |intl[31:16];
	assign x16 = b4 ? intl[31:16] : intl[15:0];
	assign b3 = |x16[15:8];
	assign x8 = b3 ? x16[15:8] : x16[7:0];
	assign b2 = |x8[7:4];
	assign x4 = b2 ? x8[7:4] : x8[3:0];
	assign b1 = |x4[3:2];
	assign b0 = b1 ? x4[3] : x4[1];

	assign intlvl = { b4, b3, b2, b1, b0 };

	/*
	 * Higher than current IPL?
	 * Check by adding complement and see if we get a carry out.
	 */
	assign iplsum = { 1'b0, (~ipl) } + { 1'b0, intlvl };
	assign intrq = iplsum[5];

endmodule

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


module bitmasks(
	input [4:0]	pos,
	input [4:0]	size,

	output [31:0]	bm_pos,
	output [31:0]	bm_neg
);
	reg [31:0]	bmsk;

	always @* begin
		case (size)
//		5'd31: bmsk = 32'hffff_ffff;
		5'd31: bmsk = 32'h7fff_ffff;

		5'd30: bmsk = 32'h3fff_ffff;
		5'd29: bmsk = 32'h1fff_ffff;
		5'd28: bmsk = 32'h0fff_ffff;
		5'd27: bmsk = 32'h07ff_ffff;
		5'd26: bmsk = 32'h03ff_ffff;
		5'd25: bmsk = 32'h01ff_ffff;
		5'd24: bmsk = 32'h00ff_ffff;
		5'd23: bmsk = 32'h007f_ffff;
		5'd22: bmsk = 32'h003f_ffff;
		5'd21: bmsk = 32'h001f_ffff;

		5'd20: bmsk = 32'h000f_ffff;
		5'd19: bmsk = 32'h0007_ffff;
		5'd18: bmsk = 32'h0003_ffff;
		5'd17: bmsk = 32'h0001_ffff;
		5'd16: bmsk = 32'h0000_ffff;
		5'd15: bmsk = 32'h0000_7fff;
		5'd14: bmsk = 32'h0000_3fff;
		5'd13: bmsk = 32'h0000_1fff;
		5'd12: bmsk = 32'h0000_0fff;
		5'd11: bmsk = 32'h0000_07ff;

		5'd10: bmsk = 32'h0000_03ff;
		5'd09: bmsk = 32'h0000_01ff;
		5'd08: bmsk = 32'h0000_00ff;
		5'd07: bmsk = 32'h0000_007f;
		5'd06: bmsk = 32'h0000_003f;
		5'd05: bmsk = 32'h0000_001f;
		5'd04: bmsk = 32'h0000_000f;
		5'd03: bmsk = 32'h0000_0007;
		5'd02: bmsk = 32'h0000_0003;
		5'd01: bmsk = 32'h0000_0001;
		5'd00: bmsk = 32'h0000_0000;
		endcase
	end

	assign bm_pos = bmsk << pos;
	assign bm_neg = (~bmsk) << pos;
endmodule

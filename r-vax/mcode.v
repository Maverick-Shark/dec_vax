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

module mcode(
	input			clk,

	input [8:0]		ADR_I,
	input			STB_I,
	output [31:0]		DAT_O,
	output			ACK_O
);

parameter	ROM_WIDTH = 32;
parameter	ROM_ADDRS = 512;

	reg [ROM_WIDTH-1:0] mcode_rom [ROM_ADDRS-1:0];
	reg [ROM_WIDTH-1:0] mcode_data;
	reg		ack;

	initial $readmemh("mcode.hex", mcode_rom, 0, ROM_ADDRS-1);


	always @(posedge clk) begin
		ack <= 0;
		if (STB_I) begin
			mcode_data <= mcode_rom[ADR_I];
			ack <= 1;
		end
	end

	assign DAT_O = STB_I ? mcode_data : 32'b0;
	assign ACK_O = STB_I ? ack : 1'b0;

endmodule

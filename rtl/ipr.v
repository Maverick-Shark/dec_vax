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
/*
 * IPR storage/handling module.
 *
 * Not used by the MiSTer build: the CPU keeps its internal processor
 * registers in cpu.v (and the MMU's in mmu.v). This module is r-vax's early
 * IPR store, kept with the rest of the original sources.
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
	end

endmodule

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

module blkram(
	input		clk,
	input		rst,

	input [21:0]	pmem_addr,
	input		pmem_write,
	input [31:0]	pmem_wdata,
	input		pmem_stb,
	output reg [31:0] pmem_rdata,
	output reg	pmem_ack
);
parameter MEMSZ=4096;
	reg [31:0] memblk [MEMSZ-1:0];

	always @(posedge clk) begin
		if (|pmem_addr[21:12] && pmem_stb) begin
			pmem_rdata <= 32'b0;
			pmem_ack <= 1;
		end else if (pmem_stb) begin
			if (pmem_write == 0) begin
				pmem_rdata <= memblk[pmem_addr[11:0]];
			end else
				memblk[pmem_addr[11:0]] <= pmem_wdata;
			pmem_ack <= 1;
		end else
			pmem_ack <= 0;
	end

endmodule


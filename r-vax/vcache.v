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

`include "opcodes.vh"

/*
 * simple virtual cache, which also converts unaligned accesses to aligned.
 */

`define	IDLE		0
`define	FASTPATH	1
`define	SLOWRMEM	2
`define	SLOWRMEM2	3
`define	SLOWRMEM3	4
`define	RETWD		5
`define	SETWD		6
`define	WRHIGH		7
`define	WRHIGH2		8
`define	WRHIGH3		9
`define	SETTLE		10
`define	SETTLEWD	11

module vcache(
	input		clk,
	input		rst,

	input		IN_STB_I,
	output [31:0]	IN_DAT_O,
	output		IN_ACK_O,
/* verilator lint_off UNUSED */
	input [31:0]	IN_ADR_I,
/* verilator lint_on UNUSED */
	input [31:0]	IN_DAT_I,
	input		IN_WE_I,

	input [1:0]	in_sz,
	input		in_passthru,

	input		in_mcheck,

//	output [1:0]	ut_sz,

`ifdef DBGCNT
	input [7:0]	dcount,
`endif
	output 		UT_STB_O,
	output [31:0]	UT_ADR_O,
	output [31:0]	UT_DAT_O,
	output		UT_WE_O,
	input [31:0]	UT_DAT_I,
	input		UT_ACK_I
);


	reg [63:0]	quad, merged_write_word;
	reg [3:0]	state;
	reg		needtwo;
	reg [31:0]	shifted_bytes;
	reg [31:0]	caddrl, caddrh;
	reg [1:0]	coff, csz;

	wire in_stb;
	reg [31:0] in_rdata;
	reg in_ack;
	assign in_stb = IN_STB_I;
	assign IN_DAT_O = IN_STB_I ? in_rdata : 32'b0;
	assign IN_ACK_O = IN_STB_I ? in_ack : 1'b0;

	reg		ut_stb, ut_write;
	reg [31:0]	ut_addr;
	reg [31:0]	ut_wdata;
//	reg [1:0]	ut_sz;
	assign UT_STB_O = ut_stb;
	assign UT_ADR_O = ut_addr;
	assign UT_DAT_O = ut_wdata;
	assign UT_WE_O = ut_write;

	/* read/write cases when we need two words */
	always @* begin
		casez ({csz, coff })
		4'b01_11: needtwo = 1; // word on addr 3
		4'b10_01: needtwo = 1;
		4'b10_1?: needtwo = 1;
		default: needtwo = 0;
		endcase
	end

	/* merged longwords when writing unaligned/partial words */
	always @* begin
		casez ({csz, coff })
		/* byte size first, addr off 0-3 */
		4'b00_00: merged_write_word = { quad[63:8], IN_DAT_I[7:0] };
		4'b00_01: merged_write_word = { quad[63:16], IN_DAT_I[7:0], quad[7:0] };
		4'b00_10: merged_write_word = { quad[63:24], IN_DAT_I[7:0], quad[15:0] };
		4'b00_11: merged_write_word = { quad[63:32], IN_DAT_I[7:0], quad[23:0] };

		/* word size */
		4'b01_00: merged_write_word = { quad[63:16], IN_DAT_I[15:0] };
		4'b01_01: merged_write_word = { quad[63:24], IN_DAT_I[15:0], quad[7:0] };
		4'b01_10: merged_write_word = { quad[63:32], IN_DAT_I[15:0], quad[15:0] };
		4'b01_11: merged_write_word = { quad[63:40], IN_DAT_I[15:0], quad[23:0] };

		4'b10_00: merged_write_word = { quad[63:32], IN_DAT_I };
		4'b10_01: merged_write_word = { quad[63:40], IN_DAT_I, quad[7:0] };
		4'b10_10: merged_write_word = { quad[63:48], IN_DAT_I, quad[15:0] };
		4'b10_11: merged_write_word = { quad[63:56], IN_DAT_I, quad[23:0] };
		default: merged_write_word = 0; /* ILLEGAL */
		endcase
	end

	/* Shift quad word left */
	always @* begin
		case (coff)
		2'b00: shifted_bytes = quad[31:0];
		2'b01: shifted_bytes = quad[39:8];
		2'b10: shifted_bytes = quad[47:16];
		2'b11: shifted_bytes = quad[55:24];
		endcase
	end

	always @(posedge clk) begin
`ifdef DBGCNT
//if (state != `IDLE && IN_ADR_I[31:4] != 28'h20001f7)
//$fdisplay(32'h80000002, "VC    %d: state %d in_addr %x rdata %x utdati %x sdack %d", dcount, state, IN_ADR_I, in_rdata, UT_DAT_I, UT_ACK_I);
`endif
		if (rst) begin
			state <= `IDLE;
			in_ack <= 0;
			ut_stb <= 0;
		end else
		case (state)
		`IDLE: begin
			if (UT_ACK_I)
				ut_stb <= 0;
			else if (in_stb == 0)
				in_ack <= 0;
			else begin
//				ut_addr <= { IN_ADR_I[31:2], 2'b0 };
				ut_addr <= IN_ADR_I[31:0];
				ut_stb <= 1;
				caddrl <= { IN_ADR_I[31:2], 2'b0 };
				caddrh <= { IN_ADR_I[31:2], 2'b0 } + 4;
				coff <= IN_ADR_I[1:0];
				csz <= in_sz[1] ? `O_LONG : in_sz;
				if (in_passthru ||
				    (IN_ADR_I[1:0] == 2'b00 && in_sz[1])) begin
					/* fastpath, aligned longword access */
					ut_write <= IN_WE_I;
					ut_wdata <= IN_DAT_I;
		//			ut_sz <= in_sz;
					state <= `FASTPATH;
				end else begin
					ut_write <= 0;
					state <= `SLOWRMEM;
				end
			end
		end
		`FASTPATH: if (UT_ACK_I | in_mcheck) begin
			if (IN_WE_I == 0)
				in_rdata <= UT_DAT_I;
			in_ack <= 1;
			state <= `SETTLE;
		end
		`SLOWRMEM: if (UT_ACK_I | in_mcheck) begin
			/* got first word */
			quad[31:0] <= UT_DAT_I;
			ut_stb <= 0;
			if (needtwo) begin // get another word
				ut_addr <= caddrh;
				state <= `SLOWRMEM2;
			end else if (IN_WE_I == 0) begin
				state <= `RETWD;
			end else begin
				state <= `SETWD;
				
			end
		end
		`SLOWRMEM2: if (UT_ACK_I == 0) begin // wait until settle
			ut_stb <= 1; /* start next word */
			state <= `SLOWRMEM3;
		end
		`SLOWRMEM3: if (UT_ACK_I || in_mcheck) begin
			quad[63:32] <= UT_DAT_I;
			ut_stb <= 0;
			if (IN_WE_I == 0)
				state <= `RETWD;
			else
				state <= `SETWD;
		end

		`SETWD: if (UT_ACK_I == 0) begin
			ut_wdata <= merged_write_word[31:0];
			ut_addr <= caddrl;
			ut_write <= 1;
			ut_stb <= 1;
			if (needtwo) begin
				state <= `WRHIGH;
			end else begin
				in_ack <= 1;
				state <= `SETTLEWD;
			end
		end

		`WRHIGH: if (UT_ACK_I) begin
			ut_stb <= 0;
			ut_wdata <= merged_write_word[63:32];
			ut_addr <= caddrh;
			ut_write <= 1;
			state <= `WRHIGH2;
		end

		`WRHIGH2: if (UT_ACK_I == 0) begin
			ut_stb <= 1;
			state <= `WRHIGH3;
		end

		`WRHIGH3: if (UT_ACK_I) begin
			ut_stb <= 0;
			in_ack <= 1;
			state <= `SETTLE;
		end

		`SETTLE: begin
			if (in_stb == 0 && UT_ACK_I == 0)
				state <= `IDLE;
			if (in_stb == 0)
				in_ack <= 0;
			if (UT_ACK_I == 1)
				ut_stb <= 0;
		end

		`SETTLEWD: begin
			if (in_stb == 0)
				in_ack <= 0;
			if (UT_ACK_I)
				ut_stb <= 0;
			if (in_ack == 0 && ut_stb == 0)
				state <= `IDLE;
		end

		/* Return an unaligned word */
		`RETWD: begin
			in_rdata <= shifted_bytes;
			in_ack <= 1;
			state <= `SETTLE;
		end
		default: state <= `IDLE;
		endcase
	end 

endmodule

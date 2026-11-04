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
 * The aligner (r-vax calls it a "simple virtual cache"; it caches nothing):
 * it turns the CPU's byte, word and longword accesses, aligned or not, into
 * aligned longword cycles with byte masks (UT_SEL_O), as the VAX 8600 MBox
 * sees them.
 *
 * An access inside one longword is one cycle: a write writes only its bytes
 * (no read first), a read asks for its bytes, which tells an I/O adapter
 * whether a word or a longword is read. An access that crosses a longword
 * is two cycles, the low longword first. A write that crosses a page
 * reads both longwords first, with write intent (in_wint from the CPU), so
 * that a translation fault on the second page leaves memory untouched; then
 * it writes them. The CPU gets its acknowledge when the last cycle has been
 * acknowledged, so a machine check (in_mcheck) always belongs to the
 * instruction that caused it.
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
`define	FLTWAIT		12

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
	input		in_flt,		/* translation fault from the MMU: give up */

`ifdef DBGCNT
	input [7:0]	dcount,
`endif
	output 		UT_STB_O,
	output [31:0]	UT_ADR_O,
	output [31:0]	UT_DAT_O,
	output [3:0]	UT_SEL_O,	/* byte mask of the longword cycle */
	output		UT_WE_O,
	input [31:0]	UT_DAT_I,
	input		UT_ACK_I
);

	reg [63:0]	quad;
	reg [3:0]	state;
	reg		needtwo;
	reg [31:0]	shifted_bytes;
	reg [31:0]	caddrl, caddrh;
	reg [1:0]	coff, csz;
	reg [63:0]	cwdat;		/* write data in its byte lanes */
	reg [7:0]	cmask;		/* the bytes of the quadword it covers */

	wire in_stb;
	reg [31:0] in_rdata;
	reg in_ack;
	assign in_stb = IN_STB_I;
	assign IN_DAT_O = IN_STB_I ? in_rdata : 32'b0;
	assign IN_ACK_O = IN_STB_I ? in_ack : 1'b0;

	reg		ut_stb, ut_write;
	reg [31:0]	ut_addr;
	reg [31:0]	ut_wdata;
	reg [3:0]	ut_sel;
	assign UT_STB_O = ut_stb;
	assign UT_ADR_O = ut_addr;
	assign UT_DAT_O = ut_wdata;
	assign UT_SEL_O = ut_sel;
	assign UT_WE_O = ut_write;

	/* the access as it comes in */
	wire [1:0]	isz = in_sz[1] ? `O_LONG : in_sz;
	wire [1:0]	ioff = IN_ADR_I[1:0];
	wire [7:0]	imask = (isz == `O_BYTE ? 8'b0000_0001 :
			    isz == `O_WORD ? 8'b0000_0011 : 8'b0000_1111) << ioff;
	wire [63:0]	iwdat = { 32'd0, IN_DAT_I } << { ioff, 3'b000 };
	wire		itwo = |imask[7:4];
	/* a crossing write within one page needs no reads first */
	wire [31:0]	iadrh = { IN_ADR_I[31:2], 2'b0 } + 32'd4;
	wire		ipage = (IN_ADR_I[31:9] != iadrh[31:9]);

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
//$fdisplay(32'h80000002, "VC    %d: state %d in_addr %x rdata %x utdati %x sdack %d", dcount, state, IN_ADR_I, in_rdata, UT_DAT_I, UT_ACK_I);
`endif
		if (rst) begin
			state <= `IDLE;
			in_ack <= 0;
			ut_stb <= 0;
		end else if (in_flt && state != `IDLE && state != `FLTWAIT) begin
			/*
			 * The MMU refused one of the longword cycles. Nothing has
			 * been written yet: a write that crosses a page reads
			 * (with write intent) both longwords before it writes
			 * either. Wait for the CPU to drop its strobe.
			 */
			ut_stb <= 0;
			in_ack <= 0;
			state <= `FLTWAIT;
		end else if (in_mcheck && state != `IDLE && state != `SETTLE &&
		    state != `FLTWAIT) begin
			/*
			 * The MBox could not complete a longword cycle (machine
			 * check): end it on the bus, so that it cannot run into
			 * the next one, and let the CPU (or the console) see the
			 * access end, with undefined data.
			 */
			ut_stb <= 0;
			in_ack <= 1;
			state <= `SETTLE;
		end else
		case (state)
		`IDLE: begin
			if (UT_ACK_I)
				ut_stb <= 0;
			else if (in_stb == 0)
				in_ack <= 0;
			else begin
				/* the first cycle carries the access's own
				   address: a fault reports it */
				ut_addr <= IN_ADR_I;
				ut_stb <= 1;
				caddrl <= { IN_ADR_I[31:2], 2'b0 };
				caddrh <= iadrh;
				coff <= ioff;
				csz <= isz;
				needtwo <= itwo;
				cwdat <= iwdat;
				cmask <= imask;
				if (in_passthru) begin
					/* physical microcode references:
					   aligned longwords */
					ut_write <= IN_WE_I;
					ut_wdata <= IN_DAT_I;
					ut_sel <= 4'b1111;
					state <= `FASTPATH;
				end else if (!itwo) begin
					/* inside one longword: one cycle */
					ut_write <= IN_WE_I;
					ut_wdata <= iwdat[31:0];
					ut_sel <= imask[3:0];
					state <= (IN_WE_I || ioff == 2'b00) ?
					    `FASTPATH : `SLOWRMEM;
				end else if (IN_WE_I && !ipage) begin
					/* crossing a longword, not a page:
					   write both halves */
					ut_write <= 1;
					ut_wdata <= iwdat[31:0];
					ut_sel <= imask[3:0];
					state <= `WRHIGH;
				end else begin
					/* crossing: read the low longword
					   (for a write, the check before it) */
					ut_write <= 0;
					ut_sel <= imask[3:0];
					state <= `SLOWRMEM;
				end
			end
		end
		`FASTPATH: if (UT_ACK_I) begin
			if (IN_WE_I == 0)
				in_rdata <= UT_DAT_I;
			ut_stb <= 0;
			in_ack <= 1;
			state <= `SETTLE;
		end
		`SLOWRMEM: if (UT_ACK_I) begin
			/* got first word */
			quad[31:0] <= UT_DAT_I;
			ut_stb <= 0;
			if (needtwo) begin // get another word
				ut_addr <= caddrh;
				ut_sel <= cmask[7:4];
				state <= `SLOWRMEM2;
			end else
				state <= `RETWD;
		end
		`SLOWRMEM2: if (UT_ACK_I == 0) begin // wait until settle
			ut_stb <= 1; /* start next word */
			state <= `SLOWRMEM3;
		end
		`SLOWRMEM3: if (UT_ACK_I) begin
			quad[63:32] <= UT_DAT_I;
			ut_stb <= 0;
			if (IN_WE_I == 0)
				state <= `RETWD;
			else
				state <= `SETWD;
		end

		/* a write crossing a page, both longwords checked: the low one */
		`SETWD: if (UT_ACK_I == 0) begin
			ut_wdata <= cwdat[31:0];
			ut_sel <= cmask[3:0];
			ut_addr <= caddrl;
			ut_write <= 1;
			ut_stb <= 1;
			state <= `WRHIGH;
		end

		/* the high longword of a crossing write */
		`WRHIGH: if (UT_ACK_I) begin
			ut_stb <= 0;
			ut_wdata <= cwdat[63:32];
			ut_sel <= cmask[7:4];
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

		/* Return an unaligned word */
		`RETWD: begin
			in_rdata <= shifted_bytes;
			in_ack <= 1;
			state <= `SETTLE;
		end
		`FLTWAIT: begin
			in_ack <= 0;
			if (in_stb == 0 && UT_ACK_I == 0)
				state <= `IDLE;
		end
		default: state <= `IDLE;
		endcase
	end 

endmodule

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
 * Interval clock logic.
 *
 * NICR (WO) keeps the starting point for the counter.
 * ICR (RO) counts up each microsecond until it wraps, then reloads from NICR.
 * ICCS (RW) keeps control/status bits;
 *	ERR (31) - clock overrun
 *	INT (7)	 - interrupt
 *	IE  (6) - interrupt enable
 *	SGL (5)	 - single step
 *	XFR (4) - load ICR
 *	RUN (0)	 - get auto increment
 *
 * wrnicr_i and wriccs_i are only set one clock cycle.
 */

`define	ERR	31
`define	INT	7
`define	IE	6
`define	SGL	5
`define	XFR	4
`define	RUN	0

module intclk(
	input		clk,
	output		intrq,

	output reg [31:0] icr, // ICR
	output reg [31:0] todr, // TODR

	input		wrnicr,
	input		wriccs,
	input		wrtodr,

	input [31:0]	iprdb,

	output		err_o,
	output		int_o,
	output		ie_o,
	output		run_o
);

parameter CLKINIT =	8'h4f;	// 50MHz clock to microseconds: 79..128 = 50 states
parameter TODRCNTINIT =	15'h18f1; // 10 ms clock: 6385..16384 = 10000 us

	reg [31:0]	nicr;
	reg		running, error, inten, intreq;

	/* load NICR */
	always @(posedge clk)
		if (wrnicr)
			nicr <= iprdb;

	/* set ICCS bits */
	always @(posedge clk) begin
		if (wriccs) begin
			running <= iprdb[`RUN];
			inten <= iprdb[`IE];
//$fdisplay(32'h80000002, "WRICCS: run %d ie %d xfr %d" , iprdb[`RUN], iprdb[`IE], iprdb[`XFR]);
		end

	end

	/*
	 * clock divider, counts up until bit7 set, then reloads
	 * with CLKINIT value.  Result is a microsecond clock.
	 */
	reg [7:0]	clkcnt;
	wire		uspulse;
	always @(posedge clk)
		if (clkcnt[7])
			clkcnt <= CLKINIT;
		else
			clkcnt <= clkcnt + 1;
	assign uspulse = clkcnt[7] & running;

	/*
	 * Counts to 10000, then increases TODR. This is a 10ms clock.
	 */
	initial todr = 32'h7315BAAC; // VMS valid something...
	reg [14:0]	todrcnt;
	always @(posedge clk) begin
		if (wrtodr)
			todr <= iprdb;
		else if (clkcnt[7]) begin
			if (todrcnt[14]) begin
				todrcnt <= TODRCNTINIT;
				todr <= todr + 1;
			end else
				todrcnt <= todrcnt + 1;
		end
	end

	/*
	 * Interval count register (SRM 8.x, interval clock): incremented
	 * every microsecond while RUN is set, or once by writing SGL with RUN
	 * clear. When an increment overflows, ICR is reloaded from NICR and
	 * INT is set (ERR too if INT still is). XFR loads ICR from NICR, which
	 * is not an overflow: ICR = FFFFFFFF interrupts at the next increment.
	 */
	wire [32:0]	nexticr;
	wire		icrstep, icrovf;
	assign nexticr = { 1'b0, icr } + 1;
	assign icrstep = uspulse || (wriccs && iprdb[`SGL] && !running);
	assign icrovf = icrstep && nexticr[32] && !(wriccs && iprdb[`XFR]);
	always @(posedge clk) begin
		if (wriccs && iprdb[`XFR])
			icr <= nicr;
		else if (icrstep)
			icr <= nexticr[32] ? nicr : nexticr[31:0];
	end

	/*
	 * Interrupts
	 */
	always @(posedge clk) begin
		if (wriccs && iprdb[`ERR])
			error <= 0;
		if (wriccs && iprdb[`INT])
			intreq <= 0;
		if (icrovf) begin
			intreq <= 1;
			if (intreq)
				error <= 1;
		end
	end

	assign intrq = intreq & inten;
	assign ie_o = inten;
	assign err_o = error;
	assign int_o = intreq;
	assign run_o = running;

endmodule

/*	$Id$	*/
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

	// ICR
	output reg [31:0] icr,

	// NICR
	input		wrnicr,
	input		wriccs,

	input [31:0]	iprdb,

	output		err_o,
	output		int_o,
	output		ie_o,
	output		run_o
);

parameter CLKINIT =	8'h4e;	// 50MHz clock to microseconds. (128-50)

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
	 * interval count register.
	 */
	wire [32:0]	nexticr;
	assign nexticr = { 1'b0, icr } + 1;
	always @(posedge clk) begin
		if (uspulse || ((iprdb[`SGL]|iprdb[`XFR]) && wriccs)) begin
			if (nexticr[32] | (wriccs & iprdb[`XFR]))
				icr <= nicr;
			else
				icr <= nexticr[31:0];
		end
	end

	/*
	 * Interrupts
	 */
	always @(posedge clk) begin
		if (wriccs && iprdb[`ERR])
			error <= 0;
		if (wriccs && iprdb[`INT])
			intreq <= 0;
		if (nexticr[32]) begin
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

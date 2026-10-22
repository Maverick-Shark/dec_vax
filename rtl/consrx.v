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
/*
 * TTI - Resembles (somewhat) a DG 4077 controller.
 *
 * Set DONE after character received. Must be cleared by program.
 * BUSY is set if START is issued and cleared when DONE.
 * 
 * When break is detected the gotbreak signal is set from that it is
 * detected in the stop bit until it is released.  Break do not generate
 * a done/devcomplete signal.
 */

`ifndef CLKPERBIT
`ifdef VERILATOR
`define	CLKPERBIT	20
`else
`define	CLKPERBIT	5208
`endif
`endif

module consrx(
	input		clk,
	input		rst,		/* processor initialization: RXCS = 0 */

	input		wrie,
	input		wrrxcs,
	input		rdrxdb,

	input		intack,
	output reg	intreq,

	output		ie,
	output		rdy,
	output [7:0]	rxdb,

	input		tti_rx
);
	parameter NCYC = 10;

	reg [8:0]	rxraw;
	reg [15:0]	clkcnt;
	reg [NCYC-1:0] shiftreg;
	reg shin, shce, last_ie_rdy;
	reg busy, inten, done, clear;

	assign rxdb = rxraw[7:0];

`ifdef TTIDEBUG
	always @(posedge clk)
		$fdisplay(32'h80000002,
		    "rxraw %x clkcnt %x bitcnt %x clear %d done %d tti_rx %d",
		    rxraw, clkcnt, bitcnt, clear, done, tti_rx);
`endif
	
	initial clkcnt = 32768-`CLKPERBIT;

	always @(posedge clk) begin
		if (rst)
			intreq <= 0;
		else if (rdy & ie & last_ie_rdy == 0) begin
			intreq <= 1;
		end else if (intack) begin
			intreq <= 0;
		end
		last_ie_rdy <= ie & rdy;
	end

	always @(posedge clk)
		clear <= rdrxdb & done;

	always @(posedge clk)
		if (rst)
			inten <= 0;
		else if (wrrxcs)
			inten <= wrie;

	always @(posedge clk)
		if (shce)
			shiftreg <= { shiftreg[NCYC-2:0], shin };

	always @(posedge clk) begin
		shce <= 0;
		shin <= 0;
		if (clkcnt[15])
			clkcnt <= 32768-`CLKPERBIT;
		else
			clkcnt <= clkcnt + 1;

		if (clear || rst)
			done <= 0;	/* processor initialization: RXCS = 0 */

		if (busy == 0) begin
			if (tti_rx == 0) begin
				shin <= 1;
				shce <= 1;
				busy <= 1;
				clkcnt <= 32768 - `CLKPERBIT/2;
			end
		end else begin
			if (clkcnt[15]) begin
				rxraw <= { tti_rx, rxraw[8:1] };
				shce <= 1;
				if (shiftreg[NCYC-1]) begin
					busy <= 0;
					done <= 1;
				end
			end
		end
	end

	assign ie = inten;
	assign rdy = done;

endmodule

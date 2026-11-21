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

/*
 * The console terminal's receiver: a character on tti_rx (8N1, CLKPERBIT
 * clocks a bit) sets rdy with the byte in rxdb until rdrxdb takes it. RXCS,
 * RXDB, the interrupt enable and the interrupt are the 8600 console's, in
 * cons86.v.
 */
module consrx(
	input		clk,
	input		rst,		/* processor initialization: no character */

	input		rdrxdb,

	output		rdy,
	output [7:0]	rxdb,

	input		tti_rx
);
	parameter NCYC = 10;

	reg [8:0]	rxraw;
	reg [15:0]	clkcnt;
	reg [NCYC-1:0] shiftreg;
	reg shin, shce;
	reg busy, done, clear;

	assign rxdb = rxraw[7:0];

`ifdef TTIDEBUG
	always @(posedge clk)
		$fdisplay(32'h80000002,
		    "rxraw %x clkcnt %x bitcnt %x clear %d done %d tti_rx %d",
		    rxraw, clkcnt, bitcnt, clear, done, tti_rx);
`endif
	
	initial clkcnt = 32768-`CLKPERBIT;

	always @(posedge clk)
		clear <= rdrxdb & done;

	/*
	 * The marker bit that counts the bits of a character is loaded when
	 * the start bit is seen, not shifted in after what the register held
	 * (see constx.v): a stray bit left in it at power-up cannot end a
	 * character early.
	 */
	initial shiftreg = {NCYC{1'b0}};
	initial busy = 1'b0;
	always @(posedge clk)
		if (shce)
			shiftreg <= shin ? { {NCYC-1{1'b0}}, 1'b1 } :
			    { shiftreg[NCYC-2:0], 1'b0 };

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
		/*
		 * Processor initialization leaves the receiver idle: busy with
		 * no marker on its way (a power-up state) would never end.
		 */
		if (rst)
			busy <= 0;
	end

	assign rdy = done;

endmodule

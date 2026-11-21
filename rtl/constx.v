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
 * The console terminal's transmitter: a byte written (wrtxdb) goes out on
 * tto_tx, 8N1, one bit every CLKPERBIT clocks; rdy while it can take the
 * next. TXCS, its interrupt enable and the interrupt are the 8600
 * console's, in cons86.v.
 */
`ifndef CLKPERBIT
`ifdef VERILATOR
`define CLKPERBIT	20
`else
`define CLKPERBIT	5208
`endif
`endif

module constx(
	input		clk,
	input		rst,		/* processor initialization */

	input [7:0]	iprdb,
	input		wrtxdb,

	output		rdy,

	output		tto_tx
);
	parameter NCYC = 10;

	reg [15:0] clkcnt;
	reg [8:0] txdb;

	reg [NCYC-1:0] shiftreg;
	reg shce, cntbit, xmit_rdy;

`ifdef notdef
	always @(posedge clk)
		if (wrtxdb)
		$fdisplay(32'h80000002,
		    "txdb %x txd %x txdb %x clkcnt %x ready %d tto_tx %d",
		    wrtxdb, iprdb, txdb, clkcnt, xmit_rdy, tto_tx);
`endif


	initial clkcnt = 32768-`CLKPERBIT;
	initial txdb = 9'h1ff;
	initial xmit_rdy = 1;

	/*
	 * One marker bit goes in when a character starts and ends the
	 * character when it comes out at the top. It is loaded, not shifted
	 * in after what the register held: at power-up the register has no
	 * defined value, and a stray bit in it ended the first character
	 * early, which left another one behind to cut the next short, and so
	 * on for ever.
	 */
	initial shiftreg = {NCYC{1'b0}};
	always @(posedge clk)
		if (shce)
			shiftreg <= cntbit ? { {NCYC-1{1'b0}}, 1'b1 } :
			    { shiftreg[NCYC-2:0], 1'b0 };

	always @(posedge clk) begin
		shce <= 0;
		cntbit <= 0;

		if (clkcnt[15])
			clkcnt <= 32768-`CLKPERBIT;
		else
			clkcnt <= clkcnt + 1;

		if (xmit_rdy) begin
			if (wrtxdb) begin
				txdb <= { iprdb, 1'b0 };
`ifdef TTODEBUG
	$fdisplay(32'h80000002, "printing char %d\r", iprdb);
`endif
				clkcnt <= 32768-`CLKPERBIT;
				shce <= 1;
				cntbit <= 1;
				xmit_rdy <= 0;
			end
		end else if (clkcnt[15]) begin
			txdb <= { 1'b1, txdb[8:1] };
			shce <= 1;
			if (shiftreg[NCYC-1]) begin
				xmit_rdy <= 1;
			end
		end
	end

	assign rdy = xmit_rdy;
	assign tto_tx = txdb[0];

endmodule

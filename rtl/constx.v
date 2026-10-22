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
 *
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
	input		rst,		/* processor initialization: IE cleared */

	input [7:0]	iprdb,
	input		wrtxcs,
	input		wrtxdb,

	input		intack,
	output reg	intreq,

	output		rdy,
	output		ie,

	output		tto_tx
);
	parameter NCYC = 10;

	reg [15:0] clkcnt;
	reg [8:0] txdb;

	reg [NCYC-1:0] shiftreg;
	reg shce, inten, cntbit, xmit_rdy, last_ie_rdy;

`ifdef notdef
	always @(posedge clk)
		if (wrtxcs | wrtxdb)
		$fdisplay(32'h80000002,
		    "txcs %x txdb %x txd %x txdb %x clkcnt %x ready %d tto_tx %d",
		    wrtxcs, wrtxdb, iprdb, txdb, clkcnt, xmit_rdy, tto_tx);
`endif


	initial clkcnt = 32768-`CLKPERBIT;
	initial txdb = 9'h1ff;
	initial xmit_rdy = 1;

	always @(posedge clk) begin
		if (rst)
			intreq <= 0;
		else if (rdy & ie & last_ie_rdy == 0)
			intreq <= 1;
		else if (intack)
			intreq <= 0;
		last_ie_rdy <= ie & rdy;
	end


	// int enable/disab only bit that can be changed
	always @(posedge clk)
		if (rst)
			inten <= 0;
		else if (wrtxcs)
			inten <= iprdb[6];

	always @(posedge clk)
		if (shce)
			shiftreg <= { shiftreg[NCYC-2:0], cntbit };

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
	assign ie = inten;
	assign tto_tx = txdb[0];

endmodule

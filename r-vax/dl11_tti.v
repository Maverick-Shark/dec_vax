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

module dl11_tti #(
`ifdef VERILATOR
	parameter CLKPERBIT = 20        // no need to wait long in simulation
`else
	parameter CLKPERBIT = 5208
`endif
) (
	input		clk,
	input		rst,

	input		clear,
	output 		done,
	output [7:0]	outdata,

	input		tti_rx
);

/* State table */
localparam TTIIDLE=	4'd0;
localparam TTISTART=	4'd1;
localparam TTIB0=	4'd2;
localparam TTIB1=	4'd3;
localparam TTIB2=	4'd4;
localparam TTIB3=	4'd5;
localparam TTIB4=	4'd6;
localparam TTIB5=	4'd7;
localparam TTIB6=	4'd8;
localparam TTIB7=	4'd9;
localparam TTISTOP=	4'd10;

	reg [7:0]	rxdata, data;
	reg [15:0]	clkcnt;
	reg [3:0]	state;
	reg		rxdone;

	assign outdata = data;
	assign done = rxdone;

	initial clkcnt = 0;
	always @(posedge clk) begin
		if (rst) begin
			rxdone <= 0;
			state <= TTIIDLE;
		end else if (state == TTIIDLE) begin
			if (clear)
				rxdone <= 0;
			if (tti_rx == 0) begin
				clkcnt <= 0;
				state <= TTISTART;
			end
		end else if (state == TTISTART) begin
			if (clkcnt == (CLKPERBIT/2)) begin
				if (tti_rx == 0) begin
					clkcnt <= 0;
					state <= TTIB0;
				end else
					state <= TTIIDLE;
			end else
				clkcnt <= clkcnt + 1;
		end else begin
			if (clkcnt == CLKPERBIT-1) begin
				if (state == TTISTOP) begin
					state <= TTIIDLE;
					data <= rxdata;
					rxdone <= 1;
				end else begin
					state <= state + 1;
					rxdata <= { tti_rx, rxdata[7:1] };
				end
				clkcnt <= 0;
			end else
				clkcnt <= clkcnt + 1;
		end
	end
endmodule

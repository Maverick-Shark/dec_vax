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
 *
 */

`define	TTOINIT		0
`define	TTOIDLE		1
`define	TTOSTART	2
`define	TTOB0		3
`define	TTOB1		4
`define	TTOB2		5
`define	TTOB3		6
`define	TTOB4		7
`define	TTOB5		8
`define	TTOB6		9
`define	TTOB7		10
`define	TTOSTOP		11

module tto #(
`ifdef VERILATOR
	parameter CLKPERBIT = 20	// no need to wait long in simulation
`else
	parameter CLKPERBIT = 5208	// (50000000/9600)
`endif
) (
	input		clk,
	input		iorst,
	input		start,
	input		clear,
	input		devsel,
	input		wdata,
	input		intmsk,
	output 		busy,
	output 		done,
	output		intreq,
	input [7:0]	data,

	output reg	tto_tx
);

	reg [15:0] clkcnt;
	reg [3:0] state;
	reg [7:0] utdata;
	reg devcomplete;
	reg ffbusy, ffdone;

	assign busy = devsel ? ffbusy : 1'b0;
	assign done = devsel ? ffdone : 1'b0;
	assign intreq = intmsk ? 1'b0 : ffdone;

	always @(posedge clk) begin
		if (iorst) begin
			ffbusy <= 0;
			ffdone <= 0;
		end else if (devcomplete) begin
			ffbusy <= 0;
			ffdone <= 1;
		end else
		if (devsel) begin
			if (clear) begin
				ffbusy <= 0;
				ffdone <= 0;
			end else if (start) begin
				ffbusy <= 1;
				ffdone <= 0;
			end
			if (wdata)
				utdata <= data;
		end
	end

	always @(posedge clk) begin
		if (iorst) begin
			state <= `TTOINIT;
			clkcnt <= 0;
		end else if (state == `TTOINIT) begin
			/* wait some time with tx high to settle */
			if (clkcnt == (CLKPERBIT*8))
				state <= `TTOIDLE;
			else
				clkcnt <= clkcnt + 1;
		end else if (state == `TTOIDLE) begin
			devcomplete <= 0;
			if (ffbusy && !devcomplete) begin
				clkcnt <= 0;
				state <= `TTOSTART;
			end
		end else begin
			if (clkcnt == CLKPERBIT-1) begin
				if (state > `TTOSTOP) begin
					state <= `TTOIDLE;
					devcomplete <= 1;
				end else
					state <= state + 1;
				clkcnt <= 0;
			end else
				clkcnt <= clkcnt + 1;
		end
	end

	always @* begin
		case (state)
		`TTOIDLE: tto_tx = 1;
		`TTOSTART: tto_tx = 0;
		`TTOB0: tto_tx = utdata[0];
		`TTOB1: tto_tx = utdata[1];
		`TTOB2: tto_tx = utdata[2];
		`TTOB3: tto_tx = utdata[3];
		`TTOB4: tto_tx = utdata[4];
		`TTOB5: tto_tx = utdata[5];
		`TTOB6: tto_tx = utdata[6];
		`TTOB7: tto_tx = utdata[7];
		`TTOSTOP: tto_tx = 1;
		default: tto_tx = 1;
		endcase
	end
endmodule

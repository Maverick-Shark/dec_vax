/*	$Id$	*/
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

	input [7:0]	iprdb,
	input		wrtxcs,
	input		wrtxdb,

//	output		intreq,

	output		rdy,
	output		ie,

	output		tto_tx
);
	parameter NCYC = 10;

	reg [15:0] clkcnt;
	reg [8:0] txdb;

	reg [NCYC-1:0] shiftreg;
	reg shce, inten, cntbit, xmit_rdy;

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

	assign tto_tx = txdb[0];

	// int enable/disab only bit that can be changed
	always @(posedge clk)
		if (wrtxcs)
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

endmodule

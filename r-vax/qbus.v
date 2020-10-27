/*	$Id$	*/
  
`timescale 1ns / 1ps
`default_nettype none

/*
 * Qbus adapter.
 *
 * Currently keeps:
 *	DL11 (for console).
 */

module qbus(
	input		clk,
	input		rst,

	input		CYC_I,
	input		STB_I,
/* verilator lint_off UNUSED */
	input [27:0]	ADR_I,
	input [31:0]	DAT_I,
	input		WE_I,
/* verilator lint_on UNUSED */
	output [31:0]	DAT_O,
	output		ACK_O,

	output		tto_tx
);

	wire request;
	assign request = CYC_I & STB_I;

	reg		qio_ack;
	reg [31:0]	qio_dato;
	assign DAT_O = request ? qio_dato : 32'b0;
	assign ACK_O = request ? qio_ack : 1'b0;

	/*
	 * DL11 transmitter.
	 */
	wire		tto_ready;
	reg		tto_start;
	reg [7:0]	txdb;

	dl11_tto dl11_tto(
		.clk(clk),
		.rst(rst),
	
		.xmit_rdy(tto_ready),	// idle
		.xmit_start(tto_start),	// start new char
		.txdb(txdb),

		.tto_tx(tto_tx)
	);

	/*
	 * Qbus I/O space.
	 */
	always @(posedge clk) begin
		tto_start <= 0;
		if (request == 0 || rst)
			qio_ack <= 0;
		if (~|ADR_I[27:13] & request) begin
			case (ADR_I[12:0])
			13'o17564: begin
//$fdisplay(32'h80000002, "txcs: adr %x \r\n", ADR_I);
				qio_dato <= { 24'b0, tto_ready, 7'b0 };
				qio_ack <= 1;
			end
			13'o17566: begin
//$fdisplay(32'h80000002, "txdb: adr %x \r\n", ADR_I);
				qio_dato <= { 24'b0, txdb };
				if (WE_I) begin
					txdb <= DAT_I[7:0];
					tto_start <= 1;
				end
				qio_ack <= 1;
			end
			default: qio_dato <= 32'h0;
			endcase
		end
	end


endmodule

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

	input		STB_I,
/* verilator lint_off UNUSED */
	input [27:0]	ADR_I,
	input [31:0]	DAT_I,
	input		WE_I,
/* verilator lint_on UNUSED */
	output [31:0]	DAT_O,
	output		ACK_O,

	input		tti_rx,
	output		tto_tx
);

	wire request;
	assign request = STB_I;

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
	 * DL11 receiver.
	 */
	wire 		tti_done;
	wire [7:0]	tti_data;
	reg		tti_clr;

	dl11_tti dl11_tti(
		.clk(clk),
		.rst(rst),

		.clear(tti_clr),
		.done(tti_done),
		.outdata(tti_data),

		.tti_rx(tti_rx)
	);


	/*
	 * Qbus I/O space.
	 */
	always @(posedge clk) begin
		tto_start <= 0;
		tti_clr <= 0;
		if (request == 0 || rst)
			qio_ack <= 0;
		if (~|ADR_I[27:13] & request) begin
			case (ADR_I[12:0])
			13'o17560: begin
//if (tti_done) $fdisplay(32'h80000002, "rxcs: ttidone %d\r\n", tti_done);
				qio_dato <= { 24'b0, tti_done, 7'b0 };
				qio_ack <= 1;
			end
			13'o17562: begin
//if (tti_done) $fdisplay(32'h80000002, "rxdb: %x\r\n", tti_data);
				qio_dato <= { 24'b0, tti_data };
				qio_ack <= 1;
				tti_clr <= 1;
			end
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

/*      $Id$        */

`timescale 1ns / 1ps
`default_nettype none

module mcode(
	input			clk,

	input [8:0]		ADR_I,
	input			STB_I,
	output [31:0]		DAT_O,
	output			ACK_O
);

parameter	ROM_WIDTH = 32;
parameter	ROM_ADDRS = 512;

	reg [ROM_WIDTH-1:0] mcode_rom [ROM_ADDRS-1:0];
	reg [ROM_WIDTH-1:0] mcode_data;
	reg		ack;

	initial $readmemh("mcode.hex", mcode_rom, 0, ROM_ADDRS-1);


	always @(posedge clk) begin
		ack <= 0;
		if (STB_I) begin
			mcode_data <= mcode_rom[ADR_I];
			ack <= 1;
		end
	end

	assign DAT_O = STB_I ? mcode_data : 32'b0;
	assign ACK_O = STB_I ? ack : 1'b0;

endmodule

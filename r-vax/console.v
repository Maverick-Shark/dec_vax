/*	$Id$	*/
/*
 *
 */

module console (
	input		clk,

	input		halted_i,

	input		dinrdy_i,
	output		dinack_o,
	input [7:0]	din_i,

	input 		dutbusy_i,
	input 		dutdone_i,
	output		dutst_o,
	output		dutclr_o,
	output [7:0]	dut_o
);

	assign dut_o = din_i;
	reg ack, start, clear;

	assign dinack_o = ack;
	assign dutst_o = start;
	assign dutclr_o = clear;

	always @(posedge clk) begin
		if (dinrdy_i) begin
			ack <= 1;
			start <= 1;
		end else if (dutdone_i) begin
			clear <= 1;
		end else begin
			ack <= 0;
			start <= 0;
			clear <= 0;
		end
	end
endmodule

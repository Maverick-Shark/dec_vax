/*	$Id$	*/
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

module dl11_tto #(
`ifdef VERILATOR
	parameter CLKPERBIT = 20	// no need to wait long in simulation
`else
	parameter CLKPERBIT = 5208	// (50000000/9600)
`endif
) (
	input		clk,
	input		rst,

	input		xmit_start,
	output 		xmit_rdy,
	input [7:0]	txdb,

	output reg	tto_tx
);

	reg [15:0] clkcnt;
	reg [3:0] state;

	assign xmit_rdy = (state == `TTOIDLE);

`ifdef notdef
always @(posedge clk) begin
	if (state != `TTOIDLE)
		$fdisplay(32'h80000002, "tto STATE: %d tto_tx %x\r\n", state, tto_tx);
end
`endif

	always @(posedge clk) begin
		if (rst) begin
			state <= `TTOINIT;
			clkcnt <= 0;
		end else if (state == `TTOINIT) begin
			/* wait some time with tx high to settle */
			if (clkcnt == (CLKPERBIT*8))
				state <= `TTOIDLE;
			else
				clkcnt <= clkcnt + 1;
		end else if (state == `TTOIDLE) begin
			if (xmit_start) begin
				clkcnt <= 0;
				state <= `TTOSTART;
			end
		end else begin
			if (clkcnt == CLKPERBIT-1) begin
				if (state > `TTOSTOP) begin
					state <= `TTOIDLE;
//$fdisplay(32'h80000002, "Written: %x\r\n", txdb);
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
		`TTOB0: tto_tx = txdb[0];
		`TTOB1: tto_tx = txdb[1];
		`TTOB2: tto_tx = txdb[2];
		`TTOB3: tto_tx = txdb[3];
		`TTOB4: tto_tx = txdb[4];
		`TTOB5: tto_tx = txdb[5];
		`TTOB6: tto_tx = txdb[6];
		`TTOB7: tto_tx = txdb[7];
		`TTOSTOP: tto_tx = 1;
		default: tto_tx = 1;
		endcase
	end
endmodule

/*	$Id$	*/
/*
 *
 */

`define	TTOIDLE		0
`define	TTOSTART	1
`define	TTOB0		2
`define	TTOB1		3
`define	TTOB2		4
`define	TTOB3		5
`define	TTOB4		6
`define	TTOB5		7
`define	TTOB6		8
`define	TTOB7		9
`define	TTOSTOP		10

module tto #(
	parameter CLKPERBIT = 5208	// (50000000/9600)
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
			state <= `TTOIDLE;
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
		`TTOIDLE: tto_tx <= 1;
		`TTOSTART: tto_tx <= 0;
		`TTOB0: tto_tx <= utdata[0];
		`TTOB1: tto_tx <= utdata[1];
		`TTOB2: tto_tx <= utdata[2];
		`TTOB3: tto_tx <= utdata[3];
		`TTOB4: tto_tx <= utdata[4];
		`TTOB5: tto_tx <= utdata[5];
		`TTOB6: tto_tx <= utdata[6];
		`TTOB7: tto_tx <= utdata[7];
		`TTOSTOP: tto_tx <= 1;
		default: tto_tx <= 1;
		endcase
	end
endmodule

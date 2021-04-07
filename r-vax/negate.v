/*      $Id$       */
`timescale 1ns / 1ps
`default_nettype none


module negate(
	input [4:0]	val,
	output [4:0]	neg
);

	(* rom_style = "DISTRIBUTED" *)
	reg [4:0]	dneg;

	always @* begin
		case (val)
		5'd31: dneg = 5'd1;
		5'd30: dneg = 5'd2;

		5'd29: dneg = 5'd3;
		5'd28: dneg = 5'd4;
		5'd27: dneg = 5'd5;
		5'd26: dneg = 5'd6;
		5'd25: dneg = 5'd7;
		5'd24: dneg = 5'd8;
		5'd23: dneg = 5'd9;
		5'd22: dneg = 5'd10;
		5'd21: dneg = 5'd11;
		5'd20: dneg = 5'd12;

		5'd19: dneg = 5'd13;
		5'd18: dneg = 5'd14;
		5'd17: dneg = 5'd15;
		5'd16: dneg = 5'd16;
		5'd15: dneg = 5'd17;
		5'd14: dneg = 5'd18;
		5'd13: dneg = 5'd19;
		5'd12: dneg = 5'd20;
		5'd11: dneg = 5'd21;
		5'd10: dneg = 5'd22;

		5'd09: dneg = 5'd23;
		5'd08: dneg = 5'd24;
		5'd07: dneg = 5'd25;
		5'd06: dneg = 5'd26;
		5'd05: dneg = 5'd27;
		5'd04: dneg = 5'd28;
		5'd03: dneg = 5'd29;
		5'd02: dneg = 5'd30;
		5'd01: dneg = 5'd31;
		5'd00: dneg = 5'd0;
		endcase
	end

	assign neg = dneg;

endmodule

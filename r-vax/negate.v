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
`default_nettype none
/*
 * 2-complement conversion of a negative number to positive (for shifting)
 * ISE creates a combinatorial LUT net (using many LUTs), hence we do the 
 * LUT ROM definition manually (using fewer LUTs).
 */


module negate(
	input [4:0]	val,
	output [4:0]	neg
);

`ifdef VERILATOR
	reg [4:0]	dneg;

	always @* begin
		case (val)
		5'd31: dneg = 5'b00001;
		5'd30: dneg = 5'b00010;

		5'd29: dneg = 5'b00011;
		5'd28: dneg = 5'b00100;
		5'd27: dneg = 5'b00101;
		5'd26: dneg = 5'b00110;
		5'd25: dneg = 5'b00111;
		5'd24: dneg = 5'b01000;
		5'd23: dneg = 5'b01001;
		5'd22: dneg = 5'b01010;
		5'd21: dneg = 5'b01011;
		5'd20: dneg = 5'b01100;

		5'd19: dneg = 5'b01101;
		5'd18: dneg = 5'b01110;
		5'd17: dneg = 5'b01111;
		5'd16: dneg = 5'b10000;
		5'd15: dneg = 5'b10001;
		5'd14: dneg = 5'b10010;
		5'd13: dneg = 5'b10011;
		5'd12: dneg = 5'b10100;
		5'd11: dneg = 5'b10101;
		5'd10: dneg = 5'b10110;

		5'd09: dneg = 5'b10111;
		5'd08: dneg = 5'b11000;
		5'd07: dneg = 5'b11001;
		5'd06: dneg = 5'b11010;
		5'd05: dneg = 5'b11011;
		5'd04: dneg = 5'b11100;
		5'd03: dneg = 5'b11101;
		5'd02: dneg = 5'b11110;
		5'd01: dneg = 5'b11111;
		5'd00: dneg = 5'b00000;
		endcase
	end

	assign neg = dneg;
`else
	wire		b4, b3, b2, b1, b0;


	ROM32X1 #( .INIT(32'h0001FFFE))
	    R4 ( .O(b4), .A0(val[0]), .A1(val[1]), .A2(val[2]), .A3(val[3]), .A4(val[4]));
	ROM32X1 #( .INIT(32'h01FE01FE))
	    R3 ( .O(b3), .A0(val[0]), .A1(val[1]), .A2(val[2]), .A3(val[3]), .A4(val[4]));
	ROM32X1 #( .INIT(32'h1E1E1E1E))
	    R2 ( .O(b2), .A0(val[0]), .A1(val[1]), .A2(val[2]), .A3(val[3]), .A4(val[4]));
	ROM32X1 #( .INIT(32'h66666666))
	    R1 ( .O(b1), .A0(val[0]), .A1(val[1]), .A2(val[2]), .A3(val[3]), .A4(val[4]));
	ROM32X1 #( .INIT(32'hAAAAAAAA))
	    R0 ( .O(b0), .A0(val[0]), .A1(val[1]), .A2(val[2]), .A3(val[3]), .A4(val[4]));

	assign neg = { b4, b3, b2, b1, b0 };

`endif
endmodule

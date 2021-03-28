/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none


module argdecode(
	input [7:0]	curarg,

	output [3:0]	arg_sh,

	output		arg_adec,
	output		arg_ainc,
	output		arg_aincd,
	output		arg_indir,

	output		arg_lit,
	output		arg_reg
);

	(* rom_style = "DISTRIBUTED" *)
	reg [9:0]	arg_rom;

	always @* begin
		case (curarg[7:4])
		4'b0000: arg_rom = 10'b01_0000_0000;
		4'b0001: arg_rom = 10'b01_0000_0000;
		4'b0010: arg_rom = 10'b01_0000_0000;
		4'b0011: arg_rom = 10'b01_0000_0000;

		4'b0100: arg_rom = 10'b00_0000_0000;
		4'b0101: arg_rom = 10'b10_0000_0000;
		4'b0110: arg_rom = 10'b00_0000_0000;
		4'b0111: arg_rom = 10'b00_0000_0001;

		4'b1000: arg_rom = 10'b00_0000_0010;
		4'b1001: arg_rom = 10'b00_0000_1100;
		4'b1010: arg_rom = 10'b00_0001_0000;
		4'b1011: arg_rom = 10'b00_0001_1000;

		4'b1100: arg_rom = 10'b00_0011_0000;
		4'b1101: arg_rom = 10'b00_0011_1000;
		4'b1110: arg_rom = 10'b00_1111_0000;
		4'b1111: arg_rom = 10'b00_1111_1000;
		endcase
	end


	assign	arg_adec = arg_rom[0];
	assign	arg_ainc = arg_rom[1];
	assign	arg_aincd = arg_rom[2];
	assign	arg_indir = arg_rom[3];

	assign	arg_sh = arg_rom[7:4];

	assign	arg_lit = arg_rom[8];
	assign	arg_reg = arg_rom[9];

endmodule



`ifdef notdef

/*
 * Decode an argument word.
 * This module is carefully designed to not have more that two levels
 * of LUTs.
 */

module argdecode(
	input [7:0] 	arg,		// argument byte

	// from instruction decode
	input		arg_is_byte,
	input		arg_is_word,
	input		arg_is_long,

	// indexed arg
	output		indexed_arg,

	// add to pc after arg
	output		pc_add_byte,
	output		pc_add_word,
	output		pc_add_long
);

	wire [3:0]	typ;
	wire		is_pc;


	assign typ = arg[7:4];
	assign is_pc = &arg[3:0];	// match PC.  1 LUT.


	/*
	 * Add size to pc.
	 *  Each of these uses 2 LUT, with the exception of type 9 with pc
	 *  as reg also must add to pc (which differs from other sizes).
	 *  This use one more LUT.
	 * In total 7 LUTs used.
	 */
	wire long_match_1, long_match_2;
	assign long_match_1 =
	    (typ[2:0] == 3'b000 && arg_is_long) || (typ[2:0] == 3'b001);
	assign long_match_2 = (typ[2:1] == 2'b11);
	assign pc_add_long =
	    ((is_pc && long_match_1) || long_match_2) && typ[3];

	wire word_match_1, word_match_2;
	assign word_match_1 = (typ[2:0] == 3'b000 && arg_is_word);
	assign word_match_2 = (typ[2:1] == 2'b10);
	assign pc_add_word =
	    ((is_pc && word_match_1) || word_match_2) && typ[3];

	wire byte_match_1, byte_match_2;
	assign byte_match_1 = (typ[2:0] == 3'b000 && arg_is_byte);
	assign byte_match_2 = (typ[2:1] == 2'b01);
	assign pc_add_byte =
	    ((is_pc && byte_match_1) || byte_match_2) && typ[3];

	/*
	 * check if arg is indexed.
	 */
	assign indexed_arg = (typ == 4'h4);

endmodule
`endif

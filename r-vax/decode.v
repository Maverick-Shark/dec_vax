/*	$Id$	*/
`timescale 1ns / 1ps

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX instruction decoder.
 *
 * The table kept here tells which argument(s) and in which order they
 * should be evaluated.  Also the number of args for an instruction is here.
 *
 * An instruction may have 0-6 arguments.  Each argument may be of type
 * Read, Write, Modify, Address and Branch.  This is encoded in three bits;
 *	read:	100
 *	write	010
 *	modify:	110
 *	addr:	001
 *	branch:	011
 *
 *	The size of the arg is in two bits;
 *	byte	00
 *	word	01
 *	long	10
 *	quad	11
 */



module decode(
	input [7:0]	insn,
	input [2:0]	current_arg,

	output [2:0]	num_args,
	output		arg_R,
	output		arg_W,
	output		arg_A,
	output [1:0]	arg_size
);

	(* rom_style = "BLOCK" *)
	reg [29:0] argtbl;
	(* rom_style = "BLOCK" *)
	reg [2:0] numarg;

	/*
	 * Argument size table.
	 */
	always @* begin
		case (insn)
		default: numarg = 3'd0;
		`I_BRB: numarg = 3'd1;		// 11
		`I_BNEQ: numarg = 3'd1;		// 12
		`I_BEQL: numarg = 3'd1;		// 13
		`I_BGTR: numarg = 3'd1;		// 14
		`I_BLEQ: numarg = 3'd1;		// 15

		`I_BGEQ: numarg = 3'd1;		// 18
		`I_BLSS: numarg = 3'd1;		// 19
		`I_BGTRU: numarg = 3'd1;	// 1a
		`I_BLEQU: numarg = 3'd1;	// 1b
		`I_BVC:	 numarg = 3'd1;		// 1c
		`I_BVS:	 numarg = 3'd1;		// 1d
		`I_BCC:	 numarg = 3'd1;		// 1e
		`I_BCS:	 numarg = 3'd1;		// 1f

		`I_BRW:	 numarg = 3'd1;		// 31

		`I_CLRB: numarg = 3'd1;		// 94

		`I_CLRW: numarg = 3'd1;		// b4

		`I_BISPSW: 	numarg = 3'd1;	// b8
		`I_BICPSW: 	numarg = 3'd1;	// b9

		`I_ADDL2: numarg = 3'd2;	// c0
		`I_ADDL3: numarg = 3'd3;	// c1

		`I_MOVL: numarg = 3'd2;		// d0

		`I_CLRL: numarg = 3'd1;		// d4

		`I_ADWC: numarg = 2'd1;		// d8
		endcase
	end

	/*
	 * Argument state table.
	 */
	always @* begin
		case (insn)
		default: argtbl = 30'b0;
		`I_BRB: argtbl = { 25'b0, `O_BYTE, `O_B };	// 11
		`I_BNEQ: argtbl = { 25'b0, `O_BYTE, `O_B };	// 12
		`I_BEQL: argtbl = { 25'b0, `O_BYTE, `O_B };	// 13
		`I_BGTR: argtbl = { 25'b0, `O_BYTE, `O_B };	// 14
		`I_BLEQ: argtbl = { 25'b0, `O_BYTE, `O_B };	// 15

		`I_BGEQ: argtbl = { 25'b0, `O_BYTE, `O_B };	// 18
		`I_BLSS: argtbl = { 25'b0, `O_BYTE, `O_B };	// 19
		`I_BGTRU: argtbl = { 25'b0, `O_BYTE, `O_B };	// 1a
		`I_BLEQU: argtbl = { 25'b0, `O_BYTE, `O_B };	// 1b
		`I_BVC:	 argtbl = { 25'b0, `O_BYTE, `O_B };	// 1c
		`I_BVS:	 argtbl = { 25'b0, `O_BYTE, `O_B };	// 1d
		`I_BCC:	 argtbl = { 25'b0, `O_BYTE, `O_B };	// 1e
		`I_BCS:	 argtbl = { 25'b0, `O_BYTE, `O_B };	// 1f

		`I_BRW:	 argtbl = { 25'b0, `O_WORD, `O_B };	// 31

		`I_CLRB: argtbl = { 25'b0, `O_BYTE, `O_W };		// 94

		`I_CLRW: argtbl = { 25'b0, `O_WORD, `O_W };		// b4

		`I_BISPSW: 	argtbl = { 25'b0, `O_WORD, `O_R };	// b8
		`I_BICPSW: 	argtbl = { 25'b0, `O_WORD, `O_R };	// b9

		`I_ADDL2: argtbl =
			{ 20'b0, `O_LONG, `O_M, `O_LONG, `O_R };	// c0
		`I_ADDL3: argtbl = { 15'b0,  `O_LONG, `O_W,
				`O_LONG, `O_R, `O_LONG, `O_R };		// c1

		`I_MOVL: argtbl =
			{ 20'b0, `O_LONG, `O_W, `O_LONG, `O_R };	// d0

		`I_CLRL: argtbl = { 25'b0, `O_LONG, `O_W };		// d4

		`I_ADWC: argtbl =
			{ 20'b0, `O_LONG, `O_M, `O_LONG, `O_R };	// d8
		endcase
	end

	/* get correct parameters based on current arg */
	reg [4:0] retarg;
	always @* begin
		case (current_arg)
		default: retarg = argtbl[4:0];
		3'd1:	retarg = argtbl[9:5];
		3'd2:	retarg = argtbl[14:10];
		3'd3:	retarg = argtbl[19:15];
		3'd4:	retarg = argtbl[24:20];
		3'd5:	retarg = argtbl[29:25];
		endcase
	end

	assign { arg_size, arg_R, arg_W, arg_A } = retarg[4:0];
	assign num_args = numarg;

endmodule



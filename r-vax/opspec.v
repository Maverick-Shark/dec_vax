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

`include "opcodes.vh"

/*
 * VAX operand types and sizes
 *
 * The upper 5 bits keep the operand size in bytes, the lower 5 bits has
 * the access type.
 */
`define	OP_RL_ML	8'd1
`define	OP_RL_RL_WL	8'd3
`define	OP_RL_WL	8'd4
`define	OP_BB		8'd6
`define	OP_BW		8'd7
`define	OP_RW		8'd8

module opspec(
	input [7:0] insn,
	input [7:0] nstate,
	output [7:0] opoff,
	output [1:0] sizel2,
	output o_r, o_w, o_m, o_a, o_v
);
	(* rom_style = "BLOCK" *)
	reg [7:0] optbl;
	(* rom_style = "BLOCK" *)
	reg [6:0] argtbl; /* 2 size + 5 op */

	always @* begin
		case (nstate)
		default:	argtbl = 0;
		`OP_RL_ML:	argtbl = { `O_LONG, `O_R };
		8'd2:		argtbl = { `O_LONG, `O_M };
		`OP_RL_RL_WL:	argtbl = { `O_LONG, `O_R };
		`OP_RL_WL:	argtbl = { `O_LONG, `O_R };
		8'd5:		argtbl = { `O_LONG, `O_W };
		`OP_BB:		argtbl = { `O_BYTE, `O_R };	// branch arg
		`OP_BW:		argtbl = { `O_WORD, `O_R };	// branch arg
		`OP_RW:		argtbl = { `O_WORD, `O_R };
		endcase
	end

	always @* begin
		case (insn)
		default:	optbl = 0;
		`I_BRB:		optbl = `OP_BB;		// 11

		`I_BNEQ:	optbl = `OP_BB;		// 12
		`I_BEQL:	optbl = `OP_BB;		// 13
		`I_BGTR:	optbl = `OP_BB;		// 14
		`I_BLEQ:	optbl = `OP_BB;		// 15

		`I_BGEQ:	optbl = `OP_BB;		// 18
		`I_BLSS:	optbl = `OP_BB;		// 19
		`I_BGTRU:	optbl = `OP_BB;		// 1a
		`I_BLEQU:	optbl = `OP_BB;		// 1b
		`I_BVC:		optbl = `OP_BB;		// 1c
		`I_BVS:		optbl = `OP_BB;		// 1d
		`I_BCC:		optbl = `OP_BB;		// 1e
		`I_BCS:		optbl = `OP_BB;		// 1f

		`I_BRW:		optbl = `OP_BW;		// 31

		`I_BISPSW:	optbl = `OP_RW;
		`I_BICPSW:	optbl = `OP_RW;

		`I_ADDL2:	optbl = `OP_RL_ML;
		`I_ADDL3:	optbl = `OP_RL_RL_WL;

		`I_MOVL:	optbl = `OP_RL_WL;
		endcase
	end

	assign sizel2 = argtbl[6:5];
	assign { o_r, o_w, o_m, o_a, o_v } = argtbl[4:0];

	assign opoff = optbl;

endmodule



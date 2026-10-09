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

`define	IHASARGS	8
`define	IEMUL		9
`define	SETADDV		10
`define	USE8		11
`define	WBACK		12
`define	USE16		13

/* 16/19 nmatches psw bits */
`define	CCC		16
`define	CCV		17
`define	CCZ		18
`define	CCN		19

`define	MOVE2		20
`define	WBACK2		21
`define	SETCMPNZ	25
`define	SETNZ		26
`define	CLV		27
`define	CLC		28
`define	SETC		35
`define	SETV		36
/* 47-55 is step offset */

`define	DOHALT		63

module ucode(
	input			clk,

	/* instruction ROM */
	input			i_enable,
	input [7:0]		i_opcode,

	output [7:0]		i_argoff,
	output			i_hasargs,
	output			i_emul,

	output			i_dohalt,

	output			i_wback,
	output			i_use8,
	output			i_use16,

	output			i_setcmpnz,
	output			i_setnz,
	output			i_clv,
	output			i_clc,
	output			i_setc,
	output			i_setv,

	output			i_move2,
	output			i_wback2,

	output [9:0]		i_stepoff,

	/* Microcode step ROM */
	input			s_enable,
	input [9:0]		s_stepoff,

	output [3:0]		s_left,
	output [3:0]		s_right,
	output [3:0]		s_op,

	output			s_eoi,
	output			s_zcond,
	output			s_nzcond,
	output			s_wback,
	output			s_savc,
	output			s_ncond,
	output			s_nncond,
	output			s_wback2,
	output			s_goto,
	output			s_savnz,
	output			s_rmem,
	output			s_wipr,
	output			s_wmem,
	output			s_wreg,
	output [3:0]		s_dest,
	output			s_savv,
	output			s_use8,
	output			s_use16,
	output			s_resopflt,
	output			s_phys,
	output [1:0]		s_size,

	output [15:0]		s_const,
	output [15:0]		s_addr,

	/* Argument ROM */
	input			a_enable,
	input [7:0]		a_argoff,

	output [2:0]		a_argcode,
	output [1:0]		a_argsz,
	output [2:0]		a_rargno,
	output 			a_wargno,

	output			a_emul,
	output			a_last,
	output [7:0]		a_arg
);

parameter	I_ROM_WIDTH = 64;
parameter	I_ROM_ADDRS = 256;
parameter	A_ROM_WIDTH = 64;
parameter	A_ROM_ADDRS = 256;
parameter	S_ROM_WIDTH = 72;
parameter	S_ROM_ADDRS = 1024;

	(* ramstyle = "M10K" *)
	reg [I_ROM_WIDTH-1:0] ucinsn_rom [I_ROM_ADDRS-1:0];
	reg [I_ROM_WIDTH-1:0] ucinsn_data;
`ifdef MISTER
	initial $readmemh("rtl/uc-insn.hex", ucinsn_rom, 0, I_ROM_ADDRS-1);
`else
	initial $readmemh("uc-insn.hex", ucinsn_rom, 0, I_ROM_ADDRS-1);
`endif

	(* ramstyle = "M10K" *)
	reg [A_ROM_WIDTH-1:0] ucargs_rom [A_ROM_ADDRS-1:0];
	reg [A_ROM_WIDTH-1:0] ucargs_data;
`ifdef MISTER
	initial $readmemh("rtl/uc-args.hex", ucargs_rom, 0, A_ROM_ADDRS-1);
`else
	initial $readmemh("uc-args.hex", ucargs_rom, 0, A_ROM_ADDRS-1);
`endif

	(* ramstyle = "M10K" *)
	reg [S_ROM_WIDTH-1:0] ucstep_rom [S_ROM_ADDRS-1:0];
	reg [S_ROM_WIDTH-1:0] ucstep_data;
`ifdef MISTER
	initial $readmemh("rtl/uc-step.hex", ucstep_rom, 0, S_ROM_ADDRS-1);
`else
	initial $readmemh("uc-step.hex", ucstep_rom, 0, S_ROM_ADDRS-1);
`endif

	always @(posedge clk)
		if (i_enable)
			ucinsn_data <= ucinsn_rom[i_opcode];

	always @(posedge clk)
		if (a_enable)
			ucargs_data <= ucargs_rom[a_argoff];

	always @(posedge clk)
		if (s_enable)
			ucstep_data <= ucstep_rom[s_stepoff];

	assign s_op = ucstep_data[3:0];
	assign s_right = ucstep_data[7:4];
	assign s_left = ucstep_data[11:8];
	assign s_wipr = ucstep_data[12];	// 12-14 wipr,wmem,wreg,rmem
	assign s_wmem = ucstep_data[13];	// 15-17 cond+enab
	assign s_wreg = ucstep_data[14];
	assign s_eoi = ucstep_data[15];
	assign s_zcond = ucstep_data[16];
	assign s_nzcond = ucstep_data[17];
	assign s_wback = ucstep_data[18];
	assign s_savc = ucstep_data[19];
	assign s_ncond = ucstep_data[20];
	assign s_nncond = ucstep_data[21];
	assign s_wback2 = ucstep_data[22];
	assign s_goto = ucstep_data[23];
	assign s_savnz = ucstep_data[24];
	assign s_rmem = ucstep_data[25];
	assign s_dest = ucstep_data[29:26];
	assign s_savv = ucstep_data[30];
	assign s_use8 = ucstep_data[31];
	assign s_resopflt = ucstep_data[32];
	assign s_use16 = ucstep_data[33];
	assign s_phys = ucstep_data[34];
	assign s_size = ucstep_data[36:35];
	assign s_addr = ucstep_data[55:40];
	assign s_const = ucstep_data[71:56];

	assign i_argoff = ucinsn_data[7:0];
	assign i_hasargs = ucinsn_data[`IHASARGS];
	assign i_emul = ucinsn_data[`IEMUL];
	assign i_dohalt = ucinsn_data[`DOHALT];
	assign i_wback = ucinsn_data[`WBACK];
	assign i_use8 = ucinsn_data[`USE8];
	assign i_use16 = ucinsn_data[`USE16];

	assign i_setcmpnz = ucinsn_data[`SETCMPNZ];
	assign i_setnz = ucinsn_data[`SETNZ];
	assign i_clv = ucinsn_data[`CLV];
	assign i_clc = ucinsn_data[`CLC];
	assign i_setc = ucinsn_data[`SETC];
	assign i_setv = ucinsn_data[`SETV];

	assign i_move2 = ucinsn_data[`MOVE2];
	assign i_wback2 = ucinsn_data[`WBACK2];

	assign i_stepoff = ucinsn_data[56:47];

	assign a_argcode = ucargs_data[2:0];
	assign a_argsz = ucargs_data[4:3];
	assign a_emul = ucargs_data[5];
	assign a_last = ucargs_data[6];
	assign a_arg = ucargs_data[15:8];
	assign a_rargno = ucargs_data[18:16];
	assign a_wargno = ucargs_data[19];

endmodule

/*      $Id$        */

`timescale 1ns / 1ps
`default_nettype none

`define	IHASARGS	8
`define	IEMUL		9
`define	SETADDV		10
`define	USEADD		11
`define	WBACK		12
`define	ISSPSW		13
`define	ISCPSW		14

/* 16/19 nmatches psw bits */
`define	CCC		16
`define	CCV		17
`define	CCZ		18
`define	CCN		19

`define	MOVE2		20
`define	WBACK2		21
`define	MOVPSL		24
`define	SETNZ		26
`define	CLV		27
`define	CLC		28
`define	USEMTPR		29
`define	USEMFPR		30
`define	USESUB		31
`define	USEAND		32
`define	USEBIS		33
`define	USEBIC		34
`define	SETC		35
`define	BBS		36
`define	BBC		37
`define	USEROT		38
`define	USEZEX		39
`define	SETBIT		40
`define	CLRBIT		41
`define	INSV		42
`define	QUAD		43
`define	USEACB		44
`define	POPR		45
`define	PUSHR		46
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

	output			i_useadd,
	output			i_usexor,
	output			i_usemtpr,
	output			i_usemfpr,
	output			i_usesub,
	output			i_useand,
	output			i_usebis,
	output			i_usebic,
	output			i_userot,
	output			i_usezex,
	output			i_insv,
	output			i_useacb,
	output			i_wback,

	output [3:0]		i_pswbits,
	output			i_isspsw,
	output			i_iscpsw,
	output			i_setnz,
	output			i_clv,
	output			i_clc,
	output			i_setc,
	output			i_bbs,
	output			i_bbc,
	output			i_setbit,
	output			i_clrbit,
	output			i_quad,

	output			i_move2,
	output			i_wback2,
	output			i_movpsl,
	output			i_popr,
	output			i_pushr,

	output [7:0]		i_stepoff,

	/* Microcode step ROM */
	input			s_enable,
	input [7:0]		s_stepoff,

	output [3:0]		s_left,
	output [3:0]		s_right,
	output [3:0]		s_op,

	output			s_argd0,
	output			s_argd1,
	output			s_psl,
	output			s_eoi,
	output			s_zcond,
	output			s_nzcond,
	output			s_wback,

	output [31:0]		s_const,

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
parameter	S_ROM_WIDTH = 64;
parameter	S_ROM_ADDRS = 256;

	reg [I_ROM_WIDTH-1:0] ucinsn_rom [I_ROM_ADDRS-1:0];
	reg [I_ROM_WIDTH-1:0] ucinsn_data;
	initial $readmemh("uc-insn.hex", ucinsn_rom, 0, I_ROM_ADDRS-1);

	reg [A_ROM_WIDTH-1:0] ucargs_rom [A_ROM_ADDRS-1:0];
	reg [A_ROM_WIDTH-1:0] ucargs_data;
	initial $readmemh("uc-args.hex", ucargs_rom, 0, A_ROM_ADDRS-1);

	reg [S_ROM_WIDTH-1:0] ucstep_rom [S_ROM_ADDRS-1:0];
	reg [S_ROM_WIDTH-1:0] ucstep_data;
	initial $readmemh("uc-step.hex", ucstep_rom, 0, S_ROM_ADDRS-1);

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
	assign s_argd0 = ucstep_data[12];
	assign s_argd1 = ucstep_data[13];
	assign s_psl = ucstep_data[14];
	assign s_eoi = ucstep_data[15];
	assign s_zcond = ucstep_data[16];
	assign s_nzcond = ucstep_data[17];
	assign s_wback = ucstep_data[18];
	assign s_const = ucstep_data[63:32];

	assign i_argoff = ucinsn_data[7:0];
	assign i_hasargs = ucinsn_data[`IHASARGS];
	assign i_emul = ucinsn_data[`IEMUL];
	assign i_dohalt = ucinsn_data[`DOHALT];
	assign i_useadd = ucinsn_data[`USEADD];
	assign i_usesub = ucinsn_data[`USESUB];
	assign i_useand = ucinsn_data[`USEAND];
	assign i_usebic = ucinsn_data[`USEBIC];
	assign i_usebis = ucinsn_data[`USEBIS];
	assign i_userot = ucinsn_data[`USEROT];
	assign i_usezex = ucinsn_data[`USEZEX];
	assign i_insv = ucinsn_data[`INSV];
	assign i_useacb = ucinsn_data[`USEACB];
	assign i_wback = ucinsn_data[`WBACK];

	assign i_pswbits = ucinsn_data[19:16];
	assign i_isspsw = ucinsn_data[`ISSPSW];
	assign i_iscpsw = ucinsn_data[`ISCPSW];
	assign i_setnz = ucinsn_data[`SETNZ];
	assign i_clv = ucinsn_data[`CLV];
	assign i_clc = ucinsn_data[`CLC];
	assign i_setc = ucinsn_data[`SETC];
	assign i_bbs = ucinsn_data[`BBS];
	assign i_bbc = ucinsn_data[`BBC];
	assign i_setbit = ucinsn_data[`SETBIT];
	assign i_clrbit = ucinsn_data[`CLRBIT];
	assign i_quad = ucinsn_data[`QUAD];
	assign i_popr = ucinsn_data[`POPR];
	assign i_pushr = ucinsn_data[`PUSHR];

	assign i_move2 = ucinsn_data[`MOVE2];
	assign i_wback2 = ucinsn_data[`WBACK2];
	assign i_movpsl = ucinsn_data[`MOVPSL];
	assign i_usemtpr = ucinsn_data[`USEMTPR];
	assign i_usemfpr = ucinsn_data[`USEMFPR];

	assign i_stepoff = ucinsn_data[54:47]; //ucinsn_data[55:47];

	assign a_argcode = ucargs_data[2:0];
	assign a_argsz = ucargs_data[4:3];
	assign a_emul = ucargs_data[5];
	assign a_last = ucargs_data[6];
	assign a_arg = ucargs_data[15:8];
	assign a_rargno = ucargs_data[18:16];
	assign a_wargno = ucargs_data[19];

endmodule

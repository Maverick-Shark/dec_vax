/*      $Id$        */

`timescale 1ns / 1ps
`default_nettype none

`define	IHASARGS	8
`define	IEMUL		9
`define	NEWFLOW		10
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
`define	BISPSW		22
`define	BICPSW		23
`define	MOVPSL		24
`define	USEXOR		25
`define	SETNZ		26
`define	CLV		27

`define	SETADDC		42
`define	SETADDV		43
`define	USEMTPR		51
`define	USEMFPR		52
`define	USEBIC		53
`define	USEBIS		55
`define	USEJMP		56
`define	CLC		58

`define	DOHALT		63

module ucode(
	input			clk,

	/* instruction ROM */
	input			i_enable,
	input [7:0]		i_opcode,

	output [7:0]		i_argoff,
	output			i_hasargs,
	output			i_emul,
	output			i_newflow,

	output			i_dohalt,

	output			i_useadd,
	output			i_usexor,
	output			i_wback,

	output [3:0]		i_pswbits,
	output			i_isspsw,
	output			i_iscpsw,
	output			i_setnz,
	output			i_clv,

	output			i_move2,
	output			i_wback2,
	output			i_bispsw,
	output			i_bicpsw,
	output			i_movpsl,

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

	reg [I_ROM_WIDTH-1:0] ucinsn_rom [I_ROM_ADDRS-1:0];
	reg [I_ROM_WIDTH-1:0] ucinsn_data;
	initial $readmemh("uc-insn.hex", ucinsn_rom, 0, I_ROM_ADDRS-1);

	reg [A_ROM_WIDTH-1:0] ucargs_rom [A_ROM_ADDRS-1:0];
	reg [A_ROM_WIDTH-1:0] ucargs_data;
	initial $readmemh("uc-args.hex", ucargs_rom, 0, A_ROM_ADDRS-1);

	always @(posedge clk)
		if (i_enable)
			ucinsn_data <= ucinsn_rom[i_opcode];

	always @(posedge clk)
		if (a_enable)
			ucargs_data <= ucargs_rom[a_argoff];

	assign i_argoff = ucinsn_data[7:0];
	assign i_hasargs = ucinsn_data[`IHASARGS];
	assign i_emul = ucinsn_data[`IEMUL];
	assign i_newflow = ucinsn_data[`NEWFLOW];
	assign i_dohalt = ucinsn_data[`DOHALT];
	assign i_useadd = ucinsn_data[`USEADD];
	assign i_wback = ucinsn_data[`WBACK];
	assign i_pswbits = ucinsn_data[19:16];
	assign i_isspsw = ucinsn_data[`ISSPSW];
	assign i_iscpsw = ucinsn_data[`ISCPSW];
	assign i_setnz = ucinsn_data[`SETNZ];
	assign i_clv = ucinsn_data[`CLV];

	assign i_move2 = ucinsn_data[`MOVE2];
	assign i_wback2 = ucinsn_data[`WBACK2];
	assign i_bispsw = ucinsn_data[`BISPSW];
	assign i_bicpsw = ucinsn_data[`BICPSW];
	assign i_movpsl = ucinsn_data[`MOVPSL];
	assign i_usexor = ucinsn_data[`USEXOR];

	assign a_argcode = ucargs_data[2:0];
	assign a_argsz = ucargs_data[4:3];
	assign a_emul = ucargs_data[5];
	assign a_last = ucargs_data[6];
	assign a_arg = ucargs_data[15:8];
	assign a_rargno = ucargs_data[18:16];
	assign a_wargno = ucargs_data[19];

`ifdef notdef
	always @(argno, ucode_data[32:30], ucode_data[35:33])
		case (argno)
		3'b000: hidden_arg = ucode_data[32:30];
		3'b001: hidden_arg = ucode_data[35:33];
		default: hidden_arg = 0;
		endcase

	assign usebr = ucode_data[`USEBR];
	assign usemtpr = ucode_data[`USEMTPR];
	assign usemfpr = ucode_data[`USEMFPR];
	assign usebic = ucode_data[`USEBIC];
	assign usexor = ucode_data[`USEXOR];
	assign usebis = ucode_data[`USEBIS];
	assign usejmp = ucode_data[`USEJMP];
	assign usemovpsl = ucode_data[`USEMOVPSL];

	assign dohalt = ucode_data[`DOHALT];

	assign setnz = ucode_data[`SETNZ];
	assign setaddc = ucode_data[`SETADDC];
	assign setaddv = ucode_data[`SETADDV];
	assign setbits = ucode_data[`SETBITS];
	assign clrbits = ucode_data[`CLRBITS];

	assign ccset = ucode_data[`FLAGSET];
	assign ccclr = ucode_data[`FLAGCLR];
	assign ccclv = ucode_data[`CLV];
`endif
endmodule

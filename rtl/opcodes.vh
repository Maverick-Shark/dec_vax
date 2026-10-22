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


/* bit number in PSL */
`define	PSL_C	0
`define	PSL_V	1
`define	PSL_Z	2
`define	PSL_N	3
`define	PSL_T	4	/* trace enable */
`define	PSL_IV	5	/* integer overflow trap enable */
`define	PSL_FU	6	/* floating underflow fault enable */

/* general regs */
`define	REG_PC		4'hf
`define	REG_SP		4'he

/* Operand specifiers */
`define	OPS_LIT		4'b00??			// 0-3
`define	OPS_INDEX	4'b0100			// 4
`define	OPS_REG		4'b0101			// 5
`define	OPS_REGD	4'b0110			// 6
`define	OPS_ADEC	4'b0111			// 7
`define	OPS_AINC	4'b1000			// 8
`define	OPS_AINCD	4'b1001			// 9
`define	OPS_DISP	4'b11??, 4'b101?	// 10-15
`define	OPS_BDISP	4'ha
`define	OPS_BDISPD	4'hb
`define	OPS_WDISP	4'hc
`define	OPS_WDISPD	4'hd
`define	OPS_LDISP	4'he
`define	OPS_LDISPD	4'hf

/* opcodes */
`define	I_HALT	8'h00
`define	I_NOP	8'h01
`define	I_REI	8'h02
`define	I_BPT	8'h03
`define	I_RET	8'h04
`define	I_RSB	8'h05
`define	I_LDPCTX	8'h06
`define	I_SVPCTX	8'h07

`define	I_BSBB	8'h10
`define	I_BRB	8'h11
`define	I_BNEQ	8'h12
`define	I_BEQL	8'h13
`define	I_BGTR	8'h14
`define	I_BLEQ	8'h15
`define	I_JSB	8'h16
`define	I_JMP	8'h17
`define	I_BGEQ	8'h18
`define	I_BLSS	8'h19
`define	I_BGTRU	8'h1a
`define	I_BLEQU	8'h1b
`define	I_BVC	8'h1c
`define	I_BVS	8'h1d
`define	I_BCC	8'h1e
`define	I_BCS	8'h1f

`define	I_BSBW	8'h30
`define	I_BRW	8'h31

`define I_MOVAW	8'h3e

`define I_CMPB	8'h91

`define I_BITB	8'h93

`define I_CLRB	8'h94
`define I_TSTB	8'h95

`define I_MOVAB	8'h9e

`define I_CMPW	8'hb1

`define I_BITW	8'hb3

`define I_CLRW	8'hb4
`define I_TSTW	8'hb5

`define	I_BISPSW	8'hb8
`define	I_BICPSW	8'hb9

`define	I_ADDL2	8'hc0
`define	I_ADDL3	8'hc1
`define	I_SUBL2	8'hc2
`define	I_SUBL3	8'hc3
`define	I_MULL2	8'hc4
`define	I_MULL3	8'hc5
`define	I_DIVL2	8'hc6
`define	I_DIVL3	8'hc7
`define	I_BISL2	8'hc8
`define	I_BISL3	8'hc9
`define	I_BICL2	8'hca
`define	I_BICL3	8'hcb
`define	I_XORL2	8'hcc
`define	I_XORL3	8'hcd

`define	I_MOVL	8'hd0
`define I_CMPL	8'hd1

`define I_BITL	8'hd3
`define I_CLRL	8'hd4
`define I_TSTL	8'hd5
`define I_INCL	8'hd6
`define I_DECL	8'hd7
`define I_ADWC	8'hd8

`define I_MTPR	8'hda
`define I_MFPR	8'hdb
`define I_MOVPSL	8'hdc

`define I_MOVAL	8'hde

/* operand data size */
`define	O_BYTE	2'd0
`define	O_WORD	2'd1
`define	O_LONG	2'd2
`define	O_QUAD	2'd3
// `define	O_OCTA	3'd0

/* operand access type */
`define	O_R	3'b100
`define	O_W	3'b010
`define	O_M	3'b110
`define	O_A	3'b001
`define	O_B	3'b011


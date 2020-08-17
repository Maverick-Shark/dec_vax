

/* bit number in PSL */
`define	PSL_C	5'd0
`define	PSL_V	5'd1
`define	PSL_Z	5'd2
`define	PSL_N	5'd3

/* pc */
`define	REG_PC		4'hf

/* Operand specifiers */
`define	OPS_LIT		4'b00??
`define	OPS_REG		4'b0101
`define	OPS_DISP	4'b11??, 4'b101?
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
`define	I_LDPCTX	8'h06
`define	I_SVPCTX	8'h07

`define	I_BRB	8'h11
`define	I_BNEQ	8'h12
`define	I_BEQL	8'h13
`define	I_BGTR	8'h14
`define	I_BLEQ	8'h15

`define	I_BGEQ	8'h18
`define	I_BLSS	8'h19
`define	I_BGTRU	8'h1a
`define	I_BLEQU	8'h1b
`define	I_BVC	8'h1c
`define	I_BVS	8'h1d
`define	I_BCC	8'h1e
`define	I_BCS	8'h1f

`define	I_BRW	8'h31

`define I_CLRB	8'h94

`define I_CLRW	8'hb4

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

`define	I_MOVL	8'hd0

`define I_CLRL	8'hd4

/* operand data type */
`define	O_BYTE	5'b00001
`define	O_WORD	5'b00010
`define	O_LONG	5'b00100
`define	O_QUAD	5'b01000
`define	O_OCTA	5'b10000

/* operand access type */
`define	O_R	5'b10000
`define	O_W	5'b01000
`define	O_M	5'b00100
`define	O_A	5'b00010
`define	O_V	5'b00001

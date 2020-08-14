

/* bit number in PSL */
`define	PSL_C	0
`define	PSL_V	1
`define	PSL_Z	2
`define	PSL_N	3


/* Operand specifiers */
`define	OPS_LIT	4'b00??
`define	OPS_REG	4'h5
//`define	OPS_REG	4'h5

/* opcodes */
`define	I_ADDL2	8'hc0
`define	I_ADDL3	8'hc1

`define	I_MOVL	8'hd0

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

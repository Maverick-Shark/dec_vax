/*	$Id$	*/

`define	STATBITS	8

`define	S_HALT		0
`define	S_FETCH		1
`define	S_WREG		2
`define	S_FILLUP	3
`define	S_ENDINST	4
`define	S_READMEM	5
`define	S_RDCDATA	6
`define	S_OAREAD	7
`define	S_READMEM2	8
`define	S_WRITEMEM	9
`define	S_WRITEMEM2	10
`define	S_EXECUTE	11
`define	S_BRARGS	12
`define	S_ARG		13
`define	S_ARGEND	14
`define	S_INDOA		15
`define	S_DECODE	16
`define	S_MTPR		17
`define	S_TXCS_R	18
`define	S_TXDB_W	19
`define	S_MFPR		20
//`define	S_MFPR2		21
`define	S_POSTINC	22
`define	S_POSTINC0	23
`define	S_GETVEC	24
`define	S_GETVEC1	25
`define	S_GETVEC2	26
`define	S_GETVEC3	27
`define	S_MCHECK	28
`define	S_MCHECK1	29
`define	S_MCHECK2	30
`define	S_SETSTK	31
`define	S_SETSTK1	32
`define	S_SETSTK2	33
`define	S_SETSTK3	34
`define	S_MCHECK3	35
`define	S_PUSH		36
`define	S_PUSH2		37


`define B_HALT		8'd0
`define B_ARG		8'd1
`define B_SOP		8'd2
`define B_BR		8'd3
`define B_AEND		8'd4


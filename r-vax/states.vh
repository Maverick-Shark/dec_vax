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



`define B_HALT		8'd0
`define B_ARG		8'd1
`define B_SOP		8'd2
`define B_BR		8'd3
`define B_AEND		8'd4


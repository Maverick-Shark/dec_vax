/*	$Id$	*/

`define	STATBITS	8

`define	S_HALT		0
`define	S_FETCH		1
`define	S_DECODE	2
`define	S_FILLUP	3
`define	S_ENDINST	4
`define	S_READMEM	5
`define	S_RDCDATA	6
`define	S_OAREAD	7
`define	S_READMEM2	8
`define	S_WRITEMEM	9
`define	S_WRITEMEM2	10
`define	S_ARGRDATA	11




`define	S_ARG		8'd20
`define	S_SOP		8'd22
`define	S_BR		8'd23

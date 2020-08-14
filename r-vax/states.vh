/*	$Id$	*/

`define	STATBITS	8
`define	STATLINE	(`STATBITS*6)

`define	S_HALT		0
`define	S_FETCH		1
`define	S_DECODE	2
`define	S_FILLUP	3
`define	S_ENDINST	4


`define	S_ARG		8'd10
`define	S_SOP		8'd12

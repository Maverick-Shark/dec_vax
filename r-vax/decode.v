/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX instruction decoder.
 *
 * There are two tables kept here.
 * 1) A mapping table that gives an offset into the state table for each instruction
 * 2) A state table that resturn the states that should be executed for an instruction.
 */

`define	SIMPOFF3	8'd1
`define	SIMPOFF2	8'd2
`define	SIMPOFF1	8'd3
`define	BROFF		8'd5

module decode(
	input [7:0] insn,
	input [7:0] nstate,
	output [7:0] stateoff,
	output [7:0] opoff
);

	(* rom_style = "BLOCK" *)
	reg [7:0] optbl;
	(* rom_style = "BLOCK" *)
	reg [7:0] statetbl;

	always @* begin
		case (nstate)
		default: 	statetbl = `S_HALT;
		8'd0:		statetbl = `S_HALT;
		`SIMPOFF3:	statetbl = `S_ARG;
		`SIMPOFF2:	statetbl = `S_ARG;
		`SIMPOFF1:	statetbl = `S_ARG;
		8'd4:		statetbl = `S_SOP;
		`BROFF:		statetbl = `S_BR;
		endcase
	end

	/*
	 * get index into state table based on instruction.
	 */
	always @* begin
		case (insn)
		default:	optbl = 0;
		`I_BRB:		optbl = `BROFF;		// 11
		`I_BNEQ:	optbl = `BROFF;		// 12
		`I_BEQL:	optbl = `BROFF;		// 13
		`I_BGTR:	optbl = `BROFF;		// 14
		`I_BLEQ:	optbl = `BROFF;		// 15

		`I_BGEQ:	optbl = `BROFF;		// 18
		`I_BLSS:	optbl = `BROFF;		// 19
		`I_BGTRU:	optbl = `BROFF;		// 1a
		`I_BLEQU:	optbl = `BROFF;		// 1b
		`I_BVC:		optbl = `BROFF;		// 1c
		`I_BVS:		optbl = `BROFF;		// 1d
		`I_BCC:		optbl = `BROFF;		// 1e
		`I_BCS:		optbl = `BROFF;		// 1f


		`I_BRW:		optbl = `BROFF;		// 31

		`I_BISPSW:	optbl = `SIMPOFF1;	// b8
		`I_BICPSW:	optbl = `SIMPOFF1;	// b9

		`I_ADDL2:	optbl = `SIMPOFF2;	// c0
		`I_ADDL3:	optbl = `SIMPOFF3;	// c1

		`I_MOVL:	optbl = `SIMPOFF2;	// d0
		endcase
	end

	assign stateoff = statetbl;
	assign opoff = optbl;

endmodule



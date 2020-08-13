/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX instruction decoder.
 *
 * An instruction can have up to 5 arguments, hence for each instruction we
 * store both the decoding state for each arg and the arg type.
 *
 * input to the decode module is the opcode and argument number.
 */

module decode(
	input [7:0] insn,
//	input [2:0] argn,
	output [`STATLINE-1:0] opdata
);

	(* rom_style = "BLOCK" *)
	reg [`STATLINE-1:0] optype;

	always @* begin
		case (insn)
		`I_ADDL3: optype = { 16'd0, `S_ADDL, `S_WL, `S_RL, `S_RL };
//		`I_MOVL: optype = `S_RL;
//		8'h57: optype = 10'h32f; //= resinflt
		default: optype = 0;
		endcase
	end

	assign opdata = optype;

`ifdef notyet
	always @* begin
		case (argn)
		3'd0: opdata = optype[`STATBITS-1:0];
		3'd0: opdata = optype[`STATBITS-1:0];
		3'd0: opdata = optype[`STATBITS-1:0];
		3'd0: opdata = optype[`STATBITS-1:0];
		default: opdata = optype[`STATBITS-1:0];
	end
`endif

endmodule



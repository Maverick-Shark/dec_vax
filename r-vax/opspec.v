/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX operand types and sizes
 *
 * The upper 5 bits keep the operand size in bytes, the lower 5 bits has
 * the access type.
 */

module opspec(
	input [7:0] insn,
	input [2:0] narg,
	output [4:0] size,
	output o_r, o_w, o_m, o_a, o_v
);

	(* rom_style = "BLOCK" *)
	reg [49:0] optype;

	reg [4:0] odata;
	reg [4:0] oacc;

	always @* begin
		case (insn)
`I_ADDL2: optype = { 30'b0, `O_LONG, `O_M, `O_LONG, `O_R };
`I_ADDL3: optype = { 20'b0, `O_LONG, `O_W, `O_LONG, `O_R, `O_LONG, `O_R };
		default: optype = 0;
		endcase
	end

	assign size = odata;
	assign { o_r, o_w, o_m, o_a, o_v } = oacc;

	always @* begin
		case (narg)
		3'd0: begin odata = optype[9:5]; oacc = optype[4:0]; end
		3'd1: begin odata = optype[19:15]; oacc = optype[14:10]; end
		3'd2: begin odata = optype[29:25]; oacc = optype[24:20]; end
		3'd3: begin odata = optype[39:35]; oacc = optype[34:30]; end
		default: begin odata = optype[49:45]; oacc = optype[44:40]; end
		endcase
	end

endmodule



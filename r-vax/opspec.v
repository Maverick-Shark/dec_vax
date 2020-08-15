/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX operand types and sizes
 *
 * The upper 5 bits keep the operand size in bytes, the lower 5 bits has
 * the access type.
 */
`define	OP_RL_ML	8'd1
`define	OP_RL_RL_WL	8'd3
`define	OP_RL_WL	8'd4

module opspec(
	input [7:0] insn,
	input [2:0] narg,
	output [4:0] size,
	output o_r, o_w, o_m, o_a, o_v
);
	(* rom_style = "BLOCK" *)
	reg [7:0] optbl;
	(* rom_style = "BLOCK" *)
	reg [9:0] statetbl;
	wire [7:0] nstate;

	always @* begin
		case (nstate+narg) /* XXX avoid add in combinatorial path */
		default:	statetbl = 0;
		`OP_RL_ML:	statetbl = { `O_LONG, `O_R };
		8'd2:		statetbl = { `O_LONG, `O_M };
		`OP_RL_RL_WL:	statetbl = { `O_LONG, `O_R };
		`OP_RL_WL:	statetbl = { `O_LONG, `O_R };
		8'd5:		statetbl = { `O_LONG, `O_W };
		endcase
	end

	always @* begin
		case (insn)
		default:	optbl = 0;
		`I_ADDL2:	optbl = `OP_RL_ML;
		`I_ADDL3:	optbl = `OP_RL_RL_WL;
		`I_MOVL:	optbl = `OP_RL_WL;
		endcase
	end

	assign size = statetbl[9:5];
	assign { o_r, o_w, o_m, o_a, o_v } = statetbl[4:0];

	assign nstate = optbl;

endmodule



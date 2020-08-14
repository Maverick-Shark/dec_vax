/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX CPU
 */

module cpu(
	input clk,
	input rst,

	input [4:0]	reg_addr,
	input [31:0]	reg_wdata,
	input 		reg_write,
	input		reg_stb,
	output reg [31:0] reg_rdata,
	output reg 	reg_ack,

	output reg [31:0] cpu_addr,
	output reg [31:0] cpu_wdata,
	input [31:0]	cpu_rdata,
	output reg	cpu_stb,
	output reg	cpu_write,
	input 		cpu_ack,

	input		cont,
	input		step,
	output		halted,

	output reg [31:0]	pc
);

	reg [31:0]	greg[15:0];
	reg [`STATBITS-1:0]	state, fillstate;

	reg [31:0]	psl;
	reg		Ctmp;

	/* different traps/faults */
	reg 	resinflt, 	/* reserved  instruction fault (FFFF) */
		resadflt,	/* reserved addressing mode fault */
		resopflt;	/* reserved operand fault */

	/* instruction word "cache" */
	reg [31:2]	itag;
	reg [31:0]	inslword;
	reg		ivalid;
	reg [7:0]	cur_inst;
	reg [7:0]	decib;

	reg [31:0]	arg[5:0], argp[5:0];	// storage for evaluated args
	reg [2:0]	nargs;		// current arg
	reg [0:0]	isreg[5:0];	// destination is reg
	reg [31:0]	res;

	wire [31:0] curpc, cur_reg_val;
	wire [1:0] curbyte;
	wire [3:0] cur_reg_num;
	assign curbyte = greg[15][1:0];
	assign curpc = greg[15];
	assign cur_reg_num = decib[3:0];
	assign cur_reg_val = greg[cur_reg_num];

	/*
	 * get current instruction byte based on pc.
	 */
	always @* begin
		case (curpc[1:0])
		2'b00: decib = inslword[7:0];
		2'b01: decib = inslword[15:8];
		2'b10: decib = inslword[23:16];
		2'b11: decib = inslword[31:24];
		endcase
	end

	wire [`STATLINE-1:0] optype;
	reg [`STATLINE-1-`STATBITS:0] savop;
	wire [`STATLINE-1-`STATBITS:0] nextsavop;
	assign nextsavop = { `STATBITS'd0, savop[(`STATBITS*5)-1:`STATBITS] };

	decode decode(decib, optype);


	wire [4:0] op_size;
	wire o_r, o_w, o_m, o_a, o_v;
	opspec opspec(cur_inst, nargs, op_size, o_r, o_w, o_m, o_a, o_v);

	assign halted = state == `S_HALT;
	assign isvalid = (itag[31:2] == greg[15][31:2]) && ivalid;
	assign anyfault = resinflt | resadflt | resopflt;

	always @(posedge clk) begin
		if (rst)
			state <= `S_HALT;
		else
		case (state)
		`S_HALT: begin
			ivalid <= 0;
			pc <= greg[15];
			if (cont)
				state <= `S_FETCH;
			if (reg_stb) begin
				if (reg_write) begin
					greg[reg_addr] <= reg_wdata;
				end else begin
					if (reg_addr == 5'h1f)
						reg_rdata <= psl; // PSL
					else if (reg_addr == 5'h1e)
						reg_rdata <= state;
					else if (reg_addr[4])
						reg_rdata <= arg[reg_addr[2:0]];
					else
						reg_rdata <= greg[reg_addr];
				end
				reg_ack <= 1;
			end else
				reg_ack <= 0;
		end

		/* get next instruction from input stream */
		`S_FETCH: begin
			if (isvalid) begin
				/* put insbyte in decode reg */
				savop <= optype[(`STATBITS*5)-1:`STATBITS];
				cur_inst <= decib;
				greg[15] <= curpc + 1;
				state <= optype[`STATBITS-1:0];
				nargs <= 0;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_FETCH;
			end
		end

		/* Read a longword and put into current arg reg */
		`S_ARG: begin
			if (isvalid) begin
				state <= savop[`STATBITS-1:0];
				savop <= nextsavop;
				case (decib[7:4])
				`OPS_LIT: begin
					if (o_r) begin
						arg[nargs] <= { 24'b0, decib };
					end else begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						state <= `S_HALT;
					end
				end
				`OPS_REG: begin
					if (o_a) begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						state <= `S_HALT;
					end else begin
						if (o_r | o_m | o_v)
							arg[nargs] <= cur_reg_val;
						if (o_m | o_w | o_v) begin
							isreg[nargs] <= 1;
							argp[nargs] <= cur_reg_num;
						end
					end
				end

				default: arg[nargs] <= { 24'd0, decib };
				endcase
				nargs <= nargs + 1;
				greg[15] <= curpc + 1;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_ARG;
			end
		end

		/*
		 * Simple operations.  We cannot end up here if a fault occurred.
		 */
		`S_SOP: begin
			state <= `S_ENDINST;
			case (cur_inst)
			`I_ADDL2, `I_ADDL3:
				{ Ctmp, arg[2]  } <= { 1'b0, arg[0] } + { 1'b0, arg[1] };
			endcase
			if (nargs == 2) begin
				argp[2] <= argp[1];
				isreg[2] <= isreg[1];
			end
		end
		/*
		 * Write back value.  Set flags. If any fault occurred take action.
		 * Resulting value is always in arg[2].
		 */
		`S_ENDINST: begin
			state <= `S_HALT;
			if (anyfault) begin
				greg[4] <= anyfault; /* XXX */
			end else begin
				psl[`PSL_C] <= Ctmp;
				psl[`PSL_V] <= 0;
				psl[`PSL_N] <= arg[2][31];
				psl[`PSL_Z] <= (|arg[2]) == 0;
				if (cur_inst == `I_ADDL2 || cur_inst == `I_ADDL3) begin
					if ((arg[0][31] == arg[1][31]) &&
					    (arg[0][31] != arg[2][31]))
						psl[`PSL_V] <= 1;
				end
				if (isreg[2]) 
					greg[argp[2][3:0]] <= arg[2];
				else
					greg[arg[2][3:0]] <= 32'hf00fbabe;
			end
		end


		`S_FILLUP: begin
			/* Fetch new longword */
			cpu_addr <= { curpc[31:2], 2'b00 };
			cpu_stb <= 1;
			if (cpu_ack) begin
				inslword <= cpu_rdata;
				itag <= curpc[31:2];
				ivalid <= 1;
				cpu_stb <= 0;
				state <= fillstate;
			end
		end
		default: state <= `S_HALT;
		endcase
	end


endmodule

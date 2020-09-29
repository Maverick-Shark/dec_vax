/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none

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
	input		reg_write,
	input		reg_stb,
	output reg [31:0] reg_rdata,
	output reg	reg_ack,

	output reg [31:0] cpu_addr,
	output reg [31:0] cpu_wdata,
	input [31:0]	cpu_rdata,
	output reg	cpu_stb,
	output reg	cpu_write,
	input		cpu_ack,
	output reg [1:0] cpu_size,

	input		cont,
	input		step,
	output		halted,

	output reg [31:0]	pc
);

	/*
	 * arg1/2 are arg value read. (if R|M)
	 * arg1p is pointer to the destination (if memory and W|A|M) 
	 * argd1 is destination for value.
	 */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSED */
	reg [31:0]	arg1, arg2, arg3, arg4, argd1, arg1p, arg2p;
	reg		num_arg, num_argd, num_argp;
	reg		arg1p_isreg, arg2p_isreg;
	reg [3:0]	arg1p_regnum, arg2p_regnum;
	reg [1:0]	arg1p_size, arg2p_size;
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSED */

	reg [`STATBITS-1:0]	state, fillstate;
	// synthesis attribute INIT of state is "0"
	reg [7:0]	haltpos;

/* verilator lint_off UNDRIVEN */
	reg [7:0]	psw;

	/* different traps/faults */
	reg	resinflt,	/* reserved instruction fault (FFFF) */
		resadflt,	/* reserved addressing mode fault (movl r0,$3) */
		resopflt;	/* reserved operand fault */
/* verilator lint_on UNDRIVEN */

	/* instruction word "cache" */
	reg [31:2]	itag;
	reg [31:0]	inslword;
	reg		ivalid;
	reg [7:0]	cur_inst;
	reg [7:0]	cur_byte;



	reg [3:0]	regnum;

	reg		isindex, writeback;
	reg [31:0]	OA, IA, OP;
	reg		OA_isreg;
	reg [3:0]	OA_regnum;



	reg [31:0] curpc;
	wire [31:0] cur_reg_val_subsz;
	wire [31:0] cur_reg_val;
//	wire [1:0] curbyte;
	wire [3:0] cur_reg_num;
/* verilator lint_off UNUSED */
	reg [3:0] cur_reg_num_save;
/* verilator lint_on UNUSED */
	assign cur_reg_num = cur_byte[3:0];

	/*
	 * get current instruction byte based on pc.
	 */
	always @* begin
		case (curpc[1:0])
		2'b00: cur_byte = inslword[7:0];
		2'b01: cur_byte = inslword[15:8];
		2'b10: cur_byte = inslword[23:16];
		2'b11: cur_byte = inslword[31:24];
		endcase
	end

	/*
	 * Argument stuff.
	 * decode_inst is this instruction arg ptr until next instruction.
	 * decode_arg is the current argument number under whole argument
	 * evaluation.
	 */
	reg [2:0] cur_arg_number; // cleared in FETCH, increased in ARGEND
	reg arg_defer;		// indirect flag set.
	reg notrash;		// don't trash OA if reading from mem
/* verilator lint_off UNUSED */
	reg [3:0] argaddto;	// for increment arguments
/* verilator lint_on UNUSED */
	wire [7:0] decode_inst;
	wire [2:0] decode_arg;
	wire [2:0] num_args;
	wire [1:0] arg_size;
	wire arg_R, arg_W, arg_A;
	assign decode_inst = (state == `S_FETCH ? cur_byte : cur_inst);
	assign decode_arg = (state == `S_FETCH ? 3'b0 : cur_arg_number);
	decode decode(
		.insn(decode_inst),		// instruction input
		.current_arg(decode_arg),	// Current arg # input

		.num_args(num_args),		// # of args set by decode_inst

		.arg_R(arg_R),
		.arg_W(arg_W), 
		.arg_A(arg_A),
		.arg_size(arg_size)
	);


	reg [3:0] op_size_ary;
	reg Ctmp;
	assign cur_reg_val_subsz = cur_reg_val - { 28'b0, op_size_ary };

	always @(arg_size) begin
		case (arg_size)
		`O_BYTE: op_size_ary = 4'b0001;
		`O_WORD: op_size_ary = 4'b0010;
		`O_LONG: op_size_ary = 4'b0100;
		default: op_size_ary = 4'b1000;
		endcase
	end

	wire isvalid, anyfault;
	assign halted = state == `S_HALT;
	assign isvalid = (itag[31:2] == curpc[31:2]) && ivalid;
	assign anyfault = resinflt | resadflt | resopflt;

	/*
	 * General register file, currently in Distributed RAM.
	 */
	(* ram_style = "DISTRIBUTED" *)
	reg [31:0]	general_reg[15:0];

	/* decoding of greg writeback */
	reg [31:0] greg_wback, greg_wbdata;
	always @* begin
		case (arg1p_size)
		`O_BYTE: greg_wback = { cur_reg_val[31:8], argd1[7:0] };
		`O_WORD: greg_wback = { cur_reg_val[31:16], argd1[15:0] };
		`O_LONG: greg_wback = argd1;
		`O_QUAD: greg_wback = argd1;
		endcase
	end

	reg [3:0] greg_wregnum;
	wire [3:0]  greg_addr;
	assign greg_addr =
		state == `S_HALT ? reg_addr[3:0] :
	    	state == `S_ARG ? cur_reg_num :
	    	state == `S_ENDINST ? arg1p_regnum : cur_reg_num_save;

	always @(posedge clk)
		if (state == `S_WREG)
			general_reg[greg_wregnum] <= greg_wbdata;
	assign cur_reg_val = general_reg[greg_addr];

	/*
	 * evaluation definitions.
	 */
	reg		calc_vnzc;

	/*
	 * Program counter mgmt. curpc is the "live" version. greg[15] is
	 * only updated between instructions.
	 */
	reg set_branch_pc, delay_halt;
	wire [31:0] pc_plus_1, pc_plus_arg1;
	assign pc_plus_1 = curpc + 1;
	assign pc_plus_arg1 = curpc + arg1;

	always @(posedge clk) begin

		if (rst)
			state <= `S_HALT;
		else
		case (state)
		`S_HALT: begin
			pc <= curpc;
			if (cont)
				state <= `S_FETCH;
			if (reg_stb) begin
				if (reg_write) begin
					ivalid <= 0;
					greg_wregnum <= reg_addr[3:0];
					greg_wbdata <= reg_wdata;
					if (reg_addr == 5'h0f)
						curpc <= reg_wdata;
					fillstate <= `S_HALT;
					state <= `S_WREG;
				end else begin
					casez (reg_addr)
					5'h1f: reg_rdata <= { 24'd0, psw };
					5'h1d: reg_rdata <= { 24'b0, haltpos };
					5'h1c: reg_rdata <= inslword;
					5'h1b: reg_rdata <= { itag, 1'b0, ivalid };
					5'h19: reg_rdata <= arg2p;
					5'h18: reg_rdata <= arg1p;
					5'h14: reg_rdata <= argd1;
					5'h13: reg_rdata <= arg4;
					5'h12: reg_rdata <= arg3;
					5'h11: reg_rdata <= arg2;
					5'h10: reg_rdata <= arg1;
					5'h0?: begin
						if (reg_addr == 5'h0f)
							reg_rdata <= curpc;
						else
							reg_rdata<= cur_reg_val;
					end
					default: reg_rdata <= 0;
					endcase
				end
				reg_ack <= 1;
			end else
				reg_ack <= 0;
		end

		/* get next instruction from input stream */
		`S_FETCH: begin
			if (cpu_ack)
				cpu_stb <= 0;
			if (step && delay_halt) begin
				state <= `S_HALT;
				delay_halt <= 0;
				haltpos <= 6;
			end else if (isvalid) begin
				/* put insbyte in decode reg */
				cur_inst <= cur_byte;
				num_arg <= 0;
				num_argd <= 0;
				num_argp <= 0;
				cur_arg_number <= 0;
				isindex <= 0;

				curpc <= pc_plus_1;
				if (num_args == 3'b0)
					state <= `S_EXECUTE;
				else if (arg_R == 0 && (arg_W & arg_A))
					state <= `S_BRARGS;
				else
					state <= `S_ARG;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_FETCH;
			end
		end

		/* Read a longword and put into current arg reg */
		`S_ARG: begin
			arg_defer <= cur_byte[4];
			if (isvalid) begin
				curpc <= pc_plus_1;
				state <= `S_ARGEND;
				cur_reg_num_save <= cur_byte[3:0];

				casez (cur_byte[7:4])
				`OPS_LIT: begin
					OP <= { 24'b0, cur_byte };
					if (~arg_R | arg_W | arg_A) begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						haltpos <= 2;
						state <= `S_HALT;
					end
				end
				`OPS_INDEX: begin
					IA <= cur_reg_val << arg_size;
					isindex <= 1;
					state <= `S_ARG;
					if (isindex || &cur_byte[3:0]) begin
						// resadflt <= 1;
						haltpos <= 12;
						state <= `S_HALT;
					end
				end
				`OPS_REG: begin	// 5
					if (arg_A | isindex) begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						haltpos <= 3;
						state <= `S_HALT;
					end
					OP <= cur_reg_val;
					OA_isreg <= 1;
					OA_regnum <= cur_byte[3:0];
				end

				`OPS_REGD: begin // 6
					OA <= cur_reg_val + IA;
					state <= arg_R ? `S_OAREAD : `S_ARGEND;
				end

				`OPS_ADEC: begin // 7
					OA <= cur_reg_val_subsz + IA;
					greg_wbdata <= cur_reg_val_subsz + IA;
					greg_wregnum <= cur_byte[3:0];
					state <= `S_WREG;
					fillstate <=
					    arg_R ? `S_OAREAD : `S_ARGEND;
				end

				`OPS_AINC, `OPS_AINCD: begin // 8-9
					if (cur_byte[4])
						argaddto <= 4'd4;
					else
						argaddto <= op_size_ary;
					OA <= 0;
					regnum <= 4'b0000;
					state <= `S_RDCDATA;
				end

				`OPS_DISP: begin // 10-15
					argaddto <= 4'd0;
					state <= `S_RDCDATA;
					case (cur_byte[6:5])
					2'b00: regnum <= 4'b0000;
					2'b01: regnum <= 4'b0001;
					2'b10: regnum <= 4'b0011;
					2'b11: regnum <= 4'b1111;
					endcase
				end
				endcase
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_ARG;
			end
		end

		/*
		 * Read in the argument offset number (byte, word or long) from
		 * the instruction stream.
		 */
		`S_RDCDATA: begin
			if (isvalid) begin
				if (regnum[0]) begin
					OA <= { {24{cur_byte[7]}}, cur_byte };
					regnum[0] <= 0;
					curpc <= pc_plus_1;
				end else if (regnum[1]) begin
					OA <= { {16{cur_byte[7]}},
					    cur_byte, OA[7:0] };
					regnum[1] <= 0;
					curpc <= pc_plus_1;
				end else if (regnum[2]) begin
					OA[23:16] <= cur_byte;
					regnum[2] <= 0;
					curpc <= pc_plus_1;
				end else if (regnum[3]) begin
					OA[31:24] <= cur_byte;
					regnum[3] <= 0;
					curpc <= pc_plus_1;
				end else begin
					if (cur_reg_num_save == `REG_PC)
						OA <= OA + curpc;
					else
						OA <= OA + cur_reg_val;
					if (arg_defer) begin
						cpu_size <= `O_LONG;
						state <= `S_READMEM;
						fillstate <= `S_INDOA;
					end else begin
						state <= `S_INDOA;
					end
				end
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_RDCDATA;
			end
		end

		/*
		 * Ended up here either via defer read state or directly
		 * from RDCDATA.
		 */
		`S_INDOA: begin
			OA <= OA + IA;
			if (arg_R) begin
				cpu_size <= arg_size;
				state <= `S_READMEM;
				fillstate <= `S_ARGEND;
				notrash <= 1;
			end else
				state <= `S_ARGEND;
		end

		/*
		 * Got OA.  Fetch val.
		 */
		`S_OAREAD: begin
			notrash <= 1;
			cpu_addr <= OA;
			cpu_size <= arg_size;
			fillstate <= `S_ARGEND;
			state <= `S_READMEM;
		end

		/*
		 * Store the argument results in their next slot.
		 */
		`S_ARGEND: begin
			if (arg_R) begin
				case (num_arg)
				1'b0: arg1 <= OP;
				1'b1: arg2 <= OP;
		//		2'b10: arg2 <= OP; // XX
		//		2'b11: arg2 <= OP; // XX
				endcase
				num_arg <= 1;
			end

			if (arg_W | arg_A) begin
				if (num_argp == 0) begin
					arg1p <= OA;
					arg1p_isreg  <= OA_isreg;
					arg1p_regnum <= OA_regnum;
					arg1p_size <= arg_size;
					num_argp <= 1;
				end
				if (num_argp) begin
					arg2p <= OA;
					arg2p_isreg  <= OA_isreg;
					arg2p_regnum <= OA_regnum;
					arg2p_size <= arg_size;
				end
			end
			OA_isreg <= 0;

			cur_arg_number <= cur_arg_number + 1;
			if (cur_arg_number + 1 == num_args)
				state <= `S_EXECUTE;
			else
				state <= `S_ARG;
		end

		/*
		 * Simple operations. 
		 * We cannot end up here if an argument fault occurred.
		 */
		`S_EXECUTE: begin
			state <= `S_ENDINST;
			Ctmp <= psw[`PSL_C];
			case (cur_inst)
			`I_BRB, `I_BRW: set_branch_pc <= 1;
			`I_BNEQ: if (psw[`PSL_Z] == 0) set_branch_pc <= 1;
			`I_BEQL: if (psw[`PSL_Z] == 1) set_branch_pc <= 1;
			`I_BGTR: if (psw[3:2] == 2'b00) set_branch_pc <= 1;
			`I_BLEQ: if (psw[3:2] == 2'b11) set_branch_pc <= 1;

			`I_BGEQ: if (psw[`PSL_N] == 0) set_branch_pc <= 1;
			`I_BLSS: if (psw[`PSL_N] == 1) set_branch_pc <= 1;
			`I_BGTRU: if ((psw[`PSL_Z]|psw[`PSL_C]) == 0)
				set_branch_pc <= 1;
			`I_BLEQU: if ((psw[`PSL_Z]|psw[`PSL_C]) == 1)
				set_branch_pc <= 1;
			`I_BVC: if (psw[`PSL_V] == 0) set_branch_pc <= 1;
			`I_BVS: if (psw[`PSL_V] == 1) set_branch_pc <= 1;
			`I_BCC: if (psw[`PSL_C] == 0) set_branch_pc <= 1;
			`I_BCS: if (psw[`PSL_C] == 1) set_branch_pc <= 1;
			`I_ADDL2, `I_ADDL3: begin
				{ Ctmp, argd1 } <=
				    { 1'b0, arg1 } + { 1'b0, arg2 };
				writeback <= 1;
				calc_vnzc <= 1;
			end
			`I_MOVL: begin argd1 <= arg1; writeback <= 1; end
			`I_BISPSW, `I_BICPSW: begin
				//  XXX handle exceptions in instr read
				if (|arg1[15:8]) begin
					// resopflt <= 1;
					// state <= S_ENDINSN;
					haltpos <= 4;
					state <= `S_HALT;
				end else begin
					if (cur_inst[0]) // bicpsw
						psw[3:0] <= psw[3:0] & ~arg1[3:0];
					else  // bispsw
						psw <= psw | { 4'b0, arg1[3:0]};
				end
			end
			default: begin state <= `S_HALT; haltpos <= 13; end
			endcase
		end

		/*
		 * Branch instruction argument.
		 * It is just setup here to use the arg 10 or 12 eval.
		 */
		`S_BRARGS: begin
			if (arg_size == `O_WORD)
				regnum <= 4'b0011;
			else
				regnum <= 4'b0001;
			cur_reg_num_save <= `REG_PC;
			OA <= 0;
			state <= `S_RDCDATA;
		end

		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`S_ENDINST: begin
			state <= `S_FETCH;
			writeback <= 0;
			calc_vnzc <= 0;

			if (anyfault) begin
				haltpos <= 5;
				state <= `S_HALT;
			end else if (writeback & (arg1p_isreg == 0)) begin
				cpu_addr <= arg1p;
				cpu_wdata <= argd1;
				cpu_size <= arg1p_size;
				state <= `S_WRITEMEM;
				fillstate <= `S_ENDINST;
			end else if (writeback) begin
				greg_wbdata <= greg_wback;
				greg_wregnum <= arg1p_regnum;
				fillstate <= `S_FETCH;
				state <= `S_WREG;
			end
			if (set_branch_pc)
				curpc <= pc_plus_arg1;
			set_branch_pc <= 0;
			if (calc_vnzc) begin
				psw[`PSL_C] <= Ctmp;
				psw[`PSL_N] <= argd1[31];
				psw[`PSL_Z] <= ~|argd1;
				psw[`PSL_V] <= 
				    ((arg1[31] & arg2[31]) &&
				     (arg1[31] ^ argd1[31]));
			end
			if (step)
				delay_halt <= 1;
		end

		`S_FILLUP: begin
			/* Fetch new longword */
			cpu_addr <= { curpc[31:2], 2'b00 };
			cpu_write <= 0;
			cpu_stb <= 1;
			cpu_size <= `O_LONG;
			if (cpu_ack) begin
				inslword <= cpu_rdata;
				itag <= curpc[31:2];
				ivalid <= 1;
				cpu_stb <= 0;
				state <= fillstate;
			end
		end

		`S_WREG: state <= fillstate;
		
		`S_WRITEMEM: begin
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_WRITEMEM2;
		end

		`S_WRITEMEM2: if (cpu_ack) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			state <= fillstate;
		end

		`S_READMEM: begin
			cpu_write <= 0;
			cpu_stb <= 1;
			state <= `S_READMEM2;
		end

		`S_READMEM2: if (cpu_ack) begin
			notrash <= 0;
			if (notrash == 0)
				OA <= cpu_rdata;
			OP <= cpu_rdata;
			cpu_stb <= 0;
			state <= fillstate;
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end


endmodule

/*	$Id$	*/
`timescale 1ns / 1ps

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX CPU
 */

`define	MEM_BYTE	2'b00
`define	MEM_WORD	2'b01
`define	MEM_LONG	2'b11

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
	output reg [1:0] cpu_size,

	input		cont,
	input		step,
	output		halted,

	output reg [31:0]	pc
);

	reg [31:0]	greg[15:0];
	reg [`STATBITS-1:0]	state, fillstate, next_state;
	reg [7:0]	haltpos;

/* verilator lint_off UNDRIVEN */
	reg [31:0]	psl;

	/* different traps/faults */
	reg 	resinflt, 	/* reserved instruction fault (FFFF) */
		resadflt,	/* reserved addressing mode fault (movl r0,$3) */
		resopflt;	/* reserved operand fault */
/* verilator lint_on UNDRIVEN */

	/* instruction word "cache" */
	reg [31:2]	itag;
	reg [31:0]	inslword;
	reg		ivalid;
	reg [7:0]	cur_inst;
	reg [7:0]	decib;

	reg [31:0]	arg[5:0], argp[5:0];	// storage for evaluated args
	reg [2:0]	nargs, prev_nargs;	// current /previous arg number.
	reg [0:0]	isreg[5:0];	// destination is reg
	reg [31:0]	oldpc;		// saved pc in case of fault
	reg [3:0]	regnum;

	reg		isindex, writeback;
	reg [31:0]	OA, BOA;

	wire [31:0] cur_reg_val_subsz, cur_reg_val_addsz, cur_reg_val_add4;
	wire [31:0] curpc, cur_reg_val;
//	wire [1:0] curbyte;
	wire [3:0] cur_reg_num;
/* verilator lint_off UNUSED */
	reg [3:0] cur_reg_num_save, cur_arg_op_sav;
/* verilator lint_on UNUSED */
//	assign curbyte = greg[15][1:0];
	assign curpc = greg[15];
	assign cur_reg_num = decib[3:0];
	assign cur_reg_val = greg[cur_reg_num];
	assign cur_reg_val_add4 = cur_reg_val + 4;

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

`ifdef notdef
	reg [1:0] d65tosz;
	always @* begin
		(* full_case *)
		case (decib[6:5])
		2'b01: d65tosz = `MEM_BYTE;
		2'b10: d65tosz = `MEM_WORD;
		2'b11: d65tosz = `MEM_LONG;
		endcase
	end
`endif

	wire [7:0] opoff, stateoff, nstate;
	reg [7:0] nxtoff;
	assign nstate = state == `S_FETCH ? opoff : nxtoff;
	decode decode(
		.insn(decib),		// instruction input
		.nstate(nstate),	// state offset input
		.stateoff(stateoff),	// next state output
		.opoff(opoff));		// first offset for insn arg output


	wire [7:0] arg_opoff, arg_nstate;
	reg [7:0] arg_nxtoff;
//	reg [3:0] op_size_save;
	reg [3:0] op_size_ary;
	wire [1:0] op_size_l2;
	wire o_r, o_w, o_m, o_a, o_v;
//	wire [31:0] arg0_arg1_add;
	reg Ctmp;
	assign arg_nstate = arg_nxtoff;
	assign cur_reg_val_subsz = cur_reg_val - { 28'b0, op_size_ary };
	assign cur_reg_val_addsz = cur_reg_val + { 28'b0, op_size_ary };
//	assign { Ctmp, arg0_arg1_add } = { 1'b0, arg[0] } + { 1'b0, arg[1] };

`ifdef notdef
	/*
	 * Arguments having displacement modes.
	 */
	reg [31:0] cur_arg_res;
	reg [31:0]	read_val;
	always @* begin
		case (cur_arg_op_sav[2:1])
		2'b00: cur_arg_res = cur_reg_val;
		2'b01: cur_arg_res = { {24{read_val[7]}}, read_val[7:0] } + cur_reg_val;
		2'b10: cur_arg_res = { {16{read_val[15]}}, read_val[15:0] } + cur_reg_val;
		2'b11: cur_arg_res = read_val + cur_reg_val;
		endcase
	end
`endif

	always @* begin
		case (op_size_l2)
		`O_BYTE: op_size_ary = 4'b0001;
		`O_WORD: op_size_ary = 4'b0010;
		`O_LONG: op_size_ary = 4'b0100;
		`O_QUAD: op_size_ary = 4'b1000;
		endcase
	end

	reg doread_save;
	opspec opspec(
		.insn(decib),
		.nstate(arg_nstate),
		.opoff(arg_opoff),
		.sizel2(op_size_l2),
		.o_r(o_r), .o_w(o_w), .o_m(o_m), .o_a(o_a), .o_v(o_v));

	wire isvalid, anyfault;
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
					greg[reg_addr[3:0]] <= reg_wdata;
				end else begin
					if (reg_addr == 5'h1f)
						reg_rdata <= psl; // PSL
					else if (reg_addr == 5'h1e)
						reg_rdata <= oldpc;
					else if (reg_addr == 5'h1d)
						reg_rdata <= { 24'b0, haltpos };
					else if (reg_addr[4:3] == 2'b11)
						reg_rdata <= argp[reg_addr[2:0]];
					else if (reg_addr[4:3] == 2'b10)
						reg_rdata <= arg[reg_addr[2:0]];
					else
						reg_rdata <= greg[reg_addr[3:0]];
				end
				reg_ack <= 1;
			end else
				reg_ack <= 0;
		end

		/* get next instruction from input stream */
		`S_FETCH: begin
			if (cpu_ack)
				cpu_stb <= 0;
			if (isvalid) begin
				/* put insbyte in decode reg */
				cur_inst <= decib;
				oldpc <= greg[15];
				greg[15] <= curpc + 1;
				state <= stateoff;
				nxtoff <= opoff + 1;
				arg_nxtoff <= arg_opoff; /* XXX */
				nargs <= 0;
				isindex <= 0;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_FETCH;
			end
		end

		/* Read a longword and put into current arg reg */
		`S_ARG: begin
			if (isvalid) begin
				state <= stateoff;
				if (isindex == 0) begin
					next_state <= stateoff;
					nxtoff <= nxtoff + 1;
					nargs <= nargs + 1;
					prev_nargs <= nargs;
					arg_nxtoff <= arg_nxtoff + 1;
				end
				doread_save <= o_r | o_m | o_v;
				greg[`REG_PC] <= curpc + 1;
				cur_reg_num_save <= decib[3:0];
				cur_arg_op_sav <= decib[7:4];
//				op_size_save <= op_size_ary;
				isreg[nargs] <= 0;

				casez (decib[7:4])
				`OPS_LIT: begin
					if (o_r && !isindex) begin
						arg[nargs] <= { 24'b0, decib };
					end else begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						haltpos <= 2;
						state <= `S_HALT;
					end
				end
				`OPS_INDEX: begin
					if (cur_reg_num == `REG_PC) begin
						// resadflt <= 1;
						haltpos <= 12;
					end else begin
						BOA <= cur_reg_val << op_size_l2;
						isindex <= 1;
						state <= `S_ARG;
					end
				end
				`OPS_REG: begin	// 5
					if (o_a | isindex) begin
						// resadflt <= 1;
						// state <= S_ENDINSN;
						haltpos <= 3;
						state <= `S_HALT;
					end else begin
						if (o_r | o_m | o_v)
							arg[nargs] <= cur_reg_val;
						if (o_m | o_w | o_v) begin
							isreg[nargs] <= 1;
							argp[nargs] <= { 28'b0, decib[3:0] };
						end
					end
				end

				`OPS_REGD, `OPS_AINC: begin // 6, 8
					OA <= cur_reg_val;
					if (decib[7])
						greg[cur_reg_num] <= cur_reg_val_addsz;
					state <= `S_OAREAD;
				end

				`OPS_AINCD: begin // 9
					cpu_addr <= cur_reg_val;
					cpu_size <= `MEM_LONG;
					greg[cur_reg_num] <= cur_reg_val_add4;
					fillstate <= `S_OAREAD;
					state <= `S_READMEM;
				end

				`OPS_ADEC: begin // 7
					greg[cur_reg_num] <= cur_reg_val_subsz;
					OA <= cur_reg_val - { 28'b0, op_size_ary};
					state <= `S_OAREAD;
				end

				`OPS_DISP: begin // 10-15
					state <= `S_RDCDATA;
					(* full_case *)
					case (decib[6:5])
					2'b01: regnum <= 4'b0001;
					2'b10: regnum <= 4'b0011;
					2'b11: regnum <= 4'b1111;
					default: begin state <= `S_HALT; haltpos <= 14; end
					endcase
				end

				default: begin
					arg[nargs] <= { 24'd0, decib };
					haltpos <= 1;
					state <= `S_HALT;
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
					OA <= { {24{decib[7]}}, decib };
					regnum[0] <= 0;
				end else if (regnum[1]) begin
					OA <= { {16{decib[7]}}, decib, OA[7:0] };
					regnum[1] <= 0;
				end else if (regnum[2]) begin
					OA[23:16] <= decib;
					regnum[2] <= 0;
				end else if (regnum[3]) begin
					OA[31:24] <= decib;
					regnum[3] <= 0;
				end else begin
					if (cur_arg_op_sav[0]) begin // indirect
						cpu_addr <= OA + greg[cur_reg_num_save];
						cpu_size <= `MEM_LONG;
						fillstate <= `S_OAREAD;
						state <= `S_READMEM;
					end else begin
						OA <= OA + greg[cur_reg_num_save];
						state <= `S_OAREAD;
					end
				end
				greg[`REG_PC] <= curpc + 1;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_RDCDATA;
			end
		end

		/*
		 * Got OA.  Save it and fetch the val as well if a read arg.
		 */
		`S_OAREAD: begin
			if (isindex) begin
				argp[prev_nargs] <= OA + BOA;
				isindex <= 0;
			end else
				argp[prev_nargs] <= OA;

			isreg[prev_nargs] <= 0;
			if (doread_save) begin
				if (isindex) begin
					cpu_addr <= OA + BOA;
				end else
					cpu_addr <= OA;
				cpu_size <= `MEM_LONG; // XXX
				fillstate <= `S_ARGRDATA;
				state <= `S_READMEM;
			end else
				state <= next_state;
		end

		`S_ARGRDATA: begin
			arg[prev_nargs] <= OA;
			state <= next_state;
		end
		/*
		 * Simple operations. 
		 * We cannot end up here if an argument fault occurred.
		 * Also initiate the write-back to memory here, so that a potential
		 * access fault is catched before ENDINIT state.
		 */
		`S_SOP: begin
			state <= `S_ENDINST;
			Ctmp <= psl[`PSL_C];
			case (cur_inst)
			`I_ADDL2, `I_ADDL3: begin
				{ Ctmp, arg[2]  } <= { 1'b0, arg[0] } + { 1'b0, arg[1] };
				writeback <= 1;
			end
			`I_MOVL: begin arg[2] <= arg[0]; writeback <= 1; end
			`I_BISPSW, `I_BICPSW: begin
				if (|arg[0][15:8]) begin
					// resopflt <= 1;
					// state <= S_ENDINSN;
					haltpos <= 4;
					state <= `S_HALT;
				end else begin
					if (cur_inst[0]) // bicpsw
						psl[3:0] <= psl[3:0] & ~arg[0][3:0];
					else  // bispsw
						psl[3:0] <= psl[3:0] | arg[0][3:0];
				end
			end
			default: begin state <= `S_HALT; haltpos <= 13; end
			endcase
			if (nargs == 2) begin
				argp[2] <= argp[1];
				isreg[2] <= isreg[1];
			end
		end

		/*
		 * Branch instruction argument.
		 */
		`S_BR: begin
			if (isvalid) begin
				greg[15] <= curpc + 1;
				nargs <= nargs + 1;
				arg_nxtoff <= arg_nxtoff + 1;
				if (nargs == 0) begin
					/* get first (or only) byte */
					arg[0] <= { {24{decib[7]}}, decib };
					if (op_size_ary[0] == 1) // byte offset
						state <= `S_ENDINST;
				end else begin // nargs == 1
					arg[0] <= { {16{decib[7]}}, decib, arg[0][7:0] };
					state <= `S_ENDINST;
				end
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_BR;
			end
		end

		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`S_ENDINST: begin
			state <= `S_FETCH;
			if (anyfault) begin
				greg[15] <= oldpc;
				haltpos <= 5;
				state <= `S_HALT;
			end else if (writeback & (isreg[2] == 0)) begin
				cpu_addr <= argp[2];
				cpu_wdata <= arg[2];
				cpu_size <= `MEM_LONG; // XXX
				state <= `S_WRITEMEM;
				writeback <= 0;
				fillstate <= `S_ENDINST;
			end else begin
			case (cur_inst)
			`I_BRB, `I_BRW: greg[15] <= curpc + arg[0];

			`I_BNEQ: if (psl[`PSL_Z] == 0) greg[15] <= curpc + arg[0];
			`I_BEQL: if (psl[`PSL_Z] == 1) greg[15] <= curpc + arg[0];
			`I_BGTR: if (psl[3:2] == 2'b00) greg[15] <= curpc + arg[0];
			`I_BLEQ: if (psl[3:2] == 2'b11) greg[15] <= curpc + arg[0];

			`I_BGEQ: if (psl[`PSL_N] == 0) greg[15] <= curpc + arg[0];
			`I_BLSS: if (psl[`PSL_N] == 1) greg[15] <= curpc + arg[0];
			`I_BGTRU: if ((psl[`PSL_Z]|psl[`PSL_C]) == 0)
				greg[15] <= curpc + arg[0];
			`I_BLEQU: if ((psl[`PSL_Z]|psl[`PSL_C]) == 1)
				greg[15] <= curpc + arg[0];
			`I_BVC: if (psl[`PSL_V] == 0) greg[15] <= curpc + arg[0];
			`I_BVS: if (psl[`PSL_V] == 1) greg[15] <= curpc + arg[0];
			`I_BCC: if (psl[`PSL_C] == 0) greg[15] <= curpc + arg[0];
			`I_BCS: if (psl[`PSL_C] == 1) greg[15] <= curpc + arg[0];

			`I_ADDL2, `I_ADDL3, `I_MOVL: begin
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
			end
			`I_BISPSW, `I_BICPSW: ;
			default: begin state <= `S_HALT; haltpos <= 8; end
			endcase
			writeback <= 0;
			if (step) begin
				state <= `S_HALT;
				haltpos <= 6;
			end
			end
		end

		`S_FILLUP: begin
			/* Fetch new longword */
			cpu_addr <= { curpc[31:2], 2'b00 };
			cpu_write <= 0;
			cpu_stb <= 1;
			cpu_size <= `MEM_LONG;
			if (cpu_ack) begin
				inslword <= cpu_rdata;
				itag <= curpc[31:2];
				ivalid <= 1;
				cpu_stb <= 0;
				state <= fillstate;
			end
		end

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
			OA <= cpu_rdata;
			cpu_stb <= 0;
			state <= fillstate;
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end


endmodule

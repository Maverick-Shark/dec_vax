/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none

`include "states.vh"
`include "opcodes.vh"
`include "ipr.vh"
`include "scb.vh"

/*
 * VAX CPU
 */

module cpu(
	input clk,
	input rst,

	input		CON_CYC_I,
	input [31:0]	CON_ADR_I,
	input [31:0]	CON_DAT_I,
	input		CON_WE_I,
	input		CON_STB_I,
	output [31:0]	CON_DAT_O,
	output 		CON_ACK_O,

	input		con_reg,
	input		con_ipr,
	input		con_pmem,
	input		con_vmem,

	output		CPU_CYC_O,
	output [31:0] 	CPU_ADR_O,
	output [31:0] 	CPU_DAT_O,
	output 		CPU_STB_O,
	output 		CPU_WE_O,
	input [31:0]	CPU_DAT_I,
	input		CPU_ACK_I,

	output [1:0]	CPU_SIZE_O,

	output		CPU_PMEM_O,

	output		cpu_mcheck,

	input		cont,
	input		step,
	output		halted

);

	/*
	 * Console communications.
	 */
	reg [31:0]	con_dat_o_reg;
	reg 		con_ack_o_reg;
	wire		con_passthru;
	assign con_passthru = CON_CYC_I & (con_vmem | con_pmem);
	assign CON_DAT_O = con_passthru ? CPU_DAT_I : con_dat_o_reg;
	assign CON_ACK_O = con_passthru ? CPU_ACK_I : con_ack_o_reg;

	/*
	 * CPU to memory/IPR communications.
	 */
	reg [31:0]	cpu_addr, cpu_wdata;
	reg		cpu_write, cpu_stb;
	reg		cpu_pmem;
	reg		mcheck;
	reg [1:0]	cpu_size;
	wire		cpu_acki;
	assign cpu_mcheck  = mcheck;
	assign cpu_acki = CPU_ACK_I | mcheck;
	assign CPU_CYC_O = halted & ~(con_reg | con_ipr) ? CON_CYC_I : cpu_stb;
	assign CPU_ADR_O = halted ? CON_ADR_I : cpu_addr;
	assign CPU_DAT_O = halted ? CON_DAT_I : cpu_wdata;
	assign CPU_WE_O  = halted ? CON_WE_I  : cpu_write;
	assign CPU_STB_O = halted ? CON_STB_I : cpu_stb;

	assign CPU_PMEM_O = halted ? con_pmem : cpu_pmem;
	assign CPU_SIZE_O = halted ? `O_LONG : cpu_size;

	/*
	 * IPR regs.  First 15 in LUT RAM, rest in flipflops.
	 */
	(* ram_style = "DISTRIBUTED" *)
	reg [31:0]	ipr_reg[15:0];

	wire [3:0]	ipr_regraddr, ipr_regwaddr;
	wire [31:0]	ipr_val, ipr_wdata;
	reg [14:0]	scbb;
	reg		ipr_write;

	always @(posedge clk)
		if (ipr_write)
			ipr_reg[ipr_regwaddr] <= ipr_wdata;
	assign ipr_val = ipr_reg[ipr_regraddr];

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

	assign ipr_regraddr = halted ? CON_ADR_I[3:0] : arg1[3:0];
	assign ipr_regwaddr = halted ? CON_ADR_I[3:0] : arg2[3:0];
	assign ipr_wdata = halted ? CON_DAT_I : arg1;

	reg [`STATBITS-1:0]	state, fillstate;
	// synthesis attribute INIT of state is "0"
	reg [7:0]	haltpos;

/* verilator lint_off UNDRIVEN */
	reg		psl_is;
	reg [1:0]	cur_mod, prv_mod;
	reg [4:0]	psl_ipl;
	reg [7:0]	psw;
initial psl_is = 1'b1;
initial psl_ipl = 5'h1f;

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



	reg [31:0] curpc, oldpc;
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
	wire [7:0] decode_inst;
	wire [2:0] decode_arg;
	wire [2:0] num_args;
	wire [1:0] arg_size;
	wire arg_R, arg_W, arg_A;
	assign decode_inst = (state == `S_FETCH ? cur_byte : cur_inst);
	assign decode_arg = (state == `S_FETCH ? 3'b0 : cur_arg_number);
	decode decode(
		.clk(clk),
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

	/*
	 * Faults.
	 */
	reg manhalt;
	reg [6:0] mchk_cnt;
	wire isvalid, anyfault;
	assign halted = (state == `S_HALT) || manhalt;
	assign isvalid = (itag[31:2] == curpc[31:2]) && ivalid;
	assign anyfault = resinflt | resadflt | resopflt;

	always @(posedge clk) begin
		if (CPU_STB_O == 0) begin
			mchk_cnt <= 0;
			mcheck <= 0;
		end else if (CPU_ACK_I == 0)
			mchk_cnt <= mchk_cnt + 1;
		if (&mchk_cnt)
			mcheck <= 1;
	end

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
		state == `S_HALT ? CON_ADR_I[3:0] :
	    	state == `S_ARG ? cur_reg_num :
	    	state == `S_ENDINST ? arg1p_regnum : cur_reg_num_save;

	always @(posedge clk)
		if (state == `S_WREG)
			general_reg[greg_wregnum] <= greg_wbdata;
	assign cur_reg_val =
	    (greg_addr == `REG_PC ? curpc : general_reg[greg_addr]);

	/*
	 * evaluation definitions.
	 */
	reg		calc_vnzc, set_vnz_dest;

	/*
	 * Program counter mgmt. curpc is the "live" version. greg[15] is
	 * only updated between instructions.
	 */
	reg set_branch_pc, delay_halt;
	wire [31:0] pc_plus_1;
	assign pc_plus_1 = curpc + 1;


	/* console communications */
	wire ref_greg_read, ref_greg_write, ipr_greg_read, ipr_greg_write;
	assign ref_greg_read = CON_STB_I & CON_CYC_I & (CON_WE_I == 0) &con_reg;
	assign ref_greg_write = CON_STB_I & CON_CYC_I & CON_WE_I & con_reg;
	assign ipr_greg_read = CON_STB_I & CON_CYC_I & (CON_WE_I == 0) &con_ipr;
	assign ipr_greg_write = CON_STB_I & CON_CYC_I & CON_WE_I & con_ipr;

	always @(posedge clk) begin
		if (rst)
			state <= `S_HALT;
		else
		case (state)
		`S_HALT: begin
			manhalt <= 1;
			if (cont) begin
				state <= `S_FETCH;
				ivalid <= 0;
				resopflt <= 0;
			end
			if (CON_STB_I == 0)
				con_ack_o_reg <= 0;

			ipr_write <= 0;
			if (ipr_greg_read) begin
				casez (CON_ADR_I[5:0])
				6'b00zzzz: con_dat_o_reg <= ipr_val;
				`IPR_SCBB: con_dat_o_reg <= { 8'b0, scbb,9'b0 };
				default: con_dat_o_reg <= 32'hdeadbabe;
				endcase
				con_ack_o_reg <= 1;
			end else if (ipr_greg_write) begin
				casez (CON_ADR_I[5:0])
				6'b00zzzz: ipr_write <= 1;
				`IPR_SCBB: scbb <= CON_DAT_I[23:9];
				default: ;
				endcase
				con_ack_o_reg <= 1;
			end else if (ref_greg_read) begin
				casez (CON_ADR_I[4:0])
				5'h1f: con_dat_o_reg <=
	{ 5'd0, psl_is, cur_mod, prv_mod, 1'b0, psl_ipl, 8'b0, psw };
				5'h1e: con_dat_o_reg <= oldpc;
				5'h1d: con_dat_o_reg <=
				    { 23'b0, resopflt, haltpos };
				5'h1c: con_dat_o_reg <= inslword;
				5'h1b: con_dat_o_reg <= { itag, 1'b0, ivalid };
				5'h19: con_dat_o_reg <= arg2p;
				5'h18: con_dat_o_reg <= arg1p;
				5'h14: con_dat_o_reg <= argd1;
				5'h13: con_dat_o_reg <= arg4;
				5'h12: con_dat_o_reg <= arg3;
				5'h11: con_dat_o_reg <= arg2;
				5'h10: con_dat_o_reg <= arg1;
				5'h0?: con_dat_o_reg <= cur_reg_val;
				default: con_dat_o_reg <= 0;
				endcase
				con_ack_o_reg <= 1;
			end else if (ref_greg_write) begin
				greg_wregnum <= CON_ADR_I[3:0];
				greg_wbdata <= CON_DAT_I;
				con_ack_o_reg <= 1;
				state <= `S_WREG;
				fillstate <= `S_HALT;
			end
		end

		/* get next instruction from input stream */
		`S_FETCH: begin
			manhalt <= 0;
			if (CPU_ACK_I)
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
				oldpc <= curpc;
				curpc <= pc_plus_1;
				state <= `S_DECODE;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_FETCH;
			end
		end

		`S_DECODE: begin
			if (num_args == 3'b0)
				state <= `S_EXECUTE;
			else if (arg_R == 0 && (arg_W & arg_A))
				state <= `S_BRARGS;
			else
				state <= `S_ARG;
		end

		/* Read a longword and put into current arg reg */
		`S_ARG: begin
			arg_defer <= cur_byte[4];
			if (isvalid) begin
				curpc <= pc_plus_1;
				state <= `S_ARGEND;
				cur_reg_num_save <= cur_byte[3:0];
//$fdisplay(32'h80000002, "ARG: curpc %x curbyte %x\r\n", curpc, cur_byte);

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
					greg_wregnum <= cur_reg_num;
					state <= `S_POSTINC0;
				end

				`OPS_DISP: begin // 10-15
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
					OA <= OA + cur_reg_val;
					cpu_addr <= OA + cur_reg_val;
					
// $fdisplay(32'h80000002, "RDC: curpc %x oa %x cur_reg_val %x\r\n", curpc, OA, cur_reg_val);
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
		 * need estra state to get pc to increment.
		 */
		`S_POSTINC0: begin
			state <= `S_WREG;
			OA <= cur_reg_val;
			if (arg_defer) begin
				fillstate <= `S_POSTINC;
				greg_wbdata <= cur_reg_val + 32'd4;
			end else begin
				fillstate <= `S_INDOA;
				greg_wbdata <= cur_reg_val +
				    { 28'b0, op_size_ary };
			end
		end

		`S_POSTINC: begin
			cpu_addr <= OA;
			cpu_size <= `O_LONG;
			state <= `S_READMEM;
			fillstate <= `S_INDOA;
		end

		/*
		 * Ended up here either via defer read state or directly
		 * from RDCDATA.
		 */
		`S_INDOA: begin
			OA <= OA + IA;
//$fdisplay(32'h80000002, "INDOA: OA %x OP %x arg_R %d\r\n", OA, OP, arg_R);
			if (arg_R) begin
				cpu_addr <= OA;
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
//if (arg_R) $fdisplay(32'h80000002, "ARGEND: numarg %d OP %x \r\n", num_arg, OP);
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
			`I_JMP: begin
				set_branch_pc <= 1;
			end

			`I_INCL: begin
				{ Ctmp, argd1 } <= { 1'b0, arg1 } + 33'h1;
				writeback <= 1;
				calc_vnzc <= 1;
			end
			`I_ADDL2, `I_ADDL3, `I_ADWC: begin
				{ Ctmp, argd1 } <=
				    { 1'b0, arg1 } + { 1'b0, arg2 } +
				    (cur_inst == `I_ADWC ?
				    { 32'b0, psw[`PSL_C] } : 33'd0);
				writeback <= 1;
				calc_vnzc <= 1;
			end
			`I_XORL2, `I_XORL3: begin
				argd1 <= arg2 ^ arg1;
//$fdisplay(32'h80000002, "BICL: arg1 %x arg2 %x\r\n", arg1, arg2);
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			`I_BICL2, `I_BICL3: begin
				argd1 <= arg2 & ~arg1;
//$fdisplay(32'h80000002, "BICL: arg1 %x arg2 %x\r\n", arg1, arg2);
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			`I_MOVAB, `I_MOVAW, `I_MOVAL: begin
				argd1 <= arg1p;
				arg1p <= arg2p;
				arg1p_regnum <= arg2p_regnum;
				arg1p_isreg <= arg2p_isreg;
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			`I_MOVL: begin
				argd1 <= arg1;
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			`I_MTPR: begin
				argd1 <= arg1;
				if (anyfault == 0)
					state <= `S_MTPR;
			end
			`I_MFPR: begin
//$fdisplay(32'h80000002, "I_MFPR: arg1 %x anyfault %d\r\n", arg1, anyfault);
				cur_reg_num_save <= `REG_SP;
				writeback <= 1;
				set_vnz_dest <= 1;
				if (anyfault == 0)
					state <= `S_MFPR;
			end
			`I_CLRB, `I_CLRW, `I_CLRL: begin
//$fdisplay(32'h80000002, "CLRL: arg1p %x \r\n", arg1p);
				argd1 <= 0;
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			`I_TSTB, `I_TSTW, `I_TSTL: begin
//$fdisplay(32'h80000002, "TSTL: arg1p %x arg1 %x\r\n", arg1p, arg1);
				argd1 <= arg1;
				set_vnz_dest <= 1;
			end
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
			arg_defer <= 0;
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
			set_vnz_dest <= 0;

			if (anyfault) begin
				haltpos <= 5;
				state <= `S_HALT;
		//		resopflt <= 0;
			end else if (writeback & (arg1p_isreg == 0)) begin
// $fdisplay(32'h80000002, "WB MEM: addr %x val %x\r\n", arg1p, argd1);
				cpu_addr <= arg1p;
				cpu_wdata <= argd1;
				cpu_size <= arg1p_size;
				state <= `S_WRITEMEM;
				fillstate <= `S_ENDINST;
			end else if (writeback) begin
// $fdisplay(32'h80000002, "WB REG: reg %x val %x\r\n", arg1p_regnum, greg_wback);
				greg_wbdata <= greg_wback;
				greg_wregnum <= arg1p_regnum;
				fillstate <= `S_FETCH;
				state <= `S_WREG;
			end
// $fdisplay(32'h80000002, "brpc: arg1p %x curpc %x\r\n", arg1p, curpc);
			if (set_branch_pc)
				curpc <= arg1p;
			set_branch_pc <= 0;
			if (set_vnz_dest) begin
				psw[`PSL_N] <= argd1[31];
				psw[`PSL_Z] <= ~|argd1;
				psw[`PSL_V] <= 0;
			end
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

		`S_MTPR: begin
			state <= `S_ENDINST;
			ipr_write <= 0;
			if (|arg2[31:6])
				resopflt <= 1;
			else
			casez (arg2[5:0])
			`IPR_KSP, `IPR_SSP, `IPR_ESP, `IPR_USP: begin
				if (psl_is == 0 && arg2[1:0] == cur_mod) begin
					arg1p_size <= `O_LONG;
					argd1 <= arg1;
					arg1p_regnum <= `REG_SP;
					arg1p_isreg <= 1;
					writeback <= 1;
				end
				ipr_write <= 1;
			end
			`IPR_ISP: begin
				if (psl_is == 1) begin
					arg1p_size <= `O_LONG;
					argd1 <= arg1;
					arg1p_regnum <= `REG_SP;
					arg1p_isreg <= 1;
					writeback <= 1;
				end
				ipr_write <= 1;
			end
			`IPR_SCBB: scbb <= arg1[23:9];
			`IPR_PCBB: ;
			`IPR_IPL: psl_ipl <= arg1[4:0];
			`IPR_TXDB: begin
				cpu_addr <= 32'h20001f76;
				cpu_wdata <= arg1;
				cpu_size <= `O_LONG;
				cpu_pmem <= 1;
				state <= `S_WRITEMEM;
				fillstate <= `S_TXDB_W;
			end
			default: resopflt <= 1;
			endcase
		end

		/*
		 * XXX check if current sp is the same
		 */
		`S_MFPR: begin
//$fdisplay(32'h80000002, "S_MFPR: arg1 %x arg2 %x\r\n", arg1, arg2);
			state <= `S_ENDINST;
			if (|arg1[31:6])
				resopflt <= 1;
			else
			casez (arg1[5:0])
			`IPR_KSP, `IPR_SSP, `IPR_ESP, `IPR_USP: begin
				if (arg1[1:0] == cur_mod)
					argd1 <= cur_reg_val;
				else
					argd1 <= ipr_val;
			end
			`IPR_ISP: begin
				if (psl_is)
					argd1 <= cur_reg_val;
				else
					argd1 <= ipr_val;
			end
			`IPR_SCBB: argd1 <= { 8'b0, scbb, 9'b0 };
			`IPR_PCBB: ;
			`IPR_IPL: argd1 <= { 27'b0, psl_ipl };
			`IPR_TXCS: begin
//$fdisplay(32'h80000002, "IPR_TXCS: pmem %d \r\n", cpu_pmem);
				state <= `S_READMEM;
				fillstate <= `S_TXCS_R;
				cpu_addr <= 32'h20001f74;
				cpu_size <= `O_LONG;
				cpu_pmem <= 1;
			end
			`IPR_SID: argd1 <= 32'h0A000006;
			default: resopflt <= 1;
			endcase
		end

		`S_TXCS_R: begin
			state <= `S_ENDINST;
			argd1 <= OP;
//$fdisplay(32'h80000002, "S_TXCS_R: OP %x \r\n", OP);
			cpu_pmem <= 0;
		end

		`S_TXDB_W: begin
			state <= `S_ENDINST;
			cpu_pmem <= 0;
		end

		/*
		 * Got a machine check.
		 * Fetch SCB mcheck address and jump there.
		 */
		`S_MCHECK: begin
			arg1 <= `VEC_MCHECK;
			state <= `S_GETVEC;
		//	haltpos <= 8;
			fillstate <= `S_MCHECK1;
		end

		/*
		 * Address from SCB in argd1. Do stack change.
		 * (mcheck should always be served on the interrupt stack)
		 */
		`S_MCHECK1: begin
			arg2 <= 0;
			state <= `S_SETSTK;
			fillstate <= `S_MCHECK2;
		end

		`S_MCHECK2: begin
			state <= `S_PUSH;
			cur_reg_num_save <= `REG_SP;
			fillstate <= `S_MCHECK2;
			arg2 <= arg2 + 1;
			case (arg2[3:0])
			4'd0: cpu_wdata <=
	{ 5'd0, psl_is, cur_mod, prv_mod, 1'b0, psl_ipl, 8'b0, psw };
			4'd1: cpu_wdata <= oldpc;
			4'd12: cpu_wdata <= 32'h28;
			default: cpu_wdata <= 0;
			endcase
			if (arg2[3:0] == 4'd12)
				fillstate <= `S_MCHECK3;
		end

		`S_MCHECK3: begin
			psl_ipl <= 5'h1f;
			psl_is <= argd1[0];
			curpc <= { argd1[31:2], 2'b0 };
			state <= `S_FETCH;
		end

		/*
		 * push cpu_wdata onto stack.
		 */
		`S_PUSH: begin
			cpu_addr <= cur_reg_val - 4;
			cpu_size <= `O_LONG;
			state <= `S_WRITEMEM;
			fillstate <= `S_PUSH2;
		end

		/*
		 * Set new stack based on ivec (in argd1).
		 */
		`S_SETSTK: begin
			/* save current stack */
			cpu_addr <= psl_is ? 32'd4 : { 30'b0, cur_mod };
			cpu_wdata <= cur_reg_val; /* XXX */
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_SETSTK1;
		end

		`S_SETSTK1: if (cpu_acki) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			state <= `S_SETSTK2;
		end

		`S_SETSTK2: begin
			/* fetch new stack */
			cpu_addr <= argd1[0] ? 32'd4 : 32'd0;
			cpu_stb <= 1;
			state <= `S_SETSTK3;
		end

		`S_SETSTK3: if (cpu_acki) begin
			cpu_stb <= 0;
			greg_wregnum <= `REG_SP;
			greg_wbdata <= CPU_DAT_I;
			state <= `S_WREG;
		end

		`S_FILLUP: begin
			/* Fetch new longword */
			cpu_addr <= { curpc[31:2], 2'b00 };
			cpu_write <= 0;
			cpu_stb <= 1;
			cpu_size <= `O_LONG;
			if (cpu_acki) begin
				inslword <= CPU_DAT_I;
				itag <= curpc[31:2];
				ivalid <= 1;
				cpu_stb <= 0;
				state <= mcheck ? `S_MCHECK : fillstate;
			end
		end

		`S_WREG: begin 
			if (greg_wregnum == `REG_PC)
				curpc <= greg_wbdata;
			state <= fillstate;
		end
		
		`S_WRITEMEM: begin
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_WRITEMEM2;
		end

		`S_WRITEMEM2: if (cpu_acki) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			state <= mcheck ? `S_MCHECK : fillstate;
		end

		`S_READMEM: begin
			cpu_write <= 0;
			cpu_stb <= 1;
			state <= `S_READMEM2;
		end

		`S_READMEM2: if (cpu_acki) begin
			notrash <= 0;
			if (notrash == 0)
				OA <= CPU_DAT_I;
			OP <= CPU_DAT_I;
			cpu_stb <= 0;
			state <= mcheck ? `S_MCHECK : fillstate;
		end

		`S_GETVEC: begin
			cpu_addr <= { 26'b0, `IPR_SCBB };
			cpu_write <= 0;
			cpu_stb <= 1;
			state <= `S_GETVEC1;
		end

		`S_GETVEC1: if (CPU_ACK_I) begin
			cpu_stb <= 0;
			cpu_addr <= CPU_DAT_I + arg1;
			state <= `S_GETVEC2;
		end

		`S_GETVEC2: begin
			cpu_stb <= 1;
			cpu_pmem <= 1;
			cpu_size <= `O_LONG;
			state <= `S_GETVEC3;
		end

		`S_GETVEC3: if (CPU_ACK_I) begin
			cpu_stb <= 0;
			cpu_pmem <= 0;
			argd1 <= CPU_DAT_I;
			state <= fillstate;
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end

endmodule

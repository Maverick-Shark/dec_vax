/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none

`include "aluops.vh"
`include "opcodes.vh"
`include "ipr.vh"
`include "scb.vh"

/*
 * VAX CPU
 */
`define STATBITS	8

`define S_HALT		0
`define S_FETCH		1
`define S_WREG		2
`define S_FILLUP	3
`define	MCODE		4
`define S_READMEM	5
`define S_READMEM2	6
`define S_WRITEMEM	7
`define S_WRITEMEM2	8
`define S_DECODE	10
`define WRITEIPR	11
`define ASETUP		13
`define ARG_GETBWL	14
`define ARG_ADDTO	15
`define ARG_INDIR	16
`define ARG_READ	17
`define ARGEND		18
`define ENDINST		19
`define PREEXEC		20
`define EXEC		21

/* WREG return states */
`define	WREG_HALT	0
`define	WREG_WRITEMEM	1
`define	WREG_PREEXEC	2
`define	WREG_FETCH	5
`define	WREG_ARG_INDIR	9
`define	WREG_xENDINST	10

/* READMEM return states */
`define	RMEM_ARG_INDIR	0
`define	RMEM_PREEXEC	1
`define	RMEM_ARG_READ	4
`define	RMEM_xARGEND	5
`define	RMEM_xENDINST	6

/* WRITEMEM return states */
`define WMEM_MCODE	0
`define WMEM_PREEXEC	1
`define	WMEM_xENDINST	3

/* FILLUP return states */
`define	FUP_FETCH	0
`define	FUP_ARG		1
`define	FUP_RDCDATA	2
`define	FUP_ASETUP	3
`define	FUP_ARG_GETBWL	4

/* halt codes */
`define	HALT_RESET	0
`define	HALT_INSN	1
`define	HALT_MCHECK	2
`define	HALT_STEP	3

module cpu(
	input clk,
	input rst,

	output [31:0] 	CPU_ADR_O,
	output [31:0] 	CPU_DAT_O,
	output 		CPU_STB_O,
	output 		CPU_WE_O,
	input [31:0]	CPU_DAT_I,
	input		CPU_ACK_I,

	output [1:0]	CPU_SIZE_O,

	output		CPU_PMEM_O,

	output		cpu_mcheck


);

	/*
	 * Console communications.
	 */
	wire [31:0]	CON_ADR_I;
	wire [31:0]	CON_DAT_I;
	wire		CON_WE_I;
	wire		CON_STB_I;
	wire [31:0]	CON_DAT_O;
	wire 		CON_ACK_O;
	wire		con_reg, con_ipr, con_pmem, con_vmem;
	wire		cont, step, halted;
	reg [7:0]	haltpos;

	reg [31:0]	con_dat_o_reg;
	reg 		con_ack_o_reg;
	wire		con_passthru;
	assign con_passthru = CON_STB_I & (con_vmem | con_pmem);
	assign CON_DAT_O = con_passthru ? CPU_DAT_I : con_dat_o_reg;
	assign CON_ACK_O = con_passthru ? CPU_ACK_I : con_ack_o_reg;

	/* different traps/faults */
	reg	resinflt,	/* reserved instruction fault (FFFF) */
		resadflt,	/* reserved addressing mode fault (movl r0,$3) */
		resopflt;	/* reserved operand fault */

	console console(
		.clk(clk),
		.rst(rst),

		.halted(halted),	// Handle commands
		.cont(cont),
		.step(step),

		.haltpos(haltpos),
		.resopflt(resopflt),

		.ADR_O(CON_ADR_I),
		.WE_O(CON_WE_I),
		.DAT_O(CON_DAT_I),
		.STB_O(CON_STB_I),
		.DAT_I(CON_DAT_O),
		.ACK_I(CON_ACK_O),

		.con_reg(con_reg),
		.con_ipr(con_ipr),
		.con_pmem(con_pmem),
		.con_vmem(con_vmem)
	);

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
	assign CPU_STB_O = halted & ~(con_reg | con_ipr) ? CON_STB_I : cpu_stb;
	assign CPU_ADR_O = halted ? CON_ADR_I : cpu_addr;
	assign CPU_DAT_O = halted ? CON_DAT_I : cpu_wdata;
	assign CPU_WE_O  = halted ? CON_WE_I  : cpu_write;

	assign CPU_PMEM_O = halted ? con_pmem : cpu_pmem;
	assign CPU_SIZE_O = halted ? `O_LONG : cpu_size;

	/*
	 * IPR regs in LUT RAM.
	 */
	(* ram_style = "DISTRIBUTED" *)
	reg [31:0]	ipr_reg[63:0];

	wire [5:0]	ipr_regaddr;
	wire [31:0]	ipr_val, ipr_regwdata;
	reg [5:0]	ipr_addr;
	reg [31:0]	ipr_wdata;
	reg		ipr_write;
	reg [`STATBITS-1:0]	state;

	always @(posedge clk)
		if (ipr_write || state == `WRITEIPR)
			ipr_reg[ipr_regaddr] <= ipr_regwdata;
	assign ipr_val = ipr_reg[ipr_regaddr];


	/*
	 * arg1/2 are arg value read. (if R|A)
	 * arg1p is pointer to the destination (if memory and W) 
	 * argd1 is destination for value.
	 */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSED */
	reg [31:0]	argp[1:0], arg[3:0], argd[1:0];
	reg		argp_isreg[1:0];
	reg [3:0]	argp_regnum[1:0];
	reg [1:0]	a1sz, argp_size[1:0];
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSED */

	assign ipr_regaddr = halted ? CON_ADR_I[5:0] : ipr_addr[5:0];
	assign ipr_regwdata = halted ? CON_DAT_I : ipr_wdata;

	reg [3:0]	wregstate;
	reg [2:0]	rmemstate, wmemstate, fupstate;
	reg [31:0]	rmem_dat;
	// synthesis attribute INIT of state is "0"

/* verilator lint_off UNDRIVEN */
	reg		psl_is;
	reg [1:0]	cur_mod, prv_mod;
	reg [4:0]	psl_ipl;
	reg [7:0]	psw;
initial psl_is = 1'b1;
initial psl_ipl = 5'h1f;
	wire [31:0]	psl;
	assign psl = 
	    { 5'd0, psl_is, cur_mod, prv_mod, 1'b0, psl_ipl, 8'b0, psw };

/* verilator lint_on UNDRIVEN */

	/* instruction word "cache" */
	reg [31:2]	itag;
	reg [31:0]	inslword;
	reg		ivalid;
	reg [7:0]	cur_byte, cur_inst;

	reg		writeback, writeback2;
	reg [31:0]	OA, IA, OP;
	reg [31:0]	getbwl_OA, addto_OA, indir_OA;
	reg		OA_isreg;
	reg [3:0]	OA_regnum;



	reg [31:0] curpc, oldpc, oldpsl;
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


	reg [3:0]	mcodectr;
	reg [31:0]	mc_rv;
	always @(mcodectr, psl, curpc, oldpc, cur_inst)
		casez (mcodectr)
		4'd13: mc_rv = psl;
		4'd12: mc_rv = curpc;
		4'b101?: mc_rv = argp_isreg[mcodectr[0]] ?
		    ~{ 28'b0, argp_regnum[mcodectr[0]] } : argp[mcodectr[0]];
		4'b01??: mc_rv = arg[mcodectr[1:0]];
		4'b0011: mc_rv = oldpc;
		4'b0010: mc_rv = { 24'b0, cur_inst };
		default: mc_rv = 0;
		endcase

	/*
	 * Argument stuff.
	 * evaluation.
	 */
	reg notrash;	// Control readmem trashing

	reg Ctmp, Ntmp, Ztmp;

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
	reg [31:0]	greg_wbdata;

	reg [3:0] greg_wregnum;
`ifdef notdef
	wire [3:0]  greg_addr;
	assign greg_addr =
		state == `S_HALT ? CON_ADR_I[3:0] :
	    	state == `ASETUP ? cur_reg_num : cur_reg_num_save;
`endif
	reg [3:0]	greg_addr;
	always @(*)
		case (state)
		`S_HALT: greg_addr = CON_ADR_I[3:0];
		`ASETUP: greg_addr = cur_reg_num;
		default: greg_addr = cur_reg_num_save;
		endcase

	always @(posedge clk)
		if (state == `S_WREG)
			general_reg[greg_wregnum] <= greg_wbdata;
`ifdef notdef
	assign cur_reg_val =
	    (greg_addr == `REG_PC ? curpc : general_reg[greg_addr]);
`endif
	reg [31:0] cur_reg_val;
	always @(greg_addr, curpc)
		case (greg_addr)
		`REG_PC: cur_reg_val = curpc;
		default: cur_reg_val = general_reg[greg_addr];
		endcase

	/* "microcode" */
	wire [7:0]	i_argoff, a_argoff, a_arg, cur_mux;
	wire		i_enable, i_hasargs, i_emul, i_dohalt;
	wire		a_enable, a_emul, a_last, i_move2, i_wback2;
	wire		i_wback;
	wire		i_setnz, i_clv, i_clc, i_setc;
	wire		arg_aR, arg_aW, arg_aA;
	wire [2:0]	a_argcode;
	wire [1:0]	a_argsz;
	wire [2:0]	a_rargno;
	wire		a_wargno;
	reg [7:0]	acounter, curarg;

	wire		s_enable, s_eoi;
	wire		s_nzcond, s_zcond, s_wback, s_savc, s_savnz;
	wire		s_nncond, s_ncond, s_wback2, s_goto, s_rmem;
	wire		s_resopflt, s_wipr, s_wmem, s_wreg;
	wire [3:0]	s_dest;
	wire [7:0]	s_stepoff, i_stepoff;
	wire [3:0]	s_op, s_left, s_right;
	wire [23:0]	s_const;
	reg [7:0]	scounter;
	

	assign i_enable = (state == `S_FETCH) && isvalid;
	assign a_enable = (state == `S_DECODE) || (state == `ARGEND);
	assign a_argoff = (state == `S_DECODE) ? i_argoff : acounter;
	assign arg_aR = a_argcode[2];
	assign arg_aW = a_argcode[1];
	assign arg_aA = a_argcode[0];
	assign cur_mux = a_emul ? a_arg : cur_byte;


	ucode ucode(
		.clk(clk),

		.i_enable(i_enable),
		.i_opcode(cur_byte),

		.i_argoff(i_argoff),
		.i_hasargs(i_hasargs),
		.i_emul(i_emul),

		.i_wback(i_wback),

		.i_setnz(i_setnz),
		.i_clv(i_clv),
		.i_clc(i_clc),
		.i_setc(i_setc),


		.i_stepoff(i_stepoff),

		.i_move2(i_move2),
		.i_wback2(i_wback2),

		.i_dohalt(i_dohalt),

		.s_enable(s_enable),
		.s_stepoff(s_stepoff),

		.s_left(s_left),
		.s_right(s_right),
		.s_op(s_op),
		.s_eoi(s_eoi),
		.s_zcond(s_zcond),
		.s_nzcond(s_nzcond),
		.s_wback(s_wback),
		.s_savc(s_savc),
		.s_ncond(s_ncond),
		.s_nncond(s_nncond),
		.s_wback2(s_wback2),
		.s_goto(s_goto),
		.s_savnz(s_savnz),
		.s_dest(s_dest),
		.s_rmem(s_rmem),
		.s_wipr(s_wipr),
		.s_wmem(s_wmem),
		.s_wreg(s_wreg),
		.s_resopflt(s_resopflt),

		.s_const(s_const),

		.a_enable(a_enable),
		.a_argoff(a_argoff),
		.a_argcode(a_argcode),
		.a_argsz(a_argsz),
		.a_rargno(a_rargno),
		.a_wargno(a_wargno),
		.a_emul(a_emul),
		.a_last(a_last),
		.a_arg(a_arg)
	);

	/*
	 * Argument decoder.
	 */
	wire		arg_adec, arg_ainc, arg_aincd, arg_indir;
	wire		arg_lit, arg_reg;
	wire [3:0]	arg_sh; /* bit mapping */
	reg [4:0]	arg_radd;
	reg [3:0]	arg_rdbmsk, bcnt;
	reg		arg_indir_loop;
	argdecode argdecode(
		/* input */
		.curarg(curarg),

		/* output */
		.arg_sh(arg_sh),

		.arg_adec(arg_adec),	/* -(Rx) */
		.arg_ainc(arg_ainc),	/* (Rx)+ */
		.arg_aincd(arg_aincd),	/* *(Rx)+ */
		.arg_indir(arg_indir),	/* Reg deferred */
		.arg_lit(arg_lit),	/* literal */
		.arg_reg(arg_reg)	/* Register */
	);

	reg [3:0]	pos_arg_size;
	always @(a_argsz)
		case (a_argsz)
		2'b00: pos_arg_size = 4'h1;
		2'b01: pos_arg_size = 4'h2;
		2'b10: pos_arg_size = 4'h4;
		2'b11: pos_arg_size = 4'h8;
		endcase

	/* used for -(Rx) */
	reg [3:0]	neg_arg_size;
	always @(a_argsz)
		case (a_argsz)
		2'b00: neg_arg_size = 4'hf;
		2'b01: neg_arg_size = 4'he;
		2'b10: neg_arg_size = 4'hc;
		2'b11: neg_arg_size = 4'h8;
		endcase

	/* double mux for arguments */
	reg [31:0]	cra, arg_rv;
	always @*
		case (arg_aA)
		1'b1: arg_rv = OP;
		1'b0: arg_rv = cra;
		endcase

	always @*
		case (a_argsz)
		`O_BYTE: cra = { {24{OP[7]}}, OP[7:0] };
		`O_WORD: cra = { {16{OP[15]}}, OP[15:0] };
		`O_LONG: cra = OP;
		`O_QUAD: cra = OP;
		endcase

	/*
	 * Program counter mgmt. curpc is the "live" version. greg[15] is
	 * only updated between instructions.
	 */
	reg delay_halt;
	wire [31:0] pc_plus_1;
	assign pc_plus_1 = curpc + 1;

`ifndef notdef
wire debug;
assign debug = 0;
`else
reg debug;
initial debug = 0;
	always @(posedge clk)
		if (curpc == 32'h5cf0)
			debug <= 1;
`endif

	/* console communications */
	wire ref_greg_read, ref_greg_write, ipr_greg_read, ipr_greg_write;
	assign ref_greg_read = CON_STB_I & (CON_WE_I == 0) &con_reg;
	assign ref_greg_write = CON_STB_I & CON_WE_I & con_reg;
	assign ipr_greg_read = CON_STB_I & (CON_WE_I == 0) &con_ipr;
	assign ipr_greg_write = CON_STB_I & CON_WE_I & con_ipr;

	/*
	 * ALU code.
	 */
	
	wire		alu_cry, alu_zero, alu_stb, alu_ack, alu_neg;
	wire [31:0]	alu_res;
	reg [31:0]	alu_right, alu_left;
	assign alu_stb = (state == `EXEC);

	alu alu(
		.clk(clk),

		.op(s_op),
		.left(alu_left),
		.right(alu_right),
		.stb(alu_stb),
		.ack(alu_ack),

		.neg(alu_neg),
		.cry(alu_cry),
		.zero(alu_zero),
		.result(alu_res)
	);

	/* OK to do conditional in microcode? */
	wire		wr_cond_ok;
	assign wr_cond_ok =
	    (s_nzcond == 0 && s_zcond == 0 && s_ncond == 0 && s_nncond == 0) ||
	    (s_zcond && alu_zero) || (s_nzcond && alu_zero == 0) ||
	    (s_ncond && alu_neg) || (s_nncond && alu_neg == 0);
	assign s_stepoff = (state == `S_DECODE) ? i_stepoff : 
	    wr_cond_ok && s_goto ? s_const[7:0] : scounter;
	assign s_enable = (state == `S_DECODE) || 
	    ((state == `EXEC) && alu_ack);

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
				con_dat_o_reg <= ipr_val;
				con_ack_o_reg <= 1;
			end else if (ipr_greg_write) begin
				ipr_write <= 1;
				con_ack_o_reg <= 1;
			end else if (ref_greg_read) begin
				casez (CON_ADR_I[4:0])
				5'h1f: con_dat_o_reg <= psl;
				5'h1e: con_dat_o_reg <= oldpc;
				5'h1d: con_dat_o_reg <=
				    { 23'b0, resopflt, haltpos };
				5'h1c: con_dat_o_reg <= inslword;
				5'h1b: con_dat_o_reg <= { itag, 1'b0, ivalid };
				5'b1100?: con_dat_o_reg <= argp[CON_ADR_I[0]];
				5'h14: con_dat_o_reg <= argd[0];
				5'b100??: con_dat_o_reg <= arg[CON_ADR_I[1:0]];
				5'h0?: con_dat_o_reg <= cur_reg_val;
				default: con_dat_o_reg <= 0;
				endcase
				con_ack_o_reg <= 1;
			end else if (ref_greg_write) begin
				greg_wregnum <= CON_ADR_I[3:0];
				greg_wbdata <= CON_DAT_I;
				con_ack_o_reg <= 1;
				state <= `S_WREG;
				wregstate <= `WREG_HALT;
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
				haltpos <= `HALT_STEP;
			end else if (isvalid) begin
if (debug) $fdisplay(32'h80000002, "FETCH: pc %x curbyte %x inslword %x\r", curpc, cur_byte, inslword);
				/* put insbyte in decode reg */
				cur_inst <= cur_byte;
				oldpc <= curpc;
				oldpsl <= psl;
				curpc <= pc_plus_1;
				state <= `S_DECODE;
			end else begin
				state <= `S_FILLUP;
				fupstate <= `FUP_FETCH;
			end
		end

		/*
		 * Instruction directives are available. Fetch argument
		 * directives if necessary.
		 */
		`S_DECODE: begin
if (debug) $fdisplay(32'h80000002, "S_DECODE: i_hasargs %d i_emul %d\r", i_hasargs, i_emul);
			acounter <= i_argoff;
			scounter <= i_stepoff;
			if (i_dohalt) begin
				state <= `S_HALT;
				haltpos <= `HALT_INSN;
			end else if (i_hasargs == 0) // XXX emul
				state <= `S_HALT;
			else
				state <= `ASETUP;
		end

		/*
		 * Argument "loop".  acounter updated, argument directives
		 * available.
		 */
		`ASETUP: begin
if (debug) $fdisplay(32'h80000002, "ASETUP: a_argcode %x a_emul %d cur_byte %x a_arg %x IA %x acounter %d\r", a_argcode, a_emul, cur_byte, a_arg, IA, acounter);
if (debug) $fdisplay(32'h80000002, "ASETUPx: isvalid %x curpc %x inslword %x\r", isvalid, curpc, inslword);
			arg_rdbmsk <=
			    { {2{&cur_mux[6:5]}}, cur_mux[6], |cur_mux[6:5]};
			cur_reg_num_save <= cur_mux[3:0];
			getbwl_OA <= 0;
			bcnt <= 1;
			if ((a_emul || isvalid) && cur_mux[7:4] != 4'b0100)
				acounter <= acounter + 1;
			state <= `ARG_GETBWL;
			if (a_emul | isvalid) begin
				if (a_emul == 0)
					curpc <= pc_plus_1;
				curarg <= cur_mux;
				if (cur_mux[7:6] == 0) // literal
					state <= `ARG_READ;
				else if (cur_mux[7:4] == 4'b0100) begin
					IA <= cur_reg_val << a_argsz;
if (debug) $fdisplay(32'h80000002, "ASETUP2: cur_reg_val %x a_argsz %x\r", cur_reg_val, a_argsz);
					state <= `ASETUP;
				end else if (cur_mux[7:4] == 4'b0101) begin
					OA_isreg <= 1;
					OA_regnum <= cur_mux[3:0];
			//		state <= `ARGEND;
					state <= `ARG_READ;
				end
			end else begin
				state <= `S_FILLUP;
				fupstate <= `FUP_ASETUP;
			end
		end

		`ARG_GETBWL: begin
if (debug)$fdisplay(32'h80000002, "ARG_GETBWL: pc %x arg_rdbmsk %x bcnt %x argsh %x\r",
	curpc, arg_rdbmsk, bcnt, arg_sh);
			if (arg_adec)
				getbwl_OA <= { 28'hfffffff, neg_arg_size };
			if (arg_adec)
				arg_radd <= { 1'b1, neg_arg_size };
			if (arg_ainc)
				arg_radd <= { 1'b0, pos_arg_size };
			if (arg_aincd)
				arg_radd <= 5'd4;
			if (arg_sh[0]) begin
				if (arg_rdbmsk[0]) begin
if (debug)$fdisplay(32'h80000002, "ARG_GETBWL2: isvalid %x getbwl_OA %x cur_byte %x\r", isvalid, getbwl_OA, cur_byte);
					if (isvalid) begin
						getbwl_OA <= { cur_byte, getbwl_OA[31:8] };
						curpc <= pc_plus_1;
					end else begin
						state <= `S_FILLUP;
						fupstate <= `FUP_ARG_GETBWL;
					end
				end else begin
					getbwl_OA <= { {8{getbwl_OA[31]}}, getbwl_OA[31:8] };
				end
				if ((arg_rdbmsk[0] & isvalid) ||
				    arg_rdbmsk[0] == 0) begin
					arg_rdbmsk <= { 1'b0, arg_rdbmsk[3:1] };
					bcnt <= { bcnt[2:0], 1'b0 };
					if (bcnt[3])
						state <= `ARG_ADDTO;
				end
			end else
				state <= `ARG_ADDTO;
		end

		`ARG_ADDTO: begin
if (debug)$fdisplay(32'h80000002, "ARG_ADDTO: getbwl_OA %x cur_reg_val %x cur_reg_num_save %d\r", getbwl_OA, cur_reg_val, cur_reg_num_save);
			arg_indir_loop <= 0;
			addto_OA <= getbwl_OA + cur_reg_val;
			wregstate <= `WREG_ARG_INDIR;
			if (arg_adec|arg_ainc|arg_aincd) begin
				greg_wbdata <= cur_reg_val +
				    { {27{arg_radd[4]}}, arg_radd };
				greg_wregnum <= cur_reg_num_save;
				state <= `S_WREG;
			end else
				state <= `ARG_INDIR;
		end

		`ARG_INDIR: begin
if (debug)$fdisplay(32'h80000002, "ARG_INDIR\r");
			arg_indir_loop <= 1;
			indir_OA <= addto_OA;
			rmemstate <= `RMEM_ARG_INDIR;
			cpu_addr <= addto_OA;
			cpu_size <= `O_LONG;
			state <= `ARG_READ;
			if (arg_indir && arg_indir_loop == 0)
				state <= `S_READMEM;
			else if (arg_indir)
				indir_OA <= rmem_dat;
		end

		`ARG_READ: begin
if (debug)$fdisplay(32'h80000002, "ARG_READ: OA %x IA %x cur_byte %x curarg %x\r", OA, IA, cur_byte, curarg);
			state <= `ARGEND;
			OA <= indir_OA + IA;
			if (arg_lit && arg_aR) begin
				OP <= { 24'b0, curarg};
			end else if (arg_reg && arg_aR) begin
				OP <= cur_reg_val;
				cur_reg_num_save <= cur_reg_num_save +1;
			end else if (arg_aR) begin
				cpu_addr <= indir_OA + IA;
				cpu_size <= a_argsz;
				notrash <= 1;
				state <= `S_READMEM;
				rmemstate <= `RMEM_xARGEND;
			end else
				OP <= indir_OA + IA;
		end

		/*
		 * Store the argument results in their next slot.
		 */
		`ARGEND: begin
if (debug) $fdisplay(32'h80000002, "ARGEND: OP %x OA %x arg_rv %x acounter %d isreg %d regnum %d \r", OP, OA, arg_rv, acounter, OA_isreg, OA_regnum);
if (debug) $fdisplay(32'h80000002, "ARGEND: a_rargno %d a_wargno %d arg_aR %d arg_aA %d arg_aW %d\r\n", a_rargno, a_wargno, arg_aR, arg_aA, arg_aW);
			if (arg_aR|arg_aA) begin
				arg[a_rargno[1:0]] <= arg_rv;
				if (a_rargno == 0)
					a1sz <= a_argsz;
			end

			if (arg_aW) begin
				if (a_wargno == 0) begin
					argp[0] <= OA;
					argp_isreg[0]  <= OA_isreg;
					argp_regnum[0] <= OA_regnum;
					argp_size[0] <= a_argsz;
				end
				if (a_wargno == 1) begin
					argp[1] <= OA;
					argp_isreg[1] <= OA_isreg;
					argp_regnum[1] <= OA_regnum;
					argp_size[1] <= a_argsz;
				end
			end
			if (a_last == 0)
				state <= `ASETUP;
			else if (i_emul) begin
				state <= `MCODE;
				mcodectr <= 13;
				cur_reg_num_save <= `REG_SP;
			end else /* if (|scounter) */ begin
				state <= `PREEXEC;
// if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "INSV pos %x size %x base %x src %x pc %x\r", arg[0], arg[1], arg[2], arg[3], oldpc);
			end
			OA_isreg <= 0;
			IA <= 0;
		end

		`PREEXEC: begin
if (debug) $fdisplay(32'h80000002, "PREEXEC: op %d sleft %d sright %d scounter %d\r", s_op, s_left, s_right, scounter);
//if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "PRESTEP:  sc %d left %d right %d \r", scounter, s_left, s_right);
			casez (s_left)
			4'b00??: alu_left <= arg[s_left[1:0]];
			4'b010?: alu_left <= argd[s_left[0]];
			4'b011?: alu_left <= argp_isreg[s_left[0]] ?
			    { 2'b11, 26'b0, argp_regnum[s_left[0]] } :
				argp[s_left[0]];
			4'b1000: alu_left <= psl;
			4'b1001: alu_left <= { 8'b0, s_const };
			4'b1010: alu_left <= ipr_val;
			4'b1011: alu_left <= cur_reg_val;
			4'b1100: alu_left <= rmem_dat;
			default: alu_left <= 0;
			endcase

			casez (s_right)
			4'b00??: alu_right <= arg[s_right[1:0]];
			4'b010?: alu_right <= argd[s_right[0]];
//			4'b011?: alu_lright<= argp_isreg[s_right[0]] ?
//	    { 2'b11, 25'b0, argp_size[s_right[0]], argp_regnum[s_right[0]] } :
//				argp[s_right[0]];
			4'b1000: alu_right <= psl;
			4'b1001: alu_right <= { 8'b0, s_const };
//			4'b1010: alu_right <= OPu;
			default: alu_right <= 0;
			endcase

			scounter <= scounter + 1;
			state <= `EXEC;
		end

		`EXEC: begin
if (debug & alu_ack) $fdisplay(32'h80000002, "EXEC: left %x right %x dest %d eoi %d ", alu_left, alu_right, s_dest, s_eoi);
if (debug & alu_ack) $fdisplay(32'h80000002, "wb %d iwb %d wb2 %d iwb2 %d wrok %d aluz %d\r", s_wback, i_wback, s_wback2, i_wback2, wr_cond_ok, alu_zero);
if (debug & alu_ack) $fdisplay(32'h80000002, "EXEC2: stb %d ack %d enable %d stepoff %d wrcond %d wipr %d\r", alu_stb, alu_ack, s_enable, s_stepoff, wr_cond_ok, s_wipr);
//if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "EXECSTEP: sc %d left %x right %x res %x xres %x\r", scounter-8'h01, alu_left, alu_right, alu_res, xxres);

			case (s_dest)
			0: ;
			1: { psl_is, cur_mod, prv_mod, psl_ipl, psw } <=
			    { alu_res[26], alu_res[25:24], 
			      alu_res[23:22], alu_res[20:16],
			      alu_res[7:0] };
			2: argd[0] <= alu_res;
			3: argd[1] <= alu_res;
			4: arg[0] <= alu_res;
			5: arg[1] <= alu_res;
			6: arg[2] <= alu_res;
			7: arg[3] <= alu_res;
			8: begin
				argp[0] <= alu_res;
				argp_regnum[0] <= alu_res[3:0];
				argp_size[0] <= `O_LONG;
				argp_isreg[0] <= &alu_res[31:30];
			end
			9: begin
				argp[1] <= alu_res;
				argp_regnum[1] <= alu_res[3:0];
				argp_size[1] <= `O_LONG;
				argp_isreg[1] <= &alu_res[31:30];
			end
			10: begin
				cur_reg_num_save <= alu_res[3:0];
				ipr_addr <= alu_res[5:0];
				greg_wregnum <= alu_res[3:0];
			end
			11: cpu_addr <= alu_res;
			12: begin
				ipr_wdata <= alu_res; 
				cpu_wdata <= alu_res;
				greg_wbdata <= alu_res;
				cpu_size <= `O_LONG;
				cpu_size <= `O_LONG;
			end
			default: ;
			endcase

			if ((wr_cond_ok && s_wback) || i_wback) begin
				writeback <= 1;
			end
			if ((wr_cond_ok && s_wback2) || i_wback2) begin
				writeback2 <= 1;
			end
			if (s_savc)
				Ctmp <= alu_cry;
			if (s_savnz) begin
				Ntmp <= alu_neg;
				Ztmp <= alu_zero;
			end
			if (alu_ack) begin
`ifdef notyet
				case (sr_cyc)
				0: state <= `PREEXEC;
				1: state <= `ENDINST;
				2: state <= `READREG;
				3: state <= `WRITEREG;
				4: state <= `READMEM;
				5: state <= `WRITEMEM;
				6: state <= `READIPR;
				7: state <= `WRITEIPR;
				endcase



				if (wrmem)
					state <= `WRITEMEM;
				else if (rdmem)
					state <= `READMEM;
				else
`endif
				if (s_wreg) begin
					state <= `S_WREG;
					wregstate <= `WREG_PREEXEC;
				end else if (s_wmem) begin
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_PREEXEC;
					cpu_pmem <= 1; // XXX
				end else if (s_wipr) begin
					state <= `WRITEIPR;
				end else if (s_rmem) begin
					state <= `S_READMEM;
					rmemstate <= `RMEM_PREEXEC;
				end else if (s_eoi) begin
					state <= `ENDINST;
				    /* regval for sizes less than long XXX */
					cur_reg_num_save <= argp_regnum[0];
				end else
					state <= `PREEXEC;
			end

			if (wr_cond_ok && s_goto)
				scounter <= s_const[7:0];
			if (wr_cond_ok && s_resopflt)
				resopflt <= 1;

			/* copy third arg XXX */
			if (i_move2)
				argd[1] <= arg[2];
		end

		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`ENDINST: begin
if (debug) $fdisplay(32'h80000002, "ENDINST: pc %x argd[0] %x argpsz[0] %d arg1p %x isreg %d regno %d wb %d\r", curpc, argd[0], argp_size[0], argp[0], argp_isreg[0], argp_regnum[0], writeback);
if (debug) $fdisplay(32'h80000002, "ENDINST: pc %x argd[1] %x arg2p %x isreg %d regno %d wb %d\r", curpc, argd[1], argp[1], argp_isreg[1], argp_regnum[1], writeback2);
// if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "INSV END: argd0 %x argd1 %x\r", argd[0], argd[1]);
			state <= `S_FETCH;

			if (resopflt) begin
				scounter <= 0;
				state <= `PREEXEC;
				resopflt <= 0;
			end else if (anyfault) begin
				haltpos <= 5;
				state <= `S_HALT;
			end else if (writeback) begin
				if (argp_isreg[0]) begin
if (debug) $fdisplay(32'h80000002, "WB0: argd0 %x size %d curreg %x curval %x\r", argd[0], argp_size[0], cur_reg_num_save, cur_reg_val);
					case (argp_size[0])
					`O_BYTE: greg_wbdata <= 
					    { cur_reg_val[31:8], argd[0][7:0] };
					`O_WORD: greg_wbdata <= 
					    { cur_reg_val[31:16],argd[0][15:0]};
					default: greg_wbdata <= argd[0];
					endcase
					greg_wregnum <= argp_regnum[0];
					cur_reg_num_save <= argp_regnum[0];
					if (writeback2)
						wregstate <= `WREG_xENDINST;
					else
						wregstate <= `WREG_FETCH;
					cur_reg_num_save <= argp_regnum[1];
					state <= `S_WREG;
				end else begin
					cpu_addr <= argp[0];
					cpu_wdata <= argd[0];
					cpu_size <= argp_size[0];
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_xENDINST;
				end
				writeback <= 0;
				if (argp_size[0] == `O_QUAD)
					writeback2 <= 1; // XXX hack
			end else if (writeback2) begin
				if (argp_isreg[1]) begin
					case (argp_size[1])
					`O_BYTE: greg_wbdata <= 
					    { cur_reg_val[31:8], argd[1][7:0] };
					`O_WORD: greg_wbdata <= 
					    { cur_reg_val[31:16],argd[1][15:0]};
					default: greg_wbdata <= argd[1];
					endcase
					greg_wregnum <= argp_regnum[1];
					cur_reg_num_save <= argp_regnum[1];
					wregstate <= `WREG_FETCH;
					state <= `S_WREG;
				end else begin
					cpu_addr <= argp[1];
					cpu_wdata <= argd[1];
					cpu_size <= argp_size[1];
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_xENDINST;
				end
				writeback2 <= 0;
			end
			if (i_setnz) begin
				psw[`PSL_N] <= Ntmp;
				psw[`PSL_Z] <= Ztmp;
			end
			if (i_clv)
				psw[`PSL_V] <= 0;
			if (i_clc)
				psw[`PSL_C] <= 0;
			if (i_setc)
				psw[`PSL_C] <= Ctmp;
			if (step)
				delay_halt <= 1;
			cpu_pmem <= 0;
		end

		/*
		 * Push an emulate frame onto stack.
		 * cur_reg_num_save is 14 (stack)
		 * cur_reg_val contains stack pointer value.
		 */
		`MCODE: begin
$fdisplay(32'h80000002, "MCODE: ctr %d mc_rv %x\r", mcodectr, mc_rv);
			mcodectr <= mcodectr - 1;
			greg_wregnum <= `REG_SP;
			greg_wbdata <= cur_reg_val - 4;
			cpu_addr <= cur_reg_val - 4;
			wregstate <= `WREG_WRITEMEM;
			wmemstate <= `WMEM_MCODE;
			state <= `S_WREG;
			cpu_wdata <= mc_rv;
			if (mcodectr == 1) begin
				curpc <= 32'hf0000000;
				state <= `S_FETCH;
			end
		end

		/*
		 * Set new stack based on ivec (in argd[0]).
		 */

		`S_FILLUP: begin
// $fdisplay(32'h80000002, "S_FILLUP: addr %x acki %d isvalid %d dati %x\r\n", { curpc[31:2], 2'b00 }, cpu_acki, isvalid, CPU_DAT_I);
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
				case (fupstate)
				`FUP_FETCH: state <= `S_FETCH;
				`FUP_ASETUP: state <= `ASETUP;
				`FUP_ARG_GETBWL: state <= `ARG_GETBWL;
				default: state <= `S_HALT;
				endcase
			end
			if (mcheck) begin
				state <= `S_HALT;
				haltpos <= `HALT_MCHECK;
			end
		end

		`S_WREG: begin 
// $fdisplay(32'h80000002, "S_WREG: regnum %x wbdata %x\r\n", greg_wregnum, greg_wbdata);
			if (greg_wregnum == `REG_PC)
				curpc <= greg_wbdata;
			case (wregstate)
			`WREG_WRITEMEM: state <= `S_WRITEMEM;
			`WREG_PREEXEC: state <= `PREEXEC;
			`WREG_FETCH: state <= `S_FETCH;
			`WREG_ARG_INDIR: state <= `ARG_INDIR;
			`WREG_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
		end

		`WRITEIPR: begin
			state <= `PREEXEC;
// $fdisplay(32'h80000002, "WIPR: wdata %x ipr %d\r", ipr_wdata, ipr_addr);
		end

		`S_WRITEMEM: begin
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_WRITEMEM2;
		end

		`S_WRITEMEM2: if (cpu_acki) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			case (wmemstate)
			`WMEM_MCODE: state <= `MCODE;
			`WMEM_PREEXEC: state <= `PREEXEC;
			`WMEM_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
			if (mcheck)
				state <= `S_HALT;
		end

		`S_READMEM: begin
			cpu_write <= 0;
			cpu_stb <= 1;
			state <= `S_READMEM2;
		end

		`S_READMEM2: if (cpu_acki) begin
			notrash <= 0;
if (debug) $fdisplay(32'h80000002, "S_READMEM2: addr %x dat %x\r", cpu_addr, CPU_DAT_I);
			if (notrash == 0)
				OA <= CPU_DAT_I;
			OP <= CPU_DAT_I;
			rmem_dat <= CPU_DAT_I;
			cpu_stb <= 0;
			case (rmemstate)
			`RMEM_ARG_INDIR: state <= `ARG_INDIR;
			`RMEM_PREEXEC: state <= `PREEXEC;
			`RMEM_ARG_READ: state <= `ARG_READ;
			`RMEM_xARGEND: state <= `ARGEND;
			`RMEM_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
			if (mcheck) begin
				state <= `S_HALT;
				haltpos <= `HALT_MCHECK;
			end
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end

endmodule

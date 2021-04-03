/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none

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
`define S_ENDINST	4
`define S_READMEM	5
`define S_READMEM2	8
`define S_WRITEMEM	9
`define S_WRITEMEM2	10
`define S_EXECUTE	11
`define MTPR		12
`define S_DECODE	16
`define MFPR		17
`define S_TXCS_R	18
`define S_GETVEC	24
`define S_GETVEC1	25
`define S_GETVEC2	26
`define S_GETVEC3	27
`define S_MCHECK	28
`define S_MCHECK1	29
`define S_MCHECK2	30
`define S_SETSTK	31
`define S_SETSTK1	32
`define S_SETSTK2	33
`define S_SETSTK3	34
`define S_MCHECK3	35
`define S_PUSH		36
`define S_PUSH2		37
`define ASETUP		41
`define ARG_GETBWL	42
`define ARG_ADDTO	43
`define ARG_INDIR	44
`define ARG_READ	45
`define ARGEND		46
`define EXECUTE		47
`define ENDINST		48

/* WREG return states */
`define	WREG_HALT	0
`define	WREG_OAREAD	1
`define	WREG_ARGEND	2
`define	WREG_POSTINC	3
`define	WREG_INDOA	4
`define	WREG_FETCH	5
//`define	WREG_JSB2	6
`define	WREG_ENDINST	7
`define	WREG_MCHECK2	8
`define	WREG_ARG_INDIR	9
`define	WREG_xENDINST	10

/* READMEM return states */
`define	RMEM_INDOA	0
`define	RMEM_ARGEND	1
//`define	RMEM_RSB2	2
// `define	RMEM_TXCS_R	3
`define	RMEM_ARG_READ	4
`define	RMEM_xARGEND	5
`define	RMEM_xENDINST	6

/* WRITEMEM return states */
`define	WMEM_ENDINST	0
//`define	WMEM_TXDB_W	1
`define	WMEM_PUSH2	2
`define	WMEM_xENDINST	3

/* FILLUP return states */
`define	FUP_FETCH	0
`define	FUP_ARG		1
`define	FUP_RDCDATA	2
`define	FUP_ASETUP	3
`define	FUP_ARG_GETBWL	4

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
	 * arg1/2 are arg value read. (if R|A)
	 * arg1p is pointer to the destination (if memory and W) 
	 * argd1 is destination for value.
	 */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSED */
	reg [31:0]	arg1, arg2, arg3, arg4, argd1, argd2, arg1p, arg2p;
	reg		num_arg, num_argd, num_argp;
	reg		arg1p_isreg, arg2p_isreg;
	reg [3:0]	arg1p_regnum, arg2p_regnum;
	reg [1:0]	arg1p_size, arg2p_size;
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSED */

	assign ipr_regraddr = halted ? CON_ADR_I[3:0] : arg1[3:0];
	assign ipr_regwaddr = halted ? CON_ADR_I[3:0] : arg2[3:0];
	assign ipr_wdata = halted ? CON_DAT_I : arg1;

	reg [`STATBITS-1:0]	state;
	reg [3:0]	wregstate;
	reg [2:0]	rmemstate, wmemstate, fupstate;
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
	reg [7:0]	cur_inst;
	reg [7:0]	cur_byte;



	reg [3:0]	regnum;

	reg		isindex, writeback, writeback2;
	reg [31:0]	OA, IA, OP, OAt;
	reg		OA_isreg;
	reg [3:0]	OA_regnum;



	reg [31:0] curpc, oldpc, oldpsl;
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
	    	state == `ASETUP ? cur_reg_num :
	    	state == `S_ENDINST ? arg1p_regnum : cur_reg_num_save;

	always @(posedge clk)
		if (state == `S_WREG)
			general_reg[greg_wregnum] <= greg_wbdata;
	assign cur_reg_val =
	    (greg_addr == `REG_PC ? curpc : general_reg[greg_addr]);

	/* "microcode" */
	wire [7:0]	i_argoff, a_argoff, a_arg, cur_mux;
	wire		i_enable, i_hasargs, i_emul, i_dohalt, i_newflow;
	wire		a_enable, a_emul, a_last, i_move2, i_wback2;
	wire		i_useadd, i_wback, i_usexor, i_usemtpr, i_usemfpr;
	wire		i_isspsw, i_iscpsw, i_setnz, i_clv, i_clc;
	wire		i_bispsw, i_bicpsw, i_movpsl, i_usesub, i_useand;
	wire		i_usebis, i_usebic;
	wire		arg_aR, arg_aW, arg_aA;
	wire [2:0]	a_argcode;
	wire [1:0]	a_argsz;
	wire [2:0]	a_rargno;
	wire		a_wargno;
	wire [3:0]	i_pswbits;
	reg [7:0]	acounter, curarg;

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
		.i_newflow(i_newflow),

		.i_useadd(i_useadd),
		.i_usexor(i_usexor),
		.i_usemtpr(i_usemtpr),
		.i_usemfpr(i_usemfpr),
		.i_usesub(i_usesub),
		.i_useand(i_useand),
		.i_usebis(i_usebis),
		.i_usebic(i_usebic),
		.i_wback(i_wback),

		.i_pswbits(i_pswbits),
		.i_isspsw(i_isspsw),
		.i_iscpsw(i_iscpsw),
		.i_bispsw(i_bispsw),
		.i_bicpsw(i_bicpsw),
		.i_setnz(i_setnz),
		.i_clv(i_clv),
		.i_clc(i_clc),

		.i_movpsl(i_movpsl),

		.i_move2(i_move2),
		.i_wback2(i_wback2),

		.i_dohalt(i_dohalt),

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
		case (arg_reg)
		1'b0: arg_rv = OP;
		1'b1: arg_rv = cra;
		endcase

	always @*
		case (a_argsz)
		`O_BYTE: cra = { {24{cur_reg_val[7]}}, cur_reg_val[7:0] };
		`O_WORD: cra = { {16{cur_reg_val[15]}}, cur_reg_val[15:0] };
		`O_LONG: cra = cur_reg_val;
		`O_QUAD: cra = 0;
		endcase


	/*
	 * evaluation definitions.
	 */
	reg		calc_vnzc, set_vnz_dest, clear_c_dest, set_c_cmp;

	/*
	 * Program counter mgmt. curpc is the "live" version. greg[15] is
	 * only updated between instructions.
	 */
	reg set_branch_pc, delay_halt;
	wire [31:0] pc_plus_1;
	assign pc_plus_1 = curpc + 1;

//reg debug;
//initial debug = 0;
//	always @(posedge clk)
//		if (curpc == 32'hbde0)
//			debug <= 1;
wire debug;
assign debug = 0;

	/* console communications */
	wire ref_greg_read, ref_greg_write, ipr_greg_read, ipr_greg_write;
	assign ref_greg_read = CON_STB_I & (CON_WE_I == 0) &con_reg;
	assign ref_greg_write = CON_STB_I & CON_WE_I & con_reg;
	assign ipr_greg_read = CON_STB_I & (CON_WE_I == 0) &con_ipr;
	assign ipr_greg_write = CON_STB_I & CON_WE_I & con_ipr;

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
				5'h1f: con_dat_o_reg <= psl;
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
				haltpos <= 6;
			end else if (isvalid) begin
if (debug) $fdisplay(32'h80000002, "FETCH: pc %x curbyte %x\r", curpc, cur_byte);
				/* put insbyte in decode reg */
				cur_inst <= cur_byte;
				num_arg <= 0;
				num_argd <= 0;
				num_argp <= 0;
				cur_arg_number <= 0;
				isindex <= 0;
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
if (debug) $fdisplay(32'h80000002, "S_DECODE: i_hasargs %d\r", i_hasargs);
			acounter <= i_argoff;
			if (i_dohalt) begin
				state <= `S_HALT;
				haltpos <= 1;
			end else if (i_hasargs == 0) // XXX emul
				state <= `S_EXECUTE;
			else
				state <= `ASETUP;
		end

		/*
		 * Argument "loop".  acounter updated, argument directives
		 * available.
		 */
		`ASETUP: begin
if (debug) $fdisplay(32'h80000002, "ASETUP: a_argcode %x a_emul %d cur_byte %x a_arg %x IA %x acounter %d\r", a_argcode, a_emul, cur_byte, a_arg, IA, acounter);
			arg_rdbmsk <=
			    { {2{&cur_mux[6:5]}}, cur_mux[6], |cur_mux[6:5]};
			cur_reg_num_save <= cur_mux[3:0];
			OAt <= 0;
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
					state <= `ARGEND;
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
				OAt <= { 28'hfffffff, neg_arg_size };
			if (arg_adec)
				arg_radd <= { 1'b1, neg_arg_size };
			if (arg_ainc)
				arg_radd <= { 1'b0, pos_arg_size };
			if (arg_aincd)
				arg_radd <= 5'd4;
			if (arg_sh[0]) begin
				if (arg_rdbmsk[0]) begin
if (debug)$fdisplay(32'h80000002, "ARG_GETBWL2: isvalid %x OAt %x cur_byte %x\r", isvalid, OAt, cur_byte);
					if (isvalid) begin
						OAt <= { cur_byte, OAt[31:8] };
						curpc <= pc_plus_1;
					end else begin
						state <= `S_FILLUP;
						fupstate <= `FUP_ARG_GETBWL;
					end
				end else begin
					OAt <= { {8{OAt[31]}}, OAt[31:8] };
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
if (debug)$fdisplay(32'h80000002, "ARG_ADDTO: OAt %x cur_reg_val %x cur_reg_num_save %d\r", OAt, cur_reg_val, cur_reg_num_save);
			OA <= OAt + cur_reg_val;
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
			if (arg_indir) begin
				cpu_addr <= OA;
				cpu_size <= `O_LONG;
				notrash <= 0;
				state <= `S_READMEM;
				rmemstate <= `RMEM_ARG_READ;
			end else
				state <= `ARG_READ;
		end

		`ARG_READ: begin
if (debug)$fdisplay(32'h80000002, "ARG_READ: OA %x IA %x cur_byte %x curarg %x\r", OA, IA, cur_byte, curarg);
			state <= `ARGEND;
			if (arg_lit) begin
				OP <= { 24'b0, curarg};
			end else if (arg_reg) begin
				OP <= cur_reg_val;
			end else if (arg_aR) begin
				cpu_addr <= OA + IA;
				cpu_size <= a_argsz;
				notrash <= 1;
				state <= `S_READMEM;
				rmemstate <= `RMEM_xARGEND;
			end else
				OP <= OA + IA;
		end

		/*
		 * Store the argument results in their next slot.
		 */
		`ARGEND: begin
if (debug) $fdisplay(32'h80000002, "ARGEND: OP %x OA %x arg_rv %x acounter %d isreg %d regnum %d argsz %d\r", OP, OA, arg_rv, acounter, OA_isreg, OA_regnum, arg_size);
if (debug) $fdisplay(32'h80000002, "ARGEND: a_rargno %d a_wargno %d arg_aR %d arg_aA %d arg_aW %d\r\n", a_rargno, a_wargno, arg_aR, arg_aA, arg_aW);
			if (arg_aR|arg_aA) begin
				case (a_rargno)
				3'b000: arg1 <= arg_rv;
				3'b001: arg2 <= arg_rv;
				3'b010: arg3 <= arg_rv;
		//		2'b11: arg2 <= OP; // XX
				default: ;
				endcase
			end

			if (arg_aW) begin
				if (a_wargno == 0) begin
					arg1p <= OA;
					arg1p_isreg  <= OA_isreg;
					arg1p_regnum <= OA_regnum;
					arg1p_size <= a_argsz;
					num_argp <= 1;
				end
				if (a_wargno == 1) begin
					arg2p <= OA;
					arg2p_isreg  <= OA_isreg;
					arg2p_regnum <= OA_regnum;
					arg2p_size <= a_argsz;
				end
			end
			if (a_last == 0)
				state <= `ASETUP;
			else if (i_usemtpr)
				state <= `MTPR;
			else if (i_usemfpr)
				state <= `MFPR;
			else
				state <= `EXECUTE;
			OA_isreg <= 0;
			IA <= 0;
		end

		`EXECUTE: begin
			state <= `ENDINST;
if (debug) $fdisplay(32'h80000002, "EXECUTE: pc %x arg1 %x arg2 %x useadd %d wback %d\r", curpc, arg1, arg2, i_useadd, i_wback);
if (debug) $fdisplay(32'h80000002, "EXECUTE2: isspsw %d iscpsw %d pswbits %x bis %d bic %d\r", i_isspsw, i_iscpsw, i_pswbits, i_usebis, i_usebic);
			writeback <= i_wback;
			writeback2 <= i_wback2;
			if (i_useadd)
				{ Ctmp, argd1 } <=
				    { 1'b0, arg1 } + { 1'b0, arg2 };
			if (i_usesub)
				{ Ctmp, argd1 } <=
				    { 1'b0, arg1 } - { 1'b0, arg2 };
			if (i_useand)
				argd1 <= arg1 & arg2;
			if (i_usexor)
				argd1 <= arg1 ^ arg2;
			if (i_usebis)
				argd1 <= arg1 | arg2;
			if (i_usebic)
				argd1 <= ~arg1 & arg2;
			if (i_isspsw && (|(psw[3:0] & i_pswbits)) == 0)
				writeback <= 0;
			if (i_iscpsw && (|(psw[3:0] & i_pswbits)))
				writeback <= 0;
			if (i_bicpsw)
				psw <= psw & ~arg1[7:0];
			if (i_bispsw)
				psw <= psw | arg1[7:0];
			if (i_movpsl)
				argd1 <= psl;
			if (i_move2)
				argd2 <= arg3;
		end

		/*
		 * Simple operations. 
		 * We cannot end up here if an argument fault occurred.
		 */
		`S_EXECUTE: begin
if (debug) $fdisplay(32'h80000002, "S_EXECUTE: arg1p %x\r\n", arg1p);
			state <= `S_ENDINST;
			case (cur_inst)
//			`I_CMPB, `I_CMPW, `I_CMPL: begin
//				{ Ctmp, argd1 } <=
//				    { 1'b0, arg1 } - { 1'b0, arg2 };
//				set_vnz_dest <= 1;
//				set_c_cmp <= 1;
//			end
//			`I_BITL: begin
//				argd1 <= arg1 & arg2;
//				set_vnz_dest <= 1;
//			end
//			`I_BISL2, `I_BISL3: begin
//				argd1 <= arg2 | arg1;
//$fdisplay(32'h80000002, "BICL: arg1 %x arg2 %x\r\n", arg1, arg2);
//				writeback <= 1;
//				set_vnz_dest <= 1;
//			end
//			`I_BICL2, `I_BICL3: begin
//				argd1 <= arg2 & ~arg1;
//$fdisplay(32'h80000002, "BICL: arg1 %x arg2 %x\r\n", arg1, arg2);
//				writeback <= 1;
//				set_vnz_dest <= 1;
//			end
			`I_MOVL: begin
				argd1 <= arg1;
				writeback <= 1;
				set_vnz_dest <= 1;
			end
			default: begin state <= `S_HALT; haltpos <= 13; end
			endcase
		end

		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`ENDINST: begin
if (debug) $fdisplay(32'h80000002, "ENDINST: pc %x argd1 %x arg1p %x isreg %d regno %d wb %d\r", curpc, argd1, arg1p, arg1p_isreg, arg1p_regnum, writeback);
if (debug) $fdisplay(32'h80000002, "ENDINST2: greg_wback %x\r", greg_wback);
			state <= `S_FETCH;

			if (anyfault) begin
				haltpos <= 5;
				state <= `S_HALT;
		//		resopflt <= 0;
			end else if (writeback) begin
				if (arg1p_isreg) begin
if (debug) $fdisplay(32'h80000002, "WB REG: reg %x val %x size %d\r\n", arg1p_regnum, greg_wback, arg1p_size);
					greg_wbdata <= greg_wback;
					greg_wregnum <= arg1p_regnum;
					cur_reg_num_save <= arg1p_regnum;
					if (writeback2)
						wregstate <= `WREG_xENDINST;
					else
						wregstate <= `WREG_FETCH;
					state <= `S_WREG;
				end else begin
if (debug) $fdisplay(32'h80000002, "WB MEM: addr %x val %x\r\n", arg1p, argd1);
					cpu_addr <= arg1p;
					cpu_wdata <= argd1;
					cpu_size <= arg1p_size;
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_xENDINST;
				end
				writeback <= 0;
			end else if (writeback2) begin
				if (arg2p_isreg) begin
					greg_wbdata <= greg_wback;
					greg_wregnum <= arg2p_regnum;
					cur_reg_num_save <= arg2p_regnum;
					wregstate <= `WREG_FETCH;
					state <= `S_WREG;
				end else begin
					cpu_addr <= arg2p;
					cpu_wdata <= argd2;
					cpu_size <= arg2p_size;
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_xENDINST;
				end
				writeback2 <= 0;
			end
			if (i_setnz) begin
				psw[`PSL_N] <= argd1[31];
				psw[`PSL_Z] <= ~|argd1;
			end
			if (i_clv)
				psw[`PSL_V] <= 0;
			if (i_clc)
				psw[`PSL_C] <= 0;

			if (step)
				delay_halt <= 1;
			cpu_pmem <= 0;
		end




		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`S_ENDINST: begin
if (debug) $fdisplay(32'h80000002, "S_ENDINST: pc %x halted %d cont %d\r", curpc, halted, cont);
			state <= `S_FETCH;
			writeback <= 0;
			calc_vnzc <= 0;
			set_vnz_dest <= 0;
			clear_c_dest <= 0;
			set_c_cmp <= 0;

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
				wmemstate <= `WMEM_ENDINST;
			end else if (writeback) begin
// $fdisplay(32'h80000002, "WB REG: reg %x val %x\r\n", arg1p_regnum, greg_wback);
				greg_wbdata <= greg_wback;
				greg_wregnum <= arg1p_regnum;
				wregstate <= `WREG_FETCH;
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
				    ((~arg1[31] & arg2[31]) &&
				     (arg1[31] ^ argd1[31]));
			end
			if (clear_c_dest)
				psw[`PSL_C] <= 0;
			if (set_c_cmp)
				psw[`PSL_C] <= (arg1 < arg2);
			if (step)
				delay_halt <= 1;
		end

		`MTPR: begin
if (debug) $fdisplay(32'h80000002, "MTPR: arg1 %x arg2 %x\r", arg1, arg2);
			state <= `ENDINST;
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
				wmemstate <= `WMEM_xENDINST;
			end
			default: resopflt <= 1;
			endcase
		end

		/*
		 * XXX check if current sp is the same
		 */
		`MFPR: begin
if (debug) $fdisplay(32'h80000002, "S_MFPR: arg1 %x arg2 %x\r\n", arg1, arg2);
			state <= `ENDINST;
			writeback <= i_wback;
			if (|arg1[31:6])
				resopflt <= 1;
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
			`IPR_RXCS, `IPR_TXCS: begin
if (debug) $fdisplay(32'h80000002, "IPR_TXCS: pmem %d \r\n", cpu_pmem);
				state <= `S_READMEM;
				rmemstate <= `RMEM_xENDINST;
				if (arg1[1])
					cpu_addr <= 32'h20001f74;
				else
					cpu_addr <= 32'h20001f70;
				cpu_size <= `O_LONG;
				cpu_pmem <= 1;
			end
			`IPR_SID: argd1 <= 32'h0A000006;
			default: resopflt <= 1;
			endcase
		end

		/*
		 * Got a machine check.
		 * Fetch SCB mcheck address and jump there.
		 */
		`S_MCHECK: begin
			arg1 <= `VEC_MCHECK;
			state <= `S_GETVEC;
		//	haltpos <= 8;
		end

		/*
		 * Address from SCB in argd1. Do stack change.
		 * (mcheck should always be served on the interrupt stack)
		 */
		`S_MCHECK1: begin
			arg2 <= 0;
			state <= `S_SETSTK;
			wregstate <= `WREG_MCHECK2;
		end

		`S_MCHECK2: begin
	//		state <= `S_PUSH;
			state <= `S_HALT;
			cur_reg_num_save <= `REG_SP;
	//		fillstate <= `S_MCHECK2;
			arg2 <= arg2 + 1;
			case (arg2[3:0])
			4'd0: cpu_wdata <=
	{ 5'd0, psl_is, cur_mod, prv_mod, 1'b0, psl_ipl, 8'b0, psw };
			4'd1: cpu_wdata <= oldpc;
			4'd12: cpu_wdata <= 32'h28;
			default: cpu_wdata <= 0;
			endcase
	//		if (arg2[3:0] == 4'd12)
	//			fillstate <= `S_MCHECK3;
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
			wmemstate <= `WMEM_PUSH2;
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
				if (mcheck)
					state <= `S_MCHECK;
				else
					case (fupstate)
					`FUP_FETCH: state <= `S_FETCH;
		//			`FUP_ARG: state <= `S_ARG;
		//			`FUP_RDCDATA: state <= `S_RDCDATA;
					`FUP_ASETUP: state <= `ASETUP;
					`FUP_ARG_GETBWL: state <= `ARG_GETBWL;
					default: state <= `S_HALT;
					endcase
			end
		end

		`S_WREG: begin 
// $fdisplay(32'h80000002, "S_WREG: regnum %x wbdata %x\r\n", greg_wregnum, greg_wbdata);
			if (greg_wregnum == `REG_PC)
				curpc <= greg_wbdata;
			case (wregstate)
//			`WREG_ARGEND: state <= `S_ARGEND;
			`WREG_FETCH: state <= `S_FETCH;
			`WREG_ENDINST: state <= `S_ENDINST;
			`WREG_MCHECK2: state <= `S_MCHECK2;
			`WREG_ARG_INDIR: state <= `ARG_INDIR;
			`WREG_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
		end
		
		`S_WRITEMEM: begin
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_WRITEMEM2;
		end

		`S_WRITEMEM2: if (cpu_acki) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			if (mcheck)
				state <= `S_MCHECK;
			else
				case (wmemstate)
				`WMEM_ENDINST: state <= `S_ENDINST;
//				`WMEM_TXDB_W: state <= `S_TXDB_W;
				`WMEM_PUSH2: state <= `S_PUSH2;
				`WMEM_xENDINST: state <= `ENDINST;
				default: state <= `S_HALT;
				endcase
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
			argd1 <= CPU_DAT_I;
			cpu_stb <= 0;
			if (mcheck)
				state <= `S_MCHECK;
			else
				case (rmemstate)
//				`RMEM_INDOA: state <= `S_INDOA;
//				`RMEM_ARGEND: state <= `S_ARGEND;
//				`RMEM_RSB2: state <= `S_RSB2;
//				`RMEM_TXCS_R: state <= `S_TXCS_R;
				`RMEM_ARG_READ: state <= `ARG_READ;
				`RMEM_xARGEND: state <= `ARGEND;
				`RMEM_xENDINST: state <= `ENDINST;
				default: state <= `S_HALT;
				endcase
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
			state <= `S_MCHECK1;
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end

endmodule

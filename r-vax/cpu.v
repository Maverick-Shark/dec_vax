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

`ifdef DBGCNT
	input [7:0]	dcount,
`endif

	output		tto_tx,
	input		tti_rx,
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
	wire [31:0]	ipr_regwdata;
	reg [5:0]	ipr_addr;
	reg [31:0]	ipr_wdata;
	reg		ipr_write;
	reg [`STATBITS-1:0]	state;

	always @(posedge clk)
		if (ipr_write || state == `WRITEIPR)
			ipr_reg[ipr_regaddr] <= ipr_regwdata;

	reg [31:0]	ipr_val;
	wire [31:0]	icr, ipr_val_tmp;
	wire		iccs_err, iccs_int, iccs_ie, iccs_run;
	wire		txcs_rdy, txcs_ie;
	wire		rxcs_rdy, rxcs_ie;
	wire [7:0]	rxdb;

	assign ipr_val_tmp = ipr_reg[ipr_regaddr];

	always @(ipr_regaddr, icr, ipr_val_tmp,
	    iccs_err, iccs_int, iccs_ie, iccs_run)
		case (ipr_regaddr)
		`IPR_ICR: ipr_val = icr;
		`IPR_ICCS: ipr_val =
		    { iccs_err, 23'b0, iccs_int, iccs_ie, 5'b0, iccs_run };
		`IPR_TXCS: ipr_val = { 24'b0, txcs_rdy, txcs_ie, 6'b0 };
		`IPR_RXCS: ipr_val = { 24'b0, rxcs_rdy, rxcs_ie, 6'b0 };
		`IPR_RXDB: ipr_val = { 24'b0, rxdb };
		default: ipr_val = ipr_val_tmp;
		endcase

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
	reg [1:0]	argp_size[1:0];
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
	reg		arg_read_step1, arg_read_step2;
	reg [31:0]	OA, IA, OP, OPu, OAu;
	reg [31:0]	getbwl_OA, addto_OA, indir_OA;
	reg		OA_isreg;
	reg [3:0]	OA_regnum;
	wire [31:0]	arg_read_add;

	reg [31:0] curpc, oldpc, oldpsl;
	wire [3:0] cur_reg_num;
/* verilator lint_off UNUSED */
	reg [3:0] cur_reg_num_save;
/* verilator lint_on UNUSED */
	assign cur_reg_num = cur_byte[3:0];
	assign arg_read_add = indir_OA + IA + { arg_read_step1 ? 32'h4 : 32'b0 };

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
	wire [31:0]	mc_rv_tmp, mc_rv_tmp2;
	assign mc_rv_tmp = argp_isreg[mcodectr[0]] ?
	    ~{ 28'b0, argp_regnum[mcodectr[0]] } : argp[mcodectr[0]];
	assign mc_rv_tmp2 = arg[mcodectr[1:0]];

	always @(mcodectr, psl, curpc, oldpc, cur_inst,
	    mc_rv_tmp, mc_rv_tmp2)
		casez (mcodectr)
		4'd13: mc_rv = psl;
		4'd12: mc_rv = curpc;
		4'b101?: mc_rv = mc_rv_tmp;
		4'b01??: mc_rv = mc_rv_tmp2;
		4'b0011: mc_rv = oldpc;
		4'b0010: mc_rv = { 24'b0, cur_inst };
		default: mc_rv = 0;
		endcase

	reg Ctmp, Ntmp, Ztmp, Vtmp;

	/*
	 * Faults.
	 */
	reg manhalt;
	reg [6:0] mchk_cnt;
	wire isvalid, anyfault;
	assign halted = (state == `S_HALT) || manhalt;
	assign isvalid = (itag[31:2] == curpc[31:2]) && ivalid;
	assign anyfault = resinflt | resadflt | resopflt | mcheck;

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
	wire [31:0] cur_reg_val;
	assign cur_reg_val =
	    (greg_addr == `REG_PC ? curpc : general_reg[greg_addr]);

	/* "microcode" */
	wire [7:0]	i_argoff, a_argoff, a_arg, cur_mux;
	wire		i_enable, i_hasargs, i_emul, i_dohalt;
	wire		a_enable, a_emul, a_last, i_move2, i_wback2;
	wire		i_wback, i_use8, i_use16;
	wire		i_setnz, i_clv, i_clc, i_setc, i_setcmpnz, i_setv;
	wire		arg_aR, arg_aW, arg_aA;
	wire [2:0]	a_argcode;
	wire [1:0]	a_argsz;
	wire [2:0]	a_rargno;
	wire		a_wargno;
	reg [7:0]	acounter, curarg;

	wire		s_eoi;
	wire		s_nzcond, s_zcond, s_wback, s_savc, s_savnz, s_savv;
	wire		s_nncond, s_ncond, s_wback2, s_goto, s_rmem, s_phys;
	wire		s_resopflt, s_wipr, s_wmem, s_wreg, s_use8, s_use16;
	wire [1:0]	s_size;
	wire [3:0]	s_dest;
	wire [9:0]	i_stepoff;
	wire [3:0]	s_op, s_left, s_right;
	wire [15:0]	s_const, s_addr;
	reg [9:0]	scounter, s_stepoff;
	reg		s_enable;

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

		.i_use8(i_use8),
		.i_use16(i_use16),
		.i_wback(i_wback),

		.i_setcmpnz(i_setcmpnz),
		.i_setnz(i_setnz),
		.i_clv(i_clv),
		.i_clc(i_clc),
		.i_setc(i_setc),
		.i_setv(i_setv),


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
		.s_savv(s_savv),
		.s_use8(s_use8),
		.s_use16(s_use16),
		.s_resopflt(s_resopflt),
		.s_phys(s_phys),
		.s_size(s_size),

		.s_const(s_const),
		.s_addr(s_addr),

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

`ifdef DBGCNT
`ifndef notdef
wire debug;
assign debug = 0;
`else
reg debug;
initial debug = 0;
	always @(posedge clk)
		if (curpc == 32'h9999)
			debug <= 1;
`endif
`else
	reg		dcount = 0;
	reg		debug = 0;
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
	
	wire		alu_cry, alu_zero, alu_stb, alu_ack, alu_neg, alu_ovf;
	wire [31:0]	alu_res, alu_ures;
	reg [31:0]	alu_right, alu_left, alu_upper_res;
	assign alu_stb = (state == `EXEC);

	alu alu(
		.clk(clk),

		.op(s_op),
		.left(alu_left),
		.right(alu_right),
		.stb(alu_stb),
		.ack(alu_ack),

		.neg(alu_neg),
		.ovf(alu_ovf),
		.use8(s_use8|i_use8),
		.use16(s_use16|i_use16),
		.cry(alu_cry),
		.zero(alu_zero),
		.ures(alu_ures),
		.result(alu_res)
	);

	/* OK to do conditional in microcode? */
	reg		doing_intr;
	wire		wr_cond_ok;
	assign wr_cond_ok = alu_ack &&
	    ((s_nzcond == 0 && s_zcond == 0 && s_ncond == 0 && s_nncond == 0) ||
	    (s_zcond && alu_zero) || (s_nzcond && alu_zero == 0) ||
	    (s_ncond && alu_neg) || (s_nncond && alu_neg == 0));

	wire [3:0]	vecoff;
	wire		intrq;
	assign vecoff =
		mcheck ? 1 :
		resopflt ? 2 :
		intrq ? 3 :
		0;

	always @* begin
		case (state)
		`S_DECODE: begin
			s_stepoff = i_stepoff;
			s_enable = 1;
		end
		`ENDINST: begin
			s_stepoff = { 6'b0, vecoff };
			s_enable = anyfault | intrq;
		end
		`EXEC: begin
			s_stepoff = (wr_cond_ok && s_goto) ?
			    s_addr[9:0] : scounter;
			s_enable = alu_ack;
		end
		default: begin
			s_stepoff = 10'b0;
			s_enable = 0;
		end
		endcase
	end

	/*
	 * Deal with interrupt priority.
	 * Load the interrupt request lines into FFs here as well.
	 */
	reg [15:0]	hwint, swint;
	wire [4:0]	intlvl;
	wire		intrq18, intrq14;
	wire		tx_intreq, rx_intreq;

	assign intrq14 = tx_intreq | rx_intreq;

	always @(posedge clk)
		hwint <= { 7'b0, intrq18, 3'b0, intrq14, 4'b0 };
	always @(posedge clk)
		if ((ipr_write || state == `WRITEIPR) &&
		    (ipr_regaddr == `IPR_SISR))	// listen to IPR writes
			swint <= { ipr_regwdata[15:1], 1'b0 };

//reg lastintrq;
//always @(posedge clk) begin
//	if (lastintrq != intrq18)
//$fdisplay(32'h80000002, "INTRQ changed: last %x intr %x\n", lastintrq, intrq18);
//	lastintrq <= intrq18;
//end

	intrpt intrpt(
		.intl({ hwint, swint }),
		.ipl(psl_ipl),
		.intrq(intrq),
		.intlvl(intlvl)
	);

//reg intrqplain;
//always @(posedge clk) begin
//	if (intrqplain != intrq)
//$fdisplay(32'h80000002, "INTRQ plain: plain %x intr %x ipl %x\n", intrqplain, intrq, psl_ipl);
//	intrqplain <= intrq;
//end
	/*
	 * The interval clock.
	 */
	wire	wrnicr, wriccs;
	assign wrnicr = (ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_NICR);
	assign wriccs = (ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_ICCS);

	intclk intclk(
		.clk(clk),
		.intrq(intrq18),

		.icr(icr),
		.wrnicr(wrnicr),
		.wriccs(wriccs),
		.iprdb(ipr_regwdata),

		.err_o(iccs_err),
		.int_o(iccs_int),
		.ie_o(iccs_ie),
		.run_o(iccs_run)

	);

	/*
	 * Write to console
	 */
	wire wrtxcs, wrtxdb;
	reg tx_intack;
	assign wrtxdb = (ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_TXDB);	// WO
	assign wrtxcs = (ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_TXCS); // RW

	constx constx(
		.clk(clk),

		.iprdb(ipr_regwdata[7:0]),
		.wrtxcs(wrtxcs),
		.wrtxdb(wrtxdb),

		.intack(tx_intack),
		.intreq(tx_intreq),

		.rdy(txcs_rdy),
		.ie(txcs_ie),

		.tto_tx(tto_tx)
	);

	/*
	 * Read from console.
	 */
	wire wrrxcs, rdrxdb;
	reg rx_intack;
	assign wrrxcs = (ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_RXCS); // RW
	assign rdrxdb = !(ipr_write || state == `WRITEIPR) &&
	    (ipr_regaddr == `IPR_RXDB); // RO
	consrx consrx(
		.clk(clk),

		.wrie(ipr_regwdata[6]),	// write interrupt enable
		.wrrxcs(wrrxcs),
		.rdrxdb(rdrxdb),

		.intack(rx_intack),
		.intreq(rx_intreq),

		.ie(rxcs_ie),		// read interrupt enable
		.rdy(rxcs_rdy),		// read ready
		.rxdb(rxdb),		// read data

		.tti_rx(tti_rx)
	);

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
if (debug) $fdisplay(32'h80000002, "FETCH: pc %x curbyte %x inslword %x pc+1 %x\r", curpc, cur_byte, inslword, pc_plus_1);
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
if (debug) $fdisplay(32'h80000002, "S_DECODE: i_hasargs %d i_emul %d pc %x\r", i_hasargs, i_emul, curpc);
			acounter <= i_argoff;
			scounter <= i_stepoff;
			if (i_dohalt) begin
				state <= `S_HALT;
				haltpos <= `HALT_INSN;
			end else if (i_hasargs == 0)
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
if (debug)$fdisplay(32'h80000002, "ARG_INDIR: addto_OA %x indir %d", addto_OA, arg_indir);
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
if (debug)$fdisplay(32'h80000002, "ARG_READ: OA %x IA %x cur_byte %x curarg %x step1 %d step2 %d", OA, IA, cur_byte, curarg, arg_read_step1, arg_read_step2);
if (debug)$fdisplay(32'h80000002, "ARG_READ2: arg_read_add %x indir_OA %x lit %d R %d reg %d", arg_read_add, indir_OA, arg_lit, arg_aR, arg_reg);
			arg_read_step1 <= 1;
			state <= `ARGEND;
			if (arg_read_step1 == 0)
				OA <= arg_read_add;
			else
				OAu <= arg_read_add;
			if (arg_lit && arg_aR) begin
				OP <= { 24'b0, curarg};
				OPu <= 0;
			end else if (arg_reg && arg_aR) begin
				if (arg_read_step1 == 0)
					OP <= cur_reg_val;
				else
					OPu <= cur_reg_val;
				cur_reg_num_save <= cur_reg_num_save +1;
				if (a_argsz == `O_QUAD && arg_read_step1 == 0)
					state <= `ARG_READ;
			end else if (arg_aR) begin
				if (arg_read_step2) begin
					OPu <= rmem_dat;
				end else if (arg_read_step1) begin
					OP <= rmem_dat;
					if (a_argsz == `O_QUAD)
						state <= `S_READMEM;
					arg_read_step2 <= 1;
				end else
					state <= `S_READMEM;
				cpu_addr <= arg_read_add;
				cpu_size <= a_argsz;
				rmemstate <= `RMEM_ARG_READ;
			end else begin
				if (arg_read_step1 == 0)
					OP <= arg_read_add;
				else
					OPu <= arg_read_add;
				if (a_argsz == `O_QUAD && arg_read_step1 == 0)
					state <= `ARG_READ; // OAu set
			end
		end

		/*
		 * Store the argument results in their next slot.
		 */
		`ARGEND: begin
if (debug) $fdisplay(32'h80000002, "ARGEND: OP %x OPu %x OA %x arg_rv %x acounter %d isreg %d regnum %d \r", OP, OPu, OA, arg_rv, acounter, OA_isreg, OA_regnum);
if (debug) $fdisplay(32'h80000002, "ARGEND: a_rargno %d a_wargno %d arg_aR %d arg_aA %d arg_aW %d\r\n", a_rargno, a_wargno, arg_aR, arg_aA, arg_aW);
			if (arg_aR|arg_aA) begin
				if (a_rargno[2])
					argd[a_rargno[0]] <= arg_rv;
				else
					arg[a_rargno[1:0]] <= arg_rv;
				if (a_argsz == `O_QUAD)
					arg[a_rargno[1:0]+1] <= OPu;
			end

			if (arg_aW) begin
				if (a_wargno == 0) begin
					argp[0] <= OA;
					argp_isreg[0]  <= OA_isreg;
					argp_regnum[0] <= OA_regnum;
					argp_size[0] <= a_argsz;
					argp[1] <= OAu;
					argp_isreg[1] <= OA_isreg;
					argp_regnum[1] <= OA_regnum + 1;
					argp_size[1] <= a_argsz;
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
//if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "INSV pos %x size %x base %x src %x pc %x\r", arg[0], arg[1], arg[2], arg[3], oldpc);
//if (cur_inst == 8'hef) $fdisplay(32'h80000002, "EXTZV pos %x size %x base %x dest %x pc %x\r", arg[0], arg[1], argp[0], argp[1], oldpc);
//if (cur_inst == 8'hed) $fdisplay(32'h80000002, "CMPZV pos %x size %x base %x dest %x pc %x\r", arg[0], arg[1], argp[0], argp[1], oldpc);
//if (cur_inst == 8'hd8) $fdisplay(32'h80000002, "ADWC arg1 %x arg2 %x psl %x dest %x pc %x\r", arg[0], arg[1], psl, argp[0], oldpc);
//if (cur_inst == 8'h7b) $fdisplay(32'h80000002, "EDIV arg1 %x arg2 %x arg3 %x psl %x", arg[0], arg[1], arg[2], psl);
//if (cur_inst == 8'h7a) $fdisplay(32'h80000002, "EMUL arg1 %x arg2 %x arg3 %x psl %x", arg[0], arg[1], arg[2], psl);
//if (cur_inst == 8'h28) $fdisplay(32'h80000002, "MOVC3 arg1 %x arg2 %x arg3 %x psl %x", arg[0], arg[1], arg[2], psl);
//if (cur_inst == 8'h28) $fdisplay(32'h80000002, "MOVC3 R8 %x", general_reg[8]);
//if (cur_inst == 8'h2c) $fdisplay(32'h80000002, "MOVC5 arg1 %x arg2 %x arg3 %x arg4 %x argd0 %x psl %x", arg[0], arg[1], arg[2], arg_rv, argd[0], psl);
//if (cur_inst == 8'h2d) $fdisplay(32'h80000002, "CMPC5 arg1 %x arg2 %x arg3 %x arg4 %x argd0 %x psl %x", arg[0], arg[1], arg[2], arg_rv, argd[0], psl);
//if (cur_inst == 8'heb) $fdisplay(32'h80000002, "FFC arg1 %x arg2 %x argp0 %x argp1 %x isreg %d psl %x", arg[0], arg[1], argp[0], arg_rv, argp_isreg[0], psl);
			end
			arg_read_step1 <= 0;
			arg_read_step2 <= 0;
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
			4'b1001: alu_left <= { 16'b0, s_const };
			4'b1010: alu_left <= ipr_val;
			4'b1011: alu_left <= cur_reg_val;
			4'b1100: alu_left <= rmem_dat;
			4'b1101: alu_left <=
			    { 11'b0, intlvl, tx_intreq, rx_intreq,
			      10'b0, Ntmp, Ztmp, Vtmp, Ctmp };
			4'b1110: alu_left <= alu_upper_res;
			default: alu_left <= 0;
			endcase

			casez (s_right)
			4'b00??: alu_right <= arg[s_right[1:0]];
			4'b010?: alu_right <= argd[s_right[0]];
//			4'b011?: alu_lright<= argp_isreg[s_right[0]] ?
//	    { 2'b11, 25'b0, argp_size[s_right[0]], argp_regnum[s_right[0]] } :
//				argp[s_right[0]];
			4'b1000: alu_right <= psl;
			4'b1001: alu_right <= { 16'b0, s_const };
//			4'b1010: alu_right <= { 27'b0, intlvl };
			default: alu_right <= 0;
			endcase

			scounter <= scounter + 1;
			state <= `EXEC;
		end

		`EXEC: begin
if (debug & alu_ack) $fdisplay(32'h80000002, "EXEC: left %x right %x dest %d eoi %d goto %d", alu_left, alu_right, s_dest, s_eoi, s_goto);
if (debug & alu_ack) $fdisplay(32'h80000002, "wb %d iwb %d wb2 %d iwb2 %d wrok %d aluz %d alun %d AN %d AZ %d AV %d AC %d", s_wback, i_wback, s_wback2, i_wback2, wr_cond_ok, alu_zero, alu_neg, alu_neg, alu_zero, alu_ovf, alu_cry);
if (debug & alu_ack) $fdisplay(32'h80000002, "EXEC2: stb %d ack %d enable %d stepoff %d wrcond %d wipr %d res %x\r", alu_stb, alu_ack, s_enable, s_stepoff, wr_cond_ok, s_wipr, alu_res);
//if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "EXECSTEP: sc %d left %x right %x res %x xres %x\r", scounter-8'h01, alu_left, alu_right, alu_res, xxres);

			case (s_dest)
			0: ;
			1: { psl_is, cur_mod, prv_mod, psl_ipl, 
			     tx_intack, rx_intack, psw } <=
			    { alu_res[26], alu_res[25:24], 
			      alu_res[23:22], alu_res[20:16],
			      alu_res[15:14], alu_res[7:0] };
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
			11: begin
				cpu_addr <= alu_res;
				cpu_size <= s_size;
			end
			12: begin
				ipr_wdata <= alu_res; 
				cpu_wdata <= alu_res;
				greg_wbdata <= alu_res;
			end
			default: ;
			endcase

			alu_upper_res <= alu_ures; // used by EMUL

			if ((wr_cond_ok && s_wback) || i_wback) begin
				writeback <= ~doing_intr;
			end
			if ((wr_cond_ok && s_wback2) || i_wback2) begin
				writeback2 <= ~doing_intr;
			end
			if (s_savv)
				Vtmp <= alu_ovf;
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
					cpu_pmem <= s_phys;
				end else if (s_wipr) begin
					state <= `WRITEIPR;
				end else if (s_rmem) begin
					state <= `S_READMEM;
					cpu_pmem <= s_phys;
					rmemstate <= `RMEM_PREEXEC;
				end else if (s_eoi) begin
					state <= `ENDINST;
				    /* regval for sizes less than long XXX */
					cur_reg_num_save <= argp_regnum[0];
				end else
					state <= `PREEXEC;
			end

			if (wr_cond_ok && s_goto)
				scounter <= s_addr[9:0];
			if (wr_cond_ok && s_resopflt)
				resopflt <= 1;

			/* copy third arg XXX */
			if (i_move2)
				argd[1] <= arg[2];
//if (resopflt)$fdisplay(32'h80000002, "EXEC: resopflt\r");
		end

		/*
		 * If any fault occurred take action, else write back (to reg)
		 * and set flags. Resulting value is always in arg[2].
		 */
		`ENDINST: begin
if (debug) $fdisplay(32'h80000002, "ENDINST: pc %x argd[0] %x argpsz[0] %d arg1p %x isreg %d regno %d wb %d\r", curpc, argd[0], argp_size[0], argp[0], argp_isreg[0], argp_regnum[0], writeback);
if (debug) $fdisplay(32'h80000002, "ENDINST: pc %x argd[1] %x argpsz[1] %d arg2p %x isreg %d regno %d wb %d\r", curpc, argd[1], argp_size[1], argp[1], argp_isreg[1], argp_regnum[1], writeback2);
//if (cur_inst == 8'hf0) $fdisplay(32'h80000002, "INSV END: argd0 %x argd1 %x\r", argd[0], argd[1]);
//if (cur_inst == 8'hef) $fdisplay(32'h80000002, "EXTZV END: argd0 %x argp0 %x pc %x\r", argd[0], argp[0], oldpc);
//if (cur_inst == 8'hed) $fdisplay(32'h80000002, "CMPZV END: argd0 %x argd1 %x pc %x\r", argd[0], argd[1], oldpc);
//if (cur_inst == 8'hd8) $fdisplay(32'h80000002, "ADWC END: argd0 %x tmpV %d pc %x\r", argd[0], Vtmp, oldpc);
//if (cur_inst == 8'h7b) $fdisplay(32'h80000002, "EDIV END: argd0 %x argd1 %x psl %x", argd[0], argd[1], psl);
//if (cur_inst == 8'h7a) $fdisplay(32'h80000002, "EMUL END: argd0 %x argd1 %x psl %x", argd[0], argd[1], psl);
//if (cur_inst == 8'h28) $fdisplay(32'h80000002, "MOVC3 END: R1 %x R3 %x psl %x", general_reg[1], general_reg[3], psl);
//if (cur_inst == 8'h2c) $fdisplay(32'h80000002, "MOVC5 END: R0 %x R1 %x R3 %x psl %x", general_reg[0], general_reg[1], general_reg[3], psl);
//if (cur_inst == 8'h2d) $fdisplay(32'h80000002, "CMPC5 END: R0 %x R1 %x R2 %x R3 %x psl %x", general_reg[0], general_reg[1], general_reg[2], general_reg[3], psl);
//if (cur_inst == 8'heb) $fdisplay(32'h80000002, "FFC END: argd1 %x psl %x", argd[1], psl);
			state <= `S_FETCH;
			doing_intr <= 0;

//if (doing_intr)
//$fdisplay(32'h80000002, "DOING INTR: i_setnz %d", i_setnz);

			if (resopflt|mcheck) begin
				scounter <= { 6'b0, vecoff };
$fdisplay(32'h80000002, "ENDINST: sc %d anyfault %d s_enable %d s_stepoff %d\r", mcheck ? 1 : resopflt ? 2 : 0, anyfault, s_enable, s_stepoff);
				state <= `PREEXEC;
				resopflt <= 0;
				writeback <= 0;
				writeback2 <= 0;
				doing_intr <= 1;
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
	//				if (writeback2)
						wregstate <= `WREG_xENDINST;
	//				else
	//					wregstate <= `WREG_FETCH;
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
	//				wregstate <= `WREG_FETCH;
					wregstate <= `WREG_xENDINST;
					state <= `S_WREG;
				end else begin
if (debug) $fdisplay(32'h80000002, "WB1: argd1 %x size %d addr %x\r", argd[1], argp_size[1], argp[1]);
					cpu_addr <= argp[1];
					cpu_wdata <= argd[1];
					cpu_size <= argp_size[1];
					state <= `S_WRITEMEM;
					wmemstate <= `WMEM_xENDINST;
				end
				writeback2 <= 0;
			end else if (intrq) begin
//$fdisplay(32'h80000002, "INTR: pc %x psl %x intlvl %x", oldpc, psl, intlvl);
//$display("INTR: pc %x psl %x intlvl %x\r", oldpc, psl, intlvl);
				doing_intr <= 1;
				scounter <= { 6'b0, vecoff };
				state <= `PREEXEC;
			end
			if (doing_intr == 0) begin
				if (i_setcmpnz) begin
					psw[`PSL_N] <= argd[0][31] ^ Vtmp;
					psw[`PSL_Z] <= Ztmp;
				end
				if (i_setnz) begin
					psw[`PSL_N] <= Ntmp;
					psw[`PSL_Z] <= Ztmp;
				end
				if (i_clv)
					psw[`PSL_V] <= 0;
				if (i_setv)
					psw[`PSL_V] <= Vtmp;
				if (i_clc)
					psw[`PSL_C] <= 0;
				if (i_setc)
					psw[`PSL_C] <= Ctmp;
			end
			if (step)
				delay_halt <= 1;
			arg_read_step1 <= 0;
			arg_read_step2 <= 0;
			OA_isreg <= 0;
			IA <= 0;
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
//if (debug) $fdisplay(32'h80000002, "FILLUP%d: addr %x acki %d isvalid %d dati %x\r\n", dcount, { curpc[31:2], 2'b00 }, cpu_acki, isvalid, CPU_DAT_I);
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
// $fdisplay(32'h80000002, "WIPR: wdata %x ipr 0x%x pc %x", ipr_wdata, ipr_addr, oldpc);
		end

		`S_WRITEMEM: begin
			cpu_write <= 1;
			cpu_stb <= 1;
			state <= `S_WRITEMEM2;
		end

		`S_WRITEMEM2: if (cpu_acki) begin
			cpu_write <= 0;
			cpu_stb <= 0;
			cpu_pmem <= 0;
//if (debug || cur_inst == 8'hed || cpu_addr == 32'h00000238 || cpu_addr == 32'h0000023c) $fdisplay(32'h80000002, "S_WRITEMEM2: addr %x dat %x pc %x size %d\r", cpu_addr, CPU_DAT_O, oldpc, cpu_size);
			case (wmemstate)
			`WMEM_MCODE: state <= `MCODE;
			`WMEM_PREEXEC: state <= `PREEXEC;
			`WMEM_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
			if (mcheck) begin
				state <= `S_HALT;
				haltpos <= `HALT_MCHECK;
			end
		end

		`S_READMEM: begin
			cpu_write <= 0;
			cpu_stb <= 1;
			state <= `S_READMEM2;
		end

		`S_READMEM2: if (cpu_acki) begin
//if (debug || cur_inst == 8'hed || cpu_addr == 32'h00000238 || cpu_addr == 32'h0000023c) $fdisplay(32'h80000002, "S_READMEM2: addr %x dat %x pc %x size %d", cpu_addr, CPU_DAT_I, oldpc, cpu_size);
//if (cpu_addr > 32'h00ffffff && cpu_addr[31:4] != 28'h20001f7) $display("S_READMEM2: addr %x pc %x", cpu_addr, curpc);
			rmem_dat <= CPU_DAT_I;
			cpu_stb <= 0;
			cpu_pmem <= 0;
			case (rmemstate)
			`RMEM_ARG_INDIR: state <= `ARG_INDIR;
			`RMEM_PREEXEC: state <= `PREEXEC;
			`RMEM_ARG_READ: state <= `ARG_READ;
			`RMEM_xARGEND: state <= `ARGEND;
			`RMEM_xENDINST: state <= `ENDINST;
			default: state <= `S_HALT;
			endcase
			if (mcheck) begin
				state <= `ENDINST;
//				state <= `S_HALT;
//				haltpos <= `HALT_MCHECK;
			end
		end

		default: begin state <= `S_HALT; haltpos <= 7; end
		endcase
	end

endmodule

/*
 * fpunit.v - the floating point unit: F_, D_, G_ and H_floating arithmetic
 * for the VAX floating point instructions (SRM chapter 3, "Floating-Point
 * Instructions"), with the results the SRM defines: the infinitely precise
 * result, normalized, then rounded by adding one at the first bit that is
 * not kept (the rounding bit) and chopping.
 *
 * The operand decoder loads the floating operands of an instruction into
 * slots S0-S2, unpacked; the microcode gives the commands and reads the
 * result, packed in the instruction's format, through internal processor
 * registers 50-5F, which MTPR and MFPR cannot reach (cpu.v and the
 * microcode).
 *
 * An unpacked number is a sign s, a true exponent e (signed, 18 bits) and a
 * 128-bit fraction f, normalized (bit 127 set) unless the number is zero:
 * the value is (-1)**s * f/2**128 * 2**e. Every format fits; H_floating,
 * with 113 fraction bits counting the hidden one, uses bits 127:15. Results
 * are developed on 128 bits and the rounding bit of each format (bit 103 F,
 * 71 D, 74 G, 14 H) comes out exact: a sum keeps the floor of the exact one
 * (the bits shifted out of a subtrahend count as a borrow), a product the
 * high half of the full product, a quotient its true bits.
 *
 * Writes:
 *	50	command (below)
 *	51-54	W0-W3: a floating operand for LD, the longwords in memory order
 *	55	IR: an integer operand (CVTIF; EMOD: the multiplier extension)
 *	58-5B	X0-X3: four longwords the microcode keeps things in
 * Reads:
 *	50	status: <0> reserved operand, <1> floating overflow, <2> floating
 *		underflow (only with PSL<FU> set), <3> divide by zero, <4>
 *		integer overflow, <5> N, <6> Z, <31> busy
 *	51-54	R packed in the format of the last command, longwords 0-3
 *	55	IR: the integer result of CVTFI and EMOD
 *	56	N and Z as a longword for the microcode's savnz: 80000000
 *		negative, 0 zero, 1 positive
 *	58-5B	X0-X3
 *
 * A command is 16 bits: <3:0> operation, <5:4> source a and <7:6> source b
 * (0-2 the slots, 3 R), <9:8> format (0 F, 1 D, 2 G, 3 H), <11:10> slot d,
 * <12> negate, <14:13> integer size (0 byte, 1 word, 2 longword), <15>
 * round (CVTFI).
 *	0  NOP
 *	1  LD	   slot d <- W0-W3 unpacked
 *	2  MOV	   R <- a, negated with <12> (MOV, MNEG)
 *	3  CMP	   N <- a < b, Z <- a = b
 *	4  ADD	   R <- a + b (a - b with <12>), rounded
 *	5  MUL	   R <- a * b, rounded
 *	6  DIV	   R <- a / b, rounded; divide by zero when b is 0
 *	7  CVTIF   R <- IR (signed), rounded
 *	8  CVTFI   IR <- a as an integer of the size given, chopped (rounded
 *		   with <15>); integer overflow if it does not fit
 *	9  RND	   R <- a rounded to the format (a conversion between formats)
 *	10 EMOD	   the product a * b, a extended by the low-order bits in IR,
 *		   chopped to 32 (F), 64 (D, G) or 128 (H) bits before it is
 *		   normalized: IR <- its integer part (low-order 32 bits,
 *		   integer overflow if it does not fit), R <- its fraction part
 *		   rounded
 *	11 POLY	   R <- R * a + b, the product chopped to 31 (F), 63 (D, G)
 *		   or 127 (H) bits before it is normalized, and the sum chopped
 *		   the same way before it is normalized and rounded: one step
 *		   of POLY's loop
 *	12 STO	   slot d <- R
 *	13 TST	   N, Z <- a
 * A command first checks the sources it uses for a reserved operand (sign 1,
 * exponent 0) and does nothing else if there is one. A rounded result is
 * checked for floating overflow and underflow, an exponent out of range
 * after rounding; on overflow, and on underflow with PSL<FU> set, R is left
 * as it was; on underflow with FU clear R is 0 and no exception is reported.
 */

`timescale 1ns / 1ps
`default_nettype none

module fpunit(
	input		clk,
	input		rst,
	input		fu,		/* PSL<FU>: floating underflow faults */
	/* a floating operand from the operand decoder */
	input		ld,
	input [1:0]	ld_slot,
	input [1:0]	ld_fmt,
	input		ld_lit,		/* a short literal, in ld_data<5:0> */
	input [127:0]	ld_data,
	/* internal registers 50-5F */
	input		wr,
	input [3:0]	wa,
	input [31:0]	wd,
	input [3:0]	ra,
	output reg [31:0] rd,
	output		busy
);

	/* verilator lint_off UNUSEDPARAM */
	localparam	OP_NOP = 4'd0, OP_LD = 4'd1, OP_MOV = 4'd2,
			OP_CMP = 4'd3, OP_ADD = 4'd4, OP_MUL = 4'd5,
			OP_DIV = 4'd6, OP_CVTIF = 4'd7, OP_CVTFI = 4'd8,
			OP_RND = 4'd9, OP_EMOD = 4'd10, OP_POLY = 4'd11,
			OP_STO = 4'd12, OP_TST = 4'd13;
	/* verilator lint_on UNUSEDPARAM */

	localparam	S_IDLE = 5'd0, S_ADD0 = 5'd1, S_ADD1 = 5'd2,
			S_ADD2 = 5'd3, S_NORM = 5'd4, S_RND = 5'd5,
			S_MUL1 = 5'd6, S_MUL2 = 5'd7, S_MUL3 = 5'd8,
			S_EM = 5'd9, S_EM2 = 5'd10, S_EM3 = 5'd11,
			S_DIV = 5'd12, S_DIV2 = 5'd13, S_CVI = 5'd14,
			S_CVI2 = 5'd15, S_CVI3 = 5'd16, S_ADD1B = 5'd17,
			S_NORM2 = 5'd18;

	/*
	 * Format helpers.
	 */
	/* unpacked: { reserved, zero, sign, exponent, fraction } */
	function [148:0] unpack(input [127:0] w, input [1:0] fmt, input lit);
		reg [31:0]	l0, l1, l2, l3;
		reg		s, z, r;
		reg [14:0]	E;
		reg [17:0]	e;
		reg [127:0]	f;
		begin
			l0 = w[31:0];
			l1 = w[63:32];
			l2 = w[95:64];
			l3 = w[127:96];
			s = l0[15];
			case (fmt)
			2'd0: begin
				E = { 7'b0, l0[14:7] };
				e = { 3'b0, E } - 18'd128;
				f = { 1'b1, l0[6:0], l0[31:16], 104'b0 };
			end
			2'd1: begin
				E = { 7'b0, l0[14:7] };
				e = { 3'b0, E } - 18'd128;
				f = { 1'b1, l0[6:0], l0[31:16], l1[15:0],
				    l1[31:16], 72'b0 };
			end
			2'd2: begin
				E = { 4'b0, l0[14:4] };
				e = { 3'b0, E } - 18'd1024;
				f = { 1'b1, l0[3:0], l0[31:16], l1[15:0],
				    l1[31:16], 75'b0 };
			end
			default: begin
				E = l0[14:0];
				e = { 3'b0, E } - 18'd16384;
				f = { 1'b1, l0[31:16], l1[15:0], l1[31:16],
				    l2[15:0], l2[31:16], l3[15:0], l3[31:16],
				    15'b0 };
			end
			endcase
			/* exponent 0: zero (whatever the fraction), or with
			   the sign set the reserved operand */
			z = E == 15'd0 && !s;
			r = E == 15'd0 && s;
			if (E == 15'd0) begin
				e = 18'd0;
				f = 128'd0;
			end
			if (lit) begin
				/* short literal: 0.1fff (binary) * 2**exp, the
				   same value in every format (SRM 2, literal
				   mode) */
				s = 1'b0;
				z = 1'b0;
				r = 1'b0;
				e = { 15'b0, w[5:3] };
				f = { 1'b1, w[2:0], 124'b0 };
			end
			unpack = { r, z, s, e, f };
		end
	endfunction

	/* packed: the longwords in memory order, L0 in bits 31:0 */
	function [127:0] pack(input s, input [17:0] e, input [127:0] f,
	    input z, input [1:0] fmt);
		reg [17:0]	E;
		begin
			case (fmt)
			2'd0: begin
				E = e + 18'd128;
				pack = { 96'b0, f[119:104], s, E[7:0],
				    f[126:120] };
			end
			2'd1: begin
				E = e + 18'd128;
				pack = { 64'b0, f[87:72], f[103:88], f[119:104],
				    s, E[7:0], f[126:120] };
			end
			2'd2: begin
				E = e + 18'd1024;
				pack = { 64'b0, f[90:75], f[106:91], f[122:107],
				    s, E[10:0], f[126:123] };
			end
			default: begin
				E = e + 18'd16384;
				pack = { f[30:15], f[46:31], f[62:47], f[78:63],
				    f[94:79], f[110:95], f[126:111], s,
				    E[14:0] };
			end
			endcase
			if (z)
				pack = 128'd0;
		end
	endfunction

	/* the last fraction bit a format keeps (128 - its precision) */
	function [7:0] lsbpos(input [1:0] fmt);
		case (fmt)
		2'd0: lsbpos = 8'd104;
		2'd1: lsbpos = 8'd72;
		2'd2: lsbpos = 8'd75;
		default: lsbpos = 8'd15;
		endcase
	endfunction

	/* the true exponents a format can hold: biased 1 to the largest */
	function signed [17:0] emax(input [1:0] fmt);
		case (fmt)
		2'd0, 2'd1: emax = 18'sd127;
		2'd2: emax = 18'sd1023;
		default: emax = 18'sd16383;
		endcase
	endfunction

	/* EMOD: the product is chopped to 32 (F), 64 (D, G), 128 (H) bits */
	function [127:0] emask(input [1:0] fmt);
		case (fmt)
		2'd0: emask = { 32'hFFFFFFFF, 96'b0 };
		2'd1, 2'd2: emask = { 64'hFFFFFFFFFFFFFFFF, 64'b0 };
		default: emask = { 128{1'b1} };
		endcase
	endfunction

	/* POLY: product and sum chopped to 31 (F), 63 (D, G), 127 (H) bits */
	function [127:0] pmask(input [1:0] fmt);
		case (fmt)
		2'd0: pmask = { 31'h7FFFFFFF, 97'b0 };
		2'd1, 2'd2: pmask = { 63'h7FFFFFFFFFFFFFFF, 65'b0 };
		default: pmask = { { 127{1'b1} }, 1'b0 };
		endcase
	endfunction

	/* EMOD: the multiplier extension below the multiplier's fraction:
	   8 bits (F, D), <15:5> (G), <15:1> (H) */
	function [127:0] emodx(input [31:0] x, input [1:0] fmt);
		case (fmt)
		2'd0: emodx = { 24'b0, x[7:0], 96'b0 };
		2'd1: emodx = { 56'b0, x[7:0], 64'b0 };
		2'd2: emodx = { 53'b0, x[15:5], 64'b0 };
		default: emodx = { 113'b0, x[15:1] };
		endcase
	endfunction

	/* DIV: quotient bits to develop, the precision plus two */
	function [6:0] qbits(input [1:0] fmt);
		case (fmt)
		2'd0: qbits = 7'd26;
		2'd1: qbits = 7'd58;
		2'd2: qbits = 7'd55;
		default: qbits = 7'd115;
		endcase
	endfunction

	/* MUL: the first nonzero 32-bit chunk of a fraction */
	function [1:0] chunk0(input [1:0] fmt);
		case (fmt)
		2'd0: chunk0 = 2'd3;
		2'd1, 2'd2: chunk0 = 2'd2;
		default: chunk0 = 2'd0;
		endcase
	endfunction

	/* leading zeros of 128 bits (128 if none is set) */
	function [7:0] lzc128(input [127:0] v);
		integer i;
		begin
			lzc128 = 8'd128;
			for (i = 0; i < 128; i = i + 1)
				if (v[i])
					lzc128 = 8'd127 - i[7:0];
		end
	endfunction

	/*
	 * Registers.
	 */
	/* the slots S0-S2 and the result R (3) */
	reg		sg[0:3];
	reg signed [17:0] ex[0:3];
	reg [127:0]	fr[0:3];
	reg		zr[0:3];
	reg		rv[0:3];

	reg [4:0]	st;
	assign busy = st != S_IDLE;

	/* the command */
	reg [3:0]	c_op;
	reg [1:0]	c_fmt, c_isz;
	reg		c_rnd;

	/* status */
	reg		f_rsv, f_ovf, f_unf, f_dvz, f_iov, f_n, f_z;

	reg [31:0]	W[0:3];
	reg [31:0]	X[0:3];
	reg [31:0]	IR;

	/* the adder's operands: pa + pb */
	reg		pa_s, pb_s, pa_z, pb_z;
	reg signed [17:0] pa_e, pb_e;
	reg [127:0]	pa_f, pb_f;
	reg		chop_sum;	/* POLY: the sum chopped */

	/* adder */
	reg		ws, wsub;
	reg signed [17:0] we;
	reg [127:0]	wx, wy;
	reg		wstk;
	reg [128:0]	wsum;

	/* the right shifter: sh_in >> sh_amt (128 or more: all out), and
	   whether anything set was shifted out */
	reg [127:0]	sh_in;
	reg [7:0]	sh_amt;
	wire [127:0]	sh_out = sh_amt[7] ? 128'd0 : sh_in >> sh_amt[6:0];
	wire		sh_stk = sh_amt[7] ? |sh_in :
			    |(sh_in & ((128'd1 << sh_amt[6:0]) - 128'd1));

	/* normalizer input, and its leading zero count */
	reg		ns;
	reg signed [17:0] ne;
	reg [127:0]	nf;
	wire [7:0]	nlz = lzc128(nf);
	reg [7:0]	nlzr;

	/* multiplier: acc <- (acc >> 32) + ma * (32 bits of mb), the four
	   32 x 32 products registered first */
	reg [127:0]	ma, mb;
	reg [159:0]	acc;
	reg [63:0]	pp0, pp1, pp2, pp3;
	reg [1:0]	mj;
	wire [31:0]	mc = mb[{ mj, 5'b0 } +: 32];
	wire [63:0]	mp0 = ma[31:0] * mc;
	wire [63:0]	mp1 = ma[63:32] * mc;
	wire [63:0]	mp2 = ma[95:64] * mc;
	wire [63:0]	mp3 = ma[127:96] * mc;
	wire [127:0]	mtop = acc[159:32];	/* the product's high half */

	/* divider */
	reg [128:0]	rem;
	reg [127:0]	dvs, quo, qbit;
	reg [6:0]	dcnt;

	/* integer conversions */
	reg [31:0]	mag;
	reg		maghi;

	/*
	 * Combinational views of the command being written.
	 */
	wire [3:0]	n_op = wd[3:0];
	wire [1:0]	n_a = wd[5:4];
	wire [1:0]	n_b = wd[7:6];
	wire [1:0]	n_fmt = wd[9:8];
	wire [1:0]	n_d = wd[11:10];
	wire		n_neg = wd[12];
	wire		use_a = n_op == OP_MOV || n_op == OP_CMP ||
			    n_op == OP_ADD || n_op == OP_MUL || n_op == OP_DIV ||
			    n_op == OP_CVTFI || n_op == OP_RND ||
			    n_op == OP_EMOD || n_op == OP_POLY || n_op == OP_TST;
	wire		use_b = n_op == OP_CMP || n_op == OP_ADD ||
			    n_op == OP_MUL || n_op == OP_DIV ||
			    n_op == OP_EMOD || n_op == OP_POLY;
	wire		bad = (use_a && rv[n_a]) || (use_b && rv[n_b]);

	/* a and b of the command */
	wire		as = sg[n_a], bs = sg[n_b];
	wire signed [17:0] ae = ex[n_a], be = ex[n_b];
	wire [127:0]	af = fr[n_a], bf = fr[n_b];
	wire		az = zr[n_a], bz = zr[n_b];

	/* compare a with b */
	wire		mag_lt = az ? !bz : bz ? 1'b0 :
			    (ae < be) || (ae == be && af < bf);
	wire		mag_eq = (az && bz) ||
			    (!az && !bz && ae == be && af == bf);
	wire		c_lt = (as != bs) ? as :
			    as ? (!mag_lt && !mag_eq) : mag_lt;

	/* the adder's operands, pa the larger in magnitude */
	wire		pa_big = (pa_e > pb_e) || (pa_e == pb_e && pa_f >= pb_f);
	wire signed [17:0] pdiff = pa_big ? pa_e - pb_e : pb_e - pa_e;

	/* rounding R to the command's format */
	wire [7:0]	rl = lsbpos(c_fmt);
	wire [128:0]	rsum = ({ 1'b0, fr[3] } + (129'd1 << (rl - 8'd1))) &
			    ~((129'd1 << rl) - 129'd1);
	wire signed [17:0] re = rsum[128] ? ex[3] + 18'sd1 : ex[3];
	wire [127:0]	rf = rsum[128] ? rsum[128:1] : rsum[127:0];

	/* CVTFI: the magnitude, chopped or rounded, and the size check */
	wire signed [17:0] cvi_sh = 18'sd128 - we;

	/* the CVTFI and EMOD size check of the magnitude in mag/maghi */
	reg		iov;
	always @* begin
		case (c_isz)
		2'd0: iov = maghi || (ws ? mag > 32'd128 : mag > 32'd127);
		2'd1: iov = maghi || (ws ? mag > 32'd32768 : mag > 32'd32767);
		default: iov = maghi ||
		    (ws ? mag > 32'h80000000 : mag > 32'h7FFFFFFF);
		endcase
	end

	/* operands unpacked: from the operand decoder, from W0-W3 (LD) */
	wire [148:0]	ld_u = unpack(ld_data, ld_fmt, ld_lit);
	wire [148:0]	w_u = unpack({ W[3], W[2], W[1], W[0] }, n_fmt, 1'b0);

	/* the packed result */
	wire [127:0]	rpk = pack(sg[3], ex[3], fr[3], zr[3], c_fmt);

	always @* begin
		case (ra)
		4'd0:	rd = { busy, 24'b0, f_z, f_n, f_iov, f_dvz, f_unf,
			    f_ovf, f_rsv };
		4'd1:	rd = rpk[31:0];
		4'd2:	rd = rpk[63:32];
		4'd3:	rd = rpk[95:64];
		4'd4:	rd = rpk[127:96];
		4'd5:	rd = IR;
		4'd6:	rd = f_n ? 32'h80000000 : f_z ? 32'd0 : 32'd1;
		4'd8, 4'd9, 4'd10, 4'd11:
			rd = X[ra[1:0]];
		default: rd = 32'd0;
		endcase
	end

	always @(posedge clk)
		if (wr && wa[3:2] == 2'b10)
			X[wa[1:0]] <= wd;

	integer		k;
	initial begin
		for (k = 0; k < 4; k = k + 1) begin
			sg[k] = 1'b0;
			ex[k] = 18'sd0;
			fr[k] = 128'd0;
			zr[k] = 1'b1;
			rv[k] = 1'b0;
		end
		st = S_IDLE;
		f_rsv = 1'b0; f_ovf = 1'b0; f_unf = 1'b0; f_dvz = 1'b0;
		f_iov = 1'b0; f_n = 1'b0; f_z = 1'b0;
		c_fmt = 2'd0;
	end

	/* R <- 0 */
	task res_zero;
		begin
			sg[3] <= 1'b0;
			ex[3] <= 18'sd0;
			fr[3] <= 128'd0;
			zr[3] <= 1'b1;
			rv[3] <= 1'b0;
		end
	endtask

	/* R <- (s, e, f), not zero */
	task res_set(input s, input signed [17:0] e, input [127:0] f);
		begin
			sg[3] <= s;
			ex[3] <= e;
			fr[3] <= f;
			zr[3] <= 1'b0;
			rv[3] <= 1'b0;
		end
	endtask

	always @(posedge clk) begin
		if (rst)
			st <= S_IDLE;
		else if (st == S_IDLE) begin
			if (ld) begin
				rv[ld_slot] <= ld_u[148];
				zr[ld_slot] <= ld_u[147];
				sg[ld_slot] <= ld_u[146];
				ex[ld_slot] <= ld_u[145:128];
				fr[ld_slot] <= ld_u[127:0];
			end
			if (wr && wa[3:2] == 2'b00 && wa[1:0] != 2'd0)
				W[wa[1:0] - 2'd1] <= wd;
			if (wr && wa == 4'd4)
				W[3] <= wd;
			if (wr && wa == 4'd5)
				IR <= wd;
			if (wr && wa == 4'd0) begin
				c_op <= n_op;
				c_fmt <= n_fmt;
				c_isz <= wd[14:13];
				c_rnd <= wd[15];
				f_rsv <= 1'b0;
				f_ovf <= 1'b0;
				f_unf <= 1'b0;
				f_dvz <= 1'b0;
				f_iov <= 1'b0;
				chop_sum <= 1'b0;
				if (bad)
					f_rsv <= 1'b1;
				else
				case (n_op)
				OP_LD: begin
					rv[n_d] <= w_u[148];
					zr[n_d] <= w_u[147];
					sg[n_d] <= w_u[146];
					ex[n_d] <= w_u[145:128];
					fr[n_d] <= w_u[127:0];
				end
				OP_MOV: begin
					sg[3] <= az ? 1'b0 : as ^ n_neg;
					ex[3] <= ae;
					fr[3] <= af;
					zr[3] <= az;
					rv[3] <= 1'b0;
					f_n <= !az && (as ^ n_neg);
					f_z <= az;
				end
				OP_TST: begin
					f_n <= !az && as;
					f_z <= az;
				end
				OP_CMP: begin
					f_n <= c_lt;
					f_z <= mag_eq && (az || as == bs);
				end
				OP_STO: begin
					sg[n_d] <= sg[3];
					ex[n_d] <= ex[3];
					fr[n_d] <= fr[3];
					zr[n_d] <= zr[3];
					rv[n_d] <= 1'b0;
				end
				OP_ADD: begin
					pa_s <= as;
					pa_e <= ae;
					pa_f <= af;
					pa_z <= az;
					pb_s <= bs ^ n_neg;
					pb_e <= be;
					pb_f <= bf;
					pb_z <= bz;
					st <= S_ADD0;
				end
				OP_RND: begin
					sg[3] <= as;
					ex[3] <= ae;
					fr[3] <= af;
					zr[3] <= az;
					rv[3] <= 1'b0;
					st <= S_RND;
				end
				OP_MUL, OP_EMOD: begin
					if (az || bz) begin
						res_zero;
						IR <= 32'd0;
						st <= S_RND;
					end else begin
						ws <= as ^ bs;
						we <= ae + be;
						ma <= n_op == OP_EMOD ?
						    af | emodx(IR, n_fmt) : af;
						mb <= bf;
						acc <= 160'd0;
						mj <= chunk0(n_fmt);
						st <= S_MUL1;
					end
				end
				OP_POLY: begin
					/* R * a + b */
					pb_s <= bs;
					pb_e <= be;
					pb_f <= bf;
					pb_z <= bz;
					if (az || zr[3]) begin
						/* the product is 0: the sum is b */
						sg[3] <= bs;
						ex[3] <= be;
						fr[3] <= bf;
						zr[3] <= bz;
						rv[3] <= 1'b0;
						st <= S_RND;
					end else begin
						ws <= as ^ sg[3];
						we <= ae + ex[3];
						ma <= fr[3];
						mb <= af;
						acc <= 160'd0;
						mj <= chunk0(n_fmt);
						st <= S_MUL1;
					end
				end
				OP_DIV: begin
					if (bz)
						f_dvz <= 1'b1;
					else if (az) begin
						res_zero;
						st <= S_RND;
					end else begin
						ws <= as ^ bs;
						we <= ae - be + 18'sd1;
						rem <= { 1'b0, af };
						dvs <= bf;
						quo <= 128'd0;
						qbit <= { 1'b1, 127'b0 };
						dcnt <= qbits(n_fmt);
						st <= S_DIV;
					end
				end
				OP_CVTIF: begin
					if (IR == 32'd0) begin
						res_zero;
						st <= S_RND;
					end else begin
						ns <= IR[31];
						ne <= 18'sd32;
						nf <= { IR[31] ? 32'd0 - IR : IR,
						    96'b0 };
						st <= S_NORM;
					end
				end
				OP_CVTFI: begin
					ws <= as;
					if (az) begin
						IR <= 32'd0;
						f_n <= 1'b0;
						f_z <= 1'b1;
					end else begin
						we <= ae;
						wx <= af;
						sh_in <= af;
						st <= S_CVI;
					end
				end
				default: ;
				endcase
			end
		end else
		case (st)
		/*
		 * ADD: R <- pa + pb. The larger magnitude x, the smaller y
		 * shifted right by the exponent difference into the shifter.
		 */
		S_ADD0: begin
			if (pa_z && pb_z) begin
				res_zero;
				st <= S_RND;
			end else if (pa_z || pb_z) begin
				sg[3] <= pa_z ? pb_s : pa_s;
				ex[3] <= pa_z ? pb_e : pa_e;
				fr[3] <= pa_z ? pb_f : pa_f;
				zr[3] <= 1'b0;
				rv[3] <= 1'b0;
				st <= S_RND;
			end else begin
				ws <= pa_big ? pa_s : pb_s;
				we <= pa_big ? pa_e : pb_e;
				wx <= pa_big ? pa_f : pb_f;
				sh_in <= pa_big ? pb_f : pa_f;
				sh_amt <= pdiff > 18'sd127 ? 8'd128 : pdiff[7:0];
				wsub <= pa_s != pb_s;
				st <= S_ADD1;
			end
		end
		/* the smaller one aligned (and what was shifted out) */
		S_ADD1: begin
			wy <= sh_out;
			wstk <= sh_stk;
			st <= S_ADD1B;
		end
		/* add, or subtract the smaller rounded up: the floor of the
		   exact difference */
		S_ADD1B: begin
			wsum <= wsub ?
			    { 1'b0, wx } - { 1'b0, wy } - { 128'b0, wstk } :
			    { 1'b0, wx } + { 1'b0, wy };
			st <= S_ADD2;
		end
		/* a carry out shifts right; POLY chops the sum */
		S_ADD2: begin
			ns <= ws;
			if (!wsub && wsum[128]) begin
				ne <= we + 18'sd1;
				nf <= chop_sum ? wsum[128:1] & pmask(c_fmt) :
				    wsum[128:1];
			end else begin
				ne <= we;
				nf <= chop_sum ? wsum[127:0] & pmask(c_fmt) :
				    wsum[127:0];
			end
			st <= S_NORM;
		end
		/* normalize (ns, ne, nf) into R: count, then shift */
		S_NORM: begin
			nlzr <= nlz;
			st <= S_NORM2;
		end
		S_NORM2: begin
			if (nlzr[7])
				res_zero;
			else
				res_set(ns, ne - { 10'b0, nlzr }, nf << nlzr[6:0]);
			st <= S_RND;
		end
		/* round R to the format and check its exponent */
		S_RND: begin
			st <= S_IDLE;
			if (zr[3]) begin
				f_n <= 1'b0;
				f_z <= 1'b1;
			end else if (re > emax(c_fmt))
				f_ovf <= 1'b1;
			else if (re < -emax(c_fmt)) begin
				if (fu)
					f_unf <= 1'b1;
				else begin
					res_zero;
					f_n <= 1'b0;
					f_z <= 1'b1;
				end
			end else begin
				ex[3] <= re;
				fr[3] <= rf;
				f_n <= sg[3];
				f_z <= 1'b0;
			end
		end
		/*
		 * MUL, EMOD, POLY: four partial products of 128 x 32 bits,
		 * from the first chunk of mb that can be nonzero.
		 */
		S_MUL1: begin
			pp0 <= mp0;
			pp1 <= mp1;
			pp2 <= mp2;
			pp3 <= mp3;
			st <= S_MUL2;
		end
		S_MUL2: begin
			acc <= { 32'b0, acc[159:32] } + { 96'b0, pp0 } +
			    { 64'b0, pp1, 32'b0 } + { 32'b0, pp2, 64'b0 } +
			    { pp3, 96'b0 };
			mj <= mj + 2'd1;
			st <= mj == 2'd3 ? S_MUL3 : S_MUL1;
		end
		S_MUL3: begin
			case (c_op)
			OP_MUL: begin
				/* the product is 1/4 or more: one shift at most */
				if (mtop[127])
					res_set(ws, we, mtop);
				else
					res_set(ws, we - 18'sd1,
					    { mtop[126:0], acc[31] });
				st <= S_RND;
			end
			OP_EMOD: begin
				ns <= ws;
				if (mtop[127]) begin
					ne <= we;
					nf <= mtop & emask(c_fmt);
				end else begin
					ne <= we - 18'sd1;
					nf <= (mtop & emask(c_fmt)) << 1;
				end
				st <= S_EM;
			end
			default: begin
				/* POLY: the product chopped, normalized, then
				   added to b and chopped again */
				pa_s <= ws;
				pa_z <= 1'b0;
				if (mtop[127]) begin
					pa_e <= we;
					pa_f <= mtop & pmask(c_fmt);
				end else begin
					pa_e <= we - 18'sd1;
					pa_f <= (mtop & pmask(c_fmt)) << 1;
				end
				chop_sum <= 1'b1;
				st <= S_ADD0;
			end
			endcase
		end
		/*
		 * EMOD: the integer part of (ns, ne, nf) into IR, the fraction
		 * part normalized and rounded into R.
		 */
		S_EM: begin
			ws <= ns;
			if (ne <= 18'sd0) begin
				/* no integer part */
				mag <= 32'd0;
				maghi <= 1'b0;
				st <= S_EM3;
			end else if (ne < 18'sd128) begin
				sh_in <= nf;
				sh_amt <= 8'd128 - ne[7:0];
				st <= S_EM2;
			end else begin
				/* no fraction part; the integer is 2**127 or
				   more, its low-order 32 bits */
				mag <= ne - 18'sd128 < 18'sd32 ?
				    nf[31:0] << (ne[4:0]) : 32'd0;
				maghi <= 1'b1;
				nf <= 128'd0;
				st <= S_EM3;
			end
		end
		S_EM2: begin
			mag <= sh_out[31:0];
			maghi <= |sh_out[127:32];
			nf <= nf << ne[6:0];
			ne <= 18'sd0;
			st <= S_EM3;
		end
		S_EM3: begin
			IR <= ws ? 32'd0 - mag : mag;
			f_iov <= iov;
			st <= S_NORM;
		end
		/* DIV: one quotient bit a clock */
		S_DIV: begin
			if (rem >= { 1'b0, dvs }) begin
				rem <= (rem - { 1'b0, dvs }) << 1;
				quo <= quo | qbit;
			end else
				rem <= rem << 1;
			qbit <= qbit >> 1;
			dcnt <= dcnt - 7'd1;
			if (dcnt == 7'd1)
				st <= S_DIV2;
		end
		S_DIV2: begin
			if (quo[127])
				res_set(ws, we, quo);
			else
				res_set(ws, we - 18'sd1, quo << 1);
			st <= S_RND;
		end
		/* CVTFI: the integer part, chopped or rounded */
		S_CVI: begin
			if (we <= 18'sd0) begin
				/* below 1: 0, or 1 when rounding 1/2 or more */
				mag <= c_rnd && we == 18'sd0 ? 32'd1 : 32'd0;
				maghi <= 1'b0;
				st <= S_CVI3;
			end else if (we <= 18'sd128) begin
				sh_amt <= cvi_sh[7:0];
				st <= S_CVI2;
			end else begin
				mag <= we - 18'sd128 < 18'sd32 ?
				    wx[31:0] << (we[4:0]) : 32'd0;
				maghi <= 1'b1;
				st <= S_CVI3;
			end
		end
		/* the shifted value, plus the rounding bit with CVTR */
		S_CVI2: begin
			{ maghi, mag } <= { 1'b0, sh_out[31:0] } + { 32'b0,
			    c_rnd && we != 18'sd128 && wx[cvi_sh[6:0] - 7'd1] };
			if (|sh_out[127:32])
				maghi <= 1'b1;
			st <= S_CVI3;
		end
		S_CVI3: begin
			IR <= ws ? 32'd0 - mag : mag;
			f_iov <= iov;
			f_n <= ws && mag != 32'd0;
			f_z <= mag == 32'd0;
			st <= S_IDLE;
		end
		default: st <= S_IDLE;
		endcase
	end

endmodule

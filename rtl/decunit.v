/*
 * decunit.v - the decimal unit: packed decimal arithmetic for the VAX
 * commercial instructions (MOVP, CMPPx, ADDPx, SUBPx, MULP, DIVP, CVTLP,
 * CVTPL, ASHP, CVTPS, CVTSP, CVTPT, CVTTP).
 *
 * The microcode reads the decimal strings from memory and writes them back;
 * this unit holds them and does the arithmetic. It is reached through
 * internal processor registers 60-6F, which MTPR and MFPR cannot reach
 * (cpu.v and the microcode).
 *
 * A decimal string is held as 32 BCD digits in 128 bits, as the bytes of
 * the packed string right-aligned: nibble 0 is where the sign goes (zero
 * while the value is worked on), nibble 1 is the least significant digit,
 * nibble 31 the most significant one. Registers A and B are the operands
 * and A the result; C and D are working registers of MUL and DIV.
 *
 * Writes:
 *	60	command: <4:0> operation, <15:8> count/length/position n,
 *		<19:16> digit; see below
 *	61	AIN: A <- A<119:0>'byte<7:0>; <9> first byte: A <- byte;
 *		<8> sign byte: its low nibble is taken as 0
 *	62	BIN: the same for B
 *	63	X: the binary operand of CVTLP
 *	64-67	U0-U3: four longwords the microcode keeps things in
 * Reads:
 *	60	status: <31> busy, <0> A = 0, <1> A > B, <2> A = B, <3> overflow,
 *		<4> CVTPL overflow, <5> B = 0, <12:8> the highest nonzero
 *		nibble of A (0 if none), <20:16> that of B
 *	61	A<127:120>, the top byte (the string is written out with ROL)
 *	62	nibble n of A (n set by SETIDX)
 *	63	X: the binary result of CVTPL
 *	64-67	U0-U3
 *
 * Operations (the CPU waits while busy is set; see the DUWAIT state):
 *	0  CLR		A, B, C, D, overflow <- 0
 *	1  SWAP		A <-> B
 *	2  COPY		B <- A
 *	3  ADD		A <- A + B; overflow if a digit is carried out
 *	4  SUB		A <- A - B (A >= B)
 *	5  RSUB		A <- B - A (B >= A)
 *	6  SHL n	A <- A shifted left n digits (n < 256); overflow if a
 *			nonzero digit is shifted out
 *	7  SHR n	A <- A shifted right n digits
 *	8  ROL n	A <- A rotated left n nibbles (n < 32)
 *	9  SETLEN n	the digits above n (n < 32) give overflow, and are
 *			cleared
 *	10 SETNIB n,d	nibble n of A <- d
 *	11 SETIDX n	the nibble read at 62 is n
 *	12 MUL		A <- A * B (MULP: A and B with digits in nibbles
 *			1-31); overflow if the product does not fit
 *	13 DIV		A <- B / A (DIVP: B the dividend, A the divisor, not
 *			zero); the remainder is lost
 *	14 CVTLP	A <- X, unsigned, in BCD (nibbles 1-10)
 *	15 CVTPL	X <- the digits of A in binary, modulo 2**32; the
 *			CVTPL overflow is set when their value passes 2**32 - 1
 *			(the microcode checks the signed range)
 *	16 CLROVF	overflow <- 0
 *	17 INC		A <- A + 1 (the digit in nibble 1: ASHP rounding)
 *
 * Arithmetic is done 8 digits (32 bits) per clock, on the binary carry
 * chain: ADD and SUB take four.
 */

`timescale 1ns / 1ps
`default_nettype none

module decunit(
	input		clk,
	input		rst,
	input		wr,		/* write to internal register 60 + wa */
	input [3:0]	wa,
	input [31:0]	wd,
	input [3:0]	ra,		/* read address 60 + ra */
	output reg [31:0] rd,
	output		busy
);

`define DU_CLR		5'd0
`define DU_SWAP		5'd1
`define DU_COPY		5'd2
`define DU_ADD		5'd3
`define DU_SUB		5'd4
`define DU_RSUB		5'd5
`define DU_SHL		5'd6
`define DU_SHR		5'd7
`define DU_ROL		5'd8
`define DU_SETLEN	5'd9
`define DU_SETNIB	5'd10
`define DU_SETIDX	5'd11
`define DU_MUL		5'd12
`define DU_DIV		5'd13
`define DU_CVTLP	5'd14
`define DU_CVTPL	5'd15
`define DU_CLROVF	5'd16
`define DU_INC		5'd17

	reg [127:0]	A, B, C, D;
	reg [31:0]	X;
	reg [31:0]	U[0:3];
	reg		ovf, xv;
	reg [4:0]	idx;

	/* sequencer */
	localparam	S_IDLE = 4'd0, S_ADD = 4'd1, S_MULD = 4'd2,
			S_MULA = 4'd3, S_MULS = 4'd4, S_DIVC = 4'd5,
			S_DIVA = 4'd6, S_DIVN = 4'd7,
			S_CVLP = 4'd9, S_CVPL = 4'd10;
	reg [3:0]	st;
	assign busy = st != S_IDLE;

	/*
	 * The adder: X + Y + carry on 8 digits, Y nine's-complemented for a
	 * subtraction. Used four times for 128 bits, chunk k = 0..3.
	 */
	reg [1:0]	k;		/* the chunk being added */
	reg		cy;		/* carry into it */
	reg [2:0]	aop;		/* what the adder does: */
	localparam	AO_ADD = 3'd0,	/* A <- A + B */
			AO_SUB = 3'd1,	/* A <- A - B */
			AO_RSUB = 3'd2,	/* A <- B - A */
			AO_MUL = 3'd3,	/* C <- C + D */
			AO_DIV = 3'd4;	/* B <- B - D */
	reg [3:0]	aret;		/* where the sequencer goes after it */

	function [31:0] chunk(input [127:0] v, input [1:0] n);
		chunk = v[n * 32 +: 32];
	endfunction

	/*
	 * 8-digit BCD addition on the binary carry chain: a + b + 66666666 +
	 * carry, then 6 taken back from every digit that did not carry out
	 * (which cannot borrow). The carries out of the digits are those into
	 * bits 4, 8, ..., 32 of the binary sum.
	 */
	function [32:0] bcdadd8(input [31:0] a, input [31:0] b, input ci);
		reg [32:0] s1, cv;
		integer i;
		begin
			s1 = { 1'b0, a } + { 1'b0, b } + 33'h066666666 + { 32'b0, ci };
			cv = s1 ^ { 1'b0, a } ^ { 1'b0, b } ^ 33'h066666666;
			for (i = 0; i < 8; i = i + 1)
				bcdadd8[i*4 +: 4] = s1[i*4 +: 4] -
				    (cv[i*4 + 4] ? 4'd0 : 4'd6);
			bcdadd8[32] = s1[32];
		end
	endfunction

	function [31:0] nines(input [31:0] v);
		integer i;
		begin
			for (i = 0; i < 8; i = i + 1)
				nines[i*4 +: 4] = 4'd9 - v[i*4 +: 4];
		end
	endfunction

	reg [31:0]	ax, ay;
	wire [32:0]	asum = bcdadd8(ax, ay, cy);
	always @* begin
		case (aop)
		AO_ADD:	begin ax = chunk(A, k); ay = chunk(B, k); end
		AO_SUB:	begin ax = chunk(A, k); ay = nines(chunk(B, k)); end
		AO_RSUB: begin ax = chunk(B, k); ay = nines(chunk(A, k)); end
		AO_MUL:	begin ax = chunk(C, k); ay = chunk(D, k); end
		default: begin ax = chunk(B, k); ay = nines(chunk(D, k)); end
		endcase
	end

	/* the highest nonzero nibble */
	function [4:0] topnib(input [127:0] v);
		integer i;
		begin
			topnib = 5'd0;
			for (i = 0; i < 32; i = i + 1)
				if (v[i*4 +: 4] != 4'd0)
					topnib = i[4:0];
		end
	endfunction

	wire [4:0]	alen = topnib(A);
	wire [4:0]	blen = topnib(B);
	wire		az = A == 128'b0;
	wire		bz = B == 128'b0;

	/* digits n+1..31 (above a length of n) */
	function [127:0] lenmask(input [4:0] n);
		lenmask = { 128{1'b1} } >> (7'd124 - { n, 2'b00 });
	endfunction

	always @* begin
		case (ra)
		4'd0:	rd = { busy, 10'b0, blen, 3'b0, alen, 2'b0, bz, xv,
			    ovf, A == B, A > B, az };
		4'd1:	rd = { 24'b0, A[127:120] };
		4'd2:	rd = { 28'b0, A[idx*4 +: 4] };
		4'd3:	rd = X;
		4'd4, 4'd5, 4'd6, 4'd7:
			rd = U[ra[1:0]];
		default: rd = 32'b0;
		endcase
	end

	/* MUL and DIV */
	reg [4:0]	mi;		/* MUL: multiplier digit; DIV: digits left */
	reg [3:0]	md;		/* MUL: adds left; DIV: the quotient digit */
	reg [5:0]	ci;		/* CVTLP, CVTPL: steps */
	reg [39:0]	bcd;		/* CVTLP */

	wire [4:0]	dshift = blen - alen;	/* DIV: alignment */

	/* CVTPL step: X <- X * 10 + digit; xv when it passes 2**32 - 1 */
	wire [3:0]	pd = A[{ ci[4:0], 2'b00 } +: 4];
	wire [35:0]	x10 = { 4'b0, X } * 36'd10;
	wire [31:0]	xn = x10[31:0] + { 28'b0, pd };

	/* CVTLP step: double dabble */
	function [39:0] dabble(input [39:0] v);
		integer i;
		begin
			for (i = 0; i < 10; i = i + 1)
				dabble[i*4 +: 4] = v[i*4 +: 4] >= 4'd5 ?
				    v[i*4 +: 4] + 4'd3 : v[i*4 +: 4];
		end
	endfunction
	wire [39:0]	bcdd = dabble(bcd);

	wire [4:0]	op = wd[4:0];
	wire [7:0]	n = wd[15:8];

	always @(posedge clk)
		if (wr && wa[3:2] == 2'b01)
			U[wa[1:0]] <= wd;

	always @(posedge clk) begin
		if (rst) begin
			st <= S_IDLE;
			ovf <= 1'b0;
		end else if (st == S_IDLE) begin
			if (wr && wa == 4'd1)
				A <= wd[9] ? { 120'b0, wd[7:4], wd[8] ? 4'b0 : wd[3:0] } :
				    { A[119:0], wd[7:4], wd[8] ? 4'b0 : wd[3:0] };
			if (wr && wa == 4'd2)
				B <= wd[9] ? { 120'b0, wd[7:4], wd[8] ? 4'b0 : wd[3:0] } :
				    { B[119:0], wd[7:4], wd[8] ? 4'b0 : wd[3:0] };
			if (wr && wa == 4'd3)
				X <= wd;
			if (wr && wa == 4'd0)
			case (op)
			`DU_CLR: begin
				A <= 128'b0; B <= 128'b0; C <= 128'b0; D <= 128'b0;
				ovf <= 1'b0;
			end
			`DU_SWAP: begin A <= B; B <= A; end
			`DU_COPY: B <= A;
			`DU_ADD: begin aop <= AO_ADD; k <= 0; cy <= 0;
				aret <= S_IDLE; st <= S_ADD; end
			`DU_SUB: begin aop <= AO_SUB; k <= 0; cy <= 1;
				aret <= S_IDLE; st <= S_ADD; end
			`DU_RSUB: begin aop <= AO_RSUB; k <= 0; cy <= 1;
				aret <= S_IDLE; st <= S_ADD; end
			`DU_SHL: begin
				if (n >= 8'd32) begin
					if (!az) ovf <= 1'b1;
					A <= 128'b0;
				end else begin
					if ((A >> (8'd128 - { n[5:0], 2'b00 })) != 128'b0 &&
					    n != 8'd0)
						ovf <= 1'b1;
					A <= A << { n[5:0], 2'b00 };
				end
			end
			`DU_SHR: A <= n >= 8'd32 ? 128'b0 : A >> { n[5:0], 2'b00 };
			`DU_ROL: A <= (A << { n[4:0], 2'b00 }) |
			    (A >> (8'd128 - { n[4:0], 2'b00 }));
			`DU_SETLEN: begin
				if ((A & ~lenmask(n[4:0])) != 128'b0)
					ovf <= 1'b1;
				A <= A & lenmask(n[4:0]);
			end
			`DU_SETNIB: A[{ n[4:0], 2'b00 } +: 4] <= wd[19:16];
			`DU_SETIDX: idx <= n[4:0];
			`DU_MUL: begin
				/* D: the multiplicand right-justified */
				D <= A >> 4;
				C <= 128'b0;
				A <= 128'b0;
				mi <= 5'd1;
				st <= S_MULD;
			end
			`DU_DIV: begin
				/* both right-justified; then (S_DIVA) the
				   divisor aligned with the dividend's highest
				   digit */
				D <= A >> 4;
				B <= B >> 4;
				A <= 128'b0;
				mi <= dshift;
				md <= 4'd0;
				if (blen >= alen)	/* else no quotient digit */
					st <= S_DIVA;
			end
			`DU_CVTLP: begin
				bcd <= 40'b0;
				ci <= 6'd32;
				st <= S_CVLP;
			end
			`DU_CVTPL: begin
				X <= 32'b0;
				xv <= 1'b0;
				ci <= 6'd31;
				st <= S_CVPL;
			end
			`DU_CLROVF: ovf <= 1'b0;
			`DU_INC: begin
				B <= 128'h10;
				aop <= AO_ADD; k <= 0; cy <= 0;
				aret <= S_IDLE; st <= S_ADD;
			end
			default: ;
			endcase
		end else
		case (st)
		/* one chunk of an addition */
		S_ADD: begin
			case (aop)
			AO_ADD, AO_SUB, AO_RSUB: A[k*32 +: 32] <= asum[31:0];
			AO_MUL: C[k*32 +: 32] <= asum[31:0];
			default: B[k*32 +: 32] <= asum[31:0];
			endcase
			cy <= asum[32];
			k <= k + 2'd1;
			if (k == 2'd3) begin
				if (aop == AO_ADD && asum[32])
					ovf <= 1'b1;
				st <= aret;
			end
		end
		/* MUL: digit mi of the multiplier */
		S_MULD: begin
			md <= B[{ mi, 2'b00 } +: 4];
			st <= S_MULA;
		end
		/* add the multiplicand md times */
		S_MULA: begin
			if (md == 4'd0) begin
				/* the product moves down a digit into A */
				A <= { C[3:0], A[127:4] };
				C <= C >> 4;
				st <= S_MULS;
			end else begin
				md <= md - 4'd1;
				aop <= AO_MUL; k <= 0; cy <= 0;
				aret <= S_MULA; st <= S_ADD;
			end
		end
		S_MULS: begin
			if (mi == 5'd31) begin
				if (C != 128'b0)
					ovf <= 1'b1;
				st <= S_IDLE;
			end else begin
				mi <= mi + 5'd1;
				st <= S_MULD;
			end
		end
		S_DIVA: begin
			D <= D << { mi, 2'b00 };
			st <= S_DIVC;
		end
		/* DIV: subtract the divisor while it fits */
		S_DIVC: begin
			if (B >= D) begin
				md <= md + 4'd1;
				aop <= AO_DIV; k <= 0; cy <= 1;
				aret <= S_DIVC; st <= S_ADD;
			end else
				st <= S_DIVN;
		end
		/* the quotient digit in, the dividend up a digit */
		S_DIVN: begin
			A <= (A | { 124'b0, md }) << 4;
			B <= B << 4;
			md <= 4'd0;
			if (mi == 5'd0)
				st <= S_IDLE;
			else begin
				mi <= mi - 5'd1;
				st <= S_DIVC;
			end
		end
		/* CVTLP: 32 steps of double dabble */
		S_CVLP: begin
			if (ci == 6'd0) begin
				A <= { 84'b0, bcd, 4'b0 };
				st <= S_IDLE;
			end else begin
				{ bcd, X } <= { bcdd, X } << 1;
				ci <= ci - 6'd1;
			end
		end
		/* CVTPL: digits 31 down to 1 */
		S_CVPL: begin
			if (ci == 6'd0)
				st <= S_IDLE;
			else begin
				if (pd != 4'd0 || X != 32'b0 || xv) begin
					if (X >= 32'd429496730)
						xv <= 1'b1;
					X <= xn;
					if (xn < { 28'b0, pd })
						xv <= 1'b1;
				end
				ci <= ci - 6'd1;
			end
		end
		default: st <= S_IDLE;
		endcase
	end

endmodule

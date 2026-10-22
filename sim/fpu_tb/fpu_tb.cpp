// fpu_tb.cpp - unit test of rtl/fpunit.v against the exact model in
// vaxfp.py: for each vector the operands are loaded into the slots, the
// command given, and the flags, the packed result and IR compared.
//
//	make -C sim fputb
//	python3 sim/fpu_tb/vaxfp.py vectors.txt 20000 1
//	sim/obj_fpu/Vfpunit vectors.txt
//
// A vector line:
//	OP fmt fu  a0 a1 a2 a3  b0 b1 b2 b3  x0 x1 x2 x3  ir  |
//	rsv ovf unf dvz iov  n z  r0 r1 r2 r3  irres  rfmt
// x0 is the integer size and rounding (CVTFI: <1:0> size, <2> round) or
// the destination format (RND); for POLY x0-x3 are the coefficient (R
// comes from b). "-" means not checked.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include "Vfpunit.h"
#include "verilated.h"

static Vfpunit *u;
static uint64_t clocks;

static void tick() {
	u->clk = 0;
	u->eval();
	u->clk = 1;
	u->eval();
	clocks++;
}

static void ld(int slot, int fmt, const uint32_t w[4]) {
	u->ld = 1;
	u->ld_slot = slot;
	u->ld_fmt = fmt;
	u->ld_lit = 0;
	for (int i = 0; i < 4; i++)
		u->ld_data[i] = w[i];
	tick();
	u->ld = 0;
}

static void wreg(int a, uint32_t d) {
	u->wr = 1;
	u->wa = a;
	u->wd = d;
	tick();
	u->wr = 0;
	int n = 0;
	while (u->busy) {
		tick();
		if (++n > 1000) {
			printf("busy for ever\n");
			exit(2);
		}
	}
}

static uint32_t rreg(int a) {
	u->ra = a;
	u->eval();
	return u->rd;
}

enum { OP_LD = 1, OP_MOV, OP_CMP, OP_ADD, OP_MUL, OP_DIV, OP_CVTIF,
	OP_CVTFI, OP_RND, OP_EMOD, OP_POLY, OP_STO, OP_TST };

static uint32_t cmd(int op, int a, int b, int fmt, int d = 0, int neg = 0,
    int isz = 0, int rnd = 0) {
	return op | a << 4 | b << 6 | fmt << 8 | d << 10 | neg << 12 |
	    isz << 13 | rnd << 15;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	u = new Vfpunit;
	u->rst = 1;
	tick();
	tick();
	u->rst = 0;
	FILE *f = fopen(argc > 1 ? argv[1] : "vectors.txt", "r");
	if (!f) {
		perror("vectors");
		return 2;
	}
	char line[1024];
	int n = 0, bad = 0;
	while (fgets(line, sizeof line, f)) {
		char op[16];
		int fmt, fu;
		uint32_t a[4], b[4], x[4], ir;
		char e[13][16];
		if (sscanf(line, "%15s %d %d %x %x %x %x %x %x %x %x %x %x %x %x %x |"
		    " %15s %15s %15s %15s %15s %15s %15s %15s %15s %15s %15s %15s"
		    " %15s",
		    op, &fmt, &fu, &a[0], &a[1], &a[2], &a[3], &b[0], &b[1],
		    &b[2], &b[3], &x[0], &x[1], &x[2], &x[3], &ir,
		    e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9],
		    e[10], e[11], e[12]) != 29)
			continue;
		n++;
		std::string o = op;
		int rfmt = atoi(e[12]);
		u->fu = fu;
		ld(0, fmt, a);
		ld(1, fmt, b);
		wreg(5, ir);
		bool stop = false;
		if (o == "ADD")
			wreg(0, cmd(OP_ADD, 0, 1, fmt));
		else if (o == "SUB")
			wreg(0, cmd(OP_ADD, 0, 1, fmt, 0, 1));
		else if (o == "MUL")
			wreg(0, cmd(OP_MUL, 0, 1, fmt));
		else if (o == "DIV")
			wreg(0, cmd(OP_DIV, 0, 1, fmt));
		else if (o == "CMP")
			wreg(0, cmd(OP_CMP, 0, 1, fmt));
		else if (o == "CVTIF")
			wreg(0, cmd(OP_CVTIF, 0, 0, fmt));
		else if (o == "CVTFI")
			wreg(0, cmd(OP_CVTFI, 0, 0, fmt, 0, 0, x[0] & 3,
			    (x[0] >> 2) & 1));
		else if (o == "RND")
			wreg(0, cmd(OP_RND, 0, 0, x[0] & 3));
		else if (o == "EMOD")
			wreg(0, cmd(OP_EMOD, 0, 1, fmt, 0, 0, 2));
		else if (o == "POLY") {
			wreg(0, cmd(OP_MOV, 1, 0, fmt));	// R <- b
			if (rreg(0) & 1)
				stop = true;
			else {
				ld(2, fmt, x);
				wreg(0, cmd(OP_POLY, 0, 2, fmt));
			}
		} else if (o == "MOV")
			wreg(0, cmd(OP_MOV, 0, 0, fmt));
		else if (o == "MNEG")
			wreg(0, cmd(OP_MOV, 0, 0, fmt, 0, 1));
		else if (o == "TST")
			wreg(0, cmd(OP_TST, 0, 0, fmt));
		(void)stop;
		uint32_t st = rreg(0);
		int got[7] = { (int)(st & 1), (int)(st >> 1 & 1), (int)(st >> 2 & 1),
		    (int)(st >> 3 & 1), (int)(st >> 4 & 1), (int)(st >> 5 & 1),
		    (int)(st >> 6 & 1) };
		std::string msg;
		const char *nm[7] = { "rsv", "ovf", "unf", "dvz", "iov", "n", "z" };
		for (int i = 0; i < 7; i++) {
			if (e[i][0] == '-')
				continue;
			if (atoi(e[i]) != got[i]) {
				char t[64];
				snprintf(t, sizeof t, " %s exp %s got %d", nm[i],
				    e[i], got[i]);
				msg += t;
			}
		}
		int nw = rfmt == 0 ? 1 : rfmt == 3 ? 4 : 2;
		if (e[7][0] != '-' && !got[0] && !got[1] && !got[2] && !got[3]) {
			for (int i = 0; i < nw; i++) {
				uint32_t r = rreg(1 + i);
				uint32_t ex = strtoul(e[7 + i], 0, 16);
				if (r != ex) {
					char t[64];
					snprintf(t, sizeof t, " r%d exp %08X got %08X",
					    i, ex, r);
					msg += t;
				}
			}
		}
		if (e[11][0] != '-') {
			uint32_t r = rreg(5);
			uint32_t ex = strtoul(e[11], 0, 16);
			if (r != ex) {
				char t[64];
				snprintf(t, sizeof t, " ir exp %08X got %08X", ex, r);
				msg += t;
			}
		}
		if (!msg.empty()) {
			bad++;
			if (bad <= 40)
				printf("FAIL%s\n  %s", msg.c_str(), line);
		}
	}
	printf("%d vectors, %d failed, %llu clocks\n", n, bad,
	    (unsigned long long)clocks);
	delete u;
	return bad ? 1 : 0;
}

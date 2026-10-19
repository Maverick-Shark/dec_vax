// du_tb.cpp - unit test of rtl/decunit.v against a C model of its
// operations (add, subtract, multiply, divide, CVTLP, CVTPL, shifts,
// lengths) on random operands.
//
//     make -C sim dutb && sim/obj_du/Vdecunit [iterations]
#include "Vdecunit.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>

typedef unsigned __int128 u128;
static Vdecunit *du;
static uint64_t cycles;

static uint32_t rdstat();
static void tick() { du->clk = 0; du->eval(); du->clk = 1; du->eval(); cycles++; }

static void wr(int a, uint32_t d) {
	du->wr = 1; du->wa = a; du->wd = d; tick(); du->wr = 0;
	int n = 0;
	while (rdstat() >> 31) { tick(); if (++n > 100000) { printf("hung\n"); exit(1); } }
}
static uint32_t rdreg(int a) { du->ra = a; du->eval(); return du->rd; }
static uint32_t rdstat() { return rdreg(0); }
static void cmd(int op, int n = 0, int d = 0) { wr(0, op | (n << 8) | (d << 16)); }

static u128 getA() {
	// rotate out the 16 bytes through the top byte
	u128 v = 0;
	for (int i = 0; i < 16; i++) { v = (v << 8) | rdreg(1); cmd(8, 2); }
	return v;
}
static void loadreg(int r, u128 v) {
	for (int i = 15; i >= 0; i--)
		wr(r, (uint32_t)((v >> (i * 8)) & 0xFF) | (i == 15 ? 0x200 : 0));
}

// the model: BCD digits in a 128-bit integer, nibble 0 the sign position
static u128 bcd_add(u128 a, u128 b, int &cy) {
	u128 r = 0; int c = cy;
	for (int i = 0; i < 32; i++) {
		int s = (int)((a >> (4*i)) & 15) + (int)((b >> (4*i)) & 15) + c;
		c = s > 9; if (c) s -= 10;
		r |= (u128)s << (4*i);
	}
	cy = c; return r;
}
static u128 nines(u128 v) { u128 r = 0; for (int i = 0; i < 32; i++) r |= (u128)(9 - (int)((v >> (4*i)) & 15)) << (4*i); return r; }
static u128 bcd_sub(u128 a, u128 b) { int c = 1; return bcd_add(a, nines(b), c); }
static int topnib(u128 v) { int t = 0; for (int i = 0; i < 32; i++) if ((v >> (4*i)) & 15) t = i; return t; }
static u128 rnd_bcd(int digits) {   // digits in nibbles 1..digits
	u128 v = 0;
	for (int i = 1; i <= digits; i++) v |= (u128)(rand() % 10) << (4*i);
	return v;
}
static void p128(const char *s, u128 v) { printf("%s %016llX%016llX\n", s, (unsigned long long)(v >> 64), (unsigned long long)v); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	du = new Vdecunit;
	int iters = argc > 1 ? atoi(argv[1]) : 2000;
	du->rst = 1; tick(); tick(); du->rst = 0; tick();
	int fails = 0;
	srand(12345);
	for (int it = 0; it < iters; it++) {
		int la = rand() % 32, lb = rand() % 32;
		u128 a = rnd_bcd(la), b = rnd_bcd(lb);
		// ADD
		cmd(0); loadreg(1, a); loadreg(2, b); cmd(3);
		int cy = 0; u128 e = bcd_add(a, b, cy);
		u128 g = getA(); int ov = (rdstat() >> 3) & 1;
		if (g != e || ov != cy) { printf("ADD fail\n"); p128("a", a); p128("b", b); p128("exp", e); p128("got", g); fails++; }
		// SUB / RSUB
		u128 big = a > b ? a : b, sml = a > b ? b : a;
		cmd(0); loadreg(1, big); loadreg(2, sml); cmd(4);
		e = bcd_sub(big, sml); g = getA();
		if (g != e) { printf("SUB fail\n"); p128("a", big); p128("b", sml); p128("exp", e); p128("got", g); fails++; }
		cmd(0); loadreg(1, sml); loadreg(2, big); cmd(5);
		g = getA();
		if (g != e) { printf("RSUB fail\n"); fails++; }
		// compare, zero, lengths
		cmd(0); loadreg(1, a); loadreg(2, b);
		uint32_t st = rdstat();
		if (((st >> 1) & 1) != (a > b) || ((st >> 2) & 1) != (a == b) || (st & 1) != (a == 0) ||
		    ((st >> 5) & 1) != (b == 0) || ((st >> 8) & 31) != (uint32_t)topnib(a) || ((st >> 16) & 31) != (uint32_t)topnib(b)) {
			printf("STAT fail %08X\n", st); p128("a", a); p128("b", b); fails++; }
		// MUL: the multiplicand added digit by digit, the product shifted down
		{
			cmd(0); loadreg(1, a); loadreg(2, b); cmd(12);
			u128 m = a >> 4, acc = 0, dst = 0;
			for (int i = 1; i < 32; i++) {
				int d = (int)((b >> (4*i)) & 15);
				for (int j = 0; j < d; j++) { int c = 0; acc = bcd_add(acc, m, c); }
				dst = (dst >> 4) | ((acc & 15) << 124); acc >>= 4;
			}
			int v = acc != 0;
			g = getA(); int gv = (rdstat() >> 3) & 1;
			if (g != dst || gv != v) { printf("MUL fail\n"); p128("a", a); p128("b", b); p128("exp", dst); p128("got", g); printf("v %d got %d\n", v, gv); fails++; }
		}
		// DIV: A = divisor, B = dividend, restoring division by digits
		if (a != 0) {
			cmd(0); loadreg(1, a); loadreg(2, b); cmd(13);
			int ldivr = topnib(a), ldivd = topnib(b);
			u128 dvr = a >> 4, dvd = b >> 4, q = 0;
			int t = ldivd - ldivr;
			if (b != 0 && t >= 0) {
				dvr <<= 4 * t;
				for (int i = 0; i <= t; i++) {
					int d = 0;
					while (dvd >= dvr) { dvd = bcd_sub(dvd, dvr); d++; }
					q = (q | d) << 4; dvd <<= 4;
				}
			}
			g = getA();
			if (g != q) { printf("DIV fail\n"); p128("dvr", a); p128("dvd", b); p128("exp", q); p128("got", g); fails++; }
		}
		// CVTLP
		{
			uint32_t x = (uint32_t)rand() ^ ((uint32_t)rand() << 16);
			if (it % 7 == 0) x = 0xFFFFFFFF; if (it % 11 == 0) x = 0;
			cmd(0); wr(3, x); cmd(14);
			u128 ev = 0; uint32_t t = x;
			for (int i = 1; t; i++) { ev |= (u128)(t % 10) << (4*i); t /= 10; }
			g = getA();
			if (g != ev) { printf("CVTLP fail %08X\n", x); p128("exp", ev); p128("got", g); fails++; }
		}
		// CVTPL: overflow when the value passes 2^32 - 1
		{
			cmd(0); loadreg(1, a); cmd(15);
			uint32_t r = 0; int v = 0;
			for (int i = 31; i > 0; i--) {
				uint32_t d = (uint32_t)((a >> (4*i)) & 15);
				if (d || r || v) {
					if (r >= 429496730u) v = 1;
					r = r * 10 + d;
					if (r < d) v = 1;
				}
			}
			uint32_t gx = rdreg(3); int gv = (rdstat() >> 4) & 1;
			if (gx != r || gv != v) { printf("CVTPL fail exp %08X %d got %08X %d\n", r, v, gx, gv); p128("a", a); fails++; }
		}
		// SHL / SHR / SETLEN
		{
			int n = rand() % 40;
			cmd(0); loadreg(1, a); cmd(6, n);
			u128 ev = n >= 32 ? 0 : a << (4*n);
			int ov = n >= 32 ? a != 0 : (n ? (a >> (128 - 4*n)) != 0 : 0);
			g = getA(); int gv = (rdstat() >> 3) & 1;
			if (g != ev || gv != ov) { printf("SHL %d fail\n", n); p128("a", a); p128("exp", ev); p128("got", g); fails++; }
			cmd(0); loadreg(1, a); cmd(7, n);
			ev = n >= 32 ? 0 : a >> (4*n);
			g = getA();
			if (g != ev) { printf("SHR %d fail\n", n); fails++; }
			int l = rand() % 32;
			cmd(0); loadreg(1, a); cmd(9, l);
			u128 mask = l == 31 ? ~(u128)0 : (((u128)1 << (4*(l+1))) - 1);
			ev = a & mask; ov = (a & ~mask) != 0;
			g = getA(); gv = (rdstat() >> 3) & 1;
			if (g != ev || gv != ov) { printf("SETLEN %d fail\n", l); p128("a", a); p128("exp", ev); p128("got", g); fails++; }
			// SETNIB / nibble read
			int pos = rand() % 32, dg = rand() % 10;
			cmd(0); loadreg(1, a); cmd(10, pos, dg); cmd(11, pos);
			if ((int)rdreg(2) != dg) { printf("NIB fail\n"); fails++; }
			// INC
			cmd(0); loadreg(1, a); cmd(17);
			int c = 0; ev = bcd_add(a, (u128)0x10, c);
			g = getA();
			if (g != ev) { printf("INC fail\n"); fails++; }
		}
		if (fails > 10) break;
	}
	printf("%d iterations, %d failures, %llu clocks\n", iters, fails, (unsigned long long)cycles);
	delete du;
	return fails != 0;
}

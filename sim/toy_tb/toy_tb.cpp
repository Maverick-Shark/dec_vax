// toy_tb.cpp - vax_toy.v against the C library: for random dates from 2000
// to 2099 (and the edges of each year), the TODR value it makes from the
// RTC's BCD fields must be 10000000 (hex) + 100 * (seconds since 1 January
// 00:00 of that year), counted here with timegm. Also: only the first RTC
// value after power-up is used, and an invalid one loads nothing.
//
//     make -C sim toytb && sim/obj_toy/Vvax_toy [count]
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include "Vvax_toy.h"
#include "verilated.h"

static Vvax_toy *m;
static void tick() { m->clk = 0; m->eval(); m->clk = 1; m->eval(); }
static unsigned b(int v) { return (unsigned)((v / 10) << 4 | (v % 10)); }

static void send(int Y, int Mo, int D, int h, int mi, int s) {
	m->rtc[0] = b(s) | b(mi) << 8 | b(h) << 16 | b(D) << 24;
	m->rtc[1] = b(Mo) | b(Y % 100) << 8 | 0x40u << 24;
	m->rtc[2] ^= 1;
}

// run until ld or n clocks; returns whether TODR was loaded
static bool wait_ld(unsigned *val, int n = 20) {
	for (int i = 0; i < n; i++) {
		tick();
		if (m->ld) { *val = m->val; return true; }
	}
	return false;
}

static unsigned expect(int Y, int Mo, int D, int h, int mi, int s) {
	struct tm t = {}, j = {};
	t.tm_year = Y - 1900; t.tm_mon = Mo - 1; t.tm_mday = D;
	t.tm_hour = h; t.tm_min = mi; t.tm_sec = s;
	j.tm_year = Y - 1900; j.tm_mday = 1;
	return 0x10000000u + (unsigned)(timegm(&t) - timegm(&j)) * 100u;
}

int main(int argc, char **argv) {
	int n = argc > 1 ? atoi(argv[1]) : 100000, bad = 0;
	srand(1);
	for (int k = 0; k < n; k++) {
		int Y, Mo, D, h, mi, s;
		static const int ml[] = {31,28,31,30,31,30,31,31,30,31,30,31};
		switch (k % 4) {
		case 0: Y = 2000 + rand() % 100; Mo = 1; D = 1; h = mi = s = 0; break;
		case 1: Y = 2000 + rand() % 100; Mo = 12; D = 31; h = 23; mi = s = 59; break;
		default:
			Y = 2000 + rand() % 100; Mo = 1 + rand() % 12;
			D = 1 + rand() % (ml[Mo - 1] + (Mo == 2 && Y % 4 == 0));
			h = rand() % 24; mi = rand() % 60; s = rand() % 60;
		}
		m = new Vvax_toy;                       // a fresh power-up each time
		m->rtc[0] = m->rtc[1] = m->rtc[2] = 0;
		for (int i = 0; i < 3; i++) tick();
		send(Y, Mo, D, h, mi, s);
		unsigned v;
		if (!wait_ld(&v) || v != expect(Y, Mo, D, h, mi, s)) {
			if (bad++ < 10)
				printf("%04d-%02d-%02d %02d:%02d:%02d: got %08X, expected %08X\n",
				       Y, Mo, D, h, mi, s, v, expect(Y, Mo, D, h, mi, s));
		}
		if (k < 50) {                           // the second value: ignored
			send(2030, 6, 15, 12, 0, 0);
			if (wait_ld(&v) && bad++ < 10)
				printf("a second RTC value was loaded\n");
		}
		delete m;
	}
	// an invalid value (month 0, as with nothing set): nothing loaded
	m = new Vvax_toy;
	m->rtc[0] = m->rtc[1] = m->rtc[2] = 0;
	tick();
	m->rtc[0] = 0; m->rtc[1] = 0x40u << 24; m->rtc[2] = 1;
	unsigned v;
	if (wait_ld(&v) && bad++ < 10) printf("an invalid RTC value was loaded\n");
	delete m;
	printf("%d dates, %d errors\n", n, bad);
	return bad != 0;
}

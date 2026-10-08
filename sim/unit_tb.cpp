// unit_tb.cpp - unit tests for vt_term and vax_kbd.
//   unit term <bytes.bin>      feed bytes, print screen as UTF-8 + attributes
//   unit kbd  <events.txt> es  feed "code pressed ext" lines, print bytes (hex)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vunit_top.h"
#include "Vunit_top___024root.h"
#include "verilated.h"

static Vunit_top *t;
#define R (t->rootp)
static int bells = 0;

static void tick() {
	t->clk = 1; t->eval(); t->clk = 0; t->eval();
	if (t->bell) bells++;
}
static void run(int n) { while (n--) tick(); }

static const unsigned gfx[32] = {
	0x00A0,0x25C6,0x2592,0x2409,0x240C,0x240D,0x240A,0x00B0,0x00B1,0x2424,0x240B,
	0x2518,0x2510,0x250C,0x2514,0x253C,0x23BA,0x23BB,0x2500,0x23BC,0x23BD,0x251C,
	0x2524,0x2534,0x252C,0x2502,0x2264,0x2265,0x03C0,0x2260,0x00A3,0x00B7};

static void utf8(unsigned u) {
	if (u < 0x80) putchar(u);
	else if (u < 0x800) { putchar(0xC0 | (u >> 6)); putchar(0x80 | (u & 63)); }
	else { putchar(0xE0 | (u >> 12)); putchar(0x80 | ((u >> 6) & 63)); putchar(0x80 | (u & 63)); }
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vunit_top;
	t->rst = 1; t->rx_valid = 0; t->ps2_key = 0; t->kbd_es = argc > 3 && !strcmp(argv[3], "es");
	run(10);
	t->rst = 0;
	run(3000);  // power-up clear

	if (!strcmp(argv[1], "term")) {
		FILE *f = fopen(argv[2], "rb");
		int c, n = 0;
		while ((c = fgetc(f)) != EOF) {
			t->rx_data = c; t->rx_valid = 1; tick(); t->rx_valid = 0;
			run(400);   // ~10x faster than the real 115200 baud line
			n++;
		}
		fclose(f);
		run(5000);
		int top = R->unit_top__DOT__term__DOT__top;
		for (int r = 0; r < 30; r++) {
			for (int col = 0; col < 80; col++) {
				int v = R->unit_top__DOT__term__DOT__tram[(((top + r) & 31) << 7) | col];
				int g = v & 0xff;
				utf8(g < 0x20 ? gfx[g] : g);
			}
			putchar('\n');
		}
		for (int r = 0; r < 30; r++) {           // attributes: b=bold r=reverse x=both
			for (int col = 0; col < 80; col++) {
				int v = R->unit_top__DOT__term__DOT__tram[(((top + r) & 31) << 7) | col] >> 8;
				putchar(".rbx"[v & 3]);
			}
			putchar('\n');
		}
		printf("cursor %d %d wrap %d bells %d bytes %d\n",
		       R->unit_top__DOT__term__DOT__cur_r, R->unit_top__DOT__term__DOT__cur_c,
		       R->unit_top__DOT__term__DOT__wrap, bells, n);
	} else {
		FILE *f = fopen(argv[2], "r");
		int code, pr, ext, tog = 0;
		while (fscanf(f, "%x %d %d", &code, &pr, &ext) == 3) {
			tog ^= 1;
			t->ps2_key = (tog << 10) | (pr << 9) | (ext << 8) | code;
			for (int i = 0; i < 20; i++) {
				tick();
				if (t->kbd_valid) printf("%02X ", t->kbd_data);
			}
		}
		printf("\n");
	}
	delete t;
	return 0;
}

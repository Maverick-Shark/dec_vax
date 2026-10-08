// tb.cpp - Verilator driver for the MiSTer port of r-vax.
//
//   ./obj/Vtb_top prog.bin [load_base_index] [keys] [frame.ppm]
//
// 1. power-up (SDRAM init), 2. download prog.bin through the ioctl port
// (like the HPS does), 3. autostart types FR<addr>CR G into the monitor,
// 4. waits for the program, 5. types [keys] on the PS/2 keyboard
// ('~' = Enter, uppercase letters use Shift), 6. dumps the terminal text
// RAM and one video frame (PPM).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"

static Vtb_top *tb;
static uint64_t cycles = 0;
static std::string tto_log;

#define R (tb->rootp)

static void tick() {
	tb->clk = 1; tb->eval();
	tb->clk = 0; tb->eval();
	cycles++;
	if (R->tb_top__DOT__sys__DOT__rx_valid) {
		unsigned char c = R->tb_top__DOT__sys__DOT__rx_data;
		tto_log.push_back((char)c);
		if (c == 0x1b) fputs("<ESC>", stdout);
		else if (c == '\r') ;
		else if (c == '\n' || (c >= 0x20 && c < 0x7f)) fputc(c, stdout);
		else printf("<%02X>", c);
		fflush(stdout);
	}
}

static void run(uint64_t n) { while (n--) tick(); }

static int ps2_toggle = 0;
static void ps2_event(int code, int pressed, int ext) {
	ps2_toggle ^= 1;
	tb->ps2_key = (ps2_toggle << 10) | (pressed << 9) | (ext << 8) | (code & 0xff);
	run(2000);
}

static int scancode(char c, int *shift) {
	static const char *row = "abcdefghijklmnopqrstuvwxyz";
	static const int let[] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
	                          0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
	static const int dig[] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
	*shift = 0;
	if (c >= 'A' && c <= 'Z') { *shift = 1; c = c - 'A' + 'a'; }
	if (c >= 'a' && c <= 'z') return let[strchr(row, c) - row];
	if (c >= '0' && c <= '9') return dig[c - '0'];
	switch (c) {
	case '~': return 0x5A;      // Enter
	case ' ': return 0x29;
	case '/': return 0x4A;
	}
	return -1;
}

static void type(const char *s) {
	for (; *s; s++) {
		int sh, sc = scancode(*s, &sh);
		if (sc < 0) continue;
		if (sh) ps2_event(0x12, 1, 0);
		ps2_event(sc, 1, 0);
		ps2_event(sc, 0, 0);
		if (sh) ps2_event(0x12, 0, 0);
		run(250000);            // 5 ms between keys
	}
}

static char gfx2ascii(int g) {
	// DEC special graphics glyphs 00h-1Fh (for chars 5Fh-7Eh)
	static const char *map = " *#    +-  ++++++----_++++|<>p#L.";
	return (g < 32) ? map[g] : '?';
}

static void dump_screen() {
	int top = R->tb_top__DOT__sys__DOT__term__DOT__top;
	printf("\n+--------------------------------------------------------------------------------+\n");
	for (int r = 0; r < 30; r++) {
		std::string line;
		for (int c = 0; c < 80; c++) {
			int v = R->tb_top__DOT__sys__DOT__term__DOT__tram[(((top + r) & 31) << 7) | c];
			int g = v & 0xff;
			char ch = (g < 0x20) ? gfx2ascii(g) : (g < 0x7f ? (char)g : '?');
			line.push_back(ch);
		}
		printf("|%s|\n", line.c_str());
	}
	printf("+--------------------------------------------------------------------------------+\n");
	printf("cursor row %d col %d, top %d\n",
	       R->tb_top__DOT__sys__DOT__term__DOT__cur_r,
	       R->tb_top__DOT__sys__DOT__term__DOT__cur_c, top);
}

static void grab_frame(const char *fn) {
	// wait for the start of vsync, then for the first active pixel
	while (!tb->vs) tick();
	while (tb->vs) tick();
	std::vector<unsigned char> img(640 * 480 * 3, 0);
	int x = 0, y = 0, n = 0, hs_last = 1, active_line = 0;
	while (y < 480) {
		tick();
		if (!tb->ce_pix) continue;
		// outputs were updated at the previous ce edge; sample like the scaler
		if (!tb->hblank && !tb->vblank) {
			if (x < 640) {
				img[(y * 640 + x) * 3 + 0] = tb->r;
				img[(y * 640 + x) * 3 + 1] = tb->g;
				img[(y * 640 + x) * 3 + 2] = tb->b;
			}
			x++; n++; active_line = 1;
		} else if (active_line) {
			if (x != 640) printf("line %d has %d pixels\n", y, x);
			x = 0; y++; active_line = 0;
		}
		(void)hs_last;
	}
	FILE *f = fopen(fn, "wb");
	fprintf(f, "P6\n640 480\n255\n");
	fwrite(img.data(), 1, img.size(), f);
	fclose(f);
	printf("frame written to %s (%d active pixels)\n", fn, n);
}

static void download(const std::vector<unsigned char> &data) {
	tb->ioctl_index = 1;
	tb->ioctl_download = 1;
	run(10);
	for (size_t i = 0; i < data.size(); i++) {
		while (tb->ioctl_wait) tick();
		tb->ioctl_addr = i;
		tb->ioctl_dout = data[i];
		tb->ioctl_wr = 1; tick();
		tb->ioctl_wr = 0; run(3);
	}
	while (tb->ioctl_wait) tick();
	run(10);
	tb->ioctl_download = 0;
	printf("\n[%llu] downloaded %zu bytes\n", (unsigned long long)cycles, data.size());
}

static bool wait_done(uint64_t budget) {
	size_t from = tto_log.size();
	uint64_t limit = cycles + budget;
	while (cycles < limit && tto_log.find("DONE", from) == std::string::npos) tick();
	run(500000);
	return tto_log.find("DONE", from) != std::string::npos;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	tb = new Vtb_top;
	const char *prog = argc > 1 ? argv[1] : "software/hello.bin";
	int base = argc > 2 ? atoi(argv[2]) : 0;
	const char *keys = argc > 3 ? argv[3] : "";
	const char *ppm = argc > 4 ? argv[4] : "frame.ppm";

	tb->clk = 0; tb->rst_mem = 1; tb->rst_sys = 1;
	tb->load_base = base; tb->autostart = 1; tb->color = 0; tb->kbd_es = 0;
	tb->ps2_key = 0; tb->ioctl_download = 0; tb->ioctl_wr = 0;
	run(20);
	tb->rst_mem = 0;
	run(10);
	tb->rst_sys = 0;

	while (!R->tb_top__DOT__sys__DOT__mem_ready) tick();
	printf("[%llu] SDRAM ready\n", (unsigned long long)cycles);
	run(200000);   // monitor prints the halt code after reset

	// ---- download like hps_io: one byte per ioctl_wr pulse, honour ioctl_wait
	FILE *f = fopen(prog, "rb");
	if (!f) { perror(prog); return 1; }
	std::vector<unsigned char> data;
	int c;
	while ((c = fgetc(f)) != EOF) data.push_back(c);
	fclose(f);
	download(data);

	// ---- verify memory through the SDRAM model
	static const unsigned bases[4] = {0x1000, 0x0, 0x200, 0x10000};
	unsigned b0 = bases[base & 3];
	int bad = 0;
	for (size_t i = 0; i < data.size(); i++) {
		unsigned a = b0 + i;
		unsigned hw = R->tb_top__DOT__sdram__DOT__mem[a >> 1];
		unsigned v = (a & 1) ? (hw >> 8) : (hw & 0xff);
		if (v != data[i] && bad++ < 5)
			printf("mem[%x] = %02x, expected %02x\n", a, v, data[i]);
	}
	printf("memory check: %s (%d mismatches)\n", bad ? "FAIL" : "OK", bad);

	// ---- let autostart and the program run
	bool done = wait_done(40000000ULL);
	printf("\n[%llu] program finished: %s\n", (unsigned long long)cycles, done ? "yes" : "NO");

	// ---- keyboard
	if (*keys) {
		printf("[%llu] typing \"%s\"\n", (unsigned long long)cycles, keys);
		type(keys);
		run(500000);
	}

	if (argc > 5 && !strcmp(argv[5], "again")) {
		// user reset: memory must survive, then a second download + autostart
		printf("[%llu] OSD reset\n", (unsigned long long)cycles);
		tb->rst_sys = 1; run(100); tb->rst_sys = 0;
		run(300000);
		type("1000P~");
		run(300000);
		download(data);
		done = wait_done(40000000ULL);
		printf("\n[%llu] second run finished: %s\n", (unsigned long long)cycles, done ? "yes" : "NO");
	}

	dump_screen();
	// wait for the cursor blink phase so the frame shows the cursor
	while (!(R->tb_top__DOT__sys__DOT__term__DOT__frame & 16)) tick();
	grab_frame(ppm);
	printf("audio %d, cycles %llu\n", tb->audio, (unsigned long long)cycles);
	delete tb;
	return 0;
}

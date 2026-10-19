// tb.cpp - Verilator driver for the MiSTer port of r-vax.
//
//   ./obj/Vtb_top prog.bin [load_base_index] [keys] [frame.ppm]
//
// 1. power-up (SDRAM init), 2. download prog.bin through the ioctl port
// (like the HPS does), 3. autostart types FR<addr>CR G into the monitor,
// 4. waits for the program, 5. types [keys] on the PS/2 keyboard
// ('~' = Enter, uppercase letters use Shift, '^X' = Ctrl+X, '{' = cursor
// up, which sends the three bytes ESC [ A), 6. dumps the
// terminal text RAM and one video frame (PPM).
//
// Environment:
//   NOTEST      power-on memory test off       PHASE=n   force read phase n-1
//   START200    start address 0x200            NOAUTO    no autostart
//   NOHPSRST    do not imitate the HPS holding the core in reset after it
//               sends the SDRAM size (MiSTer Main does: size, then status[0]
//               for the whole time it loads the saved settings)
//   HPSRST=n    length of that reset in clocks (default 2000000 = 40 ms)
//   MEMFILL=x   fill the whole SDRAM with 16-bit value x before anything
//               runs (default: zero); MEMFILL=rand for pseudo-random data,
//               which is what a real module holds at power-up
//   UNTIL/UNTIL2/BUDGET/HALT/BANNER/FAULT/SESSION  see below
//   SESSION     tokens separated by '|': text is typed, "@text" waits for
//               text to appear on the console (BUDGET clocks at most),
//               "!R" is an OSD reset, "!Wn" runs n clocks
//   PRELOAD=f@a put file f into memory at hex address a after the memory
//               test, as if a previous program had left it there

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"

static Vtb_top *tb;
static uint64_t cycles = 0;
static uint64_t nhit = 0, nmiss = 0, nrun = 0, ninst = 0;
static FILE *itr = 0;                   // ITRACE file
static int      halted_d = 1, state_d = 0;
static std::string tto_log;

#define R (tb->rootp)

// software UART receiver on UART_TXD, 115200 baud equivalent (435 clocks/bit)
static std::string uart_log;
static void uart_sample() {
	static int phase = -1, bit = 0, val = 0;
	static int cnt = 0;
	if (phase < 0) {
		if (!tb->uart_txd) { phase = 0; cnt = 435 / 2; bit = 0; val = 0; }
		return;
	}
	if (--cnt > 0) return;
	cnt = 435;
	if (phase == 0) {                 // middle of the start bit
		if (tb->uart_txd) { phase = -1; return; }
		phase = 1;
		return;
	}
	if (bit < 8) { val |= tb->uart_txd << bit; bit++; return; }
	if (tb->uart_txd) uart_log.push_back((char)val);   // stop bit present
	phase = -1;
}

static int prof_on = 0, prof_last = -1;
static uint64_t prof_t, prof_cyc[256], prof_cnt[256];

static void prof_print() {
	uint64_t tot = 0;
	int idx[256];
	for (int i = 0; i < 256; i++) { tot += prof_cyc[i]; idx[i] = i; }
	std::sort(idx, idx + 256, [](int a, int b) { return prof_cyc[a] > prof_cyc[b]; });
	printf("profile: %llu clocks between decodes\n", (unsigned long long)tot);
	for (int k = 0; k < 25 && prof_cyc[idx[k]]; k++) {
		int i = idx[k];
		printf("  %02X  %10llu insts %12llu clocks %5.1f%%  %6.1f per inst\n", i,
		       (unsigned long long)prof_cnt[i], (unsigned long long)prof_cyc[i],
		       100.0 * prof_cyc[i] / tot, (double)prof_cyc[i] / prof_cnt[i]);
	}
}

static void tick() {
	tb->clk = 1; tb->eval();
	tb->clk = 0; tb->eval();
	cycles++;
	uart_sample();
	if (R->tb_top__DOT__sys__DOT__core__DOT__cache__DOT__stat_hit)  nhit++;
	if (R->tb_top__DOT__sys__DOT__core__DOT__cache__DOT__stat_miss) nmiss++;
	// cycles with the CPU actually running, and instructions decoded
	int h = R->tb_top__DOT__sys__DOT__cpu_halted;
	if (!h) nrun++;
	int st = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__state;
	if (st == 10 && state_d != 10) ninst++;
	// EXCTRACE: every entry into the CPU's fault microcode (XFAULT): 2 reserved
	// operand, 4 memory management, 5 kernel stack not valid, 7 reserved
	// instruction; and every halt
	static int exctrace = getenv("EXCTRACE") ? 1 : 0;
	if (exctrace && st == 22 && state_d != 22)
		printf("\n[%llu] XFAULT entry %d pc %08X opcode %02X psl %08X\n",
		       (unsigned long long)cycles,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__xentry,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__oldpc,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__cur_inst,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__oldpsl);
	if (exctrace && st == 0 && state_d != 0)
		printf("\n[%llu] HALT code %X pc %08X oldpc %08X opcode %02X psl %08X\n",
		       (unsigned long long)cycles,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__haltpos,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__curpc,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__oldpc,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__cur_inst,
		       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__psl);
	// ITRACE=file: PC, PSL and opcode of every instruction, from cycle
	// ITRACE_FROM on (for comparing with a reference simulator's trace)
	static uint64_t itr_from = 0;
	static int itr_init = 0;
	if (!itr_init) {
		itr_init = 1;
		if (const char *f = getenv("ITRACE")) {
			itr = fopen(f, "w");
			if (const char *fr = getenv("ITRACE_FROM")) itr_from = strtoull(fr, 0, 0);
		}
	}
	// PROFILE: clocks from one instruction decode to the next, per opcode
	// (operand decode, execution, the following fetch and any interrupt or
	// exception in between), printed at the end
	if (prof_on && st == 10 && state_d != 10 && !h) {
		if (prof_last >= 0) {
			prof_cyc[prof_last] += cycles - prof_t;
			prof_cnt[prof_last]++;
		}
		prof_last = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__cur_inst;
		prof_t = cycles;
	}
	static int itr_regs = getenv("ITRACE_REGS") ? 1 : 0;
	if (itr && st == 10 && state_d != 10 && cycles >= itr_from) {
		fprintf(itr, "%08X %08X %02X",
		        R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__oldpc,
		        R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__psl,
		        R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__cur_inst);
		if (itr_regs)		// ITRACE_REGS: R0-R14 before the instruction
			for (int i = 0; i < 15; i++)
				fprintf(itr, " %08X", R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__general_reg[i]);
		fputc('\n', itr);
	}
	state_d = st; halted_d = h;
	// INTTRACE: every interrupt the CPU takes: PC, PSL, the level and the
	// request lines when it starts, and the SCB vector it ends up using
	static int inttrace = getenv("INTTRACE") ? 1 : 0;
	if (inttrace) {
		static int d_intr = 0;
		int di = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__doing_intr;
		if (di && !d_intr)
			printf("\n[%llu] INTR pc %08X psl %08X intlvl %02X hwint %04X swint %04X\n",
			       (unsigned long long)cycles,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__curpc,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__psl,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__intlvl,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__hwint,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__swint);
		if (!di && d_intr)
			printf("[%llu] INTR end: vector %08X psl %08X\n", (unsigned long long)cycles,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__argd[1],
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__psl);
		d_intr = di;
	}
	// RXTRACE: log the console receiver as the CPU sees it
	static int rxtrace = getenv("RXTRACE") ? 1 : 0;
	if (rxtrace) {
		static int d_done = 0, d_irq = 0, d_ie = 0;
		int done = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__consrx__DOT__done;
		int irq  = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__consrx__DOT__intreq;
		int ie   = R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__consrx__DOT__inten;
		if (done != d_done || irq != d_irq || ie != d_ie)
			printf("\n[%llu] RX done %d->%d irq %d->%d ie %d->%d char %02X ipr_addr %02X ipl %02X pc %08X halted %d\n",
			       (unsigned long long)cycles, d_done, done, d_irq, irq, d_ie, ie,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__consrx__DOT__rxraw & 0xFF,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__ipr_addr,
			       (R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__psl >> 16) & 0x1F,
			       R->tb_top__DOT__sys__DOT__core__DOT__cpu__DOT__oldpc, h);
		d_done = done; d_irq = irq; d_ie = ie;
	}
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
	case '?': *shift = 1; return 0x4A;
	case '.': return 0x49;
	case ',': return 0x41;
	case '-': return 0x4E;
	case '+': *shift = 1; return 0x55;
	case '=': return 0x55;
	case ';': return 0x4C;
	case ':': *shift = 1; return 0x4C;
	case '_': *shift = 1; return 0x4E;
	}
	return -1;
}

static void type(const char *s) {
	for (; *s; s++) {
		int ctrl = 0;
		if (*s == '{') {                              // { = cursor up (ESC [ A)
			ps2_event(0x75, 1, 1);
			ps2_event(0x75, 0, 1);
			run(250000);
			continue;
		}
		if (*s == '^' && s[1]) { ctrl = 1; s++; }    // ^X = Ctrl+X
		int sh, sc = scancode(*s, &sh);
		if (sc < 0) continue;
		if (ctrl) { sh = 0; ps2_event(0x14, 1, 0); }
		if (sh) ps2_event(0x12, 1, 0);
		ps2_event(sc, 1, 0);
		ps2_event(sc, 0, 0);
		if (sh) ps2_event(0x12, 0, 0);
		if (ctrl) ps2_event(0x14, 0, 0);
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

static bool wait_done(uint64_t budget, const char *pat) {
	uint64_t limit = cycles + budget;
	// stop on the pattern, or (with HALT set) when the CPU halts again
	size_t from = tto_log.size();
	uint64_t limit0 = cycles;
	(void)limit0;
	bool usehalt = getenv("HALT") != 0;
	int seen_run = 0;
	while (cycles < limit) {
		tick();
		if (tto_log.find(pat ? pat : "DONE", from) != std::string::npos) break;
		if (usehalt) {
			if (!R->tb_top__DOT__sys__DOT__cpu_halted) seen_run = 1;
			else if (seen_run) break;
		}
	}
	run(200000);
	return tto_log.find(pat ? pat : "DONE", from) != std::string::npos;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	tb = new Vtb_top;
	const char *prog = argc > 1 ? argv[1] : "software/hello.bin";
	int base = argc > 2 ? atoi(argv[2]) : 0;
	const char *keys = argc > 3 ? argv[3] : "";
	const char *ppm = argc > 4 ? argv[4] : "frame.ppm";

	tb->clk = 0; tb->rst_mem = 1; tb->rst_sys = 1;
	tb->load_base = base; tb->autostart = getenv("NOAUTO") ? 0 : 1; tb->color = 0; tb->kbd_es = 0;
	tb->ps2_key = 0; tb->ioctl_download = 0; tb->ioctl_wr = 0;
	tb->start_200 = getenv("START200") ? 1 : 0;
	tb->selftest_en = getenv("NOTEST") ? 0 : 1;
	prof_on = getenv("PROFILE") ? 1 : 0;
	tb->selftest_go = 0; tb->uart_rxd = 1;
	tb->rdphase_sel = getenv("PHASE") ? atoi(getenv("PHASE")) : 0;
	tb->sdram_sz = 0;                       // the HPS reports it later
	run(20);
	// after the first eval, so the model's initial block has already run
	if (const char *mf = getenv("MEMFILL")) {
		unsigned v = strtoul(mf, 0, 0), x = 0x12345678;
		bool rnd = !strcmp(mf, "rand");
		for (unsigned i = 0; i < (1u << 24); i++) {
			if (rnd) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; }
			R->tb_top__DOT__sdram__DOT__mem[i] = rnd ? (x & 0xFFFF) : v;
		}
		printf("SDRAM filled with %s\n", rnd ? "pseudo-random data" : mf);
	}
	tb->rst_mem = 0;
	run(10);
	tb->rst_sys = 0;

	while (!R->tb_top__DOT__sys__DOT__mem_ready) tick();
	printf("[%llu] SDRAM ready\n", (unsigned long long)cycles);
	// the HPS announces the module a little later, as on real hardware
	run(30000);
	tb->sdram_sz = 0x8001;                  // valid, 32 MB
	run(20);
	if (!getenv("NOHPSRST")) {
		// MiSTer Main: UIO_SET_MEMSZ, then status[0] = 1 a few microseconds
		// later, held while it loads the saved settings, then released
		uint64_t len = getenv("HPSRST") ? strtoull(getenv("HPSRST"), 0, 0) : 2000000ULL;
		run(1000);
		tb->rst_sys = 1;
		printf("[%llu] HPS holds the core in reset\n", (unsigned long long)cycles);
		run(len);
		tb->rst_sys = 0;
		printf("[%llu] HPS releases the reset\n", (unsigned long long)cycles);
	}
	{
		// optional fault injection: corrupt one longword once the test has
		// finished writing, to exercise the FAIL report
		const char *flt = getenv("FAULT");
		unsigned flw = flt ? strtoul(flt, 0, 0) : 0;
		bool done = !flt;
		while (R->tb_top__DOT__sys__DOT__st_pending || R->tb_top__DOT__sys__DOT__st_busy) {
			tick();
			if (!done && R->tb_top__DOT__sys__DOT__selftest__DOT__tst == 3) {
				R->tb_top__DOT__sdram__DOT__mem[flw * 2] ^= 0x0040;
				printf("[%llu] injected a fault at longword 0x%X\n",
				       (unsigned long long)cycles, flw);
				done = true;
			}
		}
	}
	printf("[%llu] self test done, fail=%d, phases ok=%X, using phase %d\n",
	       (unsigned long long)cycles,
	       R->tb_top__DOT__sys__DOT__st_fail,
	       R->tb_top__DOT__sys__DOT__selftest__DOT__ok,
	       R->tb_top__DOT__sys__DOT__st_best);
	run(200000);   // monitor prints the halt code after reset
	if (getenv("BANNER")) { dump_screen(); grab_frame(ppm); delete tb; return 0; }

	// PRELOAD=file@hexaddr: put a file straight into the SDRAM model, as if
	// an earlier program had been loaded there (memory left over from it)
	if (const char *pl = getenv("PRELOAD")) {
		std::string spec(pl);
		size_t at = spec.find('@');
		std::string fn = spec.substr(0, at);
		unsigned pa = (at == std::string::npos) ? 0 : strtoul(spec.c_str() + at + 1, 0, 16);
		FILE *pf = fopen(fn.c_str(), "rb");
		if (!pf) { perror(fn.c_str()); return 1; }
		int ch, n = 0;
		while ((ch = fgetc(pf)) != EOF) {
			unsigned a = pa + n++;
			unsigned short &w = R->tb_top__DOT__sdram__DOT__mem[a >> 1];
			w = (a & 1) ? ((w & 0x00FF) | (ch << 8)) : ((w & 0xFF00) | ch);
		}
		fclose(pf);
		printf("preloaded %s (%d bytes) at 0x%X\n", fn.c_str(), n, pa);
	}

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
	const char *bud = getenv("BUDGET");
	uint64_t budget = bud ? strtoull(bud, 0, 0) : 40000000ULL;
	const char *u1 = getenv("UNTIL");
	bool done = wait_done(budget, u1 ? u1 : "DONE");
	printf("\n[%llu] stage 1 (%s): %s\n", (unsigned long long)cycles,
	       u1 ? u1 : "DONE", done ? "matched" : "NOT matched");

	// ---- keyboard, then an optional second wait
	if (*keys) {
		printf("[%llu] typing \"%s\"\n", (unsigned long long)cycles, keys);
		type(keys);
		run(500000);
		const char *u2 = getenv("UNTIL2");
		if (u2) {
			bool d2 = wait_done(budget, u2);
			printf("\n[%llu] stage 2 (%s): %s\n", (unsigned long long)cycles,
			       u2, d2 ? "matched" : "NOT matched");
		}
	}

	if (argc > 5 && !strcmp(argv[5], "again")) {
		// user reset: memory must survive, then a second download + autostart
		printf("[%llu] OSD reset\n", (unsigned long long)cycles);
		tb->rst_sys = 1; run(100); tb->rst_sys = 0;
		run(300000);
		type("1000P~");
		run(300000);
		download(data);
		done = wait_done(40000000ULL, "DONE");
		printf("\n[%llu] second run finished: %s\n", (unsigned long long)cycles, done ? "yes" : "NO");
	}

	if (getenv("SESSION")) {
		char *sc = strdup(getenv("SESSION"));
		const char *bud2 = getenv("BUDGET");
		uint64_t sbudget = bud2 ? strtoull(bud2, 0, 0) : 40000000ULL;
		for (char *tok = strtok(sc, "|"); tok; tok = strtok(0, "|")) {
			if (tok[0] == '@') {
				bool ok = wait_done(sbudget, tok + 1);
				printf("\n[%llu] --- waiting for \"%s\": %s\n",
				       (unsigned long long)cycles, tok + 1, ok ? "seen" : "NOT seen");
				continue;
			}
			if (!strcmp(tok, "!R")) {               // OSD Reset
				printf("\n[%llu] --- OSD reset\n", (unsigned long long)cycles);
				tb->rst_sys = 1; run(100); tb->rst_sys = 0;
				run(300000);
				continue;
			}
			if (tok[0] == '!' && tok[1] == 'W') {   // !Wn: just run n clocks
				run(strtoull(tok + 2, 0, 0));
				continue;
			}
			printf("\n[%llu] --- typing: %s\n", (unsigned long long)cycles, tok);
			type(tok);
			run(2000000);
		}
		free(sc);
	}

	dump_screen();
	// wait for the cursor blink phase so the frame shows the cursor
	while (!(R->tb_top__DOT__sys__DOT__term__DOT__frame & 16)) tick();
	grab_frame(ppm);
	printf("audio %d, cycles %llu\n", tb->audio, (unsigned long long)cycles);
	printf("MiSTer UART captured %zu bytes; last line: ", uart_log.size());
	{
		size_t e = uart_log.find_last_not_of("\r\n");
		size_t b = (e == std::string::npos) ? 0 : uart_log.find_last_of('\n', e);
		for (size_t i = (b == std::string::npos ? 0 : b + 1); i <= e && i < uart_log.size(); i++)
			putchar(uart_log[i] >= 0x20 ? uart_log[i] : '.');
		putchar('\n');
	}
	printf("cache: %llu hits, %llu misses (%.1f%% hit rate)\n",
	       (unsigned long long)nhit, (unsigned long long)nmiss,
	       (nhit + nmiss) ? 100.0 * nhit / (nhit + nmiss) : 0.0);
	printf("cpu: %llu instructions in %llu running clocks, CPI %.2f, %.3f MIPS at 50 MHz\n",
	       (unsigned long long)ninst, (unsigned long long)nrun,
	       ninst ? (double)nrun / ninst : 0.0,
	       nrun ? 50.0 * ninst / nrun : 0.0);
	if (itr) fclose(itr);
	if (prof_on) prof_print();
	if (const char *tl = getenv("TTOLOG")) {        // everything the CPU printed
		FILE *f = fopen(tl, "wb");
		if (f) { fwrite(tto_log.data(), 1, tto_log.size(), f); fclose(f); }
	}
	delete tb;
	return 0;
}

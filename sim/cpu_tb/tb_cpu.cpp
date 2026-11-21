// tb_cpu.cpp - driver for the CPU-level test bench (tb_cpu.v).
//
//   obj_cpu/Vtb_cpu prog.bin loadaddr startpc [maxclocks] [dump...]
//
// loadaddr, startpc: hex. dump: hexaddr:count (count longwords, hex too).
// The program is copied into the memory model, the CPU is taken out of its
// halt state at startpc with PSL = 041F0000 (kernel, interrupt stack,
// IPL 1F: what a VAX has after power-up), and runs until it halts or the
// clock budget runs out. Output, one item per line, so that tests/mmu/run.py
// can compare it with the reference simulator's:
//
//   HALT code pc       halt code from the CPU and the PC after the halt
//   R0 .. R14          general registers
//   PSL                processor status longword
//   M addr value       memory longwords asked for
//   CLOCKS n           clocks until the halt
//
// Environment: TRACE=1 prints every instruction (PC, opcode); BUSTRACE=1
// prints every state change of the CPU, vcache and MMU with the bus signals;
// TTO=1 prints what the program sends to the console terminal (MTPR TXDB),
// decoded from the console line, on stderr as it comes (TTOLOG=1 also as
// "C clock hex" lines on stdout). PCSAMPLE=n prints "P clock pc psl" every
// n clocks (long runs: where the program spends its time). TBOFF=1 turns the
// MMU's translation buffer off (the OSD's fault finding option): every
// reference walks the page tables, and only what TBCHK reports may change.
//
// Disks: DISK0 and DISK1 give the images of the RP07 units 0 and 1, served
// as the HPS serves them on the board (see ../hpsdisk.h: an image file or a
// generated disk); no DISKn, no image mounted on that unit. SDLAT and
// SDTRACE: see there.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <map>
#include <string>
#include "../hpsdisk.h"
#include "Vtb_cpu.h"
#include "Vtb_cpu___024root.h"
#include "verilated.h"

static Vtb_cpu *tb;
static uint64_t cycles = 0;
#define R (tb->rootp)
#define CPU(x) R->tb_cpu__DOT__cpu__DOT__##x

static HpsDisk hps;                     // the disk images (../hpsdisk.h)

// the console line (tto_tx), 8N1 at CLKPERBIT + 1 clocks a bit
static bool tto_on = false;
static bool tto_log = false;            // TTOLOG=1: also "C clock hex" on stdout
static int  tto_st = -2, tto_cnt = 0, tto_bits = 0, tto_ch = 0;
static void tto_step() {
	const int bit = 17;                 // CLKPERBIT 16
	int line = R->tb_cpu__DOT__tto_tx;
	if (tto_st == -2) {                 // first a character time of idle line
		tto_cnt = line ? tto_cnt + 1 : 0;
		if (tto_cnt >= 12 * bit) tto_st = -1;
		return;
	}
	if (tto_st < 0) {                   // idle: wait for the start bit
		if (!line) { tto_st = 0; tto_cnt = bit / 2; tto_bits = 0; tto_ch = 0; }
		return;
	}
	if (--tto_cnt > 0)
		return;
	tto_cnt = bit;
	if (tto_st == 0) {                  // the middle of the start bit
		tto_st = line ? -1 : 1;
	} else if (tto_bits < 8) {
		tto_ch |= line << tto_bits++;
	} else {                            // the stop bit
		fputc(tto_ch & 0x7F, stderr);
		fflush(stderr);
		if (tto_log) {
			printf("C %llu %02X\n", (unsigned long long)cycles, tto_ch & 0x7F);
			fflush(stdout);
		}
		tto_st = -1;
	}
}

static void tick() {
	hps.step(cycles);
	tb->clk = 1; tb->eval();
	tb->clk = 0; tb->eval();
	cycles++;
	if (tto_on)
		tto_step();
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 4) {
		fprintf(stderr, "usage: %s prog.bin loadaddr startpc [maxclocks] [addr:count...]\n", argv[0]);
		return 2;
	}
	tb = new Vtb_cpu;
	// The memory array starts cleared, as the reference simulator's. The
	// registers start as Verilator was told: zero, or, on the bench built
	// with --x-initial unique (make -C sim cputbx) and run with
	// +verilator+rand+reset+2 +verilator+seed+n, random - which shows any
	// register that processor initialization leaves undefined and the
	// machine then depends on.
	for (size_t i = 0; i < (size_t)1 << 23; i++)
		R->tb_cpu__DOT__mem[i] = 0;
	unsigned load = strtoul(argv[2], 0, 16);
	unsigned start = strtoul(argv[3], 0, 16);
	uint64_t maxc = argc > 4 ? strtoull(argv[4], 0, 0) : 2000000ULL;
	bool trace = getenv("TRACE") != 0;
	bool bustrace = getenv("BUSTRACE") != 0;
	bool utrace = getenv("UTRACE") != 0;
	bool strace = getenv("STRACE") != 0;	// every state change

	hps.init(HpsPorts{{&tb->sd_lba0, &tb->sd_lba1}, &tb->sd_rd, &tb->sd_wr,
	                  &tb->sd_ack, &tb->sd_buff_addr, &tb->sd_buff_dout,
	                  &tb->sd_buff_wr, {&tb->sd_buff_din0, &tb->sd_buff_din1},
	                  &tb->img_mounted, &tb->img_readonly, &tb->img_size});
	tb->tb_off = getenv("TBOFF") ? 1 : 0;       // taken at reset
	tb->clk = 0; tb->rst = 1;
	for (int i = 0; i < 10; i++) tick();
	tb->rst = 0;
	for (int i = 0; i < 10; i++) tick();

	// the images, mounted one after the other as the HPS does
	for (int u = 0; u < 2; u++)
		for (int k = 0; k < 3; k++) { hps.mount_step(u, k); tick(); }
	// then processor initialization, as a program load on the board does:
	// the drives' attention from the mount is cleared
	tb->rst = 1;
	for (int i = 0; i < 10; i++) tick();
	tb->rst = 0;
	for (int i = 0; i < 10; i++) tick();

	// program into memory
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 1; }
	std::vector<unsigned char> d;
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	for (size_t i = 0; i < d.size(); i++) {
		unsigned a = load + i;
		uint32_t &w = R->tb_cpu__DOT__mem[a >> 2];
		int sh = (a & 3) * 8;
		w = (w & ~(0xFFu << sh)) | ((uint32_t)d[i] << sh);
	}

	// start the CPU: what the console's "G" command ends up doing
	// (the console monitor may still be sending its prompt: the decoder
	// waits for an idle line first)
	tto_on = getenv("TTO") != 0;
	tto_log = tto_on && getenv("TTOLOG") != 0;
	// PCSAMPLE=n: "P clock pc psl" every n clocks, for long runs
	uint64_t pcsample = getenv("PCSAMPLE") ? strtoull(getenv("PCSAMPLE"), 0, 0) : 0;
	for (int i = 0; i < 15; i++)                // R0-R14 as the reference's
		R->tb_cpu__DOT__cpu__DOT__general_reg[i] = 0;
	CPU(curpc) = start;
	CPU(ivalid) = 0;
	CPU(resopflt) = 0;
	CPU(manhalt) = 0;
	CPU(state) = 1;                     // S_FETCH
	tb->eval();

	int st_d = -1;
	uint64_t t0 = cycles;
	while (cycles - t0 < maxc) {
		tick();
		int st = CPU(state);
		if (trace && st == 10 && st_d != 10)   // S_DECODE
			printf("T %08X %02X %llu\n", CPU(oldpc), CPU(cur_inst), (unsigned long long)cycles);
		if (utrace && st == 20 && st_d != 20)    // PREEXEC: microcode step
			printf("U %llu step %d psl %08X\n", (unsigned long long)cycles, CPU(scounter), CPU(psl));
		if (strace && st != st_d)
			printf("S %llu state %d step %d pc %08X psl %08X\n", (unsigned long long)cycles,
			    st, CPU(scounter), CPU(curpc), CPU(psl));
		if (bustrace) {
			static int mst_d = -1, vst_d = -1, mc_d = 0;
			int mst = R->tb_cpu__DOT__mmu__DOT__state;
			int vst = R->tb_cpu__DOT__vcache__DOT__state;
			int mc = CPU(mcheck);
			if (mst != mst_d || vst != vst_d || st != st_d || mc != mc_d)
				printf("B %llu cpu %d stb %d we %d addr %08X sz %d pmem %d | vc %d ut_stb %d ut_adr %08X | mmu %d va %08X flt %d | bus stb %d we %d adr %08X ack %d | mc %d\n",
				    (unsigned long long)cycles, st, R->tb_cpu__DOT__cpu_stb, R->tb_cpu__DOT__cpu_write,
				    R->tb_cpu__DOT__cpu_addr, R->tb_cpu__DOT__cpu_size, R->tb_cpu__DOT__cpu_pmem,
				    vst, R->tb_cpu__DOT__va_stb, R->tb_cpu__DOT__va_addr,
				    mst, R->tb_cpu__DOT__mmu__DOT__va, R->tb_cpu__DOT__mmu_flt,
				    R->tb_cpu__DOT__bus_stb, R->tb_cpu__DOT__bus_write, R->tb_cpu__DOT__bus_addr,
				    R->tb_cpu__DOT__bus_ack, mc);
			mst_d = mst; vst_d = vst; mc_d = mc;
		}
		st_d = st;
		if (pcsample && (cycles - t0) % pcsample == 0) {
			printf("P %llu %08X %08X\n", (unsigned long long)(cycles - t0), CPU(curpc), CPU(psl));
			fflush(stdout);
		}
		if (st == 0) break;                    // S_HALT
	}
	bool timeout = CPU(state) != 0;
	printf("HALT %d %08X%s\n", timeout ? -1 : (int)CPU(haltpos), CPU(curpc),
	       timeout ? " TIMEOUT" : "");
	for (int i = 0; i < 15; i++)
		printf("R%d %08X\n", i, R->tb_cpu__DOT__cpu__DOT__general_reg[i]);
	printf("PSL %08X\n", CPU(psl));
	for (int i = 5; i < argc; i++) {
		if (argv[i][0] == '+') continue;       // a Verilator plusarg
		unsigned a = strtoul(argv[i], 0, 16), n = 1;
		const char *colon = strchr(argv[i], ':');
		if (colon) n = strtoul(colon + 1, 0, 16);
		for (unsigned k = 0; k < n; k++, a += 4)
			printf("M %08X %08X\n", a, R->tb_cpu__DOT__mem[(a >> 2) & 0x7FFFFF]);
	}
	printf("CLOCKS %llu\n", (unsigned long long)(cycles - t0));
	delete tb;
	return 0;
}

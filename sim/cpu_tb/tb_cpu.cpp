// tb_cpu.cpp - driver for the CPU-level test bench (tb_cpu.v).
//
//   obj_cpu/Vtb_cpu prog.bin loadaddr startpc [maxclocks] [dump...]
//
// loadaddr, startpc: hex. dump: hexaddr:count (count longwords, hex too).
// The program is copied into the memory model, the CPU is taken out of its
// halt state at startpc with PSL = 041F0000 (kernel, interrupt stack,
// IPL 1F: what a VAX has after power-up), and runs until it halts or the
// clock budget runs out. Output, one item per line, so that tests/mmu/run.py
// can compare it with simh:
//
//   HALT code pc       halt code from the CPU and the PC after the halt
//   R0 .. R14          general registers
//   PSL                processor status longword
//   M addr value       memory longwords asked for
//   CLOCKS n           clocks until the halt
//
// Environment: TRACE=1 prints every instruction (PC, opcode); BUSTRACE=1
// prints every state change of the CPU, vcache and MMU with the bus signals.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vtb_cpu.h"
#include "Vtb_cpu___024root.h"
#include "verilated.h"

static Vtb_cpu *tb;
static uint64_t cycles = 0;
#define R (tb->rootp)
#define CPU(x) R->tb_cpu__DOT__cpu__DOT__##x

static void tick() {
	tb->clk = 1; tb->eval();
	tb->clk = 0; tb->eval();
	cycles++;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 4) {
		fprintf(stderr, "usage: %s prog.bin loadaddr startpc [maxclocks] [addr:count...]\n", argv[0]);
		return 2;
	}
	tb = new Vtb_cpu;
	unsigned load = strtoul(argv[2], 0, 16);
	unsigned start = strtoul(argv[3], 0, 16);
	uint64_t maxc = argc > 4 ? strtoull(argv[4], 0, 0) : 2000000ULL;
	bool trace = getenv("TRACE") != 0;
	bool bustrace = getenv("BUSTRACE") != 0;
	bool utrace = getenv("UTRACE") != 0;

	tb->clk = 0; tb->rst = 1;
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
		if (st == 0) break;                    // S_HALT
	}
	bool timeout = CPU(state) != 0;
	printf("HALT %d %08X%s\n", timeout ? -1 : (int)CPU(haltpos), CPU(curpc),
	       timeout ? " TIMEOUT" : "");
	for (int i = 0; i < 15; i++)
		printf("R%d %08X\n", i, R->tb_cpu__DOT__cpu__DOT__general_reg[i]);
	printf("PSL %08X\n", CPU(psl));
	for (int i = 5; i < argc; i++) {
		unsigned a = strtoul(argv[i], 0, 16), n = 1;
		const char *colon = strchr(argv[i], ':');
		if (colon) n = strtoul(colon + 1, 0, 16);
		for (unsigned k = 0; k < n; k++, a += 4)
			printf("M %08X %08X\n", a, R->tb_cpu__DOT__mem[(a >> 2) & 0x1FFFFF]);
	}
	printf("CLOCKS %llu\n", (unsigned long long)(cycles - t0));
	delete tb;
	return 0;
}

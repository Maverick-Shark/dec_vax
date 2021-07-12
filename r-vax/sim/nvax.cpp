/*	$Id$	*/ 
#include <err.h>
#include <stdlib.h>
#include <unistd.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

int cpubusdebug, itrace, mcode, itrace2;

unsigned long nticks;
void dumpvcache(Vnvax *tb);
void cpubusdump(Vnvax *tb);
void itracedump(Vnvax *tb);
void itrace2dump(Vnvax *tb);
void loadfile(char *, int);

int nflag, port;

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	Vnvax *tb = new Vnvax;
	int needeval, off, ch;
	char *fn;

	port = 10000;
	fn = NULL;
	off = 0;
	while ((ch = getopt(argc, argv, "o:l:f:np:d:")) != -1)
		switch (ch) {
		case 'o': // Error out file
			if (freopen(optarg, "w", stderr) == NULL)
				err(1, "stderr");
			setvbuf(stderr, NULL, _IONBF, 0); // paranoia
			break;

		case 'l': // load address
			off = strtol(optarg, 0, 0);
			break;

		case 'n':
			nflag++;
			break;

		case 'p':
			port = strtol(optarg, 0, 0);
			break;

		case 'f': // offset
			fn = optarg;
			break;

		case 'd': // debug
			if (strcmp(optarg, "cpubus") == 0)
				cpubusdebug++;
			else if (strcmp(optarg, "itrace") == 0)
				itrace++;
			else if (strcmp(optarg, "itrace2") == 0)
				itrace++, itrace2++;
			else if (strcmp(optarg, "mcode") == 0)
				mcode++;
			else
				errx(1, "unknown flag %s", optarg);
			break;

		default:
			errx(1, "unknown arg");
		}

	if (fn)
		loadfile(fn, off);


	ttiinit();

	tb->tti_rx = 1;

	tb->n_rst = 0;
	tick(tb);
	tb->n_rst = 1;

	while(!Verilated::gotFinish()) {
		needeval = 0;

		if (tto_active || tb->tto_tx == 0)
			ttoexec(tb);

		if (tti_active || ttisig) {
			ttiexec(tb);
			needeval++;
		}

//if (tb->sbi__DOT__qbus__DOT__dl11_tto__DOT__state > 1)
//	fprintf(stderr, "dl11 state %d)\r\n", tb->sbi__DOT__qbus__DOT__dl11_tto__DOT__state);

		if (needeval)
			tb->eval();

		if (itrace && tb->sbi__DOT__cpu__DOT__state == 1 &&
		    tb->sbi__DOT__cpu__DOT__isvalid) // S_FETCH
			itracedump(tb);
		if (itrace2 && tb->sbi__DOT__cpu__DOT__state == 19)
			itrace2dump(tb); // ENDINST
		if (cpubusdebug && tb->sbi__DOT__cpu_stb)
			cpubusdump(tb);
//		if (tb->sbi__DOT__con_stb != 0)
//			dumpvcache(tb);

		tick(tb);
	}

	exit(EXIT_SUCCESS);
}

void
tick(Vnvax *tb)
{
	nticks++;

	tb->clkin = 1;
	tb->eval();

	sdramexec(tb);

	tb->clkin = 0;
	tb->eval();
}

void
cpubusdump(Vnvax *tb)
{
	static long lasttick, firsttick;

if ((tb->sbi__DOT__cpu_addr == 0x20001f76 || tb->sbi__DOT__cpu_addr == 0x20001f74) && tb->sbi__DOT__cpu__DOT__halted == 0)
	return;

	if (lasttick+1 < nticks) {
		firsttick = nticks;
		lasttick = nticks;
		fprintf(stderr, "--- NEWCYC\r\n");
	} else if (lasttick+1 == nticks)
		lasttick = nticks;

	if (firsttick+128 < nticks) {
		fprintf(stderr, "cpubus hung\r\n");
fprintf(stderr, "caddrl %x caddrh %x state %d\r\n", tb->sbi__DOT__vcache__DOT__caddrl, tb->sbi__DOT__vcache__DOT__caddrh, tb->sbi__DOT__vcache__DOT__state);
		fflush(stderr);
		sleep(1);
		exit(1);
	}

	fprintf(stderr, "CPUBUS %ld) ", nticks);
	fprintf(stderr, "dest %s stb %d addr %#x we %d wdata %#x ",
	    tb->sbi__DOT__cpu__DOT__cpu_pmem ? "P" : "V",
	    tb->sbi__DOT__cpu_stb, tb->sbi__DOT__cpu_addr, 
	    tb->sbi__DOT__cpu_write, tb->sbi__DOT__cpu_wdata);
	fprintf(stderr, "rdata %#x ack %d resopflt %d\r\n", 
	    tb->sbi__DOT__cpu_rdata, tb->sbi__DOT__cpu_ack,
	    tb->sbi__DOT__cpu__DOT__resopflt);
}

#if 0
void
dumpvcache(Vnvax *tb)
{
	const static char *states[] = { "IDLE", "FASTPATH", "SLOWRMEM", 
	    "SLOWRMEM2", "SLOWRMEM3", "RETWD", "SETWD", "WRHIGH",
	    "WRHIGH2", "WRHIGH3" };



	printf("\r\n---- Vcache: %ld\r\n", nticks);
	printf("in: addr %#x wdata %#x rdata %#x write %d stb %d sz %d ack %d\r\n",
	    tb->sbi__DOT__con_addr, tb->sbi__DOT__con_wdata,
	    tb->sbi__DOT__cpu_rdata,
	    tb->sbi__DOT__con_write, tb->sbi__DOT__con_stb, 
	    2, tb->sbi__DOT__cpu_ack);
	printf("ut: addr %#x wdata %#x rdata %#x write %d stb %d ack %d\r\n",
	    tb->sbi__DOT__mmu_to_sw_addr << 2, tb->sbi__DOT__mmu_to_sw_wdata,
	    tb->sbi__DOT__cpu_rdata, tb->sbi__DOT__mmu_to_sw_write,
	    tb->sbi__DOT__mmu_to_sw_stb, tb->sbi__DOT__sdram__DOT__pack);
	printf("state %s\r\n", states[tb->sbi__DOT__vcache__DOT__state]);
	printf("-------\r\n");
}
#endif

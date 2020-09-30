/*	$Id$	*/

#include <stdlib.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

unsigned long nticks;
void dumpvcache(Vnvax *tb);

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	Vnvax *tb = new Vnvax;
	int needeval;

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

		if (needeval)
			tb->eval();

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


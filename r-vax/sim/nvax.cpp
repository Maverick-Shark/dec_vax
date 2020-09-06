/*	$Id$	*/

#include <stdlib.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

unsigned long nticks;

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	Vnvax *tb = new Vnvax;

	ttiinit();

	tb->tti_rx = 1;

	tb->n_rst = 0;
	tick(tb);
	tb->n_rst = 1;

	while(!Verilated::gotFinish()) {

		if (tto_active || tb->tto_tx == 0)
			ttoexec(tb);

		if (tti_active || ttisig)
			ttiexec(tb);

		tick(tb);
	}

	exit(EXIT_SUCCESS);
}

void
tick(Vnvax *tb)
{
	nticks++;

	tb->clkin = 0;
	tb->eval();

	tb->clkin = 1;
	tb->eval();

	tb->clkin = 0;
	tb->eval();
}

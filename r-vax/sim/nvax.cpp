/*	$Id$	*/

#include <stdlib.h>
#include "Vnvax.h"
#include "verilated.h"

unsigned long nticks;

extern int tto_active;

void ttoexec(Vnvax *tb);
void tick(Vnvax *tb);


int main(int argc, char **argv)
{
	// Initialize Verilators variables
	Verilated::commandArgs(argc, argv);

	// Create an instance of our module under test
	Vnvax *tb = new Vnvax;

	// reset
	tb->n_rst = 0;
	tick(tb);
	tb->n_rst = 1;

	while(!Verilated::gotFinish()) {

		if (tto_active || tb->tto_tx == 0)
			ttoexec(tb);

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

/*	$Id$	*/

#include <stdlib.h>
#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

int tto_active;

/*
 * Receive a char from serial line, expected each 20 tick.
 * When char received, print it out.
 */
void
ttoexec(Vnvax *tb)
{
	static int intickcnt, utchar;

	if (intickcnt > 0) { /* wait for next tick */
		intickcnt--;
		return;
	}
	switch (tto_active) {
	case 0: /* got start bit. */
//fprintf(stderr, "start bit \r\n");
		intickcnt = 30;
		tto_active++;
		utchar = 0;
		break;

	case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8:
		intickcnt = 20;
		if (tb->tto_tx) utchar |= (1 << (tto_active-1));
		if (tto_active++ == 8) {
//fprintf(stderr, "print char %x\r\n", utchar);
			putchar(utchar);
			fflush(stdout);
		}
		break;

	case 9:
		if (tb->tto_tx == 0)
			printf("framing error\n");
		tto_active = 0;
		break;
	}
}

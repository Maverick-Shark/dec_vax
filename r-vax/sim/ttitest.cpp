/*	$Id$	*/

#include <stdlib.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <termios.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

volatile int ttisig;
int tti_active;

static void
sig_io(int signo)
{
	ttisig = 1;
}

void
ttiinit()
{
	struct termios p, op;
	int i;
	char c;

	signal(SIGIO, sig_io);
	fcntl(0, F_SETFL, O_NONBLOCK|O_ASYNC);

	tcgetattr(0, &op);
	tcgetattr(0, &p);
	cfmakeraw(&p);
	p.c_lflag |= ISIG;
	tcsetattr(0, TCSANOW, &p);
	ttisig = 0;
}

/*
 * If a character received on stdin, put on serial line bit by bit.
 */
void
ttiexec(Vnvax *tb)
{
	static int intickcnt;
	static char inchar;
	int i;

	if (intickcnt > 0) { /* wait for next tick */
		intickcnt--;
		return;
	}
	switch (tti_active) {
	case 0: /* got signal */
		ttisig = 0;
		if ((i = read(0, &inchar, 1)) < 0)
			return;
		intickcnt = SERIAL_TICKCNT; // start bit
		tb->tti_rx = 0;
		tti_active++;
		break;

	case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8:
		intickcnt = SERIAL_TICKCNT;
		tb->tti_rx = (inchar & (1 << (tti_active-1))) != 0;
		tti_active++;
		break;

	case 9:
		tb->tti_rx = 1;
		tti_active = 0;
		break;
	}
}

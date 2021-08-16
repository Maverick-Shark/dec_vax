/*	$Id$	*/

#include <sys/socket.h>
#include <netinet/in.h>

#include <stdlib.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <termios.h>
#include <err.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

volatile int ttisig;
int tti_active;
int sfd;

static void
sig_io(int signo)
{
	ttisig = 1;
}

void
ttiinit()
{
	struct termios p, op;
	struct sockaddr_in soin, cin;
	int i, lfd, ff;
	unsigned int clen;
	char c;

	signal(SIGIO, sig_io);
	if (nflag) {
		if ((lfd = socket(AF_INET, SOCK_STREAM, 0)) < 0)
			err(1, "socket");

		memset(&soin, 0, sizeof(soin));
		soin.sin_family = AF_INET;
		soin.sin_addr.s_addr = INADDR_ANY;
		soin.sin_port = htons(port);
		if (bind(lfd, (struct sockaddr *) &soin, sizeof(soin)) < 0)
			err(1, "bind");
		listen(lfd, 5);
		clen = sizeof(cin);
		if ((sfd = accept(lfd, (struct sockaddr *)&cin, &clen)) < 0)
			err(1, "accept");

		if (fcntl(sfd, F_SETOWN, getpid()) < 0)
			err(1, "F_SETOWN");
		if ((ff = fcntl(sfd, F_GETFL)) < 0)
			err(1, "F_GETFL");
		if (fcntl(sfd, F_SETFL, ff | FNDELAY | FASYNC) < 0)
			err(1, "F_SETFL");

	} else {
		sfd = 0;
		if (fcntl(sfd, F_SETFL, O_NONBLOCK|O_ASYNC) < 0)
			err(1, "fcntl");

		tcgetattr(0, &op);
		tcgetattr(0, &p);
		cfmakeraw(&p);
		p.c_lflag |= ISIG;
		tcsetattr(0, TCSANOW, &p);
		ttisig = 0;
	}
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
		if ((i = read(sfd, &inchar, 1)) < 0)
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

	case 9:	// stop bit
		tb->tti_rx = 1;
		tti_active++;
		break;

	case 10:
		tti_active = 0;
		ttisig = 1;	// check if any more character gotten.
		break;
	}
}

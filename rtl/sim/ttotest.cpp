/*
 * Copyright (c) 2021 Anders Magnusson (ragge@tethuvudet.se).
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


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

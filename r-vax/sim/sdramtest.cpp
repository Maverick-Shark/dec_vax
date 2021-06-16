/*	$Id$	*/

#include <fcntl.h>
#include <stdio.h>
#include <err.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

static int sdram_clk, sdram_cke, sdram_cs, sdram_ras, sdram_cas, sdram_we,
	sdram_udqm, sdram_ldqm, sdram_addr, sdram_ba, sdram_data;

enum { MODE_SET, AUTO_REFRESH, PRECHARGE_ALL, ACTIVATE, WRITE, READ,
	BURST_STOP, NOP };

const static char *cmd[] = {	// { ras, cas, we }
	"Mode reg set",	// 000
	"Auto refresh", // 001
	"Precharge banks", // 010
	"Bank active",  // 011
	"Write",	// 100
	"Read",		// 101
	"Burst stop",	// 110
	"Nop"		// 111
};

#define	SDRAMSZ	(16*1024*1024)
unsigned short sdramet[SDRAMSZ/2];

int debug = 0;

/*
 * Emulate Hynix SDRAM chip, 2M * 4 bank * 16 bit.
 */
void
sdramexec(Vnvax *tb)
{
	static unsigned long savclk;
	static int inref;
	static int oldcs = 1;
	static int quiet, daddr, state, readcnt;
	int c;

	c = (tb->sdram_ras << 2) | (tb->sdram_cas << 1) | tb->sdram_we;
	if (tb->sdram_cs != oldcs) {
		oldcs = tb->sdram_cs;
		if (tb->sdram_cs == 0) { // opening
		//	if (debug)printf("cs enable\r\n");
			savclk = nticks;
			state = NOP;
		} else {
		//	if (debug)printf("cs disable at %ld\r\n", nticks - savclk);
			quiet = 0;
		}
	}
	if (tb->sdram_cs == 1) // disabled
		return;

	switch (c) {
	case AUTO_REFRESH:
		quiet = 1;
		break;
	case ACTIVATE:
		if (debug)printf("%ld: Activate bank %d row  %#x\r\n", nticks - savclk,
		    tb->sdram_ba, tb->sdram_addr);
		daddr = (tb->sdram_addr << 11) + (tb->sdram_ba << 9);
		break;
	case READ:
		daddr = daddr + (tb->sdram_addr & 0777);
		if (debug)printf("%ld: Read col %d baddr %x %s\r\n", nticks - savclk,
		    tb->sdram_addr & 0777, daddr << 1,
		    tb->sdram_addr & (1 << 10) ? "(Auto-Close)" : "");
		readcnt = 0;
		state = READ;
		break;
	case WRITE:
		daddr = daddr + (tb->sdram_addr & 0777);
		if (debug)printf("%ld: Write col %d baddr %x %s:", nticks - savclk,
		    tb->sdram_addr & 0777, daddr << 1,
		    tb->sdram_addr & (1 << 10) ? "(Auto-Close)" : "");
		sdramet[daddr] = tb->sdram_data;
		if (debug)printf(" data %#x\r\n", tb->sdram_data);
		readcnt = 0;
		state = WRITE;
		break;
	case MODE_SET:
		
	case NOP:
		if (state == READ) {
			readcnt++;
			if (readcnt == 2) { // CAS 2
				tb->sdram_data = sdramet[daddr];
				if (debug)printf("%ld: read %#x\r\n",
				     nticks - savclk, tb->sdram_data);
			} else if (readcnt == 3) {
				tb->sdram_data = sdramet[daddr+1];
				if (debug)printf("%ld: read %#x\r\n",
				     nticks - savclk, tb->sdram_data);
			} else
				if (debug)printf("%ld: NOP\r\n", nticks - savclk);
			break;
		} else if (state == WRITE) {
			readcnt++;
			if (readcnt == 1) {
				if (debug)printf("%ld: data %#x\r\n", 
				    nticks - savclk, tb->sdram_data);
				sdramet[daddr+1] = tb->sdram_data;
			} else
				if (debug)printf("%ld: NOP\r\n", nticks - savclk);
			break;
		}
		/* FALLTHROUGH */
	default:
		if (quiet == 0)
			if (debug)printf("%s at %ld\r\n", cmd[c], nticks - savclk);
	}
}

void
loadfile(char *fn, int off)
{
	int fd, s, i;

//	for (i = 0; i < SDRAMSZ/2; i++)
//		sdramet[i] = 0xA55A;

	if ((fd = open(fn, O_RDONLY)) < 0)
		err(1, "open");

	if ((s = read(fd, sdramet+off, SDRAMSZ-off)) < 0)
		err(1, "read");

	fprintf(stderr, "read %d bytes\n", s);

	close(fd);
}

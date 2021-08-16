
#include <err.h>
#include <stdlib.h>
#include <unistd.h>

#include "Vnvax.h"
#include "verilated.h"

#include "nvax.h"

void preg_or_pos(Vnvax *tb);
void preg_or_pos2(Vnvax *tb);

struct vop { const char *name, *arg; };
extern struct vop vax_inst[];

int argvals[6], argvalp, argdest[2], argdestp;
int argvalq[6];

#define	BEQL	0x13
#define	BRW	0x31

#define	CLRB	0x94

#define	BISPSW	0xb8
#define	BICPSW	0xb9

#define	BICL2	0xca
#define	BICL3	0xcb
#define	XORL2	0xcc
#define	XORL3	0xcd

#define	MOVL	0xd0

#define	CLRL	0xd4
#define	TSTL	0xd5
#define	INCL	0xd6


#define	MTPR	0xda
#define	MFPR	0xdb

#define	MOVAL	0xde

void itracedump(Vnvax *tb);
void itrace2dump(Vnvax *tb);
void prtargs(Vnvax *tb, const char *);


#define	F(...) fprintf(stderr, __VA_ARGS__)

extern int mcode;

void
itracedump(Vnvax *tb)
{
	int cur_inst = tb->sbi__DOT__cpu__DOT__cur_byte;
	int arg1p = tb->sbi__DOT__cpu__DOT__argp[0];
	int arg1 = tb->sbi__DOT__cpu__DOT__arg[0];
	int arg2 = tb->sbi__DOT__cpu__DOT__arg[1];
	int psl;

	psl = tb->sbi__DOT__cpu__DOT__psw |
	    (tb->sbi__DOT__cpu__DOT__psl_is << 26) |
	    (tb->sbi__DOT__cpu__DOT__cur_mod << 24) |
	    (tb->sbi__DOT__cpu__DOT__prv_mod << 22) |
	    (tb->sbi__DOT__cpu__DOT__psl_ipl << 16);
	F("%08X %08X| ", tb->sbi__DOT__cpu__DOT__curpc, psl);

	if (vax_inst[cur_inst].name)
		F("%s", vax_inst[cur_inst].name);
	else
		F("opcode %02x", cur_inst);

	if (vax_inst[cur_inst].arg) {
		F(" ");
		prtargs(tb, vax_inst[cur_inst].arg);
	}
	F("\n");
	
}

void
preg_or_pos(Vnvax *tb)
{
	if (tb->sbi__DOT__cpu__DOT__argp_isreg[0])
		F("r%d", tb->sbi__DOT__cpu__DOT__argp_regnum[0]);
	else
		F("%x", tb->sbi__DOT__cpu__DOT__argp[0]);
}

void
preg_or_pos2(Vnvax *tb)
{
//	if (tb->sbi__DOT__cpu__DOT__arg2p_isreg)
//		F("r%d", tb->sbi__DOT__cpu__DOT__arg2p_regnum);
//	else
//		F("%x", tb->sbi__DOT__cpu__DOT__arg2p);
}

extern unsigned short sdramet[];

int
gmem(int addr, int sz)
{
	int n;
	char *memp = (char *)sdramet;

	if ((unsigned)addr >= 16*1024*1024)
		return 0;
	n = memp[addr++];
	if (sz == 'b')
		return n;
	n = (n & 255) | (memp[addr++] << 8);
	if (sz == 'w')
		return n;
	n = (n & 65535) | (memp[addr++] << 16);
	n = (n & 0xffffff) | (memp[addr++] << 24);
	return n;
}

const char *rnames[] = { "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
	"R8", "R9", "R10", "R11", "AP", "FP", "SP", "PC" };

void
prtargs(Vnvax *tb, const char *s)
{
	int argpc = tb->sbi__DOT__cpu__DOT__curpc + 1;
	char *memp = (char *)sdramet;
	int i, curarg, ixarg, regno, n, ixadd;
	int sav_val, sav_aorv, sav_dst, argsz, regval;

	argvalp = 0;
	argdestp = 0;

	for (; *s; s++) {
		if (*s == 'b') {
			n = memp[argpc++];
			if (s[1] == 'w')
				n = (memp[argpc++] << 8) | (n & 255);
			n += argpc;
			F("%X", n);
			goto ck;
		}

		/* save src value */
		sav_val = (*s == 'r' || *s == 'm');
		/* save src val (if reg) or addr */
		sav_aorv = (*s == 'w' || *s == 'v' || *s == 'a');
		/* save dst */
		sav_dst = (*s == 'w' || *s == 'm');

		argsz = s[1] == 'w' ? 2 : s[1] == 'l' ? 4 :
		    s[1] == 'q' ? 8 : 1;
		ixarg = ixadd = 0;

more:		curarg = memp[argpc++];
		regno = curarg & 15;
		regval = tb->sbi__DOT__cpu__DOT__general_reg[regno];

		switch ((curarg >> 4) & 15) {
		case 0: case 1: case 2: case 3:
			F("#%X", curarg & 63);
			argvals[argvalp++] = curarg & 63;
			break;
		case 4:
			ixarg = regno+1;
			ixadd = regval * argsz;
			goto more;

		case 5:
			F("%s", rnames[regno]);
			if (sav_val || sav_aorv) {
				argvals[argvalp] = regval;
				if (argsz == 8)
					argvalq[argvalp] =
				   tb->sbi__DOT__cpu__DOT__general_reg[regno+1];
			}
			argvalp++;
			if (sav_dst) {
				argdestp++;
				if (argsz == 8)
					argdestp++;
			}
			break;

		case 6:
			F("(%s)", rnames[regno]);
			i = tb->sbi__DOT__cpu__DOT__general_reg[regno];
			if (ixarg)
				i += ixadd;
			if (sav_val) {
				argvals[argvalp] = gmem(i, s[1]);
				if (argsz == 8)
					argvalq[argvalp] =
					    gmem(i+4, s[1]);
			} else if (sav_aorv) {
				argvals[argvalp] = i;
			}
			argvalp++;
			if (sav_dst) {
				argdestp++;
				if (argsz == 8)
					argdestp++;
			}
			if (ixarg)
				F("[%s]", rnames[ixarg-1]);
			break;

		case 7:
			F("-(%s)", rnames[regno]);
			if (ixarg)
				F("[%s]", rnames[ixarg-1]);
			if (sav_val) {
				argvals[argvalp++] = gmem(regval - argsz, s[1]);
			} else if (sav_aorv) {
				argvals[argvalp++] = regval - argsz;
			}
			if (sav_dst)
				argdestp++;
			break;

		case 8:
			if (regno == 15) {
				int o = 0;
				F("#");
				n = memp[argpc++] & 255;
				if (s[1] == 'w' || s[1] == 'l' || s[1] == 'q') 
					n |= ((memp[argpc++] & 255) << 8);
				if (s[1] == 'l' || s[1] == 'q') {
					n |= ((memp[argpc++] & 255) << 16);
					n |= ((memp[argpc++] & 255) << 24);
				}
				if (s[1] == 'q') {
					o = memp[argpc++] & 255;
					o |= ((memp[argpc++] & 255) << 8);
					o |= ((memp[argpc++] & 255) << 16);
					o |= ((memp[argpc++] & 255) << 24);
					if (o)
						F("%X", o);
				}
				if (o)
					F("%08X", n);
				else
					F("%X", n);
				if (ixarg)
					F("[%s]", rnames[ixarg-1]);
				argvals[argvalp++] = n;
			} else {
				F("(%s)+", rnames[regno]);
				if (ixarg)
					F("[%s]", rnames[ixarg-1]);
				if (sav_val) {
					argvals[argvalp] = gmem(regval, s[1]);
					if (argsz == 8)
						argvalq[argvalp] = 
						    gmem(regval+4, s[1]);
				} else if (sav_aorv) {
					argvals[argvalp] = regval;
				}
				argvalp++;
				if (sav_dst) {
					argdestp++;
					if (argsz == 8)
						argdestp++;
				}
			}
			break;

		case 9:
			if (regno == 15) {
				n = memp[argpc++] & 255;
				n |= ((memp[argpc++] & 255) << 8);
				n |= ((memp[argpc++] & 255) << 16);
				n |= ((memp[argpc++] & 255) << 24);
				F("@#%X", n);
				argvals[argvalp] = n;
			} else {
				F("@(%s)", rnames[regno]);
				F("+");
				argvals[argvalp] = gmem(regval, 'l');
			}
			if (ixarg)
				F("[%s]", rnames[ixarg-1]);
			if (ixarg)
				argvals[argvalp] += ixadd;
			if (sav_val) {
				i = argvals[argvalp];
				if (i == 0x60080038)
					argvals[argvalp] =
					    tb->sbi__DOT__sbi_tmo;
				else
					argvals[argvalp] = gmem(i, s[1]);
				if (argsz == 8)
					argvalq[argvalp] = gmem(i+4, s[1]);
			}
			argvalp++;
			break;

		case 10: case 11:
			n = memp[argpc++] & 255;
			if (n & 0x80) n |= 0xffffff00;
			goto prt;

		case 12: case 13:
			n = memp[argpc++] & 255;
			n = n | (memp[argpc++] << 8);
			if (n & 0x8000) n |= 0xffff0000;
			goto prt;

		case 14: case 15:
			n = memp[argpc++] & 255;
			n |= ((memp[argpc++] & 255) << 8);
			n |= ((memp[argpc++] & 255) << 16);
			n |= ((memp[argpc++] & 255) << 24);
prt:			if (curarg & 16)
				F("@");
			if (regno == 15) {
				n += argpc;
				F("%X", n);
				argvals[argvalp] = n;
			} else {
				if (n < 0)
					F("-%X(%s)", -n, rnames[regno]);
				else
					F("%X(%s)", n, rnames[regno]);
				argvals[argvalp] = n + regval;
			}
			if (ixarg)
				F("[%s]", rnames[ixarg-1]);
			if (curarg & 16)
				argvals[argvalp] = gmem(argvals[argvalp], 'l');
			if (ixarg)
				argvals[argvalp] += ixadd;
			if (sav_val)
				argvals[argvalp] =
				    gmem(argvals[argvalp], s[1]);
			if (sav_dst) {
				argdestp++;
				if (argsz == 8)
					argdestp++;
			}
			argvalp++;
			break;

		default:
			F("arg...%d", (curarg >> 4) & 15);
		}
ck:		if (s[2] != ',')
			break;
		s += 2;
		F(",");
	}
}

void
itrace2dump(Vnvax *tb)
{
	int i;
	int cur_inst;

	if (argvalp == 0 && argdestp == 0)
		return;

	F("                   ");
	cur_inst = tb->sbi__DOT__cpu__DOT__cur_inst;
	switch (cur_inst) {
	case 0x3c: // movzwl
		F("%08X %08X -> %08X", argvals[0] & 65535, argvals[1],
		    tb->sbi__DOT__cpu__DOT__argd[0]);
		break;
	case 0x3e: // movaw
		F("%08X %08X", argvals[0], argvals[1]);
		break;
	case 0x79: // ashq
		F("%08X %08X %08X -> %08X %08X\n",
		    argvals[0], argvals[1], argvals[2],
		    tb->sbi__DOT__cpu__DOT__argd[0],
		    tb->sbi__DOT__cpu__DOT__argd[1]);
		F("                            %08X         ",
		    argvalq[1]);
		break;
	case 0x7a: //
		F("%08X %08X %08X %08X",
		    argvals[0], argvals[1], argvals[2], argvals[3]);
		break;
	case 0x7b: // ediv
		F("%08X %08X %08X %08X\n",
		    argvals[0], argvals[1], argvals[2], argvals[3]);
		F("                            %08X                  ",
		    argvalq[1]);
		break;
	case 0x7c: // clrq
		F("%08X -> 00000000 00000000", argvals[0]);
		break;
	case 0x7d: // movq
		F("%08X %08X -> %08X %08X\n",
		    tb->sbi__DOT__cpu__DOT__argd[0], argvals[1],
		    tb->sbi__DOT__cpu__DOT__argd[0],
		    tb->sbi__DOT__cpu__DOT__argd[1]);
		F("                   %08X         ",
		    tb->sbi__DOT__cpu__DOT__argd[1]);
		break;
	case 0x7f: // pushaq
		F("%08X -> SP: %08X", argvals[0], argvals[0]);
		break;
	case 0x91: // cmpb
		F("%08X %08X", argvals[0] & 255, argvals[1] & 255);
		break;
	case 0x90: // movb
		F("%08X %08X -> %08X", argvals[0] & 255, argvals[1],
		    tb->sbi__DOT__cpu__DOT__argd[0] & 255);
		break;
	case 0x8a: // bicb2
	case 0x93: // bitb
		F("%08X %08X -> %08X", argvals[0] & 255, argvals[1] & 255,
		    tb->sbi__DOT__cpu__DOT__argd[0] & 255);
		break;
	case 0x9b: // movzbw
		F("%08X %08X -> %08X", argvals[0] & 255, argvals[1],
		    tb->sbi__DOT__cpu__DOT__argd[0]);
		break;
	case 0x9f: // pushab
		F("%08X -> SP: %08X", argvals[0], argvals[0]);
		break;
	case 0xa1: // addw3
		F("%08X %08X %08X -> %08X",
		    argvals[0] & 65535, argvals[1] & 65535, argvals[2],
		    tb->sbi__DOT__cpu__DOT__argd[0] & 65535);
		break;
	case 0xa8: // bisw2
		F("%08X %08X -> %08X", argvals[0] & 65535, argvals[1] & 65535,
		    tb->sbi__DOT__cpu__DOT__argd[0] & 65535);
		break;
	case 0xb6: // incw
	case 0xb7: // decw
		F("%08X -> %08X", argvals[0] & 65535,
		    tb->sbi__DOT__cpu__DOT__argd[0] & 65535);
		break;
	case 0xd1: // cmpl
		F("%08X %08X", argvals[0], argvals[1]);
		break;
	case 0xdd: // pushl
		F("%08X -> SP: %08X", argvals[0], argvals[0]);
		break;
	case 0xdf: // pushal
		F("%08X -> SP: %08X", argvals[0], argvals[0]);
		break;
	case 0xf1: // acbl
		if (argvalp == 3)
			F("%08X %08X %08X", argvals[0], argvals[1], argvals[2]);
		break;
	case 0xf2: // aoblss
	case 0xf3: // aobleq
		F("%08X %08X", argvals[0], argvals[1]);
		break;
	case 0xf5: // sobgtr
		F("%08X", argvals[0]);
		break;
	default:
		for (i = 0; i < argvalp; i++) {
			F("%08X", argvals[i]);
			if (i+1 != argvalp)
				F(" ");
		}
		if (argdestp) {
			F(" -> ");
			F("%08X", tb->sbi__DOT__cpu__DOT__argd[0]);
			if (argdestp == 2)
				F(" %08X", tb->sbi__DOT__cpu__DOT__argd[1]);
		}
	}
	argvalp = argdestp = 0;
	F("\n");
}

/* one-byte instructions */
struct vop vax_inst[256] = {
/* 0x00 */	{	"HALT",		NULL			},
/* 0x01 */	{	"NOP",		NULL			},
/* 0x02 */	{	"REI",		NULL			},
/* 0x03 */	{	"BPT",		NULL			},
/* 0x04 */	{	"RET",		NULL			},
/* 0x05 */	{	"RSB",		NULL			},
/* 0x06 */	{	"LDPCTX",	NULL			},
/* 0x07 */	{	"SVPCTX",	NULL			},
/* 0x08 */	{	"CVTPS",	"rw,ab,rw,ab"		},
/* 0x09 */	{	"CVTSP",	"rw,ab,rw,ab"		},
/* 0x0a */	{	"INDEX",	"rl,rl,rl,rl,rl,wl"	},
/* 0x0b */	{	"CRC",		"ab,rl,rw,ab"		},
/* 0x0c */	{	"PROBER",	"rb,rw,ab"		},
/* 0x0d */	{	"PROBEW",	"rb,rw,ab"		},
/* 0x0e */	{	"INSQUE",	"ab,ab"			},
/* 0x0f */	{	"REMQUE",	"ab,wl"			},
	   
/* 0x10 */	{	"BSBB",		"bb"			},
/* 0x11 */	{	"BRB",		"bb"			},
/* 0x12 */	{	"BNEQ",		"bb"			},
/* 0x13 */	{	"BEQL",		"bb"			},
/* 0x14 */	{	"BGTR",		"bb"			},
/* 0x15 */	{	"BLEQ",		"bb"			},
/* 0x16 */	{	"JSB",		"ab"			},
/* 0x17 */	{	"JMP",		"ab"			},
/* 0x18 */	{	"BGEQ",		"bb"			},
/* 0x19 */	{	"BLSS",		"bb"			},
/* 0x1a */	{	"BGTRU",	"bb"			},
/* 0x1b */	{	"BLEQU",	"bb"			},
/* 0x1c */	{	"BVC",		"bb"			},
/* 0x1d */	{	"BVS",		"bb"			},
/* 0x1e */	{	"BGEQU",	"bb"			},
/* 0x1f */	{	"BLSSU",	"bb"			},
	   
/* 0x20 */	{	"ADDP4",	"rw,ab,rw,ab"		},
/* 0x21 */	{	"ADDP6",	"rw,ab,rw,ab,rw,ab"	},
/* 0x22 */	{	"SUBP4",	"rw,ab,rw,ab"		},
/* 0x23 */	{	"SUBP6",	"rw,ab,rw,ab,rw,ab"	},
/* 0x24 */	{	"CVTPT",	"rw,ab,ab,rw,ab"	},
/* 0x25 */	{	"MULP",		"rw,ab,rw,ab,rw,ab"	},
/* 0x26 */	{	"CVTTP",	"rw,ab,ab,rw,ab"	},
/* 0x27 */	{	"DIVP",		"rw,ab,rw,ab,rw,ab"	},
/* 0x28 */	{	"MOVC3",	"rw,ab,ab"		},
/* 0x29 */	{	"CMPC3",	"rw,ab,ab"		},
/* 0x2a */	{	"SCANC",	"rw,ab,ab,rb"		},
/* 0x2b */	{	"SPANC",	"rw,ab,ab,rb"		},
/* 0x2c */	{	"MOVC5",	"rw,ab,rb,rw,ab"	},
/* 0x2d */	{	"CMPC5",	"rw,ab,rb,rw,ab"	},
/* 0x2e */	{	"MOVTC",	"rw,ab,rb,ab,rw,ab"	},
/* 0x2f */	{	"MOVTUC",	"rw,ab,rb,ab,rw,ab"	},

/* 0x30 */	{	"BSBW",		"bw"			},
/* 0x31 */	{	"BRW",		"bw"			},
/* 0x32 */	{	"CVTWL",	"rw,wl"			},
/* 0x33 */	{	"CVTWB",	"rw,wb"			},
/* 0x34 */	{	"MOVP",		"rw,ab,ab"		},
/* 0x35 */	{	"CMPP3",	"rw,ab,ab"		},
/* 0x36 */	{	"CVTPL",	"rw,ab,wl"		},
/* 0x37 */	{	"CMPP4",	"rw,ab,rw,ab"		},
/* 0x38 */	{	"EDITPC",	"rw,ab,ab,ab"		},
/* 0x39 */	{	"MATCHC",	"rw,ab,rw,ab"		},
/* 0x3a */	{	"LOCC",		"rb,rw,ab"		},
/* 0x3b */	{	"SKPC",		"rb,rw,ab"		},
/* 0x3c */	{	"MOVZWL",	"rw,wl"			},
/* 0x3d */	{	"ACBW",		"rw,rw,mw,bw"		},
/* 0x3e */	{	"MOVAW",	"aw,wl"			},
/* 0x3f */	{	"PUSHAW",	"aw"			},
	   
/* 0x40 */	{	"ADDF2",	"rf,mf"			},
/* 0x41 */	{	"ADDF3",	"rf,rf,wf"		},
/* 0x42 */	{	"SUBF2",	"rf,mf"			},
/* 0x43 */	{	"SUBF3",	"rf,rf,wf"		},
/* 0x44 */	{	"MULF2",	"rf,mf"			},
/* 0x45 */	{	"MULF3",	"rf,rf,wf"		},
/* 0x46 */	{	"DIVF2",	"rf,mf"			},
/* 0x47 */	{	"DIVF3",	"rf,rf,wf"		},
/* 0x48 */	{	"CVTFB",	"rf,wb"			},
/* 0x49 */	{	"CVTFW",	"rf,ww"			},
/* 0x4a */	{	"CVTFL",	"rf,wl"			},
/* 0x4b */	{	"CVTRFL",	"rf,wl"			},
/* 0x4c */	{	"CVTBF",	"rb,wf"			},
/* 0x4d */	{	"CVTWF",	"rw,wf"			},
/* 0x4e */	{	"CVTLF",	"rl,wf"			},
/* 0x4f */	{	"ACBF",		"rf,rf,rf,bw"		},
	   
/* 0x50 */	{	"MOVF",		"rf,wf"			},
/* 0x51 */	{	"CMPF",		"rf,rf"			},
/* 0x52 */	{	"MNEGF",	"rf,wf"			},
/* 0x53 */	{	"TSTF",		"rf"			},
/* 0x54 */	{	"EMODF",	"rf,rb,rf,wl,wf"	},
/* 0x55 */	{	"POLYF",	"rf,rw,ab"		},
/* 0x56 */	{	"CVTFD",	"rf,wd"			},
/* 0x57 */	{	"-reserved-",	NULL			},
/* 0x58 */	{	"ADAWI",	"rw,mw"			},
/* 0x59 */	{	"-reserved-",	NULL			},
/* 0x5a */	{	"-reserved-",	NULL			},
/* 0x5b */	{	"-reserved-",	NULL			},
/* 0x5c */	{	"INSQHI",	"ab,aq"			},
/* 0x5d */	{	"INSQTI",	"ab,aq"			},
/* 0x5e */	{	"REMQHI",	"aq,wl"			},
/* 0x5f */	{	"REMQTI",	"aq,wl"			},

/* 0x60 */	{	"ADDD2",	"rd,md"			},
/* 0x61 */	{	"ADDD3",	"rd,rd,wd"		},
/* 0x62 */	{	"SUBD2",	"rd,md"			},
/* 0x63 */	{	"SUBD3",	"rd,rd,wd"		},
/* 0x64 */	{	"MULD2",	"rd,md"			},
/* 0x65 */	{	"MULD3",	"rd,rd,wd"		},
/* 0x66 */	{	"DIVD2",	"rd,md"			},
/* 0x67 */	{	"DIVD3",	"rd,rd,wd"		},
/* 0x68 */	{	"CVTDB",	"rd,wb"			},
/* 0x69 */	{	"CVTDW",	"rd,ww"			},
/* 0x6a */	{	"CVTDL",	"rd,wl"			},
/* 0x6b */	{	"CVTRDL",	"rd,wl"			},
/* 0x6c */	{	"CVTBD",	"rb,wd"			},
/* 0x6d */	{	"CVTWD",	"rw,wd"			},
/* 0x6e */	{	"CVTLD",	"rl,wd"			},
/* 0x6f */	{	"ACBD",		"rd,rd,md,bw"		},
	   
/* 0x70 */	{	"MOVD",		"rd,wd"			},
/* 0x71 */	{	"CMPD",		"rd,rd"			},
/* 0x72 */	{	"MNEGD",	"rd,wd"			},
/* 0x73 */	{	"TSTD",		"rd"			},
/* 0x74 */	{	"EMODD",	"rd,rb,rd,wl,wd"	},
/* 0x75 */	{	"POLYD",	"rd,rw,ab"		},
/* 0x76 */	{	"CVTDF",	"rd,wf"			},
/* 0x77 */	{	"-reserved-",	NULL			},
/* 0x78 */	{	"ASHL",		"rb,rl,wl"		},
/* 0x79 */	{	"ASHQ",		"rb,rq,wq"		},
/* 0x7a */	{	"EMUL",		"rl,rl,rl,wq"		},
/* 0x7b */	{	"EDIV",		"rl,rq,wl,wl"		},
/* 0x7c */	{	"CLRQ",		"wq"			},
/* 0x7d */	{	"MOVQ",		"rq,wq"			},
/* 0x7e */	{	"MOVAQ",	"aq,wl"			},
/* 0x7f */	{	"PUSHAQ",	"aq"			},
	   
/* 0x80 */	{	"ADDB2",	"rb,mb"			},
/* 0x81 */	{	"ADDB3",	"rb,rb,wb"		},
/* 0x82 */	{	"SUBB2",	"rb,mb"			},
/* 0x83 */	{	"SUBB3",	"rb,rb,wb"		},
/* 0x84 */	{	"MULB2",	"rb,mb"			},
/* 0x85 */	{	"MULB3",	"rb,rb,wb"		},
/* 0x86 */	{	"DIVB2",	"rb,mb"			},
/* 0x87 */	{	"DIVB3",	"rb,rb,wb"		},
/* 0x88 */	{	"BISB2",	"rb,mb"			},
/* 0x89 */	{	"BISB3",	"rb,rb,wb"		},
/* 0x8a */	{	"BICB2",	"rb,mb"			},
/* 0x8b */	{	"BICB3",	"rb,rb,wb"		},
/* 0x8c */	{	"XORB2",	"rb,mb"			},
/* 0x8d */	{	"XORB3",	"rb,rb,wb"		},
/* 0x8e */	{	"MNEGB",	"rb,wb"			},
/* 0x8f */	{	"CASEB",	"rb,rb,rb"		},

/* 0x90 */	{	"MOVB",		"rb,wb"			},
/* 0x91 */	{	"CMPB",		"rb,rb"			},
/* 0x92 */	{	"MCOMB",	"rb,wb"			},
/* 0x93 */	{	"BITB",		"rb,rb"			},
/* 0x94 */	{	"CLRB",		"wb"			},
/* 0x95 */	{	"TSTB",		"rb"			},
/* 0x96 */	{	"INCB",		"mb"			},
/* 0x97 */	{	"DECB",		"mb"			},
/* 0x98 */	{	"CVTBL",	"rb,wl"			},
/* 0x99 */	{	"CVTBW",	"rb,ww"			},
/* 0x9a */	{	"MOVZBL",	"rb,wl"			},
/* 0x9b */	{	"MOVZBW",	"rb,ww"			},
/* 0x9c */	{	"ROTL",		"rb,rl,wl"		},
/* 0x9d */	{	"ACBB",		"rb,rb,mb,bw"		},
/* 0x9e */	{	"MOVAB",	"ab,wl"			},
/* 0x9f */	{	"PUSHAB",	"ab"			},
	   
/* 0xa0 */	{	"ADDW2",	"rw,mw"			},
/* 0xa1 */	{	"ADDW3",	"rw,rw,ww"		},
/* 0xa2 */	{	"SUBW2",	"rw,mw"			},
/* 0xa3 */	{	"SUBW3",	"rw,rw,ww"		},
/* 0xa4 */	{	"MULW2",	"rw,mw"			},
/* 0xa5 */	{	"MULW3",	"rw,rw,ww"		},
/* 0xa6 */	{	"DIVW2",	"rw,mw"			},
/* 0xa7 */	{	"DIVW3",	"rw,rw,ww"		},
/* 0xa8 */	{	"BISW2",	"rw,mw"			},
/* 0xa9 */	{	"BISW3",	"rw,rw,ww"		},
/* 0xaa */	{	"BICW2",	"rw,mw"			},
/* 0xab */	{	"BICW3",	"rw,rw,ww"		},
/* 0xac */	{	"XORW2",	"rw,mw"			},
/* 0xad */	{	"XORW3",	"rw,rw,ww"		},
/* 0xae */	{	"MNEGW",	"rw,ww"			},
/* 0xaf */	{	"CASEW",	"rw,rw,rw"		},
	   
/* 0xb0 */	{	"MOVW",		"rw,ww"			},
/* 0xb1 */	{	"CMPW",		"rw,rw"			},
/* 0xb2 */	{	"MCOMW",	"rw,ww"			},
/* 0xb3 */	{	"BITW",		"rw,rw"			},
/* 0xb4 */	{	"CLRW",		"mw"			},
/* 0xb5 */	{	"TSTW",		"rw"			},
/* 0xb6 */	{	"INCW",		"mw"			},
/* 0xb7 */	{	"DECW",		"mw"			},
/* 0xb8 */	{	"BISPSW",	"rw"			},
/* 0xb9 */	{	"BICPSW",	"rw"			},
/* 0xba */	{	"POPR",		"rw"			},
/* 0xbb */	{	"PUSHR",	"rw"			},
/* 0xbc */	{	"CHMK",		"rw"			},
/* 0xbd */	{	"CHME",		"rw"			},
/* 0xbe */	{	"CHMS",		"rw"			},
/* 0xbf */	{	"CHMU",		"rw"			},

/* 0xc0 */	{	"ADDL2",	"rl,ml"			},
/* 0xc1 */	{	"ADDL3",	"rl,rl,wl"		},
/* 0xc2 */	{	"SUBL2",	"rl,ml"			},
/* 0xc3 */	{	"SUBL3",	"rl,rl,wl"		},
/* 0xc4 */	{	"MULL2",	"rl,ml"			},
/* 0xc5 */	{	"MULL3",	"rl,rl,wl"		},
/* 0xc6 */	{	"DIVL2",	"rl,ml"			},
/* 0xc7 */	{	"DIVL3",	"rl,rl,wl"		},
/* 0xc8 */	{	"BISL2",	"rl,ml"			},
/* 0xc9 */	{	"BISL3",	"rl,rl,wl"		},
/* 0xca */	{	"BICL2",	"rl,ml"			},
/* 0xcb */	{	"BICL3",	"rl,rl,wl"		},
/* 0xcc */	{	"XORL2",	"rl,ml"			},
/* 0xcd */	{	"XORL3",	"rl,rl,wl"		},
/* 0xce */	{	"MNEGL",	"rl,wl"			},
/* 0xcf */	{	"CASEL",	"rl,rl,rl"		},
	   
/* 0xd0 */	{	"MOVL",		"rl,wl"			},
/* 0xd1 */	{	"CMPL",		"rl,rl"			},
/* 0xd2 */	{	"MCOML",	"rl,wl"			},
/* 0xd3 */	{	"BITL",		"rl,rl"			},
/* 0xd4 */	{	"CLRL",		"wl"			},
/* 0xd5 */	{	"TSTL",		"rl"			},
/* 0xd6 */	{	"INCL",		"ml"			},
/* 0xd7 */	{	"DECL",		"ml"			},
/* 0xd8 */	{	"ADWC",		"rl,ml"			},
/* 0xd9 */	{	"SBWC",		"rl,ml"			},
/* 0xda */	{	"MTPR",		"rl,rl"			},
/* 0xdb */	{	"MFPR",		"rl,wl"			},
/* 0xdc */	{	"MOVPSL",	"wl"			},
/* 0xdd */	{	"PUSHL",	"rl"			},
/* 0xde */	{	"MOVAL",	"al,wl"			},
/* 0xdf */	{	"PUSHAL",	"al"			},

/* 0xe0 */	{	"BBS",		"rl,vb,bb"		},
/* 0xe1 */	{	"BBC",		"rl,vb,bb"		},
/* 0xe2 */	{	"BBSS",		"rl,vb,bb"		},
/* 0xe3 */	{	"BBCS",		"rl,vb,bb"		},
/* 0xe4 */	{	"BBSC",		"rl,vb,bb"		},
/* 0xe5 */	{	"BBCC",		"rl,vb,bb"		},
/* 0xe6 */	{	"BBSSI",	"rl,vb,bb"		},
/* 0xe7 */	{	"BBCCI",	"rl,vb,bb"		},
/* 0xe8 */	{	"BLBS",		"rl,bb"			},
/* 0xe9 */	{	"BLBC",		"rl,bb"			},
/* 0xea */	{	"FFS",		"rl,rb,vb,wl"		},
/* 0xeb */	{	"FFC",		"rl,rb,vb,wl"		},
/* 0xec */	{	"CMPV",		"rl,rb,vb,rl"		},
/* 0xed */	{	"CMPZV",	"rl,rb,vb,rl"		},
/* 0xee */	{	"EXTV",		"rl,rb,vb,wl"		},
/* 0xef */	{	"EXTZV",	"rl,rb,vb,wl"		},

/* 0xf0 */	{	"INSV",		"rl,rl,rb,vb"		},
/* 0xf1 */	{	"ACBL",		"rl,rl,ml,bw"		},
/* 0xf2 */	{	"AOBLSS",	"rl,ml,bb"		},
/* 0xf3 */	{	"AOBLEQ",	"rl,ml,bb"		},
/* 0xf4 */	{	"SOBGEQ",	"ml,bb"			},
/* 0xf5 */	{	"SOBGTR",	"ml,bb"			},
/* 0xf6 */	{	"CVTLB",	"rl,wb"			},
/* 0xf7 */	{	"CVTLW",	"rl,ww"			},
/* 0xf8 */	{	"ASHP",		"rb,rw,ab,rb,rw,ab"	},
/* 0xf9 */	{	"CVTLP",	"rl,rw,ab"		},
/* 0xfa */	{	"CALLG",	"ab,ab"			},
/* 0xfb */	{	"CALLS",	"rl,ab"			},
/* 0xfc */	{	"XFC",		"?"			},
/* 0xfd */	{	"-reserved-",	NULL			},
/* 0xfe */	{	"-reserved-",	NULL			},
/* 0xff */	{	"-reserved-",	NULL			},
};


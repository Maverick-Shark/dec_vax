
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
void prtargs(Vnvax *tb, const char *);


#define	F(...) fprintf(stderr, __VA_ARGS__)

void
itracedump(Vnvax *tb)
{
	int cur_inst = tb->sbi__DOT__cpu__DOT__cur_inst;
	int arg1p = tb->sbi__DOT__cpu__DOT__arg1p;
	int arg1 = tb->sbi__DOT__cpu__DOT__arg1;
	int arg2 = tb->sbi__DOT__cpu__DOT__arg2;
	int psl;

#if 0
	psl = (tb->sbi__DOT__cpu__DOT__psl_is << 26) |
	    (tb->sbi__DOT__cpu__DOT__psl_ipl << 16);
#endif
	psl = 0x041f0000 | tb->sbi__DOT__cpu__DOT__psw;
	F("%08X %08X| ", tb->sbi__DOT__cpu__DOT__oldpc, psl);

	if (vax_inst[cur_inst].name)
		F("%s ", vax_inst[cur_inst].name);
	else
		F("opcode %02x", cur_inst);

	if (vax_inst[cur_inst].arg)
		prtargs(tb, vax_inst[cur_inst].arg);
	F("\r\n");
	
}

void
preg_or_pos(Vnvax *tb)
{
	if (tb->sbi__DOT__cpu__DOT__arg1p_isreg)
		F("r%d", tb->sbi__DOT__cpu__DOT__arg1p_regnum);
	else
		F("%x", tb->sbi__DOT__cpu__DOT__arg1p);
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

const char *rnames[] = { "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
	"R8", "R9", "R10", "R11", "AP", "FP", "SP", "PC" };

void
prtargs(Vnvax *tb, const char *s)
{
	int argpc = tb->sbi__DOT__cpu__DOT__oldpc + 1;
	char *memp = (char *)sdramet;
	int i, curarg, ixarg, regno, n;

	for (; *s; s++) {
		if (*s == 'b') {
			n = memp[argpc++];
			if (s[1] == 'w')
				n = (memp[argpc++] << 8) | (n & 255);
			n += argpc;
			F("%X", n);
			goto ck;
		}

		ixarg = 0;
more:		curarg = memp[argpc++];
		regno = curarg & 15;

		switch ((curarg >> 4) & 15) {
		case 0: case 1: case 2: case 3:
			F("#%X", curarg & 63);
			break;
		case 4:
			ixarg = regno+1;
			goto more;

		case 5:
			F("%s", rnames[regno]);
			break;

		case 6:
			F("(%s)", rnames[regno]);
			break;

		case 7:
			F("-(%s)", rnames[regno]);
			break;

		case 8:
			if (regno == 15) {
				n = memp[argpc++] & 255;
				n |= ((memp[argpc++] & 255) << 8);
				n |= ((memp[argpc++] & 255) << 16);
				n |= ((memp[argpc++] & 255) << 24);
				F("#%X", n);
			} else {
				F("(%s)+", rnames[regno]);
			}
			break;

		case 9:
			F("*(%s)+", rnames[regno]);
			if (regno == 15)
				argpc += 4;
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
			} else
				F("%X(%s)", n, rnames[regno]);
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
/* 0x0e */	{	"INSQUE",	"ab,wl"			},
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
/* 0x1e */	{	"BCC",		"bb"			},
/* 0x1f */	{	"BCS",		"bb"			},
	   
/* 0x20 */	{	"addp4",	"rw,ab,rw,ab"		},
/* 0x21 */	{	"addp6",	"rw,ab,rw,ab,rw,ab"	},
/* 0x22 */	{	"subp4",	"rw,ab,rw,ab"		},
/* 0x23 */	{	"subp6",	"rw,ab,rw,ab,rw,ab"	},
/* 0x24 */	{	"cvtpt",	"rw,ab,ab,rw,ab"	},
/* 0x25 */	{	"mulp",		"rw,ab,rw,ab,rw,ab"	},
/* 0x26 */	{	"cvttp",	"rw,ab,ab,rw,ab"	},
/* 0x27 */	{	"divp",		"rw,ab,rw,ab,rw,ab"	},
/* 0x28 */	{	"MOVC3",	"rw,ab,ab"		},
/* 0x29 */	{	"CMPC3",	"rw,ab,ab"		},
/* 0x2a */	{	"scanc",	"rw,ab,ab,rb"		},
/* 0x2b */	{	"spanc",	"rw,ab,ab,rb"		},
/* 0x2c */	{	"MOVC5",	"rw,ab,rb,rw,ab"	},
/* 0x2d */	{	"CMPC5",	"rw,ab,rb,rw,ab"	},
/* 0x2e */	{	"MOVTC",	"rw,ab,rb,ab,rw,ab"	},
/* 0x2f */	{	"MOVTUC",	"rw,ab,rb,ab,rw,ab"	},

/* 0x30 */	{	"BSBW",		"bw"			},
/* 0x31 */	{	"BRW",		"bw"			},
/* 0x32 */	{	"cvtwl",	"rw,wl"			},
/* 0x33 */	{	"cvtwb",	"rw,wb"			},
/* 0x34 */	{	"MOVP",		"rw,ab,ab"		},
/* 0x35 */	{	"CMPP3",	"rw,ab,ab"		},
/* 0x36 */	{	"cvtpl",	"rw,ab,wl"		},
/* 0x37 */	{	"CMPP4",	"rw,ab,rw,ab"		},
/* 0x38 */	{	"editpc",	"rw,ab,ab,ab"		},
/* 0x39 */	{	"matchc",	"rw,ab,rw,ab"		},
/* 0x3a */	{	"locc",		"rb,rw,ab"		},
/* 0x3b */	{	"skpc",		"rb,rw,ab"		},
/* 0x3c */	{	"MOVZWL",	"rw,wl"			},
/* 0x3d */	{	"acbw",		"rw,rw,mw,bw"		},
/* 0x3e */	{	"MOVAW",	"aw,wl"			},
/* 0x3f */	{	"pushaw",	"aw"			},
	   
/* 0x40 */	{	"addf2",	"rf,mf"			},
/* 0x41 */	{	"addf3",	"rf,rf,wf"		},
/* 0x42 */	{	"subf2",	"rf,mf"			},
/* 0x43 */	{	"subf3",	"rf,rf,wf"		},
/* 0x44 */	{	"mulf2",	"rf,mf"			},
/* 0x45 */	{	"mulf3",	"rf,rf,wf"		},
/* 0x46 */	{	"divf2",	"rf,mf"			},
/* 0x47 */	{	"divf3",	"rf,rf,wf"		},
/* 0x48 */	{	"cvtfb",	"rf,wb"			},
/* 0x49 */	{	"cvtfw",	"rf,ww"			},
/* 0x4a */	{	"cvtfl",	"rf,wl"			},
/* 0x4b */	{	"cvtrfl",	"rf,wl"			},
/* 0x4c */	{	"cvtbf",	"rb,wf"			},
/* 0x4d */	{	"cvtwf",	"rw,wf"			},
/* 0x4e */	{	"cvtlf",	"rl,wf"			},
/* 0x4f */	{	"acbf",		"rf,rf,rf,bw"		},
	   
/* 0x50 */	{	"MOVF",		"rf,wf"			},
/* 0x51 */	{	"CMPF",		"rf,rf"			},
/* 0x52 */	{	"mnegf",	"rf,wf"			},
/* 0x53 */	{	"TSTF",		"rf"			},
/* 0x54 */	{	"emodf",	"rf,rb,rf,wl,wf"	},
/* 0x55 */	{	"polyf",	"rf,rw,ab"		},
/* 0x56 */	{	"cvtfd",	"rf,wd"			},
/* 0x57 */	{	"-reserved-",	NULL			},
/* 0x58 */	{	"adawi",	"rw,mw"			},
/* 0x59 */	{	"-reserved-",	NULL			},
/* 0x5a */	{	"-reserved-",	NULL			},
/* 0x5b */	{	"-reserved-",	NULL			},
/* 0x5c */	{	"insqhi",	"ab,aq"			},
/* 0x5d */	{	"insqti",	"ab,aq"			},
/* 0x5e */	{	"remqhi",	"aq,wl"			},
/* 0x5f */	{	"remqti",	"aq,wl"			},

/* 0x60 */	{	"addd2",	"rd,md"			},
/* 0x61 */	{	"addd3",	"rd,rd,wd"		},
/* 0x62 */	{	"subd2",	"rd,md"			},
/* 0x63 */	{	"subd3",	"rd,rd,wd"		},
/* 0x64 */	{	"muld2",	"rd,md"			},
/* 0x65 */	{	"muld3",	"rd,rd,wd"		},
/* 0x66 */	{	"divd2",	"rd,md"			},
/* 0x67 */	{	"divd3",	"rd,rd,wd"		},
/* 0x68 */	{	"cvtdb",	"rd,wb"			},
/* 0x69 */	{	"cvtdw",	"rd,ww"			},
/* 0x6a */	{	"cvtdl",	"rd,wl"			},
/* 0x6b */	{	"cvtrdl",	"rd,wl"			},
/* 0x6c */	{	"cvtbd",	"rb,wd"			},
/* 0x6d */	{	"cvtwd",	"rw,wd"			},
/* 0x6e */	{	"cvtld",	"rl,wd"			},
/* 0x6f */	{	"acbd",		"rd,rd,md,bw"		},
	   
/* 0x70 */	{	"MOVD",		"rd,wd"			},
/* 0x71 */	{	"CMPD",		"rd,rd"			},
/* 0x72 */	{	"mnegd",	"rd,wd"			},
/* 0x73 */	{	"TSTD",		"rd"			},
/* 0x74 */	{	"emodd",	"rd,rb,rd,wl,wd"	},
/* 0x75 */	{	"polyd",	"rd,rw,ab"		},
/* 0x76 */	{	"cvtdf",	"rd,wf"			},
/* 0x77 */	{	"-reserved-",	NULL			},
/* 0x78 */	{	"ashl",		"rb,rl,wl"		},
/* 0x79 */	{	"ashq",		"rb,rq,wq"		},
/* 0x7a */	{	"emul",		"rl,rl,rl,wq"		},
/* 0x7b */	{	"ediv",		"rl,rq,wl,wl"		},
/* 0x7c */	{	"CLRQ",		"wq"			},
/* 0x7d */	{	"MOVQ",		"rq,wq"			},
/* 0x7e */	{	"MOVAQ",	"aq,wl"			},
/* 0x7f */	{	"pushaq",	"aq"			},
	   
/* 0x80 */	{	"addb2",	"rb,mb"			},
/* 0x81 */	{	"addb3",	"rb,rb,wb"		},
/* 0x82 */	{	"subb2",	"rb,mb"			},
/* 0x83 */	{	"subb3",	"rb,rb,wb"		},
/* 0x84 */	{	"mulb2",	"rb,mb"			},
/* 0x85 */	{	"mulb3",	"rb,rb,wb"		},
/* 0x86 */	{	"divb2",	"rb,mb"			},
/* 0x87 */	{	"divb3",	"rb,rb,wb"		},
/* 0x88 */	{	"BISB2",	"rb,mb"			},
/* 0x89 */	{	"BISB3",	"rb,rb,wb"		},
/* 0x8a */	{	"BICB2",	"rb,mb"			},
/* 0x8b */	{	"BICB3",	"rb,rb,wb"		},
/* 0x8c */	{	"XORB2",	"rb,mb"			},
/* 0x8d */	{	"XORB3",	"rb,rb,wb"		},
/* 0x8e */	{	"mnegb",	"rb,wb"			},
/* 0x8f */	{	"caseb",	"rb,rb,rb,bw-list"	},

/* 0x90 */	{	"MOVB",		"rb,wb"			},
/* 0x91 */	{	"CMPB",		"rb,rb"			},
/* 0x92 */	{	"mcomb",	"rb,wb"			},
/* 0x93 */	{	"bitb",		"rb,rb"			},
/* 0x94 */	{	"CLRB",		"wb"			},
/* 0x95 */	{	"TSTB",		"rb"			},
/* 0x96 */	{	"INCB",		"mb"			},
/* 0x97 */	{	"DECB",		"mb"			},
/* 0x98 */	{	"cvtbl",	"rb,wl"			},
/* 0x99 */	{	"cvtbw",	"rb,ww"			},
/* 0x9a */	{	"MOVZBL",	"rb,wl"			},
/* 0x9b */	{	"MOVZBW",	"wb,ww"			},
/* 0x9c */	{	"rotl",		"rb,rl,wl"		},
/* 0x9d */	{	"acbb",		"rb,rb,mb,bw"		},
/* 0x9e */	{	"MOVAB",	"ab,wl"			},
/* 0x9f */	{	"pushab",	"ab"			},
	   
/* 0xa0 */	{	"addw2",	"rw,mw"			},
/* 0xa1 */	{	"addw3",	"rw,rw,ww"		},
/* 0xa2 */	{	"subw2",	"rw,mw"			},
/* 0xa3 */	{	"subw3",	"rw,rw,ww"		},
/* 0xa4 */	{	"mulw2",	"rw,mw"			},
/* 0xa5 */	{	"mulw3",	"rw,rw,ww"		},
/* 0xa6 */	{	"divw2",	"rw,mw"			},
/* 0xa7 */	{	"divw3",	"rw,rw,ww"		},
/* 0xa8 */	{	"BISW2",	"rw,mw"			},
/* 0xa9 */	{	"BISW3",	"rw,rw,ww"		},
/* 0xaa */	{	"BICW2",	"rw,mw"			},
/* 0xab */	{	"BICW3",	"rw,rw,ww"		},
/* 0xac */	{	"XORW2",	"rw,mw"			},
/* 0xad */	{	"XORW3",	"rw,rw,ww"		},
/* 0xae */	{	"mnegw",	"rw,ww"			},
/* 0xaf */	{	"casew",	"rw,rw,rw,bw-list"	},
	   
/* 0xb0 */	{	"MOVW",		"rw,ww"			},
/* 0xb1 */	{	"CMPW",		"rw,rw"			},
/* 0xb2 */	{	"mcomw",	"rw,ww"			},
/* 0xb3 */	{	"bitw",		"rw,rw"			},
/* 0xb4 */	{	"CLRW",		"mw"			},
/* 0xb5 */	{	"TSTW",		"rw"			},
/* 0xb6 */	{	"INCW",		"mw"			},
/* 0xb7 */	{	"DECW",		"mw"			},
/* 0xb8 */	{	"BISPSW",	"rw"			},
/* 0xb9 */	{	"BICPSW",	"rw"			},
/* 0xba */	{	"popr",		"rw"			},
/* 0xbb */	{	"pushr",	"rw"			},
/* 0xbc */	{	"chmk",		"rw"			},
/* 0xbd */	{	"chme",		"rw"			},
/* 0xbe */	{	"chms",		"rw"			},
/* 0xbf */	{	"chmu",		"rw"			},

/* 0xc0 */	{	"addl2",	"rl,ml"			},
/* 0xc1 */	{	"addl3",	"rl,rl,wl"		},
/* 0xc2 */	{	"subl2",	"rl,ml"			},
/* 0xc3 */	{	"subl3",	"rl,rl,wl"		},
/* 0xc4 */	{	"mull2",	"rl,ml"			},
/* 0xc5 */	{	"mull3",	"rl,rl,wl"		},
/* 0xc6 */	{	"divl2",	"rl,ml"			},
/* 0xc7 */	{	"divl3",	"rl,rl,wl"		},
/* 0xc8 */	{	"BISL2",	"rl,ml"			},
/* 0xc9 */	{	"BISL3",	"rl,rl,wl"		},
/* 0xca */	{	"BICL2",	"rl,ml"			},
/* 0xcb */	{	"BICL3",	"rl,rl,wl"		},
/* 0xcc */	{	"XORL2",	"rl,ml"			},
/* 0xcd */	{	"XORL3",	"rl,rl,wl"		},
/* 0xce */	{	"mnegl",	"rl,wl"			},
/* 0xcf */	{	"casel",	"rl,rl,rl,bw-list"	},
	   
/* 0xd0 */	{	"MOVL",		"rl,wl"			},
/* 0xd1 */	{	"CMPL",		"rl,rl"			},
/* 0xd2 */	{	"mcoml",	"rl,wl"			},
/* 0xd3 */	{	"bitl",		"rl,rl"			},
/* 0xd4 */	{	"CLRL",		"wl"			},
/* 0xd5 */	{	"TSTL",		"rl"			},
/* 0xd6 */	{	"INCL",		"ml"			},
/* 0xd7 */	{	"DECL",		"ml"			},
/* 0xd8 */	{	"adwc",		"rl,ml"			},
/* 0xd9 */	{	"sbwc",		"rl,ml"			},
/* 0xda */	{	"MTPR",		"rl,rl"			},
/* 0xdb */	{	"MFPR",		"rl,wl"			},
/* 0xdc */	{	"MOVPSL",	"wl"			},
/* 0xdd */	{	"pushl",	"rl"			},
/* 0xde */	{	"MOVAL",	"al,wl"			},
/* 0xdf */	{	"pushal",	"al"			},
	   
/* 0xe0 */	{	"bbs",		"rl,vb,bb"		},
/* 0xe1 */	{	"bbc",		"rl,vb,bb"		},
/* 0xe2 */	{	"bbss",		"rl,vb,bb"		},
/* 0xe3 */	{	"bbcs",		"rl,vb,bb"		},
/* 0xe4 */	{	"bbsc",		"rl,vb,bb"		},
/* 0xe5 */	{	"bbcc",		"rl,vb,bb"		},
/* 0xe6 */	{	"bbssi",	"rl,vb,bb"		},
/* 0xe7 */	{	"bbcci",	"rl,vb,bb"		},
/* 0xe8 */	{	"blbs",		"rl,bb"			},
/* 0xe9 */	{	"blbc",		"rl,bb"			},
/* 0xea */	{	"ffs",		"rl,rb,vb"		},
/* 0xeb */	{	"ffc",		"rl,rb,vb"		},
/* 0xec */	{	"CMPV",		"rl,rb,vb,rl"		},
/* 0xed */	{	"CMPZV",	"rl,rb,vb,rl"		},
/* 0xee */	{	"extv",		"rl,rb,vb,wl"		},
/* 0xef */	{	"extzv",	"rl,rb,vb,wl"		},

/* 0xf0 */	{	"insv",		"rl,rl,rb,vb"		},
/* 0xf1 */	{	"acbl",		"rl,rl,ml,bw"		},
/* 0xf2 */	{	"aoblss",	"rl,ml,bb"		},
/* 0xf3 */	{	"aobleq",	"rl,ml,bb"		},
/* 0xf4 */	{	"sobgeq",	"ml,bb"			},
/* 0xf5 */	{	"sobgtr",	"ml,bb"			},
/* 0xf6 */	{	"cvtlb",	"rl,wb"			},
/* 0xf7 */	{	"cvtlw",	"rl,ww"			},
/* 0xf8 */	{	"ashp",		"rb,rw,ab,rb,rw,ab"	},
/* 0xf9 */	{	"cvtlp",	"rl,rw,ab"		},
/* 0xfa */	{	"callg",	"ab,ab"			},
/* 0xfb */	{	"calls",	"rl,ab"			},
/* 0xfc */	{	"xfc",		"?"			},
/* 0xfd */	{	"-reserved-",	NULL			},
/* 0xfe */	{	"-reserved-",	NULL			},
/* 0xff */	{	"-reserved-",	NULL			},
};


#!/usr/bin/env python3
"""mk_t62.py - writes tests/mmu/t62_cmops.s: PDP-11 compatibility mode
instructions with random operands, each followed by BPT, checked against
the reference simulator:

    python3 tests/mmu/gen/mk_t62.py > tests/mmu/t62_cmops.s

The instructions are those whose results the VAX Architecture Reference
Manual (chapter 9) defines: the double and single operand ones (word and
byte), SWAB, SXT, MUL, DIV (even registers), ASH, ASHC, XOR, MFPI/MFPD,
MTPI/MTPD and the condition code operators, with all eight addressing
modes. Before each one, R0-R5 are loaded - with random values, or with
addresses in the data area when a specifier needs a pointer - SP is set to
the stack area and the condition codes to a random pattern. Memory operands
are in the data area (5000-5FFF), pointers for the deferred modes in the
pointer table (6000-60FF), and the stack is 6800-77FF; the three are dumped
at the end. PC as a register appears as #n (immediate), @#a (absolute), a
(relative) and @a (relative deferred).

The BPT handler logs the code, PC, PSL and R0-R6 of each, as t61 does.
"""
import random

import sys

# python3 mk_t62.py [seed [cases]]: other random tests of the same kind
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 8600
R = random.Random(SEED)
N_CASES = int(sys.argv[2]) if len(sys.argv) > 2 else 600

DATA = (0x5000, 0x6000)
PTRS = (0x6000, 0x6100)
STACK = (0x6800, 0x7800)
SP0 = 0x7000

EDGE = [0, 1, 2, 0x7F, 0x80, 0xFF, 0x100, 0x7FFE, 0x7FFF, 0x8000, 0x8001,
        0xFF7F, 0xFF80, 0xFFFE, 0xFFFF]


def rval():
    if R.random() < 0.4:
        return R.choice(EDGE)
    return R.randrange(0x10000)


DOUBLE = ['MOV', 'CMP', 'BIT', 'BIC', 'BIS', 'ADD', 'SUB',
          'MOVB', 'CMPB', 'BITB', 'BICB', 'BISB']
DACC = {'MOV': 'w', 'CMP': 'r', 'BIT': 'r', 'BIC': 'm', 'BIS': 'm',
        'ADD': 'm', 'SUB': 'm'}
SINGLE = ['CLR', 'COM', 'INC', 'DEC', 'NEG', 'ADC', 'SBC', 'TST', 'ROR',
          'ROL', 'ASR', 'ASL']
SACC = {'CLR': 'w', 'TST': 'r'}
CCOPS = ['NOP', 'CLC', 'CLV', 'CLZ', 'CLN', 'CCC', 'SEC', 'SEV', 'SEZ', 'SEN',
         'SCC']


class Case:
    """One instruction: the register values it needs and its text."""

    def __init__(self):
        self.regs = {}          # register -> ('ptr', region, align) or value
        self.code = ''

    def need(self, r, kind):
        """kind: ('val',) or ('ptr', lo, hi, align). False on a conflict."""
        old = self.regs.get(r)
        if old is None:
            self.regs[r] = kind
            return True
        if kind[0] == 'val':
            return True                     # any value does for mode 0
        if old[0] == 'val':
            self.regs[r] = kind
            return True
        return old == kind


def spec(case, acc, byte, regs_ok=(0, 1, 2, 3, 4, 5)):
    """A random operand specifier for an operand of access acc ('r', 'w',
    'm') and size byte/word; registers in case.regs get what they need."""
    for _ in range(50):
        mode = R.randrange(8)
        r = R.choice(list(regs_ok) + [6, 7])
        if r == 7:
            # PC: #n, @#a, a, @a
            if mode == 0 or mode == 1 or mode in (4, 5):
                continue
            if mode == 2:
                if acc != 'r' and R.random() < 0.7:
                    continue                # writes go into the immediate
                return '#^x%X' % rval()
            if mode == 3:
                a = R.randrange(*DATA) & ~(0 if byte else 1)
                return '@#^x%X' % a
            if mode == 6:
                a = R.randrange(*DATA) & ~(0 if byte else 1)
                return '^x%X' % a
            a = R.randrange(*PTRS) & ~1
            return '@^x%X' % a
        if r == 6:
            # SP: (SP), (SP)+, -(SP), X(SP); it is set to SP0 each time
            if mode not in (1, 2, 4, 6):
                continue
            if mode == 1:
                return '(SP)'
            if mode == 2:
                return '(SP)+'
            if mode == 4:
                return '-(SP)'
            return '%d(SP)' % (R.randrange(-64, 64) * 2)
        if mode == 0:
            if not case.need(r, ('val',)):
                continue
            return 'R%d' % r
        align = 1 if byte else 2
        if mode in (1, 2, 4):
            k = ('ptr', 0x5100, 0x5F00, align)
            if not case.need(r, k):
                continue
            if mode != 1:
                case.delta[r] = case.delta.get(r, 0) + \
                    (align if mode == 2 else -align)
            return {1: '(R%d)', 2: '(R%d)+', 4: '-(R%d)'}[mode] % r
        if mode in (3, 5):
            k = ('ptr', 0x6010, 0x60F0, 2)
            if not case.need(r, k):
                continue
            case.delta[r] = case.delta.get(r, 0) + (2 if mode == 3 else -2)
            return {3: '@(R%d)+', 5: '@-(R%d)'}[mode] % r
        # X(Rn), @X(Rn): Rn anywhere in 0-FFFF, X such that Rn + X lands in
        # the data area (6) or the pointer table (7) - with Rn as an earlier
        # specifier of the instruction left it (delta)
        k = ('val',)
        if not case.need(r, k):
            continue
        case.xspecs.append((r, mode, align, case.delta.get(r, 0)))
        return '<X%d>' % (len(case.xspecs) - 1)
    raise RuntimeError('no specifier')


def gen_case():
    c = Case()
    c.xspecs = []
    c.delta = {}            # register -> what earlier specifiers did to it
    kind = R.random()
    if kind < 0.40:
        op = R.choice(DOUBLE)
        byte = op in ('MOVB', 'CMPB', 'BITB', 'BICB', 'BISB')
        acc = DACC[op[:-1] if byte else op]
        s = spec(c, 'r', byte)
        d = spec(c, acc, byte)
        text = '%s %s, %s' % (op, s, d)
    elif kind < 0.72:
        op = R.choice(SINGLE + ['SWAB', 'SXT'])
        byte = op in SINGLE and R.random() < 0.4
        acc = SACC.get(op, 'w' if op == 'SXT' else 'm')
        d = spec(c, acc, byte)
        text = '%s%s %s' % (op, 'B' if byte else '', d)
    elif kind < 0.86:
        op = R.choice(['MUL', 'DIV', 'ASH', 'ASHC', 'XOR'])
        if op == 'DIV':
            r = R.choice([0, 2, 4])
        else:
            r = R.randrange(6)
        c.need(r, ('val',))
        if op == 'XOR':
            d = spec(c, 'm', False)
            text = 'XOR R%d, %s' % (r, d)
        else:
            s = spec(c, 'r', False)
            text = '%s %s, R%d' % (op, s, r)
    elif kind < 0.94:
        op = R.choice(['MFPI', 'MFPD', 'MTPI', 'MTPD'])
        d = spec(c, 'r' if op.startswith('MF') else 'w', False)
        text = '%s %s' % (op, d)
    else:
        text = R.choice(CCOPS)
    # the register values
    setup = []
    vals = {}
    for r in range(6):
        k = c.regs.get(r)
        if k is None or k[0] == 'val':
            v = rval()
        else:
            lo, hi, align = k[1], k[2], k[3]
            v = R.randrange(lo, hi) & ~(align - 1)
        vals[r] = v
    # X(Rn): the index that puts Rn + X in the data area / pointer table
    for i, (r, mode, align, delta) in enumerate(c.xspecs):
        # (inside the areas, with a margin)
        if mode == 6:
            target = R.randrange(0x5010, 0x5FF0) & ~(align - 1)
        else:
            target = R.randrange(0x6010, 0x60F0) & ~1
        x = (target - vals[r] - delta) & 0xFFFF
        text = text.replace('<X%d>' % i,
                            '%s^x%X(R%d)' % ('@' if mode == 7 else '', x, r))
    for r in range(6):
        setup.append('\tmov\t#^x%X, r%d' % (vals[r], r))
    setup.append('\tmov\t#^x%X, sp' % SP0)
    cc = R.randrange(16)
    setup.append('\tccc')
    if cc:
        setup.append('\t.word\t^o%o\t\t; set %s' % (0o260 | cc, bin(cc)))
    return setup + ['\t%s' % text.lower(), '\tbpt']


def words(lo, hi, f):
    out = []
    for a in range(lo, hi, 16):
        out.append('\t.word\t' + ', '.join('^x%04X' % f(a + 2 * i)
                                            for i in range(8)))
    return out


def main():
    hdr = __doc__.split('\n\n')[0].replace('mk_t62.py - writes '
                                           'tests/mmu/t62_cmops.s', 't62_cmops')
    print('; t62_cmops - PDP-11 compatibility mode instructions with random')
    print('; operands against the reference simulator; written by')
    print('; tests/mmu/gen/mk_t62.py (which see). Each instruction is followed by')
    print('; BPT; the handler logs code, PC, PSL, R0-R6.')
    print(';@ dump=18000:%X' % (N_CASES * 10 + 4))
    print(';@ dump=5000:A00')
    print(';@ clocks=6000000')
    print('''LOG	= ^x18000
KSP	= 0
USP	= 3
SCBB	= ^x11
CMPSL	= ^x83C00000

	.org	^x1000
start:	movl	#^x17800, sp		; above 64K: the compat code is
					; up to FFFF
	clrl	r0
	movab	unexp+1, r1
scbfill: movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	cmexc, @#^x30
	mtpr	#0, #SCBB
	mtpr	#^x17000, #KSP
	mtpr	#^x16800, #USP
	movl	#LOG, r11
	pushl	#CMPSL
	pushl	#^x8000
	rei

	.org	^x8000
	.pdp11''')
    for i in range(N_CASES):
        print('; %d' % i)
        print('\n'.join(gen_case()))
    print('\temt\t^o377')
    print('\t.vax')
    print('; the data area, the pointer table (into the data area), the stack')
    print('\t.org\t^x%X' % DATA[0])
    print('\n'.join(words(DATA[0], DATA[1], lambda a: R.randrange(0x10000))))
    print('\t.org\t^x%X' % PTRS[0])
    print('\n'.join(words(PTRS[0], PTRS[1],
                          lambda a: R.randrange(0x5100, 0x5F00) & ~1)))
    print('\t.org\t^x%X' % STACK[0])
    print('\n'.join(words(STACK[0], STACK[1], lambda a: R.randrange(0x10000))))
    print('; the handlers, after the log; mkboard.py (software/mmutest.bin) appends')
    print('; its code and table after them, out of the way of the test')
    print('\t.org\t^x1F000')
    print('''	.align	4
cmexc:	movl	(sp)+, r10		; the code
	movl	r10, (r11)+
	movl	(sp), (r11)+		; PC
	movl	4(sp), (r11)+		; PSL
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	cmpl	r10, #1			; BPT: on
	bneq	cmx
	addl2	#2, (sp)
	rei
cmx:	movzwl	@(sp), r9
	cmpl	r9, #^o104377		; EMT 377: the end
	beql	done
	addl2	#2, (sp)		; anything else: logged, stepped over
	rei
done:	halt

	.align	4
unexp:	movl	#^xBAD, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	halt''')


if __name__ == '__main__':
    main()

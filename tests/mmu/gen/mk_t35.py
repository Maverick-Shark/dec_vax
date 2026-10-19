#!/usr/bin/env python3
# mk_t35.py - generates tests/mmu/t35_dec.s, random decimal string instruction cases (seed, count):
#     python3 tests/mmu/gen/mk_t35.py [seed] [count] > tests/mmu/t35_dec.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
import random, sys
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
ncase = int(sys.argv[2]) if len(sys.argv) > 2 else 120
random.seed(seed)

def packed(n, sign=None, hi=0):
    """bytes of an n-digit packed string, digits random"""
    if sign is None:
        sign = random.choice([0xC, 0xD, 0xC, 0xD, 0xA, 0xB, 0xE, 0xF])
    digits = [random.randint(0, 9) for _ in range(n)]
    # sometimes small values (leading zeros), sometimes zero
    r = random.random()
    if r < 0.15:
        digits = [0] * n
    elif r < 0.4 and n > 2:
        k = random.randint(1, n)
        digits = [0] * (n - k) + digits[n - k:]
    nib = digits + [sign]
    if n % 2 == 0:
        nib = [hi] + nib
    return bytes((nib[i] << 4) | nib[i + 1] for i in range(0, len(nib), 2))

lines = []
datas = []
dcount = [0]
def data(b):
    lab = 'd%d' % dcount[0]
    dcount[0] += 1
    datas.append('%s:\t.byte\t%s' % (lab, ', '.join('^x%02X' % x for x in b)))
    return lab

DST = 'S0+^x1C000'			# above the log (the test image reaches past 8000)
def case(com, ins, psw=0, dumpdst=True):
    lines.append('; ' + com)
    lines.append('\tmovc5\t#0, @#%s, #^x55, #32, @#%s' % (DST, DST))
    for r in range(6):
        lines.append('\tmovl\t#^x%X, r%d' % (0x11111111 * (r + 1), r))
    lines.append('\tbicpsw\t#^xFF')
    if psw:
        lines.append('\tbispsw\t#^x%X' % psw)
    lines.append('\t' + ins)
    lines.append('\tmovpsl\t(r11)+')
    lines.append('\tmovq\tr0, (r11)+')
    lines.append('\tmovq\tr2, (r11)+')
    lines.append('\tmovq\tr4, (r11)+')
    lines.append('\tmovc3\t#20, @#%s, (r11)' % DST)
    lines.append('\tmovl\tr3, r11')

def rl():
    return random.choice([random.randint(0, 31), random.randint(0, 31), random.randint(0, 8), 31])

for i in range(ncase):
    k = random.choice(['movp', 'cmpp3', 'cmpp4', 'addp4', 'addp6', 'subp4',
                       'subp6', 'mulp', 'divp', 'cvtlp', 'cvtpl', 'ashp',
                       'cvtps', 'cvtsp', 'cvtpt', 'cvttp'])
    psw = random.choice([0, 0, 0, 0x80, 0x20, 0x01])	# DV, IV, C
    if k == 'movp':
        n = rl(); s = data(packed(n))
        case('MOVP %d' % n, 'movp\t#%d, @#S0+%s, @#%s' % (n, s, DST), psw)
    elif k in ('cmpp3',):
        n = rl(); a = data(packed(n)); b = data(packed(n) if random.random() < 0.7 else packed(n))
        case('CMPP3 %d' % n, 'cmpp3\t#%d, @#S0+%s, @#S0+%s' % (n, a, b), psw)
    elif k == 'cmpp4':
        n1, n2 = rl(), rl(); a = data(packed(n1)); b = data(packed(n2))
        case('CMPP4 %d %d' % (n1, n2), 'cmpp4\t#%d, @#S0+%s, #%d, @#S0+%s' % (n1, a, n2, b), psw)
    elif k in ('addp4', 'subp4'):
        n1, n2 = rl(), rl(); a = data(packed(n1)); b = packed(n2)
        # the sum string is modified: copy it to DST first
        lines.append('; %s: the second string copied to the destination' % k.upper())
        lab = data(b)
        lines.append('\tmovc3\t#16, @#S0+%s, @#S0+^x1C100' % lab)
        case('%s %d %d' % (k.upper(), n1, n2),
             '%s\t#%d, @#S0+%s, #%d, @#S0+^x1C100' % (k, n1, a, n2), psw)
        lines.append('\tmovc3\t#16, @#S0+^x1C100, (r11)')
        lines.append('\tmovl\tr3, r11')
    elif k in ('addp6', 'subp6', 'mulp', 'divp'):
        n1, n2, n3 = rl(), rl(), rl()
        a = packed(n1)
        if k == 'divp' and random.random() < 0.15:
            a = packed(n1, hi=0)
            a = bytes([0] * (len(a) - 1) + [a[-1] & 0x0F])	# zero divisor
        la = data(a); lb = data(packed(n2))
        case('%s %d %d %d' % (k.upper(), n1, n2, n3),
             '%s\t#%d, @#S0+%s, #%d, @#S0+%s, #%d, @#%s' % (k, n1, la, n2, lb, n3, DST), psw)
    elif k == 'cvtlp':
        v = random.choice([random.randint(-2**31, 2**31 - 1), random.randint(-999999, 999999),
                           0, -1, -2**31, 2**31 - 1, random.randint(-99, 99)])
        n = rl()
        case('CVTLP %d %d' % (v, n), 'cvtlp\t#%d, #%d, @#%s' % (v, n, DST), psw)
    elif k == 'cvtpl':
        n = rl(); s = data(packed(n))
        dst = random.choice(['r6', 'r6', 'r0', 'r3', '@#S0+^x1C000'])
        case('CVTPL %d -> %s' % (n, dst), 'cvtpl\t#%d, @#S0+%s, %s' % (n, s, dst), psw)
        lines.append('\tmovl\tr6, (r11)+')
    elif k == 'ashp':
        n1, n2 = rl(), rl(); s = data(packed(n1))
        cnt = random.choice([random.randint(-10, 10), random.randint(-40, 40), -128, 127, 0, 1, -1])
        rnd = random.choice([0, 5, 9, 4, 0x15, 0xA])
        case('ASHP %d %d %d %d' % (cnt, n1, rnd, n2),
             'ashp\t#%d, #%d, @#S0+%s, #%d, #%d, @#%s' % (cnt, n1, s, rnd, n2, DST), psw)
    elif k == 'cvtps':
        n1, n2 = rl(), rl(); s = data(packed(n1))
        case('CVTPS %d %d' % (n1, n2), 'cvtps\t#%d, @#S0+%s, #%d, @#%s' % (n1, s, n2, DST), psw)
    elif k == 'cvtsp':
        n1, n2 = rl(), rl()
        sg = random.choice(b'+- ')
        digs = bytes(random.choice(b'0123456789') for _ in range(n1))
        s = data(bytes([sg]) + digs)
        case('CVTSP %d %d' % (n1, n2), 'cvtsp\t#%d, @#S0+%s, #%d, @#%s' % (n1, s, n2, DST), psw)
    elif k == 'cvtpt':
        n1, n2 = rl(), rl(); s = data(packed(n1))
        case('CVTPT %d %d' % (n1, n2), 'cvtpt\t#%d, @#S0+%s, @#S0+ptab, #%d, @#%s' % (n1, s, n2, DST), psw)
    elif k == 'cvttp':
        n1, n2 = rl(), rl()
        digs = [random.choice(b'0123456789') for _ in range(n1)]
        if n1:
            last = digs[-1] - 0x30
            digs[-1] = (0x30 + last) if random.random() < 0.5 else (0x70 + last)	# '0'-'9' or 'p'-'y'
        s = data(bytes(digs))
        case('CVTTP %d %d' % (n1, n2), 'cvttp\t#%d, @#S0+%s, @#S0+ttab, #%d, @#%s' % (n1, s, n2, DST), psw)

out = []
out.append("""; t35_dec - the decimal string instructions on random operands (seed %d):
; MOVP, CMPP3, CMPP4, ADDP4, ADDP6, SUBP4, SUBP6, MULP, DIVP (a zero divisor
; now and then: decimal divide by zero trap), CVTLP, CVTPL, ASHP, CVTPS,
; CVTSP, CVTPT, CVTTP, with PSL<DV> (decimal overflow trap), PSL<IV> or C
; set before some. Each case logs the PSL, R0-R5 and the destination; the
; trap handler logs 34, the type code, PC and PSL. Generated by
; mk_t35.py; the expected values come from the reference simulator.
;@ dump=18000:A00 clocks=8000000
	.include "mmsetup.inc"
test:
	movl	#S0+arith_h, @#^x34
""" % seed)
out += lines
out.append('\thalt')
out.append("""	.align	4
arith_h:
	movl	#^x34, (r11)+
	movl	(sp)+, (r11)+			; type code
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei
""")
# CVTPT table: the last byte (digit<7:4>, sign<3:0>) -> a character:
# plus: '0'-'9', minus: 'p'-'y'
pt = []
for b in range(256):
    d, sg = b >> 4, b & 15
    if d <= 9 and sg in (0xB, 0xD):
        pt.append(0x70 + d)
    elif d <= 9:
        pt.append(0x30 + d)
    else:
        pt.append(0x3F)
tt = []
for c in range(256):
    if 0x30 <= c <= 0x39:
        tt.append(((c - 0x30) << 4) | 0xC)
    elif 0x70 <= c <= 0x79:
        tt.append(((c - 0x70) << 4) | 0xD)
    else:
        tt.append(0xFF)
out.append('ptab:')
for i in range(0, 256, 16):
    out.append('\t.byte\t' + ', '.join('^x%02X' % x for x in pt[i:i + 16]))
out.append('ttab:')
for i in range(0, 256, 16):
    out.append('\t.byte\t' + ', '.join('^x%02X' % x for x in tt[i:i + 16]))
out += datas
sys.stdout.write('\n'.join(out) + '\n')

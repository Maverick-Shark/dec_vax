#!/usr/bin/env python3
"""mk_fp.py - generates the floating point instruction tests t42_fpf.s,
t43_fpd.s, t44_fpg.s and t45_fph.s (one per format):

    python3 tests/mmu/gen/mk_fp.py          (from the project root)

Each test runs a few hundred cases of the format's instructions on random
operands (sim/fpu_tb/vaxfp.py's generator: ordinary values, zeros, the
largest and smallest, reserved operands, fractions of all ones and with
few bits) in register, memory, short literal and immediate modes, with
PSL<FU> and PSL<IV> set or clear at random: ADD, SUB, MUL, DIV (two and
three operands), MOV, MNEG, TST, CMP, CVT to and from integers and to the
other formats, EMOD, POLY and ACB. A case stores its results in the result
area and logs the PSL; a fault (reserved operand, floating overflow, divide
by zero, underflow) or a trap (integer overflow) logs its type, PC and PSL
and the program goes on with the next case. The expected values are not in
the tests: run.py compares everything with the reference simulator.
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'sim', 'fpu_tb'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import vaxfp  # noqa: E402
import vaxfloat  # noqa: E402

NAMES = 'FDGH'
SIZE = {0: 4, 1: 8, 2: 8, 3: 16}
SEED = {0: 4201, 1: 4301, 2: 4401, 3: 4501}
NCASES = {0: 520, 1: 420, 2: 400, 3: 290}
TEST = {0: 't42_fpf', 1: 't43_fpd', 2: 't44_fpg', 3: 't45_fph'}
RES = 0x1A000           # results, dumped (cleared by the board runner)
RESLEN = 0x4000
LOG = 0x18000           # the log (R11), up to RES
IMGTOP = 0xC000         # the board suite's image (test, operands, table of
                        # expected values) must end below the stacks


class Gen:
    def __init__(self, fmt):
        self.fmt = fmt
        self.x = NAMES[fmt].lower()
        self.size = SIZE[fmt]
        self.rng = random.Random(SEED[fmt])
        self.code = []
        self.data = []          # (label, bytes), after the code
        self.rptr = RES
        self.n = 0

    # ---- helpers
    def words(self, special=0.15):
        return vaxfp.rand_words(self.fmt, self.rng, special)

    def bits(self, w):
        """The operand's bytes, memory order."""
        return b''.join(x.to_bytes(4, 'little') for x in w[:self.size // 4])

    def const(self, b):
        """Put bytes in the data after the code; their address (an
        expression)."""
        lab = 'k%d' % len(self.data)
        self.data.append((lab, b))
        return lab

    def result(self, n):
        a = self.rptr
        self.rptr += (n + 3) & ~3
        assert self.rptr < RES + RESLEN, 'result area full'
        return a

    def emit(self, s):
        self.code.append(s)

    def move_raw(self, src_addr, dst, nbytes):
        """Copy the bits (integer moves: no reserved operand check)."""
        mv = {4: 'movl', 8: 'movq', 16: 'movo'}[nbytes]
        self.emit('\t%s\t@#S0+%s, %s' % (mv, src_addr, dst))

    def operand(self, w, reg=None):
        """A source operand for the words w: a register (loaded first), a
        short literal, an immediate or memory."""
        r = self.rng.random()
        try:
            v = vaxfp.value(w, self.fmt)
            lit = vaxfloat.literal(v)
        except vaxfp.RsvdOp:
            lit = None
        if lit is not None and r < 0.5:
            return 'S^#%s' % self.lit_text(lit)
        if reg is not None and r < 0.4:
            a = self.const(self.bits(w))
            self.move_raw(a, reg, self.size)
            return reg
        if r < 0.55:
            v = 0
            for i, x in enumerate(w[:self.size // 4]):
                v |= x << (32 * i)
            return 'I^#^x%X' % v
        return '@#S0+%s' % self.const(self.bits(w))

    def lit_text(self, lit):
        # the literal as a decimal number the assembler turns back into it
        from fractions import Fraction
        v = Fraction(8 + (lit & 7), 16) * Fraction(2) ** (lit >> 3)
        s = '%.6f' % float(v)
        assert vaxfloat.literal(vaxfloat.parse(s)) == lit
        return s

    def dest(self, reg=None):
        """A destination: memory in the result area, or a register (its
        value logged after)."""
        if reg is not None and self.rng.random() < 0.3:
            return reg, True
        return '@#S0+^x%X' % self.result(self.size), False

    def log_reg(self, reg, nbytes):
        n = {'r0': 0, 'r2': 2, 'r4': 4, 'r6': 6}[reg]
        if n + nbytes // 4 > 8:
            raise ValueError('register log past R7')
        for i in range(nbytes // 4):
            self.emit('\tmovl\tr%d, @#S0+^x%X' % (n + i, self.result(4)))

    def psw(self):
        fu = self.rng.getrandbits(1)
        iv = self.rng.getrandbits(1)
        self.emit('\tbicpsw\t#^x60')
        if fu or iv:
            self.emit('\tbispsw\t#^x%X' % ((0x40 if fu else 0) | (0x20 if iv else 0)))

    def case_begin(self, comment):
        self.n += 1
        self.emit('; %d: %s' % (self.n, comment))
        self.emit('\tmovab\tc%d, r8' % self.n)
        self.psw()

    def case_end(self):
        self.emit('\tmovpsl\t(r11)+')
        self.emit('c%d:' % self.n)

    # ---- instruction kinds
    def arith(self, op):
        x = self.x
        a, b = self.words(), self.words()
        if op in ('add', 'sub') and self.rng.random() < 0.3:
            b = vaxfp.close_pair(a, self.fmt, self.rng)
        three = self.rng.getrandbits(1)
        self.case_begin('%s%s%d' % (op, x, 3 if three else 2))
        if three:
            sa = self.operand(a, 'r0')
            sb = self.operand(b, 'r2' if self.size <= 8 else 'r4')
            d, isreg = self.dest('r6' if self.size == 4 else None)
            self.emit('\t%s%s3\t%s, %s, %s' % (op, x, sa, sb, d))
        else:
            sa = self.operand(a, 'r0')
            if self.size <= 8 and self.rng.random() < 0.3:
                d, isreg = 'r2', True
            elif self.size == 16 and self.rng.random() < 0.3:
                d, isreg = 'r4', True
            else:
                d, isreg = '@#S0+^x%X' % self.result(self.size), False
            self.move_raw(self.const(self.bits(b)), d, self.size)
            self.emit('\t%s%s2\t%s, %s' % (op, x, sa, d))
        self.case_end()
        if isreg:
            self.log_reg(d, self.size)

    def move(self, op):
        a = self.words()
        self.case_begin('%s%s' % (op, self.x))
        sa = self.operand(a, 'r0')
        d, isreg = self.dest('r4' if self.size <= 8 else 'r4')
        self.emit('\t%s%s\t%s, %s' % (op, self.x, sa, d))
        self.case_end()
        if isreg:
            self.log_reg(d, self.size)

    def test(self):
        a = self.words()
        self.case_begin('tst%s' % self.x)
        self.emit('\ttst%s\t%s' % (self.x, self.operand(a, 'r0')))
        self.case_end()

    def cmp(self):
        a, b = self.words(), self.words()
        if self.rng.random() < 0.3:
            b = list(a)
            if self.rng.random() < 0.5:
                b[0] ^= 0x8000
        self.case_begin('cmp%s' % self.x)
        self.emit('\tcmp%s\t%s, %s' % (self.x, self.operand(a, 'r0'),
                                       self.operand(b, 'r4')))
        self.case_end()

    def cvt_to_int(self):
        a = self.words()
        if self.rng.random() < 0.6:
            nexp, prec, bias, nw = vaxfp.FMT[self.fmt]
            s, E, frac = vaxfp.words_to_bits(a, self.fmt)
            if E:
                a = vaxfp.bits_to_words(s, bias + self.rng.randrange(-2, 36), frac, self.fmt)
        t = self.rng.choice(['b', 'w', 'l', 'rl'])
        self.case_begin('cvt%s%s' % (self.x if t != 'rl' else 'r' + self.x, t[-1]))
        mn = 'cvtr%sl' % self.x if t == 'rl' else 'cvt%s%s' % (self.x, t)
        d = '@#S0+^x%X' % self.result(4)
        self.emit('\t%s\t%s, %s' % (mn, self.operand(a, 'r0'), d))
        self.case_end()

    def cvt_from_int(self):
        t = self.rng.choice(['b', 'w', 'l'])
        v = self.rng.choice([0, 1, -1, 0x7F, -0x80, 0x7FFF, -0x8000,
                             0x7FFFFFFF, -0x80000000, 0x00FFFFFF, 0x01000001,
                             self.rng.getrandbits(32) - (1 << 31),
                             self.rng.getrandbits(12)])
        mask = {'b': 0xFF, 'w': 0xFFFF, 'l': 0xFFFFFFFF}[t]
        self.case_begin('cvt%s%s' % (t, self.x))
        d, isreg = self.dest('r4')
        self.emit('\tcvt%s%s\tI^#^x%X, %s' % (t, self.x, v & mask, d))
        self.case_end()
        if isreg:
            self.log_reg(d, self.size)

    def cvt_formats(self):
        others = {0: 'dgh', 1: 'fh', 2: 'fh', 3: 'fdg'}[self.fmt]
        y = self.rng.choice(others)
        a = self.words()
        self.case_begin('cvt%s%s' % (self.x, y))
        n = SIZE['fdgh'.index(y)]
        d = '@#S0+^x%X' % self.result(n)
        self.emit('\tcvt%s%s\t%s, %s' % (self.x, y, self.operand(a, 'r0'), d))
        self.case_end()

    def emod(self):
        a, b = self.words(), self.words()
        if self.rng.random() < 0.7:
            nexp, prec, bias, nw = vaxfp.FMT[self.fmt]
            s, E, frac = vaxfp.words_to_bits(a, self.fmt)
            if E:
                a = vaxfp.bits_to_words(s, bias + self.rng.randrange(-4, 30), frac, self.fmt)
            s, E, frac = vaxfp.words_to_bits(b, self.fmt)
            if E:
                b = vaxfp.bits_to_words(s, bias + self.rng.randrange(-4, 8), frac, self.fmt)
        ext = self.rng.getrandbits(16)
        self.case_begin('emod%s' % self.x)
        xs = 'I^#^x%X' % (ext & 0xFF) if self.fmt < 2 else 'I^#^x%X' % ext
        di = '@#S0+^x%X' % self.result(4)
        if self.rng.random() < 0.3:
            di = 'r6'
        df, isreg = self.dest('r2' if self.size <= 8 else None)
        self.emit('\temod%s\t%s, %s, %s, %s, %s' % (
            self.x, self.operand(a, 'r0'), xs, self.operand(b, 'r4'), di, df))
        self.case_end()
        if di == 'r6':
            self.emit('\tmovl\tr6, @#S0+^x%X' % self.result(4))
        if isreg:
            self.log_reg(df, self.size)

    def poly(self):
        deg = self.rng.choice([0, 1, 2, 3, 4, 5, 8, 31, 32])
        nexp, prec, bias, nw = vaxfp.FMT[self.fmt]
        coef = []
        for _ in range(min(deg, 31) + 1):
            w = self.words(0.04)
            s, E, frac = vaxfp.words_to_bits(w, self.fmt)
            if E and self.rng.random() < 0.8:
                w = vaxfp.bits_to_words(s, bias + self.rng.randrange(-3, 3), frac, self.fmt)
            coef.append(w)
        table = self.const(b''.join(self.bits(w) for w in coef))
        arg = self.words(0.1)
        s, E, frac = vaxfp.words_to_bits(arg, self.fmt)
        if E and self.rng.random() < 0.8:
            arg = vaxfp.bits_to_words(s, bias + self.rng.randrange(-3, 2), frac, self.fmt)
        self.case_begin('poly%s, degree %d' % (self.x, deg))
        for r in range(6):
            self.emit('\tmovl\t#^x%X, r%d' % (0x11111111 * (r + 1), r))
        self.emit('\tpoly%s\t%s, #%d, @#S0+%s' % (
            self.x, self.operand(arg, None), deg, table))
        self.emit('\tmovpsl\t(r11)+')
        for r in range(6):
            self.emit('\tmovl\tr%d, @#S0+^x%X' % (r, self.result(4)))
        self.emit('c%d:' % self.n)

    def acb(self):
        # index, add, limit of moderate size; at most 20 times round
        def val(lo, hi):
            w = self.words(0.05)
            nexp, prec, bias, nw = vaxfp.FMT[self.fmt]
            s, E, frac = vaxfp.words_to_bits(w, self.fmt)
            if E and self.rng.random() < 0.85:
                w = vaxfp.bits_to_words(s, bias + self.rng.randrange(lo, hi), frac, self.fmt)
            return w
        idx, add, lim = val(-2, 4), val(-3, 2), val(-1, 5)
        self.case_begin('acb%s' % self.x)
        if self.rng.random() < 0.3:
            d, isreg = 'r2', True               # the index in R2.. (R2-R5)
        else:
            d, isreg = '@#S0+^x%X' % self.result(self.size), False
        self.move_raw(self.const(self.bits(idx)), d, self.size)
        self.emit('\tclrl\tr6')
        self.emit('a%d:\tincl\tr6' % self.n)
        self.emit('\tcmpl\tr6, #20')
        self.emit('\tbgeq\tb%d' % self.n)
        self.emit('\tacb%s\t%s, %s, %s, a%d' % (
            self.x, self.operand(lim, None), self.operand(add, None), d, self.n))
        self.emit('b%d:\tmovl\tr6, (r11)+' % self.n)
        self.case_end()
        if isreg:
            self.log_reg(d, self.size)

    def build(self):
        kinds = (['add', 'sub', 'mul', 'div'] * 4 + ['mov', 'mneg', 'tst', 'cmp',
                 'cvti', 'cvtf', 'cvtx', 'cvti', 'emod', 'poly', 'acb'])
        for i in range(NCASES[self.fmt]):
            k = kinds[i % len(kinds)]
            if k in ('add', 'sub', 'mul', 'div'):
                self.arith(k)
            elif k in ('mov', 'mneg'):
                self.move(k)
            elif k == 'tst':
                self.test()
            elif k == 'cmp':
                self.cmp()
            elif k == 'cvti':
                self.cvt_to_int()
            elif k == 'cvtf':
                self.cvt_from_int()
            elif k == 'cvtx':
                self.cvt_formats()
            elif k == 'emod':
                self.emod()
            elif k == 'poly':
                self.poly()
            else:
                self.acb()

    def text(self, nlog):
        name = TEST[self.fmt]
        nres = (self.rptr - RES + 3) // 4
        out = ["""; %s - %s_floating instructions on random operands (generated by
; tests/mmu/gen/mk_fp.py, which says what is in it): ADD, SUB, MUL, DIV, MOV,
; MNEG, TST, CMP, CVT to and from integers and to the other formats, EMOD,
; POLY, ACB; reserved operands, overflow, underflow with PSL<FU> set and
; clear, divide by zero, integer overflow with PSL<IV> set and clear.
; Compared with the reference simulator.
;@ dump=%X:%X dump=%X:%X clocks=40000000""" % (name, NAMES[self.fmt], RES, nres,
                                             LOG, nlog),
               '\t.include "mmsetup.inc"',
               'test:',
               '\tmovl\t#S0+arith_h, @#^x34',
               '\tmovl\t#S0+fix_skip, r10']
        out += self.code
        out += ['\thalt',
                '; arithmetic exception: type code, PC, PSL; go on at R8',
                '\t.align\t4',
                'arith_h:',
                '\tmovl\t(sp)+, (r11)+',
                '\tmovl\t(sp), (r11)+',
                '\tmovl\t4(sp), (r11)+',
                '\tmovl\tr8, (sp)',
                '\trei',
                '; the operands']
        for lab, b in self.data:
            out.append('\t.align\t2')
            out.append('%s:' % lab)
            for i in range(0, len(b), 4):
                out.append('\t.long\t^x%08X' % int.from_bytes(b[i:i + 4], 'little'))
        return '\n'.join(out) + '\n'


def log_length(path):
    """Longwords the test logs, from a run on the reference simulator."""
    import importlib.util
    import tempfile
    spec = importlib.util.spec_from_file_location(
        'mmurun', os.path.join(ROOT, 'tests', 'mmu', 'run.py'))
    run = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(run)
    with tempfile.TemporaryDirectory() as tmp:
        binf = os.path.join(tmp, 'prog.bin')
        load = run.assemble(path, binf)
        res, out = run.run_ref(binf, load, load, [], tmp)
        end = os.path.getsize(binf) + load
    n = ((res['R11'] & 0x3FFFFFFF) - LOG) // 4
    return n, end


def main():
    for fmt in range(4):
        g = Gen(fmt)
        g.build()
        path = os.path.join(ROOT, 'tests', 'mmu', TEST[fmt] + '.s')
        open(path, 'w').write(g.text(0x400))
        nlog, end = log_length(path)
        open(path, 'w').write(g.text(nlog))
        nres = (g.rptr - RES + 3) // 4
        # the board suite adds board.inc and 12 bytes an expected value
        img = end + 0x100 + 12 * (16 + nres + nlog)
        print('%s: %d cases, %d results, %d log longwords, image to %X' % (
            path, g.n, nres, nlog, img))
        if img > IMGTOP:
            raise SystemExit('too big for the board suite')


if __name__ == '__main__':
    main()

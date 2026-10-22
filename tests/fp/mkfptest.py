#!/usr/bin/env python3
"""mkfptest.py - builds software/fptest.bin, a self-checking test of the 98
VAX floating point instructions (F, D, G and H) for the core: random
operands, whose expected results, condition codes and exceptions come from
sim/fpu_tb/vaxfp.py, the exact model of the arithmetic written from the VAX
Architecture Reference Manual (SRM). No reference simulator is needed, so
each seed gives a new set of cases.

    python3 tests/fp/mkfptest.py                    seed 1, 200 cases each
    python3 tests/fp/mkfptest.py --seed 7 --cases 500 -o software/fp7.bin
    python3 tests/fp/mkfptest.py --only ADDF3,MULH3 --cases 2000
    python3 tests/fp/mkfptest.py --seed 7 --show ADDF3:17

--show prints one case - its sources and destination, decoded, and what is
expected - and writes nothing. Give it the --seed, --cases and --only the
file was built with: the board prints the seed in its first line, and the
instruction and case number of each failure. (tools/vaxfloat.py -d F
3D70F501 decodes a single value.)

Load the file like mmutest.bin: OSD Load Address 0x00001000, Start Address
= Load Address, Autostart Yes. The screen shows a table of the
instructions, "ok" or "ERR" for each, the number of cases and of failures,
and the details of the first four failures.

What each case does: the driver (tests/fp/fpharness.s) sets PSL<FU>,
PSL<IV> and the condition codes at random, puts random bytes in the
destination, runs the instruction once with its sources in memory, and
compares the exception it took (none, reserved operand fault, the
arithmetic fault or trap type), the condition codes (not after a fault:
the SRM leaves them UNPREDICTABLE) and the destination (unchanged after a
fault) with the model's.

The operands: ordinary values, values near 1, sparse and all-ones
fractions (rounding ties and carries), zeros, "dirty" zeros (sign 0,
exponent 0, fraction not 0), reserved operands, the largest and smallest
numbers, pairs that cancel when subtracted, halves for CVTR, ties for the
narrowing conversions, integers at the edges of their ranges, exponents
that overflow and underflow.
"""
import argparse
import os
import random
import struct
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'sim', 'fpu_tb'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import vaxfp  # noqa: E402
import vasm  # noqa: E402
import vaxfloat  # noqa: E402

F, D, G, H = range(4)
X = 'FDGH'
SIZE = {F: 4, D: 8, G: 8, H: 16}
ISIZE = {'B': 1, 'W': 2, 'L': 4}
BASE = 0x1000

# expected exception codes (fpharness.s)
E_NONE, E_RSV = 0, 0x18
E_IOV, E_FOV, E_FDZ, E_FUN = 0x101, 0x108, 0x109, 0x10A
# condition codes
CN, CZ, CV, CC = 8, 4, 2, 1


class Rsvd(Exception):
    pass


def val(w, f):
    try:
        return vaxfp.value(w, f)
    except vaxfp.RsvdOp:
        raise Rsvd()


def wbytes(words, n):
    """Longwords (memory order) as n bytes."""
    return b''.join(x.to_bytes(4, 'little') for x in words)[:n]


def nz(v):
    return (CN if v < 0 else 0) | (CZ if v == 0 else 0)


# ------------------------------------------------------------------ operands

def rnd_words(f, rng, special=0.15):
    return vaxfp.rand_words(f, rng, special)


def set_exp(w, f, e):
    """w with its exponent set to bias + e (zeros and reserved left)."""
    nexp, prec, bias, nw = vaxfp.FMT[f]
    s, E, frac = vaxfp.words_to_bits(w, f)
    if E == 0:
        return w
    return vaxfp.bits_to_words(s, max(1, min((1 << nexp) - 1, bias + e)), frac, f)


def exact(v, f):
    """The words of v, which must be exact in format f."""
    r = vaxfp.round_pack(Fraction(v), f, 0)
    assert r.words is not None
    return r.words


def tie_words(f, f_dst, rng):
    """A value of format f that sits on, just below or just above a
    rounding boundary of the smaller format f_dst."""
    nexp, prec, bias, nw = vaxfp.FMT[f]
    pd = vaxfp.FMT[f_dst][1]
    drop = prec - pd                    # bits that go
    kept = rng.getrandbits(pd - 1)
    k = rng.randrange(4)
    if k == 0:
        low = 1 << (drop - 1)           # exactly half: away from zero
    elif k == 1:
        low = (1 << (drop - 1)) - 1     # just below half
    elif k == 2:
        low = (1 << (drop - 1)) | 1     # just above half
    else:
        low = (1 << drop) - 1           # all ones: carries
    if rng.random() < 0.5:
        kept = (1 << (pd - 1)) - 1      # a carry into the exponent
    dmax = (1 << vaxfp.FMT[f_dst][0]) - 1
    dbias = vaxfp.FMT[f_dst][2]
    e = rng.randrange(1, dmax + 1) - dbias          # inside the target range
    if rng.random() < 0.2:
        e = rng.choice([dmax - dbias, 1 - dbias, 2 - dbias, dmax - dbias - 1])
    E = max(1, min((1 << nexp) - 1, bias + e))
    return vaxfp.bits_to_words(rng.getrandbits(1), E, (kept << drop) | low, f)


def half_words(f, rng):
    """n + 1/2 (or n), for CVTR: the halves go away from zero."""
    prec = vaxfp.FMT[f][1]
    nbits = rng.randrange(0, min(prec - 1, 33))
    n = rng.getrandbits(nbits) if nbits else 0
    v = Fraction(2 * n + 1, 2) if rng.random() < 0.8 else Fraction(n)
    if rng.random() < 0.5:
        v = -v
    if v == 0:
        return [0] * vaxfp.FMT[f][3]
    return exact(v, f)


def edge_int(isz, rng):
    bits = 8 * isz
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    k = rng.random()
    if k < 0.3:
        n = rng.choice([0, 1, -1, lo, hi, lo + 1, hi - 1, 0x7F, -0x80, 0xFF,
                        0x7FFF, -0x8000, 0xFFFF, 0x00FFFFFF, 0x01000000,
                        0x01000001, 0x01FFFFFF, -0x01000001, 0x7FFFFF80,
                        0x7FFFFFC0, 0x40000041])
    else:
        nb = rng.randrange(1, bits + 1)
        n = rng.getrandbits(nb) - (1 << (nb - 1) if rng.random() < 0.5 else 0)
    return n & ((1 << bits) - 1)


# ------------------------------------------------------------------ the model
# Each returns (exception, condition code mask, condition codes, the
# destination's bytes after); a fault leaves the destination as it was
# (init) and its condition codes unchecked.

def fault(e, init, dlen):
    return e, 0, 0, init[:dlen]


def done(r, f, cc_extra, init, dlen):
    """A floating result r (vaxfp.Result) rounded to f."""
    if r.ovf:
        return fault(E_FOV, init, dlen)
    if r.unf:
        return fault(E_FUN, init, dlen)
    cc = (CN if r.neg else 0) | (CZ if r.zero else 0) | cc_extra
    return E_NONE, 0xF, cc, wbytes(r.words, SIZE[f])


def m_arith(kind, f, a, b, fu, init):
    s = SIZE[f]
    try:
        va = val(a, f)
        vb = val(b, f)
    except Rsvd:
        return fault(E_RSV, init, s)
    if kind == 'add':
        x = vb + va
    elif kind == 'sub':
        x = vb - va
    elif kind == 'mul':
        x = vb * va
    else:
        if va == 0:
            return fault(E_FDZ, init, s)
        x = vb / va
    return done(vaxfp.round_pack(x, f, fu), f, 0, init, s)


def m_move(kind, f, a, fu, cc_in, init):
    s = SIZE[f]
    try:
        v = val(a, f)
    except Rsvd:
        return fault(E_RSV, init, s)
    if kind == 'mneg':
        v = -v
    r = vaxfp.round_pack(v, f, fu)
    # MOV: C unchanged; MNEG: C cleared (SRM)
    return done(r, f, (cc_in & CC) if kind == 'mov' else 0, init, s)


def m_tst(f, a):
    try:
        v = val(a, f)
    except Rsvd:
        return fault(E_RSV, b'', 0)
    return E_NONE, 0xF, nz(v), b''


def m_cmp(f, a, b):
    try:
        va, vb = val(a, f), val(b, f)
    except Rsvd:
        return fault(E_RSV, b'', 0)
    return E_NONE, 0xF, (CN if va < vb else 0) | (CZ if va == vb else 0), b''


def m_cvtif(f, isz, n, fu, init):
    bits = 8 * isz
    if n & (1 << (bits - 1)):
        n -= 1 << bits
    return done(vaxfp.round_pack(Fraction(n), f, fu), f, 0, init, SIZE[f])


def m_cvtfi(f, isz, a, rnd, iv, init):
    try:
        val(a, f)
    except Rsvd:
        return fault(E_RSV, init, isz)
    res, iov = vaxfp.op_cvtfi(a, f, {1: 0, 2: 1, 4: 2}[isz], rnd)
    bits = 8 * isz
    stored = res & ((1 << bits) - 1)
    cc = (CN if stored >> (bits - 1) else 0) | (CZ if stored == 0 else 0) | \
        (CV if iov else 0)
    return (E_IOV if iov and iv else E_NONE), 0xF, cc, stored.to_bytes(isz, 'little')


def m_cvtff(f, fd, a, fu, init):
    try:
        v = val(a, f)
    except Rsvd:
        return fault(E_RSV, init, SIZE[fd])
    return done(vaxfp.round_pack(v, fd, fu), fd, 0, init, SIZE[fd])


def m_emod(f, a, ext, b, fu, iv, init):
    s = SIZE[f]
    try:
        val(a, f)
        val(b, f)
    except Rsvd:
        return fault(E_RSV, init, 4 + s)
    r, ires, iov = vaxfp.op_emod(a, ext, b, f, fu)
    if r.unf:
        return fault(E_FUN, init, 4 + s)
    assert not r.ovf
    cc = (CN if r.neg else 0) | (CZ if r.zero else 0) | (CV if iov else 0)
    return ((E_IOV if iov and iv else E_NONE), 0xF, cc,
            ires.to_bytes(4, 'little') + wbytes(r.words, s))


def m_poly(f, arg, deg, coef, fu, init, tbl):
    """R0-R5 after POLY (24 bytes); tbl is the table's address."""
    s = SIZE[f]
    if deg > 31:
        return fault(E_RSV, init, 24)
    try:
        val(arg, f)
        R = vaxfp.round_pack(val(coef[0], f), f, fu)
        for c in coef[1:deg + 1]:
            val(c, f)
            R = vaxfp.op_poly_step(R.words, arg, c, f, fu)
            if R.ovf:
                return fault(E_FOV, init, 24)
            if R.unf:
                return fault(E_FUN, init, 24)
    except Rsvd:
        return fault(E_RSV, init, 24)
    end = (tbl + (deg + 1) * s).to_bytes(4, 'little')
    res = wbytes(R.words, s)
    z4 = bytes(4)
    if f == F:      # R0 result, R1 R2 0, R3 past the table, R4 R5 kept
        regs = res + z4 + z4 + end + init[16:24]
    elif f == H:    # R0-R3 result, R4 0, R5 past the table
        regs = res + z4 + end
    else:           # R0 R1 result, R2 0, R3 past the table, R4 R5 0
        regs = res + z4 + end + z4 + z4
    cc = (CN if R.neg else 0) | (CZ if R.zero else 0)
    return E_NONE, 0xF, cc, regs


def m_acb(f, limit, add, cc_in, fu, init):
    """index (the first SIZE bytes of init) + add; then the branch flag."""
    s = SIZE[f]
    idx = [int.from_bytes(init[i:i + 4], 'little') for i in range(0, s, 4)]
    try:
        vl, va, vi = val(limit, f), val(add, f), val(idx, f)
    except Rsvd:
        return fault(E_RSV, init, s + 4)
    r = vaxfp.round_pack(vi + va, f, fu)
    if r.ovf:
        return fault(E_FOV, init, s + 4)
    if r.unf:
        return fault(E_FUN, init, s + 4)
    vn = vaxfp.value(r.words, f)
    taken = vn <= vl if va >= 0 else vn >= vl
    cc = (CN if r.neg else 0) | (CZ if r.zero else 0) | (cc_in & CC)
    return E_NONE, 0xF, cc, wbytes(r.words, s) + (1 if taken else 0).to_bytes(4, 'little')


# ------------------------------------------------------------------ instructions

def instructions():
    out = []
    for f in range(4):
        x = X[f]
        out += [('MOV' + x, 'mov', f, None), ('MNEG' + x, 'mneg', f, None),
                ('TST' + x, 'tst', f, None), ('CMP' + x, 'cmp', f, None)]
        for op in ('ADD', 'SUB', 'MUL', 'DIV'):
            out += [(op + x + '2', op.lower() + '2', f, None),
                    (op + x + '3', op.lower() + '3', f, None)]
        for i in 'BWL':
            out.append(('CVT' + i + x, 'cvtif', f, i))
        for i in 'BWL':
            out.append(('CVT' + x + i, 'cvtfi', f, i))
        out.append(('CVTR' + x + 'L', 'cvtrfl', f, 'L'))
        for y in {F: 'DGH', D: 'FH', G: 'FH', H: 'FDG'}[f]:
            out.append(('CVT' + x + y, 'cvtff', f, X.index(y)))
        out += [('EMOD' + x, 'emod', f, None), ('POLY' + x, 'poly', f, None),
                ('ACB' + x, 'acb', f, None)]
    return out


class Case:
    pass


class Block:
    def __init__(self, idx, name, kind, f, extra):
        self.idx, self.name, self.kind, self.f, self.extra = idx, name, kind, f, extra
        s = SIZE[f]
        k = kind
        if k in ('mov', 'mneg', 'tst', 'cvtfi', 'cvtrfl', 'cvtff') or k[-1] == '2':
            self.opslen = s
        elif k in ('cmp', 'acb') or k[-1] == '3':
            self.opslen = 2 * s
        elif k == 'cvtif':
            self.opslen = 4
        elif k == 'emod':
            self.opslen = 2 * s + 4
        elif k == 'poly':
            self.opslen = s + 8
        if k in ('tst', 'cmp'):
            dl = 0
        elif k in ('cvtfi', 'cvtrfl'):
            dl = ISIZE[extra]
        elif k == 'cvtff':
            dl = SIZE[extra]
        elif k == 'emod':
            dl = 4 + s
        elif k == 'poly':
            dl = 24
        elif k == 'acb':
            dl = s + 4
        else:
            dl = s
        self.dlen = dl
        self.dlenp = (dl + 3) & ~3
        self.init_off = 16 + self.opslen
        self.exp_off = self.init_off + self.dlenp
        self.stride = self.exp_off + self.dlenp
        self.cases = []

    # ---- the stub: the instruction, sources off R6, destination in dstbuf
    def stub(self):
        s = SIZE[self.f]
        mn = self.name.lower()
        lab = 'stub%d' % self.idx
        k = self.kind
        o2 = 16 + s
        if k == 'tst':
            body = ['%s\t16(r6)' % mn]
        elif k == 'cmp':
            body = ['%s\t16(r6), %d(r6)' % (mn, o2)]
        elif k[-1] == '3':
            body = ['%s\t16(r6), %d(r6), dstbuf' % (mn, o2)]
        elif k == 'emod':
            body = ['%s\t16(r6), %d(r6), %d(r6), dstbuf, dstbuf+4' % (mn, o2, o2 + 4)]
        elif k == 'poly':
            return [lab + ':',
                    '\t%s\t16(r6), %d(r6), @%d(r6)' % (mn, o2, o2 + 4),
                    '\tmovpsl\tpslaft',
                    '\tmovq\tr0, dstbuf',
                    '\tmovq\tr2, dstbuf+8',
                    '\tmovq\tr4, dstbuf+16',
                    '\tbrw\tafter2']
        elif k == 'acb':
            t = 'tk%d' % self.idx
            return [lab + ':',
                    '\t%s\t16(r6), %d(r6), dstbuf, %s' % (mn, o2, t),
                    '\tmovpsl\tpslaft',
                    '\tclrl\tdstbuf+%d' % s,
                    '\tbrw\tafter2',
                    '%s:\tmovpsl\tpslaft' % t,
                    '\tmovl\t#1, dstbuf+%d' % s,
                    '\tbrw\tafter2']
        else:
            body = ['%s\t16(r6), dstbuf' % mn]
        return [lab + ':'] + ['\t' + b for b in body] + ['\tbrw\tafter']

    # ---- the cases
    def gen(self, rng, n):
        for _ in range(n):
            self.cases.append(self.gen_one(rng))

    def gen_one(self, rng):
        c = Case()
        f, k, s = self.f, self.kind, SIZE[self.f]
        c.cc_in = rng.getrandbits(4)
        c.fu = rng.getrandbits(1)
        c.iv = rng.getrandbits(1)
        c.psw = c.cc_in | (c.iv << 5) | (c.fu << 6)
        c.init = bytes(rng.getrandbits(8) for _ in range(self.dlenp))
        c.ops = b''
        c.tbl = None
        if k in ('mov', 'mneg', 'tst'):
            a = rnd_words(f, rng, 0.3)
            c.ops = wbytes(a, s)
            if k == 'tst':
                c.res = m_tst(f, a)
            else:
                c.res = m_move(k, f, a, c.fu, c.cc_in, c.init)
        elif k == 'cmp':
            a, b = rnd_words(f, rng), rnd_words(f, rng)
            r = rng.random()
            if r < 0.25:
                b = list(a)
            elif r < 0.4:
                b = list(a)
                b[0] ^= 0x8000          # -a (of a zero: a reserved operand)
            elif r < 0.5:
                b = vaxfp.close_pair(a, f, rng)
            c.ops = wbytes(a, s) + wbytes(b, s)
            c.res = m_cmp(f, a, b)
        elif k[:-1] in ('add', 'sub', 'mul', 'div'):
            op = k[:-1]
            a, b = rnd_words(f, rng), rnd_words(f, rng)
            r = rng.random()
            if op in ('add', 'sub') and r < 0.35:
                b = vaxfp.close_pair(a, f, rng)
            elif op in ('mul', 'div') and r < 0.3:
                a = set_exp(a, f, rng.randrange(-6, 7))
                b = set_exp(b, f, rng.randrange(-6, 7))
            elif op == 'div' and r < 0.35:
                a = [0] * len(a) if rng.random() < 0.5 else \
                    vaxfp.bits_to_words(0, 0, rng.getrandbits(8), f)
            if k[-1] == '2':
                # the second operand is the destination: in init
                c.init = wbytes(b, s) + c.init[s:]
                c.ops = wbytes(a, s)
            else:
                c.ops = wbytes(a, s) + wbytes(b, s)
            c.res = m_arith(op, f, a, b, c.fu, c.init)
        elif k == 'cvtif':
            isz = ISIZE[self.extra]
            n = edge_int(isz, rng)
            c.ops = n.to_bytes(4, 'little')
            c.res = m_cvtif(f, isz, n, c.fu, c.init)
        elif k in ('cvtfi', 'cvtrfl'):
            isz = ISIZE[self.extra]
            r = rng.random()
            if r < 0.2:
                a = half_words(f, rng)
            elif r < 0.7:
                a = set_exp(rnd_words(f, rng, 0.1), f, rng.randrange(-2, 8 * isz + 4))
            elif r < 0.8:
                a = set_exp(rnd_words(f, rng, 0.1), f, rng.randrange(8 * isz + 4, 170))
            else:
                a = rnd_words(f, rng)
            c.ops = wbytes(a, s)
            c.res = m_cvtfi(f, isz, a, 1 if k == 'cvtrfl' else 0, c.iv, c.init)
        elif k == 'cvtff':
            fd = self.extra
            r = rng.random()
            if SIZE[fd] < s or (f == G and fd == F) or (f == H and fd != H):
                narrowing = True
            else:
                narrowing = False
            if narrowing and r < 0.35:
                a = tie_words(f, fd, rng)
            elif narrowing and r < 0.55:
                # near the target's exponent limits
                dmax = (1 << vaxfp.FMT[fd][0]) - 1
                dbias = vaxfp.FMT[fd][2]
                e = rng.choice([dmax - dbias + rng.randrange(-2, 3),
                                1 - dbias + rng.randrange(-3, 3)])
                a = set_exp(rnd_words(f, rng, 0.0), f, e)
            else:
                a = rnd_words(f, rng)
            c.ops = wbytes(a, s)
            c.res = m_cvtff(f, fd, a, c.fu, c.init)
        elif k == 'emod':
            a, b = rnd_words(f, rng), rnd_words(f, rng)
            r = rng.random()
            if r < 0.6:
                a = set_exp(a, f, rng.randrange(-4, 30))
                b = set_exp(b, f, rng.randrange(-4, 8))
            elif r < 0.75:
                a = set_exp(a, f, rng.randrange(20, 50))   # integer overflow
                b = set_exp(b, f, rng.randrange(0, 20))
            ext = rng.getrandbits(16)
            if f in (F, D):
                ext &= 0xFF
            c.ops = wbytes(a, s) + ext.to_bytes(4, 'little') + wbytes(b, s)
            c.res = m_emod(f, a, ext, b, c.fu, c.iv, c.init)
        elif k == 'poly':
            r = rng.random()
            deg = rng.choice([0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 31])
            if r < 0.03:
                deg = rng.choice([32, 33, 100, 0x7FFF, 0xFFFF])
            nexp, prec, bias, nw = vaxfp.FMT[f]
            coef = []
            for _ in range(min(deg, 31) + 1):
                w = rnd_words(f, rng, 0.04)
                if rng.random() < 0.8:
                    w = set_exp(w, f, rng.randrange(-3, 3))
                coef.append(w)
            arg = rnd_words(f, rng, 0.1)
            if rng.random() < 0.8:
                arg = set_exp(arg, f, rng.randrange(-3, 2))
            c.poly = (arg, deg, coef)
            c.ops = wbytes(arg, s) + deg.to_bytes(4, 'little')   # + table address
            c.tbl_bytes = b''.join(wbytes(w, s) for w in coef) if deg <= 31 else b''
            c.res = None            # once the table's address is known
        elif k == 'acb':
            def v(lo, hi):
                w = rnd_words(f, rng, 0.05)
                if rng.random() < 0.85:
                    w = set_exp(w, f, rng.randrange(lo, hi))
                return w
            idx, add, lim = v(-2, 4), v(-3, 2), v(-1, 5)
            c.init = wbytes(idx, s) + c.init[s:]
            c.ops = wbytes(lim, s) + wbytes(add, s)
            c.res = m_acb(f, lim, add, c.cc_in, c.fu, c.init)
        else:
            raise ValueError(k)
        return c

    def layout(self):
        """For --show: the sources (name, type, offset in the operands,
        bytes) and the destination (name, type, bytes); a type is a
        floating format (0-3), 'int', 'hex', 'addr' or 'flag'."""
        f, k, s = self.f, self.kind, SIZE[self.f]
        names = {'add': ('add1', 'add2', 'sum'), 'sub': ('sub', 'min', 'dif'),
                 'mul': ('mulr', 'muld', 'prod'), 'div': ('divr', 'divd', 'quo')}
        if k in ('mov', 'mneg'):
            return [('src', f, 0, s)], [('dst', f, s)]
        if k == 'tst':
            return [('src', f, 0, s)], []
        if k == 'cmp':
            return [('src1', f, 0, s), ('src2', f, s, s)], []
        if k[:-1] in names:
            n1, n2, nd = names[k[:-1]]
            if k[-1] == '2':
                return [(n1 if k[:-1] != 'add' else 'add', f, 0, s)], [(nd, f, s)]
            return [(n1, f, 0, s), (n2, f, s, s)], [(nd, f, s)]
        if k == 'cvtif':
            return [('src', 'int', 0, ISIZE[self.extra])], [('dst', f, s)]
        if k in ('cvtfi', 'cvtrfl'):
            return [('src', f, 0, s)], [('dst', 'int', ISIZE[self.extra])]
        if k == 'cvtff':
            return [('src', f, 0, s)], [('dst', self.extra, SIZE[self.extra])]
        if k == 'emod':
            return ([('mulr', f, 0, s), ('mulrx', 'hex', s, 1 if f in (F, D) else 2),
                     ('muld', f, s + 4, s)], [('int', 'int', 4), ('fract', f, s)])
        if k == 'poly':
            return ([('arg', f, 0, s), ('degree', 'int', s, 2), ('tbladdr', 'addr', s + 4, 4)],
                    [('result', f, s), ('R%d-R5' % (s // 4), 'hex', 24 - s)])
        if k == 'acb':
            return [('limit', f, 0, s), ('add', f, s, s)], [('index', f, s), ('branch', 'flag', 4)]
        raise ValueError(k)

    def finish_poly(self, c, tbl):
        arg, deg, coef = c.poly
        c.tbl = tbl
        c.ops = c.ops + tbl.to_bytes(4, 'little')
        c.res = m_poly(self.f, arg, deg, coef, c.fu, c.init, tbl)

    def record(self, c):
        exc, mask, cc, dst = c.res
        assert len(dst) == self.dlen, (self.name, len(dst), self.dlen)
        ops = c.ops + bytes(self.opslen - len(c.ops))
        exp = dst + c.init[self.dlen:]
        rec = struct.pack('<IIII', c.psw, exc, mask, cc) + ops + c.init + exp
        assert len(rec) == self.stride
        return rec


# ------------------------------------------------------------------ the program

def source(blocks, hdr):
    """The assembler source: the harness, then the generated part."""
    out = open(os.path.join(HERE, 'fpharness.s')).read().split('\n')
    out.append('; ---------------------------------------- generated by mkfptest.py')
    out.append('NBLK = %d' % len(blocks))
    out.append('hdr:\t.ascii\t"\\r\\n%s"' % hdr)
    out.append('\t.asciz\t"\\r\\n\\r\\n"')
    for b in blocks:
        out.append('nm%d:\t.asciz\t"%-7s"' % (b.idx, b.name))
    out.append('; the stubs')
    for b in blocks:
        out += b.stub()
    out.append('; unexpected exceptions')
    vec = []
    for v in range(0, 0x200, 4):
        if v == 0x18:
            vec.append('h_rsv')
        elif v == 0x34:
            vec.append('h_arith')
        elif v >= 0x50:
            vec.append('h_dismiss')
        else:
            out.append('\t.align\t4')
            out.append('ux%X:\tmovl\t#^x%X, uvec' % (v, v))
            out.append('\tbrw\tufatal')
            vec.append('ux%X' % v)
    out.append('\t.align\t4')
    out.append('scbtab:')
    for i in range(0, len(vec), 4):
        out.append('\t.long\t' + ', '.join(vec[i:i + 4]))
    out.append('\t.align\t4')
    out.append('desc:')
    for b in blocks:
        out.append('\t.long\tnm%d, stub%d, 0, 0, %d, %d, %d, %d, %d, %d, 0' % (
            b.idx, b.idx, b.stride, b.init_off, b.exp_off, b.dlen,
            1 if b.kind == 'poly' else 0, b.opslen))
    return '\n'.join(out) + '\n'


def assemble(text):
    a = vasm.Assembler()
    lines = list(enumerate(text.split('\n'), 1))
    image = a.assemble(lines)
    lo, hi = min(image), max(image)
    if lo != BASE:
        raise SystemExit('the program does not start at %X' % BASE)
    return bytearray(image.get(i, 0) for i in range(lo, hi + 1)), a.syms


def build(args):
    allins = instructions()
    names = [i[0] for i in allins]
    blocks = []
    only = None
    if args.only:
        only = [x.strip().upper() for x in args.only.split(',') if x.strip()]
        for n in only:
            if n not in names:
                raise SystemExit('unknown instruction %s (the 98 are: %s)' % (n, ' '.join(names)))
    for i, (name, kind, f, extra) in enumerate(allins):
        if only is not None and name not in only:
            continue
        b = Block(i, name, kind, f, extra)
        # each instruction's cases depend only on the seed and its name
        b.gen(random.Random('%d:%s' % (args.seed, name)), args.cases)
        blocks.append(b)
    hdr = ('VAX floating point test - seed %d, %d %s, %d %s each\\r\\n'
           '(tests/fp/mkfptest.py, expected values from sim/fpu_tb/vaxfp.py)'
           % (args.seed, len(blocks),
              'instruction' if len(blocks) == 1 else 'instructions',
              args.cases, 'case' if args.cases == 1 else 'cases'))
    src = source(blocks, hdr)
    try:
        img, syms = assemble(src)
    except vasm.AsmError as e:
        raise SystemExit('the program does not assemble: %s' % e)
    # the cases after the program, then the POLY tables
    addr = (BASE + len(img) + 15) & ~15
    for b in blocks:
        b.tab = addr
        addr += b.stride * len(b.cases)
    addr = (addr + 15) & ~15
    tables = bytearray()
    tbase = addr
    for b in blocks:
        if b.kind != 'poly':
            continue
        for c in b.cases:
            t = tbase + len(tables)
            b.finish_poly(c, t)
            tables += c.tbl_bytes
            tables += bytes((-len(tables)) % 4)
    data = bytearray()
    for b in blocks:
        for c in b.cases:
            data += b.record(c)
    # fill in the descriptors
    for i, b in enumerate(blocks):
        off = syms['desc'] + 44 * i - BASE
        struct.pack_into('<II', img, off + 8, b.tab, len(b.cases))
    img += bytes((-(BASE + len(img))) % 16)
    out = bytes(img) + bytes(data) + bytes((tbase - BASE) - len(img) - len(data)) + bytes(tables)
    return blocks, out, src


EXC_TEXT = {E_NONE: 'no exception', E_RSV: 'reserved operand fault (resop)',
            E_IOV: 'integer overflow trap (intovf)',
            E_FOV: 'floating overflow fault (fltovf)',
            E_FDZ: 'floating divide by zero fault (fltdiv)',
            E_FUN: 'floating underflow fault (fltund)'}


def longs(bs):
    """Bytes as longwords in memory order, as the board prints them."""
    out = []
    for i in range(0, len(bs), 4):
        part = bs[i:i + 4]
        out.append('%0*X' % (2 * len(part), int.from_bytes(part, 'little')))
    return ' '.join(out)


def describe(bs, typ):
    if typ in (F, D, G, H):
        x = 'fdgh'[typ]
        return '%-35s %s' % (longs(bs), vaxfloat.decimal(vaxfloat.decode(bs, x),
                                                         vaxfloat.DIGITS[x]))
    n = int.from_bytes(bs, 'little')
    if typ == 'int':
        sn = n - (1 << (8 * len(bs))) if n >> (8 * len(bs) - 1) else n
        return '%-35s %d' % (longs(bs), sn)
    if typ == 'flag':
        return {0: 'not taken', 1: 'taken'}.get(n, '%08X (not written)' % n)
    return longs(bs)


def show(args):
    name, _, num = args.show.partition(':')
    name = name.strip().upper()
    blocks, out, src = build(args)
    b = [x for x in blocks if x.name == name]
    if not b:
        raise SystemExit('%s is not in this build' % name)
    b = b[0]
    try:
        k = int(num or 0)
    except ValueError:
        raise SystemExit('--show NAME:CASE, e.g. ADDF3:17')
    if not 0 <= k < len(b.cases):
        raise SystemExit('%s has cases 0 to %d' % (name, len(b.cases) - 1))
    c = b.cases[k]
    exc, mask, cc, dst = c.res
    srcs, dsts = b.layout()
    print('%s case %d (seed %d), record at %08X' % (b.name, k, args.seed,
                                                 b.tab + k * b.stride))
    print('  PSL before: FU %d, IV %d, condition codes %X (N Z V C = %d %d %d %d)' % (
        c.fu, c.iv, c.cc_in, c.cc_in >> 3, (c.cc_in >> 2) & 1, (c.cc_in >> 1) & 1, c.cc_in & 1))
    for nm, typ, off, size in srcs:
        print('  %-8s %s' % (nm, describe(c.ops[off:off + size], typ)))
    if b.kind == 'poly':
        arg, deg, coef = c.poly
        for i, w in enumerate(coef[:deg + 1] if deg <= 31 else []):
            print('    C%-5d %s' % (i, describe(wbytes(w, SIZE[b.f]), b.f)))
    pos = 0
    for nm, typ, size in dsts:
        print('  %-8s %s   (before)' % (nm, describe(c.init[pos:pos + size], typ)))
        pos += size
    print('  expected: %s' % EXC_TEXT.get(exc, '%X' % exc))
    if mask:
        print('            condition codes %X (N Z V C = %d %d %d %d)' % (
            cc, cc >> 3, (cc >> 2) & 1, (cc >> 1) & 1, cc & 1))
    else:
        print('            condition codes not checked (UNPREDICTABLE after a fault)')
    pos = 0
    for nm, typ, size in dsts:
        print('  %-8s %s' % (nm, describe(dst[pos:pos + size], typ)))
        pos += size


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--seed', type=int, default=1)
    p.add_argument('--cases', type=int, default=200, help='cases per instruction')
    p.add_argument('--only', help='instructions to test, e.g. ADDF3,MULH3')
    p.add_argument('-o', default=os.path.join(ROOT, 'software', 'fptest.bin'))
    p.add_argument('--show', metavar='NAME:CASE', help='print one case and stop')
    p.add_argument('-k', metavar='FILE', help='also write the program source')
    args = p.parse_args()
    if args.cases < 1:
        raise SystemExit('--cases must be at least 1')
    if args.show:
        show(args)
        return
    blocks, out, src = build(args)
    if BASE + len(out) > 0x2000000:
        raise SystemExit('%d bytes do not fit in the 32 MB the core addresses: use fewer'
                         ' --cases, or --only' % len(out))
    if args.k:
        open(args.k, 'w').write(src)
    open(args.o, 'wb').write(out)
    n = sum(len(b.cases) for b in blocks)
    print('%s: %d bytes, %d instructions, %d cases (seed %d); load and start at %X'
          % (args.o, len(out), len(blocks), n, args.seed, BASE))


if __name__ == '__main__':
    main()

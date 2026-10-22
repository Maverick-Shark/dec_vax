#!/usr/bin/env python3
"""vaxfp.py - an exact model of VAX floating point (F, D, G, H) for testing
rtl/fpunit.v, written from the VAX Architecture Reference Manual (chapter
3, "Floating-Point Instructions"): a result is the infinitely precise value,
normalized, then rounded by adding one at the first bit not kept and
chopping; the exponent is checked after rounding.

Numbers are handled as exact fractions (fractions.Fraction). Packed values
are lists of longwords in memory order.

    python3 vaxfp.py vectors.txt [count] [seed]

writes test vectors for sim/fpu_tb (see fpu_tb.cpp for the format).
"""
import random
import sys
from fractions import Fraction

# format: (exponent bits, fraction bits with the hidden one, bias, longwords)
FMT = {
    0: (8, 24, 128, 1),     # F
    1: (8, 56, 128, 2),     # D
    2: (11, 53, 1024, 2),   # G
    3: (15, 113, 16384, 4), # H
}
FMT_NAME = 'FDGH'


class RsvdOp(Exception):
    pass


def words_to_bits(words, fmt):
    """The longwords (memory order) as (sign, biased exponent, fraction
    without the hidden bit, as an integer)."""
    nexp, prec, bias, nw = FMT[fmt]
    l0 = words[0]
    s = (l0 >> 15) & 1
    E = (l0 >> (15 - nexp)) & ((1 << nexp) - 1)
    # the fraction: the bits below the exponent in word 0, then each
    # following 16-bit word in memory order
    wds = []
    for w in words[:nw]:
        wds.append(w & 0xFFFF)
        wds.append((w >> 16) & 0xFFFF)
    nfirst = 15 - nexp
    frac = wds[0] & ((1 << nfirst) - 1)
    for w16 in wds[1:]:
        frac = (frac << 16) | w16
    return s, E, frac


def bits_to_words(s, E, frac, fmt):
    nexp, prec, bias, nw = FMT[fmt]
    nfirst = 15 - nexp
    nbits = nfirst + 16 * (2 * nw - 1)     # = prec - 1
    assert nbits == prec - 1
    wds = []
    rest = frac
    for i in range(2 * nw - 1):
        wds.insert(0, rest & 0xFFFF)
        rest >>= 16
    w0 = (s << 15) | (E << nfirst) | rest
    wds.insert(0, w0)
    return [wds[2 * i] | (wds[2 * i + 1] << 16) for i in range(nw)]


def value(words, fmt):
    """Exact value; RsvdOp for a reserved operand."""
    nexp, prec, bias, nw = FMT[fmt]
    s, E, frac = words_to_bits(words, fmt)
    if E == 0:
        if s:
            raise RsvdOp()
        return Fraction(0)
    m = (1 << (prec - 1)) | frac
    v = Fraction(m, 1 << prec) * Fraction(2) ** (E - bias)
    return -v if s else v


def literal_value(lit):
    """A short literal as a floating operand: 0.1fff * 2**exp."""
    e = (lit >> 3) & 7
    f = lit & 7
    return Fraction(8 + f, 16) * Fraction(2) ** e


def normalize(x):
    """|x| = m * 2**e with 1/2 <= m < 1 (x not 0)."""
    a = abs(x)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    # adjust so that 1/2 <= a / 2**e < 1
    while a >= Fraction(2) ** e:
        e += 1
    while a < Fraction(2) ** (e - 1):
        e -= 1
    return a / Fraction(2) ** e, e


class Result:
    def __init__(self):
        self.words = None       # packed, or None
        self.ovf = self.unf = self.dvz = self.rsv = self.iov = False
        self.zero = False
        self.neg = False


def round_pack(x, fmt, fu):
    """Round x to the format: (words, ovf, unf). With FU clear, underflow
    gives 0 and no flag."""
    nexp, prec, bias, nw = FMT[fmt]
    r = Result()
    if x == 0:
        r.words = [0] * nw
        r.zero = True
        return r
    m, e = normalize(x)
    t = m * (1 << (prec + 1))           # prec bits and the rounding bit
    ti = t.numerator // t.denominator   # floor
    mant = (ti >> 1) + (ti & 1)
    if mant == 1 << prec:
        mant >>= 1
        e += 1
    E = e + bias
    if E > (1 << nexp) - 1:
        r.ovf = True
        return r
    if E < 1:
        if fu:
            r.unf = True
            return r
        r.words = [0] * nw
        r.zero = True
        return r
    r.words = bits_to_words(1 if x < 0 else 0, E, mant & ((1 << (prec - 1)) - 1), fmt)
    r.neg = x < 0
    return r


def chop(v, top_exp, nbits):
    """|v| chopped to the bits from 2**(top_exp - 1) down to
    2**(top_exp - nbits) (the sign kept)."""
    a = abs(v)
    q = a / Fraction(2) ** (top_exp - nbits)
    c = Fraction(q.numerator // q.denominator) * Fraction(2) ** (top_exp - nbits)
    return -c if v < 0 else c


def frac128(words, fmt):
    """(sign, true exponent, 128-bit integer fraction, zero) as the unit
    holds them."""
    nexp, prec, bias, nw = FMT[fmt]
    s, E, frac = words_to_bits(words, fmt)
    if E == 0:
        if s:
            raise RsvdOp()
        return 0, 0, 0, True
    m = ((1 << (prec - 1)) | frac) << (128 - prec)
    return s, E - bias, m, False


# ---------------------------------------------------------------- operations

def op_add(a, b, fmt, fu, sub=False):
    va, vb = value(a, fmt), value(b, fmt)
    return round_pack(va - vb if sub else va + vb, fmt, fu)


def op_mul(a, b, fmt, fu):
    return round_pack(value(a, fmt) * value(b, fmt), fmt, fu)


def op_div(a, b, fmt, fu):
    """a / b"""
    va, vb = value(a, fmt), value(b, fmt)
    if vb == 0:
        r = Result()
        r.dvz = True
        return r
    return round_pack(va / vb, fmt, fu)


def op_cmp(a, b, fmt):
    va, vb = value(a, fmt), value(b, fmt)
    return va < vb, va == vb


def op_cvtif(i, fmt, fu):
    if i & 0x80000000:
        i -= 1 << 32
    return round_pack(Fraction(i), fmt, fu)


def op_cvtfi(a, fmt, isz, rnd):
    """(low-order 32 bits, integer overflow)"""
    v = value(a, fmt)
    m = abs(v)
    n = m.numerator // m.denominator
    if rnd and m - n >= Fraction(1, 2):
        n += 1
    lim = {0: 7, 1: 15, 2: 31}[isz]
    iov = n > ((1 << lim) if v < 0 else (1 << lim) - 1)
    res = (-n if v < 0 else n) & 0xFFFFFFFF
    return res, iov


def op_rnd(a, fmt_src, fmt_dst, fu):
    return round_pack(value(a, fmt_src), fmt_dst, fu)


def ext_bits(ext, fmt):
    """EMOD: the multiplier extension as bits of the 128-bit fraction."""
    if fmt == 0:
        return (ext & 0xFF) << 96
    if fmt == 1:
        return (ext & 0xFF) << 64
    if fmt == 2:
        return ((ext >> 5) & 0x7FF) << 64
    return (ext >> 1) & 0x7FFF


def op_emod(a, ext, b, fmt, fu):
    """(fraction Result, integer, integer overflow)"""
    sa, ea, fa, za = frac128(a, fmt)
    sb, eb, fb, zb = frac128(b, fmt)
    if za or zb:
        r = round_pack(Fraction(0), fmt, fu)
        return r, 0, False
    wt = {0: 32, 1: 64, 2: 64, 3: 128}[fmt]
    p = (fa | ext_bits(ext, fmt)) * fb               # 256 bits
    p = (p >> (256 - wt)) << (256 - wt)              # chopped
    v = Fraction(p, 1 << 256) * Fraction(2) ** (ea + eb)
    if sa ^ sb:
        v = -v
    n = abs(v).numerator // abs(v).denominator       # integer part
    fpart = abs(v) - n
    if v < 0:
        fpart = -fpart
    iov = n > ((1 << 31) if v < 0 else (1 << 31) - 1)
    ires = (-n if v < 0 else n) & 0xFFFFFFFF
    r = round_pack(fpart, fmt, fu)
    if r.unf:
        return r, ires, iov
    return r, ires, iov


def op_poly_step(r_words, arg, coef, fmt, fu):
    """R * arg + coef with POLY's chopping (see fpunit.v)."""
    wp = {0: 31, 1: 63, 2: 63, 3: 127}[fmt]
    sr, er, fr, zr = frac128(r_words, fmt)
    sa, ea, fa, za = frac128(arg, fmt)
    vc = value(coef, fmt)
    if zr or za:
        return round_pack(vc, fmt, fu)
    p = fr * fa
    p = (p >> (256 - wp)) << (256 - wp)
    vp = Fraction(p, 1 << 256) * Fraction(2) ** (er + ea)
    if sr ^ sa:
        vp = -vp
    if vc == 0:
        return round_pack(vp, fmt, fu)
    # the sum, chopped below the larger operand's leading bit (one higher
    # after a carry)
    big = vp if abs(vp) >= abs(vc) else vc
    _, etop = normalize(big)
    s = vp + vc
    if s == 0:
        return round_pack(Fraction(0), fmt, fu)
    if abs(s) >= Fraction(2) ** etop:
        etop += 1
    return round_pack(chop(s, etop, wp), fmt, fu)


# ------------------------------------------------------------ test vectors

def rand_words(fmt, rng, special=0.15):
    nexp, prec, bias, nw = FMT[fmt]
    r = rng.random()
    s = rng.getrandbits(1)
    frac = rng.getrandbits(prec - 1)
    emaxb = (1 << nexp) - 1
    if r < special:
        kind = rng.randrange(7)
        if kind == 6:
            return bits_to_words(1, 0, frac, fmt)       # reserved operand
        if kind == 0:
            return [0] * nw                         # true zero
        if kind == 1:                               # dirty zero
            return bits_to_words(0, 0, frac, fmt)
        if kind == 2:
            return bits_to_words(s, emaxb, frac, fmt)   # largest
        if kind == 3:
            return bits_to_words(s, 1, frac, fmt)       # smallest
        if kind == 4:
            return bits_to_words(s, rng.randrange(1, emaxb + 1),
                                 (1 << (prec - 1)) - 1, fmt)    # all ones
        return bits_to_words(s, rng.randrange(1, emaxb + 1), 0, fmt)
    if r < 0.5:
        E = bias + rng.randrange(-8, 9)             # near 1
    else:
        E = rng.randrange(1, emaxb + 1)
    if rng.random() < 0.2:
        # sparse fractions: rounding ties and carries
        frac = 0
        for _ in range(rng.randrange(1, 4)):
            frac |= 1 << rng.randrange(prec - 1)
        if rng.random() < 0.5:
            frac = ((1 << (prec - 1)) - 1) ^ frac
    return bits_to_words(s, E, frac, fmt)


def close_pair(a, fmt, rng):
    """b near a: cancellation in subtraction."""
    nexp, prec, bias, nw = FMT[fmt]
    s, E, frac = words_to_bits(a, fmt)
    if E == 0:
        return a
    d = rng.randrange(0, 3)
    E2 = max(1, min((1 << nexp) - 1, E - d))
    frac2 = frac ^ rng.getrandbits(rng.randrange(1, prec))
    return bits_to_words(s ^ rng.getrandbits(1), E2, frac2 & ((1 << (prec - 1)) - 1), fmt)


def fmt_words(w):
    return ' '.join('%08X' % x for x in (list(w) + [0, 0, 0, 0])[:4])


OPS = ['ADD', 'SUB', 'MUL', 'DIV', 'CMP', 'CVTIF', 'CVTFI', 'RND',
       'EMOD', 'POLY', 'MOV', 'MNEG', 'TST']


def vector(rng, op, fmt):
    """One test: (op, fmt, a, b, ir, aux, expected) as a line."""
    fu = rng.getrandbits(1)
    a = rand_words(fmt, rng)
    b = rand_words(fmt, rng)
    if op in ('ADD', 'SUB') and rng.random() < 0.4:
        b = close_pair(a, fmt, rng)
    if op == 'CMP' and rng.random() < 0.3:
        b = list(a)
        if rng.random() < 0.5:
            b[0] ^= 0x8000
    ir = rng.getrandbits(32)
    aux = 0
    exp = {'rsv': 0, 'ovf': 0, 'unf': 0, 'dvz': 0, 'iov': 0, 'n': None,
           'z': None, 'r': None, 'ir': None}
    try:
        if op in ('ADD', 'SUB'):
            r = op_add(a, b, fmt, fu, op == 'SUB')
        elif op == 'MUL':
            r = op_mul(a, b, fmt, fu)
        elif op == 'DIV':
            r = op_div(a, b, fmt, fu)
        elif op == 'CMP':
            lt, eq = op_cmp(a, b, fmt)
            r = None
            exp['n'], exp['z'] = int(lt), int(eq)
        elif op == 'CVTIF':
            if rng.random() < 0.3:
                ir = rng.choice([0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF,
                                 0x00FFFFFF, 0x01000001, 0xFF000001])
            r = op_cvtif(ir, fmt, fu)
        elif op == 'CVTFI':
            isz = rng.randrange(3)
            rnd = rng.getrandbits(1)
            aux = isz | (rnd << 2)
            if rng.random() < 0.6:
                # values near the integer range
                nexp, prec, bias, nw = FMT[fmt]
                s, E, frac = words_to_bits(a, fmt)
                a = bits_to_words(s, bias + rng.randrange(-2, 36), frac, fmt)
            v, iov = op_cvtfi(a, fmt, isz, rnd)
            r = None
            exp['ir'], exp['iov'] = v, int(iov)
        elif op == 'RND':
            dst = rng.randrange(4)
            aux = dst
            r = op_rnd(a, fmt, dst, fu)
        elif op == 'EMOD':
            if rng.random() < 0.5:
                nexp, prec, bias, nw = FMT[fmt]
                s, E, frac = words_to_bits(a, fmt)
                if E:
                    a = bits_to_words(s, bias + rng.randrange(-4, 40), frac, fmt)
                s, E, frac = words_to_bits(b, fmt)
                if E:
                    b = bits_to_words(s, bias + rng.randrange(-4, 8), frac, fmt)
            r, iv, iov = op_emod(a, ir, b, fmt, fu)
            exp['ir'], exp['iov'] = iv, int(iov)
            if r.unf or r.ovf:
                exp['ir'] = None
        elif op == 'POLY':
            # R (from 'b' loaded and moved to R), arg a, coef c
            c = rand_words(fmt, rng)
            if rng.random() < 0.4:
                nexp, prec, bias, nw = FMT[fmt]
                for nm in ('a', 'b', 'c'):
                    w = {'a': a, 'b': b, 'c': c}[nm]
                    s, E, frac = words_to_bits(w, fmt)
                    if E:
                        w = bits_to_words(s, bias + rng.randrange(-3, 4), frac, fmt)
                    if nm == 'a':
                        a = w
                    elif nm == 'b':
                        b = w
                    else:
                        c = w
            aux = c
            value(b, fmt)       # R comes from b: reserved -> the MOV faults
            r = op_poly_step(b, a, c, fmt, fu)
        elif op in ('MOV', 'MNEG', 'TST'):
            v = value(a, fmt)
            if op == 'MNEG':
                v = -v
            if op == 'TST':
                r = None
                exp['n'], exp['z'] = int(v < 0), int(v == 0)
            else:
                r = round_pack(v, fmt, fu)
    except RsvdOp:
        exp['rsv'] = 1
        r = None
        exp['ir'] = None
    if r is not None:
        exp['ovf'], exp['unf'], exp['dvz'] = int(r.ovf), int(r.unf), int(r.dvz)
        if r.words is not None:
            exp['r'] = r.words
            exp['n'] = int(r.neg)
            exp['z'] = int(r.zero)
    if op == 'POLY':
        bstr = fmt_words(b) + ' ' + fmt_words(aux)
    else:
        bstr = fmt_words(b) + ' %08X 0 0 0' % aux
    rfmt = aux if op == 'RND' else fmt
    rstr = fmt_words(exp['r']) if exp['r'] is not None else '- - - -'
    return '%s %d %d %s %s %08X | %d %d %d %d %d %s %s %s %s %d' % (
        op, fmt, fu, fmt_words(a), bstr, ir,
        exp['rsv'], exp['ovf'], exp['unf'], exp['dvz'], exp['iov'],
        '-' if exp['n'] is None else exp['n'],
        '-' if exp['z'] is None else exp['z'],
        rstr, '-' if exp['ir'] is None else '%08X' % exp['ir'], rfmt)


def selftest():
    # 1.0 in F is 4080 0000; 0.5 is 4000; literal 0 is 0.5
    assert value([0x4080], 0) == 1
    assert value([0x4000], 0) == Fraction(1, 2)
    assert literal_value(0) == Fraction(1, 2)
    assert literal_value(63) == 120
    assert round_pack(Fraction(1), 0, 0).words == [0x4080]
    assert round_pack(Fraction(1), 1, 0).words == [0x4080, 0]
    assert round_pack(Fraction(1), 2, 0).words == [0x4010, 0]
    assert round_pack(Fraction(1), 3, 0).words == [0x4001, 0, 0, 0]
    assert round_pack(Fraction(-3, 2), 0, 0).words == [0xC0C0]
    # pi in D: 4149 0FDA A221 68C2 (16-bit words in memory order)
    w = round_pack(Fraction(314159265358979323846, 10 ** 20), 1, 0).words
    assert w == [0x0FDA4149, 0x68C2A221], ['%08X' % x for x in w]
    for fmt in range(4):
        rng = random.Random(fmt)
        for _ in range(200):
            a = rand_words(fmt, rng)
            try:
                v = value(a, fmt)
            except RsvdOp:
                continue
            r = round_pack(v, fmt, 0)
            assert r.words == a or v == 0, (fmt, a, r.words)


def main():
    selftest()
    out = sys.argv[1] if len(sys.argv) > 1 else 'vectors.txt'
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    rng = random.Random(seed)
    with open(out, 'w') as f:
        for i in range(count):
            op = OPS[i % len(OPS)]
            fmt = rng.randrange(4)
            f.write(vector(rng, op, fmt) + '\n')


if __name__ == '__main__':
    main()

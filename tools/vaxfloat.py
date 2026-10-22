#!/usr/bin/env python3
"""vaxfloat.py - VAX floating point constants for tools/vasm.py: a decimal
number as F_, D_, G_ or H_floating (VAX Architecture Reference Manual,
chapter 1, data types), rounded the way the VAX rounds (add one at the first
bit not kept, chop), and the short literal forms (chapter 2, literal mode).
It also turns the bits back into a number.

    python3 tools/vaxfloat.py F 3.14159       prints the longwords
    python3 tools/vaxfloat.py -d F 0FD04149   prints the value

The longwords are in memory order, as a VAX dump or software/fptest.bin
shows them (an F_floating number's two 16-bit words appear swapped:
0FD04149 is the word 4149, sign, exponent and the top of the fraction, then
the word 0FD0).
"""
import re
import sys
from fractions import Fraction

# format: (exponent bits, fraction bits with the hidden one, bias, bytes)
FORMATS = {
    'f': (8, 24, 128, 4),
    'd': (8, 56, 128, 8),
    'g': (11, 53, 1024, 8),
    'h': (15, 113, 16384, 16),
}

NUMBER = re.compile(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$')


def is_number(text):
    return NUMBER.match(text.replace(' ', '')) is not None


def parse(text):
    """The exact value of a decimal number."""
    t = text.replace(' ', '')
    m = re.match(r'^([+-]?)(\d*)\.?(\d*)(?:[eE]([+-]?\d+))?$', t)
    if not m:
        raise ValueError('bad number: %r' % text)
    sign, ip, fp, ex = m.groups()
    v = Fraction(int(ip or '0')) + (Fraction(int(fp), 10 ** len(fp)) if fp else 0)
    if ex:
        v *= Fraction(10) ** int(ex)
    return -v if sign == '-' else v


def encode(v, fmt):
    """The bytes of v in format fmt ('f', 'd', 'g', 'h'), memory order.
    Raises ValueError if it is out of range."""
    nexp, prec, bias, nbytes = FORMATS[fmt]
    if v == 0:
        return bytes(nbytes)
    a = abs(Fraction(v))
    e = a.numerator.bit_length() - a.denominator.bit_length()
    while a >= Fraction(2) ** e:
        e += 1
    while a < Fraction(2) ** (e - 1):
        e -= 1
    t = a / Fraction(2) ** e * (1 << (prec + 1))
    ti = t.numerator // t.denominator
    mant = (ti >> 1) + (ti & 1)                 # rounded
    if mant == 1 << prec:
        mant >>= 1
        e += 1
    E = e + bias
    if not 1 <= E < (1 << nexp):
        raise ValueError('%s out of range for %s_floating' % (v, fmt.upper()))
    bits = mant & ((1 << (prec - 1)) - 1)       # without the hidden bit
    nfirst = 15 - nexp
    nwords = nbytes // 2
    words = []
    rest = bits
    for _ in range(nwords - 1):
        words.insert(0, rest & 0xFFFF)
        rest >>= 16
    words.insert(0, ((1 if v < 0 else 0) << 15) | (E << nfirst) | rest)
    return b''.join(w.to_bytes(2, 'little') for w in words)


def literal(v):
    """The short literal (0-63) for v, or None: 0.1fff (binary) * 2**exp,
    exp and fff three bits each."""
    for lit in range(64):
        if Fraction(8 + (lit & 7), 16) * Fraction(2) ** (lit >> 3) == v:
            return lit
    return None


def decode(data, fmt):
    """The exact value of the bytes data (memory order) in format fmt, or
    None for a reserved operand (sign 1, exponent 0). Exponent 0 with sign
    0 is zero, whatever the fraction ("dirty" zero)."""
    nexp, prec, bias, nbytes = FORMATS[fmt]
    words = [int.from_bytes(data[i:i + 2], 'little') for i in range(0, nbytes, 2)]
    s = words[0] >> 15
    E = (words[0] >> (15 - nexp)) & ((1 << nexp) - 1)
    frac = words[0] & ((1 << (15 - nexp)) - 1)
    for w in words[1:]:
        frac = (frac << 16) | w
    if E == 0:
        return None if s else Fraction(0)
    v = Fraction((1 << (prec - 1)) | frac, 1 << prec) * Fraction(2) ** (E - bias)
    return -v if s else v


DIGITS = {'f': 9, 'd': 18, 'g': 17, 'h': 36}    # enough to tell values apart


def decimal(v, digits):
    """v rounded to that many significant digits, as text."""
    if v is None:
        return 'reserved operand'
    if v == 0:
        return '0'
    a = abs(Fraction(v))
    e = len(str(a.numerator)) - len(str(a.denominator))
    while a >= Fraction(10) ** (e + 1):
        e += 1
    while a < Fraction(10) ** e:
        e -= 1
    m = a / Fraction(10) ** (e - digits + 1)
    n = (2 * m.numerator + m.denominator) // (2 * m.denominator)   # rounded
    if n >= 10 ** digits:
        n //= 10
        e += 1
    t = str(n).rstrip('0') or '0'
    return '%s%s%s%sE%+d' % ('-' if v < 0 else '', t[0], '.' if len(t) > 1 else '',
                             t[1:], e)


def longwords_to_bytes(texts):
    """'0FD04149' or '40490FDB 00000000': longwords in memory order."""
    return b''.join(int(t, 16).to_bytes(4, 'little') for t in texts)


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) >= 3 and args[0] == '-d' and args[1].lower() in FORMATS:
        fmt = args[1].lower()
        try:
            data = longwords_to_bytes(args[2:])
        except ValueError:
            sys.exit('the longwords are hexadecimal: %s' % ' '.join(args[2:]))
        if len(data) != FORMATS[fmt][3]:
            sys.exit('%s_floating takes %d longword(s)' % (fmt.upper(),
                                                          FORMATS[fmt][3] // 4))
        print(decimal(decode(data, fmt), DIGITS[fmt]))
    elif len(args) == 2 and args[0].lower() in FORMATS:
        try:
            b = encode(parse(args[1]), args[0].lower())
        except ValueError as e:
            sys.exit(str(e))
        print(' '.join('%08X' % int.from_bytes(b[i:i + 4], 'little')
                       for i in range(0, len(b), 4)))
    else:
        print(__doc__)
        sys.exit(1)

#!/usr/bin/env python3
"""vasm.py - a small two-pass VAX assembler for the core's test programs.

Usage:  python3 tools/vasm.py prog.s -o prog.bin [-l prog.lst]

The output is a flat binary image that starts at the lowest address the source
places anything at (`.org`), ready for the OSD loader or a simulator's `load`.

Syntax, a subset of VAX MACRO:

    label:                      define a label (case sensitive)
    name = expr                 define a symbol
    ; comment                   comments start with ';'
    .org  expr                  set the location counter
    .byte / .word / .long / .quad  expr, ...
    .ascii "text"   .asciz "text"   (\\n \\r \\t \\0 \\\\ \\" escapes)
    .blkb n   .blkw n   .blkl n     reserve zeroed space
    .align n                    align to n bytes (n a power of two)
    .include "file"             insert another source (path relative to this one)

Operands (any general-mode operand may be followed by [Rx] for index mode):

    R0..R11 AP FP SP PC         register
    #expr                       short literal (0..63, integer read operands)
                                or immediate; S^#expr / I^#expr force either
    (Rn)  (Rn)+  -(Rn)  @(Rn)+  register deferred, autoincrement, ...
    @#expr                      absolute
    [B^|W^|L^]expr(Rn)          displacement; @ in front for deferred
    [B^|W^|L^]expr              PC relative (longword unless B^/W^ given);
                                @ in front for relative deferred
    expr                        for branch operands: the target address

Expressions are evaluated left to right, like MACRO: terms are decimal or
^X/0x hex, ^O octal, ^B binary, 'c' characters, symbols and '.', combined with
+ - * / & | ! (or) and unary - and ~; < > group.
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vax_optable import OPTABLE  # noqa: E402

REGS = {('R%d' % i): i for i in range(12)}
REGS.update({'AP': 12, 'FP': 13, 'SP': 14, 'PC': 15})
SIZES = {'b': 1, 'w': 2, 'l': 4, 'q': 8, 'o': 16, 'f': 4, 'd': 8, 'g': 8, 'h': 16}


class AsmError(Exception):
    pass


class Undefined(Exception):
    pass


def split_operands(s):
    """Split on commas that are not inside <> or quotes."""
    out, cur, depth, q = [], '', 0, False
    for c in s:
        if c == '"':
            q = not q
        if not q:
            if c == '<':
                depth += 1
            elif c == '>':
                depth -= 1
            elif c == ',' and depth == 0:
                out.append(cur.strip())
                cur = ''
                continue
        cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


class Assembler:
    def __init__(self):
        self.syms = {}
        self.choices = {}       # (line index, operand index) -> encoding choice
        self.pass_no = 1
        self.dot = 0

    # ------------------------------------------------------------ expressions
    def value(self, text):
        toks = re.findall(r"\^[Xx][0-9A-Fa-f]+|\^[Oo][0-7]+|\^[Bb][01]+|0[xX][0-9A-Fa-f]+|"
                          r"'.'|\d+|[A-Za-z_$.][A-Za-z0-9_$.]*|<<|>>|[-+*/&|!~<>]",
                          text.replace(' ', ''))
        if ''.join(toks) != text.replace(' ', ''):
            raise AsmError('bad expression: %r' % text)
        pos = [0]

        def term():
            t = toks[pos[0]]
            pos[0] += 1
            if t == '-':
                return -term()
            if t == '~':
                return ~term()
            if t == '<':
                v = expr()
                if pos[0] >= len(toks) or toks[pos[0]] != '>':
                    raise AsmError('missing > in %r' % text)
                pos[0] += 1
                return v
            if t.upper().startswith('^X') or t.lower().startswith('0x'):
                return int(t[2:], 16)
            if t.upper().startswith('^O'):
                return int(t[2:], 8)
            if t.upper().startswith('^B'):
                return int(t[2:], 2)
            if t.startswith("'"):
                return ord(t[1])
            if t.isdigit():
                return int(t)
            if t == '.':
                return self.dot
            if t in self.syms:
                return self.syms[t]
            raise Undefined(t)

        def expr():
            v = term()
            while pos[0] < len(toks) and toks[pos[0]] not in ('>',):
                op = toks[pos[0]]
                pos[0] += 1
                r = term()
                if op == '+': v = v + r
                elif op == '-': v = v - r
                elif op == '*': v = v * r
                elif op == '/': v = int(v / r)
                elif op == '&': v = v & r
                elif op in ('|', '!'): v = v | r
                elif op == '<<': v = v << r
                elif op == '>>': v = v >> r
                else:
                    raise AsmError('bad operator %r in %r' % (op, text))
            return v

        v = expr()
        if pos[0] != len(toks):
            raise AsmError('bad expression: %r' % text)
        return v

    def try_value(self, text):
        try:
            return self.value(text)
        except Undefined:
            if self.pass_no == 2:
                raise
            return None

    # ---------------------------------------------------------------- operands
    def operand(self, text, spec, key, pc_after_opcode_part):
        """Encode one operand. Returns bytes. pc_after_opcode_part is the
        address the operand starts at (needed for PC-relative modes)."""
        acc, dtype = spec[0], spec[1]
        size = SIZES[dtype]
        t = text.strip()
        if acc == 'b':
            target = self.try_value(t)
            n = 1 if dtype == 'b' else 2
            if target is None:
                return bytes(n)
            d = target - (pc_after_opcode_part + n)
            if n == 1 and not -128 <= d <= 127:
                raise AsmError('branch out of range: %s' % t)
            if n == 2 and not -32768 <= d <= 32767:
                raise AsmError('branch out of range: %s' % t)
            return struct.pack('<b' if n == 1 else '<h', d)

        # index mode
        m = re.match(r'^(.*)\[\s*(\w+)\s*\]$', t)
        if m:
            rx = REGS.get(m.group(2).upper())
            if rx is None:
                raise AsmError('bad index register: %s' % t)
            return bytes([0x40 | rx]) + self.operand(m.group(1), spec, key + ('x',),
                                                      pc_after_opcode_part + 1)
        up = t.upper()
        if up in REGS:
            return bytes([0x50 | REGS[up]])
        m = re.match(r'^\((\w+)\)$', t)
        if m and m.group(1).upper() in REGS:
            return bytes([0x60 | REGS[m.group(1).upper()]])
        m = re.match(r'^-\((\w+)\)$', t)
        if m and m.group(1).upper() in REGS:
            return bytes([0x70 | REGS[m.group(1).upper()]])
        m = re.match(r'^\((\w+)\)\+$', t)
        if m and m.group(1).upper() in REGS:
            return bytes([0x80 | REGS[m.group(1).upper()]])
        m = re.match(r'^@\((\w+)\)\+$', t)
        if m and m.group(1).upper() in REGS:
            return bytes([0x90 | REGS[m.group(1).upper()]])
        if t.startswith('@#'):
            v = self.try_value(t[2:])
            return bytes([0x9F]) + struct.pack('<I', (v or 0) & 0xFFFFFFFF)
        m = re.match(r'^([SI])\^#(.*)$', t, re.I)
        if t.startswith('#') or m:
            force = m.group(1).upper() if m else None
            ex = m.group(2) if m else t[1:]
            v = self.try_value(ex)
            ch = self.choices.get(key)
            if ch is None:
                lit_ok = acc == 'r' and dtype in 'bwlq'
                if force == 'S' or (force is None and lit_ok and v is not None and 0 <= v <= 63):
                    ch = 'S'
                else:
                    ch = 'I'
                self.choices[key] = ch
            if ch == 'S':
                if v is not None and not 0 <= v <= 63:
                    raise AsmError('short literal out of range: %s' % t)
                return bytes([(v or 0) & 0x3F])
            v = v or 0
            data = (v & ((1 << (8 * size)) - 1)).to_bytes(size, 'little')
            return bytes([0x8F]) + data
        deferred = t.startswith('@')
        if deferred:
            t = t[1:]
        m = re.match(r'^(?:([BWL])\^)?(.*?)(?:\((\w+)\))?$', t, re.I)
        forced, ex, reg = m.group(1), m.group(2), m.group(3)
        if reg is not None and reg.upper() not in REGS:
            raise AsmError('bad register: %s' % text)
        rn = REGS[reg.upper()] if reg else 15
        v = self.try_value(ex) if ex else 0
        ch = self.choices.get(key)
        if ch is None:
            if forced:
                ch = forced.upper()
            elif rn == 15 or v is None:
                ch = 'L'
            elif -128 <= v <= 127:
                ch = 'B'
            elif -32768 <= v <= 32767:
                ch = 'W'
            else:
                ch = 'L'
            self.choices[key] = ch
        n = {'B': 1, 'W': 2, 'L': 4}[ch]
        mode = {'B': 0xA, 'W': 0xC, 'L': 0xE}[ch] + (1 if deferred else 0)
        v = v or 0
        if rn == 15:
            d = v - (pc_after_opcode_part + 1 + n)
        else:
            d = v
        lim = 1 << (8 * n - 1)
        if not -lim <= d < lim and not (n == 4):
            raise AsmError('displacement out of range: %s' % text)
        return bytes([(mode << 4) | rn]) + (d & ((1 << (8 * n)) - 1)).to_bytes(n, 'little')

    # ------------------------------------------------------------------- lines
    def assemble(self, lines):
        image = {}
        for self.pass_no in (1, 2):
            self.dot = 0
            for idx, (lineno, raw) in enumerate(lines):
                line = raw.split(';', 1)[0].strip()
                try:
                    self.line(idx, line, image)
                except (AsmError, Undefined) as e:
                    raise AsmError('line %d: %s\n    %s' % (lineno, e, raw.rstrip()))
        return image

    def emit(self, image, data):
        if self.pass_no == 2:
            for i, b in enumerate(data):
                image[self.dot + i] = b
        self.dot += len(data)

    def line(self, idx, line, image):
        while True:
            m = re.match(r'^([A-Za-z_$.][A-Za-z0-9_$.]*):\s*(.*)$', line)
            if not m:
                break
            name = m.group(1)
            if self.pass_no == 1 and name in self.syms:
                raise AsmError('label defined twice: %s' % name)
            self.syms[name] = self.dot
            line = m.group(2)
        if not line:
            return
        m = re.match(r'^([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.*)$', line)
        if m:
            v = self.try_value(m.group(2))
            if v is not None:
                self.syms[m.group(1)] = v
            return
        parts = line.split(None, 1)
        op = parts[0]
        rest = parts[1] if len(parts) > 1 else ''
        if op.startswith('.'):
            return self.directive(op.lower(), rest, image)
        mn = op.upper()
        if mn not in OPTABLE:
            raise AsmError('unknown instruction %s' % op)
        code, specs = OPTABLE[mn]
        ops = split_operands(rest)
        if len(ops) != len(specs):
            raise AsmError('%s takes %d operands, got %d' % (mn, len(specs), len(ops)))
        out = struct.pack('<H', code) if code > 0xFF else bytes([code])
        for i, (o, s) in enumerate(zip(ops, specs)):
            out += self.operand(o, s, (idx, i), self.dot + len(out))
        self.emit(image, out)

    def directive(self, d, rest, image):
        if d == '.org':
            self.dot = self.value(rest)
        elif d in ('.byte', '.word', '.long', '.quad'):
            n = {'.byte': 1, '.word': 2, '.long': 4, '.quad': 8}[d]
            for e in split_operands(rest):
                v = self.try_value(e) or 0
                self.emit(image, (v & ((1 << (8 * n)) - 1)).to_bytes(n, 'little'))
        elif d in ('.ascii', '.asciz'):
            m = re.match(r'^"(.*)"$', rest.strip())
            if not m:
                raise AsmError('bad string')
            s = m.group(1).replace('\\n', '\n').replace('\\r', '\r').replace('\\t', '\t') \
                .replace('\\0', '\0').replace('\\"', '"').replace('\\\\', '\\')
            data = s.encode('latin-1') + (b'\0' if d == '.asciz' else b'')
            self.emit(image, data)
        elif d in ('.blkb', '.blkw', '.blkl'):
            n = {'.blkb': 1, '.blkw': 2, '.blkl': 4}[d] * self.value(rest)
            self.emit(image, bytes(n))
        elif d == '.align':
            a = self.value(rest)
            pad = (-self.dot) % a
            self.emit(image, bytes(pad))
        elif d in ('.globl', '.title', '.ident', '.end'):
            pass
        else:
            raise AsmError('unknown directive %s' % d)


def read_source(path, depth=0):
    """The source lines, with .include "file" lines replaced by the file."""
    if depth > 8:
        raise SystemExit('%s: .include nested too deeply' % path)
    out = []
    for line in open(path).read().split('\n'):
        m = re.match(r'\s*\.include\s+"([^"]+)"', line, re.I)
        if m:
            inc = os.path.join(os.path.dirname(path), m.group(1))
            out.extend(read_source(inc, depth + 1))
        else:
            out.append(line)
    return out


def main():
    args = sys.argv[1:]
    if not args or '-o' not in args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    out = args[args.index('-o') + 1]
    lst = args[args.index('-l') + 1] if '-l' in args else None
    lines = list(enumerate(read_source(src), 1))
    a = Assembler()
    try:
        image = a.assemble(lines)
    except AsmError as e:
        print('%s: %s' % (src, e), file=sys.stderr)
        sys.exit(1)
    if not image:
        sys.exit('%s: nothing assembled' % src)
    lo, hi = min(image), max(image)
    data = bytes(image.get(i, 0) for i in range(lo, hi + 1))
    open(out, 'wb').write(data)
    if lst:
        with open(lst, 'w') as f:
            f.write('origin %08X, %d bytes\n' % (lo, len(data)))
            for name in sorted(a.syms, key=lambda k: a.syms[k]):
                f.write('%08X  %s\n' % (a.syms[name] & 0xFFFFFFFF, name))
    print('%s: %d bytes at %08X' % (out, len(data), lo))


if __name__ == '__main__':
    main()

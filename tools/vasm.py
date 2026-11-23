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
    .byte / .word / .long / .quad / .octa  expr, ...
    .f_floating (.float) / .d_floating (.double) / .g_floating / .h_floating
                                decimal numbers, e.g. 3.25, -1.5E-10
    .ascii "text"   .asciz "text"   (\\n \\r \\t \\0 \\\\ \\" escapes)
    .blkb n   .blkw n   .blkl n     reserve zeroed space
    .align n                    align to n bytes (n a power of two)
    .include "file"             insert another source (path relative to this one)

Operands (any general-mode operand may be followed by [Rx] for index mode):

    R0..R11 AP FP SP PC         register
    #expr                       short literal (0..63, integer read operands)
                                or immediate; S^#expr / I^#expr force either;
                                for a floating operand a decimal number is a
                                floating constant (a short literal when it
                                is one of the 64 values, 0.5 to 120), any
                                other expression its bits
    (Rn)  (Rn)+  -(Rn)  @(Rn)+  register deferred, autoincrement, ...
    @#expr                      absolute
    [B^|W^|L^]expr(Rn)          displacement; @ in front for deferred
    [B^|W^|L^]expr              PC relative (longword unless B^/W^ given);
                                @ in front for relative deferred
    expr                        for branch operands: the target address

Expressions are evaluated left to right, like MACRO: terms are decimal or
^X/0x hex, ^O octal, ^B binary, 'c' characters, symbols and '.', combined with
+ - * / & | ! (or) and unary - and ~; < > group.

PDP-11 code, for the VAX's compatibility mode (VAX Architecture Reference
Manual, chapter 9): after .pdp11 the instructions are PDP-11 ones, in
MACRO-11 syntax, until .vax. Registers R0-R7, SP (R6), PC (R7); operands
Rn, (Rn) or @Rn, (Rn)+, @(Rn)+, -(Rn), @-(Rn), X(Rn), @X(Rn), #expr, @#expr,
expr and @expr (PC relative); MUL, DIV, ASH, ASHC take src,R, XOR and JSR
R,dst, SOB R,target, EMT/TRAP/MARK/SPL a number. Numbers are decimal, as
everywhere here (^O for octal). Any 16-bit opcode can also be put with .word.
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vax_optable import OPTABLE  # noqa: E402
import vaxfloat  # noqa: E402

REGS = {('R%d' % i): i for i in range(12)}
REGS.update({'AP': 12, 'FP': 13, 'SP': 14, 'PC': 15})
SIZES = {'b': 1, 'w': 2, 'l': 4, 'q': 8, 'o': 16, 'f': 4, 'd': 8, 'g': 8, 'h': 16}

# PDP-11 (compatibility mode), .pdp11
PDP_REGS = {('R%d' % i): i for i in range(8)}
PDP_REGS.update({'SP': 6, 'PC': 7})
PDP_ZERO = {'HALT': 0o0, 'WAIT': 0o1, 'RTI': 0o2, 'BPT': 0o3, 'IOT': 0o4,
            'RESET': 0o5, 'RTT': 0o6, 'MFPT': 0o7, 'NOP': 0o240, 'CLC': 0o241,
            'CLV': 0o242, 'CLZ': 0o244, 'CLN': 0o250, 'CCC': 0o257,
            'SEC': 0o261, 'SEV': 0o262, 'SEZ': 0o264, 'SEN': 0o270,
            'SCC': 0o277}
PDP_SINGLE = {'JMP': 0o000100, 'SWAB': 0o000300, 'CLR': 0o005000,
              'COM': 0o005100, 'INC': 0o005200, 'DEC': 0o005300,
              'NEG': 0o005400, 'ADC': 0o005500, 'SBC': 0o005600,
              'TST': 0o005700, 'ROR': 0o006000, 'ROL': 0o006100,
              'ASR': 0o006200, 'ASL': 0o006300, 'MFPI': 0o006500,
              'MTPI': 0o006600, 'SXT': 0o006700, 'CSM': 0o007000,
              'CLRB': 0o105000, 'COMB': 0o105100, 'INCB': 0o105200,
              'DECB': 0o105300, 'NEGB': 0o105400, 'ADCB': 0o105500,
              'SBCB': 0o105600, 'TSTB': 0o105700, 'RORB': 0o106000,
              'ROLB': 0o106100, 'ASRB': 0o106200, 'ASLB': 0o106300,
              'MTPS': 0o106400, 'MFPD': 0o106500, 'MTPD': 0o106600,
              'MFPS': 0o106700}
PDP_DOUBLE = {'MOV': 0o010000, 'CMP': 0o020000, 'BIT': 0o030000,
              'BIC': 0o040000, 'BIS': 0o050000, 'ADD': 0o060000,
              'MOVB': 0o110000, 'CMPB': 0o120000, 'BITB': 0o130000,
              'BICB': 0o140000, 'BISB': 0o150000, 'SUB': 0o160000}
PDP_BRANCH = {'BR': 0o000400, 'BNE': 0o001000, 'BEQ': 0o001400,
              'BGE': 0o002000, 'BLT': 0o002400, 'BGT': 0o003000,
              'BLE': 0o003400, 'BPL': 0o100000, 'BMI': 0o100400,
              'BHI': 0o101000, 'BLOS': 0o101400, 'BVC': 0o102000,
              'BVS': 0o102400, 'BCC': 0o103000, 'BHIS': 0o103000,
              'BCS': 0o103400, 'BLO': 0o103400}
PDP_SRCREG = {'MUL': 0o070000, 'DIV': 0o071000, 'ASH': 0o072000,
              'ASHC': 0o073000}
PDP_NUMBER = {'EMT': (0o104000, 255), 'TRAP': (0o104400, 255),
              'MARK': (0o006400, 63), 'SPL': (0o000230, 7)}


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
        self.pdp = False        # .pdp11: PDP-11 instructions

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
        if (t.startswith('#') or m) and dtype in 'fdgh' and \
                vaxfloat.is_number(m.group(2) if m else t[1:]):
            # a floating constant: a short literal if it is one of the 64
            # values, else immediate (S^# forces the literal)
            force = m.group(1).upper() if m else None
            fv = vaxfloat.parse(m.group(2) if m else t[1:])
            lit = vaxfloat.literal(fv)
            if force == 'S' or (force is None and acc == 'r' and lit is not None):
                if lit is None:
                    raise AsmError('not a floating short literal: %s' % t)
                return bytes([lit])
            try:
                return bytes([0x8F]) + vaxfloat.encode(fv, dtype)
            except ValueError as e:
                raise AsmError(str(e))
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

    # ------------------------------------------------------- PDP-11 operands
    def pdp_reg(self, t):
        r = PDP_REGS.get(t.strip().upper())
        if r is None:
            raise AsmError('bad PDP-11 register: %s' % t)
        return r

    def pdp_operand(self, text, loc):
        """A PDP-11 operand: (the 6-bit specifier, [the word after the
        instruction, if any]). loc is the address that word would have."""
        t = text.strip()
        up = t.upper()
        if up in PDP_REGS:
            return PDP_REGS[up], []
        m = re.match(r'^(@?)\((\w+)\)(\+?)$', t)
        if m and m.group(2).upper() in PDP_REGS:
            r = PDP_REGS[m.group(2).upper()]
            if m.group(3):                      # (Rn)+, @(Rn)+
                return (0o30 if m.group(1) else 0o20) | r, []
            if m.group(1):                      # @(Rn): @X(Rn) with X = 0
                return 0o70 | r, [0]
            return 0o10 | r, []                 # (Rn)
        m = re.match(r'^(@?)-\((\w+)\)$', t)
        if m and m.group(2).upper() in PDP_REGS:
            return (0o50 if m.group(1) else 0o40) | PDP_REGS[m.group(2).upper()], []
        if up.startswith('@') and up[1:] in PDP_REGS:   # @Rn = (Rn)
            return 0o10 | PDP_REGS[up[1:]], []
        if t.startswith('@#'):                  # absolute: @(PC)+
            return 0o37, [(self.try_value(t[2:]) or 0) & 0xFFFF]
        if t.startswith('#'):                   # immediate: (PC)+
            return 0o27, [(self.try_value(t[1:]) or 0) & 0xFFFF]
        deferred = t.startswith('@')
        if deferred:
            t = t[1:]
        m = re.match(r'^(.*?)\((\w+)\)$', t)
        if m and m.group(2).upper() in PDP_REGS:    # X(Rn), @X(Rn)
            x = self.try_value(m.group(1)) or 0
            return (0o70 if deferred else 0o60) | PDP_REGS[m.group(2).upper()], \
                [x & 0xFFFF]
        v = self.try_value(t)                   # relative: X(PC), @X(PC)
        x = 0 if v is None else v - (loc + 2)
        return (0o77 if deferred else 0o67), [x & 0xFFFF]

    def pdp_line(self, mn, rest, image):
        ops = split_operands(rest) if rest.strip() else []

        def need(n):
            if len(ops) != n:
                raise AsmError('%s takes %d operands, got %d' % (mn, n, len(ops)))

        def target(t):
            v = self.try_value(t)
            return v
        words = []
        if mn in PDP_ZERO:
            need(0)
            words = [PDP_ZERO[mn]]
        elif mn in PDP_SINGLE:
            need(1)
            spec, ext = self.pdp_operand(ops[0], self.dot + 2)
            words = [PDP_SINGLE[mn] | spec] + ext
        elif mn in PDP_DOUBLE:
            need(2)
            s1, e1 = self.pdp_operand(ops[0], self.dot + 2)
            s2, e2 = self.pdp_operand(ops[1], self.dot + 2 + 2 * len(e1))
            words = [PDP_DOUBLE[mn] | (s1 << 6) | s2] + e1 + e2
        elif mn in PDP_BRANCH:
            need(1)
            v = target(ops[0])
            d = 0 if v is None else v - (self.dot + 2)
            if d & 1 or not -256 <= d <= 254:
                raise AsmError('branch out of range: %s' % ops[0])
            words = [PDP_BRANCH[mn] | ((d >> 1) & 0o377)]
        elif mn == 'SOB':
            need(2)
            v = target(ops[1])
            d = 0 if v is None else (self.dot + 2) - v
            if d & 1 or not 0 <= d <= 126:
                raise AsmError('SOB out of range: %s' % ops[1])
            words = [0o077000 | (self.pdp_reg(ops[0]) << 6) | (d >> 1)]
        elif mn in PDP_SRCREG:                  # MUL src,R
            need(2)
            spec, ext = self.pdp_operand(ops[0], self.dot + 2)
            words = [PDP_SRCREG[mn] | (self.pdp_reg(ops[1]) << 6) | spec] + ext
        elif mn in ('XOR', 'JSR'):              # XOR R,dst  JSR R,dst
            need(2)
            spec, ext = self.pdp_operand(ops[1], self.dot + 2)
            words = [(0o074000 if mn == 'XOR' else 0o004000) |
                     (self.pdp_reg(ops[0]) << 6) | spec] + ext
        elif mn == 'RTS':
            need(1)
            words = [0o000200 | self.pdp_reg(ops[0])]
        elif mn in PDP_NUMBER:
            code, top = PDP_NUMBER[mn]
            n = self.try_value(ops[0]) if ops else 0
            n = n or 0
            if not 0 <= n <= top:
                raise AsmError('%s number out of range: %s' % (mn, ops[0]))
            words = [code | n]
        else:
            raise AsmError('unknown PDP-11 instruction %s' % mn)
        self.emit(image, b''.join(struct.pack('<H', w & 0xFFFF) for w in words))

    # ------------------------------------------------------------------- lines
    def assemble(self, lines):
        image = {}
        for self.pass_no in (1, 2):
            self.dot = 0
            self.pdp = False
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
        if self.pdp:
            return self.pdp_line(mn, rest, image)
        if mn not in OPTABLE:
            raise AsmError('unknown instruction %s' % op)
        code, specs = OPTABLE[mn]
        ops = split_operands(rest)
        if len(ops) != len(specs):
            raise AsmError('%s takes %d operands, got %d' % (mn, len(specs), len(ops)))
        # a two-byte opcode is FD (or FF) first, as the table writes it
        out = bytes([code >> 8, code & 0xFF]) if code > 0xFF else bytes([code])
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
        elif d in ('.f_floating', '.float', '.d_floating', '.double',
                   '.g_floating', '.h_floating'):
            fmt = {'.f_floating': 'f', '.float': 'f', '.d_floating': 'd',
                   '.double': 'd', '.g_floating': 'g', '.h_floating': 'h'}[d]
            for e in split_operands(rest):
                try:
                    self.emit(image, vaxfloat.encode(vaxfloat.parse(e), fmt))
                except ValueError as err:
                    raise AsmError(str(err))
        elif d == '.octa':
            for e in split_operands(rest):
                v = self.try_value(e) or 0
                self.emit(image, (v & ((1 << 128) - 1)).to_bytes(16, 'little'))
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
        elif d == '.pdp11':
            self.pdp = True
        elif d == '.vax':
            self.pdp = False
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

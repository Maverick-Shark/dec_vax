"""vax_optable.py - the VAX instructions for tools/vasm.py: mnemonic ->
(opcode, operand specifiers), from the VAX Architecture Reference Manual
(1987): appendix A, "Opcode Assignments", and the format of each
instruction in chapter 3. An operand specifier is the access type (r read,
m modify, w write, a address, v bit field base, b branch displacement) and
the data type (b w l q o, f d g h). A two-byte opcode is written FDxx, the
FD byte first (the manual writes the word, xxFD).
"""

OPTABLE = {}


def _op(code, name, *specs):
    assert name not in OPTABLE, name
    OPTABLE[name] = (code, list(specs))


def _alias(name, of, *specs):
    """Another name of an opcode (with its own operand data types)."""
    OPTABLE[name] = (OPTABLE[of][0], list(specs) or list(OPTABLE[of][1]))


# -------------------------------------------------- no operands, control
for code, name in ((0x00, 'HALT'), (0x01, 'NOP'), (0x02, 'REI'), (0x03, 'BPT'),
                   (0x04, 'RET'), (0x05, 'RSB'), (0x06, 'LDPCTX'),
                   (0x07, 'SVPCTX'), (0xFC, 'XFC')):
    _op(code, name)
for code, name in ((0x12, 'BNEQ'), (0x13, 'BEQL'), (0x14, 'BGTR'),
                   (0x15, 'BLEQ'), (0x18, 'BGEQ'), (0x19, 'BLSS'),
                   (0x1A, 'BGTRU'), (0x1B, 'BLEQU'), (0x1C, 'BVC'),
                   (0x1D, 'BVS'), (0x1E, 'BGEQU'), (0x1F, 'BLSSU'),
                   (0x10, 'BSBB'), (0x11, 'BRB')):
    _op(code, name, 'bb')
_alias('BNEQU', 'BNEQ')
_alias('BEQLU', 'BEQL')
_alias('BCC', 'BGEQU')
_alias('BCS', 'BLSSU')
_op(0x30, 'BSBW', 'bw')
_op(0x31, 'BRW', 'bw')
_op(0x16, 'JSB', 'ab')
_op(0x17, 'JMP', 'ab')
_op(0xFA, 'CALLG', 'ab', 'ab')
_op(0xFB, 'CALLS', 'rl', 'ab')

# ----------------------------------------------------- integer arithmetic
for t, base in (('B', 0x80), ('W', 0xA0), ('L', 0xC0)):
    x = t.lower()
    for i, n in enumerate(('ADD', 'SUB', 'MUL', 'DIV', 'BIS', 'BIC', 'XOR')):
        _op(base + 2 * i, n + t + '2', 'r' + x, 'm' + x)
        _op(base + 2 * i + 1, n + t + '3', 'r' + x, 'r' + x, 'w' + x)
    _op(base + 0x0E, 'MNEG' + t, 'r' + x, 'w' + x)
    _op(base + 0x0F, 'CASE' + t, 'r' + x, 'r' + x, 'r' + x)    # then the table
    _op(base + 0x10, 'MOV' + t, 'r' + x, 'w' + x)
    _op(base + 0x11, 'CMP' + t, 'r' + x, 'r' + x)
    _op(base + 0x12, 'MCOM' + t, 'r' + x, 'w' + x)
    _op(base + 0x13, 'BIT' + t, 'r' + x, 'r' + x)
    _op(base + 0x14, 'CLR' + t, 'w' + x)
    _op(base + 0x15, 'TST' + t, 'r' + x)
    _op(base + 0x16, 'INC' + t, 'm' + x)
    _op(base + 0x17, 'DEC' + t, 'm' + x)
_op(0x98, 'CVTBL', 'rb', 'wl')
_op(0x99, 'CVTBW', 'rb', 'ww')
_op(0x9A, 'MOVZBL', 'rb', 'wl')
_op(0x9B, 'MOVZBW', 'rb', 'ww')
_op(0x9C, 'ROTL', 'rb', 'rl', 'wl')
_op(0x9D, 'ACBB', 'rb', 'rb', 'mb', 'bw')
_op(0x9E, 'MOVAB', 'ab', 'wl')
_op(0x9F, 'PUSHAB', 'ab')
_op(0x32, 'CVTWL', 'rw', 'wl')
_op(0x33, 'CVTWB', 'rw', 'wb')
_op(0x3C, 'MOVZWL', 'rw', 'wl')
_op(0x3D, 'ACBW', 'rw', 'rw', 'mw', 'bw')
_op(0x3E, 'MOVAW', 'aw', 'wl')
_op(0x3F, 'PUSHAW', 'aw')
_op(0xB8, 'BISPSW', 'rw')
_op(0xB9, 'BICPSW', 'rw')
_op(0xBA, 'POPR', 'rw')
_op(0xBB, 'PUSHR', 'rw')
for code, name in ((0xBC, 'CHMK'), (0xBD, 'CHME'), (0xBE, 'CHMS'), (0xBF, 'CHMU')):
    _op(code, name, 'rw')
_op(0xD8, 'ADWC', 'rl', 'ml')
_op(0xD9, 'SBWC', 'rl', 'ml')
_op(0xDA, 'MTPR', 'rl', 'rl')
_op(0xDB, 'MFPR', 'rl', 'wl')
_op(0xDC, 'MOVPSL', 'wl')
_op(0xDD, 'PUSHL', 'rl')
_op(0xDE, 'MOVAL', 'al', 'wl')
_op(0xDF, 'PUSHAL', 'al')
_op(0xF1, 'ACBL', 'rl', 'rl', 'ml', 'bw')
_op(0xF2, 'AOBLSS', 'rl', 'ml', 'bb')
_op(0xF3, 'AOBLEQ', 'rl', 'ml', 'bb')
_op(0xF4, 'SOBGEQ', 'ml', 'bb')
_op(0xF5, 'SOBGTR', 'ml', 'bb')
_op(0xF6, 'CVTLB', 'rl', 'wb')
_op(0xF7, 'CVTLW', 'rl', 'ww')
_op(0x78, 'ASHL', 'rb', 'rl', 'wl')
_op(0x79, 'ASHQ', 'rb', 'rq', 'wq')
_op(0x7A, 'EMUL', 'rl', 'rl', 'rl', 'wq')
_op(0x7B, 'EDIV', 'rl', 'rq', 'wl', 'wl')
_op(0x7C, 'CLRQ', 'wq')
_op(0x7D, 'MOVQ', 'rq', 'wq')
_op(0x7E, 'MOVAQ', 'aq', 'wl')
_op(0x7F, 'PUSHAQ', 'aq')
_op(0x58, 'ADAWI', 'rw', 'mw')
_op(0x0A, 'INDEX', 'rl', 'rl', 'rl', 'rl', 'rl', 'wl')

# ------------------------------------------------------- bit fields
for i, n in enumerate(('BBS', 'BBC', 'BBSS', 'BBCS', 'BBSC', 'BBCC', 'BBSSI', 'BBCCI')):
    _op(0xE0 + i, n, 'rl', 'vb', 'bb')
_op(0xE8, 'BLBS', 'rl', 'bb')
_op(0xE9, 'BLBC', 'rl', 'bb')
_op(0xEA, 'FFS', 'rl', 'rb', 'vb', 'wl')
_op(0xEB, 'FFC', 'rl', 'rb', 'vb', 'wl')
_op(0xEC, 'CMPV', 'rl', 'rb', 'vb', 'rl')
_op(0xED, 'CMPZV', 'rl', 'rb', 'vb', 'rl')
_op(0xEE, 'EXTV', 'rl', 'rb', 'vb', 'wl')
_op(0xEF, 'EXTZV', 'rl', 'rb', 'vb', 'wl')
_op(0xF0, 'INSV', 'rl', 'rl', 'rb', 'vb')

# ------------------------------------------------- queues, probes, CRC
_op(0x0B, 'CRC', 'ab', 'rl', 'rw', 'ab')
_op(0x0C, 'PROBER', 'rb', 'rw', 'ab')
_op(0x0D, 'PROBEW', 'rb', 'rw', 'ab')
_op(0x0E, 'INSQUE', 'ab', 'ab')
_op(0x0F, 'REMQUE', 'ab', 'wl')
_op(0x5C, 'INSQHI', 'ab', 'aq')
_op(0x5D, 'INSQTI', 'ab', 'aq')
_op(0x5E, 'REMQHI', 'aq', 'wl')
_op(0x5F, 'REMQTI', 'aq', 'wl')

# ------------------------------------------------- character strings
_op(0x28, 'MOVC3', 'rw', 'ab', 'ab')
_op(0x29, 'CMPC3', 'rw', 'ab', 'ab')
_op(0x2A, 'SCANC', 'rw', 'ab', 'ab', 'rb')
_op(0x2B, 'SPANC', 'rw', 'ab', 'ab', 'rb')
_op(0x2C, 'MOVC5', 'rw', 'ab', 'rb', 'rw', 'ab')
_op(0x2D, 'CMPC5', 'rw', 'ab', 'rb', 'rw', 'ab')
_op(0x2E, 'MOVTC', 'rw', 'ab', 'rb', 'ab', 'rw', 'ab')
_op(0x2F, 'MOVTUC', 'rw', 'ab', 'rb', 'ab', 'rw', 'ab')
_op(0x39, 'MATCHC', 'rw', 'ab', 'rw', 'ab')
_op(0x3A, 'LOCC', 'rb', 'rw', 'ab')
_op(0x3B, 'SKPC', 'rb', 'rw', 'ab')

# ----------------------------------------------------- packed decimal
_op(0x08, 'CVTPS', 'rw', 'ab', 'rw', 'ab')
_op(0x09, 'CVTSP', 'rw', 'ab', 'rw', 'ab')
_op(0x20, 'ADDP4', 'rw', 'ab', 'rw', 'ab')
_op(0x21, 'ADDP6', 'rw', 'ab', 'rw', 'ab', 'rw', 'ab')
_op(0x22, 'SUBP4', 'rw', 'ab', 'rw', 'ab')
_op(0x23, 'SUBP6', 'rw', 'ab', 'rw', 'ab', 'rw', 'ab')
_op(0x24, 'CVTPT', 'rw', 'ab', 'ab', 'rw', 'ab')
_op(0x25, 'MULP', 'rw', 'ab', 'rw', 'ab', 'rw', 'ab')
_op(0x26, 'CVTTP', 'rw', 'ab', 'ab', 'rw', 'ab')
_op(0x27, 'DIVP', 'rw', 'ab', 'rw', 'ab', 'rw', 'ab')
_op(0x34, 'MOVP', 'rw', 'ab', 'ab')
_op(0x35, 'CMPP3', 'rw', 'ab', 'ab')
_op(0x36, 'CVTPL', 'rw', 'ab', 'wl')
_op(0x37, 'CMPP4', 'rw', 'ab', 'rw', 'ab')
_op(0x38, 'EDITPC', 'rw', 'ab', 'ab', 'ab')
_op(0xF8, 'ASHP', 'rb', 'rw', 'ab', 'rb', 'rw', 'ab')
_op(0xF9, 'CVTLP', 'rl', 'rw', 'ab')

# ------------------------------------------------------ floating point
# (F 40-56, D 60-76, G FD40-FD56, H FD60-FD76: the same layout)
for t, base in (('F', 0x40), ('D', 0x60), ('G', 0xFD40), ('H', 0xFD60)):
    x = t.lower()
    for i, n in enumerate(('ADD', 'SUB', 'MUL', 'DIV')):
        _op(base + 2 * i, n + t + '2', 'r' + x, 'm' + x)
        _op(base + 2 * i + 1, n + t + '3', 'r' + x, 'r' + x, 'w' + x)
    _op(base + 0x08, 'CVT' + t + 'B', 'r' + x, 'wb')
    _op(base + 0x09, 'CVT' + t + 'W', 'r' + x, 'ww')
    _op(base + 0x0A, 'CVT' + t + 'L', 'r' + x, 'wl')
    _op(base + 0x0B, 'CVTR' + t + 'L', 'r' + x, 'wl')
    _op(base + 0x0C, 'CVTB' + t, 'rb', 'w' + x)
    _op(base + 0x0D, 'CVTW' + t, 'rw', 'w' + x)
    _op(base + 0x0E, 'CVTL' + t, 'rl', 'w' + x)
    _op(base + 0x0F, 'ACB' + t, 'r' + x, 'r' + x, 'm' + x, 'bw')
    _op(base + 0x10, 'MOV' + t, 'r' + x, 'w' + x)
    _op(base + 0x11, 'CMP' + t, 'r' + x, 'r' + x)
    _op(base + 0x12, 'MNEG' + t, 'r' + x, 'w' + x)
    _op(base + 0x13, 'TST' + t, 'r' + x)
    _op(base + 0x14, 'EMOD' + t, 'r' + x, 'rb' if t in 'FD' else 'rw',
        'r' + x, 'wl', 'w' + x)
    _op(base + 0x15, 'POLY' + t, 'r' + x, 'rw', 'ab')
_op(0x56, 'CVTFD', 'rf', 'wd')
_op(0x76, 'CVTDF', 'rd', 'wf')
_op(0xFD56, 'CVTGH', 'rg', 'wh')
_op(0xFD76, 'CVTHG', 'rh', 'wg')
_op(0xFD32, 'CVTDH', 'rd', 'wh')
_op(0xFD33, 'CVTGF', 'rg', 'wf')
_op(0xFD98, 'CVTFH', 'rf', 'wh')
_op(0xFD99, 'CVTFG', 'rf', 'wg')
_op(0xFDF6, 'CVTHF', 'rh', 'wf')
_op(0xFDF7, 'CVTHD', 'rh', 'wd')

# ---------------------------------------------------------- octaword
_op(0xFD7C, 'CLRO', 'wo')
_op(0xFD7D, 'MOVO', 'ro', 'wo')
_op(0xFD7E, 'MOVAO', 'ao', 'wl')
_op(0xFD7F, 'PUSHAO', 'ao')

# the same opcodes under their floating names
_alias('CLRF', 'CLRL', 'wf')
_alias('CLRD', 'CLRQ', 'wd')
_alias('CLRG', 'CLRQ', 'wg')
_alias('CLRH', 'CLRO', 'wh')
_alias('MOVAF', 'MOVAL', 'af', 'wl')
_alias('MOVAD', 'MOVAQ', 'ad', 'wl')
_alias('MOVAG', 'MOVAQ', 'ag', 'wl')
_alias('MOVAH', 'MOVAO', 'ah', 'wl')
_alias('PUSHAF', 'PUSHAL', 'af')
_alias('PUSHAD', 'PUSHAQ', 'ad')
_alias('PUSHAG', 'PUSHAQ', 'ag')
_alias('PUSHAH', 'PUSHAO', 'ah')

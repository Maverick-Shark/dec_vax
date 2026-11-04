#!/usr/bin/env python3
"""mk_t47.py - the expected log of tests/mmu/t47_sbia.s, from the DEC
documents (EK-DB86X-TD-002, EK-8600S-MM-004 appendix K), written into the
test as ';@ rtl=' lines (python3 tests/mmu/gen/mk_t47.py tests/mmu/t47_sbia.s).
VIBASAV is the processor's: see VIBA."""
import re, sys

LOG = 0x18000
log = []

def put(*v):
    log.extend(v)

# VIBASAV - (instruction & ~3) for each machine check: the last longword of
# the instruction stream fetched before the failing reference, which is how
# far the instruction itself goes (an implementation detail; DEC defines
# VIBASAV only as the last I-buffer address the MBox acknowledged)
VIBA = {'f01': 0, 'f02': 0, 'f03': 4, 'f04': 4, 'f05': 0, 'f06': 4,
        'f07': 0, 'f08': 4, 'f09': 0, 'f10': 0, 'f11': 0, 'f12': 0,
        'f13': 8, 'f14': 0, 'f15': 0, 'f16': 0}

def mchk(name, va, pa, we=False, io=False, ifetch=False, code=0x1F,
         ehmsts=0x40000800, ehsr=0x00080020):
    ebcs = 0x0020C000 | (4 if we else 0) | (2 if (io and not we) else 0)
    mstat1 = (0xC0000000 if ifetch else 0x80000000) | \
             (0x34000000 if we else 0x38000000)
    mstat2 = 0x00180004 if io else ((code << 16) | 8)
    put(0x58, ehmsts, 0 if ifetch else va, ebcs, 0x081D0000,
        0 if ifetch else va, VIBA.get(name), 0, 0, 0, mstat1, mstat2,
        0, 3, pa & ~3, 0, 0, 0x041F0000, ehsr)

def main():
    # PAMM
    for loc, code in ((0x00000000, 0), (0x00312345, 0), (0x00400000, 1),
                      (0x01F00000, 7), (0x02000000, 0x1F), (0x1FF00000, 0x1F),
                      (0x20000000, 0x18), (0x21F00000, 0x18), (0x22000000, 0x1F),
                      (0x30000000, 0x1F), (0x3FF00000, 0x1F), (0x3FFFFFFF, 0x1F)):
        l = loc & 0x3FF00000
        put(l, l | code)
    put(0x03000002, 0x11223344, 0x55667788, 0x0300001F)
    mchk('f01', 0x03000010, 0x03000010)
    # SBIA registers after initialization
    put(0x02000010, 0xE0000000, 0x1C000000, 0, 0, 0, 0x0802000E, 0, 0, 0, 0, 0)
    put(0x3FF00010, 0x02000010, 0, 0xE0000000, 0x000F001E, 0, 0x00040000,
        0xFF80091F, 0xFFFF0000, 0)
    # address errors
    mchk('f02', 0x20080050, 0x20080050, io=True)
    put(0x1C980000, 0x08020014, 0)
    mchk('f03', 0x20080054, 0x20080054, io=True, we=True)
    put(0x1C990000, 0x1C000000)
    mchk('f04', 0x20080090, 0x20080090, io=True, we=True)
    put(0xDC980000, 0x08020024)
    mchk('f05', 0x20006000, 0x20006000, io=True)
    put(0x1C980000, 0x08001800)
    mchk('f06', 0x20080094, 0x20080094, io=True)
    put(0x50)
    # SBI timeouts
    mchk('f07', 0x2000A000, 0x2000A000, io=True)
    put(0x00001000, 0x08002800, 0x1C800000, 0, 0x08002800, 0x0802000E)
    mchk('f08', 0x2000C000, 0x2000C000, io=True, we=True)
    put(0x00001000, 0x08003000, 0xDC800000)
    mchk('f09', 0x20100000, 0x20100000, io=True)
    put(0x20100000, 0x08040000, 0x00000100)
    mchk('f10', 0x03000020, 0x03000020, io=True)
    put(0x00C00008)
    mchk('f11', 0x2001E000, 0x2001E000, io=True)
    put(0x00001000, 0x08007800)
    put(0x00010028, 0x00000020, 0, 0x1C000000)
    # non-existent memory
    mchk('f12', 0x02000000, 0x02000000)
    put(0x1C000000)
    mchk('f13', 0x30000004, 0x30000004, we=True)
    mchk('f14', 0x01FFFFFE, 0x02000000)
    mchk('f15', 0x02000000, 0x02000000, ifetch=True)
    mchk('f16', 0x3FFFFFFC, 0x3FFFFFFC, ehmsts=0xD1060800, ehsr=0x060800B1)
    put(0)                                  # R9: nothing unexpected
    pairs = ['%X:%08X' % (LOG + 4 * i, v) for i, v in enumerate(log) if v is not None]
    lines = [';@ rtl=' + ','.join(pairs[i:i + 6]) for i in range(0, len(pairs), 6)]
    return lines

if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--viba':
        for kv in sys.argv[2].split(','):
            k, v = kv.split('=')
            VIBA[k] = int(v, 16)
    out = main()
    src = sys.argv[-1] if sys.argv[-1].endswith('.s') else None
    if src:
        s = open(src).read()
        s = re.sub(r'(;@ rtl=[^\n]*\n)+', '', s)
        s = s.replace(';@ noref\n', ';@ noref\n' + '\n'.join(out) + '\n', 1)
        open(src, 'w').write(s)
        print('%d longwords expected' % sum(l.count(':') for l in out))
    else:
        print('\n'.join(out))

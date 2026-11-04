#!/usr/bin/env python3
"""mk_t56.py - the expected log of tests/mmu/t56_ubadma.s, from the DW780
Unibus Adapter Technical Description (EK-DW780-TD-001): wraparound (1.9.2,
2.5.2), the map registers (2.6.1, 2.9.10), the direct data path (2.6.2.1,
table 2-9), the buffered data paths (2.6.2.2, 3.3.1.3, 3.3.1.4), the purge
(2.9.9, 3.3.2), the status bits and their locks (2.9.3), FMER (2.9.5),
the map register disable bits (2.9.2, table 2-12), the longword access
mode (appendix A):

    python3 tests/mmu/gen/mk_t56.py tests/mmu/t56_ubadma.s
"""
import sys
from explog import Log

L = Log()

def mem(b):
    """the test's pattern: byte k of an area is k"""
    return sum(((b + i) & 0xFF) << (8 * i) for i in range(4))

def word(lo):                     # bytes lo, lo+1 of the pattern
    return (lo & 0xFF) | (((lo + 1) & 0xFF) << 8)

def dpr(bne=0, bte=0, dpf=0, bs=0, buba=0):
    return (bne << 31) | (bte << 30) | (dpf << 29) | (bs << 16) | buba

# direct data path: DATO, DATOB written as SBI write masked of the word or
# byte, DATI read masked; memory as written; a CPU byte read is the word's
L.put(0x1111, 0x2222, 0x3300, 0x0044, 0x00001111, 0x22220000, 0x00443300,
      0xCAFE, 0xBE, 0)
# map 1 invalid: IVMR, FMER 1, no slave sync - UBSSYNTO, FUBAR UA<17:2>,
# the word 0; again: LEB (2.9.3), FMER and FUBAR locked
L.put(0xFFFF0000, 0x11, 1, 0x80, 0x15, 1, 0x80, 0)
# MRD 1: map registers 0-15 not answered, no error but the timeout; map 16
# invalid: IVMR, FMER 16
L.put(0x01, 0x11, 0x10)
# BDP 1: the words collect (BNE, DPF, BS, BUBA = UA<17:2>), nothing in
# memory until the last word of the quadword (an extended write masked);
# a word and a byte then a purge: write masked of the low longword
L.put(dpr(1, 0, 1, 0x03, 0x100), dpr(1, 0, 1, 0x3F, 0x101), 0,
      dpr(0, 0, 1, 0, 0x101), 0xA2A3A0A1, 0xA6A7A4A5,
      dpr(1, 0, 1, 0x07, 0x102), dpr(0, 0, 0, 0, 0x102), 0x00B2B0B1, 0)
# byte by byte: the eighth byte sends them
L.put(dpr(0, 0, 1, 0, 0x417 >> 2), 0xC3C2C1C0, 0xC7C6C5C4)
# byte offset (2.6.2.2, figure 3-22): Unibus byte k at memory byte k+1;
# the byte past the quadword stays in the buffer as byte 0, BUBA + 1
L.put(dpr(1, 0, 1, 0x7E, 0x604 >> 2), 0xD2D1D0EE, 0xD6D5D4D3, 0xEEEEEEEE,
      dpr(1, 0, 1, 0x01, (0x606 >> 2) + 1), 0xEEEEEED7,
      dpr(0, 0, 0, 0, (0x606 >> 2) + 1))
# BDP 3 read: the quadword (extended read), then the buffer whatever memory
# holds now; the last word prefetches the next quadword (3.3.1.3.3)
L.put(word(0), dpr(1), word(2), word(4), word(6), word(8), word(10),
      word(12), word(14))
# purged: empty; a read from memory; from word 2 the longword
L.put(0, 0xAAAA, 0xBBBB, dpr(1), 0x6666, 0)
# a prefetch into an invalid map register is not recorded (2.6.2.2): the
# buffer stays empty; with the map register valid the prefetch fills it
L.put(0x1122, 0, 0, 0x1122, dpr(1), 0x5544)
# byte offset reads (3.3.1.3): bytes 1-2, 3-4, 5-6 (and the prefetch),
# 7 and the next quadword's 0, ...
L.put(*[word(1 + 2 * i) for i in range(8)])
# empty at word 3: the longword for byte 7, the next quadword for byte 0
# (the second read); empty at word 2: the longword, then the prefetch
L.put(word(7), word(9), word(5), word(7), 0)
# longword access mode (appendix A, table A-1): DATI reads the longword
# when the buffer is empty, the high word empties it; DATO of the high
# word (DATOB of byte 3) writes the longword with the bytes written
L.put(0x2211, 0x4433, 0x6655, 0x8877, 0, 0x56781234,
      dpr(0, 0, 1, 0, 0xE0A >> 2), 0xBC00009A, 0)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

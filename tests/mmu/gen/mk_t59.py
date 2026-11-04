#!/usr/bin/env python3
"""mk_t59.py - the expected log of tests/mmu/t59_ubdev.s, from the DW780
Unibus Adapter Technical Description (EK-DW780-TD-001) and the bench's
Unibus test device (sim/cpu_tb/ubdev.v, its registers in the test's
header):

  - Unibus space and its functions (2.5.2, table 2-7): a word or byte read
    is DATI of the word, a byte write DATOB, a word write DATO;
  - Unibus interrupts (2.7.1, 2.9.2 bits 6 and 5, 2.9.4 bit 30, 2.9.8): the
    BRRVR read fetches the vector with IFS set, reads zero with IFS clear,
    with DINTR or after a passive release; with IFS and BRIE the request
    goes to the SBI, the vector 100 + 40 * (IPL - 14) + 4 * TR (the 8600's
    SBIA, EK-DB86X-TD-002), TR 3; bit 31 for the adapter's own request on
    its level, BR4;
  - DMA (2.6.2, table 2-9, 3.3.1): the direct data path word by word, a
    DATIP-DATO an interlocked read-modify-write; a buffered data path
    writes its quadword when its last byte is written, keeps the rest for
    the purge, reads the quadword and prefetches the next after its last
    word, takes no DATIP (no DMA attention, no slave sync); the DPR
    (2.9.9); an invalid map register: IVMR and FMER (2.9.3, 2.9.5), no
    slave sync; the I/O page is not mapped (2.6.1);
  - Unibus select timeout when the adapter cannot become master (2.9.3),
    FUBAR (2.9.6);
  - adapter init: INIT on the Unibus (2.9.2 bit 0, 2.8.4).

    python3 tests/mmu/gen/mk_t59.py tests/mmu/t59_ubdev.s
"""
import sys
from explog import Log

L = Log()

# the device's CSR
GO, NXM, DONE, IREQ, IE = 0x8000, 0x4000, 0x0001, 0x0020, 0x0010
DATI, DATIP, DATO, DATOB = 0x0000, 0x1000, 0x2000, 0x3000

def lvl(br):
    return (br - 4) << 6

# the adapter
IVMR, UBSTO, UBSSYNTO = 0x10, 0x02, 0x01
MICOK, UBIC, CODE = 1 << 27, 1 << 16, 0x28
DINTR = 1 << 30

def dpr(bne=0, bte=0, dpf=0, bs=0, buba=0):
    return (bne << 31) | (bte << 30) | (dpf << 29) | (bs << 16) | buba

def psl(ipl):
    return 0x04000000 | (ipl << 16)            # IS, kernel

def scb(br, tr=3):
    return 0x100 + 0x40 * (br - 4) + 4 * tr

def w2l(lo, hi):
    return (hi << 16) | lo

E = 0xEEEE

# ------------------------------------------------ the device's registers
# INIT (processor initialization) cleared it; VEC as written, read back as
# the high word of its longword; BA written by bytes; BAE<1:0>; a DATOB of
# the CSR's high byte: the function; no adapter errors
L.put(0, 0x0154, 0x3412, 0x34, 3, DATOB, 0)

# ------------------------------------------------------ Unibus interrupts
# IFS clear: the BRRVR reads zero (2.9.8, case 5), the device keeps its
# request, nothing reaches the SBI
L.put(0, lvl(5) | IREQ, 0xA1)
# IFS without BRIE: no SBI request; the BRRVR read takes the vector through
# the bus grant (the device's request goes with it); BRRVR 4: no BR4
L.put(0xA2, 0, 0x0154, lvl(5), 0)
# DINTR: the request not recognized: no interrupt, the BRRVR reads zero
L.put(lvl(5) | IREQ, 0xA3, 0, lvl(5) | IREQ, DINTR | MICOK | UBIC | CODE)
# DINTR clear: REQ5; not taken at IPL 15, taken at 14: SCB 14C, IPL 15,
# the vector from BRRVR 5
L.put(0xA4, scb(5), psl(0x15), 0x0154, 0xA5, lvl(5))
# a passive release before the BRRVR read: zero (2.9.8, case 3)
L.put(scb(5), psl(0x15), 0, 0xA6)
# BR4 and the adapter's request (SUEFIE, UBSSYNTO): one interrupt, SCB 10C,
# IPL 14; BRRVR 4 negative with the device's vector; then nothing
L.put(scb(4), psl(0x14), 0x80000000 | 0xF0, UBSSYNTO, 0, 0xA7)
# BR6 (BRRVR 7 reads zero meanwhile): SCB 18C, IPL 16; BR7 above IPL 16:
# SCB 1CC, IPL 17
L.put(0, scb(6), psl(0x16), 0x01C8, 0xA8)
L.put(scb(7), psl(0x17), 0x01C8, 0xA9)

# ------------------------------------------------------------------ DMA
# the direct data path: DATO of 1111-1114 from 0 (SBI write masked)
L.put(DATO | DONE, w2l(0x1111, 0x1112), w2l(0x1113, 0x1114), w2l(E, E), 8, 0)
# DATI (read masked): the sum, the last word
L.put(DONE, 0x1111 + 0x1112 + 0x1113 + 0x1114, 0x1114)
# DATOB of 41, 42, 43 at 11, 12, 13 (octal): bytes 1-3 of MEMA+8
L.put(0x434241EE, w2l(E, E))
# DATIP-DATO (interlock read masked, interlock write masked): each word of
# MEMA plus 1
L.put(DATIP | DONE, w2l(0x1112, 0x1113), 0x1112, 0)
# BDP 1: words 0-3 fill the quadword, which goes to memory when its last
# byte is written; word 4 stays (BNE, DMA write, bytes 0-1, BUBA = UA<17:2>
# of 1010); the purge writes it
L.put(w2l(0x2000, 0x2001), w2l(0x2002, 0x2003), w2l(E, E),
      dpr(1, 0, 1, 0x03, 0x208 >> 2), dpr(buba=0x82), w2l(0x2004, E))
# DATI: the quadword, the words from the buffer, the prefetch after the
# last word (the buffer full, a DMA read); the purge empties it
L.put(0x2000 + 0x2001 + 0x2002 + 0x2003 + 0x2004, 0x2004,
      dpr(1, 0, 0, 0, 0x82), dpr(buba=0x82))
# DATIP through a buffer: not taken - the device's NXM, nothing recorded
L.put(DATIP | NXM | DONE, 0, dpr(buba=0x82))
# map register 2 not valid: IVMR, FMER, no slave sync
L.put(DATO | NXM | DONE, IVMR, 2)
# the I/O page (760000): nobody answers, not the adapter's
L.put(DATI | NXM | DONE, 0)
# 128 words in one burst: the adapter's read of VEC cannot get the bus -
# Unibus select timeout, zeros, FUBAR = UA<17:2> of 777402
L.put(0xFFFF0000, UBSTO, 0o777402 >> 2)
L.put(DATO | DONE, w2l(0x3000, 0x3001), 0)
# the interrupt at the end of a DMA: SCB 14C, the vector; the request gone
L.put(scb(5), psl(0x15), 0x0154, lvl(5) | IE | DONE)

# ------------------------------------------------------------ adapter init
# INIT on the Unibus clears the device
L.put(0)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

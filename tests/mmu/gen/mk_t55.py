#!/usr/bin/env python3
"""mk_t55.py - the expected log of tests/mmu/t55_uba.s, from the DW780
Unibus Adapter Technical Description (EK-DW780-TD-001): the registers
(2.9), the address space (2.5, table 2-6), SBI to Unibus translation
(table 2-7) and its failures (2.5.2.4), the confirmations (3.4.7.2,
figure 3-35), the interrupts (2.7, 3.6.7); the first DW780's jumpers
(EK-VAXV2-HB-002: TR 3, adapter 0, BR4); the 8600 SBIA (EK-DB86X-TD-002
3.14.8) and the machine check frame (EK-8600S-MM-004 appendix K):

    python3 tests/mmu/gen/mk_t55.py tests/mmu/t55_uba.s
"""
import sys
from explog import Log

UBA = 0x20006000
IOP = 0x20100000 + 0x3E000
L = Log()

CODE = 0x28                        # adapter code, Unibus 0 (table 2-10)
UBIC = 1 << 16
MICOK = 1 << 27

# after initialization: an adapter init long finished - UBIC (2.9.1, the
# last bit set by the sequence), CR, SR clear, DCR MIC OK and CNFGR<23:0>
# (2.9.4); FMER, FUBAR at both addresses; BRSVR, BRRVR, DPR, map 0
L.put(UBIC | CODE, 0, 0, MICOK | UBIC | CODE, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0)
# CR: <30:26> MRD, <6:2> (2.9.2); CNFIE with UBIC set: the adapter's
# request, BRRVR4 <31> (on the level its jumpers give it, BR4: 2.9.8)
L.put(0x7C00007C, 0x80000000, 0, 0)
# SR: write 1 to clear, nothing set; DCR <31:28> read/write, <27> MIC OK,
# <23:0> CNFGR (2.9.4)
L.put(0, 0xF0000000 | MICOK | UBIC | CODE, MICOK | UBIC | CODE)
# BRSVR <15:0> (figure 2-52); map registers: all 32 bits (2.9.10, 3.6.1)
L.put(0xABCD, 0x5555, 0xFFFFFFFF, 0x12345678)
# DPR1: BTE write 1 to clear, a purge of an empty buffer (2.9.9); DPR0 is
# always 0
L.put(0, 0, 0)
# a word read of a register returns the longword (2.9)
L.put(CODE, 1)
# writes to FMER, FUBAR, BRRVR: error confirmation (3.4.7.2.2)
L.mchk(UBA + 0x10, we=True); L.put(0x100)
L.mchk(UBA + 0x1C, we=True); L.put(0x100)
L.mchk(UBA + 0x34, we=True); L.put(0x100)
# reserved offsets: no response, an SBI timeout (status 00)
L.mchk(UBA + 0x80); L.put(0x1000)
L.mchk(UBA + 0xFC0); L.put(0x1000)
L.mchk(UBA + 0x1000, we=True); L.put(0x1000)
# Unibus space takes words and bytes only (table 2-7, 3.4.7.2): a longword
# read and a write with mask 0110 get an error confirmation
L.mchk(IOP); L.put(0x100)
L.mchk(IOP, we=True); L.put(0x100)
L.put(0)
# the I/O page with no device: zeros after the slave sync timeout, SR<0>,
# FUBAR UA<17:2> and locked (2.5.2.4, 2.9.3, 2.9.6); cleared, FUBAR keeps
# its contents; a write: acknowledged, the timeout comes 13 us later
L.put(0xFFFF0000, 1, 0xF800, 0xF800, 0, 0xF800)
L.put(0, 1, 0xFFFF)
# a byte read is a word read (the SBIA, mask 1100): UA 760002
L.put(0, 0xF800)
# SUEFIE: the request with UBSSYNTO (2.9.2, table 2-13)
L.put(0, 0x80000000, 0, 0)
# the interrupt: not at IPL 14, taken at 13 - SCB 100 + 4 * 3, IPL 14
L.put(0xA1, 0x10C, 0x04140000, 0x80000000, 1, 0xA2)
# CNFIE with UBIC; UBIC written 1 clears it and the request
L.put(0x80000000, CODE, 0, MICOK | CODE)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

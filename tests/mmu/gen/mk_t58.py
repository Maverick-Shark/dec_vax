#!/usr/bin/env python3
"""mk_t58.py - the expected log of tests/mmu/t58_ubainit.s, from the DW780
Unibus Adapter Technical Description (EK-DW780-TD-001): adapter init and
what it clears (2.9.2 bit 0, 3.3.3), the registers it lets software reach
meanwhile (2.9.2), MIC OK (2.9.4), the power fail sequences (2.8.4-2.8.6,
3.5.9: AC LO, DC LO and INIT 5 ms later, UBIC at the end, about 25 ms),
the configuration register's status bits (2.9.1), UPF (2.9.2 bit 1), SBI
UNJAM (2.8.6, 2.9.2), Unibus select timeout (2.9.3); the machine check
frame (EK-8600S-MM-004 appendix K):

    python3 tests/mmu/gen/mk_t58.py tests/mmu/t58_ubainit.s
"""
import sys
from explog import Log

UBA = 0x20006000
L = Log()

CODE = 0x28
UBIC, UBPDN, UBINIT, MICOK = 1 << 16, 1 << 17, 1 << 18, 1 << 27

def dpr(bne=0, bte=0, dpf=0, bs=0, buba=0):
    return (bne << 31) | (bte << 30) | (dpf << 29) | (bs << 16) | buba

# a word in BDP 1 (UA 200), the I/O page's timeout
L.put(dpr(1, 0, 1, 0x03, 0x200 >> 2), 1)
# adapter init: AC LO on the Unibus at once - UB PDN, UBIC cleared; the
# initialization routine: MIC OK clear, DCR<31:28> cleared
L.put(UBPDN | CODE, UBPDN | CODE)
# CR cannot be read during it: a machine check
L.mchk(UBA + 4)
# after the routine: CR as written meanwhile, SR, BRSVR, the map and data
# path registers cleared; CNFIE with UB PDN: the adapter's request
L.put(4, 0, MICOK | UBPDN | CODE, 0, 0, 0, 0, 0x80000000, UBPDN | CODE)
# 5 ms: DC LO and INIT - UB INIT; the adapter cannot become master: Unibus
# select timeout, zeros, FUBAR
L.put(UBINIT | UBPDN | CODE, 0xFFFF0000, 2, 0xF800)
# the power up: UBIC, which clears UB INIT and UB PDN; CNFIE; write 1 to
# clear
L.put(UBIC | CODE, 0x80000000, 0, CODE)
# UPF: AC LO; DC LO and INIT; down while UPF is set; up when cleared
L.put(UBPDN | CODE, UBINIT | UBPDN | CODE, 2, UBIC | CODE)
# UNJAM: BRIE, USEFIE, SUEFIE, CNFIE cleared; the power fail sequence
L.put(0x0C000040, UBPDN | CODE, UBIC | CODE, 0)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

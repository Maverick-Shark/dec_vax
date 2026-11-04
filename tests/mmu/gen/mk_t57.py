#!/usr/bin/env python3
"""mk_t57.py - the expected log of tests/mmu/t57_ubaerr.s, from the DW780
Unibus Adapter Technical Description (EK-DW780-TD-001): the status register
and its locking fields (2.9.3), the defeat bits (2.9.4), FMER (2.9.5), the
data path registers (2.9.9: BTE stops the buffer, the purge keeps BTE),
the map registers (2.9.10), SBI to Unibus failures (2.5.2.4: PB returned
as read data substitute), the interrupt enables (2.9.2); the 8600 SBIA's
receiver (EK-DB86X-TD-002 3.10-3.12: no response beyond the memory
separator, the MBox's abort of a page that is not memory) and the machine
check frame (EK-8600S-MM-004 appendix K, ABus bad data):

    python3 tests/mmu/gen/mk_t57.py tests/mmu/t57_ubaerr.s
"""
import sys
from explog import Log

UB = 0x20100000
L = Log()

RDS, CXTMO, DPPE, IVMR, MRPF, LEB, SSYNTO = 0x200, 0x40, 0x20, 0x10, 8, 4, 1

def dpr(bne=0, bte=0, dpf=0, bs=0, buba=0):
    return (bne << 31) | (bte << 30) | (dpf << 29) | (bs << 16) | buba

# megabyte 30 not memory: the read comes back as read data substitute -
# RDS, FMER 1, no slave sync, so UBSSYNTO; the write completes; a buffer
# read: RDS, FMER 2, no BTE (it is for writes and purges)
L.put(0xFFFF0000, RDS | SSYNTO, 1, 0, RDS | SSYNTO, 2, 0)
# beyond the separator: the direct data path tries while the master waits
# (no CXTMO for it), then the master's timeout
L.put(SSYNTO)
# BDP 2: three words in the buffer; the fourth: the quadword is not taken
# for 100 us - CXTMO, FMER 3, BTE, the data kept
L.put(0, CXTMO | SSYNTO, 3, dpr(1, 1, 1, 0xFF, 0x606 >> 2))
# BTE: the next word is not taken (no error but the master's timeout)
L.put(SSYNTO, dpr(1, 1, 1, 0xFF, 0x606 >> 2))
# BTE cleared; a purge through an invalid map register: IVMR, BTE again
L.put(dpr(1, 0, 1, 0xFF, 0x606 >> 2), IVMR, 3, dpr(1, 1, 1, 0xFF, 0x606 >> 2))
# map 3 valid: the purge writes the quadword (UA 600: page 3, quadword 0)
L.put(dpr(0, 0, 0, 0, 0x606 >> 2), 0x22221111, 0x44443333, 0)
# defeat map parity: map 0 (byte 2 = 00) fails at once - MRPF, FMER 0
L.put(MRPF | SSYNTO, 0)
# map 5 (80800103): high half odd, the words go into BDP 4; the last byte
# needs the SBI: the low half (byte 0 = 03) fails, MRPF, BTE
L.put(SSYNTO, dpr(1, 0, 1, 0x7F, 0xA06 >> 2), MRPF | SSYNTO, 5,
      dpr(1, 1, 1, 0xFF, 0xA07 >> 2))
# without the defeat the purge writes it
L.put(0x07070707, 0x07070707, 0)
# defeat data path parity: bytes 00 and 03 sent to memory fail - DPPE,
# BTE, nothing written; then without it, the purge
L.put(DPPE | SSYNTO, dpr(1, 1, 1, 0xFF, 0xA0E >> 2), 0, 0x01010101, 0x03000101)
# a read: the first word from memory (no data path check), the second from
# the buffer: FF and 00 fail - the word with PB, read data substitute to
# the CPU: machine check, ABus bad data; DPPE and BTE, BNE, no DPF
L.put(0x0101, 0)
L.mchk(UB + 0xA12, bad=True)
L.put(DPPE, dpr(1, 1, 0, 0, 0xA0E >> 2))
# USEFIE: IVMR raises the request; SUEFIE: the timeout; without USEFIE the
# IVMR left does not
L.put(0, 0x80000000, 0x80000000, 0, 0)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

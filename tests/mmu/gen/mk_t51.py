#!/usr/bin/env python3
"""mk_t51.py - the expected log of tests/mmu/t51_mba.s, from the RH780
Technical Description (EK-RH780-TD-001, chapter 3 and 4.2.6-4.2.8, 4.5.2),
the RP04/05/06 DCL manual (EK-RP056-MM-01, 2.4.1.3) for the drive's
registers, the 8600 SBIA (EK-DB86X-TD-002 3.14.3, 3.14.8) and the machine
check frame (EK-8600S-MM-004 appendix K):

    python3 tests/mmu/gen/mk_t51.py tests/mmu/t51_mba.s
"""
import sys
from explog import Log

MBA = 0x20010000
L = Log()

# after initialization: CSR adapter code 20; CR, SR, VAR, BCR, DR 0
L.put(0x20, 0, 0, 0, 0, 0)
# VAR <16:0>; BCR: a write loads both counters; DR ignored outside
# maintenance mode; CR; DR <31:21> and FAIL (<20>) in maintenance mode;
# INIT clears DR, CR; CSR, SR: write 1 to clear
L.put(0x1FFFF, 0xFFFFFFFF, 0xFE00FE00, 0, 6, 8, 0xFFF00000, 0xFFE00000,
      0, 0, 0x20, 0)
# map registers <31>, <20:0>; SMR = map[VAR<16:9>]
L.put(0x80000123, 0x801FFFFF, 0x001FFFFF, 0x801FFFFF, 0x001FFFFF, 0x80000123)
# drive 0 (RP07, no image): DT 020042, DS DPR|DRY, CS1 DVA, SN, AS;
# DA <13:8>,<6:0>; DC <9:0>; OF <15,14,12:10>; DT read only; ER1
L.put(0x2022, 0x0180, 0x0800, 0x1001, 0, 0x3F7F, 0x3FF, 0xDC00, 0x2022, 0)
# register 20: ILR, the read returns 0 with SR<31:16> (attention: the
# drive's ATA, set by the error); ER1 ILR; DS ATA|ERR|DPR|DRY; AS bit 0;
# SR<16>; drive clear clears ATA, and SR<16>, the ATTN line, goes with it
L.put(0x00010000, 0x00010002, 0x0001C180, 0x00010001, 0x00010000,
      0x00000000, 0, 0x0180)
# unit 2: no TRA in 1.5 us, NED (SR<18>), the data 0; a write too
L.put(0x00040000, 0x00040000, 0x00040000, 0)
# a word read: error confirmation (TD 4.2.7) - a machine check, SBIER<08>,
# ERRSUM read 0001, even word 01, lock
L.mchk(MBA, io=True)
L.put(0x00000100, 0x14800000)
# a byte write: ERRSUM write 1101, mask 0001 (even word 01); not written
L.mchk(MBA + 4, we=True)
L.put(0x00000100, 0xD4800000, 0)
# no response (TD 4.2.6): SBI timeout, status 00
L.mchk(MBA + 0x20)
L.put(0x00001000)
L.mchk(MBA + 0xC00)
L.put(0x00001000)
L.mchk(MBA + 0x1000, we=True)
L.put(0x00001000)
# the interrupt: not at IPL 15, taken at 14 - SCB 160, PSL IS, IPL 15,
# SR NED
L.put(0xA1, 0x160, 0x04150000, 0x00040000, 0xA2)
# INIT clears IE; ABORT; UNJAM clears it
L.put(0, 2, 0)
# maintenance mode and IE (CR = C); INIT with CR<3> 0 clears MM (CR's bits
# are read/write, figure 3-2); the drive answers again: DT
L.put(0xC, 0, 0x2022)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

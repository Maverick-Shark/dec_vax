#!/usr/bin/env python3
"""mk_t53.py - the expected log of tests/mmu/t53_mbard.s: reads from an
RP07 through the RH780 (EK-RH780-TD-001 3.5, 3.6, 4.4, 4.5.4) as the RP04/
05/06 DCL manual (EK-RP056-MM-01 2.3.2, 2.4.4, 3.4.1.3, 3.9) and the RP07's
geometry define them, on the bench's generated disk:

    python3 tests/mmu/gen/mk_t53.py tests/mmu/t53_mbard.s
"""
import sys
from explog import Log

MOL, DPR, DRY, VV, LST, ATA, ERR = (0x1000, 0x0100, 0x0080, 0x0040, 0x0400,
                                    0x8000, 0x4000)
DTCOMP, DTABT, MBEXC, INVMAP, ATTN, DTBUSY = (0x2000, 0x1000, 0x80, 0x10,
                                              0x10000, 0x80000000)
MARK = 0xEEEEEEEE
L = Log()


def h(lba):
    return (lba ^ (lba >> 8) ^ (lba >> 16)) & 0xFF


def lw(lba, j):
    """longword j of the generated sector at LBA lba"""
    return (2 * j) | (h(lba) << 8) | ((2 * j + 1) << 16) | (h(lba) << 24)


def cylsec(c, t, s):
    return (c * 32 + t) * 50 + s


# one sector: DT COMP; VAR 200; BCR 0; DA 1; DS; data; the next longword
L.put(DTCOMP, 0x200, 0, 1, MOL | DPR | DRY | VV,
      lw(0, 0), lw(0, 1), lw(0, 127), MARK)
# three sectors from LBA 49, a head switch: VAR A00, DA track 1 sector 2
L.put(DTCOMP, 0xA00, 0x0102, lw(49, 0), lw(49, 127), lw(50, 0), lw(51, 0),
      MARK)
# seven bytes to byte 3: VAR eight past the last byte (A0A + 8), Massbus
# byte counter past 0 (four words), SBI byte counter 0; masked writes
d = [((k >> 1) if k % 2 == 0 else h(0)) & 0xFF for k in range(7)]
m = [0xEE] * 16
m[3:10] = d
L.put(DTCOMP, 0xA12, 0x00010000,
      *[int.from_bytes(bytes(m[i:i + 4]), 'little') for i in (0, 4, 8, 12)])
# read header and data: the cylinder with FMT (<12>), sector/track, two
# key words, then the data
L.put(DTCOMP, 0x00001000, 0, lw(0, 0), lw(0, 127), MARK)
# a mid-transfer seek: DC 2, DA 1, CC 2
assert cylsec(1, 31, 49) == 3199
L.put(DTCOMP, 2, 1, 2, lw(3199, 0), lw(3200, 0))
# the last sector and RUN still asserted: AOE (the drive's EXC, ATA at the
# end), LST; DC 630, DA 0
last = cylsec(629, 31, 49)
assert last == 1007999
L.put(ATTN | DTCOMP | DTABT | MBEXC, ATTN | 0x0200,
      ATTN | ATA | ERR | MOL | LST | DPR | DRY | VV, ATTN | 630, ATTN,
      lw(last, 0))
# a page not valid: INVMAP, aborted; no drive error
L.put(DTCOMP | DTABT | INVMAP, MOL | LST | DPR | DRY | VV)
# FMT clear: FER, the drive's EXC
L.put(ATTN | DTCOMP | DTABT | MBEXC, ATTN | 0x0010)
# the interrupt at the end of the transfer: busy first, then SCB 160 at
# IPL 15 with DT COMP
L.put(DTBUSY, DTCOMP, 0x04150000, 0x160)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

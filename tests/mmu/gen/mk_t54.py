#!/usr/bin/env python3
"""mk_t54.py - the expected log of tests/mmu/t54_mbawr.s: writes, write
checks and errors of the RH780 (EK-RH780-TD-001 3.3, 3.5, 3.6.2-3.6.5,
4.4.8, 4.5.2, 4.5.4) with RP07s (EK-RP056-MM-01 2.3.2, 2.4.4, 3.12.1):

    python3 tests/mmu/gen/mk_t54.py tests/mmu/t54_mbawr.s
"""
import sys
from explog import Log

MOL, WRL, DPR, DRY, VV, ATA, ERR = (0x1000, 0x0800, 0x0100, 0x0080, 0x0040,
                                    0x8000, 0x4000)
DTCOMP, DTABT, WCKU, WCKL, MXF, NED, PGE, ATTN = (
    0x2000, 0x1000, 0x0400, 0x0200, 0x0100, 0x40000, 0x80000, 0x10000)
L = Log()

# memory 20000-203FF
mem = bytearray()
for j in range(256):
    mem += (0x5A000000 + j * 0x00010101).to_bytes(4, 'little')


def lw(b, off):
    return int.from_bytes(bytes(b[off:off + 4]), 'little')


def h(lba):
    return (lba ^ (lba >> 8) ^ (lba >> 16)) & 0xFF


def pat(lba, j):
    return (2 * j) | (h(lba) << 8) | ((2 * j + 1) << 16) | (h(lba) << 24)


# two sectors written: DT COMP, VAR 400, BCR 0, DA track 2 sector 2; read
# back: the same longwords, no difference
L.put(DTCOMP, 0x400, 0, 0x0202, DTCOMP, lw(mem, 0), lw(mem, 0x3FC), 0)
# write check: equal; upper byte of word 8 of the second sector: WCK UP;
# lower byte of word 8 of the first: WCK LWR; both aborted; no drive error
L.put(DTCOMP, DTCOMP | DTABT | WCKU, DTCOMP | DTABT | WCKL,
      MOL | DPR | DRY | VV)
# three bytes: then zeros to the end of the sector
L.put(DTCOMP, 0x00332211, 0, 0)
# five bytes from memory byte 6: VAR eight past the last (B + 8)
five = bytes(mem[6:11]) + bytes(3)
L.put(DTCOMP, 0x13, lw(five, 0), lw(five, 4))
# write header and data: the data is memory from byte 8
L.put(DTCOMP, lw(mem, 8), lw(mem, 8 + 508))
# write check header and data: the drive's header matches
L.put(DTCOMP)
# program errors during a transfer: VAR, BCR, MAP unchanged, the second
# command not sent; the transfer itself is fine (LBA 0 and 1)
L.put(PGE | DTCOMP, 0x1C00, 0, 0x8000010C, pat(0, 0), pat(1, 0))
# unit 3: NED, then the missed transfer
L.put(NED | DTCOMP | DTABT | MXF)
# function 075: ILF (attention), missed transfer
L.put(ATTN | DTCOMP | DTABT | MXF, ATTN | 0x0001)
# unit 1 read only: WLE, WRL, missed transfer
L.put(ATTN | DTCOMP | DTABT | MXF, ATTN | 0x0800,
      ATTN | ATA | ERR | MOL | WRL | DPR | DRY | VV)
# CR<1> abort during the seek
L.put(DTCOMP | DTABT, MOL | DPR | DRY | VV)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

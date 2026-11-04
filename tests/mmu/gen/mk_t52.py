#!/usr/bin/env python3
"""mk_t52.py - the expected log of tests/mmu/t52_rp07.s: the RP07's
registers and positioning commands as the RP04/05/06 DCL manual
(EK-RP056-MM-01 2.3, 2.4.1.3, table 2-1) defines them, with the RP07's
fields (DEC's TOPS-20 RP07 support), on the RH780 (EK-RH780-TD-001 3.7:
a drive register read carries SR<31:16>):

    python3 tests/mmu/gen/mk_t52.py tests/mmu/t52_rp07.s
"""
import sys
from explog import Log

ATA, ERR, PIP, MOL, DPR, DRY, VV, OM = (0x8000, 0x4000, 0x2000, 0x1000,
                                        0x0100, 0x0080, 0x0040, 0x0001)
SR_ATTN = 0x10000
L = Log()

# after initialization (the mount's attention cleared by it); pack ack
L.put(MOL | DPR | DRY, MOL | DPR | DRY | VV)
# OF keeps <15,14,12:10>; read-in preset clears FMT ECI HCI, DA, DC
L.put(0x9C00, 0x8000, 0, 0, MOL | DPR | DRY | VV)
# a seek: PIP, GO; then ATA (SR<16>), CC, AS; cleared
L.put(PIP | MOL | DPR | VV, 0x0805,
      SR_ATTN | ATA | MOL | DPR | DRY | VV, SR_ATTN | 100, SR_ATTN | 1,
      MOL | DPR | DRY | VV, 0)
# RMR during a seek: ERR and ATA at once, PIP still; the register is not
# written; the seek ends; a command with ERR is ignored; drive clear
L.put(SR_ATTN | ATA | ERR | PIP | MOL | DPR | VV, SR_ATTN | 0x0004, SR_ATTN,
      SR_ATTN | 600, SR_ATTN | ATA | ERR | MOL | DPR | DRY | VV,
      SR_ATTN | ATA | ERR | MOL | DPR | DRY | VV, SR_ATTN | 600,
      SR_ATTN, MOL | DPR | DRY | VV)
# IAE (cylinder 630): no motion; IAE (sector 50); ILF (041)
L.put(SR_ATTN | ATA | ERR | MOL | DPR | DRY | VV, SR_ATTN | 0x0400,
      SR_ATTN | 600, SR_ATTN | 0x0400, SR_ATTN | 0x0001,
      SR_ATTN | ATA | ERR | MOL | DPR | DRY | VV)
# search for sector 25: LA <12:6>
L.put(SR_ATTN | (25 << 6), SR_ATTN | ATA | MOL | DPR | DRY | VV)
# recalibrate: cylinder 0; offset: OM; return to centerline; a seek in
# offset mode returns to centerline; a seek to where the heads are
L.put(SR_ATTN, SR_ATTN | ATA | MOL | DPR | DRY | VV,
      SR_ATTN | ATA | MOL | DPR | DRY | VV | OM,
      SR_ATTN | ATA | MOL | DPR | DRY | VV,
      SR_ATTN | ATA | MOL | DPR | DRY | VV, SR_ATTN | 10,
      SR_ATTN | ATA | MOL | DPR | DRY | VV)
# unit 1, no image: UNS; its AS bit; drive clear
L.put(DPR | DRY, SR_ATTN | 0x4000, SR_ATTN | ATA | ERR | DPR | DRY,
      SR_ATTN | 2, 0)
# unload: off line, PIP, GO; INIT does not end it
L.put(PIP | DPR, 0x0803, PIP | DPR, 0)
L.put(0)                                    # R9: nothing unexpected

if __name__ == '__main__':
    if len(sys.argv) > 1:
        L.write_into(sys.argv[1])
    else:
        print('\n'.join(L.lines()))

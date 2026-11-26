#!/usr/bin/env python3
"""nbpatch.py - two fixes for the Massbus disk support of NetBSD 11.0/vax,
patched into its GENERIC kernel, either the kernel file itself or the
kernel inside a disk image (found by its bytes, which must be unique):

    python3 tools/netbsd/nbpatch.py netbsd-rp07.dsk

Without them NetBSD cannot use an RP07 (or any Massbus disk) on an 8600, a
780 or a 750; both were found running the kernel on the reference
simulator's VAX 8600, and both are in NetBSD's source, not in the machine:

1. sys/arch/vax/mba/hp.c, hpattach(): the disk label is read through
   makedev(0, unit * 8), partition a of the label the kernel has made up
   for a disk it knows nothing about yet, in which only partition c
   (RAW_PART) has a size: the read is out of bounds and every hp disk
   attaches with "I/O error" and no label, so the root file system on it
   cannot be mounted. Read it through partition c, minor unit * 8 + 2:

       ROTL #3,R0,R0 ; BICL2 #FFFFFF07,R0      (minor<7:0> = unit * 8)
    -> MOVAQ @#2[R0],R0 ; NOP ; NOP ; NOP      (minor<7:0> = unit * 8 + 2)

2. sys/arch/vax/vax/disksubr.c, disk_reallymapin(): for a buffer in user
   space (B_PHYS: raw I/O, fsck on /dev/rhp0a for one) the PTE is taken
   from the process's P0 or P1 page table indexed with the buffer's byte
   address instead of its page number, and the kernel takes a fault
   ("SEGV in kernel"). Index with VA<29:9>:

       BICL3 #BFFFFFFF,R1,R0 ; BEQL p0 ; MOVAL @14(R3)[R1],R3 ; BRB ;
       p0: MOVAL @C(R3)[R1],R3 ; BRB
    -> EXTZV #9,#21,R1,R0 ; BBC #30,R1,p0 ; MOVAL @14(R3)[R0],R3 ; BRB ;
       p0: MOVAL @C(R3)[R0],R3 ; BRB ; NOP

Both replacements have the length of the code they replace, so nothing
else moves. Running it twice is harmless ("already patched").
"""
import mmap
import sys

# (what comes before it, the old code, the new code) - VAX bytes
FIXES = [
    ('hpattach: the label through partition c',
     bytes.fromhex('9c0c5751ca8fffff0f0051'),     # ROTL #C,R7,R1 ; BICL2 #FFFFF,R1
     bytes.fromhex('9c035050ca8f07ffffff50'),
     bytes.fromhex('7e409f0200000050010101')),
    ('disk_reallymapin: index the page table with the page number',
     bytes.fromhex('d0b33053'),                   # MOVL @30(R3),R3
     bytes.fromhex('cb8fffffffbf51501307de41b3145311abde41b30c5311a4'),
     bytes.fromhex('ef09155150e11e5107de40b3145311acde40b30c5311a501')),
]


def patch(path):
    with open(path, 'r+b') as f:
        m = mmap.mmap(f.fileno(), 0)
        for name, ctx, old, new in FIXES:
            assert len(old) == len(new)
            at = m.find(ctx + old)
            if at < 0:
                if m.find(ctx + new) >= 0:
                    print('%s: already patched' % name)
                    continue
                raise SystemExit('%s: code not found (not NetBSD 11.0 GENERIC?)' % name)
            if m.find(ctx + old, at + 1) >= 0:
                raise SystemExit('%s: code found more than once' % name)
            m[at + len(ctx):at + len(ctx) + len(old)] = new
            print('%s: patched at offset 0x%x' % (name, at + len(ctx)))
        m.flush()
        m.close()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    patch(sys.argv[1])

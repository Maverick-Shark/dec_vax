#!/usr/bin/env python3
# mk_t34.py - generates tests/mmu/t34_strx.s, MOVTC, MOVTUC, MATCHC and CRC:
#     python3 tests/mmu/gen/mk_t34.py > tests/mmu/t34_strx.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
import sys
# CRC-16 (polynomial A001, as in the VAX documentation's example), 16 entries
def crctab(poly):
    t = []
    for i in range(16):
        c = i
        for _ in range(4):
            c = (c >> 1) ^ (poly if c & 1 else 0)
        t.append(c)
    return t
t16 = crctab(0xA001)
t32 = crctab(0xEDB88320)
o = []
o.append("""; t34_strx - MOVTC (forward, backward with overlapping strings, truncated,
; all fill, empty), MOVTUC (stopped by the escape character, by either
; length), MATCHC (found, not found, empty object, object longer than the
; string, found at the end), CRC (CRC-16 and CRC-32 tables, empty string).
; Each case logs the PSL and R0-R5; the strings are dumped. Compared with
; the reference simulator.
;@ dump=8000:C0 dump=18000:140
	.include "mmsetup.inc"
STR	= S0+^x8000			; strings
TBL	= S0+^x8200			; translation table: 255 - i
CT16	= S0+^x8300			; CRC tables
CT32	= S0+^x8340
test:
	clrl	r0
tbl_l:	subb3	r0, #^xFF, @#TBL[r0]
	aoblss	#256, r0, tbl_l
	movc3	#64, @#S0+crc_t, @#CT16
""")
def log():
    o.append('\tmovpsl\t(r11)+')
    o.append('\tmovq\tr0, (r11)+')
    o.append('\tmovq\tr2, (r11)+')
    o.append('\tmovq\tr4, (r11)+')
def init_str():
    o.append('\tmovc5\t#0, @#STR, #0, #64, @#STR')
    o.append('\tmovl\t#^x44434241, @#STR+^x40')	# "ABCD"
    o.append('\tmovl\t#^x48474645, @#STR+^x44')	# "EFGH"
    o.append('\tmovl\t#^x4C4B4A49, @#STR+^x48')	# "IJKL"
cases = [
 ("MOVTC 5 bytes into 8, forward, fill *", "movtc\t#5, @#STR+^x40, #^x2A, @#TBL, #8, @#STR"),
 ("MOVTC 8 bytes into 3: truncated", "movtc\t#8, @#STR+^x40, #^x2A, @#TBL, #3, @#STR+^x10"),
 ("MOVTC overlapping, source below: backward", "movtc\t#6, @#STR+^x40, #^x2A, @#TBL, #9, @#STR+^x42"),
 ("MOVTC overlapping, source above: forward", "movtc\t#6, @#STR+^x42, #^x2A, @#TBL, #6, @#STR+^x40"),
 ("MOVTC nothing to move: all fill", "movtc\t#0, @#STR+^x40, #^x2E, @#TBL, #5, @#STR+^x20"),
 ("MOVTC nothing at all", "movtc\t#0, @#STR+^x40, #^x2E, @#TBL, #0, @#STR+^x20"),
 ("MOVTC srclen 8000 (negative as a word) : 1", "movtc\t#^x8000, @#STR+^x40, #^x2E, @#TBL, #1, @#STR+^x28"),
 ("MOVTUC stopped by the escape (B translates to BD)", "movtuc\t#8, @#STR+^x40, #^xBD, @#TBL, #10, @#STR"),
 ("MOVTUC the source ends", "movtuc\t#4, @#STR+^x44, #^x01, @#TBL, #10, @#STR+^x10"),
 ("MOVTUC the destination ends", "movtuc\t#8, @#STR+^x40, #^x01, @#TBL, #3, @#STR+^x18"),
 ("MATCHC found in the middle", "matchc\t#3, @#STR+^x43, #12, @#STR+^x40"),
 ("MATCHC not found", "matchc\t#2, @#STR+^x41, #12, @#STR+^x44"),
 ("MATCHC empty object", "matchc\t#0, @#STR+^x41, #12, @#STR+^x44"),
 ("MATCHC object longer than the string", "matchc\t#5, @#STR+^x40, #3, @#STR+^x40"),
 ("MATCHC found at the end", "matchc\t#2, @#STR+^x4A, #12, @#STR+^x40"),
 ("MATCHC empty string, empty object", "matchc\t#0, @#STR+^x40, #0, @#STR+^x44"),
 ("CRC-16 of ABCDEFGHIJKL, initial 0", "crc\t@#CT16, #0, #12, @#STR+^x40"),
 ("CRC-16, initial FFFF", "crc\t@#CT16, #^xFFFF, #12, @#STR+^x40"),
 ("CRC-32 of ABCDEFGHIJKL, initial FFFFFFFF", "crc\t@#CT32, #-1, #12, @#STR+^x40"),
 ("CRC of nothing: the initial value", "crc\t@#CT32, #^x12345678, #0, @#STR+^x40"),
]
for com, ins in cases:
    o.append('; ' + com)
    init_str()
    o.append('\tmovl\t#^x11111111, r0')
    o.append('\tmovl\t#^x22222222, r1')
    o.append('\tmovl\t#^x33333333, r2')
    o.append('\tmovl\t#^x44444444, r3')
    o.append('\tmovl\t#^x55555555, r4')
    o.append('\tmovl\t#^x66666666, r5')
    o.append('\tbicpsw\t#^xF')
    o.append('\t' + ins)
    log()
    o.append('\tmovc3\t#32, @#STR, (r11)')
    o.append('\tmovl\tr3, r11')
o.append('\thalt')
o.append('\t.align\t2')
o.append('crc_t:')
for v in t16 + t32:
    o.append('\t.long\t^x%08X' % v)
sys.stdout.write('\n'.join(o) + '\n')

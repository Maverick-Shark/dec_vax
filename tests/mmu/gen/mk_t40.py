#!/usr/bin/env python3
# mk_t40.py - generates tests/mmu/t40_cmpc.s, the CMPC3 and CMPC5 cases:
#     python3 tests/mmu/gen/mk_t40.py > tests/mmu/t40_cmpc.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
# (comment, string 1 bytes, string 2 bytes, fill or None for CMPC3)
cases = [
 ("CMPC3, length 0", [], [], None),
 ("CMPC3, equal", [0x41, 0x42, 0x43, 0x44], [0x41, 0x42, 0x43, 0x44], None),
 ("CMPC3, C < D at the third byte", [0x41, 0x42, 0x43, 0x44], [0x41, 0x42, 0x44, 0x44], None),
 ("CMPC3, 80 : 01 (signed less, unsigned greater)", [0x80], [0x01], None),
 ("CMPC3, 01 : FF (signed greater, unsigned less)", [0x01], [0xFF], None),
 ("CMPC3, 7F : 80", [0x10, 0x7F], [0x10, 0x80], None),
 ("CMPC5, both empty", [], [], 0x2B),
 ("CMPC5, string 1 empty, string 2 all fill", [], [0x2B, 0x2B, 0x2B], 0x2B),
 ("CMPC5, string 1 empty, fill 2B : 41", [], [0x2B, 0x41], 0x2B),
 ("CMPC5, string 2 empty, 42 : fill 41", [0x41, 0x42, 0x43], [], 0x41),
 ("CMPC5, A : A++ with fill + (EVKAB test 139)", [0x41], [0x41, 0x2B, 0x2B], 0x2B),
 ("CMPC5, A++ : A with fill +", [0x41, 0x2B, 0x2B], [0x41], 0x2B),
 ("CMPC5, fill 01 : 80", [], [0x80], 0x01),
 ("CMPC5, 90 : fill 10", [0x41, 0x90], [0x41], 0x10),
 ("CMPC5, fill FF : 7F", [0x41], [0x41, 0x7F], 0xFF),
 ("CMPC5, differ in the common part", [0x41, 0x42, 0x43], [0x41, 0x58], 0x20),
 ("CMPC5, longer string 1, equal with the fill", [0x31, 0x32, 0x20, 0x20], [0x31, 0x32], 0x20),
]
base = 0x18000 + 20 * len(cases)		# the fault records, after the cases
masks = ','.join('%X:F7FFFFF0' % (base + o) for o in (0x0C, 0x20, 0x48, 0x5C))
out = ["""; t40_cmpc - CMPC3 and CMPC5: equal and unequal strings, empty ones, the
; fill against the rest of the longer string on either side, and bytes that
; compare differently signed and unsigned (N is a signed comparison of the
; last two bytes, C an unsigned one, as CMPB). Then both across an invalid
; page (the fault is taken, the instruction done again). Found with EVKAB
; test 139: CMPC5 compared the fill with string 1 instead of string 2, and
; gave the condition codes of a stale register for two empty strings. Each
; case logs the PSL and R0-R3. The reference simulator keeps the progress
; of a CMPC that
; faults in R0-R3 with PSL<FPD>; the core does it again from the start (it
; only reads), so PSL<FPD> and the condition codes of the fault frames are
; not compared.
;@ dump=18000:80
%s
	.include "mmsetup.inc"
S1	= S0+^x8000
S2	= S0+^x8100
test:
	movl	#S0+fix_valid, r10
""" % (';@ mask=' + masks)]
for i, (com, s1, s2, fill) in enumerate(cases):
    out.append('; %s' % com)
    for j, b in enumerate(s1):
        out.append('\tmovb\t#^x%02X, @#S1+%d' % (b, j))
    out.append('\tmovb\t#^x5A, @#S1+%d' % len(s1))       # the byte after it
    for j, b in enumerate(s2):
        out.append('\tmovb\t#^x%02X, @#S2+%d' % (b, j))
    out.append('\tmovb\t#^x5A, @#S2+%d' % len(s2))
    out.append('\tmovl\t#^x11111111, r0')
    out.append('\tmovl\t#^x22222222, r1')
    out.append('\tmovl\t#^x33333333, r2')
    out.append('\tmovl\t#^x44444444, r3')
    out.append('\tmovl\t#%d, r5' % i)
    out.append('\tbispsw\t#^xF')
    if fill is None:
        out.append('\tcmpc3\t#%d, @#S1, @#S2' % len(s1))
    else:
        out.append('\tcmpc5\t#%d, @#S1, #^x%02X, #%d, @#S2' % (len(s1), fill, len(s2)))
    out.append('\tmovpsl\t(r11)+')
    out.append('\tmovq\tr0, (r11)+')
    out.append('\tmovq\tr2, (r11)+')
out.append("""; across an invalid page: 8DFC..8E03 against 8FFC..9003, pages 47 and 48
; invalid (the second operand of each faults part way)
	movl	#^x44434241, @#S0+^x8DFC
	movl	#^x48474645, @#S0+^x8E00
	movl	#^x44434241, @#S0+^x8FFC
	movl	#^x48474646, @#S0+^x9000
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	bicl2	#PTE_V, @#S0+SPT+<^x48*4>
	mtpr	#S0+^x8E00, #TBIS
	mtpr	#S0+^x9000, #TBIS
	cmpc3	#8, @#S0+^x8DFC, @#S0+^x8FFC
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	bicl2	#PTE_V, @#S0+SPT+<^x48*4>
	mtpr	#S0+^x8E00, #TBIS
	mtpr	#S0+^x9000, #TBIS
	cmpc5	#8, @#S0+^x8DFC, #^x46, #6, @#S0+^x8FFC
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	halt
""")
import sys
sys.stdout.write('\n'.join(out))

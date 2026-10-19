#!/usr/bin/env python3
# mk_t28.py - generates tests/mmu/t28_acb.s, ACBB, ACBW, ACBL and the CVT cases:
#     python3 tests/mmu/gen/mk_t28.py > tests/mmu/t28_acb.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
cases = [
 # (comment, setup lines, instruction)
 ("ACBL -1+1 = 0, limit 5: branch; V clear (no overflow, only a sign change)",
  ["movl\t#-1, r0"], "acbl\t#5, #1, r0, %s"),
 ("ACBL 7FFFFFFF+1: overflow (V, N); 80000000 <= 7FFFFFFF: branch",
  ["movl\t#^x7FFFFFFF, r0"], "acbl\t#^x7FFFFFFF, #1, r0, %s"),
 ("ACBL 5-2 = 3 >= 3: branch",
  ["movl\t#5, r0"], "acbl\t#3, #-2, r0, %s"),
 ("ACBL 3-2 = 1 >= 3: no",
  ["movl\t#3, r0"], "acbl\t#3, #-2, r0, %s"),
 ("ACBL 10+1 = 11 <= -5: no",
  ["movl\t#10, r0"], "acbl\t#-5, #1, r0, %s"),
 ("ACBL -2+1 = -1 <= 7FFFFFFF: branch (limit - index overflows)",
  ["movl\t#-2, r0"], "acbl\t#^x7FFFFFFF, #1, r0, %s"),
 ("ACBL 80000000-1: overflow; 7FFFFFFF >= 0: branch",
  ["movl\t#^x80000000, r0"], "acbl\t#0, #-1, r0, %s"),
 ("ACBL -1-1 = -2 >= 80000000: branch (index - limit overflows)",
  ["movl\t#-1, r0"], "acbl\t#^x80000000, #-1, r0, %s"),
 ("ACBB 7F+1: overflow (V, N); -128 <= 127: branch",
  ["movl\t#^x1234567F, r0"], "acbb\t#^x7F, #1, r0, %s"),
 ("ACBB 80-1: overflow; 127 >= 0: branch",
  ["movl\t#^x12345680, r0"], "acbb\t#0, #-1, r0, %s"),
 ("ACBB -100+0 <= 100: branch (the difference is not a byte)",
  ["movl\t#-100, r0"], "acbb\t#100, #0, r0, %s"),
 ("ACBB 20-1 = 19 >= -100: branch",
  ["movl\t#20, r0"], "acbb\t#-100, #-1, r0, %s"),
 ("ACBB 120+1 = 121 <= -100: no",
  ["movl\t#120, r0"], "acbb\t#-100, #1, r0, %s"),
 ("ACBB on a byte in memory: 10+5 = 15 <= 20: branch, the bytes around it kept",
  ["movl\t#^xAA550AAA, @#S0+^x8000", "movl\t#S0+^x8001, r1"], "acbb\t#20, #5, (r1)+, %s"),
 ("ACBW 7FFF+1: overflow; -32768 <= 7FFF: branch",
  ["movl\t#^xABCD7FFF, r0"], "acbw\t#^x7FFF, #1, r0, %s"),
 ("ACBW 5-10 = -5 >= 0: no; the upper word of the register kept",
  ["movl\t#^xABCD0005, r0"], "acbw\t#0, #-10, r0, %s"),
 ("ACBW on a word in memory: 1000+1000 = 2000 <= 2000: branch",
  ["movl\t#^x555503E8, @#S0+^x8004", "movl\t#S0+^x8004, r1"], "acbw\t#2000, #1000, (r1), %s"),
]
cvt = [
 ("CVTLB 127: fits", "cvtlb\t#127, r0"),
 ("CVTLB 128: V", "cvtlb\t#128, r0"),
 ("CVTLB -129: V", "cvtlb\t#-129, r0"),
 ("CVTLB -128: fits, N", "cvtlb\t#-128, r0"),
 ("CVTWB 0080: V", "cvtwb\t#^x80, r0"),
 ("CVTWB FF80: fits, N", "cvtwb\t#^xFF80, r0"),
 ("CVTWB 0100: V, Z", "cvtwb\t#^x100, r0"),
 ("CVTBW FF: FFFF, N", "cvtbw\t#^xFF, r0"),
 ("CVTBW 00: Z", "cvtbw\t#0, r0"),
 ("CVTLW 8000: V", "cvtlw\t#^x8000, r0"),
 ("CVTLW FFFF8000: fits, N", "cvtlw\t#^xFFFF8000, r0"),
]
out = []
out.append("""; t28_acb - ACBB, ACBW, ACBL: the index is added to at the operand's size
; (N, Z, V from that add, C unchanged) and compared with the limit as signed
; numbers, the direction given by the sign of the addend. Then CVTLB, CVTWB,
; CVTBW, CVTLW (V when the value does not fit). ACBB is used by the
; Diagnostic Supervisor. For each case the log gets the PSL, A1 if the branch
; was taken (else A0) and the index; for the conversions the PSL and R0.
; Generated cases; the expected values come from the reference simulator.
;@ dump=8000:2 dump=18000:60
	.include "mmsetup.inc"
test:
""")
n = 0
for com, setup, ins in cases:
    lab = 'c%d' % n
    out.append('; %s' % com)
    for s in setup:
        out.append('\t' + s)
    out.append('\tbispsw\t#1')
    out.append('\t' + (ins % lab))
    out.append('\tmovpsl\t(r11)+')
    out.append('\tmovl\t#^xA0, (r11)+')
    out.append('\tbrb\t%sx' % lab)
    out.append('%s:\tmovpsl\t(r11)+' % lab)
    out.append('\tmovl\t#^xA1, (r11)+')
    if '(r1)' in ins:
        out.append('%sx:\tmovl\tr1, (r11)+' % lab)
    else:
        out.append('%sx:\tmovl\tr0, (r11)+' % lab)
    n += 1
for com, ins in cvt:
    out.append('; %s' % com)
    out.append('\tmovl\t#^x5A5A5A5A, r0')
    out.append('\tbispsw\t#^xF')
    out.append('\t' + ins)
    out.append('\tmovpsl\t(r11)+')
    out.append('\tmovl\tr0, (r11)+')
out.append('\thalt')
import sys
sys.stdout.write('\n'.join(out) + '\n')

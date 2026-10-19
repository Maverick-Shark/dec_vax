#!/usr/bin/env python3
# mk_t31.py - generates tests/mmu/t31_arith.s, the arithmetic trap cases:
#     python3 tests/mmu/gen/mk_t31.py > tests/mmu/t31_arith.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
import sys
cases = [
 # (comment, IV, C, setup lines, instruction, logged results)
 ("ADDL2 7FFFFFFF+1, IV: trap 1, after the sum is stored", 1, 0, ["movl\t#^x7FFFFFFF, r0"], "addl2\t#1, r0", ["r0"]),
 ("ADDL2 7FFFFFFF+1, IV clear: V, no trap", 0, 0, ["movl\t#^x7FFFFFFF, r0"], "addl2\t#1, r0", ["r0"]),
 ("ADDB3 7F+1 to memory, IV: the byte is stored, then the trap", 1, 0, ["movl\t#^xAAAAAAAA, @#S0+^x8000"], "addb3\t#^x7F, #1, @#S0+^x8000", ["@#S0+^x8000"]),
 ("ADDW2 7FFF+1, IV", 1, 0, ["movl\t#^x12347FFF, r0"], "addw2\t#1, r0", ["r0"]),
 ("SUBL3 80000000-1, IV", 1, 0, [], "subl3\t#1, #^x80000000, r0", ["r0"]),
 ("MNEGL 80000000, IV", 1, 0, [], "mnegl\t#^x80000000, r0", ["r0"]),
 ("MNEGB 80, IV", 1, 0, ["movl\t#-1, r0"], "mnegb\t#^x80, r0", ["r0"]),
 ("INCL 7FFFFFFF, IV", 1, 0, ["movl\t#^x7FFFFFFF, r0"], "incl\tr0", ["r0"]),
 ("DECW 8000, IV", 1, 0, ["movl\t#^x00008000, r0"], "decw\tr0", ["r0"]),
 ("MULL3 10000*10000, IV", 1, 0, [], "mull3\t#^x10000, #^x10000, r0", ["r0"]),
 ("MULB2 40*4, IV", 1, 0, ["movl\t#^x40, r0"], "mulb2\t#4, r0", ["r0"]),
 ("MULW3 -2*3FFF: fits, IV", 1, 0, [], "mulw3\t#-2, #^x3FFF, r0", ["r0"]),
 ("DIVL3 by zero, IV clear: trap 2 anyway, quotient = dividend, V", 0, 0, ["movl\t#-1, r0"], "divl3\t#0, #1234, r0", ["r0"]),
 ("DIVB2 by zero, IV: trap 2", 1, 0, ["movl\t#^x12345678, r0"], "divb2\t#0, r0", ["r0"]),
 ("DIVW3 by zero to memory", 0, 0, ["movl\t#^x55555555, @#S0+^x8004"], "divw3\t#0, #-5, @#S0+^x8004", ["@#S0+^x8004"]),
 ("DIVL3 80000000/-1, IV: trap 1, quotient = dividend", 1, 0, [], "divl3\t#-1, #^x80000000, r0", ["r0"]),
 ("DIVB3 80/-1, IV clear: V, no trap", 0, 0, ["clrl\tr0"], "divb3\t#-1, #^x80, r0", ["r0"]),
 ("DIVL3 -7/2 = -3, IV", 1, 0, [], "divl3\t#2, #-7, r0", ["r0"]),
 ("EDIV by zero, IV clear: trap 2, quotient = low dividend, remainder 0", 0, 0, ["movl\t#^x11111111, r0", "movl\t#^x22222222, r1", "movl\t#-1, r2", "movl\t#-1, r3"], "ediv\t#0, r0, r2, r3", ["r2", "r3"]),
 ("EDIV overflow, IV: trap 1", 1, 0, ["movl\t#^x11111111, r0", "movl\t#^x22222222, r1"], "ediv\t#2, r0, r2, r3", ["r2", "r3"]),
 ("EDIV -100/7, IV", 1, 0, ["movl\t#-100, r0", "movl\t#-1, r1"], "ediv\t#7, r0, r2, r3", ["r2", "r3"]),
 ("ASHL 1 of 40000000: V (the sign changes in the last shift), IV", 1, 0, [], "ashl\t#1, #^x40000000, r0", ["r0"]),
 ("ASHL 2 of 3FFFFFFF: V", 0, 0, [], "ashl\t#2, #^x3FFFFFFF, r0", ["r0"]),
 ("ASHL 31 of -1: no V, IV", 1, 0, [], "ashl\t#31, #-1, r0", ["r0"]),
 ("ASHL 32 of 1: 0, V", 0, 0, [], "ashl\t#32, #1, r0", ["r0"]),
 ("ASHL 100 of 0: no V, IV", 1, 0, [], "ashl\t#100, #0, r0", ["r0"]),
 ("ASHL 127 of -1: V, IV", 1, 0, [], "ashl\t#127, #-1, r0", ["r0"]),
 ("ASHL -1 of -5: -3", 1, 0, [], "ashl\t#-1, #-5, r0", ["r0"]),
 ("ASHL -40 of -5: -1", 1, 0, [], "ashl\t#-40, #-5, r0", ["r0"]),
 ("ASHL -128 of 7FFFFFFF: 0", 1, 0, [], "ashl\t#-128, #^x7FFFFFFF, r0", ["r0"]),
 ("ASHQ 1 of 40000000'00000000: V, IV", 1, 0, ["clrl\tr2", "movl\t#^x40000000, r3"], "ashq\t#1, r2, r0", ["r0", "r1"]),
 ("ASHQ 63 of 1: V", 0, 0, ["movl\t#1, r2", "clrl\tr3"], "ashq\t#63, r2, r0", ["r0", "r1"]),
 ("ASHQ 3 of FFFFFFFF'F0000000: no V, IV", 1, 0, ["movl\t#^xF0000000, r2", "movl\t#-1, r3"], "ashq\t#3, r2, r0", ["r0", "r1"]),
 ("ASHQ -63 of 80000000'00000000: -1", 0, 0, ["clrl\tr2", "movl\t#^x80000000, r3"], "ashq\t#-63, r2, r0", ["r0", "r1"]),
 ("CVTLB 128, IV: trap 1", 1, 0, [], "cvtlb\t#128, r0", ["r0"]),
 ("CVTLW -32769, IV", 1, 0, [], "cvtlw\t#-32769, r0", ["r0"]),
 ("CVTWB 100, IV", 1, 0, [], "cvtwb\t#^x100, r0", ["r0"]),
 ("ADWC 80000000+FFFFFFFF+C: no overflow (the first add's is undone), IV", 1, 1, ["movl\t#^x80000000, r0"], "adwc\t#^xFFFFFFFF, r0", ["r0"]),
 ("ADWC 7FFFFFFF+0+C: V, IV", 1, 1, ["movl\t#^x7FFFFFFF, r0"], "adwc\t#0, r0", ["r0"]),
 ("ADWC 1+FFFFFFFF: C, Z, no V", 1, 0, ["movl\t#1, r0"], "adwc\t#-1, r0", ["r0"]),
 ("SBWC 80000000-0-C: V, IV", 1, 1, ["movl\t#^x80000000, r0"], "sbwc\t#0, r0", ["r0"]),
 ("SBWC 7FFFFFFF-FFFFFFFF-C: no overflow, IV", 1, 1, ["movl\t#^x7FFFFFFF, r0"], "sbwc\t#-1, r0", ["r0"]),
 ("SBWC 0-0-C: -1, C, N", 1, 1, ["clrl\tr0"], "sbwc\t#0, r0", ["r0"]),
]
branches = [
 ("AOBLSS 7FFFFFFF+1 < 5: V, IV: trap 1 after the branch (PC = target)", 1, ["movl\t#^x7FFFFFFF, r0"], "aoblss\t#5, r0, %s"),
 ("AOBLEQ -1+1 = 0 <= 0: branch, no V", 1, ["movl\t#-1, r0"], "aobleq\t#0, r0, %s"),
 ("AOBLEQ 7FFFFFFF+1 <= 7FFFFFFF: branch, V (IV clear)", 0, ["movl\t#^x7FFFFFFF, r0"], "aobleq\t#^x7FFFFFFF, r0, %s"),
 ("AOBLSS 5+1 < 80000000: no", 0, ["movl\t#5, r0"], "aoblss\t#^x80000000, r0, %s"),
 ("SOBGTR 80000001-1 = 80000000: not > 0, no branch", 1, ["movl\t#^x80000001, r0"], "sobgtr\tr0, %s"),
 ("SOBGTR 80000000-1: V, IV, branch", 1, ["movl\t#^x80000000, r0"], "sobgtr\tr0, %s"),
 ("SOBGEQ 0-1: no branch", 1, ["clrl\tr0"], "sobgeq\tr0, %s"),
 ("SOBGEQ 80000000-1: V, IV, branch", 1, ["movl\t#^x80000000, r0"], "sobgeq\tr0, %s"),
 ("ACBL 7FFFFFFF+1, IV: trap after the branch", 1, ["movl\t#^x7FFFFFFF, r0"], "acbl\t#^x7FFFFFFF, #1, r0, %s"),
 ("ACBB 7F+1, IV", 1, ["movl\t#^x7F, r0"], "acbb\t#^x7F, #1, r0, %s"),
]
o = []
o.append("""; t31_arith - arithmetic traps (SCB 34, SRM 5.x): integer overflow (type 1,
; when PSL<IV> is set), integer divide by zero (2, always), taken after the
; instruction has stored its results, PC of the next instruction (the branch
; target for AOBxxx, SOBxxx, ACBx). The results and condition codes of the
; overflowing instructions (DIVx and EDIV by zero, ASHL and ASHQ, ADWC and
; SBWC, AOBxxx, SOBxxx). Then PSL<IV> through the CALLx entry mask and RET,
; and the reserved operand faults of CALLx (mask<13:12>) and RET (saved
; PSW<15:8>). The trap handler logs 34, the type code, PC, PSL; each case
; logs the PSL and its results. Generated; the expected values come from
; the reference simulator.
;@ dump=8000:2 dump=18000:180
	.include "mmsetup.inc"
test:
	movl	#S0+arith_h, @#^x34
""")
n = 0
for com, iv, c, setup, ins, res in cases:
    o.append('; %s' % com)
    for s in setup:
        o.append('\t' + s)
    o.append('\tbicpsw\t#^xFF')
    if iv or c:
        o.append('\tbispsw\t#^x%X' % ((0x20 if iv else 0) | (1 if c else 0)))
    o.append('\t' + ins)
    o.append('\tmovpsl\t(r11)+')
    for r in res:
        o.append('\tmovl\t%s, (r11)+' % r)
    n += 1
for com, iv, setup, ins in branches:
    lab = 'b%d' % n
    o.append('; %s' % com)
    for s in setup:
        o.append('\t' + s)
    o.append('\tbicpsw\t#^xFF')
    if iv:
        o.append('\tbispsw\t#^x20')
    o.append('\t' + (ins % lab))
    o.append('\tmovpsl\t(r11)+')
    o.append('\tmovl\t#^xA0, (r11)+')
    o.append('\tbrb\t%sx' % lab)
    o.append('%s:\tmovpsl\t(r11)+' % lab)
    o.append('\tmovl\t#^xA1, (r11)+')
    o.append('%sx:\tmovl\tr0, (r11)+' % lab)
    n += 1
o.append("""; CALLS to a procedure whose entry mask sets IV: its overflow traps; RET
; gives the caller its PSW back (DV and IV clear): no trap after it
	bicpsw	#^xFF
	calls	#0, proc_iv
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0
	movpsl	(r11)+
; and the other way round: IV and DV set, a procedure with neither
	bispsw	#^xA0
	calls	#0, proc_noiv
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0
	movpsl	(r11)+
	bicpsw	#^xFF
; CALLG with entry mask bit 12 set: reserved operand fault, nothing pushed
	movl	sp, r6
	movab	callg_back, r8
	movl	#S0+fix_skip, r10
	callg	@#S0+^x8000, proc_mbz
callg_back:
	clrl	r10
	subl3	sp, r6, (r11)+			; 0: the stack is as before
; RET with saved PSW<8> set: reserved operand fault at the RET
	movab	ret_fix, r8
	movl	#S0+fix_skip, r10
	calls	#0, proc_badret
	clrl	r10
	movpsl	(r11)+
	subl3	sp, r6, (r11)+
	halt

	.align	4
arith_h:
	movl	#^x34, (r11)+
	movl	(sp)+, (r11)+			; type code
	movl	(sp), (r11)+			; PC
	movl	4(sp), (r11)+			; PSL
	rei

proc_iv:
	.word	^x4000				; IV
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0				; trap 1
	ret
proc_noiv:
	.word	0
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0				; V, no trap
	ret
proc_mbz:
	.word	^x1000
	halt
proc_badret:
	.word	^x0004				; saves R2
	bisl2	#^x100, 4(fp)			; saved PSW<8>
	ret					; reserved operand
ret_fix:
	bicl2	#^x100, 4(fp)
	ret
""")
sys.stdout.write('\n'.join(o) + '\n')

#!/usr/bin/env python3
# mk_t29.py - generates tests/mmu/t29_resad.s, the reserved addressing mode cases:
#     python3 tests/mmu/gen/mk_t29.py > tests/mmu/t29_resad.s
# The expected values are not in the test: run.py compares them with the
# reference simulator's.
# (comment, bytes of the instruction, faults?)
cases = [
 ("MOVL R0, S^#3: literal destination", "^xD0, ^x50, ^x03", 1),
 ("INCL S^#1: literal modify operand", "^xD6, ^x01", 1),
 ("ADDL3 R0, R1, S^#2: literal destination", "^xC1, ^x50, ^x51, ^x02", 1),
 ("MOVAB S^#1, R1: literal address operand", "^x9E, ^x01, ^x51", 1),
 ("EXTZV #0, #4, S^#5, R0: literal field base", "^xEF, ^x00, ^x04, ^x05, ^x50", 1),
 ("MOVAB R0, R1: register address operand", "^x9E, ^x50, ^x51", 1),
 ("JMP R0: register address operand", "^x17, ^x50", 1),
 ("MOVL PC, R0: PC as a register", "^xD0, ^x5F, ^x50", 1),
 ("MOVL R0, PC: PC as a register destination", "^xD0, ^x50, ^x5F", 1),
 ("MOVL (PC), R0: register deferred PC", "^xD0, ^x6F, ^x50", 1),
 ("MOVL -(PC), R0: autodecrement PC", "^xD0, ^x7F, ^x50", 1),
 ("MOVL (R1)+, (PC): the (R1)+ is undone", "^xD0, ^x81, ^x6F", 1),
 ("MOVL R1[PC], R0: PC as the index register", "^xD0, ^x4F, ^x51, ^x50", 1),
 ("MOVL R1[R2], R0: register base", "^xD0, ^x42, ^x51, ^x50", 1),
 ("MOVL S^#1[R2], R0: literal base", "^xD0, ^x42, ^x01, ^x50", 1),
 ("MOVL [R3][R2], R0: index base", "^xD0, ^x42, ^x43, ^x61, ^x50", 1),
 ("MOVL (PC)[R2], R0: register deferred PC base", "^xD0, ^x42, ^x6F, ^x50", 1),
 ("MOVQ R0, SP: quadword in SP", "^x7D, ^x50, ^x5E", 1),
 ("CLRQ SP", "^x7C, ^x5E", 1),
 ("MOVL (R1)[R2], R0: legal", "^xD0, ^x42, ^x61, ^x50", 0),
 ("BBS #1, R4, .+3: register field base, legal", "^xE0, ^x01, ^x54, ^x00", 0),
 ("MOVZBL #^x7F[R2], R0: immediate base, legal on the 8600", "^x9A, ^x42, ^x8F, ^x7F, ^x50", 0),
]
out = ["""; t29_resad - reserved addressing mode faults (SCB 1C), with the cases
; the SRM leaves UNPREDICTABLE, decided for the 8600 this way: a literal
; for anything but a read operand, a register for an address operand, PC as
; a register or with register deferred, autodecrement or as an index
; register, a literal, register or index base for index mode, a quadword in
; SP. A fault leaves the PC at the instruction and undoes the autoincrement
; of an earlier operand. Found with EVKAE test 2. The instructions are given
; as bytes (the assembler would not make most of them). For each case the
; log gets 1C1C1C1C and the PC if it faulted, else 600D.
;@ dump=18000:40
	.include "mmsetup.inc"
test:
	movl	#S0+resad_h, @#^x1C
	clrl	r7
	movl	#S0+^x8000, r1
	movl	#4, r2
	movl	#^x5555AAAA, @#S0+^x8000
	movl	#^x12345678, @#S0+^x8010
	movl	#2, r4
"""]
for i, (com, b, flt) in enumerate(cases):
    out.append('; %s' % com)
    out.append('\tmovab\tz%d, r8' % i)
    out.append('c%d:\t.byte\t%s' % (i, b))
    out.append('\tmovl\t#^x600D, (r11)+')
    out.append('z%d:' % i)
out.append("""	movl	r0, (r11)+
	movl	r1, (r11)+
	halt
	.align	4
resad_h:
	incl	r7
	movl	#^x1C1C1C1C, (r11)+
	movl	(sp), (r11)+			; PC: the faulting instruction
	movl	r8, (sp)			; resume after it
	rei
""")
import sys
sys.stdout.write('\n'.join(out))

; t14_movcflt - MOVC3/MOVC5 that fault part way: the frame has PSL<FPD> set
; and the PC of the MOVC; after the fix-up the instruction resumes (no
; operand decode) and finishes. The overlapping backward move faults after
; it has overwritten part of its own source, so only a resume gives the
; right result (a restart from the beginning would copy changed bytes).
;@ dump=18000:14 dump=89F0:8 dump=9BF8:8 page=18004,18018
;@ mask=1800C:FFFFFFF0,18020:FFFFFFF0
; (the condition codes saved with PSL<FPD> are UNPREDICTABLE, SRM 5.6)
	.include "mmsetup.inc"
test:
	movl	#S0+^x9A00, r6			; page 4D: source data 1, 2, ...
	movl	#1, r0
fill:	movb	r0, (r6)+
	aobleq	#^x40, r0, fill
	movl	#S0+fix_valid, r10
; forward: destination 89F8 crosses into page 45, which is invalid
	bicl2	#PTE_V, @#S0+SPT+<^x45*4>
	mtpr	#S0+^x8A00, #TBIS
	movc3	#^x10, @#S0+^x9A00, @#S0+^x89F8
	movl	r1, r7
	movl	r3, r8
; backward, overlapping: 9BFC..9C0B -> 9C04..9C13, page 4D (9BFC..9BFF)
; invalid: the fault comes on the 13th byte, after bytes 9C08..9C0B of the
; source have been overwritten
	movl	#^x04030201, @#S0+^x9BFC
	movl	#^x08070605, @#S0+^x9C00
	movl	#^x0C0B0A09, @#S0+^x9C04
	movl	#^x100F0E0D, @#S0+^x9C08
	bicl2	#PTE_V, @#S0+SPT+<^x4D*4>
	mtpr	#S0+^x9A00, #TBIS
	movc3	#16, @#S0+^x9BFC, @#S0+^x9C04
	halt

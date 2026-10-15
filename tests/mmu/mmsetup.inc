; mmsetup.inc - common set-up for the memory management tests.
;
; Included first by every t*.s test that runs with memory management on.
; Starts at physical 1000 with mapping off, builds the tables below, turns
; MAPEN on and jumps to "test" in system space (S0 page n is physical page n,
; so every label L is at S0+L as well).
;
; Physical memory:
;   00000000  SCB (SCBB = 0); vectors not set below go to "unexp"
;   00001000  this code, then the test
;   00008000  data pages for the tests (pages 40-5F)
;   0000E000  interrupt stack (top), 0000F000 kernel stack (top)
;   00010000  system page table: S0 pages 0-FF -> physical 0-FF, KW, valid
;   00012000  P0 page table:     P0 pages 0-FF -> physical 0-FF, UW, valid
;   00014000  P1 page table:     P1 pages 1FFF00-1FFFFF -> physical 100-1FF, UW
;   00018000  fault log, written by the handlers (R11 points into it)
;
; Handlers: memory management faults (SCB 20, 24) log 5 longwords at (R11)+:
; parameter, virtual address, PC, PSL of the frame, and the PSL the handler
; runs with; then call the fix-up routine whose address is in R10 (if R10 is
; not zero), which may change page tables or the saved PC at 4(SP); REI.
; Kernel stack not valid (SCB 08) and reserved operand (SCB 18) log a marker,
; PC and PSL and do the same. Anything else: R9 = 0BAD, HALT.

S0	= ^x80000000
SPT	= ^x10000
P0PT	= ^x12000
P1PT	= ^x14000
LOG	= ^x18000
PTE_V	= ^x80000000
PTE_M	= ^x04000000
PR_NA	= 0
PR_KW	= ^x10000000
PR_KR	= ^x18000000
PR_UW	= ^x20000000
PR_UR	= ^x78000000
SBR	= ^xC
SLR	= ^xD
P0BR	= 8
P0LR	= 9
P1BR	= ^xA
P1LR	= ^xB
SCBB	= ^x11
MAPEN	= ^x38
TBIA	= ^x39
TBIS	= ^x3A
TBCHK	= ^x3F
KSP	= 0
USP	= 3
ISP	= 4

	.org	^x1000
start:	movl	#S0+^xE000, sp		; on the interrupt stack (PSL<IS>)
	clrl	r0
	movl	#S0+unexp, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movl	#S0+mmflt_h, @#^x20	; access-control violation
	movl	#S0+mmflt_h, @#^x24	; translation not valid
	movl	#S0+resop_h, @#^x18	; reserved operand
	movl	#S0+ksnv_h+1, @#^x08	; kernel stack not valid: interrupt stack
	mtpr	#0, #SCBB
; system page table
	movl	#SPT, r0
	movl	#PTE_V+PR_KW, r1
sptfill:
	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #SPT+^x400
	blss	sptfill
; P0 page table
	movl	#P0PT, r0
	movl	#PTE_V+PR_UW, r1
p0fill:
	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #P0PT+^x400
	blss	p0fill
; P1 page table: the last 100 pages of P1 (P1LR = 1FFF00), on physical 100-1FF
	movl	#P1PT, r0
	movl	#PTE_V+PR_UW+^x100, r1
p1fill:
	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #P1PT+^x400
	blss	p1fill
	mtpr	#SPT, #SBR
	mtpr	#^x100, #SLR
	mtpr	#S0+P0PT, #P0BR
	mtpr	#^x100, #P0LR
	mtpr	#S0+P1PT-<^x1FFF00*4>, #P1BR
	mtpr	#^x1FFF00, #P1LR
	mtpr	#S0+^xF000, #KSP
	mtpr	#0, #TBIA
	mtpr	#1, #MAPEN
	jmp	@#S0+s0start
s0start:
	movl	#S0+LOG, r11
	clrl	r10
	clrl	r9
	jmp	@#S0+test

; memory management fault: log parameter, VA, PC, PSL, handler PSL
	.align	4
mmflt_h:
	movl	(sp)+, (r11)+
	movl	(sp)+, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movpsl	(r11)+
	tstl	r10
	beql	mmflt_ret
	jsb	(r10)
mmflt_ret:
	rei

; reserved operand: marker, PC, PSL
	.align	4
resop_h:
	movl	#^x5E5E0018, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movpsl	(r11)+
	tstl	r10
	beql	resop_ret
	jsb	(r10)
resop_ret:
	rei

; kernel stack not valid (on the interrupt stack): marker, PC, PSL
	.align	4
ksnv_h:
	movl	#^x5E5E0008, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movpsl	(r11)+
	halt

	.align	4
unexp:	movl	#^xBAD, r9
	halt

; fix-up routines for the tests
; skip: resume at the address in R8 (the faulting instruction is abandoned)
fix_skip:
	movl	r8, 4(sp)
	rsb

; valid: make the S0 page of the logged fault address valid again (no TBIS:
; the TB never holds invalid PTEs)
fix_valid:
	pushl	r0
	movl	-16(r11), r0
	extzv	#9, #21, r0, r0
	bisl2	#PTE_V, @#S0+SPT[r0]
	movl	(sp)+, r0
	rsb

; kw: give the S0 page of the logged fault address protection KW, valid
fix_kw:
	pushl	r0
	movl	-16(r11), r0
	extzv	#9, #21, r0, r0
	bicl2	#^x78000000, @#S0+SPT[r0]
	bisl2	#PTE_V+PR_KW, @#S0+SPT[r0]
	ashl	#9, r0, r0
	bisl2	#S0, r0
	mtpr	r0, #TBIS
	movl	(sp)+, r0
	rsb


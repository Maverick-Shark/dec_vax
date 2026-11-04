; t49_mchk2 - a machine check while the VMS machine check handler has not
; finished with the previous one: EHSR<05> (VMS entered) is still set, and
; the error handling microcode does not call VMS again but halts the
; processor, code 5, "non-E-box double error" (DEC STD 032 table B-24;
; EK-8600S-MM-004 appendix K, EHSR), with the instruction rolled back.
;
; The first machine check's handler logs EHSR and returns without clearing
; it; the second reference that fails, an autoincrement read of
; non-existent memory, halts at its own PC with R2 as before it.
;@ noref
;@ halt=5
;@ board=skip
;@ expect=PC:1100,R2:02000000,R3:00000058,R14:0000E000
;@ rtl=18000:00000058,18004:00080020,18008:0000600D
LOG	= ^x18000
SCBB	= ^x11
EHSR	= ^x4A

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	mchk_h+1, @#^x04
	mtpr	#0, #SCBB
	movl	#LOG, r11
	movab	n1, r8
	movl	@#^x02000000, r0	; machine check, handled
	movl	#^x5A5A, (r11)+		; (skipped)
n1:	movl	#^x600D, (r11)+
	movl	#^x02000000, r2
	jmp	f2

	.org	^x1100
f2:	movl	(r2)+, r0		; the second one: halt 5 here
	movl	#^xBAD1, (r11)+
	halt

	.align	4
mchk_h:	movl	(sp)+, r3		; byte count
	movl	r3, (r11)+
	mfpr	#EHSR, (r11)+		; 00080020: vector 8, VMS entered
	addl2	r3, sp
	movl	r8, (sp)
	rei				; EHSR<05> left set

	.align	4
unexp:	movl	#^xBAD, r9
	halt

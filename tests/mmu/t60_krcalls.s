; t60_krcalls - code on a kernel read-only page (KR, as 4.3BSD maps its
; text): CALLS with a relative destination, JSB, BSBW, a push. Nothing may
; fault: the instruction stream is read, never written.
;@ dump=18000:A
	.include "mmsetup.inc"
test:
	bicl2	#^x78000000, @#S0+SPT+<^x30*4>	; page 30 (physical 6000): KR
	bisl2	#PR_KR, @#S0+SPT+<^x30*4>
	mtpr	#S0+^x6000, #TBIS
	movl	#S0+fix_kr, r10
	jmp	@#S0+kcode
fix_kr:					; the page KW again: the retry works
	bicl2	#^x78000000, @#S0+SPT+<^x30*4>
	bisl2	#PR_KW, @#S0+SPT+<^x30*4>
	mtpr	#S0+^x6000, #TBIS
	rsb

	.org	^x6000
kcode:	pushl	#7
	calls	#1, ksub		; relative destination
	movl	r0, r7
	jsb	ksub2
	bsbw	ksub2
	pushl	#3
	movl	(sp)+, r8
	halt
ksub:	.word	0
	movl	4(ap), r0
	ret
ksub2:	incl	r9
	rsb

; t68_wint_nop - addl2 #11,(sp), a modify operand in memory,
; then one instruction, all on a kernel read-only (KR) code page. Without the
; fix the fetch after the modify operand carries write intent and faults (ACV).
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
kcode:	pushl	#5
	addl2	#11, (sp)
	nop
	halt
ksub:	.word	0
	ret
ksub2:	rsb

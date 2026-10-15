; t20_chmprobe - CHMx probes the new mode's stack, at SP-1 and SP-12, for
; writing in the new mode before it pushes anything (SRM chapter 5, CHM).
; A stack the new mode cannot write, or an invalid one, is an access-control
; violation or translation-not-valid fault on the CHMx itself: parameter
; with the write bit, the probed address, and PC, PSL and SP as they were
; before the CHMx. The memory management handler of mmsetup logs each fault
; and resumes after the CHMx (fix_skip, R8).
;@ dump=18000:20
	.include "mmsetup.inc"
SSP	= 2
test:
	movl	#chms_h, @#^x48
	movl	#chmk_h, @#^x40
	bicl2	#PTE_V, @#S0+P0PT+<^x53*4>	; P0 page 53 (A600-A7FF): invalid
	mtpr	#0, #TBIA
	movl	#S0+fix_skip, r10
	mtpr	#^xB000, #USP
	mtpr	#S0+^x9000, #SSP		; (a) an S0 page, KW: supervisor
	pushl	#^x03C00000			;     cannot write it
	pushl	#user
	rei
user:	movab	u2, r8
	chms	#1				; (a) ACV at SSP-1
u2:	movl	#^xA800, r0
	chmk	#100				; kernel: SSP <- R0
	movab	u3, r8
	chms	#2				; (b) TNV at SSP-1 = A7FF
u3:	movl	#^xA804, r0
	chmk	#100
	movab	u4, r8
	chms	#3				; (c) SSP-1 fine, TNV at SSP-12 = A7F8
u4:	movl	#^xAC00, r0
	chmk	#100
	chms	#4				; (d) a valid stack: works
	chmk	#9				; the end
	halt					; not reached

	.align	4
chms_h:	movl	(sp)+, r7			; code
	movl	sp, r6
	rei
	.align	4
chmk_h:	cmpl	(sp), #9
	beql	done
	mtpr	r0, #SSP
	addl2	#4, sp
	rei
done:	halt

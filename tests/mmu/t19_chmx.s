; t19_chmx - CHMK, CHME, CHMS, CHMU (SRM chapter 5, CHM). From kernel mode
; all four stay in kernel mode but go through their own vectors (40, 44, 48,
; 4C); from user mode each goes to its own mode, on that mode's stack; CHMS
; from executive mode stays in executive mode. Every handler logs the vector,
; the frame (code, PC, PSL), the PSL it runs with and its SP, then REIs.
; The handlers and the E/S/U stacks are in P0 space (UW pages), so that every
; mode can reach them; R11 points at the log through P0 as well.
;@ dump=18000:4E
	.include "mmsetup.inc"
ESP	= 1
SSP	= 2
test:
	movl	#chmk_h, @#^x40
	movl	#chme_h, @#^x44
	movl	#chms_h, @#^x48
	movl	#chmu_h, @#^x4C
	movl	#LOG, r11			; the log, through P0
	mtpr	#^xA000, #ESP			; P0 pages 4F, 53, 57 (UW)
	mtpr	#^xA800, #SSP
	mtpr	#^xB000, #USP
	pushl	#^x001F0000			; to the kernel stack (CHMx on the
	pushab	kern				; interrupt stack halts the CPU)
	rei
kern:	chmk	#1				; kernel: all stay in kernel mode
	chme	#2
	chms	#3
	chmu	#-4
	pushl	#^x03C00000			; to user mode, in P0 space
	pushl	#user
	rei
user:	chmk	#5
	chme	#6
	chms	#7
	chmu	#^x7FFF
	chme	#10				; executive, which does a CHMS #11
	chmk	#9				; the kernel handler halts for code 9
	halt					; not reached

	.align	4
chmk_h:	movl	#^x40, r0
	brb	log
	.align	4
chme_h:	movl	#^x44, r0
	brb	log
	.align	4
chms_h:	movl	#^x48, r0
	brb	log
	.align	4
chmu_h:	movl	#^x4C, r0
log:	movl	r0, (r11)+
	movl	(sp), (r11)+			; code
	movl	4(sp), (r11)+			; PC
	movl	8(sp), (r11)+			; PSL
	movpsl	(r11)+
	movl	sp, (r11)+
	cmpl	(sp), #9
	beql	done
	cmpl	(sp), #10
	bneq	log2
	chms	#11				; from executive mode
log2:	addl2	#4, sp
	rei
done:	halt

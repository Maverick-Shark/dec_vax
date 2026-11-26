; t65_ldpks - LDPCTX on the kernel stack, as NetBSD's return from a soft
; interrupt does it (sys/arch/vax/vax/subr.S, softint_process: the soft
; interrupt's process gives the CPU back with MTPR PCBB, LDPCTX, REI on its
; own kernel stack). The SRM (6.4) leaves LDPCTX with PSL<IS> clear
; UNDEFINED; the reference simulator then leaves ISP alone and only takes
; the new process's kernel stack, and so does the core: SP goes into ISP
; only from the interrupt stack. A software interrupt on the interrupt
; stack afterwards shows where ISP is (R7: its SP, 8 below ISP).
;@ dump=1C000:18 dump=1C100:18
	.include "mmsetup.inc"
PCBB	= ^x10
IPL	= ^x12
SIRR	= ^x14
PCB_A	= ^x1C000
PCB_B	= ^x1C100
test:
	movl	#S0+sint_h+1, @#^x8C		; IPL 3 soft interrupt, interrupt stack
; PCBs: KSP, ESP, SSP, USP, R0-R13, PC, PSL, P0BR, P0LR, P1BR, P1LR
	movab	@#S0+PCB_A, r0
	movl	#S0+^xF000, (r0)+
	clrq	(r0)+
	clrl	(r0)+
	movl	#^xA0, r1
pa_r:	movl	r1, (r0)+
	aobleq	#^xAD, r1, pa_r
	movl	#S0+proc_a, (r0)+
	movl	#^x001F0000, (r0)+		; kernel mode, kernel stack, IPL 1F
	movl	#S0+P0PT, (r0)+
	movl	#^x04000100, (r0)+		; P0LR, ASTLVL 4
	movl	#S0+P1PT-<^x1FFF00*4>, (r0)+
	movl	#^x1FFF00, (r0)+
	movab	@#S0+PCB_B, r0
	movl	#S0+^xEC00, (r0)+
	clrq	(r0)+
	clrl	(r0)+
	movl	#^xB0, r1
pb_r:	movl	r1, (r0)+
	aobleq	#^xBD, r1, pb_r
	movl	#S0+proc_b, (r0)+
	movl	#^x001F0000, (r0)+
	movl	#S0+P0PT, (r0)+
	movl	#^x04000100, (r0)+
	movl	#S0+P1PT-<^x1FFF00*4>, (r0)+
	movl	#^x1FFF00, (r0)+
; from the interrupt stack (ISP = E000) to process A on its kernel stack
	mtpr	#PCB_A, #PCBB
	ldpctx
	rei
; process A, kernel stack at F000: hand over to process B as NetBSD does,
; with LDPCTX on the kernel stack
proc_a:	subl2	#^x40, sp			; something on A's kernel stack
	mtpr	#PCB_B, #PCBB
	ldpctx
	rei
; process B, kernel stack at EC00: ISP must still be E000
proc_b:	mfpr	#ISP, r6
	movl	sp, r8
	mtpr	#3, #SIRR
	mtpr	#0, #IPL			; the soft interrupt, on ISP
	movl	#^xBAD, r9			; not reached
	halt
	.align	4
sint_h:	movl	sp, r7				; ISP - 8
	movl	(sp), r10			; the PC it came from
	halt

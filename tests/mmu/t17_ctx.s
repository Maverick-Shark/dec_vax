; t17_ctx - LDPCTX/SVPCTX: two processes with their own P0 page tables
; (P0 page 40 is physical page 40 for A, physical page 200 for B), switched
; by a CHMK handler with SVPCTX, MTPR PCBB, LDPCTX, REI. A writes AAAA,
; B writes BBBB at the same virtual address, A reads its own value back.
;@ dump=8000:1 dump=40000:1 dump=1C000:18 dump=1C100:18
	.include "mmsetup.inc"
PCBB	= ^x10
PCB_A	= ^x1C000
PCB_B	= ^x1C100
P0PT_B	= ^x16000
test:
	movl	#S0+chmk_h, @#^x40
; B's P0 page table: pages 0-3F as A's (the code), 40-FF on physical 200+
	movl	#S0+P0PT_B, r0
	clrl	r1
p0b:	movl	#PTE_V+PR_UW, r2
	addl2	r1, r2
	cmpl	r1, #^x40
	blss	p0b_1
	addl2	#^x1C0, r2
p0b_1:	movl	r2, (r0)+
	aobleq	#^xFF, r1, p0b
; PCBs: KSP, ESP, SSP, USP, R0-R13, PC, PSL, P0BR, P0LR, P1BR, P1LR
	movab	@#S0+PCB_A, r0
	movl	#S0+^xF000, (r0)+
	clrq	(r0)+
	movl	#^x80000000, (r0)+
	movl	#^xA0, r1
pa_r:	movl	r1, (r0)+
	aobleq	#^xAD, r1, pa_r
	movl	#user_a, (r0)+
	movl	#^x03C00000, (r0)+
	movl	#S0+P0PT, (r0)+
	movl	#^x04000100, (r0)+		; P0LR, ASTLVL 4
	movl	#S0+P1PT-<^x1FFF00*4>, (r0)+
	movl	#^x1FFF00, (r0)+
	movab	@#S0+PCB_B, r0
	movl	#S0+^xEC00, (r0)+
	clrq	(r0)+
	movl	#^x7FFFFF00, (r0)+
	movl	#^xB0, r1
pb_r:	movl	r1, (r0)+
	aobleq	#^xBD, r1, pb_r
	movl	#user_b, (r0)+
	movl	#^x03C00000, (r0)+
	movl	#S0+P0PT_B, (r0)+
	movl	#^x04000100, (r0)+		; P0LR, ASTLVL 4
	movl	#S0+P1PT-<^x1FFF00*4>, (r0)+
	movl	#^x1FFF00, (r0)+
	mtpr	#PCB_A, #PCBB
	ldpctx
	rei

user_a:	movl	#^xAAAA, @#^x8000
	chmk	#1
	movl	@#^x8000, r5
	chmk	#3
	halt

user_b:	movl	#^xBBBB, @#^x8000
	chmk	#2
	halt

	.align	4
chmk_h:	cmpl	(sp)+, #3
	beql	chmk_3
	svpctx
	mfpr	#PCBB, r0
	cmpl	r0, #PCB_A
	beql	to_b
	mtpr	#PCB_A, #PCBB
	brb	resume
to_b:	mtpr	#PCB_B, #PCBB
resume:	ldpctx
	rei
chmk_3:	halt

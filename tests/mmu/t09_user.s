; t09_user - faults from user mode: the frame PSL shows user mode, the
; handler runs in kernel mode on the kernel stack with PRV_MOD = user; a
; fault on a user stack push leaves SP alone; CHMK back to kernel.
;@ dump=18000:14 dump=3FDF8:2 dump=3FFF8:2 dump=143F8:2
	.include "mmsetup.inc"
test:
	movl	#S0+chmk_h, @#^x40		; CHMK
	bicl2	#PTE_V, @#S0+P1PT+<^xFE*4>	; P1 page 1FFFFE invalid
	mtpr	#^x80000000, #USP		; user stack: top of P1
	pushl	#^x03C00000			; PSL: user mode, previous user
	pushl	#user				; P0 address = physical address
	rei
user:	movl	#1, r1
	pushl	#^x55				; page 1FFFFF: fine
	movab	user_2, r8
	movl	#S0+fix_skip, r10		; (read by the kernel handler)
	movl	@#S0+^x8000, r2			; KW page: ACV
user_2:	movl	#S0+fix_p1, r10
	movl	#^x7FFFFE00, sp
	movl	sp, r3
	pushl	#^x66				; page 1FFFFE: TNV, SP unchanged
	movl	sp, r4
	movpsl	r5
	chmk	#7
	halt					; not reached
fix_p1:	bisl2	#PTE_V, @#S0+P1PT+<^xFE*4>
	rsb
	.align	4
chmk_h:	movl	#^x5E5E0040, (r11)+
	movl	(sp), (r11)+			; code
	movl	4(sp), (r11)+			; PC
	movl	8(sp), (r11)+			; PSL
	movpsl	(r11)+
	mfpr	#USP, r6
	movl	sp, r7
	halt

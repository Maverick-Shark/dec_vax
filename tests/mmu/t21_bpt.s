; t21_bpt - BPT (SCB 2C) and XFC (SCB 14) are faults with PC at the opcode;
; an opcode the VAX does not define (57) and HALT outside kernel mode are
; reserved instruction faults (SCB 10), PC at the opcode, nothing changed;
; HALT in kernel mode halts the processor (8600 halt code 6). Each handler
; logs its vector, PC and PSL, and steps over the one-byte opcode.
;@ dump=18000:18 halt=6
	.include "mmsetup.inc"
test:
	movl	#S0+bpt_h, @#^x2C
	movl	#S0+xfc_h, @#^x14
	movl	#S0+rsvi_h, @#^x10
	movl	#S0+chmk_h, @#^x40
	movl	#7, r5
	bpt
	movl	#8, r6
	xfc
	movl	(sp), r7			; the stack is as before
	movl	#^x80000000, @#S0+^x9000
	movl	#S0+^x9000, r1
	.byte	^x57				; reserved opcode
	mtpr	#^xB000, #USP
	pushl	#^x03C00000
	pushl	#user
	rei
user:	.byte	0				; HALT, privileged here: reserved
					; instruction (not a halt the board
					; suite should turn into its exit)
	movl	#9, r8
	chmk	#0				; back to kernel mode
	.align	4
bpt_h:	movl	#^x2C, (r11)+
	brb	log
	.align	4
xfc_h:	movl	#^x14, (r11)+
	brb	log
	.align	4
rsvi_h:	movl	#^x10, (r11)+
log:	movl	(sp), (r11)+			; PC
	movl	4(sp), (r11)+			; PSL
	incl	(sp)				; over the opcode
	rei
	.align	4
chmk_h:	halt					; in kernel mode: halt code 6

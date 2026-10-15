; t18_rei - REI checks (SRM 5.7): popped PSLs that are inconsistent or
; more privileged give a reserved operand fault at the REI, with the stack
; pointer as before; REI to user mode with ASTLVL = user requests the IPL 2
; software interrupt (AST delivery); MTPR in user mode is a reserved
; instruction fault (SCB 10).
;@ dump=18000:1C
	.include "mmsetup.inc"
ASTLVL	= ^x13
test:
	movl	#S0+rsvi_h, @#^x10
	movl	#S0+ast_h, @#^x88
	movl	#S0+fix_skip, r10
	movab	re1, r8
	pushl	#^x041F0001			; IS with ... fine, but MBZ<8>
	bisl2	#^x100, (sp)
	pushl	#S0+re1
	rei					; MBZ bit: reserved operand
re1:	movab	re2, r8
	movl	sp, r6
	pushl	#^x04000000			; IS with IPL 0
	pushl	#S0+re2
	rei
re2:	movab	re3, r8
	movl	r6, sp
	pushl	#^x03C10000			; user mode with IPL 1
	pushl	#S0+re3
	rei
re3:	movab	re3b, r8
	movl	r6, sp
	pushl	#^x00C10000			; kernel, IPL 1: fine
	pushl	#S0+re3b
	rei
re3b:	movab	re4, r8
	movl	r6, sp
	pushl	#^x03000000			; PRV kernel < CUR user
	pushl	#S0+re4
	rei
re4:	movl	r6, sp
	mtpr	#^x80000000, #USP
	mtpr	#3, #ASTLVL			; AST pending for user mode
	pushl	#^x03C00000
	pushl	#user
	rei					; IPL 2 interrupt requested
user:	movl	#7, r7				; the AST interrupt comes here first
	mtpr	#0, #ASTLVL			; privileged: reserved instruction
	halt
	.align	4
ast_h:	movl	#^x5E5E0088, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movpsl	(r11)+
	mtpr	#4, #ASTLVL
	rei
	.align	4
rsvi_h:	movl	#^x5E5E0010, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movpsl	(r11)+
	halt

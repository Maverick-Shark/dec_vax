; t32_trace - trace (SRM 5.x): at the start of each instruction PSL<TP> set
; takes the trace fault (SCB 28, PC of that instruction, TP clear in the
; saved PSL), else TP <- PSL<T>. So an instruction that sets T is not
; traced, the one after it is; one that clears T still is. Traps (the
; arithmetic trap, CHMK) and interrupts come first and save TP set; faults
; (BPT, reserved operand, translation not valid) clear it, so the faulting
; instruction is traced once, when it completes. REI sets TP if it was set
; or the saved PSL has it (REI is traced); CALLS saves the PSW with T clear
; and RET restores it. The handlers log their vector, the PC and the PSL of
; the frame (BPT and CHMK steps over the instruction, the trace handler stops
; tracing when R7 counts down to zero).
;@ dump=18000:80
	.include "mmsetup.inc"
IPL	= ^x12
SIRR	= ^x14
test:
	movl	#S0+trace_h, @#^x28
	movl	#S0+arith_h, @#^x34
	movl	#S0+bpt_h, @#^x2C
	movl	#S0+bpt_h, @#^x14		; XFC
	movl	#S0+chmk_h, @#^x40
	movl	#S0+sw3_h, @#^x8C
	movl	#100, r7
; A: the instruction after BISPSW is traced, BICPSW too
	bispsw	#^x10
	movl	#1, r0
	movl	#2, r1
	bicpsw	#^x10
	movl	#3, r2
; B: the overflow trap first (saved TP set), then the trace fault
	movl	#^x7FFFFFFF, r0
	bispsw	#^x30
	addl2	#1, r0
	bicpsw	#^x30
; C: BPT and XFC are faults: TP clear when they are taken, the handler steps
; over them, the next instruction is traced
	bispsw	#^x10
	bpt
	movl	#4, r3
	xfc
	bicpsw	#^x10
; D: reserved operand fault (BISPSW with PSW<8>): not traced, skipped to R8
	movab	resop_back, r8
	movl	#S0+fix_skip, r10
	bispsw	#^x10
	bispsw	#^x100
	nop
resop_back:
	clrl	r10
	bicpsw	#^x10
; E: translation not valid on a traced instruction: the fault, then the
; trace after it completes
	bicl2	#PTE_V, @#S0+SPT+<^x40*4>
	mtpr	#S0+^x8000, #TBIS
	movl	#S0+fix_valid, r10
	bispsw	#^x10
	movl	@#S0+^x8000, r0
	bicpsw	#^x10
	clrl	r10
; F: a software interrupt taken after the instruction that lowers the IPL:
; it saves TP set, the trace fault comes when its handler returns
	mtpr	#3, #SIRR
	bispsw	#^x10
	mtpr	#2, #IPL
	mtpr	#^x1F, #IPL
	bicpsw	#^x10
; G: CALLS and RET with T set: the procedure is traced; RET restores the
; saved PSW, T clear, but RET itself is traced
	bispsw	#^x10
	calls	#0, proc
	movl	#5, r4
; H: REI to the kernel stack with T set in the new PSL: the first
; instruction there is traced; REI with T set is traced itself
	pushl	#^x001F0010
	pushab	kstk
	rei
kstk:	movl	#6, r5
; I: CHMK (on the kernel stack) is a trap: saved TP set, trace after its
; handler returns
	chmk	#7
	movl	#2, r7				; the trace handler stops tracing
	movl	#7, r6				; after two more trace faults
	movl	#8, r6
	movl	#9, r6
	halt

	.align	4
trace_h:
	movl	#^x28, (r11)+
	movl	(sp), (r11)+			; PC
	movl	4(sp), (r11)+			; PSL
	sobgtr	r7, trace_r
	bicl2	#^x10, 4(sp)			; stop tracing
	movl	#100, r7
trace_r:
	rei
	.align	4
arith_h:
	movl	#^x34, (r11)+
	movl	(sp)+, (r11)+			; type code
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei
	.align	4
bpt_h:	movl	#^x2C, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	incl	(sp)				; over the opcode
	rei
	.align	4
chmk_h:	movl	#^x40, (r11)+
	movl	(sp)+, (r11)+			; code
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei
	.align	4
sw3_h:	movl	#^x8C, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei

proc:	.word	0
	movl	#^xA, r8
	ret

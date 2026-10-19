; t38_tracemovc - trace with interrupts in the middle of MOVC3 and MOVC5. An
; interrupt that the CPU takes part way through an instruction (PSL<FPD>
; set in the frame, the PC at the instruction) clears PSL<TP> in the saved
; PSL, as a fault does (SRM 5.4.4, rule 3): after the REI the instruction
; completes and is traced once, with the PC of the next instruction. The
; reference simulator takes interrupts only between instructions; the trace
; handler's log, the PC and PSL of each trace fault, must be the same. Found
; with EVKAB test 134 ("MOVC3 with timer interrupts, T-bit trap"). The
; interrupt count (R9) and the count of the interrupts that saw PSL<FPD>
; (R10) are not compared.
;@ dump=18000:10 dump=1A000:4 dump=1AFF0:4 dump=1B7F0:4 dump=1CFF0:4
;@ dump=1D000:4 dump=1EFF0:4 ignore=R9,R10
	.include "mmsetup.inc"
ICCS	= ^x18
NICR	= ^x19
IPL	= ^x12
test:
	movl	#S0+clk_h, @#^xC0
	movl	#S0+trace_h, @#^x28
	clrl	r9
	clrl	r10
	mtpr	#-1000, #NICR			; every 1000 us (50000 clocks)
	mtpr	#^x51, #ICCS			; run, transfer, interrupt enable
	pushl	#^x10				; kernel stack, IPL 0, PSL<T>
	pushl	#S0+t38k
	rei
; forward, a fill, backward (the destination above the source, overlapping)
t38k:	movc3	#^x3000, @#S0+^x0000, @#S0+^x1A000
	movc5	#^x10, @#S0+^x1000, #^x5A, #^x2000, @#S0+^x1D000
	movc3	#^x1000, @#S0+^x1A000, @#S0+^x1A800
	bicpsw	#^x10				; traced as well
	mtpr	#^x1F, #IPL
	mtpr	#0, #ICCS
	halt
	.align	4
trace_h:
	movl	(sp), (r11)+			; PC: the next instruction
	movl	4(sp), (r11)+			; PSL: T set, TP and FPD clear
	rei
clk_h:	incl	r9
	bbc	#27, 4(sp), clk_1		; PSL<FPD> in the frame?
	incl	r10
clk_1:	mtpr	#^xC1, #ICCS			; clear the interrupt
	rei

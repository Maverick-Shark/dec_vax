; t70_intlvl_race - a hardware interrupt request that comes while the CPU
; starts a software interrupt. The interrupt microcode reads the requested
; level (savpsw<20:16>) more than once; with a live level, a software
; request at IPL 4 taken just before the interval clock's request (IPL 18)
; read IPL 4 the first time and "hardware" the second, read SBIA register
; 2008 0050, which does not exist, and halted with code 5 (VMS 4.6 and 7.3
; at boot, now and then). The window is a clock or two wide, so each pass
; requests IPL 4 by SIRR, starts the clock for 14-17 us, waits a different
; time (4096 different waits, every pass its own) and drops IPL to 0. Both
; handlers must run once per pass, whatever the order.
;@ dump=18000:4
;@ clocks=16000000
	.include "mmsetup.inc"
IPL	= ^x12
SIRR	= ^x14
ICCS	= ^x18
NICR	= ^x19
NPASS	= 4096
test:
	movl	#S0+tmr_h, @#^xC0
	movl	#S0+sw4_h, @#^x90
	clrl	r6				; software interrupts taken
	clrl	r7				; timer interrupts taken
	clrl	r5				; the pass
	pushl	#^x001F0000			; onto the kernel stack, IPL 1F
	pushab	pass				; (no REI back to the interrupt
	rei					; stack at IPL 0)
pass:	mtpr	#^x1F, #IPL
	mtpr	#4, #SIRR
	extzv	#8, #2, r5, r4			; 14-17 us
	mnegl	r4, r4
	subl2	#14, r4
	mtpr	r4, #NICR
	mtpr	#^x51, #ICCS			; RUN, IE, ICR <- NICR
	movl	#8, r4				; a fixed wait first
fix:	sobgtr	r4, fix
	extzv	#4, #2, r5, r4			; then 0-3 NOPs
	beql	movs
nops:	nop
	sobgtr	r4, nops
movs:	extzv	#6, #2, r5, r4			; 0-3 MOVLs
	beql	steps
movl1:	movl	r0, r0
	sobgtr	r4, movl1
steps:	extzv	#0, #4, r5, r4			; 0-15 loop steps
	beql	go
dly:	sobgtr	r4, dly
go:	mtpr	#0, #IPL
wait:	cmpl	r7, r6				; until the timer came too
	blss	wait
	incl	r5
	cmpl	r5, #NPASS
	blss	pass
	mtpr	#^x1F, #IPL
	clrl	r4
	halt
	.align	4
sw4_h:	incl	r6
	rei
	.align	4
tmr_h:	incl	r7
	mtpr	#^x80, #ICCS			; clear the request, stop
	rei

; xcommon.inc - shared by xwr.s and xrd.s: the machine, the RH780 at TR 8
; and RP07 unit 0, and a routine that generates the test data.
LOG	= ^x18000
MBA	= ^x20010000
SR	= MBA+^x08
VAR	= MBA+^x0C
BCR	= MBA+^x10
MAP	= MBA+^x800
D0	= MBA+^x400
CS1	= ^x00
DA	= ^x14
OF	= ^x24
DC	= ^x28
NBYTES	= 2048			; four sectors
DADDR	= ^x1400		; track 20, sector 0: LBA 1000

; R0 = address: NBYTES of data, LW = X, X = X * 69069 + 1 from 12345678
gen:	movl	#^x12345678, r1
	movl	#NBYTES/4, r2
gen1:	movl	r1, (r0)+
	mull2	#69069, r1
	incl	r1
	sobgtr	r2, gen1
	rsb

; R0 = first map register's page frame number: map registers 0-3
setup:	clrl	r2
setup1:	bisl3	#^x80000000, r0, @#MAP[r2]
	incl	r0
	aoblss	#4, r2, setup1
	movl	#D0, r10
	movl	#^x13, CS1(r10)		; pack acknowledge
	movl	#^x1000, OF(r10)	; 16-bit format
	clrl	DC(r10)
	movl	#DADDR, DA(r10)
	clrl	@#VAR
	movl	#-NBYTES, @#BCR
	rsb

; wait for the end of the transfer, log SR at LOG
wdt:	movl	#2000000, r1
wdt1:	tstl	@#SR
	bgeq	wdt2
	sobgtr	r1, wdt1
wdt2:	movl	@#SR, @#LOG
	rsb

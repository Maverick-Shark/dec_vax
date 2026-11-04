; xrd.s - reads four sectors at LBA 1000 of RP07 unit 0 and compares them
; with the data xwr.s writes. LOG: SR after the transfer (00002000), LOG+4:
; the longwords that differ (0), LOG+8: the first longword read.
	.org	^x1000
start:	movl	#^xE000, sp
	movl	#^x24000, r0
	jsb	gen			; what should be there
	movl	#^x110, r0		; read into 22000
	jsb	setup
	movl	#^x39, CS1(r10)		; read data
	jsb	wdt
	clrl	r5
	clrl	r0
cmp1:	cmpl	@#^x22000[r0], @#^x24000[r0]
	beql	cmp2
	incl	r5
cmp2:	aoblss	#NBYTES/4, r0, cmp1
	movl	r5, @#LOG+4
	movl	@#^x22000, @#LOG+8
	halt
	.include "xcommon.inc"

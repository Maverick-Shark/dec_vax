; xwr.s - writes four sectors of generated data at LBA 1000 of RP07 unit 0
; (the other half of the image exchange test, xrd.s, reads them back on the
; other machine). LOG: SR after the transfer (00002000).
	.org	^x1000
start:	movl	#^xE000, sp
	movl	#^x20000, r0
	jsb	gen
	movl	#^x100, r0		; 20000
	jsb	setup
	movl	#^x31, CS1(r10)		; write data
	jsb	wdt
	halt
	.include "xcommon.inc"

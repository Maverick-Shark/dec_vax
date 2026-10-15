; boot.s - the start of software/mmutest.bin. The OSD loads the file at 1000
; and starts it there; this copies the rest of the file (the runner and the
; tests, PLEN bytes, defined in payload.inc by mkboard.py) to 300000, out of
; the way of the tests, and jumps to it.

	.include "payload.inc"

	.org	^x1000
boot:	mtpr	#^x1F, #^x12		; IPL 1F
	mtpr	#0, #^x38		; mapping off
	movab	payload, r1
	movl	#^x300000, r3
	movl	#PLEN, r6
cp1:	cmpl	r6, #^x8000
	blequ	cp2
	movc3	#^x8000, (r1), (r3)	; R1, R3 advance
	subl2	#^x8000, r6
	brb	cp1
cp2:	movc3	r6, (r1), (r3)
	jmp	@#^x300000

	.align	16
payload:

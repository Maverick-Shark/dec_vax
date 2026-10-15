; basic harness test
;@ dump=8000:2
	.org	^x1000
start:	movl	#^x2000, sp
	movl	#1, r0
	addl3	r0, #2, r1
	movl	r1, @#^x8000
	movl	#^x12345678, @#^x8004
	halt

; t12_mtpr - MTPR/MFPR of the memory management registers: reserved
; operand checks (8600: P0BR/P1BR in S0 and aligned, lengths up to 2**21,
; physical addresses aligned), MFPR of write-only registers, registers
; above 7F; and the values read back.
;@ dump=18000:18
	.include "mmsetup.inc"
test:
	movl	#S0+fix_skip, r10
	movab	m1, r8
	mtpr	#^x00012000, #P0BR		; not S0: reserved operand
m1:	movab	m2, r8
	mtpr	#^x80012002, #P0BR		; not aligned
m2:	movab	m3, r8
	mtpr	#^x00200001, #P0LR		; longer than 2**21
m3:	movab	m4, r8
	mtpr	#^x10002, #SBR			; not aligned
m4:	movab	m5, r8
	mfpr	#TBIA, r1			; write only
m5:	movab	m6, r8
	mtpr	#0, #^x80			; no such register
m6:	movab	m7, r8
	mtpr	#7, #^x13			; ASTLVL 7
m7:	mtpr	#^xFF0000FF, #P0LR		; kept: <21:0>
	mfpr	#P0LR, r2
	mtpr	#^x100, #P0LR
	mfpr	#MAPEN, r3
	mfpr	#SBR, r4
	mfpr	#SLR, r5
	mfpr	#P1BR, r6
	mfpr	#P1LR, r7
	mfpr	#ISP, r9
	halt

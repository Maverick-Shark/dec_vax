; t27_ipr - the VAX 8600 internal processor registers that are not memory
; management ones (DEC STD 032 table B-25, simh vax860_abus.c): what reads
; back after writing all ones, and which register numbers do not exist
; (reserved operand fault): the 11/780 and 11/750 ones, the 8600 M-box and
; E-box ones that are not implemented, write-only ones for MFPR and read-only
; ones for MTPR. Found with EVKAE, which writes ACCS (no accelerator: the
; write is ignored and it reads as zero). The log gets the value read, or
; 5E5E5E5E for a reserved operand fault; R7 counts the faults.
;@ dump=18000:30
	.include "mmsetup.inc"
ACCS	= ^x28
PME	= ^x3D
CSWP	= ^x42
MDCTL	= ^x45
MERG	= ^x47
EHSR	= ^x4A
NICR	= ^x19
SISR	= ^x15
test:
	movl	#S0+resop_h2, @#^x18
	clrl	r7
; registers that keep (part of) what is written
	mtpr	#-1, #ACCS			; no accelerator: ignored
	mfpr	#ACCS, (r11)+			; 0
	mtpr	#-1, #PME			; bit 0
	mfpr	#PME, (r11)+
	mtpr	#0, #PME
	mtpr	#-1, #CSWP			; <3:0>
	mfpr	#CSWP, (r11)+
	mtpr	#-1, #MDCTL			; <14:13,11:8,3:0>
	mfpr	#MDCTL, (r11)+
	mtpr	#-1, #EHSR			; <5>
	mfpr	#EHSR, (r11)+
	mtpr	#0, #EHSR
	mtpr	#-1, #MERG			; ignored, reads as zero
	mfpr	#MERG, (r11)+
	mtpr	#^x12345678, #NICR		; reads back
	mfpr	#NICR, (r11)+
	mtpr	#^xFFFF, #SISR			; <15:1>, at IPL 1F nothing is taken
	mfpr	#SISR, (r11)+
	mtpr	#0, #SISR
	mfpr	#SISR, (r11)+
; MTPR to registers that do not exist or cannot be written
	movab	w1, r8
	mtpr	#0, #^x1A			; ICR: read only
	movl	#^x600D, (r11)+			; (skipped after a fault)
w1:	movab	w2, r8
	mtpr	#0, #^x21			; RXDB: read only
	movl	#^x600D, (r11)+
w2:	movab	w3, r8
	mtpr	#0, #^x25			; 11/750 CADR
	movl	#^x600D, (r11)+
w3:	movab	w4, r8
	mtpr	#0, #^x26			; 11/750 MCESR
	movl	#^x600D, (r11)+
w4:	movab	w5, r8
	mtpr	#0, #^x3E			; SID: read only
	movl	#^x600D, (r11)+
w5:	movab	w6, r8
	mtpr	#0, #^x43			; MDECC
	movl	#^x600D, (r11)+
w6:	movab	w7, r8
	mtpr	#0, #^x4E			; ESPA
	movl	#^x600D, (r11)+
w7:	movab	w8, r8
	mtpr	#0, #^x50			; above the last one, 4F
	movl	#^x600D, (r11)+
; MFPR of registers that do not exist or cannot be read
w8:	movab	q1, r8
	mfpr	#^x14, r0			; SIRR: write only
	movl	r0, (r11)+
q1:	movab	q2, r8
	mfpr	#^x23, r0			; TXDB: write only
	movl	r0, (r11)+
q2:	movab	q3, r8
	mfpr	#^x25, r0			; 11/750 CADR
	movl	r0, (r11)+
q3:	movab	q4, r8
	mfpr	#^x3A, r0			; TBIS: write only
	movl	r0, (r11)+
q4:	movab	q5, r8
	mfpr	#^x48, r0			; CRBT: write only
	movl	r0, (r11)+
q5:	movab	q6, r8
	mfpr	#^x4F, r0			; ESPD
	movl	r0, (r11)+
q6:	movab	q7, r8
	mfpr	#^x7F, r0			; no such register
	movl	r0, (r11)+
q7:	movl	#^xE0D, (r11)+
	halt
	.align	4
resop_h2:
	incl	r7
	movl	#^x5E5E5E5E, (r11)+
	movl	r8, (sp)			; resume after the faulting instruction
	rei

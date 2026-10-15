; board.inc - end of a test program in the board suite (software/mmutest.bin).
;
; tests/mmu/mkboard.py appends this to every test, after replacing each HALT
; of the test (and of mmsetup.inc) with a branch to "finish", and defines
; NEXP, the number of entries in the table of expected values.
;
; finish saves R0-R14 and the PSL as they are at the end of the test - the
; point where run.py compares simh and the RTL - turns memory management off
; and returns to the runner (runner.s, at 300008), which compares them and
; the memory the test names with what simh vax8600 gave for the same program.
; The comparison table (exptab) is filled in by mkboard.py:
;
;   .long  n                     number of entries, then n times:
;   .long  what, value, mask     what: FFFFFF00+n = Rn, FFFFFF0F = PSL,
;                                otherwise a physical address
;
; The branches into finish are PC-relative, so it is reached in whatever
; address space the test ends in (S0, P0, or physical with mapping off).

	.align	4
finish:	movpsl	sav+60			; first: the MOVLs below change the CCs
	movl	r0, sav
	movl	r1, sav+4
	movl	r2, sav+8
	movl	r3, sav+12
	movl	r4, sav+16
	movl	r5, sav+20
	movl	r6, sav+24
	movl	r7, sav+28
	movl	r8, sav+32
	movl	r9, sav+36
	movl	r10, sav+40
	movl	r11, sav+44
	movl	ap, sav+48
	movl	fp, sav+52
	movl	sp, sav+56
	mtpr	#^x1F, #^x12		; IPL 1F
	mtpr	#0, #^x38		; MAPEN off: physical addresses from here
	jmp	@#^x300008		; back to the runner

	.align	4
sav:	.blkl	16
exptab:	.long	NEXP
	.blkl	3*NEXP

#!/usr/bin/env python3
"""mk_t63.py - writes tests/mmu/t63_cmflow.s: PDP-11 compatibility mode
program control and tracing, checked against the reference simulator:

    python3 tests/mmu/gen/mk_t63.py > tests/mmu/t63_cmflow.s

  - every branch (BR, BNE ... BCS) with each of the 16 condition code
    patterns: a BPT where it goes on if not taken and one at its target,
    so the log says which (PC) and that the codes are kept (PSL); the
    longest displacements, +127 and -128 words
  - JMP with each addressing mode but register (the new PC is the
    operand's address; (Rn)+ does not affect it, JMP (PC)+ goes to the word
    after it)
  - JSR and RTS with PC and R5 as the link register, JSR R1,(R1)+ (the
    updated R1 is pushed), RTS SP
  - SOB counting down, with its longest displacement; MOV and ADD to PC
  - RTI and RTT: the PC and PSW<4:0> popped, the high bits ignored
  - tracing (ARM 9, "Tracing in compatibility mode"; SCB 28): REI with T
    set, RTI and RTT popping a PSW with T, T set at the start of RTI that
    pops a PSW without it, and a BPT with T set (the fault first, TP clear
    in its PSL; the next instruction is traced)

The handlers log the vector or code, PC, PSL and R0-R6 (ten longwords):
SCB 30 steps over BPT and stops at EMT 377; SCB 28 (trace) counts down R9
and clears T in the PSL it returns to when R9 reaches 0.
"""

BRANCHES = ['BR', 'BNE', 'BEQ', 'BGE', 'BLT', 'BGT', 'BLE', 'BPL', 'BMI', 'BHI',
            'BLOS', 'BVC', 'BVS', 'BCC', 'BCS']

HEAD = '''LOG	= ^x18000
KSP	= 0
USP	= 3
SCBB	= ^x11
CMPSL	= ^x83C00000

	.org	^x1000
start:	movl	#^x17800, sp		; above 64K: the compat code is
					; up to FFFF
	clrl	r0
	movab	unexp+1, r1
scbfill: movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	cmexc, @#^x30
	movab	trace, @#^x28
	mtpr	#0, #SCBB
	mtpr	#^x17000, #KSP
	mtpr	#^x16800, #USP
	movl	#LOG, r11
	clrl	r9
	pushl	#CMPSL
	pushl	#^x8000
	rei

'''


HANDLERS = '''; the compatibility mode exception: BPT is stepped over, EMT 377 stops,
; EMT 376 starts the trace of part T (REI with PSL<T>: R9 traces)
	.align	4
cmexc:	movl	(sp)+, r10		; the code
	jsb	log
	cmpl	r10, #1			; BPT: on
	bneq	cmx
	addl2	#2, (sp)
	rei
cmx:	movzwl	@(sp), r10
	cmpl	r10, #^o104376		; EMT 376: REI to the next word, T set
	bneq	cmy
	addl2	#2, (sp)
	bisl2	#^x10, 4(sp)
	movl	#3, r9
	rei
cmy:	halt				; EMT 377: the end

; trace fault: logged; after R9 of them T is cleared
	.align	4
trace:	movl	#^x28, r10
	jsb	log
	sobgtr	r9, tr1
	bicl2	#^x10, 4(sp)
tr1:	rei

; log r10, the PC and PSL of the frame (at 4(sp), after the JSB) and R0-R6
log:	movl	r10, (r11)+
	movl	4(sp), (r11)+
	movl	8(sp), (r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	rsb

	.align	4
unexp:	movl	#^xBAD, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	halt'''


def main():
    out = []
    p = out.append
    n = [0]

    def lbl(s):
        n[0] += 1
        return '%s%d' % (s, n[0])

    def nops(k):
        for i in range(0, k, 8):
            p('\t.word\t' + ', '.join(['^o240'] * min(8, k - i)))

    p('\t.org\t^x8000')
    p('\t.pdp11')
    p('\tmov\t#^x7000, sp')
    p('; ---- branches: not taken, the BPT after it; taken, the BPT at the target')
    for b in BRANCHES:
        for f in range(16):
            t, nx = lbl('t'), lbl('n')
            p('\tccc')
            if f:
                p('\t.word\t^o%o' % (0o260 | f))
            p('\t%s\t%s' % (b.lower(), t))
            p('\tbpt')
            p('\tbr\t%s' % nx)
            p('%s:\tbpt' % t)
            p('%s:' % nx)
    p('; ---- the longest displacements: +127 and -128 words')
    p('\tbr\tFWD')
    nops(127)
    p('FWD:\tbpt')
    p('\tbr\tBKX')
    p('BK:\tbpt')
    p('\tbr\tBKD')
    nops(125)
    p('BKX:\tbr\tBK')
    p('BKD:')
    p('; ---- JMP: each mode but register; J1 logs and returns through R5')
    for mode, setup, op in [
            ('(R1)', 'mov\t#J1, r1', 'jmp\t(r1)'),
            ('(R1)+', 'mov\t#J1, r1', 'jmp\t(r1)+'),
            ('@(R1)+', 'mov\t#JP, r1', 'jmp\t@(r1)+'),
            ('-(R1)', 'mov\t#J1+2, r1', 'jmp\t-(r1)'),
            ('@-(R1)', 'mov\t#JP+2, r1', 'jmp\t@-(r1)'),
            ('X(R1)', 'mov\t#J1-^x100, r1', 'jmp\t^x100(r1)'),
            ('@X(R1)', 'mov\t#JP+^x40, r1', 'jmp\t@-^x40(r1)'),
            ('relative', 'clr\tr1', 'jmp\tJ1'),
            ('relative deferred', 'clr\tr1', 'jmp\t@JP'),
            ('absolute', 'clr\tr1', 'jmp\t@#J1')]:
        ret = lbl('r')
        p('; %s' % mode)
        p('\tmov\t#%s, r5' % ret)
        p('\t' + setup)
        p('\t' + op)
        p('%s:' % ret)
    p('; JMP (PC)+: to the word after it')
    p('\tjmp\t(pc)+')
    p('\tbpt')
    p('; ---- JSR, RTS')
    p('\tmov\t#^x1111, r5')
    p('\tjsr\tpc, S1')
    p('\tbpt')
    p('\tjsr\tr5, S2')
    p('\t.word\t^x1234')                 # an argument after the call
    p('\tbpt')
    p('\tmov\t#JP+2, r1')
    p('\tjsr\tr1, @(r1)+')               # to J2; pushes the updated R1
    p('\tbpt')
    p('\tmov\t#SR, r1')
    p('\tjsr\tpc, (r1)')
    p('\tbpt')
    p('; ---- SOB')
    p('\tmov\t#3, r1')
    p('\tclr\tr2')
    p('SB1:\tinc\tr2')
    p('\tsob\tr1, SB1')
    p('\tbpt')
    p('\tmov\t#1, r1')
    p('SB2:\tsob\tr1, SB2')
    p('\tbpt')
    p('\tmov\t#2, r1')
    p('\tclr\tr2')
    p('SB3:\tinc\tr2')
    nops(61)
    p('\tsob\tr1, SB3')                  # 63 words back
    p('\tbpt')
    p('; ---- MOV, ADD to PC; MOV PC')
    p('\tmov\t#MP1, pc')
    p('\tbpt')
    p('MP1:\tadd\t#4, pc')
    p('\tbpt')
    p('\tbpt')
    p('\tmov\tpc, r1')
    p('\tbpt')
    p('; ---- RTI, RTT: PC and PSW<4:0> popped')
    for op, psw in [('rti', 0o000017), ('rtt', 0o177740), ('rti', 0o177757),
                    ('rtt', 0o000005)]:
        t = lbl('i')
        p('\tmov\t#^o%o, -(sp)' % psw)
        p('\tmov\t#%s, -(sp)' % t)
        p('\t' + op)
        p('\tbpt')
        p('%s:\tbpt' % t)
    p('; ---- trace')
    p('; RTI and RTT with T in the PSW popped: the next instruction runs, the')
    p('; trace comes before the one after it (the handler then clears T)')
    for op in ('rti', 'rtt'):
        t = lbl('i')
        p('\tmov\t#^o20, -(sp)')
        p('\tmov\t#%s, -(sp)' % t)
        p('\t' + op)
        p('%s:\tmov\t#1, r0' % t)
        p('\tmov\t#2, r0')
        p('\tmov\t#3, r0')
        p('\tbpt')
    p('; REI with T (EMT 376): three instructions traced, a BPT with T set')
    p('; (the fault first, TP clear in its PSL) among them')
    p('\temt\t^o376')
    p('\tmov\t#1, r1')
    p('\tbpt')
    p('\tmov\t#2, r1')
    p('\tmov\t#3, r1')
    p('\tmov\t#4, r1')
    p('\tbpt')
    p('; RTI that sets T, then an RTI with T at its start popping a PSW without')
    p('; it: the second is traced (PSL T clear), at TR2')
    p('\tmov\t#0, -(sp)')
    p('\tmov\t#TR2, -(sp)')
    p('\tmov\t#^o20, -(sp)')
    p('\tmov\t#TR1, -(sp)')
    p('\trti')
    p('TR1:\trti')
    p('TR2:\tbpt')
    p('\temt\t^o377')
    p('; the subroutines and the jump targets')
    p('S1:\tmov\t#^x2222, r5')
    p('\trts\tpc')
    p('S2:\tmov\t(r5)+, r4')
    p('\trts\tr5')
    p('SR:\tmov\tsp, r2')
    p('\trts\tpc')
    p('J1:\tbpt')
    p('\tjmp\t(r5)')
    p('J2:\tbpt')
    p('\trts\tr1')
    p('JP:\t.word\tJ1, J2, J1')
    print('; t63_cmflow - PDP-11 compatibility mode program control and tracing')
    print('; against the reference simulator; written by tests/mmu/gen/mk_t63.py')
    print('; (which see).')
    print(';@ dump=18000:C00')
    print(';@ dump=6E00:100')
    print(';@ clocks=2000000')
    print(HEAD)
    print('\n'.join(out))
    print('\t.vax')
    print('; the handlers, after the compat code; mkboard.py (software/mmutest.bin)')
    print('; appends its code and table after them, out of the way of the test')
    print('\t.org\t^xA000')
    print(HANDLERS)


if __name__ == '__main__':
    main()

/*	$Id$ */

/*
 * The emul is called with the stack set up as follows:
 *
 *      48(%sp): TOS before instruction
 *      44(%sp): Return PSL
 *      40(%sp): Return PC
 *      36(%sp): Dest op 2
 *      32(%sp): Dest op 1
 *      28(%sp): Operand 6
 *      24(%sp): Operand 5
 *      20(%sp): Operand 4
 *      16(%sp): Operand 3
 *      12(%sp): Operand 2
 *       8(%sp): Operand 1
 *       4(%sp): Instruction PC
 *        (%sp): Opcode
 */

#define	ARG1	8(%sp)
#define	ARG2	12(%sp)

emul:
//	cmpb	(%sp),$0xf0	# insv
//	beql	i_insv
	cmpb	(%sp),$0xbb	# pushr
	beql	i_pushr

//
// pushes regs in the bitmask in ARG1 onto the stack in highest-first order.
//
i_pushr:
// Adjust stack to be 16 longword, then move the whole frame down
// to make place for the pushed registers.

	movl	%r2,-(%sp)
	movl	%r2,-(%sp)
	movl	%r1,-(%sp)
	movl	%r0,-(%sp)	# save scratch regs
	movl	%sp,%r0		# remember TOS
	subl2	$64,%sp		# make room for moving frame
	movl	$16,%r2		# num longwords
	movl	%sp,%r1		# to
1:	movl	(%r0)+,(%r1)+	# Move!
	decl	%r2
	bgtr	1b

// Frame moved.  Now traverse over all bits to see which regs need to be saved.
// r0 is at top of stack.
	rotl	$16,24(%sp),%r2
#define	PUSH(reg) rotl $1,%r2,%r2 ; bgeq 1f ; movl reg,-(%r0) ; 1:;
	PUSH(%r0)
	PUSH(%fp)
	PUSH(%ap)
	PUSH(%r11)
	PUSH(%r10)
	PUSH(%r9)
	PUSH(%r8)
	PUSH(%r7)
	PUSH(%r6)
	PUSH(%r5)
	PUSH(%r4)
	PUSH(%r3)
	PUSH(8(%sp))
	PUSH(4(%sp))
	PUSH((%sp))

	movl	60(%sp),-(%r0)	# move psl
	movl	56(%sp),-(%r0)	# move pc
	movl	8(%sp),%r2	# restore r2
	movl	4(%sp),%r1	# restore r1
	movl	(%sp),-(%r0)	# push old r0 onto stack
	movl	%r0,%sp		# set sp correct
	movl	(%sp)+,%r0	# restore r0
halt
	rei			# Done!





#if 0
#define	SRC	8(%sp)
#define	POS	12(%sp)
#define	SIZE	16(%sp)
#define	BASEP	32(%sp)

i_insv:
	tstl	BASEP	# register?
	blss	1f	# yep, branch

	# bit_addr = { arg3, 3'b0 } + { {3{arg1[31]}}, arg1 };
	movl	POS,



	.long	0
	brw	LB4
	.align	2
/*	brw	LB8 */
	.long 0

I_AOBLEQ:
/* setup stack */
	addl2	$-24,%sp	# 6 longwords on stack
	mfpr	$64,12(%sp)	# arg1 (limit)
	mfpr	$65,8(%sp)	# arg2 (index)
	mfpr	$66,4(%sp)	# arg3 (braddr)

	mfpr	$73,18(%sp)	# return psl (unaligned)
	bicl2	$0xe,18(%sp)	# clear vnz

/* increase index */
	incl	8(%sp)		# index = index + 1
	movpsl	(%sp)		# save flags
	bicl2	$0xfffffff1,(%sp) # only want znv
	bisl2	(%sp),18(%sp)	# set in return psl

/* Write back index */
	mfpr	$69,(%sp)
	bitl	$0x10,(%sp)	# in reg
	beql	1f		# no, skip

	movl	8(%sp),-(%sp)	# save val
	jsb	wbreg
	addl2	$4,%sp
	brb	3f
1:
	mfpr	$68,(%sp)	# get arg1 save address
	movl	8(%sp),*(%sp)

3:
	mfpr	$72,20(%sp)	# fetch ret pc

/* compare with index */
	cmpl	8(%sp),12(%sp)
	movpsl	(%sp)
	bitl	(%sp),$12
	beql	1f

/* save as new pc */
	movl	4(%sp),20(%sp)
1:

/* return */
	addl2	$18,%sp
	bicpsw	$15		# clear all bits
	bispsw	(%sp)+		# set saved (modified) bits
	movl	(%sp)+,%pc	# jmp back


/*
 * Write back to reg.
 * Called with jsb.
 * Param:
 *	8(sp) == regno
 * 	4(sp) == val
 */
wbreg:
	bicl2   $0xfffffff0,8(%sp) # only reg number
	addl2	8(%sp),8(%sp)	# *2
	addl2	8(%sp),8(%sp)	# *4
	addl2	8(%sp),8(%sp)	# *8
	addl2	8(%sp),%pc	# additive jmp
	movl	4(%sp),%r0 ; brw 2f ; .byte 0
	movl	4(%sp),%r1 ; brw 2f ; .byte 0
	movl	4(%sp),%r2 ; brw 2f ; .byte 0
	movl	4(%sp),%r3 ; brw 2f ; .byte 0
	movl	4(%sp),%r4 ; brw 2f ; .byte 0
	movl	4(%sp),%r5 ; brw 2f ; .byte 0
	movl	4(%sp),%r6 ; brw 2f ; .byte 0
	movl	4(%sp),%r7 ; brw 2f ; .byte 0
	movl	8(%sp),%r8 ; brw 2f ; .byte 0
	movl	4(%sp),%r9 ; brw 2f ; .byte 0
	movl	4(%sp),%r10 ; brw 2f ; .byte 0
	movl	4(%sp),%r11 ; brw 2f ; .byte 0
	movl	4(%sp),%r12 ; brw 2f ; .byte 0
	movl	4(%sp),%r13 ; brw 2f ; .byte 0
	movl	4(%sp),%r14 ; brw 2f ; .byte 0
	movl	4(%sp),%r15
2:
	rsb
#endif

#	$Id$

	.long	0
	brw	1f
	.align	2
	.long 0

# 20 pc
# 16 psl
# 12 limit
# 8 index
# 4 braddr
# 0 == scratch

1:
# setup stack
	addl2	$-24,%sp	# 6 longwords on stack
	mfpr	$64,12(%sp)	# arg1 (limit)
	mfpr	$65,8(%sp)	# arg2 (index)
	mfpr	$66,4(%sp)	# arg3 (braddr)

	mfpr	$73,18(%sp)	# return psl (unaligned)
	bicl2	$0xe,18(%sp)	# clear vnz

# increase index
	incl	8(%sp)		# index = index + 1
	movpsl	(%sp)		# save flags
	bicl2	$0xfffffff1,(%sp) # only want znv
	bisl2	(%sp),18(%sp)	# set in return psl

# Write back index
	mfpr	$69,(%sp)
	bitl	$0x10,(%sp)	# in reg
	beql	1f		# no, skip
	brb	3f
1:
	mfpr	$68,(%sp)	# get arg1 save address
	movl	8(%sp),*(%sp)
	brw	2f

3:	bicl2   $0xfffffff0,(%sp) # only reg number
	addl2	(%sp),(%sp)	# *2
	addl2	(%sp),(%sp)	# *4
	addl2	(%sp),(%sp)	# *8
	addl2	(%sp),%pc	# additive jmp
	movl	8(%sp),%r0 ; brw 2f ; .byte 0
	movl	8(%sp),%r1 ; brw 2f ; .byte 0
	movl	8(%sp),%r2 ; brw 2f ; .byte 0
	movl	8(%sp),%r3 ; brw 2f ; .byte 0
	movl	8(%sp),%r4 ; brw 2f ; .byte 0
	movl	8(%sp),%r5 ; brw 2f ; .byte 0
	movl	8(%sp),%r6 ; brw 2f ; .byte 0
	movl	8(%sp),%r7 ; brw 2f ; .byte 0
	movl	8(%sp),%r8 ; brw 2f ; .byte 0
	movl	8(%sp),%r9 ; brw 2f ; .byte 0
	movl	8(%sp),%r10 ; brw 2f ; .byte 0
	movl	8(%sp),%r11 ; brw 2f ; .byte 0
	movl	8(%sp),%r12 ; brw 2f ; .byte 0
	movl	8(%sp),%r13 ; brw 2f ; .byte 0
	movl	8(%sp),%r14 ; brw 2f ; .byte 0
	movl	8(%sp),%r15 ; brw 2f ; .byte 0
2:
	mfpr	$72,20(%sp)	# fetch ret pc

# compare with index
	cmpl	8(%sp),12(%sp)
	movpsl	(%sp)
	bitl	(%sp),$12
	beql	1f

# save as new pc
	movl	4(%sp),20(%sp)
1:

# return
	addl2	$18,%sp
	bicpsw	$15		# clear all bits
	bispsw	(%sp)+		# set saved (modified) bits
	movl	(%sp)+,%pc	# jmp back


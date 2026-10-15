/*
 * Copyright (c) 2021 Anders Magnusson (ragge@tethuvudet.se).
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



`define IPR_KSP		7'h00
`define IPR_ESP		7'h01
`define IPR_SSP		7'h02
`define IPR_USP		7'h03
`define IPR_ISP		7'h04

`define IPR_P0BR	7'h08
`define IPR_P0LR	7'h09
`define IPR_P1BR	7'h0a
`define IPR_P1LR	7'h0b
`define IPR_SBR	7'h0c
`define IPR_SLR	7'h0d

`define IPR_PCBB	7'h10
`define IPR_SCBB	7'h11
`define IPR_IPL		7'h12
`define IPR_ASTLVL	7'h13

`define IPR_SIRR	7'h14
`define IPR_SISR	7'h15

`define IPR_ICCS	7'h18
`define IPR_NICR	7'h19
`define IPR_ICR		7'h1a
`define IPR_TODR	7'h1b

`define IPR_RXCS	7'h20
`define IPR_RXDB	7'h21
`define IPR_TXCS	7'h22
`define IPR_TXDB	7'h23

`define IPR_CADR	7'h25

`define IPR_MAPEN	7'h38
`define IPR_TBIA	7'h39
`define IPR_TBIS	7'h3a

`define IPR_SID		7'h3e
`define IPR_TBCHK	7'h3f

`define	IPR_PAMACC	7'h40
`define	IPR_PAMLOC	7'h41

/* internal registers, not reachable with MTPR/MFPR (microcode only) */
`define IPR_MMVA	7'h70	/* memory management fault: virtual address */
`define IPR_MMPAR	7'h71	/* memory management fault: parameter */
`define IPR_RIFLT	7'h72	/* write: next reserved operand fault is a reserved instruction fault */

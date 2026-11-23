/*
 * cmdecode.v - the PDP-11 compatibility mode instruction decode: what the
 * CPU does with the instruction word it has fetched in compatibility mode
 * (PSL<CM> set).
 *
 * Written for the MiSTer port of r-vax, after the VAX Architecture
 * Reference Manual (EY-3459E-DP, 1987), chapter 9, "PDP-11 Compatibility
 * Mode": table 9.1 (the instructions), 9.2 (the trap instructions, which
 * fault to VAX mode), 9.3 and "all other opcodes" (reserved instructions),
 * figure 9.2 (the formats), the descriptions of the instructions (the
 * operands, their access and the condition codes) and "Compatibility mode
 * exceptions and interrupts" (the fault codes).
 *
 * The CPU (cpu.v) evaluates the operand specifiers this decode asks for -
 * the eight PDP-11 addressing modes - and then enters the microcode at
 * cm_table (ucode.def) + cls with
 *	arg1	operand A, read: the source (IR<11:6>), or the specifier
 *		IR<5:0> of MUL, DIV, ASH, ASHC, MFPI, MFPD, or (SP)+ for MTPI,
 *		MTPD (the implied source of the pop, evaluated first)
 *	arg2	operand B, IR<5:0> or -(SP) for MFPI, MFPD: its value (read,
 *		modify) or its address (JMP, JSR)
 *	argp0	operand B's location (a register or an address) for the
 *		microcode's write back
 *	arg3	the register field R (IR<8:6>, IR<2:0> for RTS), read before
 *		the operands for XOR, after them for the others; arg4 R OR 1
 * Values are sign extended from their size, a byte or a word. At the end of
 * the instruction the condition codes are set from the flags the microcode
 * saved, as ccnz, ccv and ccc say.
 *
 * The instructions that fault - the reserved ones, BPT, IOT, EMT, TRAP and
 * JMP or JSR with a register destination (the illegal instruction) - do so
 * before anything is done: compatibility mode exception (SCB 30) with the
 * type code fcode (ARM table 5.2).
 */

`timescale 1ns / 1ps
`default_nettype none

/* the microcode routines (cls): the order of the table at cm_table */
`define	CMC_RTI		6'd0	/* RTI, RTT */
`define	CMC_JMP		6'd1
`define	CMC_RTS		6'd2
`define	CMC_CC		6'd3	/* CLC ... SCC, NOP */
`define	CMC_SWAB	6'd4
`define	CMC_BR		6'd5	/* BR, Bxx */
`define	CMC_JSR		6'd6
`define	CMC_CLR		6'd7	/* CLR, CLRB */
`define	CMC_COM		6'd8
`define	CMC_INC		6'd9
`define	CMC_DEC		6'd10
`define	CMC_NEG		6'd11
`define	CMC_ADC		6'd12
`define	CMC_SBC		6'd13
`define	CMC_TST		6'd14
`define	CMC_ROR		6'd15
`define	CMC_ROL		6'd16
`define	CMC_ASR		6'd17
`define	CMC_ASL		6'd18
`define	CMC_RORB	6'd19
`define	CMC_ROLB	6'd20
`define	CMC_ASRB	6'd21
`define	CMC_ASLB	6'd22
`define	CMC_MOV		6'd23	/* MOV, MOVB, MFPI, MFPD, MTPI, MTPD */
`define	CMC_SXT		6'd24
`define	CMC_CMP		6'd25
`define	CMC_BIT		6'd26
`define	CMC_BIC		6'd27
`define	CMC_BIS		6'd28
`define	CMC_ADD		6'd29
`define	CMC_SUB		6'd30
`define	CMC_MUL		6'd31
`define	CMC_DIV		6'd32
`define	CMC_ASH		6'd33
`define	CMC_ASHC	6'd34
`define	CMC_XOR		6'd35
`define	CMC_SOB		6'd36

module cmdecode(
	input [15:0]		ir,		/* the instruction word */
	input			n, z, v, c,	/* the condition codes */

	output reg [5:0]	cls,		/* the microcode routine */
	output reg		flt,		/* the instruction faults ... */
	output reg [2:0]	fcode,		/* ... with this type code */
	output reg		bsz,		/* byte operands */
	output reg [1:0]	a,		/* operand A: 0 none, 1 IR<11:6>,
						   2 IR<5:0>, 3 (SP)+ */
	output reg [1:0]	b,		/* operand B: 0 none, 1 IR<5:0>,
						   2 -(SP) */
	output reg [1:0]	bacc,		/* its access: 0 read, 1 write,
						   2 modify, 3 address */
	output reg [1:0]	r,		/* the register field: 0 not read,
						   1 before the operands, 2 after */
	output reg		rts,		/* ... is IR<2:0> */
	output reg		movb,		/* MOVB: to a register, the word */
	output reg		ccnz,		/* N, Z from the flags saved */
	output reg [1:0]	ccv,		/* V: 0 kept, 1 cleared, 2 the flag
						   saved, 3 N XOR C */
	output reg [1:0]	ccc,		/* C: 0 kept, 1 cleared, 2 the flag
						   saved, 3 set */
	output [31:0]		brdisp		/* what a branch adds to PC: twice
						   the displacement if it is taken,
						   else 0; SOB: minus twice its
						   displacement */
);

	/* Branches: 000400-003777 and 100000-103777, the condition chosen by
	   IR<15> and IR<10:9>, IR<8> branches when it holds */
	reg		bcond;
	always @*
		case ({ ir[15], ir[10:9] })
		3'b000:	bcond = 1'b1;		/* BR */
		3'b001:	bcond = z;		/* BEQ (BNE) */
		3'b010:	bcond = n ^ v;		/* BLT (BGE) */
		3'b011:	bcond = z | (n ^ v);	/* BLE (BGT) */
		3'b100:	bcond = n;		/* BMI (BPL) */
		3'b101:	bcond = c | z;		/* BLOS (BHI) */
		3'b110:	bcond = v;		/* BVS (BVC) */
		default: bcond = c;		/* BCS (BCC) */
		endcase
	wire		taken = ir[8] ? bcond : ~bcond;
	wire		sob = (ir[15:9] == 7'o077);
	assign brdisp = sob ? 32'd0 - { 25'd0, ir[5:0], 1'b0 } :
	    taken ? { {23{ir[7]}}, ir[7:0], 1'b0 } : 32'd0;

	/* a single operand instruction, CLR ... ASL (IR<11:6> 50-63) */
	task single;
		input [5:0]	sop;
		begin
			b = 2'd1;
			bacc = 2'd2;		/* modify */
			ccnz = 1'b1;
			case (sop)
			6'o50: begin cls = `CMC_CLR; bacc = 2'd1;
				ccv = 2'd1; ccc = 2'd1; end
			6'o51: begin cls = `CMC_COM; ccv = 2'd1; ccc = 2'd3; end
			6'o52: begin cls = `CMC_INC; ccv = 2'd2; end
			6'o53: begin cls = `CMC_DEC; ccv = 2'd2; end
			6'o54: begin cls = `CMC_NEG; ccv = 2'd2; ccc = 2'd2; end
			6'o55: begin cls = `CMC_ADC; ccv = 2'd2; ccc = 2'd2; end
			6'o56: begin cls = `CMC_SBC; ccv = 2'd2; ccc = 2'd2; end
			6'o57: begin cls = `CMC_TST; bacc = 2'd0;
				ccv = 2'd1; ccc = 2'd1; end
			/* ROR, ROL, ASR, ASL: C the bit shifted out, V = N XOR C */
			6'o60: begin cls = bsz ? `CMC_RORB : `CMC_ROR;
				ccv = 2'd3; ccc = 2'd2; end
			6'o61: begin cls = bsz ? `CMC_ROLB : `CMC_ROL;
				ccv = 2'd3; ccc = 2'd2; end
			6'o62: begin cls = bsz ? `CMC_ASRB : `CMC_ASR;
				ccv = 2'd3; ccc = 2'd2; end
			default: begin cls = bsz ? `CMC_ASLB : `CMC_ASL;
				ccv = 2'd3; ccc = 2'd2; end
			endcase
		end
	endtask

	/* reserved instruction (fault code 0) */
	task reserved;
		begin
			flt = 1'b1;
			fcode = 3'd0;
		end
	endtask

	always @* begin
		cls = 6'd0;
		flt = 1'b0;
		fcode = 3'd0;
		bsz = 1'b0;
		a = 2'd0;
		b = 2'd0;
		bacc = 2'd0;
		r = 2'd0;
		rts = 1'b0;
		movb = 1'b0;
		ccnz = 1'b0;
		ccv = 2'd0;
		ccc = 2'd0;
		case (ir[15:12])
		4'o00: case (ir[11:6])			/* 00xxxx */
			6'o00: case (ir[5:0])
				6'o02, 6'o06: cls = `CMC_RTI;	/* RTI, RTT */
				6'o03: begin flt = 1'b1; fcode = 3'd1; end /* BPT */
				6'o04: begin flt = 1'b1; fcode = 3'd2; end /* IOT */
				/* HALT, WAIT, RESET, MFPT, 000010-000077 */
				default: reserved;
				endcase
			6'o01: begin				/* JMP */
				cls = `CMC_JMP;
				b = 2'd1;
				bacc = 2'd3;
				if (ir[5:3] == 3'd0) begin	/* to a register */
					flt = 1'b1;
					fcode = 3'd5;
				end
			end
			6'o02: if (ir[5:3] == 3'd0) begin	/* RTS */
				cls = `CMC_RTS;
				r = 2'd2;
				rts = 1'b1;
			end else if (ir[5]) begin		/* 000240-000277 */
				cls = `CMC_CC;
			end else
				reserved;		/* 000210-000237, SPL */
			6'o03: begin				/* SWAB */
				cls = `CMC_SWAB;
				b = 2'd1;
				bacc = 2'd2;
				ccnz = 1'b1;
				ccv = 2'd1;
				ccc = 2'd1;
			end
			6'o40, 6'o41, 6'o42, 6'o43,
			6'o44, 6'o45, 6'o46, 6'o47: begin	/* JSR */
				cls = `CMC_JSR;
				b = 2'd1;
				bacc = 2'd3;
				r = 2'd2;
				if (ir[5:3] == 3'd0) begin
					flt = 1'b1;
					fcode = 3'd5;
				end
			end
			6'o50, 6'o51, 6'o52, 6'o53, 6'o54, 6'o55, 6'o56, 6'o57,
			6'o60, 6'o61, 6'o62, 6'o63:
				single(ir[11:6]);
			6'o65: begin				/* MFPI */
				cls = `CMC_MOV;
				a = 2'd2;
				b = 2'd2;
				bacc = 2'd1;
				ccnz = 1'b1;
				ccv = 2'd1;
			end
			6'o66: begin				/* MTPI */
				cls = `CMC_MOV;
				a = 2'd3;
				b = 2'd1;
				bacc = 2'd1;
				ccnz = 1'b1;
				ccv = 2'd1;
			end
			6'o67: begin				/* SXT */
				cls = `CMC_SXT;
				b = 2'd1;
				bacc = 2'd1;
				ccnz = 1'b1;
				ccv = 2'd1;
			end
			default:
				/* 0004xx-0037xx: BR ... BLE (IR<11:6> 04-37) */
				if (ir[11] == 1'b0)
					cls = `CMC_BR;
				else
					reserved;	/* MARK, CSM, 0070xx-0077xx */
			endcase
		4'o10: case (ir[11:6])			/* 10xxxx */
			6'o40, 6'o41, 6'o42, 6'o43: begin	/* EMT */
				flt = 1'b1;
				fcode = 3'd3;
			end
			6'o44, 6'o45, 6'o46, 6'o47: begin	/* TRAP */
				flt = 1'b1;
				fcode = 3'd4;
			end
			6'o50, 6'o51, 6'o52, 6'o53, 6'o54, 6'o55, 6'o56, 6'o57,
			6'o60, 6'o61, 6'o62, 6'o63: begin	/* CLRB ... ASLB */
				bsz = 1'b1;
				single(ir[11:6]);
			end
			6'o65: begin				/* MFPD */
				cls = `CMC_MOV;
				a = 2'd2;
				b = 2'd2;
				bacc = 2'd1;
				ccnz = 1'b1;
				ccv = 2'd1;
			end
			6'o66: begin				/* MTPD */
				cls = `CMC_MOV;
				a = 2'd3;
				b = 2'd1;
				bacc = 2'd1;
				ccnz = 1'b1;
				ccv = 2'd1;
			end
			default:
				/* 1000xx-1037xx: BPL ... BCS */
				if (ir[11] == 1'b0)
					cls = `CMC_BR;
				else
					reserved;	/* MTPS, MFPS, 1070xx-1077xx */
			endcase
		4'o07: begin				/* 07xxxx: EIS, XOR, SOB */
			b = 2'd0;
			ccnz = 1'b1;
			case (ir[11:9])
			3'd0: begin cls = `CMC_MUL; a = 2'd2; r = 2'd2;
				ccv = 2'd1; ccc = 2'd2; end
			3'd1: begin cls = `CMC_DIV; a = 2'd2; r = 2'd2;
				ccv = 2'd2; ccc = 2'd2; end
			3'd2: begin cls = `CMC_ASH; a = 2'd2; r = 2'd2;
				ccv = 2'd2; ccc = 2'd2; end
			3'd3: begin cls = `CMC_ASHC; a = 2'd2; r = 2'd2;
				ccv = 2'd2; ccc = 2'd2; end
			3'd4: begin cls = `CMC_XOR; b = 2'd1; bacc = 2'd2;
				r = 2'd1; ccv = 2'd1; end
			3'd7: begin cls = `CMC_SOB; r = 2'd2; ccnz = 1'b0; end
			/* 075xxx (FIS), 076xxx (CIS) */
			default: begin reserved; ccnz = 1'b0; end
			endcase
		end
		4'o17:					/* 17xxxx: FP11 */
			reserved;
		default: begin			/* double operand: MOV ... SUB */
			a = 2'd1;
			b = 2'd1;
			ccnz = 1'b1;
			bsz = ir[15] & (ir[14:12] != 3'd6);
			case (ir[14:12])
			3'd1: begin cls = `CMC_MOV; bacc = 2'd1; ccv = 2'd1;
				movb = ir[15]; end
			3'd2: begin cls = `CMC_CMP; bacc = 2'd0; ccv = 2'd2;
				ccc = 2'd2; end
			3'd3: begin cls = `CMC_BIT; bacc = 2'd0; ccv = 2'd1; end
			3'd4: begin cls = `CMC_BIC; bacc = 2'd2; ccv = 2'd1; end
			3'd5: begin cls = `CMC_BIS; bacc = 2'd2; ccv = 2'd1; end
			default: begin			/* ADD (06), SUB (16) */
				cls = ir[15] ? `CMC_SUB : `CMC_ADD;
				bacc = 2'd2;
				ccv = 2'd2;
				ccc = 2'd2;
			end
			endcase
		end
		endcase
		/* a fault does nothing else */
		if (flt) begin
			a = 2'd0;
			b = 2'd0;
			r = 2'd0;
			ccnz = 1'b0;
			ccv = 2'd0;
			ccc = 2'd0;
		end
	end

endmodule

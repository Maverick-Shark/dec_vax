/*
 * mmu.v - VAX memory management for r-vax: address translation, access
 * control, translation buffer.
 *
 * Written for the MiSTer port of r-vax, after:
 *   - VAX Architecture Reference Manual (EY-3459E-DP, 1987), chapter 4,
 *     and DEC STD 032 (VAX Architecture Standard), chapter 4;
 *   - VAX 8600 Training Print Set (EY-4818E-PP), "Address Module Block
 *     Diagram" (L0205 MAP): the translation buffer of the 8600.
 *
 * Place in the system: it sits where r-vax's sbi.v names the "mmu", between
 * the aligner (vcache.v, which already splits every access into aligned
 * longword cycles, so an access never crosses a page here) and the physical
 * bus (cache, memory, I/O):
 *
 *	cpu -- vcache -- mmu -- cache/memory, I/O adapters
 *
 * Translation buffer: as on the 8600, 512 entries, direct mapped, half for
 * system space and half for process space: index VA<31>,VA<16:9>, tag
 * VA<30:17>. An entry holds the PFN, the protection code and the modify bit
 * of a valid PTE (the TB never holds invalid PTEs). Valid bits are kept in
 * flip-flops so that TBIA and the process-space flush take one clock; the
 * rest is one M10K block RAM (512 x 40). The valid bit of an entry is read
 * in the same clock as the RAM word, and set in the same clock as the RAM
 * word is written, so the flip-flops need one 512-way read multiplexer and
 * one decoder.
 *
 * Translation (SRM 4.3 - 4.8), when the TB misses:
 *   S0  (VA<31:30> = 10): length check against SLR, PTE at SBR + 4*VPN
 *       (physical).
 *   P0, P1: length check against P0LR (VPN >= P0LR fails) or P1LR (VPN <
 *       P1LR fails); the PTE is at the system virtual address PxBR + 4*VPN,
 *       which is translated like any S0 address (TB, else the system PTE,
 *       which is then kept in the TB). A length violation or an invalid
 *       system PTE at this step is reported with the "PTE reference" bit.
 *   S1  (VA<31:30> = 11): length violation.
 * Protection is checked before the valid bit: if both would fault, the
 * access-control violation wins. A write (or a read with modify intent) to a
 * page whose PTE has M clear sets M in the PTE in memory first.
 *
 * Faults: the access is not done; FLT stays set until the CPU drops its
 * strobe, with FLT_VA (a virtual address in the faulting page; for a fault
 * on a process PTE reference, the process address) and FLT_PAR, the fault
 * parameter of SRM table 4.4: <2> write or modify intent, <1> PTE
 * reference, <0> length violation. FLT_TNV selects the vector: translation
 * not valid (SCB 24) or access-control violation (SCB 20).
 *
 * Probes (in_probe): PROBER/PROBEW ask whether a page is accessible in a
 * given mode; nothing is read or written, the answer is IN_DAT_O<0>.
 * Following the SRM's PROBE flow: the TB entry decides if there is one, a
 * length violation means "not accessible", the protection code of the PTE
 * decides even if the PTE is not valid, and only an invalid system PTE for
 * a process page table gives a translation-not-valid fault. With in_pmem as
 * well, a probe is the TBCHK test: IN_DAT_O<0> is 1 if the TB holds a
 * translation for the page.
 *
 * Registers: the MMU keeps its own copy of P0BR, P0LR, P1BR, P1LR, SBR, SLR
 * and MAPEN by watching the CPU's IPR writes (MTPR, or the console while the
 * CPU is halted); the CPU's IPR file keeps them too, for MFPR. Writes to the
 * process-space registers flush the process half of the TB; SBR, SLR,
 * MAPEN and TBIA flush all of it; TBIS flushes the entry for one page.
 *
 * With MAPEN clear, or for physical references (SCB vectors, PCB), the
 * address goes straight through: PA<29:0> = VA<29:0>, no checks, no extra
 * clock.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

`timescale 1ns / 1ps
`default_nettype none

`include "ipr.vh"

module mmu(
	input		clk,
	input		rst,

	/* virtual side: aligned longword cycles from vcache */
	input		IN_STB_I,
	input		IN_WE_I,
	input [31:0]	IN_ADR_I,
	input [31:0]	IN_DAT_I,
	output [31:0]	IN_DAT_O,
	output		IN_ACK_O,

	/* about the CPU access these cycles belong to */
	input		cpu_stb,	/* CPU strobe; a fault is held until it drops */
	input		in_pmem,	/* physical address, no translation */
	input		in_wint,	/* write or modify intent */
	input		in_probe,	/* PROBEx (or TBCHK with in_pmem) */
	input [1:0]	in_mode,	/* access mode for the protection check */
	input		in_con,		/* console access, CPU halted: no faults */
	input		in_mcheck,	/* bus timeout machine check: give up */

	/* IPR writes seen by the CPU (MTPR, console deposits) */
	input		ipr_we,
	input [6:0]	ipr_adr,
	input [31:0]	ipr_dat,

	/* fault report */
	output reg	flt,
	output reg [31:0] flt_va,
	output reg [2:0] flt_par,
	output reg	flt_tnv,

	output		progress,	/* a physical cycle was acknowledged */
	output		mapen_o,

	/* physical side */
	output		UT_STB_O,
	output		UT_WE_O,
	output [31:0]	UT_ADR_O,
	output [31:0]	UT_DAT_O,
	input [31:0]	UT_DAT_I,
	input		UT_ACK_I
);

	/* ------------------------------------------------ MM registers */
	reg		mapen;
	reg [31:0]	p0br, p1br, sbr;
	reg [21:0]	p0lr, p1lr, slr;

	assign mapen_o = mapen;

	/* ------------------------------------------------ translation buffer */
	/*
	 * no_rw_check: an entry is written in the clock after S_SPTE, S_PTE or
	 * S_PTEW, and nothing uses tb_q until the next lookup, so the value
	 * read while the same entry is being written never matters; Quartus
	 * need not add bypass logic for it.
	 */
	(* ramstyle = "M10K, no_rw_check" *)
	reg [39:0]	tb_ram [0:511];	/* tag<13:0>, pfn<20:0>, prot<3:0>, m */
	reg [39:0]	tb_q;
	reg [511:0]	tb_v;
	reg		tb_vq;		/* valid bit of the entry in tb_q */
	reg [8:0]	tb_ra;		/* read address (combinational) */
	reg		tb_we;
	reg [8:0]	tb_wa;
	reg [39:0]	tb_wd;

	always @(posedge clk) begin
		if (tb_we)
			tb_ram[tb_wa] <= tb_wd;
		tb_q <= tb_ram[tb_ra];
	end

	wire [13:0]	q_tag  = tb_q[39:26];
	wire [20:0]	q_pfn  = tb_q[25:5];
	wire [3:0]	q_prot = tb_q[4:1];
	wire		q_m    = tb_q[0];

	function [8:0] tbidx;
		input [31:0] va;
		tbidx = { va[31], va[16:9] };
	endfunction

	/*
	 * Protection codes, SRM table 4.3. For each code, a bit per access
	 * mode (K=0, E=1, S=2, U=3) that may write <7:4> and read <3:0>.
	 * Code 1 is reserved (UNPREDICTABLE): no access.
	 */
	function [7:0] prot_acc;
		input [3:0] prot;
		case (prot)
		4'd0:  prot_acc = 8'b0000_0000;	/* NA */
		4'd1:  prot_acc = 8'b0000_0000;	/* reserved */
		4'd2:  prot_acc = 8'b0001_0001;	/* KW */
		4'd3:  prot_acc = 8'b0000_0001;	/* KR */
		4'd4:  prot_acc = 8'b1111_1111;	/* UW */
		4'd5:  prot_acc = 8'b0011_0011;	/* EW */
		4'd6:  prot_acc = 8'b0001_0011;	/* ERKW */
		4'd7:  prot_acc = 8'b0000_0011;	/* ER */
		4'd8:  prot_acc = 8'b0111_0111;	/* SW */
		4'd9:  prot_acc = 8'b0011_0111;	/* SREW */
		4'd10: prot_acc = 8'b0001_0111;	/* SRKW */
		4'd11: prot_acc = 8'b0000_0111;	/* SR */
		4'd12: prot_acc = 8'b0111_1111;	/* URSW */
		4'd13: prot_acc = 8'b0011_1111;	/* UREW */
		4'd14: prot_acc = 8'b0001_1111;	/* URKW */
		default: prot_acc = 8'b0000_1111;	/* UR */
		endcase
	endfunction

	/* ------------------------------------------------ state machine */
	localparam [3:0]
		S_IDLE	= 4'd0,
		S_LOOK	= 4'd1,		/* TB data for VA available */
		S_WALK	= 4'd2,		/* length check, PTE address */
		S_SRD	= 4'd3,		/* TB read for the process PTE's page */
		S_SLOOK	= 4'd4,		/* TB data for the PTE address available */
		S_BUS	= 4'd5,		/* walker bus cycle, waiting for ACK */
		S_BEND	= 4'd6,		/* walker bus cycle, waiting for ACK to drop */
		S_SPTE	= 4'd7,		/* got the system PTE of a process PTE */
		S_PTE	= 4'd8,		/* got the PTE */
		S_PTEW	= 4'd9,		/* PTE<M> written */
		S_ACC	= 4'd10,	/* the access itself, at PA */
		S_RESP	= 4'd11,	/* answer without a bus cycle (probe, TBCHK) */
		S_FLT	= 4'd12,	/* fault, held until the CPU strobe drops */
		S_ABORT	= 4'd13;	/* machine check: wait for the strobe to drop */

	reg [3:0]	state, bret;
	reg [31:0]	va, pte_va, pa, bdat, rdat;
	reg [1:0]	mode;
	reg		wr, probe, tbchk;
	reg		bstb, bwe;
	reg [31:0]	badr, bwdat;
	reg [31:0]	pte;

	wire		need_xlate = mapen & ~in_pmem;
	wire		thru = (state == S_IDLE) & ~in_probe & ~need_xlate;

	/* physical side */
	assign UT_STB_O = thru ? IN_STB_I :
			  (state == S_ACC) ? IN_STB_I : bstb;
	assign UT_WE_O  = (thru || state == S_ACC) ? IN_WE_I : bwe;
	assign UT_ADR_O = thru ? { 2'b00, IN_ADR_I[29:0] } :
			  (state == S_ACC) ? pa : badr;
	assign UT_DAT_O = (thru || state == S_ACC) ? IN_DAT_I : bwdat;

	/* virtual side */
	assign IN_ACK_O = (thru || state == S_ACC) ? UT_ACK_I :
			  (state == S_RESP) & IN_STB_I;
	assign IN_DAT_O = (thru || state == S_ACC) ? UT_DAT_I :
			  (state == S_RESP && IN_STB_I) ? rdat : 32'd0;

	assign progress = UT_ACK_I;

	/* TB read address: the address being looked up in the next state */
	always @* begin
		case (state)
		S_IDLE:	tb_ra = tbidx(IN_ADR_I);
		S_SRD:	tb_ra = tbidx(pte_va);
		default: tb_ra = tbidx(va);
		endcase
	end

	wire [7:0]	q_acc = prot_acc(q_prot);	/* TB entry */
	wire [7:0]	b_acc = prot_acc(bdat[30:27]);	/* PTE just read */
	wire		q_ok  = wr ? q_acc[{ 1'b1, mode }] : q_acc[{ 1'b0, mode }];
	wire		b_ok  = wr ? b_acc[{ 1'b1, mode }] : b_acc[{ 1'b0, mode }];

	/*
	 * tb_q and tb_vq hold the entry read in the previous clock: for va in
	 * S_LOOK (read in S_IDLE), for pte_va in S_SLOOK (read in S_SRD).
	 */
	wire		hit   = tb_vq && q_tag == va[30:17];
	wire		shit  = tb_vq && q_tag == pte_va[30:17];

	/*
	 * One update port for single valid bits: set when an entry is written
	 * (tb_we, the clock after S_SPTE, S_PTE or S_PTEW), clear for TBIS. The
	 * two never meet: TBIS is an MTPR, and the CPU cannot execute one while
	 * it waits for the access the MMU is translating.
	 */
	wire		tbis  = ipr_we && ipr_adr == `IPR_TBIS;
	wire [8:0]	tb_vi = tbis ? tbidx(ipr_dat) : tb_wa;
	wire [20:0]	vpn   = va[29:9];
	wire [20:0]	svpn  = pte_va[29:9];

	/*
	 * Fault, or for a probe the answer "not accessible", or for the
	 * console (which cannot take faults) a read of zero.
	 */
	task fail;
		input tnv;
		input [2:0] par;
		begin
			if (probe && !(tnv && par[1])) begin
				rdat <= 32'd0;
				state <= S_RESP;
			end else if (in_con) begin
				rdat <= 32'd0;
				state <= S_RESP;
			end else begin
				flt <= 1'b1;
				flt_va <= va;
				flt_par <= par;
				flt_tnv <= tnv;
				state <= S_FLT;
			end
		end
	endtask

	/* start a walker bus cycle; continue in state ret with the data */
	task buscyc;
		input [31:0] adr;
		input we;
		input [31:0] dat;
		input [3:0] ret;
		begin
			badr <= { 2'b00, adr[29:0] };
			bwe <= we;
			bwdat <= dat;
			bstb <= 1'b1;
			bret <= ret;
			state <= S_BUS;
		end
	endtask

	initial begin
		state = S_IDLE;
		flt = 1'b0;
		bstb = 1'b0;
		mapen = 1'b0;
		tb_v = 512'd0;
		tb_vq = 1'b0;
		tb_we = 1'b0;
	end

	always @(posedge clk) begin
		tb_we <= 1'b0;
		tb_vq <= tb_v[tb_ra];

		if (rst) begin
			state <= S_IDLE;
			flt <= 1'b0;
			bstb <= 1'b0;
			mapen <= 1'b0;
			tb_v <= 512'd0;
		end else begin
			/* MM register writes and TB flushes (never during an access) */
			if (ipr_we) begin
				case (ipr_adr)
				`IPR_P0BR: begin p0br <= { ipr_dat[31:2], 2'b00 }; tb_v[255:0] <= 256'd0; end
				`IPR_P0LR: begin p0lr <= ipr_dat[21:0]; tb_v[255:0] <= 256'd0; end
				`IPR_P1BR: begin p1br <= { ipr_dat[31:2], 2'b00 }; tb_v[255:0] <= 256'd0; end
				`IPR_P1LR: begin p1lr <= ipr_dat[21:0]; tb_v[255:0] <= 256'd0; end
				`IPR_SBR:  begin sbr <= { ipr_dat[31:2], 2'b00 }; tb_v <= 512'd0; end
				`IPR_SLR:  begin slr <= ipr_dat[21:0]; tb_v <= 512'd0; end
				`IPR_MAPEN: begin mapen <= ipr_dat[0]; tb_v <= 512'd0; end
				`IPR_TBIA: tb_v <= 512'd0;
				default: ;
				endcase
			end
			if (tbis || tb_we)
				tb_v[tb_vi] <= tb_we;

			case (state)
			S_IDLE: if (IN_STB_I && cpu_stb && (in_probe || need_xlate)) begin
				va <= IN_ADR_I;
				wr <= IN_WE_I | in_wint;
				probe <= in_probe & ~in_pmem;
				tbchk <= in_probe & in_pmem;
				mode <= in_con ? 2'd0 : in_mode;
				if (in_probe && !in_pmem && !mapen) begin
					rdat <= 32'd1;		/* no mapping: all accessible */
					state <= S_RESP;
				end else
					state <= S_LOOK;
			end

			S_LOOK: begin
				if (tbchk) begin
					rdat <= { 31'd0, hit };
					state <= S_RESP;
				end else if (hit) begin
					if (!q_ok) begin
						fail(1'b0, { wr, 2'b00 });
					end else if (probe) begin
						rdat <= 32'd1;
						state <= S_RESP;
					end else if (wr && !q_m) begin
						state <= S_WALK;	/* PTE<M> must be set */
					end else begin
						pa <= { 2'b00, q_pfn, va[8:0] };
						state <= S_ACC;
					end
				end else
					state <= S_WALK;
			end

			S_WALK: begin
				case (va[31:30])
				2'b10: begin
					if ({ 1'b0, vpn } >= slr)
						fail(1'b0, { wr, 2'b01 });
					else
						buscyc(sbr + { 9'd0, vpn, 2'b00 }, 1'b0, 32'd0, S_PTE);
				end
				2'b11: fail(1'b0, { wr, 2'b01 });
				2'b00: begin
					if ({ 1'b0, vpn } >= p0lr)
						fail(1'b0, { wr, 2'b01 });
					else begin
						pte_va <= p0br + { 9'd0, vpn, 2'b00 };
						state <= S_SRD;
					end
				end
				2'b01: begin
					if ({ 1'b0, vpn } < p1lr)
						fail(1'b0, { wr, 2'b01 });
					else begin
						pte_va <= p1br + { 9'd0, vpn, 2'b00 };
						state <= S_SRD;
					end
				end
				endcase
			end

			S_SRD: state <= S_SLOOK;

			S_SLOOK: begin
				if (shit) begin
					pa <= { 2'b00, q_pfn, pte_va[8:0] };
					buscyc({ 2'b00, q_pfn, pte_va[8:0] }, 1'b0, 32'd0, S_PTE);
				end else if (pte_va[31:30] != 2'b10 || { 1'b0, svpn } >= slr)
					fail(1'b0, { wr, 2'b11 });	/* PTE ref, length */
				else
					buscyc(sbr + { 9'd0, svpn, 2'b00 }, 1'b0, 32'd0, S_SPTE);
			end

			S_BUS: begin
				if (UT_ACK_I) begin
					bdat <= UT_DAT_I;
					bstb <= 1'b0;
					state <= S_BEND;
				end
				if (in_mcheck) begin
					bstb <= 1'b0;
					state <= S_ABORT;
				end
			end

			S_BEND: if (!UT_ACK_I) state <= bret;

			S_SPTE: begin
				/* system PTE that maps the process page table */
				if (!bdat[31])
					fail(1'b1, { wr, 2'b10 });	/* PTE ref, TNV */
				else begin
					tb_we <= 1'b1;
					tb_wa <= tbidx(pte_va);
					tb_wd <= { pte_va[30:17], bdat[20:0], bdat[30:27], bdat[26] };
					buscyc({ 2'b00, bdat[20:0], pte_va[8:0] }, 1'b0, 32'd0, S_PTE);
				end
			end

			S_PTE: begin
				pte <= bdat;
				if (probe) begin
					/* PROBE: protection decides, valid bit ignored */
					rdat <= { 31'd0, b_ok };
					state <= S_RESP;
				end else if (!b_ok)
					fail(1'b0, { wr, 2'b00 });
				else if (!bdat[31])
					fail(1'b1, { wr, 2'b00 });
				else if (wr && !bdat[26])
					/* set PTE<M>: rewrite the PTE where it was read */
					buscyc(badr, 1'b1, bdat | 32'h04000000, S_PTEW);
				else begin
					tb_we <= 1'b1;
					tb_wa <= tbidx(va);
					tb_wd <= { va[30:17], bdat[20:0], bdat[30:27], bdat[26] };
					pa <= { 2'b00, bdat[20:0], va[8:0] };
					state <= S_ACC;
				end
			end

			S_PTEW: begin
				tb_we <= 1'b1;
				tb_wa <= tbidx(va);
				tb_wd <= { va[30:17], pte[20:0], pte[30:27], 1'b1 };
				pa <= { 2'b00, pte[20:0], va[8:0] };
				state <= S_ACC;
			end

			S_ACC: if (!IN_STB_I) state <= S_IDLE;

			S_RESP: if (!IN_STB_I) state <= S_IDLE;

			S_FLT: if (!cpu_stb) begin
				flt <= 1'b0;
				state <= S_IDLE;
			end

			S_ABORT: if (!IN_STB_I) state <= S_IDLE;

			default: state <= S_IDLE;
			endcase
		end
	end

endmodule

`default_nettype wire

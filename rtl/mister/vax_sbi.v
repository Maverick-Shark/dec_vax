//============================================================================
//  vax_sbi.v - SBIA 0, the VAX 8600's ABus to SBI adapter: its registers,
//  CPU transactions to the SBI, DMA from the SBI to memory, and the
//  interrupt logic.
//
//  Sources: VAX 8600/8650 SBIA Technical Description (EK-DB86X-TD-002),
//  chapters 2 and 3 and appendix A; VAX 8600/8650 System Fault Isolation
//  Manual (EK-8600S-MM-004), M-03, M-04, A-01..A-11; DEC STD 032 appendix B.
//
//  CPU side. The MBox sends this adapter every CPU reference its physical
//  address memory map (PAMM) gives code 18 (I/O adapter 0); the console
//  maps 2000 0000 - 21FF FFFF there. The adapter sees the ABus longword
//  address PA<29:2>, the byte mask and decides:
//
//    802 0000 - 802 0013   its registers (2008 0000 - 2008 004C)
//    802 0024 - 802 002E   its interrupt vector registers (read only)
//    802 0014 - 802 FFFF   anything else: address error
//    everything else       a CPU transaction on the SBI: the nexus
//                          registers (2000 0000 + 2000 * TR), Unibus space
//                          (2010 0000), or SBI memory space (PA<29> clear),
//                          which only this adapter's own DMA side answers
//
//  A CPU transaction that fails ends with ABUS CPU BUF ERR, which the MBox
//  turns into a machine check (CP I/O buffer error, MSTAT2<02>):
//
//    - address error: a nonexistent adapter register, a write to a vector
//      register, or an SBI reference (an interrupt summary read too) with
//      CSR<30> (SBI cycles out) clear (ERRSUM<23,20,19>);
//    - SBI timeout: no acknowledge in 512 SBI cycles, 102.4 us (8 with
//      DCR<0>, never with DCR<4>) (SBIER<12>, <11:10> = 00 no response or
//      01 busy, ERRSUM<23>);
//    - error confirmation from the nexus (SBIER<08>, ERRSUM<23>).
//
//  Read data that comes back marked bad (a DMA the MBox aborted, see below,
//  or read data substitute from a nexus) is passed on as such (bad): the
//  MBox's ABus bad data code.
//
//  ERRSUM<23> (CPU buffer error lock) freezes ERRSUM<31:26> (command and
//  length of the last CPU transaction), SBIER<12:10,08> and TOADR until
//  software writes 1 to it; while it is clear, those follow every CPU
//  transaction, the one reading them included.
//
//  CPU reads are a word or a longword (ABus length even word, odd word,
//  longword; the SBI mask 0011, 1100, 1111); writes carry their byte mask.
//
//  DMA side. A nexus that is an SBI master (and this adapter's own CPU
//  transactions to SBI memory space: quadclear) gets an answer from the
//  adapter's receiver when CSR<29> (SBI cycles in) is set, the address is
//  in memory space (SBI address bit 27 clear) and below the memory
//  separator, CNF<29:20> megabytes; otherwise nothing answers it. The
//  command goes into a transaction buffer - I for the interlocked ones, A,
//  B, C in turn for the others, skipping those DCR<19:16> forces busy -
//  whose command/address and ID registers (2008 0010 - 002C) record it
//  unless an error has locked them, and then to the MBox (dma_*), one
//  longword at a time: read masked and write masked one longword, extended
//  read and extended write masked a quadword. A reference the MBox aborts
//  (its PAMM code is not a memory array) sets the buffer's "MBox detected
//  error" bit in ERRSUM, which requests the adapter error interrupt; read
//  data goes back marked bad. An interlock read masked holds the memory
//  interlock until the interlock write masked (another interlock read gets
//  busy meanwhile); none within 512 SBI cycles is an interlock timeout,
//  ERRSUM<03>.
//
//  Quadclear: a CPU write to 2008 004C puts the longword written, which
//  must be 1011 (extended write masked) and a quadword address, on the SBI
//  as a command with two longwords of zeros; this adapter's receiver takes
//  it like any DMA (EK-DB86X-TD-002 3.7), so the quadword in memory is
//  cleared. Nothing answers it beyond the memory separator: a timeout.
//
//  Interrupts. The adapter presents the EBox with the highest level it has
//  a request at (ABUS IPR RETURN), if CSR<31> (master interrupt enable) is
//  set: 1C SBI fault or adapter error, 1B SBI alert, 19 silo compare, 17-14
//  the SBI REQ7-REQ4 lines. The REQ lines are levels: a nexus keeps its
//  request until software clears the condition. To take an interrupt the
//  EBox reads the level's vector register (2008 0080 + 4 * (IPL - 10)); for
//  IPL 14-17 that is an interrupt summary read on the SBI, and the vector
//  is 100 + 40 * (IPL - 14) + 4 * TR of the responding nexus with the
//  highest priority (the lowest TR); no response gives 0, a passive
//  release. The other levels have fixed vectors: 50, 58, 5C or 60, 64.
//
//  Not modelled: the SBI silo (reads as zero), the silo comparator's
//  conditional lock modes (the unconditional one counts SBI cycles and
//  locks), parity errors and the maintenance register's fault injection,
//  loopback mode, SBI fault/alert/fail from nexus, the unjam sequence
//  (nothing in this model can jam the SBI), the DMA buffers working in
//  parallel (one command at a time is taken).
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_sbi #(
	parameter CLK_HZ = 50000000,
	parameter MEMMB  = 32            // memory separator the console loads
) (
	input             clk,
	input             rst,           // processor initialization

	// ABus, CPU side: the references the PAMM sends to this adapter
	input             stb,
	input             we,
	input      [31:0] adr,
	input      [31:0] wdat,
	input       [3:0] sel,           // byte mask
	output     [31:0] rdat,
	output            ack,           // ABUS CPU BUF DONE
	output            err,           // ABUS CPU BUF ERR
	output            bad,           // read data marked bad (with ack)
	output      [4:0] ipl,           // ABUS IPR RETURN: highest request, 0 none

	// SBI: a CPU transaction for the nexus, held until a confirmation
	output            sbi_cmd,
	output      [3:0] sbi_fn,        // SBI function: 0001 read, 0010 write masked
	output     [27:0] sbi_adr,       // SBI longword address
	output      [3:0] sbi_msk,
	output     [31:0] sbi_wdat,
	output reg        sbi_unjam,     // one clock: SBI UNJAM (a write to UNJAM)
	input             nx_ack,        // done (read data on nx_rdat)
	input             nx_busy,       // busy confirmation
	input             nx_err,        // error confirmation
	input             nx_rds,        // with nx_ack: read data substitute
	input      [31:0] nx_rdat,

	// SBI: a nexus master's transaction (DMA), held until dm_done or dm_nr
	input             dm_req,
	input       [3:0] dm_fn,
	input      [27:0] dm_adr,        // SBI longword address
	input       [3:0] dm_msk,        // first longword's mask
	input       [3:0] dm_msk2,       // second longword's (extended write)
	input      [63:0] dm_wdat,
	input       [4:0] dm_id,         // the master's SBI ID (its TR)
	output reg        dm_done,       // one clock: done, read data on dm_rdat
	output reg        dm_nr,         // one clock: no response
	output reg        dm_busy,       // one clock: busy (interlocked), retry
	output reg        dm_rds,        // with dm_done: read data marked bad
	output reg [63:0] dm_rdat,
	output            dm_idle,       // the receiver has no master's command

	// to the MBox: DMA references, one longword each (physical address)
	output reg        dma_stb,
	output reg        dma_we,
	output reg [31:0] dma_adr,
	output reg [31:0] dma_wdat,
	output reg  [3:0] dma_sel,
	input      [31:0] dma_rdat,
	input             dma_ack,
	input             dma_nxm,       // the MBox aborted it (PAMM code 1x)

	// SBI interrupt requests REQ4-REQ7: bit n is the nexus at TR n
	input      [15:0] req4,
	input      [15:0] req5,
	input      [15:0] req6,
	input      [15:0] req7
);

	/* ------------------------------------------------- SBI cycle clock */
	localparam integer SBIDIV = CLK_HZ / 5000000;       // 200 ns per SBI cycle
	reg  [7:0] div;
	wire       tick = (div == SBIDIV - 1);
	always @(posedge clk)
		div <= (rst || tick) ? 8'd0 : div + 8'd1;

	/* ----------------------------------------------------------- decode */
	wire [27:0] la    = adr[29:2];                  // ABus longword address
	wire        in_local = (la[27:16] == 12'h802);  // 2008 0000 - 200B FFFF
	wire [15:0] lr    = la[15:0];
	wire        is_reg = in_local && (lr <= 16'h0013);
	wire        vec_br = (lr[15:2] == 14'h0009);    // 24-27: IPL 14-17
	wire        vec_lo = (lr == 16'h0029) || (lr == 16'h002B) ||
	                     (lr == 16'h002C) || (lr == 16'h002E);
	wire        is_qclr = is_reg && (lr[4:0] == 5'h13) && we;

	// ABus length of a CPU transaction: even word, odd word, longword
	wire  [1:0] len_now = (sel[3:2] == 2'b00) ? 2'b01 :
	                      (sel[1:0] == 2'b00) ? 2'b10 : 2'b11;

	/* -------------------------------------------------------- registers */
	reg   [9:0] cnf_msr;        // CNF<29:20> memory separator (megabytes)
	reg   [2:0] csr;            // CSR<31:29>: MIE, SBI cycles out, in
	reg   [3:0] es_cmd;         // ERRSUM<31:28> command of the last CPU C/A
	reg   [1:0] es_len;         // ERRSUM<27:26> its length
	reg         es_lock;        // ERRSUM<23> CPU buffer error lock
	reg         es_ade;         // ERRSUM<20> CPU address error
	reg         es_eca;         // ERRSUM<19> error on command/address
	reg         es_mult;        // ERRSUM<16> multiple CPU error
	reg  [14:0] es_dma;         // ERRSUM<14:0> DMA transaction buffer errors
	reg   [3:0] dcr_busy;       // DCR<19:16> force DMA buffer busy (C B A I)
	reg   [3:0] dcr;            // DCR<4:1>: no timeout, quad data, loop, PE
	reg         dcr_short;      // DCR<0> short timeout (reads as 0)
	reg         er_tmo;         // SBIER<12> CP timeout
	reg   [1:0] er_sta;         // SBIER<11:10> timeout status
	reg         er_cnf;         // SBIER<08> CPU SBI error confirmation
	reg  [27:0] toadr;          // TOADR<27:0>
	reg         fs_ie;          // FS<18> fault interrupt enable
	reg  [15:0] sc;             // SC<31:16>: lock, IE, uncond, code, cmd, tag, count
	reg  [15:0] sc_mtr;         // SC<15:0> maintenance TR (write only)
	reg  [31:0] mt;             // maintenance register
	reg  [31:0] wdl;            // write data latch (last CPU write data)
	reg  [31:0] dbuf_ca [0:3];  // DMA command/address, buffers I A B C
	reg   [4:0] dbuf_id [0:3];  // DMA ID

	localparam [31:0] MT_RW = 32'hFF80091F;

	// the command and length a transaction loads into ERRSUM<31:26>:
	// read 0001 or write mask 1101
	wire  [3:0] cmd_now = we ? 4'b1101 : 4'b0001;

	// what ERRSUM<31:26> and TOADR read: a read loads them first
	wire  [5:0] rd_cl    = es_lock ? {es_cmd, es_len} : {cmd_now, len_now};
	wire [27:0] rd_toadr = es_lock ? toadr : la;

	wire        local_err = |es_dma;        // DMA errors: a local interrupt

	// the ERRSUM bits of a buffer's errors: MBox detected, I-buffer timeout
	function [14:0] es_mbox(input [1:0] b);
		case (b)
		2'd0: es_mbox = 15'h0001;
		2'd1: es_mbox = 15'h0010;
		2'd2: es_mbox = 15'h0100;
		default: es_mbox = 15'h1000;
		endcase
	endfunction
	function [14:0] es_bits(input [1:0] b);
		case (b)
		2'd0: es_bits = 15'h000F;
		2'd1: es_bits = 15'h0070;
		2'd2: es_bits = 15'h0700;
		default: es_bits = 15'h7000;
		endcase
	endfunction

	reg  [31:0] reg_q;
	always @* begin
		case (lr[4:0])
		5'h00: reg_q = {2'b00, cnf_msr, 12'h000, 4'b0001, 4'b0000};
		5'h01: reg_q = {csr, 1'b0, 4'b0000, 24'h000000};
		5'h02: reg_q = {rd_cl, 2'b00, es_lock, 2'b00, es_ade, es_eca,
		                1'b0, 1'b0, es_mult, 1'b0, es_dma};
		5'h03: reg_q = {12'h000, dcr_busy, 11'h000, dcr, 1'b0};
		5'h04: reg_q = dbuf_ca[0];
		5'h05: reg_q = {27'd0, dbuf_id[0]};
		5'h06: reg_q = dbuf_ca[1];
		5'h07: reg_q = {27'd0, dbuf_id[1]};
		5'h08: reg_q = dbuf_ca[2];
		5'h09: reg_q = {27'd0, dbuf_id[2]};
		5'h0A: reg_q = dbuf_ca[3];
		5'h0B: reg_q = {27'd0, dbuf_id[3]};
		5'h0D: reg_q = {19'h0, er_tmo, er_sta, 1'b0, er_cnf, 8'h00};
		5'h0E: reg_q = {4'h0, rd_toadr};
		5'h0F: reg_q = {13'h0, fs_ie, 2'b00, 16'h0000};
		5'h10: reg_q = {sc, 16'h0000};
		5'h11: reg_q = mt & MT_RW;
		default: reg_q = 32'd0;     // silo, unjam, quadclear
		endcase
	end

	/* ------------------------------------------------------- interrupts */
	wire        mreq = mt[4];                       // MAINT REQ ENA
	wire  [3:0] br   = {|req7 | (mreq & sc_mtr[7]), |req6 | (mreq & sc_mtr[6]),
	                    |req5 | (mreq & sc_mtr[5]), |req4 | (mreq & sc_mtr[4])};
	wire        alert = mreq & sc_mtr[3];
	wire        comp  = sc[15] & sc[14];            // SC<31> lock and <30> IE
	wire        flt_e = local_err;                  // (no SBI faults here)

	assign ipl = !csr[2] ? 5'h00 :
	             flt_e   ? 5'h1C :
	             alert   ? 5'h1B :
	             comp    ? 5'h19 :
	             br[3]   ? 5'h17 :
	             br[2]   ? 5'h16 :
	             br[1]   ? 5'h15 :
	             br[0]   ? 5'h14 : 5'h00;

	// interrupt summary read for BR4-BR7: the responding nexus (and, with
	// MAINT<01> force ISR data, the write data latch); TR 1 first
	wire [15:0] isr = (lr[1:0] == 2'd0 ? req4 : lr[1:0] == 2'd1 ? req5 :
	                   lr[1:0] == 2'd2 ? req6 : req7) |
	                  (mt[1] ? wdl[15:0] : 16'h0000);
	reg   [3:0] isr_tr;
	integer     i;
	always @* begin
		isr_tr = 4'd0;
		for (i = 15; i >= 1; i = i - 1)
			if (isr[i]) isr_tr = i[3:0];
	end

	reg  [31:0] vec_q;
	always @* begin
		case (lr[3:0])
		4'h9: vec_q = 32'h50;                       // silo compare
		4'hB: vec_q = 32'h58;                       // SBI alert
		4'hC: vec_q = local_err ? 32'h60 : 32'h5C;  // adapter error, SBI fault
		4'hE: vec_q = 32'h64;                       // SBI fail
		default: vec_q = (isr_tr != 4'd0) ?
		           {23'd0, 1'b1, lr[1:0], isr_tr, 2'b00} : 32'd0;
		endcase
	end

	/* -------------------------------------------- CPU transactions */
	localparam [1:0] S_IDLE = 2'd0, S_SBI = 2'd1, S_DONE = 2'd2;
	reg   [1:0] st;
	reg         q_ack, q_err, q_bad;
	reg  [31:0] q;
	reg   [9:0] tmo;            // SBI cycles waited
	reg         bsy;            // a busy confirmation was seen
	reg         t_we;
	reg   [3:0] t_fn;           // SBI function of the CPU's transaction
	reg  [27:0] t_adr;
	reg  [31:0] t_wdat;
	reg   [3:0] t_msk;
	reg         t_qclr;         // a quadclear: two longwords of zeros

	wire        tmo_lim = dcr_short ? (tmo == 10'd8) : (tmo == 10'd512);
	wire        t_mem   = !t_adr[27];       // SBI memory space: the receiver

	// the receiver's answer to the CPU's own memory-space transaction
	reg         cr_ack, cr_bad, cr_busy;
	reg  [31:0] cr_rdat;

	assign sbi_cmd  = (st == S_SBI) && !t_mem;
	assign sbi_fn   = t_fn;
	assign sbi_adr  = t_adr;
	assign sbi_msk  = t_msk;
	assign sbi_wdat = t_wdat;

	assign rdat = (stb && q_ack) ? q : 32'd0;
	assign ack  = stb && q_ack;
	assign err  = stb && q_err;
	assign bad  = stb && q_ack && q_bad;

	// a CPU transaction failed: ERRSUM<23> locks the error state
	task cpu_error;
		begin
			q_err   <= 1'b1;
			es_lock <= 1'b1;
			st      <= S_DONE;
		end
	endtask

	/* -------------------------------------------------- the receiver */
	localparam [1:0] R_IDLE = 2'd0, R_MEM = 2'd1, R_END = 2'd2;
	reg   [1:0] rs;
	assign dm_idle = (rs == R_IDLE);
	reg         r_cpu;          // the command is the CPU transmitter's
	reg   [3:0] r_fn;
	reg  [27:0] r_adr;
	reg   [3:0] r_msk, r_msk2;
	reg  [63:0] r_wdat;
	reg   [1:0] r_buf;          // transaction buffer: 0 I, 1 A, 2 B, 3 C
	reg         r_two, r_half;  // a quadword; on its second longword
	reg         r_rds;
	reg  [63:0] r_rdat;
	reg   [1:0] r_next;         // the next of A, B, C
	reg         ilk;            // memory interlock held
	reg   [9:0] ilk_tmo;

	// the command the receiver looks at: a nexus master's first, else the
	// CPU transmitter's when it is for memory space. A master sees dm_done
	// a clock after it is set and drops dm_req only then: that clock is not
	// a new command.
	wire        c_dm   = dm_req && !dm_done;
	wire        c_cpu  = !c_dm && st == S_SBI && t_mem && !cr_ack;
	wire  [3:0] c_fn   = c_dm ? dm_fn  : t_fn;
	wire [27:0] c_adr  = c_dm ? dm_adr : t_adr;
	wire        c_ilkr = (c_fn == 4'b0100);         // interlock read masked
	wire        c_ilk  = c_ilkr || (c_fn == 4'b0111);
	wire        c_sep  = cnf_msr[9] || (c_adr[26:18] < cnf_msr[8:0]);
	wire        c_take = csr[0] && !c_adr[27] && c_sep;
	// a free buffer: I for interlocked commands, else the next free of A-C
	wire  [1:0] nb1 = r_next;
	wire  [1:0] nb2 = (r_next == 2'd3) ? 2'd1 : r_next + 2'd1;
	wire  [1:0] nb3 = (nb2 == 2'd3) ? 2'd1 : nb2 + 2'd1;
	wire        b_ok = c_ilk ? !dcr_busy[0] :
	                   !(dcr_busy[nb1] && dcr_busy[nb2] && dcr_busy[nb3]);
	wire  [1:0] b_sel = c_ilk ? 2'd0 : !dcr_busy[nb1] ? nb1 :
	                    !dcr_busy[nb2] ? nb2 : nb3;

	// ERRSUM<14:0> changes from several places in one clock: collected here
	reg  [14:0] es_set, es_clr;

	always @(posedge clk) begin
		dm_done <= 1'b0;
		dm_nr   <= 1'b0;
		sbi_unjam <= 1'b0;
		dm_busy <= 1'b0;
		cr_busy <= 1'b0;
		es_set = 15'd0;
		es_clr = 15'd0;
		if (rst) begin
			// processor initialization: the adapter as the console
			// leaves it after a boot
			st        <= S_IDLE;
			q_ack     <= 1'b0;
			q_err     <= 1'b0;
			q_bad     <= 1'b0;
			cnf_msr   <= MEMMB;
			csr       <= 3'b111;
			es_cmd    <= 4'd0;
			es_len    <= 2'd0;
			es_lock   <= 1'b0;
			es_ade    <= 1'b0;
			es_eca    <= 1'b0;
			es_mult   <= 1'b0;
			es_dma    <= 15'd0;
			dcr_busy  <= 4'd0;
			dcr       <= 4'd0;
			dcr_short <= 1'b0;
			er_tmo    <= 1'b0;
			er_sta    <= 2'd0;
			er_cnf    <= 1'b0;
			toadr     <= 28'd0;
			fs_ie     <= 1'b0;
			sc        <= 16'd0;
			sc_mtr    <= 16'd0;
			mt        <= 32'd0;
			wdl       <= 32'd0;
			dbuf_ca[0] <= 32'd0; dbuf_ca[1] <= 32'd0;
			dbuf_ca[2] <= 32'd0; dbuf_ca[3] <= 32'd0;
			dbuf_id[0] <= 5'd0;  dbuf_id[1] <= 5'd0;
			dbuf_id[2] <= 5'd0;  dbuf_id[3] <= 5'd0;
			rs        <= R_IDLE;
			r_next    <= 2'd1;
			ilk       <= 1'b0;
			dma_stb   <= 1'b0;
			cr_ack    <= 1'b0;
		end else begin
			// silo comparator, unconditional lock: count SBI cycles
			if (tick && sc[13] && !sc[15]) begin
				if (sc[3:0] == 4'hF)
					sc[15] <= 1'b1;
				else
					sc[3:0] <= sc[3:0] + 4'd1;
			end

			// memory interlock: an interlock write masked must follow
			// within 512 SBI cycles
			if (ilk && tick) begin
				if (ilk_tmo == 10'd512) begin
					ilk <= 1'b0;
					if (!(es_dma & es_bits(2'd0)))
						es_set = es_set | 15'h0008;
				end else
					ilk_tmo <= ilk_tmo + 10'd1;
			end

			/* ---------------------------- CPU transactions */
			case (st)
			S_IDLE: if (stb && !q_ack && !q_err) begin
				// the command/address latch is loaded
				if (!es_lock) begin
					es_cmd <= cmd_now;
					es_len <= len_now;
					toadr  <= la;
				end
				if (we)
					wdl <= wdat;

				if (in_local ? !(is_reg || (!we && (vec_lo || (vec_br && csr[1]))))
				          : !csr[1]) begin
					// address error
					if (es_lock)
						es_mult <= 1'b1;
					es_ade <= 1'b1;
					es_eca <= 1'b1;
					cpu_error;
				end else if (is_qclr) begin
					// quadclear: an extended write masked of
					// zeros, on the SBI
					t_we   <= 1'b1;
					t_fn   <= wdat[31:28];
					t_adr  <= wdat[27:0];
					t_wdat <= 32'd0;
					t_msk  <= 4'b1111;
					t_qclr <= 1'b1;
					tmo    <= 10'd0;
					bsy    <= 1'b0;
					st     <= S_SBI;
				end else if (in_local) begin
					q     <= is_reg ? reg_q : vec_q;
					q_ack <= 1'b1;
					q_bad <= 1'b0;
					st    <= S_DONE;
					if (we)
						case (lr[4:0])
						5'h00: cnf_msr <= wdat[29:20];
						5'h01: csr <= wdat[31:29];
						5'h02: begin
							if (wdat[23]) begin
								es_lock <= 1'b0;
								es_ade  <= 1'b0;
								es_eca  <= 1'b0;
								es_mult <= 1'b0;
							end
							es_clr = wdat[14:0] & 15'h777F;
						end
						5'h03: begin
							dcr_busy  <= wdat[19:16];
							dcr       <= wdat[4:1];
							dcr_short <= wdat[0];
						end
						5'h0D: if (wdat[12]) begin
							er_tmo <= 1'b0;
							er_sta <= 2'd0;
							er_cnf <= 1'b0;
						end
						5'h0F: fs_ie <= wdat[18];
						5'h10: begin
							sc[14:0] <= wdat[30:16];
							if (wdat[19:16] != 4'hF)
								sc[15] <= 1'b0;
							sc_mtr   <= wdat[15:0];
						end
						5'h11: mt <= wdat & MT_RW;
						5'h12: sbi_unjam <= 1'b1;
						default: ;  // read-only
						endcase
				end else begin
					// a transaction on the SBI: reads are a word
					// or a longword, writes carry their mask
					t_we   <= we;
					t_fn   <= we ? 4'b0010 : 4'b0001;
					t_adr  <= la;
					t_wdat <= wdat;
					t_msk  <= we ? sel : (len_now == 2'b01 ? 4'b0011 :
					          len_now == 2'b10 ? 4'b1100 : 4'b1111);
					t_qclr <= 1'b0;
					tmo    <= 10'd0;
					bsy    <= 1'b0;
					st     <= S_SBI;
				end
			end

			S_SBI: begin
				if (nx_busy || cr_busy)
					bsy <= 1'b1;
				if (cr_ack) begin
					// this adapter's receiver answered
					cr_ack <= 1'b0;
					q      <= t_we ? 32'd0 : cr_rdat;
					q_bad  <= cr_bad && !t_we;
					q_ack  <= 1'b1;
					st     <= S_DONE;
				end else if (!t_mem && nx_ack) begin
					q     <= t_we ? 32'd0 : nx_rdat;
					q_bad <= nx_rds && !t_we;   // read data substitute
					q_ack <= 1'b1;
					st    <= S_DONE;
				end else if (!t_mem && nx_err) begin
					// error confirmation
					if (!es_lock)
						er_cnf <= 1'b1;
					cpu_error;
				end else if (tick && !dcr[3] && !(t_mem && rs != R_IDLE)) begin
					if (tmo_lim) begin
						// SBI timeout
						if (!es_lock) begin
							er_tmo <= 1'b1;
							er_sta <= {1'b0, bsy | nx_busy};
						end
						cpu_error;
					end else
						tmo <= tmo + 10'd1;
				end
			end

			default: if (!stb) begin           // S_DONE: until the MBox lets go
				q_ack <= 1'b0;
				q_err <= 1'b0;
				q_bad <= 1'b0;
				st    <= S_IDLE;
			end
			endcase

			/* ---------------------------------- the receiver */
			case (rs)
			R_IDLE: if (c_dm || c_cpu) begin
				if (!c_take) begin
					// not for this adapter: no response
					if (c_dm)
						dm_nr <= 1'b1;
				end else if ((c_ilkr && ilk) || !b_ok) begin
					// interlocked, or no buffer free: busy
					if (c_dm)
						dm_busy <= 1'b1;
					else
						cr_busy <= 1'b1;
				end else begin
					r_cpu  <= c_cpu;
					r_fn   <= c_fn;
					r_adr  <= c_adr;
					r_msk  <= c_dm ? dm_msk : t_msk;
					r_msk2 <= c_dm ? dm_msk2 : 4'b1111;
					r_wdat <= c_dm ? dm_wdat : {32'd0, t_wdat};
					r_buf  <= b_sel;
					r_two  <= c_fn[3];          // extended: a quadword
					r_half <= 1'b0;
					r_rds  <= 1'b0;
					if (!c_ilk)
						r_next <= (b_sel == 2'd3) ? 2'd1 : b_sel + 2'd1;
					// the buffer records the command unless an
					// error has locked it
					if (!(es_dma & es_bits(b_sel))) begin
						dbuf_ca[b_sel] <= {c_fn, c_adr};
						dbuf_id[b_sel] <= c_dm ? dm_id : 5'b10000;
					end
					if (c_ilkr) begin
						ilk     <= 1'b1;
						ilk_tmo <= 10'd0;
					end else if (c_fn == 4'b0111)
						ilk     <= 1'b0;
					// the first longword to the MBox
					dma_stb  <= 1'b1;
					dma_we   <= c_fn[1];        // 0010, 0111, 1011
					dma_adr  <= {2'b00, c_fn[3] ? {c_adr[27:1], 1'b0} :
					             c_adr, 2'b00};
					dma_wdat <= c_dm ? dm_wdat[31:0] : t_wdat;
					dma_sel  <= c_fn[1] ? (c_dm ? dm_msk : t_msk) : 4'b1111;
					rs       <= R_MEM;
				end
			end

			R_MEM: if (dma_ack || dma_nxm) begin
				dma_stb <= 1'b0;
				if (dma_nxm) begin
					// the MBox aborted it: the buffer's error
					if (!(es_dma & es_bits(r_buf)))
						es_set = es_set | es_mbox(r_buf);
					r_rds <= 1'b1;
				end
				if (r_half)
					r_rdat[63:32] <= dma_rdat;
				else
					r_rdat[31:0]  <= dma_rdat;
				if (r_two && !r_half && !dma_nxm)
					r_half <= 1'b1;         // the second longword next
				else
					rs <= R_END;
			end else if (!dma_stb) begin
				// the second longword of a quadword
				dma_stb  <= 1'b1;
				dma_adr  <= {2'b00, r_adr[27:1], 1'b1, 2'b00};
				dma_wdat <= r_wdat[63:32];
				dma_sel  <= dma_we ? r_msk2 : 4'b1111;
			end

			default: begin                  // R_END: answer the master
				if (r_cpu) begin
					cr_ack  <= 1'b1;
					cr_bad  <= r_rds && !r_fn[1];   // read data only
					cr_rdat <= r_rdat[31:0];
				end else begin
					dm_done <= 1'b1;
					dm_rds  <= r_rds;
					dm_rdat <= r_rdat;
				end
				rs <= R_IDLE;
			end
			endcase

			es_dma <= (es_dma & ~es_clr) | es_set;
		end
	end

endmodule

`default_nettype wire

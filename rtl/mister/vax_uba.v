//============================================================================
//  vax_uba.v - the DW780 Unibus adapter (UBA): a nexus on the SBI that
//  connects a Unibus, the first one of a VAX 8600 (TR 3, Unibus 0).
//
//  Sources: DW780 Unibus Adapter Technical Description (EK-DW780-TD-001),
//  chapters 2 and 3 and appendix A (longword access mode); VAX-11/780
//  Maintenance Handbook (EK-VAXV2-HB-002), the UBA registers and the
//  backpanel jumpers (the first DW780: TR 3, adapter 0, its own interrupts
//  on BR4); VAX Hardware Handbook (1986), the 8600's Unibus subsystem.
//
//  Address space. Registers at 2000 6000 (SBI longword 800 1800): the SBI
//  longword address <14:11> is the TR, <10:0> the register:
//
//    000 CNFGR <31:26> SBI faults (never set here), <23> adapter power down,
//              <22> adapter power up, <18> Unibus INIT asserted, <17> Unibus
//              power down, <16> Unibus initialization complete (write 1 to
//              clear), <7:0> adapter code 28 + adapter number
//    001 CR    <30:26> map register disable, <6> interrupt field switch,
//              <5> BR interrupt enable, <4> Unibus to SBI error interrupt
//              enable, <3> SBI to Unibus error interrupt enable, <2>
//              configuration interrupt enable, <1> Unibus power fail, <0>
//              adapter init (self clearing)
//    002 SR    <27:24> BRRVR 7-4 full (read only), <10> read data timeout,
//              <9> read data substitute, <8> corrected read data, <7>
//              command transmit error, <6> command transmit timeout, <5> data
//              path parity error, <4> invalid map register, <3> map register
//              parity failure, <2> lost error bit, <1> Unibus select
//              timeout, <0> Unibus slave sync timeout (write 1 to clear)
//    003 DCR   <31> spare, <30> disable interrupts, <29> defeat map parity,
//              <28> defeat data path parity, <27> microsequencer OK (read
//              only), <23:0> CNFGR<23:0> (read only)
//    004, 006  FMER  <8:0> map register of the failing DMA (read only)
//    005, 007  FUBAR <15:0> Unibus address <17:2> of the failing
//              software initiated transfer (read only)
//    008-00B   BRSVR 0-3, <15:0> read/write, no effect
//    00C-00F   BRRVR 4-7 <31> adapter interrupt request, <15:0> the vector
//              of the device interrupting at BR4-BR7 (read only)
//    010-01F   DPR 0-15: <31> buffer not empty (write 1: purge), <30>
//              buffer transfer error (write 1 to clear), <29> data path
//              function (1 DMA write), <23:16> buffer state, <15:0> Unibus
//              address <17:2> of the last DMA write; DPR 0 reads 0
//    200-3EF   map registers 0-495: <31> valid, <30:26> read/write (<26>
//              longword access enable), <25> byte offset, <24:21> data path
//              (0 direct, 1-15 buffered), <20:0> SBI page (<20> is SBI
//              address <27>, I/O space)
//
//  (TD 2.5.1, 2.9; offsets 080-7FC, FC0-FFC and 1000-1FFC are reserved:
//  no response.) The registers take reads of any length and return the
//  longword; writes write the longword; a write to FMER, FUBAR or a BRRVR
//  gets an error confirmation, so does an extended function (TD 3.4.7.2).
//
//  Unibus space: SBI address <27> and <18> set, <26:19> clear, <17:16> the
//  adapter number: 2010 0000 - 2013 FFFF for Unibus 0, SBI address <15:0>
//  is Unibus address <17:2>. The mask and function give UA<1:0> and the
//  Unibus function (TD table 2-7): a read of a byte or a word is DATI of
//  the word, a write of a byte DATOB, of a word DATO, interlock read DATIP;
//  any other mask (a longword, an unaligned word) gets an error
//  confirmation. The adapter arbitrates for the Unibus as its highest NPR
//  device; not master within 51.2 us is Unibus select timeout, no slave
//  sync within 12.8 us Unibus slave sync timeout: FUBAR keeps the address,
//  a read returns zeros (TD 2.5.2.4, 3.5.6). A write is acknowledged on
//  the SBI at once and done on the Unibus afterwards.
//
//  Confirmations (TD figure 3-35): the in-progress flags UIP (Unibus in
//  progress), RIP (read data owed), AIP (the microsequencer busy with a
//  register) and RIFF (interlock read done, write to come) decide between
//  ACK and BSY for every command; CNFGR, CR, SR and DCR writes always ACK.
//  During the 500 us of the adapter initialization routine only CNFGR and
//  DCR can be read and CNFGR, CR, SR and DCR written: everything else BSY.
//
//  DMA (TD 2.6, 3.3). A Unibus master's cycle to an address below the I/O
//  page whose map register is not disabled (CR<30:26>) is mapped: UA<17:9>
//  selects the map register; not valid is IVMR, no slave sync. Direct data
//  path: each DATI, DATIP, DATO, DATOB is one SBI read masked, interlock
//  read masked, write masked or interlock write masked of its word or byte
//  (TD table 2-9). Buffered data paths 1-15: a quadword buffer each. Writes
//  collect in the buffer; writing its last byte sends it to memory (write
//  masked, or extended write masked when bytes 4-7 have data, the masks
//  from the buffer state); a purge (DPR<31> written 1) sends what is left.
//  Reads: an empty buffer reads the quadword (extended read) or, from word
//  2 on, the longword (read masked); the next words come from the buffer;
//  reading the last word prefetches the next quadword. With byte offset
//  (map register <25>) the SBI address is the Unibus address plus one.
//  Longword access mode (map register <26>, TD appendix A): longword
//  reads, one SBI write when the high word (or byte 3) is written, no
//  prefetch, no purge. Errors lock the DMA error field of SR (RDTO, RDS,
//  CXTER, CXTMO, DPPE, IVMR, MRPF) and FMER; another one while it is locked
//  is the lost error bit. A buffer write or a purge that fails sets the
//  DPR's buffer transfer error, which stops that buffer until cleared.
//
//  The CPU reaches the adapter's own DMA side through the Unibus: a
//  reference to Unibus space below the I/O page with a valid map register
//  goes out on the Unibus and comes back to memory (wraparound, TD 1.9.2).
//
//  Interrupts (TD 2.7). The adapter's own requests go on BR4 (the first
//  DW780's jumpers): status errors with CR<4> or <3>, the configuration
//  register's power and init bits with CR<2>; a level until software clears
//  them. Unibus BR4-BR7 pass to SBI REQ4-REQ7 with CR<6> and <5> (and DCR<30>
//  clear). Reading BRRVR n fetches the vector of the device interrupting
//  at BRn (bus grant, INTR) and returns it, with <31> set if the adapter's
//  own request is pending on that level; no request, or a passive release,
//  returns 0.
//
//  Initialization. Adapter init (CR<0>) clears the map, data path, status,
//  control, BRSVR and DCR registers, runs the microsequencer's
//  initialization for 500 us and a power fail sequence on the Unibus: AC
//  LO (CNFGR<17>, <16> cleared), 5 ms later DC LO and INIT (<18>), then
//  power up, INIT released 10 ms and AC LO 20 ms later: <16> set, <18:17>
//  cleared (about 25 ms, TD 2.9.2). CR<1> does the same power fail, the
//  Unibus staying down while it is set. SBI UNJAM clears CR<5:2> and starts
//  the power fail sequence (TD 2.8.6). Processor initialization leaves the
//  adapter as an adapter init long finished: CNFGR 0001 0028 (Unibus
//  initialized, no power up bit), every other register clear, no interrupt.
//
//  The Unibus. ub_* is the bus as device registers see it, with the
//  adapter (or a device doing DMA) as master; dv_* is a device that is
//  master after an NPR; ub_br, ub_bg, ub_intr and ub_vec are the interrupt
//  lines. The cycles are four phase handshakes: MSYN with address, control
//  and data, SSYN (with read data) until MSYN goes away.
//
//  Not modelled: SBI parity and faults (an interlock write masked without
//  the interlock read gets no confirmation instead of the interlock
//  sequence fault; this SBIA sends no interlock functions anyway), the
//  adapter's own power supply (AD PDN, AD PUP never set), Unibus parity
//  (PB) except the data path parity error this adapter makes, read data
//  timeouts and error confirmations from memory (the SBIA never gives
//  them), DMA to SBI I/O space (nothing on this SBI takes it; a buffered
//  data path mapped there works by longwords). The parity defeat bits
//  check the bytes a transfer uses: with DCR<29> a map register byte with
//  an even number of ones fails (the high half at the start of a DMA, the
//  low half when an SBI transfer needs it, never for a prefetch), with
//  DCR<28> a data byte of a buffered data path.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_uba #(
	parameter CLK_HZ = 50000000,
	parameter [3:0] TR  = 4'd3,      // backplane jumpers: TR 3
	parameter [1:0] UBN = 2'd0,      // adapter number: Unibus at 2010 0000
	parameter [1:0] ILV = 2'd0       // its own interrupts: BR4 + ILV
) (
	input             clk,
	input             rst,           // processor initialization

	// SBI: CPU transactions (the SBIA's transmitter)
	input             sbi_cmd,       // held until a confirmation
	input       [3:0] sbi_fn,
	input      [27:0] sbi_adr,
	input       [3:0] sbi_msk,
	input      [31:0] sbi_wdat,
	output reg        nx_ack,        // one clock: done, read data on nx_rdat
	output            nx_busy,       // busy confirmation
	output reg        nx_err,        // one clock: error confirmation
	output reg        nx_rds,        // with nx_ack: read data substitute
	output reg [31:0] nx_rdat,
	input             sbi_unjam,

	// SBI: the adapter as master (DMA through the SBIA)
	output reg        dm_req,
	output reg  [3:0] dm_fn,
	output reg [27:0] dm_adr,
	output reg  [3:0] dm_msk,
	output reg  [3:0] dm_msk2,
	output reg [63:0] dm_wdat,
	output      [4:0] dm_id,
	input             dm_done,
	input             dm_nr,
	input             dm_busy,
	input             dm_rds,
	input      [63:0] dm_rdat,

	output      [3:0] req,           // SBI REQ7-REQ4 (req[0] is REQ4)

	// Unibus, as device registers see it
	output     [17:0] ub_a,
	output      [1:0] ub_c,          // 00 DATI, 01 DATIP, 10 DATO, 11 DATOB
	output     [15:0] ub_d,
	output            ub_msyn,
	input             ub_ssyn,
	input      [15:0] ub_rd,
	// a device as master (DMA)
	input             dv_npr,
	output reg        dv_npg,        // held while the device is master
	input      [17:0] dv_a,
	input       [1:0] dv_c,
	input      [15:0] dv_d,
	input             dv_msyn,
	output            dv_ssyn,
	output     [15:0] dv_rd,
	// interrupts
	input       [3:0] ub_br,         // BR7-BR4 (ub_br[0] is BR4)
	output reg  [3:0] ub_bg,
	input             ub_intr,       // the device that took the grant
	input      [15:0] ub_vec,        // its vector, with ub_intr
	output            ub_init
);

	// times in SBI cycles (200 ns)
	localparam [11:0] T_INIT   = 12'd2500;     // initialization routine, 500 us
	localparam  [8:0] T_UBSTO  = 9'd256;       // Unibus select timeout, 51.2 us
	localparam  [8:0] T_SSYNTO = 9'd64;        // slave sync timeout, 12.8 us
	localparam  [8:0] T_CXTMO  = 9'd500;       // SBI command timeout, 100 us
	localparam  [8:0] T_NOSACK = 9'd64;        // no device takes the grant
	localparam  [9:0] T_RIFF   = 10'd512;      // interlock write not following
	localparam [16:0] T_ACDC   = 17'd25000;    // AC LO to DC LO, 5 ms
	localparam [16:0] T_PUINI  = 17'd50000;    // power up: INIT released, 10 ms
	localparam [16:0] T_PUP    = 17'd100000;   // AC LO released, 20 ms

	assign dm_id = {1'b0, TR};

	/* ------------------------------------------------- SBI cycle clock */
	localparam integer SBIDIV = CLK_HZ / 5000000;
	reg   [7:0] div;
	wire        tick = (div == SBIDIV - 1);
	always @(posedge clk)
		div <= (rst || tick) ? 8'd0 : div + 8'd1;

	/* ----------------------------------------------------------- decode */
	wire        me_r  = sbi_cmd && (sbi_adr[27:15] == 13'h1000) &&
	                    (sbi_adr[14:11] == TR);
	wire        me_u  = sbi_cmd && sbi_adr[27] && sbi_adr[18] &&
	                    (sbi_adr[26:19] == 8'd0) && (sbi_adr[17:16] == UBN);
	wire [10:0] la    = sbi_adr[10:0];
	wire        a_reg = !la[10] && !la[9] && (la[8:5] == 4'd0);
	wire        a_map = !la[10] && la[9] && (la[8:4] != 5'h1F);   // 0-495
	wire        me    = (me_r && (a_reg || a_map)) || me_u;
	wire  [4:0] rn    = la[4:0];
	wire        f_rd  = (sbi_fn == 4'b0001) || (sbi_fn == 4'b0100);
	wire        f_wr  = (sbi_fn == 4'b0010) || (sbi_fn == 4'b0111);
	wire        f_ilk = sbi_fn[2];

	// SBI mask and function to Unibus address and control (TD table 2-7)
	reg         um_ok, um_byte;
	reg   [1:0] um_a;
	always @* begin
		um_ok   = 1'b1;
		um_byte = 1'b0;
		um_a    = 2'b00;
		if (f_rd)
			case (sbi_msk)
			4'b0001, 4'b0011, 4'b0010: um_a = 2'b00;
			4'b0100, 4'b1100, 4'b1000: um_a = 2'b10;
			default: um_ok = 1'b0;
			endcase
		else
			case (sbi_msk)
			4'b0001: begin um_a = 2'b00; um_byte = 1'b1; end
			4'b0010: begin um_a = 2'b01; um_byte = 1'b1; end
			4'b0100: begin um_a = 2'b10; um_byte = 1'b1; end
			4'b1000: begin um_a = 2'b11; um_byte = 1'b1; end
			4'b0011: um_a = 2'b00;
			4'b1100: um_a = 2'b10;
			default: um_ok = 1'b0;
			endcase
	end

	/* -------------------------------------------------------- registers */
	reg         cf_ubinit, cf_ubpdn, cf_ubic;        // CNFGR<18:16>
	localparam  cf_adpdn = 1'b0, cf_adpup = 1'b0;    // no power supply here
	reg   [4:0] cr_mrd;
	reg         cr_ifs, cr_brie, cr_usefie, cr_suefie, cr_cnfie, cr_upf;
	reg  [10:0] sr;                                  // SR<10:0>
	reg         dc_spare, dc_dintr, dc_dmp, dc_ddpp;
	reg   [8:0] fmer;
	reg  [15:0] fubar;
	reg  [15:0] brsvr [0:3];
	reg  [15:1] bne, bte, dpf;                       // DPR 1-15 <31:29>
	reg   [7:0] bst  [1:15];                         // DPR<23:16>
	reg  [15:0] buba [1:15];                         // DPR<15:0>

	localparam [10:0] SR_DMA = 11'h6F8, SR_SUE = 11'h003;
	localparam [10:0] E_RDS  = 11'h200, E_CXTMO = 11'h040, E_DPPE  = 11'h020,
	                  E_IVMR = 11'h010, E_MRPF  = 11'h008, E_LEB   = 11'h004,
	                  E_UBSTO = 11'h002, E_SSYNTO = 11'h001;

	wire  [7:0] code  = {6'b001010, UBN};
	wire [31:0] cnfgr = {8'd0, cf_adpdn, cf_adpup, 3'd0, cf_ubinit, cf_ubpdn,
	                     cf_ubic, 8'd0, code};
	wire [31:0] cr_q  = {1'b0, cr_mrd, 19'd0, cr_ifs, cr_brie, cr_usefie,
	                     cr_suefie, cr_cnfie, cr_upf, 1'b0};
	wire [31:0] sr_q  = {4'd0, 4'd0, 13'd0, sr};     // BRRVR full: never seen

	wire        adp_req = (cr_usefie && |(sr & SR_DMA)) ||
	                      (cr_suefie && |(sr & SR_SUE)) ||
	                      (cr_cnfie && (cf_adpdn | cf_adpup | cf_ubinit |
	                                    cf_ubpdn | cf_ubic));
	wire        ub_pass = cr_ifs && cr_brie && !dc_dintr;
	assign req = (ub_pass ? ub_br : 4'd0) | ({3'd0, adp_req} << ILV);

	// parity defeat: a byte with an even number of ones fails
	function even8(input [7:0] b);
		even8 = ~^b;
	endfunction
	function [7:0] evens(input [63:0] d);
		integer j;
		for (j = 0; j < 8; j = j + 1)
			evens[j] = ~^d[8*j +: 8];
	endfunction

	/* ------------------------------------------------- map register RAM */
	(* ramstyle = "M10K" *) reg [31:0] mapram [0:511];
	reg   [8:0] mr_a;
	reg  [31:0] mr_q;
	reg         mw_en;
	reg   [8:0] mw_a;
	reg  [31:0] mw_d;
	integer k;
	initial
		for (k = 0; k < 512; k = k + 1)
			mapram[k] = 32'd0;
	always @(posedge clk) begin
		if (mw_en)
			mapram[mw_a] <= mw_d;
		mr_q <= mapram[mr_a];
	end

	/* ---------------------------------------- buffered data path RAM */
	// {byte 7 kept for the byte offset mode, the quadword}
	(* ramstyle = "M10K" *) reg [71:0] bdram [0:15];
	reg   [3:0] bd_a;
	reg  [71:0] bd_q;
	reg         bw_en;
	reg   [3:0] bw_a;
	reg  [71:0] bw_d;
	initial
		for (k = 0; k < 16; k = k + 1)
			bdram[k] = 72'd0;
	always @(posedge clk) begin
		if (bw_en)
			bdram[bw_a] <= bw_d;
		bd_q <= bdram[bd_a];
	end

	/* ------------------------------------------ SBI command front end */
	reg         uip, rip, aip, riff;         // TD figure 3-35
	reg         ini;                         // initialization routine runs
	reg         taken, me_d;
	reg         rd_live;                     // the read owed is still wanted
	reg         adi;                         // adapter init written

	wire        c_err = !(f_rd || f_wr) || (me_u && !um_ok) ||
	                    (me_r && a_reg && f_wr &&
	                     (rn[4:2] == 3'b001 || rn[4:2] == 3'b011));
	wire        c_loc = me_r && a_reg && (rn[4:2] == 3'b000);
	wire        c_cw  = c_loc && f_wr;               // CNFGR CR SR DCR write
	wire        c_lr  = c_loc && f_rd && (rn[1:0] == 2'd0 || rn[1:0] == 2'd3);
	wire        c_rr  = me_r && f_rd;
	wire        c_aw  = me_r && f_wr && !c_loc;      // MR BRSVR DPR write
	wire        c_ur  = me_u && f_rd;
	wire        c_uw  = me_u && f_wr;
	wire        c_flt = c_uw && f_ilk && !riff;      // interlock sequence fault
	wire        c_acc = c_cw ? 1'b1 :
	                    c_rr ? (!aip && !rip && (!ini || c_lr)) :
	                    c_aw ? (!aip && !ini) :
	                    c_ur ? (!uip && !riff && !rip && !ini) :
	                    c_uw ? ((f_ilk ? riff : !riff) && !uip && !ini) : 1'b0;

	wire        go_cmd = me && me_d && !taken;
	assign nx_busy = me && !taken && !c_err && !c_flt && !c_acc;

	// work handed on: a register for the microsequencer, a Unibus transfer
	reg         sb_pend, sb_wr;
	reg  [10:0] sb_la;
	reg  [31:0] sb_wd;
	reg         lr_pend;                     // CNFGR or DCR read
	reg   [1:0] lr_t;
	reg         ue_pend;
	reg  [17:0] ue_a;
	reg   [1:0] ue_c;
	reg  [15:0] ue_d;

	/* --------------------------------------- Unibus power fail sequence */
	reg   [1:0] ps;                          // 0 up, 1 AC LO, 2 down, 3 up again
	reg  [16:0] ps_t;
	reg         u_acl, u_dcl, u_ini;
	assign ub_init = u_ini;
	wire        bus_ok = !u_dcl && !u_ini;

	/* ------------------------------------------------- the Unibus itself */
	localparam [1:0] B_FREE = 2'd0, B_UBA = 2'd1, B_DEV = 2'd2, B_INT = 2'd3;
	reg   [1:0] bown;
	reg  [17:0] m_a;
	reg   [1:0] m_c;
	reg  [15:0] m_d;
	reg         m_msyn;
	reg         s_ssyn;                      // the adapter's DMA side answers
	reg  [15:0] s_rd;
	reg         s_pb;                        // ... with a parity error

	wire        b_msyn = (bown == B_UBA) ? m_msyn : (bown == B_DEV) ? dv_msyn : 1'b0;
	wire [17:0] b_a    = (bown == B_DEV) ? dv_a : m_a;
	wire  [1:0] b_c    = (bown == B_DEV) ? dv_c : m_c;
	wire [15:0] b_d    = (bown == B_DEV) ? dv_d : m_d;
	wire        b_ssyn = s_ssyn | ub_ssyn;
	wire [15:0] b_rd   = s_ssyn ? s_rd : ub_rd;

	assign ub_a    = b_a;
	assign ub_c    = b_c;
	assign ub_d    = b_d;
	assign ub_msyn = b_msyn;
	assign dv_ssyn = (bown == B_DEV) && b_ssyn;
	assign dv_rd   = b_rd;

	/* ----------------------------------- the adapter as Unibus master */
	localparam [2:0] M_IDLE = 3'd0, M_ARB = 3'd1, M_DSK = 3'd2, M_WAIT = 3'd3,
	                 M_REL = 3'd4, M_HOLD = 3'd5;
	reg   [2:0] ms;
	reg   [9:0] mt;
	reg         m_rdy;                       // read data (or zeros) for the SBI
	reg  [15:0] m_rdat;
	reg         m_pb;
	reg         m_ok;                        // the cycle got its slave sync

	/* --------------------------------------- the adapter's DMA side */
	// a master's cycle below the I/O page through a map register that is
	// not disabled (TD 3.5.8)
	wire        s_hit = b_msyn && (b_a[17:13] != 5'h1F) &&
	                    (b_a[17:13] >= cr_mrd);
	reg         s_eng;                       // this cycle is being served
	reg         dma_att;
	reg  [17:0] d_ua;
	reg   [1:0] d_c;
	reg  [15:0] d_wd;
	reg         ilk_ff;                      // DATIP done through the DDP

	/* --------------------------------------------- the microsequencer */
	localparam [5:0]
		U_IDLE = 6'd0,  U_INIT = 6'd1,  U_SBR  = 6'd2,  U_MRR  = 6'd3,
		U_AWE  = 6'd4,  U_PRG0 = 6'd5,  U_PRG1 = 6'd6,  U_PRG2 = 6'd7,
		U_BRV0 = 6'd8,  U_BRV1 = 6'd9,  U_BRV2 = 6'd10, U_RDR  = 6'd11,
		U_D1   = 6'd12, U_DDP  = 6'd13, U_B0   = 6'd14, U_BW1  = 6'd15,
		U_BR1  = 6'd16, U_BR3  = 6'd17, U_BR4  = 6'd18, U_BR5  = 6'd19,
		U_LW1  = 6'd20, U_XFER = 6'd21, U_SSYN = 6'd22, U_NOSY = 6'd23,
		U_PF0  = 6'd24, U_PF1  = 6'd25, U_PF2  = 6'd26, U_ANS  = 6'd27;
	reg   [5:0] us, u_ret;
	reg  [11:0] u_t;
	reg   [9:0] walk;                        // initialization: clear the RAMs
	reg  [31:0] u_q;                         // register read data
	reg  [31:0] u_m;                         // the map register in use
	reg   [3:0] u_n;                         // its buffered data path
	reg  [71:0] u_bd;                        // that path's data and state
	reg   [7:0] u_bs;
	reg  [63:0] u_nd;                        // write: the new buffer
	reg         u_sp;                        // ... a byte spills over
	reg   [7:0] u_spd;
	reg         u_pf;                        // prefetch after this cycle
	reg  [15:0] u_pa;                        // prefetch / second read address
	reg   [7:0] u_b7;                        // second read: byte 7 read first

	// the SBI transfer the microsequencer waits for
	localparam [1:0] P_DDP = 2'd0, P_BR = 2'd1, P_BW = 2'd2, P_PF = 2'd3;
	reg   [1:0] x_pol;
	reg   [8:0] x_t;
	reg         x_ok, x_rds, x_tmo, x_abt;
	reg  [63:0] x_rd;

	// start one (dm_fn, dm_adr, the masks and data set up alongside):
	// direct data path (retried while the master waits), buffer read
	// (100 us), buffer write or purge (100 us whatever the master does),
	// prefetch (100 us, nothing recorded)
	task xfer(input [5:0] ret, input [1:0] pol);
		begin
			x_ok   <= 1'b0;
			x_rds  <= 1'b0;
			x_tmo  <= 1'b0;
			x_abt  <= 1'b0;
			x_t    <= 9'd0;
			x_pol  <= pol;
			u_ret  <= ret;
			dm_req <= 1'b1;
			us     <= U_XFER;
		end
	endtask

	wire        u_idle = (us == U_IDLE) && !ini;
	wire        mic_ok = u_idle;

	wire [31:0] dcr_q = {dc_spare, dc_dintr, dc_dmp, dc_ddpp, mic_ok, 3'd0,
	                     cnfgr[23:0]};

	// SR changes from several places in one clock: collected here
	reg  [10:0] sr_set, sr_clr;
	reg         e_dma;                       // a DMA field error this clock
	reg  [10:0] e_bit;

	// a byte of the buffer, and the buffer with a byte replaced
	function [7:0] bsel(input [63:0] d, input [2:0] p);
		bsel = d[8*p +: 8];
	endfunction

	integer i;
	reg   [3:0] e0;                          // write: position of the first byte
	reg   [7:0] wb0, wb1;
	reg  [63:0] nd;
	reg   [7:0] nbs;
	reg         trig, sp;
	reg   [7:0] spd;
	reg  [15:0] dout;

	always @(posedge clk) begin
		nx_ack <= 1'b0;
		nx_err <= 1'b0;
		mw_en  <= 1'b0;
		bw_en  <= 1'b0;
		me_d   <= me && !taken;
		sr_set = 11'd0;
		sr_clr = 11'd0;
		e_dma  = 1'b0;
		e_bit  = 11'd0;

		if (rst) begin
			cf_ubinit <= 1'b0; cf_ubpdn <= 1'b0; cf_ubic <= 1'b1;
			cr_mrd <= 5'd0; cr_ifs <= 1'b0; cr_brie <= 1'b0;
			cr_usefie <= 1'b0; cr_suefie <= 1'b0; cr_cnfie <= 1'b0;
			cr_upf <= 1'b0;
			sr <= 11'd0;
			dc_spare <= 1'b0; dc_dintr <= 1'b0; dc_dmp <= 1'b0; dc_ddpp <= 1'b0;
			fmer <= 9'd0; fubar <= 16'd0;
			brsvr[0] <= 16'd0; brsvr[1] <= 16'd0;
			brsvr[2] <= 16'd0; brsvr[3] <= 16'd0;
			bne <= 15'd0; bte <= 15'd0; dpf <= 15'd0;
			for (i = 1; i < 16; i = i + 1) begin
				bst[i]  <= 8'd0;
				buba[i] <= 16'd0;
			end
			uip <= 1'b0; rip <= 1'b0; aip <= 1'b0; riff <= 1'b0;
			taken <= 1'b0; rd_live <= 1'b0;
			sb_pend <= 1'b0; lr_pend <= 1'b0; ue_pend <= 1'b0;
			ps <= 2'd0; u_acl <= 1'b0; u_dcl <= 1'b0; u_ini <= 1'b0;
			bown <= B_FREE; m_msyn <= 1'b0; ms <= M_IDLE; m_rdy <= 1'b0;
			s_ssyn <= 1'b0; s_pb <= 1'b0; s_eng <= 1'b0; dma_att <= 1'b0;
			ilk_ff <= 1'b0;
			dv_npg <= 1'b0; ub_bg <= 4'd0;
			dm_req <= 1'b0;
			nx_rds <= 1'b0;
			adi    <= 1'b0;
			// clear the map and the buffers, as the initialization
			// routine does (TD 3.3.3)
			ini  <= 1'b1;
			walk <= 10'd0;
			u_t  <= T_INIT;              // the walk only
			us   <= U_INIT;
		end else if (adi) begin
			// adapter init (TD 2.9.2): everything cleared, the
			// initialization routine, a Unibus power fail sequence
			adi <= 1'b0;
			cr_mrd <= 5'd0; cr_ifs <= 1'b0;
			cr_brie <= 1'b0; cr_usefie <= 1'b0;
			cr_suefie <= 1'b0; cr_cnfie <= 1'b0;
			cr_upf <= 1'b0;
			sr <= 11'd0;
			dc_spare <= 1'b0; dc_dintr <= 1'b0;
			dc_dmp <= 1'b0; dc_ddpp <= 1'b0;
			brsvr[0] <= 16'd0; brsvr[1] <= 16'd0;
			brsvr[2] <= 16'd0; brsvr[3] <= 16'd0;
			bne <= 15'd0; bte <= 15'd0; dpf <= 15'd0;
			for (i = 1; i < 16; i = i + 1) begin
				bst[i]  <= 8'd0;
				buba[i] <= 16'd0;
			end
			uip <= 1'b0; rip <= 1'b0; aip <= 1'b0;
			riff <= 1'b0;
			sb_pend <= 1'b0; lr_pend <= 1'b0;
			ue_pend <= 1'b0;
			ms <= M_IDLE; m_msyn <= 1'b0; m_rdy <= 1'b0;
			if (bown != B_DEV) bown <= B_FREE;
			ub_bg <= 4'd0;
			s_ssyn <= 1'b0; s_eng <= 1'b0;
			dma_att <= 1'b0; ilk_ff <= 1'b0;
			dm_req <= 1'b0;
			ini  <= 1'b1;
			walk <= 10'd0;
			u_t  <= 12'd0;
			us   <= U_INIT;
			ps   <= 2'd1;            // AC LO
			ps_t <= 17'd0;
			u_acl <= 1'b1;
			cf_ubpdn <= 1'b1;
			cf_ubic  <= 1'b0;
		end else begin
			if (!me) begin
				// the command has gone (answered, or the SBIA timed
				// out): nobody waits for a read now
				taken <= 1'b0;
				rd_live <= 1'b0;
			end

			/* ----------------------------------------- commands */
			if (go_cmd) begin
				if (c_err) begin
					taken  <= 1'b1;
					nx_err <= 1'b1;
				end else if (c_flt) begin
					taken  <= 1'b1;          // no confirmation
				end else if (c_acc) begin
					taken <= 1'b1;
					if (c_cw) begin
						nx_ack <= 1'b1;
						case (rn[1:0])
						2'd0: begin              // CNFGR: write 1 to clear
							if (sbi_wdat[18]) cf_ubinit <= 1'b0;
							if (sbi_wdat[17]) cf_ubpdn  <= 1'b0;
							if (sbi_wdat[16]) cf_ubic   <= 1'b0;
						end
						2'd1: if (sbi_wdat[0]) begin
							// adapter init: done in the next clock
							adi <= 1'b1;
						end else begin
							cr_mrd    <= sbi_wdat[30:26];
							cr_ifs    <= sbi_wdat[6];
							cr_brie   <= sbi_wdat[5];
							cr_usefie <= sbi_wdat[4];
							cr_suefie <= sbi_wdat[3];
							cr_cnfie  <= sbi_wdat[2];
							cr_upf    <= sbi_wdat[1];
							if (sbi_wdat[1] && !cr_upf && ps == 2'd0) begin
								// Unibus power fail (TD 2.8.5)
								ps <= 2'd1;
								ps_t <= 17'd0;
								u_acl <= 1'b1;
								cf_ubpdn <= 1'b1;
								cf_ubic  <= 1'b0;
							end
						end
						2'd2: sr_clr = sbi_wdat[10:0];
						default: begin           // DCR
							dc_spare <= sbi_wdat[31];
							dc_dintr <= sbi_wdat[30];
							dc_dmp   <= sbi_wdat[29];
							dc_ddpp  <= sbi_wdat[28];
						end
						endcase
					end else if (c_rr) begin
						aip <= 1'b1;
						rip <= 1'b1;
						rd_live <= 1'b1;
						sb_la <= la;
						if (c_lr) begin
							lr_pend <= 1'b1;
							lr_t <= 2'd0;
						end else begin
							sb_pend <= 1'b1;
							sb_wr <= 1'b0;
						end
					end else if (c_aw) begin
						nx_ack <= 1'b1;
						aip <= 1'b1;
						sb_pend <= 1'b1;
						sb_wr <= 1'b1;
						sb_la <= la;
						sb_wd <= sbi_wdat;
					end else begin
						// a Unibus transfer: UA<17:2> from the SBI
						// address, UA<1:0> and the function from the
						// mask (TD 2.5.2.1)
						uip <= 1'b1;
						ue_pend <= 1'b1;
						ue_a <= {sbi_adr[15:0], um_a};
						ue_d <= um_a[1] ? sbi_wdat[31:16] : sbi_wdat[15:0];
						if (c_ur) begin
							rip <= 1'b1;
							rd_live <= 1'b1;
							riff <= f_ilk;
							ue_c <= f_ilk ? 2'b01 : 2'b00;
						end else begin
							nx_ack <= 1'b1;
							if (f_ilk)
								riff <= 1'b0;
							ue_c <= um_byte ? 2'b11 : 2'b10;
						end
					end
				end
			end

			// CNFGR and DCR reads: three SBI cycles, no microsequencer
			if (lr_pend && tick) begin
				if (lr_t == 2'd2) begin
					lr_pend <= 1'b0;
					aip <= 1'b0;
					rip <= 1'b0;
					if (rd_live) begin
						nx_ack  <= 1'b1;
						nx_rds  <= 1'b0;
						nx_rdat <= (sb_la[1:0] == 2'd0) ? cnfgr : dcr_q;
					end
				end else
					lr_t <= lr_t + 2'd1;
			end

			/* ------------------------------------- SBI UNJAM */
			if (sbi_unjam) begin
				cr_brie <= 1'b0; cr_usefie <= 1'b0;
				cr_suefie <= 1'b0; cr_cnfie <= 1'b0;
				ps <= 2'd1;
				ps_t <= 17'd0;
				u_acl <= 1'b1;
				cf_ubpdn <= 1'b1;
				cf_ubic  <= 1'b0;
			end

			/* ------------------------- Unibus power fail sequence */
			if (tick && ps != 2'd0 && !sbi_unjam) begin
				case (ps)
				2'd1: if (ps_t == T_ACDC) begin
					// DC LO and INIT
					ps    <= 2'd2;
					u_dcl <= 1'b1;
					u_ini <= 1'b1;
					cf_ubinit <= 1'b1;
					cf_ubic   <= 1'b0;
				end else
					ps_t <= ps_t + 17'd1;
				2'd2: if (!cr_upf) begin
					ps   <= 2'd3;
					ps_t <= 17'd0;
				end
				default: begin
					ps_t <= ps_t + 17'd1;
					if (ps_t == T_PUINI) begin
						u_dcl <= 1'b0;
						u_ini <= 1'b0;
					end
					if (ps_t == T_PUP) begin
						// power up complete (TD 2.9.1)
						ps    <= 2'd0;
						u_acl <= 1'b0;
						cf_ubic   <= 1'b1;
						cf_ubpdn  <= 1'b0;
						cf_ubinit <= 1'b0;
					end
				end
				endcase
			end

			/* ---------------------- devices that want the bus (NPR) */
			if (bown == B_FREE && dv_npr && bus_ok && ms != M_ARB &&
			    us != U_BRV1) begin
				bown   <= B_DEV;
				dv_npg <= 1'b1;
			end else if (bown == B_DEV && !dv_npr && !dv_msyn) begin
				bown   <= B_FREE;
				dv_npg <= 1'b0;
			end

			/* ---------------------------- the adapter as master */
			case (ms)
			M_IDLE: if (ue_pend) begin
				ue_pend <= 1'b0;
				m_a  <= ue_a;
				m_c  <= ue_c;
				m_d  <= ue_d;
				mt   <= 10'd0;
				m_ok <= 1'b0;
				if (!(sr & SR_SUE))
					fubar <= ue_a[17:2];     // FUBAR follows UA<17:2>
				ms <= M_ARB;
			end
			M_ARB: if (tick) begin
				if (bown == B_FREE && bus_ok) begin
					bown <= B_UBA;
					mt   <= 10'd0;
					ms   <= M_DSK;
				end else if (mt == {1'b0, T_UBSTO}) begin
					// Unibus select timeout (TD 2.9.3)
					if (!(sr & SR_SUE))
						sr_set = sr_set | E_UBSTO;
					m_rdat <= 16'd0;
					m_pb   <= 1'b0;
					m_rdy  <= !m_c[1];
					uip    <= 1'b0;
					if (m_c == 2'b01) riff <= 1'b0;
					ms <= M_IDLE;
				end else
					mt <= mt + 10'd1;
			end
			M_DSK: if (tick) begin
				// address deskew, then MSYN
				if (mt == 10'd1) begin
					m_msyn <= 1'b1;
					mt <= 10'd0;
					ms <= M_WAIT;
				end else
					mt <= mt + 10'd1;
			end
			M_WAIT: if (b_ssyn) begin
				m_rdat <= b_rd;
				m_pb   <= s_ssyn && s_pb;
				m_ok   <= 1'b1;
				m_msyn <= 1'b0;
				ms     <= M_REL;
			end else if (tick) begin
				if (mt == {1'b0, T_SSYNTO}) begin
					// Unibus slave sync timeout
					if (!(sr & SR_SUE))
						sr_set = sr_set | E_SSYNTO;
					m_rdat <= 16'd0;
					m_pb   <= 1'b0;
					m_msyn <= 1'b0;
					ms     <= M_REL;
				end else
					mt <= mt + 10'd1;
			end
			M_REL: if (!b_ssyn && tick) begin
				if (!m_c[1])
					m_rdy <= 1'b1;           // read data to the SBI
				if (m_c == 2'b01 && m_ok) begin
					// DATIP: the bus stays ours for the DATO
					uip <= 1'b0;
					mt  <= 10'd0;
					ms  <= M_HOLD;
				end else begin
					if (m_c == 2'b01) riff <= 1'b0;
					bown <= B_FREE;
					uip  <= 1'b0;
					ms   <= M_IDLE;
				end
			end
			default: begin               // M_HOLD: until the interlock write
				if (ue_pend) begin
					ue_pend <= 1'b0;
					m_a  <= ue_a;
					m_c  <= ue_c;
					m_d  <= ue_d;
					mt   <= 10'd0;
					m_ok <= 1'b0;
					if (!(sr & SR_SUE))
						fubar <= ue_a[17:2];
					ms <= M_DSK;
				end else if (tick) begin
					if (mt == T_RIFF) begin
						riff <= 1'b0;
						bown <= B_FREE;
						ms   <= M_IDLE;
					end else
						mt <= mt + 10'd1;
				end
			end
			endcase

			/* ------------------------- DMA attention (TD 3.3.1) */
			if (!s_eng && !dma_att && s_hit) begin
				s_eng   <= 1'b1;
				dma_att <= 1'b1;
				d_ua    <= b_a;
				d_c     <= b_c;
				d_wd    <= b_d;
			end else if (dma_att && !b_msyn) begin
				// the master gave up before it was served
				dma_att <= 1'b0;
				s_eng   <= 1'b0;
			end

			/* ------------------------------- the microsequencer */
			case (us)
			U_INIT: begin
				// clear the map registers and the buffered data
				// paths (TD 3.3.3), then the rest of 500 us
				if (!walk[9]) begin
					mw_en <= 1'b1;
					mw_a  <= walk[8:0];
					mw_d  <= 32'd0;
					if (walk[8:4] == 5'd0) begin
						bw_en <= 1'b1;
						bw_a  <= walk[3:0];
						bw_d  <= 72'd0;
					end
					walk <= walk + 10'd1;
				end else if (u_t >= T_INIT) begin
					ini <= 1'b0;
					us  <= U_IDLE;
				end else if (tick)
					u_t <= u_t + 12'd1;
			end

			U_IDLE: if (tick) begin
				if (dma_att) begin
					// DMA: the map register first
					dma_att <= 1'b0;
					mr_a    <= d_ua[17:9];
					us      <= U_D1;
				end else if (m_rdy) begin
					us <= U_RDR;
				end else if (sb_pend) begin
					sb_pend <= 1'b0;
					u_t <= 12'd0;
					if (sb_la[9]) begin
						mr_a <= sb_la[8:0];
						if (sb_wr) begin
							mw_en <= 1'b1;
							mw_a  <= sb_la[8:0];
							mw_d  <= sb_wd;
							us    <= U_AWE;
						end else
							us <= U_MRR;
					end else if (sb_wr) begin
						if (sb_la[4]) begin
							// DPR: <30> clears BTE, <31> purges
							if (sb_la[3:0] != 4'd0 && sb_wd[30])
								bte[sb_la[3:0]] <= 1'b0;
							if (sb_la[3:0] != 4'd0 && sb_wd[31]) begin
								u_n  <= sb_la[3:0];
								bd_a <= sb_la[3:0];
								us   <= U_PRG0;
							end else
								us <= U_AWE;
						end else begin
							brsvr[sb_la[1:0]] <= sb_wd[15:0];
							us <= U_AWE;
						end
					end else begin
						case (sb_la[4:2])
						3'b000: u_q <= sb_la[1] ? sr_q : cr_q;
						3'b001: u_q <= sb_la[0] ? {16'd0, fubar} : {23'd0, fmer};
						3'b010: u_q <= {16'd0, brsvr[sb_la[1:0]]};
						3'b011: u_q <= 32'd0;           // BRRVR, below
						default: u_q <= (sb_la[3:0] == 4'd0) ? 32'd0 :
						         {bne[sb_la[3:0]], bte[sb_la[3:0]],
						          dpf[sb_la[3:0]], 5'd0, bst[sb_la[3:0]],
						          buba[sb_la[3:0]]};
						endcase
						us <= (sb_la[4:2] == 3'b011) ? U_BRV0 : U_SBR;
					end
				end
			end

			U_SBR: if (tick) begin
				if (u_t == 12'd2)
					us <= U_ANS;
				else
					u_t <= u_t + 12'd1;
			end

			U_MRR: if (tick) begin
				u_q <= mr_q;
				us  <= U_ANS;
			end

			U_ANS: begin                 // read data to the SBI
				aip <= 1'b0;
				rip <= 1'b0;
				if (rd_live) begin
					nx_ack  <= 1'b1;
					nx_rds  <= 1'b0;
					nx_rdat <= u_q;
				end
				us <= U_IDLE;
			end

			U_AWE: if (tick) begin       // a register written
				aip <= 1'b0;
				us  <= U_IDLE;
			end

			/* ------------------ BRRVR: the Unibus interrupt (TD 3.5.5) */
			U_BRV0: if (tick) begin
				u_q <= {(adp_req && sb_la[1:0] == ILV), 31'd0};
				if (cr_ifs && !dc_dintr && ub_br[sb_la[1:0]] && !u_acl &&
				    bus_ok)
					us <= U_BRV1;
				else
					us <= U_ANS;
			end
			U_BRV1: if (tick) begin
				if (!ub_br[sb_la[1:0]] || !bus_ok) begin
					us <= U_ANS;             // passive release: 0
				end else if (bown == B_FREE && ms != M_ARB) begin
					bown <= B_INT;
					ub_bg[sb_la[1:0]] <= 1'b1;
					u_t <= 12'd0;
					us  <= U_BRV2;
				end
			end
			U_BRV2: begin
				if (ub_intr) begin
					u_q[15:0] <= ub_vec;
					ub_bg <= 4'd0;
					bown  <= B_FREE;
					us    <= U_ANS;
				end else if (tick) begin
					if (!ub_br[sb_la[1:0]] || u_t == {3'd0, T_NOSACK}) begin
						ub_bg <= 4'd0;
						bown  <= B_FREE;
						us    <= U_ANS;
					end else
						u_t <= u_t + 12'd1;
				end
			end

			/* -------------------------- Unibus read data to the SBI */
			U_RDR: if (tick) begin
				m_rdy <= 1'b0;
				rip   <= 1'b0;
				if (rd_live) begin
					nx_ack  <= 1'b1;
					nx_rds  <= m_pb;     // Unibus parity: read data substitute
					nx_rdat <= m_a[1] ? {m_rdat, 16'd0} : {16'd0, m_rdat};
				end
				us <= U_IDLE;
			end

			/* --------------------------------- purge (TD 3.3.2) */
			U_PRG0: if (tick) begin
				u_bd <= bd_q;
				u_bs <= bst[u_n];
				if (dpf[u_n] && bst[u_n] != 8'd0) begin
					// write data left: to memory, through the map
					// register of the address in the DPR
					mr_a <= buba[u_n][15:7];
					us   <= U_PRG1;
				end else begin
					bne[u_n] <= 1'b0;
					dpf[u_n] <= 1'b0;
					bst[u_n] <= 8'd0;
					us <= U_AWE;
				end
			end
			U_PRG1: if (tick) begin
				u_m <= mr_q;
				if (!(sr & SR_DMA))
					fmer <= buba[u_n][15:7];
				if (buba[u_n][15:11] == 5'h1F || !mr_q[31]) begin
					e_dma = 1'b1; e_bit = E_IVMR;
					bte[u_n] <= 1'b1;
					us <= U_AWE;
				end else if (dc_dmp && (even8(mr_q[31:24]) || even8(mr_q[23:16]) ||
				                        even8(mr_q[15:8]) || even8(mr_q[7:0]))) begin
					e_dma = 1'b1; e_bit = E_MRPF;
					bte[u_n] <= 1'b1;
					us <= U_AWE;
				end else if (dc_ddpp && |(u_bs & evens(bd_q[63:0]))) begin
					e_dma = 1'b1; e_bit = E_DPPE;
					bte[u_n] <= 1'b1;
					us <= U_AWE;
				end else begin
					dm_fn   <= |u_bs[7:4] ? 4'b1011 : 4'b0010;
					dm_adr  <= {mr_q[20:0], buba[u_n][6:1], 1'b0};
					dm_msk  <= u_bs[3:0];
					dm_msk2 <= u_bs[7:4];
					dm_wdat <= bd_q[63:0];
					xfer(U_PRG2, P_BW);
				end
			end
			U_PRG2: if (tick) begin
				if (x_ok) begin
					bne[u_n] <= 1'b0;
					dpf[u_n] <= 1'b0;
					bst[u_n] <= 8'd0;
				end else begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					bte[u_n] <= 1'b1;
				end
				us <= U_AWE;
			end

			/* ----------------------------------- DMA (TD 3.3.1) */
			U_D1: if (tick) begin
				u_m <= mr_q;
				u_n <= mr_q[24:21];
				u_pf <= 1'b0;
				s_pb <= 1'b0;
				if (!(sr & SR_DMA))
					fmer <= d_ua[17:9];
				if (dc_dmp && (even8(mr_q[31:24]) || even8(mr_q[23:16]))) begin
					e_dma = 1'b1; e_bit = E_MRPF;
					us <= U_NOSY;
				end else if (!mr_q[31]) begin
					e_dma = 1'b1; e_bit = E_IVMR;
					us <= U_NOSY;
				end else if (mr_q[24:21] == 4'd0) begin
					// the direct data path (TD table 2-9)
					if (dc_dmp && (even8(mr_q[15:8]) || even8(mr_q[7:0]))) begin
						e_dma = 1'b1; e_bit = E_MRPF;
						us <= U_NOSY;
					end else begin
						dm_adr <= {mr_q[20:0], d_ua[8:2]};
						if (!d_c[1]) begin
							dm_fn  <= d_c[0] ? 4'b0100 : 4'b0001;
							dm_msk <= d_ua[1] ? 4'b1100 : 4'b0011;
							if (!d_c[0]) ilk_ff <= 1'b0;
						end else begin
							dm_fn  <= ilk_ff ? 4'b0111 : 4'b0010;
							dm_msk <= d_c[0] ? (4'b0001 << d_ua[1:0]) :
							          (d_ua[1] ? 4'b1100 : 4'b0011);
						end
						dm_msk2 <= 4'b0000;
						dm_wdat <= {32'd0, d_ua[1] ? {d_wd, 16'd0} : {16'd0, d_wd}};
						xfer(U_DDP, P_DDP);
					end
				end else if (d_c == 2'b01 || bte[mr_q[24:21]]) begin
					// no DATIP through a buffer; a buffer with a
					// transfer error takes nothing until cleared
					us <= U_NOSY;
				end else begin
					bd_a <= mr_q[24:21];
					us   <= U_B0;
				end
			end

			U_DDP: if (tick) begin
				if (x_abt) begin
					us <= U_NOSY;            // the master gave up
				end else if (x_rds && !d_c[1]) begin
					e_dma = 1'b1; e_bit = E_RDS;
					us <= U_NOSY;
				end else begin
					if (!d_c[1]) begin
						s_rd   <= d_ua[1] ? x_rd[31:16] : x_rd[15:0];
						ilk_ff <= d_c[0];
					end else if (ilk_ff)
						ilk_ff <= 1'b0;
					us <= U_SSYN;
				end
			end

			U_B0: if (tick) begin
				// a buffered data path: its buffer is in bd_q
				u_bd <= bd_q;
				u_bs <= bst[u_n];
				if (u_m[26] || u_m[20]) begin
					/* ------ longword access mode (TD appendix A), or SBI
					   I/O space, which a buffer reaches by longwords */
					if (!d_c[1]) begin
						if (bne[u_n]) begin
							dout = {bsel(bd_q[63:0], {d_ua[2:1], 1'b1}),
							        bsel(bd_q[63:0], {d_ua[2:1], 1'b0})};
							if (dc_ddpp && (even8(dout[15:8]) || even8(dout[7:0]))) begin
								e_dma = 1'b1; e_bit = E_DPPE;
								bte[u_n] <= 1'b1;
								s_pb <= 1'b1;
							end
							s_rd <= dout;
							bne[u_n] <= !d_ua[1];
							dpf[u_n] <= 1'b0;
							us <= U_SSYN;
						end else if (dc_dmp && (even8(u_m[15:8]) || even8(u_m[7:0]))) begin
							e_dma = 1'b1; e_bit = E_MRPF;
							us <= U_NOSY;
						end else begin
							dm_fn   <= 4'b0001;
							dm_adr  <= {u_m[20:0], d_ua[8:2]};
							dm_msk  <= 4'b1111;
							dm_msk2 <= 4'b0000;
							xfer(U_LW1, P_BR);
						end
					end else begin
						// store the word or byte; the high word or
						// byte 3 sends the longword
						nd  = bd_q[63:0];
						nbs = bst[u_n];
						if (d_c[0]) begin
							nd[8*d_ua[2:0] +: 8] = d_ua[0] ? d_wd[15:8] : d_wd[7:0];
							nbs[d_ua[2:0]] = 1'b1;
						end else begin
							nd[8*{d_ua[2:1], 1'b0} +: 16] = d_wd;
							nbs[{d_ua[2:1], 1'b0}] = 1'b1;
							nbs[{d_ua[2:1], 1'b1}] = 1'b1;
						end
						u_nd <= nd;
						buba[u_n] <= d_ua[17:2];
						dpf[u_n]  <= 1'b1;
						if (d_ua[1] && (!d_c[0] || d_ua[0])) begin
							if (dc_dmp && (even8(u_m[15:8]) || even8(u_m[7:0]))) begin
								e_dma = 1'b1; e_bit = E_MRPF;
								bte[u_n] <= 1'b1;
								us <= U_NOSY;
							end else if (dc_ddpp && |(nbs & evens(nd) &
							            (d_ua[2] ? 8'hF0 : 8'h0F))) begin
								e_dma = 1'b1; e_bit = E_DPPE;
								bte[u_n] <= 1'b1;
								us <= U_NOSY;
							end else begin
								dm_fn   <= 4'b0010;
								dm_adr  <= {u_m[20:0], d_ua[8:2]};
								dm_msk  <= d_ua[2] ? nbs[7:4] : nbs[3:0];
								dm_msk2 <= 4'b0000;
								dm_wdat <= {32'd0, d_ua[2] ? nd[63:32] : nd[31:0]};
								u_bs    <= nbs;
								xfer(U_LW1, P_BW);
							end
						end else begin
							bw_en <= 1'b1;
							bw_a  <= u_n;
							bw_d  <= {bd_q[71:64], nd};
							bst[u_n] <= nbs;
							bne[u_n] <= 1'b1;
							us <= U_SSYN;
						end
					end
				end else if (d_c[1]) begin
					/* ------------------------ buffer write (TD 3.3.1.4) */
					// the bytes at UA (+1 with byte offset)
					e0  = {1'b0, d_ua[2:1], d_c[0] & d_ua[0]} + {3'd0, u_m[25]};
					wb0 = (d_c[0] && d_ua[0]) ? d_wd[15:8] : d_wd[7:0];
					wb1 = d_wd[15:8];
					nd  = bd_q[63:0];
					nbs = bst[u_n];
					trig = 1'b0;
					sp   = 1'b0;
					spd  = 8'd0;
					if (e0[3]) begin
						sp  = 1'b1;
						spd = wb0;
					end else begin
						nd[8*e0[2:0] +: 8] = wb0;
						nbs[e0[2:0]] = 1'b1;
						if (e0[2:0] == 3'd7) trig = 1'b1;
					end
					if (!d_c[0]) begin
						if (e0[2:0] == 3'd7) begin
							sp  = 1'b1;          // the high byte spills
							spd = wb1;
						end else begin
							nd[8*(e0[2:0] + 3'd1) +: 8] = wb1;
							nbs[e0[2:0] + 3'd1] = 1'b1;
							if (e0[2:0] == 3'd6) trig = 1'b1;
						end
					end
					u_nd  <= nd;
					u_bs  <= nbs;
					u_sp  <= sp;
					u_spd <= spd;
					dpf[u_n] <= 1'b1;
					if (trig) begin
						// the quadword's last byte: to memory
						if (dc_dmp && (even8(u_m[15:8]) || even8(u_m[7:0]))) begin
							e_dma = 1'b1; e_bit = E_MRPF;
							bte[u_n] <= 1'b1;
							bw_en <= 1'b1; bw_a <= u_n; bw_d <= {bd_q[71:64], nd};
							bst[u_n] <= nbs;
							bne[u_n] <= 1'b1;
							buba[u_n] <= d_ua[17:2];
							us <= U_NOSY;
						end else if (dc_ddpp && |(nbs & evens(nd))) begin
							e_dma = 1'b1; e_bit = E_DPPE;
							bte[u_n] <= 1'b1;
							bw_en <= 1'b1; bw_a <= u_n; bw_d <= {bd_q[71:64], nd};
							bst[u_n] <= nbs;
							bne[u_n] <= 1'b1;
							buba[u_n] <= d_ua[17:2];
							us <= U_NOSY;
						end else begin
							dm_fn   <= |nbs[7:4] ? 4'b1011 : 4'b0010;
							dm_adr  <= {u_m[20:0], d_ua[8:3], 1'b0};
							dm_msk  <= nbs[3:0];
							dm_msk2 <= nbs[7:4];
							dm_wdat <= nd;
							xfer(U_BW1, P_BW);
						end
					end else begin
						if (sp) begin
							nd[7:0] = spd;
							nbs[0]  = 1'b1;
						end
						bw_en <= 1'b1;
						bw_a  <= u_n;
						bw_d  <= {bd_q[71:64], nd};
						bst[u_n]  <= nbs;
						bne[u_n]  <= 1'b1;
						buba[u_n] <= d_ua[17:2] + {15'd0, sp};
						us <= U_SSYN;
					end
				end else if (bne[u_n]) begin
					/* ------------ buffer read, data there (TD 3.3.1.3.2) */
					if (!u_m[25])
						dout = {bsel(bd_q[63:0], {d_ua[2:1], 1'b1}),
						        bsel(bd_q[63:0], {d_ua[2:1], 1'b0})};
					else
						case (d_ua[2:1])
						2'd0: dout = {bd_q[23:16], bd_q[15:8]};
						2'd1: dout = {bd_q[39:32], bd_q[31:24]};
						2'd2: dout = {bd_q[55:48], bd_q[47:40]};
						default: dout = {bd_q[7:0], bd_q[71:64]};
						endcase
					s_rd <= dout;
					dpf[u_n] <= 1'b0;
					if (dc_ddpp && (even8(dout[15:8]) || even8(dout[7:0]))) begin
						// returned with PB; the buffer stops
						e_dma = 1'b1; e_bit = E_DPPE;
						bte[u_n] <= 1'b1;
						s_pb <= 1'b1;
					end else
						u_pf <= u_m[25] ? (d_ua[2:1] == 2'd2) : (d_ua[2:1] == 2'd3);
					us <= U_SSYN;
				end else begin
					/* ------------------- buffer read, empty (TD 3.3.1.3.1) */
					dpf[u_n] <= 1'b0;
					if (dc_dmp && (even8(u_m[15:8]) || even8(u_m[7:0]))) begin
						e_dma = 1'b1; e_bit = E_MRPF;
						us <= U_NOSY;
					end else begin
						dm_msk2 <= 4'b0000;
						if (!d_ua[2]) begin
							// bytes 0-3 first: the quadword
							dm_fn  <= 4'b1000;
							dm_adr <= {u_m[20:0], d_ua[8:3], 1'b0};
							dm_msk <= 4'b0000;
							xfer(U_BR1, P_BR);
						end else begin
							// from byte 4 on: the longword
							dm_fn  <= 4'b0001;
							dm_adr <= {u_m[20:0], d_ua[8:2]};
							dm_msk <= 4'b1111;
							xfer((u_m[25] && d_ua[1]) ? U_BR3 : U_BR1, P_BR);
						end
					end
				end
			end

			U_BW1: if (tick) begin
				// the quadword written (or not)
				bw_en <= 1'b1;
				bw_a  <= u_n;
				if (x_ok) begin
					nd  = u_nd;
					nbs = 8'd0;
					if (u_sp) begin
						nd[7:0] = u_spd;
						nbs[0]  = 1'b1;
					end
					bw_d <= {u_bd[71:64], nd};
					bst[u_n]  <= nbs;
					bne[u_n]  <= u_sp;
					buba[u_n] <= d_ua[17:2] + {15'd0, u_sp};
					us <= U_SSYN;
				end else begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					bte[u_n] <= 1'b1;
					bw_d <= {u_bd[71:64], u_nd};
					bst[u_n]  <= u_bs;
					bne[u_n]  <= 1'b1;
					buba[u_n] <= d_ua[17:2];
					us <= U_NOSY;
				end
			end

			U_LW1: if (tick) begin
				// longword access mode: the SBI read or write done
				if (x_abt) begin
					us <= U_NOSY;
				end else if (!x_ok) begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					if (d_c[1]) bte[u_n] <= 1'b1;
					us <= U_NOSY;
				end else if (x_rds && !d_c[1]) begin
					e_dma = 1'b1; e_bit = E_RDS;
					us <= U_NOSY;
				end else if (!d_c[1]) begin
					nd = u_bd[63:0];
					if (d_ua[2]) nd[63:32] = x_rd[31:0];
					else         nd[31:0]  = x_rd[31:0];
					bw_en <= 1'b1;
					bw_a  <= u_n;
					bw_d  <= {u_bd[71:64], nd};
					s_rd <= d_ua[1] ? x_rd[31:16] : x_rd[15:0];
					bne[u_n] <= !d_ua[1];
					us <= U_SSYN;
				end else begin
					bw_en <= 1'b1;
					bw_a  <= u_n;
					bw_d  <= {u_bd[71:64], u_nd};
					bst[u_n] <= d_ua[2] ? {4'd0, u_bs[3:0]} : {u_bs[7:4], 4'd0};
					bne[u_n] <= 1'b0;
					us <= U_SSYN;
				end
			end

			U_BR1: if (tick) begin
				// an empty buffer's SBI read returned
				if (x_abt) begin
					us <= U_NOSY;
				end else if (!x_ok) begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					us <= U_NOSY;
				end else if (x_rds) begin
					e_dma = 1'b1; e_bit = E_RDS;
					us <= U_NOSY;
				end else begin
					nd = u_bd[63:0];
					if (!d_ua[2]) nd = x_rd;            // the quadword
					else nd[63:32] = x_rd[31:0];        // bytes 4-7
					bw_en <= 1'b1;
					bw_a  <= u_n;
					bw_d  <= {u_bd[71:64], nd};
					u_bd  <= {u_bd[71:64], nd};
					if (!u_m[25])
						dout = {bsel(nd, {d_ua[2:1], 1'b1}), bsel(nd, {d_ua[2:1], 1'b0})};
					else
						case (d_ua[2:1])
						2'd0: dout = {nd[23:16], nd[15:8]};
						2'd1: dout = {nd[39:32], nd[31:24]};
						default: dout = {nd[55:48], nd[47:40]};
						endcase
					s_rd <= dout;
					bne[u_n] <= 1'b1;
					u_pf <= u_m[25] ? (d_ua[2:1] == 2'd2) : (d_ua[2:1] == 2'd3);
					if (u_m[25] ? (d_ua[2:1] == 2'd2) : (d_ua[2:1] == 2'd3))
						bne[u_n] <= 1'b0;       // the prefetch decides
					us <= U_SSYN;
				end
			end

			U_BR3: if (tick) begin
				// byte offset, word 3, empty: byte 7 here, the rest
				// from the next quadword (the second read, TD 3.3.1.3.1)
				if (x_abt) begin
					us <= U_NOSY;
				end else if (!x_ok) begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					us <= U_NOSY;
				end else if (x_rds) begin
					e_dma = 1'b1; e_bit = E_RDS;
					us <= U_NOSY;
				end else begin
					u_b7 <= x_rd[31:24];
					u_pa <= d_ua[17:2] + 16'd1;
					mr_a <= u_pa_n(d_ua[17:2]);
					us   <= U_BR4;
				end
			end
			U_BR4: if (tick) begin
				if (!(sr & SR_DMA))
					fmer <= u_pa[15:7];
				if (u_pa[15:11] == 5'h1F || !mr_q[31]) begin
					e_dma = 1'b1; e_bit = E_IVMR;
					us <= U_NOSY;
				end else if (dc_dmp && (even8(mr_q[31:24]) || even8(mr_q[23:16]) ||
				                        even8(mr_q[15:8]) || even8(mr_q[7:0]))) begin
					e_dma = 1'b1; e_bit = E_MRPF;
					us <= U_NOSY;
				end else begin
					dm_fn   <= 4'b1000;
					dm_adr  <= {mr_q[20:0], u_pa[6:1], 1'b0};
					dm_msk  <= 4'b0000;
					dm_msk2 <= 4'b0000;
					xfer(U_BR5, P_BR);
				end
			end
			U_BR5: if (tick) begin
				if (x_abt) begin
					us <= U_NOSY;
				end else if (!x_ok) begin
					e_dma = 1'b1; e_bit = E_CXTMO;
					us <= U_NOSY;
				end else if (x_rds) begin
					e_dma = 1'b1; e_bit = E_RDS;
					us <= U_NOSY;
				end else begin
					bw_en <= 1'b1;
					bw_a  <= u_n;
					bw_d  <= {u_b7, x_rd};
					s_rd  <= {x_rd[7:0], u_b7};
					bne[u_n] <= 1'b1;
					us <= U_SSYN;
				end
			end

			/* --------------------------------- prefetch (TD 3.3.1.3.3) */
			U_PF0: if (tick) begin
				u_pa <= d_ua[17:2] + 16'd1;
				mr_a <= u_pa_n(d_ua[17:2]);
				us   <= U_PF1;
			end
			U_PF1: if (tick) begin
				// nothing is recorded: an invalid map register, or
				// the I/O page, just ends it
				if (u_pa[15:11] == 5'h1F || !mr_q[31] || mr_q[20]) begin
					us <= U_IDLE;
				end else begin
					dm_fn   <= 4'b1000;
					dm_adr  <= {mr_q[20:0], u_pa[6:1], 1'b0};
					dm_msk  <= 4'b0000;
					dm_msk2 <= 4'b0000;
					xfer(U_PF2, P_PF);
				end
			end
			U_PF2: if (tick) begin
				if (x_ok && !x_rds) begin
					// with byte offset byte 7 stays for the next word
					bw_en <= 1'b1;
					bw_a  <= u_n;
					bw_d  <= {u_m[25] ? u_bd[63:56] : u_bd[71:64], x_rd};
					bne[u_n] <= 1'b1;
				end
				us <= U_IDLE;
			end

			/* ---------------------------------- the SBI transfer */
			U_XFER: begin
				// dm_req is held through no response and busy
				if (dm_done) begin
					dm_req <= 1'b0;
					x_ok   <= 1'b1;
					x_rds  <= dm_rds && !dm_fn[1];
					x_rd   <= dm_rdat;
					us     <= u_ret;
				end else if (dm_nr || dm_busy) begin
					// no response or busy: again, unless the master
					// is gone or it has taken 100 us
					if (((x_pol == P_DDP || x_pol == P_BR) && !b_msyn) ||
					    (x_pol != P_DDP && x_t >= T_CXTMO)) begin
						dm_req <= 1'b0;
						x_abt  <= (x_pol == P_DDP || x_pol == P_BR) && !b_msyn;
						x_tmo  <= 1'b1;
						us     <= u_ret;
					end
				end
				if (tick)
					x_t <= x_t + 9'd1;
			end

			U_SSYN: begin
				// slave sync until the master lets MSYN go
				s_ssyn <= 1'b1;
				if (!b_msyn && s_ssyn) begin
					s_ssyn <= 1'b0;
					s_eng  <= 1'b0;
					s_pb   <= 1'b0;
					us     <= u_pf ? U_PF0 : U_IDLE;
					u_pf   <= 1'b0;
				end
			end

			U_NOSY: if (!b_msyn) begin
				// no slave sync: the master times out
				s_eng <= 1'b0;
				us    <= U_IDLE;
			end

			default: us <= U_IDLE;
			endcase

			/* ------------------------------ SR, with the locks */
			if (e_dma) begin
				if (|(sr & SR_DMA))
					sr_set = sr_set | E_LEB;
				else
					sr_set = sr_set | e_bit;
			end
			sr <= (sr & ~sr_clr) | sr_set;
		end
	end

	// the map register of the longword after UA<17:2>
	function [8:0] u_pa_n(input [15:0] a);
		reg [15:0] n;
		begin
			n = a + 16'd1;
			u_pa_n = n[15:7];
		end
	endfunction

endmodule

`default_nettype wire

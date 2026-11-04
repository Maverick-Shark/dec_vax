//============================================================================
//  vax_mba.v - the RH780 Massbus adapter (MBA): a nexus on the SBI that
//  connects up to eight Massbus drives (here RP07 disks, vax_rp07.v).
//
//  Sources: RH780 Technical Description (EK-RH780-TD-001), chapters 2 to 4;
//  VAX-11/780 Maintenance Handbook (EK-VAXV2-HB-002), MBA registers and the
//  backpanel jumpers (TR 8 and BR5 for the first RH780).
//
//  Address space (TR 8: 2001 0000, SBI longword address 800 4000): the SBI
//  longword address <14:11> is the TR, <10> must be 0, and <9:8> selects
//
//    00  internal registers, <7:3> zero, <2:0> the register (byte 00-1C)
//    01  drive registers, <7:5> the drive, <4:0> the register (400-7FC)
//    10  map registers, <7:0> the map register (800-BFC)
//    11  nothing: no response
//
//  (TD 4.2.6). The adapter only takes longword references (mask 1111) and
//  the read masked and write masked functions, interlocked or not; anything
//  else gets an error confirmation (TD 4.2.7), which the 8600's SBIA turns
//  into a machine check. While a drive register access is under way on the
//  Massbus (MBA BUSY) every command gets a busy confirmation (TD 4.2.8).
//
//  Registers (TD 3.6):
//
//    00 CSR  <31:26> SBI faults (never set), <23> adapter power down,
//            <22> adapter power up (write 1 to clear), <7:0> adapter
//            code 20
//    04 CR   <3> maintenance mode, <2> interrupt enable, <1> abort data
//            transfer, <0> initialize (reads 0)
//    08 SR   <31> DT busy (read only), <30> no response confirmation,
//            <19> program error, <18> non-existent drive, <16> attention,
//            <13> DT complete, <12> DT aborted, <11> data late, <10>/<09>
//            write check upper/lower byte, <08> missed transfer, <07>
//            Massbus exception, <04> invalid map, <02> read data
//            substitute, <01> interface sequence timeout; written 1 to
//            clear
//    0C VAR  <16:9> map pointer, <8:0> byte offset
//    10 BCR  <31:16> Massbus byte counter (read only), <15:0> SBI byte
//            counter; a write loads the 2's complement of the byte count
//            into both
//    14 DR   <31:21> written in maintenance mode only, <20:8> the Massbus
//            FAIL, RUN, WCLK, EXC, CTOD, DS and RS lines, <7:0> a byte of
//            the Massbus data input buffer (<23> picks the upper one)
//    18 SMR  the map register VAR<16:9> points at
//    1C CAR  the command/address of the next DMA command
//    800-BFC MAP  <31> valid, <20:0> page frame number
//
//  VAR, BCR and the map registers cannot be written during a transfer (the
//  write is ignored, program error), nor maintenance mode set.
//
//  A drive register read returns the drive's 16 bits with SR<31:16>; a
//  write writes the low 16 bits (TD 3.7). A drive that does not answer
//  (TRA) within 1.5 us sets NED and reads as 0; the attention summary
//  register (drive register 4) is answered by every drive at once and
//  never sets NED (TD 4.5.2).
//
//  Data transfers: a write of a data transfer function with GO to a
//  drive's control register (bits <5:3> 101 write check, 110 write, 111
//  read; TD table 4-3) sets DT BUSY and goes to the drive, unless the
//  adapter is already busy with a transfer (program error, the command is
//  not sent). The data goes through a 32-byte silo between the Massbus
//  (16-bit words) and the SBI (quadwords: extended read from memory for a
//  write or a write check, extended write masked to memory for a read).
//  VAR is a byte address mapped by the 256 map registers into 512-byte
//  pages; VAR<2:0> follows the bytes, VAR<16:3> advances after every memory
//  reference, so a transfer that does not end on a quadword boundary leaves
//  VAR eight bytes past its last byte (TD 3.6.4, note). The SBI byte
//  counter counts the bytes to or from memory, the Massbus byte counter
//  those on the Massbus, two a word; when the latter reaches 0 the adapter
//  negates RUN and the drive stops at the end of the sector (a write is
//  completed with zeros). The normal end (TD 4.5.4): RUN negated, EBL from
//  the drive, the SBI byte counter at 0 and, for a read, the last memory
//  write acknowledged; DT COMP is set and DT BUSY cleared. An error that
//  aborts the transfer (TD table 3-6), or CR<1>, negates RUN and sends EXC
//  to the drive; the transfer ends at the drive's EBL with DT ABORTED and
//  DT COMP. No OCC or SCLK from the drive within 50 us of DT BUSY is a
//  missed transfer.
//
//  Interrupts (TD 3.4): with CR<2> set, at the end of a data transfer, and
//  for attention or an adapter error while no transfer is in progress: a
//  level on the SBI request line the jumpers give the adapter (BR5 for the
//  first RH780: IPL 15, SCB 100 + 40 + 4 * TR = 160), until software
//  clears the status bits that raised it.
//
//  Processor initialization leaves the adapter as its INIT (CR<0>) does:
//  IE clear, status and byte counters clear, no power-up interrupt pending;
//  VAR 0. The map registers keep what was written (0 after power-up).
//
//  Not modelled: SBI parity and faults, maintenance mode's simulated
//  Massbus signals (DR<27:24>) and the parity inversion bits, reverse
//  transfers (tape), corrected read data, read data timeouts and error
//  confirmations from memory (the SBIA never gives them).
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_mba #(
	parameter CLK_HZ = 50000000,
	parameter [3:0] TR = 4'd8
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
	output reg [31:0] nx_rdat,
	input             sbi_unjam,

	// SBI: the adapter as master (DMA to memory through the SBIA)
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

	output            req,           // interrupt request line (level)

	// Massbus control bus
	output reg        mb_dem,
	output reg        mb_ctod,
	output reg  [2:0] mb_ds,
	output reg  [4:0] mb_rs,
	output reg [15:0] mb_cw,
	output reg        mb_init,       // one clock
	input             mb_tra,
	input      [15:0] mb_cr,
	input             mb_attn,

	// Massbus data bus
	output reg        mb_run,
	output reg        mb_exco,       // the adapter's EXC
	output reg        mb_wclk,       // one clock: write data on mb_dw
	output reg [15:0] mb_dw,
	input             mb_occ,
	input             mb_sclk,       // one clock: read data on mb_dr, or
	                                 // (write) the drive wants a word
	input      [15:0] mb_dr,
	input             mb_ebl,        // one clock: end of block
	input             mb_exc         // the drive's EXC
);

	localparam integer T250  = (CLK_HZ + 3999999) / 4000000;        // 250 ns
	localparam integer T1500 = (CLK_HZ * 3 + 1999999) / 2000000;    // 1.5 us
	localparam integer T50US = CLK_HZ / 20000;                      // 50 us
	localparam integer TISTO = CLK_HZ / 9766;                       // 102.4 us
	localparam integer TDLT  = (CLK_HZ + 4999999) / 5000000;        // 200 ns

	assign dm_id = {1'b0, TR};

	/* ---------------------------------------------------------- decode */
	wire        me    = sbi_cmd && (sbi_adr[27:15] == 13'h1000) &&
	                    (sbi_adr[14:11] == TR);
	wire [10:0] la    = sbi_adr[10:0];
	wire        a_int = !la[10] && (la[9:8] == 2'b00) && (la[7:3] == 5'd0);
	wire        a_ext = !la[10] && (la[9:8] == 2'b01);
	wire        a_map = !la[10] && (la[9:8] == 2'b10);
	wire        a_ok  = a_int || a_ext || a_map;
	wire        f_rd  = (sbi_fn == 4'b0001) || (sbi_fn == 4'b0100);
	wire        f_wr  = (sbi_fn == 4'b0010) || (sbi_fn == 4'b0111);
	wire        f_ok  = (f_rd || f_wr) && (sbi_msk == 4'b1111);

	/* -------------------------------------------------------- registers */
	reg         csr_pu, csr_pd;
	reg         cr_mm, cr_ie, cr_abort;
	reg         sr_dtbusy, sr_nrconf, sr_pge, sr_ned, sr_attn, sr_dtcomp,
	            sr_dtabt, sr_dlt, sr_wcku, sr_wckl, sr_mxf, sr_mbexc,
	            sr_invmap, sr_rds, sr_istmo;
	reg  [16:0] var_r;
	reg  [15:0] sbc, mbc;            // SBI and Massbus byte counters
	reg  [10:0] dr_rw;               // DR<31:21>
	reg  [15:0] mdib;                // Massbus data input buffer

	// the map: two copies written together (M10K), one read at the page
	// VAR is in, one at the CPU's address; both a clock late
	(* ramstyle = "M10K" *) reg [21:0] map_a [0:255];  // {V, PFN}
	(* ramstyle = "M10K" *) reg [21:0] map_b [0:255];
	reg  [21:0] map_cur, map_cpu;
	reg   [7:0] map_cur_p;
	reg         map_we;
	reg   [7:0] map_wa;
	reg  [21:0] map_wd;
	always @(posedge clk) begin
		if (map_we) begin
			map_a[map_wa] <= map_wd;
			map_b[map_wa] <= map_wd;
		end
		map_cur   <= map_a[var_r[16:9]];
		map_cur_p <= var_r[16:9];
		map_cpu   <= map_b[la[7:0]];
	end
	// map_cur is the map register of VAR's page
	wire        map_ok = (map_cur_p == var_r[16:9]);

	wire [31:0] sr_q = {sr_dtbusy, sr_nrconf, 1'b0, 9'd0,
	                    sr_pge, sr_ned, 1'b0, sr_attn, 2'b00,
	                    sr_dtcomp, sr_dtabt, sr_dlt, sr_wcku, sr_wckl, sr_mxf,
	                    sr_mbexc, 1'b0, 1'b0, sr_invmap, 1'b0, sr_rds,
	                    sr_istmo, 1'b0};

	// the data transfer in progress
	reg   [1:0] dt_dir;              // 1 write check, 2 write, 3 read
	wire        dt_read = (dt_dir == 2'd3);

	wire  [3:0] car_fn = dt_read ? 4'b1011 : 4'b1000;
	wire [31:0] car_q  = {car_fn, map_cur[20:0], var_r[8:3], 1'b0};

	reg  [31:0] int_q;
	always @* begin
		case (la[2:0])
		3'd0: int_q = {8'd0, csr_pd, csr_pu, 14'd0, 8'h20};
		3'd1: int_q = {28'd0, cr_mm, cr_ie, cr_abort, 1'b0};
		3'd2: int_q = sr_q;
		3'd3: int_q = {15'd0, var_r};
		3'd4: int_q = {mbc, sbc};
		3'd5: int_q = {dr_rw, cr_mm, mb_run, mb_wclk, mb_exc | mb_exco,
		               mb_ctod, mb_ds, mb_rs, dr_rw[2] ? mdib[15:8] : mdib[7:0]};
		3'd6: int_q = {map_cur[21], 10'd0, map_cur[20:0]};
		default: int_q = car_q;
		endcase
	end

	/* ------------------------------------------------------- interrupts */
	// TD 3.4 and table 3-6: data transfer end, attention, program error,
	// non-existent drive, missed transfer, power up; held off while a
	// transfer runs
	assign req = cr_ie && !sr_dtbusy &&
	             (sr_pge | sr_ned | sr_attn | sr_dtcomp | sr_dtabt | sr_mxf |
	              csr_pu | csr_pd);

	/* --------------------------------------- Massbus control operations */
	// a drive register read or write: RS, DS (and CTOD, data) for 250 ns,
	// then DEM until TRA, 250 ns more; no TRA in 1.5 us is NED (TD 4.5.2)
	localparam [2:0] C_IDLE = 3'd0, C_SET = 3'd1, C_DEM = 3'd2, C_HOLD = 3'd3,
	                 C_END = 3'd4;
	reg   [2:0] cs;
	reg   [7:0] ct;
	reg         c_rd;                // a CPU read waits for the data
	reg  [15:0] c_q;
	wire        mba_busy = (cs != C_IDLE);
	reg         taken;               // this command answered already
	reg         me_d;                // the command was there a clock ago

	assign nx_busy = me && !taken && a_ok && mba_busy;
	wire   go_cmd  = me && me_d && !taken && a_ok && !mba_busy;

	/* ----------------------------------------------------- data path */
	// silo: 32 bytes between the Massbus and the SBI
	reg   [7:0] silo [0:31];
	reg   [4:0] s_rp, s_wp;
	reg   [5:0] s_n;
	wire  [5:0] s_free = 6'd32 - s_n;

	reg         sb_zero, mb_zero;    // a counter has gone through 0
	wire [16:0] mb_rem = mb_zero ? 17'd0 : (mbc == 16'd0) ? 17'h10000 :
	                     17'h10000 - {1'b0, mbc};
	wire [16:0] mbc2   = {1'b0, mbc} + 17'd2;   // the counter after a word
	wire [16:0] sbc1   = {1'b0, sbc} + 17'd1;   // after a byte
	wire  [1:0] w_need = (mb_rem >= 17'd2) ? 2'd2 : mb_rem[1:0];

	reg  [63:0] qd;                  // the quadword to or from memory
	reg   [7:0] qm;                  // read: the bytes of qd filled
	reg         q_full;              // write: qd has bytes for the silo
	reg   [2:0] q_pos;               // write: the next byte of qd
	reg         m_busy;              // a memory command is out
	reg  [12:0] m_tmo;               // its interface sequence timer
	reg         m_rd;                // it is a read

	reg  [15:0] wword;               // write, write check: the next word
	reg   [1:0] wbytes;              // its bytes so far
	reg   [1:0] rbytes;              // read: bytes of mdib still to store
	reg         w_req;               // the drive asked for (or sent) a word
	reg   [3:0] w_t;                 // how long ago
	reg         got_occ;             // the drive took the command
	reg  [11:0] mxf_t;
	reg         aborting;            // RUN negated and EXC out: until EBL
	reg         ebl_end;             // the drive ended (EBL, RUN negated)

	// the abort conditions of table 3-6
	wire        abort_now = sr_dlt | sr_wcku | sr_wckl | sr_mbexc |
	                        sr_invmap | sr_rds | sr_istmo | cr_abort;

	/* ---------------------------------------------------- main process */
	reg         s_push, s_pop;
	reg   [7:0] s_din;

	always @(posedge clk) begin
		nx_ack  <= 1'b0;
		nx_err  <= 1'b0;
		mb_init <= 1'b0;
		map_we  <= 1'b0;
		me_d    <= me && !taken;
		mb_wclk <= 1'b0;
		s_push  = 1'b0;
		s_pop   = 1'b0;
		s_din   = 8'd0;

		if (rst) begin
			csr_pu <= 1'b0; csr_pd <= 1'b0;
			cr_mm <= 1'b0; cr_ie <= 1'b0; cr_abort <= 1'b0;
			sr_dtbusy <= 1'b0; sr_nrconf <= 1'b0; sr_pge <= 1'b0;
			sr_ned <= 1'b0; sr_attn <= 1'b0; sr_dtcomp <= 1'b0;
			sr_dtabt <= 1'b0; sr_dlt <= 1'b0; sr_wcku <= 1'b0;
			sr_wckl <= 1'b0; sr_mxf <= 1'b0; sr_mbexc <= 1'b0;
			sr_invmap <= 1'b0; sr_rds <= 1'b0; sr_istmo <= 1'b0;
			var_r <= 17'd0; sbc <= 16'd0; mbc <= 16'd0;
			dr_rw <= 11'd0; mdib <= 16'd0;
			cs <= C_IDLE; taken <= 1'b0; c_rd <= 1'b0;
			mb_dem <= 1'b0; mb_ctod <= 1'b0; mb_ds <= 3'd0; mb_rs <= 5'd0;
			mb_cw <= 16'd0; mb_init <= 1'b1;
			mb_run <= 1'b0; mb_exco <= 1'b0; mb_dw <= 16'd0;
			dm_req <= 1'b0; m_busy <= 1'b0;
			s_rp <= 5'd0; s_wp <= 5'd0; s_n <= 6'd0;
			q_full <= 1'b0; qm <= 8'd0;
			wbytes <= 2'd0; rbytes <= 2'd0; w_req <= 1'b0;
			aborting <= 1'b0; ebl_end <= 1'b0; got_occ <= 1'b0;
			sb_zero <= 1'b0; mb_zero <= 1'b0;
			dt_dir <= 2'd0;
		end else begin
			if (!sbi_cmd)
				taken <= 1'b0;

			// attention from the Massbus (TD table 3-6: set by the line)
			if (mb_attn)
				sr_attn <= 1'b1;

			/* ------------------------ CPU commands for this nexus */
			if (go_cmd) begin
				taken <= 1'b1;
				if (!f_ok) begin
					// longword references only (TD 3.6, 4.2.7)
					nx_err <= 1'b1;
				end else if (a_ext) begin
					// a drive register: the Massbus control bus
					mb_ds   <= la[7:5];
					mb_rs   <= la[4:0];
					mb_ctod <= f_wr;
					c_rd    <= f_rd;
					ct      <= 8'd0;
					if (f_wr) begin
						nx_ack <= 1'b1;         // the write data is taken
						mb_cw  <= sbi_wdat[15:0];
						if (la[4:0] == 5'd0 && sbi_wdat[0] &&
						    sbi_wdat[5] && (sbi_wdat[4] | sbi_wdat[3])) begin
							// a data transfer command (TD 4.5.2)
							if (sr_dtbusy)
								sr_pge <= 1'b1;   // not sent
							else begin
								sr_dtbusy <= 1'b1;
								dt_dir    <= sbi_wdat[4:3];
								s_rp <= 5'd0; s_wp <= 5'd0; s_n <= 6'd0;
								qm <= 8'd0; q_full <= 1'b0;
								wbytes <= 2'd0; rbytes <= 2'd0;
								w_req <= 1'b0;
								sb_zero <= 1'b0; mb_zero <= 1'b0;
								aborting <= 1'b0; ebl_end <= 1'b0;
								got_occ <= 1'b0; mxf_t <= 12'd0;
								mb_run <= !cr_mm;
								cs <= C_SET;
							end
						end else
							cs <= C_SET;
					end else
						cs <= C_SET;
				end else if (f_rd) begin
					nx_ack  <= 1'b1;
					nx_rdat <= a_map ? {map_cpu[21], 10'd0, map_cpu[20:0]}
					                 : int_q;
				end else begin
					nx_ack <= 1'b1;
					if (a_map) begin
						if (sr_dtbusy)
							sr_pge <= 1'b1;
						else
						begin
							map_we <= 1'b1;
							map_wa <= la[7:0];
							map_wd <= {sbi_wdat[31], sbi_wdat[20:0]};
						end
					end else
						case (la[2:0])
						3'd0: if (sbi_wdat[22]) csr_pu <= 1'b0;
						3'd1: begin
							if (sbi_wdat[0]) begin
								// INIT (TD 3.2, 3.6.2)
								csr_pu <= 1'b0; csr_pd <= 1'b0;
								cr_ie <= 1'b0; cr_abort <= 1'b0;
								sr_dtbusy <= 1'b0; sr_nrconf <= 1'b0;
								sr_pge <= 1'b0; sr_ned <= 1'b0;
								sr_attn <= 1'b0; sr_dtcomp <= 1'b0;
								sr_dtabt <= 1'b0; sr_dlt <= 1'b0;
								sr_wcku <= 1'b0; sr_wckl <= 1'b0;
								sr_mxf <= 1'b0; sr_mbexc <= 1'b0;
								sr_invmap <= 1'b0; sr_rds <= 1'b0;
								sr_istmo <= 1'b0;
								sbc <= 16'd0; mbc <= 16'd0;
								dr_rw <= 11'd0;
								mb_init <= 1'b1;
								mb_run <= 1'b0; mb_exco <= 1'b0;
								aborting <= 1'b0;
								dm_req <= 1'b0; m_busy <= 1'b0;
								q_full <= 1'b0; qm <= 8'd0;
							end else begin
								if (sbi_wdat[3] && !cr_mm && sr_dtbusy)
									sr_pge <= 1'b1;
								else
									cr_mm <= sbi_wdat[3];
								cr_ie    <= sbi_wdat[2];
								cr_abort <= sbi_wdat[1];
							end
						end
						3'd2: begin
							if (sbi_wdat[30]) sr_nrconf <= 1'b0;
							if (sbi_wdat[19]) sr_pge    <= 1'b0;
							if (sbi_wdat[18]) sr_ned    <= 1'b0;
							if (sbi_wdat[16]) sr_attn   <= 1'b0;
							if (sbi_wdat[13]) sr_dtcomp <= 1'b0;
							if (sbi_wdat[12]) sr_dtabt  <= 1'b0;
							if (sbi_wdat[11]) sr_dlt    <= 1'b0;
							if (sbi_wdat[10]) sr_wcku   <= 1'b0;
							if (sbi_wdat[9])  sr_wckl   <= 1'b0;
							if (sbi_wdat[8])  sr_mxf    <= 1'b0;
							if (sbi_wdat[7])  sr_mbexc  <= 1'b0;
							if (sbi_wdat[4])  sr_invmap <= 1'b0;
							if (sbi_wdat[2])  sr_rds    <= 1'b0;
							if (sbi_wdat[1])  sr_istmo  <= 1'b0;
						end
						3'd3: if (sr_dtbusy) sr_pge <= 1'b1;
						      else var_r <= sbi_wdat[16:0];
						3'd4: if (sr_dtbusy) sr_pge <= 1'b1;
						      else begin
							sbc <= sbi_wdat[15:0];
							mbc <= sbi_wdat[15:0];
						end
						3'd5: if (cr_mm) dr_rw <= sbi_wdat[31:21];
						default: ;      // SMR, CAR: read only
						endcase
				end
			end

			/* ------------------------------ Massbus control bus */
			case (cs)
			C_SET: begin
				ct <= ct + 8'd1;
				if (ct == T250 - 1) begin
					ct <= 8'd0;
					mb_dem <= !cr_mm;   // maintenance mode blocks DEM
					cs <= C_DEM;
				end
			end
			C_DEM: begin
				ct <= ct + 8'd1;
				if (mb_rs == 5'd4) begin
					// attention summary: every drive answers, no TRA
					// and no NED; a write waits 1.5 us (TD 4.5.2)
					if (!mb_ctod ? (ct == T250 - 1) : (ct == T1500 - 1)) begin
						c_q <= mb_cr;
						ct  <= 8'd0;
						cs  <= C_HOLD;
					end
				end else if (mb_tra && !cr_mm) begin
					c_q <= mb_cr;
					ct  <= 8'd0;
					cs  <= C_HOLD;
				end else if (ct == T1500 - 1) begin
					// no TRA: non-existent drive
					if (!cr_mm)
						sr_ned <= 1'b1;
					c_q <= cr_mm ? mb_cw : 16'd0;
					ct  <= 8'd0;
					cs  <= C_HOLD;
				end
			end
			C_HOLD: begin
				mb_dem <= 1'b0;
				ct <= ct + 8'd1;
				if (ct == T250 - 1)
					cs <= C_END;
			end
			C_END: begin
				if (c_rd) begin
					nx_ack  <= 1'b1;
					nx_rdat <= {sr_q[31:16], c_q};
				end
				cs <= C_IDLE;
			end
			default: ;
			endcase

			/* ------------------------------------- the transfer */
			if (sr_dtbusy) begin
				if (mb_occ)
					got_occ <= 1'b1;

				// missed transfer: no OCC or SCLK in 50 us (TD 2.2.3)
				if (!got_occ && !mb_occ && !mb_sclk) begin
					mxf_t <= mxf_t + 12'd1;
					if (mxf_t == T50US[11:0] - 1) begin
						sr_mxf    <= 1'b1;
						sr_dtabt  <= 1'b1;
						sr_dtcomp <= 1'b1;
						sr_dtbusy <= 1'b0;
						mb_run    <= 1'b0;
					end
				end

				// the drive's exception
				if (mb_exc)
					sr_mbexc <= 1'b1;

				// the drive ended: EBL with RUN negated
				if (mb_ebl && (!mb_run || aborting))
					ebl_end <= 1'b1;

				if (aborting) begin
					// the in-flight memory command, then the drive's EBL
					// (or its OCC down): DT END, aborted (TD 4.5.4)
					if (!m_busy && (ebl_end || mb_ebl || !mb_occ)) begin
						sr_dtabt  <= 1'b1;
						sr_dtcomp <= 1'b1;
						sr_dtbusy <= 1'b0;
						mb_exco   <= 1'b0;
						aborting  <= 1'b0;
					end
				end else if (abort_now && got_occ) begin
					// negate RUN, EXC to the drive (TD 3.6.2, ABORT)
					aborting <= 1'b1;
					mb_run   <= 1'b0;
					mb_exco  <= 1'b1;
				end else if (dt_read) begin
					/* read: Massbus -> silo -> memory */
					if (mb_sclk && !mb_zero) begin
						if (rbytes != 2'd0 || s_free < 6'd2) begin
							sr_dlt <= 1'b1;   // overrun: data late
						end else begin
							mdib   <= mb_dr;
							rbytes <= 2'd2;
							mbc     <= mbc2[15:0];
							mb_zero <= mbc2[16];
							if (mbc2[16])
								mb_run <= 1'b0;
						end
					end else if (rbytes != 2'd0) begin
						// one byte a clock into the silo
						s_push = 1'b1;
						s_din  = (rbytes == 2'd2) ? mdib[7:0] : mdib[15:8];
						rbytes <= rbytes - 2'd1;
					end
					// silo -> the quadword for memory, one byte a clock
					if (!m_busy && !sb_zero && s_n != 6'd0 && !qm[7]) begin
						s_pop = 1'b1;
						qd[{var_r[2:0], 3'b000} +: 8] <= silo[s_rp];
						qm[var_r[2:0]] <= 1'b1;
						var_r[2:0] <= var_r[2:0] + 3'd1;
						sbc     <= sbc1[15:0];
						sb_zero <= sbc1[16];
					end
					// a full quadword, or the last bytes: write it
					if (!m_busy && qm != 8'd0 && (qm[7] || sb_zero) &&
					    !dr_rw[7] && map_ok) begin
						if (!map_cur[21])
							sr_invmap <= 1'b1;
						else begin
							m_busy  <= 1'b1;
							m_rd    <= 1'b0;
							m_tmo   <= 13'd0;
							dm_req  <= 1'b1;
							dm_fn   <= 4'b1011;
							dm_adr  <= {map_cur[20:0], var_r[8:3], 1'b0};
							dm_msk  <= qm[3:0];
							dm_msk2 <= qm[7:4];
							dm_wdat <= qd;
						end
					end
					// normal end (TD 4.5.4, condition 1)
					if (sb_zero && !m_busy && qm == 8'd0 && ebl_end)
						sr_dtbusy <= 1'b0;
				end else begin
					/* write and write check: memory -> silo -> Massbus */
					if (!m_busy && !q_full && !sb_zero && s_free >= 6'd8 &&
					    !dr_rw[7] && map_ok) begin
						if (!map_cur[21])
							sr_invmap <= 1'b1;
						else begin
							m_busy  <= 1'b1;
							m_rd    <= 1'b1;
							m_tmo   <= 13'd0;
							dm_req  <= 1'b1;
							dm_fn   <= 4'b1000;
							dm_adr  <= {map_cur[20:0], var_r[8:3], 1'b0};
							dm_msk  <= 4'b1111;
							dm_msk2 <= 4'b1111;
						end
					end
					// the quadword read, one byte a clock into the silo
					if (q_full) begin
						s_push = 1'b1;
						s_din  = qd[{q_pos, 3'b000} +: 8];
						q_pos  <= q_pos + 3'd1;
						var_r[2:0] <= var_r[2:0] + 3'd1;
						sbc     <= sbc1[15:0];
						sb_zero <= sbc1[16];
						if (q_pos == 3'd7 || sbc1[16])
							q_full <= 1'b0;
					end
					// the next word for the drive, from the silo
					if (wbytes < w_need && s_n != 6'd0) begin
						s_pop = 1'b1;
						if (wbytes == 2'd0) wword[7:0]  <= silo[s_rp];
						else                wword[15:8] <= silo[s_rp];
						wbytes <= wbytes + 2'd1;
					end
					// the drive asks for a word (write) or sends one
					// (write check); it must be there within 200 ns
					if (mb_sclk && !mb_zero) begin
						w_req <= 1'b1;
						w_t   <= 4'd0;
						if (dt_dir == 2'd1)
							mdib <= mb_dr;
					end else if (mb_sclk && dt_dir == 2'd2) begin
						// past the byte count: the sector ends in zeros
						mb_dw   <= 16'd0;
						mb_wclk <= 1'b1;
					end
					if (w_req) begin
						if (wbytes == w_need && w_need != 2'd0) begin
							w_req  <= 1'b0;
							wbytes <= 2'd0;
							mbc     <= mbc2[15:0];
							mb_zero <= mbc2[16];
							if (mbc2[16])
								mb_run <= 1'b0;
							if (dt_dir == 2'd2) begin
								mb_dw   <= (wbytes == 2'd2) ? wword
								           : {8'd0, wword[7:0]};
								mb_wclk <= 1'b1;
							end else begin
								if (mdib[7:0] != wword[7:0])
									sr_wckl <= 1'b1;
								if (wbytes == 2'd2 &&
								    mdib[15:8] != wword[15:8])
									sr_wcku <= 1'b1;
							end
						end else begin
							w_t <= w_t + 4'd1;
							if (w_t == TDLT[3:0] - 1) begin
								w_req  <= 1'b0;
								sr_dlt <= 1'b1;   // data late
							end
						end
					end
					// normal end (TD 4.5.4, condition 2)
					if (sb_zero && !m_busy && !q_full && ebl_end)
						sr_dtbusy <= 1'b0;
				end
				// DT END: DT COMP, RUN and EXC down
				if (!aborting && sb_zero && !m_busy && ebl_end &&
				    (dt_read ? (qm == 8'd0) : !q_full)) begin
					sr_dtcomp <= 1'b1;
					mb_run    <= 1'b0;
				end
			end

			/* --------------------------- the memory command */
			if (m_busy) begin
				if (dm_done) begin
					dm_req <= 1'b0;
					m_busy <= 1'b0;
					var_r[16:3] <= var_r[16:3] + 14'd1;
					if (m_rd) begin
						if (dm_rds)
							sr_rds <= 1'b1;   // read data substitute
						else begin
							qd     <= dm_rdat;
							q_full <= 1'b1;
							q_pos  <= var_r[2:0];
						end
					end else
						qm <= 8'd0;
				end else begin
					if (dm_nr)
						sr_nrconf <= 1'b1;        // retried
					m_tmo <= m_tmo + 13'd1;
					if (m_tmo == TISTO[12:0] - 1) begin
						// interface sequence timeout: 512 SBI cycles
						sr_istmo <= 1'b1;
						dm_req   <= 1'b0;
						m_busy   <= 1'b0;
					end
				end
			end

			/* ------------------------------------------- silo */
			if (s_push) begin
				silo[s_wp] <= s_din;
				s_wp <= s_wp + 5'd1;
			end
			if (s_pop)
				s_rp <= s_rp + 5'd1;
			if (s_push && !s_pop)
				s_n <= s_n + 6'd1;
			else if (s_pop && !s_push)
				s_n <= s_n - 6'd1;

			/* -------------------------------------------- UNJAM */
			if (sbi_unjam) begin
				cr_abort <= 1'b0;
				csr_pu   <= 1'b0;
			end
		end
	end

endmodule

`default_nettype wire

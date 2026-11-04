//============================================================================
//  vax_rp07.v - an RP07 disk drive on the Massbus, its 516 MB kept in a
//  disk image on the SD card (the MiSTer HPS's block device interface).
//
//  Sources: RP04/RP05/RP06 Device Control Logic Maintenance Manual
//  (EK-RP056-MM-01): the Massbus registers and their bits (2.4.1.3), the
//  commands and what DRY, PIP and ATA do for each (2.3, table 2-1), the
//  sector format and header words (2.4.4, 3.6, 3.9), seeks (3.4), error
//  handling (3.12); RP07 Service Manual (ER-ORP07-SV): geometry and timing
//  (table 1-2), serial number, interleave and dual port options (2.5.2);
//  DEC's TOPS-20 RP07 support (rp07.mac) for what the RP07 changes in the
//  registers: drive type 042, the sector field <6:0> and track field <13:8>
//  of DA, the look-ahead sector count <12:6>, no offset magnitude in OF;
//  RH780 Technical Description (EK-RH780-TD-001) chapter 2 for the Massbus
//  signals.
//
//  Geometry: 630 cylinders, 32 tracks, 50 sectors of 512 bytes (16-bit
//  format): 1 008 000 sectors. The image holds the sectors in order,
//  LBA = (cylinder * 32 + track) * 50 + sector, 512 bytes each, the first
//  byte of a sector the low byte of its first word. Sectors beyond the end
//  of a shorter image read as zeros and are not written.
//
//  Registers (octal register number, 16 bits):
//
//    00 CS1  <11> DVA (always: a single port drive), <5:1> function,
//            <0> GO (set while a command runs)
//    01 DS   <15> ATA, <14> ERR, <13> PIP, <12> MOL, <11> WRL, <10> LST,
//            <9> PGM (0), <8> DPR (1), <7> DRY, <6> VV, <2> ILV (0: not
//            interleaved), <1> EW (0), <0> OM
//    02 ER1  DCK UNS OPI DTE WLE IAE AOE HCRC HCE ECH WCF FER PAR RMR ILR
//            ILF, <15> to <0>; the model sets UNS, WLE, IAE, AOE, FER,
//            RMR, ILR and ILF
//    03 MR   maintenance; <15> diagnostic mode (no other effect here)
//    04 AS   attention summary: every drive answers with its ATA on the
//            bit of its unit number; writing 1 there clears it
//    05 DA   <13:8> track, <6:0> sector
//    06 DT   020042: moving head, drive type 042 (no DRQ: single port)
//    07 LA   <12:6> the sector under the heads
//    10 SN   serial number, four BCD digits
//    11 OF   <15> command modifier, <14> move track descriptor, <12> FMT
//            (16-bit format), <11> ECI, <10> HCI
//    12 DC   <9:0> desired cylinder
//    13 CC   <9:0> current cylinder
//    14 ER2, 15 ER3   drive errors (none happen); 16 EC1, 17 EC2 ECC (0)
//    20-37  no such register: ILR
//
//  Every register can be read; DS, DT, LA, SN, CC, EC1, EC2 ignore writes
//  (no error). While a command runs (GO set) only MR and AS may be
//  written, anything else sets RMR and is ignored. A drive with ERR set
//  ignores every command but drive clear (RH780 TD 3.3); writing CS1
//  without an error clears ATA (EK-RP056-MM-01 3.12.1). An error sets ATA
//  at once, or at the end of a data transfer.
//
//  Commands (function code with GO, octal):
//
//    01 no-op            03 unload           05 seek
//    07 recalibrate      11 drive clear      13 release (= drive clear)
//    15 offset           17 return to centerline
//    21 read-in preset   23 pack acknowledge 31 search
//    51 write check data      53 write check header and data
//    61 write data            63 write header and data
//    71 read data             73 read header and data
//
//  anything else is an illegal function. Seek, recalibrate, offset, return
//  to centerline and search set PIP and end with ATA (a seek to where the
//  heads are ends at once); an address out of range is IAE; positioning or
//  transferring with no image mounted is UNS; a write on a write-locked
//  (read only) image is WLE. Unload takes the drive off line (MOL clear)
//  until an image is mounted again, which ends the command with ATA.
//
//  Data transfers seek if DC is not CC (no PIP), wait for the sector, then
//  transfer sector after sector while the adapter keeps RUN asserted,
//  sampled at the end of each sector (EBL); the address advances through
//  tracks and cylinders (mid-transfer seeks) and DA and DC are left at the
//  sector after the last. Past the last sector of the disk with RUN still
//  asserted the transfer stops with AOE; LST tells that the last sector was
//  done. A header command transfers four header words before each sector's
//  256 data words: the cylinder with the format bit <12>, the sector/track
//  word, two key words (0); written headers are not kept, the image holding
//  data only. Header verification against FMT: with OF<12> and HCI clear,
//  read data, write data and write check data stop at once with FER (the
//  packs are formatted 16-bit); read header and data and write check header
//  and data flag it and go on. EXC from the adapter ends the transfer at
//  once (a sector being written is not written).
//
//  Timing, from the RP07's specifications: 3633 rpm, 50 sectors (330 us a
//  sector), data at 2.16 MB/s within a sector (a word every 0.93 us);
//  seeks from 5 ms (one cylinder) through 23 ms (average) to 46 ms (full
//  stroke); offset and return to centerline 5 ms. TSCALE divides the
//  mechanical times (rotation, seeks) for simulation, not the data rate.
//  The drive is ready as soon as an image is mounted: no spin-up time. When
//  the SD card is slower than the platter, a sector waits for its data.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_rp07 #(
	parameter CLK_HZ  = 50000000,
	parameter [2:0] UNIT = 3'd0,
	parameter [15:0] SN = 16'h0001,  // serial number, BCD
	parameter TSCALE  = 1
) (
	input             clk,
	input             rst,

	// Massbus control bus
	input             mb_dem,
	input             mb_ctod,
	input       [2:0] mb_ds,
	input       [4:0] mb_rs,
	input      [15:0] mb_cw,
	input             mb_init,
	output            mb_tra,
	output     [15:0] mb_cr,
	output            mb_attn,

	// Massbus data bus
	input             mb_run,
	input             mb_exci,       // the adapter's EXC
	input             mb_wclk,
	input      [15:0] mb_dw,
	output            mb_occ,
	output reg        mb_sclk,
	output reg [15:0] mb_dr,         // 0 but with mb_sclk
	output reg        mb_ebl,
	output            mb_exc,

	// the disk image (hps_io block device, 512-byte blocks)
	output reg [31:0] sd_lba,
	output reg        sd_rd,
	output reg        sd_wr,
	input             sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,
	output reg  [7:0] sd_buff_din,
	input             img_mounted,   // one clock: a new image (or none)
	input             img_readonly,
	input      [63:0] img_size,

	output            active
);

	/* ---------------------------------------------------- geometry */
	localparam [9:0]  NCYL  = 10'd630;
	localparam [5:0]  NTRK  = 6'd32;
	localparam [6:0]  NSEC  = 7'd50;
	localparam [19:0] LAST  = 20'd1007999;
	localparam [15:0] DTYPE = 16'o020042;

	/* ------------------------------------------------------ timing */
	localparam integer T_WORD = CLK_HZ / 1080000;                       // 0.93 us
	localparam integer T_SECT = (CLK_HZ / 1000) * 3303 / 10000 / TSCALE; // 330 us
	localparam integer T_HDR  = (CLK_HZ / 1000) * 29 / 1000;            // 29 us
	localparam integer T_ECC  = (CLK_HZ / 1000) * 28 / 10000;           // 2.8 us
	localparam integer T_250  = (CLK_HZ + 3999999) / 4000000;           // 250 ns
	localparam integer T_10US = (CLK_HZ / 100000) / TSCALE;             // 10 us

	// seek time in 10 us units: 5 ms + 41 ms * (d / 629) ^ 0.75, in bands
	// of 16 cylinders (one cylinder 5 ms, average 23 ms, full stroke 46 ms)
	function [12:0] seek_t(input [9:0] d);
		begin
			if (d == 10'd0)
				seek_t = 13'd0;
			else if (d == 10'd1)
				seek_t = 13'd500;
			else case (d[9:4])
			6'd0:  seek_t = 13'd700;   6'd1:  seek_t = 13'd1000;
			6'd2:  seek_t = 13'd1210;  6'd3:  seek_t = 13'd1390;
			6'd4:  seek_t = 13'd1550;  6'd5:  seek_t = 13'd1700;
			6'd6:  seek_t = 13'd1840;  6'd7:  seek_t = 13'd1970;
			6'd8:  seek_t = 13'd2090;  6'd9:  seek_t = 13'd2210;
			6'd10: seek_t = 13'd2330;  6'd11: seek_t = 13'd2440;
			6'd12: seek_t = 13'd2550;  6'd13: seek_t = 13'd2660;
			6'd14: seek_t = 13'd2760;  6'd15: seek_t = 13'd2860;
			6'd16: seek_t = 13'd2960;  6'd17: seek_t = 13'd3060;
			6'd18: seek_t = 13'd3150;  6'd19: seek_t = 13'd3240;
			6'd20: seek_t = 13'd3340;  6'd21: seek_t = 13'd3430;
			6'd22: seek_t = 13'd3510;  6'd23: seek_t = 13'd3600;
			6'd24: seek_t = 13'd3690;  6'd25: seek_t = 13'd3770;
			6'd26: seek_t = 13'd3860;  6'd27: seek_t = 13'd3940;
			6'd28: seek_t = 13'd4020;  6'd29: seek_t = 13'd4100;
			6'd30: seek_t = 13'd4180;  6'd31: seek_t = 13'd4260;
			6'd32: seek_t = 13'd4340;  6'd33: seek_t = 13'd4420;
			6'd34: seek_t = 13'd4490;  6'd35: seek_t = 13'd4570;
			default: seek_t = 13'd4600;
			endcase
		end
	endfunction

	/* --------------------------------------------------- registers */
	reg         go;
	reg   [4:0] fn;
	reg         ata, pip, mol, lst, vv, om;
	reg  [15:0] er1, er2, er3, mr;
	reg   [5:0] da_trk;
	reg   [6:0] da_sec;
	reg   [9:0] dc, cc;
	reg  [15:0] of_r;
	wire        err = (er1 != 16'd0) || (er2 != 16'd0) || (er3 != 16'd0);
	reg         wrl;                 // the image is read only
	wire        dry = !go;
	reg   [6:0] rot_sec;             // the sector under the heads
	reg  [15:0] rot_t;

	wire [15:0] ds_q = {ata, err, pip, mol, wrl, lst, 1'b0, 1'b1, dry, vv,
	                    3'b000, 1'b0, 1'b0, om};

	reg  [15:0] reg_q;
	always @* begin
		case (mb_rs)
		5'o00: reg_q = {4'b0000, 1'b1, 5'b00000, fn, go};
		5'o01: reg_q = ds_q;
		5'o02: reg_q = er1;
		5'o03: reg_q = mr;
		5'o05: reg_q = {2'b00, da_trk, 1'b0, da_sec};
		5'o06: reg_q = DTYPE;
		5'o07: reg_q = {3'b000, rot_sec, 6'b000000};
		5'o10: reg_q = SN;
		5'o11: reg_q = of_r;
		5'o12: reg_q = {6'd0, dc};
		5'o13: reg_q = {6'd0, cc};
		5'o14: reg_q = er2;
		5'o15: reg_q = er3;
		default: reg_q = 16'd0;  // EC1, EC2; 20-37 illegal
		endcase
	end

	/* --------------------------------------------- control bus */
	reg         dem_q;
	reg   [7:0] tra_t;
	reg         tra_r;
	reg  [15:0] cr_q;
	wire        dem_rise = mb_dem && !dem_q;
	wire        sel      = (mb_ds == UNIT) && (mb_rs != 5'o04);

	assign mb_tra  = tra_r && mb_dem;
	assign mb_cr   = (mb_tra ? cr_q : 16'd0) |
	                 ((mb_dem && mb_rs == 5'o04 && !mb_ctod) ?
	                  ({15'd0, ata} << UNIT) : 16'd0);
	assign mb_attn = ata;

	/* ---------------------------------------------- the sectors */
	// two 512-byte buffers (slots), each holding a sector of the image
	localparam [2:0] SL_EMPTY = 3'd0, SL_RDREQ = 3'd1, SL_RDING = 3'd2,
	                 SL_VALID = 3'd3, SL_DIRTY = 3'd4, SL_WRING = 3'd5,
	                 SL_FILL  = 3'd6;
	reg   [2:0] sl_st0, sl_st1;
	reg  [19:0] sl_lba0, sl_lba1;
	reg         sl_z0, sl_z1;        // beyond the image: zeros
	reg  [19:0] nsect;               // sectors in the image
	reg         sd_slot;             // the slot the HPS transfer is for
	reg         sd_busy;
	reg         sd_stale;            // the image changed meanwhile

	(* ramstyle = "M10K, no_rw_check" *) reg [7:0] buf_ram [0:1023];
	reg   [9:0] b_adr;
	reg   [7:0] b_din, b_q;
	reg         b_we;
	always @(posedge clk) begin
		if (sd_buff_wr && sd_ack)
			buf_ram[{sd_slot, sd_buff_addr}] <= sd_buff_dout;
		sd_buff_din <= buf_ram[{sd_slot, sd_buff_addr}];
	end
	always @(posedge clk) begin
		if (b_we)
			buf_ram[b_adr] <= b_din;
		b_q <= buf_ram[b_adr];
	end

	/* ------------------------------------------ the transfer state */
	localparam [3:0] D_IDLE = 4'd0, D_POS = 4'd1, D_PSRCH = 4'd2,
	                 D_UNLD = 4'd3, D_XSEEK = 4'd4, D_XSRCH = 4'd5,
	                 D_XWAIT = 4'd6, D_XHDR = 4'd7, D_XDATA = 4'd8,
	                 D_XECC = 4'd9, D_XEBL = 4'd10, D_XNEXT = 4'd11;
	reg   [3:0] st;
	reg  [22:0] pos_t;               // positioning time left
	reg   [9:0] pos_cyl;             // where the positioner goes
	reg   [1:0] pos_kind;            // 0 seek/recal, 1 offset, 2 rtc, 3 search
	reg         x_occ;               // OCC
	reg         x_exc;               // the drive's EXC
	reg         x_write, x_wchk, x_hdr;
	reg         x_err;               // an error during this transfer
	reg  [19:0] x_lba;               // the current sector
	reg         x_slot;
	reg   [8:0] x_w;                 // word in the sector (header: 0-3)
	reg  [15:0] x_t;                 // word timer
	reg  [16:0] x_st;                // time since the sector began
	reg   [1:0] x_ph;                // byte phase within a word
	reg  [15:0] x_word;
	reg         x_wreq;              // write: a word asked for
	reg         x_first;             // the first sector: wait for rotation
	reg         x_done;              // the sector's data went through

	assign mb_occ  = x_occ;
	assign mb_exc  = x_exc;
	assign active  = x_occ || (st == D_POS) || (st == D_PSRCH) || sd_busy;

	// cylinder * 1600 + track * 50 + sector
	wire [19:0] lba_of = ({10'd0, dc} << 10) + ({10'd0, dc} << 9) +
	                     ({10'd0, dc} << 6) +
	                     ({14'd0, da_trk} << 5) + ({14'd0, da_trk} << 4) +
	                     ({14'd0, da_trk} << 1) + {13'd0, da_sec};
	wire        addr_ok = (dc < NCYL) && (da_trk < NTRK) && (da_sec < NSEC);
	wire  [9:0] cyl_d   = (dc > cc) ? dc - cc : cc - dc;

	// header words (EK-RP056-MM-01 2.4.4): cylinder with the format bit,
	// sector/track, two key words
	wire [15:0] hdr_w = (x_w[1:0] == 2'd0) ? {3'b000, 1'b1, 2'b00, cc} :
	                    (x_w[1:0] == 2'd1) ? {2'b00, da_trk, 1'b0, da_sec} :
	                    16'd0;

	// a slot with the current sector's data
	wire        has0  = (sl_st0 == SL_VALID || sl_st0 == SL_DIRTY ||
	                     sl_st0 == SL_WRING);
	wire        has1  = (sl_st1 == SL_VALID || sl_st1 == SL_DIRTY ||
	                     sl_st1 == SL_WRING);
	wire        hit0  = has0 && (sl_lba0 == x_lba);
	wire        hit1  = has1 && (sl_lba1 == x_lba);
	wire        pend0 = (sl_st0 == SL_RDREQ || sl_st0 == SL_RDING) &&
	                    (sl_lba0 == x_lba);
	wire        pend1 = (sl_st1 == SL_RDREQ || sl_st1 == SL_RDING) &&
	                    (sl_lba1 == x_lba);
	wire        free0 = (sl_st0 == SL_EMPTY || sl_st0 == SL_VALID);
	wire        free1 = (sl_st1 == SL_EMPTY || sl_st1 == SL_VALID);
	wire [19:0] n_lba = x_lba + 20'd1;
	wire        nx0   = (sl_st0 != SL_EMPTY) && (sl_lba0 == n_lba);
	wire        nx1   = (sl_st1 != SL_EMPTY) && (sl_lba1 == n_lba);

	task set_err(input [15:0] bits);
		begin
			er1 <= er1 | bits;
			if (!x_occ)
				ata <= 1'b1;
			else
				x_err <= 1'b1;
		end
	endtask

	task xfer_end;                  // the end of a data transfer
		begin
			x_occ <= 1'b0;
			x_exc <= 1'b0;
			go    <= 1'b0;
			st    <= D_IDLE;
			if (x_err || err)
				ata <= 1'b1;
		end
	endtask

	always @(posedge clk) begin
		mb_sclk <= 1'b0;
		mb_dr   <= 16'd0;
		mb_ebl  <= 1'b0;
		b_we    <= 1'b0;
		dem_q   <= mb_dem;

		// the spindle: the sector under the heads
		if (rot_t == T_SECT - 1) begin
			rot_t   <= 16'd0;
			rot_sec <= (rot_sec == NSEC - 1) ? 7'd0 : rot_sec + 7'd1;
		end else
			rot_t <= rot_t + 16'd1;

		if (rst) begin
			go <= 1'b0; fn <= 5'd0;
			ata <= 1'b0; pip <= 1'b0; lst <= 1'b0; vv <= 1'b0; om <= 1'b0;
			er1 <= 16'd0; er2 <= 16'd0; er3 <= 16'd0; mr <= 16'd0;
			da_trk <= 6'd0; da_sec <= 7'd0; dc <= 10'd0; cc <= 10'd0;
			of_r <= 16'd0;
			tra_r <= 1'b0; tra_t <= 8'd0;
			st <= D_IDLE; x_occ <= 1'b0; x_exc <= 1'b0;
			x_err <= 1'b0; x_wreq <= 1'b0;
			if (!sd_busy) begin
				sl_st0 <= SL_EMPTY; sl_st1 <= SL_EMPTY;
			end else
				sd_stale <= 1'b1;
			// an image mounted during processor initialization (the HPS
			// mounts them as the core starts): on line, no attention
			if (img_mounted) begin
				mol   <= (img_size != 64'd0);
				wrl   <= img_readonly;
				nsect <= (img_size[63:29] != 35'd0) ? 20'hFFFFF : img_size[28:9];
				sl_st0 <= SL_EMPTY; sl_st1 <= SL_EMPTY;
				if (sd_busy)
					sd_stale <= 1'b1;
			end
		end else begin
			/* ----------------------------- image mounted or gone */
			if (img_mounted) begin
				mol   <= (img_size != 64'd0);
				wrl   <= img_readonly;
				nsect <= (img_size[63:29] != 35'd0) ? 20'hFFFFF : img_size[28:9];
				vv    <= 1'b0;
				cc    <= 10'd0;
				sl_st0 <= SL_EMPTY; sl_st1 <= SL_EMPTY;
				if (sd_busy)
					sd_stale <= 1'b1;
				if (st == D_UNLD) begin
					// back on line: the unload is over
					if (img_size != 64'd0) begin
						pip <= 1'b0; go <= 1'b0; st <= D_IDLE;
						ata <= 1'b1;
					end
				end else if (mol || img_size != 64'd0) begin
					// off line and on line again: attention
					ata <= 1'b1;
					if (x_occ) begin
						er1   <= er1 | 16'o040000;   // UNS
						x_err <= 1'b1;
						x_exc <= 1'b1;
						st    <= D_XEBL;
					end else if (st == D_POS || st == D_PSRCH) begin
						go <= 1'b0; pip <= 1'b0; st <= D_IDLE;
					end
				end
			end

			/* ------------------------------------- control bus */
			if (!mb_dem) begin
				tra_r <= 1'b0;
				tra_t <= 8'd0;
			end else if (dem_rise && sel) begin
				tra_t <= 8'd1;
			end else if (tra_t != 8'd0 && !tra_r) begin
				tra_t <= tra_t + 8'd1;
				if (tra_t == T_250)
					tra_r <= 1'b1;
			end

			if (dem_rise && mb_rs == 5'o04 && mb_ctod) begin
				// attention summary write: every drive looks at its bit
				if (mb_cw[UNIT])
					ata <= 1'b0;
			end else if (dem_rise && sel) begin
				cr_q <= reg_q;
				if (mb_rs > 5'o17) begin
					set_err(16'o000002);            // ILR
				end else if (mb_ctod) begin
					if (go && mb_rs != 5'o03) begin
						set_err(16'o000004);        // RMR
					end else case (mb_rs)
					5'o00: begin
						fn <= mb_cw[5:1];
						if (!err)
							ata <= 1'b0;
						if (mb_cw[0] && (!err || mb_cw[5:1] == 5'o04))
							case (mb_cw[5:1])
							5'o00: ;                         // no-op
							5'o04, 5'o05: begin              // drive clear
								er1 <= 16'd0; er2 <= 16'd0; er3 <= 16'd0;
								ata <= 1'b0;
								mr[15] <= 1'b0;
							end
							5'o10: begin                     // read-in preset
								vv <= 1'b1;
								da_trk <= 6'd0; da_sec <= 7'd0; dc <= 10'd0;
								of_r[12:10] <= 3'b000;
							end
							5'o11: vv <= 1'b1;               // pack acknowledge
							5'o01: begin                     // unload
								if (!mol)
									set_err(16'o040000);      // UNS
								else begin
									go  <= 1'b1;
									pip <= 1'b1;
									mol <= 1'b0;
									vv  <= 1'b0;
									st  <= D_UNLD;
								end
							end
							5'o03: begin                     // recalibrate
								if (!mol)
									set_err(16'o040000);
								else begin
									go <= 1'b1; pip <= 1'b1; st <= D_POS;
									pos_cyl  <= 10'd0;
									pos_kind <= 2'd0;
									pos_t <= T_10US * seek_t((cc == 10'd0) ? 10'd1 : cc);
								end
							end
							5'o06, 5'o07: begin              // offset, return
								if (!mol)
									set_err(16'o040000);
								else begin
									go <= 1'b1; pip <= 1'b1; st <= D_POS;
									pos_cyl  <= cc;
									pos_kind <= mb_cw[1] ? 2'd2 : 2'd1;
									pos_t <= T_10US * 500;
								end
							end
							5'o02, 5'o14: begin              // seek, search
								if (!mol)
									set_err(16'o040000);
								else if (!addr_ok)
									set_err(16'o002000);      // IAE
								else begin
									go <= 1'b1; pip <= 1'b1; st <= D_POS;
									pos_cyl  <= dc;
									pos_kind <= mb_cw[5] ? 2'd0 : mb_cw[4] ? 2'd3 : 2'd0;
									pos_t <= T_10US * (seek_t(cyl_d) +
									         ((om && cyl_d != 10'd0) ? 13'd500 : 13'd0)) + 23'd1;
								end
							end
							5'o24, 5'o25, 5'o30, 5'o31, 5'o34, 5'o35: begin
								// data transfers
								if (!mol)
									set_err(16'o040000);      // UNS
								else if (!addr_ok)
									set_err(16'o002000);      // IAE
								else if (mb_cw[5:2] == 4'b1100 && wrl)
									set_err(16'o004000);      // WLE
								else begin
									go      <= 1'b1;
									x_occ   <= 1'b1;
									x_exc   <= 1'b0;
									x_err   <= 1'b0;
									x_write <= (mb_cw[5:2] == 4'b1100);
									x_wchk  <= (mb_cw[5:2] == 4'b1010);
									x_hdr   <= mb_cw[1];
									x_lba   <= lba_of;
									x_first <= 1'b1;
									x_wreq  <= 1'b0;
									x_done  <= 1'b0;
									pos_t   <= T_10US * (seek_t(cyl_d) +
									           ((om && cyl_d != 10'd0) ? 13'd500 : 13'd0));
									st      <= D_XSEEK;
								end
							end
							default: set_err(16'o000001);    // ILF
							endcase
					end
					5'o02: er1 <= mb_cw;
					5'o03: mr  <= mb_cw;
					5'o05: begin
						da_trk <= mb_cw[13:8];
						da_sec <= mb_cw[6:0];
					end
					5'o11: of_r <= mb_cw & 16'o156000;
					5'o12: dc   <= mb_cw[9:0];
					5'o14: er2  <= mb_cw;
					5'o15: er3  <= mb_cw;
					default: ;                     // read only
					endcase
				end
			end

			/* ----------------------------- the drive at work */
			case (st)
			D_POS: begin
				if (pos_t != 23'd0)
					pos_t <= pos_t - 23'd1;
				else begin
					cc <= pos_cyl;
					om <= (pos_kind == 2'd1);
					if (pos_kind == 2'd3)
						st <= D_PSRCH;       // search: then the sector
					else begin
						pip <= 1'b0; go <= 1'b0; ata <= 1'b1;
						st  <= D_IDLE;
					end
				end
			end

			D_PSRCH: if (rot_sec == da_sec && rot_t == 16'd0) begin
				// the sector found (EK-RP056-MM-01 3.5.2)
				pip <= 1'b0; go <= 1'b0; ata <= 1'b1;
				st  <= D_IDLE;
			end

			D_XSEEK: begin
				// implied or mid-transfer seek (no PIP)
				if (pos_t != 23'd0)
					pos_t <= pos_t - 23'd1;
				else begin
					if (dc != cc)
						om <= 1'b0;
					cc <= dc;
					if (!of_r[12] && !of_r[10] && !x_hdr) begin
						// no header verifies against FMT: FER, stop
						er1   <= er1 | 16'o000020;
						x_err <= 1'b1;
						x_exc <= 1'b1;
						st    <= D_XEBL;
					end else begin
						if (!of_r[12] && !of_r[10] && !x_write) begin
							// header command: flagged, the transfer goes on
							er1   <= er1 | 16'o000020;
							x_err <= 1'b1;
						end
						st <= D_XSRCH;
					end
				end
			end

			D_XSRCH: begin
				// the first sector waits for the platter to bring it,
				// the next ones a sector time after the last began
				if (x_first ? (rot_sec == da_sec && rot_t == 16'd0)
				            : (x_st >= T_SECT - 1)) begin
					x_first <= 1'b0;
					x_st    <= 17'd0;
					st      <= D_XWAIT;
				end else
					x_st <= x_st + 17'd1;
			end

			D_XWAIT: begin
				// the sector's data (read), a free buffer (write)
				x_st <= x_st + 17'd1;
				x_w  <= 9'd0;
				x_t  <= 16'd0;
				x_ph <= 2'd0;
				if (x_write) begin
					if (hit0 ? (sl_st0 == SL_VALID) : (!hit1 && free0 && !pend0)) begin
						x_slot <= 1'b0; sl_lba0 <= x_lba; sl_st0 <= SL_FILL;
						st <= D_XHDR;
					end else if (hit1 ? (sl_st1 == SL_VALID) : (!hit0 && free1 && !pend1)) begin
						x_slot <= 1'b1; sl_lba1 <= x_lba; sl_st1 <= SL_FILL;
						st <= D_XHDR;
					end
				end else begin
					if (hit0 || hit1) begin
						x_slot <= hit1;
						st <= D_XHDR;
						// read ahead the next sector into the other slot
						if (x_lba != LAST && !nx0 && !nx1) begin
							if (hit0 && free1) begin
								sl_lba1 <= n_lba; sl_st1 <= SL_RDREQ;
								sl_z1   <= (n_lba >= nsect);
							end else if (hit1 && free0) begin
								sl_lba0 <= n_lba; sl_st0 <= SL_RDREQ;
								sl_z0   <= (n_lba >= nsect);
							end
						end
					end else if (!pend0 && !pend1) begin
						if (free0) begin
							sl_lba0 <= x_lba; sl_st0 <= SL_RDREQ;
							sl_z0   <= (x_lba >= nsect);
						end else if (free1) begin
							sl_lba1 <= x_lba; sl_st1 <= SL_RDREQ;
							sl_z1   <= (x_lba >= nsect);
						end
					end
				end
			end

			D_XHDR: begin
				// the header area; header words for a header command
				x_st <= x_st + 17'd1;
				x_t  <= x_t + 16'd1;
				if (!x_hdr) begin
					if (x_t == T_HDR - 1) begin
						x_t <= 16'd0;
						st  <= D_XDATA;
					end
				end else if (x_write) begin
					// header words from the adapter: not kept
					if (x_t >= T_WORD - 1 && !x_wreq) begin
						x_t     <= 16'd0;
						mb_sclk <= 1'b1;
						x_wreq  <= 1'b1;
					end
					if (x_wreq && mb_wclk) begin
						x_wreq <= 1'b0;
						x_w    <= x_w + 9'd1;
						if (x_w == 9'd3) begin
							x_w <= 9'd0; x_t <= 16'd0;
							st  <= D_XDATA;
						end
					end
				end else if (x_t == T_WORD - 1) begin
					x_t     <= 16'd0;
					mb_dr   <= hdr_w;
					mb_sclk <= 1'b1;
					x_w     <= x_w + 9'd1;
					if (x_w == 9'd3) begin
						x_w <= 9'd0;
						st  <= D_XDATA;
					end
				end
			end

			D_XDATA: begin
				x_st <= x_st + 17'd1;
				x_t  <= x_t + 16'd1;
				if (x_write) begin
					// ask for a word every word time, store it on WCLK
					if (x_t >= T_WORD - 1 && !x_wreq && x_ph == 2'd0) begin
						x_t     <= 16'd0;
						mb_sclk <= 1'b1;
						x_wreq  <= 1'b1;
					end
					if (x_wreq && mb_wclk) begin
						x_wreq <= 1'b0;
						x_word <= mb_dw;
						b_adr  <= {x_slot, x_w[7:0], 1'b0};
						b_din  <= mb_dw[7:0];
						b_we   <= 1'b1;
						x_ph   <= 2'd1;
					end else if (x_ph == 2'd1) begin
						b_adr <= {x_slot, x_w[7:0], 1'b1};
						b_din <= x_word[15:8];
						b_we  <= 1'b1;
						x_ph  <= 2'd0;
						x_w   <= x_w + 9'd1;
						if (x_w == 9'd255) begin
							x_t <= 16'd0;
							st  <= D_XECC;
						end
					end
				end else begin
					// read, write check: a word every word time
					case (x_ph)
					2'd0: if (x_t >= T_WORD - 4) begin
						b_adr <= {x_slot, x_w[7:0], 1'b0};
						x_ph  <= 2'd1;
					end
					2'd1: begin
						b_adr <= {x_slot, x_w[7:0], 1'b1};
						x_ph  <= 2'd2;
					end
					2'd2: begin
						x_word[7:0] <= b_q;
						x_ph <= 2'd3;
					end
					default: if (x_t >= T_WORD - 1) begin
						mb_dr   <= (x_slot ? sl_z1 : sl_z0) ? 16'd0
						           : {b_q, x_word[7:0]};
						mb_sclk <= 1'b1;
						x_t     <= 16'd0;
						x_ph    <= 2'd0;
						x_w     <= x_w + 9'd1;
						if (x_w == 9'd255)
							st <= D_XECC;
					end
					endcase
				end
			end

			D_XECC: begin
				// the ECC field and the end of the sector
				x_st <= x_st + 17'd1;
				x_t  <= x_t + 16'd1;
				if (x_t == T_ECC - 1) begin
					if (x_write) begin
						if (x_slot) sl_st1 <= (x_lba < nsect) ? SL_DIRTY : SL_EMPTY;
						else        sl_st0 <= (x_lba < nsect) ? SL_DIRTY : SL_EMPTY;
					end
					if (x_lba == LAST) begin
						lst <= 1'b1;        // the last sector is done
						if (mb_run) begin
							// RUN still asserted: AOE
							er1   <= er1 | 16'o001000;
							x_err <= 1'b1;
							x_exc <= 1'b1;
						end
					end
					x_done <= 1'b1;
					st <= D_XEBL;
				end
			end

			D_XEBL: if (x_write && (x_exc || !mb_run) &&
			            (sl_st0 == SL_DIRTY || sl_st0 == SL_WRING ||
			             sl_st1 == SL_DIRTY || sl_st1 == SL_WRING)) begin
				// the end of a write: its sectors on the card first, so
				// that a finished transfer is on the disk, as on the drive
			end else begin
				// end of block; RUN says whether to go on
				mb_ebl <= 1'b1;
				x_done <= 1'b0;
				if (x_done) begin
					// the address of the next sector
					if (da_sec == NSEC - 1) begin
						da_sec <= 7'd0;
						if (da_trk == NTRK - 1) begin
							da_trk <= 6'd0;
							dc     <= dc + 10'd1;
						end else
							da_trk <= da_trk + 6'd1;
					end else
						da_sec <= da_sec + 7'd1;
				end
				if (x_exc || !mb_run)
					xfer_end;
				else if (x_lba == LAST) begin
					// (RUN negated in the meantime: an ordinary end)
					xfer_end;
				end
				else begin
					x_lba <= n_lba;
					st    <= D_XNEXT;
				end
			end

			D_XNEXT: begin
				x_st <= x_st + 17'd1;
				if (dc != cc) begin
					// mid-transfer seek to the next cylinder
					pos_t   <= T_10US * 500;
					x_first <= 1'b1;
					st      <= D_XSEEK;
				end else
					st <= D_XSRCH;
			end

			default: ;
			endcase

			// the adapter's EXC ends the transfer at once (EK-RP056-MM-01
			// 3.12.1): EBL, and a sector being written is dropped
			if (x_occ && mb_exci && st != D_XEBL) begin
				mb_ebl <= 1'b1;
				if (x_write && sl_st0 == SL_FILL && !x_slot) sl_st0 <= SL_EMPTY;
				if (x_write && sl_st1 == SL_FILL &&  x_slot) sl_st1 <= SL_EMPTY;
				xfer_end;
			end

			/* --------------------------------- Massbus INIT */
			if (mb_init) begin
				er1 <= 16'd0; er2 <= 16'd0; er3 <= 16'd0;
				ata <= 1'b0; lst <= 1'b0;
				mr[15] <= 1'b0;
				if (st == D_POS || st == D_PSRCH)
					cc <= pos_cyl;
				if (st != D_UNLD) begin
					go <= 1'b0; pip <= 1'b0; st <= D_IDLE;
				end
				x_occ <= 1'b0; x_exc <= 1'b0; x_wreq <= 1'b0;
				if (sl_st0 == SL_FILL) sl_st0 <= SL_EMPTY;
				if (sl_st1 == SL_FILL) sl_st1 <= SL_EMPTY;
			end
		end

		/* ---------------------------------- the SD card side */
		if (!sd_busy) begin
			sd_stale <= 1'b0;
			if (sl_st0 == SL_DIRTY || sl_st1 == SL_DIRTY) begin
				sd_slot <= (sl_st0 == SL_DIRTY) ? 1'b0 : 1'b1;
				sd_lba  <= {12'd0, (sl_st0 == SL_DIRTY) ? sl_lba0 : sl_lba1};
				if (sl_st0 == SL_DIRTY) sl_st0 <= SL_WRING;
				else                    sl_st1 <= SL_WRING;
				sd_wr   <= 1'b1;
				sd_busy <= 1'b1;
			end else if (sl_st0 == SL_RDREQ) begin
				if (sl_z0)
					sl_st0 <= SL_VALID;     // beyond the image
				else begin
					sd_slot <= 1'b0;
					sd_lba  <= {12'd0, sl_lba0};
					sl_st0  <= SL_RDING;
					sd_rd   <= 1'b1;
					sd_busy <= 1'b1;
				end
			end else if (sl_st1 == SL_RDREQ) begin
				if (sl_z1)
					sl_st1 <= SL_VALID;
				else begin
					sd_slot <= 1'b1;
					sd_lba  <= {12'd0, sl_lba1};
					sl_st1  <= SL_RDING;
					sd_rd   <= 1'b1;
					sd_busy <= 1'b1;
				end
			end
		end else if (sd_ack) begin
			sd_rd <= 1'b0;
			sd_wr <= 1'b0;
		end else if (!sd_rd && !sd_wr) begin
			// the HPS is done with it
			sd_busy <= 1'b0;
			if (!sd_stale) begin
				if (sd_slot) sl_st1 <= SL_VALID;
				else         sl_st0 <= SL_VALID;
			end
		end
	end

	initial begin
		mol = 1'b0; wrl = 1'b0; nsect = 20'd0;
		rot_sec = 7'd0; rot_t = 16'd0;
		dem_q = 1'b0;
		sd_rd = 1'b0; sd_wr = 1'b0; sd_busy = 1'b0; sd_stale = 1'b0;
		sl_st0 = SL_EMPTY; sl_st1 = SL_EMPTY;
		sl_lba0 = 20'd0; sl_lba1 = 20'd0; sl_z0 = 1'b0; sl_z1 = 1'b0;
	end

endmodule

`default_nettype wire

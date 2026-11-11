//============================================================================
//  vax_cache.v - memory cache for the r-vax CPU, built from Cyclone V M10K
//  block RAM.
//
//  The module called "vcache" in r-vax is not a cache: it only splits the
//  CPU's unaligned byte/word accesses into aligned longword bus cycles. Every
//  instruction fetch therefore went to the SDRAM, which costs about 14 clocks.
//  This block sits between that aligner and the SDRAM and turns most of those
//  into one or two clocks.
//
//  Organisation (defaults): 16 KB, direct mapped, 16-byte lines (4 longwords),
//  physically indexed and tagged - the CPU has no MMU, so there is no aliasing.
//
//      longword address LA[22:0] = { tag[10:0], index[9:0], offset[1:0] }
//
//  Policy: write through, no write allocate, with a one-entry posted write
//  buffer so a write costs the CPU two clocks instead of fourteen. A write
//  carries a byte mask (SEL_I): only those bytes are written, in the SDRAM
//  (its DQM lines) and in the cached line if it hits. A line fill is held
//  back while the write buffer is still draining, so a read can never pass
//  an older write to the same address.
//
//  Tag RAM: 2^IDXB x (TAGB+1)      Data RAM: 2^(IDXB+2) x 32, as four
//  byte lanes of 2^(IDXB+2) x 8, each with its own write enable: that is
//  how the byte mask reaches the RAM. (Quartus does not infer byte enables
//  from part-selects of one memory word: with a single 32-bit array it
//  built the 16 KB out of registers.) All inferred as M10K (ramstyle
//  attributes below). Valid bits are cleared
//  by walking the tag RAM after reset, which also covers the case where the
//  HPS loader has written to memory behind the cache's back.
//
//  Bus: the simple strobe/ack protocol of r-vax. The master holds STB_I with
//  a stable address until ACK_O, and drops STB_I for at least a clock before
//  its next reference. ACK_O and DAT_O come straight from registers: ACK_O
//  stays up until the clock after STB_I goes away, so the MBox (vax_io.v)
//  qualifies them with the strobe of the reference on its port. That keeps
//  the MBox's PAMM decision, which drives STB_I, out of the answer's path.
//
//  The RAMs are read a clock ahead. The MBox latches the CPU's reference
//  before it puts it on this port, and gives the address the latch is about
//  to take on PRE_I (its bits <21:0>: the index and the offset are all the
//  RAMs need). When the reference arrives the tag and the data of its line
//  are already there (fresh), so a hit is answered in the reference's first
//  clock here; a reference whose address was not announced (DMA) waits a
//  clock for them, as every reference did before.
//
//  DIS_I turns the cache off, for finding a fault on a board: taken at
//  reset, it makes every read a miss (a line fill from the SDRAM), so the
//  contents of the cache's RAMs are never used. The machine runs several
//  times slower and must behave the same.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_cache #(
	parameter IDXB = 10,            // log2 of the number of lines
	parameter AB   = 23             // longword address bits (23 = 32 MB)
) (
	input             clk,
	input             rst,

	// CPU side
	input             STB_I,
	input      [31:0] ADR_I,
	input      [21:0] PRE_I,        // ADR_I<21:0> a clock early (see above)
	input             DIS_I,        // cache off (taken at reset)
	input      [31:0] DAT_I,
	input       [3:0] SEL_I,        // byte mask of a write
	input             WE_I,
	output     [31:0] DAT_O,
	output            ACK_O,

	// SDRAM side
	output            req,
	output            req_we,
	output     [AB-1:0] req_adr,
	output     [31:0] req_dat,
	output      [3:0] req_sel,
	input             req_done,
	input      [31:0] rd_dat,
	input       [1:0] rd_idx,
	input             rd_stb,

	output reg        stat_hit,     // one clock pulse per hit
	output reg        stat_miss     // one clock pulse per miss
);

	localparam TAGB = AB - IDXB - 2;

	// ---------------------------------------------------------------- RAMs
	(* ramstyle = "M10K" *) reg [TAGB:0]  tag_ram [0:(1<<IDXB)-1];
	(* ramstyle = "M10K" *) reg [7:0]     dat_ram0 [0:(1<<(IDXB+2))-1];
	(* ramstyle = "M10K" *) reg [7:0]     dat_ram1 [0:(1<<(IDXB+2))-1];
	(* ramstyle = "M10K" *) reg [7:0]     dat_ram2 [0:(1<<(IDXB+2))-1];
	(* ramstyle = "M10K" *) reg [7:0]     dat_ram3 [0:(1<<(IDXB+2))-1];

	reg [TAGB:0]      tag_q;
	reg [7:0]         dat_q0, dat_q1, dat_q2, dat_q3;
	wire [31:0]       dat_q = {dat_q3, dat_q2, dat_q1, dat_q0};
	reg [IDXB+1:0]    ix_q;         // the index and offset they were read at

	reg               tw;
	reg [IDXB-1:0]    tw_adr;
	reg [TAGB:0]      tw_dat;
	reg               dw;
	reg [IDXB+1:0]    dw_adr;
	reg [31:0]        dw_dat;
	reg  [3:0]        dw_be;

	wire [AB-1:0]     la    = ADR_I[AB+1:2];
	wire [TAGB-1:0]   tag   = la[AB-1:IDXB+2];
	// the RAMs' read address: the reference on its way to the port
	wire [IDXB+1:0]   pix   = PRE_I[IDXB+3:2];

	always @(posedge clk) begin
		if (tw) tag_ram[tw_adr] <= tw_dat;
		tag_q <= tag_ram[pix[IDXB+1:2]];
		ix_q  <= pix;
	end

	// one simple dual-port RAM per byte lane
	always @(posedge clk) begin
		if (dw && dw_be[0]) dat_ram0[dw_adr] <= dw_dat[7:0];
		dat_q0 <= dat_ram0[pix];
	end
	always @(posedge clk) begin
		if (dw && dw_be[1]) dat_ram1[dw_adr] <= dw_dat[15:8];
		dat_q1 <= dat_ram1[pix];
	end
	always @(posedge clk) begin
		if (dw && dw_be[2]) dat_ram2[dw_adr] <= dw_dat[23:16];
		dat_q2 <= dat_ram2[pix];
	end
	always @(posedge clk) begin
		if (dw && dw_be[3]) dat_ram3[dw_adr] <= dw_dat[31:24];
		dat_q3 <= dat_ram3[pix];
	end

	// Cyclone V M10K gives "don't care" for a mixed-port read-during-write,
	// where plain Verilog semantics would give the old contents. Bypass the
	// write explicitly so simulation and silicon agree.
	reg        tw_q, dw_q;
	reg [TAGB:0] tw_dat_q;
	reg [31:0]   dw_dat_q;
	reg  [3:0]   dw_be_q;
	reg [IDXB-1:0]  tw_adr_q;
	reg [IDXB+1:0]  dw_adr_q;
	always @(posedge clk) begin
		tw_q <= tw; tw_adr_q <= tw_adr; tw_dat_q <= tw_dat;
		dw_q <= dw; dw_adr_q <= dw_adr; dw_dat_q <= dw_dat; dw_be_q <= dw_be;
	end

	wire [TAGB:0] tag_eff = (tw_q && tw_adr_q == ix_q[IDXB+1:2]) ? tw_dat_q : tag_q;
	wire          dw_byp  = dw_q && dw_adr_q == ix_q;
	wire [31:0]   dat_eff = {
		(dw_byp && dw_be_q[3]) ? dw_dat_q[31:24] : dat_q[31:24],
		(dw_byp && dw_be_q[2]) ? dw_dat_q[23:16] : dat_q[23:16],
		(dw_byp && dw_be_q[1]) ? dw_dat_q[15:8]  : dat_q[15:8],
		(dw_byp && dw_be_q[0]) ? dw_dat_q[7:0]   : dat_q[7:0] };

	// tag_q/dat_q belong to the reference on the port if they were read at
	// its index and offset
	wire fresh = (ix_q == la[IDXB+1:0]);
	// DIS_I, taken at reset (the lines filled while the cache is off do not
	// see the writes, and the reset invalidates them all): never a hit
	reg  off;
	initial off = 1'b0;
	always @(posedge clk)
		if (rst)
			off <= DIS_I;
`ifdef CACHE_NOHIT
	// measurement build only: never hit, so every read becomes a line fill.
	// Used to quantify what the cache is worth; not for synthesis.
	wire hit   = 1'b0;
`else
	wire hit   = fresh && !off && tag_eff[TAGB] && (tag_eff[TAGB-1:0] == tag);
`endif

	// ---------------------------------------------------------- write buffer
	reg            wb_v;
	reg [AB-1:0]   wb_a;
	reg [31:0]     wb_d;
	reg  [3:0]     wb_s;

	// ------------------------------------------------------------- main FSM
	localparam [2:0] S_CLR  = 3'd0,
	                 S_IDLE = 3'd1,
	                 S_FILL = 3'd2,
	                 S_ACK  = 3'd3;

	reg  [2:0]      state;
	reg  [IDXB:0]   clr;
	reg  [AB-1:0]   fill_la;
	reg             fill_rq;
	reg  [31:0]     dout;
	reg             ack;

	assign DAT_O = dout;
	assign ACK_O = ack;

	// the two users of the SDRAM port never overlap: a fill is only started
	// when the write buffer is empty, and the CPU is stalled during a fill
	assign req     = fill_rq | wb_v;
	assign req_we  = wb_v & ~fill_rq;
	assign req_adr = fill_rq ? {fill_la[AB-1:2], 2'b00} : wb_a;
	assign req_dat = wb_d;
	assign req_sel = fill_rq ? 4'b1111 : wb_s;

	initial begin
		state    = S_CLR;
		clr      = 0;
		wb_v     = 1'b0;
		fill_rq  = 1'b0;
		ack      = 1'b0;
		tw       = 1'b0;
		dw       = 1'b0;
		dw_be    = 4'b1111;
		wb_s     = 4'b1111;
		stat_hit = 1'b0;
		stat_miss= 1'b0;
	end

	always @(posedge clk) begin
		tw        <= 1'b0;
		dw        <= 1'b0;
		stat_hit  <= 1'b0;
		stat_miss <= 1'b0;

		// drain the posted write
		if (wb_v && !fill_rq && req_done)
			wb_v <= 1'b0;

		if (rst) begin
			state   <= S_CLR;
			clr     <= 0;
			wb_v    <= 1'b0;
			fill_rq <= 1'b0;
			ack     <= 1'b0;
		end else begin
			case (state)
			S_CLR: begin                       // invalidate every line
				tw     <= 1'b1;
				tw_adr <= clr[IDXB-1:0];
				tw_dat <= {(TAGB+1){1'b0}};
				clr    <= clr + 1'b1;
				if (clr[IDXB]) begin
					clr   <= 0;
					state <= S_IDLE;
				end
			end

			S_IDLE: if (STB_I && fresh) begin
				if (WE_I) begin
					if (!wb_v) begin           // post the write, ack at once
						wb_v <= 1'b1;
						wb_a <= la;
						wb_d <= DAT_I;
						wb_s <= SEL_I;
						if (hit) begin         // keep the cached copy current
							dw     <= 1'b1;
							dw_adr <= la[IDXB+1:0];
							dw_dat <= DAT_I;
							dw_be  <= SEL_I;
						end
						ack   <= 1'b1;
						state <= S_ACK;
					end
				end else if (hit) begin
					dout      <= dat_eff;
					ack       <= 1'b1;
					stat_hit  <= 1'b1;
					state     <= S_ACK;
				end else if (!wb_v) begin      // miss: fill, writes drained
					fill_la   <= la;
					fill_rq   <= 1'b1;
					stat_miss <= 1'b1;
					state     <= S_FILL;
				end
			end

			S_FILL: begin
				if (rd_stb) begin
					dw     <= 1'b1;
					dw_adr <= {fill_la[IDXB+1:2], rd_idx};
					dw_dat <= rd_dat;
					dw_be  <= 4'b1111;
					if (rd_idx == fill_la[1:0])
						dout <= rd_dat;        // the longword the CPU asked for
				end
				if (req_done) begin
					fill_rq <= 1'b0;
					tw      <= 1'b1;
					tw_adr  <= fill_la[IDXB+1:2];
					tw_dat  <= {1'b1, fill_la[AB-1:IDXB+2]};
					ack     <= 1'b1;
					state   <= S_ACK;
				end
			end

			S_ACK: if (!STB_I) begin
				ack   <= 1'b0;
				state <= S_IDLE;
			end

			default: state <= S_IDLE;
			endcase
		end
	end

endmodule

`default_nettype wire

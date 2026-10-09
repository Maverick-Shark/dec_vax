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
//  that hits also updates the cached line. A line fill is held back while the
//  write buffer is still draining, so a read can never pass an older write to
//  the same address.
//
//  Tag RAM: 2^IDXB x (TAGB+1)      Data RAM: 2^(IDXB+2) x 32
//  Both inferred as M10K (ramstyle attribute below). Valid bits are cleared
//  by walking the tag RAM after reset, which also covers the case where the
//  HPS loader has written to memory behind the cache's back.
//
//  Bus: the simple strobe/ack protocol of r-vax. The master holds STB_I with
//  a stable address until ACK_O; DAT_O and ACK_O read as zero while STB_I is
//  low because the r-vax bus ORs its slaves together.
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
	input      [31:0] DAT_I,
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
	(* ramstyle = "M10K" *) reg [31:0]    dat_ram [0:(1<<(IDXB+2))-1];

	reg [TAGB:0]      tag_q;
	reg [31:0]        dat_q;
	reg [AB-1:0]      la_q;

	reg               tw;
	reg [IDXB-1:0]    tw_adr;
	reg [TAGB:0]      tw_dat;
	reg               dw;
	reg [IDXB+1:0]    dw_adr;
	reg [31:0]        dw_dat;

	wire [AB-1:0]     la    = ADR_I[AB+1:2];
	wire [IDXB-1:0]   idx   = la[IDXB+1:2];
	wire [TAGB-1:0]   tag   = la[AB-1:IDXB+2];

	always @(posedge clk) begin
		if (tw) tag_ram[tw_adr] <= tw_dat;
		tag_q <= tag_ram[idx];
		if (dw) dat_ram[dw_adr] <= dw_dat;
		dat_q <= dat_ram[la[IDXB+1:0]];
		la_q  <= la;
	end

	// Cyclone V M10K gives "don't care" for a mixed-port read-during-write,
	// where plain Verilog semantics would give the old contents. Bypass the
	// write explicitly so simulation and silicon agree.
	reg        tw_q, dw_q;
	reg [TAGB:0] tw_dat_q;
	reg [31:0]   dw_dat_q;
	reg [IDXB-1:0]  tw_adr_q;
	reg [IDXB+1:0]  dw_adr_q;
	always @(posedge clk) begin
		tw_q <= tw; tw_adr_q <= tw_adr; tw_dat_q <= tw_dat;
		dw_q <= dw; dw_adr_q <= dw_adr; dw_dat_q <= dw_dat;
	end

	wire [TAGB:0] tag_eff = (tw_q && tw_adr_q == la_q[IDXB+1:2]) ? tw_dat_q : tag_q;
	wire [31:0]   dat_eff = (dw_q && dw_adr_q == la_q[IDXB+1:0]) ? dw_dat_q : dat_q;

	// tag_q/dat_q belong to the current address only if it has been stable
	wire fresh = (la_q == la);
`ifdef CACHE_NOHIT
	// measurement build only: never hit, so every read becomes a line fill.
	// Used to quantify what the cache is worth; not for synthesis.
	wire hit   = 1'b0;
`else
	wire hit   = fresh && tag_eff[TAGB] && (tag_eff[TAGB-1:0] == tag);
`endif

	// ---------------------------------------------------------- write buffer
	reg            wb_v;
	reg [AB-1:0]   wb_a;
	reg [31:0]     wb_d;

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

	assign DAT_O = (STB_I && ack) ? dout : 32'd0;
	assign ACK_O = STB_I && ack;

	// the two users of the SDRAM port never overlap: a fill is only started
	// when the write buffer is empty, and the CPU is stalled during a fill
	assign req     = fill_rq | wb_v;
	assign req_we  = wb_v & ~fill_rq;
	assign req_adr = fill_rq ? {fill_la[AB-1:2], 2'b00} : wb_a;
	assign req_dat = wb_d;
	assign req_sel = 4'b1111;

	initial begin
		state    = S_CLR;
		clr      = 0;
		wb_v     = 1'b0;
		fill_rq  = 1'b0;
		ack      = 1'b0;
		tw       = 1'b0;
		dw       = 1'b0;
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
						if (hit) begin         // keep the cached copy current
							dw     <= 1'b1;
							dw_adr <= la[IDXB+1:0];
							dw_dat <= DAT_I;
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

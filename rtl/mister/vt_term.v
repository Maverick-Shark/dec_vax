//============================================================================
//  vt_term.v - on-screen text terminal (subset of a VT100) for the VAX console.
//
//  Screen: 80 x 30 characters, 8x16 font, 640x480 @ 59.5 Hz (25 MHz pixel
//  clock from the 50 MHz system clock), 3 phosphor colours.
//
//  Supported: printable ASCII and Latin-1, CR, LF/VT/FF, BS, TAB, BEL,
//  SO/SI, autowrap (VT100 style), scrolling,
//  ESC [ n A/B/C/D, ESC [ r;c H/f, ESC [ n J, ESC [ n K, ESC [ n;n m (bold,
//  reverse), ESC D/E/M/7/8/c, ESC ( 0 / ESC ( B (DEC Special Graphics),
//  CSI also as 8-bit 9Bh.  Not yet: scrolling regions (ESC [ t;b r),
//  insert/delete line/char, answerback (ESC [ c, ESC [ 6 n).
//
//  Text RAM: 32 rows x 128 columns x 10 bits {bold, reverse, glyph}; rows are
//  used as a ring (top = first visible row) so scrolling is a pointer change
//  plus clearing one line.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vt_term (
	input            clk,          // 50 MHz
	input            rst,          // clears the screen, homes the cursor
	input      [7:0] rx_data,
	input            rx_valid,
	input      [1:0] color,        // 0 green, 1 amber, 2/3 white
	output           rx_ready,     // input FIFO has room (and reset is over)
	output reg       bell,         // one clock pulse per BEL

	output           ce_pix,
	output reg       hs,
	output reg       vs,
	output reg       hblank,
	output reg       vblank,
	output reg [7:0] r,
	output reg [7:0] g,
	output reg [7:0] b
);

	localparam [4:0] LAST_ROW = 5'd29;
	localparam [6:0] LAST_COL = 7'd79;

	// ------------------------------------------------------------ input FIFO
	// The CPU's characters arrive every 3.4 us with no way to hold them
	// back, while a full-screen clear keeps the terminal busy for 2400
	// clocks (14 characters' time). 64 entries cover several of those in a
	// row; 16 covered exactly one.
	reg  [7:0] fifo [0:63];
	reg  [5:0] wp, rp;
	wire       empty = (wp == rp);
	wire [7:0] ch    = fifo[rp];

	initial begin
		wp = 6'd0;
		rp = 6'd0;
	end

	// room for at least four more characters, and the screen clear is done
	assign rx_ready = !f_act && ((wp + 6'd4) != rp) && ((wp + 6'd3) != rp)
	                          && ((wp + 6'd2) != rp) && ((wp + 6'd1) != rp);

	always @(posedge clk)
		if (rst)
			wp <= 6'd0;
		else if (rx_valid && (wp + 6'd1 != rp)) begin
			fifo[wp] <= rx_data;
			wp <= wp + 6'd1;
		end

	// ------------------------------------------------------------ text RAM
	reg  [9:0]  tram [0:4095];
	reg         twe;
	reg  [11:0] twaddr;
	reg  [9:0]  twdata;
	reg  [11:0] traddr;
	reg  [9:0]  tq;

	always @(posedge clk) begin
		if (twe)
			tram[twaddr] <= twdata;
		tq <= tram[traddr];
	end

	// ------------------------------------------------------------ terminal state
	localparam [2:0] E_NORM = 3'd0, E_ESC = 3'd1, E_CSI = 3'd2,
	                 E_SCS0 = 3'd3, E_SCS1 = 3'd4, E_SKIP = 3'd5;

	reg  [2:0] esc;
	reg  [4:0] cur_r, sv_r;
	reg  [6:0] cur_c, sv_c;
	reg        wrap;
	reg  [4:0] top;
	reg        a_bold, a_rev, sv_bold, sv_rev;
	reg        g0_gfx, g1_gfx, so;
	reg        sv_g0, sv_g1, sv_so;
	reg  [7:0] p0, p1;
	reg  [1:0] pidx;

	reg        f_act;
	reg  [4:0] f_r, f_er;
	reg  [6:0] f_c, f_ec;

	initial begin
		esc = E_NORM;
		cur_r = 5'd0; cur_c = 7'd0; wrap = 1'b0; top = 5'd0;
		a_bold = 1'b0; a_rev = 1'b0; g0_gfx = 1'b0; g1_gfx = 1'b0; so = 1'b0;
		f_act = 1'b0; twe = 1'b0; bell = 1'b0;
	end

	wire       gfx       = so ? g1_gfx : g0_gfx;
	wire       printable = (ch >= 8'h20 && ch <= 8'h7E) || (ch >= 8'hA0);
	wire [7:0] glyph     = (gfx && ch >= 8'h5F && ch <= 8'h7E) ? (ch - 8'h5F) : ch;
	wire [7:0] n0        = (p0 == 8'd0) ? 8'd1 : p0;
	wire [7:0] n1        = (p1 == 8'd0) ? 8'd1 : p1;

	// one SGR parameter applied to (bold, rev)
	function [1:0] sgr;
		input [7:0] p;
		input [1:0] br;
		begin
			case (p)
			8'd0:    sgr = 2'b00;
			8'd1:    sgr = {1'b1, br[0]};
			8'd22:   sgr = {1'b0, br[0]};
			8'd7:    sgr = {br[1], 1'b1};
			8'd27:   sgr = {br[1], 1'b0};
			default: sgr = br;
			endcase
		end
	endfunction

	wire [1:0] sgr_a = sgr(p0, {a_bold, a_rev});
	wire [1:0] sgr_b = (pidx != 2'd0) ? sgr(p1, sgr_a) : sgr_a;

	task fill;                       // clear (r0,c0)..(r1,c1), row-major
		input [4:0] r0;
		input [6:0] c0;
		input [4:0] r1;
		input [6:0] c1;
		begin
			f_act <= 1'b1;
			f_r <= r0; f_c <= c0; f_er <= r1; f_ec <= c1;
		end
	endtask

	task lf;                         // index: cursor down, scroll at the bottom
		begin
			wrap <= 1'b0;
			if (cur_r == LAST_ROW) begin
				top <= top + 5'd1;
				fill(LAST_ROW, 7'd0, LAST_ROW, LAST_COL);
			end else
				cur_r <= cur_r + 5'd1;
		end
	endtask

	task ri;                         // reverse index: cursor up, scroll down at the top
		begin
			wrap <= 1'b0;
			if (cur_r == 5'd0) begin
				top <= top - 5'd1;
				fill(5'd0, 7'd0, 5'd0, LAST_COL);
			end else
				cur_r <= cur_r - 5'd1;
		end
	endtask

	always @(posedge clk) begin : term
		reg pop;
		reg [8:0] t;

		twe  <= 1'b0;
		bell <= 1'b0;
		pop  = 1'b0;

		if (rst) begin
			rp <= 6'd0;
			esc <= E_NORM;
			cur_r <= 5'd0; cur_c <= 7'd0; wrap <= 1'b0; top <= 5'd0;
			a_bold <= 1'b0; a_rev <= 1'b0; g0_gfx <= 1'b0; g1_gfx <= 1'b0; so <= 1'b0;
			sv_r <= 5'd0; sv_c <= 7'd0; sv_bold <= 1'b0; sv_rev <= 1'b0;
			sv_g0 <= 1'b0; sv_g1 <= 1'b0; sv_so <= 1'b0;
			fill(5'd0, 7'd0, LAST_ROW, LAST_COL);
		end else if (f_act) begin
			twe    <= 1'b1;
			twaddr <= {top + f_r, f_c};
			twdata <= {2'b00, 8'h20};
			if (f_r == f_er && f_c == f_ec)
				f_act <= 1'b0;
			else if (f_c == LAST_COL) begin
				f_c <= 7'd0;
				f_r <= f_r + 5'd1;
			end else
				f_c <= f_c + 7'd1;
		end else if (!empty) begin
			pop = 1'b1;
			case (esc)
			E_NORM:
				if (printable) begin
					if (wrap) begin
						pop = 1'b0;               // wrap first, print on the next pass
						cur_c <= 7'd0;
						lf;
					end else begin
						twe    <= 1'b1;
						twaddr <= {top + cur_r, cur_c};
						twdata <= {a_bold, a_rev, glyph};
						if (cur_c == LAST_COL)
							wrap <= 1'b1;
						else
							cur_c <= cur_c + 7'd1;
					end
				end else begin
					case (ch)
					8'h07: bell <= 1'b1;
					8'h08: begin
						if (cur_c != 7'd0) cur_c <= cur_c - 7'd1;
						wrap <= 1'b0;
					end
					8'h09: begin
						cur_c <= (cur_c >= 7'd72) ? LAST_COL : ((cur_c | 7'd7) + 7'd1);
						wrap  <= 1'b0;
					end
					8'h0A, 8'h0B, 8'h0C: lf;
					8'h0D: begin cur_c <= 7'd0; wrap <= 1'b0; end
					8'h0E: so <= 1'b1;
					8'h0F: so <= 1'b0;
					8'h1B: esc <= E_ESC;
					8'h9B: begin esc <= E_CSI; p0 <= 8'd0; p1 <= 8'd0; pidx <= 2'd0; end
					default: ;
					endcase
				end

			E_ESC: begin
				esc <= E_NORM;
				case (ch)
				"[": begin esc <= E_CSI; p0 <= 8'd0; p1 <= 8'd0; pidx <= 2'd0; end
				"(": esc <= E_SCS0;
				")": esc <= E_SCS1;
				"#": esc <= E_SKIP;
				"D": lf;
				"E": begin cur_c <= 7'd0; lf; end
				"M": ri;
				"7": begin                         // DECSC: cursor, rendition, charsets
					sv_r <= cur_r; sv_c <= cur_c; sv_bold <= a_bold; sv_rev <= a_rev;
					sv_g0 <= g0_gfx; sv_g1 <= g1_gfx; sv_so <= so;
				end
				"8": begin                         // DECRC
					cur_r <= sv_r; cur_c <= sv_c; a_bold <= sv_bold; a_rev <= sv_rev;
					g0_gfx <= sv_g0; g1_gfx <= sv_g1; so <= sv_so; wrap <= 1'b0;
				end
				"c": begin
					cur_r <= 5'd0; cur_c <= 7'd0; wrap <= 1'b0;
					a_bold <= 1'b0; a_rev <= 1'b0; g0_gfx <= 1'b0; g1_gfx <= 1'b0; so <= 1'b0;
					fill(5'd0, 7'd0, LAST_ROW, LAST_COL);
				end
				8'h1B: esc <= E_ESC;
				default: ;
				endcase
			end

			E_SCS0: begin g0_gfx <= (ch == "0"); esc <= E_NORM; end
			E_SCS1: begin g1_gfx <= (ch == "0"); esc <= E_NORM; end
			E_SKIP: esc <= E_NORM;

			E_CSI: begin
				if (ch >= "0" && ch <= "9") begin
					if (pidx == 2'd0) begin
						t = p0 * 4'd10 + (ch - "0");
						p0 <= (p0 > 8'd25) ? 8'd255 : (t[8] ? 8'd255 : t[7:0]);
					end else if (pidx == 2'd1) begin
						t = p1 * 4'd10 + (ch - "0");
						p1 <= (p1 > 8'd25) ? 8'd255 : (t[8] ? 8'd255 : t[7:0]);
					end
				end else if (ch == ";") begin
					if (pidx != 2'd3) pidx <= pidx + 2'd1;
				end else if (ch == 8'h18 || ch == 8'h1A) begin
					esc <= E_NORM;                     // CAN / SUB abort
				end else if (ch == 8'h1B) begin
					esc <= E_ESC;
				end else if (ch >= 8'h40 && ch <= 8'h7E) begin
					esc <= E_NORM;
					case (ch)
					"A": begin cur_r <= ({3'd0, cur_r} < n0) ? 5'd0 : cur_r - n0[4:0]; wrap <= 1'b0; end
					"B": begin
						t = {4'd0, cur_r} + {1'b0, n0};
						cur_r <= (t > 9'd29) ? LAST_ROW : t[4:0];
						wrap <= 1'b0;
					end
					"C": begin
						t = {2'd0, cur_c} + {1'b0, n0};
						cur_c <= (t > 9'd79) ? LAST_COL : t[6:0];
						wrap <= 1'b0;
					end
					"D": begin cur_c <= ({1'b0, cur_c} < n0) ? 7'd0 : cur_c - n0[6:0]; wrap <= 1'b0; end
					"H", "f": begin
						cur_r <= (n0 > 8'd30) ? LAST_ROW : (n0[4:0] - 5'd1);
						cur_c <= (n1 > 8'd80) ? LAST_COL : (n1[6:0] - 7'd1);
						wrap  <= 1'b0;
					end
					"J": case (p0)
						8'd0: fill(cur_r, cur_c, LAST_ROW, LAST_COL);
						8'd1: fill(5'd0, 7'd0, cur_r, cur_c);
						8'd2: fill(5'd0, 7'd0, LAST_ROW, LAST_COL);
						default: ;
						endcase
					"K": case (p0)
						8'd0: fill(cur_r, cur_c, cur_r, LAST_COL);
						8'd1: fill(cur_r, 7'd0, cur_r, cur_c);
						8'd2: fill(cur_r, 7'd0, cur_r, LAST_COL);
						default: ;
						endcase
					"m": {a_bold, a_rev} <= sgr_b;
					default: ;                         // ignored (modes, regions, reports)
					endcase
				end
				// '?', '>' and intermediates are ignored
			end

			default: esc <= E_NORM;
			endcase

			if (pop)
				rp <= rp + 6'd1;
		end
	end

	// ------------------------------------------------------------ video
	// 800 x 525 total, active hc 8..647 (one character of prefetch at hc 0..7)
	reg        ce;
	reg  [9:0] hc, vc;
	reg  [5:0] frame;

	initial begin
		ce = 1'b0; hc = 10'd0; vc = 10'd0; frame = 6'd0;
	end

	assign ce_pix = ce;

	always @(posedge clk)
		ce <= ~ce;

	wire [4:0] trow = vc[8:4];
	wire [3:0] line = vc[3:0];
	wire       vact = (vc < 10'd480);

	reg  [1:0] attr_d;
	reg        cur_p0, cur_p1, cur_p2;
	wire [7:0] font_q;

	vt_font font (
		.clk  (clk),
		.addr ({tq[7:0], line}),
		.q    (font_q)
	);

	reg  [7:0] glyph_next, shreg;
	reg  [1:0] attr_next, attr_cur;
	reg        cur_next, cur_cell;

	always @(posedge clk) begin
		attr_d <= tq[9:8];
		cur_p1 <= cur_p0;
		cur_p2 <= cur_p1;

		if (ce) begin
			if (hc == 10'd799) begin
				hc <= 10'd0;
				if (vc == 10'd524)
					vc <= 10'd0;
				else
					vc <= vc + 10'd1;
				if (vc == 10'd479)
					frame <= frame + 6'd1;
			end else
				hc <= hc + 10'd1;

			// fetch the character of the cell that starts 8 pixels later
			if (hc[2:0] == 3'd0 && hc < 10'd640) begin
				traddr <= {top + trow, hc[9:3]};
				cur_p0 <= vact && (trow == cur_r) && (hc[9:3] == cur_c) && frame[4];
			end

			if (hc[2:0] == 3'd2) begin
				glyph_next <= font_q;
				attr_next  <= attr_d;
				cur_next   <= cur_p2;
			end

			// pixel output (registered)
			begin : pix
				reg de, px;
				de = vact && (hc >= 10'd8) && (hc < 10'd648);
				px = shreg[7] ^ attr_cur[0] ^ cur_cell;
				hblank <= ~((hc >= 10'd8) && (hc < 10'd648));
				vblank <= ~vact;
				hs     <= ~((hc >= 10'd664) && (hc < 10'd760));
				vs     <= ~((vc >= 10'd490) && (vc < 10'd492));
				if (de && px) begin
					case ({color, attr_cur[1]})
					3'b00_0: {r, g, b} <= 24'h20D040;
					3'b00_1: {r, g, b} <= 24'h90FFA0;
					3'b01_0: {r, g, b} <= 24'hE09000;
					3'b01_1: {r, g, b} <= 24'hFFC840;
					3'b10_0, 3'b11_0: {r, g, b} <= 24'hB8B8B8;
					default:          {r, g, b} <= 24'hFFFFFF;
					endcase
				end else
					{r, g, b} <= 24'h000000;
			end

			if (hc[2:0] == 3'd7) begin
				shreg    <= glyph_next;
				attr_cur <= attr_next;
				cur_cell <= cur_next;
			end else
				shreg <= {shreg[6:0], 1'b0};
		end
	end

endmodule

`default_nettype wire

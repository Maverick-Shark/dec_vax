//============================================================================
//  vax_selftest.v - power-on SDRAM test, read-phase calibration and banner.
//
//  Runs while the CPU is held in reset and owns the SDRAM through the core's
//  second bus master port. It writes a unique pattern to every longword of a
//  64 KB block, plus to one longword on each of the nine top address bits so
//  that a stuck or swapped high address line is caught too, then reads
//  everything back and compares.
//
//  Pattern: data = longword address XOR A5A5A5A5h, so a read that lands on the
//  wrong address, a bit stuck in the data path, or a read captured on the wrong
//  clock edge all show up, and the report says which.
//
//  The read-back is repeated at all four settings of the controller's read
//  capture phase and the results are printed as a four-character map. The
//  first setting that reads the memory back correctly becomes the one the
//  core uses, so the board calibrates itself instead of relying on a margin
//  calculation. Writing is done once, before the sweep: only the read path
//  depends on the phase.
//
//  Finally everything the test wrote is set back to zero - and the first
//  64 KB are cleared even when the test itself is switched off. A fresh
//  simulator starts with zeroed memory, and DEC's stand-alone diagnostics
//  rely on that: EVKAA, for one, looks at the longword at FE00h, just past
//  its image, and if bit 31 is set it assumes the Diagnostic Supervisor
//  started it - it prints "DS>" instead of its banner, loops for ever and
//  then waits for supervisor commands that never come. The test pattern at
//  FE00h (A5A59A25h) has bit 31 set, so without this clear EVKAA always
//  started that way after the power-on test.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_selftest #(
	parameter BLOCKLW = 16384,      // longwords tested exhaustively (64 KB)
	parameter WALK_LO = 14,         // address-walk covers bits WALK_LO..22
	parameter WALK_HI = 22
) (
	input             clk,
	input             rst,
	input             start,        // one clock pulse
	input             enable,       // 0: print the banner, skip the test
	input      [15:0] sdram_sz,     // from hps_io, bit 15 set once reported

	output reg        busy,
	output reg        fail,
	output reg  [1:0] phase,        // read phase the controller must use now
	output reg  [1:0] best_phase,   // read phase chosen by the sweep

	// SDRAM master port
	output reg        req,
	output reg        req_we,
	output reg [22:0] req_adr,
	output reg [31:0] req_dat,
	output      [3:0] req_sel,
	input             req_done,
	input      [31:0] rd_dat,
	input       [1:0] rd_idx,
	input             rd_stb,

	// console terminal
	output reg  [7:0] tx_data,
	output reg        tx_stb,
	input             tx_ready
);

	assign req_sel = 4'b1111;

	localparam [4:0] WLO = WALK_LO;
	localparam [4:0] WHI = WALK_HI;

	function [31:0] pattern;
		input [22:0] la;
		pattern = {9'd0, la} ^ 32'hA5A5A5A5;
	endfunction

	// ------------------------------------------------------------- test FSM
	localparam [3:0] T_IDLE = 4'd0,
	                 T_WB   = 4'd1,   // write block
	                 T_WW   = 4'd2,   // write address walk
	                 T_RB   = 4'd3,   // read block at the current phase
	                 T_RW   = 4'd4,   // read address walk at the current phase
	                 T_NEXT = 4'd5,   // record this phase, set up the next
	                 T_PR   = 4'd6,   // print
	                 T_DONE = 4'd7,
	                 T_CB   = 4'd8,   // clear the block
	                 T_CW   = 4'd9;   // clear the address walk

	reg  [3:0]  tst;
	reg [22:0]  la;
	reg  [4:0]  wk;
	reg         pfail;              // failure at the phase being tried
	reg  [3:0]  ok;                 // one bit per phase
	reg         any_ok;
	reg         det;                // the failure detail has been captured
	reg [31:0]  e_got, e_exp;
	reg [22:0]  e_adr;
	reg         start_q;            // sticky, so one OSD pulse is enough

	wire [22:0] walk_la = 23'd1 << wk;

	// phase result word printed as eight hex digits:
	//   d3 = chosen phase, d4..d7 = result of phase 0..3
	wire [31:0] e_phase = {12'd0, 1'b0, 1'b0, best_phase,
	                       3'd0, ok[0], 3'd0, ok[1], 3'd0, ok[2], 3'd0, ok[3]};

	// ---------------------------------------------------------- print FSM
	localparam [2:0] P_IDLE = 3'd0,
	                 P_FETCH= 3'd1,
	                 P_WAIT = 3'd2,
	                 P_EMIT = 3'd3;

	reg  [2:0]  pst;
	reg  [3:0]  msg;
	reg  [5:0]  pidx;
	reg  [7:0]  pace;
	wire [7:0]  mq;

	vax_msg msgrom (.clk(clk), .addr({msg, pidx}), .q(mq));

	// hex digit selected by a placeholder byte
	reg [31:0] hv;
	reg  [3:0] hd;
	always @* begin
		case (mq[4:3])
		2'd0:    hv = {9'd0, e_adr};
		2'd1:    hv = e_got;
		2'd2:    hv = e_exp;
		default: hv = e_phase;
		endcase
		case (mq[2:0])
		3'd0: hd = hv[31:28];
		3'd1: hd = hv[27:24];
		3'd2: hd = hv[23:20];
		3'd3: hd = hv[19:16];
		3'd4: hd = hv[15:12];
		3'd5: hd = hv[11:8];
		3'd6: hd = hv[7:4];
		default: hd = hv[3:0];
		endcase
	end

	// placeholders are 80h..9Fh: {3'b100, value[1:0], digit[2:0]}
	wire is_ph = (mq[7:5] == 3'b100);
	wire [7:0] ph_ch = (hd < 4'd10) ? (8'h30 + {4'd0, hd}) : (8'h37 + {4'd0, hd});

	// module size message: 1 = not reported, 2/3/4 = 32/64/128 MB
	wire [3:0] szmsg = (!sdram_sz[15] || sdram_sz[1:0] == 2'd0) ? 4'd1
	                 : {2'd0, sdram_sz[1:0]} + 4'd1;

	initial begin
		tst     = T_IDLE;
		pst     = P_IDLE;
		busy    = 1'b0;
		fail    = 1'b0;
		req     = 1'b0;
		tx_stb  = 1'b0;
		phase   = 2'd1;
		best_phase = 2'd1;
		start_q = 1'b0;
		ok      = 4'd0;
	end

	always @(posedge clk) begin
		tx_stb <= 1'b0;
		if (start) start_q <= 1'b1;

		if (rst) begin
			tst     <= T_IDLE;
			pst     <= P_IDLE;
			busy    <= 1'b0;
			fail    <= 1'b0;
			req     <= 1'b0;
			phase   <= 2'd1;
			best_phase <= 2'd1;
			start_q <= 1'b0;
		end else begin

			// ------------------------------------------------ memory test
			case (tst)
			T_IDLE, T_DONE: if (start_q) begin
				start_q <= 1'b0;
				busy    <= 1'b1;
				fail    <= 1'b0;
				pfail   <= 1'b0;
				det     <= 1'b0;
				ok      <= 4'd0;
				any_ok  <= 1'b0;
				la      <= 23'd0;
				wk      <= WLO;
				phase   <= 2'd0;        // the sweep starts at phase 0
				e_adr   <= 23'd0;
				e_got   <= 32'd0;
				e_exp   <= 32'd0;
				msg     <= 4'd0;        // banner first
				pidx    <= 6'd0;
				pace    <= 8'd0;
				pst     <= P_FETCH;
				tst     <= enable ? T_WB : T_CB;
			end

			T_WB: begin
				req     <= 1'b1;
				req_we  <= 1'b1;
				req_adr <= la;
				req_dat <= pattern(la);
				if (req_done) begin
					req <= 1'b0;
					if (la == BLOCKLW - 1) begin
						la  <= 23'd0;
						tst <= T_WW;
					end else
						la <= la + 23'd1;
				end
			end

			T_WW: begin
				req     <= 1'b1;
				req_we  <= 1'b1;
				req_adr <= walk_la;
				req_dat <= pattern(walk_la);
				if (req_done) begin
					req <= 1'b0;
					if (wk == WHI) begin
						wk    <= WLO;
						la    <= 23'd0;
						pfail <= 1'b0;
						tst   <= T_RB;
					end else
						wk <= wk + 5'd1;
				end
			end

			T_RB: begin
				req     <= 1'b1;
				req_we  <= 1'b0;
				req_adr <= {la[22:2], 2'b00};
				if (rd_stb && !pfail) begin
					if (rd_dat != pattern({la[22:2], rd_idx})) begin
						pfail <= 1'b1;
						// report the first failure seen at the nominal
						// phase: the other phases fail by design on a
						// healthy board, so their details mean nothing
						if (!det && phase == 2'd1) begin
							det   <= 1'b1;
							e_adr <= {la[22:2], rd_idx};
							e_got <= rd_dat;
							e_exp <= pattern({la[22:2], rd_idx});
						end
					end
				end
				if (req_done) begin
					req <= 1'b0;
					if (pfail || la >= BLOCKLW - 4) begin
						la  <= 23'd0;
						wk  <= WLO;
						tst <= pfail ? T_NEXT : T_RW;
					end else
						la <= la + 23'd4;
				end
			end

			T_RW: begin
				req     <= 1'b1;
				req_we  <= 1'b0;
				req_adr <= {walk_la[22:2], 2'b00};
				if (rd_stb && !pfail && rd_idx == walk_la[1:0]) begin
					if (rd_dat != pattern(walk_la)) begin
						pfail <= 1'b1;
						if (!det && phase == 2'd1) begin
							det   <= 1'b1;
							e_adr <= walk_la;
							e_got <= rd_dat;
							e_exp <= pattern(walk_la);
						end
					end
				end
				if (req_done) begin
					req <= 1'b0;
					if (pfail || wk == WHI)
						tst <= T_NEXT;
					else
						wk <= wk + 5'd1;
				end
			end

			T_NEXT: begin
				ok[phase] <= ~pfail;
				if (!pfail && !any_ok) begin     // first phase that reads back
					any_ok     <= 1'b1;
					best_phase <= phase;
				end
				if (phase == 2'd3) begin
					fail <= pfail & ~any_ok;     // no phase worked at all
					la   <= 23'd0;
					wk   <= WLO;
					tst  <= T_CB;
				end else begin
					phase <= phase + 2'd1;
					la    <= 23'd0;
					wk    <= WLO;
					pfail <= 1'b0;
					tst   <= T_RB;
				end
			end

			// leave zeros behind, see the header
			T_CB: begin
				req     <= 1'b1;
				req_we  <= 1'b1;
				req_adr <= la;
				req_dat <= 32'd0;
				if (req_done) begin
					req <= 1'b0;
					if (la == BLOCKLW - 1) begin
						la  <= 23'd0;
						tst <= enable ? T_CW : T_PR;
					end else
						la <= la + 23'd1;
				end
			end

			T_CW: begin
				req     <= 1'b1;
				req_we  <= 1'b1;
				req_adr <= walk_la;
				req_dat <= 32'd0;
				if (req_done) begin
					req <= 1'b0;
					if (wk == WHI)
						tst <= T_PR;
					else
						wk <= wk + 5'd1;
				end
			end

			T_PR: if (pst == P_IDLE) begin      // printing finished
				phase <= any_ok ? best_phase : 2'd1;
				busy  <= 1'b0;
				tst   <= T_DONE;
			end

			default: tst <= T_IDLE;
			endcase

			// ------------------------------------------------ printer
			case (pst)
			P_IDLE: ;

			P_FETCH: begin                       // pace the characters
				pace <= pace + 8'd1;
				if (&pace[5:0])
					pst <= P_WAIT;
			end

			P_WAIT: pst <= P_EMIT;               // mq is valid next clock

			P_EMIT: begin
				if (mq == 8'h00) begin           // end of this message
					case (msg)
					4'd0: begin                  // banner -> module size
						msg  <= szmsg;
						pidx <= 6'd0;
						pst  <= P_FETCH;
					end
					4'd1, 4'd2, 4'd3, 4'd4: begin
						if (tst == T_PR) begin   // phase map, once swept
							msg  <= !enable ? 4'd7 : 4'd8;
							pidx <= 6'd0;
							pst  <= P_FETCH;
						end
					end
					4'd8: begin                  // then the verdict
						msg  <= fail ? 4'd6 : 4'd5;
						pidx <= 6'd0;
						pst  <= P_FETCH;
					end
					default: pst <= P_IDLE;      // all done
					endcase
				end else if (tx_ready) begin
					tx_data <= is_ph ? ph_ch : mq;
					tx_stb  <= 1'b1;
					pidx    <= pidx + 6'd1;
					pst     <= P_FETCH;
				end
			end

			default: pst <= P_IDLE;
			endcase
		end
	end

endmodule

`default_nettype wire

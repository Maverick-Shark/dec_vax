//============================================================================
//  vax_sdram.v - SDRAM controller for the MiSTer SDRAM modules.
//
//  Works on every MiSTer SDRAM module (32 / 64 / 128 MB). All of them present
//  at least 13 row bits, 4 banks and 9 column bits on the chip selected by
//  SDRAM_nCS = 0, which is the 32 MB this core uses. The 64/128 MB modules
//  carry bigger (or two) chips; the extra capacity needs either the 10th/11th
//  column bit or the nCS chip-select trick of the 128 MB boards, neither of
//  which is used here - a VAX-11/780 could not address more than 32 MB of
//  physical memory anyway.
//
//      word address WA[23:0] = {longword address, 1'b0}
//      column = WA[8:0]   bank = WA[10:9]   row = WA[23:11]
//
//  One row holds 1 KB, so a 16-byte cache line never crosses a row.
//
//  ------------------------------------------------------------------------
//  READ DATA CAPTURE - the part that decides whether this works on silicon
//
//  SDRAM_CLK is clk inverted (DDR output register in the top level), so the
//  chip's clock edges are our FALLING edges: it samples the commands we drive
//  on a rising edge half a clock later. With CAS latency 2, the word for a
//  READ sampled at chip edge E0 appears about 6 ns (tAC) after edge E1 and is
//  held until about 3 ns (tOH) after edge E2. Seen from inside the FPGA, with
//  the 4-6 ns the forwarded clock needs to reach the chip, the data window is
//  roughly E1 + 11 ns .. E2 + 8 ns. At 50 MHz:
//
//      rising edge  E1 + 10 ns  -> at the very start of the window
//      falling edge E2          -> in the middle (about 9 ns either side)
//      rising edge  E2 + 10 ns  -> after the end of the window
//
//  So DQ is captured on the FALLING edge of clk, by one unconditional
//  register (dq_n) that nothing else reads. This is how version 1 of this
//  controller did it, and version 1 is the one that ran EVKAA on the board.
//  Version 2 captured on the rising edge, outside the window, and failed the
//  memory test on the board - while passing in a simulation model that was
//  too optimistic about when the data is valid. sim/sdram_model.v now
//  presents the data only around the falling edge. On the board this version
//  passes, and TimeQuest (slow 85 C model) gives the dq_n registers, which sit
//  in the I/O cells, +5.8 ns of setup and +8.4 ns of hold slack.
//
//  The falling-edge capture is consumed on the next rising edge. Which one is
//  selectable at run time through rdphase, and the power-on self test tries
//  all four and reports which ones read back correctly:
//
//      rdphase 0 1 2 3  ->  first word captured on falling edge E1 E2 E3 E4
//      rdphase 1 is the CAS-latency-2 value; on a healthy board the self test
//      map reads 0100. A map of 0000 is not a timing problem.
//  ------------------------------------------------------------------------
//
//  Transactions (hold req until req_done):
//    read  (req_we=0): a full line of 4 longwords from a line-aligned address,
//                      delivered as rd_stb pulses with rd_idx/rd_dat. Four
//                      CAS-2 burst-of-2 reads inside one open row.
//    write (req_we=1): one longword with byte enables (req_sel), as a single
//                      burst of 2 with auto precharge.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_sdram #(
	parameter CLK_HZ = 50000000
) (
	input             clk,
	input             rst,          // synchronous, active high
	output reg        ready,        // initialisation finished
	output            busy,         // a transaction is in flight
	input       [1:0] rdphase,      // read capture phase, see above

	input             req,
	input             req_we,
	input      [22:0] req_adr,      // longword address (line aligned if read)
	input      [31:0] req_dat,
	input       [3:0] req_sel,
	output reg        req_done,     // one clock pulse

	output reg [31:0] rd_dat,
	output reg  [1:0] rd_idx,
	output reg        rd_stb,       // one clock pulse per longword

	output reg [12:0] sd_a,
	output reg  [1:0] sd_ba,
	output reg        sd_ncs,
	output reg        sd_nras,
	output reg        sd_ncas,
	output reg        sd_nwe,
	output reg        sd_dqml,
	output reg        sd_dqmh,
	output reg [15:0] sd_dq_o,
	output reg        sd_dq_oe,
	input      [15:0] sd_dq_i
);

	/* verilator lint_off WIDTHTRUNC */
	localparam [15:0] INIT_WAIT   = CLK_HZ / 5000;           // 200 us
	localparam [9:0]  REFRESH_INT = (CLK_HZ / 1000) / 150;   // ~6.7 us
	/* verilator lint_on WIDTHTRUNC */

	// {nCS, nRAS, nCAS, nWE}
	localparam [3:0] CMD_INHIBIT   = 4'b1111,
	                 CMD_NOP       = 4'b0111,
	                 CMD_ACTIVE    = 4'b0011,
	                 CMD_READ      = 4'b0101,
	                 CMD_WRITE     = 4'b0100,
	                 CMD_PRECHARGE = 4'b0010,
	                 CMD_REFRESH   = 4'b0001,
	                 CMD_MRS       = 4'b0000;

	// A2:A0 burst 2, A3 sequential, A6:A4 CAS latency 2, A8:A7 normal,
	// A9 programmed burst length for writes too. This is the mode register
	// r-vax used on its original board, kept deliberately.
	localparam [12:0] MODE = {3'b000, 1'b0, 2'b00, 3'b010, 1'b0, 3'b001};

	localparam [4:0] S_INIT    = 5'd0,
	                 S_IPRE    = 5'd1,
	                 S_IREF    = 5'd2,
	                 S_IMRS    = 5'd3,
	                 S_IDLE    = 5'd4,
	                 S_ACT     = 5'd5,
	                 S_RCD     = 5'd6,
	                 S_CMD     = 5'd7,
	                 S_WR2     = 5'd8,
	                 S_RD1N    = 5'd9,
	                 S_RD2     = 5'd10,
	                 S_RD2N    = 5'd11,
	                 S_RD3     = 5'd12,
	                 S_RD3N    = 5'd13,
	                 S_RD4     = 5'd14,
	                 S_RDWAIT  = 5'd15,
	                 S_WAIT    = 5'd16;

	reg  [4:0]  state;
	reg  [15:0] cnt;
	reg  [3:0]  nwait;
	reg  [3:0]  nref;
	reg  [9:0]  rcnt;
	reg  [2:0]  rpend;            // a counter, so a request is never lost

	reg  [22:0] adr_l;
	reg  [31:0] dat_l;
	reg   [3:0] sel_l;
	reg         we_l;

	reg  [15:0] dq_n;             // the only consumer of sd_dq_i
	reg  [13:0] dv;               // capture pipeline, bit 0 fires on consume
	reg  [2:0]  wcnt;
	reg  [15:0] wlo;

	wire [23:0] wa  = {adr_l, 1'b0};
	wire [12:0] row = wa[23:11];
	wire  [1:0] bk  = wa[10:9];
	wire  [8:0] col = wa[8:0];

	// dv[k] set at the READ means "consume dq_n at the (k+1)th rising edge
	// from now". The word captured at falling edge E(1 + rdphase) is consumed
	// at rising edge 2 + rdphase, so the lowest bit to set is 1 + rdphase.
	// Eight words follow back to back (four bursts of two).
	wire [13:0] dv_start = 14'b00_0000_1111_1111 << (1 + rdphase);

	assign busy = (state >= S_ACT);   // S_IDLE and the init states are not

	initial begin
		state    = S_INIT;
		ready    = 1'b0;
		cnt      = 16'd0;
		rcnt     = 10'd0;
		rpend    = 3'd0;
		dv       = 14'd0;
		req_done = 1'b0;
		rd_stb   = 1'b0;
		sd_dq_oe = 1'b0;
		sd_a     = 13'd0;
		sd_ba    = 2'd0;
		{sd_ncs, sd_nras, sd_ncas, sd_nwe} = CMD_INHIBIT;
		{sd_dqmh, sd_dqml} = 2'b11;
	end

	// ---- the one and only register on the DQ pins: falling edge, see above
	always @(negedge clk)
		dq_n <= sd_dq_i;

	always @(posedge clk) begin : main
		reg inc_ref;

		{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_NOP;
		sd_dq_oe <= 1'b0;
		{sd_dqmh, sd_dqml} <= 2'b00;      // reads are never masked
		req_done <= 1'b0;
		rd_stb   <= 1'b0;

		// ---- read data: consume dq_n on the scheduled edges
		dv <= {1'b0, dv[13:1]};
		if (dv[0]) begin
			wcnt <= wcnt + 3'd1;
			if (!wcnt[0])
				wlo <= dq_n;
			else begin
				rd_dat <= {dq_n, wlo};
				rd_idx <= wcnt[2:1];
				rd_stb <= 1'b1;
			end
		end

		// ---- refresh request, accumulated so none is ever dropped
		inc_ref = (rcnt == REFRESH_INT - 10'd1);
		if (inc_ref)
			rcnt <= 10'd0;
		else
			rcnt <= rcnt + 10'd1;
		if (inc_ref && !(&rpend))
			rpend <= rpend + 3'd1;

		if (rst) begin
			state <= S_INIT;
			cnt   <= 16'd0;
			ready <= 1'b0;
			rpend <= 3'd0;
			dv    <= 14'd0;
			{sd_dqmh, sd_dqml} <= 2'b11;
			{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_INHIBIT;
		end else begin
			case (state)
			S_INIT: begin                        // power-up pause
				cnt <= cnt + 16'd1;
				if (cnt == INIT_WAIT) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_PRECHARGE;
					sd_a  <= 13'h0400;           // A10: all banks
					cnt   <= 16'd0;
					nref  <= 4'd0;
					state <= S_IPRE;
				end
			end

			S_IPRE: begin                        // tRP
				cnt <= cnt + 16'd1;
				if (cnt == 16'd3) begin
					cnt   <= 16'd0;
					state <= S_IREF;
				end
			end

			S_IREF: begin                        // 8 x AUTO REFRESH
				cnt <= cnt + 16'd1;
				if (cnt == 16'd0)
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_REFRESH;
				if (cnt == 16'd7) begin
					cnt  <= 16'd0;
					nref <= nref + 4'd1;
					if (nref == 4'd7)
						state <= S_IMRS;
				end
			end

			S_IMRS: begin
				cnt <= cnt + 16'd1;
				if (cnt == 16'd0) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_MRS;
					sd_a  <= MODE;
					sd_ba <= 2'b00;
				end
				if (cnt == 16'd3) begin          // tMRD
					ready <= 1'b1;
					rpend <= 3'd0;
					state <= S_IDLE;
				end
			end

			S_IDLE: begin
				if (|rpend) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_REFRESH;
					rpend <= rpend - 3'd1;
					nwait <= 4'd4;               // tRFC
					cnt   <= 16'd0;
					state <= S_WAIT;
				end else if (req) begin
					adr_l <= req_adr;
					dat_l <= req_dat;
					sel_l <= req_sel;
					we_l  <= req_we;
					state <= S_ACT;
				end
			end

			S_ACT: begin                         // open the row
				{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_ACTIVE;
				sd_a  <= row;
				sd_ba <= bk;
				state <= S_RCD;
			end

			S_RCD: state <= S_CMD;               // 2 clocks of tRCD, not 1

			S_CMD: begin
				sd_ba <= bk;
				if (we_l) begin
					// one burst of two words, auto precharge
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_WRITE;
					sd_a     <= {2'b00, 1'b1, 1'b0, col};
					sd_dq_oe <= 1'b1;
					sd_dq_o  <= dat_l[15:0];
					{sd_dqmh, sd_dqml} <= ~sel_l[1:0];
					state <= S_WR2;
				end else begin
					// first of four burst-of-two reads in this row
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_READ;
					sd_a  <= {2'b00, 1'b0, 1'b0, col};
					dv    <= dv_start;
					wcnt  <= 3'd0;
					cnt   <= 16'd0;
					state <= S_RD1N;
				end
			end

			// a burst of two occupies two clocks, so the next READ of the
			// line goes out every other clock; the data then streams back
			// as eight consecutive words
			S_RD1N: state <= S_RD2;

			S_RD2: begin                         // second pair
				{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_READ;
				sd_ba <= bk;
				sd_a  <= {2'b00, 1'b0, 1'b0, col | 9'd2};
				state <= S_RD2N;
			end

			S_RD2N: state <= S_RD3;

			S_RD3: begin                         // third pair
				{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_READ;
				sd_ba <= bk;
				sd_a  <= {2'b00, 1'b0, 1'b0, col | 9'd4};
				state <= S_RD3N;
			end

			S_RD3N: state <= S_RD4;

			S_RD4: begin                         // fourth pair, auto precharge
				{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_READ;
				sd_ba <= bk;
				sd_a  <= {2'b00, 1'b1, 1'b0, col | 9'd6};
				state <= S_RDWAIT;
			end

			S_WR2: begin                         // second word of the burst
				sd_dq_oe <= 1'b1;
				sd_dq_o  <= dat_l[31:16];
				{sd_dqmh, sd_dqml} <= ~sel_l[3:2];
				req_done <= 1'b1;
				nwait    <= 4'd4;                // tWR + tRP
				cnt      <= 16'd0;
				state    <= S_WAIT;
			end

			S_RDWAIT: begin
				cnt <= cnt + 16'd1;
				// cnt is 0 on the first clock after the fourth READ; the
				// last longword is delivered at cnt = 2 + rdphase, and
				// req_done follows one clock later
				if (cnt == 16'd3 + {14'd0, rdphase}) begin
					req_done <= 1'b1;
					nwait    <= 4'd2;            // tRP after auto precharge
					cnt      <= 16'd0;
					state    <= S_WAIT;
				end
			end

			S_WAIT: begin
				cnt <= cnt + 16'd1;
				if (cnt[3:0] == nwait)
					state <= S_IDLE;
			end

			default: state <= S_IDLE;
			endcase
		end
	end

endmodule

`default_nettype wire

//============================================================================
//  vax_sdram.v - SDRAM controller for the MiSTer SDRAM module (32 MB).
//
//  Target chip: W9825G6KH or compatible, 4 banks x 8192 rows x 512 cols x 16.
//  50 MHz, CAS latency 2, burst length 2, one 32-bit longword per access,
//  auto-precharge after every access (closed-page policy, like r-vax sdram.v).
//
//  Bus: same simple handshake as r-vax sdram.v. The master raises STB_I and
//  keeps ADR_I/WE_I/DAT_I stable; ACK_O rises when the access is done and stays
//  high until the master drops STB_I. DAT_O/ACK_O read as 0 while STB_I is low
//  (the r-vax bus ORs the read data of all slaves). SEL_I adds byte enables
//  (DQM), used by the MiSTer program loader; the CPU path always writes 1111.
//
//  Address map (longword address ADR_I[22:0], 32 MB):
//      row = ADR_I[22:10], bank = ADR_I[9:8], column = {ADR_I[7:0], 0}
//
//  The data bus is split (dq_o / dq_oe / dq_i); the tri-state buffer and the
//  SDRAM clock forwarding (altddio_out, SDRAM_CLK = ~clk) live in the top level.
//  Read data is captured on the falling edge of clk, which centres the capture
//  window for the 180-degree shifted SDRAM clock at 50 MHz.
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

	input             STB_I,
	input             WE_I,
	input      [3:0]  SEL_I,
	input      [22:0] ADR_I,        // longword address
	input      [31:0] DAT_I,
	output     [31:0] DAT_O,
	output            ACK_O,

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

	// 200 us power-up wait, refresh every 7 us (8192 rows / 64 ms needs 7.8 us)
	localparam [15:0] INIT_WAIT   = CLK_HZ / 5000;
	localparam [9:0]  REFRESH_INT = (CLK_HZ / 1000000) * 7;

	// {nCS, nRAS, nCAS, nWE}
	localparam [3:0] CMD_INHIBIT   = 4'b1111,
	                 CMD_NOP       = 4'b0111,
	                 CMD_ACTIVE    = 4'b0011,
	                 CMD_READ      = 4'b0101,
	                 CMD_WRITE     = 4'b0100,
	                 CMD_PRECHARGE = 4'b0010,
	                 CMD_REFRESH   = 4'b0001,
	                 CMD_MRS       = 4'b0000;

	// Mode register: burst write, standard op, CL=2, sequential, BL=2
	localparam [12:0] MODE = 13'b000_0_00_010_0_001;

	localparam [3:0] S_INIT      = 4'd0,
	                 S_INIT_PRE  = 4'd1,
	                 S_INIT_REF  = 4'd2,
	                 S_INIT_MRS  = 4'd3,
	                 S_IDLE      = 4'd4,
	                 S_RCD       = 4'd5,
	                 S_RW        = 4'd6,
	                 S_RD1       = 4'd7,
	                 S_RD2       = 4'd8,
	                 S_RD3       = 4'd9,
	                 S_RD4       = 4'd10,
	                 S_WR2       = 4'd11,
	                 S_WAIT      = 4'd12;

	reg  [3:0]  state;
	reg  [15:0] cnt;
	reg  [2:0]  wait_n;
	reg  [3:0]  nref;
	reg  [9:0]  rcnt;
	reg         rpend;
	reg         ack;
	reg  [31:0] rdata;
	reg  [31:0] wdata;
	reg  [3:0]  wsel;
	reg         we_l;
	reg  [22:0] adr_l;
	reg  [15:0] dq_neg;

	initial begin
		state    = S_INIT;
		ready    = 1'b0;
		ack      = 1'b0;
		rpend    = 1'b0;
		cnt      = 16'd0;
		rcnt     = 10'd0;
		sd_dq_oe = 1'b0;
		{sd_ncs, sd_nras, sd_ncas, sd_nwe} = CMD_INHIBIT;
		{sd_dqmh, sd_dqml} = 2'b11;
	end

	// read data capture on the falling edge (see header)
	always @(negedge clk)
		dq_neg <= sd_dq_i;

	assign DAT_O = STB_I ? rdata : 32'd0;
	assign ACK_O = STB_I & ack;

	always @(posedge clk) begin
		{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_NOP;
		sd_dq_oe <= 1'b0;

		if (!STB_I)
			ack <= 1'b0;

		if (rcnt == REFRESH_INT - 10'd1) begin
			rcnt  <= 10'd0;
			rpend <= 1'b1;
		end else
			rcnt <= rcnt + 10'd1;

		if (rst) begin
			state <= S_INIT;
			cnt   <= 16'd0;
			ready <= 1'b0;
			ack   <= 1'b0;
			rpend <= 1'b0;
			{sd_dqmh, sd_dqml} <= 2'b11;
			{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_INHIBIT;
		end else begin
			case (state)
			S_INIT: begin
				cnt <= cnt + 16'd1;
				if (cnt == INIT_WAIT) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_PRECHARGE;
					sd_a[10] <= 1'b1;               // all banks
					cnt   <= 16'd0;
					nref  <= 4'd0;
					state <= S_INIT_PRE;
				end
			end

			S_INIT_PRE: begin
				cnt <= cnt + 16'd1;
				if (cnt == 16'd3) begin
					cnt   <= 16'd0;
					state <= S_INIT_REF;
				end
			end

			S_INIT_REF: begin                     // 8 x AUTO REFRESH
				cnt <= cnt + 16'd1;
				if (cnt == 16'd0)
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_REFRESH;
				if (cnt == 16'd7) begin
					cnt  <= 16'd0;
					nref <= nref + 4'd1;
					if (nref == 4'd7)
						state <= S_INIT_MRS;
				end
			end

			S_INIT_MRS: begin
				cnt <= cnt + 16'd1;
				if (cnt == 16'd0) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_MRS;
					sd_a  <= MODE;
					sd_ba <= 2'b00;
				end
				if (cnt == 16'd3) begin
					ready <= 1'b1;
					rpend <= 1'b0;
					state <= S_IDLE;
				end
			end

			S_IDLE: begin
				if (rpend) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_REFRESH;
					rpend  <= 1'b0;
					cnt    <= 16'd0;
					wait_n <= 3'd5;                 // tRFC
					state  <= S_WAIT;
				end else if (STB_I && !ack) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_ACTIVE;
					sd_ba <= ADR_I[9:8];
					sd_a  <= ADR_I[22:10];
					adr_l <= ADR_I;
					we_l  <= WE_I;
					wdata <= DAT_I;
					wsel  <= SEL_I;
					state <= S_RCD;
				end
			end

			S_RCD: state <= S_RW;                 // extra cycle of tRCD margin

			S_RW: begin
				sd_ba <= adr_l[9:8];
				sd_a  <= {2'b00, 1'b1, 1'b0, adr_l[7:0], 1'b0}; // A10: auto precharge
				if (we_l) begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_WRITE;
					sd_dq_oe <= 1'b1;
					sd_dq_o  <= wdata[15:0];
					{sd_dqmh, sd_dqml} <= ~wsel[1:0];
					state <= S_WR2;
				end else begin
					{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= CMD_READ;
					{sd_dqmh, sd_dqml} <= 2'b00;
					state <= S_RD1;
				end
			end

			S_WR2: begin                          // second word of the burst
				sd_dq_oe <= 1'b1;
				sd_dq_o  <= wdata[31:16];
				{sd_dqmh, sd_dqml} <= ~wsel[3:2];
				ack    <= 1'b1;
				cnt    <= 16'd0;
				wait_n <= 3'd4;                     // tWR + tRP
				state  <= S_WAIT;
			end

			S_RD1: state <= S_RD2;
			S_RD2: state <= S_RD3;
			S_RD3: begin
				rdata[15:0] <= dq_neg;              // captured at the previous falling edge
				state <= S_RD4;
			end
			S_RD4: begin
				rdata[31:16] <= dq_neg;
				ack    <= 1'b1;
				cnt    <= 16'd0;
				wait_n <= 3'd2;
				state  <= S_WAIT;
			end

			S_WAIT: begin
				cnt <= cnt + 16'd1;
				if (cnt[2:0] == wait_n)
					state <= S_IDLE;
			end

			default: state <= S_IDLE;
			endcase
		end
	end

endmodule

`default_nettype wire

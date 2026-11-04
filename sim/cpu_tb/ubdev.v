//============================================================================
//  ubdev.v - a Unibus test device for the CPU bench, not part of the core:
//  something on the DW780's Unibus for the tests to exercise the device
//  side of the adapter with - device registers, interrupts (BR, BG, INTR
//  and the vector) and a device that is DMA master after an NPR.
//
//  Registers (Unibus 777400, SBI 2013 FF00; words, DATOB writes a byte):
//
//    777400 CSR  <15> GO (written 1: start the DMA, reads 0), <14> NXM
//                (no slave sync in 10 us: the DMA stopped), <13:12> the
//                function: 00 DATI, 01 DATIP then DATO of the word plus 1,
//                10 DATO, 11 DATOB; <7:6> interrupt level, BR4 + <7:6>;
//                <5> interrupt request (written 1: BR until the grant;
//                written 0: taken back, a passive release); <4> interrupt
//                at the end of the DMA; <0> DONE (the DMA over)
//    777402 VEC  the vector it gives with INTR
//    777404 BA   the DMA's Unibus address <15:0>
//    777406 BAE  <1:0> the address <17:16>
//    777410 WC   how many words (bytes for DATOB) the DMA transfers
//    777412 DAT  DATI: the sum of the words read; the others: the first
//                word (byte) written, each next one plus 1
//    777414 LAST the last word read
//
//  The DMA holds the bus (NPR) for its whole burst; each cycle puts its
//  address, control and data out at least 150 ns before MSYN, as the
//  Unibus wants. INIT clears everything.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module ubdev (
	input             clk,
	input             rst,

	// the Unibus as device registers see it
	input      [17:0] ub_a,
	input       [1:0] ub_c,
	input      [15:0] ub_d,
	input             ub_msyn,
	output reg        ub_ssyn,
	output reg [15:0] ub_rd,
	// as master
	output reg        dv_npr,
	input             dv_npg,
	output reg [17:0] dv_a,
	output reg  [1:0] dv_c,
	output reg [15:0] dv_d,
	output reg        dv_msyn,
	input             dv_ssyn,
	input      [15:0] dv_rd,
	// interrupts
	output      [3:0] ub_br,
	input       [3:0] ub_bg,
	output reg        ub_intr,
	output     [15:0] ub_vec,
	input             ub_init
);

	localparam [17:0] BASE = 18'o777400;

	reg  [15:0] csr, vec, ba, wc, dat, last;
	reg   [1:0] bae;
	reg         ireq;

	assign ub_br  = ireq ? (4'd1 << csr[7:6]) : 4'd0;
	assign ub_vec = vec;

	// slave: the registers
	wire        sel = ub_msyn && (ub_a[17:4] == BASE[17:4]) && (ub_a[3:1] <= 3'd6);
	reg   [3:0] s_t;

	function [15:0] rreg(input [2:0] r);
		case (r)
		3'd0: rreg = {1'b0, csr[14:6], ireq, csr[4:0]};
		3'd1: rreg = vec;
		3'd2: rreg = ba;
		3'd3: rreg = {14'd0, bae};
		3'd4: rreg = wc;
		3'd5: rreg = dat;
		default: rreg = last;
		endcase
	endfunction

	// master: the DMA
	localparam [2:0] M_IDLE = 3'd0, M_NPR = 3'd1, M_SET = 3'd2, M_SYN = 3'd3,
	                 M_REL = 3'd4, M_END = 3'd5;
	reg   [2:0] ms;
	reg   [9:0] mt;
	reg         m_wr2;               // DATIP done: the DATO of the word + 1

	always @(posedge clk) begin
		ub_intr <= 1'b0;
		if (rst || ub_init) begin
			csr <= 16'd0; vec <= 16'd0; ba <= 16'd0; bae <= 2'd0;
			wc <= 16'd0; dat <= 16'd0; last <= 16'd0;
			ireq <= 1'b0;
			ub_ssyn <= 1'b0;
			s_t <= 4'd0;
			ms <= M_IDLE;
			dv_npr <= 1'b0; dv_msyn <= 1'b0;
		end else begin
			/* ------------------------------------------- registers */
			if (!sel) begin
				ub_ssyn <= 1'b0;
				s_t <= 4'd0;
			end else if (!ub_ssyn) begin
				if (s_t != 4'd10)
					s_t <= s_t + 4'd1;     // 200 ns to answer
				else begin
					ub_ssyn <= 1'b1;
					ub_rd   <= rreg(ub_a[3:1]);
					if (ub_c[1]) begin
						// DATO, or DATOB of one byte
						case (ub_a[3:1])
						3'd0: begin
							if (!ub_c[0] || !ub_a[0]) begin
								csr[7:4] <= ub_d[7:4];
								csr[0]   <= ub_d[0];
								ireq     <= ub_d[5];
							end
							if (!ub_c[0] || ub_a[0]) begin
								csr[14:12] <= ub_d[14:12];
								if (ub_d[15] && ms == M_IDLE) begin
									csr[0]  <= 1'b0;
									csr[14] <= 1'b0;
									m_wr2   <= 1'b0;
									ms      <= M_NPR;
								end
							end
						end
						3'd1: begin
							if (!ub_c[0] || !ub_a[0]) vec[7:0]  <= ub_d[7:0];
							if (!ub_c[0] ||  ub_a[0]) vec[15:8] <= ub_d[15:8];
						end
						3'd2: begin
							if (!ub_c[0] || !ub_a[0]) ba[7:0]  <= ub_d[7:0];
							if (!ub_c[0] ||  ub_a[0]) ba[15:8] <= ub_d[15:8];
						end
						3'd3: if (!ub_c[0] || !ub_a[0]) bae <= ub_d[1:0];
						3'd4: begin
							if (!ub_c[0] || !ub_a[0]) wc[7:0]  <= ub_d[7:0];
							if (!ub_c[0] ||  ub_a[0]) wc[15:8] <= ub_d[15:8];
						end
						3'd5: begin
							if (!ub_c[0] || !ub_a[0]) dat[7:0]  <= ub_d[7:0];
							if (!ub_c[0] ||  ub_a[0]) dat[15:8] <= ub_d[15:8];
						end
						default: ;
						endcase
					end
				end
			end

			/* -------------------------------------------- interrupt */
			if (ireq && ub_bg[csr[7:6]]) begin
				ub_intr <= 1'b1;               // the vector goes with it
				ireq    <= 1'b0;
			end

			/* --------------------------------------------------- DMA */
			case (ms)
			M_NPR: begin
				dv_npr <= 1'b1;
				if (dv_npr && dv_npg) begin
					mt <= 10'd0;
					ms <= (wc == 16'd0) ? M_END : M_SET;
				end
			end
			M_SET: begin
				dv_a <= {bae, ba};
				dv_c <= (csr[13:12] == 2'b01) ? (m_wr2 ? 2'b10 : 2'b01) :
				        (csr[13:12] == 2'b00) ? 2'b00 : csr[13:12];
				dv_d <= (csr[13:12] == 2'b01) ? last + 16'd1 :
				        (csr[13:12] == 2'b11) ? (ba[0] ? {dat[7:0], 8'd0} : {8'd0, dat[7:0]}) :
				        dat;
				if (mt == 10'd8) begin          // 150 ns of deskew, then MSYN
					dv_msyn <= 1'b1;
					mt <= 10'd0;
					ms <= M_SYN;
				end else
					mt <= mt + 10'd1;
			end
			M_SYN: if (dv_ssyn) begin
				dv_msyn <= 1'b0;
				if (!dv_c[1]) begin
					last <= dv_rd;
					if (csr[13:12] == 2'b00)
						dat <= dat + dv_rd;
				end
				ms <= M_REL;
			end else if (mt == 10'd500) begin
				// no slave sync in 10 us: non-existent memory
				dv_msyn <= 1'b0;
				csr[14] <= 1'b1;
				ms <= M_END;
			end else
				mt <= mt + 10'd1;
			M_REL: if (!dv_ssyn) begin
				mt <= 10'd0;
				if (csr[13:12] == 2'b01 && !m_wr2) begin
					m_wr2 <= 1'b1;               // the DATO of the DATIP
					ms <= M_SET;
				end else begin
					m_wr2 <= 1'b0;
					if (csr[13:12] != 2'b00)
						dat <= dat + 16'd1;
					{bae, ba} <= {bae, ba} + ((csr[13:12] == 2'b11) ? 18'd1 : 18'd2);
					wc <= wc - 16'd1;
					ms <= (wc == 16'd1) ? M_END : M_SET;
				end
			end
			M_END: begin
				dv_npr  <= 1'b0;
				csr[0]  <= 1'b1;
				if (csr[4])
					ireq <= 1'b1;
				ms <= M_IDLE;
			end
			default: ;
			endcase
		end
	end

endmodule

`default_nettype wire

/*
 * cons86.v - the VAX 8600 console registers RXCS, RXDB, TXCS and TXDB as
 * the console program presents them to the CPU while it runs (program I/O
 * mode): four lines behind one pair of transmit and receive registers, each
 * byte tagged with the line it goes to or comes from.
 *
 * Written for the MiSTer port of r-vax, after:
 *   - VAX Hardware Handbook, Volume 1 (1986), chapter 10, "VAX Privileged
 *     Registers", the VAX 8600 console registers: the formats of RXCS,
 *     RXDB, TXCS and TXDB, the line identification codes, and the logical
 *     console's requests and answers;
 *   - VAX 8600/8650 Console Software Specification (EY-4818E-DX-0001),
 *     chapter 10 (program I/O mode: the console multiplexes the CPU's bytes
 *     through TXDB to the enabled lines and passes bytes for the CPU through
 *     RXDB with their line's ID), 5.8 (CPU reboot requests), 9.1 (the COLD
 *     and WARM flags).
 *
 *   TXCS  <19:16> transmit enable mask, one bit per line, written only
 *               when <15> (write mask now) is set in the same write
 *         <11:8>  the line that is ready for a byte (F: none enabled)
 *         <7>     ready, <6> interrupt enable
 *   TXDB  <7:0>   a byte for the line TXCS<11:8> names
 *   RXCS  <19:16> data terminal ready, one bit per line, <7> done,
 *         <6> interrupt enable
 *   RXDB  <19:16> carrier, <11:8> the line the byte comes from,
 *         <7:0>   the byte
 *
 *   Lines: 0 console terminal, 1 remote services port, 2 environmental
 *   monitoring module (EMM), 3 logical console.
 *
 * Here:
 *   0  the console terminal: r-vax's serial line (constx, consrx) to the
 *      on-screen terminal and the MiSTer UART.
 *   1  the remote services port has no modem: always ready, its bytes are
 *      dropped, no carrier.
 *   2  there is no EMM: always ready, its bytes are dropped, no answers.
 *   3  the logical console: the requests below, answered at once.
 *   The CT, EMM and logical console lines are wired, not modem lines: RXDB
 *   reports their carrier (<16>, <18>, <19>) whatever RXCS<19:16> says.
 *
 * Logical console requests (a byte to line 3) and their answers (bytes from
 * line 3, the request's code first):
 *   02      reboot the CPU: the console halts it ("CPU reboot requested").
 *           The 8600's console then boots it again if its restart switch
 *           allows that; here the switch is at HALT: the processor stays
 *           halted, with the console halt code, and is booted again from
 *           the OSD.
 *   03, 04  clear the console's WARM (restart) / COLD (bootstrap) flag.
 *   10, 11  the WARM / COLD flag: 10 or 11, then 00 or 01.
 *   12      the microcode version: 12, then the version, low byte first.
 *   30      the snapshot files: 30, then 00 (neither is valid).
 *   31, 32  invalidate a snapshot file: there are none.
 *   70      cancel: answers not yet taken are dropped.
 *   20 (a console command string, used by diagnostics such as EDKAX) needs
 *   the console's command language and is not here: it gets no answer.
 * The console sets COLD when it begins a bootstrap (the OSD's Boot entry,
 * input boot). A write to CRBT reboots the console: it clears COLD and
 * WARM, drops what it had queued and answers 40, "the console has been
 * rebooted".
 *
 * The answers wait in a queue of eight bytes; the logical console takes a
 * request only while three more fit, which no request needs to wait for
 * unless the CPU stops reading. They go into RXDB as soon as it is empty,
 * before the console terminal's next character. What a program leaves
 * unread stays for the next reader; processor initialization drops it.
 *
 * TXCS<11:8> and <7> say which line the console offers the next byte to.
 * After a byte is written, or the mask, the console offers the first ready
 * enabled line in the order logical console, EMM, remote port, console
 * terminal (DEC's description gives no order). Processor initialization
 * clears the interrupt enables and RXCS and leaves the console terminal
 * enabled, as the console program has it for the programs that, like VMB,
 * write TXDB without setting the mask.
 *
 * While the CPU is halted (con) the console monitor has the registers: they
 * are the console terminal's line alone, as the 8600 console talks to its
 * terminal directly in console I/O mode, and the CPU's view of them waits,
 * unchanged, until the CPU runs again.
 *
 * Interrupts (IPL 14, SCB F8 receive and FC transmit, as before): requested
 * when RXCS<7> or TXCS<7> sets with its interrupt enable, or the enable is
 * set with it, and taken away by the CPU's acknowledge.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

`timescale 1ns / 1ps
`default_nettype none
`include "ipr.vh"

module cons86 #(
	/* answer to the logical console's microcode version request: the 8600
	   console reported the version of the microcode files it had loaded;
	   this is the reference simulator's */
	parameter [15:0] UCODE_VER = 16'h0001
) (
	input		clk,
	input		rst,		/* processor initialization */
	input		con,		/* the CPU is halted: the console monitor */

	/* the CPU's IPR bus: register, write data, write strobe (one clock
	   for MTPR); rxdb_rd: RXDB has been read (MFPR, or the monitor) */
	input [6:0]	adr,
	input [31:0]	wdata,
	input		we,
	input		rxdb_rd,

	output [31:0]	rxcs,
	output [31:0]	rxdb,
	output [31:0]	txcs,

	input		tx_intack,
	input		rx_intack,
	output reg	tx_intreq,
	output reg	rx_intreq,

	input		boot,		/* the console begins a bootstrap */
	output reg	reboot,		/* CPU reboot request, one clock */

	output		tto_tx,
	input		tti_rx
);
	localparam [3:0] ID_CT = 4'd0, ID_RS = 4'd1, ID_EMM = 4'd2, ID_LC = 4'd3,
	    ID_NONE = 4'hF;

	wire wr_txcs = we && adr == `IPR_TXCS;
	wire wr_txdb = we && adr == `IPR_TXDB;
	wire wr_rxcs = we && adr == `IPR_RXCS;
	wire wr_crbt = we && adr == `IPR_CRBT;

	/* TXCS: the mask, the line offered (tx_id, tx_rdy), the enable */
	reg	[3:0]	tx_mask, tx_id;
	reg		tx_rdy, tx_ie;

	/* ------------------------------------------------- console terminal */
	wire		ct_txrdy;
	/*
	 * TXCS<7>: the line offered can take the byte. The console terminal
	 * can be busy again by then: the monitor prints on it while the CPU is
	 * halted, so a program that goes on after the monitor's G sees the
	 * terminal ready only when it is.
	 */
	wire		tx_ready = tx_rdy && (tx_id != ID_CT || ct_txrdy);
	/* the monitor writes the terminal directly; the CPU through line 0 */
	wire		ct_wr = wr_txdb && (con || (tx_ready && tx_id == ID_CT));

	constx ct_tx (
		.clk(clk),
		.rst(rst),
		.iprdb(wdata[7:0]),
		.wrtxdb(ct_wr),
		.rdy(ct_txrdy),
		.tto_tx(tto_tx)
	);

	wire		ct_rxdone;
	wire [7:0]	ct_rxdata;
	wire		ct_take;	/* the terminal's character is taken */

	consrx ct_rx (
		.clk(clk),
		.rst(rst),
		.rdrxdb(ct_take),
		.rdy(ct_rxdone),
		.rxdb(ct_rxdata),
		.tti_rx(tti_rx)
	);

	/* ---------------------------------------------- the logical console */
	reg		cold, warm;
	initial begin
		cold = 1'b0;
		warm = 1'b0;
	end

	reg	[7:0]	lcq [0:7];	/* answers not yet in RXDB */
	reg	[2:0]	lcq_wp, lcq_rp;
	reg	[3:0]	lcq_n;
	wire		lc_room = lcq_n <= 4'd5;

	wire		lc_wr = !con && wr_txdb && tx_ready && tx_id == ID_LC;
	wire [7:0]	lc_fn = wdata[7:0];

	/* the answer to this clock's request: n bytes a0, a1, a2 */
	reg	[1:0]	an;
	reg	[7:0]	a0, a1, a2;
	reg		lc_flush;
	always @* begin
		an = 2'd0;
		a0 = 8'h00;
		a1 = 8'h00;
		a2 = 8'h00;
		lc_flush = 1'b0;
		if (lc_wr)
			case (lc_fn)
			8'h10: begin an = 2'd2; a0 = 8'h10; a1 = { 7'd0, warm }; end
			8'h11: begin an = 2'd2; a0 = 8'h11; a1 = { 7'd0, cold }; end
			8'h12: begin an = 2'd3; a0 = 8'h12; a1 = UCODE_VER[7:0];
			    a2 = UCODE_VER[15:8]; end
			8'h30: begin an = 2'd2; a0 = 8'h30; a1 = 8'h00; end
			8'h70: lc_flush = 1'b1;
			default: ;
			endcase
		else if (!con && wr_crbt) begin
			lc_flush = 1'b1;
			an = 2'd1;
			a0 = 8'h40;
		end
	end

	/* an answer byte goes into RXDB (before the terminal's next one) */
	reg		rx_done;
	wire		lc_pop = !con && !rx_done && lcq_n != 4'd0 && !lc_flush;

	always @(posedge clk) begin
		if (rst || lc_flush) begin
			lcq_wp <= 3'd0;
			lcq_rp <= 3'd0;
			lcq_n <= 4'd0;
		end else if (lc_pop) begin
			lcq_rp <= lcq_rp + 3'd1;
			lcq_n <= lcq_n - 4'd1;
		end
		/* a flush and the new answer can come in the same clock (CRBT) */
		if (!rst && an != 2'd0) begin
			lcq[(lc_flush ? 3'd0 : lcq_wp)] <= a0;
			lcq[(lc_flush ? 3'd0 : lcq_wp) + 3'd1] <= a1;
			lcq[(lc_flush ? 3'd0 : lcq_wp) + 3'd2] <= a2;
			lcq_wp <= (lc_flush ? 3'd0 : lcq_wp) + { 1'b0, an };
			lcq_n <= (lc_flush ? 4'd0 : lcq_n) - { 3'd0, lc_pop } +
			    { 2'd0, an };
		end
	end

	always @(posedge clk) begin
		reboot <= lc_wr && lc_fn == 8'h02;
		if (boot)
			cold <= 1'b1;
		else if ((lc_wr && lc_fn == 8'h04) || (!con && wr_crbt))
			cold <= 1'b0;
		if ((lc_wr && lc_fn == 8'h03) || (!con && wr_crbt))
			warm <= 1'b0;
	end

	/* --------------------------------------------- transmit: TXCS, TXDB */
	/* lines that can take a byte now */
	wire [3:0]	cand = tx_mask & { lc_room, 1'b1, 1'b1, ct_txrdy };

	always @(posedge clk)
		if (rst) begin
			tx_mask <= 4'b0001;	/* the console terminal */
			tx_id <= ID_NONE;
			tx_rdy <= 1'b0;
			tx_ie <= 1'b0;
		end else if (!con) begin
			if (wr_txcs) begin
				tx_ie <= wdata[6];
				if (wdata[15]) begin
					/* a new mask: the console offers a line again */
					tx_mask <= wdata[19:16];
					tx_rdy <= 1'b0;
				end
			end else if (wr_txdb) begin
				/* the byte went to line tx_id (or nowhere if not ready) */
				tx_rdy <= 1'b0;
			end else if (!tx_rdy) begin
				if (cand[3]) begin
					tx_id <= ID_LC;
					tx_rdy <= 1'b1;
				end else if (cand[2]) begin
					tx_id <= ID_EMM;
					tx_rdy <= 1'b1;
				end else if (cand[1]) begin
					tx_id <= ID_RS;
					tx_rdy <= 1'b1;
				end else if (cand[0]) begin
					tx_id <= ID_CT;
					tx_rdy <= 1'b1;
				end else if (tx_mask == 4'd0)
					tx_id <= ID_NONE;
			end
		end

	/* ----------------------------------------------- receive: RXCS, RXDB */
	reg	[3:0]	rx_dtr, rx_id;
	reg	[7:0]	rx_data;
	reg		rx_ie, ct_take_d;

	/* the terminal's character comes into RXDB (the CPU's), or the
	   monitor reads it */
	wire		ct_load = !con && !rx_done && !lc_pop && ct_rxdone &&
			    !ct_take_d;
	assign ct_take = con ? rxdb_rd : ct_load;

	always @(posedge clk) begin
		ct_take_d <= ct_take;
		if (rst) begin
			rx_done <= 1'b0;
			rx_ie <= 1'b0;
			rx_dtr <= 4'd0;
		end else if (!con) begin
			if (wr_rxcs) begin
				rx_ie <= wdata[6];
				rx_dtr <= wdata[19:16];
			end
			if (rxdb_rd)
				rx_done <= 1'b0;
			if (lc_pop) begin
				rx_done <= 1'b1;
				rx_id <= ID_LC;
				rx_data <= lcq[lcq_rp];
			end else if (ct_load) begin
				rx_done <= 1'b1;
				rx_id <= ID_CT;
				rx_data <= ct_rxdata;
			end
		end
	end

	/* ------------------------------------------------------- interrupts */
	reg		tx_last, rx_last;
	always @(posedge clk)
		if (rst) begin
			tx_intreq <= 1'b0;
			rx_intreq <= 1'b0;
			tx_last <= 1'b0;
			rx_last <= 1'b0;
		end else if (!con) begin
			if (tx_ready && tx_ie && !tx_last)
				tx_intreq <= 1'b1;
			else if (tx_intack)
				tx_intreq <= 1'b0;
			tx_last <= tx_ready && tx_ie;
			if (rx_done && rx_ie && !rx_last)
				rx_intreq <= 1'b1;
			else if (rx_intack)
				rx_intreq <= 1'b0;
			rx_last <= rx_done && rx_ie;
		end

	/* ------------------------------------------------------- read values */
	assign txcs = con ? { 24'd0, ct_txrdy, 7'd0 } :
	    { 12'd0, tx_mask, 4'd0, tx_id, tx_ready, tx_ie, 6'd0 };
	assign rxcs = con ? { 24'd0, ct_rxdone, 7'd0 } :
	    { 12'd0, rx_dtr, 8'd0, rx_done, rx_ie, 6'd0 };
	assign rxdb = con ? { 24'd0, ct_rxdata } :
	    { 12'd0, 4'b1101, 4'd0, rx_id, rx_data };

endmodule

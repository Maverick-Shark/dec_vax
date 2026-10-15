//============================================================================
//  vax_system.v - everything of the MiSTer core below the emu/hps_io layer.
//
//    vax_core     r-vax CPU + M10K cache + 32 MB SDRAM + SBI stubs
//    vax_selftest power-on SDRAM test and banner (owns memory, CPU in reset)
//    loader       HPS file download (OSD "Load Program") into SDRAM
//    autostart    types FR<addr><CR>G into the console monitor after a load
//    vax_kbd      USB keyboard -> ASCII -> console receive line (TTI)
//    vt_term      console transmit line (TTO) -> on-screen terminal
//    UART bridge  the same console on the MiSTer UART at 115200 baud
//    beeper       BEL -> short tone on the audio output
//
//  Console wiring: the r-vax console is a serial line inside the CPU
//  (constx/consrx on IPRs 20h-23h). Its bit rate is set by CLKPERBIT and is
//  deliberately fast here - it never leaves the FPGA, and a slow line would
//  only make the screen crawl. The MiSTer UART, which does leave the FPGA,
//  gets its own pair of 115200 baud converters with FIFOs.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_system #(
	parameter CLK_HZ   = 50000000,
	parameter CPB      = 16,        // internal console bit period - 1
	parameter UART_CPB = 434,       // 115200 baud at 50 MHz
	parameter CACHEIDX = 10
) (
	input             clk,
	input             rst_mem,      // power-up reset (PLL not locked)
	input             rst_sys,      // user reset (OSD / button)

	// HPS download
	input             ioctl_download,
	input      [15:0] ioctl_index,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input       [7:0] ioctl_dout,
	output            ioctl_wait,

	// options
	input       [1:0] load_base,    // 0: 0x1000, 1: 0x0, 2: 0x200, 3: 0x10000
	input             start_200,    // start at 0x200 instead of the load address
	input             autostart,
	input       [1:0] color,
	input             kbd_es,
	input             uart_console,
	input             ctrlp_halt,   // Ctrl+P halts the CPU instead of being typed
	input             halt_osd,     // one clock pulse: halt the CPU (OSD)
	input             selftest_en,
	input             selftest_go,  // one clock pulse: run the test again
	input       [2:0] rdphase_sel,  // 0 = calibrated, 1..4 = force phase 0..3
	input      [15:0] sdram_sz,

	input      [10:0] ps2_key,
	input             uart_rxd,
	output            uart_txd,

	// SDRAM (split data bus)
	output     [12:0] sd_a,
	output      [1:0] sd_ba,
	output            sd_ncs,
	output            sd_nras,
	output            sd_ncas,
	output            sd_nwe,
	output            sd_dqml,
	output            sd_dqmh,
	output     [15:0] sd_dq_o,
	output            sd_dq_oe,
	input      [15:0] sd_dq_i,

	// video
	output            ce_pix,
	output            hs,
	output            vs,
	output            hblank,
	output            vblank,
	output      [7:0] r,
	output      [7:0] g,
	output      [7:0] b,

	output     [15:0] audio,
	output            led_user,
	output            led_disk
);

	wire mem_ready;
	wire cpu_halted;
	reg  halt_req;      // Ctrl+P / OSD halt, one clock (see the console input)

	// ------------------------------------------------------------ loader
	wire        ldr_go = ioctl_download && (ioctl_index[5:0] == 6'd1);
	reg         ldr_stb, ldr_busy;
	reg  [22:0] ldr_adr;
	reg   [3:0] ldr_sel;
	reg  [31:0] ldr_dat;
	reg  [24:0] base;

	always @* begin
		case (load_base)
		2'd0: base = 25'h0001000;
		2'd1: base = 25'h0000000;
		2'd2: base = 25'h0000200;
		default: base = 25'h0010000;
		endcase
	end

	wire [24:0] ldr_byte_addr = base + ioctl_addr[24:0];

	initial begin
		ldr_stb  = 1'b0;
		ldr_busy = 1'b0;
	end

	assign ioctl_wait = ldr_busy;

	// ------------------------------------------------------------ self test
	wire        st_busy, st_fail;
	wire  [1:0] st_phase, st_best;
	wire        st_req, st_we;
	wire [22:0] st_adr;
	wire [31:0] st_dat;
	wire  [3:0] st_sel;
	wire  [7:0] st_char;
	wire        st_stb;
	wire        term_ready;

	// ------------------------------------------------- memory port arbitration
	wire        dma_en = ldr_go | ldr_busy | st_busy | st_pending;
	wire        dma_done;
	wire [31:0] dma_rdat;
	wire  [1:0] dma_ridx;
	wire        dma_rstb;

	wire        dma_req = st_busy ? st_req : ldr_stb;
	wire        dma_we  = st_busy ? st_we  : 1'b1;
	wire [22:0] dma_adr = st_busy ? st_adr : ldr_adr;
	wire [31:0] dma_dat = st_busy ? st_dat : ldr_dat;
	wire  [3:0] dma_sel = st_busy ? st_sel : ldr_sel;

	always @(posedge clk) begin
		if (ldr_stb && dma_done) begin
			ldr_stb  <= 1'b0;
			ldr_busy <= 1'b0;
		end
		// accept on the completion cycle too: ldr_busy still reads 1 there
		if (ldr_go && ioctl_wr && (!ldr_busy || (ldr_stb && dma_done))) begin
			ldr_adr  <= ldr_byte_addr[24:2];
			ldr_sel  <= 4'b0001 << ldr_byte_addr[1:0];
			ldr_dat  <= {4{ioctl_dout}};
			ldr_stb  <= 1'b1;
			ldr_busy <= 1'b1;
		end
	end

	// ------------------------------------------------------------ resets
	reg  rst_cpu;
	initial rst_cpu = 1'b1;
	always @(posedge clk)
		rst_cpu <= rst_mem | rst_sys | ~mem_ready | dma_en;

	reg  rst_term;
	initial rst_term = 1'b1;
	always @(posedge clk)
		rst_term <= rst_mem | rst_sys;

	// When to run the power-on test. MiSTer Main, when it starts the core,
	// sends the SDRAM module size and a few microseconds later sets status[0]
	// (our rst_sys) and holds it while it loads the saved OSD settings. The
	// terminal is reset with rst_sys, so a banner printed in that window is
	// wiped - that is what cut the first line short. So the test waits until
	// the size is known (or has not come for 2 s) AND rst_sys has then been
	// low for 50 ms. That also means the saved "Power-on Memory Test" setting
	// is in place before the test looks at it.
	localparam [26:0] SZ_TIMEOUT = 2 * CLK_HZ;    // 2 s
	/* verilator lint_off WIDTHTRUNC */
	localparam [22:0] RST_QUIET  = CLK_HZ / 20;   // 50 ms
	/* verilator lint_on WIDTHTRUNC */

	reg  [26:0] sz_wait;
	reg  [22:0] quiet;
	reg         st_armed, st_start;
	initial begin
		sz_wait = 27'd0; quiet = 23'd0; st_armed = 1'b1; st_start = 1'b0;
	end

	wire sz_known = sdram_sz[15] || (sz_wait == SZ_TIMEOUT);

	always @(posedge clk) begin
		if (rst_mem || !mem_ready)
			sz_wait <= 27'd0;
		else if (sz_wait != SZ_TIMEOUT)
			sz_wait <= sz_wait + 27'd1;

		// counts only while the size is known and the core is out of reset
		if (rst_mem || rst_sys || !sz_known)
			quiet <= 23'd0;
		else if (quiet != RST_QUIET)
			quiet <= quiet + 23'd1;
	end

	// A program download before the power-on test has started (not something
	// MiSTer does on its own; boot.rom files come with ioctl_index 0, which
	// the loader ignores) cancels the test, which would overwrite it.
	reg st_cancel;
	initial st_cancel = 1'b0;

	always @(posedge clk) begin
		st_start  <= 1'b0;
		st_cancel <= 1'b0;
		if (rst_mem)
			st_armed <= 1'b1;
		else if (st_armed) begin
			if (ldr_go) begin
				st_cancel <= 1'b1;
				st_armed  <= 1'b0;
			end else if (mem_ready && quiet == RST_QUIET) begin
				st_start <= 1'b1;
				st_armed <= 1'b0;
			end
		end else if (selftest_go && !ldr_go && !ldr_busy)
			st_start <= 1'b1;
	end

	// The test must own the bus from the moment it is asked for, not from the
	// moment it reports busy, or the CPU gets two clocks of bus access in
	// between. st_pending closes that window. It is set from power-up, so the
	// CPU stays in reset until the power-on test has run (or been cancelled).
	reg st_pending;
	initial st_pending = 1'b1;
	always @(posedge clk)
		if (rst_mem)        st_pending <= 1'b1;
		else if (st_start)  st_pending <= 1'b1;
		else if (st_busy)   st_pending <= 1'b0;
		else if (st_cancel) st_pending <= 1'b0;

	vax_selftest selftest (
		.clk      (clk),
		.rst      (rst_mem),
		.start    (st_start),
		.enable   (selftest_en),
		.sdram_sz (sdram_sz),

		.busy     (st_busy),
		.fail     (st_fail),
		.phase    (st_phase),
		.best_phase (st_best),

		.req      (st_req),
		.req_we   (st_we),
		.req_adr  (st_adr),
		.req_dat  (st_dat),
		.req_sel  (st_sel),
		.req_done (dma_done),
		.rd_dat   (dma_rdat),
		.rd_idx   (dma_ridx),
		.rd_stb   (dma_rstb),

		.tx_data  (st_char),
		.tx_stb   (st_stb),
		.tx_ready (term_ready)
	);

	// ------------------------------------------------------------ VAX
	// While the test is sweeping, it owns the phase; afterwards the core uses
	// the calibrated one unless the OSD forces a particular setting.
	wire [2:0] sel_m1  = rdphase_sel - 3'd1;
	wire [1:0] rdphase = st_busy      ? st_phase
	                   : |rdphase_sel ? sel_m1[1:0]
	                                  : st_best;

	wire tti_rx, tto_tx;

	vax_core #(.CLK_HZ(CLK_HZ), .CACHEIDX(CACHEIDX)) core (
		.clk        (clk),
		.rst_mem    (rst_mem),
		.rst_cpu    (rst_cpu),
		.mem_ready  (mem_ready),
		.rdphase    (rdphase),

		.dma_en     (dma_en),
		.dma_req    (dma_req),
		.dma_we     (dma_we),
		.dma_adr    (dma_adr),
		.dma_dat    (dma_dat),
		.dma_sel    (dma_sel),
		.dma_done   (dma_done),
		.dma_rdat   (dma_rdat),
		.dma_ridx   (dma_ridx),
		.dma_rstb   (dma_rstb),

		.tti_rx     (tti_rx),
		.tto_tx     (tto_tx),
		.halt_req   (halt_req),

		.stat_hit   (),
		.stat_miss  (),
		.cpu_halted (cpu_halted),

		.sd_a       (sd_a),
		.sd_ba      (sd_ba),
		.sd_ncs     (sd_ncs),
		.sd_nras    (sd_nras),
		.sd_ncas    (sd_ncas),
		.sd_nwe     (sd_nwe),
		.sd_dqml    (sd_dqml),
		.sd_dqmh    (sd_dqmh),
		.sd_dq_o    (sd_dq_o),
		.sd_dq_oe   (sd_dq_oe),
		.sd_dq_i    (sd_dq_i)
	);

	// --------------------------------------------- console output (TTO)
	wire [7:0] rx_data;
	wire       rx_valid;
	wire       bell;

	vax_uart_rx #(.CLKS(CPB + 1)) tto_rx (
		.clk   (clk),
		.rst   (rst_mem),
		.rxd   (tto_tx),
		.data  (rx_data),
		.valid (rx_valid)
	);

	// the self test writes to the screen before the CPU is released
	wire [7:0] term_data  = st_busy ? st_char : rx_data;
	wire       term_valid = st_busy ? st_stb  : rx_valid;

	vt_term term (
		.clk      (clk),
		.rst      (rst_term),
		.rx_data  (term_data),
		.rx_valid (term_valid),
		.rx_ready (term_ready),
		.color    (color),
		.bell     (bell),
		.ce_pix   (ce_pix),
		.hs       (hs),
		.vs       (vs),
		.hblank   (hblank),
		.vblank   (vblank),
		.r        (r),
		.g        (g),
		.b        (b)
	);

	// --------------------------------------------- MiSTer UART, 115200 8N1
	// console output -> host. The CPU can send much faster than 115200 baud
	// (the internal line takes 3.4 us per character, the UART 87 us), and
	// nothing slows it down, so this FIFO has to absorb whole bursts: 2 KB
	// covers a full screen and EVKAA's banner many times over. A longer
	// non-stop burst loses characters on the UART copy only; the screen
	// always gets everything.
	reg  [7:0]  ufo [0:2047];
	reg  [10:0] ufo_wp, ufo_rp;
	wire        ufo_empty = (ufo_wp == ufo_rp);
	wire        ufo_full  = (ufo_wp + 11'd1 == ufo_rp);
	wire        utx_busy;
	reg         utx_start;
	reg  [7:0]  utx_byte;

	initial begin
		ufo_wp = 11'd0;
		ufo_rp = 11'd0;
		utx_start = 1'b0;
	end

	always @(posedge clk) begin
		if (rst_mem)
			ufo_wp <= 11'd0;
		else if (term_valid && !ufo_full) begin
			ufo[ufo_wp] <= term_data;
			ufo_wp <= ufo_wp + 11'd1;
		end
	end

	always @(posedge clk) begin
		utx_start <= 1'b0;
		if (rst_mem)
			ufo_rp <= 11'd0;
		else if (!ufo_empty && !utx_busy && !utx_start) begin
			utx_byte  <= ufo[ufo_rp];
			utx_start <= 1'b1;
			ufo_rp    <= ufo_rp + 11'd1;
		end
	end

	vax_uart_tx #(.CLKS(UART_CPB + 1)) host_tx (
		.clk   (clk),
		.rst   (rst_mem),
		.data  (utx_byte),
		.start (utx_start),
		.busy  (utx_busy),
		.txd   (uart_txd)
	);

	// host -> console input
	wire [7:0] urx_data;
	wire       urx_valid;

	vax_uart_rx #(.CLKS(UART_CPB + 1)) host_rx (
		.clk   (clk),
		.rst   (rst_mem),
		.rxd   (uart_rxd),
		.data  (urx_data),
		.valid (urx_valid)
	);

	// --------------------------------------------- console input (TTI)
	wire [7:0] kbd_data;
	wire       kbd_valid;

	vax_kbd kbd (
		.clk       (clk),
		.rst       (rst_mem),
		.ps2_key   (ps2_key),
		.layout_es (kbd_es),
		.data      (kbd_data),
		.valid     (kbd_valid)
	);

	// autostart: after a download, type "FR" <8 hex digits> CR "G" into the
	// console monitor, which deposits the PC and starts the program
	localparam [31:0] AS_DELAY = CLK_HZ / 20;     // 50 ms before the first key
	localparam [31:0] AS_GAP   = CLK_HZ / 2000;   // 0.5 ms between keys

	reg        as_run;
	reg  [3:0] as_idx;
	reg [31:0] as_tmr;
	reg        as_valid;
	reg  [7:0] as_data;
	reg        ldr_go_d;

	initial begin
		as_run = 1'b0;
		as_valid = 1'b0;
		ldr_go_d = 1'b0;
	end

	function [7:0] hexd;
		input [3:0] v;
		hexd = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h37 + {4'd0, v});
	endfunction

	wire [31:0] start_addr = start_200 ? 32'h00000200 : {7'd0, base};

	always @(posedge clk) begin
		ldr_go_d <= ldr_go;
		as_valid <= 1'b0;
		if (rst_mem || rst_sys) begin
			as_run <= 1'b0;
		end else if (ldr_go_d && !ldr_go) begin  // download finished
			as_run <= autostart;
			as_idx <= 4'd0;
			as_tmr <= AS_DELAY;
		end else if (as_run && !rst_cpu) begin
			if (as_tmr != 32'd0)
				as_tmr <= as_tmr - 32'd1;
			else begin
				as_valid <= 1'b1;
				as_tmr   <= AS_GAP;
				as_idx   <= as_idx + 4'd1;
				case (as_idx)
				4'd0:  as_data <= "F";
				4'd1:  as_data <= "R";
				4'd2:  as_data <= hexd(start_addr[31:28]);
				4'd3:  as_data <= hexd(start_addr[27:24]);
				4'd4:  as_data <= hexd(start_addr[23:20]);
				4'd5:  as_data <= hexd(start_addr[19:16]);
				4'd6:  as_data <= hexd(start_addr[15:12]);
				4'd7:  as_data <= hexd(start_addr[11:8]);
				4'd8:  as_data <= hexd(start_addr[7:4]);
				4'd9:  as_data <= hexd(start_addr[3:0]);
				4'd10: as_data <= 8'h0D;
				default: begin
					as_data <= "G";
					as_run  <= 1'b0;
				end
				endcase
			end
		end
	end

	// transmit FIFO (keyboard + host UART + autostart) -> console line
	//
	// Characters are handed to the CPU no faster than one every 200 us. The
	// internal line itself runs at 3.4 us per character, and the r-vax
	// receiver holds a single character: without the gap, the three bytes of
	// a cursor or PF key would arrive faster than any VAX program can read
	// them, and the second would overwrite the first. 200 us is still 5000
	// characters a second - a real VAX console line ran at 9600 baud (960) -
	// and the FIFO is deep enough to take a paste from the 115200 baud UART.
	/* verilator lint_off WIDTHTRUNC */
	localparam [15:0] TTI_GAP = CLK_HZ / 5000;      // 200 us
	/* verilator lint_on WIDTHTRUNC */

	reg  [7:0] txf [0:255];
	reg  [7:0] txf_wp, txf_rp;
	wire       txf_empty = (txf_wp == txf_rp);
	wire       txf_full  = (txf_wp + 8'd1 == txf_rp);
	wire       tx_busy;
	wire       kbd_line;
	reg        tx_start;
	reg  [7:0] tx_byte;
	reg [15:0] tti_gap;

	initial begin
		txf_wp = 8'd0;
		txf_rp = 8'd0;
		tx_start = 1'b0;
		tti_gap = 16'd0;
	end

	// One-entry holding slot per source, so two characters arriving in the
	// same clock are both delivered instead of one being dropped.
	reg       kbd_p, urx_p;
	reg [7:0] kbd_h, urx_h;
	initial begin kbd_p = 1'b0; urx_p = 1'b0; end

	// Ctrl+P (10h) from the keyboard or the MiSTer UART is the VAX 8600
	// console's halt key: it halts the CPU at the end of the current
	// instruction and never reaches the program, unless the OSD says it
	// is a character. The OSD "Halt" entry does the same.
	wire kbd_ctrlp = kbd_valid && ctrlp_halt && kbd_data == 8'h10;
	wire urx_ctrlp = urx_valid && uart_console && ctrlp_halt && urx_data == 8'h10;
	initial halt_req = 1'b0;
	always @(posedge clk)
		halt_req <= kbd_ctrlp | urx_ctrlp | halt_osd;

	always @(posedge clk) begin
		if (rst_mem) begin
			txf_wp <= 8'd0;
			kbd_p  <= 1'b0;
			urx_p  <= 1'b0;
		end else begin
			if (kbd_valid && !kbd_ctrlp) begin kbd_h <= kbd_data; kbd_p <= 1'b1; end
			if (urx_valid && uart_console && !urx_ctrlp) begin urx_h <= urx_data; urx_p <= 1'b1; end

			if (as_valid && !txf_full) begin
				txf[txf_wp] <= as_data;
				txf_wp <= txf_wp + 8'd1;
			end else if (kbd_p && !txf_full) begin
				txf[txf_wp] <= kbd_h;
				txf_wp <= txf_wp + 8'd1;
				if (!(kbd_valid && !kbd_ctrlp)) kbd_p <= 1'b0;
			end else if (urx_p && !txf_full) begin
				txf[txf_wp] <= urx_h;
				txf_wp <= txf_wp + 8'd1;
				if (!(urx_valid && uart_console && !urx_ctrlp)) urx_p <= 1'b0;
			end
		end
	end

	always @(posedge clk) begin
		tx_start <= 1'b0;
		if (rst_mem) begin
			txf_rp  <= 8'd0;
			tti_gap <= 16'd0;
		end else if (tti_gap != 16'd0)
			tti_gap <= tti_gap - 16'd1;
		else if (!txf_empty && !tx_busy && !tx_start) begin
			tx_byte  <= txf[txf_rp];
			tx_start <= 1'b1;
			txf_rp   <= txf_rp + 8'd1;
			tti_gap  <= TTI_GAP;
		end
	end

	vax_uart_tx #(.CLKS(CPB + 1)) tti_tx (
		.clk   (clk),
		.rst   (rst_mem),
		.data  (tx_byte),
		.start (tx_start),
		.busy  (tx_busy),
		.txd   (kbd_line)
	);

	assign tti_rx = kbd_line;

	// ------------------------------------------------------------ beeper
	/* verilator lint_off WIDTHTRUNC */
	localparam [22:0] BEEP_LEN = CLK_HZ / 8;           // 125 ms
	localparam [15:0] BEEP_DIV = (CLK_HZ / 1760) - 1;  // 880 Hz
	/* verilator lint_on WIDTHTRUNC */

	reg [22:0] beep_len;
	reg [15:0] beep_div;
	reg        beep_sq;

	initial begin
		beep_len = 23'd0;
		beep_div = 16'd0;
		beep_sq  = 1'b0;
	end

	always @(posedge clk) begin
		if (bell)
			beep_len <= BEEP_LEN;
		else if (beep_len != 23'd0)
			beep_len <= beep_len - 23'd1;
		if (beep_div == BEEP_DIV) begin
			beep_div <= 16'd0;
			beep_sq  <= ~beep_sq;
		end else
			beep_div <= beep_div + 16'd1;
	end

	assign audio = (beep_len == 23'd0) ? 16'd0 : (beep_sq ? 16'h1800 : 16'hE800);

	// --------------------------------------------------------------- LEDs
	// USER: console activity.  DISK: CPU running (off while halted).
	reg [21:0] led_tmr;
	initial led_tmr = 22'd0;
	always @(posedge clk)
		if (ldr_go || term_valid || kbd_valid)
			led_tmr <= 22'h3FFFFF;
		else if (led_tmr != 22'd0)
			led_tmr <= led_tmr - 22'd1;

	assign led_user = (led_tmr != 22'd0);
	assign led_disk = ~cpu_halted & ~rst_cpu;

endmodule

`default_nettype wire

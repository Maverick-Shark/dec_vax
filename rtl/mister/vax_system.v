//============================================================================
//  vax_system.v - everything of the MiSTer core below the emu/hps_io layer:
//
//    vax_core   r-vax CPU + 32 MB SDRAM + SBI stubs
//    loader     HPS file download (OSD "Load program") into SDRAM
//    autostart  types "FR<addr><CR>G" into the console monitor after a load
//    vax_kbd    USB keyboard -> ASCII -> serial line into the console (TTI)
//    vt_term    console output (TTO) -> 80x30 on-screen terminal
//    UART       console also on the MiSTer UART (Linux /dev/ttyS1) if selected
//    beeper     BEL -> short tone on the audio output
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_system #(
	parameter CLK_HZ = 50000000,
	parameter CPB    = 434          // console bit period - 1 (= `CLKPERBIT)
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
	input             autostart,
	input       [1:0] color,
	input             kbd_es,
	input             uart_console,

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
	output            led
);

	// ------------------------------------------------------------ loader
	wire        ldr_go = ioctl_download && (ioctl_index[5:0] == 6'd1);
	reg         ldr_stb, ldr_busy;
	reg  [22:0] ldr_adr;
	reg   [3:0] ldr_sel;
	reg  [31:0] ldr_dat;
	wire        ldr_ack;
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

	always @(posedge clk) begin
		if (ldr_stb && ldr_ack) begin
			ldr_stb  <= 1'b0;
			ldr_busy <= 1'b0;
		end
		if (ldr_go && ioctl_wr && !ldr_busy) begin
			ldr_adr  <= ldr_byte_addr[24:2];
			ldr_sel  <= 4'b0001 << ldr_byte_addr[1:0];
			ldr_dat  <= {4{ioctl_dout}};
			ldr_stb  <= 1'b1;
			ldr_busy <= 1'b1;
		end
	end

	// keep the loader on the bus until its last write is done
	reg ldr_active;
	initial ldr_active = 1'b0;
	always @(posedge clk)
		ldr_active <= ldr_go | ldr_busy;

	// ------------------------------------------------------------ resets
	wire mem_ready;
	reg  rst_cpu;
	initial rst_cpu = 1'b1;
	always @(posedge clk)
		rst_cpu <= rst_mem | rst_sys | ~mem_ready | ldr_go | ldr_active;

	reg  rst_term;
	initial rst_term = 1'b1;
	always @(posedge clk)
		rst_term <= rst_mem | rst_sys;

	// ------------------------------------------------------------ VAX
	wire tti_rx, tto_tx;

	vax_core #(.CLK_HZ(CLK_HZ)) core (
		.clk        (clk),
		.rst_mem    (rst_mem),
		.rst_cpu    (rst_cpu),
		.mem_ready  (mem_ready),

		.ldr_active (ldr_active),
		.ldr_stb    (ldr_stb),
		.ldr_adr    (ldr_adr),
		.ldr_sel    (ldr_sel),
		.ldr_dat    (ldr_dat),
		.ldr_ack    (ldr_ack),

		.tti_rx     (tti_rx),
		.tto_tx     (tto_tx),

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

	// ------------------------------------------------------------ console output
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

	vt_term term (
		.clk      (clk),
		.rst      (rst_term),
		.rx_data  (rx_data),
		.rx_valid (rx_valid),
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

	assign uart_txd = tto_tx;

	// ------------------------------------------------------------ console input
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

	// autostart: after a download, wait for the monitor prompt and type
	// "FR" <8 hex digits of the load address> CR "G"  (deposit PC, go)
	localparam [31:0] AS_DELAY = CLK_HZ / 20;     // 50 ms before the first key
	localparam [31:0] AS_GAP   = CLK_HZ / 500;    // 2 ms between keys

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

	wire [31:0] start_addr = {7'd0, base};

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

	// transmit FIFO (keyboard + autostart) -> serial line into the CPU
	reg  [7:0] txf [0:31];
	reg  [4:0] txf_wp, txf_rp;
	wire       txf_empty = (txf_wp == txf_rp);
	wire       txf_full  = (txf_wp + 5'd1 == txf_rp);
	wire       tx_busy;
	wire       kbd_line;
	reg        tx_start;

	initial begin
		txf_wp = 5'd0;
		txf_rp = 5'd0;
		tx_start = 1'b0;
	end

	always @(posedge clk) begin
		if (rst_mem) begin
			txf_wp <= 5'd0;
		end else if (as_valid && !txf_full) begin
			txf[txf_wp] <= as_data;
			txf_wp <= txf_wp + 5'd1;
		end else if (kbd_valid && !txf_full) begin
			txf[txf_wp] <= kbd_data;
			txf_wp <= txf_wp + 5'd1;
		end
	end

	always @(posedge clk) begin
		tx_start <= 1'b0;
		if (rst_mem)
			txf_rp <= 5'd0;
		else if (!txf_empty && !tx_busy && !tx_start) begin
			tx_start <= 1'b1;
			txf_rp   <= txf_rp + 5'd1;
		end
	end

	reg [7:0] tx_byte;
	always @(posedge clk)
		if (!txf_empty && !tx_busy && !tx_start)
			tx_byte <= txf[txf_rp];

	vax_uart_tx #(.CLKS(CPB + 1)) tti_tx (
		.clk   (clk),
		.rst   (rst_mem),
		.data  (tx_byte),
		.start (tx_start),
		.busy  (tx_busy),
		.txd   (kbd_line)
	);

	reg [2:0] uart_rx_s;
	initial uart_rx_s = 3'b111;
	always @(posedge clk)
		uart_rx_s <= {uart_rx_s[1:0], uart_rxd};

	// both sources idle high; the UART is only listened to when selected
	assign tti_rx = kbd_line & (uart_console ? uart_rx_s[2] : 1'b1);

	// ------------------------------------------------------------ beeper
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
			beep_len <= CLK_HZ / 8;                  // 125 ms
		else if (beep_len != 23'd0)
			beep_len <= beep_len - 23'd1;
		if (beep_div == CLK_HZ / 1760 - 1) begin  // 880 Hz square wave
			beep_div <= 16'd0;
			beep_sq  <= ~beep_sq;
		end else
			beep_div <= beep_div + 16'd1;
	end

	assign audio = (beep_len == 23'd0) ? 16'd0 : (beep_sq ? 16'h1800 : 16'hE800);

	// ------------------------------------------------------------ activity LED
	reg [21:0] led_tmr;
	initial led_tmr = 22'd0;
	always @(posedge clk)
		if (ldr_go || rx_valid || kbd_valid)
			led_tmr <= 22'h3FFFFF;
		else if (led_tmr != 22'd0)
			led_tmr <= led_tmr - 22'd1;
	assign led = (led_tmr != 22'd0);

endmodule

`default_nettype wire

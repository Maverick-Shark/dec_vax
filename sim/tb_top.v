// tb_top.v - Verilator top for the MiSTer port: vax_system + SDRAM model.
// The C++ driver (tb.cpp) plays the role of hps_io: clock, resets,
// ioctl download, ps2_key events; it also captures the video output.

`default_nettype none

module tb_top (
	input         clk,
	input         rst_mem,
	input         rst_sys,

	input         ioctl_download,
	input  [15:0] ioctl_index,
	input         ioctl_wr,
	input  [26:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	output        ioctl_wait,

	input   [1:0] load_base,
	input         autostart,
	input   [1:0] color,
	input         kbd_es,
	input  [10:0] ps2_key,

	output        ce_pix,
	output        hs,
	output        vs,
	output        hblank,
	output        vblank,
	output  [7:0] r,
	output  [7:0] g,
	output  [7:0] b,
	output [15:0] audio,
	output        led,
	output        uart_txd
);

	wire [12:0] sd_a;
	wire  [1:0] sd_ba;
	wire        sd_ncs, sd_nras, sd_ncas, sd_nwe, sd_dqml, sd_dqmh;
	wire [15:0] sd_dq_o, m_dq;
	wire        sd_dq_oe, m_drive;

	wire [15:0] dq_bus = m_drive ? m_dq : sd_dq_oe ? sd_dq_o : 16'h0000;

	vax_system #(.CLK_HZ(50000000), .CPB(`CLKPERBIT)) sys (
		.clk(clk), .rst_mem(rst_mem), .rst_sys(rst_sys),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),
		.load_base(load_base), .autostart(autostart), .color(color),
		.kbd_es(kbd_es), .uart_console(1'b0),
		.ps2_key(ps2_key), .uart_rxd(1'b1), .uart_txd(uart_txd),
		.sd_a(sd_a), .sd_ba(sd_ba), .sd_ncs(sd_ncs), .sd_nras(sd_nras),
		.sd_ncas(sd_ncas), .sd_nwe(sd_nwe), .sd_dqml(sd_dqml), .sd_dqmh(sd_dqmh),
		.sd_dq_o(sd_dq_o), .sd_dq_oe(sd_dq_oe), .sd_dq_i(dq_bus),
		.ce_pix(ce_pix), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank),
		.r(r), .g(g), .b(b), .audio(audio), .led(led)
	);

	sdram_model sdram (
		.clk(clk), .a(sd_a), .ba(sd_ba), .ncs(sd_ncs), .nras(sd_nras),
		.ncas(sd_ncas), .nwe(sd_nwe), .dqml(sd_dqml), .dqmh(sd_dqmh),
		.dq_in(sd_dq_o), .dq_out(m_dq), .dq_drive(m_drive)
	);

	// bus contention check
	always @(negedge clk)
		if (m_drive && sd_dq_oe)
			$display("tb_top: SDRAM DQ bus contention");

endmodule

`default_nettype wire

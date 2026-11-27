// tb_top.v - Verilator top for the MiSTer port: vax_system + SDRAM model.
// The C++ driver (tb.cpp) plays the role of hps_io: clock, resets,
// ioctl download, ps2_key events; it also captures the video output.

`default_nettype none

module tb_top #(
	parameter integer CL_SKEW = 0,
	parameter integer TSCALE  = 16    // disk mechanical times / 16
) (
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
	input         start_200,
	input         autostart,
	input         boot_unit,
	input  [31:0] boot_r5,
	input   [1:0] color,
	input         kbd_es,
	input         selftest_en,
	input         selftest_go,
	input   [2:0] rdphase_sel,
	input   [1:0] diag,
	input  [15:0] sdram_sz,
	input  [64:0] rtc,
	input  [10:0] ps2_key,
	input         uart_rxd,

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
	output        led_disk,
	output        uart_txd,

	// disk images, served by tb.cpp as the HPS would
	output [31:0] dk_lba0,
	output [31:0] dk_lba1,
	output  [1:0] dk_rd,
	output  [1:0] dk_wr,
	input   [1:0] dk_ack,
	input   [8:0] dk_buff_addr,
	input   [7:0] dk_buff_dout,
	input         dk_buff_wr,
	output  [7:0] dk_buff_din0,
	output  [7:0] dk_buff_din1,
	input   [1:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size,
	output        disk_active
);

	wire [12:0] sd_a;
	wire  [1:0] sd_ba;
	wire        sd_ncs, sd_nras, sd_ncas, sd_nwe, sd_dqml, sd_dqmh;
	wire [15:0] sd_dq_o, m_dq;
	wire        sd_dq_oe, m_drive;

	wire [15:0] dq_bus = m_drive ? m_dq : sd_dq_oe ? sd_dq_o : 16'h0000;

	vax_system #(.CLK_HZ(50000000), .CPB(`CLKPERBIT), .UART_CPB(434),
	             .CACHEIDX(`CACHEIDX), .TSCALE(TSCALE)) sys (
		.clk(clk), .rst_mem(rst_mem), .rst_sys(rst_sys),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),
		.load_base(load_base), .start_200(start_200), .autostart(autostart),
		.boot_unit(boot_unit), .boot_r5(boot_r5),
		.color(color), .kbd_es(kbd_es), .uart_console(1'b1),
		.ctrlp_halt(1'b1), .halt_osd(1'b0),
		.selftest_en(selftest_en), .selftest_go(selftest_go),
		.rdphase_sel(rdphase_sel), .diag(diag), .sdram_sz(sdram_sz), .rtc(rtc),
		.ps2_key(ps2_key), .uart_rxd(uart_rxd), .uart_txd(uart_txd),
		.sd_a(sd_a), .sd_ba(sd_ba), .sd_ncs(sd_ncs), .sd_nras(sd_nras),
		.sd_ncas(sd_ncas), .sd_nwe(sd_nwe), .sd_dqml(sd_dqml), .sd_dqmh(sd_dqmh),
		.sd_dq_o(sd_dq_o), .sd_dq_oe(sd_dq_oe), .sd_dq_i(dq_bus),
		.ce_pix(ce_pix), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank),
		.r(r), .g(g), .b(b), .audio(audio),
		.led_user(led), .led_disk(led_disk),
		.dk_lba0(dk_lba0), .dk_lba1(dk_lba1), .dk_rd(dk_rd), .dk_wr(dk_wr),
		.dk_ack(dk_ack), .dk_buff_addr(dk_buff_addr),
		.dk_buff_dout(dk_buff_dout), .dk_buff_wr(dk_buff_wr),
		.dk_buff_din0(dk_buff_din0), .dk_buff_din1(dk_buff_din1),
		.img_mounted(img_mounted), .img_readonly(img_readonly),
		.img_size(img_size), .disk_active(disk_active)
	);

	// DQM_ON_A models the modules (128 MB among them) whose chips take their
	// byte masks from A11/A12 instead of the DQML/DQMH pins
`ifdef DQM_ON_A
	wire m_dqml = sd_a[11], m_dqmh = sd_a[12];
`else
	wire m_dqml = sd_dqml, m_dqmh = sd_dqmh;
`endif
	sdram_model #(.CL_SKEW(CL_SKEW)) sdram (
		.clk(clk), .a(sd_a), .ba(sd_ba), .ncs(sd_ncs), .nras(sd_nras),
		.ncas(sd_ncas), .nwe(sd_nwe), .dqml(m_dqml), .dqmh(m_dqmh),
		.dq_in(sd_dq_o), .dq_oe(sd_dq_oe), .dq_out(m_dq), .dq_drive(m_drive)
	);

	// bus contention check
	always @(negedge clk)
		if (m_drive && sd_dq_oe)
			$display("tb_top: SDRAM DQ bus contention");

endmodule

`default_nettype wire

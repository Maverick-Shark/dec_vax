//============================================================================
//
//  DEC VAX (r-vax) for MiSTer - emu top level.
//
//  r-vax VAX CPU (c) 2021 Anders Magnusson, BSD 2-Clause.
//  MiSTer glue based on Template_MiSTer.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

// Status bits
//  0      reset
//  2:1    load address
//  3      autostart (0 = yes)
//  5:4    text colour
//  6      keyboard layout
//  7      console also on UART (/dev/ttyS1)
//  122:121 aspect ratio

`include "build_id.v"
localparam CONF_STR = {
	"DEC_VAX;;",
	"-;",
	"F1,BINEXE,Load Program;",
	"O[2:1],Load Address,0x00001000,0x00000000,0x00000200,0x00010000;",
	"O[3],Autostart,Yes,No;",
	"-;",
	"O[5:4],Text Color,Green,Amber,White;",
	"O[6],Keyboard,US,ES;",
	"O[7],UART Console,Off,On;",
	"O[122:121],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;      // 50 MHz
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

// power-up reset for the SDRAM controller: PLL lock plus a few cycles
reg [7:0] rst_cnt = 0;
reg       rst_mem = 1;
always @(posedge clk_sys) begin
	if (!pll_locked) begin
		rst_cnt <= 0;
		rst_mem <= 1;
	end else if (rst_cnt != 8'hFF) begin
		rst_cnt <= rst_cnt + 1'd1;
	end else
		rst_mem <= 0;
end

reg rst_sys = 1;
always @(posedge clk_sys)
	rst_sys <= RESET | status[0] | buttons[1];

///////////////////////   SDRAM   ///////////////////////////////

wire [15:0] sd_dq_o;
wire        sd_dq_oe;

assign SDRAM_DQ  = sd_dq_oe ? sd_dq_o : 16'hZZZZ;
assign SDRAM_CKE = 1'b1;

// SDRAM clock = inverted clk_sys, forwarded through a DDR output register
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_sys),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

///////////////////////   VAX   ///////////////////////////////

wire        ce_pix, hs, vs, hblank, vblank;
wire  [7:0] vr, vg, vb;
wire [15:0] audio;
wire        led;

vax_system #(.CLK_HZ(50000000), .CPB(`CLKPERBIT)) vax
(
	.clk            (clk_sys),
	.rst_mem        (rst_mem),
	.rst_sys        (rst_sys),

	.ioctl_download (ioctl_download),
	.ioctl_index    (ioctl_index),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_wait     (ioctl_wait),

	.load_base      (status[2:1]),
	.autostart      (~status[3]),
	.color          (status[5:4]),
	.kbd_es         (status[6]),
	.uart_console   (status[7]),

	.ps2_key        (ps2_key),
	.uart_rxd       (UART_RXD),
	.uart_txd       (UART_TXD),

	.sd_a           (SDRAM_A),
	.sd_ba          (SDRAM_BA),
	.sd_ncs         (SDRAM_nCS),
	.sd_nras        (SDRAM_nRAS),
	.sd_ncas        (SDRAM_nCAS),
	.sd_nwe         (SDRAM_nWE),
	.sd_dqml        (SDRAM_DQML),
	.sd_dqmh        (SDRAM_DQMH),
	.sd_dq_o        (sd_dq_o),
	.sd_dq_oe       (sd_dq_oe),
	.sd_dq_i        (SDRAM_DQ),

	.ce_pix         (ce_pix),
	.hs             (hs),
	.vs             (vs),
	.hblank         (hblank),
	.vblank         (vblank),
	.r              (vr),
	.g              (vg),
	.b              (vb),

	.audio          (audio),
	.led            (led)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;

assign VGA_DE = ~(hblank | vblank);
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_R  = vr;
assign VGA_G  = vg;
assign VGA_B  = vb;

assign AUDIO_S = 1;
assign AUDIO_L = audio;
assign AUDIO_R = audio;

assign LED_USER = led;

endmodule

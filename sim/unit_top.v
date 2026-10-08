// unit_top.v - unit test top: on-screen terminal and keyboard translator.
`default_nettype none
module unit_top (
	input         clk,
	input         rst,
	input   [7:0] rx_data,
	input         rx_valid,
	input  [10:0] ps2_key,
	input         kbd_es,
	output  [7:0] kbd_data,
	output        kbd_valid,
	output        bell
);
	wire ce, hs, vs, hb, vb;
	wire [7:0] r, g, b;

	vt_term term (
		.clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
		.color(2'd0), .bell(bell), .ce_pix(ce), .hs(hs), .vs(vs),
		.hblank(hb), .vblank(vb), .r(r), .g(g), .b(b)
	);

	vax_kbd kbd (
		.clk(clk), .rst(rst), .ps2_key(ps2_key), .layout_es(kbd_es),
		.data(kbd_data), .valid(kbd_valid)
	);
endmodule
`default_nettype wire

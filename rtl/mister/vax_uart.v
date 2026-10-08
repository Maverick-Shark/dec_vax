//============================================================================
//  vax_uart.v - minimal 8N1 UART transmitter and receiver.
//
//  Used to bridge the r-vax console serial lines (tti_rx / tto_tx) to the
//  on-screen terminal and the keyboard. CLKS is the bit period in clocks;
//  r-vax constx/consrx use a period of `CLKPERBIT + 1 clocks.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_uart_tx #(
	parameter CLKS = 435
) (
	input            clk,
	input            rst,
	input      [7:0] data,
	input            start,      // ignored while busy
	output           busy,
	output           txd
);

	reg  [9:0]  shreg;          // {stop, data[7:0], start}, LSB first
	reg  [3:0]  nbits;
	reg  [15:0] cnt;
	reg         line;

	initial begin
		nbits = 4'd0;
		line  = 1'b1;
		cnt   = 16'd0;
	end

	assign busy = (nbits != 4'd0);
	assign txd  = line;

	always @(posedge clk) begin
		if (rst) begin
			nbits <= 4'd0;
			line  <= 1'b1;
		end else if (nbits == 4'd0) begin
			line <= 1'b1;
			if (start) begin
				shreg <= {1'b1, data, 1'b0};
				nbits <= 4'd10;
				cnt   <= 16'd0;
			end
		end else begin
			line <= shreg[0];
			if (cnt == CLKS - 1) begin
				cnt   <= 16'd0;
				shreg <= {1'b1, shreg[9:1]};
				nbits <= nbits - 4'd1;
			end else
				cnt <= cnt + 16'd1;
		end
	end

endmodule


module vax_uart_rx #(
	parameter CLKS = 435
) (
	input            clk,
	input            rst,
	input            rxd,
	output reg [7:0] data,
	output reg       valid       // one clock pulse per received byte
);

	reg  [2:0]  sync;
	reg  [15:0] cnt;
	reg  [3:0]  nbits;
	reg  [8:0]  shreg;
	reg         active;

	initial begin
		sync   = 3'b111;
		active = 1'b0;
		valid  = 1'b0;
	end

	wire rx = sync[2];

	always @(posedge clk) begin
		sync  <= {sync[1:0], rxd};
		valid <= 1'b0;

		if (rst) begin
			active <= 1'b0;
		end else if (!active) begin
			if (!rx) begin                    // start bit edge
				active <= 1'b1;
				cnt    <= CLKS / 2;
				nbits  <= 4'd0;
			end
		end else begin
			if (cnt == CLKS - 1) begin
				cnt <= 16'd0;
				if (nbits == 4'd0 && rx) begin
					active <= 1'b0;           // glitch, not a start bit
				end else if (nbits == 4'd9) begin
					active <= 1'b0;
					if (rx) begin             // valid stop bit
						data  <= shreg[8:1];
						valid <= 1'b1;
					end
				end else begin
					shreg <= {rx, shreg[8:1]};
					nbits <= nbits + 4'd1;
				end
			end else
				cnt <= cnt + 16'd1;
		end
	end

endmodule

`default_nettype wire

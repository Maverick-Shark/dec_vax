// sdram_model.v - behavioural SDR SDRAM for simulation only.
//
// 4 banks x 8192 rows x 512 columns x 16 bit (the 32 MB window this core uses).
// The model is clocked by the real SDRAM clock (clk inverted, as the DDR output
// register in the top level produces it), so command sampling happens half a
// system clock after the controller drives the pins, exactly as on hardware.
//
// READ DATA TIMING - modelled on what the board really does, not on a diagram.
// With CAS latency 2 the word for a READ sampled at chip edge E0 starts to
// appear tAC (about 6 ns) after edge E1 and is held until tOH (about 3 ns)
// after edge E2. Add the 4-6 ns it takes the forwarded clock to reach the chip
// and the data window, seen from inside the FPGA, is roughly
//     E1 + 11 ns  ..  E2 + 8 ns
// At 50 MHz the chip edges are the clk FALLING edges, 20 ns apart, so:
//   - the falling edge at E2 sits in the middle of the window   -> valid
//   - the rising edge before it (E1 + 10 ns) is at its very start -> unsafe
//   - the rising edge after it (E2 + 10 ns) is past its end       -> unsafe
// The model therefore presents the word only to samplers on the falling edge.
// A register sampling on the rising edge sees the bitwise complement, which
// stands for "the bus is changing" and makes such a design fail loudly here
// instead of intermittently on the board. (Version 2 of the controller sampled
// on the rising edge; an older version of this model let it pass, and the
// hardware did not. Version 1 and the current one sample on the falling edge
// and work on the board.)
//
// Checks performed: commands to an unopened row, reads/writes outside an open
// row, burst wrap, DQ contention and refresh interval.

`default_nettype none

module sdram_model #(
	parameter CHECK_REFRESH = 1,
	// CL_SKEW shifts the data window by a whole SDRAM clock, to check that
	// the controller's read-phase calibration finds the right setting:
	//   0 = nominal, -1 = one SDRAM clock early, +1 = one late.
	parameter integer CL_SKEW = 0
) (
	input             clk,          // system clock; SDRAM clock is its inverse
	input      [12:0] a,
	input       [1:0] ba,
	input             ncs,
	input             nras,
	input             ncas,
	input             nwe,
	input             dqml,
	input             dqmh,
	input      [15:0] dq_in,
	input             dq_oe,        // controller is driving the bus
	output     [15:0] dq_out,
	output            dq_drive
);

	localparam BL = 2;

	reg [15:0] mem [0:(1<<24)-1];
	reg [12:0] row [0:3];
	reg        rowopen [0:3];
	reg        initialised;
	reg [12:0] mode;

	// read pipeline, advanced on every chip edge. After edge E_j has been
	// processed, p1 holds the word whose window is centred on E_(j+1)
	// (nominal CL2), p2 the one for E_j (early) and p0 for E_(j+2) (late).
	reg        p0_v, p1_v, p2_v;
	reg [23:0] p0_a, p1_a, p2_a;
	reg  [3:0] bcnt;
	reg [23:0] bcol;
	reg        bactive;
	reg  [1:0] bbank;
	reg        w2;                 // second word of a burst-of-2 write due
	reg [23:0] w2_a;
	reg [15:0] dq_word;            // output stage, see the end of the file
	reg        dq_wv;
	reg        ph_p, ph_n;

	wire sdram_clk = ~clk;
	wire [3:0] cmd = {ncs, nras, ncas, nwe};

	integer i;
	initial begin
		for (i = 0; i < (1<<24); i = i + 1) mem[i] = 16'h0000;
		for (i = 0; i < 4; i = i + 1) begin row[i] = 0; rowopen[i] = 0; end
		p0_v = 0; p1_v = 0; p2_v = 0; bactive = 0;
		dq_word = 16'h0000; dq_wv = 1'b0; ph_p = 1'b0; ph_n = 1'b0;
		w2 = 0;
		initialised = 0; mode = 0;
	end

	always @(posedge sdram_clk) begin : model
		reg [23:0] addr;

		// ---------------- read data pipeline
		p0_v <= p1_v; p0_a <= p1_a;
		p1_v <= p2_v; p1_a <= p2_a;
		p2_v <= 1'b0;

		// continue a read burst
		if (bactive) begin
			bcnt <= bcnt + 4'd1;
			// sequential burst wraps inside the aligned BL block
			p2_a <= {bcol[23:1], (bcol[0] + bcnt[0] + 1'b1)};
			p2_v <= 1'b1;
			if (bcnt == BL - 2) bactive <= 1'b0;
		end

		// second word of a burst-of-2 write: sampled on the edge after WRITE
		if (w2) begin
			if (!dq_oe) $display("SDRAM model: second write word with DQ not driven");
			if (!dqml) mem[w2_a][7:0]  <= dq_in[7:0];
			if (!dqmh) mem[w2_a][15:8] <= dq_in[15:8];
		end
		w2 <= 1'b0;

		addr = {row[ba], ba, a[8:0]};

		case (cmd)
		4'b0011: begin                                    // ACTIVE
			row[ba]     <= a;
			rowopen[ba] <= 1'b1;
		end

		4'b0101: begin                                    // READ
			if (!initialised) $display("SDRAM model: READ before mode register set");
			if (!rowopen[ba]) $display("SDRAM model: READ with no open row, bank %0d", ba);
			if (a[0] != 1'b0)
				$display("SDRAM model: odd burst start, col %0d (burst would wrap)", a[8:0]);
			if (dq_oe) $display("SDRAM model: controller drives DQ during READ");
			p2_v    <= 1'b1;
			p2_a    <= addr;
			bcol    <= addr;
			bcnt    <= 4'd0;
			bbank   <= ba;
			bactive <= 1'b1;
			if (a[10]) rowopen[ba] <= 1'b0;               // auto precharge
		end

		4'b0100: begin                                    // WRITE
			if (!initialised) $display("SDRAM model: WRITE before mode register set");
			if (!rowopen[ba]) $display("SDRAM model: WRITE with no open row, bank %0d", ba);
			if (!dq_oe) $display("SDRAM model: WRITE while controller is not driving DQ");
			if (!dqml) mem[addr][7:0]  <= dq_in[7:0];
			if (!dqmh) mem[addr][15:8] <= dq_in[15:8];
			// mode register A9 = 0: writes use the programmed burst length
			// too, so a burst of 2 takes the second word on the next edge
			if (!mode[9] && mode[2:0] == 3'b001) begin
				w2   <= 1'b1;
				w2_a <= addr | 24'd1;
			end
			if (a[10]) rowopen[ba] <= 1'b0;               // auto precharge
		end

		4'b0010: begin                                    // PRECHARGE
			if (a[10]) begin
				for (i = 0; i < 4; i = i + 1) rowopen[i] <= 1'b0;
			end else
				rowopen[ba] <= 1'b0;
		end

		4'b0001: begin                                    // AUTO REFRESH
			for (i = 0; i < 4; i = i + 1)
				if (rowopen[i]) $display("SDRAM model: REFRESH with bank %0d open", i);
		end

		4'b0000: begin                                    // MODE REGISTER SET
			mode        <= a;
			initialised <= 1'b1;

			if (a[2:0] != 3'b001) $display("SDRAM model: burst length is not 2");
			if (a[6:4] != 3'b010) $display("SDRAM model: CAS latency is not 2");
		end
		default: ;
		endcase
	end

	// ---------------- what the FPGA sees on DQ
	// dq_word is loaded on the clk rising edge (between two chip edges) with
	// the word whose window is centred on the next chip edge. ph is 1 from a
	// rising edge to the following falling edge, i.e. it is 1 exactly when a
	// falling-edge sampler looks and 0 when a rising-edge sampler looks.
	wire       ph = ph_p ^ ph_n;

	always @(posedge clk) begin
		ph_p <= ~ph_n;                 // ph = 1 after every rising edge
		if (CL_SKEW < 0)      begin dq_wv <= p2_v; dq_word <= mem[p2_a]; end
		else if (CL_SKEW > 0) begin dq_wv <= p0_v; dq_word <= mem[p0_a]; end
		else                  begin dq_wv <= p1_v; dq_word <= mem[p1_a]; end
	end

	always @(negedge clk)
		ph_n <= ph_p;                  // ph = 0 after every falling edge

	assign dq_drive = dq_wv;
	assign dq_out   = ph ? dq_word : ~dq_word;

	// ---------------- refresh interval check (8192 rows every 64 ms)
	integer    nref;
	reg [31:0] ticks;
	reg        refwarn;
	initial begin nref = 0; ticks = 0; refwarn = 0; end

	always @(posedge sdram_clk) begin
		ticks <= ticks + 32'd1;
		if (cmd == 4'b0001) nref = nref + 1;
		// 64 ms at 50 MHz is 3.2 M clocks; expect at least 8192 refreshes
		if (ticks == 32'd3200000) begin
			if (CHECK_REFRESH && nref < 8192 && !refwarn) begin
				$display("SDRAM model: only %0d refreshes in 64 ms (need 8192)", nref);
				refwarn <= 1'b1;
			end
			ticks <= 32'd0;
			nref = 0;
		end
	end

endmodule

`default_nettype wire

// sdram_model.v - behavioural SDR SDRAM for simulation only.
// 4 banks x 8192 rows x 512 columns x 16 bit (32 MB), CL2, BL2 (sequential).
// The SDRAM clock is the inverted system clock, so the model works on the
// falling edge of clk; commands registered by the controller on the rising
// edge are sampled here half a cycle later.  Read data is driven one SDRAM
// clock after the READ (CL-1) and held until the next edge (CL), which is
// when the controller captures it.

`default_nettype none

module sdram_model (
	input             clk,
	input      [12:0] a,
	input       [1:0] ba,
	input             ncs,
	input             nras,
	input             ncas,
	input             nwe,
	input             dqml,
	input             dqmh,
	input      [15:0] dq_in,
	output reg [15:0] dq_out,
	output reg        dq_drive
);

	reg [15:0] mem [0:(1<<24)-1];
	reg [12:0] row [0:3];

	reg        p1_v, p2_v;
	reg [23:0] p1_a, p2_a;
	reg        w2;
	reg [23:0] w2_a;

	wire [3:0]  cmd   = {ncs, nras, ncas, nwe};
	wire [23:0] caddr = {row[ba], ba, a[8:0]};

	integer i;
	initial begin
		for (i = 0; i < (1<<24); i = i + 1) mem[i] = 16'h0000;
		p1_v = 0; p2_v = 0; w2 = 0; dq_drive = 0; dq_out = 16'h0000;
	end

	always @(negedge clk) begin
		// read pipeline
		if (p1_v) begin
			dq_out   <= mem[p1_a];
			dq_drive <= 1'b1;
		end else begin
			dq_drive <= 1'b0;
			dq_out   <= 16'hXXXX;
		end
		p1_v <= p2_v; p1_a <= p2_a;
		p2_v <= 1'b0;

		// second word of a write burst
		if (w2) begin
			if (!dqml) mem[w2_a][7:0]  <= dq_in[7:0];
			if (!dqmh) mem[w2_a][15:8] <= dq_in[15:8];
		end
		w2 <= 1'b0;

		case (cmd)
		4'b0011: row[ba] <= a;                                  // ACTIVE
		4'b0101: begin                                          // READ
			if (a[0]) $display("SDRAM model: odd column read");
			p1_v <= 1'b1; p1_a <= caddr;
			p2_v <= 1'b1; p2_a <= caddr | 24'd1;
		end
		4'b0100: begin                                          // WRITE
			if (!dqml) mem[caddr][7:0]  <= dq_in[7:0];
			if (!dqmh) mem[caddr][15:8] <= dq_in[15:8];
			w2 <= 1'b1; w2_a <= caddr | 24'd1;
		end
		default: ;
		endcase
	end

endmodule

`default_nettype wire

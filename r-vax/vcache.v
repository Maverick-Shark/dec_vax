
/*
 * simple virtual cache, which also converts unaligned accesses to aligned.
 */

`define	IDLE		0
`define	FASTPATH	1
`define	SLOWRMEM	2
`define	SLOWRMEM2	3
`define	SLOWRMEM3	4
`define	RETWD		5
`define	SETWD		6
`define	WRHIGH		7
`define	WRHIGH2		8
`define	WRHIGH3		9

module vcache(
	input		clk,
	input		rst,

	input [31:0]	in_addr,
	input [31:0]	in_wdata,
	input		in_write,
	input		in_stb,
	input [1:0]	in_sz,		// 0 == byte, 1 == word, 3 == long
	output reg [31:0] in_rdata,
	output reg	in_ack,

	output reg [21:0] ut_addr,
	output reg [31:0] ut_wdata,
	output reg 	ut_write,
	output reg 	ut_stb,
	input [31:0]	ut_rdata,
	input		ut_ack
);
	reg [63:0]	quad, merged_write_word;
	reg [3:0]	state;
	reg		needtwo;
	reg [31:0]	shifted_bytes;
	reg [21:0]	caddr;
	reg [1:0]	coff, csz;

	/* read/write cases when we need two words */
	always @* begin
		casez ({csz, coff })
		4'b01_11: needtwo = 1; // word on addr 3
		4'b11_01: needtwo = 1;
		4'b11_1?: needtwo = 1;
		default: needtwo = 0;
		endcase
	end

	/* merged longwords when writing unaligned/partial words */
	always @* begin
		casez ({csz, coff })
		/* byte size first, addr off 0-3 */
		4'b00_00: merged_write_word = { quad[63:8], in_wdata[7:0] };
		4'b00_01: merged_write_word = { quad[63:16], in_wdata[7:0], quad[7:0] };
		4'b00_10: merged_write_word = { quad[63:24], in_wdata[7:0], quad[15:0] };
		4'b00_11: merged_write_word = { quad[63:32], in_wdata[7:0], quad[23:0] };

		/* word size */
		4'b01_00: merged_write_word = { quad[63:16], in_wdata[15:0] };
		4'b01_01: merged_write_word = { quad[63:24], in_wdata[15:0], quad[7:0] };
		4'b01_10: merged_write_word = { quad[63:32], in_wdata[15:0], quad[15:0] };
		4'b01_11: merged_write_word = { quad[63:40], in_wdata[15:0], quad[23:0] };

		4'b11_00: merged_write_word = { quad[63:32], in_wdata };
		4'b11_01: merged_write_word = { quad[63:40], in_wdata, quad[7:0] };
		4'b11_10: merged_write_word = { quad[63:48], in_wdata, quad[15:0] };
		4'b11_11: merged_write_word = { quad[63:56], in_wdata, quad[23:0] };
		default: merged_write_word = 0; /* ILLEGAL */
		endcase
	end

	/* Shift quad word left */
	always @* begin
		case (coff)
		2'b00: shifted_bytes = quad[31:0];
		2'b01: shifted_bytes = quad[39:8];
		2'b10: shifted_bytes = quad[47:16];
		2'b11: shifted_bytes = quad[55:24];
		endcase
	end

	always @(posedge clk) begin
		if (rst) begin
			state <= `IDLE;
			in_ack <= 0;
			ut_stb <= 0;
		end else
		case (state)
		`IDLE: begin
			if (ut_ack)
				ut_stb <= 0;
			else if (in_stb == 0)
				in_ack <= 0;
			else begin
				ut_addr <= in_addr[23:2];
				ut_stb <= 1;
				caddr <= in_addr[23:2];
				coff <= in_addr[1:0];
				csz <= in_sz;
				if (in_addr[1:0] == 2'b00 && in_sz == 2'b11) begin
					/* fastpath, aligned longword access */
					ut_write <= in_write;
					ut_wdata <= in_wdata;
					state <= `FASTPATH;
				end else begin
					ut_write <= 0;
					state <= `SLOWRMEM;
				end
			end
		end
		`FASTPATH: if (ut_ack) begin
			if (in_write == 0)
				in_rdata <= ut_rdata;
			in_ack <= 1;
			state <= `IDLE;
		end
		`SLOWRMEM: if (ut_ack) begin
			/* got first word */
			quad[31:0] <= ut_rdata;
			ut_stb <= 0;
			if (needtwo) begin // get another word
				ut_addr <= caddr + 1;
				state <= `SLOWRMEM2;
			end else if (in_write == 0) begin
				state <= `RETWD;
			end else begin
				state <= `SETWD;
				
			end
		end
		`SLOWRMEM2: if (ut_ack == 0) begin // wait until settle
			ut_stb <= 1; /* start next word */
			state <= `SLOWRMEM3;
		end
		`SLOWRMEM3: if (ut_ack) begin
			quad[63:32] <= ut_rdata;
			ut_stb <= 0;
			if (in_write == 0)
				state <= `RETWD;
			else
				state <= `SETWD;
		end

		`SETWD: if (ut_ack == 0) begin
			ut_wdata <= merged_write_word[31:0];
			ut_addr <= caddr;
			ut_write <= 1;
			ut_stb <= 1;
			if (needtwo) begin
				state <= `WRHIGH;
			end else begin
				in_ack <= 1;
				state <= `IDLE;
			end
		end

		`WRHIGH: if (ut_ack) begin
			ut_stb <= 0;
			ut_wdata <= merged_write_word[63:32];
			ut_addr <= caddr + 22'd1;
			ut_write <= 1;
			state <= `WRHIGH2;
		end

		`WRHIGH2: if (ut_ack == 0) begin
			ut_stb <= 1;
			in_ack <= 1;
			state <= `IDLE;
		end

		/* Return an unaligned word */
		`RETWD: begin
			in_rdata <= shifted_bytes;
			in_ack <= 1;
			state <= `IDLE;
		end
		default: state <= `IDLE;
		endcase
	end


endmodule

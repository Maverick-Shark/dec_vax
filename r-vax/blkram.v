
module blkram(
	input		clk,
	input		rst,

	input [21:0]	pmem_addr,
	input		pmem_write,
	input [31:0]	pmem_wdata,
	input		pmem_stb,
	output reg [31:0] pmem_rdata,
	output reg	pmem_ack
);
parameter MEMSZ=4096;
	reg [31:0] memblk [MEMSZ-1:0];

	always @(posedge clk) begin
		if (|pmem_addr[21:12] && pmem_stb) begin
			pmem_rdata <= 32'b0;
			pmem_ack <= 1;
		end else if (pmem_stb) begin
			if (pmem_write == 0) begin
				pmem_rdata <= memblk[pmem_addr[11:0]];
			end else
				memblk[pmem_addr[11:0]] <= pmem_wdata;
			pmem_ack <= 1;
		end else
			pmem_ack <= 0;
	end

endmodule


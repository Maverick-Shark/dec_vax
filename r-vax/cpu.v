/*	$Id$	*/

`include "states.vh"
`include "opcodes.vh"

/*
 * VAX CPU
 */

module cpu(
	input clk,
	input rst,

	input [4:0]	reg_addr,
	input [31:0]	reg_wdata,
	input 		reg_write,
	input		reg_stb,
	output reg [31:0] reg_rdata,
	output reg 	reg_ack,

	output reg [31:0] cpu_addr,
	output reg [31:0] cpu_wdata,
	input [31:0]	cpu_rdata,
	output reg	cpu_stb,
	output reg	cpu_write,
	input 		cpu_ack,

	input		cont,
	input		step,
	output		halted,

	output reg [31:0]	pc
);

	reg [31:0]	greg[15:0];
	reg [`STATBITS-1:0]	state, fillstate;

	reg [31:0]	psl;
	reg		Ctmp;


	/* instruction word "cache" */
	reg [31:2]	itag;
	reg [31:0]	inslword;
	reg		ivalid;
	reg [7:0]	insbyte;
	reg [7:0]	decib;

	reg [31:0]	arg[5:0];	// storage for evaluated args
	reg [2:0]	nargs;		// current arg
	reg [0:0]	isreg[5:0];	// destination is reg
	reg [31:0]	res;

	wire [31:0] curpc, cur_reg_val;
	wire [1:0] curbyte;
	wire [3:0] cur_reg_num;
	assign curbyte = greg[15][1:0];
	assign curpc = greg[15];
	assign cur_reg_num = decib[3:0];
	assign cur_reg_val = greg[cur_reg_num];

	/*
	 * get current instruction byte based on pc.
	 */
	always @* begin
		case (curpc[1:0])
		2'b00: decib = inslword[7:0];
		2'b01: decib = inslword[15:8];
		2'b10: decib = inslword[23:16];
		2'b11: decib = inslword[31:24];
		endcase
	end

	wire [`STATLINE-1:0] optype;
	reg [`STATLINE-1-`STATBITS:0] savop;
	wire [`STATLINE-1-`STATBITS:0] nextsavop;
	assign nextsavop = { `STATBITS'd0, savop[(`STATBITS*5)-1:`STATBITS] };

	decode decode(decib, optype);

	assign halted = state == `S_HALT;
	assign isvalid = (itag[31:2] == greg[15][31:2]) && ivalid;

	always @(posedge clk) begin
		if (rst)
			state <= `S_HALT;
		else
		case (state)
		`S_HALT: begin
			ivalid <= 0;
			pc <= greg[15];
			if (cont)
				state <= `S_FETCH;
			if (reg_stb) begin
				if (reg_write) begin
				//	if (reg_addr == 5'h0f)
				//		pc <= reg_wdata;
				//	else
						greg[reg_addr] <= reg_wdata;
				end else begin
					if (reg_addr == 5'h1f)
						reg_rdata <= 32'd0; // PSL
					if (reg_addr == 5'h1e)
						reg_rdata <= state;
					else if (reg_addr[4])
						reg_rdata <= arg[reg_addr[2:0]];
				//	else if (reg_addr == 5'h0f)
				//		reg_rdata <= pc;
					else
						reg_rdata <= greg[reg_addr];
				end
				reg_ack <= 1;
			end else
				reg_ack <= 0;
		end

		/* get next instruction from input stream */
		`S_FETCH: begin
			if (isvalid) begin
				/* put insbyte in decode reg */
				savop <= optype[(`STATBITS*5)-1:`STATBITS];
				insbyte <= decib;
				greg[15] <= curpc + 1;
				state <= optype[`STATBITS-1:0];
				nargs <= 0;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_FETCH;
			end
		end

		/* Read a longword and put into current arg reg */
		`S_RL: begin
			if (isvalid) begin
				case (decib[7:4])
				`OPS_REG: arg[nargs] <= cur_reg_val;
				default: arg[nargs] <= { 24'd0, decib };
				endcase
				nargs <= nargs + 1;
				greg[15] <= curpc + 1;
				state <= savop[`STATBITS-1:0];
				savop <= nextsavop;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_RL;
			end
		end
`ifdef notyet
		`S_ML: begin
			if (isvalid) begin
				isreg[nargs] <= 0;
				case (decib[7:4])
				4'b00??: begin	// literal
					resadflt <= 1;
					state <= S_IEXIT;
				end
				4'b1???: begin // displacement
					case (decib[5:4])
					2'b00: off <= greg[decib[3:0]];
					2'b01: off <= 
				end
				`OPS_REG: begin
					arg[nargs] <= { 28'd0, decib[3:0] };
					isreg[nargs] <= 1;
				
				end
				default: arg[nargs] <= { 24'd0, decib };
				endcase
				nargs <= nargs + 1;
				greg[15] <= greg[15] + 1;
				state <= savop[`STATBITS-1:0];
				savop <= nextsavop;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_WL;
			end
		end
`endif
		`S_WL: begin
			if (isvalid) begin
				isreg[nargs] <= 0;
				case (decib[7:4])
				`OPS_REG: begin
					arg[nargs] <= { 28'd0, decib[3:0] };
					isreg[nargs] <= 1;
				end
				default: arg[nargs] <= { 24'd0, decib };
				endcase
				nargs <= nargs + 1;
				greg[15] <= curpc + 1;
				state <= savop[`STATBITS-1:0];
				savop <= nextsavop;
			end else begin
				state <= `S_FILLUP;
				fillstate <= `S_WL;
			end
		end
		`S_ADDL: begin
			if (isreg[2])
				{ psl[`PSL_C], greg[arg[2][3:0]]  } <=
				    { 1'b0, arg[0] } + { 1'b0, arg[1] };
			else
				greg[arg[2][3:0]] <= 32'hf00fbabe;
			state <= `S_HALT;
		end
		`S_FILLUP: begin
			/* Fetch new longword */
			cpu_addr <= { curpc[31:2], 2'b00 };
			cpu_stb <= 1;
			if (cpu_ack) begin
				inslword <= cpu_rdata;
				itag <= curpc[31:2];
				ivalid <= 1;
				cpu_stb <= 0;
				state <= fillstate;
			end
		end
		default: state <= `S_HALT;
		endcase
	end


endmodule

/*	$Id$	*/
`timescale 1ns / 1ps
/*
 * Simple hardware console.
 *
 * All commands can begin with a hex number.
 * 	/	Open a (direct) memory cell
 * 	P	Open a (physical) memory cell
 * 	V	Open a (virtual) memory cell
 *	L	Load from device
 *	R	Open a general register
 *	I	Open an internal register
 *	G	Continue at address
 *	S	Execute one insn, then jump back to the console
 */
`define	WBITS		32

`define	CONSOLE		6'd0
`define	CONSOLE2	6'd1
`define	CONSOLE3	6'd2
`define	CONSOLE4	6'd3
`define	GETCHAR		6'd4
`define	GETCHAR2	6'd5
`define	GETCHAR3	6'd6
`define	PUTCHAR		6'd7
`define	PUTCHAR2	6'd8
`define	PUTCHAR3	6'd9
`define	CRLFEXC		6'd10
`define	CRLFEXC2	6'd11
`define	CRLFEXC3	6'd12
`define	READNUM		6'd13
`define	READNUM2	6'd14
`define	READNUM3	6'd15
`define	WRITENUM	6'd16
`define	WRITENUM2	6'd17
`define	WRITENUM3	6'd18
`define	WRITENUM4	6'd19
`define	WRITENUM5	6'd20
`define	WRITENUM6	6'd21
`define	GETCHAR4	6'd22
`define	MEMREFS		6'd23
`define	MEMREFS2	6'd24
`define	MEMREFS3	6'd25
`define	MEMREFS4	6'd26
`define	MEMREFS5	6'd27
`define	PUTCHAR21	6'd32
`define	WRITENUM51	6'd36
`define	WRITENUM52	6'd37
`define	CONSOLE0	6'd38
`define	CONSOLE1	6'd39

`define	READNUM_NEXT_C4	2'd0
`define	READNUM_NEXT_M4	2'd2

`define	WRITNUM_NEXT_C2	2'd0
`define	WRITNUM_NEXT_M2	2'd2

`define	PUTCHAR_NEXT_C2	5'd0
`define	PUTCHAR_NEXT_M3	5'd2
`define	PUTCHAR_NEXT_C3	5'd3
`define	PUTCHAR_NXT_CL2	5'd4
`define	PUTCHAR_NXT_CL3	5'd5
`define	PUTCHAR_NEXT_W2	5'd6
`define	PUTCHAR_NEXT_W3	5'd7
`define	PUTCHAR_NEXT_W4	5'd8
`define	PUTCHAR_NEXT_W5	5'd9
`define	PUTCHAR_NEXT_W6	5'd10
`define	PUTCHAR_NEXT_R3	5'd11
`define	PUTCHAR_NEXT_M2	5'd13
`define PUTCHAR_NEXT_W51 5'd15
`define PUTCHAR_NEXT_W52 5'd16

module console(
	input clk,
	input rst,

	output reg [`WBITS-1:0]	ADR_O,
	output reg	  	WE_O,
	output reg [`WBITS-1:0] DAT_O,
	output reg	  	STB_O,
	input [`WBITS-1:0]	DAT_I,
	input		  	ACK_I,

	/* signals for what we want to reference */
	output reg	con_pmem,	// phys memory
	output reg	con_vmem,	// virt memory
	output reg	con_reg,	// general reg
	output reg	con_ipr,	// internal processor reg

	input [7:0]	haltpos,
	input		resopflt,

	output reg step,
	output reg cont,
	input halted
);

	reg [5:0]	state;		/* 33 states */
	reg [1:0] 	readnum_next;	/* three states */
	reg [1:0]	writenum_next;	/* three states */
	reg [4:0]	putchar_next;
	reg [`WBITS-1:0] 	innum, utnum;
	reg [7:0] 	tmp;
	reg		nodig;

	reg		was_pmem;	// phys memory
	reg		was_vmem;	// virt memory
	reg		was_reg;	// general reg
	reg		was_ipr;	// internal processor reg
	reg [31:0]	was_addr;

	reg [3:0] htoa;
	reg [7:0] hexd;
	always @(htoa) begin
		case (htoa)
		4'd0: hexd = "0";
		4'd1: hexd = "1";
		4'd2: hexd = "2";
		4'd3: hexd = "3";
		4'd4: hexd = "4";
		4'd5: hexd = "5";
		4'd6: hexd = "6";
		4'd7: hexd = "7";
		4'd8: hexd = "8";
		4'd9: hexd = "9";
		4'd10: hexd = "A";
		4'd11: hexd = "B";
		4'd12: hexd = "C";
		4'd13: hexd = "D";
		4'd14: hexd = "E";
		4'd15: hexd = "F";
		endcase
	end

	always @* begin
		case (state)
		`WRITENUM: htoa = utnum[31:28];
		`WRITENUM2: htoa = utnum[27:24];
		`WRITENUM3: htoa = utnum[23:20];
		`WRITENUM4: htoa = utnum[19:16];
		`WRITENUM5: htoa = utnum[15:12];
		`WRITENUM51: htoa = utnum[11:8];
		`WRITENUM52: htoa = utnum[7:4];
		default: htoa = utnum[3:0];
		endcase
	end

wire debug;
assign debug = 0;
always @(posedge clk) begin
	if (cont) begin
if (debug)$fdisplay(32'h80000002, "CSTATE %d\r", state);
	end
end

	initial state = `CONSOLE;
	always @(posedge clk) begin
		if (rst) begin
			state <= `CONSOLE;
			cont <= 0;
		end else
		/* verilator lint_off CASEINCOMPLETE */
		case (state)
		`CONSOLE1: begin
			if (halted == 0) begin
if (debug)$fdisplay(32'h80000002, "CONSOLE1: halted %x \r", halted);
				state <= `CONSOLE;
				cont <= 0;
			end
		end
		`CONSOLE: begin
			if (halted) 
				state <= `CONSOLE0;
		end
		`CONSOLE0: begin
			utnum <= { 23'b0, resopflt, haltpos };
if (debug)$fdisplay(32'h80000002, "CONSOLE0: haltpos %x \r", haltpos);
			writenum_next <= `WRITNUM_NEXT_C2;
			state <= `WRITENUM;
		end

		`CONSOLE2: begin
			state <= `CRLFEXC;
			con_reg <= 0;
			con_pmem <= 0;
			con_vmem <= 0;
			con_ipr <= 0;
		end
		`CONSOLE3: begin
			state <= `READNUM;
			readnum_next <= `READNUM_NEXT_C4;
		end
		`CONSOLE4: begin
			if (tmp == "G") begin
				state <= `CONSOLE1;
				step <= 0;
				cont <= 1;
			end else if (tmp == "S") begin
				state <= `CONSOLE1;
				step <= 1;
				cont <= 1;
			end else begin
				/* Reference some cell */
				was_addr <= innum;
				ADR_O <= innum;
				WE_O <= 0;
				STB_O <= 1;
				was_reg <= 0;
				was_pmem <= 0;
				was_vmem <= 0;
				was_ipr <= 0;
				state <= `MEMREFS;
				if (tmp == "/") begin
					con_pmem <= 1;
					was_pmem <= 1;
				end else if (tmp == "R") begin
					con_reg <= 1;
					was_reg <= 1;
				end else if (tmp == "I") begin
					con_ipr <= 1;
					was_ipr <= 1;
				end else if (tmp == "P") begin
					con_pmem <= 1;
					was_pmem <= 1;
				end else if (tmp == "V") begin
					con_vmem <= 1;
					was_vmem <= 1;
				end else begin
					tmp <= "?";
					state <= `PUTCHAR;
					putchar_next <= `PUTCHAR_NEXT_C2;
					STB_O <= 0;
				end
			end
		end

		/*
		 * Read (and maybe write?) from a mem/reg location.
		 */
		`MEMREFS: if (ACK_I) begin
			utnum <= DAT_I;
			STB_O <= 0;
			con_reg <= 0;
			con_pmem <= 0;
			con_vmem <= 0;
			con_ipr <= 0;
			writenum_next <= `WRITNUM_NEXT_M2;
			state <= `WRITENUM;
		end
		`MEMREFS2: if (ACK_I == 0) begin
			tmp <= " ";
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_M3;
		end
		`MEMREFS3: begin
			innum <= 0;
			state <= `READNUM;
			readnum_next <= `READNUM_NEXT_M4;
		end
		`MEMREFS4: begin
			if (tmp == 8'd13) begin
				if (nodig == 0) begin
					ADR_O <= was_addr;
					DAT_O <= innum;
					WE_O <= 1;
					STB_O <= 1;
					con_pmem <= was_pmem;
					con_vmem <= was_vmem;
					con_ipr <= was_ipr;
					con_reg <= was_reg;
					state <= `MEMREFS5;
				end else
					state <= `CONSOLE2;
			end else begin
				tmp <= "?";
				state <= `PUTCHAR;
				putchar_next <= `PUTCHAR_NEXT_C2;
			end
		end
		`MEMREFS5: if (ACK_I) begin
			STB_O <= 0;
			WE_O <= 0;
			con_reg <= 0;
			con_pmem <= 0;
			con_vmem <= 0;
			con_ipr <= 0;
			state <= `CONSOLE2;
		end

		/*
		 * Get char and put in tmp
		 */
		`GETCHAR: begin
			ADR_O <= 32'h20001f70;
			WE_O <= 0;
			STB_O <= 1;
			con_pmem <= 1;
			state <= `GETCHAR2;
		end
		`GETCHAR2: if (ACK_I) begin
			STB_O <= 0;
			if (DAT_I[7])
				state <= `GETCHAR3;
			else
				state <= `GETCHAR;
		end
		`GETCHAR3: begin
			ADR_O <= 32'h20001f72;
			STB_O <= 1;
			state <= `GETCHAR4;
		end
		`GETCHAR4: if (ACK_I) begin
			tmp <= DAT_I[7:0];
			STB_O <= 0;
			state <= `READNUM2;
			con_pmem <= 0;
		end

		/*
		 * Print out char in tmp
		 */
		`PUTCHAR: begin
			ADR_O <= 32'h22;
			WE_O <= 0;
			STB_O <= 1;
			con_ipr <= 1;
			state <= `PUTCHAR2;
		end
		`PUTCHAR2: if (ACK_I) begin
			STB_O <= 0;
			if (DAT_I[7])
				state <= `PUTCHAR21;
			else
				state <= `PUTCHAR;
		end
		`PUTCHAR21: begin
			ADR_O <= 32'h23;
			DAT_O <= {24'b0, tmp };
			WE_O <= 1;
			STB_O <= 1;
			state <= `PUTCHAR3;
		end
		`PUTCHAR3: if (ACK_I) begin
			STB_O <= 0;
			con_ipr <= 0;
			case (putchar_next)
			`PUTCHAR_NEXT_C2: state <= `CONSOLE2;
			`PUTCHAR_NEXT_M3: state <= `MEMREFS3;
			`PUTCHAR_NEXT_C3: state <= `CONSOLE3;
			`PUTCHAR_NXT_CL2: state <= `CRLFEXC2;
			`PUTCHAR_NXT_CL3: state <= `CRLFEXC3;
			`PUTCHAR_NEXT_W2: state <= `WRITENUM2;
			`PUTCHAR_NEXT_W3: state <= `WRITENUM3;
			`PUTCHAR_NEXT_W4: state <= `WRITENUM4;
			`PUTCHAR_NEXT_W5: state <= `WRITENUM5;
			`PUTCHAR_NEXT_W51: state <= `WRITENUM51;
			`PUTCHAR_NEXT_W52: state <= `WRITENUM52;
			`PUTCHAR_NEXT_W6: state <= `WRITENUM6;
			`PUTCHAR_NEXT_R3: state <= `READNUM3;
			`PUTCHAR_NEXT_M2: state <= `MEMREFS2;
			default: state <= `CONSOLE2;
			endcase
		end

		/*
		 * Print out \r\n!
		 */
		`CRLFEXC: begin
			tmp <= 8'd13;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NXT_CL2;
		end
		`CRLFEXC2: begin
			tmp <= 8'd10;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NXT_CL3;
		end
		`CRLFEXC3: begin
			tmp <= ">";
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_C3;
		end
		/*
		 * Print out num in utnum.
		 */
		`WRITENUM: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W2;
		end
		`WRITENUM2: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W3;
		end
		`WRITENUM3: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W4;
		end
		`WRITENUM4: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W5;
		end
		`WRITENUM5: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W51;
		end
		`WRITENUM51: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W52;
		end
		`WRITENUM52: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_W6;
		end
		`WRITENUM6: begin
			tmp <= hexd;
			state <= `PUTCHAR;
			/* verilator lint_off CASEINCOMPLETE */
			(* full_case *)
			case (writenum_next)
			`WRITNUM_NEXT_C2: putchar_next <= `PUTCHAR_NEXT_C2;
			`WRITNUM_NEXT_M2: putchar_next <= `PUTCHAR_NEXT_M2;
			endcase
			/* verilator lint_on CASEINCOMPLETE */
		end
		/*
		 * read in digits until no more digit into innum.
		 * return offending char in tmp
		 */
		`READNUM: begin
			nodig <= 1;
			innum <= 0;
			state <= `GETCHAR;
		end
		`READNUM2: begin
			state <= `PUTCHAR;
			putchar_next <= `PUTCHAR_NEXT_R3;
		end
		`READNUM3: begin
			if (tmp >= 8'd48 && tmp <= 8'd57) begin // digit
				nodig <= 0;
				innum <= { innum[27:0], tmp[3:0] };
				state <= `GETCHAR;
			end else if (tmp >= 8'd65 && tmp <= 8'd70) begin
				nodig <= 0;
				innum <= { innum[27:0], 4'd0 } + 
				    { 24'b0, tmp - 8'd55 };
				state <= `GETCHAR;
			end else begin
				if (tmp[6])
					tmp[5] <= 0;
				/* verilator lint_off CASEINCOMPLETE */
				(* full_case *)
				case (readnum_next)
				`READNUM_NEXT_C4: state <= `CONSOLE4;
				`READNUM_NEXT_M4: state <= `MEMREFS4;
				endcase
				/* verilator lint_on CASEINCOMPLETE */
			end
		end

		endcase
		/* verilator lint_on CASEINCOMPLETE */
	end

endmodule

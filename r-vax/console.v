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
`define	WBITS		31

`define	CPUHALT		5'd0
`define	CPUFETCH2	5'd2

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
`define	LOAD		6'd33
`define	LOAD2		6'd34
`define	WRITENUM51	6'd36
`define	WRITENUM52	6'd37

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

	output reg [`WBITS:0] conaddr,
	output reg	  conwrite,
	output reg [`WBITS:0] conwdata,
	output reg	  conready,
	input [`WBITS:0]  conrdata,
	input		  convalid,

	/* signals for what we want to reference */
	output reg	con_mem,	// memory
	output reg	con_reg,	// general reg
	output reg	con_ipr,	// internal processor reg


	output reg halt, output reg cont,
	output reg refpc, output reg refac0, output reg refac1,
	output reg refac2, output reg refac3,
	input [4:0] cpustate,
	input [1:15] pc,
	input [0:15] ac0,
	input [0:15] ac1,
	input [0:15] ac2,
	input [0:15] ac3,
	input C,
	input [1:0]	hreason,
	output reg [0:15]	switches,

	input halted_i,
	output break_o,

	input tti_rx,
	output tto_tx

);

	reg [5:0]	state;		/* 33 states */
	reg [1:0] 	readnum_next;	/* three states */
	reg [1:0]	writenum_next;	/* three states */
	reg [4:0]	putchar_next;
	reg [`WBITS:0] 	innum, utnum;
	reg [7:0] 	tmp;
	reg		step, nodig;
	reg [4:0]	bootidx;

	(*rom_style = "block" *) reg [15:0] romdata;

	wire ttibusy, ttobusy, ttidone, ttodone;
	wire [7:0] iodatain;
	reg start, clear;
	reg [7:0] iodataut;
	wire ttiintreq, ttointreq;

	reg seltti, seltto, ttodata;

	assign ttiintmsk = 1'b0;
	assign ttointmsk = 1'b0;
	assign intreq = ttiintreq | ttointreq;

	tti tti(
		.clk(clk),
		.iorst(rst),

		.start(start),
		.clear(clear),
		.devsel(seltti),
		.intmsk(ttiintmsk),

		.busy(ttibusy),
		.done(ttidone),
		.outdata(iodatain),
		.intreq(ttiintreq),
		.gotbreak(break_o),

		.tti_rx(tti_rx)
	);

	tto tto(
		.clk(clk),
		.iorst(rst),

		.start(start),
		.clear(clear),
		.devsel(seltto),
		.wdata(ttodata),
		.intmsk(ttointmsk),

		.busy(ttobusy),
		.done(ttodone),
		.intreq(ttointreq),

		.data(iodataut),

		.tto_tx(tto_tx)
	);

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

	always @(posedge clk) begin
		if (rst) begin
			state <= `CONSOLE;
			cont <= 0;
			step <= 0;
		end else if (cpustate == `CPUFETCH2) begin
			if (step) begin
				step <= 0;
				halt <= 1;
			end
			cont <= 0;
		end else if (cpustate == `CPUHALT)
		case (state)
		`CONSOLE: begin
			if (cpustate == `CPUHALT && !cont) begin
				halt <= 0;
		//		utnum <= { 1'b0, pc };
				utnum <= 32'h7234abcd;
				writenum_next <= `WRITNUM_NEXT_C2;
				state <= `WRITENUM;
			end
		end
		`CONSOLE2: begin
			state <= `CRLFEXC;
			conwrite <= 0;
			refpc <= 0;
			refac0 <= 0;
			refac1 <= 0;
			refac2 <= 0;
			refac3 <= 0;
			con_mem <= 0;
			con_reg <= 0;
			con_ipr <= 0;
		end
		`CONSOLE3: begin
			state <= `READNUM;
			readnum_next <= `READNUM_NEXT_C4;
		end
		`CONSOLE4: begin
			if (tmp == "G") begin
				state <= `CONSOLE;
				cont <= 1;
			end else if (tmp == "S") begin
				state <= `CONSOLE;
				step <= 1;
				cont <= 1;
			end else if (tmp == "L") begin
				switches <= innum;
				bootidx <= 0;
				state <= `LOAD;
			end else begin
				/* Reference some cell */
				conaddr <= innum;
				conwrite <= 0;
				conready <= 1;
				state <= `MEMREFS;
				if (tmp == "/") begin
					con_mem <= 1;
				end else begin
					tmp <= "?";
					state <= `PUTCHAR;
					putchar_next <= `PUTCHAR_NEXT_C2;
				end
			end
		end
		/*
		 * boot from given device.
		 */
		`LOAD: begin
			conaddr <= { 11'b0, bootidx };
			case (bootidx)
			5'o00: romdata = 16'o062677;
			5'o01: romdata = 16'o060477;
			5'o02: romdata = 16'o024026;
			5'o03: romdata = 16'o107400;
			5'o04: romdata = 16'o124000;
			5'o05: romdata = 16'o010014;
			5'o06: romdata = 16'o010030;
			5'o07: romdata = 16'o010032;
			5'o10: romdata = 16'o125404;
			5'o11: romdata = 16'o000005;
			5'o12: romdata = 16'o030016;
			5'o13: romdata = 16'o050377;
			5'o14: romdata = 16'o060077;
			5'o15: romdata = 16'o101102;
			5'o16: romdata = 16'o000377;
			5'o17: romdata = 16'o004030;
			5'o20: romdata = 16'o101065;
			5'o21: romdata = 16'o000017;
			5'o22: romdata = 16'o004027;
			5'o23: romdata = 16'o046026;
			5'o24: romdata = 16'o010100;
			5'o25: romdata = 16'o000022;
			5'o26: romdata = 16'o000077;
			5'o27: romdata = 16'o126420;
			5'o30: romdata = 16'o063577;
			5'o31: romdata = 16'o000030;
			5'o32: romdata = 16'o060477;
			5'o33: romdata = 16'o107363;
			5'o34: romdata = 16'o000030;
			5'o35: romdata = 16'o125300;
			5'o36: romdata = 16'o001400;
			5'o37: romdata = 16'o000000;
			endcase
			conwdata <= romdata;
			conwrite <= 1;
			conready <= 1;
			state <= `LOAD2;
		end
		`LOAD2: if (convalid) begin
			conready <= 0;
			conwrite <= 0;
			bootidx <= bootidx + 1;
			if (bootidx == 5'o37) begin
				state <= `CONSOLE;
				cont <= 1;
				conwdata <= 0;
				conwrite <= 1;
				refpc <= 1;
			end else
				state <= `LOAD;
		end

		/*
		 * Read (and maybe write?) from a mem/reg location.
		 */
		`MEMREFS: if (convalid) begin
			utnum <= conrdata;
			writenum_next <= `WRITNUM_NEXT_M2;
			state <= `WRITENUM;
		end
		`MEMREFS2: begin
			conready <= 0;
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
					conwdata <= innum;
					conwrite <= 1;
					conready <= 1;
					state <= `MEMREFS5;
				end else
					state <= `CONSOLE2;
			end else begin
				tmp <= "?";
				state <= `PUTCHAR;
				putchar_next <= `PUTCHAR_NEXT_C2;
			end
		end
		`MEMREFS5: if (convalid) begin
			conready <= 0;
			conwrite <= 0;
			state <= `CONSOLE2;
		end

		/*
		 * Get char and put in tmp
		 */
		`GETCHAR: begin
			seltti <= 1;
			state <= `GETCHAR2;
		end
		`GETCHAR2: if (ttidone) begin
			tmp <= iodatain;
			clear <= 1;
			state <= `GETCHAR3;
		end
		`GETCHAR3: state <= `GETCHAR4;
		`GETCHAR4: begin
			seltti <= 0;
			clear <= 0;
			state <= `READNUM2;
		end
		/*
		 * Print out char in tmp
		 */
		`PUTCHAR: begin
			seltto <= 1;
			state <= `PUTCHAR2;
		end
		`PUTCHAR2: if (ttobusy == 0) begin
			start <= 1;
			ttodata <= 1;
			iodataut <= tmp;
			state <= `PUTCHAR21;
		end
		`PUTCHAR21: state <= `PUTCHAR3;
		`PUTCHAR3: begin
			seltto <= 0;
			start <= 0;
			ttodata <= 0;
			iodataut <= 0;
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
			(* full_case *)
			case (writenum_next)
			`WRITNUM_NEXT_C2: putchar_next <= `PUTCHAR_NEXT_C2;
			`WRITNUM_NEXT_M2: putchar_next <= `PUTCHAR_NEXT_M2;
			endcase
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
				    tmp - 8'd55;
				state <= `GETCHAR;
			end else begin
				if (tmp[6])
					tmp[5] <= 0;
				(* full_case *)
				case (readnum_next)
				`READNUM_NEXT_C4: state <= `CONSOLE4;
				`READNUM_NEXT_M4: state <= `MEMREFS4;
				endcase
			end
		end
		endcase
	end

endmodule

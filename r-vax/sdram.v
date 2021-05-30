/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none

/*
 * Simple SDRAM controller for the Hynix SDRAM chip, 2M * 4 bank * 16 bit.
 * Runs at 50MHz, CAS2, burst 1.
 *
 * Addressing is <row><bank><col>.
 *
 * Memory is read/written as 32-bit longwords. 
 * Size is 16Mbyte, addressed as 4M longwords (22 bits).
 */

`ifndef VERILATOR
`define XILINX
`endif

module sdram #(
	parameter	CLOCK		= 50000000,
	parameter	NADDRB		= 12,
	parameter	NBANKB		= 2,
	parameter	NCOLB		= 9
) (
	input		clk,
	input		rst, 

	output		sdram_clk,
	output		sdram_cke,
	output		sdram_cs,
	output		sdram_ras,
	output		sdram_cas,
	output		sdram_we,
	output		sdram_udqm,
	output		sdram_ldqm,
	output [11:0]	sdram_addr,
	output [1:0]	sdram_ba,
	inout [15:0]	sdram_data,

`ifdef DBGCNT
	input [7:0]	dcount,
`endif

	input		STB_I,
	input [21:0]	ADR_I,	// note: longword addressing.
	input		WE_I,
	input [31:0]	DAT_I,
	output [31:0]	DAT_O,
	output		ACK_O
);

	/* Request that all registers for comm with sdram is in IOBs */

	(* IOB = "TRUE" *)
	reg		ras, cas, we, a11, a10;
	(* IOB = "TRUE" *)
	reg [9:0]	addr;
	(* IOB = "TRUE" *)
	reg [1:0]	bank;


	reg [15:0]	sdata;
	reg		pack;
	reg [31:0]	prdata, xprdata;

	reg		need_refresh, setdout;
	wire [15:0]	indata;
	wire		request;
	assign		request = STB_I;

	/* RAS/CAS/WE command triple */
	localparam	NOP = 3'b111,
			READ = 3'b101,
			WRITE = 3'b100,
			ACTIVATE = 3'b011,
			PRECHARGE_ALL = 3'b010,
			AUTO_REFRESH = 3'b001,
			MODE = 3'b000;

`ifdef XILINX_ISIM
	localparam	SETTLETIME = 20; /*  */
	initial		state = 0;
	initial		timer = 0;
`else
	localparam	SETTLETIME = 16'd10000;	/* (CLOCK/5000), 200us */
`endif

	/* States for this SDRAM module.  */
	reg [3:0]	state;
	localparam	STARTUP = 0,
			ISETTLE = 1,
			ICHARGE = 2,
			IREFRESH = 3,
			ISETMODE = 4,
			IDLE = 5,
			READ1 = 6,
			READ2 = 7,
			SETCAS = 8,
			REF1 = 9,
			REF2 = 10,
			REF3 = 11,
			READ3 = 12,
			READ4 = 13,
			WRITE2 = 14;

	reg [15:0]	timer;

	reg cs;

	always @(posedge clk) begin
`ifdef DBGCNT
//if (STB_I) $fdisplay(32'h80000002, "SDRAM %d: state %d stb 1 ack %d addr %x dato %x", dcount, state, ACK_O, { ADR_I, 2'b0 }, DAT_O);
`endif
		timer <= timer + 1;
		if (timer[7:0] == 8'b0)
			need_refresh <= 1;
		{ a11, a10, addr } <= 0;	// default address 0
		bank <= 0;
		setdout <= 0;
		if (STB_I == 0) begin
			pack <= 0;
		end
		{ ras, cas, we } <= NOP;	// none set
		if (rst) begin
			state <= STARTUP;
		end else case (state)
		STARTUP: begin
			cs <= 1;
			state <= ISETTLE;
			timer <= 0;
		end
		ISETTLE: if (timer == SETTLETIME) begin
			/* after 200us precharge all */
			cs <= 0;
			{ ras, cas, we } <= PRECHARGE_ALL;
			a10 <= 1;
			state <= ICHARGE;
		end
		ICHARGE: begin
			state <= IREFRESH;
			timer <= 0;
		end
		IREFRESH: begin
			if (timer[5] == 1)
				state <= ISETMODE;
			else if (timer[1:0] == 2'b00)
				{ ras, cas, we } <= AUTO_REFRESH;
		end
		ISETMODE: begin
			{ ras, cas, we } <= MODE;
			/* Mode: CAS2, two word at a time, sequential */
			{ a11, a10, addr } <= 12'b000000100001;
			state <= REF2; /* One cycle before idle */
		end


		/* default state */
		IDLE: begin
			cs <= 1;
			if (need_refresh) begin
				cs <= 0;
				{ ras, cas, we } <= AUTO_REFRESH;
				state <= REF1;
				need_refresh <= 0;
			end else if (request) begin
				cs <= 0;
				/* do something; open row */
				{ ras, cas, we } <= ACTIVATE;
				bank <= ADR_I[9:8];
				{ a11, a10, addr } <= ADR_I[21:10];
				xprdata <= DAT_I;
				state <= SETCAS;
			end
		end

		SETCAS: begin
			bank <= ADR_I[9:8];
			/* Note: precharge after use (closes row) */
			{ a11, a10, addr } <= { 3'b010, ADR_I[7:0], 1'b0 };
			if (WE_I) begin
				{ ras, cas, we } <= WRITE;
				setdout <= 1;
				sdata <= xprdata[15:0];
				state <= WRITE2;
			end else begin
				{ ras, cas, we } <= READ;
				state <= READ1;
			end
		end
		READ1: state <= READ2; /* CAS delay */
		READ2: state <= READ3; /* clock skew compensation */
		READ3: begin
			prdata[15:0] <= indata;
			state <= READ4;
		end

		READ4: begin
			prdata[31:16] <= indata;
			state <= REF2;
			pack <= 1;
		end

		WRITE2: begin
			setdout <= 1;
			state <= REF1;
			sdata <= xprdata[31:16];
			pack <= 1;
		end

		REF1: state <= REF2;
		REF2: state <= REF3;
		REF3: state <= IDLE;
		default: state <= IDLE;
		endcase
	end

`ifdef XILINX
	/*
	 * Skew clock 180 degrees by using DDR2 registers.
	 */
	ODDR2 #(
		.DDR_ALIGNMENT("NONE"),
		.INIT(1'b0),
		.SRTYPE("SYNC")
	) oddr2 (
		.Q(sdram_clk),
		.C0(clk),
		.C1(~clk),
		.CE(1'b1),
		.R(1'b0),
		.S(1'b0),
		.D0(1'b0),
		.D1(1'b1)
	);
`else
	assign	sdram_clk = ~clk;
`endif

`ifdef XILINX
genvar i;

generate
	for (i=0; i < 16; i = i + 1) begin : ibuf
		IBUF #(
			.IBUF_DELAY_VALUE("9"),
			.IFD_DELAY_VALUE("AUTO"),
			.IOSTANDARD("DEFAULT")
		) ibuf_data (
			.O(indata[i]),
			.I(sdram_data[i])
		);
	end
endgenerate
`else
	assign indata = sdram_data;
`endif

 	assign sdram_data = setdout ? sdata : 16'bz;
	assign sdram_ras = ras;
	assign sdram_cas = cas;
	assign sdram_we = we;
	assign sdram_cke = 1'b1; // clock always enabled
	assign sdram_cs = cs;
	assign sdram_addr = { a11, a10, addr };
	assign sdram_udqm = 1'b0;
	assign sdram_ldqm = 1'b0;
	assign sdram_ba = bank;

	assign DAT_O = request ? prdata : 32'b0;
	assign ACK_O = request ? pack : 1'b0;

endmodule

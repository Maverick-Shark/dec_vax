/*	$Id$	*/
`timescale 1ns / 1ps
/*
 * Simple SDRAM controller for the Hynix SDRAM chip, 2M * 4 bank * 16 bit.
 * Runs at 50MHz, CAS2, burst 1.
 *
 * Addressing is <row><bank><col>.  Only addressed word-wise (16 bit),
 * since burst mode makes it instable. (???)
 *
 * Memory is read/written as 32-bit longwords. 
 * Size is 16Mbyte, addressed as 4M longwords (22 bits).
 */

`define	ONEWORD

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

	input [23:2]	pmem_addr,	// note: longword addressing.
	input		pmem_write,
	input [31:0]	pmem_wdata,
	input		pmem_stb,
	output [31:0]	pmem_rdata,
	output		pmem_ack
);

	/* Request that all registers for comm with sdram is in IOBs */

	(* IOB = "TRUE" *)
	reg		ras, cas, we, a11, a10, cs;
	(* IOB = "TRUE" *)
	reg [9:0]	addr;
	(* IOB = "TRUE" *)
	reg [1:0]	bank;


	reg [15:0]	sdata;
	reg		pack;
	reg [31:0]	prdata, xprdata;

	reg		need_refresh, setdout, wnum;
	wire [15:0]	indata;

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
	localparam	STARTUP = 4'd0,
			IDLE = 4'd1,
			READ1 = 4'd2,
			READ2 = 4'd3,
			SETCAS = 4'd4,
			REF1 = 4'd5,
			REF2 = 4'd6,
			REF3 = 4'd7,
			READ3 = 4'd8,
			ISETTLE = 4'd9,
			ICHARGE = 4'd10,
			IREFRESH = 4'd11,
			ISETMODE = 4'd12,
			READ4 = 4'd13,
			WRITE2 = 4'd14;

	reg [15:0]	timer;

	always @(posedge clk) begin
		timer <= timer + 1;
		if (timer[7:0] == 8'b0)
			need_refresh <= 1;
		cs <= 0;
		{ a11, a10, addr } <= 0;	// default address 0
		bank <= 0;
		setdout <= 0;
		if (pmem_stb == 0) begin
			pack <= 0;
			wnum <= 0;
		end
		{ ras, cas, we } <= NOP;	// none set
		if (rst) begin
			state <= STARTUP;
			wnum <= 0;
		end else case (state)
		STARTUP: begin
			state <= ISETTLE;
			timer <= 0;
		end
		ISETTLE: if (timer == SETTLETIME) begin
			/* after 200us precharge all */
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
`ifdef ONEWORD
			{ a11, a10, addr } <= 12'b000000100000;
`else
			{ a11, a10, addr } <= 12'b000000100001;
`endif
			state <= REF2; /* One cycle before idle */
		end


		/* default state */
		IDLE: begin
			if (need_refresh) begin
				{ ras, cas, we } <= AUTO_REFRESH;
				state <= REF1;
				need_refresh <= 0;
			end else if (pmem_stb) begin
				/* do something; open row */
				{ ras, cas, we } <= ACTIVATE;
				bank <= pmem_addr[11:10];
				{ a11, a10, addr } <= pmem_addr[23:12];
				xprdata <= pmem_wdata;
				state <= SETCAS;
			end
		end

		SETCAS: begin
			bank <= pmem_addr[11:10];
			/* Note: precharge after use (closes row) */
			{ a11, a10, addr } <= { 3'b010, pmem_addr[9:2], wnum };
			if (pmem_write) begin
				{ ras, cas, we } <= WRITE;
				setdout <= 1;
				if (wnum == 0)
					sdata <= xprdata[15:0];
				else
					sdata <= xprdata[31:16];
`ifdef ONEWORD
				state <= REF2;
				if (wnum)
					pack <= 1;
`else
				state <= WRITE2;
`endif
			end else begin
				{ ras, cas, we } <= READ;
				state <= READ1;
			end
		end
		READ1: state <= READ2; /* CAS delay */
		READ2: state <= READ3; /* clock skew compensation */
		READ3: begin
			if (wnum == 0)
				prdata[15:0] <= indata;
			else
				prdata[31:16] <= indata;
`ifdef ONEWORD
			state <= REF2;
			if (wnum)
				pack <= 1;
`else
			state <= READ4;
`endif
		end

`ifndef ONEWORD
		READ4: begin
			prdata[31:16] <= indata;
			state <= REF2;
			pack <= 1;
		end

		WRITE2: begin
			setdout <= 1;
			state <= REF2;
			sdata <= xprdata[31:16];
			pack <= 1;
		end
`endif

		REF1: state <= REF2;
		REF2: begin
			if (pmem_stb)
				wnum <= 1;
			state <= REF3;
		end
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
	assign	sdram_clk = clk;
`endif

`ifdef notdef
genvar i;

generate
	for (i=0; i < 16; i = i + 1) begin : obuf
		IOBUF #(
			.DRIVE(12),
			.IOSTANDARD("LVTTL"),
			.SLEW("FAST")
		) obuf_data (
			.O(indata[i]),
			.IO(sdram_data[i]),
			.I(sdata[i]),
			.T(!setdout)
		);
	end
endgenerate
`else
 	assign sdram_data = setdout ? sdata : 16'bz;
	assign indata = sdram_data;

`endif


	assign sdram_ras = ras;
	assign sdram_cas = cas;
	assign sdram_we = we;
	assign sdram_cke = 1'b1; // clock always enabled
	assign sdram_cs = cs;
	assign sdram_addr = { a11, a10, addr };
	assign sdram_udqm = 1'b0;
	assign sdram_ldqm = 1'b0;
	assign sdram_ba = bank;

	assign pmem_rdata = prdata;
	assign pmem_ack = pack;

endmodule

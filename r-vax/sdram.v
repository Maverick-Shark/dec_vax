/*
 * Simple SDRAM controller for the Hynix SDRAM chip, 2M * 4 bank * 16 bit.
 * Runs at 50MHz, CAS2, burst 1.
 *
 * Addressing is <row><bank><col> where row only uses 6 bits,
 * since Nova only addresses 128KW.
 */




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

	input [22:0]	pmem_addr,
	input		pmem_write,
	input [0:15]	pmem_wdata,
	input		pmem_stb,
	output [0:15]	pmem_rdata,
	output		pmem_ack
);


	reg		ras, cas, we, cke, a11, a10, cs;
	reg [9:0]	addr;
	reg [1:0]	bank;

	reg		pack;
	reg [15:0]	prdata;

	reg		need_refresh, setdout;

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
	initial		initstate = 0;
	initial		timer = 0;
`else
	localparam	SETTLETIME = CLOCK/5000; /* 200us */
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
			ISETMODE = 4'd12;

	reg [15:0]	timer;

	always @(posedge clk) begin
		timer <= timer + 1;
		if (timer[7:0] == 8'b0)
			need_refresh <= 1;
		cke <= 1;
		cs <= 0;
		a10 <= 0;
		bank <= 0;
		setdout <= 0;
		if (pmem_stb == 0)
			pack <= 0;
		{ ras, cas, we } <= NOP;
		if (rst) begin
			state <= STARTUP;
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
			/* Mode: CAS2, one word at a time, sequential */
			{ a11, a10, addr } <= 12'b000000100000;
			state <= REF2; /* One cycle before idle */
		end
		IDLE: begin
			if (need_refresh) begin
				{ ras, cas, we } <= AUTO_REFRESH;
				state <= REF1;
				need_refresh <= 0;
			end else if (pmem_stb) begin
				/* Open row */
				{ ras, cas, we } <= ACTIVATE;
				bank <= pmem_addr[10:9];
				{ a11, a10, addr } <= pmem_addr[22:11];
				state <= SETCAS;
			end
		end
		SETCAS: begin
			bank <= pmem_addr[10:9];
			/* Note: precharge after use */
			{ a11, a10, addr } <= { 3'b010, pmem_addr[8:0] };
			if (pmem_write) begin
				{ ras, cas, we } <= WRITE;
				setdout <= 1;
				pack <= 1;
				state <= REF2;
			end else begin
				{ ras, cas, we } <= READ;
				state <= READ1;
			end
		end
		READ1: state <= READ2; /* CAS delay */
		READ2: state <= READ3; /* One more for clock delay */
		READ3: begin
			prdata <= sdram_data;
			pack <= 1;
			state <= REF2;
		end

		REF1: state <= REF2;
		REF2: state <= REF3;
		REF3: state <= IDLE;
		default: state <= IDLE;
		endcase
	end

	/* Seems popular to use DDR primitive to delay clock */
	ODDR2 oddr2(
		.Q(sdram_clk),
		.C0(clk),
		.C1(~clk),
		.CE(1'b1),
		.R(1'b0),
		.S(1'b0),
		.D0(1'b0),
		.D1(1'b1));

	assign sdram_ras = ras;
	assign sdram_cas = cas;
	assign sdram_we = we;
	assign sdram_cke = cke;
	assign sdram_cs = cs;
	assign sdram_addr = { a11, a10, addr };
	assign sdram_udqm = 0;
	assign sdram_ldqm = 0;
	assign sdram_data = setdout ? pmem_wdata : 16'bz;
	assign sdram_ba = bank;

	assign pmem_rdata = prdata;
	assign pmem_ack = pack;

endmodule

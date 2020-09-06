`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:	  15:49:05 08/30/2020
// Design Name:	  console
// Module Name:	  /home/ragge/verilog/nvax/test_console.v
// Project Name:  nvax
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: console
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module test_console;

	// Inputs
	reg clk;
	reg rst;
	reg [31:0] conrdata;
	reg convalid;
	reg [31:0] pc;
	reg [1:0] hreason;
	reg halted;
	reg tti_rx;

	// Outputs
	wire [31:0] conaddr;
	wire conwrite;
	wire [31:0] conwdata;
	wire conready;
	wire con_mem;
	wire con_pmem;
	wire con_vmem;
	wire con_reg;
	wire con_ipr;
	wire step;
	wire cont;
	wire break_o;
	wire tto_tx;

	// Instantiate the Unit Under Test (UUT)
	console uut (
		.clk(clk), 
		.rst(rst), 

		.ADR_O(conaddr), 
		.WE_O(conwrite), 
		.DAT_O(conwdata), 
		.STB_O(conready), 
		.DAT_I(conrdata), 
		.ACK_I(convalid), 

		.con_mem(con_mem), 
		.con_pmem(con_pmem), 
		.con_vmem(con_vmem), 
		.con_reg(con_reg), 
		.con_ipr(con_ipr), 

		.pc(pc), 
		.hreason(hreason), 
		.step(step), 
		.cont(cont), 
		.halted(halted), 
		.break_o(break_o), 

		.tti_rx(tti_rx), 
		.tto_tx(tto_tx)
	);
	defparam uut.tti.CLKPERBIT = 10;
	defparam uut.tto.CLKPERBIT = 10;

	always begin
		#1 clk = !clk;
	end

	reg [3:0] i;
	reg [7:0] ch;
	always begin
		#20;

		#1000;
		tti_rx = 0; // start bit
		#20;
		ch = "0";
		for (i = 0; i < 8; i = i + 1) begin
			tti_rx = ch[0];
			ch = { 1'b0, ch[7:1] };
			#20;
		end
		tti_rx = 1; // stop
		#40;

		tti_rx = 0; // start bit
		#20;

		ch = "/";
		for (i = 0; i < 8; i = i + 1) begin
			tti_rx = ch[0];
			ch = { 1'b0, ch[7:1] };
			#20;
		end
		tti_rx = 1; // stop

`ifdef notdef
		tti_rx = 1; // LSB bit in 'A' high
		#20;
		tti_rx = 0; // 5 bits low
		#100;
		tti_rx = 1; // one bit high
		#20;
		tti_rx = 0; // one bit low
		#20;
`endif
		tti_rx = 1; // stop bit + rest high
		#10000;
	end

	always @(negedge tto_tx) begin

	end


	initial begin
		// Initialize Inputs
		clk = 0;
		rst = 1;
		conrdata = 0;
		convalid = 0;
		pc = 0;
		hreason = 0;
		halted = 1;
		tti_rx = 1;

		#3;
		rst = 0;
		#2;

		#1000;
	end
      
endmodule

`ifdef notdef
module tti(
	input		clk,
	input		iorst,

	input		start,
	input		clear,
	input		devsel,
	input		intmsk,
	output		busy,
	output		done,
	output [7:0]	outdata,
	output		intreq,
	output reg	gotbreak,

	input		tti_rx
);
	
endmodule
`endif

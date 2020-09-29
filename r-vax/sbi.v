/*	$Id$	*/
`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    	15:54:19 04/01/2018
// Design Name: 	nvax
// Module Name:    	sbi 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
`define VCACHE
// `define HALFCLOCK
// `define	BLOCKRAM

`include "opcodes.vh"

/*
 * The memory address bus is 32 bit, 32 bit wide.
 */

module sbi (
	input		clkin,
	input		n_rst,
`ifdef notdef
	input		n_pfail,
`endif

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
	inout  [15:0]	sdram_data,

	output		buzzer,

	input		tti_rx,
	output		tto_tx
);

`ifdef HALFCLOCK
defparam console.tti.CLKPERBIT = 2604;
defparam console.tto.CLKPERBIT = 2604;
	reg clk;
	always @(posedge clkin)
		clk <= !clk;
`else
	wire clk;
	assign clk = clkin;
`endif
	/*
	 * Wiring:
	 * - cpu
	 * cpu_* -> data from cpu to mmu (before conditional)
	 * mmu_f_cpu_* -> data to mmu from cpu (after conditional)
	 * - mmu
	 * mmu_2_pc_* -> data from mmu to pcache (before conditional)
	 * pc_f_mmu_* -> data to pcache from mmu (after conditional)
	 * - pcache
	 * pc_2_mem_* -> data from pcache to memory (before conditional)
	 * mem_f_pc_* -> data to memory from pcache (after conditional)
	 */

	wire brk, rst;
	assign rst = !n_rst | brk;

	assign buzzer = 1;

	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire cpu_write, cpu_stb, cpu_ack;
	wire [1:0] cpu_size;

	/* wires from console */
	wire con_mem, con_vmem, con_pmem;
	wire [31:0] con_addr, con_wdata, con_rdata;
/* verilator lint_off UNUSED */
	wire con_write, con_stb, con_reg, con_ack, con_cyc;
/* verilator lint_on UNUSED */
	wire cont, step;
	
	/* wires from CPU */
	wire [31:0] reg_rdata, pc;
	wire reg_ack, reg_stb;
	wire halted;		// CPU is halted

	assign reg_stb = con_reg ? con_stb : 0;

	/* mmu wires */
	wire sw_to_mmu_write, sw_to_mmu_stb;
	wire [31:0] sw_to_mmu_addr;
	wire [31:0] sw_to_mmu_wdata;
	wire [1:0] sw_to_mmu_size;


	cpu cpu(
		.clk(clk),
		.rst(rst),

		.reg_addr(con_addr[4:0]),
		.reg_wdata(con_wdata),
		.reg_write(con_write),
		.reg_stb(reg_stb),
		.reg_rdata(reg_rdata),
		.reg_ack(reg_ack),

		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_write(cpu_write),
		.cpu_stb(cpu_stb),
		.cpu_rdata(cpu_rdata),
		.cpu_ack(cpu_ack),
		.cpu_size(cpu_size),

		.step(step),
		.cont(cont),
		.halted(halted),

		.pc(pc)
	);

	/* switch mmu input between console and cpu */
	assign sw_to_mmu_addr = con_vmem ? con_addr : cpu_addr;
	assign sw_to_mmu_write = con_vmem ? con_write : cpu_write;
	assign sw_to_mmu_wdata = con_vmem ? con_wdata : cpu_wdata;
	assign sw_to_mmu_stb = con_vmem ? con_stb : cpu_stb;
	assign sw_to_mmu_size = con_vmem ? `O_LONG : cpu_size;

	/* wires between mmu and pcache */
	wire mmu_to_sw_write, mmu_to_sw_stb, sw_to_pc_write, sw_to_pc_stb;
	wire pc_to_mmu_ack;
	wire [29:0] mmu_to_sw_addr, sw_to_pc_addr;
	wire [31:0] mmu_to_sw_wdata, sw_to_pc_wdata, pc_to_mmu_rdata;

`ifdef VCACHE
	vcache vcache(
		.clk(clk),
		.rst(rst),

		.in_addr(sw_to_mmu_addr),
		.in_wdata(sw_to_mmu_wdata),
		.in_write(sw_to_mmu_write),
		.in_stb(sw_to_mmu_stb),
		.in_rdata(cpu_rdata),
		.in_ack(cpu_ack),
		.in_sz(sw_to_mmu_size),

		.ut_addr(mmu_to_sw_addr),
		.ut_wdata(mmu_to_sw_wdata),
		.ut_write(mmu_to_sw_write),
		.ut_stb(mmu_to_sw_stb),
		.ut_rdata(pc_to_mmu_rdata),
		.ut_ack(pc_to_mmu_ack)
	);


`else
	assign mmu_to_sw_addr = sw_to_mmu_addr[23:2];
	assign mmu_to_sw_wdata = sw_to_mmu_wdata;
	assign mmu_to_sw_write = sw_to_mmu_write;
	assign mmu_to_sw_stb = sw_to_mmu_stb;
	assign cpu_rdata = pc_to_mmu_rdata;
	assign cpu_ack = pc_to_mmu_ack;
`endif

	/* switch pcache input between console and mmu */
	assign sw_to_pc_addr = con_pmem ? con_addr[31:2] : mmu_to_sw_addr;
	assign sw_to_pc_write = con_pmem ? con_write : mmu_to_sw_write;
	assign sw_to_pc_wdata = con_pmem ? con_wdata : mmu_to_sw_wdata;
	assign sw_to_pc_stb = con_pmem ? con_stb : mmu_to_sw_stb;

	/* wires between mem and pcache */
	wire pc_to_sw_write, pc_to_sw_stb, sw_to_mem_write, sw_to_mem_stb;
	wire mem_to_pc_ack;
	wire [29:0] pc_to_sw_addr, sw_to_mem_addr;
	wire [31:0] pc_to_sw_wdata, sw_to_mem_wdata, mem_to_pc_rdata;

`ifdef notdef
	pcache pcache(
		.clk(clk),
		.rst(rst),

		.f_mmu_addr(sw_to_pc_addr),
		.f_mmu_wdata(sw_to_pc_wdata),
		.f_mmu_write(sw_to_pc_write),
		.f_mmu_stb(sw_to_pc_stb),
		.f_mmu_rdata(pc_to_mmu_rdata),
		.f_mmu_ack(pc_to_mmu_ack),

		.t_mem_addr(pc_to_sw_addr),
		.t_mem_wdata(pc_to_sw_wdata),
		.t_mem_write(pc_to_sw_write),
		.t_mem_stb(pc_to_sw_stb),
		.t_mem_rdata(mem_to_pc_rdata),
		.t_mem_ack(mem_to_pc_ack)
	);
`else
	assign pc_to_sw_addr = sw_to_pc_addr;
	assign pc_to_sw_wdata = sw_to_pc_wdata;
	assign pc_to_sw_write = sw_to_pc_write;
	assign pc_to_sw_stb = sw_to_pc_stb;
	assign pc_to_mmu_rdata = mem_to_pc_rdata;
	assign pc_to_mmu_ack = mem_to_pc_ack;
`endif

	/* switch mem input between console and pcache */
	assign sw_to_mem_addr = con_mem ? con_addr[31:2] : pc_to_sw_addr;
	assign sw_to_mem_write = con_mem ? con_write : pc_to_sw_write;
	assign sw_to_mem_wdata = con_mem ? con_wdata : pc_to_sw_wdata;
	assign sw_to_mem_stb = con_mem ? con_stb : pc_to_sw_stb;

	/* signals to console somewhere */
	assign con_rdata = con_reg ? reg_rdata :
			con_mem ? mem_to_pc_rdata :
			con_pmem ? pc_to_mmu_rdata :
			con_vmem ? cpu_rdata : 32'b0;
	assign con_ack = con_reg ? reg_ack :
			con_mem ? mem_to_pc_ack :
			con_pmem ? pc_to_mmu_ack :
			con_vmem ? cpu_ack : 1'b0;

`ifdef BLOCKRAM
	blkram blkram(
		.clk(clk),
		.rst(rst),

		.pmem_addr(sw_to_mem_addr),		// i
		.pmem_write(sw_to_mem_write),		// i
		.pmem_wdata(sw_to_mem_wdata),		// i
		.pmem_stb(sw_to_mem_stb),		// i
		.pmem_rdata(mem_to_pc_rdata),		// o
		.pmem_ack(mem_to_pc_ack)		// o
	);
	wire [31:0] mem_32_fake;
	wire mem_1_fakeack;
`endif
	/*
	 * Ram 16MB (4MLW).  22 bits addr (21-0) * 32 bits data.
	 */
	sdram sdram(
		.clk(clk),
		.rst(rst),

		.sdram_clk(sdram_clk),
		.sdram_cke(sdram_cke),
		.sdram_cs(sdram_cs),
		.sdram_ras(sdram_ras),
		.sdram_cas(sdram_cas),
		.sdram_we(sdram_we),
		.sdram_udqm(sdram_udqm),
		.sdram_ldqm(sdram_ldqm),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba),
		.sdram_data(sdram_data),
		
`ifdef BLOCKRAM
		.pmem_addr(22'b0),		// i
		.pmem_write(1'b0),		// i
		.pmem_wdata(32'b0),		// i
		.pmem_stb(1'b0),		// i
		.pmem_rdata(mem_32_fake),		// o
		.pmem_ack(mem_1_fakeack)		// o
`else
		.pmem_addr(sw_to_mem_addr),		// i
		.pmem_write(sw_to_mem_write),		// i
		.pmem_wdata(sw_to_mem_wdata),		// i
		.pmem_stb(sw_to_mem_stb),		// i
		.pmem_rdata(mem_to_pc_rdata),		// o
		.pmem_ack(mem_to_pc_ack)		// o
`endif
	);

/* verilator lint_off UNUSED */
wire cyc_o, con_ipr;
/* verilator lint_on UNUSED */

	console console(
		.clk(clk),
		.rst(rst),

		.halted(halted),	// Handle commands
		.break_o(brk),	// want to halt
		.cont(cont),
		.step(step),

		.CYC_O(con_cyc),
		.ADR_O(con_addr),
		.WE_O(con_write),
		.DAT_O(con_wdata),
		.STB_O(con_stb),
		.DAT_I(con_rdata),
		.ACK_I(con_ack),

		.con_ipr(con_ipr),
		.con_mem(con_mem),
		.con_pmem(con_pmem),
		.con_vmem(con_vmem),
		.con_reg(con_reg),

		.pc(pc),

		.tti_rx(tti_rx),
		.tto_tx(tto_tx)
	);

endmodule

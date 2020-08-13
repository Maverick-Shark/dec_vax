/*	$Id$	*/

/*
 * Convert 16-bit to 32-bit.
 */

module pcache #(
	parameter	CSZ = 1024	// default cache size in longwords
) (
	input	clk,
	input	rst,

	/* address interface */

	/* RAM interface */
	output [22:0]	pmem_addr,	// 16MB in words
	output		pmem_write,	// write to memory
	output [15:0]	pmem_wdata,	// data to be written
	output		pmem_stb,	// want to do something
	input [15:0]	pmem_rdata,	// data read
	input		pmem_ack	// something done

);

	reg [31:0]	dcache[CSZ-1:0];	// data cache
	



endmodule


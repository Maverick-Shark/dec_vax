//============================================================================
//  altsyncram_model.v - a simulation model of Quartus's altsyncram
//  megafunction, for the one configuration the core instantiates: the
//  translation buffer's RAM in rtl/mmu.v (TB_ALTSYNCRAM).
//
//  Quartus builds that RAM from the instance; the simulators normally take
//  the plain Verilog memory next to it. So that the instance itself - its
//  parameters and the wiring of its ports - is simulated as well, "make -C
//  sim cputbf" builds the CPU bench with TB_ALTSYNCRAM and this file.
//
//  What is modelled (Intel's megafunction user guide, simple dual port):
//  port A writes, port B reads, one clock. All inputs are registered in
//  the block on the rising edge; the read data is not registered again
//  (OUTDATA_REG_B "UNREGISTERED"), so it appears after the edge that took
//  the read address. A read of the word that the same edge writes gives
//  the old contents (READ_DURING_WRITE_MODE_MIXED_PORTS "OLD_DATA").
//  Anything else stops the simulation: this is not a general model.
//
//  Not for synthesis, and not part of the Quartus project.
//============================================================================

`default_nettype none

module altsyncram #(
	parameter operation_mode = "BIDIR_DUAL_PORT",
	parameter width_a = 1,
	parameter widthad_a = 1,
	parameter numwords_a = 0,
	parameter width_b = 1,
	parameter widthad_b = 1,
	parameter numwords_b = 0,
	parameter address_aclr_b = "NONE",
	parameter address_reg_b = "CLOCK1",
	parameter outdata_aclr_b = "NONE",
	parameter outdata_reg_b = "UNREGISTERED",
	parameter clock_enable_input_a = "NORMAL",
	parameter clock_enable_input_b = "NORMAL",
	parameter clock_enable_output_b = "NORMAL",
	parameter read_during_write_mode_mixed_ports = "DONT_CARE",
	parameter power_up_uninitialized = "FALSE",
	parameter ram_block_type = "AUTO",
	parameter width_byteena_a = 1,
	parameter intended_device_family = "unused",
	parameter lpm_type = "altsyncram"
) (
	input                    clock0,
	input                    clock1,
	input                    clocken0,
	input                    clocken1,
	input                    clocken2,
	input                    clocken3,
	input                    aclr0,
	input                    aclr1,
	input                    addressstall_a,
	input                    addressstall_b,
	input  [width_byteena_a-1:0] byteena_a,
	input                    byteena_b,
	input                    wren_a,
	input                    wren_b,
	input                    rden_a,
	input                    rden_b,
	input  [widthad_a-1:0]   address_a,
	input  [widthad_b-1:0]   address_b,
	input  [width_a-1:0]     data_a,
	input  [width_b-1:0]     data_b,
	output [width_a-1:0]     q_a,
	output [width_b-1:0]     q_b,
	output [2:0]             eccstatus
);

	initial begin
		if (operation_mode != "DUAL_PORT" ||
		    address_reg_b != "CLOCK0" ||
		    outdata_reg_b != "UNREGISTERED" ||
		    read_during_write_mode_mixed_ports != "OLD_DATA" ||
		    clock_enable_input_a != "BYPASS" ||
		    clock_enable_input_b != "BYPASS" ||
		    clock_enable_output_b != "BYPASS" ||
		    width_a != width_b || widthad_a != widthad_b ||
		    numwords_a != numwords_b || numwords_a != (1 << widthad_a) ||
		    width_byteena_a != 1) begin
			$display("altsyncram_model: a configuration this model does not cover");
			$finish;
		end
	end

	reg [width_a-1:0] mem [0:numwords_a-1];
	reg [width_b-1:0] q;

	always @(posedge clock0) begin
		if (wren_a && byteena_a[0] && !addressstall_a)
			mem[address_a] <= data_a;
		if (rden_b && !addressstall_b)
			q <= mem[address_b];
	end

	assign q_b = q;
	assign q_a = {width_a{1'b0}};
	assign eccstatus = 3'b000;

	// the ports the configuration ties off must be tied off as Quartus's
	// megafunction wizard does it
	always @(posedge clock0)
		if (aclr0 || aclr1 || wren_b || !rden_b || !clocken0 || addressstall_a ||
		    addressstall_b) begin
			$display("altsyncram_model: a port that must be tied off is active");
			$finish;
		end

endmodule

`default_nettype wire

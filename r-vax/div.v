/*	$Id$	*/

`timescale 1ns / 1ps
`default_nettype none
module div(
	input clock,
	input [31:0] dividend,
	input [31:0] divisor,
	input start,

	output [31:0] q,
	output [31:0] r,
	output reg busy
);

	reg [5:0] count;
	reg [31:00] reg_q;
	reg [31:00] reg_r;
	reg [31:00] reg_b;
	wire [31:00] reg_r2;
	reg busy2,r_sign;
//	assign ready=~busy&busy2;
	wire [32:0] sub_add=r_sign?({reg_r,reg_q[31]}+{1'b0,reg_b}):
			({reg_r,reg_q[31]}-{1'b0,reg_b});
	assign reg_r2=r_sign?reg_r+reg_b:reg_r;
	assign r=dividend[31]?(~reg_r2+1):reg_r2;
	assign q=(divisor[31]^dividend[31])?(~reg_q+1):reg_q;

	initial count = 0;
	initial busy = 0;
	initial busy2 = 0;
	
	always @(posedge clock) begin
		busy2<=busy;
		if(start)begin
			reg_r<=32'b0;
			r_sign<=0;
			if(dividend[31]==1) begin
				reg_q<=~dividend+1;
			end
			else reg_q<=dividend;
			if(divisor[31]==1)begin
				reg_b<=~divisor+1;
			end
			else reg_b<=divisor;
			count<=0;
			busy<=1;
		end else if(busy)begin
			reg_r<=sub_add[31:0];
			r_sign<=sub_add[32];
			reg_q<={reg_q[30:0],~sub_add[32]};
			count<=count+1;
			if(count==31)busy<=0;
		end
	end
endmodule
 

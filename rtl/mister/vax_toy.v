// vax_toy.v - the VAX 8600's time-of-year clock at power-up, from MiSTer's
// real-time clock.
//
// The 8600's TODR lives in its console subsystem, which "provides system
// time-of-year clock" with battery backup (VAX Hardware Handbook 1986,
// chapter 7; the CPU's microcode reads it through the console bus), so
// after power-up VMS and NetBSD find the time they left in it. The core has
// no battery; MiSTer's HPS sends the time of day when the core is loaded
// instead (hps_io's RTC: local time in BCD, the MSM6242B layout - seconds,
// minutes, hours, day, month, year mod 100 in bytes 0 to 5), and this
// module turns the first value that arrives into the TODR value VMS keeps
// there: hundredths of a second since 1 January 00:00 of the current year,
// plus 10000000 (hex) - the base NetBSD's clock code also uses, "from VMS".
// Later values are left alone, and so is an OSD reset: by then TODR
// belongs to the operating system, which may set it. Without an RTC value
// TODR starts at 0, as after a battery failure (VAX Architecture Reference
// Manual, the time-of-year clock: "the register is cleared upon
// power-up"), and VMS asks for the date.
//
// The year is taken as 2000 + the two digits: leap years are those whose
// two digits divide by 4, right from 2000 to 2099.

module vax_toy(
	input             clk,
	input      [64:0] rtc,      // hps_io RTC: <64> toggles with each value
	output reg        ld,       // one clock: TODR <- val
	output reg [31:0] val
);
	initial ld = 1'b0;
	initial val = 32'd0;

	function [6:0] bcd;         // two BCD digits to binary
		input [7:0] b;
		bcd = { 3'd0, b[7:4] } * 7'd10 + { 3'd0, b[3:0] };
	endfunction

	wire [6:0] sec  = bcd(rtc[7:0]);
	wire [6:0] min  = bcd(rtc[15:8]);
	wire [6:0] hour = bcd(rtc[23:16]);
	wire [6:0] mday = bcd(rtc[31:24]);
	wire [6:0] mon  = bcd(rtc[39:32]);
	wire [6:0] year = bcd(rtc[47:40]);

	reg [8:0] mdays;           // days in the months before this one
	always @*
		case (mon)
		7'd2:  mdays = 9'd31;
		7'd3:  mdays = 9'd59;
		7'd4:  mdays = 9'd90;
		7'd5:  mdays = 9'd120;
		7'd6:  mdays = 9'd151;
		7'd7:  mdays = 9'd181;
		7'd8:  mdays = 9'd212;
		7'd9:  mdays = 9'd243;
		7'd10: mdays = 9'd273;
		7'd11: mdays = 9'd304;
		7'd12: mdays = 9'd334;
		default: mdays = 9'd0;
		endcase

	wire leap = year[1:0] == 2'd0 && mon > 7'd2;
	wire valid = mon >= 7'd1 && mon <= 7'd12 && mday >= 7'd1 && mday <= 7'd31 &&
	             hour < 7'd24 && min < 7'd60 && sec < 7'd60;

	reg        t_d = 1'b0;      // RTC<64> last clock
	reg        armed = 1'b1;    // until the first value after power-up
	reg  [2:0] step = 3'd0;
	reg [13:0] hours;           // since 1 January 00:00
	reg [19:0] mins;
	reg [24:0] secs;

	always @(posedge clk) begin
		t_d <= rtc[64];
		ld <= 1'b0;
		case (step)
		3'd0: if (armed && rtc[64] != t_d) begin
			armed <= 1'b0;
			if (valid) begin
				hours <= ({ 5'd0, mdays } + mday - 14'd1 + leap) * 14'd24 + hour;
				step <= 3'd1;
			end
		end
		3'd1: begin
			mins <= { 6'd0, hours } * 20'd60 + min;
			step <= 3'd2;
		end
		3'd2: begin
			secs <= { 5'd0, mins } * 25'd60 + sec;
			step <= 3'd3;
		end
		3'd3: begin
			val <= 32'h10000000 + { 7'd0, secs } * 32'd100;
			step <= 3'd4;
		end
		default: begin
			ld <= 1'b1;
			step <= 3'd0;
		end
		endcase
	end
endmodule

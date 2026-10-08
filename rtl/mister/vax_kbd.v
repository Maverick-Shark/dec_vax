//============================================================================
//  vax_kbd.v - MiSTer ps2_key (PS/2 set 2 scancodes) to ASCII / VT100 keys.
//
//  Layouts: 0 = US, 1 = Spanish (ES). Non-ASCII keys of the ES layout produce
//  ISO Latin-1 / DEC MCS codes (n tilde = F1h, c cedilla = E7h, ...).
//
//  Special keys:  Enter -> CR, Backspace -> DEL (7Fh, VMS delete), Tab, Esc,
//                 Delete -> DEL, cursor keys -> ESC [ A..D,
//                 F1..F4 -> PF1..PF4 (ESC O P..S), keypad -> digits/operators.
//  Ctrl+key -> key & 1Fh for keys in 40h..7Fh. Caps Lock affects letters only.
//
//  Part of the MiSTer port of r-vax (VAX CPU in Verilog by Anders Magnusson).
//  SPDX-License-Identifier: BSD-2-Clause
//============================================================================

`default_nettype none

module vax_kbd (
	input            clk,
	input            rst,
	input     [10:0] ps2_key,    // [10] toggle, [9] pressed, [8] extended, [7:0] code
	input            layout_es,

	output reg [7:0] data,
	output reg       valid       // one byte per clock while a key sequence drains
);

	// ---------------------------------------------------------------- US
	function [7:0] us_map;
		input [7:0] code;
		input       sh;
		begin
			case (code)
			8'h0E: us_map = sh ? "~" : 8'h60;
			8'h16: us_map = sh ? "!" : "1";
			8'h1E: us_map = sh ? "@" : "2";
			8'h26: us_map = sh ? "#" : "3";
			8'h25: us_map = sh ? "$" : "4";
			8'h2E: us_map = sh ? "%" : "5";
			8'h36: us_map = sh ? "^" : "6";
			8'h3D: us_map = sh ? "&" : "7";
			8'h3E: us_map = sh ? "*" : "8";
			8'h46: us_map = sh ? "(" : "9";
			8'h45: us_map = sh ? ")" : "0";
			8'h4E: us_map = sh ? "_" : "-";
			8'h55: us_map = sh ? "+" : "=";
			8'h54: us_map = sh ? "{" : "[";
			8'h5B: us_map = sh ? "}" : "]";
			8'h5D: us_map = sh ? "|" : 8'h5C;
			8'h61: us_map = sh ? "|" : 8'h5C;
			8'h4C: us_map = sh ? ":" : ";";
			8'h52: us_map = sh ? 8'h22 : "'";
			8'h41: us_map = sh ? "<" : ",";
			8'h49: us_map = sh ? ">" : ".";
			8'h4A: us_map = sh ? "?" : "/";
			default: us_map = 8'h00;
			endcase
		end
	endfunction

	// ---------------------------------------------------------------- ES
	function [7:0] es_map;
		input [7:0] code;
		input       sh;
		input       agr;
		begin
			case (code)
			8'h0E: es_map = agr ? 8'h5C : sh ? 8'hAA : 8'hBA;   // ordinal indicators (masc/fem)
			8'h16: es_map = agr ? "|"  : sh ? "!"   : "1";
			8'h1E: es_map = agr ? "@"  : sh ? 8'h22 : "2";
			8'h26: es_map = agr ? "#"  : sh ? 8'hB7 : "3";   // middle dot
			8'h25: es_map = agr ? "~"  : sh ? "$"   : "4";
			8'h2E: es_map =              sh ? "%"   : "5";
			8'h36: es_map = agr ? 8'hAC: sh ? "&"   : "6";   // not sign
			8'h3D: es_map =              sh ? "/"   : "7";
			8'h3E: es_map =              sh ? "("   : "8";
			8'h46: es_map =              sh ? ")"   : "9";
			8'h45: es_map =              sh ? "="   : "0";
			8'h4E: es_map =              sh ? "?"   : "'";
			8'h55: es_map =              sh ? 8'hBF : 8'hA1; // inverted ? and !
			8'h54: es_map = agr ? "["  : sh ? "^"   : 8'h60;
			8'h5B: es_map = agr ? "]"  : sh ? "*"   : "+";
			8'h4C: es_map =              sh ? 8'hD1 : 8'hF1; // N/n tilde
			8'h52: es_map = agr ? "{"  : sh ? 8'hA8 : 8'hB4; // diaeresis, acute accent
			8'h5D: es_map = agr ? "}"  : sh ? 8'hC7 : 8'hE7; // C/c cedilla
			8'h61: es_map =              sh ? ">"   : "<";
			8'h41: es_map =              sh ? ";"   : ",";
			8'h49: es_map =              sh ? ":"   : ".";
			8'h4A: es_map =              sh ? "_"   : "-";
			default: es_map = 8'h00;
			endcase
		end
	endfunction

	// ------------------------------------------------- letters, common keys
	function [7:0] letter;
		input [7:0] code;
		begin
			case (code)
			8'h1C: letter = "a"; 8'h32: letter = "b"; 8'h21: letter = "c";
			8'h23: letter = "d"; 8'h24: letter = "e"; 8'h2B: letter = "f";
			8'h34: letter = "g"; 8'h33: letter = "h"; 8'h43: letter = "i";
			8'h3B: letter = "j"; 8'h42: letter = "k"; 8'h4B: letter = "l";
			8'h3A: letter = "m"; 8'h31: letter = "n"; 8'h44: letter = "o";
			8'h4D: letter = "p"; 8'h15: letter = "q"; 8'h2D: letter = "r";
			8'h1B: letter = "s"; 8'h2C: letter = "t"; 8'h3C: letter = "u";
			8'h2A: letter = "v"; 8'h1D: letter = "w"; 8'h22: letter = "x";
			8'h35: letter = "y"; 8'h1A: letter = "z";
			default: letter = 8'h00;
			endcase
		end
	endfunction

	function [7:0] common;            // non-extended keys independent of layout
		input [7:0] code;
		begin
			case (code)
			8'h29: common = " ";
			8'h5A: common = 8'h0D;        // Enter
			8'h66: common = 8'h7F;        // Backspace -> DEL
			8'h0D: common = 8'h09;        // Tab
			8'h76: common = 8'h1B;        // Esc
			8'h70: common = "0"; 8'h69: common = "1"; 8'h72: common = "2";
			8'h7A: common = "3"; 8'h6B: common = "4"; 8'h73: common = "5";
			8'h74: common = "6"; 8'h6C: common = "7"; 8'h75: common = "8";
			8'h7D: common = "9"; 8'h71: common = "."; 8'h79: common = "+";
			8'h7B: common = "-"; 8'h7C: common = "*";
			default: common = 8'h00;
			endcase
		end
	endfunction

	reg        last_toggle;
	reg        lshift, rshift, lctrl, rctrl, altgr, caps;
	reg  [7:0] seq0, seq1, seq2;      // pending bytes, seq0 goes out first
	reg  [1:0] nseq;

	initial begin
		last_toggle = 1'b0;
		{lshift, rshift, lctrl, rctrl, altgr, caps} = 6'd0;
		nseq  = 2'd0;
		valid = 1'b0;
	end

	wire       ev      = ps2_key[10] != last_toggle;
	wire       pressed = ps2_key[9];
	wire       ext     = ps2_key[8];
	wire [7:0] code    = ps2_key[7:0];
	wire       shift   = lshift | rshift;
	wire       ctrl    = lctrl | rctrl;

	wire [7:0] let_ch     = letter(code);
	wire       let_up  = shift ^ caps;
	wire [7:0] es_ch   = es_map(code, shift, altgr);
	wire       es_alpha= (es_ch == 8'hF1) || (es_ch == 8'hD1) || (es_ch == 8'hE7) || (es_ch == 8'hC7);
	// Caps Lock also flips n tilde / c cedilla on the ES layout
	wire [7:0] es_fix  = (es_alpha && caps) ? (es_ch ^ 8'h20) : es_ch;
	wire [7:0] lay_ch  = layout_es ? es_fix : us_map(code, shift);
	wire [7:0] com_ch  = common(code);

	reg  [7:0] ch;
	always @* begin
		ch = 8'h00;
		if (let_ch != 8'h00)
			ch = let_up ? (let_ch & 8'hDF) : let_ch;
		else if (lay_ch != 8'h00)
			ch = lay_ch;
		else
			ch = com_ch;
		if (ctrl && ch >= 8'h40 && ch <= 8'h7F)
			ch = ch & 8'h1F;
	end

	always @(posedge clk) begin
		valid <= 1'b0;

		// drain the pending sequence, one byte per clock
		if (nseq != 2'd0) begin
			data  <= seq0;
			valid <= 1'b1;
			seq0  <= seq1;
			seq1  <= seq2;
			nseq  <= nseq - 2'd1;
		end

		if (rst) begin
			{lshift, rshift, lctrl, rctrl, altgr} <= 5'd0;
			nseq <= 2'd0;
			last_toggle <= ps2_key[10];
		end else if (ev) begin
			last_toggle <= ps2_key[10];
			if (!ext) begin
				case (code)
				8'h12: lshift <= pressed;
				8'h59: rshift <= pressed;
				8'h14: lctrl  <= pressed;
				8'h58: if (pressed) caps <= ~caps;
				default: ;
				endcase
			end else begin
				case (code)
				8'h14: rctrl <= pressed;
				8'h11: altgr <= pressed;
				default: ;
				endcase
			end

			if (pressed && nseq == 2'd0) begin
				if (!ext) begin
					case (code)
					8'h05: begin seq0 <= 8'h1B; seq1 <= "O"; seq2 <= "P"; nseq <= 2'd3; end // F1 PF1
					8'h06: begin seq0 <= 8'h1B; seq1 <= "O"; seq2 <= "Q"; nseq <= 2'd3; end // F2 PF2
					8'h04: begin seq0 <= 8'h1B; seq1 <= "O"; seq2 <= "R"; nseq <= 2'd3; end // F3 PF3
					8'h0C: begin seq0 <= 8'h1B; seq1 <= "O"; seq2 <= "S"; nseq <= 2'd3; end // F4 PF4
					default:
						if (ch != 8'h00) begin
							seq0 <= ch;
							nseq <= 2'd1;
						end
					endcase
				end else begin
					case (code)
					8'h75: begin seq0 <= 8'h1B; seq1 <= "["; seq2 <= "A"; nseq <= 2'd3; end // up
					8'h72: begin seq0 <= 8'h1B; seq1 <= "["; seq2 <= "B"; nseq <= 2'd3; end // down
					8'h74: begin seq0 <= 8'h1B; seq1 <= "["; seq2 <= "C"; nseq <= 2'd3; end // right
					8'h6B: begin seq0 <= 8'h1B; seq1 <= "["; seq2 <= "D"; nseq <= 2'd3; end // left
					8'h71: begin seq0 <= 8'h7F; nseq <= 2'd1; end                          // Delete
					8'h5A: begin seq0 <= 8'h0D; nseq <= 2'd1; end                          // keypad Enter
					8'h4A: begin seq0 <= "/";   nseq <= 2'd1; end                          // keypad /
					default: ;
					endcase
				end
			end
		end
	end

endmodule

`default_nettype wire

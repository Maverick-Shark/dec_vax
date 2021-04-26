#!/usr/bin/awk -f
#
# Two microcode files are output;
#	uc-insn.hex - per-instruction defines and offset for next file.
#	uc-args.hex - the arg steps executed for each instruction.
#
# uc-insn.hex is 256 rows of 64 (72) bits each.
# Bit definition (right to left)
#	0-7	offset into uc-args
#	8	instruction has args
#	9	instruction is emulated (calling macrocode)
#
# uc-args.hex is 256 rows of 64 (72) bits each.
# Each row has bit 0-4 for each arg.
# Of them 0-2 are address mode;
#	read:   100
#	write   010
#	modify: 110
#	addr:   001
#	branch: 011
#
#	The next two (3-4) are the size of the arg;
#	byte    00
#	word    01
#	long    10
#	quad    11
#
#	5	set if emulated
#	6	set if last arg
#	15-8	argument byte if emulated
#	19-16	arg register to put arg in
#
#	# Bit 36-39 are used to mask the psw.
#
function h1tod1(h, d) {
	h = tolower(h);
	if (h == "a") d = 10;
	else if (h == "b") d = 11;
	else if (h == "c") d = 12;
	else if (h == "d") d = 13;
	else if (h == "e") d = 14;
	else if (h == "f") d = 15;
	else d = h+0;

	return d;
}

function hex2dec(h) {
	return h1tod1(substr(h,1,1)) * 16 + h1tod1(substr(h,2,1));
}

function err(s) {
	print "ERROR: " s;
	exit(1);
}

function bitset3(line, bit, val) {
	bit = 80 - bit;
#printf "bitset3: line %d bit %d val %s\n", line, bit, val#;
#printf "bitset3: pargl: %s\n", arglist[line];
	arglist[line] = substr(arglist[line], 1, bit-3) val \
		substr(arglist[line], bit+1);
#printf "bitset3: eargl: %s\n", arglist[line];
}

function bitset(lst, bit) {
	bit = 64 - bit;
	return substr(lst, 1, bit-1) "1" substr(lst, bit+1);
}

function line2hex(ln, lst,   i, n, rv) {
	if (length(lst) != 64)
		err("bad len " length(lst) " line " ln ": " lst);
	for (i = 1; i < 64; i+= 4) {
		n = substr(lst, i, 1) * 8 + \
		    substr(lst, i+1, 1) * 4 + \
		    substr(lst, i+2, 1) * 2 + \
		    substr(lst, i+3, 1);
		rv = rv sprintf("%X", n);
	}
	return rv;
}

function line2hex32(ln, lst,   i, n, rv) {
	if (length(lst) != 32)
		err("bad len32 " length(lst) " line " ln ": " lst);
	for (i = 1; i < 32; i+= 4) {
		n = substr(lst, i, 1) * 8 + \
		    substr(lst, i+1, 1) * 4 + \
		    substr(lst, i+2, 1) * 2 + \
		    substr(lst, i+3, 1);
		rv = rv sprintf("%X", n);
	}
	return rv;
}

function num2bit(num, sz,    shsz, i, rv) {
	for (i = shsz = 1; i < sz; i++)
		shsz *= 2;
# printf "num %d sz %d shsz %d\n", num, sz, shsz;
	for (i = sz-1; i >= 0; i--) {
		if (num >= shsz) {
# printf "%d >= %d: rv %s\n", num, shsz, rv;
			rv = rv "1";
			num -= shsz;
		} else
			rv = rv "0";
		shsz /= 2;
	}
# printf "rv  %s\n", rv;
	return rv;
}

function aluops(op) {
	if (op in aluop)
		return aluop[op];
	err(op " aluop not found");
}

function leftops(op) {
	if (op in leftop)
		return leftop[op];
	err(op " leftop not found");
}

function rightops(op) {
	if (op in rightop)
		return rightop[op];
	err(op " rightop not found");
}




BEGIN {
	# Get instruction name<->opcode mapping
#	FN="opcode.def";
#	while ((getline < FN) > 0) {
#		if (substr($1,1,1) == "#")
#			continue;
#		opmap[$2] = hex2dec($1)+0;
#	}
#	close(FN);

	# get legal microcode bit names and numbers
	FN="ucode.v";
	while ((getline < FN) > 0) {
		if ($1 != "`define")
			continue;
		legalbits[tolower($2)] = $3;
	}
	close(FN);

	# get ALU opcode names and numbers
	FN="aluops.vh";
	while ((getline < FN) > 0) {
		if ($1 != "`define")
			continue;
		aluop[tolower(substr($2,5))] = substr($3,4);
	}
	close(FN);

	# hidden bits
	fakearg["0"] = "00000000";
	fakearg["1"] = "00000001";
	fakearg["pc"] = "01011111";
	fakearg["(sp)+"] = "10001110";
	fakearg["-(sp)"] = "01111110";
	fakearg["(pc)+"] = "10001111";
	fakearg["b^d(pc)"] = "10101111";
	fakearg["w^d(pc)"] = "11001111";

	# used for ALU MUX
	leftop["arg0"] = 0;

	rightop["arg1"] = 1;

	curargoff=0;
	emuloff = 1;
	stepoff = 0;

	# arglist contains the argument specifications.
	# inslist contains the instructions
	#
	# Create instruction specifications
	FN="ucode.def";
	lineno = 1;
	while ((getline < FN) > 0) {
		lineno++;
		if (substr($1,1,1) == "#")
			continue;
		if (NF == 0)
			continue;
		if ($1 == "!OPCODES") { state = 1; continue; }
		if ($1 == "!MICROCODE") { state = 2; continue; }
		if ($1 == "!INSTRUCTIONS") { state = 3; continue; }

		if (state == 1) {
			opmap[$2] = hex2dec($1)+0;
			continue;
		}

		if (state == 2) {
			shiftoff = 1;
			if ($1 ~ /.*:/) {
				steplbl[substr($1,1,length($1)-1)] = stepoff;
				shiftoff++;
			}
			ucstep[stepoff] = "00000000000000000000" \
			    num2bit(leftops($(shiftoff+1)), 4) \
			    num2bit(rightops($(shiftoff+2)), 4) \
			    num2bit(aluops($shiftoff), 4);
			stepoff++;
			continue;
		}

		if (!($1 in opmap))
			err($1 " not found");
		insnr = opmap[$1];	# insnr is instruction number
		n = split($2,a,",");

		if (insnr in inslist)
			err("duplicate " $1);

		inslist[insnr] = "0000000000000000000000000000000000000000" \
		    "000000000000000" \
		    ($2 != "-" ? "1" : "0") num2bit(curargoff,8);
# print "insnr " insnr " num2bit(curargoff,8) " num2bit(curargoff,8);

		rdcnt = 0;
		wrcnt = 0;
		if ($2 != "-")
		for (i = 1; i <= n; i++) {
			setrd = setwr = 0;
			rdno = -1;
			c = substr(a[i], 1, 1);
			if (c >= 0 && c <= 9) {
				rdno = c+0;
				a[i] = substr(a[i], 2);
				c = substr(a[i], 1, 1);
			}
# print $1 ": rdno " rdno " a[i] " a[i];

			if (c == "r") { al = "100"; setrd = 1; }
			else if (c == "w") { al = "010"; setwr = 1; }
			else if (c == "m") { al = "110"; setwr = setrd = 1; }
			else if (c == "a") { al = "001"; setrd = 1; }
			else if (c == "b") { al = "011"; setrd = 1; } # XXX
			else err("bad c " c);

			c = substr(a[i], 2, 1);
			if (c == "b") al = "00" al;
			else if (c == "w") al = "01" al;
			else if (c == "l") al = "10" al;
			else if (c == "q") al = "11" al;
			else err("bad c2 " c);

			earg = "00000000";
			isearg = "0";
			if (length(a[i]) > 2) {
				if (substr(a[i], 3, 1) != "#")
					err("bad arg " a[i]);
				c = substr(a[i], 4);
				if (c in fakearg) {
					earg = fakearg[c];
					isearg = "1";
				} else
					err("bad fake arg " a[i]);
			}

			rdwr = "0000";
			if (rdno >= 0) {
				rdwr = num2bit(rdno,3);
				rdcnt++;
			} else if (setrd) {
				rdwr = num2bit(rdcnt,3);
				rdcnt++;
			} else
				rdwr = "000";
			if (setwr) {
				rdwr = wrcnt rdwr;
				wrcnt++;
			} else
				rdwr = "0" rdwr;
			arglist[curargoff++] = \
			    "00000000000000000000000000000000000000000000" \
			    rdwr earg "0" (i==n? "1" : "0") isearg al;

		}

		for (i = 3; i <= NF; i++) {
			if ($i == "#")
				break;
			if (substr($i,1,4) == "lbl=") {
				lbl = substr($i,5);
				if (lbl in steplbl) {
#printf "lbl %s step %s insl1 %s\n", lbl, steplbl[lbl], inslist[insnr];
					lbbits = num2bit(steplbl[lbl], 9);
#printf "1: %s %s %s\n", substr(inslist[insnr], 1, 64-56), num2bit(steplbl[lbl], 9), substr(inslist[insnr], 1, 64-46);
					inslist[insnr] = \
					    substr(inslist[insnr], 1, 64-56) \
					    num2bit(steplbl[lbl], 9) \
					    substr(inslist[insnr], 64-46);
#printf "lbl2 %s step %s insl1 %s\n", lbl, steplbl[lbl], inslist[insnr];
				} else
					err("bad label " lbl);

			} else if ($i in legalbits) {
				inslist[insnr] = \
				    bitset(inslist[insnr], legalbits[$i]);
			} else
				err("bad bit " $i " line " lineno);
		}


	}
	close(FN);

	# print out instructions
	FN="uc-insn.hex";
	system("rm -f " FN);
	for (i = 0; i < 256; i++) {
		if (i in inslist) {
			print line2hex(i, inslist[i]) >> FN;
			numinst++;
		} else
			print "8000000000000000" >> FN;
	}
	close(FN);
	print "instructions " numinst;

	# print out arguments
	FN="uc-args.hex";
	system("rm -f " FN);
	for (i = 0; i < 256; i++) {
		if (i in arglist) {
			print line2hex(i, arglist[i]) >> FN;
			numargs++;
		} else
			print "0000000000000000" >> FN;
	}
	close(FN);
	print "arguments " numargs;

	# print out microcode steps
	FN="uc-step.hex";
	system("rm -f " FN);
	for (i = 0; i < 512; i++) {
		if (i in ucstep) {
			print line2hex32(i, ucstep[i]) >> FN;
			numstep++;
		} else
			print "00000000" >> FN;
	}
	close(FN);
	print "microcode steps " numstep;

}

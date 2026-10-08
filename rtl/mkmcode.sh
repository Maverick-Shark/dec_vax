#!/bin/sh
#	$Id$

AS=vaxas
LD=vaxld
OBJCOPY=vaxobjcopy
INFIL=mcode

/usr/local/bin/pcpp -x assembler-with-cpp ${INFIL}.s | ${AS} -o ${INFIL}.o
if [ $? -ne 0 ]; then
	exit 1;
fi

${LD} -e 0 -n -o ${INFIL}.bin ${INFIL}.o
if [ $? -ne 0 ]; then
	exit 1;
fi

${OBJCOPY} -O verilog ${INFIL}.bin ${INFIL}.bhex
if [ $? -ne 0 ]; then
	exit 1;
fi

awk '
BEGIN {
	getline;
	while (getline > 0) {
		for (i = 1; i <= 16; i++)
			if (i >= NF)
				$i = "00";
		for (i = 1; i <= 16; i+=4)
			printf "%s%s%s%s\n",$(i+3), $(i+2), $(i+1), $i;
		nlines += 4;
	}
	while (nlines++ < 512)
		print "00000000";
}' ${INFIL}.bhex > ${INFIL}.hex

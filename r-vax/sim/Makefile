#	$Id$
#
#
#SYSINC=/opt/local/share/verilator/include
SYSINC=/opt/pkg/share/verilator/include
VERCPP=${SYSINC}/verilated.cpp
SUBDIR=nvaxdir
TSUBDIR=nvaxtracedir
ANAME=${SUBDIR}/Vnvax__ALL.a
TANAME=${TSUBDIR}/Vnvax__ALL.a
VPATH=..
DEST=nvax
TDEST=nvax_trace
OBJS=nvax.o ttotest.o ttitest.o verilated.o sdramtest.o disasm.o
CFLAGS=-g -std=c++11
VFLAGS=-Wno-fatal -Wall

TOP=sbi.v
SRCS=console.v cpu.v decode.v opspec.v sbi.v sdram.v vcache.v \
	ipr.v qbus.v dl11_tto.v ucode.v

all:  ${DEST} # ${TDEST}

${DEST}: ${OBJS} ${ANAME}
	clang++ -g ${OBJS} ${ANAME} -o ${DEST}

verilated.o: ${SYSINC}/verilated.cpp
	clang++ -I ${SUBDIR} -I ${SYSINC} ${CFLAGS} -c $<

.cpp.o:
	clang++ -I ${SUBDIR} -I ${SYSINC} ${CFLAGS} -c $<

${OBJS}: ${ANAME}

${TDEST}: nvax.cpp ${TANAME}
	clang++ -DUSETRACE -I ${TSUBDIR} -I ${SYSINC} nvax.cpp ${VERCPP} ${TANAME} \
	${SYSINC}/verilated_vcd_c.cpp -o ${TDEST}

${ANAME}: ${SRCS}
	verilator ${VFLAGS} -Mdir ${SUBDIR} --prefix Vnvax -cc -y .. ${TOP}
	(cd ${SUBDIR}; make -f Vnvax.mk)

${TANAME}: ${SRCS}
	verilator --trace ${VFLAGS} -Mdir ${TSUBDIR} --prefix Vnvax -cc -y .. ${TOP}
	(cd ${TSUBDIR}; make -f Vnvax.mk)

clean:
	/bin/rm -rf ${DEST} ${TDEST} ${SUBDIR} ${TSUBDIR} ${OBJS}

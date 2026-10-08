# Verilator simulation of the MiSTer port (run from the project root:
#   make -C sim   then   sim/obj/Vtb_top software/hello.bin 0 "1000P~"   )
RVAX = div.v ucode.v intrpt.v intclk.v constx.v consrx.v console.v \
       argdecode.v alu.v vcache.v cpu.v
MISTER = vax_uart.v vax_kbd.v vt_font.v vt_term.v vax_sdram.v vax_core.v vax_system.v
SRC = $(addprefix ../rtl/,$(RVAX)) $(addprefix ../rtl/mister/,$(MISTER)) sdram_model.v tb_top.v

obj/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=434 --public-flat-rw -I../rtl --top-module tb_top \
	  -Mdir obj $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

unit: obj_unit/Vunit_top

clean:
	rm -rf obj obj_unit

UNIT = $(addprefix ../rtl/mister/,vt_font.v vt_term.v vax_kbd.v) unit_top.v

obj_unit/Vunit_top: $(UNIT) unit_tb.cpp
	verilator --cc --exe --build -j 4 -Wno-fatal -Wno-WIDTH --public-flat-rw --top-module unit_top \
	  -Mdir obj_unit $(UNIT) unit_tb.cpp -CFLAGS "-O1 -w" -o Vunit_top

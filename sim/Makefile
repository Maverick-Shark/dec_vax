# Verilator simulation of the MiSTer port (run from the project root:
#   make -C sim   then   sim/obj/Vtb_top software/hello.bin 0 "1000P~"   )
MISTER = vax_uart.v vax_kbd.v vt_font.v vt_term.v vax_msg.v vax_selftest.v \
         vax_sdram.v vax_cache.v vax_core.v vax_system.v
RVAX = div.v ucode.v intrpt.v intclk.v constx.v consrx.v console.v mmu.v \
       argdecode.v alu.v vcache.v cpu.v
SRC = $(addprefix ../rtl/,$(RVAX)) $(addprefix ../rtl/mister/,$(MISTER)) sdram_model.v tb_top.v

obj/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 --public-flat-rw -I../rtl --top-module tb_top \
	  -Mdir obj $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

# CPU-level test bench (cpu, vcache, mmu, plain memory) for tests/mmu
CPUTB = $(addprefix ../rtl/,$(RVAX)) cpu_tb/tb_cpu.v

cputb: obj_cpu/Vtb_cpu

obj_cpu/Vtb_cpu: $(CPUTB) cpu_tb/tb_cpu.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 --public-flat-rw -I../rtl --top-module tb_cpu \
	  -Mdir obj_cpu $(CPUTB) cpu_tb/tb_cpu.cpp -CFLAGS "-O1 -w" -o Vtb_cpu

unit: obj_unit/Vunit_top

clean:
	rm -rf obj obj_unit obj_nc obj_e obj_l obj_cpu

UNIT = $(addprefix ../rtl/mister/,vt_font.v vt_term.v vax_kbd.v) unit_top.v

obj_unit/Vunit_top: $(UNIT) unit_tb.cpp
	verilator --cc --exe --build -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  --public-flat-rw --top-module unit_top \
	  -Mdir obj_unit $(UNIT) unit_tb.cpp -CFLAGS "-O1 -w" -o Vunit_top

# measurement build with the cache forced to always miss
obj_nc/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 -DCACHE_NOHIT --public-flat-rw \
	  -I../rtl --top-module tb_top -Mdir obj_nc $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

nocache: obj_nc/Vtb_top

# builds that model read data arriving one SDRAM clock early or late
obj_e/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 --public-flat-rw -I../rtl \
	  --top-module tb_top -GCL_SKEW=-1 -Mdir obj_e $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

obj_l/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 --public-flat-rw -I../rtl \
	  --top-module tb_top -GCL_SKEW=1 -Mdir obj_l $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

skew: obj_e/Vtb_top obj_l/Vtb_top

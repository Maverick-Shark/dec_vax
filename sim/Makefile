# Verilator simulation of the MiSTer port (run from the project root:
#   make -C sim   then   sim/obj/Vtb_top software/hello.bin 0 "1000P~"   )
MISTER = vax_uart.v vax_kbd.v vt_font.v vt_term.v vax_msg.v vax_selftest.v \
         vax_sdram.v vax_cache.v vax_core.v vax_system.v
RVAX = div.v ucode.v intrpt.v intclk.v constx.v consrx.v console.v mmu.v \
       argdecode.v alu.v vcache.v decunit.v cpu.v
SRC = $(addprefix ../rtl/,$(RVAX)) $(addprefix ../rtl/mister/,$(MISTER)) sdram_model.v tb_top.v

obj/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 --public-flat-rw -I../rtl --top-module tb_top \
	  -Mdir obj $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

# the same, optimized harder: for long runs (the Diagnostic Supervisor and
# EVKAE, tests/evkae/run_sim.sh)
obj_fast/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast \
	  -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  --public-flat-rw -I../rtl --top-module tb_top -Mdir obj_fast $(SRC) tb.cpp \
	  -CFLAGS "-O2 -w" -o Vtb_top

fast: obj_fast/Vtb_top

# CPU-level test bench (cpu, vcache, mmu, plain memory) for tests/mmu
CPUTB = $(addprefix ../rtl/,$(RVAX)) cpu_tb/tb_cpu.v

cputb: obj_cpu/Vtb_cpu

obj_cpu/Vtb_cpu: $(CPUTB) cpu_tb/tb_cpu.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 --public-flat-rw -I../rtl --top-module tb_cpu \
	  -Mdir obj_cpu $(CPUTB) cpu_tb/tb_cpu.cpp -CFLAGS "-O1 -w" -o Vtb_cpu

unit: obj_unit/Vunit_top

# unit test of the decimal unit against a C model of its operations
dutb: obj_du/Vdecunit

obj_du/Vdecunit: ../rtl/decunit.v du_tb/du_tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  --top-module decunit -Mdir obj_du ../rtl/decunit.v du_tb/du_tb.cpp \
	  -CFLAGS "-O1 -w" -o Vdecunit

clean:
	rm -rf obj obj_unit obj_nc obj_e obj_l obj_cpu obj_fast obj_du obj_dqma

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

# the same, with the SDRAM chip taking its byte masks from A11/A12 (the
# wiring of the 128 MB modules), optimised like obj_fast
obj_dqma/Vtb_top: $(SRC) tb.cpp
	verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast \
	  -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  -DDQM_ON_A --public-flat-rw -I../rtl --top-module tb_top -Mdir obj_dqma \
	  $(SRC) tb.cpp -CFLAGS "-O2 -w" -o Vtb_top

dqma: obj_dqma/Vtb_top

# a strict second opinion on the Verilog: Icarus Verilog must compile it all
lint:
	iverilog -g2012 -o /dev/null -I../rtl -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  -s tb_top $(SRC)
	iverilog -g2012 -o /dev/null -I../rtl -DMISTER -s decunit ../rtl/decunit.v

# Verilator simulation of the MiSTer port (run from the project root:
#   make -C sim   then   sim/obj/Vtb_top software/hello.bin 0 "1000P~"   )
MISTER = vax_uart.v vax_kbd.v vt_font.v vt_term.v vax_msg.v vax_selftest.v \
         vax_sdram.v vax_cache.v vax_sbi.v vax_uba.v vax_mba.v vax_rp07.v vax_io.v \
         vax_core.v vax_system.v
RVAX = div.v ucode.v intrpt.v intclk.v constx.v consrx.v cons86.v console.v mmu.v \
       argdecode.v alu.v vcache.v decunit.v fpunit.v cmdecode.v cpu.v
SRC = $(addprefix ../rtl/,$(RVAX)) $(addprefix ../rtl/mister/,$(MISTER)) sdram_model.v tb_top.v

obj/Vtb_top: $(SRC) tb.cpp hpsdisk.h
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 --public-flat-rw -I../rtl --top-module tb_top \
	  -Mdir obj $(SRC) tb.cpp -CFLAGS "-O1 -w" -o Vtb_top

# the same, optimized harder: for long runs (the Diagnostic Supervisor and
# EVKAE, tests/evkae/run_sim.sh)
obj_fast/Vtb_top: $(SRC) tb.cpp hpsdisk.h
	verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast \
	  -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  --public-flat-rw -I../rtl --top-module tb_top -Mdir obj_fast $(SRC) tb.cpp \
	  -CFLAGS "-O2 -w" -o Vtb_top

fast: obj_fast/Vtb_top

# CPU-level test bench (cpu, vcache, mmu, plain memory) for tests/mmu
CPUTB = $(addprefix ../rtl/,$(RVAX)) ../rtl/mister/vax_sbi.v ../rtl/mister/vax_uba.v \
        ../rtl/mister/vax_mba.v \
        ../rtl/mister/vax_rp07.v ../rtl/mister/vax_io.v cpu_tb/ubdev.v cpu_tb/tb_cpu.v

cputb: obj_cpu/Vtb_cpu

obj_cpu/Vtb_cpu: $(CPUTB) cpu_tb/tb_cpu.cpp hpsdisk.h
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

# unit test of the floating point unit against the exact model in
# fpu_tb/vaxfp.py:  make -C sim fputb && python3 sim/fpu_tb/vaxfp.py v.txt
# 20000 && sim/obj_fpu/Vfpunit v.txt
fputb: obj_fpu/Vfpunit

obj_fpu/Vfpunit: ../rtl/fpunit.v fpu_tb/fpu_tb.cpp
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  --top-module fpunit -Mdir obj_fpu ../rtl/fpunit.v fpu_tb/fpu_tb.cpp \
	  -CFLAGS "-O1 -w" -o Vfpunit

clean:
	rm -rf obj obj_unit obj_nc obj_e obj_l obj_cpu obj_fast obj_du obj_dqma obj_fpu obj_cpux obj_x obj_cpuf

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

# Power-up state. These builds start every register that has no initial
# value with random contents (and the all-ones or random choice is made when
# they run: +verilator+rand+reset+1 or +verilator+rand+reset+2 with
# +verilator+seed+n, after the other arguments), where the builds above
# start them at zero. Whatever processor initialization leaves undefined and
# the machine then depends on shows up as a failing test; on the board such
# a register is at the mercy of how Quartus implements it.
#   RTLBIN="sim/obj_cpux/Vtb_cpu" with tests/mmu/run.py (RTLARGS for the
#   plusargs), sim/obj_x/Vtb_top like sim/obj/Vtb_top.
obj_cpux/Vtb_cpu: $(CPUTB) cpu_tb/tb_cpu.cpp hpsdisk.h
	verilator --cc --exe --build -j 4 -O2 --x-initial unique --x-assign unique \
	  -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 --public-flat-rw -I../rtl --top-module tb_cpu \
	  -Mdir obj_cpux $(CPUTB) cpu_tb/tb_cpu.cpp -CFLAGS "-O1 -w" -o Vtb_cpu

cputbx: obj_cpux/Vtb_cpu

# The CPU bench with the translation buffer's RAM as Quartus builds it: the
# altsyncram instance of rtl/mmu.v (TB_ALTSYNCRAM, which files.qip defines
# for Quartus) on a model of the megafunction, altsyncram_model.v. The tests
# must pass here as on obj_cpu (RTLBIN="sim/obj_cpuf/Vtb_cpu" with
# tests/mmu/run.py). It also takes a fault in that RAM: +TBFAULT=100+k
# (bit k of the word written stuck at 1) or +TBFAULT=200+k (stuck at 0),
# after the other arguments; tests/diag/tbfault.py runs mmudiag.bin with
# every fault and checks what the diagnostic says.
obj_cpuf/Vtb_cpu: $(CPUTB) altsyncram_model.v cpu_tb/tb_cpu.cpp hpsdisk.h
	verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
	  -DMISTER -DCLKPERBIT=16 -DTBFAULT -DTB_ALTSYNCRAM --public-flat-rw -I../rtl \
	  --top-module tb_cpu -Mdir obj_cpuf $(CPUTB) altsyncram_model.v \
	  cpu_tb/tb_cpu.cpp -CFLAGS "-O1 -w" -o Vtb_cpu

cputbf: obj_cpuf/Vtb_cpu

obj_x/Vtb_top: $(SRC) tb.cpp hpsdisk.h
	verilator --cc --exe --build -j 4 -O2 --x-initial unique --x-assign unique \
	  -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  --public-flat-rw -I../rtl --top-module tb_top -Mdir obj_x $(SRC) tb.cpp \
	  -CFLAGS "-O1 -w" -o Vtb_top

sysx: obj_x/Vtb_top

# a strict second opinion on the Verilog: Icarus Verilog must compile it all
lint:
	iverilog -g2012 -o /dev/null -I../rtl -DMISTER -DCLKPERBIT=16 -DCACHEIDX=10 \
	  -s tb_top $(SRC)
	iverilog -g2012 -o /dev/null -I../rtl -DMISTER -s decunit ../rtl/decunit.v
	iverilog -g2012 -o /dev/null -I../rtl -DMISTER -s fpunit ../rtl/fpunit.v

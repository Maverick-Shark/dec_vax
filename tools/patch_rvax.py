#!/usr/bin/env python3
"""
patch_rvax.py - minimal, idempotent changes applied to the original r-vax RTL
for the MiSTer build. Run from the project root:  python3 tools/patch_rvax.py

 1. Incomplete sensitivity lists -> always @*  (alu.v, console.v, cpu.v).
    Synthesis ignored them, but simulation diverged from hardware (the IPR
    read mux in cpu.v hung the console after the first character).

 2. ucode.v: under `define MISTER the microcode ROM images are read from
    rtl/uc-*.hex (Quartus resolves $readmemh paths from the project folder),
    and the three ROMs are forced into M10K block RAM. Left to itself Quartus
    can decide to build a 110 Kbit ROM out of logic, which costs thousands of
    ALMs and wrecks the timing.

 3. cpu.v: the register file and the IPR file carry a Xilinx `ram_style`
    attribute that Quartus ignores. Add the Altera equivalent so they stay in
    logic/MLAB - they have several read ports and do not belong in M10K.

 4. cpu.v: expose the existing internal `halted` signal as a port, so the
    MiSTer layer can light the activity LED and report CPU state.

 5. cpu.v: two $fdisplay calls were left unguarded while all the others sit
    behind `if (debug)`. Quartus only warns about them, but they flood the
    Verilator console session transcripts, so guard them the same way.

 6. intclk.v: the microsecond divider counts from CLKINIT up to and including
    128, which is 128 - CLKINIT + 1 states: 4Eh gives 51 clocks, so the
    interval timer (ICR) and TODR ran 2 % slow at 50 MHz. 4Fh gives the 50
    clocks the comment intends. Same off-by-one in the 10 ms TODR divider:
    18F0h counts 10001 microseconds, 18F1h counts 10000.
"""
import os
import re
import sys

RTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rtl")

SENS = {
    "alu.v": [r"always @\(op\)"],
    "console.v": [r"always @\(htoa\) begin"],
    "cpu.v": [
        r"always @\(ipr_regaddr, icr, ipr_val_tmp,\s*\n\s*iccs_err, iccs_int, iccs_ie, iccs_run\)",
        r"always @\(mcodectr, psl, curpc, oldpc, cur_inst,\s*\n\s*mc_rv_tmp, mc_rv_tmp2\)",
        r"always @\(a_argsz\)",
    ],
}

UCODE_ROMS = [("uc-insn.hex", "ucinsn_rom", "I_ROM_ADDRS", "I_ROM_WIDTH"),
              ("uc-args.hex", "ucargs_rom", "A_ROM_ADDRS", "A_ROM_WIDTH"),
              ("uc-step.hex", "ucstep_rom", "S_ROM_ADDRS", "S_ROM_WIDTH")]


def patch(name, fn):
    path = os.path.join(RTL, name)
    with open(path, newline="") as f:
        src = f.read()
    crlf = "\r\n" in src
    txt = src.replace("\r\n", "\n")
    new = fn(txt)
    if new != txt:
        if crlf:
            new = new.replace("\n", "\r\n")
        with open(path, "w", newline="") as f:
            f.write(new)
        print("patched", name)
    else:
        print("ok     ", name)


def fix_sens(pats):
    def fn(txt):
        for p in pats:
            txt = re.sub(p, lambda m: "always @*" + (" begin" if m.group(0).endswith("begin") else ""), txt)
        return txt
    return fn


def fix_ucode(txt):
    for hexf, rom, nadr, nwid in UCODE_ROMS:
        # ROM path: keep the original for the stand-alone r-vax simulator
        old = '\tinitial $readmemh("%s", %s, 0, %s-1);\n' % (hexf, rom, nadr)
        new = ('`ifdef MISTER\n'
               '\tinitial $readmemh("rtl/%s", %s, 0, %s-1);\n'
               '`else\n'
               '\tinitial $readmemh("%s", %s, 0, %s-1);\n'
               '`endif\n') % (hexf, rom, nadr, hexf, rom, nadr)
        if old in txt and ('"rtl/%s"' % hexf) not in txt:
            txt = txt.replace(old, new)
        # keep the microcode in block RAM
        decl = '\treg [%s-1:0] %s [%s-1:0];\n' % (nwid, rom, nadr)
        attr = '\t(* ramstyle = "M10K" *)\n' + decl
        if decl in txt and 'ramstyle = "M10K" *)\n\treg [%s-1:0] %s' % (nwid, rom) not in txt:
            txt = txt.replace(decl, attr)
    return txt


def fix_cpu_ram(txt):
    # Quartus equivalent of the Xilinx attribute already there
    old = '\t(* ram_style = "DISTRIBUTED" *)\n'
    new = '\t(* ram_style = "DISTRIBUTED" *) (* ramstyle = "logic" *)\n'
    if old in txt:
        txt = txt.replace(old, new)
    return txt


DBG = [
    '$fdisplay(32\'h80000002, "MCODE: ctr %d mc_rv %x\\r", mcodectr, mc_rv);',
    '$fdisplay(32\'h80000002, "S_WRITEMEM2: mcheck %x", cpu_addr);',
]


def fix_cpu_debug(txt):
    for d in DBG:
        if "\n" + d in txt:
            txt = txt.replace("\n" + d, "\nif (debug) " + d)
    return txt


def fix_cpu_halted(txt):
    old = "\toutput\t\ttto_tx,\n\tinput\t\ttti_rx,\n\toutput\t\tcpu_mcheck\n"
    new = "\toutput\t\ttto_tx,\n\tinput\t\ttti_rx,\n\toutput\t\tcpu_halted,\n\toutput\t\tcpu_mcheck\n"
    if old in txt:
        txt = txt.replace(old, new)
    anchor = "\tassign cpu_mcheck  = mcheck;\n"
    add = anchor + "\tassign cpu_halted  = halted;\n"
    if anchor in txt and "assign cpu_halted" not in txt:
        txt = txt.replace(anchor, add)
    return txt


INTCLK = [("parameter CLKINIT =\t8'h4e;\t// 50MHz clock to microseconds. (128-50)",
           "parameter CLKINIT =\t8'h4f;\t// 50MHz clock to microseconds: 79..128 = 50 states"),
          ("parameter TODRCNTINIT =\t15'h18f0; // 10 ms clock",
           "parameter TODRCNTINIT =\t15'h18f1; // 10 ms clock: 6385..16384 = 10000 us")]


def fix_intclk(txt):
    for old, new in INTCLK:
        txt = txt.replace(old, new)
    return txt


def main():
    for name, pats in SENS.items():
        patch(name, fix_sens(pats))
    patch("ucode.v", fix_ucode)
    patch("cpu.v", fix_cpu_ram)
    patch("cpu.v", fix_cpu_halted)
    patch("cpu.v", fix_cpu_debug)
    patch("intclk.v", fix_intclk)
    return 0


if __name__ == "__main__":
    sys.exit(main())

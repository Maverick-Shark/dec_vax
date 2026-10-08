#!/usr/bin/env python3
"""
patch_rvax.py - minimal, idempotent fixes applied to the original r-vax RTL
for the MiSTer build. Run from the project root:  python3 tools/patch_rvax.py

 1. Incomplete sensitivity lists -> always @*  (alu.v, console.v, cpu.v).
    Synthesis ignored them, but simulation diverged from hardware (the IPR
    read mux in cpu.v hung the console after the first character).
 2. ucode.v: under `define MISTER the microcode ROM images are read from
    rtl/uc-*.hex (Quartus resolves $readmemh paths from the project folder).
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

UCODE_OLD = '\tinitial $readmemh("{0}", {1}, 0, {2}-1);\n'
UCODE_NEW = ('`ifdef MISTER\n'
             '\tinitial $readmemh("rtl/{0}", {1}, 0, {2}-1);\n'
             '`else\n'
             '\tinitial $readmemh("{0}", {1}, 0, {2}-1);\n'
             '`endif\n')
UCODE_ROMS = [("uc-insn.hex", "ucinsn_rom", "I_ROM_ADDRS"),
              ("uc-args.hex", "ucargs_rom", "A_ROM_ADDRS"),
              ("uc-step.hex", "ucstep_rom", "S_ROM_ADDRS")]


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
    for hexf, rom, n in UCODE_ROMS:
        old = UCODE_OLD.format(hexf, rom, n)
        if old in txt and ('"rtl/%s"' % hexf) not in txt:
            txt = txt.replace(old, UCODE_NEW.format(hexf, rom, n))
    return txt


def main():
    for name, pats in SENS.items():
        patch(name, fix_sens(pats))
    patch("ucode.v", fix_ucode)
    return 0


if __name__ == "__main__":
    sys.exit(main())

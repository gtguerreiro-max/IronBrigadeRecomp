"""Finds function starts that ReXGlue codegen did not discover (functions reached only through a
pointer: callbacks, function tables outside vtables), and adds them to tools/hints/default.txt.

Inputs: build/default.bin (the loaded image from 0x82000000, written by
`ironbrigade.exe --ironbrigade_dump_image=...`, src/image_dump.cpp) and the generated code
(generated/default, read with PGR4Native's scripts/analysis/tu_address_map.py).

A candidate is an address in the code section that no recompiled function covers (from a
function's start to its last instruction), that follows code which cannot fall through into it
(blr, bctr, an unconditional b, or zero padding), and that something points to (a big-endian
word in the image equal to it, or an address built with lis + addi / ori within 32
instructions) or that begins with a prologue (mflr r12, stwu r1). That is the same test
FromDustDeck's gen_manifest.py --seed-old applies to the XenonRecomp port's function list.

    python tools/find_functions.py [--write]
"""
import importlib.util
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = 0x82000000
CODE = (0x82100000, 0x82B1DEAC)  # runtime log: "Function table initialized ... code=..."
# The import thunks (generated/default/ironbrigade_init.cpp's __imp__ table: 0x82B07FA4 to
# 0x82B09074, 16 bytes each) are pointed to but are not functions to recompile.
IMPORTS = (0x82B07F00, 0x82B09100)

spec = importlib.util.spec_from_file_location(
    "tu", os.path.join(os.environ.get("PGR4_NATIVE", r"F:\PGR4Native"), "scripts", "analysis",
                       "tu_address_map.py"))
tu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tu)


def main():
    img = (ROOT / "build/default.bin").read_bytes()
    word = lambda a: int.from_bytes(img[a - BASE:a - BASE + 4], "big")
    funcs = tu.listings(str(ROOT / "generated/default"))
    covered = bytearray((CODE[1] - CODE[0]) // 4 + 1)
    for f, insns in funcs.items():
        if not insns or not CODE[0] <= f < CODE[1]:
            continue
        end = max(a for a, _ in insns)
        for a in range(f, min(end, CODE[1] - 4) + 4, 4):
            covered[(a - CODE[0]) // 4] = 1

    words = [int.from_bytes(img[i:i + 4], "big") for i in range(0, len(img) - 3, 4)]
    pointed = set(w for w in words if CODE[0] <= w < CODE[1] and not w & 3)
    built = set()
    for i, w in enumerate(words):
        if w >> 26 != 15 or (w >> 16) & 31:  # lis rD,hi
            continue
        rd, hi = (w >> 21) & 31, (w & 0xFFFF) << 16
        for v in words[i + 1:i + 33]:
            op = v >> 26
            if op == 14 and (v >> 16) & 31 == rd:  # addi rX,rD,lo
                built.add((hi + (v & 0xFFFF) - ((v & 0x8000) << 1)) & 0xFFFFFFFF)
            elif op == 24 and (v >> 21) & 31 == rd:  # ori rX,rD,lo
                built.add(hi | (v & 0xFFFF))

    def ends_flow(w):
        return w in (0x4E800020, 0x4E800420, 0) or (w >> 26 == 18 and not w & 1)

    found = []
    for a in range(CODE[0], CODE[1], 4):
        if covered[(a - CODE[0]) // 4] or word(a) == 0:
            continue
        if not ends_flow(word(a - 4)):
            continue
        if IMPORTS[0] <= a < IMPORTS[1]:
            continue
        w = word(a)
        prologue = w == 0x7D8802A6 or w >> 16 == 0x9421  # mflr r12 / stwu r1,-N(r1)
        if a in pointed or a in built or prologue:
            found.append(a)
    uncovered = sum(1 for a in range(CODE[0], CODE[1], 4)
                    if not covered[(a - CODE[0]) // 4] and word(a) != 0)
    print(f"{len(funcs)} functions; {uncovered} uncovered non-zero words in code; "
          f"{len(found)} pointed-to starts after non-falling-through code")
    hints_path = ROOT / "tools/hints/default.txt"
    hints = {}
    if hints_path.exists():
        for line in hints_path.read_text().splitlines():
            p = line.split("#")[0].split()
            if p:
                hints[int(p[0], 16)] = int(p[1], 16) if len(p) > 1 else 0
    new = [a for a in found if a not in hints]
    print(f"{len(new)} new: " + " ".join(f"{a:08X}" for a in new[:40]) +
          (" ..." if len(new) > 40 else ""))
    if "--write" in sys.argv:
        for a in new:
            hints[a] = 0
        hints_path.write_text("".join(f"0x{a:08X} 0x{s:X}\n" for a, s in sorted(hints.items())))
        print("written", hints_path)


main()

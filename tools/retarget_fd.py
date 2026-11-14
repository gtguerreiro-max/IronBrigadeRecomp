#!/usr/bin/env python3
"""Rewrites From Dust guest addresses in the native renderer sources copied from FromDustDeck
(src/native, src/ib_d3d_trace.cpp) into Iron Brigade's, from match_d3d_fd.py's map plus the
matches checked by hand below. Adapted from FromDustDeck's tools/retarget_pgr4.py.

  retarget_fd.py MAP SURFACE_IN SURFACE_OUT FILE...
      SURFACE_OUT keeps only the d3d_surface functions that have an Iron Brigade copy.
      In the other FILEs every mapped address is replaced (sub_/fn_/kFn_/0x forms and bare), and
      the unmapped ones still used outside comments are listed.
"""
import re
import sys

# Checked by hand (see docs/NATIVE_RENDERER.md).
MANUAL = {
    # From Dust's public Resolve (sub_820EE9D0) is a wrapper of sub_820ED880 adding two zero
    # arguments; Iron Brigade's LTCG D3D has no wrapper and the game calls the inner function
    # (sub_82649280, fuzzy 0.89, next 0.00) from 8 sites. The hook reads the inner signature.
    0x820EE9D0: 0x82649280,
    0x820ED880: 0x82649280,
}
# Matches in match_d3d_fd.py's output that are wrong or too weak to use.
REJECT = set()


def load_map(path):
    m = {}
    for line in open(path):
        g = re.match(r"([0-9A-F]{8}) ([0-9A-F]{8}) (exact|masked|fuzzy[\d.]+\(next [\d.]+\))", line)
        if not g:
            continue
        a, b, how = int(g.group(1), 16), int(g.group(2), 16), g.group(3)
        ok = how in ("exact", "masked")
        f = re.match(r"fuzzy([\d.]+)\(next ([\d.]+)\)", how)
        if f:
            r, nxt = float(f.group(1)), float(f.group(2))
            ok = r >= 0.70 and r - nxt >= 0.10
        if ok and a not in REJECT:
            m[a] = b
    m.update(MANUAL)
    return m


def main():
    m = load_map(sys.argv[1])
    out, kept, dropped, seen = [], 0, 0, set()
    for line in open(sys.argv[2]):
        g = re.match(r"D3D_FN\(([0-9A-F]{8}),", line)
        if g:
            a = int(g.group(1), 16)
            if a not in m or m[a] in seen:  # two From Dust functions folded into one: keep one
                dropped += 1
                continue
            seen.add(m[a])
            line = line.replace(g.group(1), "%08X" % m[a], 1)
            kept += 1
        out.append(line)
    open(sys.argv[3], "w", newline="\n").write("".join(out))
    print("surface: %d kept, %d dropped" % (kept, dropped))
    # From Dust's D3D library ranges (Default.xex).
    token = re.compile(r"(?<![0-9A-Fa-f])(820[D-F][0-9A-F]{4}|8250[D-E][0-9A-F]{3}|825DD[0-9A-F]{3})"
                       r"(?![0-9A-Fa-f])")
    for path in sys.argv[4:]:
        text = open(path, encoding="utf-8").read()
        missing = set()

        def sub(mo):
            a = int(mo.group(1), 16)
            if a in m:
                return "%08X" % m[a]
            missing.add(mo.group(1))
            return mo.group(1)

        new = token.sub(sub, text)
        if new != text:
            open(path, "w", encoding="utf-8", newline="\n").write(new)
        code_missing = sorted(a for a in missing
                              if any(a in l.split("//")[0] for l in new.splitlines()))
        if code_missing:
            print("%s: unmapped in code: %s" % (path, " ".join(code_missing)))


main()

#!/usr/bin/env python3
"""Makes an iPhoneOS SDK's .tbd stubs readable by ld64.lld when linking plain arm64:
newer SDKs list only arm64e (and arm64e.x1, which lld doesn't know) for most libraries.
Each target list becomes [ arm64-ios ]. Rewrites in place (new file, so hard links to
the original SDK stay untouched): tbd_arm64.py SDK_COPY"""
import re
import sys
from pathlib import Path

LIST = re.compile(r"\[([^\[\]]*?)\]")


def fix(m):
    items = [t.strip() for t in m.group(1).split(",")]
    if not items or not all(re.fullmatch(r"arm64(e(\.x1)?)?-ios", t) for t in items):
        return m.group(0)
    return "[ arm64-ios ]"


for p in Path(sys.argv[1]).rglob("*.tbd"):
    src = p.read_text()
    out = re.sub(r"(targets:\s*)" + LIST.pattern, lambda m: m.group(1) + fix(re.match(LIST, m.group(0)[len(m.group(1)):])), src)
    if out != src:
        p.unlink()
        p.write_text(out)

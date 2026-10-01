#!/usr/bin/env python3
"""Extracts part of an odc cpio stream (stdin) correctly with hard links, which bsdtar
gets wrong for Apple's archives (Xcode .xip after pbzx.py): of a file's links, only one
carries the real bytes; the others carry a "NULLcanary" placeholder of the same size.
    pass 1:  ... | cpio_pick.py scan    REGEX inodes.json   # which inodes the files need
    pass 2:  ... | cpio_pick.py extract REGEX inodes.json   # write them out
"""
import json
import os
import re
import sys

mode, pattern, state = sys.argv[1], re.compile(sys.argv[2]), sys.argv[3]
f = sys.stdin.buffer


def read(n):
    out = bytearray()
    while len(out) < n:
        b = f.read(n - len(out))
        if not b:
            break
        out += b
    return bytes(out)


def entries():
    while True:
        h = read(76)
        if len(h) < 76 or h[:6] != b"070707":
            return
        dev, ino, m, nlink = int(h[6:12], 8), int(h[12:18], 8), int(h[18:24], 8), int(h[36:42], 8)
        namesize, size = int(h[59:65], 8), int(h[65:76], 8)
        name = read(namesize)[:-1].decode("utf-8", "replace")
        if name == "TRAILER!!!":
            return
        yield name, (dev, ino), m, nlink, size


wanted = set()
if mode == "scan":
    for name, key, m, nlink, size in entries():
        f.read(size) if size < (1 << 20) else read(size)
        if pattern.search(name) and nlink > 1:
            wanted.add("%d:%d" % key)
    json.dump(sorted(wanted), open(state, "w"))
    print("inodes with links:", len(wanted), file=sys.stderr)
    sys.exit(0)

wanted = set(json.load(open(state)))
cache, pending, files = {}, {}, 0
CANARY = b"NULLcanary"
for name, key, m, nlink, size in entries():
    data = read(size)
    k = "%d:%d" % key
    kind = m & 0o170000
    real = size > 0 and not data.startswith(CANARY)
    if kind == 0o100000 and real and k in wanted:
        cache[k] = data
        for p in pending.pop(k, []):
            open(p, "wb").write(data)
    if not pattern.search(name):
        continue
    path = name.lstrip("./") if name.startswith("./") else name
    if kind == 0o040000:
        os.makedirs(path, exist_ok=True)
        continue
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if kind == 0o120000:
        if os.path.lexists(path):
            os.remove(path)
        os.symlink(data.decode(), path)
    elif kind == 0o100000:
        files += 1
        if real:
            open(path, "wb").write(data)
        elif k in cache:
            open(path, "wb").write(cache[k])
        elif nlink > 1:
            pending.setdefault(k, []).append(path)
            open(path, "wb").close()
        else:
            open(path, "wb").close()
        os.chmod(path, m & 0o777)
print("files:", files, "unresolved links:", sum(len(v) for v in pending.values()), file=sys.stderr)

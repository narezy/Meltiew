#!/usr/bin/env python3
"""pbzx (the payload of Apple's .xip / Xcode archives) to its plain cpio, stdin to stdout.
Chunks are independent xz streams, so they're unpacked in parallel, in order."""
import lzma
import multiprocessing as mp
import struct
import sys


def chunks(f):
    if f.read(4) != b"pbzx":
        sys.exit("not a pbzx stream")
    flags = struct.unpack(">Q", f.read(8))[0]
    while flags & (1 << 24):
        head = f.read(16)
        if len(head) < 16:
            return
        flags, length = struct.unpack(">QQ", head)
        yield f.read(length)


def unpack(data):
    return lzma.decompress(data) if data[:6] == b"\xfd7zXZ\x00" else data


if __name__ == "__main__":
    out = sys.stdout.buffer
    with mp.Pool(mp.cpu_count()) as pool:
        for piece in pool.imap(unpack, chunks(sys.stdin.buffer), chunksize=4):
            out.write(piece)

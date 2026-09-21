#!/usr/bin/env python3
"""Pack the files tungsten.wasm reads at run time into ONE binary bundle.

    python3 wasm/pack_fs.py [--root <repo>] [--out wasm/tungsten.fs] [--list]

Contents (found by logging path_open in wasi_shim.js — see README.md):
    /core/**/*.w                           the stdlib, autoloaded lazily by name
    /languages/tungsten/tungsten.lex64     lexer character-class table
    /data/unit_names.txt                   unit-literal names for the lexer

Format (little-endian), designed to be served by slicing one ArrayBuffer:

    "TFS1"  u32 file_count  u32 index_bytes
    index   file_count x { u32 data_offset, u32 length, u16 path_len, path utf-8 }
    data    file bytes back to back; data_offset is relative to the data region

Paths are absolute guest paths ("/core/array.w"), sorted, so the bundle is
byte-reproducible for a given tree.
"""
import argparse
import gzip
import os
import struct
import sys

EXTRA_FILES = [
    "languages/tungsten/tungsten.lex64",
    "data/unit_names.txt",
]


def collect(root):
    files = []
    core = os.path.join(root, "core")
    for directory, _, names in os.walk(core):
        for name in names:
            if name.endswith(".w"):
                full = os.path.join(directory, name)
                files.append("/" + os.path.relpath(full, root).replace(os.sep, "/"))
    for relative in EXTRA_FILES:
        if not os.path.isfile(os.path.join(root, relative)):
            sys.exit(f"pack_fs: missing {relative}")
        files.append("/" + relative)
    return sorted(files)


def pack(root, paths):
    index = bytearray()
    data = bytearray()
    for path in paths:
        with open(os.path.join(root, path.lstrip("/")), "rb") as handle:
            content = handle.read()
        encoded = path.encode("utf-8")
        index += struct.pack("<IIH", len(data), len(content), len(encoded)) + encoded
        data += content
    return b"TFS1" + struct.pack("<II", len(paths), len(index)) + bytes(index) + bytes(data)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=os.path.dirname(here))
    parser.add_argument("--out", default=os.path.join(here, "tungsten.fs"))
    parser.add_argument("--list", action="store_true", help="print the packed paths")
    options = parser.parse_args()

    paths = collect(options.root)
    bundle = pack(options.root, paths)
    with open(options.out, "wb") as handle:
        handle.write(bundle)
    if options.list:
        print("\n".join(paths))
    zipped = len(gzip.compress(bundle, 9))
    print(f"{options.out}: {len(paths)} files, {len(bundle)} bytes raw, {zipped} bytes gzip -9")


if __name__ == "__main__":
    main()

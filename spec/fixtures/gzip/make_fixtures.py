#!/usr/bin/env python3
"""Regenerate the gzip golden fixtures of spec/core/gzip_spec.w.

Every stream here is produced by Python's zlib (the oracle), never by
core/gzip.w, so the spec checks the inflater against an independent encoder:

  sample.txt              64,000 bytes of ordinary text (compiler/lib/loader.w)
  sample.l0/l1/l6/l9.gz   the same text at zlib levels 0 (stored blocks), 1, 6, 9
  sample.fixed.gz         Z_FIXED: fixed-Huffman blocks only
  sample.huffman.gz       Z_HUFFMAN_ONLY: dynamic-Huffman blocks with no matches
  sample.rle.gz           Z_RLE: dynamic blocks with distance-1 matches only
  sample.small.gz         a 9-bit window and memLevel 1: many small blocks
  random.raw / random.gz  16,384 incompressible bytes (zlib stores them)
  zeros.gz                1 MiB of zero bytes (the spec regenerates the zeros)
  header_*.gz             FNAME, FEXTRA, FCOMMENT, FHCRC and all four together
  multi.gz                two members; multi_padded.gz: zero padding between
                          and after them
  tensor.mfw              a real 4x4x8 rank-94 GF(2) tensor (MFW1 text, sha256
                          407bc699...0b69, copied from the metaflip corpus)
  tensor.book.gz.b64      it as Python's gzip.compress(mtime=0) + encodebytes
                          (76 columns), tensor.line.gz.b64: b64encode + newline
  manifest.tsv            gzip file, expected output file (- means zeros)
  sample.zlib             sample.txt as a zlib stream (zlib.compress, level 9),
                          for Gzip.inflate_zlib
  sample.deflate          sample.txt as raw DEFLATE (level 6), for Gzip.inflate

Run from the repository root: python3 spec/fixtures/gzip/make_fixtures.py
(a global `*.gz` gitignore needs `git add -f spec/fixtures/gzip/*.gz`).  The
streams depend on the local zlib version; the spec only needs them to decode.
"""
import base64
import gzip
import os
import random
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def path(name):
    return os.path.join(HERE, name)


def write(name, data):
    with open(path(name), "wb") as f:
        f.write(data)


def source_text():
    """The first 64,000 bytes of a Tungsten source file."""
    with open(os.path.join(ROOT, "compiler/lib/loader.w"), "rb") as f:
        return f.read(64000)


def raw_deflate(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY, wbits=15, mem=8):
    c = zlib.compressobj(level, zlib.DEFLATED, -wbits, mem, strategy)
    return c.compress(data) + c.flush()


def member(data, deflated=None, flags=0, header_extra=b"", mtime=0, xfl=0, os_byte=255):
    """A gzip member with hand-made header fields (Python's writer has no FEXTRA)."""
    if deflated is None:
        deflated = raw_deflate(data)
    head = b"\x1f\x8b\x08" + bytes([flags]) + struct.pack("<I", mtime) + bytes([xfl, os_byte])
    body = head + header_extra
    if flags & 2:
        body += struct.pack("<H", zlib.crc32(body) & 0xFFFF)
    return body + deflated + struct.pack("<II", zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF)


def write_zlib_fixtures(sample):
    write("sample.zlib", zlib.compress(sample, 9))
    write("sample.deflate", raw_deflate(sample, 6))


def main():
    manifest = []

    sample = source_text()
    assert len(sample) == 64000
    write("sample.txt", sample)
    for level in (0, 1, 6, 9):
        write("sample.l%d.gz" % level, gzip.compress(sample, level, mtime=0))
        manifest.append(("sample.l%d.gz" % level, "sample.txt"))
    for name, strategy, wbits, mem in (("fixed", zlib.Z_FIXED, 15, 8),
                                       ("huffman", zlib.Z_HUFFMAN_ONLY, 15, 8),
                                       ("rle", zlib.Z_RLE, 15, 8),
                                       ("small", zlib.Z_DEFAULT_STRATEGY, 9, 1)):
        write("sample.%s.gz" % name, member(sample, raw_deflate(sample, 6, strategy, wbits, mem)))
        manifest.append(("sample.%s.gz" % name, "sample.txt"))

    rng = random.Random(20260929)
    noise = bytes(rng.getrandbits(8) for _ in range(16384))
    write("random.raw", noise)
    write("random.gz", gzip.compress(noise, 6, mtime=0))
    manifest.append(("random.gz", "random.raw"))

    write("zeros.gz", gzip.compress(bytes(1 << 20), 9, mtime=0))
    manifest.append(("zeros.gz", "-"))

    hello = b"hello, gzip\n" * 3
    extra = b"".join(struct.pack("<2sH", sub, len(body)) + body
                      for sub, body in ((b"AB", b"xyz"), (b"Ap", b"")))
    write("header_fname.gz", member(hello, flags=8, header_extra=b"hello.txt\x00"))
    write("header_extra.gz", member(hello, flags=4, header_extra=struct.pack("<H", len(extra)) + extra))
    write("header_comment.gz", member(hello, flags=16, header_extra=b"a comment\x00"))
    write("header_hcrc.gz", member(hello, flags=2))
    write("header_all.gz", member(hello, flags=2 | 4 | 8 | 16, mtime=1234567890, os_byte=3,
                                  header_extra=struct.pack("<H", len(extra)) + extra
                                  + b"hello.txt\x00" + b"a comment\x00"))
    for name in ("fname", "extra", "comment", "hcrc", "all"):
        manifest.append(("header_%s.gz" % name, "hello.txt"))
    write("hello.txt", hello)

    first, second = b"first member\n", b"second member\n"
    write("multi.gz", member(first) + member(second))
    write("multi_padded.gz", member(first) + b"\x00" * 7 + member(second) + b"\x00" * 3)
    write("multi.txt", first + second)
    manifest.append(("multi.gz", "multi.txt"))
    manifest.append(("multi_padded.gz", "multi.txt"))

    with open(path("tensor.mfw"), "rb") as f:
        tensor = f.read()
    packed = gzip.compress(tensor, 9, mtime=0)
    write("tensor.book.gz.b64", base64.encodebytes(packed))
    write("tensor.line.gz.b64", base64.b64encode(packed) + b"\n")

    write_zlib_fixtures(sample)

    with open(path("manifest.tsv"), "w") as f:
        for gz, raw in manifest:
            f.write("%s\t%s\n" % (gz, raw))


if __name__ == "__main__":
    main()

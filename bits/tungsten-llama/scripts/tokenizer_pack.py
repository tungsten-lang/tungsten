#!/usr/bin/env python3
"""tokenizer_pack — convert HuggingFace tokenizer.json to a packed binary.

The pure-Tungsten JSON parser (core/json) is O(N²) in memory on `s.chars[pos]`
and OOMs on multi-MB inputs. This one-shot Python helper produces a tight
packed-binary form that bits/tungsten-llama/lib/tokenizer.w can load with
BinReader at memcpy speed.

Format (little-endian):
    magic        4 bytes "TBPE"
    vocab_count  u32
    merges_count u32
    added_count  u32
    bos_id       i32  (-1 = absent)
    eos_id       i32
    pad_id       i32
    vocab        vocab_count × { u32 id, u16 len, len × u8 token_bytes }
    merges       merges_count × { u16 a_len, a_len × u8, u16 b_len, b_len × u8 }
    added        added_count × { u32 id, u16 len, len × u8 token_bytes }

Usage: tokenizer_pack.py <tokenizer.json> <out.bin>
"""

import json
import struct
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: tokenizer_pack.py <tokenizer.json> <out.bin>")
    src, dst = sys.argv[1], sys.argv[2]

    with open(src) as f:
        j = json.load(f)
    model = j["model"]
    vocab = model["vocab"]                  # {token_str: id}
    merges = model["merges"]                # [[a, b], ...]  or  ["a b", ...]
    added = j.get("added_tokens", [])       # [{id, content, special}, ...]

    bos_id = eos_id = pad_id = -1
    for t in added:
        c, i = t["content"], t["id"]
        if c == "<|endoftext|>":
            if eos_id < 0:
                eos_id = i
            if pad_id < 0:
                pad_id = i
        elif c == "<|im_end|>":
            eos_id = i

    with open(dst, "wb") as f:
        f.write(b"TBPE")
        f.write(struct.pack("<III", len(vocab), len(merges), len(added)))
        f.write(struct.pack("<iii", bos_id, eos_id, pad_id))
        for tok, idx in vocab.items():
            b = tok.encode("utf-8")
            f.write(struct.pack("<IH", idx, len(b)))
            f.write(b)
        for m in merges:
            if isinstance(m, str):
                a, b = m.split(" ", 1)
            else:
                a, b = m
            ab, bb = a.encode("utf-8"), b.encode("utf-8")
            f.write(struct.pack("<H", len(ab)))
            f.write(ab)
            f.write(struct.pack("<H", len(bb)))
            f.write(bb)
        for t in added:
            b = t["content"].encode("utf-8")
            f.write(struct.pack("<IH", t["id"], len(b)))
            f.write(b)


if __name__ == "__main__":
    main()

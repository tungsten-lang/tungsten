#!/usr/bin/env python3
"""Generate w_lexchar_cache.c — pre-computed LexChar lookup table.

Two-stage compressed table mapping codepoint → pre-boxed WValue metadata.
At lookup time, only a table access + one OR (to insert codepoint) is needed.

Table stores per-codepoint: W_TAG_LEXCHAR | (utf8_len << 16) | (category << 11) | (digit << 7) | flags
Lookup adds: | ((uint64_t)cp << 18)
Result is a ready-to-use NaN-boxed integer.
"""

import os
import urllib.request

UCD_BASE = "https://www.unicode.org/Public/16.0.0/ucd/"
MAX_CP = 0x110000
BLOCK_SIZE = 256
W_TAG_LEXCHAR = 0xFFFC000000000000 | (1 << 46)  # W_TAG_CHAR + subtag 01 (LexChar)

# Unicode categories
CATEGORIES = [
    "Lu", "Ll", "Lt", "Lm", "Lo",  # Letters 0-4
    "Nd", "Nl", "No",              # Numbers 5-7
    "Zs", "Zl", "Zp",             # Separators 8-10
    "Mn", "Mc", "Me",             # Marks 11-13
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",  # Punctuation 14-20
    "Sm", "Sc", "Sk", "So",       # Symbols 21-24
    "Cc", "Cf", "Cs", "Co", "Cn", # Other 25-29
]
CAT_MAP = {name: i for i, name in enumerate(CATEGORIES)}

# LexChar flag bits (matching wvalue.h W_LEXFLAG_*)
F_MAY_COMBINE = 1 << 0
F_IS_QUOTE    = 1 << 1
F_IS_OPERATOR = 1 << 2
F_IS_HEX      = 1 << 3
F_IS_WHITESPACE = 1 << 4
F_IS_ID_CONTINUE = 1 << 5
F_IS_ID_START    = 1 << 6

OPERATORS = set(b'+-*/%^&|<>=!~?.;,:()[]{}#')

def download(filename):
    cache_dir = os.path.join(os.path.dirname(__file__), ".ucd_cache")
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, filename.replace("/", "_"))
    if not os.path.exists(path):
        url = UCD_BASE + filename
        print(f"  downloading {url}")
        urllib.request.urlretrieve(url, path)
    return path

def load_unicode_data():
    """Load UnicodeData.txt, return dict cp → (category, digit_value)"""
    path = download("UnicodeData.txt")
    data = {}
    with open(path) as f:
        for line in f:
            fields = line.strip().split(";")
            if len(fields) < 9:
                continue
            cp = int(fields[0], 16)
            cat = fields[2]
            digit_str = fields[6]  # decimal digit value
            digit = int(digit_str) if digit_str else 0xF
            data[cp] = (CAT_MAP.get(cat, 29), digit)
    return data

def utf8_len(cp):
    if cp < 0x80: return 1
    if cp < 0x800: return 2
    if cp < 0x10000: return 3
    return 4

def compute_flags(cp, category):
    flags = 0
    # IS_ID_START: lowercase + underscore + Unicode letters. Plus ∫ (U+222B):
    # category Sm (math symbol), but Tungsten treats it as a callable name
    # exactly like Σ (a letter, which qualifies naturally) — `∫(x², 0..2)`.
    if (cp >= 0x61 and cp <= 0x7A) or cp == 0x5F or (cp >= 128 and category <= 4) \
       or cp == 0x222B:
        flags |= F_IS_ID_START
    # IS_ID_CONTINUE: id_start + digits
    if flags & F_IS_ID_START:
        flags |= F_IS_ID_CONTINUE
    if cp >= 0x30 and cp <= 0x39:
        flags |= F_IS_ID_CONTINUE
    # IS_HEX
    if (cp >= 0x30 and cp <= 0x39) or (cp >= 0x61 and cp <= 0x66) or (cp >= 0x41 and cp <= 0x46):
        flags |= F_IS_HEX
    # IS_WHITESPACE
    if cp == 0x20 or cp == 0x09:
        flags |= F_IS_WHITESPACE
    # IS_OPERATOR
    if cp < 128 and cp in OPERATORS:
        flags |= F_IS_OPERATOR
    # IS_QUOTE
    if cp == 0x22 or cp == 0x27:
        flags |= F_IS_QUOTE
    # IS_DIGIT / MAY_COMBINE: shared bit 0 (digits < 128, combining >= 128)
    if 0x30 <= cp <= 0x39:
        flags |= F_MAY_COMBINE  # bit 0 = IS_DIGIT for ASCII digits
    if cp >= 128 and 11 <= category <= 13:
        flags |= F_MAY_COMBINE
    return flags

def main():
    print("Loading Unicode data...")
    ucd = load_unicode_data()

    print("Computing LexChar metadata for all codepoints...")
    # Compute metadata (without codepoint) for every codepoint
    # Layout: W_TAG_LEXCHAR | (utf8_len-1 << 16) | (category << 11) | (digit << 7) | flags
    metadata = []
    for cp in range(MAX_CP):
        cat, digit = ucd.get(cp, (29, 0xF))  # default: Cn (unassigned), no digit
        ulen = utf8_len(cp)
        flags = compute_flags(cp, cat)
        packed = W_TAG_LEXCHAR | ((ulen - 1) << 16) | ((cat & 0x1F) << 11) | ((digit & 0xF) << 7) | (flags & 0x7F)
        metadata.append(packed)

    # Two-stage compression
    print("Compressing into two-stage table...")
    num_blocks = MAX_CP // BLOCK_SIZE
    blocks = []
    for i in range(num_blocks):
        block = tuple(metadata[i * BLOCK_SIZE:(i + 1) * BLOCK_SIZE])
        blocks.append(block)

    # Deduplicate
    unique_blocks = []
    block_map = {}
    index = []
    for block in blocks:
        if block not in block_map:
            block_map[block] = len(unique_blocks)
            unique_blocks.append(block)
        index.append(block_map[block])

    print(f"  {num_blocks} blocks → {len(unique_blocks)} unique ({100 * len(unique_blocks) / num_blocks:.1f}%)")
    data_bytes = len(unique_blocks) * BLOCK_SIZE * 8
    index_bytes = len(index) * 2
    print(f"  data: {data_bytes / 1024:.0f} KB, index: {index_bytes / 1024:.1f} KB, total: {(data_bytes + index_bytes) / 1024:.0f} KB")

    # Write C file
    out_path = os.path.join(os.path.dirname(__file__), "..", "runtime", "w_lexchar_cache.c")
    print(f"Writing {out_path}...")
    with open(out_path, "w") as f:
        f.write("/* Auto-generated by scripts/gen_lexchar_cache.py — DO NOT EDIT */\n")
        f.write("/* Unicode 16.0 pre-computed LexChar two-stage table */\n")
        f.write("/* Each entry: W_TAG_LEXCHAR | metadata. Add (cp << 18) at lookup time. */\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define W_LEXCHAR_BLOCK_SIZE {BLOCK_SIZE}\n")
        f.write(f"#define W_LEXCHAR_NUM_BLOCKS {num_blocks}\n")
        f.write(f"#define W_LEXCHAR_UNIQUE_BLOCKS {len(unique_blocks)}\n\n")

        # Block data
        f.write(f"static const uint64_t w_lexchar_block_data[{len(unique_blocks)}][{BLOCK_SIZE}] = {{\n")
        for bi, block in enumerate(unique_blocks):
            f.write(f"  /* block {bi} */\n  {{")
            for i, val in enumerate(block):
                if i % 4 == 0:
                    f.write("\n    ")
                f.write(f"0x{val:016X}ULL,")
                if i % 4 != 3:
                    f.write(" ")
            f.write("\n  },\n")
        f.write("};\n\n")

        # Block index
        f.write(f"static const uint16_t w_lexchar_block_index[{num_blocks}] = {{\n")
        for i in range(0, len(index), 16):
            row = ", ".join(str(index[j]) for j in range(i, min(i + 16, len(index))))
            f.write(f"    {row},\n")
        f.write("};\n\n")

        # Lookup function
        f.write("/* Look up pre-packed LexChar metadata for a codepoint.\n")
        f.write("   Returns W_TAG_LEXCHAR | metadata. Caller ORs in (cp << 18) for the final value.\n")
        f.write("   Result can be used directly with w_int() or stored as-is. */\n")
        f.write("static inline uint64_t w_lexchar_cached(uint32_t codepoint) {\n")
        f.write(f"    if (codepoint >= 0x{MAX_CP:X}) return 0x{W_TAG_LEXCHAR | (29 << 11) | (0xF << 7):016X}ULL;\n")
        f.write("    uint32_t block = codepoint >> 8;\n")
        f.write("    uint32_t offset = codepoint & 0xFF;\n")
        f.write("    return w_lexchar_block_data[w_lexchar_block_index[block]][offset];\n")
        f.write("}\n")

    print("Done.")

if __name__ == "__main__":
    main()

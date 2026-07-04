#!/usr/bin/env python3
"""Generate w_char_table.c — two-stage Unicode lookup table for Tungsten char type.

Downloads UCD files from unicode.org, computes per-codepoint metadata, and emits
a compressed two-stage table for O(1) lookup by codepoint.

Metadata layout per codepoint (mode 0 — general-purpose, 48 bits):
  bits 47:    0 (general mode)
  bits 46-26: codepoint (21 bits)
  bits 25-24: utf8_len - 1 (2 bits, 0-3 meaning 1-4 bytes)
  bits 23-19: category (5 bits, 0-29)
  bits 18-17: width (2 bits: 0=zero-width, 1=narrow, 2=fullwidth)
  bits 16-8:  case_delta (9 bits signed, ±255; -256 = sentinel)
  bits 7-4:   digit_value (4 bits, 0-9 or 0xF=not-a-digit)
  bits 3:     is_emoji
  bits 2:     is_upper (fast path for case conversion)
  bits 1:     is_ascii (hot path for ASCII-fast string ops)
  bits 0:     is_printable

We store a 22-bit packed metadata value (everything except codepoint, which is
known at lookup time). The two-stage table maps codepoint → packed metadata.
"""

import os
import sys
import urllib.request

UCD_BASE = "https://www.unicode.org/Public/16.0.0/ucd/"

CATEGORY_MAP = {
    # Letters 0-4
    "Lu": 0, "Ll": 1, "Lt": 2, "Lm": 3, "Lo": 4,
    # Numbers 5-7
    "Nd": 5, "Nl": 6, "No": 7,
    # Separators 8-10
    "Zs": 8, "Zl": 9, "Zp": 10,
    # Marks 11-13
    "Mn": 11, "Mc": 12, "Me": 13,
    # Punctuation 14-20
    "Pc": 14, "Pd": 15, "Ps": 16, "Pe": 17, "Pi": 18, "Pf": 19, "Po": 20,
    # Symbols 21-24
    "Sm": 21, "Sc": 22, "Sk": 23, "So": 24,
    # Control/Format/Other 25-29
    "Cc": 25, "Cf": 26, "Cs": 27, "Co": 28, "Cn": 29,
}

BLOCK_SIZE = 256  # codepoints per block
MAX_CP = 0x110000  # U+0000 to U+10FFFF


def download(filename):
    """Download a UCD file, caching locally."""
    cache_dir = os.path.join(os.path.dirname(__file__), ".ucd_cache")
    path = os.path.join(cache_dir, filename)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        url = UCD_BASE + filename
        print(f"  Downloading {url}...")
        urllib.request.urlretrieve(url, path)
    return path


def parse_unicode_data():
    """Parse UnicodeData.txt → per-codepoint info dict."""
    path = download("UnicodeData.txt")
    data = {}
    range_start = None
    with open(path) as f:
        for line in f:
            fields = line.strip().split(";")
            cp = int(fields[0], 16)
            name = fields[1]
            cat = fields[2]

            # Handle range entries like "<CJK Ideograph, First>"
            if name.endswith(", First>"):
                range_start = cp
                range_cat = cat
                range_fields = fields
                continue
            if name.endswith(", Last>"):
                for c in range(range_start, cp + 1):
                    data[c] = {
                        "category": range_cat,
                        "upper": 0, "lower": 0, "digit": -1,
                    }
                range_start = None
                continue

            upper_cp = int(fields[12], 16) if fields[12] else 0
            lower_cp = int(fields[13], 16) if fields[13] else 0
            digit = int(fields[6]) if fields[6] and fields[6].isdigit() else -1

            data[cp] = {
                "category": cat,
                "upper": upper_cp,
                "lower": lower_cp,
                "digit": digit,
            }
    return data


def parse_east_asian_width():
    """Parse EastAsianWidth.txt → dict of codepoint → width char."""
    path = download("EastAsianWidth.txt")
    widths = {}
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if not line:
                continue
            parts = line.split(";")
            cp_range = parts[0].strip()
            w = parts[1].strip()
            if ".." in cp_range:
                start, end = cp_range.split("..")
                for cp in range(int(start, 16), int(end, 16) + 1):
                    widths[cp] = w
            else:
                widths[int(cp_range, 16)] = w
    return widths


def parse_emoji_data():
    """Parse emoji-data.txt → set of emoji codepoints."""
    path = download("emoji/emoji-data.txt")
    emojis = set()
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if not line:
                continue
            parts = line.split(";")
            prop = parts[1].strip()
            if prop not in ("Emoji_Presentation", "Emoji"):
                continue
            cp_range = parts[0].strip()
            if ".." in cp_range:
                start, end = cp_range.split("..")
                for cp in range(int(start, 16), int(end, 16) + 1):
                    emojis.add(cp)
            else:
                emojis.add(int(cp_range, 16))
    return emojis


def utf8_len(cp):
    if cp <= 0x7F:
        return 1
    elif cp <= 0x7FF:
        return 2
    elif cp <= 0xFFFF:
        return 3
    else:
        return 4


def compute_width(cp, eaw, cat):
    """Compute display width: 0=zero-width, 1=narrow, 2=fullwidth."""
    # Zero-width: marks, control, format (except a few)
    if cat in ("Mn", "Mc", "Me", "Cc", "Cf"):
        # Soft hyphen (U+00AD) has width 1
        if cp == 0x00AD:
            return 1
        return 0
    # Fullwidth: W or F in East Asian Width
    w = eaw.get(cp, "N")
    if w in ("W", "F"):
        return 2
    return 1


def compute_case_delta(cp, info):
    """Compute signed case delta. Returns (delta, is_sentinel)."""
    if info["lower"] and info["lower"] != cp:
        delta = info["lower"] - cp
    elif info["upper"] and info["upper"] != cp:
        delta = info["upper"] - cp
    else:
        return 0, False

    if -255 <= delta <= 255:
        return delta, False
    else:
        return -256, True  # sentinel


def generate_table():
    print("Generating w_char_table.c...")
    udata = parse_unicode_data()
    eaw = parse_east_asian_width()
    emojis = parse_emoji_data()

    # Build packed metadata for each codepoint
    # Pack 26 bits: utf8(2) | cat(5) | width(2) | case_delta(9) | digit(4) | emoji(1) | is_upper(1) | is_ascii(1) | is_printable(1)
    # Total: 2+5+2+9+4+1+1+1+1 = 26 bits — stored in uint32_t
    packed = [0] * MAX_CP

    for cp in range(MAX_CP):
        info = udata.get(cp)
        if info is None:
            cat = "Cn"
            cat_idx = CATEGORY_MAP[cat]
            u8len = utf8_len(cp) - 1
            # Unassigned: all flags zero except basic ones
            p = (u8len << 24) | (cat_idx << 19) | (1 << 17) | (0xF << 4)
            packed[cp] = p
            continue

        cat = info["category"]
        cat_idx = CATEGORY_MAP.get(cat, 29)
        u8len = utf8_len(cp) - 1
        width = compute_width(cp, eaw, cat)
        delta, _ = compute_case_delta(cp, info)
        digit = info["digit"] if info["digit"] >= 0 else 0xF
        is_emoji = 1 if cp in emojis else 0
        is_upper = 1 if cat == "Lu" else 0
        is_ascii = 1 if cp <= 0x7F else 0
        # Printable: not control, not unassigned, not surrogate
        is_printable = 1 if cat not in ("Cc", "Cn", "Cs") else 0

        # Pack case_delta into 9-bit two's complement
        delta_bits = delta & 0x1FF

        p = ((u8len & 0x3) << 24) | \
            ((cat_idx & 0x1F) << 19) | \
            ((width & 0x3) << 17) | \
            ((delta_bits & 0x1FF) << 8) | \
            ((digit & 0xF) << 4) | \
            ((is_emoji & 1) << 3) | \
            ((is_upper & 1) << 2) | \
            ((is_ascii & 1) << 1) | \
            (is_printable & 1)

        packed[cp] = p

    # Two-stage compression
    num_blocks = MAX_CP // BLOCK_SIZE
    blocks = []
    block_index = []
    block_map = {}

    for b in range(num_blocks):
        start = b * BLOCK_SIZE
        block_data = tuple(packed[start:start + BLOCK_SIZE])
        if block_data in block_map:
            block_index.append(block_map[block_data])
        else:
            idx = len(blocks)
            block_map[block_data] = idx
            blocks.append(block_data)
            block_index.append(idx)

    unique_blocks = len(blocks)
    total_entries = unique_blocks * BLOCK_SIZE
    index_entries = len(block_index)
    data_bytes = total_entries * 4
    index_bytes = index_entries * 2
    total_bytes = data_bytes + index_bytes

    print(f"  Codepoints: {MAX_CP}")
    print(f"  Block size: {BLOCK_SIZE}")
    print(f"  Total blocks: {num_blocks}")
    print(f"  Unique blocks: {unique_blocks}")
    print(f"  Data: {data_bytes:,} bytes ({total_entries} uint32_t)")
    print(f"  Index: {index_bytes:,} bytes ({index_entries} uint16_t)")
    print(f"  Total: {total_bytes:,} bytes ({total_bytes/1024:.1f} KB)")

    return block_index, blocks


def emit_c(block_index, blocks, output_path):
    with open(output_path, "w") as f:
        f.write("/* Auto-generated by scripts/gen_char_table.py — DO NOT EDIT */\n")
        f.write("/* Unicode 16.0 two-stage character metadata table */\n\n")
        f.write("#include <stdint.h>\n\n")

        f.write(f"#define W_CHAR_BLOCK_SIZE {BLOCK_SIZE}\n")
        f.write(f"#define W_CHAR_NUM_BLOCKS {len(block_index)}\n")
        f.write(f"#define W_CHAR_UNIQUE_BLOCKS {len(blocks)}\n\n")

        # Block index
        f.write(f"static const uint16_t w_char_block_index[{len(block_index)}] = {{\n")
        for i in range(0, len(block_index), 16):
            chunk = block_index[i:i+16]
            f.write("    " + ", ".join(str(x) for x in chunk) + ",\n")
        f.write("};\n\n")

        # Block data
        f.write(f"static const uint32_t w_char_block_data[{len(blocks)}][{BLOCK_SIZE}] = {{\n")
        for bi, block in enumerate(blocks):
            f.write(f"    /* block {bi} */\n    {{\n")
            for i in range(0, BLOCK_SIZE, 8):
                chunk = block[i:i+8]
                f.write("        " + ", ".join(f"0x{x:08X}" for x in chunk) + ",\n")
            f.write("    },\n")
        f.write("};\n\n")

        # Lookup function
        f.write("""/* Look up packed metadata for a codepoint.
   Returns uint32_t with layout:
     bits 25-24: utf8_len - 1    (2 bits)
     bits 23-19: category        (5 bits)
     bits 18-17: width           (2 bits)
     bits 16-8:  case_delta      (9 bits signed)
     bits 7-4:   digit_value     (4 bits, 0xF = not a digit)
     bit 3:      is_emoji
     bit 2:      is_upper
     bit 1:      is_ascii
     bit 0:      is_printable
*/
static inline uint32_t w_char_lookup(uint32_t codepoint) {
    if (codepoint >= 0x110000) return 0x03EA00F0; /* Cn, width 1, not-a-digit */
    uint32_t block = codepoint >> 8;
    uint32_t offset = codepoint & 0xFF;
    return w_char_block_data[w_char_block_index[block]][offset];
}
""")

    print(f"  Written to {output_path}")


if __name__ == "__main__":
    output = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),
        "stages", "tungsten", "runtime", "w_char_table.c"
    )
    if len(sys.argv) > 1:
        output = sys.argv[1]

    block_index, blocks = generate_table()
    emit_c(block_index, blocks, output)
    print("Done!")

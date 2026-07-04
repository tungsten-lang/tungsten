#!/usr/bin/env python3
"""Generate Unicode and language-specific codepoint tables.

Base table: languages/unicode.codepoints
  Format: 2 bytes per codepoint, 0x110000 entries, indexed by codepoint.
  byte 0: category (5 bits) | utf8_len-1 (2 bits) | 0
  byte 1: digit_value (4 bits) | base_flags (4 bits)

Language tables: languages/<lang>/<lang>.lex<bits>
  bits=64 / 32: 1 byte per codepoint, 0x110000 entries (1.1 MB).
                lex64 == lex32 byte-for-byte; bit width refers to the
                LexChar element width the runtime packs into.
  bits=16:      1 byte per ASCII-range codepoint, 256 entries.
                Non-ASCII (cp > 0x7F) handled at packing time via the
                lex64 table.

Flag layout is language-specific (defined in languages/<lang>/overrides.w).

Usage:
  python3 scripts/gen_unicode_codepoints.py                            # base only
  python3 scripts/gen_unicode_codepoints.py --lang c                   # base + c.lex64
  python3 scripts/gen_unicode_codepoints.py --lang c --bits 32         # base + c.lex32
  python3 scripts/gen_unicode_codepoints.py --lang c --bits 16         # base + c.lex16
  python3 scripts/gen_unicode_codepoints.py --lang tungsten            # base + tungsten.lex64
  python3 scripts/gen_unicode_codepoints.py --lang tungsten --bits 32  # base + tungsten.lex32
"""

import argparse
import os
import urllib.request

UCD_BASE = "https://www.unicode.org/Public/16.0.0/ucd/"
MAX_CP = 0x110000

CATEGORIES = [
    "Lu", "Ll", "Lt", "Lm", "Lo",
    "Nd", "Nl", "No",
    "Zs", "Zl", "Zp",
    "Mn", "Mc", "Me",
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
    "Sm", "Sc", "Sk", "So",
    "Cc", "Cf", "Cs", "Co", "Cn",
]
CAT_MAP = {name: i for i, name in enumerate(CATEGORIES)}

# C flag bits (must match languages/c/overrides.w)
F_IS_ID_START    = 1 << 6
F_IS_ID_CONTINUE = 1 << 5
F_IS_WHITESPACE  = 1 << 4
F_IS_HEX         = 1 << 3
F_IS_OPERATOR    = 1 << 2
F_IS_QUOTE       = 1 << 1
F_IS_DIGIT       = 1 << 0
F_IS_NEWLINE     = 1 << 7   # borrows from digit_value field (bit 7) — C doesn't use digit_value

C_OPERATORS = set(b'+-*/%^&|<>=!~?.;,:()[]{}#')

# Tungsten flag bits for packed compiler lexer experiments. These mirror the
# default Tungsten identifier semantics instead of C's broader uppercase ID
# rules: lowercase/underscore/Unicode letters start identifiers; uppercase
# ASCII starts NAME tokens and is handled by codepoint checks in the lexer.
TF_IS_ID_START    = 1 << 6
TF_IS_ID_CONTINUE = 1 << 5
TF_IS_WHITESPACE  = 1 << 4
TF_IS_HEX         = 1 << 3
TF_IS_OPERATOR    = 1 << 2
TF_IS_QUOTE       = 1 << 1
TF_IS_DIGIT       = 1 << 0
TF_IS_NEWLINE     = 1 << 7

TUNGSTEN_OPERATORS = set(b'+-*/%^&|<>=!~?.;,:()[]{}#')

# Ruby flag bits. The shape mirrors C/Tungsten so Ruby lex64 can use the same
# hot dispatch mask. Ruby treats uppercase ASCII as identifier starts because
# constants are part of the identifier-like fast path.
RF_IS_ID_START    = 1 << 6
RF_IS_ID_CONTINUE = 1 << 5
RF_IS_WHITESPACE  = 1 << 4
RF_IS_HEX         = 1 << 3
RF_IS_OPERATOR    = 1 << 2
RF_IS_QUOTE       = 1 << 1
RF_IS_DIGIT       = 1 << 0
RF_IS_NEWLINE     = 1 << 7

RUBY_OPERATORS = set(b'+-*/%^&|<>=!~?.;,:()[]{}#@$')

# JSON flag bits (must match languages/json/lexer.w dispatch).
# Disjoint at the low 6 bits so `case v & 0x3F` selects on a single
# bit value per char class.
JF_IS_DIGIT       = 1 << 0  # 0-9 and '-' (number start; '-' is also continue inside exponent)
JF_IS_QUOTE       = 1 << 1  # " (string start/end)
JF_IS_STRUCT      = 1 << 2  # { } [ ] , : (single-char structural tokens)
JF_IS_WHITESPACE  = 1 << 3  # space tab newline carriage-return
JF_IS_KEYWORD     = 1 << 4  # t f n (start of true / false / null)
JF_IS_NUM_CONT    = 1 << 5  # 0-9 . e E + - (continuation chars inside a number)
JF_IS_ESCAPE      = 1 << 6  # \\ (string-content escape lookahead)


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
    path = download("UnicodeData.txt")
    data = {}
    with open(path) as f:
        for line in f:
            fields = line.strip().split(";")
            if len(fields) < 9:
                continue
            cp = int(fields[0], 16)
            cat = fields[2]
            digit_str = fields[6]
            digit = int(digit_str) if digit_str else 0xF
            data[cp] = (CAT_MAP.get(cat, 29), digit)
    return data


def utf8_len(cp):
    if cp < 0x80: return 1
    if cp < 0x800: return 2
    if cp < 0x10000: return 3
    return 4


def gen_base(ucd, root):
    """Generate languages/unicode.codepoints (2 bytes per codepoint)."""
    out_path = os.path.join(root, "languages", "unicode.codepoints")
    print(f"Generating {out_path}...")
    buf = bytearray(MAX_CP * 2)

    for cp in range(MAX_CP):
        cat, digit = ucd.get(cp, (29, 0xF))
        ulen = utf8_len(cp)

        base_flags = 0
        if (0x30 <= cp <= 0x39) or (0x61 <= cp <= 0x66) or (0x41 <= cp <= 0x46):
            base_flags |= 0x08  # IS_HEX
        if cp in (0x20, 0x09, 0x0D):
            base_flags |= 0x04  # IS_WHITESPACE
        if cp in (0x0A, 0x0D):
            base_flags |= 0x02  # IS_NEWLINE

        b0 = ((cat & 0x1F) << 3) | (((ulen - 1) & 0x3) << 1)
        b1 = ((digit & 0xF) << 4) | (base_flags & 0xF)

        off = cp * 2
        buf[off] = b0
        buf[off + 1] = b1

    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"  wrote {len(buf)} bytes ({len(buf) / 1024:.0f} KB), {MAX_CP} codepoints")


def c_flags_for(cp, ucd):
    """Compute the C lexer flag byte for a codepoint.

    Flag rules match languages/c/overrides.w — that file is the spec,
    this function is the implementation."""
    cat, _digit = ucd.get(cp, (29, 0xF))
    flags = 0

    # IS_ID_START: a-z A-Z _ + Unicode letters
    if (0x61 <= cp <= 0x7A) or (0x41 <= cp <= 0x5A) or cp == 0x5F:
        flags |= F_IS_ID_START
    elif cp >= 128 and cat <= 4:  # Lu..Lo
        flags |= F_IS_ID_START

    # IS_ID_CONTINUE: id_start + digits
    if flags & F_IS_ID_START:
        flags |= F_IS_ID_CONTINUE
    if 0x30 <= cp <= 0x39:
        flags |= F_IS_ID_CONTINUE

    # IS_WHITESPACE: space tab (NOT newline — C needs newline as its own token)
    if cp in (0x20, 0x09):
        flags |= F_IS_WHITESPACE

    # IS_HEX: 0-9 a-f A-F
    if (0x30 <= cp <= 0x39) or (0x61 <= cp <= 0x66) or (0x41 <= cp <= 0x46):
        flags |= F_IS_HEX

    # IS_OPERATOR: C operators + brackets + preprocessor
    if cp < 128 and cp in C_OPERATORS:
        flags |= F_IS_OPERATOR

    # IS_QUOTE: " '
    if cp in (0x22, 0x27):
        flags |= F_IS_QUOTE

    # IS_DIGIT: 0-9
    if 0x30 <= cp <= 0x39:
        flags |= F_IS_DIGIT

    # IS_NEWLINE: \n \r (bit 7, borrows from digit_value field)
    if cp in (0x0A, 0x0D):
        flags |= F_IS_NEWLINE

    return flags


def json_flags_for(cp):
    """Compute the JSON lexer flag byte for a codepoint."""
    flags = 0
    # IS_DIGIT — 0-9 plus '-' (number start; standalone '-' becomes T_NUMBER too)
    if (0x30 <= cp <= 0x39) or cp == 0x2D:
        flags |= JF_IS_DIGIT
    # IS_QUOTE — only the JSON string delimiter
    if cp == 0x22:
        flags |= JF_IS_QUOTE
    # IS_STRUCT — { } [ ] , :
    if cp == 0x7B or cp == 0x7D or cp == 0x5B or cp == 0x5D or cp == 0x2C or cp == 0x3A:
        flags |= JF_IS_STRUCT
    # IS_WHITESPACE — JSON's four whitespace chars
    if cp == 0x20 or cp == 0x09 or cp == 0x0A or cp == 0x0D:
        flags |= JF_IS_WHITESPACE
    # IS_KEYWORD — first chars of true / false / null
    if cp == 0x74 or cp == 0x66 or cp == 0x6E:
        flags |= JF_IS_KEYWORD
    # IS_NUM_CONT — 0-9 . e E + -
    if (0x30 <= cp <= 0x39) or cp == 0x2E or cp == 0x65 or cp == 0x45 or cp == 0x2B or cp == 0x2D:
        flags |= JF_IS_NUM_CONT
    # IS_ESCAPE — backslash (used by string-content scan_to_cp_or)
    if cp == 0x5C:
        flags |= JF_IS_ESCAPE
    return flags


def tungsten_flags_for(cp, ucd):
    """Compute the Tungsten compiler lexer flag byte for a codepoint."""
    cat, _digit = ucd.get(cp, (29, 0xF))
    flags = 0

    # IS_ID_START: lowercase ASCII, underscore, and Unicode letters.
    # Uppercase ASCII is intentionally excluded; the lexer treats it as NAME.
    # ∫ (U+222B, category Sm) is blessed as a callable name like Σ (a letter,
    # which qualifies naturally) — `∫(x², 0..2)`.
    if (0x61 <= cp <= 0x7A) or cp == 0x5F:
        flags |= TF_IS_ID_START
    elif cp >= 128 and (cat <= 4 or cp == 0x222B):  # Lu..Lo, plus ∫
        flags |= TF_IS_ID_START

    # IS_ID_CONTINUE: id_start + ASCII digits.
    if flags & TF_IS_ID_START:
        flags |= TF_IS_ID_CONTINUE
    if 0x30 <= cp <= 0x39:
        flags |= TF_IS_ID_CONTINUE

    # IS_WHITESPACE: space and tab only. Newline has its own dispatch bit.
    if cp in (0x20, 0x09):
        flags |= TF_IS_WHITESPACE

    # IS_HEX: 0-9 a-f A-F.
    if (0x30 <= cp <= 0x39) or (0x61 <= cp <= 0x66) or (0x41 <= cp <= 0x46):
        flags |= TF_IS_HEX

    # IS_OPERATOR: ASCII operators and delimiters used by the compiler lexer.
    if cp < 128 and cp in TUNGSTEN_OPERATORS:
        flags |= TF_IS_OPERATOR

    # IS_QUOTE: keep single quote flagged too, matching the default LexChar
    # cache and making the spike tolerant of future single-quote work.
    if cp in (0x22, 0x27):
        flags |= TF_IS_QUOTE

    # IS_DIGIT: 0-9. Unlike the default 64-bit LexChar cache, language tables
    # replace the digit_value nibble, so the fast lexers use this flag.
    if 0x30 <= cp <= 0x39:
        flags |= TF_IS_DIGIT

    # IS_NEWLINE: \n \r.
    if cp in (0x0A, 0x0D):
        flags |= TF_IS_NEWLINE

    return flags


def ruby_flags_for(cp, ucd):
    """Compute the Ruby lexer flag byte for a codepoint."""
    cat, _digit = ucd.get(cp, (29, 0xF))
    flags = 0

    # IS_ID_START: a-z A-Z _ + Unicode letters.
    if (0x61 <= cp <= 0x7A) or (0x41 <= cp <= 0x5A) or cp == 0x5F:
        flags |= RF_IS_ID_START
    elif cp >= 128 and cat <= 4:  # Lu..Lo
        flags |= RF_IS_ID_START

    # IS_ID_CONTINUE: id_start + ASCII digits.
    if flags & RF_IS_ID_START:
        flags |= RF_IS_ID_CONTINUE
    if 0x30 <= cp <= 0x39:
        flags |= RF_IS_ID_CONTINUE

    # IS_WHITESPACE: space/tab; newline keeps its own dispatch bit.
    if cp in (0x20, 0x09):
        flags |= RF_IS_WHITESPACE

    # IS_HEX: 0-9 a-f A-F.
    if (0x30 <= cp <= 0x39) or (0x61 <= cp <= 0x66) or (0x41 <= cp <= 0x46):
        flags |= RF_IS_HEX

    # IS_OPERATOR: Ruby ASCII operators, delimiters, and sigil starts.
    if cp < 128 and cp in RUBY_OPERATORS:
        flags |= RF_IS_OPERATOR

    # IS_QUOTE: Ruby string-ish delimiters handled by the scalar scanner.
    if cp in (0x22, 0x27, 0x60):
        flags |= RF_IS_QUOTE

    # IS_DIGIT: 0-9.
    if 0x30 <= cp <= 0x39:
        flags |= RF_IS_DIGIT

    # IS_NEWLINE: \n \r.
    if cp in (0x0A, 0x0D):
        flags |= RF_IS_NEWLINE

    return flags


def assert_json_ascii(buf):
    assert buf[ord('{')] == JF_IS_STRUCT, f"'{{' wrong: {buf[ord('{')]:#x}"
    assert buf[ord('"')] == JF_IS_QUOTE, f"'\"' wrong: {buf[ord('\"')]:#x}"
    assert buf[ord(' ')] == JF_IS_WHITESPACE, f"space wrong: {buf[ord(' ')]:#x}"
    assert buf[ord('\n')] == JF_IS_WHITESPACE, f"newline wrong: {buf[ord(chr(0x0A))]:#x}"
    assert buf[ord('5')] == JF_IS_DIGIT | JF_IS_NUM_CONT, f"'5' wrong: {buf[ord('5')]:#x}"
    assert buf[ord('-')] == JF_IS_DIGIT | JF_IS_NUM_CONT, f"'-' wrong: {buf[ord('-')]:#x}"
    assert buf[ord('e')] == JF_IS_NUM_CONT, f"'e' wrong: {buf[ord('e')]:#x}"
    assert buf[ord('t')] == JF_IS_KEYWORD, f"'t' wrong: {buf[ord('t')]:#x}"
    assert buf[ord('\\')] == JF_IS_ESCAPE, f"'\\\\' wrong: {buf[ord(chr(0x5C))]:#x}"


def assert_c_ascii(buf):
    """Spot-check a handful of well-known ASCII flag values."""
    assert buf[ord('a')] == F_IS_ID_START | F_IS_ID_CONTINUE | F_IS_HEX, f"'a' flags wrong: {buf[ord('a')]:#x}"
    assert buf[ord('A')] == F_IS_ID_START | F_IS_ID_CONTINUE | F_IS_HEX, f"'A' flags wrong: {buf[ord('A')]:#x}"
    assert buf[ord('0')] == F_IS_ID_CONTINUE | F_IS_HEX | F_IS_DIGIT, f"'0' flags wrong: {buf[ord('0')]:#x}"
    assert buf[ord('+')] == F_IS_OPERATOR, f"'+' flags wrong: {buf[ord('+')]:#x}"
    assert buf[ord('"')] == F_IS_QUOTE, f"'\"' flags wrong: {buf[ord(chr(0x22))]:#x}"
    assert buf[ord(' ')] == F_IS_WHITESPACE, f"' ' flags wrong: {buf[ord(' ')]:#x}"
    assert buf[ord('\n')] == F_IS_NEWLINE, f"'\\n' flags wrong: {buf[ord(chr(0x0A))]:#x}"


def assert_tungsten_ascii(buf):
    """Spot-check Tungsten-specific lexer flag values."""
    assert buf[ord('a')] == TF_IS_ID_START | TF_IS_ID_CONTINUE | TF_IS_HEX, f"'a' flags wrong: {buf[ord('a')]:#x}"
    assert buf[ord('_')] == TF_IS_ID_START | TF_IS_ID_CONTINUE, f"'_' flags wrong: {buf[ord('_')]:#x}"
    assert buf[ord('A')] == TF_IS_HEX, f"'A' flags wrong: {buf[ord('A')]:#x}"
    assert buf[ord('G')] == 0, f"'G' flags wrong: {buf[ord('G')]:#x}"
    assert buf[ord('0')] == TF_IS_ID_CONTINUE | TF_IS_HEX | TF_IS_DIGIT, f"'0' flags wrong: {buf[ord('0')]:#x}"
    assert buf[ord('+')] == TF_IS_OPERATOR, f"'+' flags wrong: {buf[ord('+')]:#x}"
    assert buf[ord('"')] == TF_IS_QUOTE, f"'\"' flags wrong: {buf[ord(chr(0x22))]:#x}"
    assert buf[ord(' ')] == TF_IS_WHITESPACE, f"' ' flags wrong: {buf[ord(' ')]:#x}"
    assert buf[ord('\n')] == TF_IS_NEWLINE, f"'\\n' flags wrong: {buf[ord(chr(0x0A))]:#x}"


def assert_ruby_ascii(buf):
    """Spot-check Ruby-specific lexer flag values."""
    assert buf[ord('a')] == RF_IS_ID_START | RF_IS_ID_CONTINUE | RF_IS_HEX, f"'a' flags wrong: {buf[ord('a')]:#x}"
    assert buf[ord('A')] == RF_IS_ID_START | RF_IS_ID_CONTINUE | RF_IS_HEX, f"'A' flags wrong: {buf[ord('A')]:#x}"
    assert buf[ord('_')] == RF_IS_ID_START | RF_IS_ID_CONTINUE, f"'_' flags wrong: {buf[ord('_')]:#x}"
    assert buf[ord('0')] == RF_IS_ID_CONTINUE | RF_IS_HEX | RF_IS_DIGIT, f"'0' flags wrong: {buf[ord('0')]:#x}"
    assert buf[ord('+')] == RF_IS_OPERATOR, f"'+' flags wrong: {buf[ord('+')]:#x}"
    assert buf[ord('@')] == RF_IS_OPERATOR, f"'@' flags wrong: {buf[ord('@')]:#x}"
    assert buf[ord('$')] == RF_IS_OPERATOR, f"'$' flags wrong: {buf[ord('$')]:#x}"
    assert buf[ord('"')] == RF_IS_QUOTE, f"'\"' flags wrong: {buf[ord(chr(0x22))]:#x}"
    assert buf[ord('`')] == RF_IS_QUOTE, f"'`' flags wrong: {buf[ord('`')]:#x}"
    assert buf[ord(' ')] == RF_IS_WHITESPACE, f"' ' flags wrong: {buf[ord(' ')]:#x}"
    assert buf[ord('\n')] == RF_IS_NEWLINE, f"'\\n' flags wrong: {buf[ord(chr(0x0A))]:#x}"


def gen_c(ucd, root, bits):
    """Write languages/c/c.lex<bits>.

    bits=64 / 32: 1 byte per codepoint over the full 0x110000 range.
                  lex64 and lex32 share the byte content; the bit width
                  refers to the LexChar element the runtime packs into.
    bits=16:      1 byte per ASCII-range codepoint (256 bytes total).
                  Non-ASCII codepoints are handled at packing time."""
    suffix = f"lex{bits}"
    out_path = os.path.join(root, "languages", "c", f"c.{suffix}")
    print(f"Generating {out_path}...")

    if bits in (32, 64):
        buf = bytearray(MAX_CP)
        for cp in range(MAX_CP):
            buf[cp] = c_flags_for(cp, ucd)
    elif bits == 16:
        buf = bytearray(256)
        for cp in range(256):
            buf[cp] = c_flags_for(cp, ucd)
    else:
        raise SystemExit(f"unsupported bits={bits} (must be 16, 32, or 64)")

    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"  wrote {len(buf)} bytes ({len(buf) / 1024:.1f} KB)")

    assert_c_ascii(buf)
    print("  all assertions passed")


def gen_json(root, bits):
    """Write languages/json/json.lex<bits>."""
    suffix = f"lex{bits}"
    out_path = os.path.join(root, "languages", "json", f"json.{suffix}")
    print(f"Generating {out_path}...")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    if bits in (32, 64):
        buf = bytearray(MAX_CP)
        for cp in range(MAX_CP):
            buf[cp] = json_flags_for(cp)
    elif bits == 16:
        buf = bytearray(256)
        for cp in range(256):
            buf[cp] = json_flags_for(cp)
    else:
        raise SystemExit(f"unsupported bits={bits} (must be 16, 32, or 64)")

    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"  wrote {len(buf)} bytes ({len(buf) / 1024:.1f} KB)")
    assert_json_ascii(buf)
    print("  all assertions passed")


def gen_tungsten(ucd, root, bits):
    """Write languages/tungsten/tungsten.lex<bits>."""
    suffix = f"lex{bits}"
    out_path = os.path.join(root, "languages", "tungsten", f"tungsten.{suffix}")
    print(f"Generating {out_path}...")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    if bits in (32, 64):
        buf = bytearray(MAX_CP)
        for cp in range(MAX_CP):
            buf[cp] = tungsten_flags_for(cp, ucd)
    elif bits == 16:
        buf = bytearray(256)
        for cp in range(256):
            buf[cp] = tungsten_flags_for(cp, ucd)
    else:
        raise SystemExit(f"unsupported bits={bits} (must be 16, 32, or 64)")

    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"  wrote {len(buf)} bytes ({len(buf) / 1024:.1f} KB)")
    assert_tungsten_ascii(buf)
    print("  all assertions passed")


def gen_ruby(ucd, root, bits):
    """Write languages/ruby/ruby.lex<bits>."""
    suffix = f"lex{bits}"
    out_path = os.path.join(root, "languages", "ruby", f"ruby.{suffix}")
    print(f"Generating {out_path}...")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    if bits in (32, 64):
        buf = bytearray(MAX_CP)
        for cp in range(MAX_CP):
            buf[cp] = ruby_flags_for(cp, ucd)
    elif bits == 16:
        buf = bytearray(256)
        for cp in range(256):
            buf[cp] = ruby_flags_for(cp, ucd)
    else:
        raise SystemExit(f"unsupported bits={bits} (must be 16, 32, or 64)")

    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"  wrote {len(buf)} bytes ({len(buf) / 1024:.1f} KB)")
    assert_ruby_ascii(buf)
    print("  all assertions passed")


def main():
    parser = argparse.ArgumentParser(description="Generate Unicode codepoint tables")
    parser.add_argument("--lang", choices=["c", "json", "ruby", "tungsten"], help="Generate language-specific table")
    parser.add_argument("--bits", type=int, choices=[16, 32, 64], default=64,
                        help="LexChar element width for the language table (default 64)")
    args = parser.parse_args()

    print("Loading Unicode data...")
    ucd = load_unicode_data()
    root = os.path.join(os.path.dirname(__file__), "..")

    gen_base(ucd, root)

    if args.lang == "c":
        gen_c(ucd, root, args.bits)
    elif args.lang == "json":
        gen_json(root, args.bits)
    elif args.lang == "ruby":
        gen_ruby(ucd, root, args.bits)
    elif args.lang == "tungsten":
        gen_tungsten(ucd, root, args.bits)


if __name__ == "__main__":
    main()

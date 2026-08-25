#!/usr/bin/env python3
"""Generate spec/core/string_unicode_spec.w from the vector files that
scripts/gen_unicode_tables.py writes to spec/fixtures/unicode/.

The spec is self-contained Tungsten (strings built from codepoint arrays via
Int#chr — no file I/O, no astral literals), so it runs identically compiled
and interpreted."""
import os
import sys
import unicodedata

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fix = os.path.join(root, "spec", "fixtures", "unicode")
out_path = os.path.join(root, "spec", "core", "string_unicode_spec.w")


def warr(cps):
    return "[" + ", ".join(f"0x{c:X}" for c in cps) + "]"


lines = ['''# Unicode String surface: normalization (UAX #15), grapheme clusters
# (UAX #29 incl. GB9c), astralize, inflections, and scan. The normalization
# and grapheme expectations are generated from Python's unicodedata and the
# full UCD GraphemeBreakTest by scripts/gen_unicode_spec.py — regenerate via
# scripts/gen_unicode_tables.py + gen_unicode_spec.py, never edit by hand.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

# Build a String from codepoints; astral literals have no escape spelling.
-> s(cps)
  out = StringBuffer(cps.size * 4)
  cps.each -> (cp)
    out << cp.chr
  out.to_s

-> check_norm(i, src, c_w, d_w, kc_w, kd_w)
  v = s(src)
  check("nfc [i]", v.nfc, s(c_w))
  check("nfd [i]", v.nfd, s(d_w))
  check("nfkc [i]", v.nfkc, s(kc_w))
  check("nfkd [i]", v.nfkd, s(kd_w))

-> check_graph(i, src, clusters)
  v = s(src)
  got = []
  v.each_grapheme -> (g)
    got.push(g)
  want = []
  clusters.each -> (c)
    want.push(s(c))
  check("graphemes [i]", got, want)
''']

# ---- normalization vectors
n = 0
for row in open(os.path.join(fix, "norm_vectors.tsv")):
    cols = row.rstrip("\n").split("\t")
    vecs = [[int(x, 16) for x in c.split()] if c else [] for c in cols]
    src, c_w, d_w, kc_w, kd_w = vecs
    lines.append(f"check_norm({n}, {warr(src)}, {warr(c_w)}, {warr(d_w)}, {warr(kc_w)}, {warr(kd_w)})")
    n += 1
lines.append(f'<< "normalization: {n} vectors x 4 forms ok"')
lines.append("")

# ---- grapheme vectors (full UCD GraphemeBreakTest)
g = 0
for row in open(os.path.join(fix, "grapheme_vectors.tsv")):
    src_s, breaks_s = row.rstrip("\n").split("\t")
    cps = [int(x, 16) for x in src_s.split()]
    breaks = [int(x) for x in breaks_s.split()] if breaks_s else []
    clusters = []
    for bi, start in enumerate(breaks):
        end = breaks[bi + 1] if bi + 1 < len(breaks) else len(cps)
        clusters.append(cps[start:end])
    cl = "[" + ", ".join(warr(c) for c in clusters) + "]"
    lines.append(f"check_graph({g}, {warr(cps)}, {cl})")
    g += 1
lines.append(f'<< "graphemes: {g} GraphemeBreakTest vectors ok"')
lines.append("")

# ---- astralize expectations (computed with the verified block offsets)
UPPER = [0x1D400, 0x1D434, 0x1D468, 0x1D49C, 0x1D4D0, 0x1D504, 0x1D56C,
         0x1D538, 0x1D5A0, 0x1D5D4, 0x1D608, 0x1D63C, 0x1D670]
LOWER = [0x1D41A, 0x1D44E, 0x1D482, 0x1D4B6, 0x1D4EA, 0x1D51E, 0x1D586,
         0x1D552, 0x1D5BA, 0x1D5EE, 0x1D622, 0x1D656, 0x1D68A]
DIGIT = {1: 0x1D7CE, 8: 0x1D7D8, 9: 0x1D7E2, 10: 0x1D7EC, 13: 0x1D7F6}
EXC = {
    2: {ord("h"): 0x210E},
    4: {ord("B"): 0x212C, ord("E"): 0x2130, ord("F"): 0x2131, ord("H"): 0x210B,
        ord("I"): 0x2110, ord("L"): 0x2112, ord("M"): 0x2133, ord("R"): 0x211B,
        ord("e"): 0x212F, ord("g"): 0x210A, ord("o"): 0x2134},
    6: {ord("C"): 0x212D, ord("H"): 0x210C, ord("I"): 0x2111, ord("R"): 0x211C,
        ord("Z"): 0x2128},
    8: {ord("C"): 0x2102, ord("H"): 0x210D, ord("N"): 0x2115, ord("P"): 0x2119,
        ord("Q"): 0x211A, ord("R"): 0x211D, ord("Z"): 0x2124},
}


def astral(text, style):
    out = []
    for ch in text:
        cp = ord(ch)
        m = EXC.get(style, {}).get(cp)
        if m:
            out.append(m)
        elif 65 <= cp <= 90:
            out.append(UPPER[style - 1] + cp - 65)
        elif 97 <= cp <= 122:
            out.append(LOWER[style - 1] + cp - 97)
        elif 48 <= cp <= 57 and style in DIGIT:
            out.append(DIGIT[style] + cp - 48)
        else:
            out.append(cp)
    # every mapped codepoint must be a named character (catches offset bugs)
    for cp in out:
        if cp > 0x2000:
            unicodedata.name(chr(cp))
    return out


astral_cases = [
    ("AZaz09 ok", "bold: true", astral("AZaz09 ok", 1)),
    ("hix", "italic: true", astral("hix", 2)),
    ("Wf", "bold: true, italic: true", astral("Wf", 3)),
    ("BegoHILMRFhz", "script: true", astral("BegoHILMRFhz", 4)),
    ("Bego", "script: true, bold: true", astral("Bego", 5)),
    ("CHIRZx", "fraktur: true", astral("CHIRZx", 6)),
    ("CHIRZx", "fraktur: true, bold: true", astral("CHIRZx", 7)),
    ("CHNPQRZ09", "double_struck: true", astral("CHNPQRZ09", 8)),
    ("Ab12", "sansserif: true", astral("Ab12", 9)),
    ("Ab12", "sansserif: true, bold: true", astral("Ab12", 10)),
    ("Ab", "sansserif: true, italic: true", astral("Ab", 11)),
    ("Ab", "sansserif: true, bold: true, italic: true", astral("Ab", 12)),
    ("mono01", "monospace: true", astral("mono01", 13)),
]
for i, (text, kwargs, want) in enumerate(astral_cases):
    lines.append(f'check("astralize {i}", "{text}".astralize({kwargs}), s({warr(want)}))')
lines.append('check("astralize identity", "plain".astralize, "plain")')
lines.append('<< "astralize ok"')
lines.append("")

lines.append('''# ---- normalize dispatch, canonical equivalence
check("normalize kc", s([0x3212]).normalize(:kc), s([0x28, 0xB9C8, 0x29]))
check("normalize default", s([0x45, 0x301]).normalize, s([0xC9]))
composed = s([0xE9])
decomposed = s([0x65, 0x301])
check("canonical eq", composed.canonically_equivalent?(decomposed), true)
check("canonical eq exact-neq", composed == decomposed, false)
check("canonical neq", "a".canonically_equivalent?("b"), false)
check("nfc ascii identity", "plain ascii".nfc, "plain ascii")
check("nfc symbol", s([0x65, 0x301]).to_sym.nfc, composed)
<< "normalization dispatch ok"

# ---- scan (literal patterns; regex-literal scans live in
# spec/compiler/string_scan_spec.w — the tree-walker has no regex literals)
check("scan literal", "aaaa".scan("aa"), ["aa", "aa"])
check("scan literal none", "abc".scan("zz"), [])
check("scan literal one", "x1y2".scan("y"), ["y"])
<< "scan ok"

# ---- graphemes: readable smoke on top of the vector sweep
check("flags cluster", s([0x1F1FA, 0x1F1F8, 0x1F1EB, 0x1F1F7]).graphemes.size, 2)
check("zwj family cluster", s([0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]).graphemes.size, 1)
check("hangul jamo cluster", s([0xAC01]).nfd.graphemes.size, 1)
check("graphemes view type", type("ab".graphemes), "StringGraphemes")
check("graphemes to_a", "ab".graphemes.to_a, ["a", "b"])
check("combining cluster", s([0x65, 0x301, 0x78]).graphemes.size, 2)
<< "grapheme smoke ok"

# ---- inflections
check("camelize", "foo_bar_baz".camelize, "FooBarBaz")
check("camelize mixed", "foo-bar baz".camelize, "FooBarBaz")
check("underscore", "FooBar".underscore, "foo_bar")
check("underscore acronym", "HTTPServer".underscore, "http_server")
check("underscore digits", "fooBar42Baz".underscore, "foo_bar42_baz")
check("underscore dash", "foo-bar".underscore, "foo_bar")
check("snakecase", "FooBar".snakecase, "foo_bar")
check("dasherize", "foo_bar".dasherize, "foo-bar")
check("humanize", "employee_salary".humanize, "Employee salary")
check("transliterate", s([0xC6, 0x72, 0xF8, 0x73]).transliterate, "AEros")
check("transliterate accents", s([0x43, 0x72, 0xE8, 0x6D, 0x65]).transliterate, "Creme")
check("transliterate unknown", s([0x65, 0x4E00]).transliterate, "e?")
check("transliterate custom", s([0x4E00]).transliterate("_"), "_")
check("parameterize", s([0x43, 0x72, 0xE8, 0x6D, 0x65, 0x20, 0x42, 0x72, 0xFB, 0x6C, 0xE9, 0x65, 0x21]).parameterize, "creme-brulee")
check("parameterize sep", "  Uber  droit ".parameterize("_"), "uber_droit"
)
check("parameterize trims", "--a--b--".parameterize, "a-b")
check("lowercase", "AbC".lowercase, "abc")
check("uppercase", "AbC".uppercase, "ABC")
check("includes?", "hello".includes?("ell"), true)
<< "inflections ok"

# ---- approx operator = canonical equivalence on text
check("approx nfc", composed ≈ decomposed, true)
check("approx neq", "x" ≈ "y", false)
check("approx symbol", "ab".to_sym ≈ "ab", true)

# ---- to_regex: literal-match compilation through the native engine
trx = "a.b".to_regex
check("to_regex hits literal", trx.match?("xa.bz"), true)
check("to_regex escapes dot", trx.match?("xaXbz"), false)
check("to_regex meta", "a+b".to_regex.match?("za+bz"), true)

# ---- constantize
ck = "Array".constantize
ca = ck.new
ca.push(7)
check("constantize new", ca, [7])
cz_err = ""
begin
  "NoSuchKlass99".constantize
rescue error
  cz_err = error
check("constantize unknown raises", cz_err.contains?("NoSuchKlass99"), true)

# ---- []= functional index write (returns a StringBuffer)
iw = "hello"
ib = (iw[0] = "H")
check("index write", ib.to_s, "Hello")
check("index write immutably", iw, "hello")
check("index write negative", ("abc"[-1] = "Z").to_s, "abZ")
check("index write utf8", (s([0x61, 0xE9, 0x63])[1] = "X").to_s, "aXc")
check("index write multichar", ("abc"[1] = "--").to_s, "a--c")
iw_err = ""
begin
  "abc"[9] = "x"
rescue error
  iw_err = error
check("index write oob raises", iw_err.contains?("out of range"), true)
<< "operators and conversions ok"

<< "string_unicode_spec: all checks passed"''')

with open(out_path, "w") as f:
    f.write("\n".join(lines) + "\n")
scan_path = os.path.join(root, "spec", "compiler", "string_scan_spec.w")
with open(scan_path, "w") as f:
    f.write("""# String#scan over native regex literals (compiled lanes only: the
# tree-walker has no regex-literal AST support). Generated by
# scripts/gen_unicode_spec.py.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("scan digits", "a1b22c333".scan(/[0-9]+/), ["1", "22", "333"])
check("scan groups", "a=1,b=2".scan(/([a-z])=([0-9])/), [["a", "1"], ["b", "2"]])
check("scan no match", "abc".scan(/[0-9]/), [])
check("scan anchored", "aXbX".scan(/^./), ["a"])
check("scan empty advance", "ab".scan(/x*/), ["", "", ""])
check("scan utf8", ("é" * 3).scan("é"), ["é", "é", "é"])

<< "string_scan_spec: all checks passed"
""")
print(f"wrote {scan_path}")

print(f"wrote {out_path} ({os.path.getsize(out_path)} bytes, {n} norm + {g} grapheme vectors)")

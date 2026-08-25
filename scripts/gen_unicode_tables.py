#!/usr/bin/env python3
"""Generate runtime/unicode_tables.c — Unicode normalization + grapheme data.

Sources:
  - Python's unicodedata (Unicode 16.0.0) for canonical/compat decompositions,
    canonical combining classes, and composition pairs (exclusions derived by
    NFC round-trip, so no CompositionExclusions.txt parse is needed).
  - UCD auxiliary/GraphemeBreakProperty.txt + emoji/emoji-data.txt
    (Extended_Pictographic) for UAX #29 extended grapheme cluster classes.

Before emitting anything, this script VALIDATES a Python mirror of the exact
algorithms runtime.c implements (decompose -> canonical order -> compose)
against unicodedata.normalize over every single codepoint x 4 forms plus a
large adversarial random corpus. A table or algorithm bug fails the run.

Usage: python3 scripts/gen_unicode_tables.py <ucd_dir> [out.c]
  <ucd_dir> must contain GraphemeBreakProperty.txt and emoji-data.txt.
  Also writes norm_vectors.tsv and grapheme_vectors.tsv (from
  GraphemeBreakTest.txt when present) next to the output for spec generation.
"""
import os
import random
import sys
import unicodedata

MAX_CP = 0x110000
SBASE, LBASE, VBASE, TBASE = 0xAC00, 0x1100, 0x1161, 0x11A7
LCOUNT, VCOUNT, TCOUNT = 19, 21, 28
NCOUNT = VCOUNT * TCOUNT
SCOUNT = LCOUNT * NCOUNT


def is_hangul_syl(cp):
    return SBASE <= cp < SBASE + SCOUNT


def is_surrogate(cp):
    return 0xD800 <= cp <= 0xDFFF


# ---------------------------------------------------------------- tables
print("building tables from unicodedata", unicodedata.unidata_version)
ccc = {}
for cp in range(MAX_CP):
    if is_surrogate(cp):
        continue
    c = unicodedata.combining(chr(cp))
    if c:
        ccc[cp] = c

nfd_map, nfkd_map = {}, {}
for cp in range(MAX_CP):
    if is_surrogate(cp) or is_hangul_syl(cp):
        continue
    ch = chr(cp)
    d = unicodedata.normalize("NFD", ch)
    if d != ch:
        nfd_map[cp] = tuple(map(ord, d))
    kd = unicodedata.normalize("NFKD", ch)
    if kd != ch:
        nfkd_map[cp] = tuple(map(ord, kd))

comp = {}
for cp in range(MAX_CP):
    if is_surrogate(cp) or is_hangul_syl(cp):
        continue
    raw = unicodedata.decomposition(chr(cp))
    if not raw or raw.startswith("<"):
        continue
    parts = [int(x, 16) for x in raw.split()]
    if len(parts) != 2:
        continue
    a, b = parts
    if unicodedata.normalize("NFC", chr(a) + chr(b)) == chr(cp):
        comp[(a, b)] = cp

print(f"  ccc={len(ccc)} nfd={len(nfd_map)} nfkd={len(nfkd_map)} comp={len(comp)}")


# ------------------------------------------------- python mirror of the C code
def get_ccc(cp):
    return ccc.get(cp, 0)


def decomp_one(cp, compat, out):
    if is_hangul_syl(cp):
        si = cp - SBASE
        out.append(LBASE + si // NCOUNT)
        out.append(VBASE + (si % NCOUNT) // TCOUNT)
        t = si % TCOUNT
        if t:
            out.append(TBASE + t)
        return
    m = (nfkd_map if compat else nfd_map).get(cp)
    if m is not None:
        out.extend(m)
    else:
        out.append(cp)


def canonical_order(buf):
    # In-place stable exchange sort over nonzero-ccc runs (exactly what the
    # C loop does; runs are short so O(n^2) within a run is fine).
    i = 1
    n = len(buf)
    while i < n:
        cc = get_ccc(buf[i])
        if cc != 0 and get_ccc(buf[i - 1]) > cc:
            buf[i - 1], buf[i] = buf[i], buf[i - 1]
            i = i - 1 if i > 1 else i + 1
        else:
            i += 1


def try_compose(a, b):
    # Hangul algorithmic composition first.
    if LBASE <= a < LBASE + LCOUNT and VBASE <= b < VBASE + VCOUNT:
        return SBASE + ((a - LBASE) * VCOUNT + (b - VBASE)) * TCOUNT
    if is_hangul_syl(a) and (a - SBASE) % TCOUNT == 0 and TBASE < b < TBASE + TCOUNT:
        return a + (b - TBASE)
    return comp.get((a, b))


def compose_buf(buf):
    if not buf:
        return buf
    out = [buf[0]]
    starter = 0 if get_ccc(buf[0]) == 0 else -1
    last_cc = get_ccc(buf[0])
    for cp in buf[1:]:
        cc = get_ccc(cp)
        if starter >= 0 and (last_cc == 0 or last_cc < cc):
            c = try_compose(out[starter], cp)
            if c is not None:
                out[starter] = c
                continue
        out.append(cp)
        if cc == 0:
            starter = len(out) - 1
        last_cc = cc
    return out


def normalize_py(form, s):
    compat = form in ("NFKC", "NFKD")
    buf = []
    for ch in s:
        decomp_one(ord(ch), compat, buf)
    canonical_order(buf)
    if form in ("NFC", "NFKC"):
        buf = compose_buf(buf)
    return "".join(map(chr, buf))


# ---------------------------------------------------------------- validation
print("validating: every codepoint x 4 forms")
forms = ("NFC", "NFD", "NFKC", "NFKD")
bad = 0
for cp in range(MAX_CP):
    if is_surrogate(cp):
        continue
    ch = chr(cp)
    for f in forms:
        want = unicodedata.normalize(f, ch)
        got = normalize_py(f, ch)
        if want != got:
            bad += 1
            if bad < 10:
                print(f"  MISMATCH {f} U+{cp:04X}: want {[hex(ord(c)) for c in want]} got {[hex(ord(c)) for c in got]}")
if bad:
    sys.exit(f"single-codepoint validation FAILED: {bad} mismatches")

print("validating: adversarial random corpus")
rng = random.Random(20260825)
starters_with_decomp = [cp for cp in nfd_map if get_ccc(cp) == 0]
marks = sorted(ccc)
compat_chars = [cp for cp in nfkd_map if cp not in nfd_map]
hangul = [SBASE + rng.randrange(SCOUNT) for _ in range(500)]
jamo = list(range(LBASE, LBASE + LCOUNT)) + list(range(VBASE, VBASE + VCOUNT)) + list(range(TBASE + 1, TBASE + TCOUNT))
plain = [rng.randrange(0x20, 0x3000) for _ in range(500)]
pool = starters_with_decomp + marks * 3 + compat_chars + hangul + jamo + plain
pool = [cp for cp in pool if not is_surrogate(cp)]
for trial in range(60000):
    n = rng.randrange(1, 12)
    s = "".join(chr(rng.choice(pool)) for _ in range(n))
    for f in forms:
        want = unicodedata.normalize(f, s)
        got = normalize_py(f, s)
        if want != got:
            sys.exit(
                f"random corpus FAILED trial {trial} form {f} input {[hex(ord(c)) for c in s]}: "
                f"want {[hex(ord(c)) for c in want]} got {[hex(ord(c)) for c in got]}"
            )
print("  validation clean")

# --------------------------------------------------------- grapheme property
ucd_dir = sys.argv[1] if len(sys.argv) > 1 else "."
GCB_CLASSES = [
    "Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator",
    "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT",
]
gcb_id = {name: i for i, name in enumerate(GCB_CLASSES)}


def parse_ucd_ranges(path):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        rng_s, prop = [x.strip() for x in line.split(";")[:2]]
        if ".." in rng_s:
            a, b = [int(x, 16) for x in rng_s.split("..")]
        else:
            a = b = int(rng_s, 16)
        out.append((a, b, prop))
    return out


gcb_ranges = []
for a, b, prop in parse_ucd_ranges(os.path.join(ucd_dir, "GraphemeBreakProperty.txt")):
    if prop in gcb_id:
        gcb_ranges.append((a, b, gcb_id[prop]))
gcb_ranges.sort()

extpic_ranges = sorted(
    (a, b) for a, b, prop in parse_ucd_ranges(os.path.join(ucd_dir, "emoji-data.txt"))
    if prop == "Extended_Pictographic"
)

# Indic_Conjunct_Break (GB9c, Unicode 15.1+): DerivedCoreProperties.txt rows
# are "range ; InCB; Consonant|Extend|Linker".
INCB_ID = {"Consonant": 1, "Extend": 2, "Linker": 3}
incb_ranges = []
for line in open(os.path.join(ucd_dir, "DerivedCoreProperties.txt"), encoding="utf-8"):
    line = line.split("#")[0].strip()
    if not line:
        continue
    fields = [x.strip() for x in line.split(";")]
    if len(fields) < 3 or fields[1] != "InCB":
        continue
    rng_s, val = fields[0], fields[2]
    if ".." in rng_s:
        a, b = [int(x, 16) for x in rng_s.split("..")]
    else:
        a = b = int(rng_s, 16)
    incb_ranges.append((a, b, INCB_ID[val]))
incb_ranges.sort()
print(f"  gcb ranges={len(gcb_ranges)} extpic ranges={len(extpic_ranges)} incb ranges={len(incb_ranges)}")


def gcb_class(cp):
    lo, hi = 0, len(gcb_ranges)
    while lo < hi:
        mid = (lo + hi) // 2
        a, b, cls = gcb_ranges[mid]
        if cp < a:
            hi = mid
        elif cp > b:
            lo = mid + 1
        else:
            return cls
    return 0


def is_extpic(cp):
    lo, hi = 0, len(extpic_ranges)
    while lo < hi:
        mid = (lo + hi) // 2
        a, b = extpic_ranges[mid]
        if cp < a:
            hi = mid
        elif cp > b:
            lo = mid + 1
        else:
            return True
    return False


def incb(cp):
    lo, hi = 0, len(incb_ranges)
    while lo < hi:
        mid = (lo + hi) // 2
        a, b, v = incb_ranges[mid]
        if cp < a:
            hi = mid
        elif cp > b:
            lo = mid + 1
        else:
            return v
    return 0


# Python mirror of the C boundary rule (UAX #29 extended grapheme clusters).
O, CR, LF, CN, EX, ZWJ, RI, PP, SM, L, V, T, LV, LVT = range(14)


def _incb_linked(cps, i):
    """GB9c lookbehind: Consonant [Extend Linker]* Linker [Extend Linker]*
    immediately precedes position i."""
    j = i - 1
    linker_seen = False
    while j >= 0:
        v = incb(cps[j])
        if v == 3:
            linker_seen = True
        elif v == 2:
            pass
        elif v == 1:
            return linker_seen
        else:
            return False
        j -= 1
    return False


def grapheme_breaks(cps):
    """Return break positions (indices into cps where a boundary precedes)."""
    n = len(cps)
    if n == 0:
        return []
    breaks = [0]
    ri_run = 0
    # GB11 state: seen ExtPic (Extend* ZWJ)? tracked from last boundary-relevant base
    for i in range(1, n):
        a, b = cps[i - 1], cps[i]
        ca, cb = gcb_class(a), gcb_class(b)
        if ca == RI:
            ri_run += 1
        else:
            ri_run = 0
        brk = True
        if ca == CR and cb == LF:
            brk = False                              # GB3
        elif ca in (CN, CR, LF):
            brk = True                               # GB4
        elif cb in (CN, CR, LF):
            brk = True                               # GB5
        elif ca == L and cb in (L, V, LV, LVT):
            brk = False                              # GB6
        elif ca in (LV, V) and cb in (V, T):
            brk = False                              # GB7
        elif ca in (LVT, T) and cb == T:
            brk = False                              # GB8
        elif cb in (EX, ZWJ):
            brk = False                              # GB9
        elif cb == SM:
            brk = False                              # GB9a
        elif ca == PP:
            brk = False                              # GB9b
        elif incb(b) == 1 and _incb_linked(cps, i):
            brk = False                              # GB9c (Indic conjuncts)
        elif ca == ZWJ and is_extpic(cps[i]):
            # GB11: ExtPic Extend* ZWJ x ExtPic — verify the lookbehind
            j = i - 2
            while j >= 0 and gcb_class(cps[j]) == EX:
                j -= 1
            brk = not (j >= 0 and is_extpic(cps[j]))
        elif ca == RI and cb == RI:
            brk = ri_run % 2 == 0                    # GB12/13: pair up
        if brk:
            breaks.append(i)
    return breaks


# Validate against GraphemeBreakTest.txt when available.
gbt_path = os.path.join(ucd_dir, "GraphemeBreakTest.txt")
gb_vectors = []
if os.path.exists(gbt_path):
    total = fails = 0
    for line in open(gbt_path, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        toks = line.split()
        cps, breaks_want = [], []
        for t in toks:
            if t == "÷":
                breaks_want.append(len(cps))
            elif t == "×":
                pass
            else:
                cps.append(int(t, 16))
        breaks_want = breaks_want[:-1] if breaks_want and breaks_want[-1] == len(cps) else breaks_want
        got = grapheme_breaks(cps)
        total += 1
        if got != breaks_want:
            fails += 1
            if fails < 8:
                print(f"  GB MISMATCH {[hex(c) for c in cps]}: want {breaks_want} got {got}")
        gb_vectors.append((cps, breaks_want))
    print(f"  GraphemeBreakTest: {total - fails}/{total} pass")
    if fails:
        sys.exit("grapheme validation FAILED")

# ---------------------------------------------------------------- emit C
out_path = sys.argv[2] if len(sys.argv) > 2 else "runtime/unicode_tables.c"


def emit_u32(name, vals):
    lines = [f"static const uint32_t {name}[{len(vals)}] = {{"]
    for i in range(0, len(vals), 10):
        lines.append("    " + ", ".join(f"0x{v:X}" for v in vals[i:i + 10]) + ",")
    lines.append("};")
    return "\n".join(lines)


def emit_u64(name, vals):
    lines = [f"static const uint64_t {name}[{len(vals)}] = {{"]
    for i in range(0, len(vals), 6):
        lines.append("    " + ", ".join(f"0x{v:X}ULL" for v in vals[i:i + 6]) + ",")
    lines.append("};")
    return "\n".join(lines)


def emit_u8(name, vals):
    lines = [f"static const uint8_t {name}[{len(vals)}] = {{"]
    for i in range(0, len(vals), 20):
        lines.append("    " + ", ".join(str(v) for v in vals[i:i + 20]) + ",")
    lines.append("};")
    return "\n".join(lines)


def pack_expansion_table(m):
    keys = sorted(m)
    pool, idx = [], []
    for k in keys:
        exp = m[k]
        idx.append((len(pool) << 8) | len(exp))
        pool.extend(exp)
    return keys, idx, pool


nfd_keys, nfd_idx, nfd_pool = pack_expansion_table(nfd_map)
nfkd_keys, nfkd_idx, nfkd_pool = pack_expansion_table(nfkd_map)
ccc_keys = sorted(ccc)
ccc_vals = [ccc[k] for k in ccc_keys]
comp_keys = sorted((a << 32) | b for (a, b) in comp)
comp_vals = [comp[(k >> 32, k & 0xFFFFFFFF)] for k in comp_keys]
gcb_flat_a = [a for a, b, c in gcb_ranges]
gcb_flat_b = [b for a, b, c in gcb_ranges]
gcb_flat_c = [c for a, b, c in gcb_ranges]
ep_a = [a for a, b in extpic_ranges]
ep_b = [b for a, b in extpic_ranges]

parts = [f"""/* Generated by scripts/gen_unicode_tables.py — DO NOT EDIT.
 * Unicode {unicodedata.unidata_version} normalization + UAX #29 grapheme data.
 * Pure codepoint-level tables and lookups; the WValue-facing entry points
 * (w_string_normalize, w_string_grapheme_next) live in runtime.c.
 * Validated by the generator against Python's unicodedata over every
 * codepoint x 4 forms + a 60k adversarial corpus, and against the full
 * UCD GraphemeBreakTest.txt. */
#include <stdint.h>
#include <stddef.h>

#define UN_SBASE 0xAC00
#define UN_LBASE 0x1100
#define UN_VBASE 0x1161
#define UN_TBASE 0x11A7
#define UN_LCOUNT 19
#define UN_VCOUNT 21
#define UN_TCOUNT 28
#define UN_NCOUNT (UN_VCOUNT * UN_TCOUNT)
#define UN_SCOUNT (UN_LCOUNT * UN_NCOUNT)
""",
    emit_u32("un_nfd_keys", nfd_keys),
    emit_u32("un_nfd_idx", nfd_idx),
    emit_u32("un_nfd_pool", nfd_pool),
    emit_u32("un_nfkd_keys", nfkd_keys),
    emit_u32("un_nfkd_idx", nfkd_idx),
    emit_u32("un_nfkd_pool", nfkd_pool),
    emit_u32("un_ccc_keys", ccc_keys),
    emit_u8("un_ccc_vals", ccc_vals),
    emit_u64("un_comp_keys", comp_keys),
    emit_u32("un_comp_vals", comp_vals),
    emit_u32("un_gcb_lo", gcb_flat_a),
    emit_u32("un_gcb_hi", gcb_flat_b),
    emit_u8("un_gcb_cls", gcb_flat_c),
    emit_u32("un_extpic_lo", ep_a),
    emit_u32("un_extpic_hi", ep_b),
    emit_u32("un_incb_lo", [a for a, b, v in incb_ranges]),
    emit_u32("un_incb_hi", [b for a, b, v in incb_ranges]),
    emit_u8("un_incb_val", [v for a, b, v in incb_ranges]),
    """
static ptrdiff_t un_bsearch_u32(const uint32_t *keys, ptrdiff_t n, uint32_t k) {
    ptrdiff_t lo = 0, hi = n;
    while (lo < hi) {
        ptrdiff_t mid = (lo + hi) >> 1;
        if (keys[mid] < k) lo = mid + 1;
        else if (keys[mid] > k) hi = mid;
        else return mid;
    }
    return -1;
}

int un_ccc(uint32_t cp) {
    ptrdiff_t i = un_bsearch_u32(un_ccc_keys, (ptrdiff_t)(sizeof(un_ccc_keys) / 4), cp);
    return i < 0 ? 0 : un_ccc_vals[i];
}

/* Fully-expanded canonical (compat=0) or compatibility (compat=1)
 * decomposition. Returns length and points *out at the pool, or 0 when the
 * codepoint decomposes to itself. Hangul syllables are the caller's
 * algorithmic case. */
int un_decomp(uint32_t cp, int compat, const uint32_t **out) {
    const uint32_t *keys = compat ? un_nfkd_keys : un_nfd_keys;
    const uint32_t *idx = compat ? un_nfkd_idx : un_nfd_idx;
    const uint32_t *pool = compat ? un_nfkd_pool : un_nfd_pool;
    ptrdiff_t n = compat ? (ptrdiff_t)(sizeof(un_nfkd_keys) / 4)
                         : (ptrdiff_t)(sizeof(un_nfd_keys) / 4);
    ptrdiff_t i = un_bsearch_u32(keys, n, cp);
    if (i < 0) return 0;
    *out = pool + (idx[i] >> 8);
    return (int)(idx[i] & 0xFF);
}

/* Primary composite for a starter pair (Hangul included), or 0. */
uint32_t un_compose(uint32_t a, uint32_t b) {
    if (a >= UN_LBASE && a < UN_LBASE + UN_LCOUNT &&
        b >= UN_VBASE && b < UN_VBASE + UN_VCOUNT)
        return UN_SBASE + (((a - UN_LBASE) * UN_VCOUNT) + (b - UN_VBASE)) * UN_TCOUNT;
    if (a >= UN_SBASE && a < UN_SBASE + UN_SCOUNT && (a - UN_SBASE) % UN_TCOUNT == 0 &&
        b > UN_TBASE && b < UN_TBASE + UN_TCOUNT)
        return a + (b - UN_TBASE);
    uint64_t key = ((uint64_t)a << 32) | b;
    ptrdiff_t lo = 0, hi = (ptrdiff_t)(sizeof(un_comp_keys) / 8);
    while (lo < hi) {
        ptrdiff_t mid = (lo + hi) >> 1;
        if (un_comp_keys[mid] < key) lo = mid + 1;
        else if (un_comp_keys[mid] > key) hi = mid;
        else return un_comp_vals[mid];
    }
    return 0;
}

/* Strong presence probe: overrides runtime.c's weak stand-in when this
 * translation unit is linked (gated-companion pattern, like lexchars). */
int un_tables_present(void) { return 1; }

/* UAX #29 Grapheme_Cluster_Break class (0 = Other; order matches the
 * generator's GCB_CLASSES list). */
int un_gcb_class(uint32_t cp) {
    ptrdiff_t lo = 0, hi = (ptrdiff_t)(sizeof(un_gcb_lo) / 4);
    while (lo < hi) {
        ptrdiff_t mid = (lo + hi) >> 1;
        if (un_gcb_hi[mid] < cp) lo = mid + 1;
        else if (un_gcb_lo[mid] > cp) hi = mid;
        else return un_gcb_cls[mid];
    }
    return 0;
}

/* Indic_Conjunct_Break: 0=None 1=Consonant 2=Extend 3=Linker (GB9c). */
int un_incb(uint32_t cp) {
    ptrdiff_t lo = 0, hi = (ptrdiff_t)(sizeof(un_incb_lo) / 4);
    while (lo < hi) {
        ptrdiff_t mid = (lo + hi) >> 1;
        if (un_incb_hi[mid] < cp) lo = mid + 1;
        else if (un_incb_lo[mid] > cp) hi = mid;
        else return un_incb_val[mid];
    }
    return 0;
}

int un_extended_pictographic(uint32_t cp) {
    ptrdiff_t lo = 0, hi = (ptrdiff_t)(sizeof(un_extpic_lo) / 4);
    while (lo < hi) {
        ptrdiff_t mid = (lo + hi) >> 1;
        if (un_extpic_hi[mid] < cp) lo = mid + 1;
        else if (un_extpic_lo[mid] > cp) hi = mid;
        else return 1;
    }
    return 0;
}
""",
]

with open(out_path, "w") as f:
    f.write("\n\n".join(parts) + "\n")
print(f"wrote {out_path} ({os.path.getsize(out_path)} bytes)")

# ----------------------------------------------------------- spec vectors
vec_dir = os.path.dirname(os.path.abspath(out_path))
norm_vec_path = os.path.join(os.path.dirname(vec_dir), "spec", "fixtures", "unicode")
os.makedirs(norm_vec_path, exist_ok=True)

sel = []
rng2 = random.Random(7)
interesting = [
    "Å", "Å", "Å", "é", "é", "q̣̇",
    "q̣̇", "ﬁ", "①", "㎒", "가", "퓛",
    "각", "क़", "क़", "ཷ", "ḍ̇",
    "ṩ", "ṩ", "Ǆ", "ﷺ", "½", "⁵",
    "\U0001d160", "\U0001d1c0", "ẍ́y", "̈́", "ΩKÅ",
]
sel.extend(interesting)
for _ in range(280):
    n = rng2.randrange(1, 8)
    sel.append("".join(chr(rng2.choice(pool)) for _ in range(n)))

with open(os.path.join(norm_vec_path, "norm_vectors.tsv"), "w") as f:
    for s in sel:
        row = [" ".join(f"{ord(c):X}" for c in s)]
        for form in forms:
            row.append(" ".join(f"{ord(c):X}" for c in unicodedata.normalize(form, s)))
        f.write("\t".join(row) + "\n")
print(f"wrote {norm_vec_path}/norm_vectors.tsv ({len(sel)} vectors)")

if gb_vectors:
    with open(os.path.join(norm_vec_path, "grapheme_vectors.tsv"), "w") as f:
        for cps, breaks in gb_vectors:
            f.write(" ".join(f"{c:X}" for c in cps) + "\t" + " ".join(map(str, breaks)) + "\n")
    print(f"wrote {norm_vec_path}/grapheme_vectors.tsv ({len(gb_vectors)} vectors)")

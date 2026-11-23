#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __aarch64__
#include <arm_neon.h>
#endif
#define die w_rt_die
#define dief w_rt_dief
#define as_str w_rt_as_str
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#define w_method_dispatch w_rt_method_dispatch
#define w_bytes_ascii_p w_rt_bytes_ascii_p
#define w_string_ascii_p w_rt_string_ascii_p
#define WN_index W_M5("index")
#endif

/* ---- Language-specific codepoint overrides ----
 * Per-(lang, bits) flag tables loaded on first use into a small fixed cache.
 * lex64/lex32: 0x110000 entries (1 byte per codepoint).
 * lex16: 256 entries (ASCII only; non-ASCII is computed at packing time).
 * Each byte holds 8-bit lex_flags. When loaded, these flags REPLACE the
 * default flags in LexChar packing. */

WValue w_runtime_dir(void);

#define LANG_CACHE_SLOTS 8
#define LEX_SENTINEL_PAD 16

typedef struct {
    char     lang[16];
    int      bits;
    uint8_t *flags;
    size_t   flags_size;
} WLangCacheSlot;

static WLangCacheSlot g_lang_cache[LANG_CACHE_SLOTS];
static int g_lang_cache_used = 0;

#include "tungsten_lexflags.inc"

/* A program that embeds the lexer can run where no languages/ directory
 * exists (no checkout, no TUNGSTEN_ROOT): rebuild Tungsten's own tables from
 * the run-length copy in tungsten_lexflags.inc and cache them like a load. */
static const uint8_t *w_embedded_lang_flags(const char *lang, int bits, size_t expected_size) {
    if (strcmp(lang, "tungsten") != 0 || (bits != 64 && bits != 32)) return NULL;
    uint8_t *flags = (uint8_t *)calloc(expected_size, 1);
    if (!flags) return NULL;
    const uint32_t (*runs)[3] = bits == 64 ? w_tungsten_lex64_runs : w_tungsten_lex32_runs;
    size_t n = bits == 64 ? W_TUNGSTEN_LEX64_RUNS_N : W_TUNGSTEN_LEX32_RUNS_N;
    for (size_t i = 0; i < n; i++) {
        size_t start = runs[i][0], len = runs[i][1];
        if (start + len > expected_size) continue;
        memset(flags + start, (int)runs[i][2], len);
    }
    int slot = g_lang_cache_used++;
    strncpy(g_lang_cache[slot].lang, lang, sizeof(g_lang_cache[slot].lang) - 1);
    g_lang_cache[slot].lang[sizeof(g_lang_cache[slot].lang) - 1] = '\0';
    g_lang_cache[slot].bits = bits;
    g_lang_cache[slot].flags = flags;
    g_lang_cache[slot].flags_size = expected_size;
    return flags;
}

/* Look up cached flags or load them from disk. Returns NULL on error
 * (file missing or wrong size); caller falls back to default flags.
 * Aborts if the cache fills up. */
static const uint8_t *w_load_lang_flags(const char *lang, int bits) {
    /* Linear search — N <= 8, faster than hashing. */
    for (int i = 0; i < g_lang_cache_used; i++) {
        if (g_lang_cache[i].bits == bits && strcmp(g_lang_cache[i].lang, lang) == 0) {
            return g_lang_cache[i].flags;
        }
    }
    if (g_lang_cache_used >= LANG_CACHE_SLOTS) {
        dief("lang flag cache full (max %d slots, requested %s lex%d)",
             LANG_CACHE_SLOTS, lang, bits);
    }
    if (strlen(lang) >= sizeof(g_lang_cache[0].lang)) {
        dief("lang name too long: %s", lang);
    }

    size_t expected_size;
    const char *suffix;
    if (bits == 16) {
        expected_size = 256;
        suffix = "lex16";
    } else if (bits == 32) {
        expected_size = 0x110000;
        suffix = "lex32";
    } else {
        expected_size = 0x110000;
        suffix = "lex64";
    }

    char cp_path[4096];
    FILE *f = NULL;
    snprintf(cp_path, sizeof(cp_path), "languages/%s/%s.%s", lang, lang, suffix);
    f = fopen(cp_path, "rb");
    if (!f) {
        const char *root = getenv("TUNGSTEN_ROOT");
        if (root && root[0] != '\0') {
            snprintf(cp_path, sizeof(cp_path), "%s/languages/%s/%s.%s",
                     root, lang, lang, suffix);
            f = fopen(cp_path, "rb");
        }
    }
    if (!f) {
        WValue rtdir = w_runtime_dir();
        snprintf(cp_path, sizeof(cp_path), "%s/../languages/%s/%s.%s",
                 as_str(rtdir), lang, lang, suffix);
        f = fopen(cp_path, "rb");
    }
    /* Backwards compat for bits == 64: try legacy .codepoints suffix. */
    if (!f && bits == 64) {
        snprintf(cp_path, sizeof(cp_path), "languages/%s/%s.codepoints", lang, lang);
        f = fopen(cp_path, "rb");
        if (!f) {
            const char *root = getenv("TUNGSTEN_ROOT");
            if (root && root[0] != '\0') {
                snprintf(cp_path, sizeof(cp_path), "%s/languages/%s/%s.codepoints",
                         root, lang, lang);
                f = fopen(cp_path, "rb");
            }
        }
        if (!f) {
            WValue rtdir = w_runtime_dir();
            snprintf(cp_path, sizeof(cp_path), "%s/../languages/%s/%s.codepoints",
                     as_str(rtdir), lang, lang);
            f = fopen(cp_path, "rb");
        }
    }
    if (!f) return w_embedded_lang_flags(lang, bits, expected_size);

    fseek(f, 0, SEEK_END);
    long actual_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (actual_size < 0 || (size_t)actual_size != expected_size) {
        fprintf(stderr, "warning: %s wrong size %ld (expected %zu), using defaults\n",
                cp_path, actual_size, expected_size);
        fclose(f);
        return NULL;
    }

    uint8_t *flags = (uint8_t *)malloc(expected_size);
    if (!flags) { fclose(f); return NULL; }
    if (fread(flags, 1, expected_size, f) != expected_size) {
        free(flags);
        fclose(f);
        return NULL;
    }
    fclose(f);

    int slot = g_lang_cache_used++;
    strncpy(g_lang_cache[slot].lang, lang, sizeof(g_lang_cache[slot].lang) - 1);
    g_lang_cache[slot].lang[sizeof(g_lang_cache[slot].lang) - 1] = '\0';
    g_lang_cache[slot].bits = bits;
    g_lang_cache[slot].flags = flags;
    g_lang_cache[slot].flags_size = expected_size;
    return flags;
}

/* Build a LexChar using language-specific flags instead of the default cache.
 * The flag byte from the .codepoints file replaces the 7-bit lex_flags field. */
static inline int64_t w_lexchar_lang(uint32_t cp, const uint8_t *lang_flags,
                                     const uint64_t (*lc_blocks)[256], const uint16_t *lc_index) {
    uint64_t cached = w_lexchar_cached_t(cp, lc_blocks, lc_index) | ((uint64_t)cp << 18);
    /* Replace lower 11 bits: zero out digit_value (bits 10-7) + flags (bits 6-0),
     * replace with 8-bit lang flags (C uses bit 7 for IS_NEWLINE). */
    return (int64_t)((cached & ~0x7FFULL) | (lang_flags[cp] & 0xFF));
}

/* Convert source string to LexChars using language-specific flag overrides. */
static WValue w_string_to_lexchars_lang(const char *str, size_t str_len, const uint8_t *lang_flags) {
    const uint64_t (*lc_blocks)[256]; const uint16_t *lc_index;
    if (!w_lexchar_tables(&lc_blocks, &lc_index))
        w_raise(w_string("lexchars: lexer tables not linked (program does not reference .lexchars)"));
    /* Slots contain complete tagged LexChar WValues, not numeric i64s. */
    WValue result = w_array_new(65, str_len + LEX_SENTINEL_PAD);
    WArray *ta = w_as_array(result);
    int64_t *data = (int64_t *)ta->slots;

    const unsigned char *p = (const unsigned char *)str;
    const unsigned char *end = p + str_len;
    size_t idx = 0;

    while (p < end) {
        if (*p < 0x80) {
            while (p < end && *p < 0x80) {
                data[idx++] = w_lexchar_lang(*p, lang_flags, lc_blocks, lc_index);
                p++;
            }
        } else {
            uint32_t cp;
            int clen;
            if (*p < 0xE0) { cp = (*p & 0x1F) << 6; clen = 2; }
            else if (*p < 0xF0) { cp = (*p & 0x0F) << 12; clen = 3; }
            else { cp = (*p & 0x07) << 18; clen = 4; }
            for (int k = 1; k < clen && p + k < end; k++)
                cp |= (p[k] & 0x3F) << (6 * (clen - 1 - k));
            data[idx++] = w_lexchar_lang(cp, lang_flags, lc_blocks, lc_index);
            p += (p + clen <= end) ? clen : (end - p);
        }
    }
    /* Sentinel pad: NEON 8-lane (or future 16-lane) tail loads can read
     * past idx safely. The pad value is the standard LexChar sentinel. */
    int64_t sentinel = (int64_t)(0xFFFC000000000000ULL | (1ULL << 46));
    for (int s = 0; s < LEX_SENTINEL_PAD; s++) data[idx + s] = sentinel;
    ta->size = idx;
    return result;
}

/* Pack a source string into a u32[] LexChar array for the Lex32 fast path.
 *
 * Layout per element:
 *   bits 31..11: codepoint (21 bits, full Unicode range)
 *   bits 10..8 : reserved (zero)
 *   bits  7..0 : language flag byte (same content as the lex64 table)
 *
 * Codepoint extraction in the lexer is `c = (v >> 11) & 0x1FFFFF`, which
 * lowers to a single `ubfx` on aarch64. Sentinel is a zero element — real
 * codepoints have either a non-zero codepoint field or at least one set
 * flag bit, so cp=0 + flags=0 is unambiguous. */
static WValue w_string_to_lex32_lang(const char *str, size_t str_len,
                                     const uint8_t *lex32_flags) {
    WValue result = w_array_new(32, (int64_t)str_len + LEX_SENTINEL_PAD);
    WArray *ta = w_as_array(result);
    uint32_t *data = (uint32_t *)ta->slots;

    const unsigned char *p = (const unsigned char *)str;
    const unsigned char *end = p + str_len;
    size_t idx = 0;

    while (p < end) {
        uint32_t cp;
        int clen;
        if (*p < 0x80) {
            while (p < end && *p < 0x80) {
                cp = *p;
                data[idx++] = (cp << 11) | lex32_flags[cp];
                p++;
            }
            continue;
        } else if (*p < 0xE0) { cp = (*p & 0x1F) << 6; clen = 2; }
        else if (*p < 0xF0) { cp = (*p & 0x0F) << 12; clen = 3; }
        else { cp = (*p & 0x07) << 18; clen = 4; }
        for (int k = 1; k < clen && p + k < end; k++)
            cp |= (p[k] & 0x3F) << (6 * (clen - 1 - k));
        uint8_t fl = (cp < 0x110000) ? lex32_flags[cp] : 0;
        data[idx++] = (cp << 11) | fl;
        p += (p + clen <= end) ? clen : (end - p);
    }
    for (int s = 0; s < LEX_SENTINEL_PAD; s++) data[idx + s] = 0;
    ta->size = idx;
    return result;
}

/* Pack a source string into a u16[] LexChar array for the Lex16 fast path.
 *
 * Layout per element:
 *   bits 15..8 : codepoint high byte (ASCII codepoint or 0x80 placeholder
 *                for non-ASCII)
 *   bits  7..0 : language flag byte
 *
 * For non-ASCII input the codepoint slot stores the placeholder 0x80, and
 * the flag byte comes from the language's lex64 table (or zero if that
 * table isn't loaded). Lex16 dispatch in the lexer is purely flag-based,
 * so the actual codepoint isn't needed for tokenization — it's recovered
 * from the source string via (offset, length) when the parser needs it. */
static WValue w_string_to_lex16_lang(const char *str, size_t str_len,
                                     const uint8_t *lex16_flags,
                                     const uint8_t *lex64_flags) {
    WValue result = w_array_new(16, (int64_t)str_len + LEX_SENTINEL_PAD);
    WArray *ta = w_as_array(result);
    uint16_t *data = (uint16_t *)ta->slots;

    const unsigned char *p = (const unsigned char *)str;
    const unsigned char *end = p + str_len;
    size_t idx = 0;

    while (p < end) {
        uint32_t cp;
        int clen;
        if (*p < 0x80) { cp = *p; clen = 1; }
        else if (*p < 0xE0) { cp = (*p & 0x1F) << 6; clen = 2; }
        else if (*p < 0xF0) { cp = (*p & 0x0F) << 12; clen = 3; }
        else { cp = (*p & 0x07) << 18; clen = 4; }
        for (int k = 1; k < clen && p + k < end; k++)
            cp |= (p[k] & 0x3F) << (6 * (clen - 1 - k));
        uint16_t packed;
        if (cp < 0x80) {
            packed = (uint16_t)((cp << 8) | lex16_flags[cp]);
        } else {
            uint8_t fl = (lex64_flags != NULL && cp < 0x110000) ? lex64_flags[cp] : 0;
            packed = (uint16_t)((0x80U << 8) | fl);
        }
        data[idx++] = packed;
        p += (p + clen <= end) ? clen : (end - p);
    }
    for (int s = 0; s < LEX_SENTINEL_PAD; s++) data[idx + s] = 0;
    ta->size = idx;
    return result;
}

/* ── NEON scan helpers for Lex16 / Lex32 ──────────────────────────────
 *
 * These are the inner-loop accelerators for the lexer fast path. They
 * advance `pos` past a run of LexChars whose flag byte matches `mask`
 * (scan_flag) and return the first position where the predicate fails.
 *
 * Calling convention from Tungsten (post-Shape-B hoist):
 *   data_ptr = ccall_nobox("w_array_data_ptr", lc)
 *   ...
 *   pos = ccall_nobox("w_lex16_scan_flag", data_ptr, length, pos, 0x20)
 *
 * The helpers take a RAW data pointer (the typed-array's `data` field
 * already extracted) plus the array length, instead of re-unboxing the
 * WValue typed-array on every call. Hoisting the ~10-cycle WArray
 * unbox dance out of the inner loop is the largest single win for the
 * helper hot path. See TODO.md "Shape A" for the longer-term goal of
 * lowering this hoist to an inline `var$data` view-field load with no
 * runtime call at all.
 *
 * Tail safety: the lex16 and lex32 packers append LEX_SENTINEL_PAD = 16
 * trailing zero entries, so an 8-lane NEON load past the live region is
 * always inside the allocation.
 *
 * x86 fallback: the helpers are gated on __aarch64__; on x86 they fall
 * back to a scalar loop with the same return semantics. */

/* Hoist helper: extract the raw data pointer from a typed-array WValue.
 * Called once per lexer entry; the result is passed to every scan helper
 * for the duration of tokenization. Skips the per-call WArray unbox
 * that the helpers used to do internally. */
int64_t w_array_data_ptr(int64_t arr_wval) {
    WArray *a = w_as_array((WValue)arr_wval);
    return (int64_t)(uintptr_t)a->slots;
}

int64_t w_typed_array_data_ptr(int64_t arr_wval) {
    return w_array_data_ptr(arr_wval);
}

/* Start-adjusted u8[] storage boundary for source-level byte codecs. Unlike
 * w_typed_array_data_ptr, this returns the first LIVE byte of a shifted/view
 * array. Callers hoist it once, then use raw_load_u8/raw_store_u8 intrinsics in
 * their native loop. */
int64_t w_u8_live_data_ptr(int64_t arr_wval) {
    WValue value = (WValue)arr_wval;
    if (!w_is_bytes(value))
        w_raise(w_string("u8 data pointer: expected u8[]"));
    WArray *a = w_as_array(value);
    /* A zero-length borrowed view may legally carry NULL storage. Return it
     * unchanged; source loops are size-guarded and never dereference it. */
    if (a->size == 0)
        return (int64_t)(uintptr_t)a->slots;
    return (int64_t)(uintptr_t)((uint8_t *)a->slots + a->start);
}

/* Tree-walker mirrors for the compiler's raw byte load/store intrinsics. Native
 * compiled codec loops do not call these functions; eval mode does. */
int64_t w_raw_load_u8(int64_t ptr, int64_t index) {
    return ((const uint8_t *)(uintptr_t)ptr)[index];
}

int64_t w_raw_store_u8(int64_t ptr, int64_t index, int64_t value) {
    ((uint8_t *)(uintptr_t)ptr)[index] = (uint8_t)value;
    return (uint8_t)value;
}

#ifdef __aarch64__
#include <arm_neon.h>

int64_t w_lex16_scan_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t mask = (uint16_t)flag_mask_i64;

    int16x8_t v_mask = vdupq_n_s16((int16_t)mask);
    int16x8_t zero = vdupq_n_s16(0);

    /* Unbounded — sentinel pad terminates via the data path. */
    for (;;) {
        int16x8_t v = vld1q_s16((const int16_t *)(lc + pos));
        int16x8_t and_result = vandq_s16(v, v_mask);
        int16x8_t cmp = vceqq_s16(and_result, zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s16(cmp), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s16(cmp), 1);
        if (lo | hi) {
            for (int i = 0; i < 8; i++) {
                if ((lc[pos + i] & mask) == 0) return pos + i;
            }
        }
        pos += 8;
    }
}

int64_t w_lex32_scan_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t mask = (uint32_t)flag_mask_i64;

    int32x4_t v_mask = vdupq_n_s32((int32_t)mask);
    int32x4_t zero = vdupq_n_s32(0);

    for (;;) {
        int32x4_t v = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t and_result = vandq_s32(v, v_mask);
        int32x4_t cmp = vceqq_s32(and_result, zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s32(cmp), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s32(cmp), 1);
        if (lo | hi) {
            for (int i = 0; i < 4; i++) {
                if ((lc[pos + i] & mask) == 0) return pos + i;
            }
        }
        pos += 4;
    }
}

/* w_lex32_scan_flag_pure is now identical to w_lex32_scan_flag (both
 * unbounded). Kept as a separate symbol so the lexer call sites that
 * historically used _pure don't need updating. */
int64_t w_lex32_scan_flag_pure(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    return w_lex32_scan_flag(data_ptr, length, pos, flag_mask_i64);
}

/* (#59) u8 SIMD: count occurrences of `needle` in a byte
 * array. 16 lanes per NEON cycle. Each chunk: vceqq_u8 → vshrq_n_u8(7)
 * collapses 0xFF to 1 and 0x00 to 0; vaddvq_u8 sums to a per-chunk
 * match count, accumulated across chunks. Total match count fits in
 * int64_t for any sensibly-sized array. */
int64_t w_byte_scan_count(const uint8_t *data, int64_t size, uint8_t needle) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 16) {
        uint8x16_t v_needle = vdupq_n_u8(needle);
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = vceqq_u8(v, v_needle);
            /* Per-lane 0xFF → 1, 0x00 → 0; horizontal-sum gives match count. */
            uint8x16_t ones = vshrq_n_u8(cmp, 7);
            total += (int64_t)vaddvq_u8(ones);
            i += 16;
        }
    }
    while (i < size) {
        if (data[i] == needle) total++;
        i++;
    }
    return total;
}

/* (#59) u8 SIMD: scan a byte array for the first occurrence
 * of `needle`. 16 lanes per NEON cycle. Returns the byte index, or -1
 * on miss. Bounded — caller passes the live `size`; no sentinel needed
 * because we tail-loop the unaligned remainder.
 *
 * Used by Array#index dispatch when arr->ebits == 8 and the search arg
 * is an integer fitting in a byte. Replaces a per-element w_eq scalar
 * loop in w_method_dispatch's WN_index branch. */
int64_t w_byte_scan_eq(const uint8_t *data, int64_t size, uint8_t needle) {
    int64_t i = 0;
    if (size >= 16) {
        uint8x16_t v_needle = vdupq_n_u8(needle);
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = vceqq_u8(v, v_needle);
            /* Any-lane test: max across all 16 bytes. 0 means no match. */
            if (vmaxvq_u8(cmp) != 0) {
                /* Locate the matching lane. Build a 64-bit narrowed mask
                 * (4 bits per lane via vshrn_n) and find first set. */
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(cmp), 4)),
                    0);
                int lane = __builtin_ctzll(m) >> 2;
                return i + lane;
            }
            i += 16;
        }
    }
    /* Tail */
    while (i < size) {
        if (data[i] == needle) return i;
        i++;
    }
    return -1;
}

static inline uint8x16_t w_byte_match_any4_u8x16(uint8x16_t v, int64_t a, int64_t b, int64_t c, int64_t d) {
    uint8x16_t ma = vceqq_u8(v, vdupq_n_u8((uint8_t)a));
    uint8x16_t mb = vceqq_u8(v, vdupq_n_u8((uint8_t)b));
    uint8x16_t mc = vceqq_u8(v, vdupq_n_u8((uint8_t)c));
    uint8x16_t md = vceqq_u8(v, vdupq_n_u8((uint8_t)d));
    return vorrq_u8(vorrq_u8(ma, mb), vorrq_u8(mc, md));
}

static inline uint8x16_t w_byte_match_any8_u8x16(uint8x16_t v, int64_t a, int64_t b, int64_t c, int64_t d,
                                                 int64_t e, int64_t f, int64_t g, int64_t h) {
    uint8x16_t lo = w_byte_match_any4_u8x16(v, a, b, c, d);
    uint8x16_t hi = w_byte_match_any4_u8x16(v, e, f, g, h);
    return vorrq_u8(lo, hi);
}

int64_t w_byte_scan_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t i = 0;
    if (size >= 16) {
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = w_byte_match_any4_u8x16(v, a, b, c, d);
            if (vmaxvq_u8(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(cmp), 4)),
                    0);
                int lane = __builtin_ctzll(m) >> 2;
                return i + lane;
            }
            i += 16;
        }
    }
    while (i < size) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d) return i;
        i++;
    }
    return -1;
}

int64_t w_byte_scan_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                         int64_t e, int64_t f, int64_t g, int64_t h) {
    int64_t i = 0;
    if (size >= 16) {
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = w_byte_match_any8_u8x16(v, a, b, c, d, e, f, g, h);
            if (vmaxvq_u8(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(cmp), 4)),
                    0);
                int lane = __builtin_ctzll(m) >> 2;
                return i + lane;
            }
            i += 16;
        }
    }
    while (i < size) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d ||
            x == (uint8_t)e || x == (uint8_t)f || x == (uint8_t)g || x == (uint8_t)h) return i;
        i++;
    }
    return -1;
}

int64_t w_byte_scan_count_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 16) {
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = w_byte_match_any4_u8x16(v, a, b, c, d);
            total += (int64_t)vaddvq_u8(vshrq_n_u8(cmp, 7));
            i += 16;
        }
    }
    while (i < size) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d) total++;
        i++;
    }
    return total;
}

int64_t w_byte_scan_count_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                               int64_t e, int64_t f, int64_t g, int64_t h) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 16) {
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t cmp = w_byte_match_any8_u8x16(v, a, b, c, d, e, f, g, h);
            total += (int64_t)vaddvq_u8(vshrq_n_u8(cmp, 7));
            i += 16;
        }
    }
    while (i < size) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d ||
            x == (uint8_t)e || x == (uint8_t)f || x == (uint8_t)g || x == (uint8_t)h) total++;
        i++;
    }
    return total;
}

/* (#59) u8 SIMD: scan a byte array from the END for the last
 * occurrence of `needle`. 16 lanes per NEON cycle, marching backwards
 * one chunk at a time. Returns the byte index, or -1 on miss.
 *
 * Locating the LAST match in a 16-byte chunk: build the same narrowed
 * 64-bit mask as scan_eq, then use 63 - clz to find the highest set
 * 4-bit group (mask is little-endian within u64, so highest set bit is
 * highest matching lane). */
int64_t w_byte_scan_eq_rev(const uint8_t *data, int64_t size, uint8_t needle) {
    int64_t i = size;
    if (size >= 16) {
        uint8x16_t v_needle = vdupq_n_u8(needle);
        while (i >= 16) {
            const uint8_t *p = data + (i - 16);
            uint8x16_t v = vld1q_u8(p);
            uint8x16_t cmp = vceqq_u8(v, v_needle);
            if (vmaxvq_u8(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(cmp), 4)),
                    0);
                int lane = (63 - __builtin_clzll(m)) >> 2;
                return (i - 16) + lane;
            }
            i -= 16;
        }
    }
    /* Tail: walk the remaining [0, i) bytes from the end. */
    while (i > 0) {
        i--;
        if (data[i] == needle) return i;
    }
    return -1;
}

/* (#59) u8 SIMD: in-place byte replacement. For each chunk,
 * build a mask of `old` matches via vceqq_u8 and use vbslq_u8 to select
 * between `new` (where mask is set) and the original byte (where not).
 * Returns the count of replaced bytes — useful for callers that want
 * to know how many substitutions happened. */
int64_t w_byte_replace(uint8_t *data, int64_t size, uint8_t old_b, uint8_t new_b) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 16) {
        uint8x16_t v_old = vdupq_n_u8(old_b);
        uint8x16_t v_new = vdupq_n_u8(new_b);
        int64_t end16 = size - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t mask = vceqq_u8(v, v_old);
            uint8x16_t out = vbslq_u8(mask, v_new, v);
            vst1q_u8(data + i, out);
            uint8x16_t ones = vshrq_n_u8(mask, 7);
            total += (int64_t)vaddvq_u8(ones);
            i += 16;
        }
    }
    while (i < size) {
        if (data[i] == old_b) {
            data[i] = new_b;
            total++;
        }
        i++;
    }
    return total;
}

/* (#59) u16 SIMD scans. 8 lanes per 128-bit NEON cycle. The
 * bit-pattern equality compare doesn't care whether the array is u16
 * or i16 — the same vceqq_u16 produces the right answer for either
 * interpretation (twos-complement bits match across the sign). The
 * caller already validated that `needle` fits in 16 bits.
 *
 * Lane locate: vshrn_n_u16(cmp, 8) collapses each 0xFFFF lane to 0xFF
 * in u8, giving an 8-byte mask in a u8x8. ctzll>>3 finds the lowest
 * matching lane (one byte per lane). */
int64_t w_u16_scan_eq(const uint16_t *data, int64_t size, uint16_t needle) {
    int64_t i = 0;
    if (size >= 8) {
        uint16x8_t v_needle = vdupq_n_u16(needle);
        int64_t end8 = size - 8;
        while (i <= end8) {
            uint16x8_t v = vld1q_u16(data + i);
            uint16x8_t cmp = vceqq_u16(v, v_needle);
            if (vmaxvq_u16(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(cmp, 8)),
                    0);
                int lane = __builtin_ctzll(m) >> 3;
                return i + lane;
            }
            i += 8;
        }
    }
    while (i < size) {
        if (data[i] == needle) return i;
        i++;
    }
    return -1;
}

int64_t w_u16_scan_count(const uint16_t *data, int64_t size, uint16_t needle) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 8) {
        uint16x8_t v_needle = vdupq_n_u16(needle);
        int64_t end8 = size - 8;
        while (i <= end8) {
            uint16x8_t v = vld1q_u16(data + i);
            uint16x8_t cmp = vceqq_u16(v, v_needle);
            /* Per-lane 0xFFFF → 1 via vshrq_n_u16(.., 15). */
            uint16x8_t ones = vshrq_n_u16(cmp, 15);
            total += (int64_t)vaddvq_u16(ones);
            i += 8;
        }
    }
    while (i < size) {
        if (data[i] == needle) total++;
        i++;
    }
    return total;
}

/* (#59) i32/u32 SIMD scans. 4 lanes per 128-bit NEON cycle.
 * Bit-pattern equality — same kernel covers both signed and unsigned
 * 32-bit interpretations.
 *
 * Lane locate: 4 lanes × u32 = 4 × 32 bits. vshrn_n_u32(cmp, 16)
 * narrows to 4 × u16 (16 bits per lane); vget_lane_u64 then ctzll>>4
 * finds the lowest matching lane. */
int64_t w_u32_scan_eq(const uint32_t *data, int64_t size, uint32_t needle) {
    int64_t i = 0;
    if (size >= 4) {
        uint32x4_t v_needle = vdupq_n_u32(needle);
        int64_t end4 = size - 4;
        while (i <= end4) {
            uint32x4_t v = vld1q_u32(data + i);
            uint32x4_t cmp = vceqq_u32(v, v_needle);
            if (vmaxvq_u32(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u16(vshrn_n_u32(cmp, 16)),
                    0);
                int lane = __builtin_ctzll(m) >> 4;
                return i + lane;
            }
            i += 4;
        }
    }
    while (i < size) {
        if (data[i] == needle) return i;
        i++;
    }
    return -1;
}

int64_t w_u32_scan_count(const uint32_t *data, int64_t size, uint32_t needle) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 4) {
        uint32x4_t v_needle = vdupq_n_u32(needle);
        int64_t end4 = size - 4;
        while (i <= end4) {
            uint32x4_t v = vld1q_u32(data + i);
            uint32x4_t cmp = vceqq_u32(v, v_needle);
            /* Per-lane 0xFFFFFFFF → 1 via vshrq_n_u32(.., 31). */
            uint32x4_t ones = vshrq_n_u32(cmp, 31);
            total += (int64_t)vaddvq_u32(ones);
            i += 4;
        }
    }
    while (i < size) {
        if (data[i] == needle) total++;
        i++;
    }
    return total;
}

/* Reverse scan: u16. Mirrors w_byte_scan_eq_rev — march backwards 8
 * lanes at a time, locate the highest matching lane in each chunk via
 * 63 - clz on the narrowed mask. */
int64_t w_u16_scan_eq_rev(const uint16_t *data, int64_t size, uint16_t needle) {
    int64_t i = size;
    if (size >= 8) {
        uint16x8_t v_needle = vdupq_n_u16(needle);
        while (i >= 8) {
            const uint16_t *p = data + (i - 8);
            uint16x8_t v = vld1q_u16(p);
            uint16x8_t cmp = vceqq_u16(v, v_needle);
            if (vmaxvq_u16(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u8(vshrn_n_u16(cmp, 8)),
                    0);
                int lane = (63 - __builtin_clzll(m)) >> 3;
                return (i - 8) + lane;
            }
            i -= 8;
        }
    }
    while (i > 0) {
        i--;
        if (data[i] == needle) return i;
    }
    return -1;
}

/* Reverse scan: u32. 4 lanes per chunk; narrow to u16 (2 bytes per lane)
 * and use 63 - clz with >> 4 to extract the lane index. */
int64_t w_u32_scan_eq_rev(const uint32_t *data, int64_t size, uint32_t needle) {
    int64_t i = size;
    if (size >= 4) {
        uint32x4_t v_needle = vdupq_n_u32(needle);
        while (i >= 4) {
            const uint32_t *p = data + (i - 4);
            uint32x4_t v = vld1q_u32(p);
            uint32x4_t cmp = vceqq_u32(v, v_needle);
            if (vmaxvq_u32(cmp) != 0) {
                uint64_t m = vget_lane_u64(
                    vreinterpret_u64_u16(vshrn_n_u32(cmp, 16)),
                    0);
                int lane = (63 - __builtin_clzll(m)) >> 4;
                return (i - 4) + lane;
            }
            i -= 4;
        }
    }
    while (i > 0) {
        i--;
        if (data[i] == needle) return i;
    }
    return -1;
}

/* (#59) u1 (bitpacked) SIMD scans. Each byte holds 8 bit-lanes.
 * NEON `vcntq_u8` produces a per-byte popcount; horizontal-sum via
 * `vaddvq_u8` gives total set bits per 16-byte chunk (= 128 bits = 128
 * lanes per cycle).
 *
 * The caller passes the bit-count `bit_size` (not byte-count). Trailing
 * partial byte (when bit_size % 8 != 0) is masked to ignore unused
 * high bits — crucial for `count`/`index` correctness near the end.
 *
 * Caller guarantees byte-aligned start (`arr->start % 8 == 0`); if not,
 * dispatch routes to a scalar fallback (rare in practice — bit-array
 * shifts that misalign start aren't common). */

int64_t w_u1_count_set(const uint8_t *data, int64_t bit_size) {
    int64_t total = 0;
    int64_t whole_bytes = bit_size >> 3;
    int64_t i = 0;
    if (whole_bytes >= 16) {
        int64_t end16 = whole_bytes - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            uint8x16_t pop = vcntq_u8(v);
            total += (int64_t)vaddvq_u8(pop);
            i += 16;
        }
    }
    while (i < whole_bytes) {
        total += __builtin_popcount(data[i]);
        i++;
    }
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        total += __builtin_popcount(data[whole_bytes] & mask);
    }
    return total;
}

int64_t w_u1_index_set(const uint8_t *data, int64_t bit_size) {
    int64_t whole_bytes = bit_size >> 3;
    int64_t i = 0;
    if (whole_bytes >= 16) {
        int64_t end16 = whole_bytes - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            if (vmaxvq_u8(v) != 0) {
                /* At least one byte in chunk has a set bit — scalar locate. */
                for (int j = 0; j < 16; j++) {
                    uint8_t b = data[i + j];
                    if (b != 0) return (i + j) * 8 + __builtin_ctz(b);
                }
            }
            i += 16;
        }
    }
    while (i < whole_bytes) {
        if (data[i] != 0) return i * 8 + __builtin_ctz(data[i]);
        i++;
    }
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        uint8_t b = data[whole_bytes] & mask;
        if (b != 0) return whole_bytes * 8 + __builtin_ctz(b);
    }
    return -1;
}

int64_t w_u1_index_unset(const uint8_t *data, int64_t bit_size) {
    int64_t whole_bytes = bit_size >> 3;
    int64_t i = 0;
    if (whole_bytes >= 16) {
        int64_t end16 = whole_bytes - 16;
        while (i <= end16) {
            uint8x16_t v = vld1q_u8(data + i);
            /* Any byte != 0xFF means some bit is unset. vminvq_u8 gives
             * the lowest byte across the chunk. */
            if (vminvq_u8(v) != 0xFF) {
                for (int j = 0; j < 16; j++) {
                    uint8_t b = data[i + j];
                    if (b != 0xFF) return (i + j) * 8 + __builtin_ctz((uint8_t)~b);
                }
            }
            i += 16;
        }
    }
    while (i < whole_bytes) {
        if (data[i] != 0xFF) return i * 8 + __builtin_ctz((uint8_t)~data[i]);
        i++;
    }
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        uint8_t unset_in_tail = (uint8_t)(~data[whole_bytes]) & mask;
        if (unset_in_tail != 0) return whole_bytes * 8 + __builtin_ctz(unset_in_tail);
    }
    return -1;
}

/* (#59) i64/u64 SIMD scans. 2 lanes per 128-bit NEON cycle.
 * Bit-pattern equality — works for any 64-bit storage where the needle
 * has a unique bit pattern. Used for ebits=65 polymorphic arrays when
 * the needle is a NaN-boxed immediate (int, bool, nil) — those have
 * unique bit patterns so vceqq_u64 matches w_eq semantics for that
 * subset. Pointer-tagged values (strings, hashes, instances) require
 * deep equality and aren't safe for bit-pattern compare; the dispatch
 * guard checks the needle type. */
int64_t w_u64_scan_eq(const uint64_t *data, int64_t size, uint64_t needle) {
    int64_t i = 0;
    if (size >= 2) {
        uint64x2_t v_needle = vdupq_n_u64(needle);
        int64_t end2 = size - 2;
        while (i <= end2) {
            uint64x2_t v = vld1q_u64(data + i);
            uint64x2_t cmp = vceqq_u64(v, v_needle);
            uint64_t lo = vgetq_lane_u64(cmp, 0);
            uint64_t hi = vgetq_lane_u64(cmp, 1);
            if (lo) return i;
            if (hi) return i + 1;
            i += 2;
        }
    }
    while (i < size) {
        if (data[i] == needle) return i;
        i++;
    }
    return -1;
}

int64_t w_u64_scan_count(const uint64_t *data, int64_t size, uint64_t needle) {
    int64_t i = 0;
    int64_t total = 0;
    if (size >= 2) {
        uint64x2_t v_needle = vdupq_n_u64(needle);
        int64_t end2 = size - 2;
        while (i <= end2) {
            uint64x2_t v = vld1q_u64(data + i);
            uint64x2_t cmp = vceqq_u64(v, v_needle);
            /* Each lane: all-1s on match. Right-shift by 63 gives 1/0. */
            uint64x2_t ones = vshrq_n_u64(cmp, 63);
            total += (int64_t)(vgetq_lane_u64(ones, 0) + vgetq_lane_u64(ones, 1));
            i += 2;
        }
    }
    while (i < size) {
        if (data[i] == needle) total++;
        i++;
    }
    return total;
}

int64_t w_u64_scan_eq_rev(const uint64_t *data, int64_t size, uint64_t needle) {
    int64_t i = size;
    if (size >= 2) {
        uint64x2_t v_needle = vdupq_n_u64(needle);
        while (i >= 2) {
            uint64x2_t v = vld1q_u64(data + (i - 2));
            uint64x2_t cmp = vceqq_u64(v, v_needle);
            uint64_t lo = vgetq_lane_u64(cmp, 0);
            uint64_t hi = vgetq_lane_u64(cmp, 1);
            /* Highest match in chunk: hi lane wins over lo. */
            if (hi) return (i - 2) + 1;
            if (lo) return (i - 2);
            i -= 2;
        }
    }
    while (i > 0) {
        i--;
        if (data[i] == needle) return i;
    }
    return -1;
}

/* (#59) threaded byte-scan: split the array across N pthreads,
 * each running the serial scan kernel on its chunk. Used for very large
 * arrays where the serial scan time exceeds pthread spawn overhead.
 *
 * THREAD_MIN_SIZE is conservative: pthread_create on macOS is ~10-50us
 * per call after warmup; with 8 threads that's ~80-400us setup. At
 * ~40 GB/s serial scan, breakeven is ~3-16 MB. We pick 1 MB as the
 * threshold — small enough to catch most "large array" calls, large
 * enough that the parallelism win clearly beats the spawn cost.
 *
 * N_THREADS = 8 matches the P-core count on M-series; E-cores get used
 * by the OS scheduler when P-cores are full but we don't explicitly
 * target them (E-cores have ~1/2 the SIMD throughput of P-cores). */

#define W_BYTE_SCAN_THREAD_MIN_SIZE (1024 * 1024)
#define W_BYTE_SCAN_N_THREADS       8

typedef struct {
    const uint8_t *data;
    int64_t size;
    uint8_t needle;
    int64_t result;
} w_byte_scan_worker_args;

static void *w_byte_scan_count_worker(void *p) {
    w_byte_scan_worker_args *a = (w_byte_scan_worker_args *)p;
    a->result = w_byte_scan_count(a->data, a->size, a->needle);
    return NULL;
}

int64_t w_byte_scan_count_threaded(const uint8_t *data, int64_t size, uint8_t needle) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE) {
        return w_byte_scan_count(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_byte_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = 0;
        pthread_create(&threads[i], NULL, w_byte_scan_count_worker, &args[i]);
    }
    int64_t total = 0;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total += args[i].result;
    }
    return total;
}

static void *w_byte_scan_eq_worker(void *p) {
    w_byte_scan_worker_args *a = (w_byte_scan_worker_args *)p;
    a->result = w_byte_scan_eq(a->data, a->size, a->needle);
    return NULL;
}

/* Threaded find-first: each worker scans its chunk and writes the
 * lowest-in-chunk match (or -1). Combine: walk workers in chunk order,
 * return the first non-negative result, adjusted for chunk offset. This
 * preserves left-to-right semantics without atomic shared state. */
int64_t w_byte_scan_eq_threaded(const uint8_t *data, int64_t size, uint8_t needle) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE) {
        return w_byte_scan_eq(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_byte_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = -1;
        pthread_create(&threads[i], NULL, w_byte_scan_eq_worker, &args[i]);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    /* Combine in chunk order — first hit wins. */
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        if (args[i].result >= 0) {
            return i * chunk + args[i].result;
        }
    }
    return -1;
}

typedef struct {
    const uint8_t *data;
    int64_t size;
    int64_t needles[8];
    int64_t needle_count;
    int64_t result;
} w_byte_scan_any_worker_args;

static void *w_byte_scan_any_worker(void *p) {
    w_byte_scan_any_worker_args *a = (w_byte_scan_any_worker_args *)p;
    if (a->needle_count == 4) {
        a->result = w_byte_scan_any4(a->data, a->size, a->needles[0], a->needles[1], a->needles[2], a->needles[3]);
    } else {
        a->result = w_byte_scan_any8(a->data, a->size, a->needles[0], a->needles[1], a->needles[2], a->needles[3],
                                     a->needles[4], a->needles[5], a->needles[6], a->needles[7]);
    }
    return NULL;
}

static void *w_byte_scan_count_any_worker(void *p) {
    w_byte_scan_any_worker_args *a = (w_byte_scan_any_worker_args *)p;
    if (a->needle_count == 4) {
        a->result = w_byte_scan_count_any4(a->data, a->size, a->needles[0], a->needles[1], a->needles[2], a->needles[3]);
    } else {
        a->result = w_byte_scan_count_any8(a->data, a->size, a->needles[0], a->needles[1], a->needles[2], a->needles[3],
                                           a->needles[4], a->needles[5], a->needles[6], a->needles[7]);
    }
    return NULL;
}

static void w_byte_scan_any_worker_init(w_byte_scan_any_worker_args *a, const uint8_t *data, int64_t size,
                                        int64_t needle_count, const int64_t *needles, int64_t result_init) {
    a->data = data;
    a->size = size;
    a->needle_count = needle_count;
    a->result = result_init;
    for (int i = 0; i < 8; i++) a->needles[i] = needles[i];
}

static int64_t w_byte_scan_any_threaded_impl(const uint8_t *data, int64_t size, int64_t needle_count,
                                             const int64_t *needles) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE) {
        if (needle_count == 4)
            return w_byte_scan_any4(data, size, needles[0], needles[1], needles[2], needles[3]);
        return w_byte_scan_any8(data, size, needles[0], needles[1], needles[2], needles[3],
                                needles[4], needles[5], needles[6], needles[7]);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_byte_scan_any_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        int64_t chunk_size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        w_byte_scan_any_worker_init(&args[i], data + i * chunk, chunk_size, needle_count, needles, -1);
        pthread_create(&threads[i], NULL, w_byte_scan_any_worker, &args[i]);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) pthread_join(threads[i], NULL);
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        if (args[i].result >= 0) return i * chunk + args[i].result;
    }
    return -1;
}

static int64_t w_byte_scan_count_any_threaded_impl(const uint8_t *data, int64_t size, int64_t needle_count,
                                                   const int64_t *needles) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE) {
        if (needle_count == 4)
            return w_byte_scan_count_any4(data, size, needles[0], needles[1], needles[2], needles[3]);
        return w_byte_scan_count_any8(data, size, needles[0], needles[1], needles[2], needles[3],
                                      needles[4], needles[5], needles[6], needles[7]);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_byte_scan_any_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        int64_t chunk_size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        w_byte_scan_any_worker_init(&args[i], data + i * chunk, chunk_size, needle_count, needles, 0);
        pthread_create(&threads[i], NULL, w_byte_scan_count_any_worker, &args[i]);
    }
    int64_t total = 0;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total += args[i].result;
    }
    return total;
}

int64_t w_byte_scan_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t needles[8] = {a, b, c, d, 0, 0, 0, 0};
    return w_byte_scan_any_threaded_impl(data, size, 4, needles);
}

int64_t w_byte_scan_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                  int64_t e, int64_t f, int64_t g, int64_t h) {
    int64_t needles[8] = {a, b, c, d, e, f, g, h};
    return w_byte_scan_any_threaded_impl(data, size, 8, needles);
}

int64_t w_byte_scan_count_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t needles[8] = {a, b, c, d, 0, 0, 0, 0};
    return w_byte_scan_count_any_threaded_impl(data, size, 4, needles);
}

int64_t w_byte_scan_count_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                        int64_t e, int64_t f, int64_t g, int64_t h) {
    int64_t needles[8] = {a, b, c, d, e, f, g, h};
    return w_byte_scan_count_any_threaded_impl(data, size, 8, needles);
}

/* Threaded u16 / u32 scans — same shape as the byte variants, with
 * width-typed worker args and the matching serial kernel. */
typedef struct {
    const uint16_t *data;
    int64_t size;
    uint16_t needle;
    int64_t result;
} w_u16_scan_worker_args;

static void *w_u16_scan_count_worker(void *p) {
    w_u16_scan_worker_args *a = (w_u16_scan_worker_args *)p;
    a->result = w_u16_scan_count(a->data, a->size, a->needle);
    return NULL;
}
static void *w_u16_scan_eq_worker(void *p) {
    w_u16_scan_worker_args *a = (w_u16_scan_worker_args *)p;
    a->result = w_u16_scan_eq(a->data, a->size, a->needle);
    return NULL;
}

int64_t w_u16_scan_count_threaded(const uint16_t *data, int64_t size, uint16_t needle) {
    /* Threshold counts elements, not bytes — same wall-time threshold
     * (~512 K elements × 2 bytes/elt = 1 MB) as the byte variant. */
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE / 2) {
        return w_u16_scan_count(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_u16_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = 0;
        pthread_create(&threads[i], NULL, w_u16_scan_count_worker, &args[i]);
    }
    int64_t total = 0;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total += args[i].result;
    }
    return total;
}

int64_t w_u16_scan_eq_threaded(const uint16_t *data, int64_t size, uint16_t needle) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE / 2) {
        return w_u16_scan_eq(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_u16_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = -1;
        pthread_create(&threads[i], NULL, w_u16_scan_eq_worker, &args[i]);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        if (args[i].result >= 0) {
            return i * chunk + args[i].result;
        }
    }
    return -1;
}

typedef struct {
    const uint32_t *data;
    int64_t size;
    uint32_t needle;
    int64_t result;
} w_u32_scan_worker_args;

static void *w_u32_scan_count_worker(void *p) {
    w_u32_scan_worker_args *a = (w_u32_scan_worker_args *)p;
    a->result = w_u32_scan_count(a->data, a->size, a->needle);
    return NULL;
}
static void *w_u32_scan_eq_worker(void *p) {
    w_u32_scan_worker_args *a = (w_u32_scan_worker_args *)p;
    a->result = w_u32_scan_eq(a->data, a->size, a->needle);
    return NULL;
}

int64_t w_u32_scan_count_threaded(const uint32_t *data, int64_t size, uint32_t needle) {
    /* 256K elements × 4 bytes = 1 MB threshold. */
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE / 4) {
        return w_u32_scan_count(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_u32_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = 0;
        pthread_create(&threads[i], NULL, w_u32_scan_count_worker, &args[i]);
    }
    int64_t total = 0;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total += args[i].result;
    }
    return total;
}

int64_t w_u32_scan_eq_threaded(const uint32_t *data, int64_t size, uint32_t needle) {
    if (size < W_BYTE_SCAN_THREAD_MIN_SIZE / 4) {
        return w_u32_scan_eq(data, size, needle);
    }
    pthread_t threads[W_BYTE_SCAN_N_THREADS];
    w_u32_scan_worker_args args[W_BYTE_SCAN_N_THREADS];
    int64_t chunk = size / W_BYTE_SCAN_N_THREADS;
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        args[i].data = data + i * chunk;
        args[i].size = (i == W_BYTE_SCAN_N_THREADS - 1) ? size - i * chunk : chunk;
        args[i].needle = needle;
        args[i].result = -1;
        pthread_create(&threads[i], NULL, w_u32_scan_eq_worker, &args[i]);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    for (int i = 0; i < W_BYTE_SCAN_N_THREADS; i++) {
        if (args[i].result >= 0) {
            return i * chunk + args[i].result;
        }
    }
    return -1;
}

/* scan_until_flag: opposite predicate of scan_flag. Advances past
 * LexChars whose (flag-byte AND mask) is ZERO and whose value is
 * non-zero (sentinel terminates). Returns the first position where
 * EITHER any mask bit is set OR the slot is the sentinel.
 *
 * Used for line-comment scans (mask = IS_NEWLINE = 0x80) where the
 * loop is "advance until newline or end-of-source". Block comments
 * and string literals would need a `scan_to_codepoint` shape instead
 * because they terminate on a specific char, not a flag class. */

int64_t w_lex16_scan_until_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t mask = (uint16_t)flag_mask_i64;

    int16x8_t v_mask = vdupq_n_s16((int16_t)mask);
    int16x8_t zero = vdupq_n_s16(0);

    for (;;) {
        int16x8_t v = vld1q_s16((const int16_t *)(lc + pos));
        int16x8_t and_result = vandq_s16(v, v_mask);
        int16x8_t flag_set = vmvnq_s16(vceqq_s16(and_result, zero));
        int16x8_t is_zero = vceqq_s16(v, zero);
        int16x8_t stop = vorrq_s16(flag_set, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 8; i++) {
                uint16_t w = lc[pos + i];
                if (w == 0 || (w & mask) != 0) return pos + i;
            }
        }
        pos += 8;
    }
}

int64_t w_lex32_scan_until_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t mask = (uint32_t)flag_mask_i64;

    int32x4_t v_mask = vdupq_n_s32((int32_t)mask);
    int32x4_t zero = vdupq_n_s32(0);

    for (;;) {
        int32x4_t v = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t and_result = vandq_s32(v, v_mask);
        int32x4_t flag_set = vmvnq_s32(vceqq_s32(and_result, zero));
        int32x4_t is_zero = vceqq_s32(v, zero);
        int32x4_t stop = vorrq_s32(flag_set, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 4; i++) {
                uint32_t w = lc[pos + i];
                if (w == 0 || (w & mask) != 0) return pos + i;
            }
        }
        pos += 4;
    }
}

/* scan_to_cp: find the first LexChar whose codepoint equals a target,
 * or the sentinel. Used for block-comment scans: advance until the
 * next 0x2A (asterisk), then the lexer checks if the following char
 * is 0x2F (slash) to confirm the block-comment terminator.
 *
 * Lex16 stores the codepoint in the high byte (or 0x80 placeholder for
 * non-ASCII), so the comparison masks bits 8-15. Lex32 stores the full
 * 21-bit codepoint at bits 11-31, so the mask is the top 21 bits. The
 * mask isolates the codepoint from the flag byte, so a single NEON
 * equality check per lane covers any Unicode target. */

int64_t w_lex16_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target = (uint16_t)((cp_i64 & 0xFF) << 8);
    uint16_t cp_mask = 0xFF00;

    int16x8_t v_target = vdupq_n_s16((int16_t)target);
    int16x8_t v_cp_mask = vdupq_n_s16((int16_t)cp_mask);
    int16x8_t zero = vdupq_n_s16(0);

    for (;;) {
        int16x8_t v = vld1q_s16((const int16_t *)(lc + pos));
        int16x8_t cp_part = vandq_s16(v, v_cp_mask);
        int16x8_t cp_match = vceqq_s16(cp_part, v_target);
        int16x8_t is_zero = vceqq_s16(v, zero);
        int16x8_t stop = vorrq_s16(cp_match, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 8; i++) {
                uint16_t w = lc[pos + i];
                if (w == 0 || (w & cp_mask) == target) return pos + i;
            }
        }
        pos += 8;
    }
}

int64_t w_lex32_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target = (uint32_t)(cp_i64 << 11);
    uint32_t cp_mask = 0xFFFFF800u;

    int32x4_t v_target = vdupq_n_s32((int32_t)target);
    int32x4_t v_cp_mask = vdupq_n_s32((int32_t)cp_mask);
    int32x4_t zero = vdupq_n_s32(0);

    for (;;) {
        int32x4_t v = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t cp_part = vandq_s32(v, v_cp_mask);
        int32x4_t cp_match = vceqq_s32(cp_part, v_target);
        int32x4_t is_zero = vceqq_s32(v, zero);
        int32x4_t stop = vorrq_s32(cp_match, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 4; i++) {
                uint32_t w = lc[pos + i];
                if (w == 0 || (w & cp_mask) == target) return pos + i;
            }
        }
        pos += 4;
    }
}

/* Lex64 keeps the codepoint in bits 18..38. Four unrolled two-lane loads
 * inspect eight source characters per loop. Unlike the narrower scanners,
 * this helper is explicitly length-bounded: the default Lex64 packer only
 * promises one sentinel element, while language-specific packers currently
 * provide a wider tail pad. */
int64_t w_lex64_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    uint64_t *lc = (uint64_t *)(uintptr_t)data_ptr;
    const uint64_t cp_mask = UINT64_C(0x0000007ffffc0000);
    const uint64_t target = ((uint64_t)cp_i64 << 18) & cp_mask;
    uint64x2_t v_mask = vdupq_n_u64(cp_mask);
    uint64x2_t v_target = vdupq_n_u64(target);

    while (pos + 8 <= length) {
        uint64x2_t m0 = vceqq_u64(vandq_u64(vld1q_u64(lc + pos), v_mask), v_target);
        uint64x2_t m1 = vceqq_u64(vandq_u64(vld1q_u64(lc + pos + 2), v_mask), v_target);
        uint64x2_t m2 = vceqq_u64(vandq_u64(vld1q_u64(lc + pos + 4), v_mask), v_target);
        uint64x2_t m3 = vceqq_u64(vandq_u64(vld1q_u64(lc + pos + 6), v_mask), v_target);
        uint64_t any = vgetq_lane_u64(m0, 0) | vgetq_lane_u64(m0, 1) |
                       vgetq_lane_u64(m1, 0) | vgetq_lane_u64(m1, 1) |
                       vgetq_lane_u64(m2, 0) | vgetq_lane_u64(m2, 1) |
                       vgetq_lane_u64(m3, 0) | vgetq_lane_u64(m3, 1);
        if (any != 0) {
            for (int i = 0; i < 8; i++)
                if ((lc[pos + i] & cp_mask) == target) return pos + i;
        }
        pos += 8;
    }
    while (pos < length) {
        if ((lc[pos] & cp_mask) == target) return pos;
        pos++;
    }
    return length;
}

/* scan_to_cp_or: find the first LexChar whose codepoint matches
 * EITHER of two targets, or the sentinel. Used for string and character
 * literal content scans where the loop terminates on the closing quote
 * OR a backslash escape (which the lexer then handles by skipping 2
 * chars and continuing). Two parallel vceqq lanes ORed together. */

int64_t w_lex16_scan_to_cp_or(int64_t data_ptr, int64_t length, int64_t pos,
                                  int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target_a = (uint16_t)((cp_a_i64 & 0xFF) << 8);
    uint16_t target_b = (uint16_t)((cp_b_i64 & 0xFF) << 8);
    uint16_t cp_mask = 0xFF00;

    int16x8_t v_target_a = vdupq_n_s16((int16_t)target_a);
    int16x8_t v_target_b = vdupq_n_s16((int16_t)target_b);
    int16x8_t v_cp_mask = vdupq_n_s16((int16_t)cp_mask);
    int16x8_t zero = vdupq_n_s16(0);

    for (;;) {
        int16x8_t v = vld1q_s16((const int16_t *)(lc + pos));
        int16x8_t cp_part = vandq_s16(v, v_cp_mask);
        int16x8_t match_a = vceqq_s16(cp_part, v_target_a);
        int16x8_t match_b = vceqq_s16(cp_part, v_target_b);
        int16x8_t is_zero = vceqq_s16(v, zero);
        int16x8_t stop = vorrq_s16(vorrq_s16(match_a, match_b), is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 8; i++) {
                uint16_t w = lc[pos + i];
                if (w == 0) return pos + i;
                uint16_t cp_part_scalar = w & cp_mask;
                if (cp_part_scalar == target_a || cp_part_scalar == target_b) return pos + i;
            }
        }
        pos += 8;
    }
}

int64_t w_lex32_scan_to_cp_or(int64_t data_ptr, int64_t length, int64_t pos,
                                  int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target_a = (uint32_t)(cp_a_i64 << 11);
    uint32_t target_b = (uint32_t)(cp_b_i64 << 11);
    uint32_t cp_mask = 0xFFFFF800u;

    int32x4_t v_target_a = vdupq_n_s32((int32_t)target_a);
    int32x4_t v_target_b = vdupq_n_s32((int32_t)target_b);
    int32x4_t v_cp_mask = vdupq_n_s32((int32_t)cp_mask);
    int32x4_t zero = vdupq_n_s32(0);

    for (;;) {
        int32x4_t v = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t cp_part = vandq_s32(v, v_cp_mask);
        int32x4_t match_a = vceqq_s32(cp_part, v_target_a);
        int32x4_t match_b = vceqq_s32(cp_part, v_target_b);
        int32x4_t is_zero = vceqq_s32(v, zero);
        int32x4_t stop = vorrq_s32(vorrq_s32(match_a, match_b), is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 4; i++) {
                uint32_t w = lc[pos + i];
                if (w == 0) return pos + i;
                uint32_t cp_part_scalar = w & cp_mask;
                if (cp_part_scalar == target_a || cp_part_scalar == target_b) return pos + i;
            }
        }
        pos += 4;
    }
}

/* scan_to_cp2: find the first position where cp(lc[pos]) == target_a AND
 * cp(lc[pos+1]) == target_b. Used for block comment scans where the
 * terminator is a two-codepoint sequence (asterisk-then-slash). The
 * previous loop called scan_to_cp(*) one ccall per * character, which
 * is expensive for comments dense with asterisks (separator lines,
 * ASCII art headers). This helper collapses the whole search into one
 * ccall by checking each lane against (lc[pos+i], lc[pos+i+1]) as a
 * pair and ANDing the two equality lanes together.
 *
 * The two NEON loads overlap by one element: lane i of v_a covers
 * lc[pos+i], lane i of v_b covers lc[pos+i+1]. A pair match at lane i
 * means the terminator starts at pos+i. Bounds reserve one extra lane
 * for the offset-1 load. */

int64_t w_lex16_scan_to_cp2(int64_t data_ptr, int64_t length, int64_t pos,
                             int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target_a = (uint16_t)((cp_a_i64 & 0xFF) << 8);
    uint16_t target_b = (uint16_t)((cp_b_i64 & 0xFF) << 8);
    uint16_t cp_mask = 0xFF00;

    int16x8_t v_target_a = vdupq_n_s16((int16_t)target_a);
    int16x8_t v_target_b = vdupq_n_s16((int16_t)target_b);
    int16x8_t v_cp_mask = vdupq_n_s16((int16_t)cp_mask);
    int16x8_t zero = vdupq_n_s16(0);

    for (;;) {
        int16x8_t v_a = vld1q_s16((const int16_t *)(lc + pos));
        int16x8_t v_b = vld1q_s16((const int16_t *)(lc + pos + 1));
        int16x8_t cp_a = vandq_s16(v_a, v_cp_mask);
        int16x8_t cp_b = vandq_s16(v_b, v_cp_mask);
        int16x8_t match_a = vceqq_s16(cp_a, v_target_a);
        int16x8_t match_b = vceqq_s16(cp_b, v_target_b);
        int16x8_t pair_match = vandq_s16(match_a, match_b);
        int16x8_t is_zero = vceqq_s16(v_a, zero);
        int16x8_t stop = vorrq_s16(pair_match, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s16(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 8; i++) {
                uint16_t w = lc[pos + i];
                if (w == 0) return pos + i;
                if ((w & cp_mask) == target_a && (lc[pos + i + 1] & cp_mask) == target_b) return pos + i;
            }
        }
        pos += 8;
    }
}

int64_t w_lex32_scan_to_cp2(int64_t data_ptr, int64_t length, int64_t pos,
                             int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target_a = (uint32_t)(cp_a_i64 << 11);
    uint32_t target_b = (uint32_t)(cp_b_i64 << 11);
    uint32_t cp_mask = 0xFFFFF800u;

    int32x4_t v_target_a = vdupq_n_s32((int32_t)target_a);
    int32x4_t v_target_b = vdupq_n_s32((int32_t)target_b);
    int32x4_t v_cp_mask = vdupq_n_s32((int32_t)cp_mask);
    int32x4_t zero = vdupq_n_s32(0);

    for (;;) {
        int32x4_t v_a = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t v_b = vld1q_s32((const int32_t *)(lc + pos + 1));
        int32x4_t cp_a = vandq_s32(v_a, v_cp_mask);
        int32x4_t cp_b = vandq_s32(v_b, v_cp_mask);
        int32x4_t match_a = vceqq_s32(cp_a, v_target_a);
        int32x4_t match_b = vceqq_s32(cp_b, v_target_b);
        int32x4_t pair_match = vandq_s32(match_a, match_b);
        int32x4_t is_zero = vceqq_s32(v_a, zero);
        int32x4_t stop = vorrq_s32(pair_match, is_zero);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 0);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_s32(stop), 1);
        if (lo | hi) {
            for (int i = 0; i < 4; i++) {
                uint32_t w = lc[pos + i];
                if (w == 0) return pos + i;
                if ((w & cp_mask) == target_a && (lc[pos + i + 1] & cp_mask) == target_b) return pos + i;
            }
        }
        pos += 4;
    }
}

#else  /* x86 / non-aarch64 — scalar fallback with identical semantics. */

int64_t w_lex16_scan_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t mask = (uint16_t)flag_mask_i64;
    while ((lc[pos] & mask) != 0) pos++;
    return pos;
}

int64_t w_lex32_scan_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t mask = (uint32_t)flag_mask_i64;
    while ((lc[pos] & mask) != 0) pos++;
    return pos;
}

int64_t w_lex32_scan_flag_pure(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    return w_lex32_scan_flag(data_ptr, length, pos, flag_mask_i64);
}

int64_t w_lex16_scan_until_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t mask = (uint16_t)flag_mask_i64;
    while (1) {
        uint16_t w = lc[pos];
        if (w == 0 || (w & mask) != 0) return pos;
        pos++;
    }
}

int64_t w_lex32_scan_until_flag(int64_t data_ptr, int64_t length, int64_t pos, int64_t flag_mask_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t mask = (uint32_t)flag_mask_i64;
    while (1) {
        uint32_t w = lc[pos];
        if (w == 0 || (w & mask) != 0) return pos;
        pos++;
    }
}

int64_t w_lex16_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target = (uint16_t)((cp_i64 & 0xFF) << 8);
    while (1) {
        uint16_t w = lc[pos];
        if (w == 0 || (w & 0xFF00) == target) return pos;
        pos++;
    }
}

int64_t w_lex32_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target = (uint32_t)(cp_i64 << 11);
    while (1) {
        uint32_t w = lc[pos];
        if (w == 0 || (w & 0xFFFFF800u) == target) return pos;
        pos++;
    }
}

int64_t w_lex64_scan_to_cp(int64_t data_ptr, int64_t length, int64_t pos, int64_t cp_i64) {
    uint64_t *lc = (uint64_t *)(uintptr_t)data_ptr;
    uint64_t cp_mask = UINT64_C(0x0000007ffffc0000);
    uint64_t target = ((uint64_t)cp_i64 << 18) & cp_mask;
    while (pos < length) {
        if ((lc[pos] & cp_mask) == target) return pos;
        pos++;
    }
    return length;
}

int64_t w_lex16_scan_to_cp_or(int64_t data_ptr, int64_t length, int64_t pos,
                                  int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target_a = (uint16_t)((cp_a_i64 & 0xFF) << 8);
    uint16_t target_b = (uint16_t)((cp_b_i64 & 0xFF) << 8);
    while (1) {
        uint16_t w = lc[pos];
        if (w == 0) return pos;
        uint16_t cp_part = w & 0xFF00;
        if (cp_part == target_a || cp_part == target_b) return pos;
        pos++;
    }
}

int64_t w_lex32_scan_to_cp_or(int64_t data_ptr, int64_t length, int64_t pos,
                                  int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target_a = (uint32_t)(cp_a_i64 << 11);
    uint32_t target_b = (uint32_t)(cp_b_i64 << 11);
    while (1) {
        uint32_t w = lc[pos];
        if (w == 0) return pos;
        uint32_t cp_part = w & 0xFFFFF800u;
        if (cp_part == target_a || cp_part == target_b) return pos;
        pos++;
    }
}

int64_t w_lex16_scan_to_cp2(int64_t data_ptr, int64_t length, int64_t pos,
                             int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint16_t *lc = (uint16_t *)(uintptr_t)data_ptr;
    uint16_t target_a = (uint16_t)((cp_a_i64 & 0xFF) << 8);
    uint16_t target_b = (uint16_t)((cp_b_i64 & 0xFF) << 8);
    while (1) {
        uint16_t w = lc[pos];
        if (w == 0) return pos;
        if ((w & 0xFF00) == target_a && (lc[pos + 1] & 0xFF00) == target_b) return pos;
        pos++;
    }
}

int64_t w_lex32_scan_to_cp2(int64_t data_ptr, int64_t length, int64_t pos,
                             int64_t cp_a_i64, int64_t cp_b_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    uint32_t target_a = (uint32_t)(cp_a_i64 << 11);
    uint32_t target_b = (uint32_t)(cp_b_i64 << 11);
    while (1) {
        uint32_t w = lc[pos];
        if (w == 0) return pos;
        if ((w & 0xFFFFF800u) == target_a && (lc[pos + 1] & 0xFFFFF800u) == target_b) return pos;
        pos++;
    }
}

/* (#59) u8 SIMD: x86 / non-aarch64 scalar fallback for byte
 * scan. memchr() in modern libc is itself heavily SIMD-optimized
 * (typically AVX2 on x86), so this defers to it. */
int64_t w_byte_scan_eq(const uint8_t *data, int64_t size, uint8_t needle) {
    if (size <= 0) return -1;
    const void *p = memchr(data, needle, (size_t)size);
    if (p == NULL) return -1;
    return (int64_t)((const uint8_t *)p - data);
}

/* Count form: scalar walk via memchr — repeated calls amortize the
 * per-search SIMD-ramp cost into a tight inner loop. Most libc memchr
 * implementations beat a hand-rolled scalar `for` loop here. */
int64_t w_byte_scan_count(const uint8_t *data, int64_t size, uint8_t needle) {
    int64_t total = 0;
    const uint8_t *p = data;
    int64_t remaining = size;
    while (remaining > 0) {
        const void *hit = memchr(p, needle, (size_t)remaining);
        if (hit == NULL) break;
        total++;
        const uint8_t *h = (const uint8_t *)hit;
        remaining -= (h - p) + 1;
        p = h + 1;
    }
    return total;
}

int64_t w_byte_scan_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    for (int64_t i = 0; i < size; i++) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d) return i;
    }
    return -1;
}

int64_t w_byte_scan_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                         int64_t e, int64_t f, int64_t g, int64_t h) {
    for (int64_t i = 0; i < size; i++) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d ||
            x == (uint8_t)e || x == (uint8_t)f || x == (uint8_t)g || x == (uint8_t)h) return i;
    }
    return -1;
}

int64_t w_byte_scan_count_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d) total++;
    }
    return total;
}

int64_t w_byte_scan_count_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                               int64_t e, int64_t f, int64_t g, int64_t h) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) {
        uint8_t x = data[i];
        if (x == (uint8_t)a || x == (uint8_t)b || x == (uint8_t)c || x == (uint8_t)d ||
            x == (uint8_t)e || x == (uint8_t)f || x == (uint8_t)g || x == (uint8_t)h) total++;
    }
    return total;
}

/* Threaded variants on x86: just defer to serial. Threading still works
 * but glibc memchr's AVX2 path is fast enough that the spawn overhead
 * usually outweighs the parallelism win at typical sizes. Revisit if
 * a Linux-ARM or x86 host needs the explicit threading. */
int64_t w_byte_scan_count_threaded(const uint8_t *data, int64_t size, uint8_t needle) {
    return w_byte_scan_count(data, size, needle);
}
int64_t w_byte_scan_eq_threaded(const uint8_t *data, int64_t size, uint8_t needle) {
    return w_byte_scan_eq(data, size, needle);
}
int64_t w_byte_scan_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    return w_byte_scan_any4(data, size, a, b, c, d);
}
int64_t w_byte_scan_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                  int64_t e, int64_t f, int64_t g, int64_t h) {
    return w_byte_scan_any8(data, size, a, b, c, d, e, f, g, h);
}
int64_t w_byte_scan_count_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d) {
    return w_byte_scan_count_any4(data, size, a, b, c, d);
}
int64_t w_byte_scan_count_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                        int64_t e, int64_t f, int64_t g, int64_t h) {
    return w_byte_scan_count_any8(data, size, a, b, c, d, e, f, g, h);
}

/* Reverse byte scan: scalar walk backwards. memrchr exists in glibc
 * but isn't portable to all libcs we might target — keep this simple. */
int64_t w_byte_scan_eq_rev(const uint8_t *data, int64_t size, uint8_t needle) {
    int64_t i = size;
    while (i > 0) {
        i--;
        if (data[i] == needle) return i;
    }
    return -1;
}

/* In-place byte replacement: scalar fallback. Modern compilers will
 * auto-vectorize this loop on x86 with -O3 + AVX2 or better. */
int64_t w_byte_replace(uint8_t *data, int64_t size, uint8_t old_b, uint8_t new_b) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) {
        if (data[i] == old_b) {
            data[i] = new_b;
            total++;
        }
    }
    return total;
}

/* u16/u32 scans, x86 scalar fallbacks. -O3 + AVX2 will auto-vectorize. */
int64_t w_u16_scan_eq(const uint16_t *data, int64_t size, uint16_t needle) {
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) return i;
    return -1;
}
int64_t w_u16_scan_count(const uint16_t *data, int64_t size, uint16_t needle) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) total++;
    return total;
}
int64_t w_u32_scan_eq(const uint32_t *data, int64_t size, uint32_t needle) {
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) return i;
    return -1;
}
int64_t w_u32_scan_count(const uint32_t *data, int64_t size, uint32_t needle) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) total++;
    return total;
}
int64_t w_u16_scan_eq_rev(const uint16_t *data, int64_t size, uint16_t needle) {
    while (size > 0) { size--; if (data[size] == needle) return size; }
    return -1;
}
int64_t w_u32_scan_eq_rev(const uint32_t *data, int64_t size, uint32_t needle) {
    while (size > 0) { size--; if (data[size] == needle) return size; }
    return -1;
}
int64_t w_u16_scan_count_threaded(const uint16_t *data, int64_t size, uint16_t needle) {
    return w_u16_scan_count(data, size, needle);
}
int64_t w_u16_scan_eq_threaded(const uint16_t *data, int64_t size, uint16_t needle) {
    return w_u16_scan_eq(data, size, needle);
}
int64_t w_u32_scan_count_threaded(const uint32_t *data, int64_t size, uint32_t needle) {
    return w_u32_scan_count(data, size, needle);
}
int64_t w_u32_scan_eq_threaded(const uint32_t *data, int64_t size, uint32_t needle) {
    return w_u32_scan_eq(data, size, needle);
}

/* u1 / u64 scalar fallbacks. */
int64_t w_u1_count_set(const uint8_t *data, int64_t bit_size) {
    int64_t total = 0;
    int64_t whole_bytes = bit_size >> 3;
    for (int64_t i = 0; i < whole_bytes; i++) total += __builtin_popcount(data[i]);
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        total += __builtin_popcount(data[whole_bytes] & mask);
    }
    return total;
}
int64_t w_u1_index_set(const uint8_t *data, int64_t bit_size) {
    int64_t whole_bytes = bit_size >> 3;
    for (int64_t i = 0; i < whole_bytes; i++) if (data[i] != 0) return i * 8 + __builtin_ctz(data[i]);
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        uint8_t b = data[whole_bytes] & mask;
        if (b != 0) return whole_bytes * 8 + __builtin_ctz(b);
    }
    return -1;
}
int64_t w_u1_index_unset(const uint8_t *data, int64_t bit_size) {
    int64_t whole_bytes = bit_size >> 3;
    for (int64_t i = 0; i < whole_bytes; i++) if (data[i] != 0xFF) return i * 8 + __builtin_ctz((uint8_t)~data[i]);
    int64_t tail_bits = bit_size & 7;
    if (tail_bits > 0) {
        uint8_t mask = (uint8_t)((1u << tail_bits) - 1);
        uint8_t b = (uint8_t)(~data[whole_bytes]) & mask;
        if (b != 0) return whole_bytes * 8 + __builtin_ctz(b);
    }
    return -1;
}
int64_t w_u64_scan_eq(const uint64_t *data, int64_t size, uint64_t needle) {
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) return i;
    return -1;
}
int64_t w_u64_scan_count(const uint64_t *data, int64_t size, uint64_t needle) {
    int64_t total = 0;
    for (int64_t i = 0; i < size; i++) if (data[i] == needle) total++;
    return total;
}
int64_t w_u64_scan_eq_rev(const uint64_t *data, int64_t size, uint64_t needle) {
    while (size > 0) { size--; if (data[size] == needle) return size; }
    return -1;
}

#endif

/* Helpers: extract raw byte pointer / length from a String WValue.
 * Used by the SIMD JSON classifier driver to get a raw `data_ptr` from
 * the result of `read_file`. Handles ropes (flattens first), slab
 * strings, and heap strings. Platform-independent. */
static __thread char g_string_byte_ptr_inline_buf[6];

int64_t w_string_byte_ptr(int64_t str_wval) {
    WValue v = (WValue)str_wval;
    if (w_is_rope(v)) v = w_rope_flatten(v);
    char buf[6];
    const char *s;
    size_t len;
    w_str_data(v, buf, &s, &len);
    if (s == buf) {
        memcpy(g_string_byte_ptr_inline_buf, buf, len + 1);
        s = g_string_byte_ptr_inline_buf;
    }
    (void)len;
    return (int64_t)(uintptr_t)s;
}

int64_t w_string_byte_length(int64_t str_wval) {
    WValue v = (WValue)str_wval;
    /* A rope already carries its byte length. Reading that header preserves
     * the function's pure/read-only contract and avoids materializing and
     * caching a flat String merely to answer `.size()`. */
    if (w_is_rope(v)) return (int64_t)((WRope *)w_as_ptr(v))->total_len;
    if (!w_is_stringy(v)) return 0;
    size_t mode = (v >> 1) & 7;
    if (mode <= 5) return (int64_t)mode;
    if (mode == 6) {
        size_t cached = (size_t)((v >> 28) & 0x3F);
        if (__builtin_expect(cached != 0, 1)) return (int64_t)cached;
        if (g_string_slab.base) {
            uint32_t idx = (uint32_t)((v >> 4) & 0xFFFFFF);
            return (int64_t)g_string_slab.base[(idx * W_SLAB_SLOT_SIZE) + 1];
        }
        return 0;
    }
    WString *ws = w_as_heap_str(v);
    return ws ? (int64_t)w_heap_string_len(ws) : 0;
}

/* First byte of a String, without allocating a one-byte slice. -1 denotes
 * an empty String; -2 denotes a non-String so callers can preserve a generic
 * to_s fallback. Symbols deliberately take the latter path. */
int64_t w_string_first_byte(WValue value) {
    if (__builtin_expect(w_is_string(value), 1)) {
        size_t mode = (value >> 1) & 7;
        if (mode <= 5)
            return mode == 0 ? -1 : (int64_t)((value >> 4) & 0xFF);
        if (mode == 6) {
            uint32_t idx = (uint32_t)((value >> 4) & 0xFFFFFF);
            if (__builtin_expect(g_string_slab.base != NULL, 1))
                return (int64_t)g_string_slab.base[(size_t)idx * W_SLAB_SLOT_SIZE + W_SLAB_DATA_OFFSET];
        } else {
            WString *ws = w_as_heap_str(value);
            return w_heap_string_len(ws) == 0 ? -1 : (int64_t)(uint8_t)ws->data[0];
        }
    }
    if (w_is_rope(value)) value = w_rope_flatten(value);
    if (!w_is_string(value) || w_is_symbol(value)) return -2;
    char inline_buf[6];
    const char *bytes;
    size_t len;
    w_str_data(value, inline_buf, &bytes, &len);
    return len == 0 ? -1 : (int64_t)(unsigned char)bytes[0];
}

static size_t w_utf8_index_width(const char *s, size_t remaining);
static int w_bytes_valid_utf8_p(const uint8_t *data, size_t len);

/* ---- Unicode normalization (UAX #15) + grapheme segmentation (UAX #29) ----
 * Codepoint-level tables and lookups live in the generated
 * runtime/unicode_tables.c (scripts/gen_unicode_tables.py, validated there
 * against Python's unicodedata over every codepoint x 4 forms plus a 60k
 * adversarial corpus, and against the full UCD GraphemeBreakTest). These
 * entry points do the WValue/UTF-8 work for core/string.w. */
/* Weak stand-ins, following the lexchar/ssmr gated-companion pattern: the
 * strong versions live in the generated unicode_tables.c, linked only when
 * a program's IR references w_string_normalize / w_string_grapheme_next.
 * The entry points probe un_tables_present() and raise rather than compute
 * wrong answers if the gate is ever bypassed. */
__attribute__((weak)) int un_tables_present(void) { return 0; }
__attribute__((weak)) int un_ccc(uint32_t cp) { (void)cp; return 0; }
__attribute__((weak)) int un_decomp(uint32_t cp, int compat, const uint32_t **out) {
    (void)cp; (void)compat; (void)out; return 0;
}
__attribute__((weak)) uint32_t un_compose(uint32_t a, uint32_t b) {
    (void)a; (void)b; return 0;
}
__attribute__((weak)) int un_gcb_class(uint32_t cp) { (void)cp; return 0; }
__attribute__((weak)) int un_incb(uint32_t cp) { (void)cp; return 0; }
__attribute__((weak)) int un_extended_pictographic(uint32_t cp) { (void)cp; return 0; }

#define W_UN_SBASE 0xAC00
#define W_UN_LBASE 0x1100
#define W_UN_VBASE 0x1161
#define W_UN_TBASE 0x11A7
#define W_UN_LCOUNT 19
#define W_UN_VCOUNT 21
#define W_UN_TCOUNT 28
#define W_UN_NCOUNT (W_UN_VCOUNT * W_UN_TCOUNT)
#define W_UN_SCOUNT (W_UN_LCOUNT * W_UN_NCOUNT)

/* Decode one codepoint at byte offset i. Width comes from
 * w_utf8_index_width, so an invalid lead/continuation degrades to the raw
 * byte with width 1 — same clamping as every other walker here. */
static uint32_t w_un_decode_at(const char *s, size_t len, size_t i, size_t *width) {
    size_t w = w_utf8_index_width(s + i, len - i);
    *width = w;
    uint8_t c0 = (uint8_t)s[i];
    if (w == 1) return c0;
    uint32_t cp = c0 & (uint32_t)(0x7F >> w);
    for (size_t k = 1; k < w; k++) cp = (cp << 6) | ((uint8_t)s[i + k] & 0x3F);
    return cp;
}

static size_t w_un_encode(uint32_t cp, uint8_t *out) {
    if (cp < 0x80) { out[0] = (uint8_t)cp; return 1; }
    if (cp < 0x800) {
        out[0] = (uint8_t)(0xC0 | (cp >> 6));
        out[1] = (uint8_t)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (uint8_t)(0xE0 | (cp >> 12));
        out[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (uint8_t)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (uint8_t)(0xF0 | (cp >> 18));
    out[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (uint8_t)(0x80 | (cp & 0x3F));
    return 4;
}

/* form: 0=NFC 1=NFD 2=NFKC 3=NFKD. ASCII content (flag-checked) and empty
 * strings are normalization-invariant in every form and return identity
 * (symbol bit cleared, the to_s convention). Invalid UTF-8 also returns
 * identity: normalizing undecodable bytes has no defined answer, and
 * silently rewriting them would corrupt pass-through data. */
WValue w_string_normalize(WValue recv, int64_t form) {
    char buf6[6];
    const char *s;
    size_t len;
    w_str_data(recv, buf6, &s, &len);
    if (len == 0 || w_string_ascii_p(recv)) return recv & ~1ULL;
    if (!un_tables_present())
        w_raise(w_string("normalize: Unicode tables not linked (program does not reference String normalization)"));
    if (!w_bytes_valid_utf8_p((const uint8_t *)s, len)) return recv & ~1ULL;

    int compat = (form == 2 || form == 3);
    int compose = (form == 0 || form == 2);

    size_t dcap = len + 16;
    uint32_t *d = malloc(dcap * sizeof(uint32_t));
    size_t dn = 0;
#define W_UN_PUSH(v)                                                     \
    do {                                                                 \
        if (dn == dcap) {                                                \
            dcap *= 2;                                                   \
            d = realloc(d, dcap * sizeof(uint32_t));                     \
        }                                                                \
        d[dn++] = (v);                                                   \
    } while (0)

    for (size_t i = 0; i < len;) {
        size_t w;
        uint32_t cp = w_un_decode_at(s, len, i, &w);
        i += w;
        if (cp >= W_UN_SBASE && cp < W_UN_SBASE + W_UN_SCOUNT) {
            uint32_t si = cp - W_UN_SBASE;
            W_UN_PUSH(W_UN_LBASE + si / W_UN_NCOUNT);
            W_UN_PUSH(W_UN_VBASE + (si % W_UN_NCOUNT) / W_UN_TCOUNT);
            uint32_t t = si % W_UN_TCOUNT;
            if (t) W_UN_PUSH(W_UN_TBASE + t);
            continue;
        }
        const uint32_t *exp;
        int k = un_decomp(cp, compat, &exp);
        if (k) {
            for (int j = 0; j < k; j++) W_UN_PUSH(exp[j]);
        } else {
            W_UN_PUSH(cp);
        }
    }
#undef W_UN_PUSH

    /* Canonical ordering: stable exchange walk over nonzero-ccc runs. */
    for (size_t i = 1; i < dn;) {
        int cc = un_ccc(d[i]);
        if (cc != 0 && un_ccc(d[i - 1]) > cc) {
            uint32_t tmp = d[i - 1];
            d[i - 1] = d[i];
            d[i] = tmp;
            i = (i > 1) ? i - 1 : i + 1;
        } else {
            i++;
        }
    }

    if (compose && dn > 0) {
        size_t on = 1;
        ptrdiff_t starter = (un_ccc(d[0]) == 0) ? 0 : -1;
        int last_cc = un_ccc(d[0]);
        for (size_t i = 1; i < dn; i++) {
            uint32_t cp = d[i];
            int cc = un_ccc(cp);
            if (starter >= 0 && (last_cc == 0 || last_cc < cc)) {
                uint32_t c = un_compose(d[starter], cp);
                if (c) {
                    d[starter] = c;
                    continue;
                }
            }
            d[on] = cp;
            if (cc == 0) starter = (ptrdiff_t)on;
            last_cc = cc;
            on++;
        }
        dn = on;
    }

    uint8_t *out = malloc(dn * 4 + 1);
    size_t olen = 0;
    for (size_t i = 0; i < dn; i++) olen += w_un_encode(d[i], out + olen);
    free(d);
    WValue result = w_string_n_known_ascii((const char *)out, olen,
                                           w_bytes_ascii_p(out, olen));
    free(out);
    return result;
}

/* Byte offset of the next extended-grapheme-cluster boundary after
 * byte_pos, which the caller guarantees IS a boundary (walks always start
 * at 0 or a previously returned offset). Because clusters never span a
 * boundary, the GB9c and GB11 lookbehinds reduce to forward state machines
 * seeded at byte_pos. Invalid bytes decode as width-1 Others and simply
 * break everywhere. */
int64_t w_string_grapheme_next(int64_t str_wval, int64_t byte_pos) {
    WValue recv = (WValue)str_wval;
    char buf6[6];
    const char *s;
    size_t len;
    w_str_data(recv, buf6, &s, &len);
    if (byte_pos < 0) byte_pos = 0;
    if ((size_t)byte_pos >= len) return (int64_t)len;
    if (!un_tables_present())
        w_raise(w_string("graphemes: Unicode tables not linked (program does not reference String segmentation)"));

    /* GCB class ids match the generator: 0 Other, 1 CR, 2 LF, 3 Control,
     * 4 Extend, 5 ZWJ, 6 RI, 7 Prepend, 8 SpacingMark, 9 L, 10 V, 11 T,
     * 12 LV, 13 LVT. */
    enum { GO = 0, GCR, GLF, GCN, GEX, GZWJ, GRI, GPP, GSM, GL, GV, GT, GLV, GLVT };

    size_t i = (size_t)byte_pos;
    size_t w;
    uint32_t prev = w_un_decode_at(s, len, i, &w);
    int ca = un_gcb_class(prev);
    size_t next_i = i + w;
    int ri_run = (ca == GRI) ? 1 : 0;
    /* GB11: 1 = saw ExtPic (Extend* so far), 2 = ...then ZWJ. */
    int epz = un_extended_pictographic(prev) ? 1 : 0;
    /* GB9c: 1 = InCB Consonant seen, 2 = ...with a Linker since ([Extend
     * Linker]* interleavings keep state 2). */
    int iv = un_incb(prev);
    int incb_st = (iv == 1) ? 1 : 0;

    while (next_i < len) {
        uint32_t cur = w_un_decode_at(s, len, next_i, &w);
        int cb = un_gcb_class(cur);
        int brk;
        if (ca == GCR && cb == GLF) brk = 0;                       /* GB3 */
        else if (ca == GCN || ca == GCR || ca == GLF) brk = 1;     /* GB4 */
        else if (cb == GCN || cb == GCR || cb == GLF) brk = 1;     /* GB5 */
        else if (ca == GL && (cb == GL || cb == GV || cb == GLV || cb == GLVT))
            brk = 0;                                               /* GB6 */
        else if ((ca == GLV || ca == GV) && (cb == GV || cb == GT))
            brk = 0;                                               /* GB7 */
        else if ((ca == GLVT || ca == GT) && cb == GT) brk = 0;    /* GB8 */
        else if (cb == GEX || cb == GZWJ) brk = 0;                 /* GB9 */
        else if (cb == GSM) brk = 0;                               /* GB9a */
        else if (ca == GPP) brk = 0;                               /* GB9b */
        else if (un_incb(cur) == 1 && incb_st == 2) brk = 0;       /* GB9c */
        else if (ca == GZWJ && epz == 2 && un_extended_pictographic(cur))
            brk = 0;                                               /* GB11 */
        else if (ca == GRI && cb == GRI) brk = (ri_run % 2 == 0);  /* GB12/13 */
        else brk = 1;
        if (brk) return (int64_t)next_i;

        /* advance states */
        if (cb == GRI) ri_run++; else ri_run = 0;
        if (un_extended_pictographic(cur)) epz = 1;
        else if (epz == 1 && cb == GEX) epz = 1;
        else if (epz == 1 && cb == GZWJ) epz = 2;
        else epz = 0;
        iv = un_incb(cur);
        if (iv == 1) incb_st = 1;
        else if (incb_st >= 1 && iv == 3) incb_st = 2;
        else if (incb_st >= 1 && iv == 2) { /* keep */ }
        else incb_st = 0;

        prev = cur;
        ca = cb;
        next_i += w;
    }
    return (int64_t)len;
}

/* Width of one valid UTF-8 code point for subscript traversal. Invalid input
 * advances one byte so raw data received from sockets remains addressable. */
static size_t w_utf8_index_width(const char *s, size_t remaining) {
    if (remaining == 0) return 0;
    uint8_t c0 = (uint8_t)s[0];
    if (c0 < 0x80) return 1;
    if (c0 >= 0xC2 && c0 <= 0xDF && remaining >= 2 &&
        ((uint8_t)s[1] & 0xC0) == 0x80) return 2;
    if (c0 >= 0xE0 && c0 <= 0xEF && remaining >= 3 &&
        ((uint8_t)s[1] & 0xC0) == 0x80 && ((uint8_t)s[2] & 0xC0) == 0x80 &&
        !(c0 == 0xE0 && (uint8_t)s[1] < 0xA0) &&
        !(c0 == 0xED && (uint8_t)s[1] > 0x9F)) return 3;
    if (c0 >= 0xF0 && c0 <= 0xF4 && remaining >= 4 &&
        ((uint8_t)s[1] & 0xC0) == 0x80 && ((uint8_t)s[2] & 0xC0) == 0x80 &&
        ((uint8_t)s[3] & 0xC0) == 0x80 &&
        !(c0 == 0xF0 && (uint8_t)s[1] < 0x90) &&
        !(c0 == 0xF4 && (uint8_t)s[1] > 0x8F)) return 4;
    return 1;
}

static inline int w_utf8_cont(uint8_t c) {
    return (c & 0xC0) == 0x80;
}

static int w_bytes_valid_utf8_p(const uint8_t *data, size_t len) {
    size_t i = 0;
    while (i < len) {
#ifdef __aarch64__
        while (i + 64 <= len) {
            uint8x16_t v0 = vld1q_u8(data + i);
            uint8x16_t v1 = vld1q_u8(data + i + 16);
            uint8x16_t v2 = vld1q_u8(data + i + 32);
            uint8x16_t v3 = vld1q_u8(data + i + 48);
            uint8x16_t or01 = vorrq_u8(v0, v1);
            uint8x16_t or23 = vorrq_u8(v2, v3);
            if (vmaxvq_u8(vorrq_u8(or01, or23)) >= 0x80) break;
            i += 64;
        }
        while (i + 16 <= len) {
            uint8x16_t v = vld1q_u8(data + i);
            if (vmaxvq_u8(v) >= 0x80) break;
            i += 16;
        }
#endif
        for (;;) {
            while (i + 8 <= len) {
                uint64_t w;
                memcpy(&w, data + i, 8);
                uint64_t m = w & 0x8080808080808080ULL;
                if (m != 0) {
                    i += (size_t)(__builtin_ctzll(m) >> 3);
                    goto check_mb;
                }
                i += 8;
                if (i + 16 <= len) goto neon_resume;
            }
            while (i < len && data[i] < 0x80) i++;
            if (i >= len) return 1;
        check_mb:;
            uint8_t c = data[i];
            if ((uint32_t)(c - 0xC2) <= (0xDF - 0xC2)) {
                if (i + 1 >= len || !w_utf8_cont(data[i + 1])) return 0;
                i += 2;
            } else if ((c & 0xF0) == 0xE0) {
                if (i + 2 >= len) return 0;
                uint8_t b1 = data[i + 1], b2 = data[i + 2];
                if (((b1 & 0xC0) ^ 0x80) | ((b2 & 0xC0) ^ 0x80)) return 0;
                if ((c == 0xE0 && b1 < 0xA0) || (c == 0xED && b1 > 0x9F)) return 0;
                i += 3;
            } else {
                if (i + 3 >= len) return 0;
                uint8_t b1 = data[i + 1], b2 = data[i + 2], b3 = data[i + 3];
                if (((b1 & 0xC0) ^ 0x80) | ((b2 & 0xC0) ^ 0x80) | ((b3 & 0xC0) ^ 0x80)) return 0;
                if ((uint32_t)((((uint32_t)c << 8) | b1) - 0xF090U) > (0xF48FU - 0xF090U)) return 0;
                i += 4;
            }
        }
    neon_resume:;
    }
    return 1;
}

W_RT_INTERNAL const uint8_t *w_rt_load_lang_flags(const char *lang, int bits) {
    return w_load_lang_flags(lang, bits);
}
W_RT_INTERNAL WValue w_rt_string_to_lexchars_lang(const char *str, size_t str_len, const uint8_t *lang_flags) {
    return w_string_to_lexchars_lang(str, str_len, lang_flags);
}
W_RT_INTERNAL WValue w_rt_string_to_lex32_lang(const char *str, size_t str_len, const uint8_t *lex32_flags) {
    return w_string_to_lex32_lang(str, str_len, lex32_flags);
}
W_RT_INTERNAL WValue w_rt_string_to_lex16_lang(const char *str, size_t str_len, const uint8_t *lex16_flags, const uint8_t *lex64_flags) {
    return w_string_to_lex16_lang(str, str_len, lex16_flags, lex64_flags);
}
W_RT_INTERNAL size_t w_rt_utf8_index_width(const char *s, size_t remaining) {
    return w_utf8_index_width(s, remaining);
}
W_RT_INTERNAL int w_rt_bytes_valid_utf8_p(const uint8_t *data, size_t len) {
    return w_bytes_valid_utf8_p(data, len);
}
W_RT_INTERNAL uint32_t w_rt_un_decode_at(const char *s, size_t len, size_t i, size_t *width) {
    return w_un_decode_at(s, len, i, width);
}

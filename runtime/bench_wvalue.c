/*
 * bench_wvalue.c — Micro-benchmark suite for WValue NaN-boxing operations
 *
 * Compile:
 *   clang -O2 runtime.c bench_wvalue.c -o bench_wvalue
 *
 * Run:
 *   ./bench_wvalue
 */

#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Inline truthiness — what compiled Tungsten code actually emits */
static inline int64_t w_truthy_inline(WValue v) {
    return v > W_FALSE;
}

/* ---- Benchmark harness ---- */

static double bench(const char *name, void (*fn)(int64_t), int64_t iters) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    fn(iters);
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    double ops = iters / elapsed;
    printf("  %-30s  %12.0f ops/s  (%6.3f ms)\n", name, ops, elapsed * 1000);
    return ops;
}

/* ---- 1. Truthiness check (realistic: random value + clock work) ---- */

__attribute__((noinline))
static WValue random_wvalue(void) {
    return (rand() > RAND_MAX / 2) ? W_TRUE : W_NIL;
}

static void bench_truthy(int64_t n) {
    volatile int64_t max_clock = 0;
    for (int64_t i = 0; i < n; i++) {
        WValue v = random_wvalue();
        if (w_truthy_inline(v)) {
            int64_t c = (int64_t)clock();
            if (c > max_clock) max_clock = c;
        }
    }
}

/* ---- 3. Symbol compare (equality) ---- */
static void bench_symbol_eq(int64_t n) {
    volatile WValue a = w_symbol("foo");
    volatile WValue b = w_symbol("foo");
    volatile int64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += (a == b);
    }
}

/* ---- 4. Int increment (unbox, add 1, rebox) ---- */
static void bench_int_inc(int64_t n) {
    volatile WValue v = w_box_int(0);
    for (int64_t i = 0; i < n; i++) {
        int64_t x = w_as_int(v);
        v = w_box_int(x + 1);
    }
}

/* ---- 5. Float add (two floats) ---- */
static void bench_float_add(int64_t n) {
    WValue a = w_box_double(3.14);
    WValue b = w_box_double(2.72);
    volatile double acc = 0.0;
    for (int64_t i = 0; i < n; i++) {
        double da = w_as_double(a);
        double db = w_as_double(b);
        acc += da + db;
    }
}

/* ---- 6. Bool negation ---- */
static void bench_bool_neg(int64_t n) {
    volatile WValue v = W_TRUE;
    for (int64_t i = 0; i < n; i++) {
        v = (v == W_TRUE) ? W_FALSE : W_TRUE;
    }
}

/* ---- 7. Int type check ---- */
static void bench_is_int(int64_t n) {
    WValue v = w_box_int(42);
    volatile int acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += w_is_int(v);
    }
}

/* ---- 8. Double type check ---- */
static void bench_is_double(int64_t n) {
    WValue v = w_box_double(3.14);
    volatile int acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += w_is_double(v);
    }
}

/* ---- 9. Decimal add ---- */
static void bench_decimal_add(int64_t n) {
    WValue a = w_decimal(12345, 2);  /* 123.45 */
    WValue b = w_decimal(6789, 2);   /*  67.89 */
    volatile WValue acc = W_NIL;
    for (int64_t i = 0; i < n; i++) {
        acc = w_decimal_add(a, b);
    }
}

/* ---- 10. Decimal mul ---- */
static void bench_decimal_mul(int64_t n) {
    WValue a = w_decimal(100, 2);    /* 1.00 */
    WValue b = w_decimal(200, 2);    /* 2.00 */
    volatile WValue acc = W_NIL;
    for (int64_t i = 0; i < n; i++) {
        acc = w_decimal_mul(a, b);
    }
}

/* ---- 11. Char boxing ---- */
static void bench_char_box(int64_t n) {
    volatile WValue acc = W_NIL;
    for (int64_t i = 0; i < n; i++) {
        acc = w_box_char('A');
    }
}

/* ---- 12. Char classification (is_letter) ---- */
static void bench_char_is_letter(int64_t n) {
    WValue ch = w_box_char('A');
    volatile int acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += w_char_is_letter(ch);
    }
}

/* ---- 13. Char case delta extraction ---- */
static void bench_char_case_delta(int64_t n) {
    WValue ch = w_box_char('A');
    volatile int acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += w_char_case_delta(ch);
    }
}

/* ---- 14. Instant boxing ---- */
static void bench_instant_box(int64_t n) {
    volatile WValue acc = W_NIL;
    for (int64_t i = 0; i < n; i++) {
        acc = w_box_instant(1711036800000LL + i);
    }
}

/* ---- 15. Instant diff ---- */
static void bench_instant_diff(int64_t n) {
    WValue a = w_box_instant(1711036800000LL);
    WValue b = w_box_instant(1711036700000LL);
    volatile int64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        int64_t ta = w_unbox_instant(a);
        int64_t tb = w_unbox_instant(b);
        acc += (ta - tb);
    }
}

/* ---- 16. Hot loop: if-true-then-increment ---- */
static void bench_hot_loop(int64_t n) {
    volatile WValue counter = w_box_int(0);
    WValue cond = W_TRUE;
    for (int64_t i = 0; i < n; i++) {
        if (w_truthy_inline(cond)) {
            counter = w_box_int(w_as_int(counter) + 1);
        }
    }
}

/* ---- 17. String upcase via char metadata ---- */
static void bench_string_upcase(int64_t n) {
    /* Build a 1000-char ASCII string */
    const char *src = "the quick brown fox jumps over the lazy dog, and then does it again! ";
    int src_len = (int)strlen(src);
    char input[1001];
    int pos = 0;
    while (pos < 1000) {
        int chunk = src_len;
        if (pos + chunk > 1000) chunk = 1000 - pos;
        memcpy(input + pos, src, chunk);
        pos += chunk;
    }
    input[1000] = '\0';

    volatile char out[1001];
    for (int64_t iter = 0; iter < n; iter++) {
        for (int i = 0; i < 1000; i++) {
            WValue ch = w_box_char((uint32_t)(unsigned char)input[i]);
            int delta = w_char_case_delta(ch);
            uint32_t cp = w_char_codepoint(ch);
            /* Apply delta if lowercase (delta is negative for lowercase→uppercase) */
            if (w_char_is_lower(ch) && delta != 0) {
                out[i] = (char)(cp + delta);
            } else {
                out[i] = (char)cp;
            }
        }
        out[1000] = '\0';
    }
}

/* ---- 18. String downcase via char metadata ---- */
static void bench_string_downcase(int64_t n) {
    const char *src = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG, AND THEN DOES IT AGAIN! ";
    int src_len = (int)strlen(src);
    char input[1001];
    int pos = 0;
    while (pos < 1000) {
        int chunk = src_len;
        if (pos + chunk > 1000) chunk = 1000 - pos;
        memcpy(input + pos, src, chunk);
        pos += chunk;
    }
    input[1000] = '\0';

    volatile char out[1001];
    for (int64_t iter = 0; iter < n; iter++) {
        for (int i = 0; i < 1000; i++) {
            WValue ch = w_box_char((uint32_t)(unsigned char)input[i]);
            int delta = w_char_case_delta(ch);
            uint32_t cp = w_char_codepoint(ch);
            if (w_char_is_upper(ch) && delta != 0) {
                out[i] = (char)(cp + delta);
            } else {
                out[i] = (char)cp;
            }
        }
        out[1000] = '\0';
    }
}

/* ---- 19. Walk 10K codepoints, tally all metadata flags ---- */

/* Pre-built mixed-script codepoint array (ASCII, Latin Extended, Greek,
   Cyrillic, CJK, Arabic, Emoji, Math symbols, combining marks, etc.) */
#define WALK_LEN 10000
static uint32_t walk_codepoints[WALK_LEN];

static void build_walk_codepoints(void) {
    /* Cycle through representative Unicode ranges */
    static const uint32_t ranges[][2] = {
        {0x0020, 0x007E},   /* ASCII printable */
        {0x00C0, 0x00FF},   /* Latin Extended-A */
        {0x0391, 0x03C9},   /* Greek */
        {0x0410, 0x044F},   /* Cyrillic */
        {0x4E00, 0x4E5F},   /* CJK Unified */
        {0x0600, 0x064A},   /* Arabic */
        {0x0300, 0x036F},   /* Combining diacriticals */
        {0x2200, 0x22FF},   /* Math operators */
        {0x1F600, 0x1F64F}, /* Emoticons */
        {0x0030, 0x0039},   /* Digits */
        {0x2000, 0x200F},   /* General punctuation / zero-width */
        {0xFF01, 0xFF5E},   /* Fullwidth ASCII */
    };
    int nranges = sizeof(ranges) / sizeof(ranges[0]);
    int idx = 0;
    int ri = 0;
    uint32_t cp = ranges[0][0];
    while (idx < WALK_LEN) {
        walk_codepoints[idx++] = cp;
        cp++;
        if (cp > ranges[ri][1]) {
            ri = (ri + 1) % nranges;
            cp = ranges[ri][0];
        }
    }
}

static void bench_codepoint_walk(int64_t n) {
    volatile int64_t letters = 0, digits = 0, upper = 0, lower = 0;
    volatile int64_t emoji = 0, combining = 0, printable = 0, ascii = 0;
    volatile int64_t whitespace = 0, fullwidth = 0;

    for (int64_t iter = 0; iter < n; iter++) {
        int64_t l = 0, d = 0, u = 0, lo = 0;
        int64_t em = 0, co = 0, pr = 0, as = 0;
        int64_t ws = 0, fw = 0;
        for (int i = 0; i < WALK_LEN; i++) {
            WValue ch = w_box_char(walk_codepoints[i]);
            l  += w_char_is_letter(ch);
            d  += w_char_is_digit(ch);
            u  += w_char_is_upper(ch);
            lo += w_char_is_lower(ch);
            em += w_char_is_emoji(ch);
            co += w_char_is_combining(ch);
            pr += w_char_is_printable(ch);
            as += w_char_is_ascii(ch);
            ws += w_char_is_whitespace(ch);
            fw += (w_char_width(ch) == 2);
        }
        letters = l; digits = d; upper = u; lower = lo;
        emoji = em; combining = co; printable = pr; ascii = as;
        whitespace = ws; fullwidth = fw;
    }
}

/* ---- 20. Decimal accumulator (running total of 1000 adds) ---- */
static void bench_decimal_accumulate(int64_t n) {
    /* Simulate adding line items: $19.99 × 1000 */
    WValue item = w_decimal(1999, -2);  /* $19.99 */
    volatile WValue total;
    for (int64_t iter = 0; iter < n; iter++) {
        WValue acc = w_decimal(0, 0);
        for (int i = 0; i < 1000; i++) {
            acc = w_decimal_add(acc, item);
        }
        total = acc;
    }
}

/* ---- 21. Instant timeline scan ---- */
static void bench_instant_timeline(int64_t n) {
    /* Build an array of 1000 instants, 1 hour apart */
    #define TIMELINE_LEN 1000
    WValue timeline[TIMELINE_LEN];
    int64_t base_ms = 1711036800000LL; /* 2024-03-22 00:00:00 UTC */
    for (int i = 0; i < TIMELINE_LEN; i++) {
        timeline[i] = w_box_instant(base_ms + (int64_t)i * 3600000LL);
    }
    WValue cutoff = w_box_instant(base_ms + 500LL * 3600000LL); /* halfway */

    volatile int64_t before_count = 0;
    volatile int64_t total_span = 0;
    for (int64_t iter = 0; iter < n; iter++) {
        int64_t bc = 0;
        for (int i = 0; i < TIMELINE_LEN; i++) {
            /* Count events before cutoff */
            bc += (w_unbox_instant(timeline[i]) < w_unbox_instant(cutoff));
        }
        /* Compute total span: last - first */
        total_span = w_unbox_instant(timeline[TIMELINE_LEN - 1])
                   - w_unbox_instant(timeline[0]);
        before_count = bc;
    }
}

/* ---- 22. Heavy truthiness: scan shuffled mixed-type array ---- */

/*
 * Scan a shuffled array of mixed-type values, doing truthiness on each.
 * This defeats the branch predictor for the old tag-based approach,
 * while NaN-boxed v > 1 is branchless regardless of type mix.
 */
#define HEAVY_LEN 4096

static WValue heavy_values[HEAVY_LEN];

static void build_heavy_values(void) {
    /* ~50% falsy (nil/false) to maximize branch misprediction */
    WValue types[] = {
        w_box_int(1), w_box_int(42), W_NIL,
        w_box_double(3.14), W_FALSE, W_NIL,
        W_TRUE, W_FALSE, W_NIL,
        w_string("hello"), W_FALSE, W_NIL,
    };
    int ntypes = sizeof(types) / sizeof(types[0]);
    for (int i = 0; i < HEAVY_LEN; i++) {
        heavy_values[i] = types[i % ntypes];
    }
    /* Fisher-Yates shuffle with fixed seed matching bench_before.c */
    uint32_t rng = 12345;
    for (int i = HEAVY_LEN - 1; i > 0; i--) {
        rng = rng * 1103515245 + 12345;
        int j = (int)(rng % (uint32_t)(i + 1));
        WValue tmp = heavy_values[i];
        heavy_values[i] = heavy_values[j];
        heavy_values[j] = tmp;
    }
}

static void bench_heavy_truthy(int64_t n) {
    volatile int64_t acc = 0;
    for (int64_t iter = 0; iter < n; iter++) {
        int64_t t = 0;
        for (int i = 0; i < HEAVY_LEN; i++) {
            t += w_truthy_inline(heavy_values[i]);
        }
        acc = t;
    }
}

/*
 * "Tag-checked" truthiness: mimic the old approach but on NaN-boxed values.
 * Forces multiple branches per value to show the misprediction cost.
 */
__attribute__((noinline))
static int64_t w_truthy_tagcheck(WValue v) {
    if (v == W_NIL) return 0;
    if (v == W_FALSE) return 0;
    uint64_t tag = v >> 48;
    if ((tag & 0xFFFF) == (W_TAG_INT >> 48)) return 1;
    if (v >= 0x10 && tag == 0) return 1;             /* object space */
    if ((tag & 0xFFFF) == (W_TAG_STRINGSYM >> 48)) return 1; /* string/symbol */
    if ((tag & 0xFFFF) == (W_TAG_DECIMAL >> 48)) return 1;
    if ((tag & 0xFFFF) == (W_TAG_CHAR >> 48)) return 1;
    return 1;
}

static void bench_heavy_truthy_tagcheck(int64_t n) {
    volatile int64_t acc = 0;
    for (int64_t iter = 0; iter < n; iter++) {
        int64_t t = 0;
        for (int i = 0; i < HEAVY_LEN; i++) {
            t += w_truthy_tagcheck(heavy_values[i]);
        }
        acc = t;
    }
}

/* ---- 23. Heavy truthiness with branching: 8-arg chain, mixed types ---- */

__attribute__((noinline))
static WValue heavy_branch_work(WValue a, WValue b, WValue c, WValue d,
                                 WValue e, WValue f, WValue g, WValue h) {
    WValue result = W_NIL;
    if (w_truthy_inline(a)) {
        if (w_truthy_inline(b)) {
            if (w_truthy_inline(c)) {
                result = d;
            } else if (w_truthy_inline(e)) {
                result = f;
            }
        } else if (w_truthy_inline(g)) {
            result = h;
        }
    }
    return result;
}

static void bench_heavy_branching(int64_t n) {
    /* Rotate through 8-value windows of the shuffled array so the
       branch predictor sees different type mixes each call */
    volatile WValue result;
    int off = 0;
    for (int64_t i = 0; i < n; i++) {
        result = heavy_branch_work(
            heavy_values[(off+0) % HEAVY_LEN],
            heavy_values[(off+1) % HEAVY_LEN],
            heavy_values[(off+2) % HEAVY_LEN],
            heavy_values[(off+3) % HEAVY_LEN],
            heavy_values[(off+4) % HEAVY_LEN],
            heavy_values[(off+5) % HEAVY_LEN],
            heavy_values[(off+6) % HEAVY_LEN],
            heavy_values[(off+7) % HEAVY_LEN]);
        off = (off + 3) % HEAVY_LEN;
    }
}

/* ---- Main ---- */

int main(void) {
    build_walk_codepoints();
    build_heavy_values();

    printf("\n");
    printf("  WValue NaN-boxing benchmark suite\n");
    printf("  ==================================\n\n");

    /* Fast ops: 100M iterations */
    int64_t FAST = 100000000LL;
    /* Slower ops: 10M iterations */
    int64_t SLOW = 10000000LL;

    printf("  --- Core operations ---\n");
    bench("truthiness (rand+clock)",bench_truthy,           SLOW);
    bench("symbol compare (eq)",     bench_symbol_eq,       FAST);
    bench("int increment",           bench_int_inc,         FAST);
    bench("float add",              bench_float_add,       FAST);
    bench("bool negation",          bench_bool_neg,        FAST);
    bench("int type check",         bench_is_int,          FAST);
    bench("double type check",      bench_is_double,       FAST);
    bench("hot loop: if-true-inc",  bench_hot_loop,        FAST);

    printf("\n  --- Decimal ---\n");
    bench("decimal add",            bench_decimal_add,     SLOW);
    bench("decimal mul",            bench_decimal_mul,     SLOW);
    bench("decimal 1000-item total", bench_decimal_accumulate, 10000);

    printf("\n  --- Char & strings ---\n");
    bench("char boxing",            bench_char_box,        SLOW);
    bench("char is_letter",         bench_char_is_letter,  FAST);
    bench("char case_delta",        bench_char_case_delta, FAST);
    bench("string upcase (1000ch)", bench_string_upcase,   100000);
    bench("string downcase (1000ch)", bench_string_downcase, 100000);
    bench("10K codepoint walk",     bench_codepoint_walk,  10000);

    printf("\n  --- Instant ---\n");
    bench("instant boxing",         bench_instant_box,     FAST);
    bench("instant diff",           bench_instant_diff,    FAST);
    bench("instant timeline (1000)", bench_instant_timeline, 100000);

    printf("\n  --- Heavy truthiness (mixed types, branch-hostile) ---\n");
    bench("4K scan: v > 1",        bench_heavy_truthy,          100000);
    bench("4K scan: tag-checked",  bench_heavy_truthy_tagcheck, 100000);
    bench("8-arg branch chain",    bench_heavy_branching,       FAST);

    printf("\n  Done.\n\n");
    return 0;
}

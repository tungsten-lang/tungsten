#include "runtime.h"
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

/* Helper: run a function in a child process, return 1 if it exited non-zero */
static int expect_crash(void (*fn)(void)) {
    pid_t pid = fork();
    if (pid == 0) {
        /* Child: suppress stderr, run function */
        fclose(stderr);
        fn();
        _exit(0);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) != 0;
}

/* Overflow test helpers (must be at file scope for C) */
static void overflow_fn(void) { w_int((1LL << 47)); }
static void underflow_fn(void) { w_int(-(1LL << 47) - 1); }
static void add_overflow_fn(void) { w_add(w_box_int((1LL << 47) - 1), w_box_int(1)); }

/* Helper: extract C string from WValue (rotating buffer for safe strcmp) */
static const char *str_val(WValue v) {
    static char bufs[4][6];
    static int idx = 0;
    char *buf = bufs[idx]; idx = (idx + 1) & 3;
    const char *out; size_t len;
    w_str_data(v, buf, &out, &len);
    return out;
}

int main() {
    printf("=== NaN-boxing round-trip tests ===\n");

    /* Test nil */
    {
        WValue v = w_nil();
        assert(v == W_NIL);
        assert(w_is_nil(v));
        assert(!w_truthy(v));
        printf("  nil: OK\n");
    }

    /* Test false */
    {
        WValue v = w_bool(0);
        assert(v == W_FALSE);
        assert(w_is_bool(v));
        assert(!w_is_nil(v));
        assert(!w_truthy(v));
        printf("  false: OK\n");
    }

    /* Test true */
    {
        WValue v = w_bool(1);
        assert(v == W_TRUE);
        assert(w_is_bool(v));
        assert(w_truthy(v));
        printf("  true: OK\n");
    }

    /* Test int boxing/unboxing */
    {
        int64_t vals[] = {0, 1, -1, 42, -42, 100000, -100000,
                          (1LL << 47) - 1,  /* INT48_MAX */
                          -(1LL << 47)};     /* INT48_MIN */
        for (int i = 0; i < 9; i++) {
            WValue v = w_int(vals[i]);
            assert(w_is_int(v));
            assert(!w_is_nil(v));
            assert(!w_is_double(v));
            assert(w_truthy(v));
            int64_t out = w_as_int(v);
            if (out != vals[i]) {
                printf("  int %lld: FAIL (got %lld)\n", (long long)vals[i], (long long)out);
                return 1;
            }
        }
        printf("  int round-trip: OK\n");
    }

    /* Test double boxing/unboxing */
    {
        double vals[] = {0.0, -0.0, 1.0, -1.0, 3.14159, 1e100, -1e100,
                         1.0/0.0,   /* +Inf */
                         -1.0/0.0}; /* -Inf */
        for (int i = 0; i < 9; i++) {
            WValue v = w_float(vals[i]);
            assert(w_is_double(v));
            assert(!w_is_int(v));
            assert(!w_is_nil(v));
            assert(w_truthy(v));
            double out = w_as_double(v);
            if (out != vals[i] && !(isnan(out) && isnan(vals[i]))) {
                printf("  double %g: FAIL (got %g)\n", vals[i], out);
                return 1;
            }
        }
        printf("  double round-trip: OK\n");
    }

    /* Test NaN -> biased NaN in double space */
    {
        uint64_t nan_patterns[] = {
            0x7FF0000000000001ULL,  /* +sNaN */
            0xFFF0000000000001ULL,  /* -sNaN */
            0x7FF8000000000000ULL,  /* +qNaN (canonical) */
            0xFFF8000000000000ULL,  /* -qNaN */
            0x7FFFFFFFFFFFFFFFULL,  /* +qNaN max payload */
            0xFFFFFFFFFFFFFFFFULL,  /* -qNaN max payload */
        };
        for (int i = 0; i < 6; i++) {
            double d;
            memcpy(&d, &nan_patterns[i], sizeof(double));
            WValue v = w_float(d);
            assert(v == W_BIASED_NAN);
            assert(w_is_nan(v));
            assert(w_is_double(v));  /* NaN IS a double now */
        }
        /* w_as_double(W_BIASED_NAN) returns a quiet NaN */
        double out = w_as_double(W_BIASED_NAN);
        assert(isnan(out));
        /* NaN != NaN (IEEE 754) */
        assert(w_eq(W_BIASED_NAN, W_BIASED_NAN) == W_FALSE);
        printf("  NaN -> biased NaN (double space): OK\n");
    }

    /* Test string */
    {
        WValue v = w_string("hello");
        assert(w_is_string(v));
        assert(!w_is_int(v));
        assert(w_truthy(v));
        const char *s = str_val(v);
        assert(strcmp(s, "hello") == 0);
        printf("  string: OK\n");
    }

    /* Test symbol interning */
    {
        WValue s1 = w_symbol("foo");
        WValue s2 = w_symbol("foo");
        WValue s3 = w_symbol("bar");
        assert(s1 == s2);  /* same symbol = same WValue */
        assert(s1 != s3);  /* different symbols = different WValue */
        assert(w_is_symbol(s1));
        assert(w_truthy(s1));
        printf("  symbol interning: OK\n");
    }

    /* Test array */
    {
        WValue arr = w_array_new_empty();
        assert(w_is_array(arr));
        assert(w_is_obj(arr));
        w_array_push(arr, w_int(10));
        w_array_push(arr, w_int(20));
        w_array_push(arr, w_int(30));
        assert(w_as_int(w_array_size(arr)) == 3);
        assert(w_as_int(w_array_get(arr, w_int(0))) == 10);
        assert(w_as_int(w_array_get(arr, w_int(1))) == 20);
        assert(w_as_int(w_array_get(arr, w_int(2))) == 30);
        printf("  array: OK\n");
    }

    /* Test arithmetic */
    {
        WValue a = w_int(7), b = w_int(3);
        assert(w_as_int(w_add(a, b)) == 10);
        assert(w_as_int(w_sub(a, b)) == 4);
        assert(w_as_int(w_mul(a, b)) == 21);
        assert(w_as_int(w_div(a, b)) == 2);
        assert(w_as_int(w_mod(a, b)) == 1);
        assert(w_as_int(w_neg(a)) == -7);
        printf("  int arithmetic: OK\n");
    }

    /* Test float arithmetic */
    {
        WValue a = w_float(3.5), b = w_float(1.5);
        assert(w_as_double(w_add(a, b)) == 5.0);
        assert(w_as_double(w_sub(a, b)) == 2.0);
        assert(w_as_double(w_mul(a, b)) == 5.25);
        printf("  float arithmetic: OK\n");
    }

    /* Test comparison */
    {
        assert(w_eq(w_int(5), w_int(5)) == W_TRUE);
        assert(w_eq(w_int(5), w_int(6)) == W_FALSE);
        assert(w_eq(w_int(1), w_float(1.0)) == W_TRUE);   /* numeric == coerces int/float (3d126ac5) */
        assert(w_eq(w_float(1.0), w_int(1)) == W_TRUE);
        assert(w_eq(w_float(0.0), w_float(-0.0)) == W_TRUE);
        assert(w_lt(w_int(3), w_int(5)) == W_TRUE);
        assert(w_gt(w_int(5), w_int(3)) == W_TRUE);
        assert(w_eq(W_NIL, W_NIL) == W_TRUE);
        assert(w_eq(W_TRUE, W_TRUE) == W_TRUE);
        assert(w_eq(W_FALSE, W_FALSE) == W_TRUE);
        assert(w_neq(W_TRUE, W_FALSE) == W_TRUE);
        printf("  comparison: OK\n");
    }

    /* Test string comparison */
    {
        WValue a = w_string("hello");
        WValue b = w_string("hello");
        WValue c = w_string("world");
        assert(w_eq(a, b) == W_TRUE);   /* same content */
        assert(w_eq(a, c) == W_FALSE);  /* different content */
        printf("  string comparison: OK\n");
    }

    /* Test truthiness */
    {
        assert(!w_truthy(W_NIL));
        assert(!w_truthy(W_FALSE));
        assert(w_truthy(W_TRUE));
        assert(w_truthy(w_int(0)));      /* 0 is truthy in Tungsten */
        assert(w_truthy(w_int(1)));
        assert(w_truthy(w_int(-1)));
        assert(w_truthy(w_float(0.0)));  /* 0.0 is truthy */
        assert(w_truthy(w_string("")));  /* "" is truthy */
        assert(w_truthy(w_array_new_empty())); /* [] is truthy */
        printf("  truthiness: OK\n");
    }

    /* Test class/object */
    {
        WValue klass = w_class_new("Dog", W_NIL);
        assert(w_is_class(klass));
        WValue obj = w_object_new(klass);
        assert(w_is_instance(obj));
        w_ivar_set(obj, "@name", w_string("Rex"));
        WValue name = w_ivar_get(obj, "@name");
        assert(w_is_string(name));
        assert(strcmp(str_val(name), "Rex") == 0);
        printf("  class/object: OK\n");
    }

    /* Test closure */
    {
        WValue cl = w_closure_new((void *)(uintptr_t)0x1234, NULL, 0);
        assert(w_is_closure(cl));
        assert(w_is_obj(cl));
        printf("  closure: OK\n");
    }

    /* Test to_s */
    {
        assert(strcmp(str_val(w_to_s(w_int(42))), "42") == 0);
        assert(strcmp(str_val(w_to_s(W_TRUE)), "true") == 0);
        assert(strcmp(str_val(w_to_s(W_FALSE)), "false") == 0);
        assert(strcmp(str_val(w_to_s(W_NIL)), "") == 0);
        printf("  to_s: OK\n");
    }

    /* Test memo */
    {
        void *table = w_memo_init(NULL);
        WValue args[2] = {w_int(5), w_int(10)};
        WValue result = w_memo_lookup(table, args, 2);
        assert(result == W_MEMO_MISS);
        w_memo_store(table, args, 2, w_int(15));
        result = w_memo_lookup(table, args, 2);
        assert(result != W_MEMO_MISS);
        assert(w_as_int(result) == 15);
        printf("  memoization: OK\n");
    }

    /* Test negative int edge cases */
    {
        WValue v = w_int(-1);
        assert(w_as_int(v) == -1);
        v = w_int(-100);
        assert(w_as_int(v) == -100);
        v = w_int(-(1LL << 47));
        assert(w_as_int(v) == -(1LL << 47));
        printf("  negative int edge cases: OK\n");
    }

    /* Test WValue size */
    {
        assert(sizeof(WValue) == 8);
        printf("  sizeof(WValue) = %zu (was 16): OK\n", sizeof(WValue));
    }

    /* Type collision detection */
    {
        WValue vals[] = {
            W_NIL, W_FALSE, W_TRUE, W_UNDEF,
            w_int(0), w_int(1), w_int(-1),
            w_float(0.0), w_float(1.0), w_float(-1.0),
            w_float(1.0/0.0), w_float(-1.0/0.0),
            w_string("test"),
            w_array_new_empty(),
            w_decimal(100, -2),
            w_box_char('A'),
            w_symbol("sym"),
            w_box_instant(12345),
        };
        const char *names[] = {
            "nil", "false", "true", "undef",
            "int(0)", "int(1)", "int(-1)",
            "float(0)", "float(1)", "float(-1)",
            "float(+inf)", "float(-inf)",
            "string", "array",
            "decimal", "char",
            "symbol", "instant",
        };
        int n = 18;
        for (int i = 0; i < n; i++) {
            int types = w_is_nil(vals[i]) + w_is_bool(vals[i]) +
                        w_is_undef(vals[i]) +
                        w_is_int(vals[i]) + w_is_double(vals[i]) +
                        w_is_string(vals[i]) + w_is_obj(vals[i]) +
                        w_is_symbol(vals[i]) +
                        w_is_decimal(vals[i]) + w_is_char(vals[i]) +
                        w_is_instant(vals[i]);
            if (types != 1) {
                printf("  COLLISION: %s matches %d types!\n", names[i], types);
                return 1;
            }
        }
        printf("  type collision detection: OK\n");
    }

    /* Double bias boundary proof table */
    {
        struct { double d; const char *name; uint64_t raw; } bias_cases[] = {
            { 0.0,      "+0",   0x0000000000000000ULL },
            { -0.0,     "-0",   0x8000000000000000ULL },
            { 1.0/0.0,  "+Inf", 0x7FF0000000000000ULL },
            { -1.0/0.0, "-Inf", 0xFFF0000000000000ULL },
        };
        for (int i = 0; i < 4; i++) {
            WValue v = w_box_double(bias_cases[i].d);
            uint64_t biased = bias_cases[i].raw + W_DOUBLE_BIAS;
            if (v != biased) {
                printf("  double bias %s: FAIL (v=0x%016llx expected=0x%016llx)\n",
                       bias_cases[i].name, (unsigned long long)v, (unsigned long long)biased);
                return 1;
            }
            assert(w_is_double(v));
            assert(!w_is_int(v) && !w_is_nil(v) && !w_is_obj(v));
            double out = w_as_double(v);
            /* -0.0 == 0.0 in C, so use memcmp for sign bit */
            uint64_t out_bits, orig_bits;
            memcpy(&out_bits, &out, 8);
            memcpy(&orig_bits, &bias_cases[i].d, 8);
            assert(out_bits == orig_bits);
        }
        printf("  double bias proof table: OK\n");
    }

    /* Denormal doubles round-trip */
    {
        double denormals[] = {
            5e-324,           /* smallest positive denormal */
            -5e-324,          /* smallest negative denormal */
            2.2250738585072009e-308, /* largest denormal */
            -2.2250738585072009e-308,
        };
        for (int i = 0; i < 4; i++) {
            WValue v = w_box_double(denormals[i]);
            assert(w_is_double(v));
            double out = w_as_double(v);
            uint64_t out_bits, orig_bits;
            memcpy(&out_bits, &out, 8);
            memcpy(&orig_bits, &denormals[i], 8);
            assert(out_bits == orig_bits);
        }
        printf("  denormal double round-trip: OK\n");
    }

    /* INT48 boundary: MAX works, MAX+1 would overflow (tested in step 7) */
    {
        int64_t max48 = (1LL << 47) - 1;   /* 140737488355327 */
        int64_t min48 = -(1LL << 47);       /* -140737488355328 */
        WValue vmax = w_box_int(max48);
        WValue vmin = w_box_int(min48);
        assert(w_as_int(vmax) == max48);
        assert(w_as_int(vmin) == min48);
        /* Verify these are correctly tagged */
        assert((vmax & W_TAG_MASK) == W_TAG_INT);
        assert((vmin & W_TAG_MASK) == W_TAG_INT);
        printf("  INT48 boundary: OK\n");
    }

    /* Exhaustive NaN collision: biased doubles must not land in tag space */
    {
        /* Every IEEE 754 double, when biased, must either:
           - fall in the double range [0x0001..., 0xFFF8...]
           - or be a NaN that gets canonicalized first
           Check that no valid (non-NaN) double biases into 0xFFF9-0xFFFF */
        uint64_t tag_prefixes[] = {
            0xFFF9000000000000ULL, 0xFFFA000000000000ULL,
            0xFFFB000000000000ULL, 0xFFFC000000000000ULL,
            0xFFFD000000000000ULL, 0xFFFE000000000000ULL,
            0xFFFF000000000000ULL,
        };
        for (int t = 0; t < 7; t++) {
            /* If a raw double + BIAS == this tag prefix, that raw would be: */
            uint64_t raw = tag_prefixes[t] - W_DOUBLE_BIAS;
            /* Check: is this raw value a NaN? It must be, otherwise collision */
            int is_nan = ((raw & 0x7FF0000000000000ULL) == 0x7FF0000000000000ULL) &&
                         ((raw & 0x000FFFFFFFFFFFFFULL) != 0);
            assert(is_nan); /* If not NaN, we have a collision! */
        }
        printf("  NaN collision proof (tag prefixes): OK\n");
    }

    /* Decimal round-trip and normalization */
    {
        /* $499.99 = sig 49999, scale -2 */
        WValue v = w_decimal(49999, -2);
        assert(w_is_decimal(v));
        assert(!w_is_int(v));
        assert(!w_is_double(v));
        assert(w_truthy(v));
        int64_t sig = w_unbox_decimal_sig(v);
        int scale = w_unbox_decimal_scale(v);
        assert(sig == 49999);
        assert(scale == -2);

        /* Normalization: 1000 scale -1 -> 100 scale 0 -> 1 scale 2 */
        WValue v2 = w_decimal(1000, -1);
        assert(w_unbox_decimal_sig(v2) == 1);
        assert(w_unbox_decimal_scale(v2) == 2);

        /* Negative decimal */
        WValue v3 = w_decimal(-12345, -3);
        assert(w_unbox_decimal_sig(v3) == -12345);
        assert(w_unbox_decimal_scale(v3) == -3);

        /* Zero normalizes to sig=0 scale=0 */
        WValue v4 = w_decimal(0, -5);
        assert(w_unbox_decimal_sig(v4) == 0);
        assert(w_unbox_decimal_scale(v4) == 0);

        printf("  decimal round-trip: OK\n");
    }

    /* Decimal arithmetic */
    {
        WValue a = w_decimal(100, -2);  /* 1.00 */
        WValue b = w_decimal(250, -2);  /* 2.50 */

        /* add: 1.00 + 2.50 = 3.50 */
        WValue sum = w_decimal_add(a, b);
        assert(w_unbox_decimal_sig(sum) == 35);
        assert(w_unbox_decimal_scale(sum) == -1);

        /* sub: 2.50 - 1.00 = 1.50 */
        WValue diff = w_decimal_sub(b, a);
        assert(w_unbox_decimal_sig(diff) == 15);
        assert(w_unbox_decimal_scale(diff) == -1);

        /* mul: 1.00 * 2.50 = 2.50 */
        WValue prod = w_decimal_mul(a, b);
        int64_t prod_sig = w_unbox_decimal_sig(prod);
        int prod_scale = w_unbox_decimal_scale(prod);
        /* 1 * 25 = 25, scale = 0 + -1 = -1. 25 * 10^-1 = 2.5 */
        assert(prod_sig == 25);
        assert(prod_scale == -1);

        /* Decimal comparison */
        assert(w_lt(a, b) == W_TRUE);
        assert(w_gt(b, a) == W_TRUE);
        assert(w_eq(a, a) == W_TRUE);

        /* Decimal in w_add/w_sub/w_mul/w_div */
        assert(w_is_decimal(w_add(a, b)));
        assert(w_is_decimal(w_sub(b, a)));
        assert(w_is_decimal(w_mul(a, b)));
        assert(w_is_decimal(w_div(b, a)));

        /* Decimal to_s */
        WValue s = w_to_s(w_decimal(49999, -2));
        assert(strcmp(str_val(s), "499.99") == 0);

        WValue s2 = w_to_s(w_decimal(5, 2));
        assert(strcmp(str_val(s2), "500") == 0);

        printf("  decimal arithmetic: OK\n");
    }

    /* Decimal edge cases (39-bit sig after 2-bit subtype added) */
    {
        /* Max significand (39-bit: 2^38 - 1) */
        int64_t max_sig = (1LL << 38) - 1;
        assert(w_decimal_fits(max_sig, 0));
        WValue v = w_decimal(max_sig, 0);
        assert(w_unbox_decimal_sig(v) == max_sig);

        /* Old 41-bit range no longer fits */
        assert(!w_decimal_fits((1LL << 40) - 1, 0));

        /* Min significand */
        int64_t min_sig = -(1LL << 38);
        assert(w_decimal_fits(min_sig, 0));
        WValue v2 = w_decimal(min_sig, 0);
        assert(w_unbox_decimal_sig(v2) == min_sig);

        /* Max/min scale */
        assert(w_decimal_fits(1, 63));
        assert(w_decimal_fits(1, -64));
        WValue v3 = w_decimal(1, 63);
        assert(w_unbox_decimal_scale(v3) == 63);
        WValue v4 = w_decimal(1, -64);
        assert(w_unbox_decimal_scale(v4) == -64);

        printf("  decimal edge cases: OK\n");
    }

    /* Instant round-trip */
    {
        /* Unix epoch */
        WValue v = w_box_instant(0);
        assert(w_is_instant(v));
        assert(w_truthy(v));
        assert(w_unbox_instant(v) == 0);

        /* Positive timestamp: 2024-01-01T00:00:00Z = 1704067200000ms */
        int64_t ts = 1704067200000LL;
        WValue v2 = w_box_instant(ts);
        assert(w_is_instant(v2));
        assert(w_unbox_instant(v2) == ts);

        /* Negative timestamp (before epoch) */
        int64_t neg_ts = -86400000LL; /* 1969-12-31 */
        WValue v3 = w_box_instant(neg_ts);
        assert(w_unbox_instant(v3) == neg_ts);

        printf("  instant round-trip: OK\n");
    }

    /* Instant now() and arithmetic */
    {
        WValue now = w_instant_now();
        assert(w_is_instant(now));
        int64_t ms = w_unbox_instant(now);
        /* Should be after 2024 and before 2100 */
        assert(ms > 1704067200000LL);
        assert(ms < 4102444800000LL);

        /* instant + int -> instant */
        WValue later = w_add(now, w_int(1000));
        assert(w_is_instant(later));
        assert(w_unbox_instant(later) == ms + 1000);

        /* instant - instant -> duration (ns) */
        WValue diff = w_sub(later, now);
        assert(w_is_duration(diff));
        assert(w_duration_mode(diff) == 0);
        assert(w_unbox_duration_ns(diff) == 1000000000LL); /* 1000ms = 1e9 ns */

        /* instant - int -> instant */
        WValue earlier = w_sub(now, w_int(500));
        assert(w_is_instant(earlier));
        assert(w_unbox_instant(earlier) == ms - 500);

        /* instant comparison */
        assert(w_lt(now, later) == W_TRUE);
        assert(w_gt(later, now) == W_TRUE);
        assert(w_eq(now, now) == W_TRUE);

        printf("  instant now/arithmetic: OK\n");
    }

    /* Instant to_s */
    {
        WValue v = w_box_instant(1704067200000LL);
        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "1704067200000") == 0);

        WValue v2 = w_box_instant(0);
        WValue s2 = w_to_s(v2);
        assert(strcmp(str_val(s2), "0") == 0);

        printf("  instant to_s: OK\n");
    }

    /* Char boxing/unboxing */
    {
        /* ASCII 'A' */
        WValue v = w_box_char('A');
        assert(w_is_char(v));
        assert(!w_is_int(v));
        assert(!w_is_string(v));
        assert(w_truthy(v));
        assert(w_char_codepoint(v) == 'A');
        assert(w_char_is_ascii(v));
        assert(w_char_is_letter(v));
        assert(w_char_is_upper(v));
        assert(!w_char_is_lower(v));
        assert(w_char_is_printable(v));
        assert(w_char_utf8_len(v) == 1);

        /* Case delta: A->a = +32 */
        int delta = w_char_case_delta(v);
        assert(delta == 32);

        /* ASCII 'a' */
        WValue va = w_box_char('a');
        assert(w_char_is_lower(va));
        assert(w_char_case_delta(va) == -32);

        /* Digit '5' */
        WValue v5 = w_box_char('5');
        assert(w_char_is_digit(v5));
        assert(w_char_digit_value(v5) == 5);

        /* Non-digit letter */
        assert(w_char_digit_value(v) == -1);

        printf("  char ASCII: OK\n");
    }

    /* Char Unicode */
    {
        /* Euro sign U+20AC */
        WValue v = w_box_char(0x20AC);
        assert(w_char_codepoint(v) == 0x20AC);
        assert(!w_char_is_ascii(v));
        assert(w_char_is_printable(v));
        assert(w_char_utf8_len(v) == 3);

        /* Max codepoint U+10FFFF */
        WValue vmax = w_box_char(0x10FFFF);
        assert(w_char_codepoint(vmax) == 0x10FFFF);
        assert(w_char_utf8_len(vmax) == 4);

        /* Surrogate (invalid) -> replaced with U+FFFD */
        WValue vsur = w_box_char(0xD800);
        assert(w_char_codepoint(vsur) == 0xD800); /* table still stores it */

        /* CJK ideograph (fullwidth) */
        WValue vcjk = w_box_char(0x4E00); /* one */
        assert(w_char_width(vcjk) == 2);

        printf("  char Unicode: OK\n");
    }

    /* Char to_s */
    {
        WValue v = w_box_char('A');
        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "A") == 0);

        WValue v2 = w_box_char(0x20AC); /* euro */
        WValue s2 = w_to_s(v2);
        assert(strcmp(str_val(s2), "\xe2\x82\xac") == 0);

        printf("  char to_s: OK\n");
    }

    /* Char arithmetic */
    {
        /* char + int -> char */
        WValue a = w_box_char('A');
        WValue b = w_add(a, w_int(1));
        assert(w_is_char(b));
        assert(w_char_codepoint(b) == 'B');

        /* char - char -> int */
        WValue diff = w_sub(w_box_char('z'), w_box_char('a'));
        assert(w_is_int(diff));
        assert(w_as_int(diff) == 25);

        /* char - int -> char */
        WValue c = w_sub(w_box_char('Z'), w_int(1));
        assert(w_is_char(c));
        assert(w_char_codepoint(c) == 'Y');

        printf("  char arithmetic: OK\n");
    }

    /* Integer overflow promotion to bigint */
    {
        /* INT48_MAX works fine */
        int64_t max48 = (1LL << 47) - 1;
        WValue v = w_int(max48);
        assert(w_as_int(v) == max48);

        /* INT48_MAX + 1 promotes to bigint */
        WValue ov = w_int(1LL << 47);
        assert(w_is_integer_any(ov));
        assert(!w_is_int(ov));  /* not inline i48 */

        /* INT48_MIN - 1 promotes to bigint */
        WValue uv = w_int(-(1LL << 47) - 1);
        assert(w_is_integer_any(uv));
        assert(!w_is_int(uv));

        /* Arithmetic overflow: INT48_MAX + 1 via w_add promotes to bigint */
        WValue av = w_add(w_box_int((1LL << 47) - 1), w_box_int(1));
        assert(w_is_integer_any(av));
        assert(!w_is_int(av));

        printf("  integer overflow promotion: OK\n");
    }

    /* Pointer alignment: w_as_ptr strips sub-tag correctly */
    {
        /* Simulate a 16-byte aligned pointer */
        uintptr_t fake_ptr = 0x0000000012345670ULL; /* low 4 bits = 0 */
        WValue v = (fake_ptr & ~0xFULL) | W_SUBTAG_ARRAY;
        assert(w_is_array(v));
        void *out = w_as_ptr(v);
        assert((uintptr_t)out == fake_ptr);
        /* Verify sub-tag didn't corrupt the pointer */
        assert(((uintptr_t)out & 0xF) == 0);
        printf("  pointer alignment: OK\n");
    }

    /* Inline string round-trip */
    {
        const char *tests[] = {"", "a", "ab", "abc", "abcd", "abcde"};
        for (int i = 0; i < 6; i++) {
            WValue v = w_string(tests[i]);
            assert(w_is_string(v));
            assert(w_is_inline_str(v));
            assert(!w_is_heap_str(v));
            assert(strcmp(str_val(v), tests[i]) == 0);
        }
        printf("  inline string round-trip: OK\n");
    }

    /* Slab string round-trip (6-61 bytes go to slab) */
    {
        WValue v = w_string("hello world");
        WValue vmax = w_string("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789");
        assert(w_is_string(v));
        assert(w_is_slab(v));
        assert(!w_is_inline(v));
        assert(strcmp(str_val(v), "hello world") == 0);
        assert(w_is_string(vmax));
        assert(w_is_slab(vmax));
        assert(!w_is_inline(vmax));
        assert(strcmp(str_val(vmax), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789") == 0);
        printf("  slab string round-trip: OK\n");
    }

    /* Negative int comparison regression */
    {
        assert(w_lt(w_int(-1), w_int(0)) == W_TRUE);
        assert(w_lt(w_int(0), w_int(-1)) == W_FALSE);
        assert(w_lt(w_int(W_INT48_MIN), w_int(W_INT48_MAX)) == W_TRUE);
        assert(w_gt(w_int(W_INT48_MAX), w_int(W_INT48_MIN)) == W_TRUE);
        assert(w_lt(w_int(-100), w_int(-50)) == W_TRUE);
        printf("  negative int comparison: OK\n");
    }

    /* Instant separate tag */
    {
        WValue inst = w_box_instant(42);
        WValue intv = w_int(42);
        assert(w_is_instant(inst));
        assert(!w_is_int(inst));
        assert(w_is_int(intv));
        assert(!w_is_instant(intv));
        assert(w_unbox_instant(inst) == 42);
        printf("  instant separate tag: OK\n");
    }

    /* Char subtype check */
    {
        WValue v = w_box_char('A');
        /* Char subtype is 3 (W_LEXICAL_CHAR) */
        assert(w_is_char(v));
        assert(!w_is_token(v));
        assert(!w_is_lexchar(v));
        assert(!w_is_slice(v));
        printf("  char subtype: OK\n");
    }

    /* Symbol round-trip */
    {
        WValue s1 = w_symbol("alpha");
        WValue s2 = w_symbol("beta");
        WValue s3 = w_symbol("alpha");
        assert(w_is_symbol(s1));
        assert(w_is_symbol(s2));
        assert(!w_is_string(s1));
        assert(s1 == s3);
        assert(s1 != s2);
        printf("  symbol round-trip: OK\n");
    }

    /* Currency round-trip */
    {
        WValue v = w_currency(0, 525, -2);   /* $5.25 */
        assert(w_is_currency(v));
        assert(!w_is_int(v));
        assert(!w_is_decimal(v));
        assert(w_unbox_currency_symbol(v) == 0);
        assert(w_unbox_currency_sig(v) == 525);
        assert(w_unbox_currency_scale(v) == -2);

        /* Euro: w_currency normalizes 1000,-2 → 1,1 (1000/10^3, scale -2+3=1) */
        WValue e = w_currency(1, 1000, -2);  /* €10.00 */
        assert(w_unbox_currency_symbol(e) == 1);
        /* Normalized: sig=1, scale=1 (1 * 10^1 = 10) */
        assert(w_unbox_currency_sig(e) == 1);
        assert(w_unbox_currency_scale(e) == 1);

        printf("  currency round-trip: OK\n");
    }

    /* Currency arithmetic */
    {
        WValue a = w_currency(0, 525, -2);   /* $5.25 */
        WValue b = w_currency(0, 375, -2);   /* $3.75 */

        WValue sum = w_add(a, b);
        assert(w_is_currency(sum));
        /* $5.25 + $3.75 = $9.00, normalized to sig=9, scale=0 */
        assert(w_unbox_currency_symbol(sum) == 0);

        WValue diff = w_sub(a, b);
        assert(w_is_currency(diff));
        assert(w_unbox_currency_sig(diff) == 15);
        assert(w_unbox_currency_scale(diff) == -1);

        /* Currency to_s: always 2+ decimals */
        WValue s = w_to_s(sum);
        assert(strcmp(str_val(s), "$9.00") == 0);

        WValue sd = w_to_s(diff);
        assert(strcmp(str_val(sd), "$1.50") == 0);

        printf("  currency arithmetic: OK\n");
    }

    /* Quantity round-trip */
    {
        WValue v = w_quantity(1, 3, 0);      /* 3 kg */
        assert(w_is_quantity(v));
        assert(!w_is_currency(v));
        assert(w_unbox_quantity_unit(v) == 1);
        assert(w_unbox_quantity_sig(v) == 3);
        assert(w_unbox_quantity_scale(v) == 0);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "3 kg") == 0);

        /* Percentage */
        WValue pct = w_quantity(255, 765, -2);  /* 7.65% */
        assert(w_unbox_quantity_unit(pct) == 255);
        WValue ps = w_to_s(pct);
        assert(strcmp(str_val(ps), "7.65%") == 0);

        printf("  quantity round-trip: OK\n");
    }

    /* Quantity arithmetic */
    {
        WValue a = w_quantity(1, 5, 0);      /* 5 kg */
        WValue b = w_quantity(1, 3, 0);      /* 3 kg */
        WValue sum = w_add(a, b);
        assert(w_is_quantity(sum));
        assert(w_unbox_quantity_sig(sum) == 8);

        WValue diff = w_sub(a, b);
        assert(w_is_quantity(diff));
        assert(w_unbox_quantity_sig(diff) == 2);

        printf("  quantity arithmetic: OK\n");
    }

    /* Expanded Ruby unit registry (IDs above the inline 8-bit range). */
    {
        WValue hour = w_quantity_parse(w_string("1"), w_string("hours"));
        assert(w_is_domain_obj(hour));
        assert(strcmp(str_val(w_to_s(hour)), "1 h") == 0);

        WValue minutes = w_quantity_pipe(hour, w_string("min"), W_NIL);
        assert(strcmp(str_val(w_to_s(minutes)), "60 min") == 0);

        WValue psi = w_quantity_parse(w_string("1"), w_string("psi"));
        WValue pa = w_quantity_pipe(psi, w_string("Pa"), W_NIL);
        assert(strcmp(str_val(w_to_s(pa)), "6894.757 Pa") == 0);

        WValue ev = w_quantity_parse(w_string("1"), w_string("eV"));
        WValue joules = w_quantity_pipe(ev, w_string("J"), W_NIL);
        WValue ev_roundtrip = w_quantity_pipe(joules, w_string("eV"), W_NIL);
        assert(strcmp(str_val(w_to_s(ev_roundtrip)), "1 eV") == 0);

        printf("  expanded quantity registry: OK\n");
    }

    /* Semantic kinds, temperature points/deltas, and modern quantities. */
    {
        WValue c30 = w_quantity_parse(w_string("30"), w_string("°C"));
        WValue f68 = w_quantity_parse(w_string("68"), w_string("°F"));
        WValue delta = w_quantity_sub(c30, f68);
        assert(strcmp(str_val(w_to_s(delta)), "10 Δ°C") == 0);

        WValue c20 = w_quantity_parse(w_string("20"), w_string("°C"));
        WValue df18 = w_quantity_parse(w_string("18"), w_string("Δ°F"));
        assert(strcmp(str_val(w_to_s(w_quantity_add(c20, df18))), "30 °C") == 0);
        assert(strcmp(str_val(w_to_s(w_quantity_add(df18, c20))), "30 °C") == 0);

        WValue glucose = w_quantity_parse(w_string("100"), w_string("mg/dL_glucose"));
        WValue mmol = w_quantity_pipe(glucose, w_string("mmol/L_glucose"), W_NIL);
        assert(strcmp(str_val(w_to_s(mmol)), "5.55075 mmol/L_glucose") == 0);

        WValue dppx = w_quantity_parse(w_string("1"), w_string("dppx"));
        WValue dpi = w_quantity_pipe(dppx, w_string("dpi"), W_NIL);
        assert(strcmp(str_val(w_to_s(dpi)), "96 dpi") == 0);

        WValue nit = w_quantity_parse(w_string("1"), w_string("nit"));
        WValue candela_area = w_quantity_pipe(nit, w_string("cd/m²"), W_NIL);
        assert(strcmp(str_val(w_to_s(candela_area)), "1 cd/m²") == 0);

        printf("  semantic and contextual quantities: OK\n");
    }

    /* PB + J is shared by the Ruby and compiled runtimes. */
    {
        WValue pb = w_quantity_parse(w_string("1"), w_string("PB"));
        WValue joule = w_quantity_parse(w_string("1"), w_string("J"));
        WValue sandwich = w_quantity_add(pb, joule);
        assert(w_is_string(sandwich));
        assert(strstr(str_val(sandwich), "It's peanut butter jelly time!") != NULL);
        printf("  PB + J sandwich: OK\n");
    }

    /* Duration ns mode */
    {
        WValue v = w_duration_ns(1500);      /* 1.500µs */
        assert(w_is_duration(v));
        assert(w_duration_mode(v) == 0);
        assert(w_unbox_duration_ns(v) == 1500);

        printf("  duration ns mode: OK\n");
    }

    /* Duration months+ms mode */
    {
        WValue v = w_duration_months_ms(3, 7200000);  /* 3mo + 2h */
        assert(w_is_duration(v));
        assert(w_duration_mode(v) == 1);
        assert(w_unbox_duration_months(v) == 3);
        assert(w_unbox_duration_ms(v) == 7200000);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "3mo2h") == 0);

        printf("  duration months+ms mode: OK\n");
    }

    /* Duration arithmetic */
    {
        WValue a = w_duration_months_ms(0, 9000000);  /* 2h30m */
        WValue b = w_duration_months_ms(0, 3600000);  /* 1h */
        WValue sum = w_add(a, b);
        assert(w_is_duration(sum));
        assert(w_unbox_duration_ms(sum) == 12600000);  /* 3h30m */

        WValue s = w_to_s(sum);
        assert(strcmp(str_val(s), "3h30m") == 0);

        printf("  duration arithmetic: OK\n");
    }

    /* Packed type: Color */
    {
        WValue v = w_color(255, 0, 128, 255);
        assert(w_is_packed(v));
        assert(w_packed_subtype(v) == W_PACKED_COLOR);
        assert(w_unbox_color_r(v) == 255);
        assert(w_unbox_color_g(v) == 0);
        assert(w_unbox_color_b(v) == 128);
        assert(w_unbox_color_a(v) == 255);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "#FF0080") == 0);  /* alpha omitted when 0xFF */

        /* Also test with non-opaque alpha */
        WValue v2 = w_color(255, 0, 128, 200);
        WValue s2 = w_to_s(v2);
        assert(strcmp(str_val(s2), "#FF0080C8") == 0);

        printf("  packed color: OK\n");
    }

    /* Packed type: Date */
    {
        WValue v = w_date(2026, 3, 25, 14, 30, 0, 0);
        assert(w_is_packed(v));
        assert(w_packed_subtype(v) == W_PACKED_DATE);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "2026-03-25T14:30:00Z") == 0);

        printf("  packed date: OK\n");
    }

    /* Packed type: IPv4 */
    {
        WValue v = w_ipv4(192, 168, 1, 1, 24);
        assert(w_is_packed(v));
        assert(w_packed_subtype(v) == W_PACKED_IPV4);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "192.168.1.1/24") == 0);

        printf("  packed ipv4: OK\n");
    }

    /* Packed type: AST Body — both fields retain their documented maxima. */
    {
        WValue v = w_box_body((uint32_t)W_BODY_OFFSET_MASK,
                              (uint32_t)W_BODY_LENGTH_MASK);
        assert(w_is_body(v));
        assert(w_unbox_body_offset(v) == (uint32_t)W_BODY_OFFSET_MASK);
        assert(w_unbox_body_length(v) == (uint32_t)W_BODY_LENGTH_MASK);

        printf("  packed body limits: OK\n");
    }

    /* Packed type: Rational */
    {
        WValue v = w_rational(22, 7);
        assert(w_is_packed(v));
        assert(w_packed_subtype(v) == W_PACKED_RATIONAL);

        WValue s = w_to_s(v);
        assert(strcmp(str_val(s), "22/7") == 0);

        printf("  packed rational: OK\n");
    }

    /* Packed type: Complex */
    {
        WValue a = w_complex(2, 0, 3, 0);      /* 2+3i */
        WValue b = w_complex(4, 0, -5, 0);     /* 4-5i */
        assert(w_is_packed(a));
        assert(w_packed_subtype(a) == W_PACKED_COMPLEX);

        WValue s = w_to_s(a);
        assert(strcmp(str_val(s), "2+3i") == 0);

        WValue sum = w_add(a, b);
        assert(w_is_complex(sum));
        assert(w_unbox_complex_real_sig(sum) == 6);
        assert(w_unbox_complex_real_scale(sum) == 0);
        assert(w_unbox_complex_imag_sig(sum) == -2);
        assert(w_unbox_complex_imag_scale(sum) == 0);

        WValue diff = w_sub(a, b);
        assert(w_is_complex(diff));
        assert(w_unbox_complex_real_sig(diff) == -2);
        assert(w_unbox_complex_imag_sig(diff) == 8);

        WValue product = w_mul(a, b);
        assert(w_is_complex(product));
        assert(w_unbox_complex_real_sig(product) == 23);
        assert(w_unbox_complex_real_scale(product) == 0);
        assert(w_unbox_complex_imag_sig(product) == 2);
        assert(w_unbox_complex_imag_scale(product) == 0);

        WValue scaled = w_add(w_complex(12, -1, 3, 0), w_complex(3, -2, -5, 0));
        assert(w_is_complex(scaled));
        assert(w_unbox_complex_real_sig(scaled) == 123);
        assert(w_unbox_complex_real_scale(scaled) == -2);
        assert(w_unbox_complex_imag_sig(scaled) == -2);
        assert(w_unbox_complex_imag_scale(scaled) == 0);

        WValue int_sum = w_add(w_int(3), w_complex(0, 0, 4, 0));
        assert(w_is_complex(int_sum));
        assert(w_unbox_complex_real_sig(int_sum) == 3);
        assert(w_unbox_complex_imag_sig(int_sum) == 4);

        WValue complex_minus_int = w_sub(w_complex(12, -1, 4, 0), w_int(1));
        assert(w_is_complex(complex_minus_int));
        assert(w_unbox_complex_real_sig(complex_minus_int) == 2);
        assert(w_unbox_complex_real_scale(complex_minus_int) == -1);
        assert(w_unbox_complex_imag_sig(complex_minus_int) == 4);

        WValue int_minus_complex = w_sub(w_int(3), w_complex(12, -1, 4, 0));
        assert(w_is_complex(int_minus_complex));
        assert(w_unbox_complex_real_sig(int_minus_complex) == 18);
        assert(w_unbox_complex_real_scale(int_minus_complex) == -1);
        assert(w_unbox_complex_imag_sig(int_minus_complex) == -4);

        WValue scalar_product = w_mul(w_int(2), w_complex(12, -1, -3, 0));
        assert(w_is_complex(scalar_product));
        assert(w_unbox_complex_real_sig(scalar_product) == 24);
        assert(w_unbox_complex_real_scale(scalar_product) == -1);
        assert(w_unbox_complex_imag_sig(scalar_product) == -6);

        printf("  packed complex: OK\n");
    }

    /* Domain heap overflow: decimal */
    {
        int64_t big_sig = W_DECIMAL_SIG_MAX * 10 + 1;  /* well above 39-bit range, no trailing zero */
        WValue v = w_decimal(big_sig, -2);
        assert(w_is_domain_obj(v));
        WValue s = w_to_s(v);
        assert(strstr(str_val(s), ".") != NULL);  /* has decimal point */

        /* Round-trip through neg */
        WValue neg = w_neg(v);
        assert(w_is_domain_obj(neg));  /* 10x max stays overflowed when negated */
        WValue ns2 = w_to_s(neg);
        assert(str_val(ns2)[0] == '-');

        /* Arithmetic: heap decimal + heap decimal */
        WValue v2 = w_decimal(big_sig, -2);
        WValue sum = w_add(v, v2);
        assert(w_is_domain_obj(sum));

        /* Mixed: heap + inline */
        WValue small = w_decimal(123, -2);  /* 1.23 inline */
        WValue mixed = w_add(v, small);
        assert(w_is_domain_obj(mixed));

        printf("  domain heap decimal overflow: OK\n");
    }

    /* Domain heap overflow: currency */
    {
        int64_t big_sig = W_CURRENCY_SIG_MAX * 10 + 1;  /* well above 37-bit range, no trailing zero */
        WValue v = w_currency(0, big_sig, -2);  /* $-denominated */
        assert(w_is_domain_obj(v));
        WValue s = w_to_s(v);
        assert(str_val(s)[0] == '$');

        /* Currency add: heap + inline */
        WValue small = w_currency(0, 100, -2);  /* $1.00 inline */
        assert(!w_is_domain_obj(small));
        WValue sum = w_add(v, small);
        assert(w_is_domain_obj(sum));  /* result still overflows */

        /* Currency sub: result still overflows since big_sig >> small */
        WValue diff = w_sub(v, small);
        assert(w_is_domain_obj(diff));

        /* Currency mul by scalar */
        WValue product = w_mul(v, w_int(2));
        assert(w_is_domain_obj(product));

        printf("  domain heap currency overflow: OK\n");
    }

    /* Domain heap overflow: quantity */
    {
        int64_t big_sig = W_QUANTITY_SIG_MAX * 10 + 1;  /* well above 31-bit range, no trailing zero */
        WValue v = w_quantity(0, big_sig, 0);  /* meters */
        assert(w_is_domain_obj(v));
        WValue s = w_to_s(v);
        assert(strstr(str_val(s), "m") != NULL);

        /* Quantity add: heap + inline */
        WValue small = w_quantity(0, 5, 0);
        WValue sum = w_add(v, small);
        assert(w_is_domain_obj(sum));

        /* Quantity sub */
        WValue diff = w_sub(v, small);
        assert(w_is_domain_obj(diff));

        printf("  domain heap quantity overflow: OK\n");
    }

    /* Domain heap overflow: duration ns */
    {
        int64_t big_ns = W_DURATION_NS_MAX * 10 + 1;  /* well above 47-bit range */
        WValue v = w_duration_ns(big_ns);
        assert(w_is_domain_obj(v));
        WValue s = w_to_s(v);
        const char *duration_str = str_val(s);
        size_t duration_len = strlen(duration_str);
        assert(duration_len > 0);
        assert(duration_str[duration_len - 1] == 's');

        /* Duration add: heap + inline */
        WValue small = w_duration_ns(1000000000LL);  /* 1s in ns */
        WValue sum = w_add(v, small);
        assert(w_is_domain_obj(sum));

        /* Duration sub: result still overflows since big_ns >> small */
        WValue diff = w_sub(v, small);
        assert(w_is_domain_obj(diff));

        printf("  domain heap duration overflow: OK\n");
    }

    /* Cross-type: heap decimal comparison */
    {
        int64_t big = W_DECIMAL_SIG_MAX * 10 + 1;
        WValue a = w_decimal(big, 0);
        WValue b = w_decimal(big + 2, 0);  /* +2 to avoid trailing zero normalization */
        assert(w_lt(a, b) == W_TRUE);
        assert(w_gt(b, a) == W_TRUE);
        assert(w_eq(a, a) == W_TRUE);

        printf("  domain heap decimal comparison: OK\n");
    }

    printf("\n=== All tests passed! ===\n");
    return 0;
}

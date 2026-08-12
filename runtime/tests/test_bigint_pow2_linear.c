/* Differential fuzz for the pow2 strength-reduction and fused
 * multiply-accumulate entries:
 *
 *   w_bigint_div_pow2 / w_bigint_div_pow2_mut  vs  w_div(a, 1 << k)
 *   w_bigint_mod_pow2 / w_bigint_mod_pow2_mut  vs  w_mod(a, 1 << k)
 *   w_bigint_addmul_any / w_bigint_submul_any  vs  w_add/w_sub(r, x * y)
 *
 * Operands cover inline ints, heap bigints to ~8 limbs, header-negative
 * values (0 - x), overlay-negated aliases (w_neg), shared receivers, wide-
 * capacity receivers (mod_pow2_mut leaves a small value in a wide buffer),
 * and receiver-aliased factors (r += r * y). Deterministic xorshift seed;
 * every case compares boxed results with w_eq. Run under ASan+UBSan:
 *
 *   clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
 *     runtime/tests/test_bigint_pow2_linear.c runtime/runtime.c -lm \
 *     -o /tmp/test_bigint_pow2_linear
 *   /tmp/test_bigint_pow2_linear                # scratch-product leg
 *   TUNGSTEN_BIGINT_ADDMUL_ROWS=1 /tmp/test_bigint_pow2_linear   # rows leg
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../runtime.h"

static uint64_t rng_state = 0x9E3779B97F4A7C15ULL;
static uint64_t rng_next(void) {
    uint64_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    rng_state = x;
    return x;
}

static int failures = 0;
static void expect_eq(const char *what, long cse, WValue got, WValue want) {
    if (w_eq(got, want) == w_bool(1)) return;
    fprintf(stderr,
            "MISMATCH %s case=%ld got.low=%lld want.low=%lld\n",
            what, cse, (long long)w_to_i64(got), (long long)w_to_i64(want));
    if (++failures > 20) exit(1);
}

/* Build a fresh integer value from the CURRENT rng stream: limb count 0..8,
 * then sign flavor: 0 = positive, 1 = header-negative (0 - x),
 * 2 = overlay-negative (w_neg alias of a fresh positive). Replaying the
 * same stream builds an independent equal value (fresh buffer). */
static WValue build_value(void) {
    uint64_t shape = rng_next();
    int limbs = (int)(shape % 9);
    int sign = (int)((shape >> 8) % 3);
    WValue v = w_int(0);
    for (int i = 0; i < limbs; i++) {
        v = w_bit_shl(v, w_int(64));
        /* keep some limbs zero / small for carry and trim edge cases */
        uint64_t limb = rng_next();
        switch (limb % 4) {
        case 0: limb = 0; break;
        case 1: limb &= 0xFFULL; break;
        case 2: limb |= 0xFFFFFFFFFFFFFF00ULL; break;
        default: break;
        }
        v = w_add(v, w_u64(limb));
    }
    if (limbs == 0) v = w_int((int64_t)(rng_next() % 1000) - 500);
    if (sign == 1) return w_sub(w_int(0), v);
    if (sign == 2) return w_neg(v);
    return v;
}

static void fuzz_div_mod_pow2(long cases) {
    for (long c = 0; c < cases; c++) {
        uint64_t save = rng_state;
        WValue a1 = build_value();
        rng_state = save;
        WValue a2 = build_value();   /* independent equal value */
        rng_state = save;
        WValue a3 = build_value();
        int64_t k = (int64_t)(rng_next() % 600);
        if ((rng_next() & 7) == 0) k = 0;
        WValue kk = w_int(k);
        WValue divisor = w_bit_shl(w_int(1), kk);
        WValue want_q = w_div(a1, divisor);
        WValue want_r = w_mod(a1, divisor);
        expect_eq("div_pow2", c, w_bigint_div_pow2(a1, kk), want_q);
        expect_eq("mod_pow2", c, w_bigint_mod_pow2(a1, kk), want_r);
        /* consume variants own their operand (a2/a3 are never read again) */
        expect_eq("div_pow2_mut", c, w_bigint_div_pow2_mut(a2, kk), want_q);
        expect_eq("mod_pow2_mut", c, w_bigint_mod_pow2_mut(a3, kk), want_r);
    }
}

/* Receiver flavors for the linear entries: 0 = fresh exact-size, 1 = wide
 * capacity (built wide, truncated in place via mod_pow2_mut, keeping the
 * wide buffer), 2 = shared (an extra w_neg alias pins it). */
static WValue build_receiver(int flavor, WValue seedv) {
    if (flavor == 1) {
        WValue wide = w_add(w_bit_shl(w_int(1), w_int(1600)), seedv);
        WValue cut = w_bigint_mod_pow2_mut(wide, w_int(300));
        return cut;
    }
    if (flavor == 2) {
        (void)w_neg(seedv); /* mint and drop an overlay alias: marks shared */
        return seedv;
    }
    return seedv;
}

static void fuzz_linear_any(long cases) {
    for (long c = 0; c < cases; c++) {
        uint64_t save = rng_state;
        WValue r1 = build_value();
        rng_state = save;
        WValue r2 = build_value();
        int flavor = (int)(rng_next() % 3);
        uint64_t save2 = rng_state;
        r1 = build_receiver(flavor, r1);
        rng_state = save2;
        r2 = build_receiver(flavor, r2);
        WValue x = build_value();
        WValue y = build_value();
        int sub = (int)(rng_next() & 1);
        int alias = (int)(rng_next() % 4);

        WValue want, got;
        if (alias == 1) {          /* r ±= r * y */
            want = sub ? w_sub(r2, w_mul(r2, y)) : w_add(r2, w_mul(r2, y));
            got = sub ? w_bigint_submul_any(r1, r1, y)
                      : w_bigint_addmul_any(r1, r1, y);
        } else if (alias == 2) {   /* r ±= x * r */
            want = sub ? w_sub(r2, w_mul(x, r2)) : w_add(r2, w_mul(x, r2));
            got = sub ? w_bigint_submul_any(r1, x, r1)
                      : w_bigint_addmul_any(r1, x, r1);
        } else if (alias == 3) {   /* r ±= (-r) * y (overlay alias factor) */
            WValue m1 = w_neg(r1);
            WValue m2 = w_neg(r2);
            want = sub ? w_sub(r2, w_mul(m2, y)) : w_add(r2, w_mul(m2, y));
            got = sub ? w_bigint_submul_any(r1, m1, y)
                      : w_bigint_addmul_any(r1, m1, y);
        } else {
            want = sub ? w_sub(r2, w_mul(x, y)) : w_add(r2, w_mul(x, y));
            got = sub ? w_bigint_submul_any(r1, x, y)
                      : w_bigint_addmul_any(r1, x, y);
        }
        expect_eq(sub ? "submul_any" : "addmul_any", c, got, want);
    }
}

int main(void) {
    long cases = 40000;
    const char *n = getenv("FUZZ_CASES");
    if (n && atol(n) > 0) cases = atol(n);
    fuzz_div_mod_pow2(cases);
    fuzz_linear_any(cases);
    if (failures) {
        fprintf(stderr, "FAILED with %d mismatches\n", failures);
        return 1;
    }
    printf("OK: %ld div/mod pow2 cases + %ld linear-any cases\n",
           cases, cases);
    return 0;
}

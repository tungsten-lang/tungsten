#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/*
 * Include the runtime directly so this benchmark can time the static BigInt
 * dispatchers without exporting benchmark-only APIs.
 */
#include "runtime.c"

static volatile uint64_t bench_sink;

static double bench_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static uint64_t bench_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static uint64_t *bench_limbs(int32_t n, uint64_t seed) {
    uint64_t *limbs = (uint64_t *)calloc((size_t)n, sizeof(uint64_t));
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) limbs[i] = bench_rng(&state);
    limbs[0] |= 1ULL;
    limbs[n - 1] |= 1ULL << 63;
    return limbs;
}

static WValue bench_bigint(int32_t n, uint64_t seed) {
    WBigint *b = bigint_alloc(n);
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) b->limbs[i] = bench_rng(&state);
    b->limbs[0] |= 1ULL;
    b->limbs[n - 1] |= 1ULL << 63;
    b->size = n;
    return bigint_box(b);
}

static void bench_free_value(WValue value) {
    if (w_is_bigint(value)) free(w_as_bigint(value));
}

static int bench_iters_for_limbs(int32_t limbs) {
    if (limbs <= 32) return 2000;
    if (limbs <= 64) return 1000;
    if (limbs <= 256) return 300;
    if (limbs <= 1024) return 60;
    if (limbs <= 4096) return 10;
    return 4;
}

static int bench_iters_for_mulmod(int32_t limbs) {
    if (limbs <= 32) return 300;
    if (limbs <= 64) return 120;
    if (limbs <= 256) return 20;
    return 4;
}

static int bench_iters_for_gcd(int32_t limbs) {
    if (limbs <= 32) return 40;
    if (limbs <= 128) return 12;
    if (limbs <= 512) return 3;
    return 1;
}

static int bench_iters_for_addsub(int32_t limbs) {
    if (limbs <= 4) return 200000;
    if (limbs <= 64) return 30000;
    if (limbs <= 256) return 5000;
    return 1000;
}

/* The pre-direct-subtraction implementation: copy b, flip its sign, then add.
 * Keep it here as an A/B reference, but free the temporary it historically
 * leaked so repeated benchmark runs do not grow without bound. */
static WValue bench_sub_negate_add_ref(WValue a, WValue b) {
    WBigint *bb = w_as_bigint(b);
    int32_t n = bb->size < 0 ? -bb->size : bb->size;
    WBigint *neg = bigint_alloc(n);
    for (int32_t i = 0; i < n; i++) neg->limbs[i] = bb->limbs[i];
    neg->size = -bb->size;
    WValue result = bigint_add_any(a, bigint_box(neg));
    free(neg);
    return result;
}

static double bench_subtract(int32_t limbs, int iters, int negate_add_ref) {
    WValue a = bench_bigint(limbs, 0x123456789abcdef0ULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0xfedcba9876543210ULL ^ (uint64_t)limbs);
    if (bigint_compare(a, b) < 0) { WValue tmp = a; a = b; b = tmp; }

    WValue expected = bench_sub_negate_add_ref(a, b);
    WValue actual = bigint_sub_any(a, b);
    if (w_eq(expected, actual) != W_TRUE) die("direct bigint subtraction mismatch");
    bench_free_value(expected);
    bench_free_value(actual);

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = negate_add_ref ? bench_sub_negate_add_ref(a, b) : bigint_sub_any(a, b);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_equal_mul(int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0x123456789abcdef0ULL ^ (uint64_t)limbs);
    uint64_t *b = bench_limbs(limbs, 0xfedcba9876543210ULL ^ (uint64_t)limbs);
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bigint_mul_dispatch(out, a, limbs, b, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    free(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_equal_sqr(int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0x2d358dccaa6c78a5ULL ^ (uint64_t)limbs);
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bigint_sqr_dispatch(out, a, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_unbalanced_mul(int32_t hi, int32_t lo, int iters) {
    uint64_t *a = bench_limbs(hi, 0x9081726354453627ULL ^ (uint64_t)hi);
    uint64_t *b = bench_limbs(lo, 0xa3d70a3d70a3d70aULL ^ (uint64_t)lo);
    uint64_t *out = (uint64_t *)calloc((size_t)hi + (size_t)lo + 4, sizeof(uint64_t));
    uint64_t saved = b[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        b[0] = saved + (uint64_t)i;
        bigint_mul_dispatch(out, a, hi, b, lo);
        bench_sink ^= out[(unsigned)i % ((unsigned)hi + (unsigned)lo)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    free(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_forced_ntt_mul(int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
    uint64_t *b = bench_limbs(limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bn_ntt_mul(out, a, b, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    free(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_forced_ntt_sqr(int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0xa4093822299f31d0ULL ^ (uint64_t)limbs);
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bn_ntt_sqr(out, a, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

/* Time the actual boxed public arithmetic route.  The raw dispatch benchmarks
 * above are useful kernel measurements, but bigint_mul_any uses the
 * capacity-aware entry points; a policy mismatch there can otherwise remain
 * completely invisible in this benchmark.  Allocation and result release are
 * intentionally included because callers pay both. */
static double bench_value_mul(int32_t limbs, int iters, int square) {
    WValue a = bench_bigint(limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
    WValue b = square ? a : bench_bigint(limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);

    WValue warm = w_mul(a, b);
    bench_sink ^= (uint64_t)integer_low_i64(warm);
    bench_free_value(warm);

    double best = 1e300;
    for (int rep = 0; rep < 3; rep++) {
        double start = bench_now();
        for (int i = 0; i < iters; i++) {
            WValue r = w_mul(a, b);
            bench_sink ^= (uint64_t)integer_low_i64(r) + (uint64_t)i;
            bench_free_value(r);
        }
        double elapsed = bench_now() - start;
        if (elapsed < best) best = elapsed;
    }
    bench_free_value(a);
    if (!square) bench_free_value(b);
    return best * 1e9 / (double)iters;
}

/* Exact A/B for the former capacity-aware policy: allocate the same boxed
 * result, but unconditionally run NTT once the public path is in this size
 * band. */
static double bench_value_forced_ntt(int32_t limbs, int iters, int square) {
    WValue a = bench_bigint(limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
    WValue b = square ? a : bench_bigint(limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
    WBigint *ab = w_as_bigint(a);
    WBigint *bb = w_as_bigint(b);

    double best = 1e300;
    for (int rep = 0; rep < 3; rep++) {
        double start = bench_now();
        for (int i = 0; i < iters; i++) {
            WBigint *r = bigint_alloc(2 * limbs + 2);
            if (square) bn_ntt_sqr(r->limbs, ab->limbs, limbs);
            else bn_ntt_mul(r->limbs, ab->limbs, bb->limbs, limbs);
            r->size = 2 * limbs;
            while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
            bench_sink ^= r->limbs[0] + (uint64_t)i;
            free(r);
        }
        double elapsed = bench_now() - start;
        if (elapsed < best) best = elapsed;
    }
    bench_free_value(a);
    if (!square) bench_free_value(b);
    return best * 1e9 / (double)iters;
}

static void check_value_dispatch(int32_t limbs, int square) {
    WValue a = bench_bigint(limbs, 0x6c8e9cf570932bd5ULL ^ (uint64_t)limbs);
    WValue b = square ? a : bench_bigint(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    WBigint *ab = w_as_bigint(a);
    WBigint *bb = w_as_bigint(b);
    uint64_t *ref = (uint64_t *)calloc((size_t)(2 * limbs + 2), sizeof(uint64_t));
    if (square) bigint_sqr_dispatch(ref, ab->limbs, limbs);
    else bigint_mul_dispatch(ref, ab->limbs, limbs, bb->limbs, limbs);

    WValue got = w_mul(a, b);
    uint64_t scratch;
    int32_t glen;
    const uint64_t *glimbs = integer_limbs(got, &scratch, &glen);
    if (glen != 2 * limbs || memcmp(ref, glimbs, (size_t)(2 * limbs) * sizeof(uint64_t)) != 0)
        die("public BigInt transform dispatch mismatch");

    free(ref);
    bench_free_value(got);
    bench_free_value(a);
    if (!square) bench_free_value(b);
}

static double bench_mod_single(int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0x6a09e667f3bcc909ULL ^ (uint64_t)limbs);
    WValue d = w_u64(1000000007ULL);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = bigint_mod_any(a, d);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_mulmod(int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0xbb67ae8584caa73bULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x3c6ef372fe94f82bULL ^ (uint64_t)limbs);
    WValue m = bench_bigint(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    w_as_bigint(m)->limbs[0] |= 1ULL;
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_prime_bn_mulmod(a, b, m);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(a);
    bench_free_value(b);
    bench_free_value(m);
    return elapsed * 1e9 / (double)iters;
}

static double bench_ctx_mulmod(int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0xbb67ae8584caa73bULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x3c6ef372fe94f82bULL ^ (uint64_t)limbs);
    WValue m = bench_bigint(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    w_as_bigint(m)->limbs[0] |= 1ULL;

    WPrimeModCtx ctx;
    w_prime_modctx_init(&ctx, m);
    /* Domain-aware check: convert operands in (identity under Barrett), multiply
     * in-domain, convert back out for the equality (MontMul(x,1) = xR⁻¹). */
    WBigint *dab = bigint_alloc(limbs + 2), *dbb = bigint_alloc(limbs + 2);
    WValue da = w_prime_stable_copy(dab, w_prime_modctx_to_domain(&ctx, a));
    WValue db = w_prime_stable_copy(dbb, w_prime_modctx_to_domain(&ctx, b));
    WValue expected = w_prime_bn_mulmod(a, b, m);
    WValue r0 = w_prime_modctx_mul(&ctx, da, db);
    WValue actual = ctx.mont ? w_prime_modctx_mul(&ctx, r0, w_int(1)) : r0;
    if (w_eq(expected, actual) != W_TRUE) die("ctx mulmod mismatch");
    bench_free_value(expected);
    /* slot results are ctx-owned rotating buffers — never freed by callers;
     * the ctx owns them until w_prime_modctx_fini. */

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_prime_modctx_mul(&ctx, da, db);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    w_prime_modctx_fini(&ctx);
    free(dab); free(dbb);
    bench_free_value(a);
    bench_free_value(b);
    bench_free_value(m);
    return elapsed * 1e9 / (double)iters;
}

static WValue bench_mersenne_value(uint64_t p) {
    int32_t limbs = (int32_t)((p + 63ULL) >> 6);
    uint32_t top_bits = (uint32_t)(p & 63ULL);
    if (top_bits == 0) top_bits = 64;
    uint64_t top_mask = top_bits == 64 ? ~0ULL : ((1ULL << top_bits) - 1ULL);
    WBigint *m = bigint_alloc(limbs);
    for (int32_t i = 0; i < limbs; i++) m->limbs[i] = ~0ULL;
    m->limbs[limbs - 1] = top_mask;
    m->size = limbs;
    return bigint_box(m);
}

static WValue bench_mersenne_residue(uint64_t p, uint64_t seed) {
    int32_t limbs = (int32_t)((p + 63ULL) >> 6);
    uint32_t top_bits = (uint32_t)(p & 63ULL);
    if (top_bits == 0) top_bits = 64;
    uint64_t top_mask = top_bits == 64 ? ~0ULL : ((1ULL << top_bits) - 1ULL);
    WValue s = bench_bigint(limbs, seed);
    WBigint *b = w_as_bigint(s);
    b->limbs[limbs - 1] &= top_mask;
    b->limbs[limbs - 1] |= 1ULL << (top_bits - 1);
    b->limbs[0] &= ~2ULL;
    return s;
}

static double bench_mersenne_square_generic(uint64_t p, int iters) {
    WValue n = bench_mersenne_value(p);
    WValue s = bench_mersenne_residue(p, 0x510e527fade682d1ULL ^ p);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_mersenne_mod(w_mul(s, s), p, n);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(n);
    bench_free_value(s);
    return elapsed * 1e9 / (double)iters;
}

static double bench_mersenne_square_direct(uint64_t p, int iters) {
    WValue n = bench_mersenne_value(p);
    WValue s = bench_mersenne_residue(p, 0x510e527fade682d1ULL ^ p);
    WValue expected = w_mersenne_mod(w_mul(s, s), p, n);
    WValue actual = w_mersenne_square_mod(s, p);
    if (w_eq(expected, actual) != W_TRUE) die("Mersenne square-mod mismatch");
    bench_free_value(expected);
    bench_free_value(actual);

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_mersenne_square_mod(s, p);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(n);
    bench_free_value(s);
    return elapsed * 1e9 / (double)iters;
}

static WValue bench_abs_integer(WValue v) {
    if (w_is_int(v)) {
        int64_t iv = w_as_int(v);
        return iv < 0 ? (iv == W_INT48_MIN ? bigint_from_i64(-iv) : w_box_int(-iv)) : v;
    }

    WBigint *b = w_as_bigint(v);
    if (b->size >= 0) return v;

    int32_t n = -b->size;
    WBigint *pos = bigint_alloc(n);
    for (int32_t i = 0; i < n; i++) pos->limbs[i] = b->limbs[i];
    pos->size = n;
    return bigint_box(pos);
}

static WValue bench_gcd_euclid_ref(WValue a, WValue b) {
    WValue x = bench_abs_integer(a);
    WValue y = bench_abs_integer(b);

    while (1) {
        int y_zero;
        if (w_is_int(y)) y_zero = w_as_int(y) == 0;
        else y_zero = w_as_bigint(y)->size == 0;
        if (y_zero) return x;

        WValue rem = bigint_mod_any(x, y);
        x = y;
        y = rem;
    }
}

static int bench_gcd_equivalence(void) {
    const struct { int32_t limbs; uint64_t amul, bmul; } cases[] = {
        {8, 97ULL, 89ULL},
        {32, 123457ULL, 65537ULL},
        {128, 1000003ULL, 999983ULL},
        {512, 4294967291ULL, 2147483647ULL},
        {1024, 1099511627791ULL, 1099511627689ULL}
    };
    int bad = 0, checked = 0;

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        WValue g = bench_bigint(cases[i].limbs, 0x8f1bbcdc8a513f7dULL ^ (uint64_t)cases[i].limbs);
        WValue a = w_mul(g, w_u64(cases[i].amul));
        WValue b = w_mul(g, w_u64(cases[i].bmul));
        WValue ref = bench_gcd_euclid_ref(a, b);
        WValue got = bigint_gcd_any(a, b);
        if (w_eq(ref, got) != W_TRUE) bad++;
        checked++;
        bench_sink ^= integer_low_i64(got) + (uint64_t)i;
    }

    printf("gcd equivalence: %d/%d match%s\n", checked - bad, checked, bad ? "  *** MISMATCH ***" : "");
    return bad;
}

static double bench_gcd_shared_factor(int32_t limbs, int iters, int optimized) {
    WValue g = bench_bigint(limbs, 0xd6e8feb86659fd93ULL ^ (uint64_t)limbs);
    WValue a = w_mul(g, w_u64(1099511627791ULL));
    WValue b = w_mul(g, w_u64(1099511627689ULL));

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = optimized ? bigint_gcd_any(a, b) : bench_gcd_euclid_ref(a, b);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
    }
    return (bench_now() - start) * 1e6 / (double)iters;
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    const int32_t equal_sizes[] = {32, 64, 256, 1024, 4096, 8192};
    const struct { int32_t hi, lo; } unbalanced[] = {
        {256, 32}, {1024, 64}, {4096, 256}, {8192, 512}
    };

    printf("BigInt dispatch benchmark (ns/op)\n\n");

    printf("balanced limbs       mul        sqr    iters\n");
    for (size_t i = 0; i < sizeof(equal_sizes) / sizeof(equal_sizes[0]); i++) {
        int32_t limbs = equal_sizes[i];
        int iters = bench_iters_for_limbs(limbs);
        printf("%14d %9.1f %9.1f %8d\n",
               limbs,
               bench_equal_mul(limbs, iters),
               bench_equal_sqr(limbs, iters),
               iters);
    }

    printf("\nbigint subtract limbs   direct  negate+add  speedup   iters\n");
    const int32_t sub_sizes[] = {1, 4, 16, 64, 256, 1024};
    for (size_t i = 0; i < sizeof(sub_sizes) / sizeof(sub_sizes[0]); i++) {
        int32_t limbs = sub_sizes[i];
        int iters = bench_iters_for_addsub(limbs);
        double direct = bench_subtract(limbs, iters, 0);
        double reference = bench_subtract(limbs, iters, 1);
        printf("%21d %8.1f %11.1f %7.2fx %7d\n",
               limbs, direct, reference, reference / direct, iters);
    }

    printf("\nunbalanced limbs     mul        ratio   iters\n");
    for (size_t i = 0; i < sizeof(unbalanced) / sizeof(unbalanced[0]); i++) {
        int32_t hi = unbalanced[i].hi;
        int32_t lo = unbalanced[i].lo;
        int iters = bench_iters_for_limbs(hi);
        printf("%7d x %-6d %9.1f %8.1f %7d\n",
               hi, lo, bench_unbalanced_mul(hi, lo, iters), (double)hi / (double)lo, iters);
    }

    printf("\nforced NTT crossover  dispatch   ntt mul  ntt sqr   iters\n");
    const int32_t ntt_sizes[] = {1024, 2048, 3072, 4096};
    for (size_t i = 0; i < sizeof(ntt_sizes) / sizeof(ntt_sizes[0]); i++) {
        int32_t limbs = ntt_sizes[i];
        int iters = bench_iters_for_limbs(limbs);
        printf("%18d %9.1f %9.1f %8.1f %7d\n",
               limbs,
               bench_equal_mul(limbs, iters),
               bench_forced_ntt_mul(limbs, iters),
               bench_forced_ntt_sqr(limbs, iters),
               iters);
    }

    { uint64_t seed = 0x6c8e9cf570932bd5ULL; int bad = 0, checked = 0;
      const struct { int32_t a, b; int square; } dc[] = {
          {2048, 2048, 0}, {2048, 2048, 1}, {3072, 2048, 0}, {4096, 4096, 1}
      };
      for (size_t t = 0; t < sizeof(dc) / sizeof(dc[0]); t++) {
          int32_t na = dc[t].a, nb = dc[t].b, hi = na > nb ? na : nb;
          int32_t tot = na + nb, cap = 2 * hi + 2;
          uint64_t *A = bench_limbs(na, seed ^ (uint64_t)na);
          uint64_t *B = dc[t].square ? A : bench_limbs(nb, seed ^ (uint64_t)nb ^ 0x9e3779b97f4a7c15ULL);
          uint64_t *ref = calloc((size_t)cap, sizeof(uint64_t));
          uint64_t *got = calloc((size_t)cap, sizeof(uint64_t));
          if (dc[t].square) {
              bigint_sqr_dispatch(ref, A, na);
              bigint_sqr_dispatch_cap(got, cap, A, na);
          } else {
              bigint_mul_dispatch(ref, A, na, B, nb);
              bigint_mul_dispatch_cap(got, cap, A, na, B, nb);
          }
          int case_bad = memcmp(ref, got, (size_t)tot * sizeof(uint64_t)) != 0;
          for (int32_t i = tot; i < cap; i++) if (got[i] != 0) case_bad = 1;
          if (case_bad) bad++;
          checked++;
          free(A); if (!dc[t].square) free(B); free(ref); free(got);
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
      }
      printf("direct NTT output equivalence: %d/%d match%s\n", checked - bad, checked, bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
    }

    printf("\npublic boxed top rung  policy mul  old NTT  speedup  policy sqr  old NTT  speedup  iters\n");
    /* These are the SSA-selected windows; the 3072-limb NTT-selected control
     * is already covered by direct NTT output equivalence above. */
    const int32_t value_sizes[] = {2048, 4096, 8192, 16384};
    for (size_t i = 0; i < sizeof(value_sizes) / sizeof(value_sizes[0]); i++) {
        int32_t limbs = value_sizes[i];
        /* The top-rung timings are short enough to be scheduler-sensitive at
         * the generic iteration counts; use a longer sample for this A/B. */
        int iters = bench_iters_for_limbs(limbs) * 5;
        check_value_dispatch(limbs, 0);
        check_value_dispatch(limbs, 1);
        double policy_mul = bench_value_mul(limbs, iters, 0);
        double old_mul = bench_value_forced_ntt(limbs, iters, 0);
        double policy_sqr = bench_value_mul(limbs, iters, 1);
        double old_sqr = bench_value_forced_ntt(limbs, iters, 1);
        printf("%21d %11.1f %8.1f %7.2fx %11.1f %8.1f %7.2fx %6d\n",
               limbs, policy_mul, old_mul, old_mul / policy_mul,
               policy_sqr, old_sqr, old_sqr / policy_sqr, iters);
    }

    if (bench_gcd_equivalence()) return 1;

    printf("\ngcd shared factor (us) limbs   euclid   quotient-step  iters\n");
    const int32_t gcd_sizes[] = {32, 128, 512, 1024};
    for (size_t i = 0; i < sizeof(gcd_sizes) / sizeof(gcd_sizes[0]); i++) {
        int32_t limbs = gcd_sizes[i];
        int iters = bench_iters_for_gcd(limbs);
        printf("%29d %8.1f %13.1f %6d\n",
               limbs,
               bench_gcd_shared_factor(limbs, iters, 0),
               bench_gcd_shared_factor(limbs, iters, 1),
               iters);
    }

    printf("\nmod paths limbs  mod small   mulmod  ctxmulmod   iters\n");
    for (size_t i = 0; i < 4; i++) {
        int32_t limbs = equal_sizes[i];
        int mod_iters = bench_iters_for_limbs(limbs);
        int mulmod_iters = bench_iters_for_mulmod(limbs);
        printf("%14d %9.1f %9.1f %10.1f %7d/%d\n",
               limbs,
               bench_mod_single(limbs, mod_iters),
               bench_mulmod(limbs, mulmod_iters),
               bench_ctx_mulmod(limbs, mulmod_iters),
               mod_iters,
               mulmod_iters);
    }

    printf("\nMersenne square-mod       generic     direct   iters\n");
    const struct { uint64_t p; int iters; } mersenne[] = {
        {127, 300}, {521, 80}, {1279, 24}, {3217, 8}
    };
    for (size_t i = 0; i < sizeof(mersenne) / sizeof(mersenne[0]); i++) {
        uint64_t p = mersenne[i].p;
        int iters = mersenne[i].iters;
        printf("p=%-6llu %14.1f %10.1f %7d\n",
               (unsigned long long)p,
               bench_mersenne_square_generic(p, iters),
               bench_mersenne_square_direct(p, iters),
               iters);
    }

    /* BPSW primality on 2^bits + delta primes (verified externally): times the
     * full test and A/Bs the reference (WValue w_mul/w_mod) Lucas against the
     * modctx (Barrett + limb-native) Lucas, asserting they agree. */
    printf("\nbigint BPSW (us/op)  bits    total    lucas_ref   lucas_ctx   iters\n");
    const struct { int bits; uint64_t delta; int iters; } bp[] = {
        {64, 13, 300}, {128, 51, 100}, {256, 297, 30}, {512, 75, 8}, {1024, 643, 2}
    };
    for (size_t i = 0; i < sizeof(bp) / sizeof(bp[0]); i++) {
        int32_t nl = bp[i].bits / 64 + 1;
        WBigint *nb = bigint_alloc(nl);
        nb->limbs[0] = bp[i].delta; nb->limbs[nl - 1] = 1; nb->size = nl;
        WValue n = bigint_box(nb);
        if (w_prime_test_bigint(n) != 1) die("BPSW bench: prime misreported composite");
        WPrimeModCtx ctx;
        w_prime_modctx_init(&ctx, n);
        if (w_prime_lucas_strong(n) != w_prime_lucas_strong_ctx(n, &ctx))
            die("BPSW bench: lucas_ref and lucas_ctx disagree");
        int iters = bp[i].iters;
        double t0 = bench_now();
        for (int it = 0; it < iters; it++) bench_sink ^= (uint64_t)w_prime_test_bigint(n);
        double t_total = (bench_now() - t0) * 1e6 / iters;
        t0 = bench_now();
        for (int it = 0; it < iters; it++) bench_sink ^= (uint64_t)w_prime_lucas_strong(n);
        double t_ref = (bench_now() - t0) * 1e6 / iters;
        t0 = bench_now();
        for (int it = 0; it < iters; it++) bench_sink ^= (uint64_t)w_prime_lucas_strong_ctx(n, &ctx);
        double t_ctx = (bench_now() - t0) * 1e6 / iters;
        printf("%20d %9.1f %11.1f %11.1f %7d\n", bp[i].bits, t_total, t_ref, t_ctx, iters);
        w_prime_modctx_fini(&ctx);
        free(nb);
    }

    /* Lucas agreement fuzz: both implementations must agree on random odd n
     * (primes, composites, gcd(D,n)>1 cases — identical branch structure). */
    { uint64_t seed = 0x2545f4914f6cdd1dULL; int checked = 0, bad = 0;
      for (int t = 0; t < 300; t++) {
          WBigint *rb = bigint_alloc(3);
          for (int j = 0; j < 3; j++) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; rb->limbs[j] = seed; }
          rb->limbs[0] |= 1ULL; rb->limbs[2] |= 1ULL;   /* odd, full 3 limbs */
          rb->size = 3;
          WValue rn = bigint_box(rb);
          WPrimeModCtx ctx;
          w_prime_modctx_init(&ctx, rn);
          int a = w_prime_lucas_strong(rn), b = w_prime_lucas_strong_ctx(rn, &ctx);
          if (a != b) bad++;
          checked++;
          w_prime_modctx_fini(&ctx);
          free(rb);
      }
      printf("\nlucas agreement fuzz: %d/%d agree%s\n", checked - bad, checked, bad ? "  *** DISAGREE ***" : "");
      if (bad) return 1;
    }

    /* k=2 register-Barrett fast path (w_prime_modctx_mul2) equivalence sweep:
     * random and adversarial 2-limb odd moduli (tiny top limb, all-ones limbs)
     * × random operands, vs the generic w_prime_bn_mulmod. */
    { uint64_t seed = 0x9e3779b97f4a7c15ULL; int checked = 0, bad = 0;
      for (int m = 0; m < 120; m++) {
          uint64_t hi_l, lo_l;
          switch (m % 4) {
          case 0: seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; hi_l = seed;
                  seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; lo_l = seed; break;
          case 1: hi_l = 1; lo_l = 13 + 2 * (uint64_t)m; break;                 /* n ≈ 2^64 */
          case 2: hi_l = 0xFFFFFFFFFFFFFFFFULL; lo_l = 2 * (uint64_t)m + 1; break; /* n ≈ 2^128 */
          default: hi_l = 2; lo_l = 0xFFFFFFFFFFFFFFFFULL - 2 * (uint64_t)m; break;
          }
          WBigint *nb2 = bigint_alloc(2);
          nb2->limbs[0] = lo_l | 1ULL; nb2->limbs[1] = hi_l ? hi_l : 1; nb2->size = 2;
          WValue n2 = bigint_box(nb2);
          WPrimeModCtx c2;
          w_prime_modctx_init(&c2, n2);
          for (int t = 0; t < 60; t++) {
              WBigint *ab = bigint_alloc(2), *bb2 = bigint_alloc(2);
              seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; ab->limbs[0] = seed;
              seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; ab->limbs[1] = seed % (nb2->limbs[1] ? nb2->limbs[1] : 1);
              seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; bb2->limbs[0] = seed;
              seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; bb2->limbs[1] = seed % (nb2->limbs[1] ? nb2->limbs[1] : 1);
              ab->size = ab->limbs[1] ? 2 : 1; bb2->size = bb2->limbs[1] ? 2 : 1;
              WValue a = bigint_box(ab), b = bigint_box(bb2);
              WValue e = w_prime_bn_mulmod(a, b, n2);
              WValue g = w_prime_modctx_mul(&c2, a, b);
              if (w_eq(e, g) != W_TRUE) bad++;
              checked++;
              bench_free_value(e); free(ab); free(bb2);
          }
          w_prime_modctx_fini(&c2);
          free(nb2);
      }
      printf("mul2 (k=2) equivalence sweep: %d/%d match%s\n", checked - bad, checked, bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
    }

    /* chunked unbalanced multiply: equivalence vs schoolbook, random + all-ones
     * limb patterns (carry torture), odd sizes. */
    { uint64_t seed = 0xdeadbeefcafef00dULL; int bad = 0, checked = 0;
      const struct { int32_t big, small; } ub[] = {{300,40},{1000,64},{517,33},{2048,128},{8192,512}};
      for (size_t u = 0; u < sizeof(ub)/sizeof(ub[0]); u++) {
          int32_t nb_ = ub[u].big, ns_ = ub[u].small;
          uint64_t *A = malloc((size_t)nb_*8), *B = malloc((size_t)ns_*8);
          uint64_t *got = malloc((size_t)(nb_+ns_)*8), *ref = malloc((size_t)(nb_+ns_)*8);
          for (int r = 0; r < 3; r++) {
              for (int32_t i = 0; i < nb_; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; A[i] = (r==1)?~0ULL:seed; }
              for (int32_t i = 0; i < ns_; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; B[i] = (r==2)?~0ULL:seed; }
              bigint_mul_dispatch(got, A, nb_, B, ns_);
              bigint_mul_schoolbook_into(ref, A, nb_, B, ns_);
              if (memcmp(got, ref, (size_t)(nb_+ns_)*8) != 0) bad++;
              checked++;
          }
          free(A); free(B); free(got); free(ref);
      }
      printf("\nunbalanced chunked mul: %d/%d match%s\n", checked-bad, checked, bad?"  *** MISMATCH ***":"");
      if (bad) return 1;
    }

    /* chunked base-10^18 decimal parse vs digit-at-a-time reference. */
    { uint64_t seed = 0x123456789abcdefULL; int bad = 0, checked = 0;
      const char *fixed[] = {"0","9","123456789012345678","1234567890123456789",
          "999999999999999999999999999999999999","-12345678901234567890123","+42",
          "1_000_000_000_000_000_000_000_000","10000000000000000000000000000000000001"};
      char buf[260];
      for (int t = 0; t < 49; t++) {
          const char *src;
          if (t < 9) src = fixed[t];
          else {
              int len = 1 + (int)(seed % 240); seed^=seed<<13;seed^=seed>>7;seed^=seed<<17;
              for (int i = 0; i < len; i++) { buf[i] = (char)('0' + (seed % 10)); seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; }
              if (buf[0] == '0') buf[0] = '1';
              buf[len] = 0; src = buf;
          }
          WValue got = w_bigint_from_dec_str(w_string(src));
          WValue ref = w_box_int(0); size_t i = 0; int neg = 0;
          if (src[0]=='-'){neg=1;i=1;} else if (src[0]=='+'){i=1;}
          for (; src[i]; i++) { char c = src[i]; if (c=='_') continue; if (c<'0'||c>'9') break;
              ref = w_add(w_mul(ref, w_box_int(10)), w_box_int(c-'0')); }
          if (neg) ref = w_sub(w_box_int(0), ref);
          if (w_eq(got, ref) != W_TRUE) bad++;
          checked++;
      }
      printf("chunked dec parse: %d/%d match%s\n", checked-bad, checked, bad?"  *** MISMATCH ***":"");
      if (bad) return 1;
      /* timing: 5000-digit parse, chunked vs the digit-at-a-time reference */
      { char *big5k = malloc(5001);
        uint64_t s2 = 0x9e3779b97f4a7c15ULL;
        for (int i = 0; i < 5000; i++) { s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; big5k[i] = (char)('0' + (s2 % 10)); }
        if (big5k[0]=='0') big5k[0]='1';
        big5k[5000] = 0;
        WValue sv = w_string(big5k);
        double t0 = bench_now();
        for (int r = 0; r < 20; r++) bench_sink ^= integer_low_i64(w_bigint_from_dec_str(sv));
        double tn = (bench_now() - t0) * 1e6 / 20;
        t0 = bench_now();
        for (int r = 0; r < 20; r++) {
            WValue ref = w_box_int(0);
            for (int i = 0; big5k[i]; i++) ref = w_add(w_mul(ref, w_box_int(10)), w_box_int(big5k[i]-'0'));
            bench_sink ^= integer_low_i64(ref);
        }
        double tr = (bench_now() - t0) * 1e6 / 20;
        printf("5000-digit parse: chunked %.1fus  per-digit %.1fus  (%.1fx)\n", tn, tr, tr/tn);
        free(big5k);
      }
    }

    /* Proth fast path: k·2^n+1 — Proth's-theorem proof must agree with BOTH the
     * externally verified expectation and the BPSW path, on primes and
     * composites. Then time proth vs BPSW on the larger primes. */
    { int bad = 0, checked = 0;
      const struct { uint64_t k; int n; int prime; } pr[] = {
        {3,66,1},{3,189,1},{5,75,1},{5,85,1},{7,92,1},{7,120,1},{9,67,1},{9,81,1},
        {11,81,1},{11,125,1},{13,82,1},{13,188,1},{15,78,1},{15,112,1},{21,124,1},{21,128,1},
        {3,276,1},{3,408,1},{3,534,1},
        {3,70,0},{3,100,0},{3,150,0},{3,200,0},{3,300,0},{3,401,0},{3,500,0},
        {5,70,0},{5,100,0},{5,150,0},{7,70,0},{9,100,0},{11,100,0},{13,100,0},
        {15,100,0},{21,100,0},{10223,100,0},{10223,200,0},{3,1024,0}
      };
      for (size_t i = 0; i < sizeof(pr)/sizeof(pr[0]); i++) {
          int n = pr[i].n;
          int32_t nl = n / 64 + 2;
          WBigint *b = bigint_alloc(nl);
          for (int32_t j = 0; j < nl; j++) b->limbs[j] = 0;
          int limb = n / 64, sh = n % 64;
          b->limbs[limb] |= pr[i].k << sh;
          if (sh && (pr[i].k >> (64 - sh))) b->limbs[limb + 1] |= pr[i].k >> (64 - sh);
          b->limbs[0] |= 1ULL;
          int32_t sz = nl; while (sz > 0 && b->limbs[sz - 1] == 0) sz--;
          b->size = sz;
          WValue N = bigint_box(b);
          if (!w_prime_proth_shape(b->limbs, sz)) { bad++; checked++; free(b); continue; }
          int got = w_prime_test_proth(N);
          int bpw = w_prime_test_bigint(N);
          if (got != pr[i].prime || bpw != pr[i].prime) bad++;
          checked++;
          free(b);
      }
      printf("proth proof vs expected+BPSW: %d/%d agree%s\n", checked - bad, checked,
             bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
      /* timing on 3·2^534+1 (~535 bits, prime) */
      { int n = 534; int32_t nl = n / 64 + 2;
        WBigint *b = bigint_alloc(nl);
        for (int32_t j = 0; j < nl; j++) b->limbs[j] = 0;
        b->limbs[n / 64] |= 3ULL << (n % 64);
        if ((n % 64) && (3ULL >> (64 - n % 64))) b->limbs[n / 64 + 1] |= 3ULL >> (64 - n % 64);
        b->limbs[0] |= 1ULL;
        int32_t sz = nl; while (sz > 0 && b->limbs[sz - 1] == 0) sz--;
        b->size = sz;
        WValue N = bigint_box(b);
        double t0 = bench_now();
        for (int r = 0; r < 20; r++) bench_sink ^= (uint64_t)w_prime_test_proth(N);
        double tp = (bench_now() - t0) * 1e6 / 20;
        t0 = bench_now();
        for (int r = 0; r < 20; r++) bench_sink ^= (uint64_t)w_prime_test_bigint(N);
        double tb = (bench_now() - t0) * 1e6 / 20;
        printf("proth 3*2^534+1: proof %.1fus  BPSW %.1fus  (%.1fx, and it IS a proof)\n", tp, tb, tb / tp);
        free(b);
      }
    }

    /* Burnikel–Ziegler divmod: bit-for-bit equality with Knuth across random +
     * adversarial shapes, plus q·v + r == u reconstruction on a subset. */
    { uint64_t seed = 0x0c0ffee123456789ULL; int bad = 0, checked = 0;
      for (int t = 0; t < 250; t++) {
          int32_t vlen, ulen;
          switch (t % 5) {
          case 0: vlen = 128 + (int32_t)(seed % 130); break;      /* just over the gate */
          case 1: vlen = 200 + (int32_t)(seed % 313); break;      /* mid, odd sizes */
          case 2: vlen = 128; break;                              /* power-of-two-ish */
          case 3: vlen = 129; break;                              /* odd → base-case heavy */
          default: vlen = 256 + (int32_t)(seed % 100); break;
          }
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
          ulen = vlen + 64 + (int32_t)(seed % 500);
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
          uint64_t *U = malloc((size_t)ulen * 8), *V = malloc((size_t)vlen * 8);
          for (int32_t i = 0; i < ulen; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; U[i] = (t % 7 == 3) ? ~0ULL : seed; }
          for (int32_t i = 0; i < vlen; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; V[i] = (t % 7 == 5) ? ~0ULL : seed; }
          if (t % 9 == 0) V[vlen - 1] = 0x8000000000000000ULL;    /* already-normalized divisor */
          if (U[ulen - 1] == 0) U[ulen - 1] = 1;
          if (V[vlen - 1] == 0) V[vlen - 1] = 1;
          WBigint *q1 = NULL, *r1 = NULL, *q2 = NULL, *r2 = NULL;
          mag_divmod(U, ulen, V, vlen, &q1, &r1);            /* B–Z (gated) */
          mag_divmod_knuth(U, ulen, V, vlen, &q2, &r2);
          int ok = (q1->size == q2->size && r1->size == r2->size &&
                    memcmp(q1->limbs, q2->limbs, (size_t)(q1->size < 0 ? -q1->size : q1->size) * 8) == 0 &&
                    memcmp(r1->limbs, r2->limbs, (size_t)(r1->size < 0 ? -r1->size : r1->size) * 8) == 0);
          if (ok && t % 4 == 0) {                            /* reconstruction oracle */
              int32_t ql = q1->size, rl = r1->size;
              uint64_t *rec = calloc((size_t)(ql + vlen + 2), 8);
              if (ql) bigint_mul_dispatch(rec, q1->limbs, ql, V, vlen);
              uint64_t c = 0;
              for (int32_t i = 0; i < rl || c; i++) {
                  __uint128_t s = (__uint128_t)rec[i] + (i < rl ? r1->limbs[i] : 0) + c;
                  rec[i] = (uint64_t)s; c = (uint64_t)(s >> 64);
              }
              int32_t recl = ql + vlen + 2; while (recl > 0 && rec[recl-1] == 0) recl--;
              int32_t ut2 = ulen; while (ut2 > 0 && U[ut2-1] == 0) ut2--;
              if (recl != ut2 || memcmp(rec, U, (size_t)ut2 * 8) != 0) ok = 0;
              free(rec);
          }
          if (!ok) bad++;
          checked++;
          free(q1); free(r1); free(q2); free(r2); free(U); free(V);
      }
      printf("\nBZ divmod fuzz (vs Knuth + q*v+r==u): %d/%d ok%s\n", checked - bad, checked,
             bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
      /* timing: 2n ÷ n */
      printf("BZ divmod (us)   n     knuth      bz\n");
      const int32_t dn[] = {128, 256, 512, 1024, 2048};
      for (size_t di = 0; di < sizeof(dn)/sizeof(dn[0]); di++) {
          int32_t n = dn[di];
          uint64_t *U = malloc((size_t)(2 * n) * 8), *V = malloc((size_t)n * 8);
          uint64_t s2 = 0x9e3779b97f4a7c15ULL ^ (uint64_t)n;
          for (int32_t i = 0; i < 2 * n; i++) { s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; U[i] = s2; }
          for (int32_t i = 0; i < n; i++) { s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; V[i] = s2; }
          if (V[n-1] == 0) V[n-1] = 1;
          int it = n <= 256 ? 60 : (n <= 1024 ? 16 : 6);
          double t0 = bench_now();
          for (int r = 0; r < it; r++) { WBigint *qq, *rr; mag_divmod_knuth(U, 2*n, V, n, &qq, &rr); bench_sink ^= qq->limbs[0]; free(qq); free(rr); }
          double tk = (bench_now() - t0) * 1e6 / it;
          t0 = bench_now();
          for (int r = 0; r < it; r++) { WBigint *qq, *rr; mag_divmod(U, 2*n, V, n, &qq, &rr); bench_sink ^= qq->limbs[0]; free(qq); free(rr); }
          double tb = (bench_now() - t0) * 1e6 / it;
          printf("%18d %9.1f %9.1f  (%.2fx)\n", n, tk, tb, tk / tb);
          free(U); free(V);
      }
    }

    /* D&C to_s: equality with the base chunk algorithm (valid at any size) on
     * random values spanning the threshold + zero-padding stress (exact
     * multiples of 10^(18·2^j)), then timing. */
    { uint64_t seed = 0xfeedfacecafebeefULL; int bad = 0, checked = 0;
      for (int t = 0; t < 120; t++) {
          int32_t nl = 20 + (int32_t)(seed % 220);
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
          WBigint *xb = bigint_alloc(nl);
          for (int32_t i = 0; i < nl; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; xb->limbs[i] = seed; }
          if (t % 6 == 2) { for (int32_t i = 0; i < nl / 2; i++) xb->limbs[i] = 0; }   /* low zeros */
          if (t % 6 == 4) { for (int32_t i = 0; i < nl; i++) xb->limbs[i] = ~0ULL; }
          if (xb->limbs[nl-1] == 0) xb->limbs[nl-1] = 1;
          xb->size = nl;
          char *s1 = malloc((size_t)nl * 20 + 4), *s2 = malloc((size_t)nl * 20 + 4);
          int32_t l1 = w_dec_write(xb->limbs, nl, s1, 0);      /* D&C */
          int32_t l2 = w_dec_chunks_write(xb->limbs, nl, s2, 0); /* base oracle */
          if (l1 != l2 || memcmp(s1, s2, (size_t)l1) != 0) bad++;
          checked++;
          free(s1); free(s2); free(xb);
      }
      /* exact multiples of P_2 = 10^72: forces long zero-padded tails */
      { WBigint *p = bigint_alloc(4); p->limbs[0]=1000000000000000000ULL; p->size=1;
        /* p = 10^72 via three squarings of 10^18? 10^18^4 = 10^72: sq twice */
        uint64_t tmp[8] = {0}; bigint_sqr_dispatch(tmp, p->limbs, 1);            /* 10^36 */
        uint64_t tmp2[16] = {0}; bigint_sqr_dispatch(tmp2, tmp, 2);              /* 10^72 */
        int32_t pl = 16; while (pl > 0 && tmp2[pl-1] == 0) pl--;
        for (int t = 0; t < 40; t++) {
            int32_t kl = 40 + (int32_t)(seed % 80);
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
            uint64_t *k = calloc((size_t)kl, 8);
            for (int32_t i = 0; i < kl; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; k[i]=seed; }
            if (k[kl-1] == 0) k[kl-1] = 1;
            int32_t xl2 = kl + pl;
            uint64_t *x = calloc((size_t)xl2, 8);
            bigint_mul_dispatch(x, k, kl, tmp2, pl);                             /* k·10^72 */
            while (xl2 > 0 && x[xl2-1] == 0) xl2--;
            char *s1 = malloc((size_t)xl2 * 20 + 4), *s2 = malloc((size_t)xl2 * 20 + 4);
            int32_t l1 = w_dec_write(x, xl2, s1, 0);
            int32_t l2 = w_dec_chunks_write(x, xl2, s2, 0);
            if (l1 != l2 || memcmp(s1, s2, (size_t)l1) != 0) bad++;
            checked++;
            free(s1); free(s2); free(k); free(x);
        }
        free(p); }
      printf("\nD&C to_s fuzz vs base: %d/%d match%s\n", checked - bad, checked,
             bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
      /* timing: 2^131072 (2048 limbs, ~39k digits) */
      { int32_t nl = 2048;
        uint64_t *x = calloc((size_t)nl, 8); x[nl-1] = 0x8000000000000000ULL;
        char *s = malloc((size_t)nl * 20 + 4);
        double t0 = bench_now();
        for (int r = 0; r < 10; r++) bench_sink ^= (uint64_t)w_dec_write(x, nl, s, 0);
        double td = (bench_now() - t0) * 1e6 / 10;
        t0 = bench_now();
        for (int r = 0; r < 10; r++) bench_sink ^= (uint64_t)w_dec_chunks_write(x, nl, s, 0);
        double tc = (bench_now() - t0) * 1e6 / 10;
        printf("to_s 2048 limbs (~39k digits): D&C %.0fus  base %.0fus  (%.1fx)\n", td, tc, tc / td);
        free(x); free(s); }
    }

    /* submul_1 asm vs portable reference: random + all-ones, lengths spanning
     * the 4x-unroll boundary (tails). */
    { uint64_t seed = 0x5deece66d1234567ULL; int bad = 0, checked = 0;
      for (int t = 0; t < 400; t++) {
          int32_t n = 1 + (int32_t)(seed % 41);
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
          uint64_t up[48], r1[48], r2[48], v;
          for (int32_t i = 0; i < n; i++) {
              seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; up[i] = (t%5==1)?~0ULL:seed;
              seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; r1[i] = (t%5==3)?0:seed;
              r2[i] = r1[i];
          }
          seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; v = (t%5==2)?~0ULL:seed;
          uint64_t b1 = bn_submul_1(r1, up, n, v);
          uint64_t b2 = bn_submul_1_ref(r2, up, n, v);
          int ok = (b1 == b2) && memcmp(r1, r2, (size_t)n * 8) == 0;
          if (!ok) bad++;
          checked++;
      }
      printf("\nsubmul_1 asm vs ref: %d/%d match%s\n", checked-bad, checked, bad?"  *** MISMATCH ***":"");
      if (bad) return 1;
    }

    /* SOS vs CIOS Montgomery: equivalence at k=3..64 (random + all-ones + tiny
     * top limbs), then a crossover timing sweep. */
    { uint64_t seed = 0xabcdef0123456789ULL; int bad = 0, checked = 0;
      for (int t = 0; t < 300; t++) {
          int32_t k = 3 + (int32_t)(seed % 62);
          seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
          uint64_t N[66], A[66], B[66], o1[66], o2[66], T[134];
          for (int32_t i = 0; i < k; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; N[i] = seed; }
          N[0] |= 1ULL;
          if (t % 4 == 1) N[k-1] = 1;                     /* tiny top limb */
          if (t % 4 == 2) N[k-1] = 0x8000000000000000ULL;
          if (N[k-1] == 0) N[k-1] = 1;
          uint64_t np = 0; { uint64_t inv = N[0]; for (int z = 0; z < 5; z++) inv *= 2ULL - N[0]*inv; np = 0ULL - inv; }
          for (int32_t i = 0; i < k; i++) {
              seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; A[i] = (t%5==3)?~0ULL:seed;
              seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; B[i] = seed;
          }
          A[k-1] %= (N[k-1] ? N[k-1] : 1); B[k-1] %= (N[k-1] ? N[k-1] : 1);  /* keep < n */
          w_mont_cios_mul(o1, A, k, B, k, N, k, np);
          w_mont_sos_mul(o2, A, k, B, k, N, k, np, T);
          if (memcmp(o1, o2, (size_t)k * 8) != 0) bad++;
          checked++;
      }
      printf("SOS vs CIOS mont: %d/%d match%s\n", checked-bad, checked, bad?"  *** MISMATCH ***":"");
      if (bad) return 1;
      printf("mont kernel (ns)   k     CIOS      SOS\n");
      const int32_t ks[] = {4, 8, 16, 32, 64};
      for (size_t ki = 0; ki < 5; ki++) {
          int32_t k = ks[ki];
          uint64_t N[66], A[66], B[66], o1[66], T[134];
          uint64_t s2 = 0x123456789abcdefULL ^ (uint64_t)k;
          for (int32_t i = 0; i < k; i++) { s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; N[i]=s2;
              s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; A[i]=s2; s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; B[i]=s2; }
          N[0] |= 1ULL; if (N[k-1]==0) N[k-1]=1;
          A[k-1] %= N[k-1]; B[k-1] %= N[k-1];
          uint64_t np; { uint64_t inv=N[0]; for (int z=0;z<5;z++) inv*=2ULL-N[0]*inv; np=0ULL-inv; }
          int it = 200000 / (k * k / 16 + 1);
          double t0 = bench_now();
          for (int r = 0; r < it; r++) { w_mont_cios_mul(o1, A, k, B, k, N, k, np); bench_sink ^= o1[0]; }
          double tc = (bench_now() - t0) * 1e9 / it;
          t0 = bench_now();
          for (int r = 0; r < it; r++) { w_mont_sos_mul(o1, A, k, B, k, N, k, np, T); bench_sink ^= o1[0]; }
          double ts = (bench_now() - t0) * 1e9 / it;
          printf("%18d %8.0f %8.0f  (%.2fx)\n", k, tc, ts, tc / ts);
      }
    }

    /* Schönhage–Strassen: equivalence vs the Goldilocks NTT (balanced) and vs
     * schoolbook (unbalanced / small), then the SSA-vs-NTT timing sweep that
     * sets BN_SSA_THRESHOLD. Direct calls — independent of dispatch routing. */
    { uint64_t seed = 0x55aa55aa12345678ULL; int bad = 0, checked = 0;
      const int32_t szs[] = {2048, 2049, 3072, 4096, 5000, 8192};
      for (size_t si = 0; si < sizeof(szs)/sizeof(szs[0]); si++) {
          int32_t n = szs[si];
          uint64_t *A = malloc((size_t)n * 8), *B = malloc((size_t)n * 8);
          uint64_t *r1 = malloc((size_t)(2 * n + 4) * 8), *r2 = malloc((size_t)(2 * n + 4) * 8);
          for (int rep = 0; rep < 2; rep++) {
              for (int32_t i = 0; i < n; i++) {
                  seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; A[i] = (rep==1)?~0ULL:seed;
                  seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; B[i] = (rep==1)?~0ULL:seed;
              }
              if (A[n-1]==0) A[n-1]=1;
              if (B[n-1]==0) B[n-1]=1;
              bn_ssa_mul(r1, A, n, B, n);
              bn_ntt_mul(r2, A, B, n);
              if (memcmp(r1, r2, (size_t)(2 * n) * 8) != 0) bad++;
              checked++;
              bn_ssa_mul(r1, A, n, NULL, 0);          /* square path */
              bn_ntt_sqr(r2, A, n);
              if (memcmp(r1, r2, (size_t)(2 * n) * 8) != 0) bad++;
              checked++;
          }
          free(A); free(B); free(r1); free(r2);
      }
      /* ragged/unbalanced direct entries vs schoolbook */
      for (int t = 0; t < 6; t++) {
          int32_t na = 2048 + (int32_t)(seed % 700); seed^=seed<<13;seed^=seed>>7;seed^=seed<<17;
          int32_t nb2 = 1500 + (int32_t)(seed % 900); seed^=seed<<13;seed^=seed>>7;seed^=seed<<17;
          uint64_t *A = malloc((size_t)na * 8), *B = malloc((size_t)nb2 * 8);
          uint64_t *r1 = malloc((size_t)(na + nb2 + 4) * 8), *r2 = malloc((size_t)(na + nb2 + 4) * 8);
          for (int32_t i = 0; i < na; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; A[i]=seed; }
          for (int32_t i = 0; i < nb2; i++) { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17; B[i]=seed; }
          if (A[na-1]==0) A[na-1]=1;
          if (B[nb2-1]==0) B[nb2-1]=1;
          bn_ssa_mul(r1, A, na, B, nb2);
          bigint_mul_schoolbook_into(r2, A, na, B, nb2);
          if (memcmp(r1, r2, (size_t)(na + nb2) * 8) != 0) bad++;
          checked++;
          free(A); free(B); free(r1); free(r2);
      }
      printf("\nSSA fuzz (vs NTT + schoolbook): %d/%d match%s\n", checked - bad, checked,
             bad ? "  *** MISMATCH ***" : "");
      if (bad) return 1;
      printf("dispatch decisions (model):\n");
      const int32_t dn[] = {2048, 2560, 3072, 3584, 4096, 6144, 8192, 16384};
      for (size_t di = 0; di < sizeof(dn)/sizeof(dn[0]); di++) {
          int32_t n = dn[di];
          int32_t sw; long sL; uint64_t sK;
          double sc = ssa_choose(n, n, &sw, &sL, &sK);
          double nc = ntt_cost_est(n);
          printf("  n=%-6d ssa_est %8.0f  ntt_est %8.0f  -> %s\n", n, sc, nc, sc < nc ? "SSA" : "NTT");
      }
      printf("SSA vs NTT (us)    n       ntt       ssa\n");
      const int32_t tn[] = {2048, 3072, 4096, 8192, 16384};
      for (size_t ti = 0; ti < sizeof(tn)/sizeof(tn[0]); ti++) {
          int32_t n = tn[ti];
          uint64_t *A = malloc((size_t)n * 8), *B = malloc((size_t)n * 8);
          uint64_t *r1 = malloc((size_t)(2 * n + 4) * 8);
          uint64_t s2 = 0xabcdef987654321ULL ^ (uint64_t)n;
          for (int32_t i = 0; i < n; i++) { s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; A[i]=s2;
                                            s2^=s2<<13;s2^=s2>>7;s2^=s2<<17; B[i]=s2; }
          int it = n <= 4096 ? 20 : (n <= 8192 ? 8 : 3);
          double t0 = bench_now();
          for (int r = 0; r < it; r++) { bn_ntt_mul(r1, A, B, n); bench_sink ^= r1[0]; }
          double tt = (bench_now() - t0) * 1e6 / it;
          t0 = bench_now();
          for (int r = 0; r < it; r++) { bn_ssa_mul(r1, A, n, B, n); bench_sink ^= r1[0]; }
          double ts = (bench_now() - t0) * 1e6 / it;
          printf("%18d %9.0f %9.0f  (%.2fx)\n", n, tt, ts, tt / ts);
          free(A); free(B); free(r1);
      }
    }

    printf("\nsink=%llu\n", (unsigned long long)bench_sink);
    return 0;
}

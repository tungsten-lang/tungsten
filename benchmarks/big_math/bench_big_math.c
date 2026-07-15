#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef HAVE_GMP
#include <gmp.h>
#if GMP_LIMB_BITS != 64
#error "This benchmark expects 64-bit GMP limbs."
#endif
#endif

/*
 * Include the runtime directly so the benchmark can time the internal BigInt
 * kernels without adding exported benchmark-only APIs.
 */
#include "../../runtime/runtime.c"

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
    if (!limbs) die("out of memory allocating benchmark limbs");
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

static WValue bench_clone_integer(WValue value) {
    uint64_t scratch;
    int32_t len;
    const uint64_t *limbs = integer_limbs(value, &scratch, &len);
    int32_t n = len < 0 ? -len : len;
    if (n == 0) return w_box_int(0);
    WBigint *copy = bigint_alloc(n);
    memcpy(copy->limbs, limbs, (size_t)n * sizeof(uint64_t));
    copy->size = len;
    return bigint_box(copy);
}

static void bench_free_value(WValue value) {
    if (w_is_bigint(value)) free(w_as_bigint(value));
}

static int bench_iters_for_limbs(int32_t limbs) {
    if (limbs <= 64) return 1000;
    if (limbs <= 256) return 300;
    if (limbs <= 1024) return 80;
    if (limbs <= 4096) return 16;
    if (limbs <= 8192) return 8;
    return 4;
}

static int bench_iters_for_mod(int32_t limbs) {
    if (limbs <= 4) return 200000;
    if (limbs <= 16) return 50000;
    if (limbs <= 64) return 10000;
    if (limbs <= 256) return 1000;
    if (limbs <= 1024) return 100;
    return 30;
}

static void assert_same_limbs(const char *label, const uint64_t *a, const uint64_t *b, int32_t n) {
    for (int32_t i = 0; i < n; i++) {
        if (a[i] != b[i]) {
            fprintf(stderr, "%s mismatch at limb %d\n", label, i);
            exit(1);
        }
    }
}

static double ratio(double tungsten, double gmp) {
    return gmp > 0.0 ? tungsten / gmp : 0.0;
}

static double bench_tungsten_mul(const uint64_t *a0, const uint64_t *b, int32_t limbs, int iters) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in multiply benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    bigint_mul_dispatch(out, a, limbs, b, limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bigint_mul_dispatch(out, a, limbs, b, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_sqr(const uint64_t *a0, int32_t limbs, int iters) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in square benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    bigint_sqr_dispatch(out, a, limbs);
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

static double bench_tungsten_mod1(const uint64_t *a, int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= mag_mod_single(a, limbs, 1000000007ULL + (uint64_t)(i & 1));
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static uint64_t bench_mag_mod_single_ref(const uint64_t *a, int32_t limbs, uint64_t d) {
    __uint128_t r = 0;
    for (int32_t i = limbs - 1; i >= 0; i--) {
        r = (r << 64) | a[i];
        r %= d;
    }
    return (uint64_t)r;
}

static double bench_tungsten_mod1_ref(const uint64_t *a, int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= bench_mag_mod_single_ref(a, limbs,
                                               1000000007ULL + (uint64_t)(i & 1));
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static double bench_tungsten_ctx_mulmod(int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0xbb67ae8584caa73bULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x3c6ef372fe94f82bULL ^ (uint64_t)limbs);
    WValue m = bench_bigint(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    w_as_bigint(m)->limbs[0] |= 1ULL;
    WValue reduced_a = w_mod(a, m);
    WValue reduced_b = w_mod(b, m);

    WPrimeModCtx ctx;
    w_prime_modctx_init(&ctx, m);
    WValue mul_a = reduced_a, mul_b = reduced_b;
    if (ctx.mont) {
        mul_a = bench_clone_integer(w_prime_modctx_to_domain(&ctx, reduced_a));
        mul_b = bench_clone_integer(w_prime_modctx_to_domain(&ctx, reduced_b));
    }
    (void)w_prime_modctx_mul(&ctx, mul_a, mul_b);

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_prime_modctx_mul(&ctx, mul_a, mul_b);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    w_prime_modctx_fini(&ctx);
    if (ctx.mont) {
        bench_free_value(mul_a);
        bench_free_value(mul_b);
    }
    if (reduced_a != a) bench_free_value(reduced_a);
    if (reduced_b != b) bench_free_value(reduced_b);
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

static double bench_tungsten_mersenne_square(uint64_t p, int iters) {
    WValue s = bench_mersenne_residue(p, 0x510e527fade682d1ULL ^ p);
    WValue warm = w_mersenne_square_mod(s, p);
    bench_free_value(warm);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_mersenne_square_mod(s, p);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        bench_free_value(r);
    }
    double elapsed = bench_now() - start;
    bench_free_value(s);
    return elapsed * 1e9 / (double)iters;
}

#ifdef HAVE_GMP
static void gmp_import_limbs(mpz_t z, const uint64_t *limbs, int32_t n) {
    mpz_import(z, (size_t)n, -1, sizeof(uint64_t), 0, 0, limbs);
}

static int value_matches_mpz(WValue value, const mpz_t z) {
    uint64_t scratch;
    int32_t len;
    const uint64_t *limbs = integer_limbs(value, &scratch, &len);
    if (len < 0) return 0;
    while (len > 0 && limbs[len - 1] == 0) len--;

    size_t cap = (mpz_sizeinbase(z, 2) + 63U) / 64U + 1U;
    uint64_t *tmp = (uint64_t *)calloc(cap, sizeof(uint64_t));
    if (!tmp) die("out of memory exporting GMP value");
    size_t count = 0;
    mpz_export(tmp, &count, -1, sizeof(uint64_t), 0, 0, z);
    while (count > 0 && tmp[count - 1] == 0) count--;

    int ok = (count == (size_t)len) && memcmp(tmp, limbs, (size_t)len * sizeof(uint64_t)) == 0;
    free(tmp);
    return ok;
}

static double bench_gmp_mul(const uint64_t *a0, const uint64_t *b, int32_t limbs, int iters) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in GMP multiply benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    mpn_mul_n((mp_limb_t *)out, (const mp_limb_t *)a, (const mp_limb_t *)b, (mp_size_t)limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        mpn_mul_n((mp_limb_t *)out, (const mp_limb_t *)a, (const mp_limb_t *)b, (mp_size_t)limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_sqr(const uint64_t *a0, int32_t limbs, int iters) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in GMP square benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    mpn_sqr((mp_limb_t *)out, (const mp_limb_t *)a, (mp_size_t)limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        mpn_sqr((mp_limb_t *)out, (const mp_limb_t *)a, (mp_size_t)limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_mod1(const uint64_t *a, int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= mpn_mod_1((const mp_limb_t *)a, (mp_size_t)limbs, 1000000007UL + (unsigned long)(i & 1));
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static double bench_gmp_mulmod(int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0xbb67ae8584caa73bULL ^ (uint64_t)limbs);
    uint64_t *b = bench_limbs(limbs, 0x3c6ef372fe94f82bULL ^ (uint64_t)limbs);
    uint64_t *m = bench_limbs(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    m[0] |= 1ULL;

    mpz_t za, zb, zm, zr;
    mpz_inits(za, zb, zm, zr, NULL);
    gmp_import_limbs(za, a, limbs);
    gmp_import_limbs(zb, b, limbs);
    gmp_import_limbs(zm, m, limbs);
    mpz_mul(zr, za, zb);
    mpz_mod(zr, zr, zm);

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_mul(zr, za, zb);
        mpz_mod(zr, zr, zm);
        bench_sink ^= mpz_getlimbn(zr, 0) + (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    mpz_clears(za, zb, zm, zr, NULL);
    free(a);
    free(b);
    free(m);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_mersenne_square(uint64_t p, int iters) {
    WValue s_value = bench_mersenne_residue(p, 0x510e527fade682d1ULL ^ p);
    WValue n_value = bench_mersenne_value(p);
    uint64_t ss, ns;
    int32_t slen, nlen;
    const uint64_t *slimbs = integer_limbs(s_value, &ss, &slen);
    const uint64_t *nlimbs = integer_limbs(n_value, &ns, &nlen);

    mpz_t s, n, r;
    mpz_inits(s, n, r, NULL);
    gmp_import_limbs(s, slimbs, slen);
    gmp_import_limbs(n, nlimbs, nlen);
    mpz_mul(r, s, s);
    mpz_mod(r, r, n);

    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_mul(r, s, s);
        mpz_mod(r, r, n);
        bench_sink ^= mpz_getlimbn(r, 0) + (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    mpz_clears(s, n, r, NULL);
    bench_free_value(s_value);
    bench_free_value(n_value);
    return elapsed * 1e9 / (double)iters;
}

static void check_raw_against_gmp(int32_t limbs, const uint64_t *a, const uint64_t *b) {
    uint64_t *tw = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    uint64_t *gm = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!tw || !gm) die("out of memory in GMP check");
    bigint_mul_dispatch(tw, a, limbs, b, limbs);
    mpn_mul_n((mp_limb_t *)gm, (const mp_limb_t *)a, (const mp_limb_t *)b, (mp_size_t)limbs);
    assert_same_limbs("mul", tw, gm, 2 * limbs);
    bigint_sqr_dispatch(tw, a, limbs);
    mpn_sqr((mp_limb_t *)gm, (const mp_limb_t *)a, (mp_size_t)limbs);
    assert_same_limbs("sqr", tw, gm, 2 * limbs);
    free(tw);
    free(gm);
}

static void check_mod1_against_gmp(const uint64_t *a, int32_t limbs) {
    static const uint64_t divisors[] = {
        1ULL, 2ULL, 3ULL, 7ULL, 0xffffULL, 0x10000ULL,
        0x7fffffffULL, 0x80000000ULL, 1000000007ULL,
        0xfffffffbULL, 0xffffffffULL, 0x100000000ULL,
        0x100000001ULL, 0x7fffffffffffffffULL, UINT64_MAX
    };
    for (size_t i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        uint64_t tw = mag_mod_single(a, limbs, divisors[i]);
        uint64_t gm = (uint64_t)mpn_mod_1((const mp_limb_t *)a,
                                          (mp_size_t)limbs,
                                          (mp_limb_t)divisors[i]);
        if (tw != gm) die("single-limb remainder mismatch vs GMP");
    }
}

static void check_mod_against_gmp(int32_t limbs) {
    WValue a = bench_bigint(limbs, 0xbb67ae8584caa73bULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x3c6ef372fe94f82bULL ^ (uint64_t)limbs);
    WValue m = bench_bigint(limbs, 0xa54ff53a5f1d36f1ULL ^ (uint64_t)limbs);
    w_as_bigint(m)->limbs[0] |= 1ULL;
    WValue reduced_a = w_mod(a, m);
    WValue reduced_b = w_mod(b, m);
    WPrimeModCtx ctx;
    w_prime_modctx_init(&ctx, m);
    WValue mul_a = reduced_a, mul_b = reduced_b;
    if (ctx.mont) {
        mul_a = bench_clone_integer(w_prime_modctx_to_domain(&ctx, reduced_a));
        mul_b = bench_clone_integer(w_prime_modctx_to_domain(&ctx, reduced_b));
    }
    WValue tw = w_prime_modctx_mul(&ctx, mul_a, mul_b);
    if (ctx.mont) tw = w_prime_modctx_mul(&ctx, tw, w_box_int(1));

    mpz_t za, zb, zm, zr;
    mpz_inits(za, zb, zm, zr, NULL);
    uint64_t scratch;
    int32_t len;
    const uint64_t *limbs_a = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, limbs_a, len);
    const uint64_t *limbs_b = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, limbs_b, len);
    const uint64_t *limbs_m = integer_limbs(m, &scratch, &len);
    gmp_import_limbs(zm, limbs_m, len);
    mpz_mul(zr, za, zb);
    mpz_mod(zr, zr, zm);
    if (!value_matches_mpz(tw, zr)) die("modctx mulmod mismatch vs GMP");

    mpz_clears(za, zb, zm, zr, NULL);
    w_prime_modctx_fini(&ctx);
    if (ctx.mont) {
        bench_free_value(mul_a);
        bench_free_value(mul_b);
    }
    if (reduced_a != a) bench_free_value(reduced_a);
    if (reduced_b != b) bench_free_value(reduced_b);
    bench_free_value(a);
    bench_free_value(b);
    bench_free_value(m);
}
#endif

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    const int32_t sizes[] = {64, 256, 1024, 2048, 4096, 8192, 16384};
    printf("Big math benchmark (ns/op, lower is better)\n");
#ifdef HAVE_GMP
    printf("GMP comparison enabled\n\n");
#else
    printf("GMP comparison disabled; install GMP and compile with -DHAVE_GMP -lgmp\n\n");
#endif

#ifdef HAVE_GMP
    printf("limbs     bits  tungsten mul   gmp mul   gap  tungsten sqr   gmp sqr   gap\n");
#else
    printf("limbs     bits  tungsten mul  tungsten sqr\n");
#endif
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        int32_t limbs = sizes[i];
        int iters = bench_iters_for_limbs(limbs);
        uint64_t *a = bench_limbs(limbs, 0x123456789abcdef0ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(limbs, 0xfedcba9876543210ULL ^ (uint64_t)limbs);
#ifdef HAVE_GMP
        check_raw_against_gmp(limbs, a, b);
        check_mod1_against_gmp(a, limbs);
#endif
        double tw_mul = bench_tungsten_mul(a, b, limbs, iters);
        double tw_sqr = bench_tungsten_sqr(a, limbs, iters);
#ifdef HAVE_GMP
        double gm_mul = bench_gmp_mul(a, b, limbs, iters);
        double gm_sqr = bench_gmp_sqr(a, limbs, iters);
        printf("%5d %8d %13.1f %9.1f %5.2fx %13.1f %9.1f %5.2fx\n",
               limbs, limbs * 64, tw_mul, gm_mul, ratio(tw_mul, gm_mul), tw_sqr, gm_sqr, ratio(tw_sqr, gm_sqr));
#else
        printf("%5d %8d %13.1f %13.1f\n", limbs, limbs * 64, tw_mul, tw_sqr);
#endif
        free(a);
        free(b);
    }

#ifdef HAVE_GMP
    printf("\nsmall modulus and generic modular multiply\n");
    printf("limbs  tungsten mod1  old mod1 speedup  gmp mod1   gap  tungsten ctxmulmod gmp mulmod   gap\n");
#else
    printf("\nsmall modulus and generic modular multiply\n");
    printf("limbs  tungsten mod1  old mod1 speedup  tungsten ctxmulmod\n");
#endif
    const int32_t mod_sizes[] = {1, 2, 4, 16, 64, 256, 1024, 2048};
    for (size_t i = 0; i < sizeof(mod_sizes) / sizeof(mod_sizes[0]); i++) {
        int32_t limbs = mod_sizes[i];
        int iters = bench_iters_for_mod(limbs);
        uint64_t *a = bench_limbs(limbs, 0x6a09e667f3bcc909ULL ^ (uint64_t)limbs);
        double tw_mod1 = bench_tungsten_mod1(a, limbs, iters * 10);
        double old_mod1 = bench_tungsten_mod1_ref(a, limbs, iters * 10);
        double tw_mulmod = bench_tungsten_ctx_mulmod(limbs, iters);
#ifdef HAVE_GMP
        check_mod_against_gmp(limbs);
        double gm_mod1 = bench_gmp_mod1(a, limbs, iters * 10);
        double gm_mulmod = bench_gmp_mulmod(limbs, iters);
        printf("%5d %14.1f %9.1f %6.2fx %9.1f %5.2fx %19.1f %10.1f %5.2fx\n",
               limbs, tw_mod1, old_mod1, ratio(old_mod1, tw_mod1), gm_mod1,
               ratio(tw_mod1, gm_mod1), tw_mulmod, gm_mulmod, ratio(tw_mulmod, gm_mulmod));
#else
        printf("%5d %14.1f %9.1f %6.2fx %19.1f\n",
               limbs, tw_mod1, old_mod1, ratio(old_mod1, tw_mod1), tw_mulmod);
#endif
        free(a);
    }

    printf("\nMersenne square mod: s^2 mod (2^p-1)\n");
#ifdef HAVE_GMP
    printf("p          tungsten direct    gmp mpz   gap\n");
#else
    printf("p          tungsten direct\n");
#endif
    const struct { uint64_t p; int iters; } mersenne[] = {
        {127, 400}, {521, 120}, {1279, 40}, {3217, 12}, {8191, 4}
    };
    for (size_t i = 0; i < sizeof(mersenne) / sizeof(mersenne[0]); i++) {
        uint64_t p = mersenne[i].p;
        int iters = mersenne[i].iters;
        double tw = bench_tungsten_mersenne_square(p, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mersenne_square(p, iters);
        printf("%-8llu %16.1f %10.1f %5.2fx\n", (unsigned long long)p, tw, gm, ratio(tw, gm));
#else
        printf("%-8llu %16.1f\n", (unsigned long long)p, tw);
#endif
    }

    printf("\nsink=%llu\n", (unsigned long long)bench_sink);
    return 0;
}

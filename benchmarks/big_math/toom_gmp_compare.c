#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <gmp.h>
#if GMP_LIMB_BITS != 64
#error "This benchmark expects 64-bit GMP limbs."
#endif

/*
 * GMP keeps these Toom kernels internal, but Homebrew's GMP dylib exports them.
 * Signatures and scratch sizing are from GMP 6.3.0 gmp-impl.h.
 */
extern void __gmpn_toom22_mul(mp_ptr, mp_srcptr, mp_size_t, mp_srcptr, mp_size_t, mp_ptr);
extern void __gmpn_toom33_mul(mp_ptr, mp_srcptr, mp_size_t, mp_srcptr, mp_size_t, mp_ptr);
extern void __gmpn_toom44_mul(mp_ptr, mp_srcptr, mp_size_t, mp_srcptr, mp_size_t, mp_ptr);

#include "../../runtime/runtime.c"

static volatile uint64_t compare_sink;

typedef void (*TungstenToomFn)(uint64_t *, const uint64_t *, const uint64_t *, int32_t, uint64_t *);
typedef void (*GmpToomFn)(mp_ptr, mp_srcptr, mp_size_t, mp_srcptr, mp_size_t, mp_ptr);

typedef struct {
    const char *name;
    TungstenToomFn tungsten;
    GmpToomFn gmp;
    size_t (*gmp_scratch)(int32_t);
    const int32_t *sizes;
    size_t size_count;
} ToomCase;

static double compare_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static uint64_t compare_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static uint64_t *compare_limbs(int32_t n, uint64_t seed) {
    uint64_t *limbs = (uint64_t *)calloc((size_t)n, sizeof(uint64_t));
    if (!limbs) die("out of memory allocating compare limbs");
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) limbs[i] = compare_rng(&state);
    limbs[0] |= 1ULL;
    limbs[n - 1] |= 1ULL << 63;
    return limbs;
}

static int compare_iters(int32_t n) {
    if (n <= 64) return 1400;
    if (n <= 128) return 700;
    if (n <= 256) return 300;
    if (n <= 512) return 120;
    if (n <= 1024) return 50;
    return 20;
}

static size_t tungsten_scratch_len(int32_t n) {
    size_t dispatch_need = bn_scratch_need(n);
    size_t forced_need = (size_t)n * 128U + 4096U;
    return dispatch_need > forced_need ? dispatch_need : forced_need;
}

static size_t gmp_toom22_scratch(int32_t n) {
    return 2U * ((size_t)n + (size_t)GMP_LIMB_BITS);
}

static size_t gmp_toom33_scratch(int32_t n) {
    return 3U * (size_t)n + (size_t)GMP_LIMB_BITS;
}

static size_t gmp_toom44_scratch(int32_t n) {
    return 3U * (size_t)n + (size_t)GMP_LIMB_BITS;
}

static void compare_check(const char *label, const uint64_t *got, const uint64_t *want, int32_t n) {
    for (int32_t i = 0; i < 2 * n; i++) {
        if (got[i] != want[i]) {
            fprintf(stderr, "%s mismatch at n=%d limb=%d\n", label, n, i);
            exit(1);
        }
    }
}

static double time_tungsten_once(TungstenToomFn fn, const uint64_t *a0, const uint64_t *b,
                                 const uint64_t *ref, int32_t n, int iters, const char *label) {
    uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)2 * n + 4U, sizeof(uint64_t));
    uint64_t *scratch = (uint64_t *)calloc(tungsten_scratch_len(n), sizeof(uint64_t));
    if (!a || !out || !scratch) die("out of memory in Tungsten Toom compare");

    memcpy(a, a0, (size_t)n * sizeof(uint64_t));
    fn(out, a, b, n, scratch);
    compare_check(label, out, ref, n);

    uint64_t saved = a[0];
    double start = compare_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        fn(out, a, b, n, scratch);
        compare_sink ^= out[(unsigned)i % ((unsigned)n * 2U)];
    }
    double elapsed = compare_now() - start;
    free(scratch);
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double time_gmp_once(GmpToomFn fn, size_t (*scratch_len)(int32_t),
                            const uint64_t *a0, const uint64_t *b,
                            const uint64_t *ref, int32_t n, int iters, const char *label) {
    uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)2 * n + 4U, sizeof(uint64_t));
    mp_limb_t *scratch = (mp_limb_t *)calloc(scratch_len(n) + 64U, sizeof(mp_limb_t));
    if (!a || !out || !scratch) die("out of memory in GMP Toom compare");

    memcpy(a, a0, (size_t)n * sizeof(uint64_t));
    fn((mp_ptr)out, (mp_srcptr)a, (mp_size_t)n, (mp_srcptr)b, (mp_size_t)n, scratch);
    compare_check(label, out, ref, n);

    uint64_t saved = a[0];
    double start = compare_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        fn((mp_ptr)out, (mp_srcptr)a, (mp_size_t)n, (mp_srcptr)b, (mp_size_t)n, scratch);
        compare_sink ^= out[(unsigned)i % ((unsigned)n * 2U)];
    }
    double elapsed = compare_now() - start;
    free(scratch);
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double best_tungsten(TungstenToomFn fn, const uint64_t *a, const uint64_t *b,
                            const uint64_t *ref, int32_t n, int iters, const char *label) {
    double best = time_tungsten_once(fn, a, b, ref, n, iters, label);
    for (int i = 1; i < 3; i++) {
        double next = time_tungsten_once(fn, a, b, ref, n, iters, label);
        if (next < best) best = next;
    }
    return best;
}

static double best_gmp(GmpToomFn fn, size_t (*scratch_len)(int32_t),
                       const uint64_t *a, const uint64_t *b, const uint64_t *ref,
                       int32_t n, int iters, const char *label) {
    double best = time_gmp_once(fn, scratch_len, a, b, ref, n, iters, label);
    for (int i = 1; i < 3; i++) {
        double next = time_gmp_once(fn, scratch_len, a, b, ref, n, iters, label);
        if (next < best) best = next;
    }
    return best;
}

static void run_case(const ToomCase *tc) {
    printf("\n%s forced multiply (best of 3, ns/op)\n", tc->name);
    printf("limbs       ours        gmp    ours/gmp\n");
    for (size_t i = 0; i < tc->size_count; i++) {
        int32_t n = tc->sizes[i];
        int iters = compare_iters(n);
        uint64_t *a = compare_limbs(n, 0x123456789abcdef0ULL ^ (uint64_t)n);
        uint64_t *b = compare_limbs(n, 0xfedcba9876543210ULL ^ (uint64_t)n);
        uint64_t *ref = (uint64_t *)calloc((size_t)2 * n + 4U, sizeof(uint64_t));
        if (!ref) die("out of memory in GMP reference");
        mpn_mul_n((mp_ptr)ref, (mp_srcptr)a, (mp_srcptr)b, (mp_size_t)n);

        double ours = best_tungsten(tc->tungsten, a, b, ref, n, iters, tc->name);
        double gmp = best_gmp(tc->gmp, tc->gmp_scratch, a, b, ref, n, iters, tc->name);
        printf("%5d %10.1f %10.1f %8.2fx\n", n, ours, gmp, ours / gmp);

        free(ref);
        free(a);
        free(b);
    }
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    static const int32_t toom2_sizes[] = {32, 40, 48, 64, 80, 96, 128};
    static const int32_t toom3_sizes[] = {128, 144, 160, 192, 224, 256, 320, 384, 512};
    static const int32_t toom4_sizes[] = {384, 448, 512, 640, 768, 1024, 1536, 2048};
    static const ToomCase cases[] = {
        {"Toom-2 / GMP toom22", bn_toom2, __gmpn_toom22_mul, gmp_toom22_scratch,
         toom2_sizes, sizeof(toom2_sizes) / sizeof(toom2_sizes[0])},
        {"Toom-3 / GMP toom33", bn_toom3, __gmpn_toom33_mul, gmp_toom33_scratch,
         toom3_sizes, sizeof(toom3_sizes) / sizeof(toom3_sizes[0])},
        {"Toom-4 / GMP toom44", bn_toom4, __gmpn_toom44_mul, gmp_toom44_scratch,
         toom4_sizes, sizeof(toom4_sizes) / sizeof(toom4_sizes[0])}
    };

    printf("Tungsten forced Toom vs GMP forced Toom kernels\n");
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) run_case(&cases[i]);
    printf("\nsink=%llu\n", (unsigned long long)compare_sink);
    return 0;
}

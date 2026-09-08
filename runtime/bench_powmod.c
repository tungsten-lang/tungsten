#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Times bigint_powmod_any on RSA-shaped inputs: odd k-limb moduli with the
 * top bit set, small public exponents (3, 65537) and a full-width exponent.
 * Includes runtime.c directly, like bench_bigint.c. */
#include "runtime.c"

static double bench_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static uint64_t bench_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static WValue bench_value(int32_t n, uint64_t seed, int modulus) {
    WBigint *b = bigint_alloc(n);
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) b->limbs[i] = bench_rng(&state);
    if (modulus) { b->limbs[0] |= 1ULL; b->limbs[n - 1] |= 1ULL << 63; }
    else b->limbs[n - 1] &= ~(1ULL << 63);      /* base < modulus */
    b->size = n;
    return bigint_box(b);
}

static void bench_run(const char *name, WValue base, WValue e, WValue m, int iters) {
    uint64_t sum = 0;
    for (int i = 0; i < 3; i++) {
        WValue r = bigint_powmod_any(base, e, m);
        uint64_t s; int32_t l; const uint64_t *rl = integer_limbs(r, &s, &l);
        sum += l ? rl[0] : 0;
        if (w_is_bigint(r)) bigint_backing_free(w_as_bigint(r));
    }
    double t0 = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = bigint_powmod_any(base, e, m);
        uint64_t s; int32_t l; const uint64_t *rl = integer_limbs(r, &s, &l);
        sum += l ? rl[0] : 0;
        if (w_is_bigint(r)) bigint_backing_free(w_as_bigint(r));
    }
    double dt = (bench_now() - t0) / iters;
    printf("%-28s %10.2f us/op   (checksum %016llx)\n", name, dt * 1e6,
           (unsigned long long)sum);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    int32_t ks[3] = {8, 16, 32};
    for (int ki = 0; ki < 3; ki++) {
        int32_t k = ks[ki];
        WValue m = bench_value(k, 0x9e3779b97f4a7c15ULL + (uint64_t)k, 1);
        WValue b = bench_value(k, 0xd1b54a32d192ed03ULL + (uint64_t)k, 0);
        WValue efull = bench_value(k, 0xa0761d6478bd642fULL + (uint64_t)k, 0);
        char name[64];
        int base_iters = k == 32 ? 400 : k == 16 ? 1500 : 4000;
        snprintf(name, sizeof name, "k=%d e=3", k);
        bench_run(name, b, w_box_int(3), m, base_iters);
        snprintf(name, sizeof name, "k=%d e=65537", k);
        bench_run(name, b, w_box_int(65537), m, base_iters / 3);
        snprintf(name, sizeof name, "k=%d e=full(%d bits)", k, 64 * k);
        bench_run(name, b, efull, m, base_iters / 40 + 5);
    }
    return 0;
}

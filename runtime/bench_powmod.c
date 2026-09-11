#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <limits.h>

/* Times bigint_powmod_any on RSA-shaped inputs: odd k-limb moduli with the
 * top bit set, small public exponents (3, 65537) and a full-width exponent.
 * Includes runtime.c directly, like bench_bigint.c. */
#include "runtime.c"

static const char *bench_filter;
static int bench_iters, bench_matched;

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
    if (bench_filter && strcmp(name, bench_filter) != 0) return;
    bench_matched++;
    if (bench_iters) iters = bench_iters;
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
    printf("%-28s %10.4f us/op   (checksum %016llx)\n", name, dt * 1e6,
           (unsigned long long)sum);
}

static void bench_fermat(void) {
    const uint64_t primes[2][4] = {
        {0x3c208c16d87cfd47ULL, 0x97816a916871ca8dULL,
         0xb85045b68181585dULL, 0x30644e72e131a029ULL},
        {0xfffffffefffffc2fULL, UINT64_MAX, UINT64_MAX, UINT64_MAX}
    };
    const char *names[2] = {"bn254", "secp256k1"};
    for (int i = 0; i < 2; i++) {
        WBigint *m = bigint_alloc(4), *e = bigint_alloc(4);
        memcpy(m->limbs, primes[i], sizeof primes[i]);
        memcpy(e->limbs, primes[i], sizeof primes[i]);
        m->size = e->size = 4;
        e->limbs[0]--;
        char name[64];
        snprintf(name, sizeof name, "%s e=p-1", names[i]);
        if (bigint_powmod_any(w_box_int(2), bigint_box(e), bigint_box(m)) != w_box_int(1)) {
            fprintf(stderr, "incorrect Fermat result: %s\n", names[i]);
            exit(1);
        }
        bench_run(name, w_box_int(2), bigint_box(e), bigint_box(m), 1000000);
        e->limbs[0]--;                 /* guard miss: ordinary inversion */
        snprintf(name, sizeof name, "%s e=p-2", names[i]);
        bench_run(name, w_box_int(2), bigint_box(e), bigint_box(m), 20000);
        bigint_backing_free(e);
        bigint_backing_free(m);
    }
}

int main(int argc, char **argv) {
    if (argc != 1) {
        char *end;
        errno = 0;
        long count = argc == 4 ? strtol(argv[3], &end, 10) : 0;
        if (argc != 4 || strcmp(argv[1], "--block") || errno ||
            count <= 0 || count > INT_MAX || *end) {
            fprintf(stderr, "usage: %s [--block 'case name' iterations]\n", argv[0]);
            return 2;
        }
        bench_filter = argv[2];
        bench_iters = (int)count;
    }
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
    bench_fermat();
    if (!bench_matched) {
        fprintf(stderr, "unknown benchmark case: %s\n", bench_filter);
        return 2;
    }
    return 0;
}

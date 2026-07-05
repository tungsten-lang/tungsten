/* Verify SSMR hashed single-base strong MR against Jaeschke {2,7,61} on [2^32, 4.76e9).
 *
 *   cc -O3 -march=native -o gen_ssmr_verify gen_ssmr_verify.c && ./gen_ssmr_verify
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "ssmr_witness.h"

static uint64_t w_mont_ninv(uint64_t n) {
    uint64_t inv = n;
    for (int i = 0; i < 5; i++) inv *= 2ULL - n * inv;
    return inv;
}

static uint64_t w_mont_mul(uint64_t a, uint64_t b, uint64_t n, uint64_t np) {
    __uint128_t x = (__uint128_t)a * b;
    uint64_t m = (uint64_t)x * np;
    __uint128_t mn = (__uint128_t)m * n;
    uint64_t x_hi = (uint64_t)(x >> 64), x_lo = (uint64_t)x;
    uint64_t mn_hi = (uint64_t)(mn >> 64), mn_lo = (uint64_t)mn;
    uint64_t carry = (x_lo + mn_lo) < x_lo;
    uint64_t res = x_hi + mn_hi + carry;
    int of = (res < x_hi) || (carry && res == x_hi);
    if (of || res >= n) res -= n;
    return res;
}

static int mont_mr(uint64_t n, const uint64_t *bases, size_t nb) {
    if ((n & 1ULL) == 0ULL) return n == 2ULL;
    uint64_t np = 0ULL - w_mont_ninv(n);
    uint64_t one_m = (0ULL - n) % n;
    uint64_t r2 = (n <= 0xFFFFFFFFULL) ? (one_m * one_m) % n
                                       : (uint64_t)(((__uint128_t)one_m * one_m) % n);
    uint64_t nm1_m = n - one_m;
    int s = __builtin_ctzll(n - 1ULL);
    uint64_t d = (n - 1ULL) >> s;
    for (size_t i = 0; i < nb; i++) {
        uint64_t a = bases[i] % n;
        if (a == 0ULL) continue;
        uint64_t xm = one_m, bm = w_mont_mul(a, r2, n, np), e = d;
        while (e != 0ULL) {
            if ((e & 1ULL) != 0ULL) xm = w_mont_mul(xm, bm, n, np);
            bm = w_mont_mul(bm, bm, n, np);
            e >>= 1;
        }
        if (xm == one_m || xm == nm1_m) continue;
        int ok = 0;
        for (int r = 1; r < s; r++) {
            xm = w_mont_mul(xm, xm, n, np);
            if (xm == nm1_m) { ok = 1; break; }
        }
        if (!ok) return 0;
    }
    return 1;
}

static int b3(uint64_t n) {
    static const uint64_t B3[] = {2ULL, 7ULL, 61ULL};
    return mont_mr(n, B3, 3);
}

static inline uint32_t ssmr_idx(uint64_t n) {
    return ((uint32_t)n * W_SSMR_HASH_MUL) >> 14;
}

static int ssmr1(uint64_t n) {
    uint64_t base = W_SSMR_WITNESS[ssmr_idx(n)];
    return mont_mr(n, &base, 1);
}

static int small_composite(uint64_t n) {
    static const uint64_t P[] = {3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97};
    for (size_t i = 0; i < sizeof(P)/sizeof(P[0]); i++)
        if (n % P[i] == 0ULL) return 1;
    return 0;
}

int main(void) {
    const uint64_t LO = 4294967296ULL;
    const uint64_t HI = 4759123140ULL;
    uint64_t mism = 0, first = 0;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (uint64_t n = LO | 1ULL; n <= HI; n += 2ULL) {
        if (small_composite(n)) continue;
        int a = b3(n), b = ssmr1(n);
        if (a != b) {
            mism++;
            if (!first) first = n;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double sec = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9;
    printf("mismatches=%llu first=%llu (%.1fs)\n",
           (unsigned long long)mism, (unsigned long long)first, sec);
    return mism ? 1 : 0;
}
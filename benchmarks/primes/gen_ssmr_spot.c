#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "ssmr_witness.h"
/* same helpers as gen_ssmr_verify.c - include minimal */
static uint64_t w_mont_ninv(uint64_t n) { uint64_t inv = n; for (int i = 0; i < 5; i++) inv *= 2ULL - n * inv; return inv; }
static uint64_t w_mont_mul(uint64_t a, uint64_t b, uint64_t n, uint64_t np) {
    __uint128_t x = (__uint128_t)a * b; uint64_t m = (uint64_t)x * np; __uint128_t mn = (__uint128_t)m * n;
    uint64_t x_hi = (uint64_t)(x >> 64), x_lo = (uint64_t)x, mn_hi = (uint64_t)(mn >> 64), mn_lo = (uint64_t)mn;
    uint64_t carry = (x_lo + mn_lo) < x_lo; uint64_t res = x_hi + mn_hi + carry;
    if ((res < x_hi) || (carry && res == x_hi) || res >= n) res -= n; return res;
}
static int mont_mr(uint64_t n, const uint64_t *bases, size_t nb) {
    if ((n & 1ULL) == 0ULL) return n == 2ULL;
    uint64_t np = 0ULL - w_mont_ninv(n), one_m = (0ULL - n) % n;
    uint64_t r2 = (n <= 0xFFFFFFFFULL) ? (one_m * one_m) % n : (uint64_t)(((__uint128_t)one_m * one_m) % n);
    uint64_t nm1_m = n - one_m; int s = __builtin_ctzll(n - 1ULL); uint64_t d = (n - 1ULL) >> s;
    for (size_t i = 0; i < nb; i++) {
        uint64_t a = bases[i] % n; if (!a) continue;
        uint64_t xm = one_m, bm = w_mont_mul(a, r2, n, np), e = d;
        while (e) { if (e & 1) xm = w_mont_mul(xm, bm, n, np); bm = w_mont_mul(bm, bm, n, np); e >>= 1; }
        if (xm == one_m || xm == nm1_m) continue;
        int ok = 0; for (int r = 1; r < s; r++) { xm = w_mont_mul(xm, xm, n, np); if (xm == nm1_m) { ok = 1; break; } }
        if (!ok) return 0;
    }
    return 1;
}
static int b3(uint64_t n) { static const uint64_t B3[] = {2,7,61}; return mont_mr(n, B3, 3); }
static int ssmr1(uint64_t n) { uint64_t b = W_SSMR_WITNESS[((uint32_t)n * W_SSMR_HASH_MUL) >> 14]; return mont_mr(n, &b, 1); }
int main(void) {
    uint64_t lo = 4294967296ULL, hi = 4759123140ULL; int mism = 0;
    for (int t = 0; t < 200000; t++) {
        uint64_t n = lo + ((uint64_t)rand() % (hi - lo + 1));
        if (!(n & 1)) n++;
        if (b3(n) != ssmr1(n)) { printf("mismatch %llu\n", (unsigned long long)n); mism++; if (mism > 5) break; }
    }
    printf("spot mismatches=%d\n", mism);
    return mism ? 1 : 0;
}

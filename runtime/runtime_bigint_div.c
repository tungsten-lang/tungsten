#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__has_include)
#  if __has_include("generated/bigint_thresholds.h")
#    include "generated/bigint_thresholds.h"
#  endif
#endif
#ifndef BN_KARA_THRESHOLD
#define BN_KARA_THRESHOLD 24
#endif
#ifndef BN_EQ_PAGE_HAZARD_GUARD
#define BN_EQ_PAGE_HAZARD_GUARD 0
#endif
#ifndef BN_EQ_PAGE_HAZARD_FORCE
#define BN_EQ_PAGE_HAZARD_FORCE 0
#endif
#ifndef BN_BIGINT_POOL_MAX_CAP
#define BN_BIGINT_POOL_MAX_CAP (1U << 14)
#endif
#define die w_rt_die
#define dief w_rt_dief
#define die_as w_rt_die_as
#define bigint_box w_rt_bigint_box
#define bn_copy_tail w_rt_bn_copy_tail
#define bigint_alloc w_rt_bigint_alloc
#define bigint_alloc_raw w_rt_bigint_alloc_raw
#define bigint_alloc_raw_hot w_rt_bigint_alloc_raw_hot
#define bigint_alloc_raw_hot_exact w_rt_bigint_alloc_raw_hot_exact
#define bigint_alloc_capacity w_rt_bigint_alloc_capacity
#define bigint_release w_rt_bigint_release
#define bigint_release_if_live w_rt_bigint_release_if_live
#define bigint_normalize w_rt_bigint_normalize
#define bigint_finish_mag_sub w_rt_bigint_finish_mag_sub
#define bigint_finish_one_limb w_rt_bigint_finish_one_limb
#define bigint_finish_div1 w_rt_bigint_finish_div1
#define bigint_from_u64 w_rt_bigint_from_u64
#define integer_limbs w_rt_integer_limbs
#define integer_low_i64 w_rt_integer_low_i64
#define mag_cmp w_rt_mag_cmp
#define bn_add_n w_rt_bn_add_n
#define bn_sub_n w_rt_bn_sub_n
#define bn_mul_1 w_rt_bn_mul_1
#define bn_addmul_1 w_rt_bn_addmul_1
#define bn_addmul_2 w_rt_bn_addmul_2
#define bn_submul_from_1 w_rt_bn_submul_from_1
#define bn_modinv_odd w_rt_bn_modinv_odd
#define bigint_mul_schoolbook_into w_rt_bigint_mul_schoolbook_into
#define bigint_mul_dispatch w_rt_bigint_mul_dispatch
#define bigint_sqr_dispatch w_rt_bigint_sqr_dispatch
#define bn_div_preinv_thread_cache w_rt_bn_div_preinv_thread_cache
#define bn_page_hazard w_rt_bn_page_hazard
#define bn_toom_no_spin (*w_rt_bn_toom_no_spin_ptr())
#define bn_toom_parallel_depth (*w_rt_bn_toom_parallel_depth_ptr())
#define bn_div_recip_diff28_depth (*w_rt_bn_div_recip_diff28_depth_ptr())
#define bn_toom_product_set_init w_rt_bn_toom_product_set_init
#define bn_toom_product_set_add w_rt_bn_toom_product_set_add
#define bn_toom_point_set_run w_rt_bn_toom_point_set_run
#define bigint_abs_alias w_rt_bigint_abs_alias
#define bn_ws_get w_rt_bn_ws_get
#endif

typedef struct {
    uint64_t *key;
    size_t key_cap;
    uint64_t *reciprocal;
    size_t reciprocal_cap;
    uint64_t *product;
    size_t product_cap;
    uint64_t *verification;
    size_t verification_cap;
    int32_t n;
    int state; /* 0 empty, 1/2 admission hits, 3 ready, -1 rejected */
} WDivReciprocalCache;
/* Two independently warmed entries: repeated-divisor call patterns can
 * alternate two eligible divisor widths within one outer operation (the
 * sqrt recursion at an 8192-limb root exactly divides by its 2048- and
 * 1024-limb partial roots each call), and a single entry then evicts the
 * other width mid-warmup on every sighting, so neither ever warms.
 * Entries are selected by key match, replaced empty-first then
 * least-recently-used. */
#ifndef BN_DIV_RECIP_CACHE_ENTRIES
#define BN_DIV_RECIP_CACHE_ENTRIES 2
#endif
static __thread WDivReciprocalCache
    bn_div_recip_caches[BN_DIV_RECIP_CACHE_ENTRIES];
static __thread int bn_div_recip_cache_mru;

/* ---- Bigint division (schoolbook, Knuth Algorithm D simplified) ---- */

/* For normalized d and nh < d, divide nh:B+nl by d using a precomputed
 * reciprocal. A multiply-high estimate plus two bounded corrections replace the compiler's
 * multi-instruction __udivmodti4 helper for every quotient limb. */
#ifndef BN_DIV_QR_AARCH64_FLAGS
#define BN_DIV_QR_AARCH64_FLAGS 1
#endif

static inline uint64_t bn_div_qr_preinv(uint64_t nh, uint64_t nl,
                                        uint64_t d, uint64_t dinv,
                                        uint64_t *rem) {
#if defined(__aarch64__) && BN_DIV_QR_AARCH64_FLAGS
    /* Preserve the borrow flag from the candidate-remainder comparison into
     * both corrections.  C otherwise makes clang materialize the same bit,
     * then consume it in two separate data-processing instructions. */
    uint64_t pl, ph, q, r, adjusted;
    __asm__ volatile(
        "add   %[q], %[nh], #1\n\t"
        "mul   %[pl], %[nh], %[dinv]\n\t"
        "umulh %[ph], %[nh], %[dinv]\n\t"
        "adds  %[pl], %[pl], %[nl]\n\t"
        "adc   %[q], %[q], %[ph]\n\t"
        "msub  %[r], %[q], %[d], %[nl]\n\t"
        "cmp   %[pl], %[r]\n\t"
        "add   %[adjusted], %[r], %[d]\n\t"
        "csel  %[r], %[adjusted], %[r], lo\n\t"
        "sbc   %[q], %[q], xzr"
        : [pl] "=&r" (pl), [ph] "=&r" (ph), [q] "=&r" (q),
          [r] "=&r" (r), [adjusted] "=&r" (adjusted)
        : [nh] "r" (nh), [nl] "r" (nl), [d] "r" (d),
          [dinv] "r" (dinv)
        : "cc");
    if (__builtin_expect(r >= d, 0)) {
        __asm__ volatile("");
        r -= d;
        q++;
    }
    *rem = r;
    return q;
#else
    __uint128_t p = (__uint128_t)nh * dinv;
    uint64_t pl = (uint64_t)p;
    uint64_t ph = (uint64_t)(p >> 64);
    uint64_t ql = pl + nl;
    uint64_t carry = ql < pl;
    uint64_t q = ph + nh + 1 + carry;
    uint64_t r = nl - q * d;
    /* First correction: keep the r+d addend independent of the compare so
     * both issue in parallel right after the msub, leaving one csel on the
     * serial remainder chain (the quotient fixup rides off that chain). */
    uint64_t adjusted = r + d;
    int under = r > ql;
    q -= (uint64_t)under;
    r = under ? adjusted : r;
    if (__builtin_expect(r >= d, 0)) {
        /* The empty asm keeps clang from if-converting this rarely-taken
         * second correction into a csel chain on the per-limb critical
         * path (same trick as bn_udiv_qr_3by2 below). */
        __asm__ volatile("");
        r -= d;
        q++;
    }
    *rem = r;
    return q;
#endif
}

/* floor((2^19 - 3*2^8) / d9) for d9 in [256, 511]: the 11-bit seed of the
 * Moller-Granlund division-free reciprocal iteration below. */
static const uint16_t bn_invert_limb_table[256] = {
    0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6,
    0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b,
    0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754,
    0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720,
    0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee,
    0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf,
    0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693,
    0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669,
    0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640,
    0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a,
    0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6,
    0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3,
    0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2,
    0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592,
    0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574,
    0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556,
    0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a,
    0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520,
    0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506,
    0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed,
    0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5,
    0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be,
    0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8,
    0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493,
    0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e,
    0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a,
    0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457,
    0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444,
    0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432,
    0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421,
    0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410,
    0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400,
};

/* floor((B^2-1)/d) - B for normalized d (top bit set), computed with the
 * branchless Moller-Granlund Newton iteration: a table seed refined to 21,
 * 34, then 64 bits.  This replaces a __udivti3 libcall (and the TLS cache
 * that amortized it) with ~15 straight-line multiply/shift instructions. */
static inline uint64_t bn_invert_limb(uint64_t d) {
    uint64_t v0 = bn_invert_limb_table[(d >> 55) - 256];
    uint64_t d40 = (d >> 24) + 1;
    uint64_t v1 = (v0 << 11) - ((v0 * v0 * d40) >> 40) - 1;
    uint64_t v2 = (v1 << 13) +
                  ((v1 * ((1ULL << 60) - v1 * d40)) >> 47);
    uint64_t d0 = d & 1;
    uint64_t d63 = (d >> 1) + d0;                      /* ceil(d/2) */
    uint64_t e = ((v2 >> 1) & (0 - d0)) - v2 * d63;
    uint64_t v3 = (v2 << 31) +
                  ((uint64_t)(((__uint128_t)v2 * e) >> 64) >> 1);
    uint64_t v4 =
        v3 - (uint64_t)((((__uint128_t)v3 * d) + d) >> 64) - d;
    return v4;
}

/* Two-entry per-thread inverse cache: repeated division by one divisor
 * (radix conversion, modular loops, the common n/1 shapes) skips the
 * ~12-cycle invert_limb chain.  Divisors here are normalized (top bit
 * set), so the zero-initialized entries can never false-hit. */
static inline __attribute__((always_inline))
uint64_t bn_div_preinv_cached(uint64_t d, BnDivPreinvCache *cache) {
#ifndef BN_DIV_PREINV_CACHE
#define BN_DIV_PREINV_CACHE 1
#endif
#if !BN_DIV_PREINV_CACHE
    (void)cache;
    return bn_invert_limb(d);
#else
    if (cache->d[0] == d) return cache->v[0];
    if (cache->d[1] == d) return cache->v[1];
    uint64_t v = bn_invert_limb(d);
    int slot = cache->next & 1;
    cache->next ^= 1;
    cache->d[slot] = d;
    cache->v[slot] = v;
    cache->bpow_ready[slot] = 0;
    return v;
#endif
}

/* floor((B^3-1)/(d1*B+d0)) - B for normalized d1: the 2-limb reciprocal
 * seeding the 3-by-2 division steps below. */
static inline uint64_t bn_invert_pi1(uint64_t d1, uint64_t d0) {
    uint64_t v = bn_invert_limb(d1);
    uint64_t p = d1 * v;
    p += d0;
    if (p < d0) {
        v--;
        uint64_t mask = 0 - (uint64_t)(p >= d1);
        p -= d1;
        v += mask;
        p -= mask & d1;
    }
    __uint128_t t = (__uint128_t)d0 * v;
    uint64_t t1 = (uint64_t)(t >> 64);
    uint64_t t0 = (uint64_t)t;
    p += t1;
    if (p < t1) {
        v--;
        if (p >= d1 && (p > d1 || t0 >= d0)) v--;
    }
    return v;
}

/* Divide (n2,n1,n0) by the normalized 2-limb divisor (d1,d0) with the
 * precomputed 3/2 reciprocal: one umulh, a few adds, and one unlikely fixup.
 * Requires (n2,n1) < (d1,d0); yields the exact digit
 * and 2-limb remainder, so no refine loop and no add-back are needed. */
static inline uint64_t bn_udiv_qr_3by2(uint64_t n2, uint64_t n1, uint64_t n0,
                                       uint64_t d1, uint64_t d0,
                                       uint64_t dinv,
                                       uint64_t *r1p, uint64_t *r0p) {
    __uint128_t qq = (__uint128_t)n2 * dinv;
    qq += ((__uint128_t)n2 << 64) | n1;
    uint64_t q = (uint64_t)(qq >> 64);
    uint64_t q0 = (uint64_t)qq;
    __uint128_t r = ((__uint128_t)(n1 - d1 * q) << 64) | n0;
    r -= ((__uint128_t)d1 << 64) | d0;
    r -= (__uint128_t)q * d0;
    uint64_t r1 = (uint64_t)(r >> 64);
    q++;
    uint64_t mask = 0 - (uint64_t)(r1 >= q0);
    q += mask;
    r += ((__uint128_t)(mask & d1) << 64) | (mask & d0);
    if (__builtin_expect(
            r >= (((__uint128_t)d1 << 64) | d0), 0)) {
        /* The empty asm keeps clang from if-converting this ~never-taken
         * fixup into a csel chain on the per-digit critical path. */
        __asm__ volatile("");
        q++;
        r -= ((__uint128_t)d1 << 64) | d0;
    }
    *r1p = (uint64_t)(r >> 64);
    *r0p = (uint64_t)r;
    return q;
}

#ifndef BN_DIV1_2WAY
#define BN_DIV1_2WAY 1
#endif
#if BN_DIV1_2WAY
static inline void bn_div_preinv_bpow_fill(uint64_t *bpow, uint64_t d,
                                           uint64_t dinv) {
    uint64_t r = 0 - d; /* B^1 mod d = 2^64 - d < d for normalized d */
    bpow[0] = r;
    for (int k = 1; k < 8; k++) {
        (void)bn_div_qr_preinv(r, 0, d, dinv, &r);
        bpow[k] = r;
    }
    __uint128_t sq = (__uint128_t)r * r;
    (void)bn_div_qr_preinv((uint64_t)(sq >> 64), (uint64_t)sq, d, dinv, &r);
    bpow[8] = r; /* B^16 mod d */
}

static inline const uint64_t *bn_div_preinv_bpow_cached(
    uint64_t d, uint64_t dinv, BnDivPreinvCache *cache,
    uint64_t bpow_stack[9]) {
#if BN_DIV_PREINV_CACHE
    if (cache) {
        int slot = (cache->d[0] == d) ? 0 : ((cache->d[1] == d) ? 1 : -1);
        if (__builtin_expect(slot >= 0, 1)) {
            if (__builtin_expect(!cache->bpow_ready[slot], 0)) {
                bn_div_preinv_bpow_fill(cache->bpow[slot], d, dinv);
                cache->bpow_ready[slot] = 1;
            }
            return cache->bpow[slot];
        }
    }
#else
    (void)cache;
#endif
    bn_div_preinv_bpow_fill(bpow_stack, d, dinv);
    return bpow_stack;
}

static inline __attribute__((always_inline))
uint64_t bn_mod_fold8_step(uint64_t r_in, uint64_t bp_top,
                           const uint64_t *p, const uint64_t *bpow,
                           uint64_t d, uint64_t dinv) {
    __uint128_t s1 = (__uint128_t)p[7] * bpow[6] + p[0];
    __uint128_t s2 = (__uint128_t)p[6] * bpow[5];
    __uint128_t s3 = (__uint128_t)p[5] * bpow[4];
    __uint128_t s4 = (__uint128_t)p[4] * bpow[3];
    __uint128_t s5 = (__uint128_t)p[3] * bpow[2];
    __uint128_t s6 = (__uint128_t)p[2] * bpow[1];
    __uint128_t s7 = (__uint128_t)p[1] * bpow[0];
    __uint128_t lo0 = (__uint128_t)(uint64_t)s1 + (uint64_t)s2 +
                      (uint64_t)s3 + (uint64_t)s4;
    __uint128_t lo1 = (__uint128_t)(uint64_t)s5 + (uint64_t)s6 +
                      (uint64_t)s7;
    __uint128_t lo_a = (__uint128_t)(uint64_t)lo0 + (uint64_t)lo1;
    __uint128_t hi_a = (s1 >> 64) + (s2 >> 64) + (s3 >> 64) + (s4 >> 64) +
                       (s5 >> 64) + (s6 >> 64) + (s7 >> 64) +
                       (lo0 >> 64) + (lo1 >> 64) + (lo_a >> 64);
    __uint128_t s0 = (__uint128_t)r_in * bp_top + (uint64_t)lo_a;
    __uint128_t hi = hi_a + (s0 >> 64);
    uint64_t r;
    (void)bn_div_qr_preinv((uint64_t)(hi >> 64), (uint64_t)hi, d, dinv, &r);
    (void)bn_div_qr_preinv(r, (uint64_t)s0, d, dinv, &r);
    return r;
}

static inline uint64_t bn_mod_fold_slice(const uint64_t *p, int32_t len,
                                         const uint64_t *bpow,
                                         uint64_t d, uint64_t dinv) {
    const uint64_t *cur = p + len;
    uint64_t r;
    if (len >= 16) {
        cur -= 16;
        uint64_t r_hi = bn_mod_fold8_step(0, 0, cur + 8, bpow, d, dinv);
        uint64_t r_lo = bn_mod_fold8_step(0, 0, cur, bpow, d, dinv);
        while (cur - p >= 16) {
            cur -= 16;
            r_hi = bn_mod_fold8_step(r_hi, bpow[8], cur + 8, bpow, d, dinv);
            r_lo = bn_mod_fold8_step(r_lo, bpow[8], cur, bpow, d, dinv);
        }
        __uint128_t comb = (__uint128_t)r_hi * bpow[7] + r_lo;
        (void)bn_div_qr_preinv((uint64_t)(comb >> 64), (uint64_t)comb,
                               d, dinv, &r);
    } else {
        cur -= 8;
        r = bn_mod_fold8_step(0, 0, cur, bpow, d, dinv);
    }
    if (cur > p) {
        cur -= 8;
        r = bn_mod_fold8_step(r, bpow[7], cur, bpow, d, dinv);
    }
    return r;
}
#endif

static uint64_t mag_div_wide_preinv_cached(uint64_t *quotient,
                                           const uint64_t *a, int32_t alen,
                                           uint64_t d,
                                           BnDivPreinvCache *cache) {
    if (d >> 63) {
        uint64_t dinv = bn_div_preinv_cached(d, cache);
#if BN_DIV1_2WAY
        if (quotient && alen >= 32) {
            uint64_t bpow_stack[9];
            const uint64_t *bpow =
                bn_div_preinv_bpow_cached(d, dinv, cache, bpow_stack);
            int32_t hi_fold = (alen >> 1) & ~7;
            int32_t m = alen - hi_fold;
            uint64_t top = a[alen - 1];
            uint64_t q_top = top >= d;
            uint64_t rem_hi = top - (q_top ? d : 0);
            uint64_t rem_lo = bn_mod_fold_slice(a + m, hi_fold, bpow, d, dinv);
            quotient[alen - 1] = q_top;
            int32_t i_hi = alen - 2;
            int32_t i_lo = m - 1;
            for (; i_hi >= m + 1; i_hi -= 2, i_lo -= 2) {
                uint64_t hi0 = a[i_hi], lo0 = a[i_lo];
                uint64_t hi1 = a[i_hi - 1], lo1 = a[i_lo - 1];
                quotient[i_hi] = bn_div_qr_preinv(rem_hi, hi0, d, dinv, &rem_hi);
                quotient[i_lo] = bn_div_qr_preinv(rem_lo, lo0, d, dinv, &rem_lo);
                quotient[i_hi - 1] = bn_div_qr_preinv(rem_hi, hi1, d, dinv, &rem_hi);
                quotient[i_lo - 1] = bn_div_qr_preinv(rem_lo, lo1, d, dinv, &rem_lo);
            }
            if (i_hi == m) {
                quotient[m] = bn_div_qr_preinv(rem_hi, a[m], d, dinv, &rem_hi);
                quotient[i_lo] = bn_div_qr_preinv(rem_lo, a[i_lo], d, dinv, &rem_lo);
                i_lo--;
            }
            for (; i_lo >= 0; i_lo--) {
                quotient[i_lo] = bn_div_qr_preinv(rem_lo, a[i_lo], d, dinv, &rem_lo);
            }
            return rem_lo;
        }
#endif
        uint64_t top = a[alen - 1];
        uint64_t q_top = top >= d;
        uint64_t rem = top - (q_top ? d : 0);
        if (quotient) quotient[alen - 1] = q_top;
        int32_t i = alen - 2;
#if BN_DIV1_2WAY
        if (quotient) {
            for (; i >= 1; i -= 2) {
                uint64_t low_hi = a[i];
                uint64_t low_lo = a[i - 1];
                quotient[i] = bn_div_qr_preinv(rem, low_hi, d, dinv, &rem);
                quotient[i - 1] = bn_div_qr_preinv(rem, low_lo, d, dinv, &rem);
            }
            if (i == 0)
                quotient[0] = bn_div_qr_preinv(rem, a[0], d, dinv, &rem);
        } else {
            for (; i >= 1; i -= 2) {
                uint64_t low_hi = a[i];
                uint64_t low_lo = a[i - 1];
                (void)bn_div_qr_preinv(rem, low_hi, d, dinv, &rem);
                (void)bn_div_qr_preinv(rem, low_lo, d, dinv, &rem);
            }
            if (i == 0)
                (void)bn_div_qr_preinv(rem, a[0], d, dinv, &rem);
        }
#else
        for (; i >= 0; i--) {
            uint64_t q = bn_div_qr_preinv(rem, a[i], d, dinv, &rem);
            if (quotient) quotient[i] = q;
        }
#endif
        return rem;
    }
    unsigned shift = (unsigned)__builtin_clzll(d);
    unsigned rshift = 64 - shift;
    uint64_t normalized_d = d << shift;
    uint64_t dinv = bn_div_preinv_cached(normalized_d, cache);
    uint64_t rem = a[alen - 1] >> rshift;
#if BN_DIV1_2WAY
    /* Software-pipelined two-limbs-per-iteration form of the single-step
     * loop kept under the #else.  The remainder recurrence is inherently
     * serial, but unrolling by two halves the loop overhead and widens the
     * scheduling window so the out-of-order core overlaps the low step's
     * normalized-`low` setup and quotient store with the high step's
     * reciprocal multiply -- the two-steps-in-flight schedule GMP's
     * mpn_divrem_1 uses.  Bit-identical to the serial loop for every input:
     * the two 2-by-1 steps execute in the same high-to-low order and thread
     * the same `rem`, and each `low` word is formed exactly as below (no
     * cross-limb shift-in for limb 0). */
    int32_t i = alen - 1;
    for (; i >= 2; i -= 2) {
        uint64_t low_hi = (a[i] << shift) | (a[i - 1] >> rshift);
        uint64_t low_lo = (a[i - 1] << shift) | (a[i - 2] >> rshift);
        uint64_t q_hi =
            bn_div_qr_preinv(rem, low_hi, normalized_d, dinv, &rem);
        uint64_t q_lo =
            bn_div_qr_preinv(rem, low_lo, normalized_d, dinv, &rem);
        if (quotient) {
            quotient[i] = q_hi;
            quotient[i - 1] = q_lo;
        }
    }
    for (; i >= 0; i--) {
        uint64_t low = a[i] << shift;
        if (i > 0) low |= a[i - 1] >> rshift;
        uint64_t q =
            bn_div_qr_preinv(rem, low, normalized_d, dinv, &rem);
        if (quotient) quotient[i] = q;
    }
#else
    for (int32_t i = alen - 1; i >= 0; i--) {
        uint64_t low = a[i] << shift;
        if (i > 0) low |= a[i - 1] >> rshift;
        uint64_t q =
            bn_div_qr_preinv(rem, low, normalized_d, dinv, &rem);
        if (quotient) quotient[i] = q;
    }
#endif
    return rem >> shift;
}

static uint64_t mag_div_wide_preinv(uint64_t *quotient,
                                    const uint64_t *a, int32_t alen,
                                    uint64_t d) {
    return mag_div_wide_preinv_cached(
        quotient, a, alen, d, bn_div_preinv_thread_cache());
}

#ifndef BN_DIV_SINGLE_PREINV
#define BN_DIV_SINGLE_PREINV 1
#endif
#ifndef BN_DIV_SINGLE_32BIT_RECIP
#if defined(__aarch64__)
#define BN_DIV_SINGLE_32BIT_RECIP 0
#else
#define BN_DIV_SINGLE_32BIT_RECIP 1
#endif
#endif

/* Divide a bigint magnitude by one word into caller-provided storage.  The
 * high-to-low word kernels, and the low-to-high power-of-two shift, are safe
 * when q == a; the latter reads a[i + 1] before overwriting a[i]. */
static inline __attribute__((always_inline))
int32_t mag_div_single_to(uint64_t *q, const uint64_t *a, int32_t alen,
                          uint64_t d, uint64_t *rem,
                          BnDivPreinvCache *cache) {
    if (d == 0) die_as("ZeroDivisionError", "division by zero");

    if (d == 1) {
        if (q != a)
            for (int32_t i = 0; i < alen; i++) q[i] = a[i];
        *rem = 0;
    } else if ((d & (d - 1)) == 0) {
        /* Dividing a base-2^64 magnitude by 2^k is just a cross-limb shift.
         * Avoid the compiler's 128/64 division helper entirely; d == 1 was
         * split out above so every shift count here is in [1, 63]. */
        unsigned shift = (unsigned)__builtin_ctzll(d);
        *rem = alen > 0 ? a[0] & (d - 1) : 0;
        for (int32_t i = 0; i < alen; i++) {
            uint64_t hi = i + 1 < alen ? a[i + 1] : 0;
            q[i] = (a[i] >> shift) | (hi << (64 - shift));
        }
#if BN_DIV_SINGLE_32BIT_RECIP
    } else if (d <= UINT32_MAX) {
        /* Work in base 2^32 so (remainder << 32) | digit always fits in u64.
         * For reciprocal=floor(2^64/d), multiply-high underestimates the exact
         * digit quotient by at most one; the correction updates BOTH quotient
         * and remainder. This replaces one 128/64 helper call per input limb
         * with two multiply-high Barrett steps. */
        uint64_t reciprocal = UINT64_MAX / d;
        if (UINT64_MAX % d == d - 1) reciprocal++;
        uint64_t r = 0;
        for (int32_t i = alen - 1; i >= 0; i--) {
            uint64_t x = (r << 32) | (a[i] >> 32);
            uint64_t qhi = (uint64_t)(((__uint128_t)x * reciprocal) >> 64);
            r = x - qhi * d;
            if (r >= d) {
                r -= d;
                qhi++;
            }

            x = (r << 32) | (a[i] & UINT32_MAX);
            uint64_t qlo = (uint64_t)(((__uint128_t)x * reciprocal) >> 64);
            r = x - qlo * d;
            if (r >= d) {
                r -= d;
                qlo++;
            }
            q[i] = (qhi << 32) | qlo;
        }
        *rem = r;
#endif
    } else {
#if BN_DIV_SINGLE_PREINV
        if (alen == 2 && (d >> 63) != 0) {
            /* With a normalized one-limb divisor, the high quotient digit of
             * a two-limb dividend is only zero or one.  The generic preinverse
             * loop computes it with the same full multiply-high quotient step
             * used for every later digit.  Resolve that first digit directly,
             * leaving just the genuinely 2-by-1 low-digit division.  This is
             * the public 2N/N division shape at N=1 and avoids both a loop
             * trip and an unnecessary reciprocal multiply/fixup chain. */
            uint64_t high = a[1];
            uint64_t high_quotient = high >= d;
            uint64_t r = high - (d & (0 - high_quotient));
            uint64_t dinv = bn_div_preinv_cached(d, cache);
            q[1] = high_quotient;
            q[0] =
                bn_div_qr_preinv(r, a[0], d, dinv, &r);
            *rem = r;
        } else {
            *rem = mag_div_wide_preinv_cached(q, a, alen, d, cache);
        }
#else
        __uint128_t r = 0;
        for (int32_t i = alen - 1; i >= 0; i--) {
            r = (r << 64) | a[i];
            q[i] = (uint64_t)(r / d);
            r %= d;
        }
        *rem = (uint64_t)r;
#endif
    }
    /* Division by one nonzero base-B digit can remove at most one leading
     * digit from a normalized magnitude. */
    if (alen > 0 && q[alen - 1] == 0) alen--;
    return alen;
}

/* Divide bigint magnitude by a single uint64_t divisor. Returns quotient, writes remainder. */
static WBigint *mag_div_single(const uint64_t *a, int32_t alen, uint64_t d, uint64_t *rem) {
    BnDivPreinvCache *cache = bn_div_preinv_thread_cache();
    WBigint *q = bigint_alloc_raw_hot(alen);
    q->size = mag_div_single_to(q->limbs, a, alen, d, rem, cache);
    return q;
}

/* Fixed normalized N/1 quotient for the small boxed lane.  The leading
 * quotient digit is only zero or one; resolving it directly leaves at most
 * three reciprocal steps and avoids both generic division call frames. */
static inline __attribute__((always_inline))
WBigint *mag_div_single_small_normalized(const uint64_t *a, int32_t alen,
                                         uint64_t d) {
    BnDivPreinvCache *cache = bn_div_preinv_thread_cache();
    uint32_t cap = alen <= 2 ? 2U : 4U;
    WBigint *q = bigint_alloc_raw_hot_exact(cap);
    uint64_t dinv = bn_div_preinv_cached(d, cache);
    int32_t top = alen - 1;
    uint64_t high = a[top];
    uint64_t high_quotient = high >= d;
    uint64_t rem = high - (d & (0 - high_quotient));
    q->limbs[top] = high_quotient;
    if (alen == 4)
        q->limbs[2] = bn_div_qr_preinv(rem, a[2], d, dinv, &rem);
    if (alen >= 3)
        q->limbs[1] = bn_div_qr_preinv(rem, a[1], d, dinv, &rem);
    q->limbs[0] = bn_div_qr_preinv(rem, a[0], d, dinv, &rem);
    q->size = alen - (high_quotient == 0);
    return q;
}

/* Exact reduction for x < 2^64 using floor(2^64 / d).  The multiply-high
 * quotient can undershoot by at most one, so a single correction suffices. */
static inline uint64_t mag_reduce_u64_recip(uint64_t x, uint64_t d,
                                            uint64_t reciprocal) {
    uint64_t q = (uint64_t)(((__uint128_t)x * reciprocal) >> 64);
    uint64_t r = x - q * d;
    if (r >= d) r -= d;
    return r;
}

typedef struct {
    uint64_t d;
    uint64_t reciprocal;
    uint64_t bmod;
    uint64_t pow_b[513];
    uint16_t max_power;
    uint8_t valid;
} WMod1Plan;

static __thread WMod1Plan w_mod1_plans[2];
static __thread unsigned w_mod1_plan_next;

static const WMod1Plan *mag_mod1_plan(uint64_t d, int block) {
    WMod1Plan *plan = NULL;
    for (int i = 0; i < 2; i++) {
        if (w_mod1_plans[i].valid && w_mod1_plans[i].d == d) {
            plan = &w_mod1_plans[i];
            break;
        }
    }
    if (!plan) {
        plan = &w_mod1_plans[w_mod1_plan_next++ & 1U];
        plan->d = d;
        plan->reciprocal = UINT64_MAX / d;
        uint64_t rem_max = UINT64_MAX - plan->reciprocal * d;
        if (rem_max == d - 1) plan->reciprocal++;
        plan->bmod = rem_max + 1;
        if (plan->bmod == d) plan->bmod = 0;
        plan->pow_b[0] = 1;
        plan->max_power = 0;
        plan->valid = 1;
    }
    for (int i = (int)plan->max_power + 1; i <= block; i++)
        plan->pow_b[i] = mag_reduce_u64_recip(
            plan->pow_b[i - 1] * plan->bmod, d, plan->reciprocal);
    if (plan->max_power < block) plan->max_power = (uint16_t)block;
    return plan;
}

static uint64_t mag_mod_single(const uint64_t *a, int32_t alen, uint64_t d) {
    /* A 128/64 remainder lowers to a comparatively expensive compiler-runtime
     * helper on targets without native 128-bit division.  Small divisors are
     * common (hashing, primality screens, decimal conversions), so process each
     * limb as two base-2^32 digits with a precomputed reciprocal; the hot loop
     * then needs only multiply-high and one correction, with no division. */
    if (d == 1) return 0;
    if ((d & (d - 1)) == 0) return alen > 0 ? (a[0] & (d - 1)) : 0;
    if (d <= UINT32_MAX) {
        if (alen >= 8) {
            /*
             * Fold blocks of base-2^64 limbs.  Let B = 2^64 mod d.
             * A block contributes
             *
             *   r*B^8 + a[7]*B^7 + ... + a[1]*B + a[0]  (mod d).
             *
             * Every B^i is below the 32-bit divisor, so the nine products fit
             * in u128.  Reducing the high and low halves uses exact
             * multiply-high reciprocal reductions; high*B + low remains below
             * 2^64 because both residues are below d.  Even a 512-limb block
             * fits comfortably in u128 (the sum is below 2^105).  Four
             * independent accumulators hide multiply latency, then one
             * reduction handles the whole block.
             */
            /* The two-entry plan cache amortizes power-table setup.  With warm
             * plans the best fold tracks the input's power-of-two scale,
             * flattening at 512 limbs; wider plans add cold-cache/TLS cost for
             * little further reduction in the number of folds. */
            int block = alen >= 512 ? 512 :
                        alen >= 256 ? 256 :
                        alen >= 128 ? 128 :
                        alen >= 64  ? 64 :
                        alen >= 32  ? 32 :
                        alen >= 16  ? 16 : 8;
            const WMod1Plan *plan = mag_mod1_plan(d, block);
            uint64_t reciprocal = plan->reciprocal;
            uint64_t bmod = plan->bmod;
            const uint64_t *pow_b = plan->pow_b;

            uint64_t r = 0;
            int32_t pos = alen;
            int width = pos % block;
            if (width == 0) width = block;
            while (pos > 0) {
                int32_t base = pos - width;
                __uint128_t acc0 = (__uint128_t)r * pow_b[width];
                __uint128_t acc1 = 0, acc2 = 0, acc3 = 0;
                int j = 0;
                for (; j + 4 <= width; j += 4) {
                    acc0 += (__uint128_t)a[base + j] * pow_b[j];
                    acc1 += (__uint128_t)a[base + j + 1] * pow_b[j + 1];
                    acc2 += (__uint128_t)a[base + j + 2] * pow_b[j + 2];
                    acc3 += (__uint128_t)a[base + j + 3] * pow_b[j + 3];
                }
                for (; j < width; j++)
                    acc0 += (__uint128_t)a[base + j] * pow_b[j];
                __uint128_t acc = (acc0 + acc1) + (acc2 + acc3);
                uint64_t hi_rem = mag_reduce_u64_recip(
                    (uint64_t)(acc >> 64), d, reciprocal);
                uint64_t lo_rem = mag_reduce_u64_recip(
                    (uint64_t)acc, d, reciprocal);
                r = mag_reduce_u64_recip(hi_rem * bmod + lo_rem,
                                         d, reciprocal);
                pos = base;
                width = block;
            }
            return r;
        }

        /* floor(2^64 / d).  For x < 2^64, high64(x * reciprocal)
         * underestimates floor(x / d) by at most one, so one conditional
         * subtraction completes an exact Barrett reduction. */
        uint64_t reciprocal = UINT64_MAX / d;
        if (UINT64_MAX - reciprocal * d == d - 1) reciprocal++;
        uint64_t r = 0;
        for (int32_t i = alen - 1; i >= 0; i--) {
            uint64_t x = (r << 32) | (a[i] >> 32);
            r = mag_reduce_u64_recip(x, d, reciprocal);

            x = (r << 32) | (a[i] & UINT32_MAX);
            r = mag_reduce_u64_recip(x, d, reciprocal);
        }
        return r;
    }
#if BN_DIV_SINGLE_PREINV
    return mag_div_wide_preinv(NULL, a, alen, d);
#else
    __uint128_t r = 0;
    for (int32_t i = alen - 1; i >= 0; i--) {
        r = (r << 64) | a[i];
        r %= d;
    }
    return (uint64_t)r;
#endif
}

#ifndef BN_DIV_TRIANGULAR_Q_CERTIFIED
#define BN_DIV_TRIANGULAR_Q_CERTIFIED 1
#endif
#ifndef BN_DIV_TRIANGULAR_Q_SELECT
#define BN_DIV_TRIANGULAR_Q_SELECT 1
#endif
#ifndef BN_DIV_TRIANGULAR_Q_MIN
#define BN_DIV_TRIANGULAR_Q_MIN 2
#endif
#ifndef BN_DIV_TRIANGULAR_Q_MAX
#define BN_DIV_TRIANGULAR_Q_MAX 384
#endif
#ifndef BN_DIV_Q_LAZY_LOW
#define BN_DIV_Q_LAZY_LOW 1
#endif
#ifndef BN_DIV_Q_FIRST_01
#define BN_DIV_Q_FIRST_01 1
#endif
#ifndef BN_DIV_Q_ALIAS_NORMALIZED_V
#define BN_DIV_Q_ALIAS_NORMALIZED_V 1
#endif
#ifndef BN_DIV_63_DIRECT
#define BN_DIV_63_DIRECT 1
#endif

#if BN_DIV_TRIANGULAR_Q_CERTIFIED
static inline __attribute__((always_inline))
uint64_t bn_submul_fixed_2(uint64_t *rp, const uint64_t *up, uint64_t v) {
    uint64_t borrow = 0;
#if defined(__clang__)
#pragma clang loop unroll(full)
#endif
    for (int32_t i = 0; i < 2; i++) {
        __uint128_t product = (__uint128_t)up[i] * v;
        uint64_t low = (uint64_t)product;
        uint64_t sum = low + borrow;
        uint64_t carry = sum < low;
        uint64_t old = rp[i];
        rp[i] = old - sum;
        borrow =
            (uint64_t)(product >> 64) + carry + (old < sum);
    }
    return borrow;
}

static inline __attribute__((always_inline))
uint64_t bn_submul_fixed_3(uint64_t *rp, const uint64_t *up, uint64_t v) {
    uint64_t borrow = 0;
#if defined(__clang__)
#pragma clang loop unroll(full)
#endif
    for (int32_t i = 0; i < 3; i++) {
        __uint128_t product = (__uint128_t)up[i] * v;
        uint64_t low = (uint64_t)product;
        uint64_t sum = low + borrow;
        uint64_t carry = sum < low;
        uint64_t old = rp[i];
        rp[i] = old - sum;
        borrow =
            (uint64_t)(product >> 64) + carry + (old < sum);
    }
    return borrow;
}


static inline __attribute__((always_inline))
uint64_t mag_div_q_triangular_digit(
    uint64_t *un, const uint64_t *vn, int32_t vlen,
    int32_t j, int32_t skip, uint64_t d1, uint64_t d0, uint64_t dinv,
    int cheap_zero_or_one, uint64_t *r1p, uint64_t *r0p) {
    /* The remainder's top two limbs travel in registers (*r1p, *r0p) across
     * digits: a digit loads one fresh low limb, runs one
     * 3-by-2 step, and multiply-subtracts only the row limbs BELOW the
     * 3-by-2 window.  No per-digit top-limb stores or reloads remain. */
    uint64_t r1 = *r1p;
    uint64_t r0 = *r0p;
    int32_t row = vlen - skip;
    int32_t low = row - 2;
    uint64_t n0 = un[j + vlen - 2];
    uint64_t q;
    if (cheap_zero_or_one && r1 == 0) {
        q = r0 > d1 || (r0 == d1 && n0 >= d0);
        if (q) {
            uint64_t bw = low > 0
                ? bn_sub_n(un + j + skip, un + j + skip, vn + skip, low)
                : 0;
            __uint128_t lhs = ((__uint128_t)r0 << 64) | n0;
            __uint128_t rhs =
                ((((__uint128_t)d1 << 64) | d0)) + bw;
            if (__builtin_expect(lhs < rhs, 0)) {
                /* 2-limb prefix tied the divisor but the low limbs fell
                 * short: undo, the digit is 0. */
                q = 0;
                if (low > 0)
                    (void)bn_add_n(un + j + skip, un + j + skip,
                                   vn + skip, low);
            } else {
                lhs -= rhs;
                *r1p = (uint64_t)(lhs >> 64);
                *r0p = (uint64_t)lhs;
                return 1;
            }
        }
        *r1p = r0;
        *r0p = n0;
        return q;
    }
    if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
        /* Digit saturates at B-1: materialize the register limbs, run the
         * classic full-row multiply-subtract with top-borrow add-back (a
         * saturated estimate never refined downward in the old scheme, so
         * the digit value is unchanged), and reload. */
        un[j + vlen] = r1;
        un[j + vlen - 1] = r0;
        q = UINT64_MAX;
        uint64_t bw = bn_submul_1(un + j + skip, vn + skip, row, q);
        uint64_t top = un[j + vlen];
        un[j + vlen] = top - bw;
        if (top < bw) {
            q--;
            uint64_t carry = bn_add_n(
                un + j + skip, un + j + skip, vn + skip, row);
            un[j + vlen] += carry;
        }
        *r1p = un[j + vlen - 1];
        *r0p = un[j + vlen - 2];
        return q;
    }
    q = bn_udiv_qr_3by2(r1, r0, n0, d1, d0, dinv, &r1, &r0);
    /* The 3-by-2 step consumed the top two divisor limbs exactly; only the
     * row's lower limbs remain for the multiply-subtract. */
    uint64_t cy = low > 0
        ? bn_submul_1(un + j + skip, vn + skip, low, q)
        : 0;
    uint64_t cy1 = r0 < cy;
    r0 -= cy;
    uint64_t cy2 = r1 < cy1;
    r1 -= cy1;
    if (__builtin_expect(cy2 != 0, 0)) {
        q--;
        uint64_t carry = low > 0
            ? bn_add_n(un + j + skip, un + j + skip, vn + skip, low)
            : 0;
        __uint128_t s = (__uint128_t)r0 + d0 + carry;
        r0 = (uint64_t)s;
        r1 += d1 + (uint64_t)(s >> 64);
    }
    *r1p = r1;
    *r0p = r0;
    return q;
}

#if BN_DIV_63_DIRECT
/*
 * The 6-by-3 quotient leaf is too small to amortize the generic triangular
 * loop and variable-width submul entry.  Spell out its four quotient digits;
 * the last digit needs only the high two divisor limbs under the same
 * certificate used by the general triangular path.
 */
static inline __attribute__((always_inline))
uint64_t mag_div_q_63_digit(
    uint64_t *un, const uint64_t *vn, int32_t j, int skip,
    uint64_t d1, uint64_t d0, uint64_t dinv, int cheap_zero_or_one) {
    uint64_t n2 = un[j + 3];
    uint64_t n1 = un[j + 2];
    uint64_t n0 = un[j + 1];
    uint64_t q;
    if (cheap_zero_or_one && n2 == 0) {
        q = n1 > d1 || (n1 == d1 && n0 >= d0);
        if (q) {
            uint64_t borrow = 0;
#if defined(__clang__)
#pragma clang loop unroll(full)
#endif
            for (int32_t i = 0; i < 3; i++) {
                uint64_t old = un[j + i];
                uint64_t sub = vn[i] + borrow;
                uint64_t overflow = sub < vn[i];
                un[j + i] = old - sub;
                borrow = overflow | (old < sub);
            }
            if (borrow) {
                /* the 2-limb prefix tied the divisor but the low limbs
                 * fell short: undo, digit is 0 */
                q = 0;
                uint64_t carry = 0;
                for (int32_t i = 0; i < 3; i++) {
                    __uint128_t sum =
                        (__uint128_t)un[j + i] + vn[i] + carry;
                    un[j + i] = (uint64_t)sum;
                    carry = (uint64_t)(sum >> 64);
                }
            }
        }
        return q;
    }
    if (__builtin_expect(n2 >= d1 && (n2 > d1 || n1 >= d0), 0)) {
        /* Digit saturates at B-1: full-row multiply-subtract, classic
         * top-borrow add-back.  Identical to the previous refine-loop
         * outcome (a saturated estimate never refines downward). */
        q = UINT64_MAX;
        uint64_t bw = skip
            ? bn_submul_fixed_2(un + j + 1, vn + 1, q)
            : bn_submul_fixed_3(un + j, vn, q);
        uint64_t top = un[j + 3];
        un[j + 3] = top - bw;
        if (top < bw) {
            q--;
            uint64_t carry = 0;
            int32_t first = skip ? 1 : 0;
            for (int32_t i = first; i < 3; i++) {
                __uint128_t sum = (__uint128_t)un[j + i] + vn[i] + carry;
                un[j + i] = (uint64_t)sum;
                carry = (uint64_t)(sum >> 64);
            }
            un[j + 3] += carry;
        }
        return q;
    }
    uint64_t r1, r0;
    q = bn_udiv_qr_3by2(n2, n1, n0, d1, d0, dinv, &r1, &r0);
    if (!skip) {
        /* One low divisor limb remains below the 3-by-2 window. */
        __uint128_t p = (__uint128_t)q * vn[0];
        uint64_t plo = (uint64_t)p;
        uint64_t old = un[j];
        un[j] = old - plo;
        uint64_t cy = (uint64_t)(p >> 64) + (old < plo);
        uint64_t cy1 = r0 < cy;
        r0 -= cy;
        uint64_t cy2 = r1 < cy1;
        r1 -= cy1;
        if (__builtin_expect(cy2 != 0, 0)) {
            q--;
            __uint128_t s = (__uint128_t)un[j] + vn[0];
            un[j] = (uint64_t)s;
            s = (__uint128_t)r0 + vn[1] + (uint64_t)(s >> 64);
            r0 = (uint64_t)s;
            r1 += vn[2] + (uint64_t)(s >> 64);
        }
    }
    un[j + 3] = 0;
    un[j + 2] = r1;
    un[j + 1] = r0;
    return q;
}

static __attribute__((no_stack_protector))
WBigint *mag_div_q_63_certified(
    const uint64_t *u, const uint64_t *v) {
    uint64_t un[7], vn_work[3];
    const uint64_t *vn;
    int shift = __builtin_clzll(v[2]);
    if (shift) {
        vn_work[2] = (v[2] << shift) | (v[1] >> (64 - shift));
        vn_work[1] = (v[1] << shift) | (v[0] >> (64 - shift));
        vn_work[0] = v[0] << shift;
        vn = vn_work;
        un[6] = u[5] >> (64 - shift);
        un[5] = (u[5] << shift) | (u[4] >> (64 - shift));
        un[4] = (u[4] << shift) | (u[3] >> (64 - shift));
        un[3] = (u[3] << shift) | (u[2] >> (64 - shift));
        un[2] = (u[2] << shift) | (u[1] >> (64 - shift));
        un[1] = (u[1] << shift) | (u[0] >> (64 - shift));
    } else {
        vn = v;
        un[6] = 0;
        un[5] = u[5];
        un[4] = u[4];
        un[3] = u[3];
        un[2] = u[2];
        un[1] = u[1];
    }

    WBigint *q = bigint_alloc_raw_hot_exact(4);
    uint64_t d1 = vn[2];
    uint64_t d0 = vn[1];
    uint64_t dinv = bn_invert_pi1(d1, d0);
    q->limbs[3] =
        mag_div_q_63_digit(un, vn, 3, 0, d1, d0, dinv, 1);
    q->limbs[2] =
        mag_div_q_63_digit(un, vn, 2, 0, d1, d0, dinv, 0);
    q->limbs[1] =
        mag_div_q_63_digit(un, vn, 1, 0, d1, d0, dinv, 0);
    q->limbs[0] =
        mag_div_q_63_digit(un, vn, 0, 1, d1, d0, dinv, 0);

    if (un[6] != 0 || un[5] != 0 || un[4] != 0 ||
        un[3] != 0 || un[2] == 0 || un[2] >= vn[2]) {
        bigint_release(q);
        return NULL;
    }
    q->size = q->limbs[3] ? 4 :
              q->limbs[2] ? 3 :
              q->limbs[1] ? 2 :
              q->limbs[0] ? 1 : 0;
    return q;
}
#endif

/*
 * Quotient-only Knuth division can omit a growing low triangle of each
 * multiply-subtract row.  For a 2n/n division, digit j skips
 *
 *     s(j) = max(0, n - j - 2)
 *
 * low divisor limbs.  The working residual W therefore differs from the true
 * residual R = U-QV by the nonnegative omitted amount
 *
 *     E = sum(q[j] * (V mod B^s(j)) * B^j).
 *
 * Every nonzero summand is strictly below B^(n-1), and there are n-2 of them,
 * so E < (n-2)*B^(n-1).  The candidate quotient is rigorously exact whenever
 *
 *     (n-2)*B^(n-1) <= W < V,
 *
 * because then 0 < W-E = U-QV < V.  The bound is normally tiny relative to a
 * normalized n-limb divisor.  If either comparison is inconclusive, return
 * NULL and let the ordinary full division prove the result.
 */
static __attribute__((noinline, no_stack_protector))
WBigint *mag_div_q_triangular_certified(
    const uint64_t *u, int32_t ulen,
    const uint64_t *v, int32_t vlen) {
    if (vlen < BN_DIV_TRIANGULAR_Q_MIN ||
        vlen > BN_DIV_TRIANGULAR_Q_MAX ||
        ulen != 2 * vlen)
        return NULL;

    int shift = __builtin_clzll(v[vlen - 1]);
    int32_t m = ulen - vlen;
    /* Kick off the long serial reciprocal chain before the normalization
     * copies so the two overlap in the out-of-order window. */
    uint64_t d1, d0;
    if (shift) {
        d1 = (v[vlen - 1] << shift) | (v[vlen - 2] >> (64 - shift));
        d0 = v[vlen - 2] << shift;
        if (vlen > 2) d0 |= v[vlen - 3] >> (64 - shift);
    } else {
        d1 = v[vlen - 1];
        d0 = v[vlen - 2];
    }
    uint64_t dinv = bn_invert_pi1(d1, d0);
    uint64_t local[3 * 64 + 1];
    uint64_t *memory = local;
    int memory_owned = 0;
    if (vlen > 64) {
        memory = bn_ws_get((size_t)(3 * vlen + 1));
        if (!memory) {
            memory =
                (uint64_t *)malloc((size_t)(3 * vlen + 1) * sizeof(uint64_t));
            memory_owned = memory != NULL;
        }
        if (!memory) return NULL;
    }
    uint64_t *un = memory;
    uint64_t *vn_work = un + 2 * vlen + 1;
    const uint64_t *vn;

#if BN_DIV_Q_LAZY_LOW
    /* Leave the prefix below the lowest triangular row unmaterialized. */
    int32_t active_lo = vlen - 2;
#else
    int32_t active_lo = 0;
#endif
    if (shift) {
        vn = vn_work;
        for (int32_t i = vlen - 1; i > 0; i--)
            vn_work[i] =
                (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn_work[0] = v[0] << shift;
        un[ulen] = u[ulen - 1] >> (64 - shift);
        for (int32_t i = ulen - 1; i > active_lo; i--)
            un[i] = (u[i] << shift) | (u[i - 1] >> (64 - shift));
        if (active_lo)
            un[active_lo] =
                (u[active_lo] << shift) |
                (u[active_lo - 1] >> (64 - shift));
        else
            un[0] = u[0] << shift;
    } else {
#if BN_DIV_Q_ALIAS_NORMALIZED_V
        vn = v;
#else
        memcpy(vn_work, v, (size_t)vlen * sizeof(uint64_t));
        vn = vn_work;
#endif
        memcpy(un + active_lo, u + active_lo,
               (size_t)(ulen - active_lo) * sizeof(uint64_t));
        un[ulen] = 0;
    }

    WBigint *q = bigint_alloc_raw_hot(m + 1);
    uint64_t r1 = un[ulen];
    uint64_t r0 = un[ulen - 1];
    int32_t j = m;
#if BN_DIV_Q_FIRST_01
    q->limbs[j] = mag_div_q_triangular_digit(
        un, vn, vlen, j, 0, d1, d0, dinv, 1, &r1, &r0);
    j--;
#endif
    for (; j >= 0; j--) {
        int32_t skip = m - j - 2;
        if (skip < 0) skip = 0;
        q->limbs[j] = mag_div_q_triangular_digit(
            un, vn, vlen, j, skip, d1, d0, dinv, 0, &r1, &r0);
    }
    /* Land the register-carried remainder top limbs where the certificate
     * (and the non-lazy variant's scan) expect them. */
    un[vlen - 1] = r1;
    un[vlen - 2] = r0;

#if BN_DIV_Q_LAZY_LOW
    /*
     * The low prefix is unmaterialized.  Use only limbs vlen-1 and above
     * for a sufficient certificate, falling back if equal top limbs make
     * the W < V comparison inconclusive.  There is no need to rescan limbs
     * vlen..ulen: every quotient-digit step clears its own top position, and
     * all omitted products are strictly below B^(vlen-1), so they cannot
     * change any of those already-cleared limbs.
     */
    uint64_t wtop = un[vlen - 1];
    uint64_t error_bound_top = (uint64_t)(vlen - 2);
    if (wtop < error_bound_top || wtop >= vn[vlen - 1]) {
#else
    int32_t wlen = ulen + 1;
    while (wlen > 0 && un[wlen - 1] == 0) wlen--;
    uint64_t error_bound_top = (uint64_t)(vlen - 2);
    int above_error_bound =
        wlen > vlen ||
        (wlen == vlen && un[vlen - 1] >= error_bound_top);
    if (!above_error_bound ||
        mag_cmp(un, wlen, vn, vlen) >= 0) {
#endif
        bigint_release(q);
        if (memory_owned) free(memory);
        return NULL;
    }

    /*
     * This entry accepts exactly 2n live dividend limbs over n live divisor
     * limbs.  Hence B^(2n-1) <= U < B^(2n) and V < B^n, so the quotient has
     * either n or n+1 limbs; limb n alone decides which.  Avoid a generic
     * backwards normalization scan on every division.
     */
    int32_t qlen = m + (q->limbs[m] != 0);
    q->size = qlen;
    if (memory_owned) free(memory);
    return q;
}
#endif

/* Fixed 8-by-4-limb remainder.  Keep the normalized running remainder's
 * high two limbs in registers and subtract only the divisor's low two limbs
 * after each 3-by-2 quotient estimate. */
#ifndef BN_MOD_84_DIRECT
#define BN_MOD_84_DIRECT 1
#endif
#ifndef BN_BENCH_RUNTIME_MOD84_KNOB
#define BN_BENCH_RUNTIME_MOD84_KNOB 0
#endif
#if BN_BENCH_RUNTIME_MOD84_KNOB
static int bn_bench_runtime_mod84_direct;
#define BN_MOD_84_DIRECT_ENABLED() bn_bench_runtime_mod84_direct
#else
#define BN_MOD_84_DIRECT_ENABLED() BN_MOD_84_DIRECT
#endif
/* Fixed 8-by-4-limb quotient (below): the remainder kernel's recurrence
 * keeping the digits it discards.  Shares the reciprocal cache. */
#ifndef BN_DIV_84_DIRECT
#define BN_DIV_84_DIRECT 1
#endif

#if BN_MOD_84_DIRECT || BN_BENCH_RUNTIME_MOD84_KNOB || BN_DIV_84_DIRECT
#ifndef BN_MOD84_PREINV_CACHE
#define BN_MOD84_PREINV_CACHE 1
#endif
#if BN_MOD84_PREINV_CACHE
#ifndef BN_MOD84_PREINV_CACHE_ENTRIES
#define BN_MOD84_PREINV_CACHE_ENTRIES 2
#endif
#if BN_MOD84_PREINV_CACHE_ENTRIES < 1 || BN_MOD84_PREINV_CACHE_ENTRIES > 2
#error "BN_MOD84_PREINV_CACHE_ENTRIES must be 1 or 2"
#endif
#ifndef BN_BENCH_RUNTIME_MOD84_CACHE_ENTRIES_KNOB
#define BN_BENCH_RUNTIME_MOD84_CACHE_ENTRIES_KNOB 0
#endif
#if BN_BENCH_RUNTIME_MOD84_CACHE_ENTRIES_KNOB
static int bn_bench_runtime_mod84_cache_entries = 2;
#define BN_MOD84_PREINV_CACHE_ENTRIES_ENABLED() \
    bn_bench_runtime_mod84_cache_entries
#else
#define BN_MOD84_PREINV_CACHE_ENTRIES_ENABLED() BN_MOD84_PREINV_CACHE_ENTRIES
#endif
/* The exact native-Tungsten mag_mod_84 port reads the same process-private
 * cache through Mach-O TLS descriptors.  Hidden linkage keeps these runtime
 * implementation details out of the public ABI while allowing the embedded
 * assembly object to share, rather than approximate, the tuned C policy. */
__attribute__((visibility("hidden"))) __thread uint64_t
    bn_mod84_preinv_d1[2];
__attribute__((visibility("hidden"))) __thread uint64_t
    bn_mod84_preinv_d0[2];
__attribute__((visibility("hidden"))) __thread uint64_t
    bn_mod84_preinv_value[2];
__attribute__((visibility("hidden"))) __thread uint8_t
    bn_mod84_preinv_next;

typedef struct {
    struct {
        uint64_t d1;
        uint64_t d0;
        uint64_t value;
    } entry[2];
    uint8_t next;
} BnMod84NativePreinvCache;

/* Native follow-up to the exact port: one TLS descriptor lookup exposes the
 * same two entries and round-robin replacement policy.  The retained C lane
 * keeps its original independently measured cache layout above. */
__attribute__((visibility("hidden"))) __thread BnMod84NativePreinvCache
    bn_mod84_native_preinv_cache;
#endif

static inline __attribute__((always_inline))
uint64_t bn_submul_2_inline(uint64_t *rp, const uint64_t *up, uint64_t v) {
    __uint128_t product0 = (__uint128_t)up[0] * v;
    uint64_t low0 = (uint64_t)product0;
    uint64_t old0 = rp[0];
    rp[0] = old0 - low0;
    uint64_t borrow = (uint64_t)(product0 >> 64) + (old0 < low0);

    __uint128_t product1 = (__uint128_t)up[1] * v;
    uint64_t low1 = (uint64_t)product1;
    uint64_t sub1 = low1 + borrow;
    uint64_t carry1 = sub1 < low1;
    uint64_t old1 = rp[1];
    rp[1] = old1 - sub1;
    return (uint64_t)(product1 >> 64) + carry1 + (old1 < sub1);
}

/* The 8/4 remainder and quotient kernels normalize one divisor to the same
 * (d1, d0), so one cached 3-by-2 reciprocal serves both. */
static inline __attribute__((always_inline))
uint64_t bn_mod84_preinv(uint64_t d1, uint64_t d0) {
#if BN_MOD84_PREINV_CACHE
    if (bn_mod84_preinv_d1[0] == d1 && bn_mod84_preinv_d0[0] == d0)
        return bn_mod84_preinv_value[0];
    if (BN_MOD84_PREINV_CACHE_ENTRIES_ENABLED() > 1 &&
        bn_mod84_preinv_d1[1] == d1 && bn_mod84_preinv_d0[1] == d0)
        return bn_mod84_preinv_value[1];
    uint64_t dinv = bn_invert_pi1(d1, d0);
    int slot = BN_MOD84_PREINV_CACHE_ENTRIES_ENABLED() > 1
        ? (bn_mod84_preinv_next++ & 1) : 0;
    bn_mod84_preinv_d1[slot] = d1;
    bn_mod84_preinv_d0[slot] = d0;
    bn_mod84_preinv_value[slot] = dinv;
    return dinv;
#else
    return bn_invert_pi1(d1, d0);
#endif
}

#if BN_MOD_84_DIRECT || BN_BENCH_RUNTIME_MOD84_KNOB
static __attribute__((no_stack_protector))
WBigint *mag_mod_84(const uint64_t *u, const uint64_t *v) {
    uint64_t un[8], vn_work[4];
    const uint64_t *vn;
    int shift = __builtin_clzll(v[3]);
    uint64_t r1, r0;
    if (shift) {
        vn_work[0] = v[0] << shift;
        for (int32_t i = 1; i < 4; i++)
            vn_work[i] = (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn = vn_work;
        for (int32_t i = 0; i < 8; i++) {
            uint64_t lower = i ? u[i - 1] : 0;
            un[i] = (u[i] << shift) | (lower >> (64 - shift));
        }
        r1 = u[7] >> (64 - shift);
        r0 = un[7];
    } else {
        vn = v;
        memcpy(un, u, sizeof(un));
        r1 = 0;
        r0 = un[7];
    }

    uint64_t d1 = vn[3], d0 = vn[2];
    uint64_t dinv = bn_mod84_preinv(d1, d0);
    for (int32_t j = 4; j >= 0; j--) {
        uint64_t qhat;
        if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
            uint64_t window[5] = {
                un[j], un[j + 1], un[j + 2], r0, r1
            };
            qhat = UINT64_MAX;
            uint64_t borrow = bn_submul_1(window, vn, 4, qhat);
            uint64_t top = window[4];
            window[4] = top - borrow;
            if (top < borrow) {
                qhat--;
                uint64_t carry = bn_add_n(window, window, vn, 4);
                window[4] += carry;
            }
            /* The corrected remainder occupies window[0..3]; window[4]
             * is the cleared borrow/carry limb.  The next quotient digit
             * consumes window[3:2] as its register pair and brings
             * window[1] down as n0.  Keeping window[4:3] here shifts the
             * recurrence by one limb and corrupts consecutive saturated
             * digits (for example (B^4-1)^2+r mod (B^4-1)). */
            un[j] = window[0];
            un[j + 1] = window[1];
            r0 = window[2];
            r1 = window[3];
        } else {
            qhat = bn_udiv_qr_3by2(
                r1, r0, un[j + 2], d1, d0, dinv, &r1, &r0);
            uint64_t carry =
                bn_submul_2_inline(un + j, vn, qhat);
            uint64_t carry1 = r0 < carry;
            r0 -= carry;
            uint64_t carry2 = r1 < carry1;
            r1 -= carry1;
            if (__builtin_expect(carry2 != 0, 0)) {
                qhat--;
                uint64_t low_carry = bn_add_n(un + j, un + j, vn, 2);
                __uint128_t sum = (__uint128_t)r0 + d0 + low_carry;
                r0 = (uint64_t)sum;
                r1 += d1 + (uint64_t)(sum >> 64);
            }
        }
        (void)qhat;
    }

    WBigint *r = bigint_alloc_raw_hot(4);
    if (shift) {
        r->limbs[0] = (un[0] >> shift) | (un[1] << (64 - shift));
        r->limbs[1] = (un[1] >> shift) | (r0 << (64 - shift));
        r->limbs[2] = (r0 >> shift) | (r1 << (64 - shift));
        r->limbs[3] = r1 >> shift;
    } else {
        r->limbs[0] = un[0];
        r->limbs[1] = un[1];
        r->limbs[2] = r0;
        r->limbs[3] = r1;
    }
    r->size = 4;
    while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
    return r;
}
#endif

#if BN_DIV_84_DIRECT
/*
 * Fixed 8-by-4-limb quotient, with the remainder on request.  The 8/4
 * quotient used to take the generic quotient-only triangular certificate
 * (variable-width digit entry, arena-sized frame, certificate scan, and a
 * second full division when it is inconclusive) while its remainder twin
 * above is straight-line.  This is mag_mod_84's recurrence keeping the
 * digits it discards: the normalized remainder's top two limbs travel in
 * registers, each digit is one 3-by-2 reciprocal step followed by the
 * two-limb multiply-subtract below that window and the rare add-back.  The
 * remainder is exact, so no certificate is needed.  With no normalization
 * shift (the common boxed shape) the leading digit is 0 or 1 and is decided
 * by a compare instead of a reciprocal step.
 */
static __attribute__((no_stack_protector))
WBigint *mag_div_84(const uint64_t *u, const uint64_t *v,
                    WBigint **r_out) {
    uint64_t un[8], vn_work[4];
    const uint64_t *vn;
    int shift = __builtin_clzll(v[3]);
    uint64_t r1, r0;
    if (shift) {
        vn_work[0] = v[0] << shift;
        for (int32_t i = 1; i < 4; i++)
            vn_work[i] = (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn = vn_work;
        for (int32_t i = 0; i < 8; i++) {
            uint64_t lower = i ? u[i - 1] : 0;
            un[i] = (u[i] << shift) | (lower >> (64 - shift));
        }
        r1 = u[7] >> (64 - shift);
        r0 = un[7];
    } else {
        vn = v;
        memcpy(un, u, sizeof(un));
        r1 = 0;
        r0 = un[7];
    }

    uint64_t d1 = vn[3], d0 = vn[2];
    uint64_t dinv = bn_mod84_preinv(d1, d0);
    /* Five digits at most; the churn hands back the 5-limb quotient's own
     * capacity class, so ask for it exactly. */
    WBigint *q = bigint_alloc_raw_hot_exact(bigint_alloc_capacity(5U));
    int32_t j = 4;
    if (r1 == 0) {
        /* Unshifted top: the leading digit is 0 or 1.  Compare the 2-limb
         * prefix, subtract the two low divisor limbs, and let their borrow
         * settle a prefix tie. */
        uint64_t n0 = un[6];
        uint64_t qtop = 0;
        if (r0 > d1 || (r0 == d1 && n0 >= d0)) {
            uint64_t old0 = un[4];
            uint64_t b0 = old0 < vn[0];
            uint64_t old1 = un[5];
            uint64_t sub1 = vn[1] + b0;
            uint64_t b1 = (sub1 < vn[1]) | (old1 < sub1);
            __uint128_t lhs = ((__uint128_t)r0 << 64) | n0;
            __uint128_t rhs = (((__uint128_t)d1 << 64) | d0) + b1;
            if (__builtin_expect(lhs >= rhs, 1)) {
                lhs -= rhs;
                un[4] = old0 - vn[0];
                un[5] = old1 - sub1;
                r1 = (uint64_t)(lhs >> 64);
                r0 = (uint64_t)lhs;
                qtop = 1;
            } else {
                /* prefix tied the divisor, low limbs fell short: 0 */
                r1 = r0;
                r0 = n0;
            }
        } else {
            r1 = r0;
            r0 = n0;
        }
        q->limbs[4] = qtop;
        j = 3;
    }
    for (; j >= 0; j--) {
        uint64_t qhat;
        if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
            /* Saturated digit: full-row multiply-subtract with the classic
             * top-borrow add-back; see mag_mod_84 for the window layout. */
            uint64_t window[5] = {
                un[j], un[j + 1], un[j + 2], r0, r1
            };
            qhat = UINT64_MAX;
            uint64_t borrow = bn_submul_1(window, vn, 4, qhat);
            uint64_t top = window[4];
            window[4] = top - borrow;
            if (top < borrow) {
                qhat--;
                uint64_t carry = bn_add_n(window, window, vn, 4);
                window[4] += carry;
            }
            un[j] = window[0];
            un[j + 1] = window[1];
            r0 = window[2];
            r1 = window[3];
        } else {
            qhat = bn_udiv_qr_3by2(
                r1, r0, un[j + 2], d1, d0, dinv, &r1, &r0);
            uint64_t carry =
                bn_submul_2_inline(un + j, vn, qhat);
            uint64_t carry1 = r0 < carry;
            r0 -= carry;
            uint64_t carry2 = r1 < carry1;
            r1 -= carry1;
            if (__builtin_expect(carry2 != 0, 0)) {
                qhat--;
                uint64_t low_carry = bn_add_n(un + j, un + j, vn, 2);
                __uint128_t sum = (__uint128_t)r0 + d0 + low_carry;
                r0 = (uint64_t)sum;
                r1 += d1 + (uint64_t)(sum >> 64);
            }
        }
        q->limbs[j] = qhat;
    }
    q->size = q->limbs[4] ? 5 :
              q->limbs[3] ? 4 :
              q->limbs[2] ? 3 :
              q->limbs[1] ? 2 :
              q->limbs[0] ? 1 : 0;

    if (r_out) {
        WBigint *r = bigint_alloc_raw_hot(4);
        if (shift) {
            r->limbs[0] = (un[0] >> shift) | (un[1] << (64 - shift));
            r->limbs[1] = (un[1] >> shift) | (r0 << (64 - shift));
            r->limbs[2] = (r0 >> shift) | (r1 << (64 - shift));
            r->limbs[3] = r1 >> shift;
        } else {
            r->limbs[0] = un[0];
            r->limbs[1] = un[1];
            r->limbs[2] = r0;
            r->limbs[3] = r1;
        }
        r->size = 4;
        while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
        *r_out = r;
    }
    return q;
}
#endif
#endif

/*
 * Fixed 6-by-3-limb remainder kernel.  The quotient-only 6/3 leaf above has
 * no remainder twin, so 6/3 mod used to fall into the generic Knuth entry
 * (arena copies, large stack frame).  With the 3-by-2 step the remainder is
 * exact: four digits, each one udiv_qr_3by2 plus a single low-limb
 * multiply-subtract, the running remainder's top two limbs in registers.
 */
#ifndef BN_MOD_63_DIRECT
#define BN_MOD_63_DIRECT 1
#endif

#if BN_MOD_63_DIRECT
static __attribute__((no_stack_protector))
WBigint *mag_mod_63(const uint64_t *u, const uint64_t *v) {
    uint64_t un[5], vn_work[3];
    const uint64_t *vn;
    int shift = __builtin_clzll(v[2]);
    uint64_t r1, r0;
    if (shift) {
        vn_work[2] = (v[2] << shift) | (v[1] >> (64 - shift));
        vn_work[1] = (v[1] << shift) | (v[0] >> (64 - shift));
        vn_work[0] = v[0] << shift;
        vn = vn_work;
        r1 = u[5] >> (64 - shift);
        r0 = (u[5] << shift) | (u[4] >> (64 - shift));
        un[4] = (u[4] << shift) | (u[3] >> (64 - shift));
        un[3] = (u[3] << shift) | (u[2] >> (64 - shift));
        un[2] = (u[2] << shift) | (u[1] >> (64 - shift));
        un[1] = (u[1] << shift) | (u[0] >> (64 - shift));
        un[0] = u[0] << shift;
    } else {
        vn = v;
        r1 = 0;
        r0 = u[5];
        un[4] = u[4];
        un[3] = u[3];
        un[2] = u[2];
        un[1] = u[1];
        un[0] = u[0];
    }
    uint64_t d1 = vn[2];
    uint64_t d0 = vn[1];
    uint64_t dl = vn[0];
    uint64_t dinv = bn_invert_pi1(d1, d0);
    int32_t jtop = 3;
    if (r1 == 0) {
        /* Unshifted top: the leading digit is 0 or 1; decide with a 2-limb
         * compare and one conditional 3-limb subtract. */
        uint64_t n0 = un[4];
        if (r0 > d1 || (r0 == d1 && n0 >= d0)) {
            uint64_t b0 = un[3] < dl;
            un[3] -= dl;
            uint64_t sub0 = d0 + b0;
            uint64_t b1 = (sub0 < d0) | (n0 < sub0);
            uint64_t sub1 = d1 + b1;
            uint64_t b2 = (sub1 < d1) | (r0 < sub1);
            if (__builtin_expect(b2 != 0, 0)) {
                /* prefix tie, low limb fell short: digit is 0, undo */
                un[3] += dl;
                r1 = r0;
                r0 = n0;
            } else {
                r1 = r0 - sub1;
                r0 = n0 - sub0;
            }
        } else {
            r1 = r0;
            r0 = n0;
        }
        jtop = 2;
    }
    for (int32_t j = jtop; j >= 0; j--) {
        uint64_t n0 = un[j + 1];
        if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
            /* Saturated digit: subtract (B-1)*V from the 4-limb window. */
            uint64_t w[4];
            w[0] = un[j];
            w[1] = n0;
            w[2] = r0;
            w[3] = r1;
            uint64_t borrow = 0;
            for (int32_t i = 0; i < 3; i++) {
                __uint128_t product = (__uint128_t)vn[i] * UINT64_MAX;
                uint64_t lowp = (uint64_t)product;
                uint64_t sum = lowp + borrow;
                uint64_t carry = sum < lowp;
                uint64_t old = w[i];
                w[i] = old - sum;
                borrow =
                    (uint64_t)(product >> 64) + carry + (old < sum);
            }
            uint64_t top = w[3];
            w[3] = top - borrow;
            if (top < borrow) {
                uint64_t carry = 0;
                for (int32_t i = 0; i < 3; i++) {
                    __uint128_t sum =
                        (__uint128_t)w[i] + vn[i] + carry;
                    w[i] = (uint64_t)sum;
                    carry = (uint64_t)(sum >> 64);
                }
                w[3] += carry;
            }
            un[j] = w[0];
            r0 = w[1];
            r1 = w[2];
        } else {
            uint64_t q =
                bn_udiv_qr_3by2(r1, r0, n0, d1, d0, dinv, &r1, &r0);
            __uint128_t p = (__uint128_t)q * dl;
            uint64_t plo = (uint64_t)p;
            uint64_t old = un[j];
            un[j] = old - plo;
            uint64_t cy = (uint64_t)(p >> 64) + (old < plo);
            uint64_t cy1 = r0 < cy;
            r0 -= cy;
            uint64_t cy2 = r1 < cy1;
            r1 -= cy1;
            if (__builtin_expect(cy2 != 0, 0)) {
                __uint128_t s = (__uint128_t)un[j] + dl;
                un[j] = (uint64_t)s;
                s = (__uint128_t)r0 + d0 + (uint64_t)(s >> 64);
                r0 = (uint64_t)s;
                r1 += d1 + (uint64_t)(s >> 64);
            }
        }
    }
    WBigint *r = bigint_alloc_raw_hot(3);
    if (shift) {
        r->limbs[0] = (un[0] >> shift) | (r0 << (64 - shift));
        r->limbs[1] = (r0 >> shift) | (r1 << (64 - shift));
        r->limbs[2] = r1 >> shift;
    } else {
        r->limbs[0] = un[0];
        r->limbs[1] = r0;
        r->limbs[2] = r1;
    }
    r->size = 3;
    while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
    return r;
}
#endif

/*
 * Fixed 4-by-2-limb Knuth leaf.  This is the first genuinely multi-limb
 * division shape used by the bignum benchmarks, but the generic path pays for
 * two bounded-arena copies, three variable-width submul calls, and loop
 * control.  Keep the exact Algorithm D estimate/correction rules while
 * spelling out the two-limb multiply-subtract and normalization.
 */
#ifndef BN_DIVMOD_42
#define BN_DIVMOD_42 1
#endif
#ifndef BN_DIVMOD_42_DIRECT
#define BN_DIVMOD_42_DIRECT 1
#endif

#if BN_DIVMOD_42
typedef struct {
    uint64_t q0, q1, q2;
    uint64_t r0, r1;
} WDivmod42;

static inline __attribute__((always_inline))
WDivmod42 mag_divmod_42_core(const uint64_t *u, const uint64_t *v) {
    uint64_t un[5];
    uint64_t vn_work[2];
    const uint64_t *vn;
    int shift = __builtin_clzll(v[1]);
    if (shift) {
        vn_work[0] = v[0] << shift;
        vn_work[1] = (v[1] << shift) | (v[0] >> (64 - shift));
        vn = vn_work;
        un[0] = u[0] << shift;
        un[1] = (u[1] << shift) | (u[0] >> (64 - shift));
        un[2] = (u[2] << shift) | (u[1] >> (64 - shift));
        un[3] = (u[3] << shift) | (u[2] >> (64 - shift));
        un[4] = u[3] >> (64 - shift);
    } else {
        vn = v;
        un[0] = u[0];
        un[1] = u[1];
        un[2] = u[2];
        un[3] = u[3];
        un[4] = 0;
    }

    /*
     * The whole division is three straight-line 3-by-2 steps with the
     * remainder carried in registers.  The top digit's
     * precondition (un[4],un[3]) < (d1,d0) always holds: the 2-limb divisor
     * IS the full divisor here, so a violation would force the quotient to
     * a fourth limb, impossible for a 4-limb dividend over a >= B divisor.
     */
    uint64_t d1 = vn[1];
    uint64_t d0 = vn[0];
    uint64_t dinv = bn_invert_pi1(d1, d0);
    uint64_t r1 = un[4];
    uint64_t r0 = un[3];
    WDivmod42 result;
    if (r1 == 0) {
        /* Unshifted top (always so when the divisor is pre-normalized):
         * the leading digit is 0 or 1, decided by a two-limb compare -- no
         * 3-by-2 step needed. */
        uint64_t n0 = un[2];
        if (r0 > d1 || (r0 == d1 && n0 >= d0)) {
            result.q2 = 1;
            __uint128_t t = (((__uint128_t)r0 << 64) | n0) -
                            (((__uint128_t)d1 << 64) | d0);
            r1 = (uint64_t)(t >> 64);
            r0 = (uint64_t)t;
        } else {
            result.q2 = 0;
            r1 = r0;
            r0 = n0;
        }
    } else {
        result.q2 =
            bn_udiv_qr_3by2(r1, r0, un[2], d1, d0, dinv, &r1, &r0);
    }
    result.q1 = bn_udiv_qr_3by2(r1, r0, un[1], d1, d0, dinv, &r1, &r0);
    result.q0 = bn_udiv_qr_3by2(r1, r0, un[0], d1, d0, dinv, &r1, &r0);
    if (shift) {
        result.r0 = (r0 >> shift) | (r1 << (64 - shift));
        result.r1 = r1 >> shift;
    } else {
        result.r0 = r0;
        result.r1 = r1;
    }
    return result;
}

static __attribute__((no_stack_protector))
WBigint *mag_div_42(const uint64_t *u, const uint64_t *v) {
    WDivmod42 result = mag_divmod_42_core(u, v);
    WBigint *q = bigint_alloc_raw_hot(3);
    q->limbs[0] = result.q0;
    q->limbs[1] = result.q1;
    q->limbs[2] = result.q2;
    q->size = result.q2 ? 3 : result.q1 ? 2 : result.q0 ? 1 : 0;
    return q;
}

static __attribute__((no_stack_protector))
WBigint *mag_mod_42(const uint64_t *u, const uint64_t *v) {
    WDivmod42 result = mag_divmod_42_core(u, v);
    WBigint *r = bigint_alloc_raw_hot(2);
    r->limbs[0] = result.r0;
    r->limbs[1] = result.r1;
    r->size = result.r1 ? 2 : result.r0 ? 1 : 0;
    return r;
}

static __attribute__((no_stack_protector))
void mag_divmod_42(const uint64_t *u, const uint64_t *v,
                          WBigint **q_out, WBigint **r_out) {
    if (q_out && !r_out) {
        *q_out = mag_div_42(u, v);
        return;
    }
    if (r_out && !q_out) {
        *r_out = mag_mod_42(u, v);
        return;
    }

    WDivmod42 result = mag_divmod_42_core(u, v);
    if (q_out) {
        WBigint *q = bigint_alloc_raw_hot(3);
        q->limbs[0] = result.q0;
        q->limbs[1] = result.q1;
        q->limbs[2] = result.q2;
        q->size = result.q2 ? 3 :
                  result.q1 ? 2 :
                  result.q0 ? 1 : 0;
        *q_out = q;
    }
    if (r_out) {
        WBigint *r = bigint_alloc_raw_hot(2);
        r->limbs[0] = result.r0;
        r->limbs[1] = result.r1;
        r->size = result.r1 ? 2 : result.r0 ? 1 : 0;
        *r_out = r;
    }
}
#endif

/* Multi-limb division: a / b → quotient and remainder.
   Simplified Knuth Algorithm D for base 2^64. */
static __attribute__((no_stack_protector))
void mag_divmod_knuth(const uint64_t *u, int32_t ulen,
                             const uint64_t *v, int32_t vlen,
                             WBigint **q_out, WBigint **r_out) {
    if (vlen == 0) die_as("ZeroDivisionError", "division by zero");

    /* Single-limb divisor: fast path */
    if (vlen == 1) {
        uint64_t rem;
        if (q_out) {
            WBigint *q = mag_div_single(u, ulen, v[0], &rem);
            *q_out = q;
        } else {
            rem = mag_mod_single(u, ulen, v[0]);
        }
        if (r_out) {
            WBigint *r = bigint_alloc(1);
            r->limbs[0] = rem;
            r->size = rem ? 1 : 0;
            *r_out = r;
        }
        return;
    }

    if (ulen < vlen || (ulen == vlen && mag_cmp(u, ulen, v, vlen) < 0)) {
        /* |u| < |v|: quotient = 0, remainder = u */
        if (q_out) {
            WBigint *q = bigint_alloc(1);
            q->size = 0;
            *q_out = q;
        }
        if (r_out) {
            WBigint *r = bigint_alloc(ulen);
            for (int32_t i = 0; i < ulen; i++) r->limbs[i] = u[i];
            r->size = ulen;
            while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
            *r_out = r;
        }
        return;
    }

    /* Normalize: shift so top bit of divisor is set */
    int shift = __builtin_clzll(v[vlen - 1]);
    int32_t m = ulen - vlen;
    /* Start the serial reciprocal chain before the normalization copies so
     * the two overlap in the out-of-order window. */
    uint64_t d1, d0;
    if (shift) {
        d1 = (v[vlen - 1] << shift) | (v[vlen - 2] >> (64 - shift));
        d0 = v[vlen - 2] << shift;
        if (vlen > 2) d0 |= v[vlen - 3] >> (64 - shift);
    } else {
        d1 = v[vlen - 1];
        d0 = v[vlen - 2];
    }
    uint64_t dinv = bn_invert_pi1(d1, d0);

    /* B–Z leaves and ordinary small divisions fit in a bounded stack arena,
     * avoiding two malloc/free pairs per Knuth call. */
    uint64_t un_local[129], vn_local[64];
    int heap_work = ulen > 128 || vlen > 64;
    uint64_t *un = heap_work
        ? (uint64_t *)malloc((size_t)(ulen + 1) * sizeof(uint64_t))
        : un_local;
    uint64_t *vn = heap_work
        ? (uint64_t *)malloc((size_t)vlen * sizeof(uint64_t))
        : vn_local;

    /* Shift divisor left */
    if (shift > 0) {
        for (int32_t i = vlen - 1; i > 0; i--)
            vn[i] = (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn[0] = v[0] << shift;
    } else {
        for (int32_t i = 0; i < vlen; i++) vn[i] = v[i];
    }

    /* Shift dividend left */
    if (shift > 0) {
        un[ulen] = u[ulen - 1] >> (64 - shift);
        for (int32_t i = ulen - 1; i > 0; i--)
            un[i] = (u[i] << shift) | (u[i - 1] >> (64 - shift));
        un[0] = u[0] << shift;
    } else {
        for (int32_t i = 0; i < ulen; i++) un[i] = u[i];
        un[ulen] = 0;
    }

    WBigint *q = q_out ? bigint_alloc_raw_hot(m + 1) : NULL;
    /* Remainder top-2 limbs live in registers across digits. */
    uint64_t r1 = un[ulen];
    uint64_t r0 = un[ulen - 1];

    for (int32_t j = m; j >= 0; j--) {
        uint64_t qhat;
        if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
            /* Digit saturates at B-1:
             * materialize, full-row multiply-subtract with the classic
             * top-borrow add-back, reload. */
            un[j + vlen] = r1;
            un[j + vlen - 1] = r0;
            qhat = UINT64_MAX;
            uint64_t bw = bn_submul_1(un + j, vn, vlen, qhat);
            uint64_t top = un[j + vlen];
            un[j + vlen] = top - bw;
            if (top < bw) {
                qhat--;
                uint64_t carry = bn_add_n(un + j, un + j, vn, vlen);
                un[j + vlen] += carry;
            }
            r1 = un[j + vlen - 1];
            r0 = un[j + vlen - 2];
        } else {
            /* Exact digit and top-2 remainder limbs in one 3-by-2 step;
             * only vlen-2 low divisor limbs remain for the subtract. */
            qhat = bn_udiv_qr_3by2(r1, r0, un[j + vlen - 2],
                                   d1, d0, dinv, &r1, &r0);
            uint64_t cy = vlen > 2
                ? bn_submul_1(un + j, vn, vlen - 2, qhat)
                : 0;
            uint64_t cy1 = r0 < cy;
            r0 -= cy;
            uint64_t cy2 = r1 < cy1;
            r1 -= cy1;
            if (__builtin_expect(cy2 != 0, 0)) {
                qhat--;
                uint64_t carry = vlen > 2
                    ? bn_add_n(un + j, un + j, vn, vlen - 2)
                    : 0;
                __uint128_t s = (__uint128_t)r0 + d0 + carry;
                r0 = (uint64_t)s;
                r1 += d1 + (uint64_t)(s >> 64);
            }
        }
        if (q) q->limbs[j] = qhat;
    }
    un[vlen - 1] = r1;
    un[vlen - 2] = r0;

    if (q_out) {
        q->size = m + 1;
        while (q->size > 0 && q->limbs[q->size - 1] == 0) q->size--;
        *q_out = q;
    }

    if (r_out) {
        WBigint *r = bigint_alloc_raw_hot(vlen);
        if (shift > 0) {
            for (int32_t i = 0; i < vlen - 1; i++)
                r->limbs[i] = (un[i] >> shift) | (un[i + 1] << (64 - shift));
            r->limbs[vlen - 1] = un[vlen - 1] >> shift;
        } else {
            for (int32_t i = 0; i < vlen; i++) r->limbs[i] = un[i];
        }
        r->size = vlen;
        while (r->size > 0 && r->limbs[r->size - 1] == 0) r->size--;
        *r_out = r;
    }

    if (heap_work) {
        free(un);
        free(vn);
    }
}

/* ---- Burnikel–Ziegler recursive division --------------------------------
 * Knuth Algorithm D is O(m·n) with a full multiply-subtract per quotient limb;
 * at 1024 limbs the division of a 2n-limb product costs ~7× the (subquadratic)
 * multiply that produced it. B–Z rewrites division as recursion on halves whose
 * work is dominated by CALLS TO THE FAST MULTIPLY: D2n/1n splits into two
 * D3n/2n steps; D3n/2n estimates the quotient with a half-size D2n/1n, then
 * corrects with one k×k multiply (Q̂·B0) and ≤2 add-backs. One normalization
 * (top bit of the divisor set) at entry keeps every recursive divisor
 * normalized, since B1 inherits the top bit. Base cases fall back to Knuth. */
#ifndef BZ_THRESHOLD
#define BZ_THRESHOLD 24
#endif
#ifndef BZ_TOP_THRESHOLD
#define BZ_TOP_THRESHOLD 64
#endif
#ifndef BN_BZ_SKIP_ZERO_TOP_DIGIT
#define BN_BZ_SKIP_ZERO_TOP_DIGIT 1
#endif
#ifndef BN_BZ_ALIAS_NORMALIZED_TOP
#define BN_BZ_ALIAS_NORMALIZED_TOP 1
#endif
#ifndef BN_BZ_ZERO_PADDING_ONLY
#define BN_BZ_ZERO_PADDING_ONLY 1
#endif

#ifdef BN_DIV_ROUTE_COUNTERS
/* Diagnostic routing counters (probe builds only): which division route each
 * call takes, and why the cached-reciprocal path declines. */
uint64_t bn_div_route_knuth;
uint64_t bn_div_route_bz;
uint64_t bn_div_route_recip_hit;
uint64_t bn_div_route_triangular_hit;
uint64_t bn_div_recip_reject_qmax;
uint64_t bn_div_recip_reject_shape;
uint64_t bn_div_recip_reject_min;
uint64_t bn_div_recip_warmup;
uint64_t bn_div_recip_cert_fail;
uint64_t bn_div_bz_ws_fallback;
#define BN_DIV_ROUTE_COUNT(counter) ((counter)++)
#else
#define BN_DIV_ROUTE_COUNT(counter) ((void)0)
#endif

static __thread uint64_t *bz_ws = NULL;
static __thread size_t bz_ws_cap = 0;
#ifdef BN_BZ_PROFILE_COUNTS
static uint64_t bz_profile_mul_calls;
static uint64_t bz_profile_mul_q_limbs;
static uint64_t bz_profile_mul_b_limbs;
static uint64_t bz_profile_mul_equal;
static uint64_t bz_profile_mul_full;
static uint64_t bz_profile_clamped;
static uint64_t bz_profile_mul_bins[12];
static int32_t bz_profile_shape_count;
static int32_t bz_profile_shape_k[32];
static int32_t bz_profile_shape_q[32];
static int32_t bz_profile_shape_b[32];
#endif
static uint64_t *bz_ws_get(size_t limbs) {
    if (limbs > bz_ws_cap) {
        free(bz_ws);
        size_t ncap = limbs + limbs / 2 + 64;
        bz_ws = (uint64_t *)malloc(ncap * sizeof(uint64_t));
        bz_ws_cap = bz_ws ? ncap : 0;
    }
    return bz_ws;
}

static inline int32_t bz_trim(const uint64_t *a, int32_t n) {
    while (n > 0 && a[n - 1] == 0) n--;
    return n;
}
static void bz_dec1(uint64_t *q, int32_t n) {          /* q -= 1, borrow-propagating */
    for (int32_t i = 0; i < n; i++) {
        uint64_t old = q[i];
        q[i] = old - 1;
        if (old != 0) break;
    }
}

/* Allocation-free Knuth leaf for B–Z's fixed-width q/r buffers. */
static __attribute__((no_stack_protector))
void bz_base_div_into(const uint64_t *u, int32_t ulen,
                             const uint64_t *v, int32_t vlen,
                             uint64_t *q, int32_t qw,
                             uint64_t *r, int32_t rw,
                             int skip_zero_top) {
    for (int32_t i = 0; i < qw; i++) q[i] = 0;
    for (int32_t i = 0; i < rw; i++) r[i] = 0;
    ulen = bz_trim(u, ulen);
    if (ulen == 0) return;
    if (ulen < vlen || (ulen == vlen && mag_cmp(u, ulen, v, vlen) < 0)) {
        int32_t copy = ulen < rw ? ulen : rw;
        memcpy(r, u, (size_t)copy * sizeof(uint64_t));
        return;
    }

    /* B–Z reaches this helper with multi-limb divisors. */
    if (vlen == 1) {
        __uint128_t rem = 0;
        for (int32_t i = ulen - 1; i >= 0; i--) {
            rem = (rem << 64) | u[i];
            if (i < qw) q[i] = (uint64_t)(rem / v[0]);
            rem %= v[0];
        }
        if (rw) r[0] = (uint64_t)rem;
        return;
    }

    /* The dividend arena covers every B-Z leaf the divappr padding rules
     * produce (the odd leaves reach 130/65 at the 4096- and 8192-limb
     * roots, which overflowed the old 129-limb arena by two limbs and paid
     * a malloc/free per leaf) plus the sqrt recursion's raw-Knuth band
     * (ulen <= 2h <= 256).  The divisor arena only backs shift != 0, which
     * the pre-normalized B-Z/sqrt callers never take. */
    uint64_t un_local[261], vn_local[64];
    int un_heap = ulen > 260;
    int vn_heap = vlen > 64;
    int shift = __builtin_clzll(v[vlen - 1]);
    /* Start the serial reciprocal chain before the normalization copies so
     * the two overlap in the out-of-order window. */
    uint64_t d1, d0;
    if (shift) {
        d1 = (v[vlen - 1] << shift) | (v[vlen - 2] >> (64 - shift));
        d0 = v[vlen - 2] << shift;
        if (vlen > 2) d0 |= v[vlen - 3] >> (64 - shift);
    } else {
        d1 = v[vlen - 1];
        d0 = v[vlen - 2];
    }
    uint64_t dinv = bn_invert_pi1(d1, d0);
    uint64_t *un = un_heap
        ? (uint64_t *)malloc((size_t)(ulen + 1) * sizeof(uint64_t))
        : un_local;
    uint64_t *vn_work = shift
        ? (vn_heap
            ? (uint64_t *)malloc((size_t)vlen * sizeof(uint64_t))
            : vn_local)
        : NULL;

    const uint64_t *vn;
    if (shift) {
        for (int32_t i = vlen - 1; i > 0; i--)
            vn_work[i] = (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn_work[0] = v[0] << shift;
        vn = vn_work;
        un[ulen] = u[ulen - 1] >> (64 - shift);
        for (int32_t i = ulen - 1; i > 0; i--)
            un[i] = (u[i] << shift) | (u[i - 1] >> (64 - shift));
        un[0] = u[0] << shift;
    } else {
        /* B-Z normalizes once at the top, so recursive leaves can read their
         * divisor slice directly instead of copying it into a local arena. */
        vn = v;
        memcpy(un, u, (size_t)ulen * sizeof(uint64_t));
        un[ulen] = 0;
    }

    int32_t m = ulen - vlen;
#if BN_BZ_SKIP_ZERO_TOP_DIGIT
    /* D2n/1n guarantees u < v*B^n and provides only n quotient limbs, so the
     * Knuth digit at position n is known to be zero.  Avoid an estimate and a
     * complete multiply-subtract row for that artificial leading digit. */
    if (skip_zero_top && m >= qw) m = qw - 1;
#else
    (void)skip_zero_top;
#endif
    /* Remainder top-2 limbs live in registers across digits. */
    uint64_t r1 = un[m + vlen];
    uint64_t r0 = un[m + vlen - 1];
    for (int32_t j = m; j >= 0; j--) {
        uint64_t qhat;
        if (__builtin_expect(r1 >= d1 && (r1 > d1 || r0 >= d0), 0)) {
            un[j + vlen] = r1;
            un[j + vlen - 1] = r0;
            qhat = UINT64_MAX;
            uint64_t bw = bn_submul_1(un + j, vn, vlen, qhat);
            uint64_t top = un[j + vlen];
            un[j + vlen] = top - bw;
            if (top < bw) {
                qhat--;
                uint64_t carry = bn_add_n(un + j, un + j, vn, vlen);
                un[j + vlen] += carry;
            }
            r1 = un[j + vlen - 1];
            r0 = un[j + vlen - 2];
        } else {
            qhat = bn_udiv_qr_3by2(r1, r0, un[j + vlen - 2],
                                   d1, d0, dinv, &r1, &r0);
            uint64_t cy = vlen > 2
                ? bn_submul_1(un + j, vn, vlen - 2, qhat)
                : 0;
            uint64_t cy1 = r0 < cy;
            r0 -= cy;
            uint64_t cy2 = r1 < cy1;
            r1 -= cy1;
            if (__builtin_expect(cy2 != 0, 0)) {
                qhat--;
                uint64_t carry = vlen > 2
                    ? bn_add_n(un + j, un + j, vn, vlen - 2)
                    : 0;
                __uint128_t s = (__uint128_t)r0 + d0 + carry;
                r0 = (uint64_t)s;
                r1 += d1 + (uint64_t)(s >> 64);
            }
        }
        if (j < qw) q[j] = qhat;
    }
    un[vlen - 1] = r1;
    un[vlen - 2] = r0;

    int32_t copy = vlen < rw ? vlen : rw;
    if (shift) {
        for (int32_t i = 0; i < copy; i++) {
            uint64_t hi = i + 1 < vlen ? un[i + 1] : 0;
            r[i] = (un[i] >> shift) | (hi << (64 - shift));
        }
    } else {
        memcpy(r, un, (size_t)copy * sizeof(uint64_t));
    }
    if (un_heap) free(un);
    if (shift && vn_heap) free(vn_work);
}

/* Knuth base case with fixed-width outputs (zero-padded to qw / rw limbs). */
static void bz_base_div(const uint64_t *a, int32_t alen, const uint64_t *b, int32_t blen,
                        uint64_t *q, int32_t qw, uint64_t *r, int32_t rw) {
    bz_base_div_into(a, alen, b, blen, q, qw, r, rw, 1);
}

static void bz_d3n2n(const uint64_t *a, const uint64_t *b, int32_t n,
                     uint64_t *q, uint64_t *r, uint64_t *sc);

/* D2n/1n: a (2n limbs) ÷ b (n limbs, top bit set), a < b·β^n.
 * q, r: n limbs each. Odd or small n falls back to Knuth. */
static void bz_d2n1n(const uint64_t *a, const uint64_t *b, int32_t n,
                     uint64_t *q, uint64_t *r, uint64_t *sc) {
    if ((n & 1) || n <= BZ_THRESHOLD) {
        bz_base_div(a, 2 * n, b, n, q, n, r, n);
        return;
    }
    int32_t k = n >> 1;
    uint64_t *r1 = sc;                     /* n limbs */
    uint64_t *t3 = sc + n;                 /* 3k limbs */
    uint64_t *sc2 = t3 + 3 * k;
    bz_d3n2n(a + k, b, n, q + k, r1, sc2);           /* top 3k limbs */
    for (int32_t i = 0; i < k; i++) t3[i] = a[i];
    for (int32_t i = 0; i < n; i++) t3[k + i] = r1[i];
    bz_d3n2n(t3, b, n, q, r, sc2);
}

/* D3n/2n: a (3k limbs, k = n/2) ÷ b (n limbs, top bit set), a < b·β^k.
 * q: k limbs, r: n limbs. Estimate Q̂ from the top 2k limbs vs B1, then correct
 * against D = Q̂·B0 with a (2k+2)-wide signed subtract and ≤2 add-backs. */
static void bz_d3n2n(const uint64_t *a, const uint64_t *b, int32_t n,
                     uint64_t *q, uint64_t *r, uint64_t *sc) {
    int32_t k = n >> 1;
    const uint64_t *A0  = a;               /* k limbs  */
    const uint64_t *A12 = a + k;           /* n limbs  */
    const uint64_t *Blo = b;               /* k limbs */
    const uint64_t *Bhi = b + k;           /* k limbs, top bit set */
    uint64_t *r1  = sc;                    /* k+1 limbs */
    uint64_t *dd  = sc + (k + 1);          /* 2k limbs: Q̂·Blo */
    uint64_t *rh  = dd + 2 * k;            /* 2k+2 limbs: R̂ */
    uint64_t *sc2 = rh + (2 * k + 2);

    if (mag_cmp(A12 + k, bz_trim(A12 + k, k), Bhi, k) < 0) {
        bz_d2n1n(A12, Bhi, k, q, r1, sc2);
        r1[k] = 0;
    } else {
        /* a < b·β^k forces A2 ≤ Bhi, so here A2 == Bhi: clamp Q̂ = β^k − 1 and
         * R1 = A12 − Q̂·Bhi = A1 + Bhi (may carry into limb k). */
        for (int32_t i = 0; i < k; i++) q[i] = ~0ULL;
        r1[k] = bn_add_n(r1, A12, Bhi, k);
#ifdef BN_BZ_PROFILE_COUNTS
        bz_profile_clamped++;
#endif
    }
    /* D = Q̂·Blo */
    int32_t qt = bz_trim(q, k), b0t = bz_trim(Blo, k);
    int32_t dlen = 0;
    if (qt && b0t) {
#ifdef BN_BZ_PROFILE_COUNTS
        int32_t width = qt > b0t ? qt : b0t;
        int bin = 0;
        while (bin < 11 && (1 << bin) < width) bin++;
        bz_profile_mul_calls++;
        bz_profile_mul_q_limbs += (uint64_t)qt;
        bz_profile_mul_b_limbs += (uint64_t)b0t;
        bz_profile_mul_equal += qt == b0t;
        bz_profile_mul_full += qt == k && b0t == k;
        bz_profile_mul_bins[bin]++;
        if (bz_profile_shape_count < 32) {
            int32_t shape = bz_profile_shape_count++;
            bz_profile_shape_k[shape] = k;
            bz_profile_shape_q[shape] = qt;
            bz_profile_shape_b[shape] = b0t;
        }
#endif
        bigint_mul_dispatch(dd, q, qt, Blo, b0t);
        dlen = qt + b0t;
    }
    for (int32_t i = dlen; i < 2 * k; i++) dd[i] = 0;
    /* R̂ = R1·β^k + A0 − D over W = 2k+2 limbs; borrow-out ⇒ negative. */
    int32_t W = 2 * k + 2;
    for (int32_t i = 0; i < k; i++) rh[i] = A0[i];
    for (int32_t i = 0; i <= k; i++) rh[k + i] = r1[i];
    rh[W - 1] = 0;
    uint64_t bw = bn_sub_n(rh, rh, dd, 2 * k);
    for (int32_t i = 2 * k; bw && i < W; i++) {
        uint64_t old = rh[i];
        rh[i] = old - 1;
        bw = old == 0;
    }
    int neg = (int)bw;
    while (neg) {                          /* R̂ ∈ (−2B, B): ≤ 2 corrections */
        uint64_t c = bn_add_n(rh, rh, b, n);
        for (int32_t i = n; c && i < W; i++) {
            uint64_t old = rh[i];
            rh[i] = old + 1;
            c = rh[i] == 0;
        }
        bz_dec1(q, k);
        if (c) neg = 0;                    /* wrapped back to non-negative */
    }
    for (int32_t i = 0; i < n; i++) r[i] = rh[i];
}

/* ---- Approximate quotient-only B-Z spine for root-only sqrt division.
 * Structure mirrors
 * bz_d2n1n/bz_d3n2n exactly, except the LOW half of every level recurses
 * approximately and the bottom-spine correction products (Q-hat times Blo,
 * one M(k) per level) are skipped along with all remainder work.  The
 * result never falls below the true quotient and exceeds it by at most
 * ~2 units of the lowest limb per skipped level (the amount the skipped
 * add-back corrections could have removed) — the caller's certificate
 * window absorbs that.  Preconditions as bz_d2n1n: a (2n limbs) < b*B^n,
 * b top-bit-normalized. */
static void bz_d3n2n_q(const uint64_t *a, const uint64_t *b, int32_t n,
                       uint64_t *q, uint64_t *sc);

static void bz_d2n1n_q(const uint64_t *a, const uint64_t *b, int32_t n,
                       uint64_t *q, uint64_t *sc) {
    if ((n & 1) || n <= BZ_THRESHOLD) {
        bz_base_div_into(a, 2 * n, b, n, q, n, q, 0, 1);
        return;
    }
    int32_t k = n >> 1;
    uint64_t *r1 = sc;                     /* n limbs */
    uint64_t *t3 = sc + n;                 /* 3k limbs */
    uint64_t *sc2 = t3 + 3 * k;
    bz_d3n2n(a + k, b, n, q + k, r1, sc2); /* exact: its rem feeds the low */
    for (int32_t i = 0; i < k; i++) t3[i] = a[i];
    for (int32_t i = 0; i < n; i++) t3[k + i] = r1[i];
    bz_d3n2n_q(t3, b, n, q, sc2);
}

static void bz_d3n2n_q(const uint64_t *a, const uint64_t *b, int32_t n,
                       uint64_t *q, uint64_t *sc) {
    int32_t k = n >> 1;
    const uint64_t *A12 = a + k;
    const uint64_t *Bhi = b + k;
    if (mag_cmp(A12 + k, bz_trim(A12 + k, k), Bhi, k) < 0) {
        bz_d2n1n_q(A12, Bhi, k, q, sc);
    } else {
        for (int32_t i = 0; i < k; i++) q[i] = ~0ULL;
    }
    /* Q-hat correction against Blo intentionally skipped. */
}

/* Top level: normalize once, walk the dividend in n-limb blocks from the top,
 * one D2n/1n per block. Scratch bound: S2(n) = 2.5n + S3(n), S3(n) = 2.5n+3 +
 * S2(n/2) ⇒ S2(n) < 10n + O(log n); 12n+64 is safely above. */
static void mag_divmod_bz(const uint64_t *u, int32_t ulen,
                          const uint64_t *v, int32_t vlen,
                          WBigint **q_out, WBigint **r_out) {
    int shift = __builtin_clzll(v[vlen - 1]);
    int32_t n = vlen;
    int32_t tmax = (ulen + 1 + n - 1) / n + 2;
    size_t total = (size_t)n                    /* vn  */
                 + (size_t)(tmax * n)           /* un, block-padded */
                 + (size_t)(2 * n)              /* Z   */
                 + (size_t)n                    /* rt  */
                 + (size_t)(tmax * n)           /* qf  */
                 + (size_t)(12 * n + 64);       /* recursion scratch */
    uint64_t *mem = bz_ws_get(total);
    if (!mem) {
        BN_DIV_ROUTE_COUNT(bn_div_bz_ws_fallback);
        mag_divmod_knuth(u, ulen, v, vlen, q_out, r_out);
        return;
    }
    uint64_t *vn_work = mem;
    uint64_t *un = vn_work + n;
    uint64_t *Z  = un + tmax * n;
    uint64_t *rt = Z + 2 * n;
    uint64_t *qf = rt + n;
    uint64_t *sc = qf + tmax * n;
    /* Only the block-padded dividend relies on implicit zeros.  Its live
     * prefix is overwritten immediately below, so clear only the padding. */
#if BN_BZ_ZERO_PADDING_ONLY
    memset(un + ulen, 0,
           (size_t)(tmax * n - ulen) * sizeof(uint64_t));
#else
    memset(un, 0, (size_t)(tmax * n) * sizeof(uint64_t));
#endif

    const uint64_t *vn;
    if (shift > 0) {
        for (int32_t i = vlen - 1; i > 0; i--)
            vn_work[i] = (v[i] << shift) | (v[i - 1] >> (64 - shift));
        vn_work[0] = v[0] << shift;
        vn = vn_work;
        un[ulen] = u[ulen - 1] >> (64 - shift);
        for (int32_t i = ulen - 1; i > 0; i--)
            un[i] = (u[i] << shift) | (u[i - 1] >> (64 - shift));
        un[0] = u[0] << shift;
    } else {
#if BN_BZ_ALIAS_NORMALIZED_TOP
        vn = v;
#else
        vn = vn_work;
        for (int32_t i = 0; i < vlen; i++) vn_work[i] = v[i];
#endif
        for (int32_t i = 0; i < ulen; i++) un[i] = u[i];
    }
    int32_t ut = bz_trim(un, ulen + 1);

    int32_t t = (ut + n - 1) / n;
    if (t < 2) t = 2;
    /* top block must be < vn (D2n/1n precondition); else grow by a zero block */
    if (mag_cmp(un + (t - 1) * n, bz_trim(un + (t - 1) * n, n), vn, n) >= 0) t++;

    /*
     * Recursive division interleaves correction products with substantial
     * serial quotient/remainder work.  Let its workers sleep immediately
     * after each product; the short post-job spin that helps back-to-back
     * standalone multiplies only steals execution resources here.
     */
    bn_toom_no_spin++;
    for (int32_t i = 0; i < 2 * n; i++) Z[i] = un[(t - 2) * n + i];
    for (int32_t i = t - 2; i >= 0; i--) {
        bz_d2n1n(Z, vn, n, qf + (size_t)i * n, rt, sc);
        if (i > 0) {
            for (int32_t j = 0; j < n; j++) Z[j] = un[(size_t)(i - 1) * n + j];
            for (int32_t j = 0; j < n; j++) Z[n + j] = rt[j];
        }
    }
    bn_toom_no_spin--;

    if (q_out) {
        int32_t ql = bz_trim(qf, (t - 1) * n);
        WBigint *qb = bigint_alloc_raw_hot(ql > 0 ? ql : 1);
        for (int32_t i = 0; i < ql; i++) qb->limbs[i] = qf[i];
        qb->size = ql;
        *q_out = qb;
    }
    if (r_out) {
        WBigint *rb = bigint_alloc_raw_hot(n);
        if (shift > 0) {
            for (int32_t i = 0; i < n - 1; i++)
                rb->limbs[i] = (rt[i] >> shift) | (rt[i + 1] << (64 - shift));
            rb->limbs[n - 1] = rt[n - 1] >> shift;
        } else {
            for (int32_t i = 0; i < n; i++) rb->limbs[i] = rt[i];
        }
        rb->size = n;
        while (rb->size > 0 && rb->limbs[rb->size - 1] == 0) rb->size--;
        *r_out = rb;
    }
}

#ifndef BN_DIV_RECIP_Q_MIN
#define BN_DIV_RECIP_Q_MIN 16
#endif
/* Upper divisor width for the cached-reciprocal division path.  This is an
 * int32/uint-headroom guard, not a tuning point: wherever the path applies
 * (>= 3 sightings of one normalized divisor) it beats the B-Z spine, and its
 * cache retains ~7n limbs versus the ~26n-limb B-Z workspace the same
 * division would otherwise grow, so there is no memory reason to stop at the
 * recycler's pool cap.  Coupling it to BN_BIGINT_POOL_MAX_CAP (16384) put a
 * 1.4-1.7x division cliff at 16k..262k limbs: every 2n/n benchmark rep above
 * the cap was rejected straight to B-Z (route counters: rej-qmax = 100%). */
#ifndef BN_DIV_RECIP_Q_MAX
#define BN_DIV_RECIP_Q_MAX (1 << 24)
#endif
#ifndef BN_DIV_RECIP_Q_GUARD_LIMBS
#define BN_DIV_RECIP_Q_GUARD_LIMBS 1
#endif
#ifndef BN_DIV_RECIP_R_MIN
#define BN_DIV_RECIP_R_MIN 1024
#endif
#ifndef BN_DIV_BARRETT_R_MIN
#define BN_DIV_BARRETT_R_MIN 4
#endif
#ifndef BN_DIV_BARRETT_LOW_MUL_MAX
#define BN_DIV_BARRETT_LOW_MUL_MAX 56
#endif
#ifndef BN_DIV_BARRETT_LOW_MUL_MIN
#define BN_DIV_BARRETT_LOW_MUL_MIN 25
#endif
/* At exactly 64 divisor limbs the full two-product Barrett rung sits between
 * the triangular low-product range and the width where its products amortize;
 * ordinary division is faster there.  Retain reciprocal reduction on both
 * sides of this narrow hole. */
#ifndef BN_DIV_BARRETT_SKIP_MIN
#define BN_DIV_BARRETT_SKIP_MIN 64
#endif
#ifndef BN_DIV_BARRETT_SKIP_MAX
#define BN_DIV_BARRETT_SKIP_MAX 64
#endif
/* ITEM 11: a repeated fixed modulus in the Barrett skip band (mod@64) can
 * reuse the very reciprocal the quotient path (div1) caches for the same
 * divisor value, instead of re-deriving reduction constants every call.  With
 * reuse on, the remainder-only path no longer short-circuits at the skip band
 * (see mag_divmod_reciprocal_certified); it enters the shared reciprocal cache
 * keyed by the divisor value, so once the divisor clears the 3-sighting warmup
 * gate the cached reciprocal is reused with no recompute.  The warmup gate
 * still keeps varying (cold) divisors on the ordinary division route, so a
 * one-shot modulus never pays for a reciprocal.  Off (0) restores the
 * unconditional skip-band bypass (baseline). */
#ifndef BN_MOD_RECIP_REUSE
#define BN_MOD_RECIP_REUSE 1
#endif
#ifndef BN_DIV_RECIP_WARMUP_SIGHTINGS
#define BN_DIV_RECIP_WARMUP_SIGHTINGS 3
#endif
_Static_assert(BN_DIV_RECIP_WARMUP_SIGHTINGS >= 1 &&
               BN_DIV_RECIP_WARMUP_SIGHTINGS <= 3,
               "reciprocal warmup sightings must be in 1..3");

static int bn_div_recip_reserve(
    uint64_t **memory, size_t *capacity, size_t need) {
    if (need <= *capacity) return 1;
    size_t next_cap = need + need / 2 + 16;
    uint64_t *next =
        (uint64_t *)realloc(*memory, next_cap * sizeof(uint64_t));
    if (!next) return 0;
    *memory = next;
    *capacity = next_cap;
    return 1;
}

/* Low rn limbs of a*b.  Barrett reduction below never observes the upper
 * half of q3*D; for small operands, triangular addmul rows are cheaper than
 * computing and then discarding a complete balanced product.
 *
 * When a row is cut short by the operand (row == bn) rather than by the
 * result window (row == rn - i), the addmul carry lands at rp[i + bn],
 * which is still INSIDE the low-rn window and must be propagated.
 * Discarding it (as this function did until 2026-08) made the Barrett
 * certificate below fail whenever q3 trimmed to vlen limbs (~3 of 4
 * random operand pairs), silently double-paying the 24..56-limb band:
 * a full Barrett attempt, then the ordinary division it fell back to. */
static void bn_mul_low(
    uint64_t *rp, int32_t rn,
    const uint64_t *a, int32_t an,
    const uint64_t *b, int32_t bn) {
    if (an > bn) {
        const uint64_t *swap_limbs = a;
        int32_t swap_len = an;
        a = b;
        an = bn;
        b = swap_limbs;
        bn = swap_len;
    }
    memset(rp, 0, (size_t)rn * sizeof(uint64_t));
    int32_t rows = an < rn ? an : rn;
    int32_t i = 0;
#if defined(__aarch64__) && BN_SCHOOLBOOK_ADDMUL2
    for (; i + 1 < rows; i += 2) {
        int32_t row0 = bn < rn - i ? bn : rn - i;
        int32_t row1 = bn < rn - (i + 1) ? bn : rn - (i + 1);
        if (row1 < 8) break;
        uint64_t carry = bn_addmul_2(rp + i, b, row1, a[i], a[i + 1]);
        if (row0 > row1) {
            rp[rn - 1] += a[i] * b[row1];
        } else {
            for (int32_t p = i + 1 + row1; carry && p < rn; p++) {
                uint64_t old = rp[p];
                rp[p] = old + carry;
                carry = rp[p] < old;
            }
        }
    }
#endif
    for (; i < rows; i++) {
        int32_t row = bn < rn - i ? bn : rn - i;
        uint64_t carry = bn_addmul_1(rp + i, b, row, a[i]);
        for (int32_t p = i + row; carry && p < rn; p++) {
            uint64_t old = rp[p];
            rp[p] = old + carry;
            carry = rp[p] < old;
        }
    }
}

/* ==== Truncated high product (Mulders short product), bn_mul_low's mirror.
 *
 * bn_mulhi_approx(rp, a, b, n, sc): rp[0..n+1) receives an
 * under-approximation of H = floor(A*V / B^(n-1)) (A = {a,n}, V = {b,n},
 * B = 2^64) — the 2n-limb product's top n+1 limbs, anchored one limb below
 * its high half:
 *
 *     0 <= H - rp <= n*B.
 *
 * Base case: accumulate every cross product a_i*b_j with i+j >= n-1
 * exactly (triangular addmul rows).  Each such term is divisible by
 * B^(n-1), so the included sum is an integer at the anchor and fits n+1
 * limbs (the full product is < B^(2n)).  The dropped terms total
 *
 *     sum_{k=0}^{n-2} (k+1)*(B-1)^2*B^k  <  (n-1)*B^n + n*B^(n-1),
 *
 * under n*B anchor units.  Mulders step: split off the low m = n - k limbs
 * (k ~ 3n/4).  One FULL k-by-k product of the two high parts covers every
 * pair with i >= m and j >= m; its limbs from k-m-1 upward land exactly on
 * rp[0..n+1), and its (exact) sub-anchor limbs are dropped — at most one
 * anchor unit.  Two recursive m-by-m short products cover {i < m, j >= k}
 * and {i >= k, j < m}; their thresholds i'+j' >= m-1 sit on the same
 * anchor because k + m = n.  No needed pair is missed (i+j >= n-1 with
 * i < m forces j >= k), so ERR(n) <= 2*ERR(m) + 1, and with 2m < n the
 * bound ERR(n) <= n*B holds inductively.  Callers thus keep >= 57 guard
 * bits below the anchor limb at any n < 2^20 and supply whole guard limbs
 * on top of that.
 *
 * sc needs 2n limbs and must not alias bn_ws (the full products own it).
 *
 * STATUS: wired into the certified-reciprocal division paths below (the
 * 2n/n quotient step and the remainder-only Barrett arm), which consume
 * only the top part of their reciprocal products and run where the pool
 * cannot help the incumbent.  It remains NOT taken for the sqrt spine —
 * measured on Apple M5 Max (LLVM 22, -O3 -flto -mcpu=apple-m5) it does
 * not clear the cost bar that would let a Newton-inversion top quotient
 * beat the sqrt divappr spine.  mulhigh(n)/mul(n), median of 9:
 *
 *     n      sequential   parallel-allowed (the sqrt path's regime)
 *     512      0.87           1.17
 *     1024     0.78           1.06
 *     2048     0.92           1.17
 *     4096     0.92           1.15
 *
 * (best of a {low_pct 20/25/30} x {base 24/48/96} sweep per cell; the
 * defaults below are the best sequential config).  Two structural facts
 * kill the isqrt application, not implementation quality: (a) a single
 * balanced product this size gains ~2-2.5x from the parallel Toom pool,
 * which the short product's serial composition cannot match, so in
 * context mulhigh COSTS MORE than a full multiply; and (b) the Newton
 * residual 1 - high(D*X) cancels its entire high half, so each precision
 * doubling to width v needs the product's limbs down to position ~v -- a
 * width-v short product, not width v/2 -- making an inversion chain to
 * width h cost ~[hp(h) + 2*hp(h/2)/(1-0.4)] ~ 2.4*hp(h).  Composed:
 * chain + high(U*R) ~ 294us at h = 2048 against the incumbent
 * bz_d2n1n_q(2080) at ~266us measured in place (55% of isqrt@4096-root).
 * Full products instead of hp: ~244us -- inside noise of the incumbent
 * and not worth the certificate surface.  Revisit only if the multiply
 * ladder's parallel advantage disappears (single-core targets) or a
 * wraparound (mulmod B^m+-1) residual gets cheap enough to change (b). */
#ifndef BN_MULHI_BASE
#define BN_MULHI_BASE 48
#endif
#ifndef BN_MULHI_LOW_PCT
#define BN_MULHI_LOW_PCT 25
#endif

static void bn_mulhi_base(uint64_t *rp, const uint64_t *a, const uint64_t *b,
                          int32_t n) {
    memset(rp, 0, (size_t)(n + 1) * sizeof(uint64_t));
    int32_t i = 0;
#if defined(__aarch64__) && BN_SCHOOLBOOK_ADDMUL2
    if (n & 1) {
        __uint128_t p0 = (__uint128_t)a[0] * b[n - 1];
        rp[0] = (uint64_t)p0;
        rp[1] = (uint64_t)(p0 >> 64);
        i = 1;
    }
    for (; i + 1 < n; i += 2) {
        uint64_t c = bn_addmul_2(rp, b + (n - 1 - i), i + 1, a[i], a[i + 1]);
        rp[i + 2] = c;
        __uint128_t diag = (__uint128_t)a[i + 1] * b[n - 2 - i] + rp[0];
        rp[0] = (uint64_t)diag;
        uint64_t cy = (uint64_t)(diag >> 64);
        int32_t p = 1;
        while (cy) {
            uint64_t old = rp[p];
            rp[p] = old + cy;
            cy = rp[p] < old;
            p++;
        }
    }
#endif
    for (; i < n; i++) {
        uint64_t c = bn_addmul_1(rp, b + (n - 1 - i), i + 1, a[i]);
        int32_t p = i + 1;
        while (c) {
            uint64_t old = rp[p];
            rp[p] = old + c;
            c = rp[p] < old;
            p++;
        }
    }
}

static void bn_mulhi_approx(uint64_t *rp, const uint64_t *a,
                            const uint64_t *b, int32_t n, uint64_t *sc) {
    if (n <= BN_MULHI_BASE) {
        bn_mulhi_base(rp, a, b, n);
        return;
    }
    int32_t m = (int32_t)(((int64_t)n * BN_MULHI_LOW_PCT) / 100);
    if (m < 1) m = 1;
    int32_t k = n - m;
    int32_t off = k - m - 1;
    bigint_mul_dispatch(sc, a + m, k, b + m, k);
    memcpy(rp, sc + off, (size_t)(n + 1) * sizeof(uint64_t));
    uint64_t *sub = sc;
    uint64_t *sc2 = sc + (m + 1);
    bn_mulhi_approx(sub, a, b + k, m, sc2);
    uint64_t c = bn_add_n(rp, rp, sub, m + 1);
    for (int32_t p = m + 1; c && p <= n; p++) {
        uint64_t old = rp[p];
        rp[p] = old + c;
        c = rp[p] < old;
    }
    bn_mulhi_approx(sub, a + k, b, m, sc2);
    c = bn_add_n(rp, rp, sub, m + 1);
    for (int32_t p = m + 1; c && p <= n; p++) {
        uint64_t old = rp[p];
        rp[p] = old + c;
        c = rp[p] < old;
    }
}

/*
 * With g guard limbs, cache R = floor(B^(2n+g) / D) after seeing the same
 * n-limb divisor three times.  For U < B^(2n), let
 *
 *     UR = q0 B^(2n+g) + T,  0 <= T < B^(2n+g).
 *
 * Since B^(2n+g) = RD + S with 0 <= S < D,
 *
 *     0 <= U/D - UR/B^(2n+g) < B^(-g).
 *
 * Therefore q0 is the exact quotient whenever
 *
 *     T < B^(2n+g) - B^(2n).
 *
 * That certificate fails only when T's top g limbs are all UINT64_MAX
 * (probability about B^-g for ordinary inputs); the ordinary division path
 * handles that case.  One 64-bit guard limb is already enough to make the
 * failure probability 2^-64 while keeping the steady-state product near
 * 2n-by-n.  No quotient-times-divisor verification product is needed.
 */
static int mag_divmod_reciprocal_certified(
    const uint64_t *u, int32_t ulen,
    const uint64_t *v, int32_t vlen,
    WBigint **q_out, WBigint **r_out) {
#if !BN_MOD_RECIP_REUSE
    /* Baseline: the remainder-only path skips the reciprocal machinery inside
     * the narrow Barrett hole.  With BN_MOD_RECIP_REUSE on this bypass is
     * dropped so a repeated modulus can reach the shared reciprocal cache;
     * the warmup gate below still routes cold divisors to ordinary division. */
    if (r_out && !q_out &&
        vlen >= BN_DIV_BARRETT_SKIP_MIN &&
        vlen <= BN_DIV_BARRETT_SKIP_MAX)
        return 0;
#endif
#ifdef BN_DIV_ROUTE_COUNTERS
    if (vlen > BN_DIV_RECIP_Q_MAX)
        bn_div_recip_reject_qmax++;
    else if (ulen != 2 * vlen || !(v[vlen - 1] >> 63))
        bn_div_recip_reject_shape++;
    else if ((q_out && vlen < BN_DIV_RECIP_Q_MIN) ||
             (r_out && vlen <
                 (q_out ? BN_DIV_RECIP_R_MIN : BN_DIV_BARRETT_R_MIN)))
        bn_div_recip_reject_min++;
#endif
    if (vlen > BN_DIV_RECIP_Q_MAX ||
        ulen != 2 * vlen || !(v[vlen - 1] >> 63) ||
        (q_out && vlen < BN_DIV_RECIP_Q_MIN) ||
        (r_out && vlen <
            (q_out ? BN_DIV_RECIP_R_MIN : BN_DIV_BARRETT_R_MIN)))
        return 0;

    /* The most-recently-used entry hits on the very next call in every
     * repeated-divisor pattern, so it is the ONLY entry the steady state
     * tests — structured as the original single-entry probe so the compiled
     * hot shape stays identical (an entry-scan loop here measurably slowed
     * the whole certified divide).  The second entry exists for callers
     * that alternate two divisor widths inside one outer operation (the
     * sqrt recursion at an 8192-limb root divides by its 2048- and
     * 1024-limb partial roots each call); those flip mru per call and pay
     * one extra probe, which is what they saved by not thrashing. */
    size_t n = (size_t)vlen;
    WDivReciprocalCache *cache = &bn_div_recip_caches[bn_div_recip_cache_mru];
    int same =
        cache->state != 0 && cache->n == vlen &&
        cache->key_cap >= n &&
        memcmp(cache->key, v, n * sizeof(uint64_t)) == 0;
#if BN_DIV_RECIP_CACHE_ENTRIES > 1
    if (__builtin_expect(!same, 0)) {
        WDivReciprocalCache *other =
            &bn_div_recip_caches[bn_div_recip_cache_mru ^ 1];
        if (other->state != 0 && other->n == vlen &&
            other->key_cap >= n &&
            memcmp(other->key, v, n * sizeof(uint64_t)) == 0) {
            cache = other;
            same = 1;
        } else if (cache->state != 0) {
            /* Full miss with the MRU entry occupied: take the other slot —
             * empty it is a plain fill, occupied it is the LRU eviction
             * (never displace the most recently proven divisor). */
            cache = other;
        }
        /* Miss-only by design, and NOT a displace-form candidate: the
         * steady-state hit performs no store at all, and the mru load
         * above is address generation — hoisting this store out of the
         * miss branch removes no dependent load (8/12 displace audit:
         * unconditional-store probe measured div@256/512 and mod@256 at
         * +0.05..0.24%, pure noise). */
        bn_div_recip_cache_mru = (int)(cache - bn_div_recip_caches);
    }
    _Static_assert(BN_DIV_RECIP_CACHE_ENTRIES == 2,
                   "the mru^1 probe pairs exactly two entries");
#endif
    if (!same) {
        if (!bn_div_recip_reserve(&cache->key, &cache->key_cap, n)) {
            cache->state = 0;
            return 0;
        }
        memcpy(cache->key, v, n * sizeof(uint64_t));
        cache->n = vlen;
#if BN_DIV_RECIP_WARMUP_SIGHTINGS == 1
        cache->state = 2;
#else
        cache->state = 1;
        BN_DIV_ROUTE_COUNT(bn_div_recip_warmup);
        return 0;
#endif
    }
    if (cache->state < 0) return 0;
    if (cache->state == 1) {
        cache->state = 2;
#if BN_DIV_RECIP_WARMUP_SIGHTINGS == 3
        BN_DIV_ROUTE_COUNT(bn_div_recip_warmup);
        return 0;
#endif
    }

    size_t guard = BN_DIV_RECIP_Q_GUARD_LIMBS;
    size_t reciprocal_len = n + guard + 1;
    /* Sized for the widest client: the warm-fill numerator (2n+g+1), the
     * half-width quotient product (2n+4), and the short-product layout
     * rp[0..n+3) + 2*(n+2)-limb scratch = 3n+7. */
    size_t product_len = 3 * n + guard + 6;
    if (!bn_div_recip_reserve(
            &cache->reciprocal, &cache->reciprocal_cap, reciprocal_len) ||
        !bn_div_recip_reserve(
            &cache->product, &cache->product_cap, product_len)) {
        cache->state = -1;
        return 0;
    }

    if (cache->state == 2) {
        size_t numerator_len = 2 * n + guard + 1;
        memset(cache->product, 0, numerator_len * sizeof(uint64_t));
        cache->product[2 * n + guard] = 1;
        WBigint *reciprocal;
        mag_divmod_bz(
            cache->product, (int32_t)numerator_len,
            v, vlen, &reciprocal, NULL);
        int32_t rlen = reciprocal->size;
        if (rlen <= 0 || (size_t)rlen > reciprocal_len) {
            bigint_release(reciprocal);
            cache->state = -1;
            return 0;
        }
        memcpy(cache->reciprocal, reciprocal->limbs,
               (size_t)rlen * sizeof(uint64_t));
        memset(cache->reciprocal + rlen, 0,
               (reciprocal_len - (size_t)rlen) * sizeof(uint64_t));
        bigint_release(reciprocal);
        cache->state = 3;
    }

    /*
     * R/B = floor(B^(2n)/D) is the ordinary Barrett reciprocal mu.  For a
     * remainder-only 2n/n division, using q1=floor(U/B^(n-1)) turns the first
     * product into (n+1)-by-(n+1), rather than the 2n-by-(n+2) product needed
     * to recover the exact quotient below.  The low n+1 limbs of U-q3*D are
     * congruent to U modulo D and, because D is normalized, need at most two
     * subtractions of D.  Both products use the existing TLS work buffers.
     */
    if (r_out && !q_out && vlen >= BN_DIV_BARRETT_R_MIN) {
        size_t barrett_product_len = 2 * n + 2;

/* Below this divisor width the two Barrett products use the Mulders short
 * product and sequential multiplication, avoiding worker-pool wake stalls
 * in interleaved ABBA quartet blocks at 384..512 limbs. */
#ifndef BN_DIV_RECIP_PAR_MIN
#define BN_DIV_RECIP_PAR_MIN 768
#endif
/* In the forced-sequential band the q3 estimate comes from a Mulders short
 * product over one extra live limb of U and the FULL cached reciprocal
 * (floor(B^(2n+1)/D), n+2 limbs) instead of the complete (n+1)x(n+1)
 * q1*mu product whose low half is discarded: measured (M5 Max, LLVM 22)
 * mulhigh(N)/mul(N) = 0.63..0.87 sequentially across N = 26..770.  With
 * pool-eligible products (vlen >= BN_DIV_RECIP_PAR_MIN) the short product
 * loses (1.07-1.22x) and the incumbent stays.  Error bound: writing
 * A = floor(U/B^(n-2)) (n+2 limbs) and R = floor(B^(2n+1)/D),
 *
 *   U*R = A*R*B^(n-2) + (U mod B^(n-2))*R,
 *
 * bn_mulhi_approx returns rp <= H = floor(A*R/B^(n+1)) with
 * H - rp <= (n+2)*B, so with Δ collecting the three dropped tails
 * (mulhigh deficit, A*R mod B^(n+1), (U mod B^(n-2))*R < 2*B^(2n-1)):
 *
 *   U*R = rp*B^(2n-1) + Δ,   0 <= Δ < (n+3)*B^(2n).
 *
 * For q̂ = floor(rp/B^2) and q̄ = floor(U*R/B^(2n+1)) that gives
 * q̄ ∈ [q̂, q̂+1], and 0 <= U/D - U*R/B^(2n+1) < 1/B puts the true
 * quotient in [q̄, q̄+1], so U - q̂*D ∈ [0, 3D): exactly the two
 * correction subtractions the certificate below already allows. */
#ifndef BN_DIV_RECIP_MULHI_R_MIN
#define BN_DIV_RECIP_MULHI_R_MIN 8
#endif
        int sequential_products = vlen < BN_DIV_RECIP_PAR_MIN;
        int use_mulhi = sequential_products &&
                        vlen >= BN_DIV_RECIP_MULHI_R_MIN;
        /* mulhigh needs rp (n+3 limbs) plus 2*(n+2) scratch that must not
         * alias bn_ws (its internal full product owns bn_ws). */
        size_t first_product_len =
            use_mulhi ? 3 * n + 7 : barrett_product_len;
        if (!bn_div_recip_reserve(
                &cache->product, &cache->product_cap,
                first_product_len) ||
            !bn_div_recip_reserve(
                &cache->verification, &cache->verification_cap,
                barrett_product_len))
            return 0;

        if (sequential_products) bn_toom_parallel_depth++;
#if BN_DIV_RECIP_DIFF28 || BN_BENCH_RUNTIME_DIV_RECIP_DIFF28_KNOB
        int use_diff28 = BN_DIV_RECIP_DIFF28_ENABLED();
        if (use_diff28) bn_div_recip_diff28_depth++;
#endif

        const uint64_t *q3;
        if (use_mulhi) {
            bn_mulhi_approx(cache->product, u + n - 2,
                            cache->reciprocal, vlen + 2,
                            cache->product + (n + 3));
            q3 = cache->product + 2;
        } else {
            const uint64_t *q1 = u + n - 1;
            const uint64_t *mu = cache->reciprocal + 1;
            uint64_t *product_out = cache->product;
            int product_redirected = 0;
#if BN_EQ_PAGE_HAZARD_GUARD
            /* The TLS product buffer can land close enough to either
             * source's page offset that streamed stores false-alias later
             * loads.  From eight limbs up, always choosing the page-safe
             * arena costs less than the residual layout modes; the tiny
             * four-limb leaf redirects only when the explicit hazard test
             * fires.  Copy the complete product back before q3 aliases
             * it.  The length guard preserves the redirect arena's
             * 128-result-limb contract. */
            if (barrett_product_len <= 128 &&
                (vlen >= 8 || BN_EQ_PAGE_HAZARD_FORCE ||
                 bn_page_hazard(product_out, q1) ||
                 bn_page_hazard(product_out, mu))) {
                uint64_t *safe = bn_eq_redirect_slot(q1, mu);
                if (safe) {
                    product_out = safe;
                    product_redirected = 1;
                }
            }
#endif
            if (vlen == 4) {
                bigint_mul_schoolbook_into(product_out, q1, 5, mu, 5);
            } else {
                bigint_mul_dispatch(
                    product_out + 2, q1 + 1, vlen, mu + 1, vlen);
                __uint128_t p00 = (__uint128_t)q1[0] * mu[0];
                product_out[0] = (uint64_t)p00;
                product_out[1] = (uint64_t)(p00 >> 64);
                uint64_t c1 = bn_addmul_1(product_out + 1, mu + 1, vlen, q1[0]);
                uint64_t c2 = bn_addmul_1(product_out + 1, q1 + 1, vlen, mu[0]);
                __uint128_t top = (__uint128_t)product_out[n + 1] + c1 + c2;
                product_out[n + 1] = (uint64_t)top;
                uint64_t cy = (uint64_t)(top >> 64);
                for (size_t k = n + 2; cy && k < 2 * n + 2; k++) {
                    uint64_t old = product_out[k];
                    product_out[k] = old + cy;
                    cy = product_out[k] < old;
                }
            }
            if (product_redirected)
                memcpy(cache->product, product_out,
                       barrett_product_len * sizeof(uint64_t));

            q3 = cache->product + n + 1;
        }
        int32_t q3_len = vlen + 1;
        while (q3_len > 0 && q3[q3_len - 1] == 0)
            q3_len--;
        uint64_t *verification_out = cache->verification;
        int verification_redirected = 0;
#if BN_EQ_PAGE_HAZARD_GUARD
        /* At the top of the small Barrett range, the triangular low product
         * is long enough to show the same page-offset mode as the full first
         * product.  The first result has already been copied back, so safely
         * reuse its redirect arena and copy only the n+1 live low limbs. */
        if (vlen >= 48 && barrett_product_len <= 128) {
            uint64_t *safe = bn_eq_redirect_slot(q3, v);
            if (safe) {
                verification_out = safe;
                verification_redirected = 1;
            }
        }
#endif
        if (vlen >= BN_DIV_BARRETT_LOW_MUL_MIN &&
            vlen <= BN_DIV_BARRETT_LOW_MUL_MAX) {
            bn_mul_low(
                verification_out, vlen + 1,
                q3, q3_len, v, vlen);
        } else {
            uint64_t q3_top = q3[n];
            int32_t q3_lo_len = q3_len > vlen ? vlen : q3_len;
            while (q3_lo_len > 0 && q3[q3_lo_len - 1] == 0)
                q3_lo_len--;
            if (q3_lo_len > 0) {
                if (vlen == 4)
                    bigint_mul_schoolbook_into(
                        verification_out, q3, q3_lo_len, v, 4);
                else
                    bigint_mul_dispatch(
                        verification_out, q3, q3_lo_len, v, vlen);
            } else {
                /* Only these live limbs feed the reduction below. */
                memset(verification_out, 0,
                       (n + 1) * sizeof(uint64_t));
            }
            verification_out[n] += q3_top * v[0];
        }
        if (verification_redirected)
            memcpy(cache->verification, verification_out,
                   (n + 1) * sizeof(uint64_t));
#if BN_DIV_RECIP_DIFF28 || BN_BENCH_RUNTIME_DIV_RECIP_DIFF28_KNOB
        if (use_diff28) bn_div_recip_diff28_depth--;
#endif
        if (sequential_products) bn_toom_parallel_depth--;

        uint64_t *reduced = cache->product;
        (void)bn_sub_n(
            reduced, u, cache->verification, vlen + 1);
        for (int correction = 0; correction < 2; correction++) {
            if (reduced[n] == 0 &&
                mag_cmp(reduced, vlen, v, vlen) < 0)
                break;
            uint64_t borrow =
                bn_sub_n(reduced, reduced, v, vlen);
            reduced[n] -= borrow;
        }
        if (reduced[n] != 0 ||
            mag_cmp(reduced, vlen, v, vlen) >= 0) {
            BN_DIV_ROUTE_COUNT(bn_div_recip_cert_fail);
            return 0;
        }

        WBigint *r = bigint_alloc_raw_hot(vlen);
        memcpy(r->limbs, reduced, n * sizeof(uint64_t));
        r->size = vlen;
        while (r->size > 0 && r->limbs[r->size - 1] == 0)
            r->size--;
        *r_out = r;
        BN_DIV_ROUTE_COUNT(bn_div_route_recip_hit);
        return 1;
    }

    /* Quotient step.  Only the top n+2+g limbs of U*R are ever consumed
     * (g certificate limbs at B^(2n) plus the quotient), so the full
     * 2n-by-(n+g+1) product is twice the needed work.  Both replacements
     * drop the low n-2 limbs of U up front: with A = floor(U/B^(n-2))
     * (n+2 limbs, all live) and R = floor(B^(2n+g)/D),
     *
     *   U*R = A*R*B^(n-2) + (U mod B^(n-2))*R,
     *
     * and the dropped tail is < 2*B^(2n-1).  rp names n+3 limbs
     * approximating floor(A*R/B^(n+1)) from below:
     *
     *   - exact half-width product (pool-eligible widths): rp is the top
     *     of the balanced (n+2)x(n+2) A*R, deficit only the sub-anchor
     *     tails, Δ < B^(2n) in U*R terms;
     *   - Mulders short product (below the pool floor, or when a caller
     *     already forced products sequential): bn_mulhi_approx adds a
     *     deficit <= (n+2)*B at B^(n+1), so Δ < (n+3)*B^(2n).
     *
     * With rp = Q̂*B^2 + rp[1]*B + rp[0],
     *
     *   Q̂ <= U*R/B^(2n+g) <= U/D < Q̂ + (rp[1] + n + 5)/B,
     *
     * (the n+5 collects Δ, rp[0], and the U/D - U*R/B^(2n+g) < B^-g gap),
     * so rp[1] <= B - (n+5) certifies floor(U/D) = Q̂ outright — the
     * all-ones probe of the exact product's certificate limbs becomes a
     * headroom test on the one approximate certificate limb, failing with
     * probability ~n/B instead of ~1/B; failure still falls back to the
     * ordinary division path.  Measured (M5 Max): the incumbent product
     * is 98-100% of this divide's cost; the half-width product more than
     * halves it at 512+ limbs (the two-lane rect pool only ever recovered
     * the unbalance penalty) and the short product wins 0.58x at 256. */
    _Static_assert(BN_DIV_RECIP_Q_GUARD_LIMBS == 1,
                   "the rp[1] headroom certificate is derived for g == 1");
#ifndef BN_DIV_RECIP_MULHI_Q_MAX
#define BN_DIV_RECIP_MULHI_Q_MAX 510
#endif
    const uint64_t *rp;
    if (vlen < BN_DIV_RECIP_MULHI_Q_MAX || bn_toom_parallel_depth) {
        /* rp = product[0..n+3); scratch above it (2n+4, never bn_ws). */
        bn_toom_parallel_depth++;
        bn_mulhi_approx(cache->product, u + n - 2,
                        cache->reciprocal, vlen + 2,
                        cache->product + (n + 3));
        bn_toom_parallel_depth--;
        rp = cache->product;
    } else {
        bigint_mul_dispatch(
            cache->product, u + n - 2, vlen + 2,
            cache->reciprocal, (int32_t)reciprocal_len);
        rp = cache->product + n + 1;
    }

    if (rp[1] <= ~(uint64_t)(vlen + 8)) {
        const uint64_t *q_limbs = rp + 2;
        int32_t q_len = vlen + 1;
        while (q_len > 0 && q_limbs[q_len - 1] == 0)
            q_len--;
        if (r_out) {
            size_t verification_len = 2 * n + 2;
            if (!bn_div_recip_reserve(
                    &cache->verification,
                    &cache->verification_cap,
                    verification_len))
                return 0;
            int32_t q_lo_len = q_len > vlen ? vlen : q_len;
            while (q_lo_len > 0 && q_limbs[q_lo_len - 1] == 0)
                q_lo_len--;
            if (q_lo_len > 0) {
                bigint_mul_dispatch(
                    cache->verification,
                    q_limbs, q_lo_len, v, vlen);
            } else {
                memset(cache->verification, 0,
                       n * sizeof(uint64_t));
            }
            WBigint *r = bigint_alloc_raw_hot(vlen);
            (void)bn_sub_n(
                r->limbs, u, cache->verification, vlen);
            r->size = vlen;
            while (r->size > 0 && r->limbs[r->size - 1] == 0)
                r->size--;
            *r_out = r;
        }
        if (q_out) {
            WBigint *q = bigint_alloc_raw_hot(vlen + 1);
            memcpy(q->limbs, q_limbs,
                   (size_t)q_len * sizeof(uint64_t));
            q->size = q_len;
            *q_out = q;
        }
        BN_DIV_ROUTE_COUNT(bn_div_route_recip_hit);
        return 1;
    }
    BN_DIV_ROUTE_COUNT(bn_div_recip_cert_fail);
    return 0;
}

/* Dispatcher: B–Z pays off only when BOTH the divisor and the quotient are
 * large (small quotients make Knuth O(m·n) cheap already). */
static void mag_divmod(const uint64_t *u, int32_t ulen,
                       const uint64_t *v, int32_t vlen,
                       WBigint **q_out, WBigint **r_out) {
#if BN_TZ_STRIP
    /* Divisor trailing zero limbs (v = v'·B^z): q = (u >> 64z) / v' and
     * r = ((u >> 64z) mod v')·B^z + (u mod B^z).  Magnitude identity:
     * r'·B^z + u_lo ≤ (v'−1)·B^z + B^z − 1 < v.  One never-taken
     * load+branch on random divisors; the decimal D&C ladder divides by
     * 10^(18·2^j) (≥2 whole zero limbs from j=3), which rides this. */
    if (__builtin_expect(v[0] == 0, 0) &&
        v[(vlen + 1) / 2 - 1] == 0) {
        /* The second probe is the one-load pre-gate: 2z ≥ vlen (below)
         * requires every limb under ⌈vlen/2⌉ to be zero, so a nonzero
         * mid limb rejects without scanning the zero run. */
        int32_t z = 1;
        while (v[z] == 0) z++;              /* v normalized: z < vlen */
        /* Only strip when it at least HALVES the divisor: the division
         * spine is dense with shape-specialized paths (certified
         * reciprocal at 2n/n, width-tuned kernels), and a small strip
         * demotes a tuned shape to a generic one — measured 256/128
         * z=32 → 224/96 = 0.91x (a loss) while z=64 → 192/64 = 1.26x.
         * At 2z ≥ vlen the quadratic work reduction dominates any
         * shape penalty.  Small-z divisors (the decimal ladder's P_j)
         * deliberately stay on their tuned paths. */
        if (ulen > z && 2 * z >= vlen) {
            if (!r_out) {
                mag_divmod(u + z, ulen - z, v + z, vlen - z, q_out, NULL);
                return;
            }
            WBigint *q = NULL, *r2 = NULL;
            mag_divmod(u + z, ulen - z, v + z, vlen - z,
                       q_out ? &q : NULL, &r2);
            int32_t r2n = r2->size;
            WBigint *r = bigint_alloc_raw_hot(r2n + z);
            memcpy(r->limbs, u, (size_t)z * sizeof(uint64_t));
            if (r2n)
                memcpy(r->limbs + z, r2->limbs,
                       (size_t)r2n * sizeof(uint64_t));
            int32_t rn = r2n + z;
            while (rn > 0 && r->limbs[rn - 1] == 0) rn--;
            r->size = rn;
            bigint_release(r2);
            if (q_out) *q_out = q;
            *r_out = r;
            return;
        }
        /* ulen ≤ z means u < v: leave the generic path to handle it. */
    }
#endif
#if BN_MOD_84_DIRECT || BN_BENCH_RUNTIME_MOD84_KNOB
    if (BN_MOD_84_DIRECT_ENABLED() &&
        ulen == 8 && vlen == 4 && r_out && !q_out) {
        *r_out = mag_mod_84(u, v);
        return;
    }
#endif
#if BN_DIV_84_DIRECT
    if (ulen == 8 && vlen == 4 && q_out) {
        *q_out = mag_div_84(u, v, r_out);
        return;
    }
#endif
#if BN_DIVMOD_42
    if (ulen == 4 && vlen == 2) {
        mag_divmod_42(u, v, q_out, r_out);
        return;
    }
#endif
#if BN_MOD_63_DIRECT
    if (ulen == 6 && vlen == 3 && r_out && !q_out) {
        *r_out = mag_mod_63(u, v);
        return;
    }
#endif
#ifndef BN_DIV_RECIP_CACHE
#define BN_DIV_RECIP_CACHE 1
#endif
#if BN_DIV_RECIP_CACHE
    if ((q_out || r_out) &&
        mag_divmod_reciprocal_certified(
            u, ulen, v, vlen, q_out, r_out))
        return;
#endif
    if (q_out && !r_out) {
#if BN_DIV_TRIANGULAR_Q_CERTIFIED && BN_DIV_TRIANGULAR_Q_SELECT
#if BN_DIV_63_DIRECT
        if (ulen == 6 && vlen == 3) {
            WBigint *q = mag_div_q_63_certified(u, v);
            if (q) {
                *q_out = q;
                return;
            }
        }
#endif
        WBigint *q =
            mag_div_q_triangular_certified(u, ulen, v, vlen);
        if (q) {
            *q_out = q;
            BN_DIV_ROUTE_COUNT(bn_div_route_triangular_hit);
            return;
        }
#endif
    }
    if (vlen >= BZ_TOP_THRESHOLD && ulen - vlen >= BZ_THRESHOLD) {
        BN_DIV_ROUTE_COUNT(bn_div_route_bz);
        mag_divmod_bz(u, ulen, v, vlen, q_out, r_out);
        return;
    }
    BN_DIV_ROUTE_COUNT(bn_div_route_knuth);
    mag_divmod_knuth(u, ulen, v, vlen, q_out, r_out);
}

/* Exact division q = n / d for KNOWN divisors (d | n, d != 0), Hensel /
 * Jebelean style: strip d's 2-adic part (n carries it too), then produce
 * quotient limbs low-to-high as q_i = r_i * (-d)^-1 ... * inv mod B with a
 * truncated submul row — everything runs mod B^qn, so there is no
 * normalization, no quotient estimation, and no borrow correction.  About
 * half the work of a full division for one-limb divisors and strictly less
 * for multi-limb ones.  Only valid when d divides n exactly. */
static WBigint *mag_divexact(const uint64_t *np, int32_t nn,
                             const uint64_t *dp, int32_t dn) {
    /* 2-adic valuation of d: whole limbs, then bits. */
    int32_t zl = 0;
    while (dp[zl] == 0) zl++;                   /* d != 0 */
    int tz = __builtin_ctzll(dp[zl]);
    np += zl;
    nn -= zl;
    dp += zl;
    dn -= zl;
    int32_t qn = nn - dn + (mag_cmp(np + nn - dn, dn, dp, dn) >= 0);
    if (qn <= 0) qn = 1;
    if (qn == 1) {
        uint64_t d0 = (dp[0] >> tz) | (tz && dn > 1 ? (dp[1] << (64 - tz)) : 0);
        uint64_t r0 = (np[0] >> tz) | (tz && nn > 1 ? (np[1] << (64 - tz)) : 0);
        uint64_t q0 = r0 * bn_modinv_odd(d0);
        WBigint *q = bigint_alloc_raw_hot_exact(1U);
        q->limbs[0] = q0;
        q->size = q0 != 0 ? 1 : 0;
        return q;
    }
    WBigint *q = bigint_alloc_raw_hot(qn);
    /* Only the low qn limbs of the shifted r and d ever matter (mod B^qn). */
    int32_t dw = dn < qn ? dn : qn;
    uint64_t d0v, dstack[64];
    uint64_t *dv = NULL;
    const uint64_t *dsh;
    uint64_t rstack[128];
    uint64_t *r = qn <= 128
        ? rstack
        : (uint64_t *)malloc((size_t)qn * sizeof(uint64_t));
    if (!r) die("divexact: out of memory");
    if (tz == 0) {
        dsh = dp;
        d0v = dp[0];
        for (int32_t i = 0; i < qn; i++) r[i] = np[i];
    } else {
        dv = dw <= 64
            ? dstack
            : (uint64_t *)malloc((size_t)dw * sizeof(uint64_t));
        if (!dv) die("divexact: out of memory");
        for (int32_t i = 0; i < dw; i++) {
            uint64_t hi = i + 1 < dn ? dp[i + 1] : 0;
            dv[i] = (dp[i] >> tz) | (hi << (64 - tz));
        }
        dsh = dv;
        d0v = dv[0];
        for (int32_t i = 0; i < qn; i++) {
            uint64_t hi = i + 1 < nn ? np[i + 1] : 0;
            r[i] = (np[i] >> tz) | (hi << (64 - tz));
        }
    }
    uint64_t inv = bn_modinv_odd(d0v);
    if (qn == 4 && dw == 4) {
        uint64_t r0 = r[0], r1 = r[1], r2 = r[2], r3 = r[3];
        uint64_t d1 = dsh[1], d2 = dsh[2], d3 = dsh[3];
        uint64_t q0 = r0 * inv;
        q->limbs[0] = q0;
        {
            uint64_t b = (uint64_t)(((__uint128_t)q0 * d0v) >> 64);
            __uint128_t p1 = (__uint128_t)q0 * d1 + b;
            uint64_t lo1 = (uint64_t)p1;
            b = (uint64_t)(p1 >> 64) + (r1 < lo1);
            r1 -= lo1;
            __uint128_t p2 = (__uint128_t)q0 * d2 + b;
            uint64_t lo2 = (uint64_t)p2;
            b = (uint64_t)(p2 >> 64) + (r2 < lo2);
            r2 -= lo2;
            r3 -= (uint64_t)(q0 * d3) + b;
        }
        uint64_t q1 = r1 * inv;
        q->limbs[1] = q1;
        {
            uint64_t b = (uint64_t)(((__uint128_t)q1 * d0v) >> 64);
            __uint128_t p1 = (__uint128_t)q1 * d1 + b;
            uint64_t lo1 = (uint64_t)p1;
            b = (uint64_t)(p1 >> 64) + (r2 < lo1);
            r2 -= lo1;
            r3 -= (uint64_t)(q1 * d2) + b;
        }
        uint64_t q2 = r2 * inv;
        q->limbs[2] = q2;
        {
            uint64_t b = (uint64_t)(((__uint128_t)q2 * d0v) >> 64);
            r3 -= (uint64_t)(q2 * d1) + b;
        }
        q->limbs[3] = r3 * inv;
        int32_t qs = 4;
        while (qs > 0 && q->limbs[qs - 1] == 0) qs--;
        q->size = qs;
        return q;
    }
    for (int32_t i = 0; i < qn; i++) {
        uint64_t qi = r[i] * inv;
        q->limbs[i] = qi;
        if (i == qn - 1) break;
        if (i == qn - 2) {
            uint64_t b = (uint64_t)(((__uint128_t)qi * d0v) >> 64);
            r[qn - 1] -= b + (dw >= 2 ? qi * dsh[1] : 0);
            q->limbs[qn - 1] = r[qn - 1] * inv;
            break;
        }
        int32_t row = dw < qn - i ? dw : qn - i;
        if (row > 1 || (row == 1 && i + 1 < qn)) {
            uint64_t bw = bn_submul_1(r + i, dsh, row, qi);
            for (int32_t k = i + row; bw && k < qn; k++) {
                uint64_t old = r[k];
                r[k] = old - bw;
                bw = old < bw;
            }
        }
    }
    if (r != rstack) free(r);
    if (dv && dv != dstack) free(dv);
    int32_t qs = qn;
    while (qs > 0 && q->limbs[qs - 1] == 0) qs--;
    q->size = qs;
    return q;
}

static __attribute__((noinline))
WValue bigint_div_any_generic(WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *al = integer_limbs(a, &sa, &alen);
    const uint64_t *bl = integer_limbs(b, &sb, &blen);

    int result_neg = (alen < 0) != (blen < 0);
    int32_t a_abs = alen < 0 ? -alen : alen;
    int32_t b_abs = blen < 0 ? -blen : blen;
    if (b_abs == 0) die_as("ZeroDivisionError", "division by zero");
    if (a_abs == 0) return w_box_int(0);

    WBigint *q;
    if (b_abs == 1) {
        uint64_t rem;
        q = mag_div_single(al, a_abs, bl[0], &rem);
#if BN_DIVMOD_42 && BN_DIVMOD_42_DIRECT
    } else if (a_abs == 4 && b_abs == 2) {
        q = mag_div_42(al, bl);
#endif
    } else {
        mag_divmod(al, a_abs, bl, b_abs, &q, NULL);
    }
    if (result_neg && q->size > 0) q->size = -q->size;
#ifndef BN_DIV_KNOWN_NORMALIZED
#define BN_DIV_KNOWN_NORMALIZED 1
#endif
#if BN_DIV_KNOWN_NORMALIZED
    return bigint_finish_mag_sub(q);
#else
    return bigint_normalize(q);
#endif
}

static __attribute__((noinline))
WValue bigint_mod_any_generic(WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *al = integer_limbs(a, &sa, &alen);
    const uint64_t *bl = integer_limbs(b, &sb, &blen);

    int a_neg = alen < 0;
    int32_t a_abs = a_neg ? -alen : alen;
    int32_t b_abs = blen < 0 ? -blen : blen;
    if (b_abs == 0) die("modulo by zero");
    if (a_abs == 0) return w_box_int(0);
    if (b_abs == 1) {
        uint64_t rem = mag_mod_single(al, a_abs, bl[0]);
        if (!a_neg || rem == 0) return bigint_from_u64(rem);
        if (rem <= (uint64_t)W_INT48_MAX) return w_box_int(-(int64_t)rem);
        WBigint *r = bigint_alloc(1);
        r->limbs[0] = rem;
        r->size = -1;
        return bigint_box(r);
    }

    WBigint *r;
#if BN_DIVMOD_42 && BN_DIVMOD_42_DIRECT
    if (a_abs == 4 && b_abs == 2)
        r = mag_mod_42(al, bl);
    else
#endif
    mag_divmod(al, a_abs, bl, b_abs, NULL, &r);
    if (a_neg && r->size > 0) r->size = -r->size;
#if BN_DIV_KNOWN_NORMALIZED
    return bigint_finish_mag_sub(r);
#else
    return bigint_normalize(r);
#endif
}

#ifndef BN_DIVMOD_42_BOXED_FAST
#define BN_DIVMOD_42_BOXED_FAST 1
#endif
#ifndef BN_DIV_BY_LIMB_BOXED_FAST
#define BN_DIV_BY_LIMB_BOXED_FAST 1
#endif
#ifndef BN_DIV1_SMALL_NORMALIZED
#if defined(__aarch64__)
#define BN_DIV1_SMALL_NORMALIZED 1
#else
#define BN_DIV1_SMALL_NORMALIZED 0
#endif
#endif
#ifndef BN_DIV_63_BOXED_FAST
#define BN_DIV_63_BOXED_FAST 1
#endif
#ifndef BN_DIV_POSITIVE_2N_N_BOXED_FAST
#define BN_DIV_POSITIVE_2N_N_BOXED_FAST 1
#endif

static inline __attribute__((always_inline))
WValue bigint_div_any_inline(WValue a, WValue b) {
#if BN_DIV_BY_LIMB_BOXED_FAST || (BN_DIVMOD_42 && BN_DIVMOD_42_BOXED_FAST) || \
    (BN_DIV_TRIANGULAR_Q_CERTIFIED && BN_DIV_63_DIRECT && \
     BN_DIV_63_BOXED_FAST) || BN_DIV_84_DIRECT || \
    BN_DIV_POSITIVE_2N_N_BOXED_FAST
    if (w_is_bigint(a) && w_is_bigint(b)) {
        int32_t as, bs;
        WBigint *aa = w_bigint_view(a, &as);
        WBigint *bb = w_bigint_view(b, &bs);
#if BN_DIV_BY_LIMB_BOXED_FAST
        /* N-limb by one-limb quotient (subsumes the old 2/1 arm): one
         * backward pass of the reciprocal-by-word kernel.  Truncated
         * division: quotient is negative iff the effective signs differ;
         * the magnitude kernel already truncates toward zero. */
        if (bs == 1 || bs == -1) {
            int neg = (as < 0) != (bs < 0);
            int32_t alen = as < 0 ? -as : as;
            uint64_t d = bb->limbs[0];
            if (alen == 0) return w_box_int(0);
            if (alen == 1) {
                /* Normalized divisor (bit 63 set) has quotient in {0, 1};
                 * otherwise fall back to one hardware divide. */
                if ((int64_t)d < 0) {
                    return w_box_int(aa->limbs[0] >= d ? (neg ? -1 : 1) : 0);
                }
                if (__builtin_expect(d == 0, 0)) die_as("ZeroDivisionError", "division by zero");
                return bigint_finish_one_limb(aa->limbs[0] / d, neg);
            }
            uint64_t remainder;
            WBigint *q;
#if BN_DIV1_SMALL_NORMALIZED
            if (alen <= 4 && (d >> 63) != 0)
                q = mag_div_single_small_normalized(aa->limbs, alen, d);
            else
#endif
                q = mag_div_single(aa->limbs, alen, d, &remainder);
            if (neg) q->size = -q->size;
            return bigint_finish_div1(q);
        }
#endif
#if BN_DIVMOD_42 && BN_DIVMOD_42_BOXED_FAST
        if (as == 4 && bs == 2)
            return bigint_finish_mag_sub(
                mag_div_42(aa->limbs, bb->limbs));
#endif
#if BN_DIV_TRIANGULAR_Q_CERTIFIED && BN_DIV_TRIANGULAR_Q_SELECT && \
    BN_DIV_63_DIRECT && BN_DIV_63_BOXED_FAST
        if (as == 6 && bs == 3) {
            WBigint *q =
                mag_div_q_63_certified(aa->limbs, bb->limbs);
            if (q) return bigint_finish_mag_sub(q);
        }
#endif
#if BN_DIV_84_DIRECT
        /* Positive 8/4: the straight-line kernel ahead of the balanced
         * arm's triangular certificate (whose rare inconclusive result
         * would re-divide from scratch). */
        if (as == 8 && bs == 4)
            return bigint_finish_mag_sub(
                mag_div_84(aa->limbs, bb->limbs, NULL));
#endif
#if BN_DIV_POSITIVE_2N_N_BOXED_FAST
        /*
         * Balanced positive division is the dominant public bignum shape.
         * Its boxed operands already expose the unsigned limb arrays and
         * exact lengths, so avoid rebuilding that information in the generic
         * signed/type-polymorphic entry before dispatching the same magnitude
         * kernel.
         */
        if (bs >= 4 && as > 0 &&
            (as & 1) == 0 && bs == as / 2) {
            WBigint *q;
#if BN_DIV_TRIANGULAR_Q_CERTIFIED && BN_DIV_TRIANGULAR_Q_SELECT
            /*
             * Below the cached-reciprocal crossover, quotient-only 2n/n
             * division goes straight to the triangular certificate.  Keeping
             * that sizeable kernel out of line also prevents mag_divmod's
             * ordinary dispatcher from inheriting its large fixed stack
             * frame.  A rare inconclusive certificate falls back to the full
             * dispatcher unchanged.
             */
            if (bs < BN_DIV_RECIP_Q_MIN) {
                q = mag_div_q_triangular_certified(
                    aa->limbs, as, bb->limbs, bs);
                if (q) return bigint_finish_mag_sub(q);
            }
#endif
            mag_divmod(
                aa->limbs, as, bb->limbs, bs, &q, NULL);
            return bigint_finish_mag_sub(q);
        }
#endif
    }
#endif
#if BN_ALGEBRAIC_IDENTITY_FAST
    /* Check identities after the shaped boxed/boxed routes, keeping their
     * ordinary 2n/n benchmark path byte-for-byte free of extra branches. */
    if (b == w_box_int(1)) return w_bigint_mark_shared_value(a);
    if (b == w_box_int(-1)) return w_neg(a);
    /* A normalized heap BigInt is nonzero, so this preserves 0 / 0 raising. */
    if (a == b && w_is_bigint(a)) return w_box_int(1);
#endif
    return bigint_div_any_generic(a, b);
}

W_RT_INTERNAL WValue bigint_div_any(WValue a, WValue b) {
    return bigint_div_any_inline(a, b);
}

/* Unsigned-word quotient entry: the divisor is already decoded and hoisted,
 * so only the dividend's sign/length remains. */
static inline __attribute__((always_inline))
WValue bigint_div_ui_any(WValue a, uint64_t divisor) {
    if (__builtin_expect(divisor == 0, 0)) die_as("ZeroDivisionError", "division by zero");
    if (divisor == 1) {
        if (w_is_bigint(a)) w_bigint_mark_shared(w_as_bigint(a));
        return a;
    }
    uint64_t scratch;
    int32_t alen;
    const uint64_t *al = integer_limbs(a, &scratch, &alen);
    int negative = alen < 0;
    int32_t n = negative ? -alen : alen;
    if (n == 0) return w_box_int(0);
    if (n == 1) {
        if ((int64_t)divisor < 0)
            return w_box_int(al[0] >= divisor ? (negative ? -1 : 1) : 0);
        return bigint_finish_one_limb(al[0] / divisor, negative);
    }
    uint64_t remainder;
    WBigint *q;
#if BN_DIV1_SMALL_NORMALIZED
    if (n <= 4 && (divisor >> 63) != 0)
        q = mag_div_single_small_normalized(al, n, divisor);
    else
#endif
        q = mag_div_single(al, n, divisor, &remainder);
    if (negative) q->size = -q->size;
    return bigint_finish_div1(q);
}

static inline __attribute__((always_inline))
WValue bigint_mod_ui_any(WValue a, uint64_t divisor) {
    if (__builtin_expect(divisor == 0, 0)) die("modulo by zero");
    if (divisor == 1) return w_box_int(0);
    if (__builtin_expect((a >> 47) == (W_TAG_BIGINT >> 47), 1)) {
        WBigint *ba = w_as_bigint(a);
        int32_t n = ba->size;
        if (n == 1) {
            uint64_t v = ba->limbs[0];
            uint64_t rem = ((int64_t)divisor < 0) ? (v >= divisor ? v - divisor : v) : (v % divisor);
            return bigint_finish_one_limb(rem, 0);
        }
        if (n >= 2) {
#if BN_DIV1_SMALL_NORMALIZED
            if (n <= 4 && (divisor >> 63) != 0) {
                uint64_t dinv = bn_div_preinv_cached(divisor, bn_div_preinv_thread_cache());
                int32_t top = n - 1;
                uint64_t high = ba->limbs[top];
                uint64_t rem = high - (divisor & (0 - (uint64_t)(high >= divisor)));
                if (n == 4) (void)bn_div_qr_preinv(rem, ba->limbs[2], divisor, dinv, &rem);
                if (n >= 3) (void)bn_div_qr_preinv(rem, ba->limbs[1], divisor, dinv, &rem);
                (void)bn_div_qr_preinv(rem, ba->limbs[0], divisor, dinv, &rem);
                return bigint_finish_one_limb(rem, 0);
            }
#endif
            return bigint_finish_one_limb(mag_mod_single(ba->limbs, n, divisor), 0);
        }
    }
    uint64_t scratch;
    int32_t alen;
    const uint64_t *al = integer_limbs(a, &scratch, &alen);
    int negative = alen < 0;
    int32_t n = negative ? -alen : alen;
    if (n == 0) return w_box_int(0);
    if (n == 1) {
        uint64_t v = al[0];
        uint64_t rem = ((int64_t)divisor < 0) ? (v >= divisor ? v - divisor : v) : (v % divisor);
        return bigint_finish_one_limb(rem, negative);
    }
    return bigint_finish_one_limb(mag_mod_single(al, n, divisor), negative);
}

static inline __attribute__((always_inline))
WValue bigint_mod_any_inline(WValue a, WValue b) {
#if BN_DIV_BY_LIMB_BOXED_FAST || (BN_DIVMOD_42 && BN_DIVMOD_42_BOXED_FAST) || \
    BN_MOD_63_DIRECT || BN_DIV_POSITIVE_2N_N_BOXED_FAST
    if (w_is_bigint(a) && w_is_bigint(b)) {
        int32_t as, bs;
        WBigint *aa = w_bigint_view(a, &as);
        WBigint *bb = w_bigint_view(b, &bs);
#if BN_DIV_BY_LIMB_BOXED_FAST
        /* Sibling of bigint_div_any's by-limb arm: the same backward pass
         * yields the one-limb remainder, which takes the dividend's
         * effective sign (truncated division). */
        if (bs == 1 || bs == -1) {
            int32_t alen = as < 0 ? -as : as;
            uint64_t d = bb->limbs[0];
            if (alen == 0) return w_box_int(0);
            if (alen == 1) {
                uint64_t v = aa->limbs[0];
                if ((int64_t)d < 0) {
                    return bigint_finish_one_limb(v >= d ? v - d : v, as < 0);
                }
                if (__builtin_expect(d == 0, 0)) die("modulo by zero");
                return bigint_finish_one_limb(v % d, as < 0);
            }
#if BN_DIV1_SMALL_NORMALIZED
            if (alen <= 4 && (d >> 63) != 0) {
                uint64_t dinv = bn_div_preinv_cached(d, bn_div_preinv_thread_cache());
                int32_t top = alen - 1;
                uint64_t high = aa->limbs[top];
                uint64_t rem = high - (d & (0 - (uint64_t)(high >= d)));
                if (alen == 4) (void)bn_div_qr_preinv(rem, aa->limbs[2], d, dinv, &rem);
                if (alen >= 3) (void)bn_div_qr_preinv(rem, aa->limbs[1], d, dinv, &rem);
                (void)bn_div_qr_preinv(rem, aa->limbs[0], d, dinv, &rem);
                return bigint_finish_one_limb(rem, as < 0);
            }
#endif
            return bigint_finish_one_limb(
                mag_mod_single(aa->limbs, alen, d), as < 0);
        }
#endif
#if BN_DIVMOD_42 && BN_DIVMOD_42_BOXED_FAST
        if (as == 4 && bs == 2)
            return bigint_finish_mag_sub(
                mag_mod_42(aa->limbs, bb->limbs));
#endif
#if BN_MOD_63_DIRECT
        if (as == 6 && bs == 3)
            return bigint_finish_mag_sub(
                mag_mod_63(aa->limbs, bb->limbs));
#endif
#if BN_DIV_POSITIVE_2N_N_BOXED_FAST
        /*
         * Mirror of bigint_div_any's balanced positive fast path: the boxed
         * operands already expose the unsigned limb arrays and exact
         * lengths, so skip the noinline generic entry and its duplicate
         * integer_limbs walk before dispatching the same magnitude kernel.
         */
        if (bs >= 4 && as > 0 &&
            (as & 1) == 0 && bs == as / 2) {
            WBigint *r;
            mag_divmod(
                aa->limbs, as, bb->limbs, bs, NULL, &r);
            return bigint_finish_mag_sub(r);
        }
#endif
#if BN_ALGEBRAIC_IDENTITY_FAST
        /* |a| < |b| (effective magnitudes): truncated division has a zero
         * quotient, so the remainder IS a — sign included. The generic
         * path would alloc-and-copy a's limbs (mag_divmod_knuth's
         * short-dividend arm); alias the operand instead. One shared-count
         * byte store replaces the copy. Checked after the shaped kernels
         * so their hot lanes stay branch-free. */
        {
            int32_t an = as < 0 ? -as : as;
            int32_t bn = bs < 0 ? -bs : bs;
            if (an < bn ||
                (an == bn &&
                 mag_cmp(aa->limbs, an, bb->limbs, bn) < 0)) {
                w_bigint_mark_shared(aa);
                return a;
            }
        }
#endif
    }
#endif
#if BN_ALGEBRAIC_IDENTITY_FAST
    if (b == w_box_int(1) || b == w_box_int(-1)) return w_box_int(0);
    /* A normalized heap BigInt is nonzero, so this preserves 0 % 0 raising. */
    if (a == b && w_is_bigint(a)) return w_box_int(0);
    /* Inline % heap-BigInt with |a| < |b|: the remainder is a itself — an
     * inline value copy, no aliasing or marking needed. Multi-limb b always
     * exceeds the i48 range; a normalized one-limb b can still sit just
     * above it, so compare the limb. */
    if (w_is_int(a) && w_is_bigint(b)) {
        int32_t bs;
        WBigint *bb = w_bigint_view(b, &bs);
        int64_t av = w_as_int(a);
        uint64_t am = av < 0 ? (uint64_t)(-av) : (uint64_t)av;
        if (bs > 1 || bs < -1 || bb->limbs[0] > am) return a;
    }
#endif
    return bigint_mod_any_generic(a, b);
}

W_RT_INTERNAL WValue bigint_mod_any(WValue a, WValue b) {
    return bigint_mod_any_inline(a, b);
}

/* ---- Integer square root: divide-and-conquer sqrtrem ------------------
 *
 * Zimmermann's "Karatsuba square root" (INRIA RR-3805): normalize so the
 * operand spans an even number of limbs with its top limb >= 2^62 (an even
 * bit shift keeps the root exact: isqrt(a*4^k) = isqrt(a)*2^k), then split
 * a = a3*B^(2h) rest and recurse:
 *
 *   s', r' = sqrtrem(high 2h limbs)
 *   q , u  = divmod(r'*B^l + a1, 2s')      (divide by s', halve the quotient)
 *   s      = s'*B^l + q
 *   r      = u*B^l + a0 - q^2              (fix-up: s -= 1; r += 2s+1)
 *
 * The division and the q^2 product ride the existing subquadratic
 * mag_divmod / bigint_sqr_dispatch engines, so the whole root costs a small
 * constant times one full-size division. Int#isqrt only keeps the root, but
 * the recursion needs remainders internally, so sqrtrem is the worker. */

/* floor sqrt + remainder of one normalized limb (hi >= 2^62): hardware
 * double sqrt seed (error well under one ulp of the 32-bit root), exact
 * integer fixup.  The root has bit 31 set. */
static inline uint64_t bn_sqrtrem1(uint64_t hi, uint64_t *rp) {
    uint64_t s = (uint64_t)__builtin_sqrt((double)hi);
    if (s > 0xFFFFFFFFULL) s = 0xFFFFFFFFULL;
    uint64_t r = hi - s * s;
    while ((int64_t)r < 0) { r += 2 * s - 1; s--; }        /* <= 1 pass */
    while (r > 2 * s) { r -= 2 * s + 1; s++; }             /* <= 1 pass */
    *rp = r;
    return s;
}

/* sqrtrem base case: {np, 2} with np[1] >= 2^62. Root (top bit set) in
 * sp[0], remainder low limb in np[0]; returns its B^1 limb (rem <= 2s).
 * Uses a 32-bit root of the top limb, one 64/64 integer
 * divide to extend it, exact 128-bit fixup (no fdiv anywhere). */
static uint64_t bn_sqrtrem2(uint64_t *sp, uint64_t *np) {
    uint64_t hi = np[1], lo = np[0];
    uint64_t r1;
    uint64_t s1 = bn_sqrtrem1(hi, &r1);           /* 2^31 <= s1 < 2^32 */
    /* Next 32 root bits: q = floor((r1:lo) / (2 s1)) approximated on the
     * top bits (r1 <= 2 s1 < 2^33, so the shift cannot overflow). */
    uint64_t num = (r1 << 31) | (lo >> 33);
    uint64_t q = num / s1;
    if (q >> 32) q = 0xFFFFFFFFULL;
    uint64_t s = (s1 << 32) | q;
    unsigned __int128 a = ((unsigned __int128)hi << 64) | lo;
    unsigned __int128 rem = a - (unsigned __int128)s * s;
    /* |error| <= 3: each pass moves the root by one. */
    while ((__int128)rem < 0) {
        rem += 2 * (unsigned __int128)s - 1;
        s--;
    }
    while (rem > 2 * (unsigned __int128)s) {
        rem -= 2 * (unsigned __int128)s + 1;
        s++;
    }
    sp[0] = s;
    np[0] = (uint64_t)rem;
    return (uint64_t)(rem >> 64);
}

/* Exact floor sqrt of a 128-bit value (any normalization). */
static uint64_t bn_isqrt_u128(unsigned __int128 a) {
    uint64_t hi = (uint64_t)(a >> 64);
    if (hi == 0) {
        uint64_t v = (uint64_t)a;
        if (v == 0) return 0;
        uint64_t s = (uint64_t)__builtin_sqrt((double)v);
        if (s > 0xFFFFFFFFULL) s = 0xFFFFFFFFULL;
        while (s * s > v) s--;
        while (v - s * s > 2 * s) s++;
        return s;
    }
    int sh = __builtin_clzll(hi) & ~1;
    unsigned __int128 an = a << sh;
    uint64_t nl[2] = { (uint64_t)an, (uint64_t)(an >> 64) };
    uint64_t sr;
    (void)bn_sqrtrem2(&sr, nl);
    return sr >> (sh >> 1);
}

static inline uint64_t bn_sqrt_sub_1(uint64_t *p, int32_t n, uint64_t v) {
    for (int32_t i = 0; i < n && v; i++) {
        uint64_t old = p[i];
        p[i] = old - v;
        v = old < v;
    }
    return v;
}

static inline uint64_t bn_sqrt_add_1(uint64_t *p, int32_t n, uint64_t v) {
    for (int32_t i = 0; i < n && v; i++) {
        uint64_t old = p[i];
        p[i] = old + v;
        v = p[i] < old;
    }
    return v;
}

/* Divide {up, l+h} by the bit-63-normalized divisor {vp, h}: quotient into
 * qp[0..l) (returns its carry limb, <= 2), remainder into up[0..h). The
 * dividend may carry high zero limbs (the recursive remainder can be tiny).
 * h <= 2 runs allocation-free on the reciprocal step primitives; below
 * BN_SQRT_DIVREM_KNUTH_MAX the divide runs allocation-free raw Knuth;
 * larger h rides mag_divmod. */
#ifndef BN_SQRT_DIVREM_KNUTH_MAX
#define BN_SQRT_DIVREM_KNUTH_MAX 64
#endif
static uint64_t bn_sqrt_divrem(uint64_t *up, int32_t l, int32_t h,
                               const uint64_t *vp, uint64_t *qp) {
    if (h == 1) {
        uint64_t d = vp[0];
        uint64_t dinv = bn_invert_limb(d);
        uint64_t r = up[l];
        uint64_t carry = 0;
        if (r >= d) { carry = 1; r -= d; }      /* B/d <= 2: one step */
        for (int32_t i = l - 1; i >= 0; i--)
            qp[i] = bn_div_qr_preinv(r, up[i], d, dinv, &r);
        up[0] = r;
        return carry;
    }
    if (h == 2) {
        uint64_t d1 = vp[1], d0 = vp[0];
        uint64_t dinv = bn_invert_pi1(d1, d0);
        uint64_t r1 = up[l + 1], r0 = up[l];
        uint64_t carry = 0;
        if (r1 > d1 || (r1 == d1 && r0 >= d0)) {
            uint64_t borrow = r0 < d0;
            r0 -= d0;
            r1 -= d1 + borrow;
            carry = 1;
        }
        for (int32_t i = l - 1; i >= 0; i--)
            qp[i] = bn_udiv_qr_3by2(r1, r0, up[i], d1, d0, dinv, &r1, &r0);
        up[0] = r0;
        up[1] = r1;
        return carry;
    }
    if (h == 3) {
        uint64_t d2 = vp[2], d1 = vp[1], d0 = vp[0];
        uint64_t dinv = bn_invert_pi1(d2, d1);
        uint64_t r2 = up[l + 2], r1 = up[l + 1], r0 = up[l];
        uint64_t carry = 0;
        if (r2 > d2 || (r2 == d2 && (r1 > d1 || (r1 == d1 && r0 >= d0)))) {
            uint64_t bw0 = r0 < d0;
            r0 -= d0;
            uint64_t sub1 = d1 + bw0;
            uint64_t bw1 = (sub1 < d1) | (r1 < sub1);
            r1 -= sub1;
            r2 -= d2 + bw1;
            carry = 1;
        }
        for (int32_t i = l - 1; i >= 0; i--) {
            uint64_t u0 = up[i];
            uint64_t qhat;
            if (__builtin_expect(r2 == d2 && r1 >= d1, 0)) {
                qhat = UINT64_MAX;
                uint64_t un[4] = { u0, r0, r1, r2 };
                uint64_t bw = bn_submul_1(un, vp, 3, qhat);
                if (un[3] < bw) {
                    qhat--;
                    (void)bn_add_n(un, un, vp, 3);
                }
                r0 = un[0]; r1 = un[1]; r2 = un[2];
            } else {
                qhat = bn_udiv_qr_3by2(r2, r1, r0, d2, d1, dinv, &r1, &r0);
                unsigned __int128 p = (unsigned __int128)qhat * d0;
                uint64_t p_lo = (uint64_t)p;
                uint64_t p_hi = (uint64_t)(p >> 64);
                uint64_t bw0 = u0 < p_lo;
                uint64_t n0 = u0 - p_lo;
                uint64_t sub1 = p_hi + bw0;
                uint64_t bw1 = (sub1 < p_hi) | (r0 < sub1);
                uint64_t n1 = r0 - sub1;
                uint64_t bw2 = r1 < bw1;
                uint64_t n2 = r1 - bw1;
                if (__builtin_expect(bw2 != 0, 0)) {
                    qhat--;
                    unsigned __int128 s0 = (unsigned __int128)n0 + d0;
                    n0 = (uint64_t)s0;
                    unsigned __int128 s1 =
                        (unsigned __int128)n1 + d1 + (uint64_t)(s0 >> 64);
                    n1 = (uint64_t)s1;
                    n2 += d2 + (uint64_t)(s1 >> 64);
                }
                r0 = n0; r1 = n1; r2 = n2;
            }
            qp[i] = qhat;
        }
        up[0] = r0;
        up[1] = r1;
        up[2] = r2;
        return carry;
    }
    int32_t ulen = l + h;
    while (ulen > 0 && up[ulen - 1] == 0) ulen--;
    if (ulen < h || (ulen == h && mag_cmp(up, ulen, vp, h) < 0)) {
        memset(qp, 0, (size_t)l * sizeof(uint64_t));
        return 0;          /* quotient 0; dividend == remainder, in place */
    }
    if (h < BN_SQRT_DIVREM_KNUTH_MAX) {
        /* Allocation-free Knuth straight into the caller's buffers (the
         * divisor is already normalized, and l + h <= 2h - 1 keeps the leaf
         * on its stack arena).  Pre-fold the top block below the divisor
         * so the quotient fits l limbs exactly (r' <= 2s': one pass). */
        uint64_t carry = 0;
        while (ulen == l + h &&
               mag_cmp(up + l, bz_trim(up + l, h), vp, h) >= 0) {
            (void)bn_sub_n(up + l, up + l, vp, h);
            carry++;                            /* r' <= 2s': <= 2 passes */
            while (ulen > 0 && up[ulen - 1] == 0) ulen--;
        }
        uint64_t rbuf[BN_SQRT_DIVREM_KNUTH_MAX];
        /* r must not alias the dividend: the leaf
         * zeroes its r buffer before reading u */
        bz_base_div_into(up, ulen, vp, h, qp, l, rbuf, h, 1);
        memcpy(up, rbuf, (size_t)h * sizeof(uint64_t));
        return carry;
    }
    if (l == h && !(h & 1) && h < BN_DIV_RECIP_R_MIN) {
        /* Balanced even 2h/h shape below the cached-reciprocal band: the
         * divisor is already bit-63-normalized, so run the B-Z engine in
         * place -- quotient straight into qp, remainder straight into up --
         * skipping mag_divmod's dispatch, workspace copies, and two result
         * allocations per recursion level.  Even h > BZ_THRESHOLD keeps
         * bz_d2n1n off its Knuth base at the top, whose r-buffer zeroing
         * would otherwise clobber the aliased dividend; the recursive path
         * consumes a's low half into scratch before r is written.  Pre-fold
         * as the raw-Knuth band does so a < s' * B^h. */
        uint64_t *sc = h > BZ_THRESHOLD
            ? bz_ws_get((size_t)(12 * h + 64))
            : NULL;
        if (sc) {
            uint64_t carry = 0;
            while (ulen == l + h &&
                   mag_cmp(up + l, bz_trim(up + l, h), vp, h) >= 0) {
                (void)bn_sub_n(up + l, up + l, vp, h);
                carry++;                        /* r' <= 2s': <= 2 passes */
                while (ulen > 0 && up[ulen - 1] == 0) ulen--;
            }
            bn_toom_no_spin++;
            bz_d2n1n(up, vp, h, qp, up, sc);
            bn_toom_no_spin--;
            return carry;
        }
    }
    WBigint *q, *r;
    mag_divmod(up, ulen, vp, h, &q, &r);
    int32_t rlen = r->size;
    memcpy(up, r->limbs, (size_t)rlen * sizeof(uint64_t));
    memset(up + rlen, 0, (size_t)(h - rlen) * sizeof(uint64_t));
    bigint_release(r);
    int32_t qlen = q->size;
    uint64_t carry = qlen > l ? q->limbs[l] : 0;
    if (qlen > l) qlen = l;
    memcpy(qp, q->limbs, (size_t)qlen * sizeof(uint64_t));
    memset(qp + qlen, 0, (size_t)(l - qlen) * sizeof(uint64_t));
    bigint_release(q);
    return carry;
}

#ifndef BN_SQRTREM_POW2_HIGH_SPLIT
#  if defined(__aarch64__)
#    define BN_SQRTREM_POW2_HIGH_SPLIT 1
#  else
#    define BN_SQRTREM_POW2_HIGH_SPLIT 0
#  endif
#endif
#ifndef BN_SQRTREM_POW2_HIGH_MIN
#define BN_SQRTREM_POW2_HIGH_MIN 1025
#endif

/* In-place divide-and-conquer sqrtrem: np holds 2n limbs with
 * np[2n-1] >= 2^62. On return sp[0..n) is floor(sqrt) (top bit set),
 * np[0..n) the remainder's low limbs, and the returned carry (0 or 1) its
 * B^n limb (rem <= 2s < 2*B^n). np[n..2n) is consumed as scratch. */
static uint64_t bn_dc_sqrtrem(uint64_t *np, uint64_t *sp, int32_t n) {
    if (n == 1) return bn_sqrtrem2(sp, np);
    int32_t l = n >> 1, h = n - l;              /* 1 <= l <= h */
#if BN_SQRTREM_POW2_HIGH_SPLIT
    /* At 2^k+1, a balanced split sends the entire expensive recurrence
     * through another odd width.  Extend a 2^k-limb high root by one limb
     * instead: the recurrence permits any l <= h, and the final division
     * then has only one quotient limb. */
    if (n >= BN_SQRTREM_POW2_HIGH_MIN &&
        ((uint32_t)(n - 1) & (uint32_t)(n - 2)) == 0) {
        l = 1;
        h = n - 1;
    }
#endif
    /* Root of the high 2h limbs (a prefix, so it stays normalized). */
    uint64_t q = bn_dc_sqrtrem(np + 2 * l, sp + l, h);
    /* r' = q*B^h + {np+2l, h} <= 2s'. Fold a set carry as r' - s' (exact:
     * r' >= B^h > s' forces r' - s' < B^h since r' <= 2s'), which pre-adds
     * B^l to the quotient below. */
    if (q) (void)bn_sub_n(np + 2 * l, np + 2 * l, sp + l, h);
    /* Q = floor((r'*B^l + a1) / s'), u = that remainder (at np+l). */
    q += bn_sqrt_divrem(np + l, l, h, sp + l, sp);
    /* The step really divides by 2s': halve Q, returning the dropped bit
     * times s' to u. Afterwards q-hat = q*B^l + {sp,l}; q == 1 forces
     * {sp,l} == 0 (Q <= 2*B^l with equality exactly when q ends up set). */
    uint64_t c0 = sp[0] & 1;
    for (int32_t i = 0; i + 1 < l; i++)
        sp[i] = (sp[i] >> 1) | (sp[i + 1] << 63);
    sp[l - 1] = (sp[l - 1] >> 1) | (q << 63);
    q >>= 1;
    int64_t cc = 0;
    if (c0) cc = (int64_t)bn_add_n(np + l, np + l, sp + l, h);
    /* r = u*B^l + a0 - q-hat^2 (a0 = {np, l}, untouched so far). */
    if (q) {
        /* q-hat = B^l exactly: q-hat^2 = B^2l. */
        if (2 * l == n) cc -= 1;
        else cc -= (int64_t)bn_sqrt_sub_1(np + 2 * l, n - 2 * l, 1);
        /* The candidate root (s'+1) B^l always overshoots: Q reaches 2 B^l
         * only for r' = 2 s', i.e. the high 2h limbs are (s'+1)^2 - 1, and
         * the low limbs keep the operand below (s'+1)^2 B^2l.  Step down to
         * s' B^l + (B^l - 1) -- the high h limbs of the root stay s' -- with
         * r += 2 (s'+1) B^l - 1, which is nonnegative (2 s' B^l >= B^2l) and
         * below 2 root + 1, so no further correction follows. */
        for (int32_t i = 0; i < l; i++) sp[i] = UINT64_MAX;
        cc += (int64_t)bn_add_n(np + l, np + l, sp + l, h);
        cc += (int64_t)bn_add_n(np + l, np + l, sp + l, h);
        cc += (int64_t)bn_sqrt_add_1(np + l, h, 2);
        cc -= (int64_t)bn_sqrt_sub_1(np, n, 1);
    } else {
        uint64_t *sq = np + n;                  /* dead upper half */
        if (l == 1) {
            unsigned __int128 p = (unsigned __int128)sp[0] * sp[0];
            sq[0] = (uint64_t)p;
            sq[1] = (uint64_t)(p >> 64);
        } else {
            bigint_sqr_dispatch(sq, sp, l);
        }
        uint64_t borrow = bn_sub_n(np, np, sq, 2 * l);
        if (2 * l == n) cc -= (int64_t)borrow;
        else cc -= (int64_t)bn_sqrt_sub_1(np + 2 * l, n - 2 * l, borrow);
    }
    while (cc < 0) {                            /* at most one pass */
        (void)bn_sqrt_sub_1(sp, n, 1);
        cc += (int64_t)bn_add_n(np, np, sp, n);
        cc += (int64_t)bn_add_n(np, np, sp, n);
        cc += (int64_t)bn_sqrt_add_1(np, n, 1);
    }
    return (uint64_t)cc;
}

/* Quotient-only guarded divide for the root-only top level: {up, l1 + h} /
 * {vp, h} (vp bit-63-normalized), quotient into qp[0..l1) plus a returned
 * carry limb.  Unlike bn_sqrt_divrem this never writes the dividend (the
 * uncertified fallback re-reads it) and never materializes a remainder —
 * mag_divmod's quotient-only path is 15-35% cheaper than divrem at the
 * sizes the sqrt recursion feeds it. */
#ifndef BN_SQRT_DIVQ_63_DIRECT
#define BN_SQRT_DIVQ_63_DIRECT 1
#endif

static uint64_t bn_sqrt_divq_guard(const uint64_t *up, int32_t l1, int32_t h,
                                   const uint64_t *vp, uint64_t *qp) {
    if (h == 1) {
        uint64_t d = vp[0];
        uint64_t dinv = bn_invert_limb(d);
        uint64_t r = up[l1];
        uint64_t carry = 0;
        if (r >= d) { carry = 1; r -= d; }      /* B/d <= 2: one step */
        for (int32_t i = l1 - 1; i >= 0; i--)
            qp[i] = bn_div_qr_preinv(r, up[i], d, dinv, &r);
        return carry;
    }
    if (h == 2) {
        uint64_t d1 = vp[1], d0 = vp[0];
        uint64_t dinv = bn_invert_pi1(d1, d0);
        uint64_t r1 = up[l1 + 1], r0 = up[l1];
        uint64_t carry = 0;
        if (r1 > d1 || (r1 == d1 && r0 >= d0)) {
            uint64_t borrow = r0 < d0;
            r0 -= d0;
            r1 -= d1 + borrow;
            carry = 1;
        }
        for (int32_t i = l1 - 1; i >= 0; i--)
            qp[i] = bn_udiv_qr_3by2(r1, r0, up[i], d1, d0, dinv, &r1, &r0);
        return carry;
    }
    if (h == 3) {
        uint64_t d2 = vp[2], d1 = vp[1], d0 = vp[0];
        uint64_t dinv = bn_invert_pi1(d2, d1);
        uint64_t r2 = up[l1 + 2], r1 = up[l1 + 1], r0 = up[l1];
        uint64_t carry = 0;
        if (r2 > d2 || (r2 == d2 && (r1 > d1 || (r1 == d1 && r0 >= d0)))) {
            uint64_t bw0 = r0 < d0;
            r0 -= d0;
            uint64_t sub1 = d1 + bw0;
            uint64_t bw1 = (sub1 < d1) | (r1 < sub1);
            r1 -= sub1;
            r2 -= d2 + bw1;
            carry = 1;
        }
        for (int32_t i = l1 - 1; i >= 0; i--) {
            uint64_t u0 = up[i];
            uint64_t qhat;
            if (__builtin_expect(r2 == d2 && r1 >= d1, 0)) {
                qhat = UINT64_MAX;
                uint64_t un[4] = { u0, r0, r1, r2 };
                uint64_t bw = bn_submul_1(un, vp, 3, qhat);
                if (un[3] < bw) {
                    qhat--;
                    (void)bn_add_n(un, un, vp, 3);
                }
                r0 = un[0]; r1 = un[1]; r2 = un[2];
            } else {
                qhat = bn_udiv_qr_3by2(r2, r1, r0, d2, d1, dinv, &r1, &r0);
                unsigned __int128 p = (unsigned __int128)qhat * d0;
                uint64_t p_lo = (uint64_t)p;
                uint64_t p_hi = (uint64_t)(p >> 64);
                uint64_t bw0 = u0 < p_lo;
                uint64_t n0 = u0 - p_lo;
                uint64_t sub1 = p_hi + bw0;
                uint64_t bw1 = (sub1 < p_hi) | (r0 < sub1);
                uint64_t n1 = r0 - sub1;
                uint64_t bw2 = r1 < bw1;
                uint64_t n2 = r1 - bw1;
                if (__builtin_expect(bw2 != 0, 0)) {
                    qhat--;
                    unsigned __int128 s0 = (unsigned __int128)n0 + d0;
                    n0 = (uint64_t)s0;
                    unsigned __int128 s1 =
                        (unsigned __int128)n1 + d1 + (uint64_t)(s0 >> 64);
                    n1 = (uint64_t)s1;
                    n2 += d2 + (uint64_t)(s1 >> 64);
                }
                r0 = n0; r1 = n1; r2 = n2;
            }
            qp[i] = qhat;
        }
        return carry;
    }
    int32_t ulen = l1 + h;
    while (ulen > 0 && up[ulen - 1] == 0) ulen--;
    if (ulen < h || (ulen == h && mag_cmp(up, ulen, vp, h) < 0)) {
        memset(qp, 0, (size_t)l1 * sizeof(uint64_t));
        return 0;
    }
    /* Prefer the triangular quotient-only engine outright: the dispatch
     * would try the cached-reciprocal path first, whose full 2n-by-(n+2)
     * product costs ~2 M(n) sequentially and thrashes the parallel-Toom
     * pool awake when run in the sqrt call pattern. */
    WBigint *q;
#if BN_SQRT_DIVQ_63_DIRECT && BN_DIV_63_DIRECT
    /* The root-only n=4 step presents exactly the certified 6/3 shape.
     * Use its straight-line quotient leaf instead of rediscovering the same
     * four digits through the variable-width triangular loop. */
    if (ulen == 6 && h == 3)
        q = mag_div_q_63_certified(up, vp);
    else
#endif
        q = ulen == 2 * h
            ? mag_div_q_triangular_certified(up, ulen, vp, h)
            : NULL;
    if (!q) {
        int sequential = h < BN_DIV_RECIP_PAR_MIN;
        if (sequential) bn_toom_parallel_depth++;
        mag_divmod(up, ulen, vp, h, &q, NULL);
        if (sequential) bn_toom_parallel_depth--;
    }
    int32_t qlen = q->size;
    uint64_t carry = qlen > l1 ? q->limbs[l1] : 0;
    if (qlen > l1) qlen = l1;
    memcpy(qp, q->limbs, (size_t)qlen * sizeof(uint64_t));
    memset(qp + qlen, 0, (size_t)(l1 - qlen) * sizeof(uint64_t));
    bigint_release(q);
    return carry;
}

/* The quotient-only B-Z spine crosses over independently in the sqrt call
 * shape: the root feeds a normalized, balanced 2n/n divide and needs only two
 * guard limbs for its certificate.  Keep this separate from the general
 * quotient-only cutoff.  The AArch64 sweep selected 193: lower cutoffs made
 * 128-256-limb inputs slower, while the old effective cutoff of 385 exposed a
 * repeatable branch-footprint cliff at 512 limbs.  Other targets retain the
 * old policy until they have their own sweep. */
#ifndef BN_SQRT_DIVAPPR_MIN
#  if defined(__aarch64__)
#    define BN_SQRT_DIVAPPR_MIN 193
#  else
#    define BN_SQRT_DIVAPPR_MIN 385
#  endif
#endif
#ifndef BN_SQRT_DIVAPPR_EXPECT
#define BN_SQRT_DIVAPPR_EXPECT 0
#endif
#ifndef BN_SQRT_DIVAPPR_PAD_LIMBS
#define BN_SQRT_DIVAPPR_PAD_LIMBS 0
#endif
#if BN_SQRT_DIVAPPR_PAD_LIMBS && \
    (BN_SQRT_DIVAPPR_PAD_LIMBS & (BN_SQRT_DIVAPPR_PAD_LIMBS - 1))
#error "BN_SQRT_DIVAPPR_PAD_LIMBS must be zero or a power of two"
#endif

static inline int32_t bn_sqrt_divappr_pad_limbs(int32_t n) {
#if BN_SQRT_DIVAPPR_PAD_LIMBS
    (void)n;
    return BN_SQRT_DIVAPPR_PAD_LIMBS;
#elif defined(__aarch64__)
    /* Larger alignment trades a small amount of zero padding for additional
     * even B-Z splits before the quadratic odd leaf.  The AArch64 crossover
     * sweep favors progressively smoother widths through the measured
     * 65,536-limb root band. */
    if (n >= 32768) return 256;
    if (n >= 16384) return 128;
    if (n >= 8192) return 64;
    if (n >= 4095) return 32;
    if (n >= 1024) return 16;
    return 8;
#else
    (void)n;
    return 8;
#endif
}

/* The exact quotient spine wins in one middle AArch64 band: below it the
 * serial-product guard makes the full correction work more expensive than
 * divappr, while just above it unfavorable B-Z leaf widths produce a sharp
 * basecase cliff.  Keep the island target-specific until equivalent sweeps
 * exist elsewhere. */
#ifndef BN_SQRT_DIVQ_EXACT_MIN
#  if defined(__aarch64__)
#    define BN_SQRT_DIVQ_EXACT_MIN 1535
#  else
#    define BN_SQRT_DIVQ_EXACT_MIN INT32_MAX
#  endif
#endif
#ifndef BN_SQRT_DIVQ_EXACT_MAX
#  if defined(__aarch64__)
#    define BN_SQRT_DIVQ_EXACT_MAX 4094
#  else
#    define BN_SQRT_DIVQ_EXACT_MAX 0
#  endif
#endif

/* Top-level root-only variant: the same balanced split as the sqrtrem
 * recursion (keeping every engine call on the power-of-two-friendly
 * sizes), but quotient-only, remainder-free, and square-free.
 *
 * Divide with ONE GUARD LIMB below the true quotient.  When h == l + 1 the
 * dividend {np + l - 1, 2h} over s' is already the ulen == 2*vlen shape the
 * fast quotient-only engines (triangular-certified / cached-reciprocal)
 * want; when h == l, extend one more limb down and pad the divisor with a
 * low zero limb ({sp + l - 1, h + 1} with sp[l-1] = 0) — the quotient is
 * unchanged (rho*B + extra < s'B) and the shape stays 2(h+1) over (h+1).
 * Either way Q' = floor((r'*B^(l+1) + a1*B + np[l-1]) / s'), l+2 limbs
 * including the carry, and the root candidate is s'*B^l + floor(Q'/2B).
 * With g = the dropped 65-bit chunk of Q',
 *
 *     sqrt(A) - cand = g/2^65 + eps - theta,   0 <= eps < 2^-63,
 *
 * where theta = c^2/(2 s' B^l) is the AM-GM correction: < 2^-64 for
 * h == l + 1, and < 1 but computable to ~2^-50 relative from the top two
 * limbs of c and s' when h == l.  Whenever g - theta*2^65 sits 2^16 clear
 * of 0 and 2^65 the floor is certified with no square and no remainder
 * (below 0 certifies cand - 1).  Returns 1 when certified; 0 (probability
 * ~2^-48) sends the caller down the exact full-sqrtrem path.  qp needs
 * l + 2 limbs. */
#ifndef BN_SQRT_ONLY_NOINLINE
#  if defined(__aarch64__)
#    define BN_SQRT_ONLY_NOINLINE 1
#  else
#    define BN_SQRT_ONLY_NOINLINE 0
#  endif
#endif
#if BN_SQRT_ONLY_NOINLINE
__attribute__((noinline, aligned(64)))
#endif
static int bn_dc_sqrt_only(uint64_t *np, uint64_t *sp, uint64_t *qp,
                           int32_t n) {
    if (n <= 2) {
        (void)bn_dc_sqrtrem(np, sp, n);
        return 1;
    }
#ifndef BN_ISQRT_FULL_REM_ROOT_4096
#define BN_ISQRT_FULL_REM_ROOT_4096 1
#endif
    /* At this exact root width the full recurrence's balanced 4096/2048
     * division lands on a substantially better B-Z shape than the guarded
     * quotient-only top level.  Keep the exception exact: the neighboring
     * 4095/4097 widths do not share the win. */
    if (__builtin_expect(BN_ISQRT_FULL_REM_ROOT_4096 && n == 4096, 0)) {
        (void)bn_dc_sqrtrem(np, sp, n);
        return 1;
    }
    int32_t l = n >> 1, h = n - l;              /* h == l or l + 1 */
    uint64_t q = bn_dc_sqrtrem(np + 2 * l, sp + l, h);
    /* Fold r' strictly below s' (r' <= 2s': at most two subtractions,
     * each pre-adding B^(l+1) to Q'), so every divide below sees its
     * dividend under divisor * B^(quotient limbs). */
    if (q) (void)bn_sub_n(np + 2 * l, np + 2 * l, sp + l, h);
    while (mag_cmp(np + 2 * l, bz_trim(np + 2 * l, h), sp + l, h) >= 0) {
        (void)bn_sub_n(np + 2 * l, np + 2 * l, sp + l, h);
        q++;                                    /* r' <= 2s': <= 2 passes */
    }
    int32_t t = h == l;                         /* min divisor pad limbs */
    int32_t e = 0;                              /* guard limbs below root */
    int divided = 0;
    int exact_q = n >= BN_SQRT_DIVQ_EXACT_MIN &&
                  n <= BN_SQRT_DIVQ_EXACT_MAX;
    if (__builtin_expect(!exact_q && h + t >= BN_SQRT_DIVAPPR_MIN,
                         BN_SQRT_DIVAPPR_EXPECT)) {
        /* Even n (t == 1): the divisor pad limb below s' is ZERO, so
         * dividing by s'*B^p is exactly dividing by s'.  When h's halving
         * chain bottoms exactly on the tuned Knuth leaf (h = leaf * 2^j,
         * e.g. the 3*2^k family: 192 -> 96 -> 48 -> 24), peel the single
         * top quotient digit with one exact Knuth row and hand the
         * remaining 2h/h shape to the B-Z spine with NO padding at all --
         * the padded alternative widens the divide by up to pad/h (3.6%
         * at a 384-limb root) and fragments the leaves off the tuned
         * width.  Q' then has h+1 limbs (root l+1 limbs above one guard
         * limb, e = 0).  Relative to the padded dividend this drops the
         * limbs below np[l-1], perturbing Q' by less than one unit of the
         * guard limb -- absorbed by the certificate's 2^16 margin like
         * the spine's own skipped corrections. */
        int32_t w = h;
        while (!(w & 1) && w > BZ_THRESHOLD) w >>= 1;
        if (t && w == BZ_THRESHOLD) {
            uint64_t *sc = bz_ws_get((size_t)(13 * h + 64));
            if (sc) {
                uint64_t *rt = sc + 12 * h + 64;    /* peel remainder */
                uint64_t *dw = np + l - 1 + h;      /* top window, h+1 limbs */
                uint64_t qtop;
                /* {dw+1, h} < s' (folded above), so the window quotient is
                 * a single digit and the remainder feeds the spine. */
                bz_base_div_into(dw, h + 1, sp + l, h, &qtop, 1, rt, h, 1);
                memcpy(dw, rt, (size_t)h * sizeof(uint64_t));
                bn_toom_no_spin++;
                bz_d2n1n_q(np + l - 1, sp + l, h, qp, sc);
                bn_toom_no_spin--;
                qp[h] = qtop;                       /* e stays 0 */
                divided = 1;
            }
        }
        if (!divided) {
            /* Approximate B-Z quotient (divappr): pad the divisor to a
             * fixed-width multiple so the recursion stays on even splits
             * down to the Knuth base.  Each pad limb cancels one extra
             * dividend limb, so the quotient is unchanged apart from e
             * extra guard limbs appearing below it. */
            int32_t p = t;
            int32_t pad_limbs = bn_sqrt_divappr_pad_limbs(n);
            while ((h + p) & (pad_limbs - 1)) p++;
            uint64_t *sc = bz_ws_get((size_t)(12 * (h + p) + 64));
            if (sc) {
                e = h - l - 1 + p;
                for (int32_t i = 0; i < p; i++) sp[l - p + i] = 0;
                bn_toom_no_spin++;
                bz_d2n1n_q(np + 2 * l - h - 2 * p, sp + l - p, h + p, qp, sc);
                bn_toom_no_spin--;
                divided = 1;
            }
        }
    }
    if (!divided) {
        int32_t pad = t && h > 3;
        if (pad) sp[l - 1] = 0;                 /* divisor {sp+l-1, h+pad} */
        q += bn_sqrt_divq_guard(np + l - 1 - pad, l + 1, h + pad,
                                sp + l - pad, qp);
    }
    uint64_t g_lo = qp[e], g_hi = qp[e + 1] & 1;    /* dropped 65-bit chunk */
    for (int32_t i = 0; i + 1 < l; i++)
        sp[i] = (qp[i + e + 1] >> 1) | (qp[i + e + 2] << 63);
    sp[l - 1] = (qp[l + e] >> 1) | (q << 63);
    q >>= 1;
    if (q) {
        /* Quotient overflow: the unhalved Q' reached 2B^(l+1), so the
         * candidate is >= (s'+1)B^l.  But sqrt(A) < (s'+1)B^l always
         * (a1 B^l + a0 < B^2l), while the floor bound gives sqrt(A) >
         * (s'+1)B^l - 1.  Exactly: root = s'*B^l + (B^l - 1), certified. */
        for (int32_t i = 0; i < l; i++) sp[i] = UINT64_MAX;
        return 1;
    }
    double th;
    if (t) {
        /* theta*2^65 ~= cd^2/(sd*2^64) from the top two limbs of c, s'. */
        double cd = (double)sp[l - 1] * 18446744073709551616.0 +
                    (double)sp[l - 2];
        double sd = (double)sp[n - 1] * 18446744073709551616.0 +
                    (double)sp[n - 2];
        th = cd * cd / sd / 18446744073709551616.0;
    } else {
        th = 2.0;                               /* theta*2^65 < 2 */
    }
    double gd = (g_hi ? 18446744073709551616.0 : 0.0) + (double)g_lo;
    double diff = gd - th;
    if (diff > 65536.0 && diff < 36893488147419037696.0)
        return 1;                               /* < 2^65 - 2^16 */
    if (diff < -65536.0) {
        /* certified cand - 1 (frac < 0; frac > -1 always) */
        (void)bn_sqrt_sub_1(sp, n, 1);
        return 1;
    }
    return 0;
}

/* ---- Fixed 3..4-limb integer square root (two-limb root) --------------
 *
 * For a 3- or 4-limb operand the divide-and-conquer path above spends more
 * on bookkeeping than on the root: a normalization copy into the TLS
 * workspace, one recursion level, the guard-limb quotient buffer and the
 * certification arithmetic.  This leaf performs Zimmermann's digit
 * doubling once, entirely in registers:
 *
 *   n  = a << shift             even shift, n3 >= 2^62, so the root of n
 *                               has bit 127 set and isqrt(a) = isqrt(n) >>
 *                               (shift / 2) exactly
 *   s1, r = sqrtrem(n3:n2)      bn_sqrtrem2 (hardware sqrt seed, one udiv,
 *                               exact 128-bit fixup); r <= 2 s1
 *   q  = floor((r B + n1) / (2 s1))
 *                               r contributes at most two quotient units of
 *                               B, then one 2-by-1 reciprocal step against
 *                               s1 and a halving give the exact floor
 *   s  = s1 B + q               the root, or one too large: n < (s + 1)^2
 *                               always, and (s - 1)^2 <= n since q <= B
 *   n - s^2 in [0, 2 s]         exact 256-bit square and floor correction
 *
 * q == B is possible (r = 2 s1 with a large n1); the true root's top limb
 * is s1 exactly (floor(sqrt(floor(n / B^2))) == floor(sqrt(n) / B)), so
 * the saturated low limb B - 1 is then the root itself.  The downward
 * correction runs at most once; the upward loop is defensive.  No
 * workspace, no recursion, no certification: the remainder is exact. */
#ifndef BN_ISQRT4_DIRECT
#define BN_ISQRT4_DIRECT 0
#endif
#if BN_ISQRT4_DIRECT
static __attribute__((noinline))
WValue bigint_isqrt_34(const uint64_t *al, int32_t alen) {
    uint64_t n0 = al[0], n1 = al[1], n2 = al[2];
    uint64_t n3 = alen == 4 ? al[3] : 0;
    int lz = n3 ? __builtin_clzll(n3) : 64 + __builtin_clzll(n2);
    int shift = lz & ~1;                        /* even, 0..126 */
    int back = shift >> 1;                      /* 0..63 */
    if (shift >= 64) {
        n3 = n2; n2 = n1; n1 = n0; n0 = 0;
        shift -= 64;
    }
    if (shift) {
        n3 = (n3 << shift) | (n2 >> (64 - shift));
        n2 = (n2 << shift) | (n1 >> (64 - shift));
        n1 = (n1 << shift) | (n0 >> (64 - shift));
        n0 <<= shift;
    }
    uint64_t top[2] = { n2, n3 };
    uint64_t s1;
    uint64_t rh = bn_sqrtrem2(&s1, top);        /* s1 >= 2^63 */
    unsigned __int128 rem = ((unsigned __int128)rh << 64) | top[0];
    /* q' = floor((rem B + n1) / s1): rem <= 2 s1 yields the high quotient
     * units by at most two subtractions, then one reciprocal step. */
    uint64_t qh = 0;
    if (rem >= s1) {
        rem -= s1;
        qh = 1;
        if (rem >= s1) {
            rem -= s1;
            qh = 2;
        }
    }
    uint64_t dinv = bn_invert_limb(s1);
    uint64_t rr;
    uint64_t ql = bn_div_qr_preinv((uint64_t)rem, n1, s1, dinv, &rr);
    /* q = q' >> 1 with q' = qh B + ql <= 2B + 1; q' >= 2B saturates. */
    uint64_t q = qh >= 2 ? UINT64_MAX : (qh << 63) | (ql >> 1);

    /* s^2 = s1^2 B^2 + 2 s1 q B + q^2; only the low three limbs of n - s^2
     * are needed: |n - s^2| < 2^130, so limb 2 already carries the sign. */
    unsigned __int128 pll = (unsigned __int128)q * q;
    unsigned __int128 pm = (unsigned __int128)s1 * q;
    unsigned __int128 phh = (unsigned __int128)s1 * s1;
    uint64_t m0 = (uint64_t)pm << 1;
    uint64_t m1 = (uint64_t)(pm >> 63);
    uint64_t sq0 = (uint64_t)pll;
    unsigned __int128 t = (unsigned __int128)(uint64_t)(pll >> 64) + m0;
    uint64_t sq1 = (uint64_t)t;
    uint64_t sq2 = (uint64_t)phh + m1 + (uint64_t)(t >> 64);
    uint64_t r0 = n0 - sq0;
    uint64_t bw = n0 < sq0;
    uint64_t d1 = n1 - sq1;
    uint64_t r1 = d1 - bw;
    bw = (n1 < sq1) | (d1 < bw);
    uint64_t r2 = n2 - sq2 - bw;                /* sign-carrying limb */

    /* n - s^2 < 0: s -= 1, remainder += 2 s + 1 (with the new s). */
    while ((int64_t)r2 < 0) {
        s1 -= q == 0;
        q -= 1;
        uint64_t t0 = (q << 1) | 1, t1 = (s1 << 1) | (q >> 63);
        uint64_t t2 = s1 >> 63;
        uint64_t a0 = r0 + t0, c = a0 < r0;
        uint64_t a1 = r1 + t1, c1 = a1 < r1;
        a1 += c; c1 |= a1 < c;
        r2 += t2 + c1;
        r0 = a0; r1 = a1;
    }
    /* n - s^2 > 2 s: s += 1, remainder -= 2 s + 1 (with the old s). */
    for (;;) {
        uint64_t t0 = (q << 1) | 1, t1 = (s1 << 1) | (q >> 63);
        uint64_t t2 = s1 >> 63;
        uint64_t e0 = t0 & ~UINT64_C(1);        /* 2 s */
        if (r2 < t2 || (r2 == t2 && (r1 < t1 || (r1 == t1 && r0 <= e0))))
            break;
        uint64_t d0 = r0 - t0, b0 = r0 < t0;
        uint64_t e1 = r1 - t1, b1 = r1 < t1;
        uint64_t f1 = e1 - b0; b1 |= e1 < b0;
        r2 -= t2 + b1;
        r0 = d0; r1 = f1;
        q += 1;
        s1 += q == 0;
    }

    /* Undo the even normalization shift.  The root of the normalized value
     * has bit 127 set, so the top limb survives the back shift (>= 1 for a
     * 3-limb operand, >= 2^32 for four): always two limbs, never int48. */
    uint64_t lo = back ? (q >> back) | (s1 << (64 - back)) : q;
    uint64_t hi = s1 >> back;
    WBigint *r = bigint_alloc_raw_hot(2);
    r->limbs[0] = lo;
    r->limbs[1] = hi;
    r->size = 2;
    return bigint_box(r);
}
#endif

static __thread uint64_t *bn_sqrt_ws = NULL;
static __thread size_t bn_sqrt_ws_cap = 0;

/* Round-3 item 1: direct few-limb integer sqrt that divides with the raw
 * bn_udiv_qr_3by2 3-by-2 step (GMP divrem_2 shape) instead of the certified
 * 6/3 quotient (mag_div_q_63_certified) that the remainder-free top-level
 * path reaches at root widths 4-5.  Default on; item 1 routes operand
 * alen 3..8 (root <= 4, covering the isqrt@4 losing cell), item 17 widens
 * BN_ISQRT4V2_MAX to reach root 5 (alen 10). */
#ifndef BN_ISQRT4V2
#define BN_ISQRT4V2 0
#endif
/* Operand-limb cutoff for the direct kernel.  isqrt@4 (bench root 4) is a
 * 2*4 = 8-limb operand, and mag_div_q_63_certified fires at operand alen
 * 7..10 (root 4..5); routing alen 3..8 removes it from isqrt@4 -- the losing
 * cell -- and from root 3.  Item 17 raises this to reach root 5 (alen 10). */
#ifndef BN_ISQRT4V2_MAX
#define BN_ISQRT4V2_MAX 8
#endif
#if BN_ISQRT4V2
/* Exact integer Newton fallback for the rare case where the fast sqrtrem
 * candidate fails its certificate (a near-perfect-square edge the sqrtrem
 * overflow branch still mishandles at the n=2 top level: rem_hi plus the
 * refine carry can reach 2, whose << 63 wraps to 0 and misfires the
 * candidate == B^n overshoot correction).  The normalized operand keeps its
 * root in the top limb, so the all-ones seed B^m-1 is within a factor of two
 * and the descent converges in a couple of steps.  Rare, so the per-step
 * mag_divmod allocations are irrelevant.  Standard result: for s0 >=
 * floor(sqrt(N)) the map s -> (s + floor(N/s))/2 is monotone until it stops
 * decreasing, and the value it stops at is floor(sqrt(N)). */
static void bn_isqrt_small_newton(const uint64_t *nsave, int32_t wide,
                                  uint64_t *sp, int32_t m) {
    uint64_t s[12], t[14];
    for (int32_t i = 0; i < m; i++) s[i] = UINT64_MAX;   /* s0 = B^m - 1 */
    int32_t slen = m;
    for (;;) {
        WBigint *q = NULL, *r = NULL;
        mag_divmod(nsave, wide, s, slen, &q, &r);         /* q = floor(N/s) */
        int32_t qlen = q->size;
        int cmp = qlen != slen
            ? (qlen < slen ? -1 : 1)
            : mag_cmp(q->limbs, qlen, s, slen);
        if (cmp >= 0) { bigint_release(q); bigint_release(r); break; }
        /* t = s + q  (q < s < B^m, so the sum is below 2 B^m) */
        int32_t n = slen > qlen ? slen : qlen;
        uint64_t carry = 0;
        for (int32_t i = 0; i < n; i++) {
            uint64_t sv = i < slen ? s[i] : 0;
            uint64_t qv = i < qlen ? q->limbs[i] : 0;
            uint64_t lo = sv + qv;
            uint64_t c1 = lo < sv;
            uint64_t rr = lo + carry;
            carry = c1 | (rr < lo);
            t[i] = rr;
        }
        t[n] = carry;
        int32_t tn = n + (carry ? 1 : 0);
        for (int32_t i = 0; i + 1 < tn; i++)              /* s = t >> 1 */
            s[i] = (t[i] >> 1) | (t[i + 1] << 63);
        s[tn - 1] = t[tn - 1] >> 1;
        slen = tn;
        while (slen > 1 && s[slen - 1] == 0) slen--;
        bigint_release(q);
        bigint_release(r);
    }
    for (int32_t i = 0; i < m; i++) sp[i] = i < slen ? s[i] : 0;
}

/* Operand alen 3..BN_ISQRT4V2_MAX limbs (root m = ceil(alen/2) <= 4 limbs).
 * Normalize into an even 2m-limb window (top limb >= 2^62) and take the
 * divide-and-conquer sqrtrem, whose h <= 2 divide is the raw bn_udiv_qr_3by2
 * step and whose h = 3,4 divide is allocation-free Knuth -- never the
 * certified 6/3.  A cheap exact s^2 certificate guards the candidate; the
 * rare miss falls back to the exact Newton above.  Every buffer is a tiny
 * stack array (wide <= 8). */
static WValue bigint_isqrt_4direct(const uint64_t *al, int32_t alen) {
    int32_t m = (alen + 1) >> 1;
    int32_t wide = 2 * m;
    int32_t shift =
        (int32_t)((((int64_t)(wide - alen) << 6) +
                   __builtin_clzll(al[alen - 1])) & ~1LL);   /* even, < 128 */
    uint64_t np[20], nsave[20], sp[12];
    int32_t off = shift >> 6;                   /* == wide - alen (0 or 1) */
    int b = shift & 63;
    if (off) np[0] = 0;
    if (b == 0) {
        memcpy(np + off, al, (size_t)alen * sizeof(uint64_t));
    } else {
        np[off] = al[0] << b;
        for (int32_t i = 1; i < alen; i++)
            np[off + i] = (al[i] << b) | (al[i - 1] >> (64 - b));
    }
    memcpy(nsave, np, (size_t)wide * sizeof(uint64_t));

    (void)bn_dc_sqrtrem(np, sp, m);             /* candidate root (m limbs) */

    /* Exact certificate on the normalized value: 0 <= N - sp^2 <= 2*sp. */
    uint64_t sq[20], rem[20], two_s[20];
    bigint_sqr_dispatch(sq, sp, m);
    int ok = mag_cmp(sq, wide, nsave, wide) <= 0;
    if (ok) {
        (void)bn_sub_n(rem, nsave, sq, wide);
        uint64_t c = bn_add_n(two_s, sp, sp, m);
        two_s[m] = c;
        for (int32_t i = m + 1; i < wide; i++) two_s[i] = 0;
        if (mag_cmp(rem, wide, two_s, wide) > 0) ok = 0;
    }
    if (!ok)
        bn_isqrt_small_newton(nsave, wide, sp, m);

    int32_t back = shift >> 1;                   /* < 64 */
    if (back) {
        for (int32_t i = 0; i + 1 < m; i++)
            sp[i] = (sp[i] >> back) | (sp[i + 1] << (64 - back));
        sp[m - 1] >>= back;
    }
    WBigint *res = bigint_alloc_raw_hot(m);
    memcpy(res->limbs, sp, (size_t)m * sizeof(uint64_t));
    res->size = m;
    while (res->size > 0 && res->limbs[res->size - 1] == 0) res->size--;
    return bigint_box(res);
}
#endif

/* Integer square root of any non-negative int48-or-bigint WValue; exact
 * floor(sqrt(a)). Negative receivers die with Int#isqrt's message. */
WValue bigint_isqrt_any(WValue a) {
    if (w_is_int(a)) {
        int64_t n = w_as_int(a);
        if (n < 0) die("Int#isqrt: negative receiver");
        return w_box_int((int64_t)__builtin_sqrt((double)n));
    }
    uint64_t sa;
    int32_t alen;
    const uint64_t *al = integer_limbs(a, &sa, &alen);
    if (alen < 0) die("Int#isqrt: negative receiver");
    if (alen == 0) return w_box_int(0);
    if (alen <= 2) {
        unsigned __int128 v = alen == 2
            ? ((unsigned __int128)al[1] << 64) | al[0]
            : (unsigned __int128)al[0];
        uint64_t root = bn_isqrt_u128(v);
        if (root <= (uint64_t)W_INT48_MAX) return w_box_int((int64_t)root);
        WBigint *r = bigint_alloc_raw_hot(1);
        r->limbs[0] = root;
        r->size = 1;
        return bigint_box(r);
    }
    if (alen <= 4) {
        uint64_t np[4];
        int b = __builtin_clzll(al[alen - 1]) & ~1;
        if (alen == 3) {
            np[0] = 0;
            if (b == 0) {
                np[1] = al[0]; np[2] = al[1]; np[3] = al[2];
            } else {
                np[1] = al[0] << b;
                np[2] = (al[1] << b) | (al[0] >> (64 - b));
                np[3] = (al[2] << b) | (al[1] >> (64 - b));
            }
        } else if (b == 0) {
            np[0] = al[0]; np[1] = al[1]; np[2] = al[2]; np[3] = al[3];
        } else {
            np[0] = al[0] << b;
            np[1] = (al[1] << b) | (al[0] >> (64 - b));
            np[2] = (al[2] << b) | (al[1] >> (64 - b));
            np[3] = (al[3] << b) | (al[2] >> (64 - b));
        }
        uint64_t s1;
        uint64_t q = bn_sqrtrem2(&s1, np + 2);
        uint64_t r = np[2];
        if (q) r -= s1;
        if (r >= s1) { q++; r -= s1; }
        uint64_t dinv = bn_invert_limb(s1);
        uint64_t s0 = bn_div_qr_preinv(r, np[1], s1, dinv, &r);
        uint64_t c0 = s0 & 1;
        s0 = (s0 >> 1) | (q << 63);
        q >>= 1;
        if (__builtin_expect(q != 0, 0)) {
            s0 = UINT64_MAX;
        } else {
            uint64_t r1 = r + (c0 ? s1 : 0);
            uint64_t cc = c0 & (r1 < r);
            unsigned __int128 sq = (unsigned __int128)s0 * s0;
            unsigned __int128 u_low = ((unsigned __int128)r1 << 64) | np[0];
            if (!cc && u_low < sq) { s1 -= (s0 == 0); s0--; }
        }
        int back = ((alen == 3 ? 64 : 0) + b) >> 1;
        uint64_t lo = back ? (s0 >> back) | (s1 << (64 - back)) : s0;
        uint64_t hi = s1 >> back;
        WBigint *res = bigint_alloc_raw_hot_exact(2U);
        res->limbs[0] = lo;
        res->limbs[1] = hi;
        res->size = 2;
        return bigint_box(res);
    }
    /* Sub-2048-limb roots: the recursion's interior products (half and
     * quarter width) fall right at the parallel thresholds, and dispatch
     * churn inside the serial spine measured isqrt@512 at 1.49x GMP with
     * the lowered pool cutoffs vs 0.93x sequential.  At >= 2048 operand
     * limbs the products are large enough that parallel dispatch pays. */
#ifndef BN_ISQRT_SEQ_MAX
#define BN_ISQRT_SEQ_MAX INT32_MAX
#endif
    int isqrt_seq = alen < BN_ISQRT_SEQ_MAX;
    if (isqrt_seq) bn_toom_no_spin++;
    /* Normalize into the workspace: 2m limbs, top limb >= 2^62. */
    int32_t m = (alen + 1) >> 1;
    int32_t wide = 2 * m;
    int32_t shift =
        (int32_t)((((int64_t)(wide - alen) << 6) +
                   __builtin_clzll(al[alen - 1])) & ~1LL);   /* even, < 128 */
    /* The workspace holds the 2m normalized operand limbs AND the
     * guard-limb quotient buffer that bn_dc_sqrt_only writes at np + wide.
     * Growing on `wide` alone was wrong: a later, larger call whose `wide`
     * still fit under a previous inflated capacity skipped the regrow and
     * ran the quotient buffer off the end (isqrt at 16 limbs then 24 limbs
     * in one process — wide 48 under a cap of 56, needing 61). */
    size_t need = (size_t)wide + (size_t)((m - 1) / 2) + 4;
    if (need > bn_sqrt_ws_cap) {
        free(bn_sqrt_ws);
        size_t cap = need + need / 4 + 16;
        bn_sqrt_ws = (uint64_t *)malloc(cap * sizeof(uint64_t));
        if (!bn_sqrt_ws) { bn_sqrt_ws_cap = 0; die("isqrt: out of memory"); }
        bn_sqrt_ws_cap = cap;
    }
    uint64_t *np = bn_sqrt_ws;
    int32_t off = shift >> 6;                   /* == wide - alen */
    int b = shift & 63;
    if (off) np[0] = 0;
    if (b == 0) {
        memcpy(np + off, al, (size_t)alen * sizeof(uint64_t));
    } else {
        np[off] = al[0] << b;
        for (int32_t i = 1; i < alen; i++)
            np[off + i] = (al[i] << b) | (al[i - 1] >> (64 - b));
    }
    WBigint *res = bigint_alloc_raw_hot(m);
    /* Guard-limb quotient buffer ((m-1)/2 + 2 limbs) fits in the workspace
     * slack past the 2m operand limbs (cap >= 2m + m/2 + 16). */
    /* The square-root recursion interleaves its parallel products with
     * substantial serial quotient work; let the pool workers park right
     * after each product instead of burst-lingering through those spans
     * (measured +8-10% on isqrt@4096-8192 otherwise). */
    bn_toom_no_spin++;
    int sqrt_certified = bn_dc_sqrt_only(np, res->limbs, np + wide, m);
    bn_toom_no_spin--;
    if (!sqrt_certified) {
        /* Uncertified guard window (~2^-56): the workspace was consumed,
         * so re-normalize and take the exact full-sqrtrem path. */
        if (off) np[0] = 0;
        if (b == 0) {
            memcpy(np + off, al, (size_t)alen * sizeof(uint64_t));
        } else {
            np[off] = al[0] << b;
            for (int32_t i = 1; i < alen; i++)
                np[off + i] = (al[i] << b) | (al[i - 1] >> (64 - b));
        }
        bn_toom_no_spin++;
        (void)bn_dc_sqrtrem(np, res->limbs, m);
        bn_toom_no_spin--;
    }
    int32_t back = shift >> 1;                  /* < 64 */
    if (back) {
        for (int32_t i = 0; i + 1 < m; i++)
            res->limbs[i] =
                (res->limbs[i] >> back) | (res->limbs[i + 1] << (64 - back));
        res->limbs[m - 1] >>= back;
    }
    /* Root of a 2m-limb normalized value stays >= B^(m-1) after the shift
     * back, so the top limb is nonzero and no i48 demotion applies (m>=2). */
    res->size = m;
    if (isqrt_seq) bn_toom_no_spin--;
    return bigint_box(res);
}


/* ---- GCD: u64 fast path + Lehmer batching for multi-limb operands ----
 *
 * The previous implementation was one-limb-quotient Euclid: one 128/64
 * divide plus one freshly allocated remainder bigint per step. Lehmer batches
 * many Euclid steps into a 2x2 cofactor matrix computed on the leading 63
 * bits, then applies it to the full magnitudes in one linear-combination pass
 * over reusable scratch buffers. */
#if defined(BN_GCD_PROFILE_NOINLINE)
#define BN_GCD_PROFILE_ATTR __attribute__((noinline))
#else
#define BN_GCD_PROFILE_ATTR
#endif

#ifndef BN_GCD_U64_ASM
#define BN_GCD_U64_ASM 1
#endif
#ifndef BN_GCD_U64_BRANCHY
#define BN_GCD_U64_BRANCHY 0
#endif
/* Trailing-zero count inside the GCD asm kernels.  FEAT_CSSC cores (Apple
 * M4/M5, reached via -mcpu=apple-m5 or an explicit +cssc) have a single-uop
 * CTZ, which shortens every kernel's loop-carried chain
 * (subs -> ctz -> lsr -> subs) from 4 cycles to 3 — measured 25% on the
 * one-limb loop and 18% on the two-limb loop, which is what moves gcd@1/@2
 * past GMP's rbit+clz gcd_11/gcd_22.  Without CSSC the classic rbit+clz
 * pair is kept, machine-code-identical to the previous kernels:
 * BN_ASM_CTZ2 preserves the interleaved two-register prologue schedule,
 * and the EARLY/LATE pair keeps bn_gcd_odd_22's split placement (rbit
 * issues before the flag-consuming selects, clz after; CSSC folds the
 * whole count into the early slot). */
#if defined(__ARM_FEATURE_CSSC)
#define BN_ASM_CTZ(d, s)            "ctz " d ", " s "\n"
#define BN_ASM_CTZ2(d1, s1, d2, s2) "ctz " d1 ", " s1 "\n" \
                                    "ctz " d2 ", " s2 "\n"
#define BN_ASM_CTZ_EARLY(d, s)      "ctz " d ", " s "\n"
#define BN_ASM_CTZ_LATE(d)
#else
#define BN_ASM_CTZ(d, s)            "rbit " d ", " s "\n" \
                                    "clz " d ", " d "\n"
#define BN_ASM_CTZ2(d1, s1, d2, s2) "rbit " d1 ", " s1 "\n" \
                                    "rbit " d2 ", " s2 "\n" \
                                    "clz " d1 ", " d1 "\n" \
                                    "clz " d2 ", " d2 "\n"
#define BN_ASM_CTZ_EARLY(d, s)      "rbit " d ", " s "\n"
#define BN_ASM_CTZ_LATE(d)          "clz " d ", " d "\n"
#endif
#if defined(__aarch64__) && BN_GCD_U64_ASM
__attribute__((naked, noinline, aligned(64)))
static uint64_t bn_gcd_u64_binary(uint64_t a, uint64_t b) {
    __asm__(
        "cbz x0, 3f\n"
        "cbz x1, 4f\n"
        BN_ASM_CTZ2("x2", "x0", "x3", "x1")
        "lsr x0, x0, x2\n"
        "lsr x1, x1, x3\n"
        "cmp x2, x3\n"
        "csel x2, x2, x3, lo\n"
        "1:\n"
#if BN_GCD_U64_BRANCHY
        "subs x3, x0, x1\n"
        "b.eq 2f\n"
        "b.lo 5f\n"
        BN_ASM_CTZ("x4", "x3")
        "lsr x0, x3, x4\n"
        "b 1b\n"
        "5:\n"
        "neg x3, x3\n"
        BN_ASM_CTZ("x4", "x3")
        "lsr x1, x3, x4\n"
        "b 1b\n"
#else
        "subs x3, x0, x1\n"
        "b.eq 2f\n"
        /*
         * Align the loop and begin its independent trailing-zero chain
         * (rbit+clz, or one ctz on CSSC cores) before consuming the
         * subtraction flags.  On Apple AArch64 this overlaps trailing-zero
         * latency with cneg/csel instead of serializing them.
         */
        "nop\n"
        "nop\n"
        "nop\n"
        "6:\n"
        BN_ASM_CTZ("x4", "x3")
        "cneg x3, x3, lo\n"
        "csel x0, x1, x0, hs\n"
        "lsr x1, x3, x4\n"
        "subs x3, x0, x1\n"
        "b.ne 6b\n"
#endif
        "2:\n"
        "lsl x0, x0, x2\n"
        "ret\n"
        "3:\n"
        "mov x0, x1\n"
        "4:\n"
        "ret\n"
    );
}
#endif

/* Binary GCD for two nonzero words, force-inlined so call sites overlap the
 * trailing-zero prologue with operand loads instead of paying a naked-call
 * boundary.  ctz(d) == ctz(-d), so the trailing-zero chain of the raw
 * difference starts before the sign of the difference is resolved — the same
 * schedule as the hand-written loop in bn_gcd_u64_binary. */
static inline __attribute__((always_inline))
uint64_t bn_gcd_u64_nonzero(uint64_t a, uint64_t b) {
#if defined(__aarch64__) && BN_GCD_U64_ASM
    /* Same loop schedule as bn_gcd_u64_binary: the trailing-zero chain of
     * the raw difference (rbit+clz, or one CSSC ctz) starts before cneg/csel
     * resolve its sign (ctz(d) == ctz(-d)).
     * Inlined, minus that function's zero checks, which are dead here. */
    uint64_t sh, t3, t4;
    __asm__(
        BN_ASM_CTZ2("%[t3]", "%[a]", "%[t4]", "%[b]")
        "lsr %[a], %[a], %[t3]\n\t"
        "lsr %[b], %[b], %[t4]\n\t"
        "cmp %[t3], %[t4]\n\t"
        "csel %[sh], %[t3], %[t4], lo\n\t"
        "subs %[t3], %[a], %[b]\n\t"
        "b.eq 2f\n"
        "1:\n\t"
        BN_ASM_CTZ("%[t4]", "%[t3]")
        "cneg %[t3], %[t3], lo\n\t"
        "csel %[a], %[b], %[a], hs\n\t"
        "lsr %[b], %[t3], %[t4]\n\t"
        "subs %[t3], %[a], %[b]\n\t"
        "b.ne 1b\n"
        "2:\n\t"
        "lsl %[a], %[a], %[sh]\n"
        : [a] "+&r"(a), [b] "+&r"(b), [sh] "=&r"(sh),
          [t3] "=&r"(t3), [t4] "=&r"(t4)
        :
        : "cc");
    return a;
#else
    unsigned az = (unsigned)__builtin_ctzll(a);
    unsigned bz = (unsigned)__builtin_ctzll(b);
    unsigned shift = az < bz ? az : bz;
    a >>= az;
    b >>= bz;
    while (a != b) {
        uint64_t d = a - b;
        unsigned tz = (unsigned)__builtin_ctzll(d);
        uint64_t lo = a < b ? a : b;
        uint64_t mag = a < b ? (uint64_t)-d : d;
        b = lo;
        a = mag >> tz;
    }
    return a << shift;
#endif
}

static uint64_t w_gcd_u64(uint64_t a, uint64_t b) {
#ifndef BN_GCD_U64_BINARY
#define BN_GCD_U64_BINARY 1
#endif
#if BN_GCD_U64_BINARY
#if defined(__aarch64__) && BN_GCD_U64_ASM
    return bn_gcd_u64_binary(a, b);
#else
    if (a == 0) return b;
    if (b == 0) return a;
    unsigned common_shift = (unsigned)__builtin_ctzll(a | b);
    a >>= (unsigned)__builtin_ctzll(a);
    do {
        b >>= (unsigned)__builtin_ctzll(b);
        if (a > b) {
            uint64_t swap = a;
            a = b;
            b = swap;
        }
        b -= a;
    } while (b != 0);
    return a << common_shift;
#endif
#else
    while (b) {
        uint64_t t = a % b;
        a = b;
        b = t;
    }
    return a;
#endif
}

#ifndef BN_GCD_22_ASM
#define BN_GCD_22_ASM 1
#endif
#ifndef BN_GCD_22_BRANCHY
#define BN_GCD_22_BRANCHY 0
#endif
#if defined(__aarch64__) && BN_GCD_22_ASM
/* Register-only binary GCD for two already-odd magnitudes.
 * Arguments are (u_hi, u_lo, v_hi, v_lo); __int128 returns (lo, hi) in
 * (x0, x1) under AAPCS64. */
__attribute__((naked, noinline, aligned(64)))
static unsigned __int128 bn_gcd_odd_22(
    uint64_t u_hi, uint64_t u_lo, uint64_t v_hi, uint64_t v_lo) {
    __asm__(
        /* Subtract, retain the smaller operand, and strip all powers of two
         * from the absolute difference. */
        "1:\n"
        "subs x4, x1, x3\n"
        "cbz x4, 4f\n"
        "sbcs x5, x0, x2\n"
        BN_ASM_CTZ_EARLY("x6", "x4")
#if BN_GCD_22_BRANCHY
        "b.hs 7f\n"
        "neg x4, x4\n"
        "mvn x5, x5\n"
        "mov x3, x1\n"
        "mov x2, x0\n"
        "7:\n"
#else
        "cneg x4, x4, lo\n"
        "cinv x5, x5, lo\n"
        "csel x3, x3, x1, hs\n"
        "csel x2, x2, x0, hs\n"
#endif
        BN_ASM_CTZ_LATE("x6")   /* nonzero even low difference: 1..63 */
        "neg x7, x6\n"
        "lsr x1, x4, x6\n"
        "lsl x7, x5, x7\n"
        "lsr x0, x5, x6\n"
        "orr x1, x1, x7\n"
        "orr x7, x0, x2\n"
        "cbnz x7, 1b\n"

        /* Both magnitudes now fit one limb. */
        "2:\n"
#if BN_GCD_22_BRANCHY
        "subs x4, x1, x3\n"
        "b.eq 5f\n"
        "b.lo 8f\n"
        BN_ASM_CTZ("x5", "x4")
        "lsr x1, x4, x5\n"
        "b 2b\n"
        "8:\n"
        "neg x4, x4\n"
        BN_ASM_CTZ("x5", "x4")
        "lsr x3, x4, x5\n"
        "b 2b\n"
#else
        "subs x4, x1, x3\n"
        "b.eq 5f\n"
        "nop\n"
        "nop\n"
        "9:\n"
        BN_ASM_CTZ("x5", "x4")
        "cneg x4, x4, lo\n"
        "csel x1, x3, x1, hs\n"
        "lsr x3, x4, x5\n"
        "subs x4, x1, x3\n"
        "b.ne 9b\n"
#endif

        /* Low limbs matched but the high limbs did not. */
        "4:\n"
        "subs x5, x0, x2\n"
        "b.eq 6f\n"
        "cneg x5, x5, lo\n"
        "csel x2, x2, x0, hs\n"
        BN_ASM_CTZ("x6", "x5")
        "lsr x1, x5, x6\n"
        "mov x0, xzr\n"
        "cbnz x2, 1b\n"
        "b 2b\n"

        "5:\n"
        "mov x0, x1\n"
        "mov x1, xzr\n"
        "ret\n"

        /* Equal two-limb operands. */
        "6:\n"
        "mov x4, x0\n"
        "mov x0, x1\n"
        "mov x1, x4\n"
        "ret\n"
    );
}

static inline int bn_ctz_2(uint64_t hi, uint64_t lo) {
    return lo ? __builtin_ctzll(lo) : 64 + __builtin_ctzll(hi);
}

static inline void bn_rshift_2(
    uint64_t *hi, uint64_t *lo, int shift) {
    if (shift >= 64) {
        *lo = *hi >> (shift - 64);
        *hi = 0;
    } else if (shift) {
        *lo = (*lo >> shift) | (*hi << (64 - shift));
        *hi >>= shift;
    }
}

static unsigned __int128 bn_gcd_22(
    uint64_t uh, uint64_t ul, uint64_t vh, uint64_t vl) {
    int us = bn_ctz_2(uh, ul);
    int vs = bn_ctz_2(vh, vl);
    int common = us < vs ? us : vs;
    bn_rshift_2(&uh, &ul, us);
    bn_rshift_2(&vh, &vl, vs);
    unsigned __int128 odd = bn_gcd_odd_22(uh, ul, vh, vl);
    return odd << common;
}
#endif

/* x mod y0 for a raw magnitude.  Reuse the single-limb remainder dispatcher
 * so GCD's final reduction also benefits from reciprocal/block folding when
 * the last divisor is narrow. */
static uint64_t mag_mod_u64(const uint64_t *x, int32_t n, uint64_t y0) {
    return mag_mod_single(x, n, y0);
}

static BN_GCD_PROFILE_ATTR int32_t mag_norm_len(const uint64_t *p, int32_t n) {
    while (n > 0 && p[n - 1] == 0) n--;
    return n;
}

static int64_t mag_bitlen(const uint64_t *p, int32_t n) {
    if (n == 0) return 0;
    return (int64_t)(n - 1) * 64 + (64 - __builtin_clzll(p[n - 1]));
}

/* Leading bits of x, and the bits of y at the same bit positions. */
#ifndef BN_GCD_TOP_BITS
#define BN_GCD_TOP_BITS 63
#endif
static BN_GCD_PROFILE_ATTR void mag_top_digits(
    const uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen,
    uint64_t *xh_out, uint64_t *yh_out) {
    int32_t top = xlen - 1;
    int lz = __builtin_clzll(x[top]);
    uint64_t xh = x[top] << lz;
    uint64_t yh = 0;
    if (lz && top > 0) xh |= x[top - 1] >> (64 - lz);
    if (ylen > top) {
        yh = y[top] << lz;
        if (lz && top > 0) yh |= y[top - 1] >> (64 - lz);
    } else if (ylen == top && lz) {
        yh = y[top - 1] >> (64 - lz);
    }
#if BN_GCD_TOP_BITS == 63
    /* The spare bit prevents cofactor-corrected sums from wrapping u64. */
    *xh_out = xh >> 1;
    *yh_out = yh >> 1;
#elif BN_GCD_TOP_BITS == 64
    *xh_out = xh;
    *yh_out = yh;
#else
#error "BN_GCD_TOP_BITS must be 63 or 64"
#endif
}

#ifndef BN_GCD_DOUBLE_LEHMER
#define BN_GCD_DOUBLE_LEHMER 1
#endif
/* Engage the fused 128-bit window from 32 limbs: single 63-bit windows die
 * at ~18 steps (window precision crosses the growing cofactors), while the
 * double window reaches the ~33-step cofactor bound, halving the number of
 * full-width pair passes for everything above this threshold. */
#ifndef BN_GCD_DOUBLE_LEHMER_THRESHOLD
#define BN_GCD_DOUBLE_LEHMER_THRESHOLD 32
#endif
#ifndef BN_GCD_DOUBLE_LEHMER_ROUNDS
#define BN_GCD_DOUBLE_LEHMER_ROUNDS 2
#endif

#if BN_GCD_DOUBLE_LEHMER
/* Leading 128 bits of x, and the bits of y at the same positions. */
static BN_GCD_PROFILE_ATTR void mag_top_double(
    const uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen,
    uint64_t *xh_out, uint64_t *xl_out,
    uint64_t *yh_out, uint64_t *yl_out) {
    int32_t top = xlen - 1;
    int lz = __builtin_clzll(x[top]);
    uint64_t x1 = x[top];
    uint64_t x0 = top > 0 ? x[top - 1] : 0;
    uint64_t xm = top > 1 ? x[top - 2] : 0;
    uint64_t y1 = top < ylen ? y[top] : 0;
    uint64_t y0 = top > 0 && top - 1 < ylen ? y[top - 1] : 0;
    uint64_t ym = top > 1 && top - 2 < ylen ? y[top - 2] : 0;
    *xh_out = (x1 << lz) | (lz ? x0 >> (64 - lz) : 0);
    *xl_out = (x0 << lz) | (lz ? xm >> (64 - lz) : 0);
    *yh_out = (y1 << lz) | (lz ? y0 >> (64 - lz) : 0);
    *yl_out = (y0 << lz) | (lz ? ym >> (64 - lz) : 0);
}

static inline int gcd_u128_mul_u64(
    __uint128_t x, uint64_t y, __uint128_t *out) {
    uint64_t xl = (uint64_t)x;
    uint64_t xh = (uint64_t)(x >> 64);
    __uint128_t lp = (__uint128_t)xl * y;
    __uint128_t hp0 = (__uint128_t)xh * y;
    __uint128_t hp = hp0 + (uint64_t)(lp >> 64);
    if (hp < hp0 || hp >> 64) return 0;
    *out = (hp << 64) | (uint64_t)lp;
    return 1;
}
#endif

/* Knuth Algorithm L inner loop. Returns the number of simulated Euclid steps;
 * zero tells the caller to perform a full-magnitude fallback step. */
#ifndef BN_GCD_SMALL_QUOTIENT_BOUNDS
#define BN_GCD_SMALL_QUOTIENT_BOUNDS 1
#endif
#ifndef BN_GCD_FAST_QUOTIENT_ONE
#define BN_GCD_FAST_QUOTIENT_ONE 1
#endif
#ifndef BN_GCD_SMALL_FAST_QUOTIENT_TWO
#define BN_GCD_SMALL_FAST_QUOTIENT_TWO 1
#endif
#ifndef BN_GCD_SMALL_SINGLE_TRIAL_DIVIDE
#define BN_GCD_SMALL_SINGLE_TRIAL_DIVIDE 1
#endif
#ifdef BN_GCD_PROFILE_COUNTS
static uint64_t gcd_profile_sim_calls;
static uint64_t gcd_profile_sim_steps;
static uint64_t gcd_profile_fast_q1;
static uint64_t gcd_profile_pair_calls;
static uint64_t gcd_profile_pair_limbs;
static uint64_t gcd_profile_matrix_products;
static uint64_t gcd_profile_matrix_product_work;
static uint64_t gcd_profile_matrix_product_bins[12];
/* hgcd diagnosis counters (probe builds only) */
static uint64_t gcd_profile_hgcd_top_calls, gcd_profile_hgcd_top_ok;
static uint64_t gcd_profile_hgcd_top_xlen;
static uint64_t gcd_profile_child_calls, gcd_profile_child_ok;
static uint64_t gcd_profile_child_removed;
static uint64_t gcd_profile_block_calls[2];
static uint64_t gcd_profile_block_ok[2];
static uint64_t gcd_profile_block_removed[2];
static uint64_t gcd_profile_block_batches[2];
static uint64_t gcd_profile_block_batch_limbs[2];
static int gcd_profile_ctx; /* 0 = tree, 1 = apply, 2 = acc-multiply */
static uint64_t gcd_profile_ctx_work[3];
/* failure reasons: 0 entry-geometry, 1 slice-degenerate, 2 matrix-overflow,
 * 3 reduction-stall, 4 apply-invalid, 5 no-shrink */
static uint64_t gcd_profile_block_fail[2][6];
static uint64_t gcd_profile_block_fail_xlen[2][6];
#define GCD_PROF_FAIL(reason) do { \
        int ar_ = allow_recursive ? 1 : 0; \
        gcd_profile_block_fail[ar_][reason]++; \
        gcd_profile_block_fail_xlen[ar_][reason] += (uint64_t)xlen; \
    } while (0)
#else
#define GCD_PROF_FAIL(reason) ((void)0)
#endif
/* Cofactor magnitude limit (2^61 - 1) / q, indexed by quotient.  A wider
 * 2^62 limit was tried and lifts the quadratic loop ~2% (longer batches),
 * but it degrades the HGCD band badly: slice batches carry near-overflow
 * cofactors into the accumulated matrices and chained blocks at 1.5-2K limbs
 * lose more than the batching gain. */
static const uint64_t bn_gcd_cofactor_bounds[17] = {
    0,
    2305843009213693951ULL, 1152921504606846975ULL,
    768614336404564650ULL,  576460752303423487ULL,
    461168601842738790ULL,  384307168202282325ULL,
    329406144173384850ULL,  288230376151711743ULL,
    256204778801521550ULL,  230584300921369395ULL,
    209622091746699450ULL,  192153584101141162ULL,
    177372539170284150ULL,  164703072086692425ULL,
    153722867280912930ULL,  144115188075855871ULL
};

static BN_GCD_PROFILE_ATTR int lehmer_simulate(
    uint64_t xh, uint64_t yh,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd,
    uint64_t *quotients) {
    int64_t a = 1, b = 0, c = 0, d = 1;
    int steps = 0;
    for (;;) {
        __int128 yc = (__int128)yh + c;
        __int128 yd = (__int128)yh + d;
        if (yc <= 0 || yd <= 0) break;
        __int128 xa = (__int128)xh + a;
        __int128 xb = (__int128)xh + b;
        if (xa < 0 || xb < 0) break;
#if BN_GCD_TOP_BITS == 64
        if (yc > UINT64_MAX || yd > UINT64_MAX ||
            xa > UINT64_MAX || xb > UINT64_MAX)
            break;
#endif
#if BN_GCD_FAST_QUOTIENT_ONE
        uint64_t xau = (uint64_t)xa, xbu = (uint64_t)xb;
        uint64_t ycu = (uint64_t)yc, ydu = (uint64_t)yd;
        if (xau < ycu || xbu < ydu) break;
        uint64_t q1, q2;
        uint64_t xr = xau - ycu, yr = xbu - ydu;
        if (xr < ycu && yr < ydu) {
            q1 = 1;
            q2 = 1;
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_fast_q1++;
#endif
        } else {
            q1 = xau / ycu;
            q2 = xbu / ydu;
        }
#else
        uint64_t q1 = (uint64_t)xa / (uint64_t)yc;
        uint64_t q2 = (uint64_t)xb / (uint64_t)yd;
#endif
        if (q1 != q2 || q1 == 0) break;
#if BN_GCD_SMALL_QUOTIENT_BOUNDS
        if (q1 > INT64_MAX) break;
        uint64_t bound = q1 <= 16 ? bn_gcd_cofactor_bounds[q1]
                                  : (uint64_t)((INT64_MAX >> 2) /
                                               (int64_t)q1);
#else
        int64_t bound = (INT64_MAX >> 2) / (int64_t)q1;
#endif
        if ((uint64_t)llabs(c) > (uint64_t)bound ||
            (uint64_t)llabs(d) > (uint64_t)bound)
            break;
        if (quotients && steps >= 96) break;
        if (quotients) quotients[steps] = q1;
        int64_t t;
        t = a - (int64_t)q1 * c; a = c; c = t;
        t = b - (int64_t)q1 * d; b = d; d = t;
        uint64_t r = xh - q1 * yh;
        xh = yh;
        yh = r;
        steps++;
    }
    *pa = a;
    *pb = b;
    *pc = c;
    *pd = d;
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_sim_calls++;
    gcd_profile_sim_steps += (uint64_t)steps;
#endif
    return steps;
}

#if BN_GCD_SMALL_FAST_QUOTIENT_TWO
/* Small random GCDs spend most of their time in the two trial divisions in
 * Algorithm L.  Keep a separate <=4-limb simulator so recognizing quotient
 * two does not add a branch or perturb register allocation in the large-GCD
 * loop. */
static int lehmer_simulate_small_q2(
    uint64_t xh, uint64_t yh,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd) {
    int64_t a = 1, b = 0, c = 0, d = 1;
    int steps = 0;
    for (;;) {
        __int128 yc = (__int128)yh + c;
        __int128 yd = (__int128)yh + d;
        if (yc <= 0 || yd <= 0) break;
        __int128 xa = (__int128)xh + a;
        __int128 xb = (__int128)xh + b;
        if (xa < 0 || xb < 0) break;

        uint64_t xau = (uint64_t)xa, xbu = (uint64_t)xb;
        uint64_t ycu = (uint64_t)yc, ydu = (uint64_t)yd;
        if (xau < ycu || xbu < ydu) break;
        uint64_t q1, q2;
        uint64_t xr = xau - ycu, yr = xbu - ydu;
        if (xr < ycu && yr < ydu) {
            q1 = q2 = 1;
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_fast_q1++;
#endif
        } else if (xr >= ycu && yr >= ydu &&
                   xr - ycu < ycu && yr - ydu < ydu) {
            q1 = q2 = 2;
        } else {
            q1 = xau / ycu;
#if BN_GCD_SMALL_SINGLE_TRIAL_DIVIDE
            __uint128_t qp = (__uint128_t)q1 * ydu;
            if (qp > xbu || (uint64_t)(xbu - qp) >= ydu) break;
            q2 = q1;
#else
            q2 = xbu / ydu;
#endif
        }
        if (q1 != q2 || q1 == 0 || q1 > INT64_MAX) break;
        uint64_t bound = q1 <= 16 ? bn_gcd_cofactor_bounds[q1]
                                  : (uint64_t)((INT64_MAX >> 2) /
                                               (int64_t)q1);
        if ((uint64_t)llabs(c) > bound || (uint64_t)llabs(d) > bound)
            break;
        int64_t t;
        t = a - (int64_t)q1 * c; a = c; c = t;
        t = b - (int64_t)q1 * d; b = d; d = t;
        uint64_t r = xh - q1 * yh;
        xh = yh;
        yh = r;
        steps++;
    }
    *pa = a;
    *pb = b;
    *pc = c;
    *pd = d;
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_sim_calls++;
    gcd_profile_sim_steps += (uint64_t)steps;
#endif
    return steps;
}
#endif

/* Keep the <=4-limb entry separate from the double-window simulator below.
 * Otherwise Clang merges both into one function and every tiny GCD pays the
 * latter's 96-quotient stack frame and callee-save prologue. */
#if BN_GCD_SMALL_FAST_QUOTIENT_TWO
__attribute__((noinline))
static int lehmer_simulate_small_magnitudes(
    const uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd) {
    uint64_t xh, yh;
    mag_top_digits(x, xlen, y, ylen, &xh, &yh);
    return yh ? lehmer_simulate_small_q2(
        xh, yh, pa, pb, pc, pd) : 0;
}

__attribute__((noinline))
static int lehmer_simulate_2_magnitudes(
    const uint64_t *x, const uint64_t *y,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd) {
    int lz = __builtin_clzll(x[1]);
    uint64_t xh = x[1] << lz;
    uint64_t yh = y[1] << lz;
    if (lz) {
        xh |= x[0] >> (64 - lz);
        yh |= y[0] >> (64 - lz);
    }
    xh >>= 1;
    yh >>= 1;
    return yh ? lehmer_simulate_small_q2(
        xh, yh, pa, pb, pc, pd) : 0;
}
#endif

#if BN_GCD_DOUBLE_LEHMER
/* Fused double-window Lehmer.  Algorithm L quotient selection runs on a
 * 64-bit leading window while each accepted quotient is applied immediately
 * to the 128-bit pair.  One loop replaces the previous collect-then-replay
 * split (a 96-entry quotient buffer plus a second pass of redundant bound
 * re-checks), and the window division chain overlaps the 128-bit
 * multiply-subtract chain instead of serializing after it. */
static BN_GCD_PROFILE_ATTR int lehmer_simulate_double(
    uint64_t xh, uint64_t xl, uint64_t yh, uint64_t yl,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd) {
    __uint128_t x = ((__uint128_t)xh << 64) | xl;
    __uint128_t y = ((__uint128_t)yh << 64) | yl;
    int64_t a = 1, b = 0, c = 0, d = 1;
    int steps = 0;
    for (int round = 0; round < BN_GCD_DOUBLE_LEHMER_ROUNDS; round++) {
        uint64_t xhi = (uint64_t)(x >> 64);
        uint64_t yhi = (uint64_t)(y >> 64);
        if (!xhi || !yhi) break;
        int lz = __builtin_clzll(xhi);
        uint64_t xt = (xhi << lz) |
                      (lz ? (uint64_t)x >> (64 - lz) : 0);
        uint64_t yt = (yhi << lz) |
                      (lz ? (uint64_t)y >> (64 - lz) : 0);
        if (!yt) break;
        int64_t la = 1, lb = 0, lc = 0, ld = 1;
        int local_steps = 0;
        int stalled = 0;
        for (;;) {
            /* Window quotient selection, identical to lehmer_simulate. */
            __int128 yc = (__int128)yt + lc;
            __int128 yd = (__int128)yt + ld;
            if (yc <= 0 || yd <= 0) break;
            __int128 xa = (__int128)xt + la;
            __int128 xb = (__int128)xt + lb;
            if (xa < 0 || xb < 0) break;
            uint64_t xau = (uint64_t)xa, xbu = (uint64_t)xb;
            uint64_t ycu = (uint64_t)yc, ydu = (uint64_t)yd;
            if (xau < ycu || xbu < ydu) break;
            uint64_t q1, q2;
            uint64_t xr = xau - ycu, yr = xbu - ydu;
            if (xr < ycu && yr < ydu) {
                q1 = 1;
                q2 = 1;
#ifdef BN_GCD_PROFILE_COUNTS
                gcd_profile_fast_q1++;
#endif
            } else {
                /* Two independent trial divisions pipeline on separate
                 * ports; a single division plus multiply-verify was tried
                 * and serializes into the step's dependency chain, losing
                 * more at large widths than it saves. */
                q1 = xau / ycu;
                q2 = xbu / ydu;
            }
            if (q1 != q2 || q1 == 0 || q1 > INT64_MAX) break;
            uint64_t bound = q1 <= 16 ? bn_gcd_cofactor_bounds[q1]
                                      : (uint64_t)((INT64_MAX >> 2) /
                                                   (int64_t)q1);
            /* The window cofactors validate the quotient; the accumulated
             * cofactors are what the caller applies.  Both must stay clear
             * of int64 overflow. */
            if ((uint64_t)llabs(lc) > bound ||
                (uint64_t)llabs(ld) > bound ||
                (uint64_t)llabs(c) > bound ||
                (uint64_t)llabs(d) > bound) {
                stalled = 1;
                break;
            }
            __uint128_t product;
            if (!gcd_u128_mul_u64(y, q1, &product) || product > x) {
                stalled = 1;
                break;
            }
            int64_t t;
            t = la - (int64_t)q1 * lc; la = lc; lc = t;
            t = lb - (int64_t)q1 * ld; lb = ld; ld = t;
            uint64_t wr = xt - q1 * yt;
            xt = yt;
            yt = wr;
            t = a - (int64_t)q1 * c; a = c; c = t;
            t = b - (int64_t)q1 * d; b = d; d = t;
            __uint128_t r = x - product;
            x = y;
            y = r;
            local_steps++;
            steps++;
        }
#ifdef BN_GCD_PROFILE_COUNTS
        gcd_profile_sim_calls++;
        gcd_profile_sim_steps += (uint64_t)local_steps;
#endif
        if (!local_steps || stalled) break;
    }
    *pa = a;
    *pb = b;
    *pc = c;
    *pd = d;
    return steps;
}
#endif

static inline int lehmer_simulate_magnitudes(
    const uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen,
    int64_t *pa, int64_t *pb, int64_t *pc, int64_t *pd) {
#if BN_GCD_DOUBLE_LEHMER
    if (xlen >= BN_GCD_DOUBLE_LEHMER_THRESHOLD) {
        uint64_t xh, xl, yh, yl;
        mag_top_double(x, xlen, y, ylen, &xh, &xl, &yh, &yl);
        return yh ? lehmer_simulate_double(
            xh, xl, yh, yl, pa, pb, pc, pd) : 0;
    }
#endif
    uint64_t xh, yh;
    mag_top_digits(x, xlen, y, ylen, &xh, &yh);
    return yh ? lehmer_simulate(xh, yh, pa, pb, pc, pd, NULL) : 0;
}

/* ---- hgcd2: two-limb quotient batching with Jebelean-exact steps -----
 *
 * Moller's hgcd2 shape (Schonhage/HGCD base case): run the Euclid quotient
 * sequence on the leading 128 bits of both operands, aligned to x's top
 * bit, and accumulate the nonnegative cofactor matrix
 *
 *   (a; b) = M (alpha; beta),  M = [u00 u01; u10 u11],  det M = +1,
 *
 * without ever swapping the pair: the roles of a and b alternate between
 * half-steps (a -= q b then b -= q a), so M is updated by right
 * multiplication with [1 q; 0 1] / [1 0; q 1], and the reduced pair is
 * always alpha = u11 a - u01 b, beta = u00 b - u10 a.  The full operands
 * receive the same rows through mag_linear_comb_pair with the unsigned
 * magnitudes directly, so cofactors use every bit below 2^63 instead of
 * the 2^61 limit the signed Algorithm-L bounds tables impose.
 *
 * Exactness (Jebelean's condition, derived for X = a T + a', Y = b T + b',
 * 0 <= a', b' < T).  Let r be the value produced by a half-step and c the
 * other value.  The quotient is the true quotient of the full operands for
 * every possible low part when
 *
 *   (C1)  r >= |negative cofactor of r|          (full r stays >= 0)
 *   (C2)  c - r >= |c's negative cofactor| + |r's matching cofactor|
 *                                               (full r stays below full c)
 *
 * With alpha = u11 a - u01 b and beta = u00 b - u10 a the cofactors are
 * read straight off M: after a -= q b the new alpha has b-cofactor u01' =
 * q u00 + u01 (its negative one) while beta keeps a-cofactor u10 and the
 * new alpha's a-cofactor is u11' = q u10 + u11, so the tests are
 * alpha' >= u01' and beta - alpha' >= u10 + u11'.  After b -= q a the rows
 * swap roles: beta' >= u10' and alpha - beta' >= u01 + u00'.  A step that
 * fails either test is not applied, so every quotient the matrix encodes
 * is exact and the full-width pass can only produce the true Euclid
 * remainders (the caller still validates).
 *
 * Quotient: q = 1 is a compare (41% of Euclid steps), q = 2 one more;
 * otherwise q0 = ah / bh from the high limbs, which is the true q or one
 * too large whenever q0 <= bh, resolved by one 128x64 multiply-subtract
 * and a compare.  q0 > bh (a quotient beyond the high limb's precision,
 * only possible with tiny bh, i.e. at the very end of a batch or for an
 * unbalanced first step) stops the batch and leaves the step to the
 * existing simulators.  Row 0 dominates row 1 entrywise after the first
 * step, so a single < 2^63 test on the new row-0 entry bounds the whole
 * matrix for the signed-carry pair kernel. */
#ifndef BN_GCD_HGCD2
#define BN_GCD_HGCD2 1
#endif
#ifndef BN_GCD_HGCD2_MIN_LIMBS
#define BN_GCD_HGCD2_MIN_LIMBS 3
#endif
#ifndef BN_GCD_HGCD2_FAST_Q2
#define BN_GCD_HGCD2_FAST_Q2 1
#endif
#if BN_GCD_HGCD2
/* Half-step: `big` -= q * `small`, and the matrix column belonging to
 * `big` (entries c0 in row 0, c1 in row 1) gains q times the other column
 * (o0, o1).  Row 0 holds b-cofactors, row 1 a-cofactors, so the two
 * half-steps are not index mirrors: after a -= q b the new alpha's negative
 * cofactor is its b-cofactor (row 0) and the difference test pairs the
 * a-cofactors (row 1); after b -= q a the roles swap.  `neg0` names the
 * row of the new value's negative cofactor.  Breaks out of the enclosing
 * loop when the step cannot be certified. */
#define GCD_HGCD2_HALF_STEP(big, small, c0, c1, o0, o1, neg0)               \
    do {                                                                    \
        __uint128_t g_ = (big) - (small);                                   \
        uint64_t q_;                                                        \
        if (g_ < (small)) {                                                 \
            q_ = 1;                                                         \
        } else if (BN_GCD_HGCD2_FAST_Q2 && g_ - (small) < (small)) {        \
            q_ = 2;                                                         \
            g_ -= (small);                                                  \
        } else {                                                            \
            uint64_t bh_ = (uint64_t)((small) >> 64);                       \
            if (!bh_) goto done;                                            \
            q_ = (uint64_t)((big) >> 64) / bh_;                             \
            if (q_ > bh_) goto done;                                        \
            /* (q_ - 1) * small <= q * small <= big: no wrap. */            \
            __uint128_t p_ = (__uint128_t)(uint64_t)(small) * (q_ - 1);     \
            p_ += (__uint128_t)(bh_ * (q_ - 1)) << 64;                      \
            g_ = (big) - p_;                                                \
            if (g_ >= (small)) g_ -= (small);                               \
            else q_--;                                                      \
        }                                                                   \
        __uint128_t n0_ = (__uint128_t)q_ * (o0) + (c0);                    \
        if (n0_ >> 63) goto done;                                           \
        uint64_t c0n_ = (uint64_t)n0_;                                      \
        uint64_t c1n_ = q_ * (o1) + (c1);        /* <= c0n_ */              \
        uint64_t neg_ = (neg0) ? c0n_ : c1n_;                               \
        uint64_t sum_ = (neg0) ? (o1) + c1n_ : (o0) + c0n_;                 \
        if (!(uint64_t)(g_ >> 64) && (uint64_t)g_ < neg_) goto done;        \
        __uint128_t d_ = (small) - g_;                                      \
        if (!(uint64_t)(d_ >> 64) && (uint64_t)d_ < sum_) goto done;        \
        (big) = g_;                                                         \
        (c0) = c0n_;                                                        \
        (c1) = c1n_;                                                        \
        steps++;                                                            \
    } while (0)

/* a >= b, a normalized (bit 127 set).  Returns the number of exact Euclid
 * steps encoded in m = {u00, u01, u10, u11}; zero means the leading window
 * could not certify even one step (equal tops, b below 2^64, or a first
 * quotient beyond one limb) and the caller falls back. */
static BN_GCD_PROFILE_ATTR int gcd_hgcd2_simulate(
    uint64_t ah, uint64_t al, uint64_t bh, uint64_t bl, uint64_t m[4]) {
    __uint128_t a = ((__uint128_t)ah << 64) | al;
    __uint128_t b = ((__uint128_t)bh << 64) | bl;
    uint64_t u00 = 1, u01 = 0, u10 = 0, u11 = 1;
    int steps = 0;
    for (;;) {
        /* a -= q b: column 1 += q * column 0; alpha' = u11' a - u01' b. */
        GCD_HGCD2_HALF_STEP(a, b, u01, u11, u00, u10, 1);
        /* b -= q a: column 0 += q * column 1; beta' = u00' b - u10' a. */
        GCD_HGCD2_HALF_STEP(b, a, u00, u10, u01, u11, 0);
    }
done:
    m[0] = u00;
    m[1] = u01;
    m[2] = u10;
    m[3] = u11;
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_sim_calls++;
    gcd_profile_sim_steps += (uint64_t)steps;
#endif
    return steps;
}
#undef GCD_HGCD2_HALF_STEP

/* Leading 128 bits of x (normalized) and the bits of y at the same
 * positions; y may be shorter (zero-extended). */
static inline int gcd_hgcd2_magnitudes(
    const uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen, uint64_t m[4]) {
    int32_t top = xlen - 1;
    int lz = __builtin_clzll(x[top]);
    uint64_t x1 = x[top], x0 = x[top - 1];
    uint64_t xm = top > 1 ? x[top - 2] : 0;
    uint64_t y1 = top < ylen ? y[top] : 0;
    uint64_t y0 = top - 1 < ylen ? y[top - 1] : 0;
    uint64_t ym = top > 1 && top - 2 < ylen ? y[top - 2] : 0;
    uint64_t ah = (x1 << lz) | (lz ? x0 >> (64 - lz) : 0);
    uint64_t al = (x0 << lz) | (lz ? xm >> (64 - lz) : 0);
    uint64_t bh = (y1 << lz) | (lz ? y0 >> (64 - lz) : 0);
    uint64_t bl = (y0 << lz) | (lz ? ym >> (64 - lz) : 0);
    return gcd_hgcd2_simulate(ah, al, bh, bl, m);
}
#endif

/* Apply both rows of a Lehmer matrix in one pass:
 *
 *   rx = ux*x - vx*y
 *   ry = uy*y - vy*x
 *
 * Both inputs have zero-filled normalized tails through n limbs. */
static int mag_linear_comb_pair_core_ref(
    uint64_t *rx, uint64_t *ry, int32_t n,
    const uint64_t *x, const uint64_t *y,
    const uint64_t coeff[4]) {
    uint64_t ux = coeff[0], vx = coeff[1], uy = coeff[2], vy = coeff[3];
    __uint128_t cux = 0, cvy = 0, cuy = 0, cvx = 0;
    uint64_t bx = 0, by = 0;
    for (int32_t i = 0; i < n; i++) {
        uint64_t xi = x[i];
        uint64_t yi = y[i];
        cux += (__uint128_t)ux * xi;
        cvy += (__uint128_t)vx * yi;
        cuy += (__uint128_t)uy * yi;
        cvx += (__uint128_t)vy * xi;

        uint64_t x0 = (uint64_t)cux - (uint64_t)cvy;
        uint64_t xb0 = (uint64_t)cux < (uint64_t)cvy;
        uint64_t x1 = x0 - bx;
        uint64_t xb1 = x0 < bx;
        rx[i] = x1;
        bx = xb0 | xb1;

        uint64_t y0 = (uint64_t)cuy - (uint64_t)cvx;
        uint64_t yb0 = (uint64_t)cuy < (uint64_t)cvx;
        uint64_t y1 = y0 - by;
        uint64_t yb1 = y0 < by;
        ry[i] = y1;
        by = yb0 | yb1;

        cux >>= 64;
        cvy >>= 64;
        cuy >>= 64;
        cvx >>= 64;
    }
    return cux == cvy + bx && cuy == cvx + by;
}

#ifndef BN_GCD_SERIAL_ROW_SCHEDULE
#define BN_GCD_SERIAL_ROW_SCHEDULE 1
#endif

#if defined(__aarch64__) && BN_GCD_SERIAL_ROW_SCHEDULE
/* One-pass pair update with a row-serial product schedule.  This variant uses
 * only caller-saved registers.  The fallback interleaved schedule below keeps
 * more products in flight but needs x19 and is slightly slower at 256 limbs. */
#define MAG_LINEAR_COMB_PAIR_SERIAL_STEP \
        "ldr x15, [x3], #8\n" \
        "ldr x16, [x4], #8\n" \
        "mul x12, x15, x5\n" \
        "umulh x17, x15, x5\n" \
        "mul x13, x16, x6\n" \
        "umulh x14, x16, x6\n" \
        "subs x12, x12, x13\n" \
        "sbc x17, x17, x14\n" \
        "asr x14, x9, #63\n" \
        "adds x12, x12, x9\n" \
        "adc x9, x17, x14\n" \
        "str x12, [x0], #8\n" \
        "mul x12, x16, x7\n" \
        "umulh x17, x16, x7\n" \
        "mul x13, x15, x8\n" \
        "umulh x14, x15, x8\n" \
        "subs x12, x12, x13\n" \
        "sbc x17, x17, x14\n" \
        "asr x14, x11, #63\n" \
        "adds x12, x12, x11\n" \
        "adc x11, x17, x14\n" \
        "str x12, [x1], #8\n"

__attribute__((naked, noinline, aligned(64)))
static int mag_linear_comb_pair_core(uint64_t *rx, uint64_t *ry, int32_t n,
                                     const uint64_t *x, const uint64_t *y,
                                     const uint64_t coeff[4]) {
    __asm__(
        "mov x17, x5\n"
        "ldp x5, x6, [x17]\n"
        "ldp x7, x8, [x17, #16]\n"
        "mov x9, xzr\n"
        "mov x11, xzr\n"
        "tbz w2, #0, 1f\n"
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        "1:\n"
        "tbz w2, #1, 2f\n"
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        "2:\n"
        "lsr w2, w2, #2\n"
        "cbz w2, 4f\n"
        "3:\n"
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        MAG_LINEAR_COMB_PAIR_SERIAL_STEP
        "subs w2, w2, #1\n"
        "b.ne 3b\n"
        "4:\n"
        "orr x9, x9, x11\n"
        "cmp x9, xzr\n"
        "cset w0, eq\n"
        "ret\n"
    );
}
#undef MAG_LINEAR_COMB_PAIR_SERIAL_STEP
#elif defined(__aarch64__)
/* Track each row as one signed carry:
 *
 *   t = positive_product - negative_product + signed_carry
 *
 * Its low limb is the output and its signed high limb is the next carry.
 * This replaces four independent unsigned carries plus two borrows, saving
 * four flag/materialization instructions per input limb. */
#ifndef BN_GCD_LINEAR_COMB_UNROLL
#define BN_GCD_LINEAR_COMB_UNROLL 4
#endif
#define MAG_LINEAR_COMB_PAIR_STEP \
        "ldr x15, [x3], #8\n" \
        "ldr x16, [x4], #8\n" \
        "mul x12, x15, x5\n" \
        "umulh x17, x15, x5\n" \
        "mul x13, x16, x6\n" \
        "umulh x19, x16, x6\n" \
        "mul x14, x16, x7\n" \
        "umulh x16, x16, x7\n" \
        "mul x10, x15, x8\n" \
        "umulh x15, x15, x8\n" \
        "adds x12, x12, x9\n" \
        "asr x9, x9, #63\n" \
        "adc x17, x17, x9\n" \
        "subs x12, x12, x13\n" \
        "sbc x9, x17, x19\n" \
        "str x12, [x0], #8\n" \
        "adds x14, x14, x11\n" \
        "asr x11, x11, #63\n" \
        "adc x16, x16, x11\n" \
        "subs x14, x14, x10\n" \
        "sbc x11, x16, x15\n" \
        "str x14, [x1], #8\n"

__attribute__((naked, noinline))
static int mag_linear_comb_pair_core(uint64_t *rx, uint64_t *ry, int32_t n,
                                     const uint64_t *x, const uint64_t *y,
                                     const uint64_t coeff[4]) {
    __asm__(
        "stp x19, x20, [sp, #-16]!\n"
        "mov x17, x5\n"
        "ldp x5, x6, [x17]\n"       /* ux, vx */
        "ldp x7, x8, [x17, #16]\n"  /* uy, vy */
        "mov x9, xzr\n"             /* signed carry rx */
        "mov x11, xzr\n"            /* signed carry ry */
#if BN_GCD_LINEAR_COMB_UNROLL == 2
        "lsr w20, w2, #1\n"
        "cbz w20, 2f\n"
        "1:\n"
        MAG_LINEAR_COMB_PAIR_STEP
        MAG_LINEAR_COMB_PAIR_STEP
        "subs w20, w20, #1\n"
        "b.ne 1b\n"
        "2:\n"
        "tbz w2, #0, 3f\n"
        MAG_LINEAR_COMB_PAIR_STEP
        "3:\n"
#elif BN_GCD_LINEAR_COMB_UNROLL == 4
        "tbz w2, #0, 1f\n"
        MAG_LINEAR_COMB_PAIR_STEP
        "1:\n"
        "tbz w2, #1, 2f\n"
        MAG_LINEAR_COMB_PAIR_STEP
        MAG_LINEAR_COMB_PAIR_STEP
        "2:\n"
        "lsr w20, w2, #2\n"
        "cbz w20, 4f\n"
        "3:\n"
        MAG_LINEAR_COMB_PAIR_STEP
        MAG_LINEAR_COMB_PAIR_STEP
        MAG_LINEAR_COMB_PAIR_STEP
        MAG_LINEAR_COMB_PAIR_STEP
        "subs w20, w20, #1\n"
        "b.ne 3b\n"
        "4:\n"
#else
#error "BN_GCD_LINEAR_COMB_UNROLL must be 2 or 4"
#endif
        "orr x9, x9, x11\n"
        "cmp x9, xzr\n"
        "cset w0, eq\n"
        "ldp x19, x20, [sp], #16\n"
        "ret\n"
    );
}
#undef MAG_LINEAR_COMB_PAIR_STEP
#else
#define mag_linear_comb_pair_core mag_linear_comb_pair_core_ref
#endif

#ifndef BN_GCD_TWO_STEP_REPLAY
#define BN_GCD_TWO_STEP_REPLAY 1
#endif
#ifndef BN_GCD_FUSED_REPLAY_SUBMUL
#define BN_GCD_FUSED_REPLAY_SUBMUL 1
#endif
#ifndef BN_GCD_FUSED_REPLAY_THRESHOLD
#define BN_GCD_FUSED_REPLAY_THRESHOLD 32
#endif

static int mag_linear_comb_pair(uint64_t *rx, uint64_t *ry, int32_t n,
                                const uint64_t *x, const uint64_t *y,
                                uint64_t ux, uint64_t vx,
                                uint64_t uy, uint64_t vy,
                                int32_t *rxlen, int32_t *rylen) {
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_pair_calls++;
    gcd_profile_pair_limbs += (uint64_t)n;
#endif
#if BN_GCD_TWO_STEP_REPLAY
    /* A 1-quotient Euclid step has either:
     *   rx = x - q*y, ry = y  (ux=1, vx=q, uy=1, vy=0, from gcd_hgcd2)
     * or
     *   rx = x, ry = y - q*x  (ux=1, vx=0, uy=1, vy=q, from odd-step Lehmer).
     * Handle both with one subtract/submul_1 and one memcpy instead of four
     * scalar products per limb. */
    if (ux == 1 && uy == 1 && (vx == 0 || vy == 0)) {
        uint64_t borrow = 0;
        if (vy == 0) {
            if (vx == 1) {
                borrow = bn_sub_n(rx, x, y, n);
            } else if (vx != 0) {
#if BN_GCD_FUSED_REPLAY_SUBMUL
                if (n >= BN_GCD_FUSED_REPLAY_THRESHOLD) {
                    borrow = bn_submul_from_1(rx, x, y, n, vx);
                } else {
                    memcpy(rx, x, (size_t)n * sizeof(uint64_t));
                    borrow = bn_submul_1(rx, y, n, vx);
                }
#else
                memcpy(rx, x, (size_t)n * sizeof(uint64_t));
                borrow = bn_submul_1(rx, y, n, vx);
#endif
            } else {
                memcpy(rx, x, (size_t)n * sizeof(uint64_t));
            }
            if (borrow) return 0;
            memcpy(ry, y, (size_t)n * sizeof(uint64_t));
        } else {
            if (vy == 1) {
                borrow = bn_sub_n(ry, y, x, n);
            } else {
#if BN_GCD_FUSED_REPLAY_SUBMUL
                if (n >= BN_GCD_FUSED_REPLAY_THRESHOLD) {
                    borrow = bn_submul_from_1(ry, y, x, n, vy);
                } else {
                    memcpy(ry, y, (size_t)n * sizeof(uint64_t));
                    borrow = bn_submul_1(ry, x, n, vy);
                }
#else
                memcpy(ry, y, (size_t)n * sizeof(uint64_t));
                borrow = bn_submul_1(ry, x, n, vy);
#endif
            }
            if (borrow) return 0;
            memcpy(rx, x, (size_t)n * sizeof(uint64_t));
        }
        *rxlen = mag_norm_len(rx, n);
        *rylen = mag_norm_len(ry, n);
        return 1;
    }
    /* A two-quotient Euclid matrix has the exact shape
     *
     *   [ 1,             -q1 ]
     *   [ -q2, 1 + q1 * q2 ].
     *
     * Replaying its two rows sequentially replaces four scalar products per
     * limb with two multiply-subtracts (and q=1 becomes a plain subtract).
     * Borrow checks provide the same nonnegative-result guard as the generic
     * signed-carry kernel. */
    if (ux == 1 && vx != 0 && vy != 0 &&
        (__uint128_t)vx * vy + 1 == uy) {
        uint64_t borrow;
        if (vx == 1) {
            borrow = bn_sub_n(rx, x, y, n);
        } else {
#if BN_GCD_FUSED_REPLAY_SUBMUL
            if (n >= BN_GCD_FUSED_REPLAY_THRESHOLD) {
                borrow = bn_submul_from_1(rx, x, y, n, vx);
            } else {
                memcpy(rx, x, (size_t)n * sizeof(uint64_t));
                borrow = bn_submul_1(rx, y, n, vx);
            }
#else
            memcpy(rx, x, (size_t)n * sizeof(uint64_t));
            borrow = bn_submul_1(rx, y, n, vx);
#endif
        }
        if (borrow) return 0;
        if (vy == 1) {
            borrow = bn_sub_n(ry, y, rx, n);
        } else {
#if BN_GCD_FUSED_REPLAY_SUBMUL
            if (n >= BN_GCD_FUSED_REPLAY_THRESHOLD) {
                borrow = bn_submul_from_1(ry, y, rx, n, vy);
            } else {
                memcpy(ry, y, (size_t)n * sizeof(uint64_t));
                borrow = bn_submul_1(ry, rx, n, vy);
            }
#else
            memcpy(ry, y, (size_t)n * sizeof(uint64_t));
            borrow = bn_submul_1(ry, rx, n, vy);
#endif
        }
        if (borrow) return 0;
        *rxlen = mag_norm_len(rx, n);
        *rylen = mag_norm_len(ry, n);
        return 1;
    }
#endif
    uint64_t coeff[4] = {ux, vx, uy, vy};
    if (!mag_linear_comb_pair_core(rx, ry, n, x, y, coeff)) return 0;
    *rxlen = mag_norm_len(rx, n);
    *rylen = mag_norm_len(ry, n);
    return 1;
}

/* A leading-slice half-GCD block.  Lehmer's scalar matrix is excellent while its
 * entries fit one limb, but a full GCD still makes O(n) passes over n-limb
 * operands.  Reduce a leading slice, accumulate the inverse transform M with
 * arbitrary-size nonnegative entries, then apply M^-1 to the full operands
 * using four subquadratic multiplies.
 *
 * The leading slice can occasionally choose a quotient invalidated by the
 * omitted low limbs.  This is harmless: the exact full-width application is
 * accepted only when both signed differences are nonnegative and the maximum
 * operand size decreases.  Since det(M) is always +/-1, every accepted block
 * preserves gcd exactly. */
#ifndef BN_GCD_HGCD_THRESHOLD
#define BN_GCD_HGCD_THRESHOLD 768
#endif
#ifndef BN_GCD_HGCD_RECURSIVE_THRESHOLD
#define BN_GCD_HGCD_RECURSIVE_THRESHOLD 512
#endif
/* With the low-split row application (products against only the low p limbs
 * plus the shifted slice residue), quarter slices win at practical widths.
 * From 6K limbs, half slices amortize the four full-width row products over
 * twice as much reduction.  Choose that geometry once from the root capacity
 * and propagate it through the recursive chain; changing geometry after a
 * successful reduction loses the larger-slice advantage. */
#ifndef BN_GCD_HGCD_TOP_DEN
#define BN_GCD_HGCD_TOP_DEN 4
#endif
#ifndef BN_GCD_HGCD_HALF_THRESHOLD
#define BN_GCD_HGCD_HALF_THRESHOLD 6144
#endif
#ifndef BN_GCD_HGCD_APPLY_PAR_THRESHOLD
#define BN_GCD_HGCD_APPLY_PAR_THRESHOLD 768
#endif
#ifndef BN_GCD_HGCD_DEN5_THRESHOLD
#define BN_GCD_HGCD_DEN5_THRESHOLD 2048
#endif
#ifndef BN_GCD_HGCD_LARGE_DEN5_THRESHOLD
#define BN_GCD_HGCD_LARGE_DEN5_THRESHOLD 3072
#endif
#ifndef BN_GCD_HGCD_RECURSIVE_DEN_THRESHOLD
#define BN_GCD_HGCD_RECURSIVE_DEN_THRESHOLD 6144
#endif

static inline int gcd_hgcd_top_den(int32_t n) {
    if (n < BN_GCD_HGCD_DEN5_THRESHOLD) return BN_GCD_HGCD_TOP_DEN;
    if (n < BN_GCD_HGCD_LARGE_DEN5_THRESHOLD) return 8;
    if (n < BN_GCD_HGCD_RECURSIVE_DEN_THRESHOLD) return 5;
    return 6;
}

static inline int gcd_hgcd_work_den(int32_t n) {
    return n >= BN_GCD_HGCD_HALF_THRESHOLD ? 2 : BN_GCD_HGCD_TOP_DEN;
}

/* Matrix caps carry 12 limbs of slack: the first block of a GCD runs at
 * xlen == cap, where a full half-slice reduction produces entries within a
 * couple of limbs of hcap/2, and a tight cap makes the final tree multiply
 * overflow and discard the entire block. */
static size_t gcd_hgcd_level_ws_need(int32_t cap, int work_den) {
    int32_t hcap = (cap + work_den - 1) / work_den;
    int32_t mcap = (hcap + 1) / 2 + 12;
    int32_t pcap = cap + mcap + 2;
    int32_t max_matrices = 2 * hcap;
    int depth = 0;
    for (int32_t n = max_matrices; n > 1; n = (n + 1) / 2) depth++;
    size_t tree_stride = (size_t)12 * mcap + 2;
    return (size_t)4 * hcap
         + (size_t)4 * max_matrices
         + (size_t)12 * mcap
         + tree_stride * (size_t)depth
         + (size_t)4 * pcap;
}

static size_t gcd_hgcd_ws_need(int32_t cap, int work_den) {
    size_t total = gcd_hgcd_level_ws_need(cap, work_den);
    int32_t hcap = (cap + work_den - 1) / work_den;
    if (hcap >= BN_GCD_HGCD_RECURSIVE_THRESHOLD)
        total += gcd_hgcd_ws_need(hcap, work_den);
    return total;
}

static int32_t gcd_matrix_product(uint64_t *out,
                                  const uint64_t *a, int32_t an,
                                  const uint64_t *b, int32_t bn) {
    if (an == 0 || bn == 0) return 0;
    /* The product tree's lower levels are dominated by 1x1 and 2x1 leaves;
     * skip the general multiply dispatch for them. */
    if (an == 1 && bn == 1) {
        __uint128_t prod = (__uint128_t)a[0] * b[0];
        uint64_t hi = (uint64_t)(prod >> 64);
        out[0] = (uint64_t)prod;
        out[1] = hi;
        return hi ? 2 : 1;
    }
    if (bn == 1) {
        uint64_t c = bn_mul_1(out, a, an, b[0]);
        out[an] = c;
        return c ? an + 1 : mag_norm_len(out, an);
    }
    if (an == 1) {
        uint64_t c = bn_mul_1(out, b, bn, a[0]);
        out[bn] = c;
        return c ? bn + 1 : mag_norm_len(out, bn);
    }
#ifdef BN_GCD_PROFILE_COUNTS
    int32_t width = an > bn ? an : bn;
    int bin = 0;
    while (width > 1 && bin < 11) {
        width = (width + 1) >> 1;
        bin++;
    }
    gcd_profile_matrix_products++;
    gcd_profile_matrix_product_work += (uint64_t)an * (uint64_t)bn;
    gcd_profile_matrix_product_bins[bin]++;
    gcd_profile_ctx_work[gcd_profile_ctx] += (uint64_t)an * (uint64_t)bn;
#endif
    if (an <= BN_KARA_THRESHOLD || bn <= BN_KARA_THRESHOLD) {
        bigint_mul_schoolbook_into(out, a, an, b, bn);
        return mag_norm_len(out, an + bn);
    }
    bigint_mul_dispatch(out, a, an, b, bn);
    return mag_norm_len(out, an + bn);
}

static int32_t gcd_matrix_add_products(uint64_t *out, int32_t cap,
                                       uint64_t *a, int32_t an,
                                       uint64_t *b, int32_t bn) {
    int32_t n = an > bn ? an : bn;
    if (n == 0) return 0;
    if (n >= cap) return -1;
    if (an < n) memset(a + an, 0, (size_t)(n - an) * sizeof(uint64_t));
    if (bn < n) memset(b + bn, 0, (size_t)(n - bn) * sizeof(uint64_t));
    uint64_t carry = bn_add_n(out, a, b, n);
    if (carry) out[n++] = carry;
    return n;
}

static int gcd_matrix_multiply(uint64_t *out[4], int32_t ol[4],
                               uint64_t *left[4], const int32_t ll[4],
                               uint64_t *right[4], const int32_t rl[4],
                               int32_t cap, uint64_t *p0, uint64_t *p1) {
    int32_t min_l = ll[0];
    for (int i = 1; i < 4; i++) if (ll[i] < min_l) min_l = ll[i];
    for (int i = 0; i < 4; i++) if (rl[i] < min_l) min_l = rl[i];
    if (min_l >= 64) {
        int fits = 1;
        for (int row = 0; row < 2; row++) {
            for (int col = 0; col < 2; col++) {
                if (ll[2 * row] + rl[col] > cap ||
                    ll[2 * row + 1] + rl[2 + col] > cap)
                    fits = 0;
            }
        }
        if (fits) {
            WToomPointSet products;
            bn_toom_no_spin++;
            bn_toom_product_set_init(&products, 8, 4);
            bn_toom_no_spin--;
            if (products.parallel) {
                for (int row = 0; row < 2; row++) {
                    for (int col = 0; col < 2; col++) {
                        int oi = 2 * row + col;
                        uint64_t *b0 = p0 + (size_t)(2 * oi) * cap;
                        uint64_t *b1 = p0 + (size_t)(2 * oi + 1) * cap;
                        bn_toom_product_set_add(
                            &products, b0, left[2 * row], ll[2 * row],
                            right[col], rl[col]);
                        bn_toom_product_set_add(
                            &products, b1, left[2 * row + 1], ll[2 * row + 1],
                            right[2 + col], rl[2 + col]);
                    }
                }
                bn_toom_point_set_run(&products);
                for (int row = 0; row < 2; row++) {
                    for (int col = 0; col < 2; col++) {
                        int oi = 2 * row + col;
                        uint64_t *b0 = p0 + (size_t)(2 * oi) * cap;
                        uint64_t *b1 = p0 + (size_t)(2 * oi + 1) * cap;
                        int32_t n0 = mag_norm_len(b0, ll[2 * row] + rl[col]);
                        int32_t n1 = mag_norm_len(
                            b1, ll[2 * row + 1] + rl[2 + col]);
                        ol[oi] = gcd_matrix_add_products(
                            out[oi], cap, b0, n0, b1, n1);
                        if (ol[oi] < 0) return 0;
                    }
                }
                return 1;
            }
        }
    }
    for (int row = 0; row < 2; row++) {
        for (int col = 0; col < 2; col++) {
            int oi = 2 * row + col;
            int32_t n0 = gcd_matrix_product(
                p0, left[2 * row], ll[2 * row],
                right[col], rl[col]);
            int32_t n1 = gcd_matrix_product(
                p1, left[2 * row + 1], ll[2 * row + 1],
                right[2 + col], rl[2 + col]);
            ol[oi] = gcd_matrix_add_products(out[oi], cap, p0, n0, p1, n1);
            if (ol[oi] < 0) return 0;
        }
    }
    return 1;
}

/* Ordered product of scalar 2x2 matrices.  Each recursion level owns fixed
 * output and product slices; normalized prefixes alone reach multiplication. */
static int gcd_matrix_product_tree(const uint64_t *leaves, int32_t count,
                                   uint64_t *out[4], int32_t ol[4],
                                   int32_t cap, uint64_t *scratch) {
    if (count == 1) {
        for (int i = 0; i < 4; i++) {
            uint64_t v = leaves[i];
            if (v) out[i][0] = v;
            ol[i] = v != 0;
        }
        return 1;
    }
    if (count == 2) {
        const uint64_t *l = leaves;
        const uint64_t *r = leaves + 4;
        for (int row = 0; row < 2; row++) {
            for (int col = 0; col < 2; col++) {
                int oi = 2 * row + col;
                __uint128_t pr0 = (__uint128_t)l[2 * row] * r[col];
                __uint128_t pr1 = (__uint128_t)l[2 * row + 1] * r[2 + col];
                __uint128_t sum = pr0 + pr1;
                uint64_t c = sum < pr0;
                uint64_t lo = (uint64_t)sum;
                uint64_t hi = (uint64_t)(sum >> 64);
                if (c) {
                    if (cap < 3) return 0;
                    out[oi][0] = lo;
                    out[oi][1] = hi;
                    out[oi][2] = 1;
                    ol[oi] = 3;
                } else if (hi) {
                    if (cap < 2) return 0;
                    out[oi][0] = lo;
                    out[oi][1] = hi;
                    ol[oi] = 2;
                } else if (lo) {
                    if (cap < 1) return 0;
                    out[oi][0] = lo;
                    ol[oi] = 1;
                } else {
                    ol[oi] = 0;
                }
            }
        }
        return 1;
    }
    int32_t left_count = count / 2;
    int32_t right_count = count - left_count;
    uint64_t *left[4] = {
        scratch, scratch + cap, scratch + 2 * cap, scratch + 3 * cap
    };
    uint64_t *right[4] = {
        scratch + 4 * cap, scratch + 5 * cap,
        scratch + 6 * cap, scratch + 7 * cap
    };
    uint64_t *p0 = scratch + 8 * cap;
    uint64_t *p1 = p0 + 2 * cap + 1;
    uint64_t *child = p1 + 2 * cap + 1;
    int32_t ll[4], rl[4];
    if (!gcd_matrix_product_tree(leaves, left_count, left, ll, cap, child) ||
        !gcd_matrix_product_tree(leaves + (size_t)4 * left_count,
                                 right_count, right, rl, cap, child))
        return 0;
    return gcd_matrix_multiply(out, ol, left, ll, right, rl, cap, p0, p1);
}

/* out = pc*low(pv) - nc*low(nv) + hi << (64*p), validated nonnegative.
 *
 * The block's reduced slice value IS the leading combination already:
 * hx_final = pc*slice(pv) - nc*slice(nv) exactly, because every batch applies
 * an exact unimodular map to the slice pair while the same matrices
 * accumulate into cur.  So the full-width row application only needs fresh
 * products against the LOW p limbs of each operand plus the shifted slice
 * residue -- at top_den 4 that is a quarter less multiplication work than
 * multiplying the whole operands. */
static int gcd_hgcd_finish_row_low(uint64_t *out, int32_t out_cap,
                                    uint64_t *p0, int32_t n0,
                                    uint64_t *p1, int32_t n1, int32_t p,
                                    const uint64_t *hi, int32_t hin,
                                    int32_t prod_cap, int32_t *out_len) {
    if (n0 > prod_cap || n1 > prod_cap) return 0;
    if (hin) {
        int32_t hi_end = p + hin;
        if (hi_end > prod_cap) return 0;
        if (n0 < hi_end) {
            memset(p0 + n0, 0, (size_t)(hi_end - n0) * sizeof(uint64_t));
            n0 = hi_end;
        }
        uint64_t carry = bn_add_n(p0 + p, p0 + p, hi, hin);
        int32_t i = p + hin;
        while (carry) {
            if (i >= n0) {
                if (i >= prod_cap) return 0;
                p0[i] = carry;
                n0 = i + 1;
                break;
            }
            uint64_t s = p0[i] + 1;
            p0[i] = s;
            carry = s == 0;
            i++;
        }
    }
    if (mag_cmp(p0, n0, p1, n1) < 0) return 0;
    int32_t n = n0 > n1 ? n0 : n1;
    if (n1 < n) memset(p1 + n1, 0, (size_t)(n - n1) * sizeof(uint64_t));
    if (n0 < n) memset(p0 + n0, 0, (size_t)(n - n0) * sizeof(uint64_t));
    if (bn_sub_n(p0, p0, p1, n)) return 0;
    n = mag_norm_len(p0, n);
    if (n > out_cap) return 0;
    if (n) memcpy(out, p0, (size_t)n * sizeof(uint64_t));
    memset(out + n, 0, (size_t)(out_cap - n) * sizeof(uint64_t));
    *out_len = n;
    return 1;
}

static int gcd_hgcd_apply_row_low(uint64_t *out, int32_t out_cap,
                                  const uint64_t *pc, int32_t pcn,
                                  const uint64_t *pv,
                                  const uint64_t *nc, int32_t ncn,
                                  const uint64_t *nv, int32_t p,
                                  const uint64_t *hi, int32_t hin,
                                  uint64_t *p0, uint64_t *p1,
                                  int32_t prod_cap, int32_t *out_len) {
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_ctx = 1;
#endif
    int32_t n0 = gcd_matrix_product(p0, pc, pcn, pv, mag_norm_len(pv, p));
    int32_t n1 = gcd_matrix_product(p1, nc, ncn, nv, mag_norm_len(nv, p));
    return gcd_hgcd_finish_row_low(out, out_cap, p0, n0, p1, n1, p,
                                   hi, hin, prod_cap, out_len);
}

static int gcd_hgcd_block(const uint64_t *x, int32_t xlen,
                          const uint64_t *y, int32_t ylen,
                          uint64_t *rx, int32_t min_result,
                          uint64_t *ry, int32_t cap,
                          uint64_t *mem, int32_t *rxlen, int32_t *rylen,
                          uint64_t *out_matrix[4], int32_t out_ml[4],
                          int *out_det, int allow_recursive, int work_den) {
    /* allow_recursive is a remaining recursion depth: children run with
     * allow_recursive - 1, and 0 forces a pure scalar block (also used by
     * the failure-retry paths).  Depth in practice is bounded by geometry:
     * each level's slice is at least 2x smaller, and levels below
     * BN_GCD_HGCD_RECURSIVE_THRESHOLD never engage children -- the
     * recursive gcd_hgcd_ws_need provisions exactly that chain. */
    /* Recursive blocks retain the root geometry so every slice fits the
     * recursively provisioned workspace and the large-width half-slice win
     * survives later reductions.  The eighth/fifth/sixth ladder is only a
     * fallback for a scalar retry after a recursive application fails. */
    int top_den = allow_recursive > 0 ? work_den : gcd_hgcd_top_den(xlen);
    int32_t p = (int32_t)(((int64_t)(top_den - 1) * xlen) / top_den);
    int32_t h = xlen - p;
    int32_t hcap = (cap + work_den - 1) / work_den;
    int32_t mcap = (hcap + 1) / 2 + 12;
    int32_t prod_cap = cap + mcap + 2;
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_block_calls[allow_recursive ? 1 : 0]++;
#endif
    if (h < 8 || ylen <= p) { GCD_PROF_FAIL(0); return 0; }

    uint64_t *hx = mem;
    uint64_t *hy = hx + hcap;
    uint64_t *hnx = hy + hcap;
    uint64_t *hny = hnx + hcap;
    int32_t max_matrices = 2 * hcap;
    uint64_t *leaves = hny + hcap;
    uint64_t *matrix = leaves + (size_t)4 * max_matrices;
    uint64_t *acc[4] = {
        matrix, matrix + mcap, matrix + 2 * mcap, matrix + 3 * mcap
    };
    uint64_t *step_matrix = matrix + 4 * mcap;
    uint64_t *step[4] = {
        step_matrix, step_matrix + mcap,
        step_matrix + 2 * mcap, step_matrix + 3 * mcap
    };
    uint64_t *tmp_matrix = matrix + 8 * mcap;
    uint64_t *tmp[4] = {
        tmp_matrix, tmp_matrix + mcap,
        tmp_matrix + 2 * mcap, tmp_matrix + 3 * mcap
    };
    int depth = 0;
    for (int32_t z = max_matrices; z > 1; z = (z + 1) / 2) depth++;
    size_t tree_stride = (size_t)12 * mcap + 2;
    uint64_t *tree_scratch = matrix + 12 * mcap;
    uint64_t *prod0 = tree_scratch + tree_stride * (size_t)depth;
    uint64_t *prod1 = prod0 + prod_cap;
    uint64_t *prod2 = prod1 + prod_cap;
    uint64_t *prod3 = prod2 + prod_cap;
    uint64_t *child_mem = mem + gcd_hgcd_level_ws_need(cap, work_den);

    /* hx is overwritten across its full live slice, and every producer of
     * hnx/hny returns explicit lengths.  Only hy's short high slice needs a
     * zero tail; clearing four capacity-sized buffers here was dead work. */
    memcpy(hx, x + p, (size_t)(xlen - p) * sizeof(uint64_t));
    int32_t yh = ylen - p;
    memcpy(hy, y + p, (size_t)yh * sizeof(uint64_t));
    if (yh < h)
        memset(hy + yh, 0, (size_t)(h - yh) * sizeof(uint64_t));
    int32_t hxl = mag_norm_len(hx, h);
    int32_t hyl = mag_norm_len(hy, yh);
    if (!hyl || mag_cmp(hx, hxl, hy, hyl) < 0) { GCD_PROF_FAIL(1); return 0; }

    int det = 1;
    int success = 0;
    int have_acc = 0;
    int used_recursive = 0;
    int32_t al[4] = {0, 0, 0, 0};
    int32_t matrix_count = 0;
    int32_t target = h / 2 + 1;
    /* A caller with a tight remaining budget floors the result: reducing
     * past min_result would overshoot the caller's own validity margin. */
    if (min_result > p && min_result - p > target) target = min_result - p;

    /* Continue only while BOTH residues stay clear of the accumulated
     * matrix entries (~h - hxl limbs).  The full-width application computes
     * each row as products against the low limbs plus residue << 64*p; a
     * row is guaranteed nonnegative only while its residue outweighs its
     * negative coefficient, and the smaller residue hy is the one that gets
     * undershot when a batch lands a run of large quotients.  Stopping on
     * hxl alone left a ~2-limb margin that lumpy quotients overran in
     * 15-20% of blocks, and every overrun discarded the block's entire
     * slice reduction at the application step. */
    while (hxl > target && hyl > h - hxl + 4) {
        /* Delegate to a child block whenever one fits: a child reduces the
         * slice at slice-of-slice width, so every limb it removes costs a
         * fraction of a full-slice scalar batch.  The child's result floor
         * (target + 2) keeps it from overshooting the h/2 validity margin
         * that the final full-width application depends on; the +24 guard
         * leaves it enough budget to clear its own minimum progress. */
        if (allow_recursive && h >= BN_GCD_HGCD_RECURSIVE_THRESHOLD &&
            hxl > target + 24) {
            int32_t sl[4], hnxl, hnyl;
            int step_det;
            step[0] = step_matrix;
            step[1] = step_matrix + mcap;
            step[2] = step_matrix + 2 * mcap;
            step[3] = step_matrix + 3 * mcap;
            /* The total transform is an ordered product.  Any scalar leaves
             * accumulated since the last merge must fold into acc BEFORE a
             * child contributes its matrix; leaves left pending here would
             * be folded after the child at block end, corrupting the order
             * (and with it the slice-residue identity the final full-width
             * application depends on). */
            if (matrix_count) {
                if (!have_acc) {
                    if (!gcd_matrix_product_tree(leaves, matrix_count,
                                                 acc, al, mcap,
                                                 tree_scratch)) {
                        GCD_PROF_FAIL(2);
                        return 0;
                    }
                    have_acc = 1;
                } else {
                    int32_t fl[4], tl[4];
                    if (!gcd_matrix_product_tree(leaves, matrix_count,
                                                 step, fl, mcap,
                                                 tree_scratch)) {
                        GCD_PROF_FAIL(2);
                        return 0;
                    }
                    if (!gcd_matrix_multiply(tmp, tl, acc, al, step, fl,
                                             mcap, prod0, prod1)) {
                        GCD_PROF_FAIL(2);
                        return 0;
                    }
                    for (int i = 0; i < 4; i++) {
                        uint64_t *ht = acc[i];
                        acc[i] = tmp[i];
                        tmp[i] = ht;
                        al[i] = tl[i];
                    }
                }
                matrix_count = 0;
            }
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_child_calls++;
            uint64_t prof_child_prev = (uint64_t)hxl;
#endif
            if (gcd_hgcd_block(hx, hxl, hy, hyl, hnx, target + 2,
                               hny, hcap,
                               child_mem, &hnxl, &hnyl,
                               step, sl, &step_det,
                               allow_recursive - 1, work_den)) {
#ifdef BN_GCD_PROFILE_COUNTS
                gcd_profile_child_ok++;
                gcd_profile_child_removed +=
                    prof_child_prev - (uint64_t)(hnxl > hnyl ? hnxl : hnyl);
#endif
                uint64_t *ht = hx; hx = hnx; hnx = ht;
                ht = hy; hy = hny; hny = ht;
                hxl = hnxl;
                hyl = hnyl;
                if (mag_cmp(hx, hxl, hy, hyl) < 0) {
                    ht = hx; hx = hy; hy = ht;
                    int32_t lt = hxl; hxl = hyl; hyl = lt;
                    ht = step[0]; step[0] = step[1]; step[1] = ht;
                    ht = step[2]; step[2] = step[3]; step[3] = ht;
                    lt = sl[0]; sl[0] = sl[1]; sl[1] = lt;
                    lt = sl[2]; sl[2] = sl[3]; sl[3] = lt;
                    step_det = -step_det;
                }
                if (!have_acc) {
                    for (int i = 0; i < 4; i++) {
                        if (sl[i])
                            memcpy(acc[i], step[i],
                                   (size_t)sl[i] * sizeof(uint64_t));
                        al[i] = sl[i];
                    }
                    have_acc = 1;
                } else {
                    int32_t tl[4];
#ifdef BN_GCD_PROFILE_COUNTS
                    gcd_profile_ctx = 2;
#endif
                    if (!gcd_matrix_multiply(tmp, tl, acc, al, step, sl,
                                             mcap, prod0, prod1)) {
                        GCD_PROF_FAIL(2);
                        return 0;
                    }
                    for (int i = 0; i < 4; i++) {
                        ht = acc[i]; acc[i] = tmp[i]; tmp[i] = ht;
                        al[i] = tl[i];
                    }
                }
                det *= step_det;
                success = 1;
                used_recursive = 1;
                continue;
            }
        }

#if BN_GCD_HGCD2
        if (hxl >= BN_GCD_HGCD2_MIN_LIMBS) {
            uint64_t m[4];
            int h2_steps = gcd_hgcd2_magnitudes(hx, hxl, hy, hyl, m);
            if (h2_steps > 0) {
#ifdef BN_GCD_PROFILE_COUNTS
                gcd_profile_block_batches[allow_recursive ? 1 : 0]++;
                gcd_profile_block_batch_limbs[allow_recursive ? 1 : 0] +=
                    (uint64_t)hxl;
#endif
                int32_t hnxl, hnyl;
                int valid;
                if (!(h2_steps & 1)) {
                    valid = mag_linear_comb_pair(
                        hnx, hny, hxl, hx, hy,
                        m[3], m[1], m[0], m[2], &hnxl, &hnyl);
                } else {
                    valid = mag_linear_comb_pair(
                        hny, hnx, hxl, hx, hy,
                        m[3], m[1], m[0], m[2], &hnyl, &hnxl);
                }
                if (valid) {
                    if (matrix_count >= max_matrices) { GCD_PROF_FAIL(2); return 0; }
                    uint64_t *leaf = leaves + (size_t)4 * matrix_count++;
                    if (!(h2_steps & 1)) {
                        leaf[0] = m[0]; leaf[1] = m[1];
                        leaf[2] = m[2]; leaf[3] = m[3];
                    } else {
                        leaf[0] = m[1]; leaf[1] = m[0];
                        leaf[2] = m[3]; leaf[3] = m[2];
                        det = -det;
                    }
                    uint64_t *ht = hx; hx = hnx; hnx = ht;
                    ht = hy; hy = hny; hny = ht;
                    hxl = hnxl;
                    hyl = hnyl;
                    if (mag_cmp(hx, hxl, hy, hyl) < 0) {
                        ht = hx; hx = hy; hy = ht;
                        int32_t lt = hxl; hxl = hyl; hyl = lt;
                        uint64_t t0 = leaf[0], t2 = leaf[2];
                        leaf[0] = leaf[1]; leaf[1] = t0;
                        leaf[2] = leaf[3]; leaf[3] = t2;
                        det = -det;
                    }
                    success = 1;
                    continue;
                }
            }
        }
#endif

        int64_t A, B, C, D;
        int steps = lehmer_simulate_magnitudes(
            hx, hxl, hy, hyl, &A, &B, &C, &D);
        if (!steps) break;
#ifdef BN_GCD_PROFILE_COUNTS
        gcd_profile_block_batches[allow_recursive ? 1 : 0]++;
        gcd_profile_block_batch_limbs[allow_recursive ? 1 : 0] +=
            (uint64_t)hxl;
#endif
        int32_t hnxl, hnyl;
        int valid;
        if (!(steps & 1)) {
            valid = mag_linear_comb_pair(
                hnx, hny, hxl, hx, hy,
                (uint64_t)A, (uint64_t)(-B),
                (uint64_t)D, (uint64_t)(-C), &hnxl, &hnyl);
        } else {
            valid = mag_linear_comb_pair(
                hnx, hny, hxl, hy, hx,
                (uint64_t)B, (uint64_t)(-A),
                (uint64_t)C, (uint64_t)(-D), &hnxl, &hnyl);
        }
        if (!valid) break;

        uint64_t e00, e01, e10, e11;
        if (!(steps & 1)) {
            e00 = (uint64_t)D;    e01 = (uint64_t)(-B);
            e10 = (uint64_t)(-C); e11 = (uint64_t)A;
        } else {
            e00 = (uint64_t)(-D); e01 = (uint64_t)B;
            e10 = (uint64_t)C;    e11 = (uint64_t)(-A);
        }
        if (matrix_count >= max_matrices) { GCD_PROF_FAIL(2); return 0; }
        uint64_t *leaf = leaves + (size_t)4 * matrix_count++;
        leaf[0] = e00; leaf[1] = e01; leaf[2] = e10; leaf[3] = e11;
        det = (steps & 1) ? -det : det;
        uint64_t *ht = hx; hx = hnx; hnx = ht;
        ht = hy; hy = hny; hny = ht;
        hxl = hnxl;
        hyl = hnyl;
        if (mag_cmp(hx, hxl, hy, hyl) < 0) {
            ht = hx; hx = hy; hy = ht;
            int32_t lt = hxl; hxl = hyl; hyl = lt;
            uint64_t t0 = leaf[0], t2 = leaf[2];
            leaf[0] = leaf[1]; leaf[1] = t0;
            leaf[2] = leaf[3]; leaf[3] = t2;
            det = -det;
        }
        success = 1;
    }
    /* Accept partial reductions.  A batch invalidated by the omitted low
     * limbs near the slice's precision limit merely shortens the block; the
     * full-width application below still validates whatever prefix was
     * accumulated.  The bar is deliberately low: the slice work is already
     * spent, and applying a short matrix (4 products of ~removed/2 x p) is
     * far cheaper per removed limb than the caller's full-width scalar
     * fallback.  A proportional bar (h/8) discarded ~1000-batch reductions
     * over one late invalid batch, and each discard cost a quadratic
     * full-width cooldown -- the 8k->16k scaling cliff. */
    int32_t min_remove = 8;
    if (!success || hxl > h - min_remove) { GCD_PROF_FAIL(3); return 0; }
    uint64_t *cur[4];
    int32_t cl[4];
    if (matrix_count) {
        uint64_t *tail[4];
        if (have_acc) {
            tail[0] = step_matrix;
            tail[1] = step_matrix + mcap;
            tail[2] = step_matrix + 2 * mcap;
            tail[3] = step_matrix + 3 * mcap;
        } else {
            for (int i = 0; i < 4; i++) tail[i] = acc[i];
        }
        int32_t tl[4];
#ifdef BN_GCD_PROFILE_COUNTS
        gcd_profile_ctx = 0;
#endif
        if (!gcd_matrix_product_tree(leaves, matrix_count, tail, tl,
                                     mcap, tree_scratch)) {
            GCD_PROF_FAIL(2);
            return 0;
        }
        if (have_acc) {
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_ctx = 2;
#endif
            if (!gcd_matrix_multiply(tmp, cl, acc, al, tail, tl,
                                     mcap, prod0, prod1)) {
                GCD_PROF_FAIL(2);
                return 0;
            }
            for (int i = 0; i < 4; i++) cur[i] = tmp[i];
        } else {
            for (int i = 0; i < 4; i++) {
                cur[i] = acc[i];
                cl[i] = tl[i];
            }
        }
    } else {
        if (!have_acc) { GCD_PROF_FAIL(3); return 0; }
        for (int i = 0; i < 4; i++) {
            cur[i] = acc[i];
            cl[i] = al[i];
        }
    }
    int ok;
    if (xlen >= BN_GCD_HGCD_APPLY_PAR_THRESHOLD) {
        int32_t xn = mag_norm_len(x, p);
        int32_t yn = mag_norm_len(y, p);
        const uint64_t *pc[4];
        const uint64_t *pv[4];
        int32_t pcn[4], pvn[4];
        if (det > 0) {
            pc[0] = cur[3]; pcn[0] = cl[3]; pv[0] = x; pvn[0] = xn;
            pc[1] = cur[1]; pcn[1] = cl[1]; pv[1] = y; pvn[1] = yn;
            pc[2] = cur[0]; pcn[2] = cl[0]; pv[2] = y; pvn[2] = yn;
            pc[3] = cur[2]; pcn[3] = cl[2]; pv[3] = x; pvn[3] = xn;
        } else {
            pc[0] = cur[1]; pcn[0] = cl[1]; pv[0] = y; pvn[0] = yn;
            pc[1] = cur[3]; pcn[1] = cl[3]; pv[1] = x; pvn[1] = xn;
            pc[2] = cur[2]; pcn[2] = cl[2]; pv[2] = x; pvn[2] = xn;
            pc[3] = cur[0]; pcn[3] = cl[0]; pv[3] = y; pvn[3] = yn;
        }
        if (xn && yn && pcn[0] >= 16 && pcn[1] >= 16 &&
            pcn[2] >= 16 && pcn[3] >= 16) {
            WToomPointSet products;
            /* Long serial hgcd spans separate these product bursts:
             * parking immediately beats burst-lingering here (the same
             * policy recursive division applies to its correction
             * products).  The budget is captured at init time. */
            bn_toom_no_spin++;
            bn_toom_product_set_init(&products, 4, 4);
            bn_toom_no_spin--;
            if (!products.parallel) goto sequential_apply;
            uint64_t *out[4] = {prod0, prod1, prod2, prod3};
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_ctx = 1;
            for (int i = 0; i < 4; i++) {
                int32_t width = pcn[i] > pvn[i] ? pcn[i] : pvn[i];
                int bin = 0;
                while (width > 1 && bin < 11) {
                    width = (width + 1) >> 1;
                    bin++;
                }
                gcd_profile_matrix_products++;
                gcd_profile_matrix_product_work +=
                    (uint64_t)pcn[i] * (uint64_t)pvn[i];
                gcd_profile_matrix_product_bins[bin]++;
                gcd_profile_ctx_work[1] +=
                    (uint64_t)pcn[i] * (uint64_t)pvn[i];
            }
#endif
            for (int i = 0; i < 4; i++)
                bn_toom_product_set_add(&products, out[i], pc[i], pcn[i],
                                        pv[i], pvn[i]);
            bn_toom_point_set_run(&products);
            int32_t pn[4];
            for (int i = 0; i < 4; i++)
                pn[i] = mag_norm_len(out[i], pcn[i] + pvn[i]);
            ok = gcd_hgcd_finish_row_low(rx, cap, prod0, pn[0],
                                         prod1, pn[1], p, hx, hxl,
                                         prod_cap, rxlen)
              && gcd_hgcd_finish_row_low(ry, cap, prod2, pn[2],
                                         prod3, pn[3], p, hy, hyl,
                                         prod_cap, rylen);
            goto apply_done;
        }
    }
sequential_apply:
    if (det > 0) {
        ok = gcd_hgcd_apply_row_low(rx, cap, cur[3], cl[3], x,
                                    cur[1], cl[1], y, p, hx, hxl,
                                    prod0, prod1, prod_cap, rxlen)
          && gcd_hgcd_apply_row_low(ry, cap, cur[0], cl[0], y,
                                    cur[2], cl[2], x, p, hy, hyl,
                                    prod0, prod1, prod_cap, rylen);
    } else {
        ok = gcd_hgcd_apply_row_low(rx, cap, cur[1], cl[1], y,
                                    cur[3], cl[3], x, p, hx, hxl,
                                    prod0, prod1, prod_cap, rxlen)
          && gcd_hgcd_apply_row_low(ry, cap, cur[2], cl[2], x,
                                    cur[0], cl[0], y, p, hy, hyl,
                                    prod0, prod1, prod_cap, rylen);
    }
apply_done:
    if (!ok) GCD_PROF_FAIL(4);
    if (!ok && used_recursive)
        return gcd_hgcd_block(x, xlen, y, ylen, rx, min_result, ry, cap,
                              mem, rxlen, rylen,
                              out_matrix, out_ml, out_det, 0, work_den);
    if (!ok) return 0;
    int32_t out_max = *rxlen > *rylen ? *rxlen : *rylen;
    if (out_max >= xlen) GCD_PROF_FAIL(5);
    if (out_max >= xlen && used_recursive)
        return gcd_hgcd_block(x, xlen, y, ylen, rx, min_result, ry, cap,
                              mem, rxlen, rylen,
                              out_matrix, out_ml, out_det, 0, work_den);
    if (out_max >= xlen) return 0;
    if (out_matrix) {
        for (int i = 0; i < 4; i++) {
            if (cl[i])
                memcpy(out_matrix[i], cur[i],
                       (size_t)cl[i] * sizeof(uint64_t));
            out_ml[i] = cl[i];
        }
        *out_det = det;
    }
#ifdef BN_GCD_PROFILE_COUNTS
    gcd_profile_block_ok[allow_recursive ? 1 : 0]++;
    gcd_profile_block_removed[allow_recursive ? 1 : 0] +=
        (uint64_t)(xlen - out_max);
#endif
    return 1;
}

/* x -= y << d, in place. The caller guarantees y << d <= x. */
static void mag_sub_shifted(uint64_t *x, int32_t xlen,
                            const uint64_t *y, int32_t ylen, uint64_t d) {
    int32_t s = (int32_t)(d >> 6);
    int r = (int)(d & 63);
    if (r == 0) {
        int32_t room = xlen - s;
        int32_t count = ylen < room ? ylen : room;
        uint64_t borrow = bn_sub_n(x + s, x + s, y, count);
        for (int32_t i = s + count; borrow && i < xlen; i++) {
            uint64_t xi = x[i];
            x[i] = xi - 1;
            borrow = xi == 0;
        }
        return;
    }
    uint64_t borrow = 0;
    uint64_t carry_bits = 0;
    for (int32_t i = 0; i <= ylen && s + i < xlen; i++) {
        uint64_t yl = i < ylen ? y[i] : 0;
        uint64_t sub = r ? ((yl << r) | carry_bits) : yl;
        if (r) carry_bits = yl >> (64 - r);
        uint64_t xi = x[s + i];
        uint64_t d1 = xi - sub;
        uint64_t b1 = xi < sub;
        uint64_t d2 = d1 - borrow;
        uint64_t b2 = d1 < borrow;
        x[s + i] = d2;
        borrow = b1 | b2;
    }
    for (int32_t i = s + ylen + 1; borrow && i < xlen; i++) {
        uint64_t xi = x[i];
        x[i] = xi - 1;
        borrow = xi == 0;
    }
}

/* Fallback for shapes whose leading digits cannot batch. */
static BN_GCD_PROFILE_ATTR int32_t mag_mod_binary(
    uint64_t *x, int32_t xlen,
    const uint64_t *y, int32_t ylen) {
    for (;;) {
        xlen = mag_norm_len(x, xlen);
        if (mag_cmp(x, xlen, y, ylen) < 0) return xlen;
        int64_t d = mag_bitlen(x, xlen) - mag_bitlen(y, ylen);
        mag_sub_shifted(x, xlen, y, ylen, d > 0 ? (uint64_t)(d - 1) : 0);
    }
}
#undef BN_GCD_PROFILE_ATTR

static __thread uint64_t *gcd_ws = NULL;
static __thread size_t gcd_ws_cap = 0;
static uint64_t *gcd_ws_get(size_t limbs) {
    if (limbs > gcd_ws_cap) {
        free(gcd_ws);
        size_t ncap = limbs + limbs / 2 + 64;
        gcd_ws = (uint64_t *)malloc(ncap * sizeof(uint64_t));
        gcd_ws_cap = gcd_ws ? ncap : 0;
    }
    return gcd_ws;
}

static __attribute__((noinline))
WValue bigint_gcd_mag(const uint64_t *al, int32_t an,
                      const uint64_t *bl, int32_t bn) {
    if (an <= 1 && bn <= 1) {
        uint64_t av = an ? al[0] : 0;
        uint64_t bv = bn ? bl[0] : 0;
        uint64_t g = (av && bv) ? bn_gcd_u64_nonzero(av, bv) : (av | bv);
        if (g <= (uint64_t)W_INT48_MAX) return w_box_int((int64_t)g);
        WBigint *r = bigint_alloc_raw(1);
        r->limbs[0] = g;
        r->size = 1;
        return bigint_normalize(r);
    }
#if defined(__aarch64__) && BN_GCD_22_ASM
    if (an == 2 && bn == 2) {
        unsigned __int128 g =
            bn_gcd_22(al[1], al[0], bl[1], bl[0]);
        uint64_t hi = (uint64_t)(g >> 64);
        if (!hi) return bigint_from_u64((uint64_t)g);
        WBigint *r = bigint_alloc_raw(2);
        r->limbs[0] = (uint64_t)g;
        r->limbs[1] = hi;
        r->size = 2;
        return bigint_normalize(r);
    }
#endif
    int32_t cap = an > bn ? an : bn;
    int hgcd_work_den = gcd_hgcd_work_den(cap);
    size_t hgcd_need = cap >= BN_GCD_HGCD_THRESHOLD
        ? gcd_hgcd_ws_need(cap, hgcd_work_den) : 0;
    uint64_t *buf = gcd_ws_get((size_t)cap * 4 + hgcd_need);
    if (!buf) die("out of memory in bigint gcd");
    uint64_t *x = buf;
    uint64_t *y = buf + cap;
    uint64_t *nx = buf + 2 * (size_t)cap;
    uint64_t *ny = buf + 3 * (size_t)cap;
    int32_t xlen, ylen;
    if (mag_cmp(al, an, bl, bn) >= 0) {
        memcpy(x, al, (size_t)an * sizeof(uint64_t));
        memcpy(y, bl, (size_t)bn * sizeof(uint64_t));
        xlen = an;
        ylen = bn;
    } else {
        memcpy(x, bl, (size_t)bn * sizeof(uint64_t));
        memcpy(y, al, (size_t)an * sizeof(uint64_t));
        xlen = bn;
        ylen = an;
    }
    if (ylen < cap)
        memset(y + ylen, 0, (size_t)(cap - ylen) * sizeof(uint64_t));
    int32_t hgcd_retry_at = INT32_MAX;
    while (ylen > 1) {
        if (xlen >= BN_GCD_HGCD_THRESHOLD && xlen <= hgcd_retry_at) {
            int32_t nxl, nyl;
#ifdef BN_GCD_PROFILE_COUNTS
            gcd_profile_hgcd_top_calls++;
            gcd_profile_hgcd_top_xlen += (uint64_t)xlen;
#endif
            bn_toom_no_spin++;
            int hgcd_ok = gcd_hgcd_block(
                x, xlen, y, ylen, nx, 0, ny, cap,
                buf + (size_t)4 * cap, &nxl, &nyl,
                NULL, NULL, NULL, 8, hgcd_work_den);
            bn_toom_no_spin--;
            if (hgcd_ok) {
#ifdef BN_GCD_PROFILE_COUNTS
                gcd_profile_hgcd_top_ok++;
#endif
                uint64_t *t;
                int32_t tl;
                t = x; x = nx; nx = t;
                t = y; y = ny; ny = t;
                xlen = nxl;
                ylen = nyl;
                if (mag_cmp(x, xlen, y, ylen) < 0) {
                    t = x; x = y; y = t;
                    tl = xlen; xlen = ylen; ylen = tl;
                }
                hgcd_retry_at = INT32_MAX;
                continue;
            }
            /* One scalar batch rewrites the leading slice entirely, so a
             * retry is statistically independent after a couple of limbs of
             * progress.  A constant cooldown keeps the failure penalty O(n)
             * (a proportional xlen/8 cooldown made every failure cost
             * O(n^2/8) of full-width scalar work). */
            hgcd_retry_at = xlen - 8;
        }
        int64_t A, B, C, D;
        int steps;
#if BN_GCD_HGCD2
        if (xlen >= BN_GCD_HGCD2_MIN_LIMBS) {
            uint64_t m[4];
            int32_t nxl, nyl;
            /* alpha = u11 x - u01 y, beta = u00 y - u10 x. */
            int h2_steps = gcd_hgcd2_magnitudes(x, xlen, y, ylen, m);
            if (h2_steps > 0 &&
                (!(h2_steps & 1)
                    ? mag_linear_comb_pair(nx, ny, xlen, x, y,
                                           m[3], m[1], m[0], m[2], &nxl, &nyl)
                    : mag_linear_comb_pair(ny, nx, xlen, x, y,
                                           m[3], m[1], m[0], m[2], &nyl, &nxl))) {
                uint64_t *t;
                int32_t tl;
                t = x; x = nx; nx = t;
                t = y; y = ny; ny = t;
                xlen = nxl;
                ylen = nyl;
                if (mag_cmp(x, xlen, y, ylen) < 0) {
                    t = x; x = y; y = t;
                    tl = xlen; xlen = ylen; ylen = tl;
                }
                continue;
            }
        }
#endif
#if BN_GCD_SMALL_FAST_QUOTIENT_TWO
        if (xlen == 2)
            steps = lehmer_simulate_2_magnitudes(
                x, y, &A, &B, &C, &D);
        else if (xlen <= 4)
            steps = lehmer_simulate_small_magnitudes(
                x, xlen, y, ylen, &A, &B, &C, &D);
        else
#endif
            steps = lehmer_simulate_magnitudes(
                x, xlen, y, ylen, &A, &B, &C, &D);
        if (steps > 0) {
            int32_t nxl, nyl;
            int valid;
            if (!(steps & 1)) {
                valid = mag_linear_comb_pair(
                    nx, ny, xlen, x, y,
                    (uint64_t)A, (uint64_t)(-B),
                    (uint64_t)D, (uint64_t)(-C), &nxl, &nyl);
            } else {
                valid = mag_linear_comb_pair(
                    nx, ny, xlen, y, x,
                    (uint64_t)B, (uint64_t)(-A),
                    (uint64_t)C, (uint64_t)(-D), &nxl, &nyl);
            }
            if (valid) {
                uint64_t *t;
                int32_t tl;
                t = x; x = nx; nx = t;
                t = y; y = ny; ny = t;
                xlen = nxl;
                ylen = nyl;
                if (mag_cmp(x, xlen, y, ylen) < 0) {
                    t = x; x = y; y = t;
                    tl = xlen; xlen = ylen; ylen = tl;
                }
                continue;
            }
        }
        xlen = mag_mod_binary(x, xlen, y, ylen);
        uint64_t *t = x;
        x = y;
        y = t;
        int32_t tl = xlen;
        xlen = ylen;
        ylen = tl;
    }

    WValue result;
    if (ylen == 0) {
        /* Every result limb is replaced by the workspace copy below.  Raw
         * allocation preserves recycler give/take semantics without clearing
         * the retained capacity immediately before overwriting it. */
        WBigint *r = bigint_alloc_raw(xlen);
        memcpy(r->limbs, x, (size_t)xlen * sizeof(uint64_t));
        r->size = xlen;
        result = bigint_normalize(r);
    } else {
        uint64_t g = w_gcd_u64(mag_mod_u64(x, xlen, y[0]), y[0]);
        if (g <= (uint64_t)W_INT48_MAX) {
            result = w_box_int((int64_t)g);
        } else {
            WBigint *r = bigint_alloc_raw(1);
            r->limbs[0] = g;
            r->size = 1;
            result = bigint_normalize(r);
        }
    }
    return result;
}

WValue bigint_gcd_any_generic(WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *al = integer_limbs(a, &sa, &alen);
    const uint64_t *bl = integer_limbs(b, &sb, &blen);
    int32_t an = alen < 0 ? -alen : alen;
    int32_t bn = blen < 0 ? -blen : blen;

#if BN_TZ_STRIP
    /* gcd(x·B^m, y·B^m) = B^m·gcd(x, y): strip only the COMMON trailing
     * zero-limb count.  Full per-side stripping is invalid at limb
     * granularity — after the common strip the other operand may still be
     * even, so one side's excess factors of two can pair with it (e.g.
     * gcd(3·B, 6) = 6, not 3).  One never-taken branch on random
     * operands. */
    if (__builtin_expect(an > 1 && bn > 1 &&
                         (al[0] == 0 || bl[0] == 0), 0)) {
        int32_t za = 0;
        while (za < an && al[za] == 0) za++;
        int32_t zb = 0;
        while (zb < bn && bl[zb] == 0) zb++;
        int32_t m = za < zb ? za : zb;
        if (m > 0) {
            WValue g = bigint_gcd_mag(al + m, an - m, bl + m, bn - m);
            uint64_t sg;
            int32_t lg;
            const uint64_t *gl = integer_limbs(g, &sg, &lg);  /* gcd > 0 */
            WBigint *r = bigint_alloc_raw(lg + m);
            memset(r->limbs, 0, (size_t)m * sizeof(uint64_t));
            memcpy(r->limbs + m, gl, (size_t)lg * sizeof(uint64_t));
            r->size = lg + m;
            if (w_is_bigint(g)) bigint_release_if_live(w_as_bigint(g));
            return bigint_normalize(r);
        }
    }
#endif
    return bigint_gcd_mag(al, an, bl, bn);
}

#ifndef BN_GCD_BOXED_SMALL_FAST
#define BN_GCD_BOXED_SMALL_FAST 1
#endif

static inline __attribute__((always_inline))
WValue bigint_gcd_boxed_one_limb(const WBigint *a, const WBigint *b) {
    /* Normalized one-limb bigints guarantee limbs[0] != 0, so the zero checks
     * and the out-of-line call are pure overhead here. */
    uint64_t g = bn_gcd_u64_nonzero(a->limbs[0], b->limbs[0]);
    if (g <= (uint64_t)W_INT48_MAX) return w_box_int((int64_t)g);
    WBigint *r = bigint_alloc_raw(1);
    r->limbs[0] = g;
    r->size = 1;
    return bigint_normalize(r);
}

static inline __attribute__((always_inline))
WValue bigint_gcd_any_inline(WValue a, WValue b) {
#if BN_GCD_BOXED_SMALL_FAST
    if (w_is_bigint(a) && w_is_bigint(b)) {
        int32_t as, bs;
        WBigint *aa = w_bigint_view(a, &as);
        WBigint *bb = w_bigint_view(b, &bs);
#if BN_ALGEBRAIC_IDENTITY_FAST
        /* Both values are already known boxed.  Handle aliasing here so the
         * ordinary boxed-small lane does not first compare against every
         * mixed inline identity (zero and both signs of one). */
        if (a == b) return bigint_abs_alias(a);
#endif
        if (as == 1 && bs == 1)
            return bigint_gcd_boxed_one_limb(aa, bb);
        int32_t an = as < 0 ? -as : as;
        int32_t bn = bs < 0 ? -bs : bs;
        if (an == 1 && bn == 1)
            return bigint_gcd_boxed_one_limb(aa, bb);
        if (an <= 1 && bn <= 1) {
            uint64_t g = w_gcd_u64(
                an ? aa->limbs[0] : 0,
                bn ? bb->limbs[0] : 0);
            if (g <= (uint64_t)W_INT48_MAX)
                return w_box_int((int64_t)g);
            /* g > i48 with one limb: already canonical, no rescan/demotion. */
            WBigint *r = bigint_alloc_raw_hot(1);
            r->limbs[0] = g;
            r->size = 1;
            return bigint_box(r);
        }
#if defined(__aarch64__) && BN_GCD_22_ASM
        if (an == 2 && bn == 2) {
            unsigned __int128 g =
                bn_gcd_22(
                    aa->limbs[1], aa->limbs[0],
                    bb->limbs[1], bb->limbs[0]);
            uint64_t hi = (uint64_t)(g >> 64);
            if (!hi) return bigint_from_u64((uint64_t)g);
            /* hi != 0: two canonical limbs, no rescan/demotion. */
            WBigint *r = bigint_alloc_raw_hot(2);
            r->limbs[0] = (uint64_t)g;
            r->limbs[1] = hi;
            r->size = 2;
            return bigint_box(r);
        }
#endif
    }
#endif
#if BN_ALGEBRAIC_IDENTITY_FAST
#if !BN_GCD_BOXED_SMALL_FAST
    if (a == b && w_is_bigint(a))
        return bigint_abs_alias(a);
#endif
    if (b == w_box_int(0) && w_is_bigint(a))
        return bigint_abs_alias(a);
    if (a == w_box_int(0) && w_is_bigint(b))
        return bigint_abs_alias(b);
    if (a == w_box_int(1) || a == w_box_int(-1) ||
        b == w_box_int(1) || b == w_box_int(-1))
        return w_box_int(1);
#endif
    return bigint_gcd_any_generic(a, b);
}

/* Exported entry with external linkage for core/numeric/big_int.w's
 * `ccall("bigint_gcd_any", …)` — the always_inline copy above has none.
 * Internal hot paths keep calling the inline directly. */
WValue bigint_gcd_any(WValue a, WValue b) {
    return bigint_gcd_any_inline(a, b);
}



W_RT_INTERNAL uint64_t w_rt_bn_div_preinv_thread(uint64_t d) { return bn_div_preinv_cached(d, bn_div_preinv_thread_cache()); }
W_RT_INTERNAL uint64_t w_rt_bn_div_qr_preinv(uint64_t nh, uint64_t nl, uint64_t d, uint64_t dinv, uint64_t *rem) { return bn_div_qr_preinv(nh, nl, d, dinv, rem); }
W_RT_INTERNAL WBigint *w_rt_mag_div_single(const uint64_t *a, int32_t alen, uint64_t d, uint64_t *rem) { return mag_div_single(a, alen, d, rem); }
W_RT_INTERNAL int32_t w_rt_mag_div_single_to(uint64_t *q, const uint64_t *a, int32_t alen, uint64_t d, uint64_t *rem_out, BnDivPreinvCache *cache) { return mag_div_single_to(q, a, alen, d, rem_out, cache); }
W_RT_INTERNAL uint64_t w_rt_mag_mod_single(const uint64_t *a, int32_t alen, uint64_t d) { return mag_mod_single(a, alen, d); }
W_RT_INTERNAL WBigint *w_rt_mag_div_84(const uint64_t *u, const uint64_t *v, WBigint **r_out) { return mag_div_84(u, v, r_out); }
W_RT_INTERNAL WBigint *w_rt_mag_mod_63(const uint64_t *u, const uint64_t *v) { return mag_mod_63(u, v); }
W_RT_INTERNAL WBigint *w_rt_mag_mod_42(const uint64_t *u, const uint64_t *v) { return mag_mod_42(u, v); }
W_RT_INTERNAL void w_rt_mag_divmod(const uint64_t *u, int32_t ulen, const uint64_t *v, int32_t vlen, WBigint **q_out, WBigint **r_out) { mag_divmod(u, ulen, v, vlen, q_out, r_out); }
W_RT_INTERNAL WBigint *w_rt_mag_divexact(const uint64_t *np, int32_t nn, const uint64_t *dp, int32_t dn) { return mag_divexact(np, nn, dp, dn); }
W_RT_INTERNAL int32_t w_rt_mag_mod_binary(uint64_t *u, int32_t ulen, const uint64_t *v, int32_t vlen) { return mag_mod_binary(u, ulen, v, vlen); }
W_RT_INTERNAL uint64_t w_rt_bn_isqrt_u128(unsigned __int128 a) { return bn_isqrt_u128(a); }
W_RT_INTERNAL uint64_t w_rt_bn_gcd_u64_nonzero(uint64_t a, uint64_t b) { return bn_gcd_u64_nonzero(a, b); }

/* Resume the positive 6/3 quotient route immediately after its fixed
 * certificate has proved inconclusive.  The native source leaf has already
 * run that exact certificate, so re-entering bigint_div_any would execute it
 * twice more (boxed fast arm, then mag_divmod).  Preserve the remainder of
 * mag_divmod's selection tree verbatim. */
WValue w_bigint_div_63_after_cert_fail(WValue a, WValue b) {
    WBigint *aa = w_as_bigint(a);
    WBigint *bb = w_as_bigint(b);
    WBigint *q = NULL;
#if BN_DIV_RECIP_CACHE
    if (mag_divmod_reciprocal_certified(
            aa->limbs, 6, bb->limbs, 3, &q, NULL))
        return bigint_finish_mag_sub(q);
#endif
#if BN_DIV_TRIANGULAR_Q_CERTIFIED && BN_DIV_TRIANGULAR_Q_SELECT
    q = mag_div_q_triangular_certified(aa->limbs, 6, bb->limbs, 3);
    if (q) {
        BN_DIV_ROUTE_COUNT(bn_div_route_triangular_hit);
        return bigint_finish_mag_sub(q);
    }
#endif
    if (3 >= BZ_TOP_THRESHOLD && 3 >= BZ_THRESHOLD) {
        BN_DIV_ROUTE_COUNT(bn_div_route_bz);
        mag_divmod_bz(aa->limbs, 6, bb->limbs, 3, &q, NULL);
    } else {
        BN_DIV_ROUTE_COUNT(bn_div_route_knuth);
        mag_divmod_knuth(aa->limbs, 6, bb->limbs, 3, &q, NULL);
    }
    return bigint_finish_mag_sub(q);
}

/* Native-only continuation after the positive 8/4 source leaf has proved the
 * triangular certificate inconclusive.  At vlen=4 the reciprocal and B-Z
 * selectors are compile-time below their 256- and 24/64-limb thresholds, so
 * mag_divmod can only retry the identical certificate and then call Knuth.
 * Resume directly at that proven destination. */
WValue w_bigint_div_84_after_cert_fail(WValue a, WValue b) {
    WBigint *aa = w_as_bigint(a);
    WBigint *bb = w_as_bigint(b);
    WBigint *q = NULL;
    BN_DIV_ROUTE_COUNT(bn_div_route_knuth);
    mag_divmod_knuth(aa->limbs, 8, bb->limbs, 4, &q, NULL);
    return bigint_finish_mag_sub(q);
}
W_RT_INTERNAL void w_rt_bigint_div_release_recip_thread(void) {
    for (int i = 0; i < BN_DIV_RECIP_CACHE_ENTRIES; i++) {
        free(bn_div_recip_caches[i].key);
        free(bn_div_recip_caches[i].reciprocal);
        free(bn_div_recip_caches[i].product);
        free(bn_div_recip_caches[i].verification);
        memset(&bn_div_recip_caches[i], 0, sizeof(bn_div_recip_caches[i]));
    }
    bn_div_recip_cache_mru = 0;
}
W_RT_INTERNAL void w_rt_bigint_div_release_thread(void) {
    free(bz_ws);
    bz_ws = NULL;
    bz_ws_cap = 0;
    free(gcd_ws);
    gcd_ws = NULL;
    gcd_ws_cap = 0;
}

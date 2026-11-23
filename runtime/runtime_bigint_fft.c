#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define die w_rt_die
#define bn_add_n w_rt_bn_add_n
#define bn_sub_n w_rt_bn_sub_n
#define bn_addto w_rt_bn_addto
#define bigint_mul_schoolbook_into w_rt_bigint_mul_schoolbook_into
#define bigint_mul_dispatch w_rt_bigint_mul_dispatch
#define bigint_sqr_dispatch w_rt_bigint_sqr_dispatch
#define bn_pool_run_tasks w_rt_bn_pool_run_tasks
#define bn_pool_env_int w_rt_bn_pool_env_int
#define bn_ws_release_thread w_rt_bn_ws_release_thread
#endif

/* ====================================================================
 * Goldilocks single-prime NTT bignum multiply (the O(n log n) top rung).
 *
 * Ported from the validated Tungsten reference (~/math/bigmul.w gmul/gadd/
 * gsub/pack/recompose).  Prime P = 2^64 - 2^32 + 1; one machine word per
 * coefficient.  Input is packed into B-bit coefficients (B chosen per call so
 * the convolution coefficients stay < P), forward-transformed (radix-2 DIF,
 * natural->bit-reversed, NO explicit bit-reversal pass), pointwise multiplied
 * (with the 1/L scale folded in), inverse-transformed (radix-2 DIT,
 * bit-reversed->natural), and recomposed by carrying the B-bit-offset coeffs.
 * Twiddles are precomputed per call (one-shot; this is the general core path).
 *
 * Plain C is used (not inline asm): clang's codegen for the radix-2 butterfly
 * does not spill the way LLVM did for the wide radix-4/8 butterflies, and the
 * plain-C transform beat SERIAL Toom-4 by 1.2-3x when this rung was measured
 * in, so the hand-asm gold stage is unnecessary here.  The parallel point
 * scheduler has since moved that goalpost: forced NTT loses to seven-way
 * Toom-4 and to SSA everywhere in the reachable >= BN_PAR_TOOM_LIMIT band
 * (see ntt_cost_est), so this rung survives as the top-choice model's
 * fallback option rather than the expected winner.  Correctness was
 * cross-checked vs schoolbook (DIF-forward * DIF-forward == DIT-inverse of
 * the convolution, a true convolution homomorphism — not merely a
 * round-trip).
 * ==================================================================== */
#define GOLD_P  0xFFFFFFFF00000001ULL    /* 2^64 - 2^32 + 1 */
#define GOLD_EP 0xFFFFFFFFULL            /* 2^32 - 1 */

static inline uint64_t gold_mul(uint64_t a, uint64_t b) {
    __uint128_t prod = (__uint128_t)a * b;
    uint64_t lo = (uint64_t)prod;
    uint64_t hi = (uint64_t)(prod >> 64);
    uint64_t hihi = hi >> 32;            /* 2^96 == -1  (mod P) */
    uint64_t hilo = hi & GOLD_EP;        /* 2^64 == 2^32 - 1 (mod P) */
    uint64_t t0 = lo - hihi;
    if (lo < hihi) t0 -= GOLD_EP;
    uint64_t t1 = (hilo << 32) - hilo;
    uint64_t res = t0 + t1;
    if (res < t0) res += GOLD_EP;
    if (res >= GOLD_P) res -= GOLD_P;
    return res;
}
static inline uint64_t gold_add(uint64_t a, uint64_t b) {
    uint64_t r = a + b;
    if (r < a) r += GOLD_EP;
    if (r >= GOLD_P) r -= GOLD_P;
    return r;
}
static inline uint64_t gold_sub(uint64_t a, uint64_t b) {
    uint64_t r = a - b;
    if (a < b) r += GOLD_P;
    return r;
}
static uint64_t gold_pow(uint64_t base, uint64_t e) {
    uint64_t r = 1;
    while (e) { if (e & 1) r = gold_mul(r, base); base = gold_mul(base, base); e >>= 1; }
    return r;
}

typedef struct {
    long length;
    long half;
    uint64_t ninv;
    uint64_t *tw_forward;
    uint64_t *tw_inverse;
} WNTTPlan;

static __thread WNTTPlan *w_ntt_plan_cache[33];
static __thread uint64_t *w_ntt_workspace[2];
static __thread long w_ntt_workspace_cap[2];

static uint64_t *ntt_workspace_buffer(int slot, long length) {
    if (slot < 0 || slot >= 2) die("invalid NTT workspace slot");
    if (w_ntt_workspace_cap[slot] < length) {
        uint64_t *next = (uint64_t *)realloc(w_ntt_workspace[slot], (size_t)length * sizeof(uint64_t));
        if (!next) die("out of memory allocating NTT workspace");
        w_ntt_workspace[slot] = next;
        w_ntt_workspace_cap[slot] = length;
    }
    memset(w_ntt_workspace[slot], 0, (size_t)length * sizeof(uint64_t));
    return w_ntt_workspace[slot];
}

/* Largest B (bits/coeff, <=24) with ncoef*(2^B-1)^2 < P so the convolution
 * coefficients never overflow the single Goldilocks prime. */
static int ntt_choose_B(int32_t n) {
    long bits = (long)n * 64;
    for (int B = 24; B >= 8; B--) {
        long ncoef = (bits + B - 1) / B;
        unsigned __int128 mx = (unsigned __int128)ncoef * ((1ULL << B) - 1) * ((1ULL << B) - 1);
        if (mx < (unsigned __int128)GOLD_P) return B;
    }
    return 8;
}
static int ntt_choose_klog(long ncoef) {
    long need = 2 * ncoef; int klog = 1;
    while (((long)1 << klog) < need) klog++;
    return klog;
}
/* pack n limbs of `a` into `ncoef` B-bit coefficients fa[0..ncoef) */
static void ntt_pack(const uint64_t *a, int32_t n, uint64_t *fa, long ncoef, int B) {
    uint64_t mask = (B >= 64) ? ~0ULL : ((1ULL << B) - 1);
    long bitpos = 0;
    for (long j = 0; j < ncoef; j++) {
        long limb = bitpos >> 6; int sh = (int)(bitpos & 63);
        uint64_t window;
        if (sh == 0) window = a[limb] & mask;
        else {
            int lowbits = 64 - sh;
            uint64_t lowpart = a[limb] >> sh;
            uint64_t hipart = 0;
            if (limb + 1 < n) hipart = a[limb + 1] << lowbits;
            window = (lowpart | hipart) & mask;
        }
        fa[j] = window;
        bitpos += B;
    }
}
/* carry the nc B-bit-offset coefficients fc[0..nc) back into out[0..outlen) */
static void ntt_recompose(const uint64_t *fc, long nc, uint64_t *out, int32_t outlen, int B) {
    for (int32_t i = 0; i < outlen; i++) out[i] = 0;
    long bitpos = 0;
    for (long k = 0; k < nc; k++) {
        uint64_t val = fc[k];
        long limb = bitpos >> 6; int sh = (int)(bitpos & 63);
        uint64_t lo = val << sh;
        uint64_t oc = out[limb];
        out[limb] = oc + lo;
        uint64_t cc = (out[limb] < oc) ? 1 : 0;
        long pp2 = limb + 1;
        while (cc) { uint64_t oc2 = out[pp2]; out[pp2] = oc2 + cc; cc = (out[pp2] < oc2) ? 1 : 0; pp2++; }
        if (sh > 0) {
            uint64_t hi = (val >> (64 - sh)) & ((1ULL << sh) - 1);
            uint64_t oc3 = out[limb + 1];
            out[limb + 1] = oc3 + hi;
            uint64_t cc2 = (out[limb + 1] < oc3) ? 1 : 0;
            long pp3 = limb + 2;
            while (cc2) { uint64_t oc4 = out[pp3]; out[pp3] = oc4 + cc2; cc2 = (out[pp3] < oc4) ? 1 : 0; pp3++; }
        }
        bitpos += B;
    }
}
/* twiddle power table tw[0..half) = rt^0, rt^1, ...  (half = L/2) */
static void ntt_build_tw(uint64_t *tw, long half, uint64_t rt) {
    tw[0] = 1;
    for (long j = 1; j < half; j++) tw[j] = gold_mul(tw[j - 1], rt);
}

static WNTTPlan *ntt_plan_for_klog(int klog) {
    if (klog < 1 || klog > 32) die("unsupported NTT length");
    WNTTPlan *plan = w_ntt_plan_cache[klog];
    if (plan) return plan;

    plan = (WNTTPlan *)calloc(1, sizeof(WNTTPlan));
    if (!plan) die("out of memory allocating NTT plan");
    plan->length = (long)1 << klog;
    plan->half = plan->length >> 1;
    plan->tw_forward = (uint64_t *)malloc((size_t)plan->half * sizeof(uint64_t));
    plan->tw_inverse = (uint64_t *)malloc((size_t)plan->half * sizeof(uint64_t));
    if (!plan->tw_forward || !plan->tw_inverse) die("out of memory allocating NTT twiddles");

    uint64_t exp = GOLD_EP << (32 - klog);       /* (P-1)/L = (2^32-1) << (32-klog) */
    uint64_t wn = gold_pow(7, exp);              /* primitive L-th root (g = 7) */
    uint64_t winv = gold_pow(wn, GOLD_P - 2);    /* inverse root (Fermat) */
    plan->ninv = gold_pow((uint64_t)plan->length, GOLD_P - 2);
    ntt_build_tw(plan->tw_forward, plan->half, wn);
    ntt_build_tw(plan->tw_inverse, plan->half, winv);
    w_ntt_plan_cache[klog] = plan;
    return plan;
}

/* radix-2 DIF forward (natural -> bit-reversed), root powers in tw[] */
static void ntt_dif(uint64_t *v, long L, const uint64_t *tw) {
    for (long len = L; len >= 2; len >>= 1) {
        long half = len >> 1, stride = L / len;
        for (long i = 0; i < L; i += len) {
            uint64_t *base = v + i;
            long tidx = 0;
            for (long j = 0; j < half; j++) {
                uint64_t u = base[j], x = base[j + half];
                base[j] = gold_add(u, x);
                base[j + half] = gold_mul(gold_sub(u, x), tw[tidx]);
                tidx += stride;
            }
        }
    }
}
/* radix-2 DIT inverse (bit-reversed -> natural), inverse-root powers in tw[] */
static void ntt_dit(uint64_t *v, long L, const uint64_t *tw) {
    for (long len = 2; len <= L; len <<= 1) {
        long half = len >> 1, stride = L / len;
        for (long i = 0; i < L; i += len) {
            uint64_t *base = v + i;
            long tidx = 0;
            for (long j = 0; j < half; j++) {
                uint64_t t = gold_mul(base[j + half], tw[tidx]);
                uint64_t u = base[j];
                base[j] = gold_add(u, t);
                base[j + half] = gold_sub(u, t);
                tidx += stride;
            }
        }
    }
}
/* out[0..2n) = a[0..n) * b[0..n) via Goldilocks NTT. */
static void bn_ntt_mul(uint64_t *out, const uint64_t *a, const uint64_t *b, int32_t n) {
    int B = ntt_choose_B(n);
    long ncoef = ((long)n * 64 + B - 1) / B;
    int klog = ntt_choose_klog(ncoef);
    WNTTPlan *plan = ntt_plan_for_klog(klog);
    long L = plan->length;
    uint64_t *fa = ntt_workspace_buffer(0, L);
    uint64_t *fb = ntt_workspace_buffer(1, L);
    ntt_pack(a, n, fa, ncoef, B);
    ntt_pack(b, n, fb, ncoef, B);
    ntt_dif(fa, L, plan->tw_forward);
    ntt_dif(fb, L, plan->tw_forward);
    for (long k = 0; k < L; k++) fa[k] = gold_mul(gold_mul(fa[k], fb[k]), plan->ninv);
    ntt_dit(fa, L, plan->tw_inverse);
    ntt_recompose(fa, 2 * ncoef, out, n + n + 2, B);
}
/* out[0..2n) = a[0..n)^2 via Goldilocks NTT (ONE forward transform). */
static void bn_ntt_sqr(uint64_t *out, const uint64_t *a, int32_t n) {
    int B = ntt_choose_B(n);
    long ncoef = ((long)n * 64 + B - 1) / B;
    int klog = ntt_choose_klog(ncoef);
    WNTTPlan *plan = ntt_plan_for_klog(klog);
    long L = plan->length;
    uint64_t *fa = ntt_workspace_buffer(0, L);
    ntt_pack(a, n, fa, ncoef, B);
    ntt_dif(fa, L, plan->tw_forward);
    for (long k = 0; k < L; k++) fa[k] = gold_mul(gold_mul(fa[k], fa[k]), plan->ninv);
    ntt_dit(fa, L, plan->tw_inverse);
    ntt_recompose(fa, 2 * ncoef, out, n + n + 2, B);
}

/* ====================================================================
 * Schönhage–Strassen multiply (the very top rung, ≥ BN_SSA_THRESHOLD limbs).
 *
 * The Goldilocks NTT above pays one gold_mul per butterfly (~1.6M at 8192
 * limbs). SSA works in the Fermat ring Z/(2^K+1), where 2 has order 2K, so
 * the transform's L-th root of unity is ω = 2^(2K/L): every butterfly twiddle
 * is a BIT SHIFT with negacyclic wrap — zero multiplications in the
 * transforms. The only real multiplies are L pointwise products of K-bit ring
 * elements, which recurse into the (asm-kernel) Toom ladder via
 * bigint_mul_dispatch.
 *
 * Current simplifications (correct, slightly conservative):
 *   • pieces are limb-aligned (M = 64·w bits) — pack/recompose are limb
 *     slicing + bn_addto, no bit-granular carries;
 *   • K = 64·m, rounded up to a multiple of lcm(64, L/2) so 2^(2K/L) exists
 *     and the K-boundary split in shifts is limb-clean;
 *   • cyclic convolution with 2× zero padding (L = 2·ncoef rounded up).
 * The √2 trick IS implemented (ssa_shl_half below: √2 = 2^(3K/4) − 2^(K/4),
 * a primitive 4K-th root, live in the forward and inverse transforms with a
 * family selector in ssa_choose) — it halves K for a given L. What remains
 * for the next performance step is true negacyclic convolution (weighting
 * away the 2× zero pad) and bit-granular M; w_mulmod_bnm1 is the CRT building
 * block for it.
 *
 * Ring element: stride S = m+1 limbs; canonical value = lo + top·2^K with
 * top ∈ {0,1} and top==1 ⇒ lo==0 (value 2^K = p−1 exactly). All element
 * add/sub ride the asm bn_add_n / bn_sub_n kernels.
 *
 * SSA packs its operands into its OWN thread workspace immediately: the
 * pointwise products recurse into bigint_mul_dispatch, which owns bn_ws, so
 * nothing SSA needs may live there.
 * ==================================================================== */
#ifndef BN_SSA_THRESHOLD
#define BN_SSA_THRESHOLD 2048   /* limbs; below this SSA never wins. Above it,
                                 * the dispatcher compares the two cost models
                                 * (both step functions of transform length). */
#endif


static __thread uint64_t *w_ssa_ws = NULL;
static __thread size_t w_ssa_ws_cap = 0;
static uint64_t *ssa_ws_get(size_t limbs) {
    if (limbs > w_ssa_ws_cap) {
        free(w_ssa_ws);
        size_t ncap = limbs + limbs / 4 + 64;
        w_ssa_ws = (uint64_t *)malloc(ncap * sizeof(uint64_t));
        w_ssa_ws_cap = w_ssa_ws ? ncap : 0;
        if (!w_ssa_ws) return NULL;
    }
    return w_ssa_ws;
}
static uint64_t *ssa_ws_get_zeroed(size_t limbs) {
    uint64_t *ws = ssa_ws_get(limbs);
    if (!ws) return NULL;
    memset(w_ssa_ws, 0, limbs * sizeof(uint64_t));
    return ws;
}

/* Canonicalize: value ≡ (e[0..m) as unsigned) − c (mod 2^K+1), |c| ≤ 4.
 * Writes e[m] (top). Wrap identities: an m-limb subtract-wrap means the true
 * value is e_now + 1 (−2^K ≡ +1); an add-overflow means e_now − 1. */
static void ssa_fix(uint64_t *e, int32_t m, int64_t c) {
    e[m] = 0;
    if (c > 0) {
        uint64_t bw = (uint64_t)c;
        for (int32_t i = 0; i < m && bw; i++) { uint64_t old = e[i]; e[i] = old - bw; bw = (old < bw); }
        if (bw) {                                    /* lo < c: value = lo−c+p = e_now+1 */
            uint64_t cy = 1;
            for (int32_t i = 0; i < m && cy; i++) { e[i] += 1; cy = (e[i] == 0); }
            if (cy) e[m] = 1;                        /* was all-ones ⇒ value = 2^K */
        }
    } else if (c < 0) {
        uint64_t cy = (uint64_t)(-c);
        for (int32_t i = 0; i < m && cy; i++) { uint64_t old = e[i]; e[i] = old + cy; cy = (e[i] < old); }
        if (cy) {                                    /* overflow: value = e_now + 2^K */
            int32_t z = 0;
            while (z < m && e[z] == 0) z++;
            if (z == m) e[m] = 1;                    /* e_now == 0 ⇒ value = 2^K */
            else {                                   /* ≡ e_now − 1 (no wrap, e_now ≥ 1) */
                uint64_t bw = 1;
                for (int32_t i = 0; i < m && bw; i++) { uint64_t old = e[i]; e[i] = old - 1; bw = (old == 0); }
            }
        }
    }
}

/* r = a ± b (r may alias a; tops read before the limb pass). */
static void ssa_add(uint64_t *r, const uint64_t *a, const uint64_t *b, int32_t m) {
    uint64_t at = a[m], bt = b[m];
    uint64_t co = bn_add_n(r, a, b, m);
    ssa_fix(r, m, (int64_t)(co + at + bt));
}
static void ssa_sub(uint64_t *r, const uint64_t *a, const uint64_t *b, int32_t m) {
    uint64_t at = a[m], bt = b[m];
    uint64_t bo = bn_sub_n(r, a, b, m);
    ssa_fix(r, m, (int64_t)at - (int64_t)bt - (int64_t)bo);
}

#if defined(__aarch64__)
/* Complete fused limb pass in caller-saved registers.  Returning carry in bit
 * 0 and borrow in bit 1 leaves only the two rare canonicalization fixes in C.
 * Keeping this out of inline assembly avoids the eight live result registers
 * forcing compiler spills around every four-limb butterfly. */
__attribute__((naked, noinline))
static uint64_t ssa_addsub_core(uint64_t *u, uint64_t *dout,
                                const uint64_t *v, int32_t m) {
    __asm__(
        "mov x16, xzr\n"
        "mov x17, xzr\n"
        "cmp w3, #4\n"
        "b.lt 2f\n"
        "1:\n"
        "ldp x4, x5, [x0]\n"
        "ldp x6, x7, [x0, #16]\n"
        "ldp x8, x9, [x2], #32\n"
        "ldp x10, x11, [x2, #-16]\n"
        "cmp x16, #1\n"
        "adcs x12, x4, x8\n"
        "adcs x13, x5, x9\n"
        "adcs x14, x6, x10\n"
        "adcs x15, x7, x11\n"
        "cset x16, cs\n"
        "cmp xzr, x17\n"
        "sbcs x4, x4, x8\n"
        "sbcs x5, x5, x9\n"
        "sbcs x6, x6, x10\n"
        "sbcs x7, x7, x11\n"
        "cset x17, cc\n"
        "stp x12, x13, [x0], #32\n"
        "stp x14, x15, [x0, #-16]\n"
        "stp x4, x5, [x1], #32\n"
        "stp x6, x7, [x1, #-16]\n"
        "sub w3, w3, #4\n"
        "cmp w3, #4\n"
        "b.ge 1b\n"
        "2:\n"
        "cbz w3, 4f\n"
        "3:\n"
        "ldr x4, [x0]\n"
        "ldr x8, [x2], #8\n"
        "cmp x16, #1\n"
        "adcs x12, x4, x8\n"
        "cset x16, cs\n"
        "cmp xzr, x17\n"
        "sbcs x4, x4, x8\n"
        "cset x17, cc\n"
        "str x12, [x0], #8\n"
        "str x4, [x1], #8\n"
        "subs w3, w3, #1\n"
        "b.ne 3b\n"
        "4:\n"
        "orr x0, x16, x17, lsl #1\n"
        "ret\n"
    );
}
#endif

/* Fused butterfly add/sub: usum ← u+v and dout ← u−v (mod p) in ONE pass —
 * u and the second operand load once (separate ssa_add + ssa_sub load them
 * twice). dout must not alias u or v. */
static void ssa_addsub(uint64_t *u, uint64_t *dout, const uint64_t *v, int32_t m) {
    uint64_t ut = u[m], vt = v[m];
    uint64_t cy, bw;
#if defined(__aarch64__)
    uint64_t flags = ssa_addsub_core(u, dout, v, m);
    cy = flags & 1U;
    bw = flags >> 1;
#else
    cy = 0;
    bw = 0;
    for (int32_t i = 0; i < m; i++) {
        uint64_t uv = u[i], vv = v[i];
        __uint128_t ss = (__uint128_t)uv + vv + cy;
        u[i] = (uint64_t)ss; cy = (uint64_t)(ss >> 64);
        uint64_t t = uv - vv;
        uint64_t b1 = uv < vv;
        uint64_t d = t - bw;
        uint64_t b2 = t < bw;
        dout[i] = d; bw = b1 | b2;
    }
#endif
    ssa_fix(u, m, (int64_t)(cy + ut + vt));
    ssa_fix(dout, m, (int64_t)ut - (int64_t)vt - (int64_t)bw);
}

/* e = p − e in place (negation; 0 stays 0). p − lo = ~lo + 2 over m limbs. */
static void ssa_neg(uint64_t *e, int32_t m) {
    if (e[m]) { e[m] = 0; e[0] = 1; return; }        /* p − 2^K = 1 */
    int32_t z = 0;
    while (z < m && e[z] == 0) z++;
    if (z == m) return;                              /* 0 → 0 */
    for (int32_t i = 0; i < m; i++) e[i] = ~e[i];
    ssa_fix(e, m, -2);                               /* value ≡ ~lo + 2 = p − lo */
}

/* r = x · 2^s mod (2^K+1), 0 ≤ s < 2K, r ≠ x. lo·2^s = B·2^K + A (A the low
 * K bits, B the spilled top s bits) ⇒ x·2^s ≡ A − B − top·2^s. */
static void ssa_shl(uint64_t *r, const uint64_t *x, uint64_t s, int32_t m, uint64_t K) {
    int neg = 0;
    if (s >= K) { s -= K; neg = 1; }                 /* 2^K ≡ −1 */
    if (s == 0) {
        for (int32_t i = 0; i <= m; i++) r[i] = x[i];
        if (neg) ssa_neg(r, m);
        return;
    }
    int32_t q = (int32_t)(s >> 6);
    int rb = (int)(s & 63);
    uint64_t bw = 0;
    if (rb == 0) {
        /* Word-aligned twiddles are common. Form A-B directly instead of
         * writing A and then revisiting its low q limbs to subtract B. */
        int32_t j = 0;
        for (; j < q && x[m + j - q] == 0; j++) r[j] = 0;
        if (j < q) {
            r[j] = 0 - x[m + j - q];
            j++;
            for (; j < q; j++) r[j] = ~x[m + j - q];
            bw = 1;
        }
        int32_t alen = m - q;
        j = 0;
        if (bw) {
            for (; j < alen && x[j] == 0; j++) r[q + j] = UINT64_MAX;
            if (j < alen) {
                r[q + j] = x[j] - 1;
                j++;
                bw = 0;
            }
        }
        if (j < alen)
            memcpy(r + q + j, x + j, (size_t)(alen - j) * sizeof(uint64_t));
    } else {
        for (int32_t i = 0; i < q; i++) r[i] = 0;    /* A = (lo << s) mod 2^K */
        for (int32_t i = m - 1; i >= q; i--) {
            uint64_t hi2 = x[i - q] << rb;
            uint64_t lo2 = (i - q - 1 >= 0) ? (x[i - q - 1] >> (64 - rb)) : 0;
            r[i] = hi2 | lo2;
        }
        /* subtract B = lo >> (K−s): the spilled top s bits, limbs 0..q */
        for (int32_t j = 0; j <= q; j++) {
            int32_t idx = m + j - q;
            uint64_t hi_src = (idx < m) ? x[idx] : 0;
            uint64_t lo_src = (idx - 1 >= 0 && idx - 1 < m) ? x[idx - 1] : 0;
            uint64_t bj = (hi_src << rb) | (lo_src >> (64 - rb));
            uint64_t old = r[j];
            uint64_t t = old - bj;
            uint64_t b1 = old < bj;
            uint64_t d = t - bw;
            uint64_t b2 = t < bw;
            r[j] = d;
            bw = b1 | b2;
        }
        for (int32_t j = q + 1; j < m && bw; j++) {
            uint64_t old = r[j];
            r[j] = old - 1;
            bw = old == 0;
        }
    }
    int64_t c = -(int64_t)bw;                        /* wrap ⇒ value = e_now + 1 */
    if (x[m]) {                                      /* − top·2^s: one bit at limb q */
        uint64_t bit = 1ULL << rb;
        uint64_t old = r[q];
        r[q] = old - bit;
        uint64_t bw2 = old < bit;
        for (int32_t j = q + 1; j < m && bw2; j++) { uint64_t o2 = r[j]; r[j] = o2 - 1; bw2 = (o2 == 0); }
        c -= (int64_t)bw2;
    }
    ssa_fix(r, m, c);
    if (neg) ssa_neg(r, m);
}

/* Twiddle by a HALF-power of two: r = x·(√2)^th, th ∈ [0, 4K). In Z/(2^K+1),
 * √2 = 2^(3K/4) − 2^(K/4) (check: square = 2^(3K/2) − 2·2^K + 2^(K/2) ≡
 * −2^(K/2) + 2 + 2^(K/2) = 2 ✓), a primitive 4K-th root alongside 2's 2K.
 * Half-exponents let K be a multiple of L/4 instead of L/2 — halving the
 * K-rounding waste — at the cost of one extra shift+subtract on ODD
 * exponents (which occur only in the finest transform stage). */
static void ssa_shl_half(uint64_t *r, const uint64_t *x, uint64_t th,
                         int32_t m, uint64_t K, uint64_t *t3) {
    if ((th & 1) == 0) {
        ssa_shl(r, x, (th >> 1) % (2 * K), m, K);
        return;
    }
    uint64_t hb = th >> 1;                       /* 2^hb · √2 · x */
    ssa_shl(r,  x, (hb + 3 * K / 4) % (2 * K), m, K);
    ssa_shl(t3, x, (hb + K / 4) % (2 * K), m, K);
    ssa_sub(r, r, t3, m);
}

/* dst ≡ a·b (b == NULL squares a; dst may alias a). Full product through the
 * dispatcher, then split-at-K reduction plus the rare top-flag corrections:
 * (alo−at)(blo−bt) = alo·blo − at·blo − bt·alo + at·bt  (tops ≡ −1). */
static void ssa_pointwise(uint64_t *dst, const uint64_t *a, const uint64_t *b,
                          int32_t m, uint64_t *prod, uint64_t *tsave) {
    uint64_t at = a[m], bt = b ? b[m] : at;
    const uint64_t *blo = b ? b : a;
    int32_t an = m, bl2 = m;
    while (an > 0 && a[an - 1] == 0) an--;
    while (bl2 > 0 && blo[bl2 - 1] == 0) bl2--;
    if (at || bt) { for (int32_t i = 0; i < m; i++) tsave[i] = a[i]; }  /* alo survives dst write */
    int32_t plen = 0;
    if (an && bl2) {
        if (b) {
            bigint_mul_dispatch(prod, a, an, blo, bl2);
            plen = an + bl2;
        } else {
            bigint_sqr_dispatch(prod, a, an);
            plen = 2 * an;
        }
    }
    for (int32_t i = plen; i < 2 * m; i++) prod[i] = 0;
    const uint64_t *bkeep = b ? blo : tsave;          /* blo copy for the at-correction */
    for (int32_t i = 0; i < m; i++) dst[i] = prod[i];
    uint64_t bo = bn_sub_n(dst, dst, prod + m, m);    /* value ≡ lo − hi */
    int64_t c = -(int64_t)bo;
    if (at) { uint64_t b2 = bn_sub_n(dst, dst, bkeep, m); c -= (int64_t)b2; }
    if (bt) { uint64_t b3 = bn_sub_n(dst, dst, tsave, m); c -= (int64_t)b3; }
    if (at && bt) c -= 1;                             /* + at·bt ⇒ value + 1 */
    ssa_fix(dst, m, c);
}

static int ssa_ceil_log2(long v) { int k = 0; while ((1L << k) < v) k++; return k; }
static double ssa_mul_est(double m) {                 /* rough dispatcher cost */
    return (m <= 48.0) ? 0.35 * m * m : 0.35 * 48.0 * 48.0 * pow(m / 48.0, 1.585);
}

/* Parameter chooser, shared with the dispatcher's SSA-vs-NTT cost compare.
 * Returns the modeled cost (~ns; calibrated against measurement) and the
 * chosen (w, L, K), or a huge cost if no valid split exists. */
static double ssa_choose(int32_t na, int32_t nb, int32_t *w_out, long *L_out, uint64_t *K_out) {
    int32_t best_w = 0; long best_L = 0; uint64_t best_K = 0; double best_cost = 1e30;
    for (int32_t w = 2; w <= 256; w *= 2) {
        long pa = (na + w - 1) / w, pb = (nb + w - 1) / w;
        long need = pa + pb;
        if (need < 8) continue;
        int k = ssa_ceil_log2(need);
        long L = 1L << k;
        /* two K-granularity families: L/2 (plain 2^j twiddles, never odd) and
         * L/4 (√2 half-exponents — finer K, but odd exponents in the finest
         * stage cost an extra shift+subtract each). Model both, keep the best. */
        for (int fam = 0; fam < 2; fam++) {
            uint64_t granv = fam ? (uint64_t)(L / 4) : (uint64_t)(L / 2);
            if (granv < 64) granv = 64;
            uint64_t Kb = ((uint64_t)(128 * w + k + 2) + granv - 1) / granv * granv;
            double md = (double)(Kb / 64);
            double cost = 3.0 * (double)(L / 2) * k * (md + 1) * 0.7
                        + (double)L * ssa_mul_est(md)
                        + 3.0 * (double)L * (md + 1) * 0.5;
            if ((4 * Kb / (uint64_t)L) & 1)          /* odd finest-stage twiddles */
                cost += 3.0 * (double)(L / 4) * 2.0 * (md + 1) * 0.7;
            /* At L>=2048, the extra odd half-twiddle pass is memory-bound
             * enough that two to eight extra plain-family limbs are cheaper.
             * Measured at 16384 limbs: 2.23ms plain vs 2.34ms half-family. */
            if (fam && L >= 2048)
                cost *= 1.10;
            cost *= 1.6;                             /* calibration vs measured */
            if (!best_w || cost < best_cost) { best_w = w; best_L = L; best_K = Kb; best_cost = cost; }
        }
    }
    *w_out = best_w; *L_out = best_L; *K_out = best_K;
    return best_cost;
}

/* Goldilocks-NTT cost model with the same step structure as its real
 * dispatcher path (transform-length quantization dominates).  The historical
 * 1.2 ns per gold_mul-equivalent was measured at n=2048 (432µs vs 424) — but
 * n < BN_PAR_TOOM_LIMIT never reaches a transform, so the model only ever
 * decides in the n >= 16384 band, where the kernel runs 3.2-5.6x its small-n
 * calibration (forced-kernel sweep, Apple arm64, 16384..131073 limbs:
 * NTT/SSA/Toom = 6.8/1.1/1.6ms at 16384, 4.4/1.6/1.9 at 24576, 9.4/3.4/2.9
 * at 32769, 21.9/7.3/7.4 at 65537, 50/16/20 at 131073 — forced NTT never
 * wins in-band).  The stale constant let NTT steal exactly the cells where
 * SSA's transform length doubles (20480-24576, 32769-40960, 65537-81920,
 * 131073..), turning the cached-reciprocal division's (n+1)-limb Barrett
 * products 3-6x pessimal just past every power of two.  Calibrate to the
 * reachable band instead: 4.8 ns per gold_mul-equivalent (~4x, the measured
 * mid-band drift). */
static double ntt_cost_est(int32_t n) {
    int B = ntt_choose_B(n);
    long ncoef = ((long)n * 64 + B - 1) / B;
    long L0 = 1L << ssa_ceil_log2(2 * ncoef);
    return (3.0 * (double)(L0 / 2) * ssa_ceil_log2(L0) + (double)L0) * 4.8;
}


/* Transform costs are step functions, while the Toom-4 ladder is smooth
 * between its recursion resonances.  Comparing only SSA with NTT forced one
 * transform even immediately after both transform lengths doubled.  Calibrate
 * all three against the forced-kernel sweep on Apple arm64:
 *
 *   multiply Toom-4 ~= 6.7 * n^log_4(7)
 *   square   Toom-4 ~= 5.0 * n^log_4(7)
 *
 * The raw SSA model is accurate once its piece width reaches 16 limbs; its
 * first (w=8) multiply window needs the measured setup correction.  Squaring
 * saves one operand transform, hence its separate SSA/NTT factors. */
static int bn_top_choice(int32_t na, int32_t nb, int square) {
    int32_t n = na > nb ? na : nb;
    if (n < BN_SSA_THRESHOLD && n < BN_NTT_THRESHOLD)
        return BN_TOP_TOOM;
    /* The bounded point scheduler changes the medium-size Toom cost curve
     * from the serial model below. Direct measurements keep seven-way Toom-4
     * ahead through 14K; the parallel SSA transform takes over around 16K. */
    if (n < BN_PAR_TOOM_LIMIT)
        return BN_TOP_TOOM;
    double toom = (square ? 5.0 : 6.7) * pow((double)n, 1.403677461);
    double ssa = 1e30;
    double ntt = 1e30;
    if (n >= BN_SSA_THRESHOLD) {
        int32_t sw;
        long sL;
        uint64_t sK;
        ssa = ssa_choose(na, nb, &sw, &sL, &sK);
        if (!sw) {
            ssa = 1e30;
        } else if (square) {
            ssa *= sw <= 8 ? 0.92 : 0.66;
        } else if (sw <= 8) {
            ssa *= 1.45;
        }
    }
    if (n >= BN_NTT_THRESHOLD)
        ntt = ntt_cost_est(n) * (square ? 1.15 : 1.65);
    if (ssa < toom && ssa <= ntt) return BN_TOP_SSA;
    if (ntt < toom) return BN_TOP_NTT;
    return BN_TOP_TOOM;
}


typedef struct {
    uint64_t *a;
    long length;
    int32_t m;
    uint64_t K;
    uint64_t *t1;
    uint64_t *t2;
    int parallel;
} WSSAForwardJob;

static void ssa_forward_range(WSSAForwardJob *job, long start, long end,
                              long first_len, long last_len) {
    uint64_t *A = job->a;
    int32_t m = job->m;
    int32_t S = m + 1;
    uint64_t K = job->K;
    for (long len = first_len; len >= last_len; len >>= 1) {
        uint64_t steph = 2 * K / (uint64_t)len;
        for (long base = start; base < end; base += 2 * len) {
            for (long j = 0; j < len; j++) {
                uint64_t *u = A + (base + j) * S;
                uint64_t *v = A + (base + j + len) * S;
                ssa_addsub(u, job->t1, v, m);
                ssa_shl_half(v, job->t1, (steph * (uint64_t)j) % (4 * K),
                             m, K, job->t2);
            }
        }
    }
}

typedef struct {
    WSSAForwardJob *job;
    long start;
    long end;
    long first_len;
    long last_len;
} WSSAForwardRangeJob;

static void *ssa_forward_range_worker(void *arg) {
    WSSAForwardRangeJob *range = (WSSAForwardRangeJob *)arg;
    ssa_forward_range(range->job, range->start, range->end,
                      range->first_len, range->last_len);
    return NULL;
}

static void ssa_forward_transform(WSSAForwardJob *job) {
    long L = job->length;
    if (!job->parallel || L < 4) {
        ssa_forward_range(job, 0, L, L / 2, 1);
        return;
    }
    ssa_forward_range(job, 0, L, L / 2, L / 2);
    uint64_t right_t1[job->m + 1];
    uint64_t right_t2[job->m + 1];
    WSSAForwardJob other = *job;
    other.t1 = right_t1;
    other.t2 = right_t2;
    WSSAForwardRangeJob right = {&other, L / 2, L, L / 4, 1};
    pthread_t worker;
    int live = pthread_create(&worker, NULL, ssa_forward_range_worker, &right) == 0;
    ssa_forward_range(job, 0, L / 2, L / 4, 1);
    if (live) pthread_join(worker, NULL);
    else ssa_forward_range(&other, L / 2, L, L / 4, 1);
}

static void *ssa_forward_worker(void *arg) {
    ssa_forward_transform((WSSAForwardJob *)arg);
    return NULL;
}

typedef struct {
    uint64_t *a;
    long start;
    long end;
    long first_len;
    long last_len;
    int32_t m;
    uint64_t K;
    uint64_t *t1;
    uint64_t *t2;
} WSSAInverseRangeJob;

static void ssa_inverse_range(WSSAInverseRangeJob *job) {
    int32_t S = job->m + 1;
    for (long len = job->first_len; len <= job->last_len; len <<= 1) {
        uint64_t steph = 2 * job->K / (uint64_t)len;
        for (long base = job->start; base < job->end; base += 2 * len) {
            for (long j = 0; j < len; j++) {
                uint64_t *u = job->a + (base + j) * S;
                uint64_t *v = job->a + (base + j + len) * S;
                uint64_t sh = (4 * job->K - steph * (uint64_t)j) % (4 * job->K);
                ssa_shl_half(job->t1, v, sh, job->m, job->K, job->t2);
                ssa_addsub(u, v, job->t1, job->m);
            }
        }
    }
}

static void *ssa_inverse_range_worker(void *arg) {
    ssa_inverse_range((WSSAInverseRangeJob *)arg);
    return NULL;
}

typedef struct {
    uint64_t *a;
    const uint64_t *b;
    long start;
    long end;
    int32_t m;
    uint64_t *scratch;
} WSSAPointJob;

static void ssa_pointwise_range(WSSAPointJob *job) {
    int32_t S = job->m + 1;
    uint64_t *prod = job->scratch;
    uint64_t *tsave = prod + 2 * (size_t)job->m + 2;
    for (long i = job->start; i < job->end; i++)
        ssa_pointwise(job->a + i * S, job->a + i * S,
                      job->b ? job->b + i * S : NULL,
                      job->m, prod, tsave);
}

static void *ssa_pointwise_worker(void *arg) {
    ssa_pointwise_range((WSSAPointJob *)arg);
    bn_ws_release_thread();
    return NULL;
}

/* Pool-task thunks for the fused SSA schedule (persistent workers instead
 * of per-phase thread spawns; each dispatch is the phase barrier). */
static void ssa_forward_range_task(void *arg) {
    WSSAForwardRangeJob *range = (WSSAForwardRangeJob *)arg;
    ssa_forward_range(range->job, range->start, range->end,
                      range->first_len, range->last_len);
}

static void ssa_pointwise_task(void *arg) {
    ssa_pointwise_range((WSSAPointJob *)arg);
}

static void ssa_inverse_range_task(void *arg) {
    ssa_inverse_range((WSSAInverseRangeJob *)arg);
}

static int bn_ssa_pool_enabled(void) {
    static _Atomic int cached = -1;
    int value = atomic_load_explicit(&cached, memory_order_relaxed);
    if (value < 0) {
        value = bn_pool_env_int("TUNGSTEN_BN_SSA_POOL", 1) != 0;
        atomic_store_explicit(&cached, value, memory_order_relaxed);
    }
    return value;
}

#ifndef BN_BENCH_RUNTIME_SSA_PACK_KNOB
#define BN_BENCH_RUNTIME_SSA_PACK_KNOB 0
#endif
#ifndef BN_SSA_PACK_ZERO_ONLY
#define BN_SSA_PACK_ZERO_ONLY 1
#endif
#if BN_BENCH_RUNTIME_SSA_PACK_KNOB
static int bn_bench_runtime_ssa_pack_zero_only;
#endif

static void ssa_pack_zero_padded(uint64_t *dst, long L, int32_t S,
                                 const uint64_t *src, int32_t n,
                                 int32_t piece_limbs) {
    long pieces = (n + piece_limbs - 1) / piece_limbs;
    for (long piece = 0; piece < pieces; piece++) {
        int32_t off = (int32_t)piece * piece_limbs;
        int32_t live = n - off < piece_limbs ? n - off : piece_limbs;
        uint64_t *slot = dst + piece * S;
        for (int32_t j = 0; j < live; j++) slot[j] = src[off + j];
        for (int32_t j = live; j < S; j++) slot[j] = 0;
    }
    if (pieces < L)
        memset(dst + pieces * S, 0,
               (size_t)(L - pieces) * (size_t)S * sizeof(uint64_t));
}

/* out[0..na+nb) = a·b (b == NULL: square, nb ignored → na). */
static void bn_ssa_mul(uint64_t *out, const uint64_t *a, int32_t na,
                       const uint64_t *b, int32_t nb) {
    if (!b) nb = na;
    int32_t outlen = na + nb;
    int32_t best_w; long best_L; uint64_t best_K;
    ssa_choose(na, nb, &best_w, &best_L, &best_K);
    if (!best_w) {
        bigint_mul_schoolbook_into(out, a, na, b ? b : a, nb);
        return;
    }
    int32_t w = best_w;
    long L = best_L;
    int klog = ssa_ceil_log2(L);
    uint64_t K = best_K;
    int32_t m = (int32_t)(K / 64);
    int32_t S = m + 1;
    int parallel = na >= BN_SSA_PAR_THRESHOLD && nb >= BN_SSA_PAR_THRESHOLD;
    int point_threads = parallel ? BN_SSA_PAR_THREADS : 1;
    if (point_threads < 1) point_threads = 1;
    size_t point_stride = 3 * (size_t)m + 2;

    size_t total = (size_t)L * S * (b ? 2 : 1)
                 + 4 * (size_t)S + (size_t)point_threads * point_stride
                 + 8 * (size_t)S;
    int pack_zero_only = BN_SSA_PACK_ZERO_ONLY;
#if BN_BENCH_RUNTIME_SSA_PACK_KNOB
    pack_zero_only = bn_bench_runtime_ssa_pack_zero_only;
#endif
    uint64_t *ws = pack_zero_only ? ssa_ws_get(total)
                                  : ssa_ws_get_zeroed(total);
    if (!ws) { bigint_mul_schoolbook_into(out, a, na, b ? b : a, nb); return; }
    uint64_t *fa = ws;
    uint64_t *fb = b ? fa + (size_t)L * S : NULL;
    uint64_t *t1 = fa + (size_t)L * S * (b ? 2 : 1);
    uint64_t *t2 = t1 + S;
    uint64_t *t3 = t2 + S;
    uint64_t *t4 = t3 + S;
    uint64_t *point_ws = t4 + S;
    uint64_t *quad_ws = point_ws + (size_t)point_threads * point_stride;

    if (pack_zero_only) {
        /* Transform points must carry explicit zero padding, but the four
         * butterfly temporaries and each pointwise product frame are fully
         * written before their first read.  Fill every transform limb once
         * instead of clearing the complete arena and overwriting live input. */
        ssa_pack_zero_padded(fa, L, S, a, na, w);
        if (b) ssa_pack_zero_padded(fb, L, S, b, nb, w);
    } else {
        /* pack: piece i = limbs [i*w, i*w+w); the full clear supplied
         * transform padding and all unused points. */
        long pa = (na + w - 1) / w;
        for (long i = 0; i < pa; i++) {
            int32_t off = (int32_t)i * w;
            int32_t len = (na - off < w) ? na - off : w;
            for (int32_t j2 = 0; j2 < len; j2++)
                fa[i * S + j2] = a[off + j2];
        }
        if (b) {
            long pb = (nb + w - 1) / w;
            for (long i = 0; i < pb; i++) {
                int32_t off = (int32_t)i * w;
                int32_t len = (nb - off < w) ? nb - off : w;
                for (int32_t j2 = 0; j2 < len; j2++)
                    fb[i * S + j2] = b[off + j2];
            }
        }
    }

    /* Forward DIF. For large multiplies the operand transforms are independent;
     * run B on one worker while the caller transforms A. */
    int use_pool = parallel && L >= 4 && bn_ssa_pool_enabled();
    WSSAForwardJob fa_job = {fa, L, m, K, t1, t2, use_pool ? 0 : parallel};
    WSSAForwardJob fb_job = {fb, L, m, K, t3, t4, use_pool ? 0 : parallel};
    if (use_pool) {
        /* Fused schedule: each phase is one dispatch on the persistent
         * pool and doubles as the phase barrier; burst linger carries the
         * workers between phases without a park/wake cycle.  The first
         * forward stage couples the halves, below it the quarters run
         * independently to the leaves. */
        WSSAForwardJob fa_hi = {fa, L, m, K, quad_ws, quad_ws + S, 0};
        if (b) {
            WSSAForwardRangeJob stage1[2] = {
                {&fa_job, 0, L, L / 2, L / 2},
                {&fb_job, 0, L, L / 2, L / 2},
            };
            void *stage_args[2] = {&stage1[0], &stage1[1]};
            bn_pool_run_tasks(ssa_forward_range_task, stage_args, 2,
                              BN_TOOM_POOL_SPIN);
            WSSAForwardJob fb_hi = {fb, L, m, K, quad_ws + 2 * S,
                                    quad_ws + 3 * S, 0};
            WSSAForwardRangeJob quads[4] = {
                {&fa_job, 0, L / 2, L / 4, 1},
                {&fa_hi, L / 2, L, L / 4, 1},
                {&fb_job, 0, L / 2, L / 4, 1},
                {&fb_hi, L / 2, L, L / 4, 1},
            };
            void *quad_args[4] = {&quads[0], &quads[1], &quads[2],
                                  &quads[3]};
            bn_pool_run_tasks(ssa_forward_range_task, quad_args, 4,
                              BN_TOOM_POOL_SPIN);
        } else {
            ssa_forward_range(&fa_job, 0, L, L / 2, L / 2);
            WSSAForwardRangeJob halves[2] = {
                {&fa_job, 0, L / 2, L / 4, 1},
                {&fa_hi, L / 2, L, L / 4, 1},
            };
            void *half_args[2] = {&halves[0], &halves[1]};
            bn_pool_run_tasks(ssa_forward_range_task, half_args, 2,
                              BN_TOOM_POOL_SPIN);
        }
    } else {
        pthread_t forward_thread;
        int forward_live = 0;
        if (parallel && b && pthread_create(&forward_thread, NULL, ssa_forward_worker, &fb_job) == 0)
            forward_live = 1;
        ssa_forward_transform(&fa_job);
        if (b) {
            if (forward_live) pthread_join(forward_thread, NULL);
            else ssa_forward_transform(&fb_job);
        }
    }

    WSSAPointJob point_jobs[BN_SSA_PAR_THREADS > 0 ? BN_SSA_PAR_THREADS : 1];
    pthread_t point_workers[BN_SSA_PAR_THREADS > 1 ? BN_SSA_PAR_THREADS - 1 : 1];
    int point_live[BN_SSA_PAR_THREADS > 1 ? BN_SSA_PAR_THREADS - 1 : 1];
    for (int t = 0; t < point_threads; t++) {
        point_jobs[t].a = fa;
        point_jobs[t].b = b ? fb : NULL;
        point_jobs[t].start = L * t / point_threads;
        point_jobs[t].end = L * (t + 1) / point_threads;
        point_jobs[t].m = m;
        point_jobs[t].scratch = point_ws + (size_t)t * point_stride;
    }
    if (use_pool && point_threads > 1) {
        void *point_args[BN_SSA_PAR_THREADS > 0 ? BN_SSA_PAR_THREADS : 1];
        for (int t = 0; t < point_threads; t++)
            point_args[t] = &point_jobs[t];
        bn_pool_run_tasks(ssa_pointwise_task, point_args, point_threads,
                          BN_TOOM_POOL_SPIN);
    } else {
        for (int t = 1; t < point_threads; t++) {
            point_live[t - 1] =
                pthread_create(&point_workers[t - 1], NULL, ssa_pointwise_worker,
                               &point_jobs[t]) == 0;
            if (!point_live[t - 1]) ssa_pointwise_range(&point_jobs[t]);
        }
        ssa_pointwise_range(&point_jobs[0]);
        for (int t = 1; t < point_threads; t++)
            if (point_live[t - 1]) pthread_join(point_workers[t - 1], NULL);
    }

    /* Inverse DIT: both halves are independent through len=L/4; only the
     * final len=L/2 stage couples them. */
    if (use_pool) {
        WSSAInverseRangeJob left = {fa, 0, L / 2, 1, L / 4, m, K, t1, t2};
        WSSAInverseRangeJob right = {fa, L / 2, L, 1, L / 4, m, K, t3, t4};
        void *inverse_args[2] = {&left, &right};
        /* Last dispatch of the fused schedule: a long serial tail (final
         * stage, scaling, recompose) follows, so the worker parks at once. */
        bn_pool_run_tasks(ssa_inverse_range_task, inverse_args, 2, 0);
        WSSAInverseRangeJob final = {fa, 0, L, L / 2, L / 2, m, K, t1, t2};
        ssa_inverse_range(&final);
    } else if (parallel) {
        WSSAInverseRangeJob left = {fa, 0, L / 2, 1, L / 4, m, K, t1, t2};
        WSSAInverseRangeJob right = {fa, L / 2, L, 1, L / 4, m, K, t3, t4};
        pthread_t inverse_thread;
        int inverse_live =
            pthread_create(&inverse_thread, NULL, ssa_inverse_range_worker, &right) == 0;
        ssa_inverse_range(&left);
        if (inverse_live) pthread_join(inverse_thread, NULL);
        else ssa_inverse_range(&right);
        WSSAInverseRangeJob final = {fa, 0, L, L / 2, L / 2, m, K, t1, t2};
        ssa_inverse_range(&final);
    } else {
        WSSAInverseRangeJob inverse = {fa, 0, L, 1, L / 2, m, K, t1, t2};
        ssa_inverse_range(&inverse);
    }
#ifndef BN_SSA_NORMALIZE_RECOMPOSE_FUSED
#define BN_SSA_NORMALIZE_RECOMPOSE_FUSED 1
#endif
#if BN_SSA_NORMALIZE_RECOMPOSE_FUSED
    /* Normalize each used coefficient directly into recomposition. The inverse
     * transform has finished, and no later consumer needs normalized fa. */
    for (int32_t i = 0; i < outlen; i++) out[i] = 0;
    static const uint64_t ssa_one = 1;
    uint64_t normalize_shift = (2 * K - (uint64_t)klog) % (2 * K);
    for (long i = 0; i < L; i++) {
        int32_t base = (int32_t)i * w;
        if (base >= outlen) break;
        ssa_shl(t1, fa + i * S, normalize_shift, m, K);
        int32_t room = outlen - base;
        int32_t cl = m < room ? m : room;
        bn_addto(out + base, room, t1, cl);
        if (t1[m] && base + m < outlen)
            bn_addto(out + base + m, room - m, &ssa_one, 1);
    }
#else
    /* scale by 1/L = 2^(2K − klog)  (2^(2K) ≡ 1 in the ring) */
    for (long i = 0; i < L; i++) {
        ssa_shl(t1, fa + i * S, (2 * K - (uint64_t)klog) % (2 * K), m, K);
        for (int32_t x2 = 0; x2 <= m; x2++) fa[i * S + x2] = t1[x2];
    }

    /* recompose: out = Σ coeff_i · 2^(64·w·i); coefficients are exact (< 2^K
     * by the K ≥ 128w + log L + 2 bound ⇒ canonical value == true value). */
    for (int32_t i = 0; i < outlen; i++) out[i] = 0;
    static const uint64_t ssa_one = 1;
    for (long i = 0; i < L; i++) {
        int32_t base = (int32_t)i * w;
        if (base >= outlen) break;
        int32_t room = outlen - base;
        int32_t cl = m < room ? m : room;
        bn_addto(out + base, room, fa + i * S, cl);
        if (fa[i * S + m] && base + m < outlen)
            bn_addto(out + base + m, room - m, &ssa_one, 1);
    }
#endif
}


W_RT_INTERNAL void w_rt_bn_ntt_mul(uint64_t *out, const uint64_t *a, const uint64_t *b, int32_t n) {
    bn_ntt_mul(out, a, b, n);
}

W_RT_INTERNAL void w_rt_bn_ntt_sqr(uint64_t *out, const uint64_t *a, int32_t n) {
    bn_ntt_sqr(out, a, n);
}

W_RT_INTERNAL void w_rt_bn_ssa_mul(uint64_t *out, const uint64_t *a, int32_t na,
                                   const uint64_t *b, int32_t nb) {
    bn_ssa_mul(out, a, na, b, nb);
}

W_RT_INTERNAL int w_rt_bn_top_choice(int32_t na, int32_t nb, int square) {
    return bn_top_choice(na, nb, square);
}

W_RT_INTERNAL void w_rt_bigint_fft_release_thread(void) {
    free(w_ssa_ws);
    w_ssa_ws = NULL;
    w_ssa_ws_cap = 0;
    for (int i = 0; i < 2; i++) {
        free(w_ntt_workspace[i]);
        w_ntt_workspace[i] = NULL;
        w_ntt_workspace_cap[i] = 0;
    }
    for (int i = 0; i < 33; i++) {
        WNTTPlan *plan = w_ntt_plan_cache[i];
        if (!plan) continue;
        free(plan->tw_forward);
        free(plan->tw_inverse);
        free(plan);
        w_ntt_plan_cache[i] = NULL;
    }
}

#ifndef W_RUNTIME_UNITY_INCLUDE
#undef die
#undef bn_add_n
#undef bn_sub_n
#undef bn_addto
#undef bigint_mul_schoolbook_into
#undef bigint_mul_dispatch
#undef bigint_sqr_dispatch
#undef bn_pool_run_tasks
#undef bn_pool_env_int
#undef bn_ws_release_thread
#endif

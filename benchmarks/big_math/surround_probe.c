/* Surrounding-cost decomposition probe: where does non-math work tax the
 * math?  For representative matrix cells (add@4, mul1@8, mul@64, mod@128,
 * mul@4096) each stage of the boxed-op sandwich is timed in isolation:
 *
 *   full     boxed entry + observe + churn release (the matrix lane shape)
 *   wop      the polymorphic w_add/w_mul/w_mod entry above the bigint arm
 *   kernel   the raw limb kernel into preallocated buffers (the floor)
 *   alloc    pool take -> box -> release round trip at the result cap
 *   decode   w_bigint_view of both operands (nanbox + sign compose)
 *   observe  the benchmark's own result observation
 *
 * Per stage it reports wall ns/op (min over reps) plus exact instructions
 * and cycles per op via proc_pid_rusage two-point deltas (Apple's
 * RUSAGE_INFO_V4 counters; exact, not sampled).
 *
 * Alignment rider: the WBigint header is 16 B, so limbs start 16 B past
 * the allocation base and the first limb shares the header's cache line.
 * The `align` stages run the mul@4096 / add@8192 kernels with all limb
 * pointers at +16 (current layout) vs +64 (hypothetical padded header) of
 * 128-B-aligned blocks to price a 64-B-aligned-limbs redesign at kernel
 * level before any structural work.
 *
 * Build/run: benchmarks/big_math/run_surround.sh
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/resource.h>

#ifndef TUNGSTEN_RUNTIME_SOURCE
#define TUNGSTEN_RUNTIME_SOURCE "../../runtime/runtime.c"
#endif
#include TUNGSTEN_RUNTIME_SOURCE

static volatile uint64_t sink;

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static void counters(uint64_t *insts, uint64_t *cycles) {
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&ri) == 0) {
        *insts = ri.ri_instructions;
        *cycles = ri.ri_cycles;
    } else {
        *insts = 0;
        *cycles = 0;
    }
}

static uint64_t rng_state = 0x9E3779B97F4A7C15ULL;
static uint64_t rng(void) {
    uint64_t x = rng_state;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    rng_state = x;
    return x * 2685821657736338717ULL;
}

static WValue mk_bigint(int32_t n, uint64_t seed) {
    WBigint *b = bigint_alloc(n);
    rng_state = seed;
    for (int32_t i = 0; i < n; i++) b->limbs[i] = rng();
    b->limbs[0] |= 1ULL;
    b->limbs[n - 1] |= 1ULL << 63;
    b->size = n;
    return bigint_box(b);
}

static uint64_t observe(WValue v) {
    if (w_is_bigint(v)) {
        WBigint *b = w_as_bigint(v);
        return b->size ? b->limbs[0] : 0;
    }
    return (uint64_t)w_as_int(v);
}

/* min-of-reps timed loop + exact instruction/cycle deltas on the min rep */
#define STAGE(label, iters, reps, BODY) do {                               \
    double best = 1e30; uint64_t bi = 0, bc = 0;                           \
    for (int rep = 0; rep < (reps); rep++) {                               \
        uint64_t i0, c0, i1, c1;                                           \
        counters(&i0, &c0);                                                \
        double t0 = now_ns();                                              \
        for (int it = 0; it < (iters); it++) { BODY; }                     \
        double el = now_ns() - t0;                                         \
        counters(&i1, &c1);                                                \
        if (el < best) { best = el; bi = i1 - i0; bc = c1 - c0; }          \
    }                                                                      \
    printf("%-22s %10.2f ns/op %10.1f inst/op %9.1f cyc/op\n", (label),    \
           best / (iters), (double)bi / (iters), (double)bc / (iters));    \
    fflush(stdout);                                                        \
} while (0)

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    printf("== surround_probe: stage decomposition ==\n");

    /* ---------------- add@4 ---------------- */
    {
        WValue a = mk_bigint(4, 0x1111), b = mk_bigint(4, 0x2222);
        WValue prev = W_NIL;
        int I = 2000000, R = 9;
        STAGE("add4 full", I, R, {
            WValue r = bigint_add_any(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        prev = W_NIL;
        STAGE("add4 w_add", I, R, {
            WValue r = w_add(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        uint64_t rp[5];
        const uint64_t *ap = w_as_bigint(a)->limbs, *bp = w_as_bigint(b)->limbs;
        STAGE("add4 kernel bn_add_n", I, R, {
            rp[4] = bn_add_n(rp, ap, bp, 4);
            sink ^= rp[0];
        });
        STAGE("add4 alloc rt (cap5)", I, R, {
            WBigint *t = bigint_alloc_raw_hot(5);
            t->size = 5;
            WValue v = bigint_box(t);
            bigint_release_if_live(w_as_bigint(v));
        });
        int32_t s1, s2;
        STAGE("add4 decode 2 views", I, R, {
            WBigint *x = w_bigint_view(a, &s1);
            WBigint *y = w_bigint_view(b, &s2);
            sink ^= (uint64_t)(uintptr_t)x ^ (uint64_t)(uintptr_t)y ^
                    (uint64_t)(s1 + s2);
        });
        STAGE("add4 observe only", I, R, { sink ^= observe(a); });
        bigint_release_if_live(w_as_bigint(a));
        bigint_release_if_live(w_as_bigint(b));
    }

    /* ---------------- mul1@8 (8 limbs x 1 word) ---------------- */
    {
        WValue a = mk_bigint(8, 0x3333), b = mk_bigint(1, 0x4444);
        uint64_t w = w_as_bigint(b)->limbs[0];
        WValue prev = W_NIL;
        int I = 1500000, R = 9;
        STAGE("mul1_8 full ui_any", I, R, {
            WValue r = bigint_mul_ui_any(a, w);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        prev = W_NIL;
        STAGE("mul1_8 w_mul", I, R, {
            WValue r = w_mul(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        uint64_t rp[9];
        const uint64_t *ap = w_as_bigint(a)->limbs;
        STAGE("mul1_8 kernel bn_mul_1", I, R, {
            rp[8] = bn_mul_1(rp, ap, 8, w);
            sink ^= rp[0];
        });
        STAGE("mul1_8 alloc rt (cap9)", I, R, {
            WBigint *t = bigint_alloc_raw_hot(9);
            t->size = 9;
            WValue v = bigint_box(t);
            bigint_release_if_live(w_as_bigint(v));
        });
        bigint_release_if_live(w_as_bigint(a));
        bigint_release_if_live(w_as_bigint(b));
    }

    /* ---------------- mul@64 ---------------- */
    {
        WValue a = mk_bigint(64, 0x5555), b = mk_bigint(64, 0x6666);
        WValue prev = W_NIL;
        int I = 120000, R = 9;
        STAGE("mul64 full mul_any", I, R, {
            WValue r = bigint_mul_any(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        static uint64_t rp[130];
        const uint64_t *ap = w_as_bigint(a)->limbs, *bp = w_as_bigint(b)->limbs;
        STAGE("mul64 kernel dispatch", I, R, {
            bigint_mul_dispatch_cap(rp, 130, ap, 64, bp, 64);
            sink ^= rp[0];
        });
        STAGE("mul64 alloc rt (128)", I, R, {
            WBigint *t = bigint_alloc_raw_hot(128);
            t->size = 128;
            WValue v = bigint_box(t);
            bigint_release_if_live(w_as_bigint(v));
        });
        bigint_release_if_live(w_as_bigint(a));
        bigint_release_if_live(w_as_bigint(b));
    }

    /* ---------------- mod@128 (256/128) ---------------- */
    {
        WValue a = mk_bigint(256, 0x7777), b = mk_bigint(128, 0x8888);
        WValue prev = W_NIL;
        int I = 20000, R = 7;
        STAGE("mod128 full mod_any", I, R, {
            WValue r = bigint_mod_any(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        const uint64_t *ap = w_as_bigint(a)->limbs, *bp = w_as_bigint(b)->limbs;
        STAGE("mod128 mag_divmod", I, R, {
            WBigint *r = NULL;
            mag_divmod(ap, 256, bp, 128, NULL, &r);
            sink ^= r->size ? r->limbs[0] : 0;
            bigint_release(r);
        });
        STAGE("mod128 alloc rt (128)", I, R, {
            WBigint *t = bigint_alloc_raw_hot(128);
            t->size = 128;
            WValue v = bigint_box(t);
            bigint_release_if_live(w_as_bigint(v));
        });
        bigint_release_if_live(w_as_bigint(a));
        bigint_release_if_live(w_as_bigint(b));
    }

    /* ---------------- mul@4096 ---------------- */
    {
        WValue a = mk_bigint(4096, 0x9999), b = mk_bigint(4096, 0xAAAA);
        WValue prev = W_NIL;
        int I = 250, R = 7;
        STAGE("mul4096 full mul_any", I, R, {
            WValue r = bigint_mul_any(a, b);
            sink ^= observe(r);
            if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
            prev = r;
        });
        if (w_is_bigint(prev)) bigint_release_if_live(w_as_bigint(prev));
        static uint64_t rp4k[8194];
        const uint64_t *ap = w_as_bigint(a)->limbs, *bp = w_as_bigint(b)->limbs;
        STAGE("mul4096 kernel", I, R, {
            bigint_mul_dispatch_cap(rp4k, 8194, ap, 4096, bp, 4096);
            sink ^= rp4k[0];
        });
        STAGE("mul4096 alloc rt (8192)", 200000, 7, {
            WBigint *t = bigint_alloc_raw_hot(8192);
            t->size = 8192;
            WValue v = bigint_box(t);
            bigint_release_if_live(w_as_bigint(v));
        });
        bigint_release_if_live(w_as_bigint(a));
        bigint_release_if_live(w_as_bigint(b));
    }

    /* ---------------- alignment rider ---------------- */
    {
        printf("-- limbs at +16 (current header) vs +64 (padded header) --\n");
        size_t bytes = (size_t)(8192 + 16) * 8 + 128;
        uint64_t *ba = NULL, *bb = NULL, *br = NULL;
        posix_memalign((void **)&ba, 128, bytes);
        posix_memalign((void **)&bb, 128, bytes);
        posix_memalign((void **)&br, 128, bytes);
        rng_state = 0xBBBB;
        for (size_t i = 0; i < bytes / 8; i++) {
            ba[i] = rng(); bb[i] = rng();
        }
        /* +16 = limbs two words past a 128-aligned base (current layout);
         * +64 = limbs on their own cache line. */
        uint64_t *a16 = ba + 2, *b16 = bb + 2, *r16 = br + 2;
        uint64_t *a64 = ba + 8, *b64 = bb + 8, *r64 = br + 8;
        int I = 250, R = 7;
        STAGE("mul4096 kern +16", I, R, {
            bigint_mul_dispatch_cap(r16, 8194, a16, 4096, b16, 4096);
            sink ^= r16[0];
        });
        STAGE("mul4096 kern +64", I, R, {
            bigint_mul_dispatch_cap(r64, 8194, a64, 4096, b64, 4096);
            sink ^= r64[0];
        });
        int IA = 60000;
        STAGE("add8192 kern +16", IA, R, {
            uint64_t cy = bn_add_n(r16, a16, b16, 8192);
            sink ^= r16[0] ^ cy;
        });
        STAGE("add8192 kern +64", IA, R, {
            uint64_t cy = bn_add_n(r64, a64, b64, 8192);
            sink ^= r64[0] ^ cy;
        });
        STAGE("add4 kern +16", 2000000, 9, {
            uint64_t cy = bn_add_n(r16, a16, b16, 4);
            sink ^= r16[0] ^ cy;
        });
        STAGE("add4 kern +64", 2000000, 9, {
            uint64_t cy = bn_add_n(r64, a64, b64, 4);
            sink ^= r64[0] ^ cy;
        });
        free(ba); free(bb); free(br);
    }

    printf("sink=%llu\n", (unsigned long long)sink);
    return 0;
}

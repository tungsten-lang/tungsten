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
#ifndef TUNGSTEN_RUNTIME_SOURCE
#define TUNGSTEN_RUNTIME_SOURCE "../../runtime/runtime.c"
#endif
#include TUNGSTEN_RUNTIME_SOURCE

#include <sys/resource.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

/* Name the compile-time capacity policy this binary was built with, so the
 * real-allocation probes below are self-describing. */
#define BENCH_CAP_STR2(x) #x
#define BENCH_CAP_STR(x) BENCH_CAP_STR2(x)
#if BN_BIGINT_HYBRID_CAP && BN_BIGINT_HYBRID_MID_LIMIT
#define BENCH_CAP_BUILD_POLICY                                        \
    ("hybrid-p2" BENCH_CAP_STR(BN_BIGINT_HYBRID_P2_LIMIT)             \
     "-q" BENCH_CAP_STR(BN_BIGINT_HYBRID_QUANTUM)                     \
     "-mid" BENCH_CAP_STR(BN_BIGINT_HYBRID_MID_LIMIT)                 \
     "-q" BENCH_CAP_STR(BN_BIGINT_HYBRID_QUANTUM2))
#elif BN_BIGINT_HYBRID_CAP
#define BENCH_CAP_BUILD_POLICY                                        \
    ("hybrid-p2" BENCH_CAP_STR(BN_BIGINT_HYBRID_P2_LIMIT)             \
     "-q" BENCH_CAP_STR(BN_BIGINT_HYBRID_QUANTUM))
#elif BN_BIGINT_POWER2_CAP
#define BENCH_CAP_BUILD_POLICY "power-of-two"
#else
#define BENCH_CAP_BUILD_POLICY "exact"
#endif

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

static WValue bench_bigint(int32_t n, uint64_t seed);
static void bench_free_value(WValue value);

typedef struct {
    _Atomic(uint64_t) *slot;
    pthread_mutex_t *lock;
    _Atomic(int) *ready;
    _Atomic(int) *go;
    int updates;
    int use_cas;
} BenchAtomicBigintJob;

static void *bench_atomic_bigint_worker(void *opaque) {
    BenchAtomicBigintJob *job = (BenchAtomicBigintJob *)opaque;
    atomic_fetch_add_explicit(job->ready, 1, memory_order_release);
    while (!atomic_load_explicit(job->go, memory_order_acquire))
        sched_yield();
    WValue one = w_box_int(1);
    for (int i = 0; i < job->updates; i++) {
        if (!job->use_cas) {
            pthread_mutex_lock(job->lock);
            WValue old = (WValue)atomic_load_explicit(
                job->slot, memory_order_relaxed);
            WValue next = w_bigint_add_mut(old, one);
            atomic_store_explicit(
                job->slot, (uint64_t)next, memory_order_relaxed);
            if (next != old) bench_free_value(old);
            pthread_mutex_unlock(job->lock);
            continue;
        }
        for (;;) {
            uint64_t observed = atomic_load_explicit(
                job->slot, memory_order_acquire);
            WValue next = bigint_add_any((WValue)observed, one);
            uint64_t expected = observed;
            if (atomic_compare_exchange_weak_explicit(
                    job->slot, &expected, (uint64_t)next,
                    memory_order_release, memory_order_acquire)) {
                /* Published immutable values cannot be reclaimed without a
                 * hazard-pointer/epoch scheme: another contender may still
                 * hold `observed`.  Deliberately retain winners so this is a
                 * safe upper-bound prototype rather than a UAF benchmark. */
                break;
            }
            bench_free_value(next);
        }
    }
    return NULL;
}

static double bench_atomic_bigint_counter(
    int threads, int updates, int use_cas, uint64_t *checksum) {
    WValue initial = bench_bigint(2, UINT64_C(0x4a6f7921cafe1234));
    uint64_t initial_low = (uint64_t)integer_low_i64(initial);
    _Atomic(uint64_t) slot;
    atomic_init(&slot, (uint64_t)initial);
    pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    _Atomic(int) ready;
    _Atomic(int) go;
    atomic_init(&ready, 0);
    atomic_init(&go, 0);
    pthread_t workers[16];
    BenchAtomicBigintJob jobs[16];
    for (int t = 0; t < threads; t++) {
        jobs[t] = (BenchAtomicBigintJob){
            .slot = &slot, .lock = &lock, .ready = &ready, .go = &go,
            .updates = updates, .use_cas = use_cas,
        };
        if (pthread_create(
                &workers[t], NULL, bench_atomic_bigint_worker, &jobs[t]) != 0)
            die("atomic bigint benchmark could not create worker");
    }
    while (atomic_load_explicit(&ready, memory_order_acquire) < threads)
        sched_yield();
    double started = bench_now();
    atomic_store_explicit(&go, 1, memory_order_release);
    for (int t = 0; t < threads; t++) pthread_join(workers[t], NULL);
    double elapsed = bench_now() - started;
    WValue result = (WValue)atomic_load_explicit(&slot, memory_order_acquire);
    uint64_t observed = (uint64_t)integer_low_i64(result);
    uint64_t expected = initial_low + (uint64_t)threads * (uint64_t)updates;
    if (observed != expected)
        dief("atomic bigint counter mismatch: got %llu expected %llu",
             (unsigned long long)observed, (unsigned long long)expected);
    *checksum = observed;
    /* Mutex mode owns exactly one live result. CAS mode intentionally retains
     * all published generations until process exit, as documented above. */
    if (!use_cas) bench_free_value(result);
    pthread_mutex_destroy(&lock);
    return elapsed * 1e9 / ((double)threads * (double)updates);
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

/* Trailing-zero fixture: TOTAL n limbs with the low z limbs zero (a
 * multiple of B^z), the stripped low limb odd, top bit set. z == 0
 * degenerates to bench_bigint's shape (the control cell). */
static WValue bench_bigint_tz(int32_t n, int32_t z, uint64_t seed) {
    WBigint *b = bigint_alloc(n);
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++)
        b->limbs[i] = i < z ? 0 : bench_rng(&state);
    b->limbs[z] |= 1ULL;
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

/* Direct-lane free that honors the tag-alias count (v4): abs/neg lanes
 * hold tag ALIASES of their fixtures in `previous`, and a raw free() there
 * killed the fixture's buffer under the next iteration (ASAN UAF at
 * abs@1). An aliased buffer dies only with its last reference; the
 * non-recycle lanes keep their free-not-park semantics for unaliased
 * buffers. */
static void bench_direct_free(WBigint *b) {
    if (b->shared) {
        if (b->shared != 255) b->shared--;
        return;
    }
    bigint_backing_free(b);
}

static void bench_free_value(WValue value) {
    /* Tag-sign overlays (v4) mean a bitwise-distinct result can share its
     * buffer with a fixture (`abs`/`neg` return aliases): raw free() here
     * double-freed. Route through the alias-counting release so the buffer
     * dies exactly once, when its last reference is freed. */
    if (w_is_bigint(value)) bigint_release_if_live(w_as_bigint(value));
}

static WValue bench_bigint_with_capacity(
    int32_t n, int32_t capacity, uint64_t seed) {
    WBigint *b = bigint_alloc_raw(capacity);
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) b->limbs[i] = bench_rng(&state);
    b->limbs[0] |= 1ULL;
    b->limbs[n - 1] |= UINT64_C(1) << 63;
    b->size = n;
    return bigint_box(b);
}

static void bench_consumed_bitwise_apply(char op, WBigint *a,
                                         const WBigint *b) {
    int32_t n = a->size;
    for (int32_t i = 0; i < n; i++)
        a->limbs[i] = apply_bitop(op, a->limbs[i], b->limbs[i]);
    while (n > 0 && a->limbs[n - 1] == 0) n--;
    a->size = n;
}

static void bench_consumed_shift_cycle(WBigint *a, unsigned shift) {
    int32_t n = a->size;
    uint64_t carry = a->limbs[n - 1] >> (64U - shift);
    for (int32_t i = n - 1; i > 0; i--)
        a->limbs[i] =
            (a->limbs[i] << shift) |
            (a->limbs[i - 1] >> (64U - shift));
    a->limbs[0] <<= shift;
    if (carry) a->limbs[n++] = carry;
    for (int32_t i = 0; i + 1 < n; i++)
        a->limbs[i] =
            (a->limbs[i] >> shift) |
            (a->limbs[i + 1] << (64U - shift));
    a->limbs[n - 1] >>= shift;
    if (n > 1 && a->limbs[n - 1] == 0) n--;
    a->size = n;
}

static void bench_pow3_dest(WBigint *dest, const WBigint *base,
                            uint64_t *square) {
    int32_t n = base->size;
    bigint_sqr_dispatch(square, base->limbs, n);
    int32_t sn = 2 * n;
    while (sn > 1 && square[sn - 1] == 0) sn--;
    bigint_mul_dispatch(dest->limbs, square, sn, base->limbs, n);
    int32_t outn = sn + n;
    while (outn > 1 && dest->limbs[outn - 1] == 0) outn--;
    dest->size = outn;
}

static double bench_consumed_operation(
    const char *operation, int32_t limbs, int iterations, int consume,
    uint64_t *checksum) {
    WValue seed = bench_bigint_with_capacity(
        limbs, 4 * limbs,
        UINT64_C(0x4f7065726174696f) ^ (uint64_t)limbs);
    WValue operand = bench_bigint(
        limbs, UINT64_C(0x6e44657374696e61) ^ (uint64_t)limbs);
    WBigint *ob = w_as_bigint(operand);
    WValue shift = w_box_int(13);
    if (strcmp(operation, "and") == 0) {
        for (int32_t i = 0; i < limbs; i++) ob->limbs[i] = UINT64_MAX;
    } else if (strcmp(operation, "or") == 0 ||
               strcmp(operation, "xor") == 0) {
        ob->limbs[limbs - 1] &= ~(UINT64_C(1) << 63);
        ob->limbs[limbs - 1] |= UINT64_C(1) << 62;
    }
    WValue value = consume
        ? bench_bigint_with_capacity(
              limbs, 4 * limbs,
              UINT64_C(0x4f7065726174696f) ^ (uint64_t)limbs)
        : bench_clone_integer(seed);
    uint64_t *square = NULL;
    if (strcmp(operation, "pow3") == 0) {
        square = (uint64_t *)malloc((size_t)(2 * limbs) * sizeof(uint64_t));
        if (!square) die("out of memory preparing consumed power benchmark");
        bench_free_value(value);
        value = bench_bigint_with_capacity(
            1, 4 * limbs, UINT64_C(0x506f773344657374));
        w_as_bigint(value)->size = 0;
        bench_pow3_dest(w_as_bigint(value), w_as_bigint(seed), square);
        WValue expected = w_pow(seed, w_box_int(3));
        if (bigint_compare(value, expected) != 0)
            die("consumed pow3 destination mismatch");
        bench_free_value(expected);
    }

    double started = bench_now();
    if (consume) {
        WBigint *destination = w_as_bigint(value);
        for (int i = 0; i < iterations; i++) {
            if (strcmp(operation, "and") == 0)
                bench_consumed_bitwise_apply('&', destination, ob);
            else if (strcmp(operation, "or") == 0)
                bench_consumed_bitwise_apply('|', destination, ob);
            else if (strcmp(operation, "xor") == 0)
                bench_consumed_bitwise_apply('^', destination, ob);
            else if (strcmp(operation, "shift") == 0)
                bench_consumed_shift_cycle(destination, 13);
            else
                bench_pow3_dest(destination, w_as_bigint(seed), square);
            bench_sink ^= destination->limbs[0] ^ (uint64_t)i;
        }
    } else {
        if (strcmp(operation, "pow3") == 0) {
            bench_free_value(value);
            value = w_box_int(0);
            for (int i = 0; i < iterations; i++) {
                WValue next = w_pow(seed, w_box_int(3));
                if (w_is_bigint(value)) bench_free_value(value);
                value = next;
                bench_sink ^= (uint64_t)integer_low_i64(value) ^ (uint64_t)i;
            }
        } else {
            for (int i = 0; i < iterations; i++) {
                WValue next;
                if (strcmp(operation, "and") == 0)
                    next = w_bit_and(value, operand);
                else if (strcmp(operation, "or") == 0)
                    next = w_bit_or(value, operand);
                else if (strcmp(operation, "xor") == 0)
                    next = w_bit_xor(value, operand);
                else {
                    WValue left = w_bit_shl(value, shift);
                    next = w_bit_shr(left, shift);
                    bench_free_value(left);
                }
                bench_free_value(value);
                value = next;
                bench_sink ^= (uint64_t)integer_low_i64(value) ^ (uint64_t)i;
            }
        }
    }
    double ns = (bench_now() - started) * 1e9 / (double)iterations;
    *checksum = (uint64_t)integer_low_i64(value);
    bench_free_value(value);
    bench_free_value(seed);
    bench_free_value(operand);
    free(square);
    return ns;
}

static int bench_iters_for_limbs(int32_t limbs) {
    if (limbs <= 8) return 2000000;
    if (limbs <= 16) return 500000;
    if (limbs <= 64) return 100000;
    if (limbs <= 256) return 10000;
    if (limbs <= 1024) return 1000;
    if (limbs <= 4096) return 100;
    if (limbs <= 8192) return 40;
    return 20;
}

static int bench_iters_for_mod(int32_t limbs) {
    if (limbs <= 4) return 200000;
    if (limbs <= 16) return 50000;
    if (limbs <= 64) return 10000;
    if (limbs <= 256) return 1000;
    if (limbs <= 1024) return 100;
    return 30;
}

static int bench_iters_for_linear(int32_t limbs) {
    if (limbs <= 4) return 2000000;
    if (limbs <= 16) return 1000000;
    if (limbs <= 64) return 300000;
    if (limbs <= 256) return 100000;
    if (limbs <= 1024) return 20000;
    return 5000;
}

static int bench_iters_for_boxed_linear(int32_t limbs) {
    if (limbs <= 16) return 500000;
    if (limbs <= 64) return 300000;
    if (limbs <= 256) return 200000;
    if (limbs <= 1024) return 100000;
    return 20000;
}

static int bench_iters_for_divmod(int32_t limbs) {
    if (limbs <= 4) return 500000;
    if (limbs <= 16) return 100000;
    if (limbs <= 64) return 20000;
    if (limbs <= 256) return 5000;
    if (limbs <= 1024) return 500;
    return 100;
}

static int bench_iters_for_gcd(int32_t limbs) {
    if (limbs <= 4) return 100000;
    if (limbs <= 16) return 20000;
    if (limbs <= 64) return 5000;
    if (limbs <= 256) return 500;
    if (limbs <= 1024) return 100;
    return 20;
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

static double bench_tungsten_add(const uint64_t *a, const uint64_t *b,
                                 int32_t limbs, int iters) {
    uint64_t *out = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!out) die("out of memory in add benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t carry = bn_add_n(out, a, b, limbs);
        bench_sink ^= out[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(out);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_sub(const uint64_t *a, const uint64_t *b,
                                 int32_t limbs, int iters) {
    uint64_t *out = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!out) die("out of memory in subtract benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t borrow = bn_sub_n(out, a, b, limbs);
        bench_sink ^= out[(unsigned)i % (unsigned)limbs] ^ borrow ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(out);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_cmp(const uint64_t *a, const uint64_t *b,
                                 int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= (uint64_t)(bn_cmp_n(a, b, limbs) + 1) + (uint64_t)i;
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

/* The previous compiler-scheduled four-limb ARM64 kernel, retained here as a
 * benchmark oracle while tuning the production leaf-assembly pipeline. */
static uint64_t bench_addmul_1_old(uint64_t *rp, const uint64_t *up,
                                   int32_t n, uint64_t v) {
    uint64_t carry = 0;
    int32_t i = 0;
#if defined(__aarch64__)
    for (; i + 4 <= n; i += 4) {
        __uint128_t p0 = (__uint128_t)up[i] * v;
        __uint128_t p1 = (__uint128_t)up[i + 1] * v;
        __uint128_t p2 = (__uint128_t)up[i + 2] * v;
        __uint128_t p3 = (__uint128_t)up[i + 3] * v;
        uint64_t l0 = (uint64_t)p0, h0 = (uint64_t)(p0 >> 64);
        uint64_t l1 = (uint64_t)p1, h1 = (uint64_t)(p1 >> 64);
        uint64_t l2 = (uint64_t)p2, h2 = (uint64_t)(p2 >> 64);
        uint64_t l3 = (uint64_t)p3, h3 = (uint64_t)(p3 >> 64);
        uint64_t r0 = rp[i], r1 = rp[i + 1], r2 = rp[i + 2], r3 = rp[i + 3];
        uint64_t s0, s1, s2, s3;
        __asm__("adds %[s0], %[l0], %[cy]\n\t"
                "adcs %[s1], %[l1], %[h0]\n\t"
                "adcs %[s2], %[l2], %[h1]\n\t"
                "adcs %[s3], %[l3], %[h2]\n\t"
                "adc  %[cy], %[h3], xzr\n\t"
                "adds %[r0], %[r0], %[s0]\n\t"
                "adcs %[r1], %[r1], %[s1]\n\t"
                "adcs %[r2], %[r2], %[s2]\n\t"
                "adcs %[r3], %[r3], %[s3]\n\t"
                "adc  %[cy], %[cy], xzr"
                : [s0] "=&r"(s0), [s1] "=&r"(s1), [s2] "=&r"(s2), [s3] "=&r"(s3),
                  [r0] "+&r"(r0), [r1] "+&r"(r1), [r2] "+&r"(r2), [r3] "+&r"(r3),
                  [cy] "+&r"(carry)
                : [l0] "r"(l0), [l1] "r"(l1), [l2] "r"(l2), [l3] "r"(l3),
                  [h0] "r"(h0), [h1] "r"(h1), [h2] "r"(h2), [h3] "r"(h3)
                : "cc");
        rp[i] = r0; rp[i + 1] = r1; rp[i + 2] = r2; rp[i + 3] = r3;
    }
#endif
    for (; i < n; i++) {
        __uint128_t p = (__uint128_t)up[i] * v + rp[i] + carry;
        rp[i] = (uint64_t)p;
        carry = (uint64_t)(p >> 64);
    }
    return carry;
}

typedef uint64_t (*bench_addmul_1_fn)(uint64_t *, const uint64_t *, int32_t, uint64_t);

static double bench_tungsten_mul_1(bench_addmul_1_fn fn,
                                   const uint64_t *up,
                                   int32_t limbs, int iters) {
    uint64_t *rp = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!rp) die("out of memory in mul_1 benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t carry = fn(rp, up, limbs, 0xd6e8feb86659fd93ULL);
        bench_sink ^= rp[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(rp);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_addmul_1(bench_addmul_1_fn fn,
                                      const uint64_t *rp0, const uint64_t *up,
                                      int32_t limbs, int iters) {
    uint64_t *rp = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!rp) die("out of memory in addmul_1 benchmark");
    memcpy(rp, rp0, (size_t)limbs * sizeof(uint64_t));
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t carry = fn(rp, up, limbs, 0xd6e8feb86659fd93ULL);
        bench_sink ^= rp[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(rp);
    return elapsed * 1e9 / (double)iters;
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

static double bench_tungsten_mul_rect(
    const uint64_t *a0, int32_t na, const uint64_t *b, int32_t nb,
    int iters) {
    uint64_t *a = (uint64_t *)malloc((size_t)na * sizeof(uint64_t));
    uint64_t *out =
        (uint64_t *)calloc((size_t)na + (size_t)nb + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in rectangular multiply benchmark");
    memcpy(a, a0, (size_t)na * sizeof(uint64_t));
    uint64_t saved = a[0];
    bigint_mul_dispatch(out, a, na, b, nb);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        bigint_mul_dispatch(out, a, na, b, nb);
        bench_sink ^= out[(unsigned)i % ((unsigned)na + (unsigned)nb)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_mul_serial(const uint64_t *a0, const uint64_t *b,
                                        int32_t limbs, int iters) {
    bn_toom_parallel_depth++;
    double elapsed = bench_tungsten_mul(a0, b, limbs, iters);
    bn_toom_parallel_depth--;
    return elapsed;
}

static double bench_tungsten_mul_ladder(
    const uint64_t *a0, const uint64_t *b, int32_t limbs,
    int iters, int kernel) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out =
        (uint64_t *)malloc(((size_t)limbs * 2 + 4) * sizeof(uint64_t));
    size_t scratch_limbs = (size_t)limbs * 128 + 4096;
    uint64_t *scratch =
        (uint64_t *)malloc(scratch_limbs * sizeof(uint64_t));
    if (!a || !out || !scratch)
        die("out of memory in multiply ladder benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        switch (kernel) {
        case 0: bn_toom2_diff(out, a, b, limbs, scratch); break;
        case 1: bn_toom2_sum(out, a, b, limbs, scratch); break;
        case 2: bn_toom3(out, a, b, limbs, scratch); break;
        default: bn_toom4(out, a, b, limbs, scratch); break;
        }
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(scratch);
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

static double bench_tungsten_sqr_path(const uint64_t *a0, int32_t limbs,
                                      int iters, int karatsuba) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2 + 4, sizeof(uint64_t));
    if (!a || !out) die("out of memory in square path benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    if (karatsuba) bn_sqr_top_kara(out, a, limbs);
    else bn_sqr_school(out, a, limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        if (karatsuba) bn_sqr_top_kara(out, a, limbs);
        else bn_sqr_school(out, a, limbs);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_sqr_ladder(const uint64_t *a0, int32_t limbs,
                                        int iters, int kernel) {
    uint64_t *a = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)malloc(((size_t)limbs * 2 + 4) * sizeof(uint64_t));
    size_t scratch_limbs = (size_t)limbs * 128 + 4096;
    uint64_t *scratch = (uint64_t *)malloc(scratch_limbs * sizeof(uint64_t));
    if (!a || !out || !scratch) die("out of memory in square ladder benchmark");
    memcpy(a, a0, (size_t)limbs * sizeof(uint64_t));
    uint64_t saved = a[0];
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        if (kernel == 2) bn_toom4_sq(out, a, limbs, scratch);
        else if (kernel == 1) bn_toom3_sq(out, a, limbs, scratch);
        else bn_kara_sq(out, a, limbs, scratch);
        bench_sink ^= out[(unsigned)i % ((unsigned)limbs * 2U)];
    }
    double elapsed = bench_now() - start;
    free(scratch);
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_sqr_serial(const uint64_t *a0, int32_t limbs,
                                        int iters) {
    bn_toom_parallel_depth++;
    double elapsed = bench_tungsten_sqr(a0, limbs, iters);
    bn_toom_parallel_depth--;
    return elapsed;
}

static double bench_tungsten_mod1(const uint64_t *a, int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= mag_mod_single(a, limbs, 1000000007ULL + (uint64_t)(i & 1));
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

/* Previous small-divisor path: two reciprocal reductions per input limb. */
static uint64_t bench_mag_mod_single_serial32(const uint64_t *a, int32_t alen,
                                              uint64_t d) {
    if (d == 1) return 0;
    if ((d & (d - 1)) == 0) return alen > 0 ? (a[0] & (d - 1)) : 0;
    if (d <= UINT32_MAX) {
        uint64_t reciprocal = UINT64_MAX / d;
        if (UINT64_MAX % d == d - 1) reciprocal++;
        uint64_t r = 0;
        for (int32_t i = alen - 1; i >= 0; i--) {
            uint64_t x = (r << 32) | (a[i] >> 32);
            uint64_t q = (uint64_t)(((__uint128_t)x * reciprocal) >> 64);
            r = x - q * d;
            if (r >= d) r -= d;
            x = (r << 32) | (a[i] & UINT32_MAX);
            q = (uint64_t)(((__uint128_t)x * reciprocal) >> 64);
            r = x - q * d;
            if (r >= d) r -= d;
        }
        return r;
    }
    __uint128_t r = 0;
    for (int32_t i = alen - 1; i >= 0; i--) {
        r = (r << 64) | a[i];
        r %= d;
    }
    return (uint64_t)r;
}

static double bench_tungsten_mod1_serial32(const uint64_t *a, int32_t limbs,
                                           int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= bench_mag_mod_single_serial32(a, limbs,
                                                    1000000007ULL + (uint64_t)(i & 1));
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static uint64_t bench_mag_mod_single_block(const uint64_t *a, int32_t alen,
                                           uint64_t d, int block) {
    uint64_t reciprocal = UINT64_MAX / d;
    uint64_t rem_max = UINT64_MAX - reciprocal * d;
    if (rem_max == d - 1) reciprocal++;
    uint64_t bmod = rem_max + 1;
    if (bmod == d) bmod = 0;
    uint64_t pow_b[33];
    pow_b[0] = 1;
    for (int i = 1; i <= block; i++)
        pow_b[i] = mag_reduce_u64_recip(pow_b[i - 1] * bmod, d, reciprocal);

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
        r = mag_reduce_u64_recip(hi_rem * bmod + lo_rem, d, reciprocal);
        pos = base;
        width = block;
    }
    return r;
}

static double bench_tungsten_mod1_block(const uint64_t *a, int32_t limbs,
                                        int block, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++)
        bench_sink ^= bench_mag_mod_single_block(
            a, limbs, 1000000007ULL + (uint64_t)(i & 1), block);
    return (bench_now() - start) * 1e9 / (double)iters;
}

static uint64_t bench_mag_mod_single_block_cached(const uint64_t *a, int32_t alen,
                                                  uint64_t d, int block) {
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
        r = mag_reduce_u64_recip(hi_rem * bmod + lo_rem, d, reciprocal);
        pos = base;
        width = block;
    }
    return r;
}

static double bench_tungsten_mod1_block_cached(const uint64_t *a, int32_t limbs,
                                               int block, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++)
        bench_sink ^= bench_mag_mod_single_block_cached(
            a, limbs, 1000000007ULL + (uint64_t)(i & 1), block);
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

static double bench_tungsten_divmod(const uint64_t *u, const uint64_t *v,
                                    int32_t limbs, int iters) {
    bigint_pool_release_thread();
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WBigint *q, *r;
        mag_divmod(u, 2 * limbs, v, limbs, &q, &r);
        unsigned qi = q->size > 0 ? (unsigned)i % (unsigned)q->size : 0;
        unsigned ri = r->size > 0 ? (unsigned)i % (unsigned)r->size : 0;
        bench_sink ^= (q->size > 0 ? q->limbs[qi] : 0) ^
                      (r->size > 0 ? r->limbs[ri] : 0) ^ (uint64_t)i;
        bigint_release(q);
        bigint_release(r);
    }
    double elapsed = bench_now() - start;
    bigint_pool_release_thread();
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_divmod_path(const uint64_t *u, const uint64_t *v,
                                         int32_t limbs, int iters, int path) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WBigint *q, *r;
        if (path == 1)
            mag_divmod_knuth(u, 2 * limbs, v, limbs, &q, &r);
        else
            mag_divmod_bz(u, 2 * limbs, v, limbs, &q, &r);
        unsigned qi = q->size > 0 ? (unsigned)i % (unsigned)q->size : 0;
        unsigned ri = r->size > 0 ? (unsigned)i % (unsigned)r->size : 0;
        bench_sink ^= (q->size > 0 ? q->limbs[qi] : 0) ^
                      (r->size > 0 ? r->limbs[ri] : 0) ^ (uint64_t)i;
        bigint_backing_free(q);
        bigint_backing_free(r);
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static double bench_tungsten_divmod_into(const uint64_t *u, const uint64_t *v,
                                         int32_t limbs, int iters) {
    uint64_t *q = (uint64_t *)malloc(((size_t)limbs + 1) * sizeof(uint64_t));
    uint64_t *r = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!q || !r) die("out of memory in Tungsten divmod-into benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bz_base_div_into(u, 2 * limbs, v, limbs,
                         q, limbs + 1, r, limbs, 0);
        bench_sink ^= q[(unsigned)i % (unsigned)(limbs + 1)] ^
                      r[(unsigned)i % (unsigned)limbs] ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(q);
    free(r);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_submul1(const uint64_t *u, const uint64_t *r0,
                                     int32_t limbs, uint64_t v, int iters) {
    uint64_t *r = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!r) die("out of memory in Tungsten submul1 benchmark");
    memcpy(r, r0, (size_t)limbs * sizeof(uint64_t));
    uint64_t borrow = 0;
    double start = bench_now();
    for (int i = 0; i < iters; i++)
        borrow ^= bn_submul_1(r, u, limbs, v);
    double elapsed = bench_now() - start;
    bench_sink ^= borrow ^ r[(unsigned)iters % (unsigned)limbs];
    free(r);
    return elapsed * 1e9 / (double)iters;
}

static void bench_gcd_operands(int32_t limbs, WValue *a_out, WValue *b_out) {
    WValue common = bench_bigint(limbs, 0xd6e8feb86659fd93ULL ^ (uint64_t)limbs);
    *a_out = bigint_mul_any(common, w_box_int(65537));
    *b_out = bigint_mul_any(common, w_box_int(65539));
    bench_free_value(common);
}

static void bench_gcd_random_operands(int32_t limbs, WValue *a_out, WValue *b_out) {
    *a_out = bench_bigint(limbs, 0x3f84d5b5b5470917ULL ^ (uint64_t)limbs);
    *b_out = bench_bigint(limbs, 0x9216d5d98979fb1bULL ^ (uint64_t)limbs);
}

#ifndef BN_BENCH_GCD_RECYCLE
#define BN_BENCH_GCD_RECYCLE 1
#endif

#ifdef BN_GCD_PROFILE_COUNTS
static void bench_gcd_profile_reset(void) {
    gcd_profile_sim_calls = 0;
    gcd_profile_sim_steps = 0;
    gcd_profile_fast_q1 = 0;
    gcd_profile_pair_calls = 0;
    gcd_profile_pair_limbs = 0;
    gcd_profile_matrix_products = 0;
    gcd_profile_matrix_product_work = 0;
    memset(gcd_profile_matrix_product_bins, 0,
           sizeof(gcd_profile_matrix_product_bins));
    gcd_profile_hgcd_top_calls = 0;
    gcd_profile_hgcd_top_ok = 0;
    gcd_profile_hgcd_top_xlen = 0;
    gcd_profile_child_calls = 0;
    gcd_profile_child_ok = 0;
    gcd_profile_child_removed = 0;
    memset(gcd_profile_block_calls, 0, sizeof(gcd_profile_block_calls));
    memset(gcd_profile_block_ok, 0, sizeof(gcd_profile_block_ok));
    memset(gcd_profile_block_removed, 0, sizeof(gcd_profile_block_removed));
    memset(gcd_profile_block_batches, 0, sizeof(gcd_profile_block_batches));
    memset(gcd_profile_block_batch_limbs, 0,
           sizeof(gcd_profile_block_batch_limbs));
    memset(gcd_profile_ctx_work, 0, sizeof(gcd_profile_ctx_work));
    memset(gcd_profile_block_fail, 0, sizeof(gcd_profile_block_fail));
    memset(gcd_profile_block_fail_xlen, 0,
           sizeof(gcd_profile_block_fail_xlen));
}

static void bench_gcd_profile_print(void) {
    printf("  hgcd top=%llu ok=%llu avg-xlen=%.1f"
           " child=%llu ok=%llu removed=%llu\n",
           (unsigned long long)gcd_profile_hgcd_top_calls,
           (unsigned long long)gcd_profile_hgcd_top_ok,
           gcd_profile_hgcd_top_calls
               ? (double)gcd_profile_hgcd_top_xlen /
                     (double)gcd_profile_hgcd_top_calls
               : 0.0,
           (unsigned long long)gcd_profile_child_calls,
           (unsigned long long)gcd_profile_child_ok,
           (unsigned long long)gcd_profile_child_removed);
    printf("  blocks scalar=%llu/%llu removed=%llu batches=%llu/%llu"
           " recursive=%llu/%llu removed=%llu batches=%llu/%llu\n",
           (unsigned long long)gcd_profile_block_ok[0],
           (unsigned long long)gcd_profile_block_calls[0],
           (unsigned long long)gcd_profile_block_removed[0],
           (unsigned long long)gcd_profile_block_batches[0],
           (unsigned long long)gcd_profile_block_batch_limbs[0],
           (unsigned long long)gcd_profile_block_ok[1],
           (unsigned long long)gcd_profile_block_calls[1],
           (unsigned long long)gcd_profile_block_removed[1],
           (unsigned long long)gcd_profile_block_batches[1],
           (unsigned long long)gcd_profile_block_batch_limbs[1]);
    printf("  matrix work tree=%llu apply=%llu acc=%llu fails",
           (unsigned long long)gcd_profile_ctx_work[0],
           (unsigned long long)gcd_profile_ctx_work[1],
           (unsigned long long)gcd_profile_ctx_work[2]);
    for (int ar = 0; ar < 2; ar++) {
        printf(" %c:", ar ? 'r' : 's');
        for (int reason = 0; reason < 6; reason++)
            printf("%s%llu", reason ? "," : "",
                   (unsigned long long)gcd_profile_block_fail[ar][reason]);
    }
    printf("\n");
}
#endif

static double bench_tungsten_gcd(int32_t limbs, int iters) {
    WValue a, b;
    bench_gcd_operands(limbs, &a, &b);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue g = bigint_gcd_any(a, b);
        bench_sink ^= (uint64_t)integer_low_i64(g) ^ (uint64_t)i;
        /* GMP reuses zg across iterations.  Return Tungsten's dead immutable
         * result through the runtime handoff so its limb capacity is likewise
         * available to the next GCD result. */
        if (g != a && g != b) {
#if BN_BENCH_GCD_RECYCLE
            w_value_free(g);
#else
            bench_free_value(g);
#endif
        }
    }
    double elapsed = bench_now() - start;
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_gcd_random(int32_t limbs, int iters) {
    WValue a, b;
    bench_gcd_random_operands(limbs, &a, &b);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue g = bigint_gcd_any(a, b);
        bench_sink ^= (uint64_t)integer_low_i64(g) ^ (uint64_t)i;
        if (g != a && g != b) {
#if BN_BENCH_GCD_RECYCLE
            w_value_free(g);
#else
            bench_free_value(g);
#endif
        }
    }
    double elapsed = bench_now() - start;
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
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

static double bench_tungsten_bitwise(char op, int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0x082efa98ec4e6c89ULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x452821e638d01377ULL ^ (uint64_t)limbs);
    WValue warm = bignum_bitwise(op, a, b);
    w_value_free(warm);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = bignum_bitwise(op, a, b);
        bench_sink ^= (uint64_t)integer_low_i64(r) ^ (uint64_t)i;
        w_value_free(r);
    }
    double elapsed = bench_now() - start;
    bigint_pool_release_thread();
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_tungsten_shift(int left, int32_t limbs, int iters) {
    WValue a = bench_bigint(limbs, 0xbe5466cf34e90c6cULL ^ (uint64_t)limbs);
    WValue warm = left ? bignum_shl(a, 13) : bignum_shr(a, 13);
    w_value_free(warm);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = left ? bignum_shl(a, 13) : bignum_shr(a, 13);
        bench_sink ^= (uint64_t)integer_low_i64(r) ^ (uint64_t)i;
        w_value_free(r);
    }
    double elapsed = bench_now() - start;
    bigint_pool_release_thread();
    bench_free_value(a);
    return elapsed * 1e9 / (double)iters;
}

enum {
    BENCH_BOXED_ADD,
    BENCH_BOXED_SUB,
    BENCH_BOXED_MUL,
    BENCH_BOXED_SQR,
    BENCH_BOXED_DIV,
    BENCH_BOXED_MOD,
    BENCH_BOXED_AND,
    BENCH_BOXED_OR,
    BENCH_BOXED_XOR,
    BENCH_BOXED_SHL,
    BENCH_BOXED_SHR,
    BENCH_BOXED_GCD,
    BENCH_BOXED_CMP,
    BENCH_BOXED_NEG,
    BENCH_BOXED_ABS,
    BENCH_BOXED_NEG_BANG,
    BENCH_BOXED_ABS_BANG,
    BENCH_BOXED_POW,
    BENCH_BOXED_POWMOD,
    BENCH_BOXED_LCM,
    BENCH_BOXED_ISQRT,
    BENCH_BOXED_TOSTR,
    BENCH_BOXED_FROMSTR,
    /* Asymmetric cells: second operand is ONE limb. The equal-size matrix
     * cannot see the dominant real-loop shape (big op small — the E3
     * accumulate/mulchain workloads); these rows measure it per-op, with
     * both native lanes hoisting the word into their unsigned-word entry. */
    BENCH_BOXED_ADD1,
    BENCH_BOXED_SUB1,
    BENCH_BOXED_MUL1,
    BENCH_BOXED_DIV1
};

/* Benchmark-only copies of the retired runtime C handlers. They remain an
 * explicit historical/control lane after production neg!/abs! move to native
 * Tungsten source; no runtime dispatch reaches these functions. */
static WValue bench_bigint_neg_bang_c_ref(WValue r, WValue *a, int c) {
    (void)a; (void)c;
    w_as_bigint(r)->size = -w_as_bigint(r)->size;
    return r;
}

static WValue bench_bigint_abs_bang_c_ref(WValue r, WValue *a, int c) {
    (void)a; (void)c;
    WBigint *b = w_as_bigint(r);
    if (b->size < 0) b->size = -b->size;
    return r;
}

/* a^BENCH_BOXED_POW_EXP for the pow lane (mpz_pow_ui / a**5 elsewhere). */
#define BENCH_BOXED_POW_EXP 5
/* Third-operand seed for the powmod modulus; the Python driver mirrors it. */
#define BENCH_BOXED_M_SEED 0xa4093822299f31d0ULL

/* ---- Tag-sign differential fuzz (encoding v4) ----
 *
 * w_neg/w_abs hand out the SAME buffer with the overlay bit (bit 47)
 * flipped; every boxed entry must compose header XOR overlay. This gate
 * runs each op over all sign combinations twice — once with tag-flipped
 * negatives, once with overlay-free header-signed COPIES — and requires
 * identical results. Same-engine differential isolates the overlay
 * machinery from any division/bitwise sign-convention questions; the
 * convention-safe subset is additionally triangulated against GMP by the
 * caller reusing check_boxed_op_against_gmp fixtures. Blocking: the R3
 * migration does not land while this reports a single mismatch. */
static void bench_boxed_operands(int op, int32_t limbs, WValue *a, WValue *b,
                                 WValue *m);
static WValue bench_boxed_op_apply(int op, WValue a, WValue b);

static WValue fuzz_copy_negate(WValue v) {
    if (!w_is_bigint(v)) return w_neg(v);
    WBigint *b = w_as_bigint(v);
    int overlay = (v & W_BIGINT_SIGN_BIT) ? 1 : 0;
    return bigint_copy_signed(b, 1 ^ overlay);
}

static const struct { int op; const char *name; int unary; int rhs_sign_ok; }
fuzz_tag_sign_ops[] = {
    {BENCH_BOXED_ADD, "add", 0, 1}, {BENCH_BOXED_SUB, "sub", 0, 1},
    {BENCH_BOXED_MUL, "mul", 0, 1}, {BENCH_BOXED_DIV, "div", 0, 1},
    {BENCH_BOXED_MOD, "mod", 0, 1}, {BENCH_BOXED_AND, "and", 0, 1},
    {BENCH_BOXED_OR,  "or",  0, 1}, {BENCH_BOXED_XOR, "xor", 0, 1},
    {BENCH_BOXED_SHL, "shl", 0, 0}, {BENCH_BOXED_SHR, "shr", 0, 0},
    {BENCH_BOXED_GCD, "gcd", 0, 1}, {BENCH_BOXED_CMP, "cmp", 0, 1},
    {BENCH_BOXED_NEG, "neg", 1, 0}, {BENCH_BOXED_ABS, "abs", 1, 0},
    {BENCH_BOXED_LCM, "lcm", 0, 1},
    {BENCH_BOXED_TOSTR, "tostr", 1, 0},
};

static void fuzz_tag_sign_case(size_t oi, int32_t limbs) {
    int op = fuzz_tag_sign_ops[oi].op;
    const char *name = fuzz_tag_sign_ops[oi].name;
    WValue a, b, m;
    bench_boxed_operands(op == BENCH_BOXED_TOSTR ? BENCH_BOXED_ADD : op,
                         limbs, &a, &b, &m);
    int sb_max = fuzz_tag_sign_ops[oi].unary ? 1
               : (fuzz_tag_sign_ops[oi].rhs_sign_ok ? 2 : 1);
    for (int sa = 0; sa < 2; sa++) {
        for (int sb = 0; sb < sb_max; sb++) {
            WValue ta = sa ? w_neg(a) : a;
            WValue tb = sb ? w_neg(b) : b;
            WValue ca = sa ? fuzz_copy_negate(a) : a;
            WValue cb = sb ? fuzz_copy_negate(b) : b;
            if (op == BENCH_BOXED_CMP) {
                int rt = bigint_compare(ta, tb);
                int rc = bigint_compare(ca, cb);
                if ((rt > 0) != (rc > 0) || (rt < 0) != (rc < 0))
                    dief("tag-sign cmp mismatch limbs=%d sa=%d sb=%d",
                         limbs, sa, sb);
            } else if (op == BENCH_BOXED_TOSTR) {
                WValue st = w_to_s(ta);
                WValue sc = w_to_s(ca);
                if (strcmp(as_str(st), as_str(sc)) != 0)
                    dief("tag-sign tostr mismatch limbs=%d sa=%d", limbs, sa);
            } else if (op == BENCH_BOXED_NEG) {
                WValue rt = w_neg(ta);
                WValue rc = fuzz_copy_negate(ca);
                if (bigint_compare(rt, rc) != 0)
                    dief("tag-sign neg mismatch limbs=%d sa=%d", limbs, sa);
                /* involution through the overlay */
                if (bigint_compare(w_neg(rt), ta) != 0)
                    dief("tag-sign neg involution broke limbs=%d sa=%d",
                         limbs, sa);
            } else if (op == BENCH_BOXED_ABS) {
                WValue rt = w_ic_bigint_abs(ta, NULL, 0);
                if (w_is_bigint(rt) && w_bigint_effective_negative(rt))
                    dief("tag-sign abs negative limbs=%d sa=%d", limbs, sa);
                WValue rc = w_ic_bigint_abs(ca, NULL, 0);
                if (bigint_compare(rt, rc) != 0)
                    dief("tag-sign abs mismatch limbs=%d sa=%d", limbs, sa);
            } else {
                WValue rt, rc;
                if (op == BENCH_BOXED_LCM) {
                    rt = w_ic_integer_lcm(ta, &tb, 1);
                    rc = w_ic_integer_lcm(ca, &cb, 1);
                } else {
                    rt = bench_boxed_op_apply(op, ta, tb);
                    rc = bench_boxed_op_apply(op, ca, cb);
                }
                if (bigint_compare(rt, rc) != 0)
                    dief("tag-sign %s mismatch limbs=%d sa=%d sb=%d",
                         name, limbs, sa, sb);
                /* the composed results must also HASH equal: hash keys by
                 * value, and a tag-flipped result that hashes by header
                 * would split equal keys */
                if (w_hash_value(rt) != w_hash_value(rc))
                    dief("tag-sign %s hash split limbs=%d sa=%d sb=%d",
                         name, limbs, sa, sb);
            }
        }
    }
    /* Leak-tolerant by design: tag aliases pin their buffers (shared bit),
     * so this fuzz loop does not free intermediates. */
}

static int bench_boxed_op_parse(const char *name) {
    if (strcmp(name, "add") == 0) return BENCH_BOXED_ADD;
    if (strcmp(name, "add1") == 0) return BENCH_BOXED_ADD1;
    if (strcmp(name, "sub1") == 0) return BENCH_BOXED_SUB1;
    if (strcmp(name, "mul1") == 0) return BENCH_BOXED_MUL1;
    if (strcmp(name, "div1") == 0) return BENCH_BOXED_DIV1;
    if (strcmp(name, "sub") == 0) return BENCH_BOXED_SUB;
    if (strcmp(name, "mul") == 0) return BENCH_BOXED_MUL;
    if (strcmp(name, "sqr") == 0) return BENCH_BOXED_SQR;
    if (strcmp(name, "div") == 0) return BENCH_BOXED_DIV;
    if (strcmp(name, "mod") == 0) return BENCH_BOXED_MOD;
    if (strcmp(name, "and") == 0) return BENCH_BOXED_AND;
    if (strcmp(name, "or") == 0) return BENCH_BOXED_OR;
    if (strcmp(name, "xor") == 0) return BENCH_BOXED_XOR;
    if (strcmp(name, "shl") == 0) return BENCH_BOXED_SHL;
    if (strcmp(name, "shr") == 0) return BENCH_BOXED_SHR;
    if (strcmp(name, "gcd") == 0) return BENCH_BOXED_GCD;
    if (strcmp(name, "cmp") == 0) return BENCH_BOXED_CMP;
    if (strcmp(name, "neg") == 0) return BENCH_BOXED_NEG;
    if (strcmp(name, "abs") == 0) return BENCH_BOXED_ABS;
    if (strcmp(name, "negbang") == 0) return BENCH_BOXED_NEG_BANG;
    if (strcmp(name, "absbang") == 0) return BENCH_BOXED_ABS_BANG;
    if (strcmp(name, "pow") == 0) return BENCH_BOXED_POW;
    if (strcmp(name, "powmod") == 0) return BENCH_BOXED_POWMOD;
    if (strcmp(name, "lcm") == 0) return BENCH_BOXED_LCM;
    if (strcmp(name, "isqrt") == 0) return BENCH_BOXED_ISQRT;
    if (strcmp(name, "tostr") == 0) return BENCH_BOXED_TOSTR;
    if (strcmp(name, "fromstr") == 0) return BENCH_BOXED_FROMSTR;
    return -1;
}

static int32_t bench_boxed_a_limbs(int op, int32_t limbs) {
    /* div/mod keep their historical 2N/N shape; isqrt takes a 2N-limb
     * operand so the result is N limbs (the row's size column). */
    if (op == BENCH_BOXED_DIV || op == BENCH_BOXED_MOD ||
        op == BENCH_BOXED_ISQRT)
        return 2 * limbs;
    return limbs;
}

#ifndef BENCH_CMP_SHAPE
#define BENCH_CMP_SHAPE 0
#endif
#ifndef BENCH_GCD_COMMON_TZ
#define BENCH_GCD_COMMON_TZ 0
#endif
#ifndef BENCH_ADDSUB_ZERO_PREFIX
#define BENCH_ADDSUB_ZERO_PREFIX 0
#endif

/*
 * Operand contract shared by the correctness check, the Tungsten lane, and
 * the GMP lane (the Python driver mirrors it exactly):
 *   cmp:    by default b equals a except in the LOWEST limb (bit 0 flipped),
 *           so the comparison must scan the full length. BENCH_CMP_SHAPE
 *           selects a highest-limb difference or equality for controlled
 *           comparison-geometry experiments.
 *   abs:    a is negative (sign flipped on the boxed bigint).
 *   powmod: *m_out is a deterministic odd n-limb modulus (bench_bigint
 *           already sets limb 0's low bit); e is the regular b operand.
 */
static void bench_boxed_operands(int op, int32_t limbs,
                                 WValue *a_out, WValue *b_out,
                                 WValue *m_out) {
    WValue a = bench_bigint(bench_boxed_a_limbs(op, limbs),
                            0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
    WValue b;
    if (op == BENCH_BOXED_CMP) {
        b = bench_clone_integer(a);
#if BENCH_CMP_SHAPE == 0
        w_as_bigint(b)->limbs[0] ^= 1ULL;
#elif BENCH_CMP_SHAPE == 1
        w_as_bigint(b)->limbs[limbs - 1] ^= 1ULL;
#elif BENCH_CMP_SHAPE == 2
        /* Equal magnitudes exercise the complete scan. */
#else
#error "BENCH_CMP_SHAPE must be 0 (low), 1 (high), or 2 (equal)"
#endif
    } else {
        int32_t b_limbs =
            (op == BENCH_BOXED_ADD1 || op == BENCH_BOXED_SUB1 ||
             op == BENCH_BOXED_MUL1 || op == BENCH_BOXED_DIV1)
                ? 1
                : limbs;
        b = bench_bigint(b_limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
    }
#if BENCH_ADDSUB_ZERO_PREFIX > 0
    if (op == BENCH_BOXED_ADD || op == BENCH_BOXED_SUB) {
        WBigint *ab = w_as_bigint(a);
        WBigint *bb = w_as_bigint(b);
        int32_t zero_limbs = BENCH_ADDSUB_ZERO_PREFIX;
        if (zero_limbs >= limbs) zero_limbs = limbs - 1;
        memset(bb->limbs, 0, (size_t)zero_limbs * sizeof(uint64_t));
        /* Make b unambiguously smaller so subtraction exercises the same
         * sparse operand regardless of the deterministic random top words. */
        ab->limbs[limbs - 1] |= UINT64_C(1) << 63;
        bb->limbs[limbs - 1] =
            (bb->limbs[limbs - 1] & ((UINT64_C(1) << 62) - 1)) |
            (UINT64_C(1) << 62);
    }
#endif
#if BENCH_GCD_COMMON_TZ > 0
#if BENCH_GCD_COMMON_TZ >= 64
#error "BENCH_GCD_COMMON_TZ must be in 0..63"
#endif
    if (op == BENCH_BOXED_GCD) {
        const uint64_t bit = 1ULL << BENCH_GCD_COMMON_TZ;
        const uint64_t low_mask = bit - 1;
        w_as_bigint(a)->limbs[0] =
            (w_as_bigint(a)->limbs[0] & ~low_mask) | bit;
        w_as_bigint(b)->limbs[0] =
            (w_as_bigint(b)->limbs[0] & ~low_mask) | bit;
    }
#endif
    if (op == BENCH_BOXED_ABS || op == BENCH_BOXED_ABS_BANG)
        w_as_bigint(a)->size = -w_as_bigint(a)->size;
    *m_out = W_NIL;
    if (op == BENCH_BOXED_POWMOD)
        *m_out = bench_bigint(limbs, BENCH_BOXED_M_SEED ^ (uint64_t)limbs);
    *a_out = a;
    *b_out = b;
}

/* Release a dead intermediate through the runtime handoff unless it aliases
 * a value the caller still holds. */
static void bench_boxed_free_dead(WValue dead, WValue keep1, WValue keep2,
                                  WValue keep3) {
    if (dead == keep1 || dead == keep2 || dead == keep3) return;
    if (w_is_bigint(dead)) w_value_free(dead);
}

#ifndef BENCH_TUNGSTEN_WORD_API
#define BENCH_TUNGSTEN_WORD_API 1
#endif

/*
 * Mirror of core/numeric/int.w Int#modpow exactly as compiled Tungsten runs
 * it today: LSB-first square-and-multiply where every step goes through the
 * boxed entry points (bigint_mul_any / bigint_mod_any / bigint_div_any by
 * two, odd test on limb 0) under the same immutable-result churn discipline.
 * Aliasing guards matter: mul-by-one and mod-below-modulus may return an
 * operand unchanged, so a value is only released once nothing live equals it.
 */
static WValue bench_tungsten_powmod_once(WValue a, WValue e, WValue m) {
    WValue zero = w_box_int(0);
    WValue two = w_box_int(2);
    WValue r = w_box_int(1);
    WValue b = bigint_mod_any(a, m);
    WValue x = e;
    while (bigint_compare(x, zero) > 0) {
        if (integer_low_i64(x) & 1) {
            WValue product = bigint_mul_any(r, b);
            WValue next_r = bigint_mod_any(product, m);
            if (product != next_r && product != r && product != b &&
                product != x)
                bench_boxed_free_dead(product, a, e, m);
            if (r != next_r && r != b && r != x)
                bench_boxed_free_dead(r, a, e, m);
            r = next_r;
        }
        WValue square = bigint_mul_any(b, b);
        WValue next_b = bigint_mod_any(square, m);
        if (square != next_b && square != b && square != r && square != x)
            bench_boxed_free_dead(square, a, e, m);
        if (b != next_b && b != r && b != x)
            bench_boxed_free_dead(b, a, e, m);
        b = next_b;
        WValue next_x = bigint_div_any(x, two);
        if (x != next_x && x != r && x != b)
            bench_boxed_free_dead(x, a, e, m);
        x = next_x;
    }
    if (b != r) bench_boxed_free_dead(b, a, e, m);
    if (x != r && x != b) bench_boxed_free_dead(x, a, e, m);
    return r;
}

/*
 * Mirror of core/numeric/int.w Int#isqrt: Newton's method from the tight
 * 2^ceil(bit_length/2) overestimate, every step through the boxed entry
 * points (bignum_shl for the guess, bigint_div_any / bigint_add_any /
 * division by two, bigint_compare for the loop test).
 */
static WValue bench_tungsten_isqrt_once(WValue a) {
    uint64_t scratch;
    int32_t len;
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    int64_t bits = mag_bitlen(al, len < 0 ? -len : len);
    WValue two = w_box_int(2);
    WValue x = bignum_shl(w_box_int(1), (bits + 1) / 2);
    for (;;) {
        WValue quotient = bigint_div_any(a, x);
        WValue sum = bigint_add_any(x, quotient);
        WValue y = bigint_div_any(sum, two);
        if (quotient != sum && quotient != y && quotient != x)
            bench_boxed_free_dead(quotient, a, a, a);
        if (sum != y && sum != x)
            bench_boxed_free_dead(sum, a, a, a);
        if (bigint_compare(y, x) < 0) {
            if (x != y) bench_boxed_free_dead(x, a, a, a);
            x = y;
        } else {
            if (y != x) bench_boxed_free_dead(y, a, a, a);
            return x;
        }
    }
}

static WValue bench_boxed_op_apply(int op, WValue a, WValue b) {
    switch (op) {
    case BENCH_BOXED_ADD: return bigint_add_any(a, b);
    case BENCH_BOXED_SUB: return bigint_sub_any(a, b);
    case BENCH_BOXED_MUL: return bigint_mul_any(a, b);
    case BENCH_BOXED_SQR: return bigint_mul_any(a, a);
    case BENCH_BOXED_DIV: return bigint_div_any(a, b);
    case BENCH_BOXED_MOD: return bigint_mod_any(a, b);
    case BENCH_BOXED_AND: return bignum_bitwise('&', a, b);
    case BENCH_BOXED_OR:  return bignum_bitwise('|', a, b);
    case BENCH_BOXED_XOR: return bignum_bitwise('^', a, b);
    case BENCH_BOXED_SHL: return bignum_shl(a, 13);
    case BENCH_BOXED_SHR: return bignum_shr(a, 13);
    case BENCH_BOXED_NEG_BANG: return bench_bigint_neg_bang_c_ref(a, NULL, 0);
    case BENCH_BOXED_ABS_BANG: return bench_bigint_abs_bang_c_ref(a, NULL, 0);
    case BENCH_BOXED_GCD: return bigint_gcd_any(a, b);
#if BENCH_TUNGSTEN_WORD_API
    case BENCH_BOXED_ADD1:
        return bigint_add_ui_any(a, w_as_bigint(b)->limbs[0]);
    case BENCH_BOXED_SUB1:
        return bigint_sub_ui_any(a, w_as_bigint(b)->limbs[0]);
    case BENCH_BOXED_MUL1:
        return bigint_mul_ui_any(a, w_as_bigint(b)->limbs[0]);
    case BENCH_BOXED_DIV1:
        return bigint_div_ui_any(a, w_as_bigint(b)->limbs[0]);
#else
    case BENCH_BOXED_ADD1: return bigint_add_any(a, b);
    case BENCH_BOXED_SUB1: return bigint_sub_any(a, b);
    case BENCH_BOXED_MUL1: return bigint_mul_any(a, b);
    case BENCH_BOXED_DIV1: return bigint_div_any(a, b);
#endif
    default: die("unknown boxed-result benchmark operation");
    }
    return W_NIL;
}

/*
 * A native sample can be much shorter than the Python sample used to choose
 * its iteration count.  In particular, a few milliseconds of tiny shifts or
 * adds mostly measures Apple-silicon frequency ramp-up.  Warm for a fixed
 * wall-clock interval under the same result-lifetime contract before starting
 * either the Tungsten or GMP timer.
 *
 * Check the clock in small chunks for expensive nonlinear operations, but
 * amortize the check for linear/tiny operations.  Warm-up work is intentionally
 * not included in bench_sink's iteration-index stream.
 */
static int bench_boxed_warm_chunk(int op, int32_t limbs) {
    if (op == BENCH_BOXED_POWMOD) return 1;
    if (op == BENCH_BOXED_ISQRT && limbs >= 4) return 1;
    if (op == BENCH_BOXED_LCM && limbs >= 16) return 1;
    if ((op == BENCH_BOXED_DIV || op == BENCH_BOXED_MOD ||
         op == BENCH_BOXED_GCD) && limbs >= 128)
        return 1;
    if ((op == BENCH_BOXED_MUL || op == BENCH_BOXED_SQR) && limbs >= 256)
        return 8;
    if ((op == BENCH_BOXED_POW || op == BENCH_BOXED_TOSTR ||
         op == BENCH_BOXED_FROMSTR) && limbs >= 64)
        return 8;
    return 1024;
}

/*
 * Model immutable result churn with one previous result still live while the
 * next is computed.  In recycle mode, releasing that previous result makes
 * its allocation available two generations later; no live operand/result is
 * ever overwritten.  Direct mode uses malloc/free exactly as before.
 */
/*
 * One noinline, cache-line-aligned timing function PER OPERATION.  When all
 * lanes shared one giant switch, every kernel inlined into a single function
 * whose internal layout reshuffled each time a lane was added — small-op
 * cells (2-6 ns/op) would swing ±10% from I-cache/BTB placement alone,
 * reading as phantom regressions.  A lane function's inner loop sits at a
 * fixed offset from its own aligned entry, independent of the other lanes.
 */
/* Warm-up window per timed call.  Each lane pays this before its timed
 * region, and a sweep makes 2*(runs+1) lane calls per size, so the default
 * 3ms dominates cheap operations.  The sweep shortens it: the caches and
 * branch predictors are already warm from the pilot and preceding reps. */
static double bench_warm_seconds = 0.003;

typedef struct {
    WValue a, b, m, parse_input;
    WValue previous;
    int recycle;
    int warm_chunk;
    int iters;
} BenchLaneCtx;

#ifndef BENCH_ARITH_WS_RELEASE_KNOB
#define BENCH_ARITH_WS_RELEASE_KNOB 0
#endif

#if BENCH_ARITH_WS_RELEASE_KNOB
static int bench_release_arith_ws_each_iteration;
static void bench_release_arith_workspaces(void) {
    free(bn_ws);
    bn_ws = NULL;
    bn_ws_cap = 0;
#if BN_TOOM_POINT_TLS_MEMORY
    free(bn_toom_point_memory);
    bn_toom_point_memory = NULL;
    bn_toom_point_memory_cap = 0;
#endif
    for (int depth = 0; depth < BN_RECT_WS_DEPTH; depth++) {
        free(bn_rect_ws[depth]);
        bn_rect_ws[depth] = NULL;
        bn_rect_ws_cap[depth] = 0;
    }
    bn_rect_depth = 0;
    free(w_ssa_ws);
    w_ssa_ws = NULL;
    w_ssa_ws_cap = 0;
    for (int slot = 0; slot < 2; slot++) {
        free(w_ntt_workspace[slot]);
        w_ntt_workspace[slot] = NULL;
        w_ntt_workspace_cap[slot] = 0;
    }
    free(bz_ws);
    bz_ws = NULL;
    bz_ws_cap = 0;
    free(bn_sqrt_ws);
    bn_sqrt_ws = NULL;
    bn_sqrt_ws_cap = 0;
}
#define BENCH_MAYBE_RELEASE_ARITH_WS() do {                               \
    if (bench_release_arith_ws_each_iteration)                            \
        bench_release_arith_workspaces();                                 \
} while (0)
#else
#define BENCH_MAYBE_RELEASE_ARITH_WS() ((void)0)
#endif

/* Observation mirror of the GMP lanes' mpz_get_ui: the low limb of the
 * MAGNITUDE, no sign application (mpz_get_ui reads |z| mod 2^64).  The
 * previous signed observation (integer_low_i64) charged every Tungsten
 * lane an overlay-sign test plus two conditional negates per iteration
 * that the GMP lanes never pay; the sink only needs result-dependent
 * entropy, symmetrically priced. */
static inline uint64_t bench_observe_low(WValue v) {
    if (w_is_int(v)) {
        int64_t iv = w_as_int(v);
        return (uint64_t)(iv < 0 ? -iv : iv);
    }
    WBigint *b = w_as_bigint(v);
    int32_t sz = b->size;   /* header length; overlay sign irrelevant here */
    return sz != 0 ? b->limbs[0] : 0;
}

#define DEFINE_BENCH_LANE(NAME, APPLY)                                     \
static double __attribute__((noinline, aligned(128)))                      \
bench_lane_##NAME(BenchLaneCtx *cx) {                                      \
    WValue a = cx->a, b = cx->b, m = cx->m;                                \
    uint64_t word = w_as_bigint(b)->limbs[0];                              \
    WValue parse_input = cx->parse_input;                                  \
    WValue previous = cx->previous;                                        \
    int recycle = cx->recycle;                                             \
    (void)a; (void)b; (void)m; (void)word; (void)parse_input;              \
    /* warm_chunk == 0 skips the warm-up entirely: the quartet sweep       \
     * re-enters an already-warm lane for each short timed block. */       \
    if (cx->warm_chunk > 0) {                                              \
        double warm_start = bench_now();                                   \
        do {                                                               \
            for (int warm_i = 0; warm_i < cx->warm_chunk; warm_i++) {      \
                WValue result = (APPLY);                                   \
                bench_sink ^= bench_observe_low(result);                   \
                if (w_is_bigint(previous)) {                               \
                    if (recycle)                                           \
                        bigint_release_if_live(w_as_bigint(previous));     \
                    else bench_direct_free(w_as_bigint(previous));         \
                }                                                          \
                previous = result;                                         \
                BENCH_MAYBE_RELEASE_ARITH_WS();                            \
            }                                                              \
        } while (bench_now() - warm_start < bench_warm_seconds);           \
    }                                                                      \
    int iters = cx->iters;                                                 \
    double timed_start = bench_now();                                      \
    for (int timed_i = 0; timed_i < iters; timed_i++) {                    \
        WValue result = (APPLY);                                           \
        bench_sink ^= bench_observe_low(result) ^                          \
                      (uint64_t)timed_i;                                   \
        if (w_is_bigint(previous)) {                                       \
            if (recycle)                                                   \
                bigint_release_if_live(w_as_bigint(previous));             \
            else bench_direct_free(w_as_bigint(previous));                              \
        }                                                                  \
        previous = result;                                                 \
        BENCH_MAYBE_RELEASE_ARITH_WS();                                    \
    }                                                                      \
    double elapsed = bench_now() - timed_start;                            \
    cx->previous = previous;                                               \
    return elapsed;                                                        \
}

DEFINE_BENCH_LANE(add, bigint_add_any(a, b))
DEFINE_BENCH_LANE(sub, bigint_sub_any(a, b))
DEFINE_BENCH_LANE(mul, bigint_mul_any(a, b))
DEFINE_BENCH_LANE(sqr, bigint_mul_any(a, a))
#ifndef BENCH_MOD84_DIVISOR_TOGGLE
#define BENCH_MOD84_DIVISOR_TOGGLE 0
#endif
#if BENCH_MOD84_DIVISOR_TOGGLE
static inline WValue bench_mod84_divisor_toggle(WValue a, WValue b) {
    WBigint *dividend = w_as_bigint(a);
    WBigint *divisor = w_as_bigint(b);
    int32_t dividend_size = dividend->size < 0
        ? -dividend->size : dividend->size;
    int32_t divisor_size = divisor->size < 0
        ? -divisor->size : divisor->size;
    if (dividend_size == 8 && divisor_size == 4)
        divisor->limbs[2] ^= UINT64_C(0x1e3779b97f4a7c15);
    return bigint_mod_any(a, b);
}
#endif
#ifndef BENCH_DIV_RECIP_REUSE
#define BENCH_DIV_RECIP_REUSE 0
#endif
#if BENCH_DIV_RECIP_REUSE > 0
static uint64_t bench_div_recip_reuse_counter;
static inline WValue bench_div_recip_reuse(WValue a, WValue b, int mod) {
    if (bench_div_recip_reuse_counter++ % BENCH_DIV_RECIP_REUSE == 0)
        bn_div_recip_cache.state = 0;
    return mod ? bigint_mod_any(a, b) : bigint_div_any(a, b);
}
DEFINE_BENCH_LANE(div, bench_div_recip_reuse(a, b, 0))
DEFINE_BENCH_LANE(mod, bench_div_recip_reuse(a, b, 1))
#else
DEFINE_BENCH_LANE(div, bigint_div_any(a, b))
#if BENCH_MOD84_DIVISOR_TOGGLE
DEFINE_BENCH_LANE(mod, bench_mod84_divisor_toggle(a, b))
#else
DEFINE_BENCH_LANE(mod, bigint_mod_any(a, b))
#endif
#endif
DEFINE_BENCH_LANE(band, bignum_bitwise('&', a, b))
DEFINE_BENCH_LANE(bor, bignum_bitwise('|', a, b))
DEFINE_BENCH_LANE(bxor, bignum_bitwise('^', a, b))
DEFINE_BENCH_LANE(shl, bignum_shl(a, 13))
DEFINE_BENCH_LANE(shr, bignum_shr(a, 13))
DEFINE_BENCH_LANE(gcd, bigint_gcd_any(a, b))
/* This is the BigInt matrix, so the receiver class is already known just as
 * it is for GMP's mpz_neg input and for the abs lane below.  Calling w_neg
 * here would charge only neg for generic numeric/user-class dispatch before
 * reaching the same immutable copy kernel. */
/* neg measures the production `-x` path (w_neg: tag flip since v4), not
 * the copy kernel it called historically — the matrix row means "-x". The
 * overlay-free copy path stays covered by the tag-sign fuzzer's reference
 * lane (fuzz_copy_negate). */
#ifndef BENCH_TAG_SIGN_OVERLAY
#define BENCH_TAG_SIGN_OVERLAY 1
#endif
#if BENCH_TAG_SIGN_OVERLAY
DEFINE_BENCH_LANE(neg, w_neg(a))
DEFINE_BENCH_LANE(abs, w_ic_bigint_abs(a, NULL, 0))
#else
DEFINE_BENCH_LANE(neg, bigint_copy_signed(w_as_bigint(a), 1))
DEFINE_BENCH_LANE(abs, bigint_copy_signed(w_as_bigint(a), 0))
#endif
#if BENCH_TUNGSTEN_WORD_API
DEFINE_BENCH_LANE(add1, bigint_add_ui_any(a, word))
DEFINE_BENCH_LANE(sub1, bigint_sub_ui_any(a, word))
DEFINE_BENCH_LANE(mul1, bigint_mul_ui_any(a, word))
#else
DEFINE_BENCH_LANE(add1, bigint_add_any(a, b))
DEFINE_BENCH_LANE(sub1, bigint_sub_any(a, b))
DEFINE_BENCH_LANE(mul1, bigint_mul_any(a, b))
#endif
#ifndef BENCH_DIV1_THRASH
#define BENCH_DIV1_THRASH 0
#endif
#if BENCH_DIV1_THRASH
static inline WValue bench_div1_thrash(WValue a, WValue b) {
    WBigint *divisor = w_as_bigint(b);
#if BENCH_DIV1_THRASH == 1
    divisor->limbs[0] += UINT64_C(0x9e3779b97f4a7c15);
    divisor->limbs[0] |= UINT64_C(1) << 63;
#else
    divisor->limbs[0] ^= UINT64_C(0x1e3779b97f4a7c15);
#endif
    return bigint_div_any(a, b);
}
DEFINE_BENCH_LANE(div1, bench_div1_thrash(a, b))
#else
#if BENCH_TUNGSTEN_WORD_API
DEFINE_BENCH_LANE(div1, bigint_div_ui_any(a, word))
#else
DEFINE_BENCH_LANE(div1, bigint_div_any(a, b))
#endif
#endif
/* In-place sign mutation: O(1) field write, nothing allocated.  These
 * return the RECEIVER, so they must not go through the result-churn macro
 * (which would release the operand).  Compared against GMP's equivalent
 * in-place mpz_neg(a,a) / mpz_abs(a,a), which are likewise O(1). */
#define DEFINE_BENCH_INPLACE_LANE(NAME, APPLY)                             \
static double __attribute__((noinline, aligned(128)))                      \
bench_lane_##NAME(BenchLaneCtx *cx) {                                      \
    WValue a = cx->a;                                                      \
    if (cx->warm_chunk > 0) {                                              \
        double warm_start = bench_now();                                   \
        do {                                                               \
            for (int warm_i = 0; warm_i < cx->warm_chunk; warm_i++)        \
                bench_sink ^= (uint64_t)integer_low_i64(APPLY);            \
        } while (bench_now() - warm_start < bench_warm_seconds);           \
    }                                                                      \
    int iters = cx->iters;                                                 \
    double timed_start = bench_now();                                      \
    for (int timed_i = 0; timed_i < iters; timed_i++)                      \
        bench_sink ^= (uint64_t)integer_low_i64(APPLY) ^ (uint64_t)timed_i;\
    return bench_now() - timed_start;                                      \
}
DEFINE_BENCH_INPLACE_LANE(negbang, bench_bigint_neg_bang_c_ref(a, NULL, 0))
DEFINE_BENCH_INPLACE_LANE(absbang, bench_bigint_abs_bang_c_ref(a, NULL, 0))
DEFINE_BENCH_LANE(pow, w_pow(a, w_box_int(BENCH_BOXED_POW_EXP)))
DEFINE_BENCH_LANE(powmod, bigint_powmod_any(a, b, m))
DEFINE_BENCH_LANE(lcm, w_ic_integer_lcm(a, &b, 1))
DEFINE_BENCH_LANE(isqrt, bigint_isqrt_any(a))
DEFINE_BENCH_LANE(fromstr, w_bigint_from_dec_str(parse_input))

/* cmp needs its volatile-operand slot (bigint_compare is a same-TU static;
 * without it clang hoists the loop-invariant compare out of the loop).
 *
 * Sink discipline, for parity with the external lanes: results accumulate
 * in a REGISTER and flush to bench_sink once, after timing.  Compare is
 * the one sub-ns lane, and the previous per-iteration `bench_sink ^=`
 * volatile read-modify-write added two global memory ops to every
 * iteration that the Rust lane (register sink, one black_box at the end)
 * does not pay.  The volatile operand slot stays: one stack reload per
 * iteration is the cheaper twin of rustc's black_box on each operand
 * reference (a stack store+reload round-trip per operand per iteration),
 * so the anti-hoist tax remains symmetric or slightly against us.  The
 * GMP cmp lane below mirrors this structure exactly. */
static double __attribute__((noinline, aligned(128)))
bench_lane_cmp(BenchLaneCtx *cx) {
    volatile WValue cmp_operand = cx->a;
    WValue b = cx->b;
    uint64_t sink = 0;
    if (cx->warm_chunk > 0) {
        double warm_start = bench_now();
        do {
            for (int warm_i = 0; warm_i < cx->warm_chunk; warm_i++)
                sink ^= (uint64_t)bigint_compare(cmp_operand, b);
        } while (bench_now() - warm_start < bench_warm_seconds);
    }
    int iters = cx->iters;
    double timed_start = bench_now();
    for (int timed_i = 0; timed_i < iters; timed_i++)
        sink ^= (uint64_t)bigint_compare(cmp_operand, b) ^
                (uint64_t)timed_i;
    double elapsed = bench_now() - timed_start;
    bench_sink ^= sink;
    return elapsed;
}

/* tostr frees its string result every iteration (mirrors str(a) with no
 * retained previous). */
static double __attribute__((noinline, aligned(128)))
bench_lane_tostr(BenchLaneCtx *cx) {
    WValue a = cx->a;
    if (cx->warm_chunk > 0) {
        double warm_start = bench_now();
        do {
            for (int warm_i = 0; warm_i < cx->warm_chunk; warm_i++) {
                WValue text = w_int_to_s(a);
                bench_sink ^= (uint64_t)(unsigned char)
                              w_as_heap_str(text)->data[0];
                w_value_free(text);
            }
        } while (bench_now() - warm_start < bench_warm_seconds);
    }
    int iters = cx->iters;
    double timed_start = bench_now();
    for (int timed_i = 0; timed_i < iters; timed_i++) {
        WValue text = w_int_to_s(a);
        bench_sink ^= (uint64_t)(unsigned char)
                          w_as_heap_str(text)->data[0] ^
                      (uint64_t)timed_i;
        w_value_free(text);
    }
    return bench_now() - timed_start;
}

/* The churn measurement, split into setup / run / teardown so the paired
 * ABBA-quartet sweep can interleave many short Tungsten and GMP timed
 * blocks over ONE prepared operand set.  bench_boxed_result_churn below
 * composes the three pieces unchanged for every one-shot caller. */
static void bench_boxed_lane_setup(int op, int32_t limbs, int recycle,
                                   BenchLaneCtx *cx) {
    WValue a, b, m;
    bench_boxed_operands(op, limbs, &a, &b, &m);
    /* fromstr parses one fixed decimal string (precomputed outside timing);
     * the correctness check verifies it byte-matches GMP's writer. */
    WValue parse_input = W_NIL;
    if (op == BENCH_BOXED_FROMSTR) parse_input = w_int_to_s(a);
    if (op == BENCH_BOXED_TOSTR) {
        /* Every benchmark operand is at least 2^63 and the slab is frozen,
         * so production formatting returns a mode-7 heap string.  Establish
         * that invariant outside timing: the lane can then observe data[0]
         * exactly as GMP observes its returned char buffer's first byte. */
        WValue probe = w_int_to_s(a);
        if (!w_is_heap_str(probe))
            die("boxed tostr expected a post-freeze heap string");
        w_value_free(probe);
    }

    bigint_pool_release_thread();
    cx->a = a;
    cx->b = b;
    cx->m = m;
    cx->parse_input = parse_input;
    cx->previous = W_NIL;
    cx->recycle = recycle;
    cx->warm_chunk = bench_boxed_warm_chunk(op, limbs);
    cx->iters = 0;
}

/* Returns the elapsed SECONDS of the timed region (cx->iters operations);
 * cx->warm_chunk > 0 pays the per-lane warm-up first, 0 skips it. */
static double bench_boxed_lane_run(int op, BenchLaneCtx *cx) {
    switch (op) {
    case BENCH_BOXED_ADD:    return bench_lane_add(cx);
    case BENCH_BOXED_SUB:    return bench_lane_sub(cx);
    case BENCH_BOXED_MUL:    return bench_lane_mul(cx);
    case BENCH_BOXED_SQR:    return bench_lane_sqr(cx);
    case BENCH_BOXED_DIV:    return bench_lane_div(cx);
    case BENCH_BOXED_MOD:    return bench_lane_mod(cx);
    case BENCH_BOXED_AND:    return bench_lane_band(cx);
    case BENCH_BOXED_OR:     return bench_lane_bor(cx);
    case BENCH_BOXED_XOR:    return bench_lane_bxor(cx);
    case BENCH_BOXED_SHL:    return bench_lane_shl(cx);
    case BENCH_BOXED_SHR:    return bench_lane_shr(cx);
    case BENCH_BOXED_GCD:    return bench_lane_gcd(cx);
    case BENCH_BOXED_CMP:    return bench_lane_cmp(cx);
    case BENCH_BOXED_NEG:    return bench_lane_neg(cx);
    case BENCH_BOXED_ABS:    return bench_lane_abs(cx);
    case BENCH_BOXED_ADD1:   return bench_lane_add1(cx);
    case BENCH_BOXED_SUB1:   return bench_lane_sub1(cx);
    case BENCH_BOXED_MUL1:   return bench_lane_mul1(cx);
    case BENCH_BOXED_DIV1:   return bench_lane_div1(cx);
    case BENCH_BOXED_NEG_BANG: return bench_lane_negbang(cx);
    case BENCH_BOXED_ABS_BANG: return bench_lane_absbang(cx);
    case BENCH_BOXED_POW:    return bench_lane_pow(cx);
    case BENCH_BOXED_POWMOD: return bench_lane_powmod(cx);
    case BENCH_BOXED_LCM:    return bench_lane_lcm(cx);
    case BENCH_BOXED_ISQRT:  return bench_lane_isqrt(cx);
    case BENCH_BOXED_FROMSTR: return bench_lane_fromstr(cx);
    case BENCH_BOXED_TOSTR:  return bench_lane_tostr(cx);
    default:
        die("unknown boxed-result benchmark operation");
    }
    return 0.0;
}

static void bench_boxed_lane_teardown(int op, BenchLaneCtx *cx) {
    if (w_is_bigint(cx->previous))
        bench_direct_free(w_as_bigint(cx->previous));
    bigint_pool_release_thread();
    bench_free_value(cx->a);
    bench_free_value(cx->b);
    bench_free_value(cx->m);
    if (op == BENCH_BOXED_FROMSTR) w_value_free(cx->parse_input);
}

static double bench_boxed_result_churn(int op, int32_t limbs, int iters,
                                       int recycle) {
    BenchLaneCtx cx;
    bench_boxed_lane_setup(op, limbs, recycle, &cx);
    cx.iters = iters;
    double elapsed = bench_boxed_lane_run(op, &cx);
    bench_boxed_lane_teardown(op, &cx);
    return elapsed * 1e9 / (double)iters;
}

/* Full boxed immutable-result lane for an explicitly rectangular multiply.
 * The ordinary matrix supplies equal limb counts, so keep this separate from
 * bench_boxed_operands while preserving the same one-previous-result-live
 * lifecycle used by the documented boxed operation rows. */
static double bench_boxed_mul_rect_churn(
    int32_t na, int32_t nb, int iters) {
    WValue a = bench_bigint(
        na, UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)na);
    WValue b = bench_bigint(
        nb, UINT64_C(0x13198a2e03707344) ^ (uint64_t)nb);

    bigint_pool_release_thread();
    BenchLaneCtx cx;
    cx.a = a;
    cx.b = b;
    cx.m = W_NIL;
    cx.parse_input = W_NIL;
    cx.previous = W_NIL;
    cx.recycle = 1;
    cx.warm_chunk = bench_boxed_warm_chunk(
        BENCH_BOXED_MUL, na > nb ? na : nb);
    cx.iters = iters;
    double elapsed = bench_lane_mul(&cx);

    if (w_is_bigint(cx.previous))
        bench_direct_free(w_as_bigint(cx.previous));
    bigint_pool_release_thread();
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
}

/*
 * Focused algebraic fast-path benchmark.  Unlike the general boxed-result
 * lanes above, these operations are explicitly allowed to return one of
 * their operands.  Keep the benchmark-owned values separate from temporary
 * results so a new identity path cannot make the harness recycle a live
 * operand.  Volatile operand slots are reloaded inside the timed loop: this
 * prevents the C optimizer from specializing an invariant zero/one argument
 * away before the runtime entry point sees it.
 */
typedef struct {
    WValue x;
    WValue negative_x;
    WValue bitwise_not_x;
    WValue modulus;
    WValue modulus_minus_one;
} BenchFastpathOwned;

typedef struct {
    const char *name;
    volatile WValue a;
    volatile WValue b;
    volatile WValue m;
    volatile int64_t shift;
    WValue expected;
    const BenchFastpathOwned *owned;
} BenchFastpathLaneCtx;

typedef double (*BenchFastpathLane)(BenchFastpathLaneCtx *, int);

typedef struct {
    const char *name;
    BenchFastpathLane lane;
    BenchFastpathLaneCtx cx;
} BenchFastpathScenario;

/* Default mode leaves benchmark-owned aliases live and lets their shared
 * count saturate, isolating the arithmetic dispatch itself.  The paired mode
 * mirrors a consumed temporary: every alias result immediately releases its
 * shared mark, measuring the steady mark/unmark tax without risking the
 * benchmark's still-live owner. */
static int bench_fastpath_release_alias;

static int bench_fastpath_is_owned(WValue value,
                                   const BenchFastpathOwned *owned) {
    return value == owned->x || value == owned->negative_x ||
           value == owned->bitwise_not_x || value == owned->modulus ||
           value == owned->modulus_minus_one;
}

static void bench_fastpath_release_result(WValue result,
                                          const BenchFastpathOwned *owned) {
    if (!w_is_bigint(result)) return;
    if (bench_fastpath_is_owned(result, owned)) {
        if (bench_fastpath_release_alias) {
            WBigint *b = w_as_bigint(result);
            if (b->shared == 0)
                die("fastpath alias result was not marked shared");
            bigint_release_if_live(b);
        }
        return;
    }
    bigint_release_if_live(w_as_bigint(result));
}

static void bench_fastpath_expect(BenchFastpathLaneCtx *cx, WValue got) {
    if (!w_is_integer_any(got) || bigint_compare(got, cx->expected) != 0) {
        fprintf(stderr, "fastpath validation failed: %s\n", cx->name);
        exit(2);
    }
}

#define DEFINE_FASTPATH_BINARY_LANE(NAME, APPLY)                           \
static double __attribute__((noinline, aligned(128)))                      \
bench_fastpath_lane_##NAME(BenchFastpathLaneCtx *cx, int iters) {          \
    {                                                                      \
        WValue a = cx->a;                                                  \
        WValue b = cx->b;                                                  \
        WValue check = (APPLY);                                            \
        bench_fastpath_expect(cx, check);                                  \
        bench_fastpath_release_result(check, cx->owned);                   \
    }                                                                      \
    double start = bench_now();                                            \
    for (int i = 0; i < iters; i++) {                                     \
        WValue a = cx->a;                                                  \
        WValue b = cx->b;                                                  \
        WValue result = (APPLY);                                           \
        bench_sink ^= (uint64_t)integer_low_i64(result) ^ (uint64_t)i;     \
        bench_fastpath_release_result(result, cx->owned);                  \
    }                                                                      \
    return bench_now() - start;                                            \
}

DEFINE_FASTPATH_BINARY_LANE(add, bigint_add_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(sub, bigint_sub_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(mul, bigint_mul_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(div, bigint_div_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(mod, bigint_mod_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(band, bignum_bitwise('&', a, b))
DEFINE_FASTPATH_BINARY_LANE(bor, bignum_bitwise('|', a, b))
DEFINE_FASTPATH_BINARY_LANE(bxor, bignum_bitwise('^', a, b))
DEFINE_FASTPATH_BINARY_LANE(gcd, bigint_gcd_any(a, b))
DEFINE_FASTPATH_BINARY_LANE(lcm, w_ic_integer_lcm(a, &b, 1))
DEFINE_FASTPATH_BINARY_LANE(pow, w_pow(a, b))
#undef DEFINE_FASTPATH_BINARY_LANE

#define DEFINE_FASTPATH_SHIFT_LANE(NAME, APPLY)                            \
static double __attribute__((noinline, aligned(128)))                      \
bench_fastpath_lane_##NAME(BenchFastpathLaneCtx *cx, int iters) {          \
    {                                                                      \
        WValue a = cx->a;                                                  \
        int64_t shift = cx->shift;                                         \
        WValue check = (APPLY);                                            \
        bench_fastpath_expect(cx, check);                                  \
        bench_fastpath_release_result(check, cx->owned);                   \
    }                                                                      \
    double start = bench_now();                                            \
    for (int i = 0; i < iters; i++) {                                     \
        WValue a = cx->a;                                                  \
        int64_t shift = cx->shift;                                         \
        WValue result = (APPLY);                                           \
        bench_sink ^= (uint64_t)integer_low_i64(result) ^ (uint64_t)i;     \
        bench_fastpath_release_result(result, cx->owned);                  \
    }                                                                      \
    return bench_now() - start;                                            \
}

DEFINE_FASTPATH_SHIFT_LANE(shl, bignum_shl(a, shift))
DEFINE_FASTPATH_SHIFT_LANE(shr, bignum_shr(a, shift))
#undef DEFINE_FASTPATH_SHIFT_LANE

static double __attribute__((noinline, aligned(128)))
bench_fastpath_lane_powmod(BenchFastpathLaneCtx *cx, int iters) {
    WValue check_a = cx->a;
    WValue check_b = cx->b;
    WValue check_m = cx->m;
    WValue check = bigint_powmod_any(check_a, check_b, check_m);
    bench_fastpath_expect(cx, check);
    bench_fastpath_release_result(check, cx->owned);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue a = cx->a;
        WValue b = cx->b;
        WValue m = cx->m;
        WValue result = bigint_powmod_any(a, b, m);
        bench_sink ^= (uint64_t)integer_low_i64(result) ^ (uint64_t)i;
        bench_fastpath_release_result(result, cx->owned);
    }
    return bench_now() - start;
}

static void bench_fastpaths(int32_t limbs, int iters, int runs) {
    bigint_pool_release_thread();
    bench_fastpath_release_alias =
        getenv("BENCH_FASTPATH_RELEASE_ALIAS") != NULL;

    BenchFastpathOwned owned;
    owned.x = bench_bigint(limbs,
                           0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
    WBigint *xb = w_as_bigint(owned.x);
    xb->limbs[limbs - 1] &= ~(UINT64_C(1) << 63);
    xb->limbs[limbs - 1] |= UINT64_C(1) << 62;
    xb->limbs[0] |= 1;

    owned.negative_x = bench_clone_integer(owned.x);
    w_as_bigint(owned.negative_x)->size =
        -w_as_bigint(owned.negative_x)->size;

    owned.modulus = bench_bigint(
        limbs, BENCH_BOXED_M_SEED ^ (uint64_t)limbs);
    owned.modulus_minus_one = bench_clone_integer(owned.modulus);
    /* bench_bigint makes the low limb odd, so this cannot borrow. */
    w_as_bigint(owned.modulus_minus_one)->limbs[0]--;

    WValue zero = w_box_int(0);
    WValue one = w_box_int(1);
    WValue negative_one = w_box_int(-1);
    WValue exponent16 = w_box_int(16);
    WValue exponent17 = w_box_int(17);
    owned.bitwise_not_x = bigint_sub_any(owned.negative_x, one);

#define FASTPATH_SCENARIO(LABEL, LANE, A, B, M, SHIFT, EXPECTED)           \
    { LABEL, bench_fastpath_lane_##LANE,                                   \
      { LABEL, A, B, M, SHIFT, EXPECTED, &owned } }
    BenchFastpathScenario scenarios[] = {
        FASTPATH_SCENARIO("add_x_0", add, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("sub_x_0", sub, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("sub_x_x", sub, owned.x, owned.x, zero, 0, zero),
        FASTPATH_SCENARIO("mul_x_0", mul, owned.x, zero, zero, 0, zero),
        FASTPATH_SCENARIO("mul_x_1", mul, owned.x, one, zero, 0, owned.x),
        FASTPATH_SCENARIO("mul_x_neg1", mul, owned.x, negative_one, zero, 0,
                          owned.negative_x),
        FASTPATH_SCENARIO("div_x_1", div, owned.x, one, zero, 0, owned.x),
        FASTPATH_SCENARIO("div_x_neg1", div, owned.x, negative_one, zero, 0,
                          owned.negative_x),
        FASTPATH_SCENARIO("div_x_x", div, owned.x, owned.x, zero, 0, one),
        FASTPATH_SCENARIO("mod_x_1", mod, owned.x, one, zero, 0, zero),
        FASTPATH_SCENARIO("mod_x_x", mod, owned.x, owned.x, zero, 0, zero),
        FASTPATH_SCENARIO("shl_x_0", shl, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("shr_x_0", shr, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("and_x_x", band, owned.x, owned.x, zero, 0, owned.x),
        FASTPATH_SCENARIO("and_x_0", band, owned.x, zero, zero, 0, zero),
        FASTPATH_SCENARIO("and_x_neg1", band, owned.x, negative_one, zero, 0,
                          owned.x),
        FASTPATH_SCENARIO("or_x_x", bor, owned.x, owned.x, zero, 0, owned.x),
        FASTPATH_SCENARIO("or_x_0", bor, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("or_x_neg1", bor, owned.x, negative_one, zero, 0,
                          negative_one),
        FASTPATH_SCENARIO("xor_x_x", bxor, owned.x, owned.x, zero, 0, zero),
        FASTPATH_SCENARIO("xor_x_0", bxor, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("xor_x_neg1", bxor, owned.x, negative_one, zero, 0,
                          owned.bitwise_not_x),
        FASTPATH_SCENARIO("gcd_x_0", gcd, owned.x, zero, zero, 0, owned.x),
        FASTPATH_SCENARIO("gcd_x_1", gcd, owned.x, one, zero, 0, one),
        FASTPATH_SCENARIO("gcd_x_x", gcd, owned.x, owned.x, zero, 0, owned.x),
        FASTPATH_SCENARIO("lcm_x_0", lcm, owned.x, zero, zero, 0, zero),
        FASTPATH_SCENARIO("lcm_x_1", lcm, owned.x, one, zero, 0, owned.x),
        FASTPATH_SCENARIO("lcm_x_x", lcm, owned.x, owned.x, zero, 0, owned.x),
        FASTPATH_SCENARIO("pow_x_0", pow, owned.x, zero, zero, 0, one),
        FASTPATH_SCENARIO("pow_x_1", pow, owned.x, one, zero, 0, owned.x),
        FASTPATH_SCENARIO("powmod_exp_0", powmod, owned.x, zero,
                          owned.modulus, 0, one),
        FASTPATH_SCENARIO("powmod_exp_1", powmod, owned.x, one,
                          owned.modulus, 0, owned.x),
        FASTPATH_SCENARIO("powmod_base_0", powmod, zero, exponent17,
                          owned.modulus, 0, zero),
        FASTPATH_SCENARIO("powmod_base_1", powmod, one, exponent17,
                          owned.modulus, 0, one),
        FASTPATH_SCENARIO("powmod_base_neg1_even", powmod, negative_one,
                          exponent16, owned.modulus, 0, one),
        FASTPATH_SCENARIO("powmod_base_neg1_odd", powmod, negative_one,
                          exponent17, owned.modulus, 0,
                          owned.modulus_minus_one),
        FASTPATH_SCENARIO("powmod_mod_1", powmod, owned.x, exponent17,
                          one, 0, zero)
    };
#undef FASTPATH_SCENARIO

    size_t count = sizeof(scenarios) / sizeof(scenarios[0]);
    for (size_t i = 0; i < count; i++) {
        double best = 1e300;
        for (int run = 0; run < runs; run++) {
            double elapsed = scenarios[i].lane(&scenarios[i].cx, iters);
            if (elapsed < best) best = elapsed;
        }
        printf("fastpath\t%s\t%d\t%d\t%d\t%.3f\n",
               scenarios[i].name, limbs, iters, runs,
               best * 1e9 / (double)iters);
        fflush(stdout);
    }

    bigint_pool_release_thread();
    bench_free_value(owned.modulus_minus_one);
    bench_free_value(owned.modulus);
    bench_free_value(owned.bitwise_not_x);
    bench_free_value(owned.negative_x);
    bench_free_value(owned.x);
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
    w_value_free(warm);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        WValue r = w_mersenne_square_mod(s, p);
        bench_sink ^= integer_low_i64(r) + (uint64_t)i;
        w_value_free(r);
    }
    double elapsed = bench_now() - start;
    bigint_pool_release_thread();
    bench_free_value(s);
    return elapsed * 1e9 / (double)iters;
}

#ifdef HAVE_GMP
static void gmp_import_limbs(mpz_t z, const uint64_t *limbs, int32_t n) {
    mpz_import(z, (size_t)n, -1, sizeof(uint64_t), 0, 0, limbs);
}
static void gmp_import_value(mpz_t z, WValue v);

static int value_matches_mpz(WValue value, const mpz_t z) {
    uint64_t scratch;
    int32_t len;
    const uint64_t *limbs = integer_limbs(value, &scratch, &len);
    int value_neg = len < 0;
    int z_neg = mpz_sgn(z) < 0;
    if (value_neg != z_neg) return 0;
    if (len < 0) len = -len;
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

static double bench_gmp_add(const uint64_t *a, const uint64_t *b,
                            int32_t limbs, int iters) {
    uint64_t *out = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!out) die("out of memory in GMP add benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mp_limb_t carry = mpn_add_n((mp_limb_t *)out, (const mp_limb_t *)a,
                                    (const mp_limb_t *)b, (mp_size_t)limbs);
        bench_sink ^= out[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(out);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_sub(const uint64_t *a, const uint64_t *b,
                            int32_t limbs, int iters) {
    uint64_t *out = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!out) die("out of memory in GMP subtract benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mp_limb_t borrow = mpn_sub_n((mp_limb_t *)out, (const mp_limb_t *)a,
                                     (const mp_limb_t *)b, (mp_size_t)limbs);
        bench_sink ^= out[(unsigned)i % (unsigned)limbs] ^ borrow ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(out);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_cmp(const uint64_t *a, const uint64_t *b,
                            int32_t limbs, int iters) {
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        bench_sink ^= (uint64_t)(mpn_cmp((const mp_limb_t *)a,
                                         (const mp_limb_t *)b,
                                         (mp_size_t)limbs) + 1) + (uint64_t)i;
    }
    return (bench_now() - start) * 1e9 / (double)iters;
}

static double bench_gmp_addmul_1(const uint64_t *rp0, const uint64_t *up,
                                 int32_t limbs, int iters) {
    uint64_t *rp = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!rp) die("out of memory in GMP addmul_1 benchmark");
    memcpy(rp, rp0, (size_t)limbs * sizeof(uint64_t));
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t carry = (uint64_t)mpn_addmul_1(
            (mp_limb_t *)rp, (const mp_limb_t *)up, (mp_size_t)limbs,
            (mp_limb_t)0xd6e8feb86659fd93ULL);
        bench_sink ^= rp[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(rp);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_mul_1(const uint64_t *up, int32_t limbs, int iters) {
    uint64_t *rp = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!rp) die("out of memory in GMP mul_1 benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        uint64_t carry = (uint64_t)mpn_mul_1(
            (mp_limb_t *)rp, (const mp_limb_t *)up, (mp_size_t)limbs,
            (mp_limb_t)0xd6e8feb86659fd93ULL);
        bench_sink ^= rp[(unsigned)i % (unsigned)limbs] ^ carry ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(rp);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_bitwise(char op, int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0x082efa98ec4e6c89ULL ^ (uint64_t)limbs);
    uint64_t *b = bench_limbs(limbs, 0x452821e638d01377ULL ^ (uint64_t)limbs);
    mpz_t za, zb;
    mpz_inits(za, zb, NULL);
    gmp_import_limbs(za, a, limbs);
    gmp_import_limbs(zb, b, limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_t zr;
        mpz_init(zr);
        if (op == '&') mpz_and(zr, za, zb);
        else if (op == '|') mpz_ior(zr, za, zb);
        else mpz_xor(zr, za, zb);
        bench_sink ^= (uint64_t)mpz_get_ui(zr) ^ (uint64_t)i;
        mpz_clear(zr);
    }
    double elapsed = bench_now() - start;
    mpz_clears(za, zb, NULL);
    free(a);
    free(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_shift(int left, int32_t limbs, int iters) {
    uint64_t *a = bench_limbs(limbs, 0xbe5466cf34e90c6cULL ^ (uint64_t)limbs);
    mpz_t za;
    mpz_init(za);
    gmp_import_limbs(za, a, limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_t zr;
        mpz_init(zr);
        if (left) mpz_mul_2exp(zr, za, 13);
        else mpz_fdiv_q_2exp(zr, za, 13);
        bench_sink ^= (uint64_t)mpz_get_ui(zr) ^ (uint64_t)i;
        mpz_clear(zr);
    }
    double elapsed = bench_now() - start;
    mpz_clear(za);
    free(a);
    return elapsed * 1e9 / (double)iters;
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

static double bench_gmp_mul_rect(
    const uint64_t *a0, int32_t na, const uint64_t *b, int32_t nb,
    int iters) {
    const uint64_t *large = na >= nb ? a0 : b;
    const uint64_t *small = na >= nb ? b : a0;
    int32_t nl = na >= nb ? na : nb;
    int32_t ns = na >= nb ? nb : na;
    uint64_t *mutable_large =
        (uint64_t *)malloc((size_t)nl * sizeof(uint64_t));
    uint64_t *out =
        (uint64_t *)calloc((size_t)na + (size_t)nb + 4, sizeof(uint64_t));
    if (!mutable_large || !out)
        die("out of memory in GMP rectangular multiply benchmark");
    memcpy(mutable_large, large, (size_t)nl * sizeof(uint64_t));
    uint64_t saved = mutable_large[0];
    mpn_mul((mp_limb_t *)out,
            (const mp_limb_t *)mutable_large, (mp_size_t)nl,
            (const mp_limb_t *)small, (mp_size_t)ns);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mutable_large[0] = saved + (uint64_t)i;
        mpn_mul((mp_limb_t *)out,
                (const mp_limb_t *)mutable_large, (mp_size_t)nl,
                (const mp_limb_t *)small, (mp_size_t)ns);
        bench_sink ^= out[(unsigned)i % ((unsigned)na + (unsigned)nb)];
    }
    double elapsed = bench_now() - start;
    free(out);
    free(mutable_large);
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

static double bench_gmp_divmod(const uint64_t *u, const uint64_t *v,
                               int32_t limbs, int iters) {
    uint64_t *q = (uint64_t *)calloc((size_t)limbs + 1, sizeof(uint64_t));
    uint64_t *r = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    if (!q || !r) die("out of memory in GMP divmod benchmark");
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpn_tdiv_qr((mp_limb_t *)q, (mp_limb_t *)r, 0,
                    (const mp_limb_t *)u, (mp_size_t)(2 * limbs),
                    (const mp_limb_t *)v, (mp_size_t)limbs);
        bench_sink ^= q[(unsigned)i % (unsigned)(limbs + 1)] ^
                      r[(unsigned)i % (unsigned)limbs] ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    free(q);
    free(r);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_divmod_fresh(const uint64_t *u, const uint64_t *v,
                                     int32_t limbs, int iters) {
    mpz_t zu, zv;
    mpz_inits(zu, zv, NULL);
    gmp_import_limbs(zu, u, 2 * limbs);
    gmp_import_limbs(zv, v, limbs);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_t zq, zr;
        mpz_inits(zq, zr, NULL);
        mpz_tdiv_qr(zq, zr, zu, zv);
        bench_sink ^= (uint64_t)mpz_get_ui(zq) ^
                      (uint64_t)mpz_get_ui(zr) ^ (uint64_t)i;
        mpz_clears(zq, zr, NULL);
    }
    double elapsed = bench_now() - start;
    mpz_clears(zu, zv, NULL);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_submul1(const uint64_t *u, const uint64_t *r0,
                                int32_t limbs, uint64_t v, int iters) {
    uint64_t *r = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!r) die("out of memory in GMP submul1 benchmark");
    memcpy(r, r0, (size_t)limbs * sizeof(uint64_t));
    mp_limb_t borrow = 0;
    double start = bench_now();
    for (int i = 0; i < iters; i++)
        borrow ^= mpn_submul_1((mp_limb_t *)r, (const mp_limb_t *)u,
                              (mp_size_t)limbs, (mp_limb_t)v);
    double elapsed = bench_now() - start;
    bench_sink ^= (uint64_t)borrow ^ r[(unsigned)iters % (unsigned)limbs];
    free(r);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_gcd(int32_t limbs, int iters) {
    WValue a, b;
    bench_gcd_operands(limbs, &a, &b);
    uint64_t scratch;
    int32_t len;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, al, len);
    const uint64_t *bl = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, bl, len);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_gcd(zg, za, zb);
        bench_sink ^= (uint64_t)mpz_getlimbn(zg, 0) ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    mpz_clears(za, zb, zg, NULL);
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
}

static double bench_gmp_gcd_random(int32_t limbs, int iters) {
    WValue a, b;
    bench_gcd_random_operands(limbs, &a, &b);
    uint64_t scratch;
    int32_t len;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, al, len);
    const uint64_t *bl = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, bl, len);
    double start = bench_now();
    for (int i = 0; i < iters; i++) {
        mpz_gcd(zg, za, zb);
        bench_sink ^= (uint64_t)mpz_getlimbn(zg, 0) ^ (uint64_t)i;
    }
    double elapsed = bench_now() - start;
    mpz_clears(za, zb, zg, NULL);
    bench_free_value(a);
    bench_free_value(b);
    return elapsed * 1e9 / (double)iters;
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

static void check_linear_against_gmp(int32_t limbs, const uint64_t *a, const uint64_t *b) {
    uint64_t *tw = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    uint64_t *gm = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
    if (!tw || !gm) die("out of memory in linear GMP check");
    uint64_t tc = bn_add_n(tw, a, b, limbs);
    uint64_t gc = (uint64_t)mpn_add_n((mp_limb_t *)gm, (const mp_limb_t *)a,
                                      (const mp_limb_t *)b, (mp_size_t)limbs);
    if (tc != gc) die("add carry mismatch vs GMP");
    assert_same_limbs("add", tw, gm, limbs);
    tc = bn_sub_n(tw, a, b, limbs);
    gc = (uint64_t)mpn_sub_n((mp_limb_t *)gm, (const mp_limb_t *)a,
                             (const mp_limb_t *)b, (mp_size_t)limbs);
    if (tc != gc) die("subtract borrow mismatch vs GMP");
    assert_same_limbs("sub", tw, gm, limbs);
    if ((bn_cmp_n(a, b, limbs) > 0) !=
        (mpn_cmp((const mp_limb_t *)a, (const mp_limb_t *)b,
                 (mp_size_t)limbs) > 0))
        die("comparison mismatch vs GMP");
    free(tw);
    free(gm);
}

static void check_divmod_against_gmp(int32_t limbs, const uint64_t *u,
                                     const uint64_t *v) {
    WBigint *tq, *tr;
    mag_divmod(u, 2 * limbs, v, limbs, &tq, &tr);
    uint64_t *gq = (uint64_t *)calloc((size_t)limbs + 1, sizeof(uint64_t));
    uint64_t *gr = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    if (!gq || !gr) die("out of memory in divmod GMP check");
    mpn_tdiv_qr((mp_limb_t *)gq, (mp_limb_t *)gr, 0,
                (const mp_limb_t *)u, (mp_size_t)(2 * limbs),
                (const mp_limb_t *)v, (mp_size_t)limbs);
    for (int32_t i = 0; i < limbs + 1; i++) {
        uint64_t got = i < tq->size ? tq->limbs[i] : 0;
        if (got != gq[i]) die("div quotient mismatch vs GMP");
    }
    for (int32_t i = 0; i < limbs; i++) {
        uint64_t got = i < tr->size ? tr->limbs[i] : 0;
        if (got != gr[i]) die("div remainder mismatch vs GMP");
    }
    bigint_backing_free(tq);
    bigint_backing_free(tr);
    free(gq);
    free(gr);
}

static void check_gcd_against_gmp(int32_t limbs) {
    WValue a, b;
    bench_gcd_operands(limbs, &a, &b);
    WValue tg = bigint_gcd_any(a, b);
    uint64_t scratch;
    int32_t len;
    mpz_t za, zb, gg;
    mpz_inits(za, zb, gg, NULL);
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, al, len);
    const uint64_t *bl = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, bl, len);
    mpz_gcd(gg, za, zb);
    if (!value_matches_mpz(tg, gg)) die("gcd mismatch vs GMP");
    mpz_clears(za, zb, gg, NULL);
    if (tg != a && tg != b) bench_free_value(tg);
    bench_free_value(a);
    bench_free_value(b);
}

static void check_random_gcd_against_gmp(int32_t limbs) {
    WValue a, b;
    bench_gcd_random_operands(limbs, &a, &b);
    WValue tg = bigint_gcd_any(a, b);
    uint64_t scratch;
    int32_t len;
    mpz_t za, zb, gg;
    mpz_inits(za, zb, gg, NULL);
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, al, len);
    const uint64_t *bl = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, bl, len);
    mpz_gcd(gg, za, zb);
    if (!value_matches_mpz(tg, gg)) die("random gcd mismatch vs GMP");
    mpz_clears(za, zb, gg, NULL);
    if (tg != a && tg != b) bench_free_value(tg);
    bench_free_value(a);
    bench_free_value(b);
}

static uint64_t gcd_fuzz_next(uint64_t *state) {
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static void check_tostr_one_limb_case(uint64_t magnitude, int negative,
                                      int case_index) {
    WBigint *b = bigint_alloc_raw(1);
    b->limbs[0] = magnitude;
    b->size = magnitude == 0 ? 0 : (negative ? -1 : 1);
    WValue text = bigint_to_s_impl(b, b->size);

    mpz_t expected_z;
    mpz_init(expected_z);
    mpz_import(expected_z, 1, -1, sizeof(magnitude), 0, 0, &magnitude);
    if (negative && magnitude != 0) mpz_neg(expected_z, expected_z);
    char *expected = mpz_get_str(NULL, 10, expected_z);
    if (strcmp(as_str(text), expected) != 0) {
        fprintf(stderr,
                "one-limb tostr mismatch: case=%d magnitude=%llu sign=%s"
                " got=%s expected=%s\n",
                case_index, (unsigned long long)magnitude,
                negative ? "negative" : "positive", as_str(text), expected);
        abort();
    }

    void (*gmp_free_fn)(void *, size_t);
    mp_get_memory_functions(NULL, NULL, &gmp_free_fn);
    gmp_free_fn(expected, strlen(expected) + 1);
    mpz_clear(expected_z);
    w_value_free(text);
    bigint_backing_free(b);
}

static void check_tostr_two_limb_case(uint64_t lo, uint64_t hi, int negative,
                                      int case_index) {
    uint64_t limbs[2] = {lo, hi};
    WBigint *b = bigint_alloc_raw(2);
    b->limbs[0] = lo;
    b->limbs[1] = hi;
    b->size = negative ? -2 : 2;
    WValue text = bigint_to_s_impl(b, b->size);

    mpz_t expected_z;
    mpz_init(expected_z);
    mpz_import(expected_z, 2, -1, sizeof(uint64_t), 0, 0, limbs);
    if (negative) mpz_neg(expected_z, expected_z);
    char *expected = mpz_get_str(NULL, 10, expected_z);
    if (strcmp(as_str(text), expected) != 0) {
        fprintf(stderr,
                "two-limb tostr mismatch: case=%d hi=%llu lo=%llu sign=%s"
                " got=%s expected=%s\n",
                case_index, (unsigned long long)hi, (unsigned long long)lo,
                negative ? "negative" : "positive", as_str(text), expected);
        abort();
    }

    void (*gmp_free_fn)(void *, size_t);
    mp_get_memory_functions(NULL, NULL, &gmp_free_fn);
    gmp_free_fn(expected, strlen(expected) + 1);
    mpz_clear(expected_z);
    w_value_free(text);
    bigint_backing_free(b);
}

static void fuzz_tostr_small_against_gmp(int cases) {
    int checked = 0;
    /* Every decimal digit-count transition representable by u64, on both
     * sides and with both signs.  Include the signed/unsigned handoff and the
     * absolute u64 endpoint explicitly. */
    check_tostr_one_limb_case(0, 0, checked++);
    uint64_t power = 10;
    for (int digits = 1; digits <= 19; digits++) {
        uint64_t values[3] = {power - 1, power, power + 1};
        for (int vi = 0; vi < 3; vi++) {
            check_tostr_one_limb_case(values[vi], 0, checked++);
            check_tostr_one_limb_case(values[vi], 1, checked++);
        }
        if (digits < 19) power *= 10;
    }
    const uint64_t endpoints[] = {
        (1ULL << 63) - 1, 1ULL << 63, (1ULL << 63) + 1,
        UINT64_MAX - 1, UINT64_MAX
    };
    for (size_t i = 0; i < sizeof(endpoints) / sizeof(endpoints[0]); i++) {
        check_tostr_one_limb_case(endpoints[i], 0, checked++);
        check_tostr_one_limb_case(endpoints[i], 1, checked++);
    }

    uint64_t state = 0x510e527fade682d1ULL;
    for (int i = 0; i < cases; i++) {
        uint64_t magnitude = gcd_fuzz_next(&state);
        check_tostr_one_limb_case(magnitude, 0, checked++);
        if (magnitude != 0)
            check_tostr_one_limb_case(magnitude, 1, checked++);
    }

    const uint64_t two_limb_endpoints[][2] = {
        {0, 1}, {UINT64_MAX, 1}, {0, 1ULL << 63},
        {UINT64_MAX - 1, UINT64_MAX}, {UINT64_MAX, UINT64_MAX}
    };
    for (size_t i = 0;
         i < sizeof(two_limb_endpoints) / sizeof(two_limb_endpoints[0]);
         i++) {
        check_tostr_two_limb_case(
            two_limb_endpoints[i][0], two_limb_endpoints[i][1], 0,
            checked++);
        check_tostr_two_limb_case(
            two_limb_endpoints[i][0], two_limb_endpoints[i][1], 1,
            checked++);
    }
    for (int i = 0; i < cases; i++) {
        uint64_t lo = gcd_fuzz_next(&state);
        uint64_t hi = gcd_fuzz_next(&state) | 1ULL;
        check_tostr_two_limb_case(lo, hi, 0, checked++);
        check_tostr_two_limb_case(lo, hi, 1, checked++);
    }
    printf("one-/two-limb tostr fuzz vs GMP: %d cases match"
           " (%d random values per width)\n", checked, cases);
}

static int fuzz_sqr_against_gmp(int cases, int32_t max_limbs) {
    uint64_t state = 0x9e3779b97f4a7c15ULL;
    for (int t = 0; t < cases; t++) {
        int32_t limbs = t < 80
            ? 1 + t
            : 1 + (int32_t)(gcd_fuzz_next(&state) % (uint64_t)max_limbs);
        if (limbs > max_limbs) limbs = max_limbs;
        uint64_t *a = bench_limbs(limbs, gcd_fuzz_next(&state));
        uint64_t *tw = (uint64_t *)calloc((size_t)2 * limbs + 4U, sizeof(uint64_t));
        uint64_t *gm = (uint64_t *)calloc((size_t)2 * limbs + 4U, sizeof(uint64_t));
        if (!a || !tw || !gm) die("out of memory in square fuzz");
        bigint_sqr_dispatch(tw, a, limbs);
        mpn_sqr((mp_limb_t *)gm, (const mp_limb_t *)a, (mp_size_t)limbs);
        if (memcmp(tw, gm, (size_t)2 * limbs * sizeof(uint64_t)) != 0) {
            fprintf(stderr, "square fuzz mismatch: case=%d limbs=%d\n", t, limbs);
            free(gm);
            free(tw);
            free(a);
            return 1;
        }
        free(gm);
        free(tw);
        free(a);
    }
    return 0;
}

static int fuzz_mul_against_gmp(int cases, int32_t max_limbs) {
    uint64_t state = 0x243f6a8885a308d3ULL;
    for (int t = 0; t < cases; t++) {
        int32_t na = t < 80
            ? 1 + t
            : 1 + (int32_t)(gcd_fuzz_next(&state) % (uint64_t)max_limbs);
        int32_t nb = t < 80
            ? 1 + (int32_t)(((uint32_t)t * 37U) % 80U)
            : 1 + (int32_t)(gcd_fuzz_next(&state) % (uint64_t)max_limbs);
        if (na > max_limbs) na = max_limbs;
        if (nb > max_limbs) nb = max_limbs;
        uint64_t *a = bench_limbs(na, gcd_fuzz_next(&state));
        uint64_t *b = bench_limbs(nb, gcd_fuzz_next(&state));
        size_t product_limbs = (size_t)na + (size_t)nb;
        uint64_t *tw = (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        uint64_t *gm = (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        if (!a || !b || !tw || !gm) die("out of memory in multiply fuzz");
        bigint_mul_dispatch(tw, a, na, b, nb);
        if (na >= nb)
            mpn_mul((mp_limb_t *)gm, (const mp_limb_t *)a, (mp_size_t)na,
                    (const mp_limb_t *)b, (mp_size_t)nb);
        else
            mpn_mul((mp_limb_t *)gm, (const mp_limb_t *)b, (mp_size_t)nb,
                    (const mp_limb_t *)a, (mp_size_t)na);
        if (memcmp(tw, gm, product_limbs * sizeof(uint64_t)) != 0) {
            fprintf(stderr,
                    "multiply fuzz mismatch: case=%d na=%d nb=%d\n",
                    t, na, nb);
            free(gm);
            free(tw);
            free(b);
            free(a);
            return 1;
        }
        free(gm);
        free(tw);
        free(b);
        free(a);
    }
    return 0;
}

static int fuzz_mul_exact_against_gmp(int cases, int32_t limbs) {
    uint64_t state = 0x13198a2e03707344ULL ^ (uint64_t)limbs;
    for (int t = 0; t < cases; t++) {
        uint64_t *a = bench_limbs(limbs, gcd_fuzz_next(&state));
        uint64_t *b = bench_limbs(limbs, gcd_fuzz_next(&state));
        size_t product_limbs = (size_t)2 * (size_t)limbs;
        uint64_t *tw = (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        uint64_t *gm = (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        if (!a || !b || !tw || !gm)
            die("out of memory in exact-width multiply fuzz");
        bigint_mul_dispatch(tw, a, limbs, b, limbs);
        mpn_mul((mp_limb_t *)gm, (const mp_limb_t *)a, (mp_size_t)limbs,
                (const mp_limb_t *)b, (mp_size_t)limbs);
        if (memcmp(tw, gm, product_limbs * sizeof(uint64_t)) != 0) {
            fprintf(stderr,
                    "exact-width multiply fuzz mismatch: case=%d limbs=%d\n",
                    t, limbs);
            free(gm);
            free(tw);
            free(b);
            free(a);
            return 1;
        }
        free(gm);
        free(tw);
        free(b);
        free(a);
    }
    return 0;
}

static int fuzz_mul_rect4_against_gmp(int cases, int32_t max_short_limbs) {
    static const int32_t boundary_short_limbs[] = {
        BN_RECT4_PAR_THRESHOLD,
        BN_RECT4_PAR_THRESHOLD + 1,
        BN_RECT4_PAR_THRESHOLD + 7,
        BN_RECT4_PAR_THRESHOLD + 63,
        BN_RECT4_PAR_THRESHOLD * 2 - 1,
        BN_RECT4_PAR_THRESHOLD * 2
    };
    uint64_t state = 0xa4093822299f31d0ULL;
    int32_t span = max_short_limbs - BN_RECT4_PAR_THRESHOLD + 1;
    for (int t = 0; t < cases; t++) {
        int32_t lo;
        int boundary_index = t - (t + 3) / 4;
        if ((t & 3) == 0) {
            /* The tuned serial rung used by the 24-limb x**5 path. */
            lo = 24;
        } else if (boundary_index <
                       (int)(sizeof(boundary_short_limbs) /
                             sizeof(boundary_short_limbs[0])) &&
                   boundary_short_limbs[boundary_index] <= max_short_limbs) {
            lo = boundary_short_limbs[boundary_index];
        } else {
            lo = BN_RECT4_PAR_THRESHOLD +
                 (int32_t)(gcd_fuzz_next(&state) % (uint64_t)span);
        }
        int32_t hi = 4 * lo;
        uint64_t *big = bench_limbs(hi, gcd_fuzz_next(&state));
        uint64_t *small = bench_limbs(lo, gcd_fuzz_next(&state));
        size_t product_limbs = (size_t)hi + (size_t)lo;
        uint64_t *tw =
            (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        uint64_t *gm =
            (uint64_t *)calloc(product_limbs + 4U, sizeof(uint64_t));
        if (!big || !small || !tw || !gm)
            die("out of memory in exact 4:1 multiply fuzz");

        if (t & 1)
            bigint_mul_dispatch(tw, small, lo, big, hi);
        else
            bigint_mul_dispatch(tw, big, hi, small, lo);
        mpn_mul((mp_limb_t *)gm, (const mp_limb_t *)big, (mp_size_t)hi,
                (const mp_limb_t *)small, (mp_size_t)lo);
        if (memcmp(tw, gm, product_limbs * sizeof(uint64_t)) != 0) {
            fprintf(stderr,
                    "exact 4:1 multiply fuzz mismatch: case=%d hi=%d lo=%d"
                    " order=%s\n",
                    t, hi, lo, (t & 1) ? "small-first" : "big-first");
            free(gm);
            free(tw);
            free(small);
            free(big);
            return 1;
        }
        free(gm);
        free(tw);
        free(small);
        free(big);
    }
    return 0;
}

static int fuzz_pow5_against_gmp(int cases, int32_t max_limbs) {
    static const uint64_t one_limb_boundaries[] = {
        0,
        1,
        (uint64_t)W_INT48_MAX,
        (uint64_t)W_INT48_MAX + 1,
        UINT64_C(1) << 63,
        UINT64_MAX
    };
    uint64_t state = 0x082efa98ec4e6c89ULL;
    mpz_t zbase, zpow;
    mpz_inits(zbase, zpow, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t limbs;
        WBigint *base_storage;
        if ((t & 3) == 0) {
            limbs = 1;
            base_storage = bigint_alloc(1);
            int boundary = t / 4;
            base_storage->limbs[0] =
                boundary < (int)(sizeof(one_limb_boundaries) /
                                 sizeof(one_limb_boundaries[0]))
                    ? one_limb_boundaries[boundary]
                    : gcd_fuzz_next(&state);
        } else {
            limbs = 1 + (int32_t)(
                gcd_fuzz_next(&state) % (uint64_t)max_limbs);
            WValue generated = bench_bigint(limbs, gcd_fuzz_next(&state));
            base_storage = w_as_bigint(generated);
        }
        base_storage->size = (t & 4) ? -limbs : limbs;
        WValue base = bigint_box(base_storage);
        WValue got = w_pow(base, w_box_int(BENCH_BOXED_POW_EXP));
        gmp_import_limbs(zbase, base_storage->limbs, limbs);
        if (base_storage->size < 0) mpz_neg(zbase, zbase);
        mpz_pow_ui(zpow, zbase, BENCH_BOXED_POW_EXP);
        if (!value_matches_mpz(got, zpow)) {
            fprintf(stderr,
                    "power fuzz mismatch: case=%d limbs=%d exponent=%d\n",
                    t, limbs, BENCH_BOXED_POW_EXP);
            bench_free_value(got);
            bench_free_value(base);
            mpz_clears(zbase, zpow, NULL);
            return 1;
        }
        bench_free_value(got);
        bench_free_value(base);
    }
    mpz_clears(zbase, zpow, NULL);
    return 0;
}

static int fuzz_mulmod_bnm1_against_gmp(int cases, int32_t max_limbs) {
    static const int32_t boundaries[] = {
        1, 2, 3, 6, 7, 8, 9, 12, 16, 24, 32, 48, 64,
        W_POWM_REDC_MULLO_MIN - 1,
        W_POWM_REDC_MULLO_MIN,
        W_POWM_REDC_MULLO_MIN + 1,
        127, 128, 129
    };
    uint64_t state = 0x3c6ef372fe94f82bULL;
    mpz_t za, zb, zm, zr;
    mpz_inits(za, zb, zm, zr, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t limbs;
        if (t < (int)(sizeof(boundaries) / sizeof(boundaries[0])) &&
            boundaries[t] <= max_limbs)
            limbs = boundaries[t];
        else
            limbs = 1 + (int32_t)(gcd_fuzz_next(&state) %
                                  (uint64_t)max_limbs);
        uint64_t *a = bench_limbs(limbs, gcd_fuzz_next(&state));
        uint64_t *b = bench_limbs(limbs, gcd_fuzz_next(&state));
        uint64_t *got = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
        uint64_t *expected =
            (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
        uint64_t *scratch =
            (uint64_t *)calloc((size_t)4 * limbs + 16U, sizeof(uint64_t));
        if (!a || !b || !got || !expected || !scratch)
            die("out of memory in B^n-1 product fuzz");

        /* Force the two zero representations and the CRT's signed extremes,
         * in addition to the random full-width cases. */
        switch (t & 15) {
        case 0: memset(a, 0, (size_t)limbs * sizeof(uint64_t)); break;
        case 1: memset(a, 0xff, (size_t)limbs * sizeof(uint64_t)); break;
        case 2: memset(b, 0, (size_t)limbs * sizeof(uint64_t)); break;
        case 3: memset(b, 0xff, (size_t)limbs * sizeof(uint64_t)); break;
        case 4:
            memset(a, 0, (size_t)limbs * sizeof(uint64_t));
            memset(b, 0xff, (size_t)limbs * sizeof(uint64_t));
            a[0] = 1;
            b[0]--;
            break;
        default: break;
        }

        w_mulmod_bnm1(got, a, b, limbs, scratch);
        gmp_import_limbs(za, a, limbs);
        gmp_import_limbs(zb, b, limbs);
        mpz_set_ui(zm, 1);
        mpz_mul_2exp(zm, zm, (mp_bitcnt_t)limbs * 64U);
        mpz_sub_ui(zm, zm, 1);
        mpz_mul(zr, za, zb);
        mpz_mod(zr, zr, zm);
        size_t count = 0;
        mpz_export(expected, &count, -1, sizeof(uint64_t), 0, 0, zr);
        if (count > (size_t)limbs ||
            memcmp(got, expected, (size_t)limbs * sizeof(uint64_t)) != 0) {
            fprintf(stderr,
                    "B^n-1 product fuzz mismatch: case=%d limbs=%d\n",
                    t, limbs);
            free(scratch); free(expected); free(got); free(b); free(a);
            mpz_clears(za, zb, zm, zr, NULL);
            return 1;
        }
        free(scratch); free(expected); free(got); free(b); free(a);
    }
    mpz_clears(za, zb, zm, zr, NULL);
    return 0;
}

static int fuzz_powmod_against_gmp(int cases, int32_t max_limbs) {
    static const int32_t boundaries[] = {
        1, 2, 3, 4, 7, 8, 16, 32, 64,
        W_POWM_REDC_MULLO_MIN - 2,
        W_POWM_REDC_MULLO_MIN - 1,
        W_POWM_REDC_MULLO_MIN,
        W_POWM_REDC_MULLO_MIN + 1,
        W_POWM_REDC_MULLO_MIN + 2,
        126, 127, 128, 129
    };
    uint64_t state = 0xbb67ae8584caa73bULL;
    mpz_t za, ze, zm, zr;
    mpz_inits(za, ze, zm, zr, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t limbs;
        if (t < (int)(sizeof(boundaries) / sizeof(boundaries[0])) &&
            boundaries[t] <= max_limbs) {
            limbs = boundaries[t];
        } else if (max_limbs >= W_POWM_REDC_MULLO_MIN && (t & 1)) {
            limbs = W_POWM_REDC_MULLO_MIN + (int32_t)(
                gcd_fuzz_next(&state) %
                (uint64_t)(max_limbs - W_POWM_REDC_MULLO_MIN + 1));
        } else {
            limbs = 1 + (int32_t)(gcd_fuzz_next(&state) %
                                  (uint64_t)max_limbs);
        }
        int32_t base_limbs = (t & 7) == 0 ? 2 * limbs : limbs;
        WValue base = bench_bigint(base_limbs, gcd_fuzz_next(&state));
        WValue mod = bench_bigint(limbs, gcd_fuzz_next(&state));
        WBigint *mb = w_as_bigint(mod);
        mb->limbs[0] |= 1ULL;                     /* Montgomery requires odd */
        if (t & 2) w_as_bigint(base)->size = -w_as_bigint(base)->size;
        if (t & 4) mb->size = -mb->size;          /* result still modulo |m| */

        WValue exponent;
        if ((t & 31) == 0) {
            exponent = w_box_int(0);
        } else if ((t & 31) == 1) {
            exponent = w_box_int(1);
        } else {
            int32_t elen = 1 + (int32_t)(gcd_fuzz_next(&state) % 4U);
            exponent = bench_bigint(elen, gcd_fuzz_next(&state));
            if ((t & 15) == 2)
                memset(w_as_bigint(exponent)->limbs, 0xff,
                       (size_t)elen * sizeof(uint64_t));
        }

        WValue got = bigint_powmod_any(base, exponent, mod);
        gmp_import_value(za, base);
        gmp_import_value(ze, exponent);
        gmp_import_value(zm, mod);
        mpz_abs(zm, zm);
        mpz_powm(zr, za, ze, zm);
        if (!value_matches_mpz(got, zr)) {
            fprintf(stderr,
                    "powmod fuzz mismatch: case=%d modulus_limbs=%d"
                    " exponent_limbs=%d\n",
                    t, limbs,
                    w_is_bigint(exponent)
                        ? (w_as_bigint(exponent)->size < 0
                               ? -w_as_bigint(exponent)->size
                               : w_as_bigint(exponent)->size)
                        : 0);
            if (got != base && got != exponent && got != mod)
                bench_free_value(got);
            bench_free_value(base); bench_free_value(exponent);
            bench_free_value(mod);
            mpz_clears(za, ze, zm, zr, NULL);
            return 1;
        }
        if (got != base && got != exponent && got != mod)
            bench_free_value(got);
        bench_free_value(base); bench_free_value(exponent);
        bench_free_value(mod);
    }
    mpz_clears(za, ze, zm, zr, NULL);
    return 0;
}

typedef struct {
    int id;
    int iters;
    int32_t limbs;
    _Atomic int *ready;
    _Atomic int *go;
    _Atomic int *bad;
} BenchPowmodStress;

static void *bench_powmod_stress_worker(void *opaque) {
    BenchPowmodStress *job = (BenchPowmodStress *)opaque;
    WValue base = bench_bigint(
        job->limbs, UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)job->id);
    WValue exponent = bench_bigint(
        2, UINT64_C(0x13198a2e03707344) ^ ((uint64_t)job->id << 32));
    WValue modulus = bench_bigint(
        job->limbs, UINT64_C(0xa4093822299f31d0) ^ (uint64_t)job->id);
    WBigint *bb = w_as_bigint(base);
    WBigint *mb = w_as_bigint(modulus);
    mb->limbs[0] |= 1ULL;
    if (job->id & 1) bb->size = -bb->size;
    if (job->id & 2) mb->size = -mb->size;
    uint64_t saved = bb->limbs[0];
    mpz_t za, ze, zm, zr;
    mpz_inits(za, ze, zm, zr, NULL);
    gmp_import_value(ze, exponent);
    gmp_import_value(zm, modulus);
    mpz_abs(zm, zm);

    atomic_fetch_add_explicit(job->ready, 1, memory_order_release);
    while (!atomic_load_explicit(job->go, memory_order_acquire))
        bn_toom_pool_spin_hint();
    for (int i = 0; i < job->iters; i++) {
        bb->limbs[0] = saved + (uint64_t)i;
        WValue got = bigint_powmod_any(base, exponent, modulus);
        gmp_import_value(za, base);
        mpz_powm(zr, za, ze, zm);
        if (!value_matches_mpz(got, zr)) {
            atomic_store_explicit(job->bad, 1, memory_order_release);
            if (got != base && got != exponent && got != modulus)
                bench_free_value(got);
            break;
        }
        if (got != base && got != exponent && got != modulus)
            bench_free_value(got);
    }
    mpz_clears(za, ze, zm, zr, NULL);
    bench_free_value(base);
    bench_free_value(exponent);
    bench_free_value(modulus);
    bn_ws_release_thread();
    bigint_pool_release_thread();
    return NULL;
}

static void stress_powmod_against_gmp(int threads, int iters, int32_t limbs) {
    pthread_t *workers =
        (pthread_t *)malloc((size_t)threads * sizeof(pthread_t));
    BenchPowmodStress *jobs =
        (BenchPowmodStress *)calloc((size_t)threads, sizeof(*jobs));
    if (!workers || !jobs) die("out of memory creating powmod stress");
    _Atomic int ready = 0;
    _Atomic int go = 0;
    _Atomic int bad = 0;
    for (int t = 0; t < threads; t++) {
        jobs[t].id = t;
        jobs[t].iters = iters;
        jobs[t].limbs = limbs;
        jobs[t].ready = &ready;
        jobs[t].go = &go;
        jobs[t].bad = &bad;
        if (pthread_create(&workers[t], NULL, bench_powmod_stress_worker,
                           &jobs[t]) != 0)
            die("could not create powmod stress worker");
    }
    while (atomic_load_explicit(&ready, memory_order_acquire) < threads)
        bn_toom_pool_spin_hint();
    atomic_store_explicit(&go, 1, memory_order_release);
    for (int t = 0; t < threads; t++) pthread_join(workers[t], NULL);
    int failed = atomic_load_explicit(&bad, memory_order_acquire);
    free(jobs);
    free(workers);
    if (failed) die("parallel powmod stress mismatch");
    printf("parallel powmod stress vs GMP: %d threads x %d iterations"
           " match (%d limbs)\n", threads, iters, limbs);
}

typedef struct {
    int id;
    int iters;
    int32_t limbs;
    _Atomic int *ready;
    _Atomic int *go;
    _Atomic int *bad;
} BenchParallelMulStress;

static void *bench_parallel_mul_stress_worker(void *opaque) {
    BenchParallelMulStress *job = (BenchParallelMulStress *)opaque;
    int32_t n = job->limbs;
    uint64_t *a = bench_limbs(
        n, 0x243f6a8885a308d3ULL ^ (uint64_t)job->id);
    uint64_t *b = bench_limbs(
        n, 0x13198a2e03707344ULL ^ ((uint64_t)job->id << 32));
    uint64_t *tw =
        (uint64_t *)malloc(((size_t)2 * n + 4) * sizeof(uint64_t));
    uint64_t *gm =
        (uint64_t *)malloc(((size_t)2 * n + 4) * sizeof(uint64_t));
    if (!a || !b || !tw || !gm)
        die("out of memory in parallel multiply stress");
    uint64_t saved = a[0];
    atomic_fetch_add_explicit(job->ready, 1, memory_order_release);
    while (!atomic_load_explicit(job->go, memory_order_acquire))
        bn_toom_pool_spin_hint();
    for (int i = 0; i < job->iters; i++) {
        a[0] = saved + (uint64_t)i;
        bigint_mul_dispatch(tw, a, n, b, n);
        mpn_mul_n((mp_limb_t *)gm, (const mp_limb_t *)a,
                  (const mp_limb_t *)b, (mp_size_t)n);
        if (memcmp(tw, gm, (size_t)2 * n * sizeof(uint64_t)) != 0) {
            atomic_store_explicit(job->bad, 1, memory_order_release);
            break;
        }
        bigint_sqr_dispatch(tw, a, n);
        mpn_sqr((mp_limb_t *)gm, (const mp_limb_t *)a, (mp_size_t)n);
        if (memcmp(tw, gm, (size_t)2 * n * sizeof(uint64_t)) != 0) {
            atomic_store_explicit(job->bad, 1, memory_order_release);
            break;
        }
    }
    free(gm);
    free(tw);
    free(b);
    free(a);
    bn_ws_release_thread();
    bigint_pool_release_thread();
    return NULL;
}

static void stress_parallel_mul_against_gmp(
    int threads, int iters, int32_t limbs) {
    pthread_t *workers =
        (pthread_t *)malloc((size_t)threads * sizeof(pthread_t));
    BenchParallelMulStress *jobs =
        (BenchParallelMulStress *)calloc(
            (size_t)threads, sizeof(BenchParallelMulStress));
    if (!workers || !jobs)
        die("out of memory creating parallel multiply stress");
    _Atomic int ready = 0;
    _Atomic int go = 0;
    _Atomic int bad = 0;
    for (int t = 0; t < threads; t++) {
        jobs[t].id = t;
        jobs[t].iters = iters;
        jobs[t].limbs = limbs;
        jobs[t].ready = &ready;
        jobs[t].go = &go;
        jobs[t].bad = &bad;
        if (pthread_create(
                &workers[t], NULL,
                bench_parallel_mul_stress_worker, &jobs[t]) != 0)
            die("could not create parallel multiply stress worker");
    }
    while (atomic_load_explicit(&ready, memory_order_acquire) < threads)
        bn_toom_pool_spin_hint();
    atomic_store_explicit(&go, 1, memory_order_release);
    for (int t = 0; t < threads; t++)
        pthread_join(workers[t], NULL);
    int failed = atomic_load_explicit(&bad, memory_order_acquire);
    free(jobs);
    free(workers);
    if (failed) die("parallel multiply/square stress mismatch");
    printf("parallel multiply/square stress vs GMP: %d threads x %d"
           " iterations match (%d limbs)\n",
           threads, iters, limbs);
}

static void fuzz_divmod_against_gmp(int cases, int32_t max_limbs) {
    uint64_t state = 0xa4093822299f31d0ULL;
    for (int t = 0; t < cases; t++) {
        int32_t limbs = t < 80
            ? 1 + t
            : 1 + (int32_t)(gcd_fuzz_next(&state) % (uint64_t)max_limbs);
        if (limbs > max_limbs) limbs = max_limbs;
        uint64_t *v = bench_limbs(
            limbs, gcd_fuzz_next(&state) ^ ((uint64_t)t << 32));
        uint64_t *u;
        if (limbs >= 8 && (t & 3) == 0) {
            /*
             * Construct U = QV+R so exact divisibility, V-1, and residuals
             * around the triangular certificate's error bound are exercised
             * deliberately instead of waiting for negligible-probability
             * random hits.  Keeping Q's top below B/4 guarantees the sum fits
             * in exactly 2*limbs limbs.
             */
            uint64_t *cq = bench_limbs(
                limbs, gcd_fuzz_next(&state) ^ (uint64_t)t);
            uint64_t *cr =
                (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
            u = (uint64_t *)calloc((size_t)2 * limbs, sizeof(uint64_t));
            if (!cq || !cr || !u)
                die("out of memory constructing division fuzz case");
            cq[limbs - 1] >>= 2;
            switch ((t >> 2) % 6) {
            case 0:                         /* R = 0 */
                break;
            case 1:                         /* R = 1 */
                cr[0] = 1;
                break;
            case 2:                         /* R = V-1 */
                memcpy(cr, v, (size_t)limbs * sizeof(uint64_t));
                for (int32_t i = 0; i < limbs; i++) {
                    uint64_t old = cr[i];
                    cr[i] = old - 1;
                    if (old != 0) break;
                }
                break;
            case 3:                         /* R = error_bound-1 */
                for (int32_t i = 0; i < limbs - 1; i++)
                    cr[i] = UINT64_MAX;
                cr[limbs - 1] = (uint64_t)(limbs - 3);
                break;
            case 4:                         /* R = error_bound */
                cr[limbs - 1] = (uint64_t)(limbs - 2);
                break;
            default:                        /* R = error_bound+1 */
                cr[0] = 1;
                cr[limbs - 1] = (uint64_t)(limbs - 2);
                break;
            }
            mpn_mul_n((mp_limb_t *)u, (const mp_limb_t *)cq,
                      (const mp_limb_t *)v, (mp_size_t)limbs);
            uint64_t carry = (uint64_t)mpn_add_n(
                (mp_limb_t *)u, (const mp_limb_t *)u,
                (const mp_limb_t *)cr, (mp_size_t)limbs);
            for (int32_t i = limbs; carry && i < 2 * limbs; i++) {
                uint64_t old = u[i];
                u[i] = old + 1;
                carry = u[i] == 0;
            }
            if (carry || u[2 * limbs - 1] == 0)
                die("invalid constructed division fuzz width");
            free(cr);
            free(cq);
        } else {
            u = bench_limbs(
                2 * limbs, gcd_fuzz_next(&state) ^ (uint64_t)t);
            /* Cover every normalization shift, not only top-bit-set V. */
            v[limbs - 1] >>= (unsigned)t & 63U;
        }
        uint64_t *gq =
            (uint64_t *)calloc((size_t)limbs + 1U, sizeof(uint64_t));
        uint64_t *gr =
            (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
        if (!u || !v || !gq || !gr)
            die("out of memory in division fuzz");

        mpn_tdiv_qr((mp_limb_t *)gq, (mp_limb_t *)gr, 0,
                    (const mp_limb_t *)u, (mp_size_t)(2 * limbs),
                    (const mp_limb_t *)v, (mp_size_t)limbs);

        WBigint *q;
        mag_divmod(u, 2 * limbs, v, limbs, &q, NULL);
        for (int32_t i = 0; i < limbs + 1; i++) {
            uint64_t got = i < q->size ? q->limbs[i] : 0;
            if (got != gq[i]) {
                fprintf(stderr,
                        "quotient-only division fuzz mismatch:"
                        " case=%d limbs=%d limb=%d\n",
                        t, limbs, i);
                abort();
            }
        }

        WBigint *r;
        mag_divmod(u, 2 * limbs, v, limbs, NULL, &r);
        for (int32_t i = 0; i < limbs; i++) {
            uint64_t got = i < r->size ? r->limbs[i] : 0;
            if (got != gr[i]) {
                fprintf(stderr,
                        "remainder-only division fuzz mismatch:"
                        " case=%d limbs=%d limb=%d\n",
                        t, limbs, i);
                abort();
            }
        }

        bigint_backing_free(r);
        bigint_backing_free(q);
        free(gr);
        free(gq);
        free(v);
        free(u);
    }
    printf("multi-limb div/mod fuzz vs GMP: %d/%d mixed random/boundary"
           " cases match (max %d divisor limbs)\n",
           cases, cases, max_limbs);
}

static void fuzz_div_reciprocal_against_gmp(
    int cases, int32_t limbs) {
    uint64_t state = 0xbb67ae8584caa73bULL ^ (uint64_t)limbs;
    uint64_t *v = NULL;
    uint64_t *u =
        (uint64_t *)malloc((size_t)2 * limbs * sizeof(uint64_t));
    uint64_t *gq =
        (uint64_t *)calloc((size_t)limbs + 1, sizeof(uint64_t));
    uint64_t *gr =
        (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    if (!u || !gq || !gr)
        die("out of memory in reciprocal division fuzz");
    for (int t = 0; t < cases; t++) {
        if ((t & 7) == 0) {
            free(v);
            v = bench_limbs(
                limbs, gcd_fuzz_next(&state) ^ (uint64_t)t);
        }
        for (int32_t i = 0; i < 2 * limbs; i++)
            u[i] = gcd_fuzz_next(&state);
        u[2 * limbs - 1] |= 1ULL << 63;
        memset(gq, 0, ((size_t)limbs + 1) * sizeof(uint64_t));
        memset(gr, 0, (size_t)limbs * sizeof(uint64_t));
        mpn_tdiv_qr((mp_limb_t *)gq, (mp_limb_t *)gr, 0,
                    (const mp_limb_t *)u, (mp_size_t)(2 * limbs),
                    (const mp_limb_t *)v, (mp_size_t)limbs);
        WBigint *q;
        mag_divmod(u, 2 * limbs, v, limbs, &q, NULL);
        for (int32_t i = 0; i < limbs + 1; i++) {
            uint64_t got = i < q->size ? q->limbs[i] : 0;
            if (got != gq[i]) {
                fprintf(stderr,
                        "reciprocal quotient fuzz mismatch:"
                        " case=%d limbs=%d limb=%d\n",
                        t, limbs, i);
                abort();
            }
        }
        bigint_backing_free(q);

        WBigint *r;
        mag_divmod(u, 2 * limbs, v, limbs, NULL, &r);
        for (int32_t i = 0; i < limbs; i++) {
            uint64_t got = i < r->size ? r->limbs[i] : 0;
            if (got != gr[i]) {
                fprintf(stderr,
                        "reciprocal remainder fuzz mismatch:"
                        " case=%d limbs=%d limb=%d\n",
                        t, limbs, i);
                abort();
            }
        }
        bigint_backing_free(r);

        if ((t & 3) == 0) {
            WBigint *both_q, *both_r;
            mag_divmod(
                u, 2 * limbs, v, limbs, &both_q, &both_r);
            for (int32_t i = 0; i < limbs + 1; i++) {
                uint64_t got =
                    i < both_q->size ? both_q->limbs[i] : 0;
                if (got != gq[i])
                    die("reciprocal divmod quotient mismatch");
            }
            for (int32_t i = 0; i < limbs; i++) {
                uint64_t got =
                    i < both_r->size ? both_r->limbs[i] : 0;
                if (got != gr[i])
                    die("reciprocal divmod remainder mismatch");
            }
            bigint_backing_free(both_r);
            bigint_backing_free(both_q);
        }
    }
    free(v);
    free(gr);
    free(gq);
    free(u);
    printf("cached reciprocal div/mod fuzz vs GMP: %d/%d match"
           " (%d-limb divisor)\n",
           cases, cases, limbs);
}

static void gmp_import_value(mpz_t z, WValue v);

static void fuzz_div_single_against_gmp(int cases, int32_t max_limbs) {
    uint64_t state = 0xd1310ba698dfb5acULL;
    mpz_t za, zd, zq, zr;
    mpz_inits(za, zd, zq, zr, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t limbs =
            1 + (int32_t)(bench_rng(&state) % (uint64_t)max_limbs);
        uint64_t *a = bench_limbs(limbs, bench_rng(&state));
        uint64_t d;
        switch (t & 7) {
        case 0: d = 1; break;
        case 1: d = 1ULL << (bench_rng(&state) & 63U); break;
        case 2: d = UINT32_MAX; break;
        case 3: d = UINT32_MAX + 1ULL; break;
        case 4: d = UINT64_MAX; break;
        default:
            d = bench_rng(&state) | 1ULL;
            break;
        }

        uint64_t remainder;
        WBigint *q = mag_div_single(a, limbs, d, &remainder);
        uint64_t mod_only = mag_mod_single(a, limbs, d);
        gmp_import_limbs(za, a, limbs);
        mpz_set_ui(zd, d);
        mpz_tdiv_qr(zq, zr, za, zd);
        WValue qv = bigint_box(q);
        if (!value_matches_mpz(qv, zq) ||
            remainder != (uint64_t)mpz_get_ui(zr) ||
            mod_only != remainder) {
            fprintf(stderr,
                    "single-limb division fuzz mismatch case=%d limbs=%d"
                    " divisor=%llu\n",
                    t, limbs, (unsigned long long)d);
            abort();
        }
        bigint_backing_free(q);
        free(a);
    }

    /* Exercise the boxed 2..4-limb normalized-divisor arm directly.  The
     * raw-kernel loop above cannot cover its allocation, fixed-size quotient
     * construction, sign composition, or result normalization. */
    int boxed_cases = cases < 4096 ? cases : 4096;
    for (int t = 0; t < boxed_cases; t++) {
        int32_t limbs = 2 + (int32_t)(bench_rng(&state) % 3U);
        uint64_t *magnitude = bench_limbs(limbs, bench_rng(&state));
        WBigint *ab = bigint_alloc(limbs);
        memcpy(ab->limbs, magnitude, (size_t)limbs * sizeof(uint64_t));
        ab->size = (t & 1) ? -limbs : limbs;

        uint64_t d = bench_rng(&state) | (1ULL << 63);
        WBigint *db = bigint_alloc(1);
        db->limbs[0] = d;
        db->size = (t & 2) ? -1 : 1;

        WValue a = bigint_box(ab);
        WValue divisor = bigint_box(db);
        WValue q = bigint_div_any(a, divisor);
        gmp_import_value(za, a);
        gmp_import_value(zd, divisor);
        mpz_tdiv_q(zq, za, zd);
        if (!value_matches_mpz(q, zq)) {
            fprintf(stderr,
                    "boxed single-limb division fuzz mismatch case=%d"
                    " limbs=%d divisor=%llu\n",
                    t, limbs, (unsigned long long)d);
            abort();
        }
        bench_free_value(q);
        bench_free_value(divisor);
        bench_free_value(a);
        free(magnitude);
    }
    mpz_clears(za, zd, zq, zr, NULL);
    printf("single-limb division fuzz vs GMP: %d/%d match"
           " (max %d dividend limbs); boxed small path: %d/%d match\n",
           cases, cases, max_limbs, boxed_cases, boxed_cases);
}

static void fuzz_add_sub_against_gmp(int cases, int32_t max_limbs) {
    uint64_t state = 0x2ffd72dbd01adfb7ULL;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    if (max_limbs >= 128) {
        /* Force the add128 chunk correction to wrap.  Chunk zero produces a
         * carry, while chunk one's independently computed first limb is
         * UINT64_MAX; incrementing it must trigger the serial replay. */
        WBigint *add_ab = bigint_alloc(128);
        WBigint *add_bb = bigint_alloc(128);
        add_ab->size = 128;
        add_bb->size = 128;
        add_ab->limbs[0] = UINT64_MAX;
        add_bb->limbs[0] = 1;
        add_ab->limbs[16] = UINT64_MAX;
        add_ab->limbs[127] = 1;
        add_bb->limbs[127] = 1;
        WValue add_a = bigint_box(add_ab);
        WValue add_b = bigint_box(add_bb);
        gmp_import_value(za, add_a);
        gmp_import_value(zb, add_b);
        WValue sum = bigint_add_any(add_a, add_b);
        mpz_add(zg, za, zb);
        if (!value_matches_mpz(sum, zg))
            die("add128 carry-select ripple fallback mismatch");
        bench_free_value(sum);
        bench_free_value(add_a);
        bench_free_value(add_b);

        /* Force the 128-limb carry-select boundary correction to ripple.
         * The independent chunk result starts with zero at limb 16, while
         * the borrow produced by limb 0 must pass through it; the optimized
         * kernel must recognize that shape and replay the serial chain. */
        WBigint *ab = bigint_alloc(128);
        WBigint *bb = bigint_alloc(128);
        ab->size = 128;
        bb->size = 128;
        ab->limbs[127] = 2;
        bb->limbs[127] = 1;
        bb->limbs[0] = 1;
        WValue a = bigint_box(ab);
        WValue b = bigint_box(bb);
        gmp_import_value(za, a);
        gmp_import_value(zb, b);
        WValue difference = bigint_sub_any(a, b);
        mpz_sub(zg, za, zb);
        if (!value_matches_mpz(difference, zg))
            die("sub128 carry-select ripple fallback mismatch");
        bench_free_value(difference);
        bench_free_value(a);
        bench_free_value(b);
    }
    if (max_limbs >= 256) {
        /* Force the shared subtraction kernel's 256-limb ripple fallback. */
        WBigint *ab = bigint_alloc(256);
        WBigint *bb = bigint_alloc(256);
        ab->size = 256;
        bb->size = 256;
        ab->limbs[255] = 2;
        bb->limbs[255] = 1;
        bb->limbs[0] = 1;
        WValue a = bigint_box(ab);
        WValue b = bigint_box(bb);
        gmp_import_value(za, a);
        gmp_import_value(zb, b);
        WValue difference = bigint_sub_any(a, b);
        mpz_sub(zg, za, zb);
        if (!value_matches_mpz(difference, zg))
            die("sub256 carry-select ripple fallback mismatch");
        bench_free_value(difference);
        bench_free_value(a);
        bench_free_value(b);

        /* Carry out of chunk zero must increment an all-ones boundary limb,
         * forcing the existing 256-limb addition kernel's serial replay. */
        ab = bigint_alloc(256);
        bb = bigint_alloc(256);
        ab->size = 256;
        bb->size = 256;
        for (int32_t i = 0; i < 16; i++)
            ab->limbs[i] = UINT64_MAX;
        bb->limbs[0] = 1;
        ab->limbs[16] = UINT64_MAX;
        ab->limbs[255] = 1;
        bb->limbs[255] = 1;
        a = bigint_box(ab);
        b = bigint_box(bb);
        gmp_import_value(za, a);
        gmp_import_value(zb, b);
        WValue sum = bigint_add_any(a, b);
        mpz_add(zg, za, zb);
        if (!value_matches_mpz(sum, zg))
            die("add256 carry-select ripple fallback mismatch");
        bench_free_value(sum);
        bench_free_value(a);
        bench_free_value(b);
    }
    /* Random limbs practically never produce either end condition of the
     * boxed N +/- 1-word path.  Force full carry growth and top-limb shrink
     * across both signs and every small retained-capacity class. */
    int word_cases = 0;
    int32_t word_max = max_limbs < 64 ? max_limbs : 64;
    for (int32_t limbs = 2; limbs <= word_max; limbs++) {
        for (int negative = 0; negative < 2; negative++) {
            WBigint *ab = bigint_alloc(limbs);
            for (int32_t i = 0; i < limbs; i++)
                ab->limbs[i] = UINT64_MAX;
            ab->size = negative ? -limbs : limbs;
            WValue a = bigint_box(ab);
            WValue word = w_box_int(negative ? -1 : 1);
            gmp_import_value(za, a);
            gmp_import_value(zb, word);
            WValue sum = bigint_add_any(a, word);
            mpz_add(zg, za, zb);
            if (!value_matches_mpz(sum, zg))
                dief("boxed add1 full-carry mismatch limbs=%d sign=%d",
                     limbs, negative);
            bench_free_value(sum);
            bench_free_value(a);
            word_cases++;

            ab = bigint_alloc(limbs);
            memset(ab->limbs, 0, (size_t)limbs * sizeof(uint64_t));
            ab->limbs[limbs - 1] = 1;
            ab->size = negative ? -limbs : limbs;
            a = bigint_box(ab);
            gmp_import_value(za, a);
            WValue difference = bigint_sub_any(a, word);
            mpz_sub(zg, za, zb);
            if (!value_matches_mpz(difference, zg))
                dief("boxed sub1 top-shrink mismatch limbs=%d sign=%d",
                     limbs, negative);
            bench_free_value(difference);
            bench_free_value(a);
            word_cases++;
        }
    }
    for (int t = 0; t < cases; t++) {
        int32_t a_limbs =
            1 + (int32_t)(bench_rng(&state) % (uint64_t)max_limbs);
        int32_t b_limbs =
            1 + (int32_t)(bench_rng(&state) % (uint64_t)max_limbs);
        WValue a = bench_bigint(a_limbs, bench_rng(&state));
        WValue b = bench_bigint(b_limbs, bench_rng(&state));
        if (bench_rng(&state) & 1)
            w_as_bigint(a)->size = -w_as_bigint(a)->size;
        if (bench_rng(&state) & 1)
            w_as_bigint(b)->size = -w_as_bigint(b)->size;
        gmp_import_value(za, a);
        gmp_import_value(zb, b);

        WValue sum = bigint_add_any(a, b);
        mpz_add(zg, za, zb);
        if (!value_matches_mpz(sum, zg)) {
            fprintf(stderr, "add fuzz mismatch case=%d a=%d b=%d\n",
                    t, a_limbs, b_limbs);
            abort();
        }
        WValue difference = bigint_sub_any(a, b);
        mpz_sub(zg, za, zb);
        if (!value_matches_mpz(difference, zg)) {
            fprintf(stderr, "sub fuzz mismatch case=%d a=%d b=%d\n",
                    t, a_limbs, b_limbs);
            abort();
        }

        if (sum != a && sum != b) bench_free_value(sum);
        if (difference != a && difference != b)
            bench_free_value(difference);
        bench_free_value(a);
        bench_free_value(b);
    }
    mpz_clears(za, zb, zg, NULL);
    int boundary_cases = max_limbs >= 256 ? 3 : (max_limbs >= 128 ? 1 : 0);
    printf("signed add/sub fuzz vs GMP: %d/%d random match"
           " + %d carry/borrow boundary cases + %d boxed word-edge cases"
           " (max %d limbs)\n",
           cases, cases, boundary_cases, word_cases, max_limbs);
}

static void fuzz_bitwise_shifts_against_gmp(
    int cases, int32_t max_limbs) {
    uint64_t state = 0x9e3779b97f4a7c15ULL;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    static const uint64_t boundary_shifts[] = {
        0, 1, 13, 63, 64, 65, 127, 128, 129
    };
    for (int t = 0; t < cases; t++) {
        int32_t a_limbs =
            1 + (int32_t)(bench_rng(&state) % (uint64_t)max_limbs);
        int32_t b_limbs = (t & 1)
            ? a_limbs
            : 1 + (int32_t)(
                bench_rng(&state) % (uint64_t)max_limbs);
        WValue a = bench_bigint(a_limbs, bench_rng(&state));
        WValue b = bench_bigint(b_limbs, bench_rng(&state));
        /* Force periodic equal magnitudes to exercise complete XOR
         * cancellation and the normalized-zero result path. */
        if ((t & 31) == 0 && a_limbs == b_limbs)
            memcpy(w_as_bigint(b)->limbs, w_as_bigint(a)->limbs,
                   (size_t)a_limbs * sizeof(uint64_t));
        if (bench_rng(&state) & 1)
            w_as_bigint(a)->size = -a_limbs;
        if (bench_rng(&state) & 1)
            w_as_bigint(b)->size = -b_limbs;
        gmp_import_value(za, a);
        gmp_import_value(zb, b);

        const char ops[] = {'&', '|', '^'};
        for (size_t oi = 0; oi < sizeof(ops); oi++) {
            WValue got = bignum_bitwise(ops[oi], a, b);
            if (ops[oi] == '&') mpz_and(zg, za, zb);
            else if (ops[oi] == '|') mpz_ior(zg, za, zb);
            else mpz_xor(zg, za, zb);
            if (!value_matches_mpz(got, zg)) {
                fprintf(stderr,
                        "bitwise fuzz mismatch case=%d op=%c a=%d b=%d\n",
                        t, ops[oi], a_limbs, b_limbs);
                abort();
            }
            bench_free_value(got);
        }

        uint64_t k = t < (int)(
            sizeof(boundary_shifts) / sizeof(boundary_shifts[0]))
            ? boundary_shifts[t]
            : bench_rng(&state) %
                ((uint64_t)max_limbs * 64ULL + 130ULL);
        WValue left = bignum_shl(a, (int64_t)k);
        mpz_mul_2exp(zg, za, (mp_bitcnt_t)k);
        if (!value_matches_mpz(left, zg)) {
            fprintf(stderr,
                    "left-shift fuzz mismatch case=%d limbs=%d shift=%llu\n",
                    t, a_limbs, (unsigned long long)k);
            abort();
        }
        if (left != a && left != b) bench_free_value(left);

        WValue right = bignum_shr(a, (int64_t)k);
        mpz_fdiv_q_2exp(zg, za, (mp_bitcnt_t)k);
        if (!value_matches_mpz(right, zg)) {
            fprintf(stderr,
                    "right-shift fuzz mismatch case=%d limbs=%d shift=%llu\n",
                    t, a_limbs, (unsigned long long)k);
            abort();
        }
        if (right != a && right != b) bench_free_value(right);
        bench_free_value(a);
        bench_free_value(b);
    }
    mpz_clears(za, zb, zg, NULL);
    bigint_pool_release_thread();
    printf("bitwise/shift fuzz vs GMP: %d/%d match"
           " (max %d limbs)\n",
           cases, cases, max_limbs);
}

static void fuzz_boxed_mul_sqr_against_gmp(
    int cases, int32_t max_limbs) {
    uint64_t state = 0x3c6ef372fe94f82bULL;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t a_limbs =
            1 + (int32_t)(bench_rng(&state) % (uint64_t)max_limbs);
        int32_t b_limbs = (t & 1)
            ? a_limbs
            : 1 + (int32_t)(
                bench_rng(&state) % (uint64_t)max_limbs);
        WValue a = bench_bigint(a_limbs, bench_rng(&state));
        WValue b = bench_bigint(b_limbs, bench_rng(&state));
        if (bench_rng(&state) & 1)
            w_as_bigint(a)->size = -a_limbs;
        if (bench_rng(&state) & 1)
            w_as_bigint(b)->size = -b_limbs;
        gmp_import_value(za, a);
        gmp_import_value(zb, b);

        WValue product = bigint_mul_any(a, b);
        mpz_mul(zg, za, zb);
        if (!value_matches_mpz(product, zg)) {
            fprintf(stderr,
                    "boxed multiply fuzz mismatch case=%d a=%d b=%d\n",
                    t, a_limbs, b_limbs);
            abort();
        }
        bench_free_value(product);

        WValue square = bigint_mul_any(a, a);
        mpz_mul(zg, za, za);
        if (!value_matches_mpz(square, zg)) {
            fprintf(stderr,
                    "boxed square fuzz mismatch case=%d limbs=%d\n",
                    t, a_limbs);
            abort();
        }
        bench_free_value(square);
        bench_free_value(a);
        bench_free_value(b);
    }
    mpz_clears(za, zb, zg, NULL);
    bigint_pool_release_thread();
    printf("boxed multiply/square fuzz vs GMP: %d/%d match"
           " (max %d limbs)\n",
           cases, cases, max_limbs);
}

static void fuzz_boxed_mul1_against_gmp(int cases) {
    static const int32_t widths[] = {
        2, 3, 4, 5, 6, 7, 8, 16, 24, 32, 40, 48, 64, 128,
        256, 384, 448, 512, 1024
    };
    uint64_t state = 0xbb67ae8584caa73bULL;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t width = widths[(size_t)t %
            (sizeof widths / sizeof widths[0])];
        WValue big_base = bench_bigint(width, bench_rng(&state));
        WValue word_base = bench_bigint(1, bench_rng(&state));
        WValue big = big_base;
        WValue word = word_base;
        int big_negative = (t & 1) != 0;
        int word_negative = (t & 2) != 0;
        int overlay = (t & 4) != 0;
        if (big_negative) {
            if (overlay) big = w_neg(big_base);
            else w_as_bigint(big)->size = -w_as_bigint(big)->size;
        }
        if (word_negative) {
            if (overlay) word = w_neg(word_base);
            else w_as_bigint(word)->size = -w_as_bigint(word)->size;
        }
        gmp_import_value(za, big);
        gmp_import_value(zb, word);
        mpz_mul(zg, za, zb);

        WValue forward = bigint_mul_any(big, word);
        if (!value_matches_mpz(forward, zg))
            dief("boxed mul1 fuzz mismatch case=%d width=%d order=forward",
                 t, width);
        WValue reverse = bigint_mul_any(word, big);
        if (!value_matches_mpz(reverse, zg))
            dief("boxed mul1 fuzz mismatch case=%d width=%d order=reverse",
                 t, width);
        bench_free_value(forward);
        bench_free_value(reverse);
        if (big != big_base) bench_free_value(big);
        if (word != word_base) bench_free_value(word);
        bench_free_value(big_base);
        bench_free_value(word_base);
    }

    /* Force the exact-128 four-chain correction to wrap at its first
     * 32-limb boundary. */
    WBigint *boundary128 = bigint_alloc(128);
    boundary128->size = 128;
    boundary128->limbs[30] = UINT64_MAX;
    boundary128->limbs[31] = 1;
    boundary128->limbs[32] = 1;
    boundary128->limbs[127] = 1;
    WValue boundary128_value = bigint_box(boundary128);
    gmp_import_value(za, boundary128_value);
    mpz_mul_ui(zg, za, UINT64_MAX);
    WValue boundary128_product =
        bigint_mul_ui_any(boundary128_value, UINT64_MAX);
    if (!value_matches_mpz(boundary128_product, zg))
        die("boxed mul1 128-limb carry-select replay mismatch");
    bench_free_value(boundary128_product);
    bench_free_value(boundary128_value);

    /* Force a carry-select boundary correction to wrap.  With v=2^64-1,
     * limbs 14/15 make chunk zero return the extra carry bit and limb 16's
     * independently computed low word is UINT64_MAX.  Correcting it wraps,
     * so the 128-limb block must replay its seeded serial fallback. */
    WBigint *boundary = bigint_alloc(256);
    boundary->size = 256;
    boundary->limbs[14] = UINT64_MAX;
    boundary->limbs[15] = 1;
    boundary->limbs[16] = 1;
    boundary->limbs[255] = 1;
    WValue boundary_value = bigint_box(boundary);
    gmp_import_value(za, boundary_value);
    mpz_mul_ui(zg, za, UINT64_MAX);
    WValue boundary_product =
        bigint_mul_ui_any(boundary_value, UINT64_MAX);
    if (!value_matches_mpz(boundary_product, zg))
        die("boxed mul1 carry-select replay mismatch");
    bench_free_value(boundary_product);
    bench_free_value(boundary_value);

    /* Repeat the same forced wrap in the 64-limb tail of the dedicated
     * 448-limb shape.  The zero prefix makes the carry entering limb 384
     * exactly zero, isolating the tail replay. */
    WBigint *tail_boundary = bigint_alloc(448);
    tail_boundary->size = 448;
    tail_boundary->limbs[398] = UINT64_MAX;
    tail_boundary->limbs[399] = 1;
    tail_boundary->limbs[400] = 1;
    tail_boundary->limbs[447] = 1;
    WValue tail_value = bigint_box(tail_boundary);
    gmp_import_value(za, tail_value);
    mpz_mul_ui(zg, za, UINT64_MAX);
    WValue tail_product = bigint_mul_ui_any(tail_value, UINT64_MAX);
    if (!value_matches_mpz(tail_product, zg))
        die("boxed mul1 carry-select tail replay mismatch");
    bench_free_value(tail_product);
    bench_free_value(tail_value);

    mpz_clears(za, zb, zg, NULL);
    bigint_pool_release_thread();
    printf("boxed mul1 fuzz vs GMP: %d/%d match"
           " (2..1024 limbs, both orders/sign encodings; replay boundaries)\n",
           cases, cases);
}

static void fuzz_word_ui_against_gmp(int cases, int32_t max_limbs) {
    static const uint64_t boundary_words[] = {
        0, 1, 2, (uint64_t)W_INT48_MAX,
        (uint64_t)W_INT48_MAX + 1U,
        UINT64_C(1) << 63, UINT64_MAX - 1U, UINT64_MAX
    };
    uint64_t state = UINT64_C(0x510e527fade682d1);
    mpz_t za, zw, expected;
    mpz_inits(za, zw, expected, NULL);
    for (int t = 0; t < cases; t++) {
        WValue base;
        if ((t % 19) == 0) {
            static const int64_t inline_values[] = {
                0, 1, -1, W_INT48_MAX, W_INT48_MIN
            };
            base = w_box_int(inline_values[(size_t)t %
                (sizeof inline_values / sizeof inline_values[0])]);
        } else {
            int32_t width = 1 + (int32_t)(
                bench_rng(&state) % (uint64_t)max_limbs);
            base = bench_bigint(width, bench_rng(&state));
        }
        WValue a = base;
        if (w_is_bigint(base) && (t & 1)) {
            if (t & 2) a = w_neg(base);
            else w_as_bigint(a)->size = -w_as_bigint(a)->size;
        }
        uint64_t word = t < (int)(sizeof boundary_words /
                                      sizeof boundary_words[0])
            ? boundary_words[t]
            : bench_rng(&state);
        gmp_import_value(za, a);
        mpz_set_ui(zw, (unsigned long)word);

        WValue got = bigint_add_ui_any(a, word);
        mpz_add(expected, za, zw);
        if (!value_matches_mpz(got, expected))
            dief("word-ui add mismatch case=%d word=%llu", t,
                 (unsigned long long)word);
        bench_free_value(got);

        got = bigint_sub_ui_any(a, word);
        mpz_sub(expected, za, zw);
        if (!value_matches_mpz(got, expected))
            dief("word-ui sub mismatch case=%d word=%llu", t,
                 (unsigned long long)word);
        bench_free_value(got);

        got = bigint_mul_ui_any(a, word);
        mpz_mul(expected, za, zw);
        if (!value_matches_mpz(got, expected))
            dief("word-ui mul mismatch case=%d word=%llu", t,
                 (unsigned long long)word);
        bench_free_value(got);

        uint64_t divisor = word == 0 ? 1 : word;
        mpz_set_ui(zw, (unsigned long)divisor);
        got = bigint_div_ui_any(a, divisor);
        mpz_tdiv_q(expected, za, zw);
        if (!value_matches_mpz(got, expected))
            dief("word-ui div mismatch case=%d word=%llu", t,
                 (unsigned long long)divisor);
        bench_free_value(got);

        if (a != base) bench_free_value(a);
        bench_free_value(base);
    }
    mpz_clears(za, zw, expected, NULL);
    bigint_pool_release_thread();
    printf("unsigned-word add/sub/mul/div fuzz vs GMP: %d/%d match"
           " (max %d limbs, signed/overlay inputs)\n",
           cases, cases, max_limbs);
}

static void gmp_import_value(mpz_t z, WValue v) {
    uint64_t scratch;
    int32_t len;
    const uint64_t *limbs = integer_limbs(v, &scratch, &len);
    int neg = len < 0;
    if (len < 0) len = -len;
    gmp_import_limbs(z, limbs, len);
    if (neg) mpz_neg(z, z);
}

static void fuzz_isqrt_against_gmp(int cases) {
    static const int32_t edges[] = {
        1, 2, 3, 4, 5, 6, 7, 8,
        16, 24, 32, 40, 48, 64, 96, 128, 192, 256,
        383, 384, 385, 511, 512, 513,
        1023, 1024, 1025,
        1534, 1535, 1536, 2047, 2048, 2049,
        3071, 3072, 3073, 4093, 4094, 4095, 4096, 4097,
        8191, 8192, 8193, 16383, 16384, 16385,
        32767, 32768, 32769, 65535, 65536
    };
    uint64_t state = 0xd1b54a32d192ed03ULL;
    mpz_t za, zg;
    mpz_inits(za, zg, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t root_limbs = (t & 1)
            ? edges[(unsigned)t % (sizeof(edges) / sizeof(edges[0]))]
            : 1023 + (int32_t)(gcd_fuzz_next(&state) % (16385 - 1023 + 1));
        WValue a = bench_bigint(
            2 * root_limbs, gcd_fuzz_next(&state));
        WValue got = bigint_isqrt_any(a);
        gmp_import_value(za, a);
        mpz_sqrt(zg, za);
        if (!value_matches_mpz(got, zg))
            dief("isqrt fuzz mismatch case=%d root-width=%d",
                 t, root_limbs);
        if (got != a) bench_free_value(got);
        bench_free_value(a);
    }
    mpz_clears(za, zg, NULL);
    bigint_pool_release_thread();
    printf("isqrt fuzz vs GMP: %d/%d match"
           " (random 1023..16385 limbs plus edges 1..65536)\n",
           cases, cases);
}

static void fuzz_isqrt_small_against_gmp(
    int cases, int32_t max_root_limbs) {
    uint64_t state = UINT64_C(0x94d049bb133111eb);
    mpz_t za, zg;
    mpz_inits(za, zg, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t root_limbs = 1 + (int32_t)(
            gcd_fuzz_next(&state) % (uint64_t)max_root_limbs);
        WValue a = bench_bigint(
            2 * root_limbs, gcd_fuzz_next(&state));
        WValue got = bigint_isqrt_any(a);
        gmp_import_value(za, a);
        mpz_sqrt(zg, za);
        if (!value_matches_mpz(got, zg))
            dief("small isqrt fuzz mismatch case=%d root-width=%d",
                 t, root_limbs);
        if (got != a) bench_free_value(got);
        bench_free_value(a);
    }
    mpz_clears(za, zg, NULL);
    bigint_pool_release_thread();
    printf("small isqrt fuzz vs GMP: %d/%d match"
           " (random 1..%d root limbs)\n",
           cases, cases, max_root_limbs);
}

static void fuzz_gcd_against_gmp(int cases, int32_t max_limbs) {
    static const int32_t edges[] = {
        2, 3, 63, 64, 65, 95, 96, 97, 127, 128, 129,
        255, 256, 257, 511, 512, 513, 1023, 1024, 1025
    };
    uint64_t state = 0x8f3f73b5cf1c9adeULL;
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    for (int t = 0; t < cases; t++) {
        int32_t limbs;
        if ((t & 3) == 0) {
            limbs = edges[(unsigned)t %
                          (sizeof(edges) / sizeof(edges[0]))];
            if (limbs > max_limbs) limbs = max_limbs;
        } else {
            limbs = 2 + (int32_t)(gcd_fuzz_next(&state) %
                                  (uint64_t)(max_limbs - 1));
        }
        WValue a = bench_bigint(limbs, gcd_fuzz_next(&state));
        WValue b;
        switch (t % 5) {
        case 0: /* Near-equal: omitted low limbs are maximally relevant. */
            b = bench_clone_integer(a);
            w_as_bigint(b)->limbs[0] ^=
                1ULL << (unsigned)(gcd_fuzz_next(&state) & 63);
            break;
        case 1: { /* Different widths exercise high-slice rejection/fallback. */
            int32_t short_limbs = limbs -
                (int32_t)(gcd_fuzz_next(&state) %
                          (uint64_t)(limbs / 3 + 1));
            if (short_limbs < 2) short_limbs = 2;
            b = bench_bigint(short_limbs, gcd_fuzz_next(&state));
            break;
        }
        case 2: { /* Known shared factor with unrelated small cofactors. */
            WValue common = bench_bigint(limbs, gcd_fuzz_next(&state));
            bench_free_value(a);
            a = bigint_mul_any(common, w_box_int(65537));
            b = bigint_mul_any(common, w_box_int(65539));
            bench_free_value(common);
            break;
        }
        default:
            b = bench_bigint(limbs, gcd_fuzz_next(&state));
            break;
        }
        if ((t % 5) == 3) {
            /* Exercise a nontrivial shared power of two independently of
             * the usual odd random-input matrix. */
            unsigned shift = 1u + (unsigned)(gcd_fuzz_next(&state) % 63u);
            uint64_t bit = 1ULL << shift;
            uint64_t low_mask = bit - 1;
            w_as_bigint(a)->limbs[0] =
                (w_as_bigint(a)->limbs[0] & ~low_mask) | bit;
            w_as_bigint(b)->limbs[0] =
                (w_as_bigint(b)->limbs[0] & ~low_mask) | bit;
        }
        if ((t % 7) == 3) w_as_bigint(a)->size = -w_as_bigint(a)->size;
        if ((t % 11) == 5) w_as_bigint(b)->size = -w_as_bigint(b)->size;

        WValue got = bigint_gcd_any(a, b);
        gmp_import_value(za, a);
        gmp_import_value(zb, b);
        mpz_gcd(zg, za, zb);
        if (!value_matches_mpz(got, zg)) {
            fprintf(stderr, "gcd fuzz mismatch case=%d limbs=%d\n", t, limbs);
            abort();
        }
        if (got != a && got != b) bench_free_value(got);
        bench_free_value(a);
        bench_free_value(b);
    }
    mpz_clears(za, zb, zg, NULL);
    printf("gcd fuzz vs GMP: %d/%d match (max %d limbs)\n",
           cases, cases, max_limbs);
}

static void check_bitwise_shifts_against_gmp(int32_t limbs) {
    WValue a = bench_bigint(limbs, 0x082efa98ec4e6c89ULL ^ (uint64_t)limbs);
    WValue b = bench_bigint(limbs, 0x452821e638d01377ULL ^ (uint64_t)limbs);
    mpz_t za, zb, zg;
    mpz_inits(za, zb, zg, NULL);
    uint64_t scratch;
    int32_t len;
    const uint64_t *al = integer_limbs(a, &scratch, &len);
    gmp_import_limbs(za, al, len);
    const uint64_t *bl = integer_limbs(b, &scratch, &len);
    gmp_import_limbs(zb, bl, len);

    for (int neg_a = 0; neg_a <= 1; neg_a++) {
        for (int neg_b = 0; neg_b <= 1; neg_b++) {
            w_as_bigint(a)->size = neg_a ? -limbs : limbs;
            w_as_bigint(b)->size = neg_b ? -limbs : limbs;
            if (neg_a) mpz_neg(za, za);
            if (neg_b) mpz_neg(zb, zb);
            const char ops[] = {'&', '|', '^'};
            for (size_t oi = 0; oi < sizeof(ops); oi++) {
                char op = ops[oi];
                WValue tw = bignum_bitwise(op, a, b);
                if (op == '&') mpz_and(zg, za, zb);
                else if (op == '|') mpz_ior(zg, za, zb);
                else mpz_xor(zg, za, zb);
                if (!value_matches_mpz(tw, zg)) die("bitwise mismatch vs GMP");
                bench_free_value(tw);
            }
            if (neg_a) mpz_neg(za, za);
            if (neg_b) mpz_neg(zb, zb);
        }
    }

    static const int64_t shifts[] = {0, 1, 13, 63, 64, 65, 127};
    for (int neg = 0; neg <= 1; neg++) {
        w_as_bigint(a)->size = neg ? -limbs : limbs;
        if (neg) mpz_neg(za, za);
        for (size_t i = 0; i < sizeof(shifts) / sizeof(shifts[0]); i++) {
            int64_t k = shifts[i];
            WValue left = bignum_shl(a, k);
            mpz_mul_2exp(zg, za, (mp_bitcnt_t)k);
            if (!value_matches_mpz(left, zg)) die("left shift mismatch vs GMP");
            if (left != a) bench_free_value(left);

            WValue right = bignum_shr(a, k);
            mpz_fdiv_q_2exp(zg, za, (mp_bitcnt_t)k);
            if (!value_matches_mpz(right, zg)) die("right shift mismatch vs GMP");
            if (right != a) bench_free_value(right);
        }
        if (neg) mpz_neg(za, za);
    }

    w_as_bigint(a)->size = limbs;
    w_as_bigint(b)->size = limbs;
    mpz_clears(za, zb, zg, NULL);
    bench_free_value(a);
    bench_free_value(b);
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
        uint64_t serial32 = bench_mag_mod_single_serial32(a, limbs, divisors[i]);
        if (tw != gm || serial32 != gm) die("single-limb remainder mismatch vs GMP");
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

static void bench_gmp_boxed_apply(
    int op, mpz_t out, const mpz_t a, const mpz_t b) {
    switch (op) {
    case BENCH_BOXED_ADD: mpz_add(out, a, b); break;
    case BENCH_BOXED_SUB: mpz_sub(out, a, b); break;
    case BENCH_BOXED_MUL: mpz_mul(out, a, b); break;
    case BENCH_BOXED_SQR: mpz_mul(out, a, a); break;
    case BENCH_BOXED_DIV: mpz_tdiv_q(out, a, b); break;
    case BENCH_BOXED_MOD: mpz_tdiv_r(out, a, b); break;
    case BENCH_BOXED_AND: mpz_and(out, a, b); break;
    case BENCH_BOXED_OR:  mpz_ior(out, a, b); break;
    case BENCH_BOXED_XOR: mpz_xor(out, a, b); break;
    case BENCH_BOXED_SHL: mpz_mul_2exp(out, a, 13); break;
    case BENCH_BOXED_SHR: mpz_fdiv_q_2exp(out, a, 13); break;
    case BENCH_BOXED_GCD: mpz_gcd(out, a, b); break;
    /* one-limb rows: idiomatic GMP reaches for the _ui entry */
    case BENCH_BOXED_ADD1: mpz_add_ui(out, a, mpz_get_ui(b)); break;
    case BENCH_BOXED_SUB1: mpz_sub_ui(out, a, mpz_get_ui(b)); break;
    case BENCH_BOXED_MUL1: mpz_mul_ui(out, a, mpz_get_ui(b)); break;
    case BENCH_BOXED_DIV1: mpz_tdiv_q_ui(out, a, mpz_get_ui(b)); break;
    default: die("unknown GMP boxed benchmark operation");
    }
}

static void check_boxed_op_against_gmp(int op, int32_t limbs) {
    WValue a, b, m;
    bench_boxed_operands(op, limbs, &a, &b, &m);
    mpz_t za, zb, zm, zg;
    mpz_inits(za, zb, zm, zg, NULL);
    gmp_import_value(za, a);
    gmp_import_value(zb, b);
    if (w_is_bigint(m)) gmp_import_value(zm, m);

    switch (op) {
    case BENCH_BOXED_CMP: {
        int tw = bigint_compare(a, b);
        int gm = mpz_cmp(za, zb);
        if ((tw > 0) != (gm > 0) || (tw < 0) != (gm < 0))
            die("boxed cmp mismatch vs GMP");
        break;
    }
    case BENCH_BOXED_NEG: {
        WValue got = bigint_copy_signed(w_as_bigint(a), 1);
        mpz_neg(zg, za);
        if (!value_matches_mpz(got, zg)) die("boxed neg mismatch vs GMP");
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    case BENCH_BOXED_ABS: {
        WValue got = w_ic_bigint_abs(a, NULL, 0);
        mpz_abs(zg, za);
        if (!value_matches_mpz(got, zg)) die("boxed abs mismatch vs GMP");
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    /* In-place forms mutate the receiver: verify against GMP's in-place
     * result, then restore the operand so the timed run starts clean. */
    case BENCH_BOXED_NEG_BANG: {
        WValue got = bench_bigint_neg_bang_c_ref(a, NULL, 0);
        mpz_neg(zg, za);
        if (got != a) die("neg! must return its receiver");
        if (!value_matches_mpz(got, zg)) die("boxed neg! mismatch vs GMP");
        w_as_bigint(a)->size = -w_as_bigint(a)->size;
        break;
    }
    case BENCH_BOXED_ABS_BANG: {
        WValue got = bench_bigint_abs_bang_c_ref(a, NULL, 0);
        mpz_abs(zg, za);
        if (got != a) die("abs! must return its receiver");
        if (!value_matches_mpz(got, zg)) die("boxed abs! mismatch vs GMP");
        w_as_bigint(a)->size = -w_as_bigint(a)->size;
        break;
    }
    case BENCH_BOXED_POW: {
        WValue got = w_pow(a, w_box_int(BENCH_BOXED_POW_EXP));
        mpz_pow_ui(zg, za, BENCH_BOXED_POW_EXP);
        if (!value_matches_mpz(got, zg)) die("boxed pow mismatch vs GMP");
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    case BENCH_BOXED_POWMOD: {
        WValue got = bigint_powmod_any(a, b, m);
        mpz_powm(zg, za, zb, zm);
        if (!value_matches_mpz(got, zg)) die("boxed powmod mismatch vs GMP");
        WValue naive = bench_tungsten_powmod_once(a, b, m);
        if (!value_matches_mpz(naive, zg))
            die("boxed powmod naive mirror mismatch vs GMP");
        if (naive != a && naive != b && naive != m && naive != got)
            bench_free_value(naive);
        if (got != a && got != b && got != m) bench_free_value(got);
        break;
    }
    case BENCH_BOXED_LCM: {
        WValue got = w_ic_integer_lcm(a, &b, 1);
        mpz_lcm(zg, za, zb);
        if (!value_matches_mpz(got, zg)) die("boxed lcm mismatch vs GMP");
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    case BENCH_BOXED_ISQRT: {
        WValue got = bigint_isqrt_any(a);
        mpz_sqrt(zg, za);
        if (!value_matches_mpz(got, zg)) die("boxed isqrt mismatch vs GMP");
        WValue naive = bench_tungsten_isqrt_once(a);
        if (!value_matches_mpz(naive, zg))
            die("boxed isqrt naive mirror mismatch vs GMP");
        if (naive != a && naive != b && naive != got)
            bench_free_value(naive);
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    case BENCH_BOXED_TOSTR:
    case BENCH_BOXED_FROMSTR: {
        /* One check covers both directions: Tungsten's decimal writer must
         * byte-match GMP's, and parsing that string must return the value. */
        void (*gmp_free_fn)(void *, size_t);
        mp_get_memory_functions(NULL, NULL, &gmp_free_fn);
        WValue text = w_int_to_s(a);
        char *expected = mpz_get_str(NULL, 10, za);
        if (strcmp(as_str(text), expected) != 0)
            die("boxed tostr mismatch vs GMP");
        WValue parsed = w_bigint_from_dec_str(text);
        if (!value_matches_mpz(parsed, za))
            die("boxed fromstr mismatch vs GMP");
        if (parsed != a) bench_free_value(parsed);
        gmp_free_fn(expected, strlen(expected) + 1);
        w_value_free(text);
        break;
    }
    default: {
        WValue got = bench_boxed_op_apply(op, a, b);
        bench_gmp_boxed_apply(op, zg, za, zb);
        if (!value_matches_mpz(got, zg))
            die("boxed operation mismatch vs GMP");
        if (got != a && got != b) bench_free_value(got);
        break;
    }
    }
    mpz_clears(za, zb, zm, zg, NULL);
    bench_free_value(a);
    bench_free_value(b);
    bench_free_value(m);
}

/* Per-op GMP lanes, mirroring DEFINE_BENCH_LANE on the Tungsten side: one
 * noinline aligned(128) function per operation so each op's warm+timed loops
 * sit at a fixed offset from their own aligned entry.  Before this, every
 * GMP loop lived inside one switch function, so any growth elsewhere in the
 * translation unit re-dealt loop alignments and small-op GMP timings swung
 * 10-30% between otherwise-identical builds (the same artifact the Tungsten
 * lanes were insulated from on 2026-08-01). */
typedef struct GmpLaneCtx {
    mpz_ptr r0, r1;   /* alternating retained destinations */
    mpz_ptr a, b, m;
    unsigned long w;  /* hoisted one-limb operand for the _ui rows */
    char *dec;        /* fromstr input; tostr's fixed result block size */
    size_t dec_block;
    void (*free_fn)(void *, size_t);
    int iters;
    int warm_chunk;
} GmpLaneCtx;

#define DEFINE_GMP_LANE(NAME, APPLY)                                       \
static double __attribute__((noinline, aligned(128)))                      \
bench_gmp_lane_##NAME(GmpLaneCtx *cx) {                                    \
    mpz_ptr result[2] = { cx->r0, cx->r1 };                                \
    mpz_ptr a = cx->a, b = cx->b, m = cx->m;                               \
    unsigned long w = cx->w;                                               \
    char *dec = cx->dec;                                                   \
    (void)a; (void)b; (void)m; (void)w; (void)dec;                         \
    int warm_chunk = cx->warm_chunk;                                       \
    int warm_index = 0;                                                    \
    if (warm_chunk > 0) {                                                  \
        double warm_start = bench_now();                                   \
        do {                                                               \
            for (int warm_i = 0; warm_i < warm_chunk;                      \
                 warm_i++, warm_index++) {                                 \
                mpz_ptr r = result[warm_index & 1];                        \
                APPLY;                                                     \
                bench_sink ^= (uint64_t)mpz_get_ui(r);                     \
            }                                                              \
        } while (bench_now() - warm_start < bench_warm_seconds);           \
    }                                                                      \
    int iters = cx->iters;                                                 \
    double timed_start = bench_now();                                      \
    for (int timed_i = 0; timed_i < iters; timed_i++) {                    \
        mpz_ptr r = result[(warm_index + timed_i) & 1];                    \
        APPLY;                                                             \
        bench_sink ^= (uint64_t)mpz_get_ui(r) ^ (uint64_t)timed_i;         \
    }                                                                      \
    return bench_now() - timed_start;                                      \
}

DEFINE_GMP_LANE(add,    mpz_add(r, a, b))
DEFINE_GMP_LANE(sub,    mpz_sub(r, a, b))
DEFINE_GMP_LANE(mul,    mpz_mul(r, a, b))
DEFINE_GMP_LANE(sqr,    mpz_mul(r, a, a))
DEFINE_GMP_LANE(div,    mpz_tdiv_q(r, a, b))
DEFINE_GMP_LANE(mod,    mpz_tdiv_r(r, a, b))
DEFINE_GMP_LANE(band,   mpz_and(r, a, b))
DEFINE_GMP_LANE(bor,    mpz_ior(r, a, b))
DEFINE_GMP_LANE(bxor,   mpz_xor(r, a, b))
DEFINE_GMP_LANE(shl,    mpz_mul_2exp(r, a, 13))
DEFINE_GMP_LANE(shr,    mpz_fdiv_q_2exp(r, a, 13))
DEFINE_GMP_LANE(gcd,    mpz_gcd(r, a, b))
DEFINE_GMP_LANE(add1,   mpz_add_ui(r, a, w))
DEFINE_GMP_LANE(sub1,   mpz_sub_ui(r, a, w))
DEFINE_GMP_LANE(mul1,   mpz_mul_ui(r, a, w))
DEFINE_GMP_LANE(div1,   mpz_tdiv_q_ui(r, a, w))
DEFINE_GMP_LANE(neg,    mpz_neg(r, a))
DEFINE_GMP_LANE(abs,    mpz_abs(r, a))
/* in-place: GMP's own O(1) path (no copy when dest == source) */
DEFINE_GMP_LANE(negbang, mpz_neg(a, a))
DEFINE_GMP_LANE(absbang, mpz_abs(a, a))
DEFINE_GMP_LANE(pow,    mpz_pow_ui(r, a, BENCH_BOXED_POW_EXP))
DEFINE_GMP_LANE(powmod, mpz_powm(r, a, b, m))
DEFINE_GMP_LANE(lcm,    mpz_lcm(r, a, b))
DEFINE_GMP_LANE(isqrt,  mpz_sqrt(r, a))
DEFINE_GMP_LANE(fromstr, mpz_set_str(r, dec, 10))

/* Mirror of bench_lane_cmp's measurement discipline (see its comment):
 * volatile operand slot plus a register sink flushed once after timing,
 * so every cmp lane pays the same per-iteration bookkeeping.  The
 * volatile slot is load-bearing here too: gmp.h declares mpz_cmp
 * __GMP_ATTRIBUTE_PURE, so with plain loop-invariant operands clang
 * hoists the whole call out of the loop (measured 0.07 ns/op). */
static double __attribute__((noinline, aligned(128)))
bench_gmp_lane_cmp(GmpLaneCtx *cx) {
    volatile mpz_ptr cmp_operand = cx->a;
    mpz_ptr b = cx->b;
    uint64_t sink = 0;
    int warm_chunk = cx->warm_chunk;
    if (warm_chunk > 0) {
        double warm_start = bench_now();
        do {
            for (int warm_i = 0; warm_i < warm_chunk; warm_i++)
                sink ^= (uint64_t)(int64_t)mpz_cmp(cmp_operand, b);
        } while (bench_now() - warm_start < bench_warm_seconds);
    }
    int iters = cx->iters;
    double timed_start = bench_now();
    for (int timed_i = 0; timed_i < iters; timed_i++)
        sink ^= (uint64_t)(int64_t)mpz_cmp(cmp_operand, b) ^
                (uint64_t)timed_i;
    double elapsed = bench_now() - timed_start;
    bench_sink ^= sink;
    return elapsed;
}

/* Mirror of the Tungsten lane: convert, observe, free every iteration
 * through GMP's own allocator hooks. */
static double __attribute__((noinline, aligned(128)))
bench_gmp_lane_tostr(GmpLaneCtx *cx) {
    mpz_ptr a = cx->a;
    void (*free_fn)(void *, size_t) = cx->free_fn;
    size_t dec_block = cx->dec_block;
    int warm_chunk = cx->warm_chunk;
    if (warm_chunk > 0) {
        double warm_start = bench_now();
        do {
            for (int warm_i = 0; warm_i < warm_chunk; warm_i++) {
                char *text = mpz_get_str(NULL, 10, a);
                bench_sink ^= (uint64_t)(unsigned char)text[0];
                free_fn(text, dec_block);
            }
        } while (bench_now() - warm_start < bench_warm_seconds);
    }
    int iters = cx->iters;
    double timed_start = bench_now();
    for (int timed_i = 0; timed_i < iters; timed_i++) {
        char *text = mpz_get_str(NULL, 10, a);
        bench_sink ^= (uint64_t)(unsigned char)text[0] ^
                      (uint64_t)timed_i;
        free_fn(text, dec_block);
    }
    return bench_now() - timed_start;
}

/* Same one-previous-result-live contract as the Tungsten churn benchmark.
 * Two alternating mpz destinations let GMP retain its own result capacity
 * without overwriting the immediately previous immutable result.  Split
 * into setup / run / teardown exactly like the Tungsten side so the paired
 * ABBA-quartet sweep can interleave short timed blocks from both lanes. */
typedef struct {
    mpz_t a, b, m, result0, result1;
    char *dec;
    size_t dec_block;
    void (*free_fn)(void *, size_t);
} GmpLaneOwn;

static void bench_gmp_lane_setup(int op, int32_t limbs,
                                 GmpLaneOwn *own, GmpLaneCtx *cx) {
    WValue av, bv, mv;
    bench_boxed_operands(op, limbs, &av, &bv, &mv);
    mpz_inits(own->a, own->b, own->m, own->result0, own->result1, NULL);
    gmp_import_value(own->a, av);
    gmp_import_value(own->b, bv);
    if (w_is_bigint(mv)) gmp_import_value(own->m, mv);
    /* tostr/fromstr: fixed operand means a fixed decimal length, so the
     * result block size is constant; fromstr parses one precomputed string. */
    own->free_fn = NULL;
    own->dec = NULL;
    own->dec_block = 0;
    if (op == BENCH_BOXED_TOSTR || op == BENCH_BOXED_FROMSTR) {
        mp_get_memory_functions(NULL, NULL, &own->free_fn);
        own->dec = mpz_get_str(NULL, 10, own->a);
        own->dec_block = strlen(own->dec) + 1;
    }
    bench_free_value(av);
    bench_free_value(bv);
    bench_free_value(mv);

    cx->r0 = own->result0;
    cx->r1 = own->result1;
    cx->a = own->a;
    cx->b = own->b;
    cx->m = own->m;
    /* one-limb rows: idiomatic GMP uses the _ui entries; hoist the word. */
    cx->w = mpz_get_ui(own->b);
    cx->dec = own->dec;
    cx->dec_block = own->dec_block;
    cx->free_fn = own->free_fn;
    cx->iters = 0;
    cx->warm_chunk = bench_boxed_warm_chunk(op, limbs);
}

/* Returns the elapsed SECONDS of the timed region (cx->iters operations);
 * cx->warm_chunk > 0 pays the per-lane warm-up first, 0 skips it. */
static double bench_gmp_lane_run(int op, GmpLaneCtx *cx) {
    switch (op) {
    case BENCH_BOXED_ADD:      return bench_gmp_lane_add(cx);
    case BENCH_BOXED_SUB:      return bench_gmp_lane_sub(cx);
    case BENCH_BOXED_MUL:      return bench_gmp_lane_mul(cx);
    case BENCH_BOXED_SQR:      return bench_gmp_lane_sqr(cx);
    case BENCH_BOXED_DIV:      return bench_gmp_lane_div(cx);
    case BENCH_BOXED_MOD:      return bench_gmp_lane_mod(cx);
    case BENCH_BOXED_AND:      return bench_gmp_lane_band(cx);
    case BENCH_BOXED_OR:       return bench_gmp_lane_bor(cx);
    case BENCH_BOXED_XOR:      return bench_gmp_lane_bxor(cx);
    case BENCH_BOXED_SHL:      return bench_gmp_lane_shl(cx);
    case BENCH_BOXED_SHR:      return bench_gmp_lane_shr(cx);
    case BENCH_BOXED_GCD:      return bench_gmp_lane_gcd(cx);
    case BENCH_BOXED_ADD1:     return bench_gmp_lane_add1(cx);
    case BENCH_BOXED_SUB1:     return bench_gmp_lane_sub1(cx);
    case BENCH_BOXED_MUL1:     return bench_gmp_lane_mul1(cx);
    case BENCH_BOXED_DIV1:     return bench_gmp_lane_div1(cx);
    case BENCH_BOXED_CMP:      return bench_gmp_lane_cmp(cx);
    case BENCH_BOXED_NEG:      return bench_gmp_lane_neg(cx);
    case BENCH_BOXED_ABS:      return bench_gmp_lane_abs(cx);
    case BENCH_BOXED_NEG_BANG: return bench_gmp_lane_negbang(cx);
    case BENCH_BOXED_ABS_BANG: return bench_gmp_lane_absbang(cx);
    case BENCH_BOXED_POW:      return bench_gmp_lane_pow(cx);
    case BENCH_BOXED_POWMOD:   return bench_gmp_lane_powmod(cx);
    case BENCH_BOXED_LCM:      return bench_gmp_lane_lcm(cx);
    case BENCH_BOXED_ISQRT:    return bench_gmp_lane_isqrt(cx);
    case BENCH_BOXED_FROMSTR:  return bench_gmp_lane_fromstr(cx);
    case BENCH_BOXED_TOSTR:    return bench_gmp_lane_tostr(cx);
    default:
        die("unknown GMP boxed benchmark operation");
    }
    return 0.0;
}

static void bench_gmp_lane_teardown(GmpLaneOwn *own) {
    if (own->dec) own->free_fn(own->dec, own->dec_block);
    mpz_clears(own->a, own->b, own->m, own->result0, own->result1, NULL);
}

/* Ascending-double comparator for the quartet statistics. */
static int bench_double_cmp(const void *pa, const void *pb) {
    double a = *(const double *)pa, b = *(const double *)pb;
    return a < b ? -1 : a > b ? 1 : 0;
}

static double bench_gmp_boxed_result_churn(
    int op, int32_t limbs, int iters) {
    GmpLaneOwn own;
    GmpLaneCtx cx;
    bench_gmp_lane_setup(op, limbs, &own, &cx);
    cx.iters = iters;
    double elapsed = bench_gmp_lane_run(op, &cx);
    bench_gmp_lane_teardown(&own);
    return elapsed * 1e9 / (double)iters;
}

/*
 * Quartet primitives for the paired sweep.  Each timed block rebuilds and
 * tears down its OWN lane context so no block ever runs while the other
 * lane's operands and destinations are resident: leaving both contexts
 * alive moved the cheap-op cells by +-30% purely through allocation
 * layout (the documented 4K page-offset hazard), independent of block
 * length.  Per-block re-setup keeps every timed region under the same
 * heap discipline as the historical sequential screen -- operand
 * construction always follows the other lane's teardown -- and malloc's
 * size-class reuse then hands back the same chunks block after block.
 * Returns elapsed SECONDS for the whole block (iters operations).
 */
static double bench_boxed_churn_block(int op, int32_t limbs, int iters) {
    BenchLaneCtx cx;
    bench_boxed_lane_setup(op, limbs, 1, &cx);
    cx.warm_chunk = 0;                 /* lanes are pre-warmed per rep */
    cx.iters = iters;
    double elapsed = bench_boxed_lane_run(op, &cx);
    bench_boxed_lane_teardown(op, &cx);
    return elapsed;
}

static double bench_gmp_churn_block(int op, int32_t limbs, int iters) {
    GmpLaneOwn own;
    GmpLaneCtx cx;
    bench_gmp_lane_setup(op, limbs, &own, &cx);
    cx.warm_chunk = 0;
    cx.iters = iters;
    double elapsed = bench_gmp_lane_run(op, &cx);
    bench_gmp_lane_teardown(&own);
    return elapsed;
}

/* Untimed per-rep warm-up: the full warm loop of the one-shot churn, no
 * timed iterations, context torn down again so nothing stays resident. */
static void bench_boxed_churn_warm(int op, int32_t limbs) {
    BenchLaneCtx cx;
    bench_boxed_lane_setup(op, limbs, 1, &cx);
    cx.iters = 0;
    (void)bench_boxed_lane_run(op, &cx);
    bench_boxed_lane_teardown(op, &cx);
}

static void bench_gmp_churn_warm(int op, int32_t limbs) {
    GmpLaneOwn own;
    GmpLaneCtx cx;
    bench_gmp_lane_setup(op, limbs, &own, &cx);
    cx.iters = 0;
    (void)bench_gmp_lane_run(op, &cx);
    bench_gmp_lane_teardown(&own);
}

static void check_boxed_mul_rect_against_gmp(int32_t na, int32_t nb) {
    WValue a = bench_bigint(
        na, UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)na);
    WValue b = bench_bigint(
        nb, UINT64_C(0x13198a2e03707344) ^ (uint64_t)nb);
    WValue got = bigint_mul_any(a, b);
    mpz_t za, zb, expected;
    mpz_inits(za, zb, expected, NULL);
    gmp_import_value(za, a);
    gmp_import_value(zb, b);
    mpz_mul(expected, za, zb);
    if (!value_matches_mpz(got, expected))
        die("boxed rectangular multiply mismatch vs GMP");
    if (got != a && got != b) bench_free_value(got);
    bench_free_value(a);
    bench_free_value(b);
    mpz_clears(za, zb, expected, NULL);
}

/* GMP control for the boxed rectangular lane.  As in the documented matrix,
 * two alternating mpz destinations preserve one previous immutable result
 * while retaining result capacity across iterations. */
static double bench_gmp_boxed_mul_rect_churn(
    int32_t na, int32_t nb, int iters) {
    WValue av = bench_bigint(
        na, UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)na);
    WValue bv = bench_bigint(
        nb, UINT64_C(0x13198a2e03707344) ^ (uint64_t)nb);
    mpz_t a, b, result[2];
    mpz_inits(a, b, result[0], result[1], NULL);
    gmp_import_value(a, av);
    gmp_import_value(b, bv);
    bench_free_value(av);
    bench_free_value(bv);

    int32_t max_limbs = na > nb ? na : nb;
    int warm_chunk = bench_boxed_warm_chunk(BENCH_BOXED_MUL, max_limbs);
    int warm_index = 0;
    double warm_start = bench_now();
    do {
        for (int warm_i = 0; warm_i < warm_chunk;
             warm_i++, warm_index++) {
            mpz_ptr r = result[warm_index & 1];
            mpz_mul(r, a, b);
            bench_sink ^= (uint64_t)mpz_get_ui(r);
        }
    } while (bench_now() - warm_start < bench_warm_seconds);

    double timed_start = bench_now();
    for (int timed_i = 0; timed_i < iters; timed_i++) {
        mpz_ptr r = result[(warm_index + timed_i) & 1];
        mpz_mul(r, a, b);
        bench_sink ^= (uint64_t)mpz_get_ui(r) ^ (uint64_t)timed_i;
    }
    double elapsed = bench_now() - timed_start;
    mpz_clears(a, b, result[0], result[1], NULL);
    return elapsed * 1e9 / (double)iters;
}
#endif

/*
 * Capacity-policy experiment for the immutable-result recycler.  It uses the
 * production pool shape (15 logarithmic buckets, two buffers per bucket,
 * smallest sufficient fit) and the same ownership overlap as BigInt
 * operations: allocate the next result while the previous result is still
 * live, then give the previous buffer back.
 *
 * The only variable is the capacity chosen on a miss.  This isolates whether
 * exact one-limb growth, a fixed limb quantum, 1.5x reserve, or powers of two
 * produce the best time/reuse/memory tradeoff for a mixed-size workload.
 */
typedef struct BenchCapacityBuffer {
    uint32_t cap;
    uint64_t limbs[];
} BenchCapacityBuffer;

typedef struct {
    BenchCapacityBuffer *hot;
    BenchCapacityBuffer
        *slot[BN_BIGINT_POOL_BUCKETS][BN_BIGINT_POOL_PER_BUCKET];
    uint8_t count[BN_BIGINT_POOL_BUCKETS];
} BenchCapacityPool;

typedef struct {
    double ns_per_request;
    double hit_percent;
    double average_slack;
    uint64_t allocations;
    uint64_t frees;
    uint64_t peak_limbs;
    uint64_t retained_limbs;
} BenchCapacityStats;

enum {
    BENCH_CAP_EXACT,
    BENCH_CAP_QUANTUM_2,
    BENCH_CAP_QUANTUM_4,
    BENCH_CAP_QUANTUM_8,
    BENCH_CAP_QUANTUM_16,
    BENCH_CAP_QUANTUM_24,
    BENCH_CAP_QUANTUM_32,
    BENCH_CAP_QUANTUM_48,
    BENCH_CAP_QUANTUM_64,
    BENCH_CAP_QUANTUM_96,
    BENCH_CAP_QUANTUM_128,
    BENCH_CAP_GROW_50,
    BENCH_CAP_POWER_2,
    BENCH_CAP_P2_32_Q32,
    BENCH_CAP_P2_64_Q64,
    BENCH_CAP_P2_128_Q32,
    /* Multiple-threshold ladders: a second, coarser quantum above a mid
     * threshold caps the class count in the top decades while the lower
     * rung keeps waste small where sizes are dense. */
    BENCH_CAP_LADDER_A,   /* p2<=32, q32 to 512, q128 above */
    BENCH_CAP_LADDER_B,   /* p2<=32, q32 to 256, q96 above */
    BENCH_CAP_LADDER_C,   /* p2<=32, q16 to 128, q64 to 1024, q128 above */
    BENCH_CAP_POLICY_COUNT
};

static const char *bench_capacity_policy_name(int policy) {
    static const char *const names[BENCH_CAP_POLICY_COUNT] = {
        "exact/+1", "quantum-2", "quantum-4", "quantum-8", "quantum-16",
        "quantum-24", "quantum-32", "quantum-48", "quantum-64",
        "quantum-96", "quantum-128", "reserve-1.5x", "power-of-two",
        "p2<=32+q32", "p2<=64+q64", "p2<=128+q32",
        "lad32/512/128", "lad32/256/96", "lad3step"
    };
    return names[policy];
}

/* Hybrid: powers of two while the absolute waste they cost is small, then a
 * fixed limb quantum.  Power-of-two rounding wastes up to 50% of the
 * allocation — 8 limbs at 16, but 512 limbs (4 KiB) at 1024 — while a fixed
 * quantum caps waste at `quantum` limbs regardless of size.  Below the
 * crossover, powers of two keep the size-class count (and so the pool's
 * per-class reuse) low; above it, the quantum keeps memory bounded. */
static uint32_t bench_capacity_hybrid(
    uint32_t requested, uint32_t p2_limit, uint32_t quantum) {
    if (requested <= p2_limit) {
        uint32_t cap = 1;
        while (cap < requested) cap <<= 1;
        return cap;
    }
    return ((requested + quantum - 1U) / quantum) * quantum;
}

/* Ladder: hybrid with a second, coarser quantum above `mid`. */
static uint32_t bench_capacity_ladder(
    uint32_t requested, uint32_t p2_limit, uint32_t mid,
    uint32_t q_low, uint32_t q_high) {
    if (requested <= mid)
        return bench_capacity_hybrid(requested, p2_limit, q_low);
    return ((requested + q_high - 1U) / q_high) * q_high;
}

static uint32_t bench_capacity_round(
    int policy, uint32_t requested, uint32_t max_cap) {
    uint32_t cap = requested;
    uint32_t quantum = 1;
    switch (policy) {
    case BENCH_CAP_QUANTUM_2: quantum = 2; break;
    case BENCH_CAP_QUANTUM_4: quantum = 4; break;
    case BENCH_CAP_QUANTUM_8: quantum = 8; break;
    case BENCH_CAP_QUANTUM_16: quantum = 16; break;
    case BENCH_CAP_QUANTUM_24: quantum = 24; break;
    case BENCH_CAP_QUANTUM_32: quantum = 32; break;
    case BENCH_CAP_QUANTUM_48: quantum = 48; break;
    case BENCH_CAP_QUANTUM_64: quantum = 64; break;
    case BENCH_CAP_QUANTUM_96: quantum = 96; break;
    case BENCH_CAP_QUANTUM_128: quantum = 128; break;
    case BENCH_CAP_GROW_50:
        cap = requested + (requested + 1U) / 2U;
        break;
    case BENCH_CAP_POWER_2:
        cap = 1;
        while (cap < requested) cap <<= 1;
        break;
    case BENCH_CAP_P2_32_Q32:
        cap = bench_capacity_hybrid(requested, 32U, 32U);
        break;
    case BENCH_CAP_P2_64_Q64:
        cap = bench_capacity_hybrid(requested, 64U, 64U);
        break;
    case BENCH_CAP_P2_128_Q32:
        cap = bench_capacity_hybrid(requested, 128U, 32U);
        break;
    case BENCH_CAP_LADDER_A:
        cap = bench_capacity_ladder(requested, 32U, 512U, 32U, 128U);
        break;
    case BENCH_CAP_LADDER_B:
        cap = bench_capacity_ladder(requested, 32U, 256U, 32U, 96U);
        break;
    case BENCH_CAP_LADDER_C:
        cap = requested <= 128U
                  ? bench_capacity_hybrid(requested, 32U, 16U)
                  : bench_capacity_ladder(requested, 32U, 1024U, 64U, 128U);
        break;
    default:
        break;
    }
    if (quantum > 1)
        cap = ((requested + quantum - 1U) / quantum) * quantum;
    if (cap > max_cap) cap = max_cap;
    if (cap < requested) cap = requested;
    return cap;
}

static BenchCapacityBuffer *bench_capacity_take(
    BenchCapacityPool *pool, uint32_t requested) {
    int first = bigint_pool_bucket(requested);
    BenchCapacityBuffer *best = NULL;
    int best_bucket = -1;
    int best_index = -1;
    int hot_bucket =
        pool->hot && pool->hot->cap >= requested
            ? bigint_pool_bucket(pool->hot->cap)
            : -1;
    for (int bucket = first; bucket < BN_BIGINT_POOL_BUCKETS; bucket++) {
        if (bucket == hot_bucket) {
            best = pool->hot;
            best_bucket = -2;
        }
        int count = pool->count[bucket];
        for (int i = 0; i < count; i++) {
            BenchCapacityBuffer *candidate = pool->slot[bucket][i];
            if (candidate->cap >= requested &&
                (!best || candidate->cap < best->cap)) {
                best = candidate;
                best_bucket = bucket;
                best_index = i;
            }
        }
        if (best) break;
    }
    if (!best) return NULL;
    if (best_bucket == -2) {
        pool->hot = NULL;
        return best;
    }
    int last = --pool->count[best_bucket];
    pool->slot[best_bucket][best_index] = pool->slot[best_bucket][last];
    pool->slot[best_bucket][last] = NULL;
    return best;
}

static void bench_capacity_release(
    BenchCapacityPool *pool, BenchCapacityBuffer *buffer,
    uint64_t *resident_limbs, uint64_t *frees) {
    if (!pool->hot) {
        pool->hot = buffer;
        return;
    }
    int bucket = bigint_pool_bucket(buffer->cap);
    int count = pool->count[bucket];
    if (buffer->cap > BN_BIGINT_POOL_MAX_CAP ||
        count >= BN_BIGINT_POOL_PER_BUCKET) {
        *resident_limbs -= buffer->cap;
        (*frees)++;
        free(buffer);
        return;
    }
    pool->slot[bucket][count] = buffer;
    pool->count[bucket] = (uint8_t)(count + 1);
}

static void bench_capacity_pool_free(BenchCapacityPool *pool) {
    free(pool->hot);
    for (int bucket = 0; bucket < BN_BIGINT_POOL_BUCKETS; bucket++) {
        for (int i = 0; i < pool->count[bucket]; i++)
            free(pool->slot[bucket][i]);
    }
}

static uint32_t *bench_capacity_trace(uint32_t max_limbs, uint32_t requests) {
    uint32_t *trace =
        (uint32_t *)malloc((size_t)requests * sizeof(uint32_t));
    if (!trace) die("out of memory allocating capacity benchmark trace");
    uint64_t state = 0x6a09e667f3bcc909ULL ^ max_limbs ^ requests;
    uint32_t log_max = 0;
    while ((1U << log_max) < max_limbs) log_max++;
    uint32_t small_max = max_limbs < 32 ? max_limbs : 32;
    for (uint32_t i = 0; i < requests; i++) {
        uint64_t random = bench_rng(&state);
        uint32_t step = i >> 3;
        uint32_t requested;
        switch (i & 7U) {
        case 0:
            requested = step % max_limbs + 1U;
            break;
        case 1:
            requested = max_limbs - step % max_limbs;
            break;
        case 2:
            requested = (uint32_t)(random % max_limbs) + 1U;
            break;
        case 3: {
            uint32_t bit = (uint32_t)(random % (log_max + 1U));
            uint32_t low = bit == 0 ? 1U : (1U << (bit - 1U)) + 1U;
            uint32_t high = 1U << bit;
            if (high > max_limbs) high = max_limbs;
            requested = low + (uint32_t)(bench_rng(&state) %
                                         (uint64_t)(high - low + 1U));
            break;
        }
        case 4:
            /* Slowly growing local values exercise incremental +1 demand. */
            requested = (step / 8U) % max_limbs + 1U;
            break;
        case 5: {
            /* Multiplication- and shift-shaped results around twice an input. */
            uint32_t half = max_limbs > 1 ? max_limbs / 2U : 1U;
            uint32_t base = (uint32_t)(random % half) + 1U;
            requested = base * 2U + (uint32_t)(random >> 63);
            if (requested > max_limbs) requested = max_limbs;
            break;
        }
        case 6:
            /* A realistic small-value-heavy lane with occasional large values. */
            requested = (random & 7U)
                ? (uint32_t)(bench_rng(&state) % small_max) + 1U
                : (uint32_t)(bench_rng(&state) % max_limbs) + 1U;
            break;
        default:
            requested = (uint32_t)(bench_rng(&state) % max_limbs) + 1U;
            break;
        }
        trace[i] = requested;
    }
    return trace;
}

/* A live set of exactly one buffer let the single released buffer serve
 * almost every take: hit%% pinned at ~100 for EVERY policy and the grid's
 * recycler stage had no signal. Real programs hold several values live
 * (operands + result + retained references); `live_depth` models that with
 * a ring — depth 1 reproduces the old single-live behavior exactly. */
#define BENCH_CAP_MAX_LIVE 32u

/* p2_override/q_override != 0 bypass the named-policy switch and round
 * through bench_capacity_hybrid directly — the B4 grid's lever. */
static BenchCapacityStats bench_capacity_policy_grid(
    int policy, const uint32_t *trace, uint32_t requests,
    uint32_t max_limbs, uint32_t live_depth,
    uint32_t p2_override, uint32_t q_override);

static BenchCapacityStats bench_capacity_policy(
    int policy, const uint32_t *trace, uint32_t requests,
    uint32_t max_limbs, uint32_t live_depth) {
    return bench_capacity_policy_grid(policy, trace, requests, max_limbs,
                                      live_depth, 0, 0);
}

static BenchCapacityStats bench_capacity_policy_grid(
    int policy, const uint32_t *trace, uint32_t requests,
    uint32_t max_limbs, uint32_t live_depth,
    uint32_t p2_override, uint32_t q_override) {
    BenchCapacityPool pool;
    memset(&pool, 0, sizeof(pool));
    BenchCapacityBuffer *live[BENCH_CAP_MAX_LIVE] = {0};
    if (live_depth == 0) live_depth = 1;
    if (live_depth > BENCH_CAP_MAX_LIVE) live_depth = BENCH_CAP_MAX_LIVE;
    uint64_t hits = 0;
    uint64_t allocations = 0;
    uint64_t frees = 0;
    uint64_t slack = 0;
    uint64_t resident_limbs = 0;
    uint64_t peak_limbs = 0;

    double start = bench_now();
    for (uint32_t i = 0; i < requests; i++) {
        uint32_t requested = trace[i];
        BenchCapacityBuffer *next = bench_capacity_take(&pool, requested);
        if (next) {
            hits++;
        } else {
            uint32_t cap =
                p2_override
                    ? bench_capacity_hybrid(requested, p2_override,
                                            q_override)
                    : bench_capacity_round(policy, requested, max_limbs);
            if (cap > max_limbs) cap = max_limbs;
            if (cap < requested) cap = requested;
            size_t bytes = sizeof(BenchCapacityBuffer) +
                           (size_t)cap * sizeof(uint64_t);
            next = (BenchCapacityBuffer *)malloc(bytes);
            if (!next) die("out of memory in capacity benchmark");
            next->cap = cap;
            allocations++;
            resident_limbs += cap;
            if (resident_limbs > peak_limbs) peak_limbs = resident_limbs;
        }
        slack += (uint64_t)(next->cap - requested);
        next->limbs[0] = (uint64_t)requested ^ i;
        next->limbs[requested - 1U] =
            ((uint64_t)requested << 32) ^ ((uint64_t)i << 1);
        bench_sink ^= next->limbs[0] ^ next->limbs[requested - 1U];
        uint32_t slot = i % live_depth;
        if (live[slot])
            bench_capacity_release(
                &pool, live[slot], &resident_limbs, &frees);
        live[slot] = next;
    }
    for (uint32_t s = 0; s < live_depth; s++)
        if (live[s])
            bench_capacity_release(&pool, live[s], &resident_limbs, &frees);
    double elapsed = bench_now() - start;

    BenchCapacityStats stats;
    stats.ns_per_request = elapsed * 1e9 / (double)requests;
    stats.hit_percent = (double)hits * 100.0 / (double)requests;
    stats.average_slack = (double)slack / (double)requests;
    stats.allocations = allocations;
    stats.frees = frees;
    stats.peak_limbs = peak_limbs;
    stats.retained_limbs = resident_limbs;
    bench_capacity_pool_free(&pool);
    return stats;
}

#ifdef HAVE_GMP
#define BENCH_PRIME_DATASET 256
static void bench_prime_prefilter_values(const char *mode,
                                         uint64_t *values) {
    static const uint64_t factors[] = {3,5,7,11,13,17,19,23,29,31,37};
    int easy = strcmp(mode, "easy") == 0;
    int mixed = strcmp(mode, "mixed") == 0;
    int prime = strcmp(mode, "prime") == 0;
    if (!easy && !mixed && !prime)
        die("prime prefilter mode must be easy, mixed, or prime");

    mpz_t cursor, next;
    mpz_inits(cursor, next, NULL);
    mpz_set_ui(cursor, UINT64_C(0x7ffffffffff00001));
    for (int i = 0; i < BENCH_PRIME_DATASET; i++) {
        int use_easy = easy || (mixed && (i & 1) == 0);
        if (use_easy) {
            uint64_t factor = factors[(unsigned)i %
                (sizeof(factors) / sizeof(factors[0]))];
            uint64_t cofactor =
                UINT64_C(1000000000000037) + (uint64_t)(2 * i);
            values[i] = factor * cofactor;
        } else {
            mpz_nextprime(next, cursor);
            values[i] = (uint64_t)mpz_get_ui(next);
            mpz_add_ui(cursor, next, 2);
        }
    }
    mpz_clears(cursor, next, NULL);

    mpz_t z;
    mpz_init(z);
    for (int i = 0; i < BENCH_PRIME_DATASET; i++) {
        mpz_set_ui(z, values[i]);
        int expected = mpz_probab_prime_p(z, 32) != 0;
        int got = w_prime_test_u64(values[i]);
        if (got != expected)
            die("prime prefilter fixture mismatch vs GMP");
    }
    mpz_clear(z);
}

static double bench_prime_prefilter(const char *mode, int iters) {
    uint64_t values[BENCH_PRIME_DATASET];
    bench_prime_prefilter_values(mode, values);
    double warm_start = bench_now();
    int warm_i = 0;
    do {
        for (int chunk = 0; chunk < 256; chunk++, warm_i++)
            bench_sink ^= (uint64_t)w_prime_test_u64(
                values[(unsigned)warm_i & (BENCH_PRIME_DATASET - 1)]);
    } while (bench_now() - warm_start < bench_warm_seconds);

    double start = bench_now();
    for (int i = 0; i < iters; i++)
        bench_sink ^= (uint64_t)w_prime_test_u64(
                          values[(unsigned)i & (BENCH_PRIME_DATASET - 1)]) ^
                      (uint64_t)i;
    return (bench_now() - start) * 1e9 / (double)iters;
}
#endif

int main(int argc, char **argv) {
#ifdef BN_BZ_PROFILE_COUNTS
    if (argc == 3 && strcmp(argv[1], "--trace-isqrt-bz") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("isqrt B-Z trace expects positive limbs");
        WValue a, b, m;
        bench_boxed_operands(BENCH_BOXED_ISQRT, limbs, &a, &b, &m);
        bz_profile_mul_calls = 0;
        bz_profile_mul_q_limbs = 0;
        bz_profile_mul_b_limbs = 0;
        bz_profile_mul_equal = 0;
        bz_profile_mul_full = 0;
        bz_profile_clamped = 0;
        bz_profile_shape_count = 0;
        memset(bz_profile_mul_bins, 0, sizeof(bz_profile_mul_bins));
        WValue root = bigint_isqrt_any(a);
        printf("isqrt %d: correction mul calls=%llu q-limbs=%llu"
               " b-limbs=%llu equal=%llu full=%llu clamped=%llu bins:",
               limbs,
               (unsigned long long)bz_profile_mul_calls,
               (unsigned long long)bz_profile_mul_q_limbs,
               (unsigned long long)bz_profile_mul_b_limbs,
               (unsigned long long)bz_profile_mul_equal,
               (unsigned long long)bz_profile_mul_full,
               (unsigned long long)bz_profile_clamped);
        for (int i = 0; i < 12; i++) {
            if (bz_profile_mul_bins[i])
                printf(" <=%d:%llu", 1 << i,
                       (unsigned long long)bz_profile_mul_bins[i]);
        }
        printf("\n");
        if (bz_profile_shape_count) {
            printf("correction shapes:");
            for (int i = 0; i < bz_profile_shape_count; i++)
                printf(" k%d=%dx%d", bz_profile_shape_k[i],
                       bz_profile_shape_q[i], bz_profile_shape_b[i]);
            printf("\n");
        }
        bench_free_value(root);
        bench_free_value(a);
        bench_free_value(b);
        bench_free_value(m);
        return 0;
    }
#endif
#if BN_BENCH_RUNTIME_MOD84_CACHE_ENTRIES_KNOB
    const char *mod84_cache_entries = getenv("BENCH_MOD84_CACHE_ENTRIES");
    if (mod84_cache_entries) {
        bn_bench_runtime_mod84_cache_entries = atoi(mod84_cache_entries);
        if (bn_bench_runtime_mod84_cache_entries < 1 ||
            bn_bench_runtime_mod84_cache_entries > 2)
            die("BENCH_MOD84_CACHE_ENTRIES must be 1 or 2");
    }
#endif
#if BN_BENCH_RUNTIME_MOD84_KNOB
    const char *mod84_direct = getenv("BENCH_MOD84_DIRECT");
    bn_bench_runtime_mod84_direct =
        mod84_direct && strcmp(mod84_direct, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_DIV_RECIP_DIFF28_KNOB
    const char *div_recip_diff28 = getenv("BENCH_DIV_RECIP_DIFF28");
    bn_bench_runtime_div_recip_diff28 =
        div_recip_diff28 && strcmp(div_recip_diff28, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_TOOM480_KNOB
    const char *toom480_fixed = getenv("BENCH_TOOM480_FIXED");
    bn_bench_runtime_toom480_fixed =
        toom480_fixed && strcmp(toom480_fixed, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_MUL1_CSEL128X32_KNOB
    const char *mul1_csel128x32 = getenv("BENCH_MUL1_CSEL128X32");
    bn_bench_runtime_mul1_csel128x32 =
        mul1_csel128x32 && strcmp(mul1_csel128x32, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_MUL1_CSEL_KNOB
    const char *mul1_csel128 = getenv("BENCH_MUL1_CSEL128");
    bn_bench_runtime_mul1_csel128 =
        mul1_csel128 && strcmp(mul1_csel128, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_WS_ZERO_KNOB
    const char *force_ws_zero = getenv("BENCH_WS_FORCE_ZERO");
    bn_bench_runtime_ws_force_zero =
        force_ws_zero && strcmp(force_ws_zero, "0") != 0;
#endif
#if BN_BENCH_RUNTIME_SSA_PACK_KNOB
    const char *ssa_pack_zero_only = getenv("BENCH_SSA_PACK_ZERO_ONLY");
    bn_bench_runtime_ssa_pack_zero_only =
        ssa_pack_zero_only && strcmp(ssa_pack_zero_only, "0") != 0;
#endif
#if BENCH_ARITH_WS_RELEASE_KNOB
    const char *release_arith_ws = getenv("BENCH_RELEASE_ARITH_WS");
    bench_release_arith_ws_each_iteration =
        release_arith_ws && strcmp(release_arith_ws, "0") != 0;
#endif
#ifdef HAVE_GMP
    if (argc == 4 && strcmp(argv[1], "--bench-prime-prefilter") == 0) {
        int iters = atoi(argv[3]);
        if (iters <= 0)
            die("prime prefilter benchmark expects positive iterations");
        double ns = bench_prime_prefilter(argv[2], iters);
        printf("prime prefilter %s (%d iters): tungsten %.3f ns\n",
               argv[2], iters, ns);
        return 0;
    }
#endif
    /* Compiled Tungsten initializes its static string slab and freezes it
     * before user code.  This source-including native harness has no emitted
     * startup, so reproduce that lifecycle before correctness checks or
     * timing.  Initializing first matters: lazy w_slab_init resets frozen. */
    if (!g_string_slab.base) w_slab_init();
    /* A compiled program's static literals populate the intern table before
     * it freezes.  Seed a nondecimal entry so short decimal results pay the
     * same frozen-table miss instead of taking the empty-table shortcut. */
    (void)w_string("bignum-bench");
    w_slab_freeze();

    if (argc == 5 && strcmp(argv[1], "--bench-atomic-bigint") == 0) {
        const char *mode = argv[2];
        int threads = atoi(argv[3]);
        int updates = atoi(argv[4]);
        int use_cas = strcmp(mode, "cas") == 0;
        if ((!use_cas && strcmp(mode, "mutex") != 0) ||
            threads < 1 || threads > 16 || updates <= 0)
            die("atomic bigint benchmark expects mutex|cas, 1..16 threads,"
                " and positive updates");
        uint64_t checksum = 0;
        double ns = bench_atomic_bigint_counter(
            threads, updates, use_cas, &checksum);
        printf("atomic\t%s\t%d\t%d\t%.6f\t%llu\n",
               mode, threads, updates, ns,
               (unsigned long long)checksum);
        return 0;
    }

    if (argc == 6 && strcmp(argv[1], "--bench-consumed-op") == 0) {
        const char *operation = argv[2];
        int32_t limbs = (int32_t)atoi(argv[3]);
        int iterations = atoi(argv[4]);
        int consume = strcmp(argv[5], "consume") == 0;
        int known_operation =
            strcmp(operation, "and") == 0 ||
            strcmp(operation, "or") == 0 ||
            strcmp(operation, "xor") == 0 ||
            strcmp(operation, "shift") == 0 ||
            strcmp(operation, "pow3") == 0;
        if (!known_operation || limbs < 2 || limbs > 64 ||
            iterations <= 0 ||
            (!consume && strcmp(argv[5], "immutable") != 0))
            die("consumed operation benchmark expects and|or|xor|shift|pow3,"
                " 2..64 limbs, positive iterations, and immutable|consume");
        uint64_t checksum = 0;
        double ns = bench_consumed_operation(
            operation, limbs, iterations, consume, &checksum);
        printf("consumed\t%s\t%d\t%d\t%s\t%.6f\t%llu\n",
               operation, limbs, iterations, argv[5], ns,
               (unsigned long long)checksum);
        return 0;
    }

    if (argc == 5 && strcmp(argv[1], "--bench-fastpaths") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        int runs = atoi(argv[4]);
        if (limbs <= 0 || iters <= 0 || runs <= 0)
            die("fastpath benchmark expects positive limbs, iterations,"
                " and runs");
        bench_fastpaths(limbs, iters, runs);
        return 0;
    }
    if (argc == 3 &&
        (strcmp(argv[1], "--fuzz-tostr-small") == 0 ||
         strcmp(argv[1], "--fuzz-tostr-one-limb") == 0)) {
        int cases = atoi(argv[2]);
        if (cases <= 0)
            die("small tostr fuzz expects a positive case count");
#ifdef HAVE_GMP
        fuzz_tostr_small_against_gmp(cases);
#else
        die("small tostr fuzz requires GMP");
#endif
        return 0;
    }
    /* B4 grid: sweep hybrid (p2_limit, quantum) pairs over the mixed-size
     * trace at live depths 1/4/8. p2list/qlist are comma-separated. */
    if (argc == 7 && strcmp(argv[1], "--bench-capacity-grid") == 0) {
        uint32_t max_limbs = (uint32_t)strtoul(argv[4], NULL, 10);
        uint32_t requests = (uint32_t)strtoul(argv[5], NULL, 10);
        int runs = atoi(argv[6]);
        if (max_limbs == 0 || max_limbs > BN_BIGINT_POOL_MAX_CAP ||
            requests < 1000 || runs <= 0)
            die("capacity grid expects max limbs 1..16384, >=1000 requests,"
                " positive runs");
        uint32_t *trace = bench_capacity_trace(max_limbs, requests);
        char p2buf[256], qbuf[256];
        snprintf(p2buf, sizeof p2buf, "%s", argv[2]);
        snprintf(qbuf, sizeof qbuf, "%s", argv[3]);
        uint32_t p2s[32], qs[32];
        int np2 = 0, nq = 0;
        for (char *tok = strtok(p2buf, ","); tok && np2 < 32;
             tok = strtok(NULL, ","))
            p2s[np2++] = (uint32_t)strtoul(tok, NULL, 10);
        for (char *tok = strtok(qbuf, ","); tok && nq < 32;
             tok = strtok(NULL, ","))
            qs[nq++] = (uint32_t)strtoul(tok, NULL, 10);
        static const uint32_t depths[] = {1, 4, 8};
        for (int pi = 0; pi < np2; pi++) {
            for (int qi = 0; qi < nq; qi++) {
                for (size_t di = 0; di < 3; di++) {
                    BenchCapacityStats best = {0};
                    best.ns_per_request = 1e300;
                    for (int run = 0; run < runs; run++) {
                        BenchCapacityStats cur = bench_capacity_policy_grid(
                            0, trace, requests, max_limbs, depths[di],
                            p2s[pi], qs[qi]);
                        if (cur.ns_per_request < best.ns_per_request)
                            best = cur;
                    }
                    printf("grid\tp2%u+q%u\t%u\t%u\t%u\t%.3f\t%.3f"
                           "\t%llu\t%.3f\t%.3f\t%.3f\n",
                           p2s[pi], qs[qi], depths[di], max_limbs, requests,
                           best.ns_per_request, best.hit_percent,
                           (unsigned long long)best.allocations,
                           best.average_slack,
                           (double)best.peak_limbs * 8.0 / 1024.0,
                           (double)best.retained_limbs * 8.0 / 1024.0);
                    fflush(stdout);
                }
            }
        }
        free(trace);
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--bench-capacity-policies") == 0) {
        uint32_t max_limbs = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t requests = (uint32_t)strtoul(argv[3], NULL, 10);
        int runs = atoi(argv[4]);
        if (max_limbs == 0 || max_limbs > BN_BIGINT_POOL_MAX_CAP ||
            requests < 1000 || runs <= 0)
            die("capacity benchmark expects max limbs 1..16384,"
                " at least 1000 requests, and positive runs");
        uint32_t *trace = bench_capacity_trace(max_limbs, requests);
        /* Depth 1 is the historical single-live churn; 4 and 8 hold a
         * realistic working set so the pool actually misses and the
         * policies separate. One row per (policy, depth). */
        static const uint32_t live_depths[] = {1, 4, 8};
        for (int policy = 0; policy < BENCH_CAP_POLICY_COUNT; policy++) {
            for (size_t di = 0;
                 di < sizeof(live_depths) / sizeof(live_depths[0]); di++) {
                uint32_t depth = live_depths[di];
                BenchCapacityStats best = {0};
                best.ns_per_request = 1e300;
                for (int run = 0; run < runs; run++) {
                    BenchCapacityStats current = bench_capacity_policy(
                        policy, trace, requests, max_limbs, depth);
                    if (current.ns_per_request < best.ns_per_request)
                        best = current;
                }
                printf("capacity\t%s\t%u\t%u\t%u\t%.3f\t%.3f\t%llu\t%.3f"
                       "\t%.3f\t%.3f\n",
                       bench_capacity_policy_name(policy), depth, max_limbs,
                       requests, best.ns_per_request, best.hit_percent,
                       (unsigned long long)best.allocations,
                       best.average_slack,
                       (double)best.peak_limbs * 8.0 / 1024.0,
                       (double)best.retained_limbs * 8.0 / 1024.0);
            }
        }
        free(trace);
        return 0;
    }
    /* Live-set view of the same trace: what each rounding policy costs when
     * the values are all held simultaneously (an array/matrix of bignums)
     * rather than churned one at a time through the recycler.  This is the
     * scenario where per-allocation rounding waste is fully exposed. */
    if (argc == 4 && strcmp(argv[1], "--bench-capacity-liveset") == 0) {
        uint32_t max_limbs = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t requests = (uint32_t)strtoul(argv[3], NULL, 10);
        if (max_limbs == 0 || max_limbs > BN_BIGINT_POOL_MAX_CAP ||
            requests < 1000)
            die("liveset expects max limbs 1..16384 and >= 1000 requests");
        uint32_t *trace = bench_capacity_trace(max_limbs, requests);
        uint8_t *seen = (uint8_t *)calloc((size_t)max_limbs + 1U, 1);
        if (!seen) die("out of memory in liveset benchmark");
        printf("policy\t\treq_MiB\talloc_MiB\twaste%%\tmax_waste%%\tclasses\n");
        for (int policy = 0; policy < BENCH_CAP_POLICY_COUNT; policy++) {
            memset(seen, 0, (size_t)max_limbs + 1U);
            uint64_t req_total = 0, alloc_total = 0;
            double worst = 0.0;
            uint32_t classes = 0;
            for (uint32_t i = 0; i < requests; i++) {
                uint32_t r = trace[i];
                uint32_t c = bench_capacity_round(policy, r, max_limbs);
                req_total += r;
                alloc_total += c;
                double w = (double)(c - r) * 100.0 / (double)r;
                if (w > worst) worst = w;
                if (c <= max_limbs && !seen[c]) { seen[c] = 1; classes++; }
            }
            double req_mib = (double)req_total * 8.0 / (1024.0 * 1024.0);
            double alloc_mib = (double)alloc_total * 8.0 / (1024.0 * 1024.0);
            printf("%-14s\t%.2f\t%.2f\t%.2f\t%.1f\t%u\n",
                   bench_capacity_policy_name(policy), req_mib, alloc_mib,
                   ((double)alloc_total / (double)req_total - 1.0) * 100.0,
                   worst, classes);
        }
        free(seen);
        free(trace);
        return 0;
    }
    /* REAL live-set probe: allocate `count` bigints through the actual
     * configured allocator (bigint_alloc -> pool/arena/malloc; the policy is
     * fixed at compile time — build one binary per policy via CFLAGS), hold
     * every value live, and report process-level memory.  The simulated
     * liveset above models rounding waste only; this measures the whole
     * stack: policy slack, arena chunk carving, and allocator overhead. */
    if (argc == 4 && strcmp(argv[1], "--bench-capacity-rss") == 0) {
        uint32_t max_limbs = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t count = (uint32_t)strtoul(argv[3], NULL, 10);
        if (max_limbs == 0 || max_limbs > BN_BIGINT_POOL_MAX_CAP ||
            count < 1000)
            die("capacity rss expects max limbs 1..16384 and >= 1000 values");
        uint32_t *trace = bench_capacity_trace(max_limbs, count);
        WValue *live = (WValue *)malloc((size_t)count * sizeof(WValue));
        if (!live) die("out of memory in capacity rss probe");
        uint64_t req_limbs = 0, cap_limbs = 0;
        double start = bench_now();
        for (uint32_t i = 0; i < count; i++) {
            live[i] = bench_bigint((int32_t)trace[i],
                                   0x9E3779B97F4A7C15ULL ^ i);
            req_limbs += trace[i];
        }
        double elapsed = bench_now() - start;
        for (uint32_t i = 0; i < count; i++)
            cap_limbs += (uint64_t)w_as_bigint(live[i])->cap;
        double footprint_mib = 0.0;
#ifdef __APPLE__
        task_vm_info_data_t vm_info;
        mach_msg_type_number_t vm_count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO,
                      (task_info_t)&vm_info, &vm_count) == KERN_SUCCESS)
            footprint_mib =
                (double)vm_info.phys_footprint / (1024.0 * 1024.0);
#endif
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
        double maxrss_mib = (double)usage.ru_maxrss / (1024.0 * 1024.0);
#else
        double maxrss_mib = (double)usage.ru_maxrss / 1024.0;
#endif
        uint64_t arena_reserved = 0, arena_bumped = 0, arena_out = 0;
        w_bigint_arena_stats(&arena_reserved, &arena_bumped, &arena_out);
        /* rss POLICY max count req_MiB cap_MiB maxrss_MiB footprint_MiB
         * arena_reserved_MiB arena_bumped_MiB ns/alloc */
        printf("rss\t%s\t%u\t%u\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.1f\n",
               BENCH_CAP_BUILD_POLICY, max_limbs, count,
               (double)req_limbs * 8.0 / (1024.0 * 1024.0),
               (double)cap_limbs * 8.0 / (1024.0 * 1024.0),
               maxrss_mib, footprint_mib,
               (double)arena_reserved / (1024.0 * 1024.0),
               (double)arena_bumped / (1024.0 * 1024.0),
               elapsed * 1e9 / (double)count);
        for (uint32_t i = 0; i < count; i++) bench_free_value(live[i]);
        free(live);
        free(trace);
        return 0;
    }
    /* E4 stage-1 gate (D5: blocking, no build flag): differential fuzz of
     * the mutating add/sub entries against the immutable engine. Each case
     * builds fresh operands, computes the immutable reference FIRST (from
     * copies, so the mutation cannot contaminate it), then runs the
     * mutating entry on a dedicated dying copy and requires identical
     * results — plus GMP triangulation, self-alias shapes (x+=x, x-=x,
     * x+=0), guard-refusal shapes (shared/overlay receivers must fall back
     * and leave the receiver intact), and carry/borrow edges. */
    if ((argc == 2 || argc == 3) && strcmp(argv[1], "--fuzz-mut") == 0) {
        int32_t max_limbs = argc == 3 ? (int32_t)atoi(argv[2]) : 64;
        if (max_limbs <= 0) die("fuzz-mut expects positive max limbs");
        for (int32_t l = 1; l <= max_limbs; l++) {
            for (int sa = 0; sa < 2; sa++) {
                for (int sb = 0; sb < 2; sb++) {
                    for (int sub = 0; sub < 2; sub++) {
                        WValue a0, b0, m0;
                        bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                        /* one-limb b: the accumulator shape this is for */
                        WValue bw = w_box_int(
                            (int64_t)(w_as_bigint(b0)->limbs[0] >> 17));
                        WValue a_ref = sa ? w_neg(bench_clone_integer(a0))
                                          : bench_clone_integer(a0);
                        WValue b_use = sb ? w_neg(bw) : bw;
                        WValue want = sub ? bigint_sub_any(a_ref, b_use)
                                          : bigint_add_any(a_ref, b_use);
                        /* dying receiver: fresh clone, header-signed */
                        WValue a_mut = bench_clone_integer(a0);
                        if (sa) {
                            WBigint *am = w_as_bigint(a_mut);
                            am->size = -am->size;
                        }
                        WValue got = sub ? w_bigint_sub_mut(a_mut, b_use)
                                         : w_bigint_add_mut(a_mut, b_use);
                        if (bigint_compare(got, want) != 0)
                            dief("fuzz-mut %s mismatch l=%d sa=%d sb=%d",
                                 sub ? "sub" : "add", l, sa, sb);
                        mpz_t za, zb, zg;
                        mpz_inits(za, zb, zg, NULL);
                        gmp_import_value(za, a_ref);
                        gmp_import_value(zb, b_use);
                        if (sub) mpz_sub(zg, za, zb);
                        else mpz_add(zg, za, zb);
                        if (!value_matches_mpz(got, zg))
                            dief("fuzz-mut %s GMP mismatch l=%d sa=%d sb=%d",
                                 sub ? "sub" : "add", l, sa, sb);
                        mpz_clears(za, zb, zg, NULL);
                    }
                }
            }
            /* mul: mutating vs immutable across signs, incl. the carry
             * limb and word-boundary values */
            {
                static const int64_t words[] = {3, -7, 2, 140737488355327LL};
                for (size_t wi = 0; wi < 4; wi++) {
                    WValue a0, b0, m0;
                    bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                    for (int sa = 0; sa < 2; sa++) {
                        WValue a_ref = sa ? w_neg(bench_clone_integer(a0))
                                          : bench_clone_integer(a0);
                        WValue want = bigint_mul_any(a_ref,
                                                     w_box_int(words[wi]));
                        WValue a_mut = bench_clone_integer(a0);
                        if (sa) {
                            WBigint *am = w_as_bigint(a_mut);
                            am->size = -am->size;
                        }
                        WValue got = w_bigint_mul_mut(a_mut,
                                                      w_box_int(words[wi]));
                        if (bigint_compare(got, want) != 0)
                            dief("fuzz-mut mul mismatch l=%d sa=%d w=%lld",
                                 l, sa, (long long)words[wi]);
                    }
                }
                /* identity and annihilator words */
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                WValue x = bench_clone_integer(a0);
                if (w_bigint_mul_mut(x, w_box_int(1)) != x)
                    dief("fuzz-mut mul x*1 not identity l=%d", l);
                WValue z = w_bigint_mul_mut(x, w_box_int(0));
                if (!w_is_int(z) || w_as_int(z) != 0)
                    dief("fuzz-mut mul x*0 nonzero l=%d", l);
                /* shared receivers refuse */
                WValue shared = bench_clone_integer(a0);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_mul_mut(shared, w_box_int(3));
                if (got == shared)
                    dief("fuzz-mut mul mutated a SHARED receiver l=%d", l);
                if (bigint_compare(shared, a0) != 0)
                    dief("fuzz-mut mul shared receiver corrupted l=%d", l);
            }
            /* fused addmul/submul: all sign combinations, including a
             * product larger than the accumulator (result-sign flip), and
             * runtime refusal for a shared receiver. */
            {
                static const int64_t words[] = {1, 3, -7, 140737488355327LL};
                WValue a0, x0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &x0, &m0);
                for (size_t wi = 0;
                     wi < sizeof(words) / sizeof(words[0]); wi++) {
                    WValue word = w_box_int(words[wi]);
                    for (int sa = 0; sa < 2; sa++) {
                        for (int sx = 0; sx < 2; sx++) {
                            for (int sub = 0; sub < 2; sub++) {
                                WValue a_ref = bench_clone_integer(a0);
                                WValue x_ref = bench_clone_integer(x0);
                                if (sa) w_as_bigint(a_ref)->size *= -1;
                                if (sx) w_as_bigint(x_ref)->size *= -1;
                                WValue product = bigint_mul_any(x_ref, word);
                                WValue want = sub
                                    ? bigint_sub_any(a_ref, product)
                                    : bigint_add_any(a_ref, product);
                                WValue a_mut = bench_clone_integer(a0);
                                WValue x_use = bench_clone_integer(x0);
                                if (sa) w_as_bigint(a_mut)->size *= -1;
                                if (sx) w_as_bigint(x_use)->size *= -1;
                                WValue got = sub
                                    ? w_bigint_submul_mut(a_mut, x_use, word)
                                    : w_bigint_addmul_mut(a_mut, x_use, word);
                                if (bigint_compare(got, want) != 0)
                                    dief("fuzz-mut %smul mismatch l=%d sa=%d sx=%d w=%lld",
                                         sub ? "sub" : "add", l, sa, sx,
                                         (long long)words[wi]);
                                mpz_t za, zx, zw, zg;
                                mpz_inits(za, zx, zw, zg, NULL);
                                gmp_import_value(za, a_ref);
                                gmp_import_value(zx, x_ref);
                                mpz_set_si(zw, words[wi]);
                                if (sub) mpz_submul(za, zx, zw);
                                else mpz_addmul(za, zx, zw);
                                gmp_import_value(zg, got);
                                if (mpz_cmp(zg, za) != 0)
                                    dief("fuzz-mut %smul GMP mismatch l=%d sa=%d sx=%d w=%lld",
                                         sub ? "sub" : "add", l, sa, sx,
                                         (long long)words[wi]);
                                mpz_clears(za, zx, zw, zg, NULL);
                            }
                        }
                    }
                }
                WValue shared = bench_clone_integer(a0);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue before = bench_clone_integer(shared);
                WValue got = w_bigint_addmul_mut(
                    shared, x0, w_box_int(3));
                if (got == shared || bigint_compare(shared, before) != 0)
                    dief("fuzz-mut addmul shared receiver corrupted l=%d", l);
            }
            /* div: in-place N/1 across signs and every one-word kernel band,
             * checked against both the immutable entry and GMP. */
            {
                static const uint64_t divisors[] = {
                    1, 2, 3, UINT32_MAX,
                    (uint64_t)UINT32_MAX + 2,
                    UINT64_C(0x8000000000000029), UINT64_MAX
                };
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                for (size_t di = 0;
                     di < sizeof(divisors) / sizeof(divisors[0]); di++) {
                    for (int sa = 0; sa < 2; sa++) {
                        for (int sb = 0; sb < 2; sb++) {
                            WBigint *db = bigint_alloc(1);
                            db->limbs[0] = divisors[di];
                            db->size = sb ? -1 : 1;
                            WValue divisor = bigint_box(db);
                            WValue a_ref = bench_clone_integer(a0);
                            if (sa) w_as_bigint(a_ref)->size *= -1;
                            WValue want = bigint_div_any(a_ref, divisor);
                            WValue a_mut = bench_clone_integer(a0);
                            if (sa) w_as_bigint(a_mut)->size *= -1;
                            WValue got = w_bigint_div_mut(a_mut, divisor);
                            if (bigint_compare(got, want) != 0)
                                dief("fuzz-mut div mismatch l=%d sa=%d sb=%d d=%llu",
                                     l, sa, sb,
                                     (unsigned long long)divisors[di]);
                            mpz_t za, zd, zq;
                            mpz_inits(za, zd, zq, NULL);
                            gmp_import_value(za, a_ref);
                            gmp_import_value(zd, divisor);
                            mpz_tdiv_q(zq, za, zd);
                            if (!value_matches_mpz(got, zq))
                                dief("fuzz-mut div GMP mismatch l=%d sa=%d sb=%d d=%llu",
                                     l, sa, sb,
                                     (unsigned long long)divisors[di]);
                            mpz_clears(za, zd, zq, NULL);
                        }
                    }
                }
                WValue shared = bench_clone_integer(a0);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_div_mut(shared, w_box_int(3));
                if (got == shared || bigint_compare(shared, a0) != 0)
                    dief("fuzz-mut div shared receiver corrupted l=%d", l);
                WValue flipped = w_neg(bench_clone_integer(a0));
                WValue flipped_before = bench_clone_integer(flipped);
                WValue got2 = w_bigint_div_mut(flipped, w_box_int(3));
                if (got2 == flipped ||
                    bigint_compare(flipped, flipped_before) != 0)
                    dief("fuzz-mut div overlay receiver corrupted l=%d", l);
            }
            /* mod: in-place N%1 across signs and the same divisor bands.
             * Remainders that fit inline exercise receiver retirement; large
             * one-limb remainders keep the dying box. */
            {
                static const uint64_t divisors[] = {
                    1, 2, 3, UINT32_MAX,
                    (uint64_t)UINT32_MAX + 2,
                    UINT64_C(0x8000000000000029), UINT64_MAX
                };
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                for (size_t di = 0;
                     di < sizeof(divisors) / sizeof(divisors[0]); di++) {
                    for (int sa = 0; sa < 2; sa++) {
                        for (int sb = 0; sb < 2; sb++) {
                            WBigint *db = bigint_alloc(1);
                            db->limbs[0] = divisors[di];
                            db->size = sb ? -1 : 1;
                            WValue divisor = bigint_box(db);
                            WValue a_ref = bench_clone_integer(a0);
                            if (sa) w_as_bigint(a_ref)->size *= -1;
                            WValue want = bigint_mod_any(a_ref, divisor);
                            WValue a_mut = bench_clone_integer(a0);
                            if (sa) w_as_bigint(a_mut)->size *= -1;
                            WValue got = w_bigint_mod_mut(a_mut, divisor);
                            if (bigint_compare(got, want) != 0)
                                dief("fuzz-mut mod mismatch l=%d sa=%d sb=%d d=%llu",
                                     l, sa, sb,
                                     (unsigned long long)divisors[di]);
                            mpz_t za, zd, zr;
                            mpz_inits(za, zd, zr, NULL);
                            gmp_import_value(za, a_ref);
                            gmp_import_value(zd, divisor);
                            mpz_tdiv_r(zr, za, zd);
                            if (!value_matches_mpz(got, zr))
                                dief("fuzz-mut mod GMP mismatch l=%d sa=%d sb=%d d=%llu",
                                     l, sa, sb,
                                     (unsigned long long)divisors[di]);
                            mpz_clears(za, zd, zr, NULL);
                        }
                    }
                }
                WValue shared = bench_clone_integer(a0);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_mod_mut(shared, w_box_int(3));
                if (got == shared || bigint_compare(shared, a0) != 0)
                    dief("fuzz-mut mod shared receiver corrupted l=%d", l);
                WValue flipped = w_neg(bench_clone_integer(a0));
                WValue flipped_before = bench_clone_integer(flipped);
                WValue got2 = w_bigint_mod_mut(flipped, w_box_int(3));
                if (got2 == flipped ||
                    bigint_compare(flipped, flipped_before) != 0)
                    dief("fuzz-mut mod overlay receiver corrupted l=%d", l);
            }
            /* bitwise: destination reuse across the positive equal-width
             * fast shape, plus GMP triangulation and fail-closed shared /
             * tag-sign receiver guards. */
            {
                static const char ops[] = {'&', '|', '^'};
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                for (size_t oi = 0; oi < sizeof(ops); oi++) {
                    char op = ops[oi];
                    WValue a_ref = bench_clone_integer(a0);
                    WValue b_ref = bench_clone_integer(b0);
                    WValue want = bit_binop(op, a_ref, b_ref);
                    WValue a_mut = bench_clone_integer(a0);
                    WValue b_use = bench_clone_integer(b0);
                    WValue got = op == '&'
                        ? w_bigint_and_mut(a_mut, b_use)
                        : (op == '|' ? w_bigint_or_mut(a_mut, b_use)
                                     : w_bigint_xor_mut(a_mut, b_use));
                    if (bigint_compare(got, want) != 0)
                        dief("fuzz-mut bitwise %c mismatch l=%d", op, l);
                    mpz_t za, zb, zg;
                    mpz_inits(za, zb, zg, NULL);
                    gmp_import_value(za, a_ref);
                    gmp_import_value(zb, b_ref);
                    if (op == '&') mpz_and(zg, za, zb);
                    else if (op == '|') mpz_ior(zg, za, zb);
                    else mpz_xor(zg, za, zb);
                    if (!value_matches_mpz(got, zg))
                        dief("fuzz-mut bitwise %c GMP mismatch l=%d", op, l);
                    mpz_clears(za, zb, zg, NULL);
                }
                WValue shared = bench_clone_integer(a0);
                WValue before = bench_clone_integer(shared);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_or_mut(shared, b0);
                if (got == shared || bigint_compare(shared, before) != 0)
                    dief("fuzz-mut bitwise shared receiver corrupted l=%d", l);
                WValue flipped = w_neg(bench_clone_integer(a0));
                WValue flipped_before = bench_clone_integer(flipped);
                WValue flipped_want = bit_binop('&', flipped_before, b0);
                WValue got2 = w_bigint_and_mut(flipped, b0);
                if (got2 == flipped || bigint_compare(got2, flipped_want) != 0 ||
                    bigint_compare(flipped, flipped_before) != 0)
                    dief("fuzz-mut bitwise overlay receiver corrupted l=%d", l);
            }
            /* shift: cover every in-place sub-limb boundary and allocating
             * wide/negative fallbacks. The n+1-capacity receiver makes the
             * carry-growing left-shift fast shape reachable at every width. */
            {
                static const int64_t shifts[] = {1, 13, 63, 64, 77, -13};
                WValue seed = bench_bigint_with_capacity(
                    l, l + 1, UINT64_C(0x8c3c010cb4754c91) + (uint64_t)l);
                mpz_t zseed, zleft, zright;
                mpz_inits(zseed, zleft, zright, NULL);
                gmp_import_value(zseed, seed);
                for (size_t si = 0;
                     si < sizeof(shifts) / sizeof(shifts[0]); si++) {
                    WValue amount = w_box_int(shifts[si]);
                    WValue left_ref = bench_clone_integer(seed);
                    WValue left_want = w_bit_shl(left_ref, amount);
                    WValue left_mut = bench_bigint_with_capacity(
                        l, l + 1,
                        UINT64_C(0x8c3c010cb4754c91) + (uint64_t)l);
                    WValue left_got = w_bigint_shl_mut(left_mut, amount);
                    if (bigint_compare(left_got, left_want) != 0)
                        dief("fuzz-mut shl mismatch l=%d k=%lld", l,
                             (long long)shifts[si]);

                    WValue right_ref = bench_clone_integer(seed);
                    WValue right_want = w_bit_shr(right_ref, amount);
                    WValue right_mut = bench_bigint_with_capacity(
                        l, l + 1,
                        UINT64_C(0x8c3c010cb4754c91) + (uint64_t)l);
                    WValue right_got = w_bigint_shr_mut(right_mut, amount);
                    if (bigint_compare(right_got, right_want) != 0)
                        dief("fuzz-mut shr mismatch l=%d k=%lld", l,
                             (long long)shifts[si]);
                    if (shifts[si] >= 0) {
                        mpz_mul_2exp(zleft, zseed, (mp_bitcnt_t)shifts[si]);
                        mpz_fdiv_q_2exp(zright, zseed, (mp_bitcnt_t)shifts[si]);
                    } else {
                        mp_bitcnt_t reverse = (mp_bitcnt_t)(-shifts[si]);
                        mpz_fdiv_q_2exp(zleft, zseed, reverse);
                        mpz_mul_2exp(zright, zseed, reverse);
                    }
                    if (!value_matches_mpz(left_got, zleft) ||
                        !value_matches_mpz(right_got, zright))
                        dief("fuzz-mut shift GMP mismatch l=%d k=%lld", l,
                             (long long)shifts[si]);
                }
                mpz_clears(zseed, zleft, zright, NULL);
                WValue shared = bench_clone_integer(seed);
                WValue before = bench_clone_integer(shared);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_shl_mut(shared, w_box_int(13));
                if (got == shared || bigint_compare(shared, before) != 0)
                    dief("fuzz-mut shift shared receiver corrupted l=%d", l);
                WValue flipped = w_neg(bench_clone_integer(seed));
                WValue flipped_before = bench_clone_integer(flipped);
                WValue got2 = w_bigint_shr_mut(flipped, w_box_int(13));
                if (got2 == flipped ||
                    bigint_compare(flipped, flipped_before) != 0)
                    dief("fuzz-mut shift overlay receiver corrupted l=%d", l);
            }
            /* self-alias: x += x doubles; x -= x zeroes; x += 0 identity */
            {
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                WValue x = bench_clone_integer(a0);
                WValue two_x = bigint_add_any(bench_clone_integer(a0),
                                              bench_clone_integer(a0));
                WValue got = w_bigint_add_mut(x, x);
                if (bigint_compare(got, two_x) != 0)
                    dief("fuzz-mut x+=x mismatch l=%d", l);
                WValue y = bench_clone_integer(a0);
                WValue gz = w_bigint_sub_mut(y, y);
                if (!w_is_int(gz) || w_as_int(gz) != 0)
                    dief("fuzz-mut x-=x nonzero l=%d", l);
                WValue z = bench_clone_integer(a0);
                WValue gid = w_bigint_add_mut(z, w_box_int(0));
                if (bigint_compare(gid, a0) != 0)
                    dief("fuzz-mut x+=0 mismatch l=%d", l);
            }
            /* guard refusal: shared and overlay receivers fall back and the
             * receiver's value survives */
            {
                WValue a0, b0, m0;
                bench_boxed_operands(BENCH_BOXED_ADD, l, &a0, &b0, &m0);
                WValue shared = bench_clone_integer(a0);
                w_bigint_mark_shared(w_as_bigint(shared));
                WValue got = w_bigint_add_mut(shared, w_box_int(7));
                if (got == shared)
                    dief("fuzz-mut mutated a SHARED receiver l=%d", l);
                if (bigint_compare(shared, a0) != 0)
                    dief("fuzz-mut shared receiver corrupted l=%d", l);
                WValue flipped = w_neg(bench_clone_integer(a0));
                WValue got2 = w_bigint_add_mut(flipped, w_box_int(7));
                if (got2 == flipped)
                    dief("fuzz-mut mutated an OVERLAY receiver l=%d", l);
            }
            /* carry growth: all-ones magnitude + 1 must grow a limb */
            {
                WBigint *ones = bigint_alloc(l + 1);
                for (int32_t i = 0; i < l; i++) ones->limbs[i] = ~0ULL;
                ones->size = l;
                WValue got = w_bigint_add_mut(bigint_box(ones), w_box_int(1));
                mpz_t zo, zg2;
                mpz_inits(zo, zg2, NULL);
                mpz_set_ui(zo, 1);
                mpz_mul_2exp(zg2, zo, (mp_bitcnt_t)(64 * l));
                if (!value_matches_mpz(got, zg2))
                    dief("fuzz-mut carry growth wrong l=%d", l);
                mpz_clears(zo, zg2, NULL);
            }
        }
        printf("mutate-if-unique differential: CLEAN (1..%d limbs)\n",
               max_limbs);
        return 0;
    }
    if ((argc == 2 || argc == 3) && strcmp(argv[1], "--fuzz-tag-sign") == 0) {
        int32_t max_limbs = argc == 3 ? (int32_t)atoi(argv[2]) : 64;
        if (max_limbs <= 0) die("fuzz-tag-sign expects positive max limbs");
        for (size_t oi = 0;
             oi < sizeof fuzz_tag_sign_ops / sizeof fuzz_tag_sign_ops[0];
             oi++) {
            for (int32_t l = 1; l <= max_limbs; l++)
                fuzz_tag_sign_case(oi, l);
            printf("tag-sign %s 1..%d: OK\n",
                   fuzz_tag_sign_ops[oi].name, max_limbs);
            fflush(stdout);
        }
        printf("tag-sign differential: CLEAN\n");
        return 0;
    }
    if ((argc == 5 || argc == 6) &&
        strcmp(argv[1], "--bench-boxed-compare") == 0) {
        int op = bench_boxed_op_parse(argv[2]);
        int32_t limbs = (int32_t)atoi(argv[3]);
        int iters = atoi(argv[4]);
        int reverse = argc == 6 && strcmp(argv[5], "reverse") == 0;
        if (op < 0)
            die("boxed comparison op must be add/sub/mul/sqr/div/mod/gcd/"
                "and/or/xor/shl/shr/cmp/neg/abs/pow/powmod/lcm/isqrt/"
                "tostr/fromstr");
        if (limbs <= 0 || iters <= 0)
            die("boxed comparison expects positive limbs and iterations");
        if (argc == 6 && !reverse)
            die("boxed comparison optional order must be reverse");
#ifdef HAVE_GMP
        check_boxed_op_against_gmp(op, limbs);
        double tw, gm;
        if (reverse) {
            gm = bench_gmp_boxed_result_churn(op, limbs, iters);
            tw = bench_boxed_result_churn(op, limbs, iters, 1);
        } else {
            tw = bench_boxed_result_churn(op, limbs, iters, 1);
            gm = bench_gmp_boxed_result_churn(op, limbs, iters);
        }
        printf("boxed\t%s\t%d\t%d\t%.3f\t%.3f\n",
               argv[2], limbs, iters, tw, gm);
#else
        die("boxed comparison requires GMP");
#endif
        return 0;
    }
    /*
     * Batched sweep: calibrate and time every size for one operation inside a
     * single process, emitting each row as soon as it is done.  The per-row
     * cost of the old one-process-per-(op,size,rep) shape was dominated by
     * fixed overhead — ~12ms of process spawn plus a fresh warm-up per rep —
     * not by the timed region.  Reps run here, the warm-up is paid once per
     * size, and stdout is flushed per row so a driver can stream results.
     */
    if (argc == 6 &&
        (strcmp(argv[1], "--bench-boxed-sweep") == 0 ||
         strcmp(argv[1], "--bench-tungsten-sweep") == 0)) {
#ifndef HAVE_GMP
        die("boxed sweep requires GMP");
#else
        int tungsten_only = strcmp(argv[1], "--bench-tungsten-sweep") == 0;
        int op = bench_boxed_op_parse(argv[2]);
        if (op < 0) die("unknown boxed sweep operation");
        int runs = atoi(argv[4]);
        double target_ms = atof(argv[5]);
        if (runs <= 0 || target_ms <= 0.0)
            die("boxed sweep expects positive runs and target-ms");
        double target_ns = target_ms * 1e6;
        bench_warm_seconds = 0.0005;   /* pilot + reps keep things warm */
        /* Parse the whole list up front: strtok keeps static state, and the
         * timed lanes below call into code that also tokenizes, which would
         * silently truncate this loop after its first size. */
        char sizes[512];
        snprintf(sizes, sizeof sizes, "%s", argv[3]);
        int32_t size_list[128];
        int size_count = 0;
        for (char *tok = strtok(sizes, ","); tok; tok = strtok(NULL, ",")) {
            if (size_count >= (int)(sizeof size_list / sizeof size_list[0]))
                die("boxed sweep supports at most 128 sizes");
            int32_t v = (int32_t)atoi(tok);
            if (v <= 0) die("boxed sweep sizes must be positive");
            size_list[size_count++] = v;
        }
        for (int si = 0; si < size_count; si++) {
            int32_t limbs = size_list[si];
            check_boxed_op_against_gmp(op, limbs);
            /* Adaptive pilot: start at a single operation and widen only
             * while it is too short to time.  A fixed pilot is a trap at the
             * slow end — 64 iterations of powmod at 128 limbs (~137ms each)
             * costs ~9 seconds before the real measurement even starts. */
            int pilot = 1;
            double pt, pg, fastest;
            for (;;) {
                pt = bench_boxed_result_churn(op, limbs, pilot, 1);
                pg = tungsten_only
                    ? 0.0
                    : bench_gmp_boxed_result_churn(op, limbs, pilot);
                /* Variant A/Bs can intentionally make the Tungsten lanes
                 * differ by orders of magnitude (for example O(1) sign
                 * overlay versus a forced limb copy).  The Tungsten-only
                 * mode calibrates each build from its own measured lane. */
                fastest = tungsten_only ? pt : (pt < pg ? pt : pg);
                if (fastest * pilot >= 20000.0 || pilot >= 4096) break;
                pilot *= 16;                       /* still cheap: <20us so far */
            }
            if (fastest < 0.001) fastest = 0.001;
            /* Floor of 1, not 16: when a single operation already exceeds
             * the target window (powmod at 128 limbs runs ~137ms), forcing
             * 16 of them costs seconds per rep and measures nothing extra —
             * `runs` already provides the repetition. */
            /* A shared iteration count keeps the input/lifecycle contract
             * identical, but derive it from the faster lane so BOTH timed
             * regions reach the requested window. */
            double cell_target_ns = target_ns;
            int cell_runs = runs;
            if (limbs <= 8) {
                /* Sub-nanosecond-margin cells: a 2ms timed region under a
                 * host-load burst flips a 1-3% verdict routinely, and these
                 * cells cost microseconds to rerun.  Floor the window and
                 * rep count so the default screen's tiny-cell verdicts mean
                 * what they say; the suite pays ~10 extra seconds total. */
                if (cell_target_ns < 8e6) cell_target_ns = 8e6;
                if (cell_runs < 5) cell_runs = 5;
            }
            double want = cell_target_ns / fastest;
            int iters = want > 40000000.0 ? 40000000
                      : (want < 1.0 ? 1 : (int)want);
            /*
             * Paired ABBA quartets (the default two-lane verdict).  The old
             * shape timed each lane's whole window back-to-back, so a
             * millisecond-scale host-load burst landed on ONE lane and
             * flipped small-margin verdicts (cells that win 0.87x in
             * accurate mode screened at 1.02-1.05x).  Instead, split each
             * rep's window into short blocks -- 10..24 per lane, >=100us
             * each, block iterations derived from the same pilot -- and
             * interleave them as T,G,G,T / G,T,T,G quartets.  A quartet is
             * ~4 block-lengths wide, so slow drift (thermal, DVFS) cancels
             * to first order inside it, and a burst inflates T and G blocks
             * of the SAME quartet together.  Each quartet yields one ratio
             * (T1+T2)/(G1+G2); the cell verdict is the MEDIAN of the
             * quartet log-ratios, so a burst must corrupt half of all
             * quartets across all reps -- not any single 2ms stretch -- to
             * move the reported ratio.
             *
             * Printed columns in this regime: gm is the median per-op GMP
             * block time (a genuine lane representative); tw is
             * gm * exp(median log-ratio), the quartet-consistent Tungsten
             * representative, so downstream tw/gm IS the robust paired
             * ratio.  gm_iqr is the IQR of the per-op GMP block times;
             * tw_iqr maps the log-ratio IQR onto ns as
             * gm * (exp(q3) - exp(q1)) -- the spread of the quartet-implied
             * Tungsten time.  Row format is unchanged.
             *
             * Every block rebuilds its own lane context (see the quartet
             * primitives): with both contexts resident the cheap-op cells
             * moved +-30% from allocation-layout luck alone.  The block
             * length floor covers that rebuild cost -- >=100us and >=3x
             * the measured per-pair setup cost -- so re-setup stays a few
             * percent of the timed region and wide operands simply get
             * fewer, longer blocks.
             *
             * The sequential min-of-reps path below remains for the
             * tungsten-only sweep (no partner lane) and for cells whose
             * calibrated window holds fewer than 4 operations (the FFT
             * band), which keep their historical median+IQR semantics.
             */
            if (!tungsten_only && iters >= 4) {
                /* Measure one setup+teardown round trip per lane; it also
                 * primes malloc's free lists for the per-block rebuilds. */
                double setup_start = bench_now();
                bench_boxed_churn_block(op, limbs, 1);
                bench_gmp_churn_block(op, limbs, 1);
                double pair_setup_ns =
                    (bench_now() - setup_start) * 1e9 - 2.0 * fastest;
                double block_floor_ns = 3.0 * pair_setup_ns;
                if (block_floor_ns < 1.0e5) block_floor_ns = 1.0e5;
                int blocks = (int)(cell_target_ns / block_floor_ns);
                if (blocks > 24) blocks = 24;
                if (blocks > iters) blocks = iters;
                blocks &= ~1;                      /* two T + two G per quartet */
                if (blocks < 2) blocks = 2;
                int block_iters = iters / blocks;
                if (block_iters < 1) block_iters = 1;
                enum { QUARTET_KEEP = 1024, BLOCK_KEEP = 2048 };
                static double lr[QUARTET_KEEP];    /* quartet log-ratios */
                static double gb[BLOCK_KEEP];      /* GMP per-op block ns */
                int lr_n = 0, gb_n = 0;
                for (int r = 0; r < cell_runs; r++) {
                    /* Warm each lane before its first timed quartet, the
                     * warm order rotating with the rep like the historical
                     * alternate-lane-order loop. */
                    if (r & 1) {
                        bench_gmp_churn_warm(op, limbs);
                        bench_boxed_churn_warm(op, limbs);
                    } else {
                        bench_boxed_churn_warm(op, limbs);
                        bench_gmp_churn_warm(op, limbs);
                    }
                    for (int q = 0; q < blocks / 2; q++) {
                        double t1, g1, g2, t2;
                        if (((q + r) & 1) == 0) {  /* T,G,G,T */
                            t1 = bench_boxed_churn_block(op, limbs, block_iters);
                            g1 = bench_gmp_churn_block(op, limbs, block_iters);
                            g2 = bench_gmp_churn_block(op, limbs, block_iters);
                            t2 = bench_boxed_churn_block(op, limbs, block_iters);
                        } else {                   /* G,T,T,G */
                            g1 = bench_gmp_churn_block(op, limbs, block_iters);
                            t1 = bench_boxed_churn_block(op, limbs, block_iters);
                            t2 = bench_boxed_churn_block(op, limbs, block_iters);
                            g2 = bench_gmp_churn_block(op, limbs, block_iters);
                        }
                        double tsum = t1 + t2, gsum = g1 + g2;
                        if (tsum > 0.0 && gsum > 0.0 && lr_n < QUARTET_KEEP)
                            lr[lr_n++] = log(tsum / gsum);
                        double per_op = 1e9 / (double)block_iters;
                        if (gb_n + 2 <= BLOCK_KEEP) {
                            gb[gb_n++] = g1 * per_op;
                            gb[gb_n++] = g2 * per_op;
                        }
                    }
                }
                if (lr_n == 0 || gb_n == 0)
                    die("boxed sweep produced no quartets");
                qsort(lr, (size_t)lr_n, sizeof lr[0], bench_double_cmp);
                qsort(gb, (size_t)gb_n, sizeof gb[0], bench_double_cmp);
                double ratio_med = exp(lr[lr_n / 2]);
                double ratio_lo = exp(lr[lr_n / 4]);
                double ratio_hi = exp(lr[(3 * lr_n) / 4]);
                double gm_med = gb[gb_n / 2];
                printf("boxed\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\n",
                       argv[2], limbs, blocks * block_iters,
                       gm_med * ratio_med, gm_med,
                       gm_med * (ratio_hi - ratio_lo),
                       gb[(3 * gb_n) / 4] - gb[gb_n / 4]);
                fflush(stdout);                    /* stream to the driver */
                continue;
            }
            double tw_best = 0.0, gm_best = 0.0;
            enum { SWEEP_KEEP = 64 };
            double tw_s[SWEEP_KEEP], gm_s[SWEEP_KEEP];
            int kept = cell_runs < SWEEP_KEEP ? cell_runs : SWEEP_KEEP;
            for (int r = 0; r < cell_runs; r++) {
                double tw, gm;
                if (tungsten_only) {
                    tw = bench_boxed_result_churn(op, limbs, iters, 1);
                    gm = 0.0;
                } else if (r & 1) {                /* alternate lane order */
                    gm = bench_gmp_boxed_result_churn(op, limbs, iters);
                    tw = bench_boxed_result_churn(op, limbs, iters, 1);
                } else {
                    tw = bench_boxed_result_churn(op, limbs, iters, 1);
                    gm = bench_gmp_boxed_result_churn(op, limbs, iters);
                }
                if (r < SWEEP_KEEP) { tw_s[r] = tw; gm_s[r] = gm; }
                if (r == 0 || tw < tw_best) tw_best = tw;
                if (r == 0 || gm < gm_best) gm_best = gm;
            }
            /* Retain interquartile spread at every width so power throttling
             * and host noise are visible even though the practical band
             * keeps its historical min-of-reps representative.  In the FFT
             * band (>8192 limbs), a single op can exceed the timing window;
             * use the median as well so page-fault luck cannot become the
             * reported result. */
            double tw_rep = tw_best, gm_rep = gm_best;
            double tw_iqr = 0.0, gm_iqr = 0.0;
            if (kept >= 3) {
                for (int i = 1; i < kept; i++) {   /* insertion sort, n<=64 */
                    double tv = tw_s[i], gv = gm_s[i];
                    int j = i;
                    while (j > 0 && tw_s[j - 1] > tv) { tw_s[j] = tw_s[j - 1]; j--; }
                    tw_s[j] = tv;
                    j = i;
                    while (j > 0 && gm_s[j - 1] > gv) { gm_s[j] = gm_s[j - 1]; j--; }
                    gm_s[j] = gv;
                }
                tw_iqr = tw_s[(3 * kept) / 4] - tw_s[kept / 4];
                gm_iqr = gm_s[(3 * kept) / 4] - gm_s[kept / 4];
                if (limbs > 8192) {
                    tw_rep = tw_s[kept / 2];
                    gm_rep = gm_s[kept / 2];
                }
            }
            printf("boxed\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\n",
                   argv[2], limbs, iters, tw_rep, gm_rep, tw_iqr, gm_iqr);
            fflush(stdout);                        /* stream to the driver */
        }
        return 0;
#endif
    }
    if (argc == 6 && strcmp(argv[1], "--profile-result-recycle") == 0) {
        /* argv[3] is a comma list of limbs[:iters] entries run in sequence
         * inside ONE process; iters defaults to argv[5].  A predecessor
         * entry recreates allocator-history states (a smaller row poisoning
         * a later row's buffer placements) that per-size processes and the
         * adaptive sweep cannot pin down for counter differencing. */
        int op = bench_boxed_op_parse(argv[2]);
        int recycle = strcmp(argv[4], "pool") == 0;
        int direct = strcmp(argv[4], "direct") == 0;
        int default_iters = atoi(argv[5]);
        if (op < 0 || (!recycle && !direct) || default_iters <= 0)
            die("profile result recycle expects op limbs[:iters][,...] "
                "direct|pool iterations");
        /* Pre-parse the whole list: strtok keeps static state and the timed
         * lanes below call into code that also tokenizes. */
        char list[512];
        snprintf(list, sizeof list, "%s", argv[3]);
        int32_t entry_limbs[64];
        int entry_iters[64];
        int entry_count = 0;
        for (char *tok = strtok(list, ","); tok; tok = strtok(NULL, ",")) {
            if (entry_count >= (int)(sizeof entry_limbs / sizeof entry_limbs[0]))
                die("profile result recycle supports at most 64 entries");
            char *colon = strchr(tok, ':');
            int iters = default_iters;
            if (colon) {
                *colon = '\0';
                iters = atoi(colon + 1);
            }
            int32_t limbs = (int32_t)atoi(tok);
            if (limbs <= 0 || iters <= 0)
                die("profile result recycle expects positive limbs and iterations");
            entry_limbs[entry_count] = limbs;
            entry_iters[entry_count] = iters;
            entry_count++;
        }
        for (int e = 0; e < entry_count; e++) {
            double ns = bench_boxed_result_churn(
                op, entry_limbs[e], entry_iters[e], recycle);
            printf("boxed-result profile %s %d limbs %s: %.1f ns sink=%llu\n",
                   argv[2], entry_limbs[e], argv[4], ns,
                   (unsigned long long)bench_sink);
        }
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--profile-gmp-result") == 0) {
        int op = bench_boxed_op_parse(argv[2]);
        int32_t limbs = (int32_t)atoi(argv[3]);
        int iters = atoi(argv[4]);
        if (op < 0 || limbs <= 0 || iters <= 0)
            die("GMP result profile expects op limbs iterations");
#ifdef HAVE_GMP
        double ns = bench_gmp_boxed_result_churn(op, limbs, iters);
        printf("GMP boxed-result profile %s %d limbs: %.1f ns sink=%llu\n",
               argv[2], limbs, ns, (unsigned long long)bench_sink);
#else
        die("GMP result profile requires GMP");
#endif
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--bench-result-recycle") == 0) {
        int op = bench_boxed_op_parse(argv[2]);
        int32_t limbs = (int32_t)atoi(argv[3]);
        int iters = atoi(argv[4]);
        if (op < 0)
            die("result recycle op must be add/sub/mul/sqr/div/mod/gcd/"
                "and/or/xor/shl/shr/cmp/neg/abs/pow/powmod/lcm/isqrt/"
                "tostr/fromstr");
        if (limbs <= 0 || iters <= 0)
            die("result recycle benchmark expects positive limbs and iterations");
        double direct = bench_boxed_result_churn(op, limbs, iters, 0);
        double recycled = bench_boxed_result_churn(op, limbs, iters, 1);
        printf("boxed-result %s %d limbs (%d iters): malloc/free %.1f ns,"
               " give/take %.1f ns, speedup %.2fx\n",
               argv[2], limbs, iters, direct, recycled,
               recycled > 0.0 ? direct / recycled : 0.0);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-shift-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("shift benchmark expects positive limbs and iterations");
#ifdef HAVE_GMP
        check_bitwise_shifts_against_gmp(limbs);
        double tl = bench_tungsten_shift(1, limbs, iters);
        double gl = bench_gmp_shift(1, limbs, iters);
        double tr = bench_tungsten_shift(0, limbs, iters);
        double gr = bench_gmp_shift(0, limbs, iters);
        printf("shift %d limbs (%d iters): shl tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx; shr tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tl, gl, ratio(tl, gl),
               tr, gr, ratio(tr, gr));
#else
        printf("shift %d limbs (%d iters): shl tungsten %.1f ns;"
               " shr tungsten %.1f ns\n",
               limbs, iters,
               bench_tungsten_shift(1, limbs, iters),
               bench_tungsten_shift(0, limbs, iters));
#endif
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-shift") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("shift profile limbs must be positive");
        int iters = limbs <= 256 ? 30000000 :
                    limbs <= 1024 ? 10000000 : 2000000;
        (void)bench_tungsten_shift(1, limbs, iters);
        printf("shift profile sink=%llu\n",
               (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--bench-mod1-blocks-cached") == 0) {
        const int32_t sizes[] = {8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096};
        printf("cached mod1 blocks (ns/op)\n");
        printf("limbs   block8  block16  block32  block64 block128 block256 block512\n");
        for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
            int32_t limbs = sizes[i];
            int iters = bench_iters_for_mod(limbs) * 10;
            uint64_t *a = bench_limbs(
                limbs, 0x6a09e667f3bcc909ULL ^ (uint64_t)limbs);
            double b8 = bench_tungsten_mod1_block_cached(a, limbs, 8, iters);
            double b16 = bench_tungsten_mod1_block_cached(a, limbs, 16, iters);
            double b32 = bench_tungsten_mod1_block_cached(a, limbs, 32, iters);
            double b64 = bench_tungsten_mod1_block_cached(a, limbs, 64, iters);
            double b128 = bench_tungsten_mod1_block_cached(a, limbs, 128, iters);
            double b256 = bench_tungsten_mod1_block_cached(a, limbs, 256, iters);
            double b512 = bench_tungsten_mod1_block_cached(a, limbs, 512, iters);
            printf("%5d %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f\n",
                   limbs, b8, b16, b32, b64, b128, b256, b512);
            free(a);
        }
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--bench-mod1-blocks") == 0) {
        const int32_t sizes[] = {8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096};
#ifdef HAVE_GMP
        printf("limbs   block8  block16  block32      gmp\n");
#else
        printf("limbs   block8  block16  block32\n");
#endif
        for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
            int32_t limbs = sizes[i];
            int iters = bench_iters_for_mod(limbs) * 10;
            uint64_t *a = bench_limbs(limbs, 0x6a09e667f3bcc909ULL ^ (uint64_t)limbs);
            double b8 = bench_tungsten_mod1_block(a, limbs, 8, iters);
            double b16 = bench_tungsten_mod1_block(a, limbs, 16, iters);
            double b32 = bench_tungsten_mod1_block(a, limbs, 32, iters);
#ifdef HAVE_GMP
            double gm = bench_gmp_mod1(a, limbs, iters);
            printf("%5d %8.1f %8.1f %8.1f %8.1f\n", limbs, b8, b16, b32, gm);
#else
            printf("%5d %8.1f %8.1f %8.1f\n", limbs, b8, b16, b32);
#endif
            free(a);
        }
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--dispatch-cost") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int32_t sw;
        long sL;
        uint64_t sK;
        double ssa = ssa_choose(limbs, limbs, &sw, &sL, &sK);
        printf("dispatch cost %d limbs: ssa=%.1f (w=%d L=%ld K=%llu) ntt=%.1f choices mul=%d sqr=%d\n",
               limbs, ssa, sw, sL, (unsigned long long)sK, ntt_cost_est(limbs),
               bn_top_choice(limbs, limbs, 0), bn_top_choice(limbs, limbs, 1));
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-gcd") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs < 2)
            die("gcd fuzz expects positive cases and max limbs >= 2");
#ifdef HAVE_GMP
        fuzz_gcd_against_gmp(cases, max_limbs);
#else
        die("gcd fuzz requires GMP");
#endif
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--fuzz-isqrt") == 0) {
        int cases = atoi(argv[2]);
        if (cases <= 0) die("isqrt fuzz expects a positive case count");
#ifdef HAVE_GMP
        fuzz_isqrt_against_gmp(cases);
#else
        die("isqrt fuzz requires GMP");
#endif
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-isqrt-small") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_root_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_root_limbs <= 0 || max_root_limbs > 4096)
            die("small isqrt fuzz expects positive cases and"
                " max root limbs in 1..4096");
#ifdef HAVE_GMP
        fuzz_isqrt_small_against_gmp(cases, max_root_limbs);
#else
        die("small isqrt fuzz requires GMP");
#endif
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-sqr") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("square fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        int bad = fuzz_sqr_against_gmp(cases, max_limbs);
        printf("square fuzz vs GMP: %d/%d match (max %d limbs)%s\n",
               cases - bad, cases, max_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("square fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-mul") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("multiply fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        int bad = fuzz_mul_against_gmp(cases, max_limbs);
        printf("multiply fuzz vs GMP: %d/%d match (max %d limbs)%s\n",
               cases - bad, cases, max_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("multiply fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-mul-exact") == 0) {
        int cases = atoi(argv[2]);
        int32_t limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || limbs <= 0)
            die("exact-width multiply fuzz expects positive cases and limbs");
#ifdef HAVE_GMP
        int bad = fuzz_mul_exact_against_gmp(cases, limbs);
        printf("exact-width multiply fuzz vs GMP: %d/%d match (%d limbs)%s\n",
               cases - bad, cases, limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("exact-width multiply fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-mul-rect4") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_short_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_short_limbs < BN_RECT4_PAR_THRESHOLD ||
            max_short_limbs > BN_PAR_TOOM_LIMIT)
            die("exact 4:1 multiply fuzz expects positive cases and a"
                " short-side width within the parallel range");
#ifdef HAVE_GMP
        int bad = fuzz_mul_rect4_against_gmp(cases, max_short_limbs);
        printf("exact 4:1 multiply fuzz vs GMP: %d/%d match"
               " (short side 24 and %d..%d limbs)%s\n",
               cases - bad, cases, BN_RECT4_PAR_THRESHOLD, max_short_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("exact 4:1 multiply fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-pow5") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0 ||
            max_limbs > BN_PAR_TOOM_LIMIT)
            die("power fuzz expects positive cases and a max base width"
                " within the supported parallel range");
#ifdef HAVE_GMP
        int bad = fuzz_pow5_against_gmp(cases, max_limbs);
        printf("x**5 fuzz vs GMP: %d/%d match (max %d base limbs)%s\n",
               cases - bad, cases, max_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("power fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-mulmod-bnm1") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("B^n-1 product fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        int bad = fuzz_mulmod_bnm1_against_gmp(cases, max_limbs);
        printf("mulmod B^n-1 fuzz vs GMP: %d/%d match (max %d limbs)%s\n",
               cases - bad, cases, max_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("B^n-1 product fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-powmod") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("powmod fuzz expects positive cases and max modulus limbs");
#ifdef HAVE_GMP
        int bad = fuzz_powmod_against_gmp(cases, max_limbs);
        printf("powmod fuzz vs GMP: %d/%d match (max %d modulus limbs)%s\n",
               cases - bad, cases, max_limbs,
               bad ? "  *** MISMATCH ***" : "");
        return bad ? 1 : 0;
#else
        die("powmod fuzz requires GMP");
#endif
    }
    if (argc == 5 && strcmp(argv[1], "--stress-powmod") == 0) {
        int threads = atoi(argv[2]);
        int iters = atoi(argv[3]);
        int32_t limbs = (int32_t)atoi(argv[4]);
        if (threads < 2 || threads > 16 || iters <= 0 || limbs <= 0)
            die("powmod stress expects 2..16 threads, positive iterations,"
                " and a positive modulus width");
#ifdef HAVE_GMP
        stress_powmod_against_gmp(threads, iters, limbs);
#else
        die("powmod stress requires GMP");
#endif
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--stress-parallel-mul") == 0) {
        int threads = atoi(argv[2]);
        int iters = atoi(argv[3]);
        int32_t limbs = (int32_t)atoi(argv[4]);
        if (threads < 2 || threads > 16 || iters <= 0 ||
            limbs < BN_TOOM2_PAR_THRESHOLD)
            die("parallel multiply stress expects 2..16 threads,"
                " positive iterations, and a parallel limb width");
#ifdef HAVE_GMP
        stress_parallel_mul_against_gmp(threads, iters, limbs);
#else
        die("parallel multiply stress requires GMP");
#endif
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-div-single") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("single-limb division fuzz expects positive cases"
                " and max limbs");
#ifdef HAVE_GMP
        fuzz_div_single_against_gmp(cases, max_limbs);
        return 0;
#else
        die("single-limb division fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-divmod") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("multi-limb division fuzz expects positive cases"
                " and max limbs");
#ifdef HAVE_GMP
        fuzz_divmod_against_gmp(cases, max_limbs);
        return 0;
#else
        die("multi-limb division fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-div-recip") == 0) {
        int cases = atoi(argv[2]);
        int32_t limbs = (int32_t)atoi(argv[3]);
        int32_t min_limbs =
            BN_DIV_BARRETT_R_MIN < BN_DIV_RECIP_Q_MIN
                ? BN_DIV_BARRETT_R_MIN : BN_DIV_RECIP_Q_MIN;
        if (cases <= 0 || limbs < min_limbs)
            die("reciprocal division fuzz expects positive cases and"
                " a supported divisor width");
#ifdef HAVE_GMP
        fuzz_div_reciprocal_against_gmp(cases, limbs);
#else
        die("reciprocal division fuzz requires GMP");
#endif
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-add-sub") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("add/sub fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        fuzz_add_sub_against_gmp(cases, max_limbs);
        return 0;
#else
        die("add/sub fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-bitwise-shifts") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("bitwise/shift fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        fuzz_bitwise_shifts_against_gmp(cases, max_limbs);
        return 0;
#else
        die("bitwise/shift fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-boxed-mul-sqr") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("boxed multiply/square fuzz expects positive cases"
                " and max limbs");
#ifdef HAVE_GMP
        fuzz_boxed_mul_sqr_against_gmp(cases, max_limbs);
        return 0;
#else
        die("boxed multiply/square fuzz requires GMP");
#endif
    }
    if (argc == 3 && strcmp(argv[1], "--fuzz-boxed-mul1") == 0) {
        int cases = atoi(argv[2]);
        if (cases <= 0)
            die("boxed mul1 fuzz expects positive cases");
#ifdef HAVE_GMP
        fuzz_boxed_mul1_against_gmp(cases);
        return 0;
#else
        die("boxed mul1 fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--fuzz-word-ui") == 0) {
        int cases = atoi(argv[2]);
        int32_t max_limbs = (int32_t)atoi(argv[3]);
        if (cases <= 0 || max_limbs <= 0)
            die("unsigned-word fuzz expects positive cases and max limbs");
#ifdef HAVE_GMP
        fuzz_word_ui_against_gmp(cases, max_limbs);
        return 0;
#else
        die("unsigned-word fuzz requires GMP");
#endif
    }
    if (argc == 4 && strcmp(argv[1], "--bench-linear-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("linear benchmark expects positive limbs and iterations");
        uint64_t *a = bench_limbs(
            limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b =
            (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        if (!b) die("out of memory preparing linear benchmark");
        memcpy(b, a, (size_t)limbs * sizeof(uint64_t));
        b[0] ^= 1ULL;
#ifdef HAVE_GMP
        check_linear_against_gmp(limbs, a, b);
        double ta = bench_tungsten_add(a, b, limbs, iters);
        double ga = bench_gmp_add(a, b, limbs, iters);
        double ts = bench_tungsten_sub(a, b, limbs, iters);
        double gs = bench_gmp_sub(a, b, limbs, iters);
        printf("linear %d limbs (%d iters): add tungsten %.3f ns,"
               " gmp %.3f ns, gap %.3fx; sub tungsten %.3f ns,"
               " gmp %.3f ns, gap %.3fx\n",
               limbs, iters, ta, ga, ratio(ta, ga),
               ts, gs, ratio(ts, gs));
#else
        printf("linear %d limbs (%d iters): add tungsten %.3f ns;"
               " sub tungsten %.3f ns\n",
               limbs, iters,
               bench_tungsten_add(a, b, limbs, iters),
               bench_tungsten_sub(a, b, limbs, iters));
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-gcd-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("gcd benchmark expects positive limbs and iterations");
#ifdef HAVE_GMP
        check_gcd_against_gmp(limbs);
#ifdef BN_GCD_PROFILE_COUNTS
        gcd_profile_sim_calls = 0;
        gcd_profile_sim_steps = 0;
        gcd_profile_fast_q1 = 0;
        gcd_profile_pair_calls = 0;
        gcd_profile_pair_limbs = 0;
#endif
        double tg = bench_tungsten_gcd(limbs, iters);
#ifdef BN_GCD_PROFILE_COUNTS
        uint64_t sim_calls = gcd_profile_sim_calls;
        uint64_t sim_steps = gcd_profile_sim_steps;
        uint64_t fast_q1 = gcd_profile_fast_q1;
        uint64_t pair_calls = gcd_profile_pair_calls;
        uint64_t pair_limbs = gcd_profile_pair_limbs;
#endif
        double gg = bench_gmp_gcd(limbs, iters);
        printf("gcd %d limbs (%d iters): tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tg, gg, ratio(tg, gg));
#ifdef BN_GCD_PROFILE_COUNTS
        printf("  lehmer calls=%llu steps=%llu fast-q1=%llu"
               " pair calls=%llu pair limbs=%llu\n",
               (unsigned long long)sim_calls,
               (unsigned long long)sim_steps,
               (unsigned long long)fast_q1,
               (unsigned long long)pair_calls,
               (unsigned long long)pair_limbs);
#endif
#else
        printf("gcd %d limbs (%d iters): tungsten %.1f ns\n",
               limbs, iters, bench_tungsten_gcd(limbs, iters));
#endif
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-gcd-random-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("random gcd benchmark expects positive limbs and iterations");
#ifdef HAVE_GMP
        check_random_gcd_against_gmp(limbs);
#ifdef BN_GCD_PROFILE_COUNTS
        bench_gcd_profile_reset();
#endif
        double tg = bench_tungsten_gcd_random(limbs, iters);
#ifdef BN_GCD_PROFILE_COUNTS
        uint64_t sim_calls = gcd_profile_sim_calls;
        uint64_t sim_steps = gcd_profile_sim_steps;
        uint64_t fast_q1 = gcd_profile_fast_q1;
        uint64_t pair_calls = gcd_profile_pair_calls;
        uint64_t pair_limbs = gcd_profile_pair_limbs;
        uint64_t matrix_products = gcd_profile_matrix_products;
        uint64_t matrix_work = gcd_profile_matrix_product_work;
        uint64_t matrix_bins[12];
        memcpy(matrix_bins, gcd_profile_matrix_product_bins,
               sizeof(matrix_bins));
#endif
        double gg = bench_gmp_gcd_random(limbs, iters);
        printf("random gcd %d limbs (%d iters): tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tg, gg, ratio(tg, gg));
#ifdef BN_GCD_PROFILE_COUNTS
        printf("  lehmer calls=%llu steps=%llu fast-q1=%llu"
               " pair calls=%llu pair limbs=%llu\n",
               (unsigned long long)sim_calls,
               (unsigned long long)sim_steps,
               (unsigned long long)fast_q1,
               (unsigned long long)pair_calls,
               (unsigned long long)pair_limbs);
        printf("  matrix products=%llu schoolbook-work=%llu bins:",
               (unsigned long long)matrix_products,
               (unsigned long long)matrix_work);
        for (int i = 0; i < 12; i++) {
            if (matrix_bins[i])
                printf(" <=%d:%llu", 1 << i,
                       (unsigned long long)matrix_bins[i]);
        }
        printf("\n");
        bench_gcd_profile_print();
#endif
#else
        printf("random gcd %d limbs (%d iters): tungsten %.1f ns\n",
               limbs, iters, bench_tungsten_gcd_random(limbs, iters));
#endif
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-gcd-random") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("random gcd benchmark limbs must be positive");
        int iters = bench_iters_for_gcd(limbs);
#ifdef HAVE_GMP
        check_random_gcd_against_gmp(limbs);
        double tg = bench_tungsten_gcd_random(limbs, iters);
        double gg = bench_gmp_gcd_random(limbs, iters);
        printf("random gcd %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tg, gg, ratio(tg, gg));
#else
        printf("random gcd %d limbs: tungsten %.1f ns\n",
               limbs, bench_tungsten_gcd_random(limbs, iters));
#endif
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-gcd-random") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile random gcd limbs must be positive");
        int iters = limbs <= 64 ? 5000000 :
                    limbs <= 256 ? 200000 : 1000;
        (void)bench_tungsten_gcd_random(limbs, iters);
        printf("random gcd profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-gcd") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile gcd limbs must be positive");
        int iters = limbs <= 64 ? 5000000 :
                    limbs <= 256 ? 2000000 : 500000;
        (void)bench_tungsten_gcd(limbs, iters);
        printf("gcd profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-divmod") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile divmod limbs must be positive");
        int iters = limbs <= 4 ? 10000000 :
                    limbs <= 16 ? 3000000 :
                    limbs <= 64 ? 500000 :
                    limbs <= 256 ? 50000 : 5000;
        uint64_t *u = bench_limbs(2 * limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs,
                                  0xa4093822299f31d0ULL ^ (uint64_t)limbs);
        (void)bench_tungsten_divmod(u, v, limbs, iters);
        free(u);
        free(v);
        printf("divmod profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-submul1") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("submul1 benchmark limbs must be positive");
        int iters = limbs <= 4 ? 10000000 :
                    limbs <= 16 ? 5000000 :
                    limbs <= 64 ? 1000000 :
                    limbs <= 256 ? 200000 : 50000;
        uint64_t *u = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *r = bench_limbs(limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t v = 0xd6e8feb86659fd93ULL;
        double tw = bench_tungsten_submul1(u, r, limbs, v, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_submul1(u, r, limbs, v, iters);
        printf("submul1 %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tw, gm, ratio(tw, gm));
#else
        printf("submul1 %d limbs: tungsten %.1f ns\n", limbs, tw);
#endif
        free(u);
        free(r);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-divmod-paths") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("divmod path benchmark limbs must be positive");
        int iters = bench_iters_for_divmod(limbs);
        uint64_t *u = bench_limbs(2 * limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs,
                                  0xa4093822299f31d0ULL ^ (uint64_t)limbs);
        double knuth = bench_tungsten_divmod_path(u, v, limbs, iters, 1);
        double bz = bench_tungsten_divmod_path(u, v, limbs, iters, 2);
#ifdef HAVE_GMP
        double gm = bench_gmp_divmod(u, v, limbs, iters);
        printf("divmod paths %d limbs: knuth %.1f ns, bz %.1f ns, gmp %.1f ns"
               " (best/gmp %.2fx)\n",
               limbs, knuth, bz, gm, ratio(knuth < bz ? knuth : bz, gm));
#else
        printf("divmod paths %d limbs: knuth %.1f ns, bz %.1f ns\n",
               limbs, knuth, bz);
#endif
        free(u);
        free(v);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-divmod-kernel") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("divmod kernel benchmark limbs must be positive");
        int iters = bench_iters_for_divmod(limbs);
        uint64_t *u = bench_limbs(2 * limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs,
                                  0xa4093822299f31d0ULL ^ (uint64_t)limbs);
        double tw = bench_tungsten_divmod_into(u, v, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_divmod(u, v, limbs, iters);
        printf("divmod kernel %d limbs: tungsten %.1f ns, gmp %.1f ns,"
               " gap %.2fx\n", limbs, tw, gm, ratio(tw, gm));
#else
        printf("divmod kernel %d limbs: tungsten %.1f ns\n", limbs, tw);
#endif
        free(u);
        free(v);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-divmod") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("divmod benchmark limbs must be positive");
        int iters = bench_iters_for_divmod(limbs);
        uint64_t *u = bench_limbs(2 * limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs,
                                  0xa4093822299f31d0ULL ^ (uint64_t)limbs);
#ifdef HAVE_GMP
        check_divmod_against_gmp(limbs, u, v);
        double tw = bench_tungsten_divmod(u, v, limbs, iters);
        double gm = bench_gmp_divmod(u, v, limbs, iters);
        printf("divmod %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tw, gm, ratio(tw, gm));
#else
        printf("divmod %d limbs: tungsten %.1f ns\n", limbs,
               bench_tungsten_divmod(u, v, limbs, iters));
#endif
        free(u);
        free(v);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-divmod-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("divmod benchmark expects positive limbs and iterations");
        uint64_t *u = bench_limbs(2 * limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs,
                                  0xa4093822299f31d0ULL ^ (uint64_t)limbs);
#ifdef HAVE_GMP
        check_divmod_against_gmp(limbs, u, v);
#ifdef BN_BZ_PROFILE_COUNTS
        bz_profile_mul_calls = 0;
        bz_profile_mul_q_limbs = 0;
        bz_profile_mul_b_limbs = 0;
        bz_profile_mul_equal = 0;
        bz_profile_mul_full = 0;
        bz_profile_clamped = 0;
        bz_profile_shape_count = 0;
        for (int i = 0; i < 12; i++) bz_profile_mul_bins[i] = 0;
#endif
        double tw = bench_tungsten_divmod(u, v, limbs, iters);
#ifdef BN_BZ_PROFILE_COUNTS
        uint64_t bz_mul_calls = bz_profile_mul_calls;
        uint64_t bz_mul_q_limbs = bz_profile_mul_q_limbs;
        uint64_t bz_mul_b_limbs = bz_profile_mul_b_limbs;
        uint64_t bz_mul_equal = bz_profile_mul_equal;
        uint64_t bz_mul_full = bz_profile_mul_full;
        uint64_t bz_clamped = bz_profile_clamped;
        uint64_t bz_mul_bins[12];
        int32_t bz_shape_count = bz_profile_shape_count;
        int32_t bz_shape_k[32], bz_shape_q[32], bz_shape_b[32];
        memcpy(bz_mul_bins, bz_profile_mul_bins, sizeof(bz_mul_bins));
        memcpy(bz_shape_k, bz_profile_shape_k, sizeof(bz_shape_k));
        memcpy(bz_shape_q, bz_profile_shape_q, sizeof(bz_shape_q));
        memcpy(bz_shape_b, bz_profile_shape_b, sizeof(bz_shape_b));
#endif
        double gm = bench_gmp_divmod(u, v, limbs, iters);
        printf("divmod %d limbs (%d iters): tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tw, gm, ratio(tw, gm));
#ifdef BN_BZ_PROFILE_COUNTS
        printf("  correction mul calls=%llu q-limbs=%llu b-limbs=%llu"
               " equal=%llu full=%llu clamped=%llu bins:",
               (unsigned long long)bz_mul_calls,
               (unsigned long long)bz_mul_q_limbs,
               (unsigned long long)bz_mul_b_limbs,
               (unsigned long long)bz_mul_equal,
               (unsigned long long)bz_mul_full,
               (unsigned long long)bz_clamped);
        for (int i = 0; i < 12; i++) {
            if (bz_mul_bins[i])
                printf(" <=%d:%llu", 1 << i,
                       (unsigned long long)bz_mul_bins[i]);
        }
        printf("\n");
        if (bz_shape_count) {
            printf("  correction shapes:");
            for (int i = 0; i < bz_shape_count; i++)
                printf(" k%d=%dx%d",
                       bz_shape_k[i], bz_shape_q[i], bz_shape_b[i]);
            printf("\n");
        }
#endif
#else
        printf("divmod %d limbs (%d iters): tungsten %.1f ns\n",
               limbs, iters, bench_tungsten_divmod(u, v, limbs, iters));
#endif
        free(u);
        free(v);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-mul") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile multiply limbs must be positive");
        int iters = limbs <= 8 ? 200000000 :
                    limbs <= 64 ? 1000000 :
                    limbs <= 256 ? 200000 :
                    limbs <= 1024 ? 20000 :
                    limbs <= 4096 ? 5000 : 1000;
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        (void)bench_tungsten_mul(a, b, limbs, iters);
        free(a);
        free(b);
        printf("multiply profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-mul1-offsets") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || limbs > 128 || iters <= 0)
            die("mul_1 offset benchmark expects 1..128 limbs and positive iterations");
        enum { OFFSET_ARENA = 65536, SOURCE_BASE = 4096 + 1024,
               RESULT_BASE = 32768 + 1024 };
        void *arena_raw = NULL;
        if (posix_memalign(&arena_raw, 4096, OFFSET_ARENA) != 0)
            die("out of memory in mul_1 offset benchmark");
        uint8_t *arena = (uint8_t *)arena_raw;
        uint64_t *up = (uint64_t *)(arena + SOURCE_BASE);
        uint64_t state = 0x13198a2e03707344ULL ^ (uint64_t)limbs;
        for (int32_t i = 0; i < limbs; i++) up[i] = bench_rng(&state);
        up[0] |= 1ULL;
        up[limbs - 1] |= 1ULL << 63;
        uint64_t v = 0x9e3779b97f4a7c15ULL;
        for (int offset = 0; offset < 4096; offset += 64) {
            uint64_t *rp = (uint64_t *)(arena + RESULT_BASE + offset);
            uint64_t sink = 0;
            for (int i = 0; i < 10000; i++) sink ^= bn_mul_1(rp, up, limbs, v);
            double best = 0.0;
            for (int rep = 0; rep < 7; rep++) {
                double start = bench_now();
                for (int i = 0; i < iters; i++)
                    sink ^= bn_mul_1(rp, up, limbs, v) + (uint64_t)i;
                double ns = (bench_now() - start) * 1e9 / (double)iters;
                if (rep == 0 || ns < best) best = ns;
            }
            bench_sink ^= sink ^ rp[0];
            printf("mul1-offset\t%d\t%d\t%.3f\n", limbs, offset, best);
        }
        free(arena_raw);
        return 0;
    }
    if ((argc == 3 || argc == 4) && strcmp(argv[1], "--bench-mul1") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("mul_1 benchmark limbs must be positive");
        int iters = argc == 4 ? atoi(argv[3]) : bench_iters_for_linear(limbs);
        if (iters <= 0) die("mul_1 benchmark iterations must be positive");
        uint64_t *up = bench_limbs(
            limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *tw = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        uint64_t *ref = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        if (!tw || !ref) die("out of memory checking mul_1");
        uint64_t tc = bn_mul_1(
            tw, up, limbs, 0xd6e8feb86659fd93ULL);
        uint64_t rc = bn_mul_1_ref(
            ref, up, limbs, 0xd6e8feb86659fd93ULL);
        if (tc != rc || memcmp(tw, ref, (size_t)limbs * sizeof(uint64_t)) != 0)
            die("mul_1 mismatch vs reference");
        double tn = bench_tungsten_mul_1(bn_mul_1, up, limbs, iters);
        double tr = bench_tungsten_mul_1(bn_mul_1_ref, up, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul_1(up, limbs, iters);
        printf("mul1 %d limbs: tungsten %.1f ns, ref %.1f ns,"
               " speedup %.2fx, gmp %.1f ns, gap %.2fx\n",
               limbs, tn, tr, ratio(tr, tn), gm, ratio(tn, gm));
#else
        printf("mul1 %d limbs: tungsten %.1f ns, ref %.1f ns, speedup %.2fx\n",
               limbs, tn, tr, ratio(tr, tn));
#endif
        free(ref);
        free(tw);
        free(up);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-sqr") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile square limbs must be positive");
        int iters = limbs <= 64 ? 1000000 :
                    limbs <= 256 ? 200000 :
                    limbs <= 1024 ? 20000 :
                    limbs <= 4096 ? 5000 : 1000;
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        (void)bench_tungsten_sqr(a, limbs, iters);
        free(a);
        printf("square profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
#ifdef HAVE_GMP
    if (argc == 6 && strcmp(argv[1], "--bench-tz") == 0) {
        /* Trailing-zero-limb fixture lanes for the BN_TZ_STRIP pre-
         * transforms: --bench-tz <op> <limbs> <zlimbs> <iters> with op in
         * {mul, div, mod, gcd}.  Operands are TOTAL <limbs> wide with
         * <zlimbs> trailing zero limbs — mul/gcd zero both sides, div/mod
         * zero the divisor (dividend 2*<limbs> wide, random).  Results are
         * checked against GMP on identical operands before timing.  GMP
         * does not strip trailing zeros either, so the printed gap is the
         * honest cross-library comparison; A/B the BN_TZ_STRIP=0 build for
         * the isolated transform win. */
        const char *opname = argv[2];
        int32_t limbs = (int32_t)atoi(argv[3]);
        int32_t z = (int32_t)atoi(argv[4]);
        int iters = atoi(argv[5]);
        if (limbs < 2 || z < 0 || z >= limbs || iters <= 0)
            die("bench-tz expects limbs >= 2, 0 <= z < limbs, iters > 0");
        int opk = strcmp(opname, "mul") == 0 ? 0
                : strcmp(opname, "div") == 0 ? 1
                : strcmp(opname, "mod") == 0 ? 2
                : strcmp(opname, "gcd") == 0 ? 3 : -1;
        if (opk < 0) die("bench-tz op must be mul, div, mod, or gcd");
        WValue a, b;
        if (opk == 1 || opk == 2) {
            a = bench_bigint(2 * limbs, 0x9e3779b97f4a7c15ULL);
            b = bench_bigint_tz(limbs, z, 0xd1b54a32d192ed03ULL);
        } else {
            a = bench_bigint_tz(limbs, z, 0x9e3779b97f4a7c15ULL);
            b = bench_bigint_tz(limbs, z, 0xd1b54a32d192ed03ULL);
        }
        mpz_t za, zb, zg, zr;
        mpz_inits(za, zb, zg, zr, NULL);
        gmp_import_value(za, a);
        gmp_import_value(zb, b);
        {   /* Oracle check before timing. */
            WValue got = opk == 0 ? bigint_mul_any(a, b)
                       : opk == 1 ? bigint_div_any(a, b)
                       : opk == 2 ? bigint_mod_any(a, b)
                       :            bigint_gcd_any(a, b);
            if (opk == 0) mpz_mul(zg, za, zb);
            else if (opk == 1) mpz_tdiv_q(zg, za, zb);
            else if (opk == 2) mpz_tdiv_r(zg, za, zb);
            else mpz_gcd(zg, za, zb);
            if (!value_matches_mpz(got, zg))
                dief("bench-tz %s mismatch vs GMP (limbs=%d z=%d)",
                     opname, limbs, z);
            if (got != a && got != b) bench_free_value(got);
        }
        WValue previous = W_NIL;
        double t0 = bench_now();
        for (int i = 0; i < iters; i++) {
            WValue result = opk == 0 ? bigint_mul_any(a, b)
                          : opk == 1 ? bigint_div_any(a, b)
                          : opk == 2 ? bigint_mod_any(a, b)
                          :            bigint_gcd_any(a, b);
            bench_sink ^= bench_observe_low(result) ^ (uint64_t)i;
            if (w_is_bigint(previous))
                bigint_release_if_live(w_as_bigint(previous));
            previous = result;
        }
        double tw = (bench_now() - t0) * 1e9 / iters;
        if (w_is_bigint(previous))
            bigint_release_if_live(w_as_bigint(previous));
        double g0 = bench_now();
        for (int i = 0; i < iters; i++) {
            if (opk == 0) mpz_mul(zr, za, zb);
            else if (opk == 1) mpz_tdiv_q(zr, za, zb);
            else if (opk == 2) mpz_tdiv_r(zr, za, zb);
            else mpz_gcd(zr, za, zb);
            bench_sink ^= mpz_getlimbn(zr, 0) ^ (uint64_t)i;
        }
        double gm = (bench_now() - g0) * 1e9 / iters;
        printf("tz-%s %d limbs z=%d (%d iters): tungsten %.1f ns, "
               "gmp %.1f ns, gap %.3fx\n",
               opname, limbs, z, iters, tw, gm, ratio(tw, gm));
        mpz_clears(za, zb, zg, zr, NULL);
        bench_free_value(a);
        bench_free_value(b);
        return 0;
    }
#endif
#ifdef HAVE_GMP
    if (argc == 3 && strcmp(argv[1], "--fuzz-tz") == 0) {
        /* Randomized trailing-zero-limb fuzz for BN_TZ_STRIP: random
         * widths, random per-side trailing-zero counts (including 0), all
         * tag-sign overlay combos, mul/div/mod/gcd each checked against
         * GMP on identical operands. */
        int cases = atoi(argv[2]);
        if (cases <= 0) die("fuzz-tz expects a positive case count");
        uint64_t state = 0x0ddc0ffeebadf00dULL;
        mpz_t za, zb, zg;
        mpz_inits(za, zb, zg, NULL);
        for (int c = 0; c < cases; c++) {
            int32_t na = 2 + (int32_t)(bench_rng(&state) % 96);
            int32_t nb = 2 + (int32_t)(bench_rng(&state) % 96);
            int32_t zla = (int32_t)(bench_rng(&state) % (uint64_t)na);
            int32_t zlb = (int32_t)(bench_rng(&state) % (uint64_t)nb);
            WValue a = bench_bigint_tz(na, zla, bench_rng(&state) | 1);
            WValue b = bench_bigint_tz(nb, zlb, bench_rng(&state) | 1);
            uint64_t signs = bench_rng(&state);
            if (signs & 1) a ^= W_BIGINT_SIGN_BIT;
            if (signs & 2) b ^= W_BIGINT_SIGN_BIT;
            gmp_import_value(za, a);
            gmp_import_value(zb, b);
            for (int op = 0; op < 4; op++) {
                WValue got = op == 0 ? bigint_mul_any(a, b)
                           : op == 1 ? bigint_div_any(a, b)
                           : op == 2 ? bigint_mod_any(a, b)
                           :           bigint_gcd_any(a, b);
                if (op == 0) mpz_mul(zg, za, zb);
                else if (op == 1) mpz_tdiv_q(zg, za, zb);
                else if (op == 2) mpz_tdiv_r(zg, za, zb);
                else mpz_gcd(zg, za, zb);
                if (!value_matches_mpz(got, zg))
                    dief("fuzz-tz mismatch case=%d op=%d na=%d nb=%d "
                         "za=%d zb=%d signs=%d",
                         c, op, na, nb, zla, zlb, (int)(signs & 3));
                /* Alias-safe: operand-identity returns (mod with |a|<|b|,
                 * etc.) are always marked shared, so the alias-counting
                 * release is correct for fresh AND aliased results. */
                bench_free_value(got);
            }
            bench_free_value(a);
            bench_free_value(b);
        }
        mpz_clears(za, zb, zg, NULL);
        printf("fuzz-tz: %d cases x 4 ops OK\n", cases);
        return 0;
    }
#endif
    if (argc == 4 && strcmp(argv[1], "--bench-mul-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("multiply benchmark expects positive limbs and iterations");
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        double tw = bench_tungsten_mul(a, b, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul(a, b, limbs, iters);
        printf("multiply %d limbs (%d iters): tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tw, gm, ratio(tw, gm));
#else
        printf("multiply %d limbs (%d iters): tungsten %.1f ns\n",
               limbs, iters, tw);
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-mul") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("multiply benchmark limbs must be positive");
        int iters = bench_iters_for_limbs(limbs);
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        double tw = bench_tungsten_mul(a, b, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul(a, b, limbs, iters);
        printf("multiply %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tw, gm, ratio(tw, gm));
#else
        printf("multiply %d limbs: tungsten %.1f ns\n", limbs, tw);
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-mul-ladder") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= BN_KARA_THRESHOLD || iters <= 0)
            die("multiply ladder expects limbs above the Karatsuba floor"
                " and positive iterations");
        uint64_t *a = bench_limbs(
            limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(
            limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
        double diff = bench_tungsten_mul_ladder(a, b, limbs, iters, 0);
        double sum = bench_tungsten_mul_ladder(a, b, limbs, iters, 1);
        double toom3 = bench_tungsten_mul_ladder(a, b, limbs, iters, 2);
        double toom4 = bench_tungsten_mul_ladder(a, b, limbs, iters, 3);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul(a, b, limbs, iters);
        printf("multiply ladder %d limbs (%d iters): diff %.1f ns,"
               " sum %.1f ns, toom3 %.1f ns, toom4 %.1f ns,"
               " gmp %.1f ns\n",
               limbs, iters, diff, sum, toom3, toom4, gm);
#else
        printf("multiply ladder %d limbs (%d iters): diff %.1f ns,"
               " sum %.1f ns, toom3 %.1f ns, toom4 %.1f ns\n",
               limbs, iters, diff, sum, toom3, toom4);
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--bench-boxed-mul-rect") == 0) {
        int32_t na = (int32_t)atoi(argv[2]);
        int32_t nb = (int32_t)atoi(argv[3]);
        int iters = atoi(argv[4]);
        if (na <= 0 || nb <= 0 || iters <= 0)
            die("boxed rectangular multiply expects two positive limb counts"
                " and positive iterations");
#ifdef HAVE_GMP
        check_boxed_mul_rect_against_gmp(na, nb);
#endif
        double tw = bench_boxed_mul_rect_churn(na, nb, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_boxed_mul_rect_churn(na, nb, iters);
        printf("boxed rectangular multiply %d x %d limbs (%d iters):"
               " tungsten %.1f ns, gmp %.1f ns, gap %.4fx\n",
               na, nb, iters, tw, gm, ratio(tw, gm));
#else
        printf("boxed rectangular multiply %d x %d limbs (%d iters):"
               " tungsten %.1f ns\n",
               na, nb, iters, tw);
#endif
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "--bench-mul-rect") == 0) {
        int32_t na = (int32_t)atoi(argv[2]);
        int32_t nb = (int32_t)atoi(argv[3]);
        int iters = atoi(argv[4]);
        if (na <= 0 || nb <= 0 || iters <= 0)
            die("rectangular multiply expects two positive limb counts"
                " and positive iterations");
        uint64_t *a = bench_limbs(
            na, 0x243f6a8885a308d3ULL ^ (uint64_t)na);
        uint64_t *b = bench_limbs(
            nb, 0x13198a2e03707344ULL ^ (uint64_t)nb);
        double tw = bench_tungsten_mul_rect(a, na, b, nb, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul_rect(a, na, b, nb, iters);
        printf("rectangular multiply %d x %d limbs (%d iters):"
               " tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               na, nb, iters, tw, gm, ratio(tw, gm));
#else
        printf("rectangular multiply %d x %d limbs (%d iters):"
               " tungsten %.1f ns\n",
               na, nb, iters, tw);
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-sqr") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("square benchmark limbs must be positive");
        int iters = bench_iters_for_limbs(limbs);
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        double tw = bench_tungsten_sqr(a, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_sqr(a, limbs, iters);
        printf("square %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tw, gm, ratio(tw, gm));
#else
        printf("square %d limbs: tungsten %.1f ns\n", limbs, tw);
#endif
        free(a);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-sqr-iters") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= 0 || iters <= 0)
            die("square benchmark expects positive limbs and iterations");
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        double tw = bench_tungsten_sqr(a, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_sqr(a, limbs, iters);
        printf("square %d limbs (%d iters): tungsten %.1f ns,"
               " gmp %.1f ns, gap %.2fx\n",
               limbs, iters, tw, gm, ratio(tw, gm));
#else
        printf("square %d limbs (%d iters): tungsten %.1f ns\n",
               limbs, iters, tw);
#endif
        free(a);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-sqr-paths") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= BN_KARA_THRESHOLD || iters <= 0)
            die("square path benchmark expects limbs above the Karatsuba floor"
                " and positive iterations");
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        double school = bench_tungsten_sqr_path(a, limbs, iters, 0);
        double kara = bench_tungsten_sqr_path(a, limbs, iters, 1);
#ifdef HAVE_GMP
        double gm = bench_gmp_sqr(a, limbs, iters);
        printf("square paths %d limbs (%d iters): school %.1f ns,"
               " karatsuba %.1f ns, gmp %.1f ns, best/gmp %.2fx\n",
               limbs, iters, school, kara, gm,
               ratio(school < kara ? school : kara, gm));
#else
        printf("square paths %d limbs (%d iters): school %.1f ns,"
               " karatsuba %.1f ns\n", limbs, iters, school, kara);
#endif
        free(a);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "--bench-sqr-ladder") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        int iters = atoi(argv[3]);
        if (limbs <= BN_KARA_THRESHOLD || iters <= 0)
            die("square ladder benchmark expects limbs above the Karatsuba"
                " floor and positive iterations");
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        double kara = bench_tungsten_sqr_ladder(a, limbs, iters, 0);
        double toom3 = bench_tungsten_sqr_ladder(a, limbs, iters, 1);
        double toom4 = bench_tungsten_sqr_ladder(a, limbs, iters, 2);
#ifdef HAVE_GMP
        double gm = bench_gmp_sqr(a, limbs, iters);
        printf("square ladder %d limbs (%d iters): karatsuba %.1f ns,"
               " toom3 %.1f ns, toom4 %.1f ns, gmp %.1f ns\n",
               limbs, iters, kara, toom3, toom4, gm);
#else
        printf("square ladder %d limbs (%d iters): karatsuba %.1f ns,"
               " toom3 %.1f ns, toom4 %.1f ns\n",
               limbs, iters, kara, toom3, toom4);
#endif
        free(a);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-mul-parallel") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("parallel multiply benchmark limbs must be positive");
        int iters = bench_iters_for_limbs(limbs);
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = bench_limbs(limbs,
                                  0x13198a2e03707344ULL ^ (uint64_t)limbs);
        double serial = bench_tungsten_mul_serial(a, b, limbs, iters);
        double parallel = bench_tungsten_mul(a, b, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mul(a, b, limbs, iters);
        printf("multiply paths %d limbs: serial %.1f ns, parallel %.1f ns,"
               " gmp %.1f ns (parallel/serial %.2fx)\n",
               limbs, serial, parallel, gm, ratio(parallel, serial));
#else
        printf("multiply paths %d limbs: serial %.1f ns, parallel %.1f ns"
               " (parallel/serial %.2fx)\n",
               limbs, serial, parallel, ratio(parallel, serial));
#endif
        free(a);
        free(b);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-sqr-parallel") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("parallel square benchmark limbs must be positive");
        int iters = bench_iters_for_limbs(limbs);
        uint64_t *a = bench_limbs(limbs,
                                  0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        double serial = bench_tungsten_sqr_serial(a, limbs, iters);
        double parallel = bench_tungsten_sqr(a, limbs, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_sqr(a, limbs, iters);
        printf("square paths %d limbs: serial %.1f ns, parallel %.1f ns,"
               " gmp %.1f ns (parallel/serial %.2fx)\n",
               limbs, serial, parallel, gm, ratio(parallel, serial));
#else
        printf("square paths %d limbs: serial %.1f ns, parallel %.1f ns"
               " (parallel/serial %.2fx)\n",
               limbs, serial, parallel, ratio(parallel, serial));
#endif
        free(a);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-mersenne") == 0) {
        uint64_t p = (uint64_t)strtoull(argv[2], NULL, 10);
        if (p < 2) die("Mersenne benchmark exponent must be at least two");
        int iters = p <= 127 ? 1000000 :
                    p <= 521 ? 200000 :
                    p <= 1279 ? 50000 : 5000;
        double tw = bench_tungsten_mersenne_square(p, iters);
#ifdef HAVE_GMP
        double gm = bench_gmp_mersenne_square(p, iters);
        printf("Mersenne square p=%llu: tungsten %.1f ns, gmp %.1f ns,"
               " gap %.2fx\n", (unsigned long long)p, tw, gm, ratio(tw, gm));
#else
        printf("Mersenne square p=%llu: tungsten %.1f ns\n",
               (unsigned long long)p, tw);
#endif
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--profile-ctxmulmod") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("profile ctxmulmod limbs must be positive");
        int iters = limbs <= 64 ? 1000000 :
                    limbs <= 256 ? 200000 :
                    limbs <= 1024 ? 20000 : 3000;
        (void)bench_tungsten_ctx_mulmod(limbs, iters);
        printf("ctxmulmod profile sink=%llu\n", (unsigned long long)bench_sink);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--bench-ctxmulmod") == 0) {
        int32_t limbs = (int32_t)atoi(argv[2]);
        if (limbs <= 0) die("ctxmulmod benchmark limbs must be positive");
        int iters = bench_iters_for_mod(limbs);
#ifdef HAVE_GMP
        check_mod_against_gmp(limbs);
        double tw = bench_tungsten_ctx_mulmod(limbs, iters);
        double gm = bench_gmp_mulmod(limbs, iters);
        printf("ctxmulmod %d limbs: tungsten %.1f ns, gmp %.1f ns, gap %.2fx\n",
               limbs, tw, gm, ratio(tw, gm));
#else
        printf("ctxmulmod %d limbs: tungsten %.1f ns\n", limbs,
               bench_tungsten_ctx_mulmod(limbs, iters));
#endif
        return 0;
    }

    const int32_t sizes[] = {
        4, 8, 16, 24, 32, 40, 48, 64,
        256, 1024, 2048, 4096, 8192, 16384
    };
    printf("Big math benchmark (ns/op, lower is better)\n");
#ifdef HAVE_GMP
    printf("GMP comparison enabled\n\n");
#else
    printf("GMP comparison disabled; install GMP and compile with -DHAVE_GMP -lgmp\n\n");
#endif

#ifdef HAVE_GMP
    printf("raw linear kernels (worst-case compare scans every limb)\n");
    printf("limbs  tungsten add  gmp add   gap  tungsten sub  gmp sub   gap  tungsten cmp  gmp cmp   gap\n");
    const int32_t linear_sizes[] = {1, 4, 16, 64, 256, 1024, 4096};
    for (size_t i = 0; i < sizeof(linear_sizes) / sizeof(linear_sizes[0]); i++) {
        int32_t limbs = linear_sizes[i];
        int iters = bench_iters_for_linear(limbs);
        uint64_t *a = bench_limbs(limbs, 0x243f6a8885a308d3ULL ^ (uint64_t)limbs);
        uint64_t *b = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        if (!b) die("out of memory preparing linear benchmark");
        memcpy(b, a, (size_t)limbs * sizeof(uint64_t));
        b[0] ^= 1ULL;
        check_linear_against_gmp(limbs, a, b);
        double ta = bench_tungsten_add(a, b, limbs, iters);
        double ga = bench_gmp_add(a, b, limbs, iters);
        double ts = bench_tungsten_sub(a, b, limbs, iters);
        double gs = bench_gmp_sub(a, b, limbs, iters);
        double tc = bench_tungsten_cmp(a, b, limbs, iters);
        double gc = bench_gmp_cmp(a, b, limbs, iters);
        printf("%5d %13.1f %8.1f %5.2fx %13.1f %8.1f %5.2fx %13.1f %8.1f %5.2fx\n",
               limbs, ta, ga, ratio(ta, ga), ts, gs, ratio(ts, gs),
               tc, gc, ratio(tc, gc));
        free(a);
        free(b);
    }
    printf("\n");

    printf("multiply-accumulate base kernel (rp += up * scalar)\n");
    printf("limbs  tungsten pipelined  prior c4  speedup  gmp addmul1   gap\n");
    const int32_t addmul_sizes[] = {4, 16, 64, 256, 1024, 4096};
    for (size_t i = 0; i < sizeof(addmul_sizes) / sizeof(addmul_sizes[0]); i++) {
        int32_t limbs = addmul_sizes[i];
        int iters = bench_iters_for_linear(limbs) / 4;
        uint64_t *up = bench_limbs(limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *rp0 = bench_limbs(limbs, 0xa4093822299f31d0ULL ^ (uint64_t)limbs);
        uint64_t *tw = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        uint64_t *old = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        uint64_t *gm = (uint64_t *)malloc((size_t)limbs * sizeof(uint64_t));
        if (!tw || !old || !gm) die("out of memory checking addmul_1");
        memcpy(tw, rp0, (size_t)limbs * sizeof(uint64_t));
        memcpy(old, rp0, (size_t)limbs * sizeof(uint64_t));
        memcpy(gm, rp0, (size_t)limbs * sizeof(uint64_t));
        uint64_t tc = bn_addmul_1(tw, up, limbs, 0xd6e8feb86659fd93ULL);
        uint64_t oc = bench_addmul_1_old(old, up, limbs, 0xd6e8feb86659fd93ULL);
        uint64_t gc = (uint64_t)mpn_addmul_1(
            (mp_limb_t *)gm, (const mp_limb_t *)up, (mp_size_t)limbs,
            (mp_limb_t)0xd6e8feb86659fd93ULL);
        if (tc != gc || oc != gc) die("addmul_1 carry mismatch vs GMP");
        assert_same_limbs("addmul_1 pipelined", tw, gm, limbs);
        assert_same_limbs("addmul_1 prior", old, gm, limbs);
        double tn = bench_tungsten_addmul_1(bn_addmul_1, rp0, up, limbs, iters);
        double to = bench_tungsten_addmul_1(bench_addmul_1_old, rp0, up, limbs, iters);
        double gg = bench_gmp_addmul_1(rp0, up, limbs, iters);
        printf("%5d %19.1f %9.1f %7.2fx %12.1f %5.2fx\n",
               limbs, tn, to, ratio(to, tn), gg, ratio(tn, gg));
        free(tw);
        free(old);
        free(gm);
        free(up);
        free(rp0);
    }
    printf("\n");

    printf("immutable positive bitwise ops"
           " (dead Tungsten capacity recycled; fresh GMP result)\n");
    printf("limbs  tw and  gmp and   gap  tw or  gmp or   gap  tw xor  gmp xor   gap\n");
    const int32_t bit_sizes[] = {1, 4, 16, 64, 256, 1024};
    for (size_t i = 0; i < sizeof(bit_sizes) / sizeof(bit_sizes[0]); i++) {
        int32_t limbs = bit_sizes[i];
        int iters = bench_iters_for_boxed_linear(limbs);
        check_bitwise_shifts_against_gmp(limbs);
        double ta = bench_tungsten_bitwise('&', limbs, iters);
        double ga = bench_gmp_bitwise('&', limbs, iters);
        double to = bench_tungsten_bitwise('|', limbs, iters);
        double go = bench_gmp_bitwise('|', limbs, iters);
        double tx = bench_tungsten_bitwise('^', limbs, iters);
        double gx = bench_gmp_bitwise('^', limbs, iters);
        printf("%5d %7.1f %8.1f %5.2fx %6.1f %7.1f %5.2fx %7.1f %8.1f %5.2fx\n",
               limbs, ta, ga, ratio(ta, ga), to, go, ratio(to, go),
               tx, gx, ratio(tx, gx));
    }
    printf("\n");

    printf("immutable positive shifts by 13 bits"
           " (dead Tungsten capacity recycled; fresh GMP result)\n");
    printf("limbs  tungsten shl  gmp shl   gap  tungsten shr  gmp shr   gap\n");
    for (size_t i = 0; i < sizeof(bit_sizes) / sizeof(bit_sizes[0]); i++) {
        int32_t limbs = bit_sizes[i];
        int iters = bench_iters_for_boxed_linear(limbs);
        double tl = bench_tungsten_shift(1, limbs, iters);
        double gl = bench_gmp_shift(1, limbs, iters);
        double tr = bench_tungsten_shift(0, limbs, iters);
        double gr = bench_gmp_shift(0, limbs, iters);
        printf("%5d %13.1f %8.1f %5.2fx %13.1f %8.1f %5.2fx\n",
               limbs, tl, gl, ratio(tl, gl), tr, gr, ratio(tr, gr));
    }
    printf("\n");
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
    printf("limbs  tungsten mod1  serial32 speedup  gmp mod1   gap  tungsten ctxmulmod gmp mulmod   gap\n");
#else
    printf("\nsmall modulus and generic modular multiply\n");
    printf("limbs  tungsten mod1  serial32 speedup  tungsten ctxmulmod\n");
#endif
    const int32_t mod_sizes[] = {1, 2, 4, 16, 64, 128, 256, 512, 1024, 2048};
    for (size_t i = 0; i < sizeof(mod_sizes) / sizeof(mod_sizes[0]); i++) {
        int32_t limbs = mod_sizes[i];
        int iters = bench_iters_for_mod(limbs);
        uint64_t *a = bench_limbs(limbs, 0x6a09e667f3bcc909ULL ^ (uint64_t)limbs);
        double tw_mod1 = bench_tungsten_mod1(a, limbs, iters * 10);
        double serial32_mod1 = bench_tungsten_mod1_serial32(a, limbs, iters * 10);
        double tw_mulmod = bench_tungsten_ctx_mulmod(limbs, iters);
#ifdef HAVE_GMP
        check_mod_against_gmp(limbs);
        double gm_mod1 = bench_gmp_mod1(a, limbs, iters * 10);
        double gm_mulmod = bench_gmp_mulmod(limbs, iters);
        printf("%5d %14.1f %9.1f %6.2fx %9.1f %5.2fx %19.1f %10.1f %5.2fx\n",
               limbs, tw_mod1, serial32_mod1, ratio(serial32_mod1, tw_mod1), gm_mod1,
               ratio(tw_mod1, gm_mod1), tw_mulmod, gm_mulmod, ratio(tw_mulmod, gm_mulmod));
#else
        printf("%5d %14.1f %9.1f %6.2fx %19.1f\n",
               limbs, tw_mod1, serial32_mod1, ratio(serial32_mod1, tw_mod1), tw_mulmod);
#endif
        free(a);
    }

#ifdef HAVE_GMP
    printf("\nimmutable-result divmod (dead Tungsten capacity recycled)"
           " and shared-factor gcd\n");
    printf("limbs  tungsten divmod  gmp divmod   gap  tungsten gcd  gmp gcd   gap\n");
    const int32_t div_sizes[] = {4, 16, 64, 256, 1024};
    for (size_t i = 0; i < sizeof(div_sizes) / sizeof(div_sizes[0]); i++) {
        int32_t limbs = div_sizes[i];
        int div_iters = bench_iters_for_divmod(limbs);
        int gcd_iters = bench_iters_for_gcd(limbs);
        uint64_t *u = bench_limbs(2 * limbs, 0x13198a2e03707344ULL ^ (uint64_t)limbs);
        uint64_t *v = bench_limbs(limbs, 0xa4093822299f31d0ULL ^ (uint64_t)limbs);
        check_divmod_against_gmp(limbs, u, v);
        check_gcd_against_gmp(limbs);
        double td = bench_tungsten_divmod(u, v, limbs, div_iters);
        double gd = bench_gmp_divmod_fresh(u, v, limbs, div_iters);
        double tg = bench_tungsten_gcd(limbs, gcd_iters);
        double gg = bench_gmp_gcd(limbs, gcd_iters);
        printf("%5d %16.1f %11.1f %5.2fx %13.1f %8.1f %5.2fx\n",
               limbs, td, gd, ratio(td, gd), tg, gg, ratio(tg, gg));
        free(u);
        free(v);
    }

    printf("\nrandom same-width gcd\n");
    printf("limbs  tungsten gcd  gmp gcd   gap\n");
    for (size_t i = 0; i < sizeof(div_sizes) / sizeof(div_sizes[0]); i++) {
        int32_t limbs = div_sizes[i];
        int gcd_iters = bench_iters_for_gcd(limbs);
        check_random_gcd_against_gmp(limbs);
        double tg = bench_tungsten_gcd_random(limbs, gcd_iters);
        double gg = bench_gmp_gcd_random(limbs, gcd_iters);
        printf("%5d %13.1f %8.1f %5.2fx\n",
               limbs, tg, gg, ratio(tg, gg));
    }
#endif

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

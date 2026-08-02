/*
 * Compare full 64-bit limbs with 63-bit "nail" limbs.
 *
 * This is intentionally a standalone layout experiment, not a second BigInt
 * implementation.  It measures two carry-heavy primitives that nails can
 * plausibly change: add_n and mul_1.  The AArch64 paths use matched four-limb
 * kernels, with the full-width side following the uninterrupted flag-chain
 * shape of Tungsten's runtime.  Other targets use portable unsigned-128-bit
 * reference-quality loops.
 *
 * Build (Apple Silicon):
 *   clang -O3 -DNDEBUG -mcpu=native -std=c11 \
 *     benchmarks/big_math/bench_limb_nails.c -lm -o /tmp/bench_limb_nails
 *
 * Usage:
 *   /tmp/bench_limb_nails [--target-ms 20] [--samples 9]
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(__clang__) || defined(__GNUC__)
#define NB_NOINLINE __attribute__((noinline, used))
#define NB_ALIGN64 __attribute__((aligned(64)))
#else
#define NB_NOINLINE
#define NB_ALIGN64
#endif

enum { MAX_LIMBS = 256, WIDTH_COUNT = 9, VALIDATION_TRIALS = 256 };

static const uint32_t widths[WIDTH_COUNT] = {
    1, 2, 4, 8, 16, 32, 64, 128, 256,
};

static const uint64_t NAIL63_MASK = UINT64_C(0x7fffffffffffffff);
static volatile uint64_t benchmark_sink;

/* r[0..n) = a[0..n) + b[0..n), radix 2^64; return carry. */
NB_NOINLINE NB_ALIGN64
uint64_t nailbench_add64(uint64_t *r, const uint64_t *a,
                         const uint64_t *b, uint32_t n) {
#if defined(__aarch64__)
    uint64_t blocks = (uint64_t)n >> 2;
    uint64_t count = n;
    uint64_t carry;

    /*
     * Loads, stores, TBZ, SUB, CBNZ do not modify NZCV, so carry stays in C
     * for the whole traversal.  Prefixing n%4 limbs leaves a four-limb body.
     */
    __asm__ volatile(
        "cmn xzr, xzr\n\t"
        "tbz %w[count], #0, 1f\n\t"
        "ldr x4, [%[ap]], #8\n\t"
        "ldr x8, [%[bp]], #8\n\t"
        "adcs x12, x4, x8\n\t"
        "str x12, [%[rp]], #8\n\t"
        "1:\n\t"
        "tbz %w[count], #1, 2f\n\t"
        "ldp x4, x5, [%[ap]], #16\n\t"
        "ldp x8, x9, [%[bp]], #16\n\t"
        "adcs x12, x4, x8\n\t"
        "adcs x13, x5, x9\n\t"
        "stp x12, x13, [%[rp]], #16\n\t"
        "2:\n\t"
        "cbz %[blocks], 4f\n\t"
        "3:\n\t"
        "ldp x4, x5, [%[ap]], #16\n\t"
        "ldp x6, x7, [%[ap]], #16\n\t"
        "ldp x8, x9, [%[bp]], #16\n\t"
        "ldp x10, x11, [%[bp]], #16\n\t"
        "adcs x12, x4, x8\n\t"
        "adcs x13, x5, x9\n\t"
        "adcs x14, x6, x10\n\t"
        "adcs x15, x7, x11\n\t"
        "stp x12, x13, [%[rp]], #16\n\t"
        "stp x14, x15, [%[rp]], #16\n\t"
        "sub %[blocks], %[blocks], #1\n\t"
        "cbnz %[blocks], 3b\n\t"
        "4:\n\t"
        "cset %[carry], hs"
        : [carry] "=&r"(carry), [rp] "+&r"(r), [ap] "+&r"(a),
          [bp] "+&r"(b), [blocks] "+&r"(blocks)
        : [count] "r"(count)
        : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11",
          "x12", "x13", "x14", "x15", "cc", "memory");
    return carry;
#else
    uint64_t carry = 0;
    for (uint32_t i = 0; i < n; i++) {
        __uint128_t sum = (__uint128_t)a[i] + b[i] + carry;
        r[i] = (uint64_t)sum;
        carry = (uint64_t)(sum >> 64);
    }
    return carry;
#endif
}

/* r[0..n) = a[0..n) + b[0..n), radix 2^63; return carry. */
#if defined(__aarch64__)
__attribute__((naked, noinline, used, aligned(64)))
uint64_t nailbench_add63(uint64_t *r, const uint64_t *a,
                         const uint64_t *b, uint32_t n) {
    __asm__(
        "mov x17, xzr\n"
        "tbz w3, #0, 1f\n"
        "ldr x4, [x1], #8\n"
        "ldr x8, [x2], #8\n"
        "add x12, x4, x8\n"
        "add x12, x12, x17\n"
        "lsr x17, x12, #63\n"
        "and x12, x12, #0x7fffffffffffffff\n"
        "str x12, [x0], #8\n"
        "1:\n"
        "tbz w3, #1, 2f\n"
        "ldp x4, x5, [x1], #16\n"
        "ldp x8, x9, [x2], #16\n"
        "add x12, x4, x8\n"
        "add x12, x12, x17\n"
        "add x13, x5, x9\n"
        "add x13, x13, x12, lsr #63\n"
        "and x12, x12, #0x7fffffffffffffff\n"
        "lsr x17, x13, #63\n"
        "and x13, x13, #0x7fffffffffffffff\n"
        "stp x12, x13, [x0], #16\n"
        "2:\n"
        "lsr x3, x3, #2\n"
        "cbz x3, 4f\n"
        "3:\n"
        "ldp x4, x5, [x1], #32\n"
        "ldp x6, x7, [x1, #-16]\n"
        "ldp x8, x9, [x2], #32\n"
        "ldp x10, x11, [x2, #-16]\n"
        "add x12, x4, x8\n"
        "add x12, x12, x17\n"
        "add x13, x5, x9\n"
        "add x13, x13, x12, lsr #63\n"
        "add x14, x6, x10\n"
        "add x14, x14, x13, lsr #63\n"
        "add x15, x7, x11\n"
        "add x15, x15, x14, lsr #63\n"
        "lsr x17, x15, #63\n"
        "and x12, x12, #0x7fffffffffffffff\n"
        "and x13, x13, #0x7fffffffffffffff\n"
        "and x14, x14, #0x7fffffffffffffff\n"
        "and x15, x15, #0x7fffffffffffffff\n"
        "stp x12, x13, [x0], #32\n"
        "stp x14, x15, [x0, #-16]\n"
        "sub x3, x3, #1\n"
        "cbnz x3, 3b\n"
        "4:\n"
        "mov x0, x17\n"
        "ret\n");
}
#else
NB_NOINLINE NB_ALIGN64
uint64_t nailbench_add63(uint64_t *r, const uint64_t *a,
                         const uint64_t *b, uint32_t n) {
    uint64_t carry = 0;
    uint32_t blocks = n >> 2;

    /* Match the full-width kernel's four-way loop unrolling. */
#define NB_ADD63_DIGIT() do {                                             \
        uint64_t sum = *a++ + *b++ + carry;                              \
        *r++ = sum & NAIL63_MASK;                                         \
        carry = sum >> 63;                                                \
    } while (0)
    if (n & 1)
        NB_ADD63_DIGIT();
    if (n & 2) {
        NB_ADD63_DIGIT();
        NB_ADD63_DIGIT();
    }
    while (blocks-- != 0) {
        NB_ADD63_DIGIT();
        NB_ADD63_DIGIT();
        NB_ADD63_DIGIT();
        NB_ADD63_DIGIT();
    }
#undef NB_ADD63_DIGIT
    return carry;
}
#endif

/* r[0..n) = a[0..n) * v, radix 2^64; return high digit. */
#if defined(__aarch64__)
__attribute__((naked, noinline, used, aligned(64)))
uint64_t nailbench_mul64(uint64_t *r, const uint64_t *a,
                         uint32_t n, uint64_t v) {
    __asm__(
        "mov x17, xzr\n"
        "tbz w2, #0, 1f\n"
        "ldr x4, [x1], #8\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "adds x8, x8, x17\n"
        "cinc x17, x12, hs\n"
        "str x8, [x0], #8\n"
        "1:\n"
        "tbz w2, #1, 2f\n"
        "ldp x4, x5, [x1], #16\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "mul x9, x5, x3\n"
        "umulh x13, x5, x3\n"
        "adds x8, x8, x17\n"
        "adcs x9, x9, x12\n"
        "adc x17, x13, xzr\n"
        "stp x8, x9, [x0], #16\n"
        "2:\n"
        "lsr x2, x2, #2\n"
        "cbz x2, 4f\n"
        "3:\n"
        "ldp x4, x5, [x1], #32\n"
        "ldp x6, x7, [x1, #-16]\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "mul x9, x5, x3\n"
        "umulh x13, x5, x3\n"
        "mul x10, x6, x3\n"
        "umulh x14, x6, x3\n"
        "mul x11, x7, x3\n"
        "umulh x15, x7, x3\n"
        "adds x8, x8, x17\n"
        "adcs x9, x9, x12\n"
        "adcs x10, x10, x13\n"
        "adcs x11, x11, x14\n"
        "adc x17, x15, xzr\n"
        "stp x8, x9, [x0], #32\n"
        "stp x10, x11, [x0, #-16]\n"
        "sub x2, x2, #1\n"
        "cbnz x2, 3b\n"
        "4:\n"
        "mov x0, x17\n"
        "ret\n");
}
#else
NB_NOINLINE NB_ALIGN64
uint64_t nailbench_mul64(uint64_t *r, const uint64_t *a,
                         uint32_t n, uint64_t v) {
    uint64_t carry = 0;
    for (uint32_t i = 0; i < n; i++) {
        __uint128_t product = (__uint128_t)a[i] * v + carry;
        r[i] = (uint64_t)product;
        carry = (uint64_t)(product >> 64);
    }
    return carry;
}
#endif

/* r[0..n) = a[0..n) * v, radix 2^63; return high digit. */
#if defined(__aarch64__)
__attribute__((naked, noinline, used, aligned(64)))
uint64_t nailbench_mul63(uint64_t *r, const uint64_t *a,
                         uint32_t n, uint64_t v) {
    __asm__(
        "mov x17, xzr\n"
        "tbz w2, #0, 1f\n"
        "ldr x4, [x1], #8\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "adds x8, x8, x17\n"
        "cinc x12, x12, hs\n"
        "extr x17, x12, x8, #63\n"
        "and x8, x8, #0x7fffffffffffffff\n"
        "str x8, [x0], #8\n"
        "1:\n"
        "tbz w2, #1, 2f\n"
        "ldp x4, x5, [x1], #16\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "mul x9, x5, x3\n"
        "umulh x13, x5, x3\n"
        "adds x8, x8, x17\n"
        "cinc x12, x12, hs\n"
        "extr x17, x12, x8, #63\n"
        "and x8, x8, #0x7fffffffffffffff\n"
        "adds x9, x9, x17\n"
        "cinc x13, x13, hs\n"
        "extr x17, x13, x9, #63\n"
        "and x9, x9, #0x7fffffffffffffff\n"
        "stp x8, x9, [x0], #16\n"
        "2:\n"
        "lsr x2, x2, #2\n"
        "cbz x2, 4f\n"
        "3:\n"
        "ldp x4, x5, [x1], #32\n"
        "ldp x6, x7, [x1, #-16]\n"
        "mul x8, x4, x3\n"
        "umulh x12, x4, x3\n"
        "mul x9, x5, x3\n"
        "umulh x13, x5, x3\n"
        "mul x10, x6, x3\n"
        "umulh x14, x6, x3\n"
        "mul x11, x7, x3\n"
        "umulh x15, x7, x3\n"
        "adds x8, x8, x17\n"
        "cinc x12, x12, hs\n"
        "extr x17, x12, x8, #63\n"
        "and x8, x8, #0x7fffffffffffffff\n"
        "adds x9, x9, x17\n"
        "cinc x13, x13, hs\n"
        "extr x17, x13, x9, #63\n"
        "and x9, x9, #0x7fffffffffffffff\n"
        "adds x10, x10, x17\n"
        "cinc x14, x14, hs\n"
        "extr x17, x14, x10, #63\n"
        "and x10, x10, #0x7fffffffffffffff\n"
        "adds x11, x11, x17\n"
        "cinc x15, x15, hs\n"
        "extr x17, x15, x11, #63\n"
        "and x11, x11, #0x7fffffffffffffff\n"
        "stp x8, x9, [x0], #32\n"
        "stp x10, x11, [x0, #-16]\n"
        "sub x2, x2, #1\n"
        "cbnz x2, 3b\n"
        "4:\n"
        "mov x0, x17\n"
        "ret\n");
}
#else
NB_NOINLINE NB_ALIGN64
uint64_t nailbench_mul63(uint64_t *r, const uint64_t *a,
                         uint32_t n, uint64_t v) {
    uint64_t carry = 0;
    uint32_t blocks = n >> 2;

#define NB_MUL63_DIGIT() do {                                             \
        __uint128_t product = (__uint128_t)*a++ * v + carry;              \
        *r++ = (uint64_t)product & NAIL63_MASK;                            \
        carry = (uint64_t)(product >> 63);                                \
    } while (0)
    if (n & 1)
        NB_MUL63_DIGIT();
    if (n & 2) {
        NB_MUL63_DIGIT();
        NB_MUL63_DIGIT();
    }
    while (blocks-- != 0) {
        NB_MUL63_DIGIT();
        NB_MUL63_DIGIT();
        NB_MUL63_DIGIT();
        NB_MUL63_DIGIT();
    }
#undef NB_MUL63_DIGIT
    return carry;
}
#endif

static uint64_t rng_state = UINT64_C(0x243f6a8885a308d3);

static uint64_t next_random(void) {
    uint64_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    rng_state = x;
    return x;
}

static uint64_t reference_add(uint64_t *r, const uint64_t *a,
                              const uint64_t *b, uint32_t n,
                              uint32_t digit_bits) {
    const __uint128_t mask = digit_bits == 64
        ? (__uint128_t)UINT64_MAX
        : (((__uint128_t)1 << digit_bits) - 1);
    __uint128_t carry = 0;

    for (uint32_t i = 0; i < n; i++) {
        __uint128_t sum = (__uint128_t)a[i] + b[i] + carry;
        r[i] = (uint64_t)(sum & mask);
        carry = sum >> digit_bits;
    }
    return (uint64_t)carry;
}

static uint64_t reference_mul_1(uint64_t *r, const uint64_t *a,
                                uint32_t n, uint64_t v,
                                uint32_t digit_bits) {
    const __uint128_t mask = digit_bits == 64
        ? (__uint128_t)UINT64_MAX
        : (((__uint128_t)1 << digit_bits) - 1);
    __uint128_t carry = 0;

    for (uint32_t i = 0; i < n; i++) {
        __uint128_t product = (__uint128_t)a[i] * v + carry;
        r[i] = (uint64_t)(product & mask);
        carry = product >> digit_bits;
    }
    return (uint64_t)carry;
}

typedef uint64_t (*add_kernel)(uint64_t *, const uint64_t *,
                               const uint64_t *, uint32_t);
typedef uint64_t (*mul_kernel)(uint64_t *, const uint64_t *,
                               uint32_t, uint64_t);

static void validation_failure(const char *operation, uint32_t digit_bits,
                               uint32_t n, uint32_t trial, uint32_t limb,
                               uint64_t got, uint64_t expected) {
    fprintf(stderr,
            "validation failed: %s radix=2^%u limbs=%u trial=%u "
            "limb=%u got=0x%016" PRIx64 " expected=0x%016" PRIx64 "\n",
            operation, digit_bits, n, trial, limb, got, expected);
    exit(1);
}

static void check_add(add_kernel kernel, uint32_t digit_bits, uint32_t n,
                      uint32_t trial, const uint64_t *a, const uint64_t *b) {
    const uint64_t left_canary = UINT64_C(0x6a09e667f3bcc909);
    const uint64_t right_canary = UINT64_C(0xbb67ae8584caa73b);
    uint64_t guarded[MAX_LIMBS + 2];
    uint64_t expected[MAX_LIMBS];

    memset(guarded, 0xa5, sizeof(guarded));
    guarded[0] = left_canary;
    guarded[n + 1] = right_canary;
    uint64_t got_carry = kernel(guarded + 1, a, b, n);
    uint64_t expected_carry = reference_add(expected, a, b, n, digit_bits);

    if (guarded[0] != left_canary)
        validation_failure("add_n left canary", digit_bits, n, trial, 0,
                           guarded[0], left_canary);
    if (guarded[n + 1] != right_canary)
        validation_failure("add_n right canary", digit_bits, n, trial, n,
                           guarded[n + 1], right_canary);
    for (uint32_t i = 0; i < n; i++) {
        if (guarded[i + 1] != expected[i])
            validation_failure("add_n", digit_bits, n, trial, i,
                               guarded[i + 1], expected[i]);
    }
    if (got_carry != expected_carry)
        validation_failure("add_n carry", digit_bits, n, trial, n,
                           got_carry, expected_carry);
}

static void check_mul(mul_kernel kernel, uint32_t digit_bits, uint32_t n,
                      uint32_t trial, const uint64_t *a, uint64_t v) {
    const uint64_t left_canary = UINT64_C(0x3c6ef372fe94f82b);
    const uint64_t right_canary = UINT64_C(0xa54ff53a5f1d36f1);
    uint64_t guarded[MAX_LIMBS + 2];
    uint64_t expected[MAX_LIMBS];

    memset(guarded, 0x5a, sizeof(guarded));
    guarded[0] = left_canary;
    guarded[n + 1] = right_canary;
    uint64_t got_carry = kernel(guarded + 1, a, n, v);
    uint64_t expected_carry = reference_mul_1(expected, a, n, v, digit_bits);

    if (guarded[0] != left_canary)
        validation_failure("mul_1 left canary", digit_bits, n, trial, 0,
                           guarded[0], left_canary);
    if (guarded[n + 1] != right_canary)
        validation_failure("mul_1 right canary", digit_bits, n, trial, n,
                           guarded[n + 1], right_canary);
    for (uint32_t i = 0; i < n; i++) {
        if (guarded[i + 1] != expected[i])
            validation_failure("mul_1", digit_bits, n, trial, i,
                               guarded[i + 1], expected[i]);
    }
    if (got_carry != expected_carry)
        validation_failure("mul_1 carry", digit_bits, n, trial, n,
                           got_carry, expected_carry);
}

static void fill_boundary_case(uint64_t *a64, uint64_t *b64,
                               uint64_t *a63, uint64_t *b63,
                               uint32_t n, uint32_t pattern) {
    for (uint32_t i = 0; i < n; i++) {
        switch (pattern) {
        case 0:
            a64[i] = b64[i] = a63[i] = b63[i] = 0;
            break;
        case 1:
            a64[i] = b64[i] = UINT64_MAX;
            a63[i] = b63[i] = NAIL63_MASK;
            break;
        case 2:
            a64[i] = (i & 1) ? UINT64_MAX : 0;
            b64[i] = ~a64[i];
            a63[i] = (i & 1) ? NAIL63_MASK : 0;
            b63[i] = NAIL63_MASK ^ a63[i];
            break;
        default:
            a64[i] = UINT64_MAX;
            b64[i] = i == 0 ? 1 : 0;
            a63[i] = NAIL63_MASK;
            b63[i] = i == 0 ? 1 : 0;
            break;
        }
    }
}

static void validate_kernels(void) {
    uint64_t a64[MAX_LIMBS], b64[MAX_LIMBS];
    uint64_t a63[MAX_LIMBS], b63[MAX_LIMBS];

    for (uint32_t wi = 0; wi < WIDTH_COUNT; wi++) {
        uint32_t n = widths[wi];

        for (uint32_t pattern = 0; pattern < 4; pattern++) {
            fill_boundary_case(a64, b64, a63, b63, n, pattern);
            uint64_t v64 = pattern == 0 ? 0
                         : pattern == 1 ? UINT64_MAX
                         : pattern == 2 ? UINT64_C(0xaaaaaaaaaaaaaaaa)
                                        : 1;
            uint64_t v63 = v64 & NAIL63_MASK;
            check_add(nailbench_add64, 64, n, pattern, a64, b64);
            check_add(nailbench_add63, 63, n, pattern, a63, b63);
            check_mul(nailbench_mul64, 64, n, pattern, a64, v64);
            check_mul(nailbench_mul63, 63, n, pattern, a63, v63);
        }

        for (uint32_t trial = 0; trial < VALIDATION_TRIALS; trial++) {
            for (uint32_t i = 0; i < n; i++) {
                a64[i] = next_random();
                b64[i] = next_random();
                a63[i] = a64[i] & NAIL63_MASK;
                b63[i] = b64[i] & NAIL63_MASK;
            }
            uint64_t v64 = next_random();
            uint64_t v63 = v64 & NAIL63_MASK;
            uint32_t label = trial + 4;
            check_add(nailbench_add64, 64, n, label, a64, b64);
            check_add(nailbench_add63, 63, n, label, a63, b63);
            check_mul(nailbench_mul64, 64, n, label, a64, v64);
            check_mul(nailbench_mul63, 63, n, label, a63, v63);
        }
    }
}

static uint64_t monotonic_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(1);
    }
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
}

typedef double (*timed_loop)(uint64_t);

static uint32_t active_n;
static uint64_t active_v64;
static uint64_t active_v63;
static uint64_t active_a64[MAX_LIMBS] NB_ALIGN64;
static uint64_t active_b64[MAX_LIMBS] NB_ALIGN64;
static uint64_t active_a63[MAX_LIMBS] NB_ALIGN64;
static uint64_t active_b63[MAX_LIMBS] NB_ALIGN64;
static uint64_t active_out[MAX_LIMBS] NB_ALIGN64;

static double time_add64(uint64_t iterations) {
    uint64_t carry = 0;
    uint64_t start = monotonic_ns();
    for (uint64_t i = 0; i < iterations; i++)
        carry = nailbench_add64(active_out, active_a64, active_b64, active_n);
    uint64_t elapsed = monotonic_ns() - start;
    benchmark_sink ^= carry ^ active_out[0] ^ active_out[active_n - 1];
    return (double)elapsed;
}

static double time_add63(uint64_t iterations) {
    uint64_t carry = 0;
    uint64_t start = monotonic_ns();
    for (uint64_t i = 0; i < iterations; i++)
        carry = nailbench_add63(active_out, active_a63, active_b63, active_n);
    uint64_t elapsed = monotonic_ns() - start;
    benchmark_sink ^= carry ^ active_out[0] ^ active_out[active_n - 1];
    return (double)elapsed;
}

static double time_mul64(uint64_t iterations) {
    uint64_t carry = 0;
    uint64_t start = monotonic_ns();
    for (uint64_t i = 0; i < iterations; i++)
        carry = nailbench_mul64(active_out, active_a64, active_n, active_v64);
    uint64_t elapsed = monotonic_ns() - start;
    benchmark_sink ^= carry ^ active_out[0] ^ active_out[active_n - 1];
    return (double)elapsed;
}

static double time_mul63(uint64_t iterations) {
    uint64_t carry = 0;
    uint64_t start = monotonic_ns();
    for (uint64_t i = 0; i < iterations; i++)
        carry = nailbench_mul63(active_out, active_a63, active_n, active_v63);
    uint64_t elapsed = monotonic_ns() - start;
    benchmark_sink ^= carry ^ active_out[0] ^ active_out[active_n - 1];
    return (double)elapsed;
}

static uint64_t calibrate_iterations(timed_loop loop, double target_ns) {
    uint64_t iterations = 1;
    double elapsed;

    do {
        elapsed = loop(iterations);
        if (elapsed >= 1000000.0 || iterations >= (UINT64_C(1) << 40))
            break;
        iterations *= 2;
    } while (1);

    double estimate = target_ns * (double)iterations / elapsed;
    if (estimate < 1.0)
        return 1;
    if (estimate > (double)(UINT64_C(1) << 50))
        return UINT64_C(1) << 50;
    return (uint64_t)(estimate + 0.5);
}

static int compare_double(const void *left, const void *right) {
    double a = *(const double *)left;
    double b = *(const double *)right;
    return (a > b) - (a < b);
}

static double median(double *values, uint32_t count) {
    qsort(values, count, sizeof(*values), compare_double);
    return values[count / 2];
}

struct summary {
    double log_raw_ratio;
    double log_density_ratio;
    uint32_t density_wins;
};

static void record_pair(const char *operation, uint32_t n,
                        timed_loop loop64, timed_loop loop63,
                        double target_ns, uint32_t samples,
                        uint32_t order_seed, struct summary *summary) {
    double *times64 = malloc(samples * sizeof(*times64));
    double *times63 = malloc(samples * sizeof(*times63));
    if (times64 == NULL || times63 == NULL) {
        fprintf(stderr, "out of memory allocating samples\n");
        exit(1);
    }

    uint64_t iterations64 = calibrate_iterations(loop64, target_ns);
    uint64_t iterations63 = calibrate_iterations(loop63, target_ns);

    for (uint32_t sample = 0; sample < samples; sample++) {
        if (((sample + order_seed) & 1) == 0) {
            times64[sample] = loop64(iterations64) / (double)iterations64;
            times63[sample] = loop63(iterations63) / (double)iterations63;
        } else {
            times63[sample] = loop63(iterations63) / (double)iterations63;
            times64[sample] = loop64(iterations64) / (double)iterations64;
        }
    }

    double ns_per_limb64 = median(times64, samples) / n;
    double ns_per_limb63 = median(times63, samples) / n;
    double raw_ratio = ns_per_limb63 / ns_per_limb64;
    double ns_per_bit64 = ns_per_limb64 / 64.0;
    double ns_per_bit63 = ns_per_limb63 / 63.0;
    double density_ratio = ns_per_bit63 / ns_per_bit64;

    printf("%s,%u,%.6f,%.6f,%.6f,%.9f,%.9f,%.6f\n",
           operation, n, ns_per_limb64, ns_per_limb63, raw_ratio,
           ns_per_bit64, ns_per_bit63, density_ratio);

    summary->log_raw_ratio += log(raw_ratio);
    summary->log_density_ratio += log(density_ratio);
    summary->density_wins += density_ratio < 1.0;

    free(times64);
    free(times63);
}

static double parse_positive_double(const char *text, const char *flag) {
    char *end = NULL;
    errno = 0;
    double value = strtod(text, &end);
    if (errno != 0 || end == text || *end != '\0' || !isfinite(value) ||
        !(value > 0.0)) {
        fprintf(stderr, "%s requires a positive number, got '%s'\n", flag, text);
        exit(2);
    }
    return value;
}

static uint32_t parse_samples(const char *text) {
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value < 3 ||
        value > 99 || (value & 1) == 0) {
        fprintf(stderr,
                "--samples requires an odd integer in [3, 99], got '%s'\n",
                text);
        exit(2);
    }
    return (uint32_t)value;
}

static void usage(const char *program) {
    fprintf(stderr, "usage: %s [--target-ms NUMBER] [--samples ODD]\n", program);
}

int main(int argc, char **argv) {
    double target_ms = 20.0;
    uint32_t samples = 9;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--target-ms") == 0 && i + 1 < argc) {
            target_ms = parse_positive_double(argv[++i], "--target-ms");
        } else if (strcmp(argv[i], "--samples") == 0 && i + 1 < argc) {
            samples = parse_samples(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    validate_kernels();

    for (uint32_t i = 0; i < MAX_LIMBS; i++) {
        active_a64[i] = next_random();
        active_b64[i] = next_random();
        active_a63[i] = active_a64[i] & NAIL63_MASK;
        active_b63[i] = active_b64[i] & NAIL63_MASK;
    }
    active_v64 = next_random();
    active_v63 = active_v64 & NAIL63_MASK;

#if defined(__aarch64__)
    printf("# backend=aarch64-matched-four-limb-asm\n");
#else
    printf("# backend=portable-uint128 nail63=optimized-c\n");
#endif
    printf("# validation=4-boundary-plus-%d-random-per-width status=passed\n",
           VALIDATION_TRIALS);
    printf("# target_ms=%.3f samples=%u statistic=median timing_order=alternating\n",
           target_ms, samples);
    printf("# density_ratio=(nail63_ns_per_limb/63)/(full64_ns_per_limb/64); "
           "nail63 wins below 1.0\n");
    printf("operation,limbs,full64_ns_per_limb,nail63_ns_per_limb,"
           "raw_nail63_over_full64,full64_ns_per_useful_bit,"
           "nail63_ns_per_useful_bit,density_nail63_over_full64\n");

    struct summary add_summary = {0};
    struct summary mul_summary = {0};
    double target_ns = target_ms * 1000000.0;
    for (uint32_t wi = 0; wi < WIDTH_COUNT; wi++) {
        active_n = widths[wi];
        record_pair("add_n", active_n, time_add64, time_add63,
                    target_ns, samples, wi, &add_summary);
        record_pair("mul_1", active_n, time_mul64, time_mul63,
                    target_ns, samples, wi + 1, &mul_summary);
    }

    printf("# summary operation=add_n raw_geomean=%.6f density_geomean=%.6f "
           "nail63_density_wins=%u/%u\n",
           exp(add_summary.log_raw_ratio / WIDTH_COUNT),
           exp(add_summary.log_density_ratio / WIDTH_COUNT),
           add_summary.density_wins, WIDTH_COUNT);
    printf("# summary operation=mul_1 raw_geomean=%.6f density_geomean=%.6f "
           "nail63_density_wins=%u/%u\n",
           exp(mul_summary.log_raw_ratio / WIDTH_COUNT),
           exp(mul_summary.log_density_ratio / WIDTH_COUNT),
           mul_summary.density_wins, WIDTH_COUNT);
    printf("# sink=0x%016" PRIx64 "\n", benchmark_sink);
    return 0;
}

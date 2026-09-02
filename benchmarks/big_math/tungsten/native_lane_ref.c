/* Support code for the compiled-Tungsten bignum benchmark lane.
 *
 * Operand construction, the thread CPU clock, and the correctness oracle are
 * deliberately outside the timed Tungsten loops.  The loops themselves use
 * ordinary Tungsten operators and methods; Core may in turn reach retained C
 * kernels through its production ccall seams.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* These are retained runtime boundaries but not part of the broad public
 * header surface.  The benchmark oracle calls them outside timed regions. */
WValue bigint_isqrt_any(WValue a);
WValue bigint_powmod_any(WValue base, WValue exponent, WValue modulus);
WValue w_bigint_from_dec_str(WValue text);

static int native_operation_is(WValue value, const char *expected) {
    char inline_buffer[6];
    const char *data = NULL;
    size_t length = 0;
    w_str_data(value, inline_buffer, &data, &length);
    size_t expected_length = strlen(expected);
    return length == expected_length &&
           memcmp(data, expected, expected_length) == 0;
}

static uint64_t native_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * UINT64_C(2685821657736338717);
}

static WValue native_bigint(int32_t limbs, uint64_t seed) {
    WValue value = w_bigint_alloc_boxed(w_int(limbs));
    WBigint *big = w_as_bigint(value);
    uint64_t state = seed;
    for (int32_t index = 0; index < limbs; index++)
        big->limbs[index] = native_rng(&state);
    big->limbs[0] |= UINT64_C(1);
    big->limbs[limbs - 1] |= UINT64_C(1) << 63;
    big->size = limbs;
    return value;
}

WValue w_bench_tungsten_native_operand(
    WValue operation_value, WValue row_limbs_value, WValue which_value
) {
    int64_t row_limbs_i64 = w_to_i64(row_limbs_value);
    int64_t which = w_to_i64(which_value);
    if (row_limbs_i64 < 1 || row_limbs_i64 > 1048576)
        abort();
    int32_t row_limbs = (int32_t)row_limbs_i64;

    if (which == 2) {
        if (!native_operation_is(operation_value, "powmod")) return W_NIL;
        return native_bigint(
            row_limbs,
            UINT64_C(0xa4093822299f31d0) ^ (uint64_t)row_limbs
        );
    }

    if (which != 0 && which != 1) abort();
    int32_t limbs = row_limbs;
    uint64_t seed;
    if (which == 0) {
        if (native_operation_is(operation_value, "div") ||
            native_operation_is(operation_value, "mod") ||
            native_operation_is(operation_value, "isqrt"))
            limbs *= 2;
        seed = UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)row_limbs;
    } else {
        if (native_operation_is(operation_value, "add1") ||
            native_operation_is(operation_value, "sub1") ||
            native_operation_is(operation_value, "mul1") ||
            native_operation_is(operation_value, "div1"))
            limbs = 1;
        seed = UINT64_C(0x13198a2e03707344) ^ (uint64_t)row_limbs;
        if (native_operation_is(operation_value, "cmp"))
            seed = UINT64_C(0x243f6a8885a308d3) ^ (uint64_t)row_limbs;
    }

    WValue value = native_bigint(limbs, seed);
    if (which == 1 && native_operation_is(operation_value, "cmp"))
        w_as_bigint(value)->limbs[0] ^= UINT64_C(1);
    if (which == 0 && native_operation_is(operation_value, "abs"))
        w_as_bigint(value)->size = -w_as_bigint(value)->size;
    return value;
}

WValue w_bench_tungsten_native_thread_cpu_ns(void) {
    struct timespec timestamp;
    if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) abort();
    uint64_t nanoseconds =
        (uint64_t)timestamp.tv_sec * UINT64_C(1000000000) +
        (uint64_t)timestamp.tv_nsec;
    return w_u64(nanoseconds);
}

WValue w_bench_tungsten_native_release(WValue value) {
    w_value_free(value);
    return W_NIL;
}

WValue w_bench_tungsten_native_assert_equal(
    WValue operation, WValue got, WValue expected
) {
    if (w_eq(got, expected) != W_TRUE) {
        char inline_buffer[6];
        const char *data = NULL;
        size_t length = 0;
        w_str_data(operation, inline_buffer, &data, &length);
        fprintf(stderr, "Tungsten native/C mismatch for %.*s\n",
                (int)length, data);
        abort();
    }
    return W_TRUE;
}

WValue w_bench_tungsten_native_reference(
    WValue operation, WValue a, WValue b, WValue modulus, WValue decimal
) {
    if (native_operation_is(operation, "add") ||
        native_operation_is(operation, "add1"))
        return w_bigint_add(a, b);
    if (native_operation_is(operation, "sub") ||
        native_operation_is(operation, "sub1"))
        return w_bigint_sub(a, b);
    if (native_operation_is(operation, "mul") ||
        native_operation_is(operation, "mul1"))
        return w_mul(a, b);
    if (native_operation_is(operation, "sqr"))
        return w_mul(a, a);
    if (native_operation_is(operation, "div") ||
        native_operation_is(operation, "div1"))
        return w_bigint_div(a, b);
    if (native_operation_is(operation, "mod"))
        return w_bigint_mod(a, b);
    if (native_operation_is(operation, "gcd"))
        return w_bigint_gcd(a, b);
    if (native_operation_is(operation, "and"))
        return w_bigint_and_c(a, b);
    if (native_operation_is(operation, "or"))
        return w_bigint_or_c(a, b);
    if (native_operation_is(operation, "xor"))
        return w_bigint_xor_c(a, b);
    if (native_operation_is(operation, "shl"))
        return w_bigint_shl(a, w_int(13));
    if (native_operation_is(operation, "shr"))
        return w_bigint_shr(a, w_int(13));
    if (native_operation_is(operation, "cmp"))
        return w_bigint_compare_c(a, b);
    if (native_operation_is(operation, "neg"))
        return w_neg(a);
    if (native_operation_is(operation, "abs"))
        return w_neg(a);
    if (native_operation_is(operation, "pow"))
        return w_pow(a, w_int(5));
    if (native_operation_is(operation, "powmod"))
        return bigint_powmod_any(a, b, modulus);
    if (native_operation_is(operation, "lcm"))
        return w_bigint_lcm(a, b);
    if (native_operation_is(operation, "isqrt"))
        return bigint_isqrt_any(a);
    if (native_operation_is(operation, "tostr"))
        return w_bigint_to_s(a, w_int(10));
    if (native_operation_is(operation, "fromstr"))
        return w_bigint_from_dec_str(decimal);
    abort();
}

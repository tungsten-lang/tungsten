/* Benchmark-only mirror and fixtures for the installed BigArray#size IC. */

#include "runtime.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

/* Compiler-generated cleanup calls this exported runtime symbol directly,
 * but it is intentionally not part of runtime.h's public embedding surface. */
extern void w_value_free(WValue value);

/* Include ordinary values, the 2^32 boundary that motivates BigArray, both
 * i48 boxing boundaries, and the signed i64 endpoints. Negative sizes are
 * invalid for ordinary constructors but are reachable through the public
 * low-level w_big_array_view bridge; checking them pins the source body's
 * signed cast and makes the mirror exact over every header bit pattern. */
static const int64_t W_BENCH_BIG_ARRAY_SIZES[] = {
    INT64_C(0),
    INT64_C(1),
    INT64_C(7),
    INT64_C(255),
    INT64_C(4294967295),
    INT64_C(4294967296),
    INT64_C(4294967297),
    INT64_C(140737488355326),
    INT64_C(140737488355327),
    INT64_C(140737488355328),
    INT64_C(140737488355329),
    -INT64_C(1),
    -INT64_C(140737488355328),
    -INT64_C(140737488355329),
    INT64_MAX,
    INT64_MIN,
};

WValue w_ref_big_array_size(WValue recv) {
    return w_int(((WBigArray *)w_as_ptr(recv))->size);
}

WValue w_bench_big_array_size_fixture(WValue selector) {
    int64_t index = w_as_int(selector);
    int64_t count = (int64_t)(sizeof(W_BENCH_BIG_ARRAY_SIZES) /
                              sizeof(W_BENCH_BIG_ARRAY_SIZES[0]));
    if (index < 0 || index >= count)
        w_raise(w_string("big-array-size fixture index out of bounds"));

    WBigArray *array = (WBigArray *)calloc(1, sizeof(WBigArray));
    if (!array) w_raise(w_string("big-array-size fixture allocation failed"));
    array->type = W_TYPE_BIG_ARRAY;
    array->ebits = 65;
    array->flags = W_FLAG_VIEW;
    array->start = 0;
    array->size = W_BENCH_BIG_ARRAY_SIZES[index];
    array->cap = array->size;
    array->slots = NULL;
    return w_box_ptr(array, W_SUBTAG_GENERIC);
}

int64_t w_bench_big_array_raw_size(WValue recv) {
    return ((WBigArray *)w_as_ptr(recv))->size;
}

/* 0 = immediate Int, positive = positive BigInt limb count, negative =
 * negative BigInt limb count. w_int canonicalizes every tested overflow to a
 * one-limb BigInt, so this plus numeric equality pins representation. */
WValue w_bench_big_array_size_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-INT64_C(99));
}

/* Overflow timing must not accumulate millions of one-limb BigInts. Consume
 * the low byte and release only heap BigInts; immediate Ints need no action. */
WValue w_bench_big_array_size_consume(WValue value) {
    int64_t raw = w_to_i64(value);
    if (w_is_bigint(value)) w_value_free(value);
    return w_int(raw & INT64_C(0xFF));
}

WValue w_bench_big_array_size_dispose(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

WValue w_bench_big_array_size_release(WValue value) {
    free(w_as_ptr(value));
    return W_NIL;
}

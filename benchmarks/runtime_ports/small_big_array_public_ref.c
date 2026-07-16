/* Cross-root fixtures and thread-CPU clock for the public SmallArray/BigArray
 * leaf migration gate. The timed path itself always calls the public method. */

#include "runtime.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

extern void w_value_free(WValue value);

static const uint8_t W_LEAF_SMALL_SIZES[] = {
    0, 1, 2, 7, 15, 31, 63, 127, 128, 254, 255
};

static const int64_t W_LEAF_BIG_SIZES[] = {
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

static int64_t checked_index(WValue selector, int64_t count,
                             const char *message) {
    int64_t index = w_as_int(selector);
    if (index < 0 || index >= count) {
        w_raise(w_string(message));
        return 0;
    }
    return index;
}

WValue w_leaf_small_fixture(WValue selector) {
    int64_t count = (int64_t)(sizeof(W_LEAF_SMALL_SIZES) /
                              sizeof(W_LEAF_SMALL_SIZES[0]));
    int64_t index = checked_index(selector, count,
                                  "SmallArray leaf fixture out of bounds");
    return w_small_array_new(8, W_LEAF_SMALL_SIZES[index], 0);
}

WValue w_leaf_small_expected(WValue selector) {
    int64_t count = (int64_t)(sizeof(W_LEAF_SMALL_SIZES) /
                              sizeof(W_LEAF_SMALL_SIZES[0]));
    int64_t index = checked_index(selector, count,
                                  "SmallArray leaf expected out of bounds");
    return w_int(W_LEAF_SMALL_SIZES[index]);
}

WValue w_leaf_big_fixture(WValue selector) {
    int64_t count = (int64_t)(sizeof(W_LEAF_BIG_SIZES) /
                              sizeof(W_LEAF_BIG_SIZES[0]));
    int64_t index = checked_index(selector, count,
                                  "BigArray leaf fixture out of bounds");
    /* The public view constructor deliberately accepts signed-i64 lengths.
     * That pins source parity even for raw headers outside ordinary valid
     * collection sizes, including both w_int overflow directions. */
    return w_big_array_view(NULL, 65, W_LEAF_BIG_SIZES[index]);
}

WValue w_leaf_big_expected(WValue selector) {
    int64_t count = (int64_t)(sizeof(W_LEAF_BIG_SIZES) /
                              sizeof(W_LEAF_BIG_SIZES[0]));
    int64_t index = checked_index(selector, count,
                                  "BigArray leaf expected out of bounds");
    return w_int(W_LEAF_BIG_SIZES[index]);
}

int64_t w_leaf_small_raw_size(WValue recv) {
    return ((WSmallArray *)w_as_ptr(recv))->size;
}

int64_t w_leaf_big_raw_size(WValue recv) {
    return ((WBigArray *)w_as_ptr(recv))->size;
}

WValue w_leaf_big_view_p(WValue recv) {
    WBigArray *array = (WBigArray *)w_as_ptr(recv);
    return (array->flags & W_FLAG_VIEW) != 0 ? W_TRUE : W_FALSE;
}

/* 0 = immediate Int, positive/negative = BigInt signed limb count. */
WValue w_leaf_integer_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-INT64_C(99));
}

WValue w_leaf_consume_integer(WValue value) {
    int64_t raw = w_to_i64(value);
    if (w_is_bigint(value)) w_value_free(value);
    return w_int(raw & INT64_C(0xFF));
}

WValue w_leaf_dispose_integer(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

WValue w_leaf_release_fixture(WValue value) {
    free(w_as_ptr(value));
    return W_NIL;
}

WValue w_leaf_thread_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) != 0) return w_int(-1);
    return w_int((int64_t)now.tv_sec * INT64_C(1000000000) + now.tv_nsec);
}

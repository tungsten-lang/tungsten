/* Public-dispatch fixtures and a thread-CPU clock for the isolated
 * BigArray#cap/#empty? migration gate. Timed code calls the public methods;
 * these helpers only build exact raw headers, consume results, and measure. */

#include "runtime.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

extern void w_value_free(WValue value);

typedef struct {
    int64_t size;
    int64_t cap;
} WBaceCase;

static const WBaceCase W_BACE_CASES[] = {
    { INT64_C(0),                    INT64_C(0) },
    { INT64_C(1),                    INT64_C(1) },
    { INT64_C(7),                    INT64_C(7) },
    { INT64_C(255),                  INT64_C(255) },
    { INT64_C(4294967295),           INT64_C(4294967295) },
    { INT64_C(4294967296),           INT64_C(4294967296) },
    { INT64_C(1),                    INT64_C(140737488355326) },
    { INT64_C(1),                    INT64_C(140737488355327) },
    { -INT64_C(1),                  -INT64_C(1) },
    { -INT64_C(1),                  -INT64_C(140737488355328) },
    { INT64_C(1),                    INT64_C(140737488355328) },
    { INT64_C(1),                    INT64_C(140737488355329) },
    { INT64_C(1),                    INT64_MAX },
    { -INT64_C(1),                  -INT64_C(140737488355329) },
    { -INT64_C(1),                  -INT64_C(140737488355330) },
    { -INT64_C(1),                   INT64_MIN },
    { INT64_C(0),                    INT64_C(7) },
    { INT64_C(7),                    INT64_C(0) },
    { INT64_MAX,                     INT64_C(7) },
    { INT64_MIN,                     INT64_C(7) },
    { INT64_C(0),                    INT64_MAX },
    { INT64_C(0),                    INT64_MIN },
};

static int64_t bace_checked_index(WValue selector) {
    int64_t index = w_as_int(selector);
    int64_t count = (int64_t)(sizeof(W_BACE_CASES) / sizeof(W_BACE_CASES[0]));
    if (index < 0 || index >= count) {
        w_raise(w_string("BigArray cap/empty fixture out of bounds"));
        return 0;
    }
    return index;
}

static WValue bace_make(int64_t size, int64_t cap) {
    WValue value = w_big_array_view(NULL, 65, size);
    ((WBigArray *)w_as_ptr(value))->cap = cap;
    return value;
}

WValue w_bace_case_count(void) {
    return w_int((int64_t)(sizeof(W_BACE_CASES) / sizeof(W_BACE_CASES[0])));
}

WValue w_bace_fixture(WValue selector) {
    int64_t index = bace_checked_index(selector);
    return bace_make(W_BACE_CASES[index].size, W_BACE_CASES[index].cap);
}

/* Unmapped factory used to ensure each no-use spec is autoloaded by the one
 * low-level BigArray entry point it names, rather than by its seed value. */
WValue w_bace_seed(void) {
    return w_big_array_new(65, 8);
}

WValue w_bace_expected_cap(WValue selector) {
    return w_int(W_BACE_CASES[bace_checked_index(selector)].cap);
}

WValue w_bace_expected_empty(WValue selector) {
    return W_BACE_CASES[bace_checked_index(selector)].size == 0
        ? W_TRUE : W_FALSE;
}

int64_t w_bace_raw_size(WValue value) {
    return ((WBigArray *)w_as_ptr(value))->size;
}

int64_t w_bace_raw_cap(WValue value) {
    return ((WBigArray *)w_as_ptr(value))->cap;
}

WValue w_bace_view_p(WValue value) {
    WBigArray *array = (WBigArray *)w_as_ptr(value);
    return (array->flags & W_FLAG_VIEW) != 0 ? W_TRUE : W_FALSE;
}

/* 0 = immediate Int, positive/negative = BigInt signed limb count. */
WValue w_bace_integer_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-INT64_C(99));
}

WValue w_bace_consume_integer(WValue value) {
    int64_t raw = w_to_i64(value);
    if (w_is_bigint(value)) w_value_free(value);
    return w_int(raw & INT64_C(0xFF));
}

WValue w_bace_dispose_integer(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

WValue w_bace_release(WValue value) {
    WBigArray *array = (WBigArray *)w_as_ptr(value);
    if ((array->flags & W_FLAG_OWNED) && !(array->flags & W_FLAG_VIEW)) {
        free(array->slots);
    }
    free(array);
    return W_NIL;
}

WValue w_bace_thread_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) != 0) return w_int(-1);
    return w_int((int64_t)now.tv_sec * INT64_C(1000000000) + now.tv_nsec);
}

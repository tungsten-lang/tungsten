/* Cross-root fixtures, native references, and thread-CPU clock for the
 * production Array size/cap/empty?/first/last migration gate. Timed code calls
 * only the public methods; these helpers keep setup and result consumption
 * identical across the baseline and candidate builds. */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <time.h>

extern void w_value_free(WValue value);

enum { W_ARRAY_LEAF_FIXTURE_COUNT = 16 };

static int64_t fixture_index(WValue selector) {
    int64_t index = w_as_int(selector);
    if (index < 0 || index >= W_ARRAY_LEAF_FIXTURE_COUNT) {
        w_raise(w_string("Array leaf fixture out of bounds"));
        return 0;
    }
    return index;
}

static WValue new_int_array(int64_t ebits, const int64_t *values, int64_t n) {
    WValue array = w_array_new(ebits, n);
    for (int64_t i = 0; i < n; i++) {
        WValue value = w_int(values[i]);
        w_array_push(array, value);
        /* Packed arrays copy the numeric payload; an overflow BigInt argument
         * is not retained. All w64 fixtures below use immediate integers. */
        if (ebits != 65 && w_is_bigint(value)) w_value_free(value);
    }
    return array;
}

static WValue new_float_array(int64_t ebits, const double *values, int64_t n) {
    WValue array = w_array_new(ebits, n);
    for (int64_t i = 0; i < n; i++) w_array_push(array, w_float(values[i]));
    return array;
}

static WValue new_bool_array(const int *values, int64_t n) {
    WValue array = w_array_new(1, n);
    for (int64_t i = 0; i < n; i++) {
        w_array_push(array, values[i] ? W_TRUE : W_FALSE);
    }
    return array;
}

WValue w_array_leaf_fixture(WValue selector) {
    int64_t index = fixture_index(selector);
    switch (index) {
    case 0:
        return w_array_new_empty();                         /* empty w64 */
    case 1: {
        const int64_t values[] = {11, 22, 33};
        return new_int_array(65, values, 3);               /* plain w64 */
    }
    case 2: {
        const int64_t values[] = {101, 102, 103, 104};
        WValue array = new_int_array(65, values, 4);
        (void)w_array_shift(array);
        return array;                                      /* shifted w64 */
    }
    case 3: {
        const int64_t values[] = {201, 202, 203, 204, 205};
        WValue parent = new_int_array(65, values, 5);
        return w_array_view(parent, w_int(1), w_int(3));   /* w64 view */
    }
    case 4:
        return w_array_new(8, 0);                          /* empty u8 */
    case 5: {
        const int64_t values[] = {3, 129, 251};
        return new_int_array(8, values, 3);                /* u8 */
    }
    case 6: {
        const int64_t values[] = {4, 18, 130, 252};
        WValue array = new_int_array(8, values, 4);
        (void)w_array_shift(array);
        return array;                                      /* shifted u8 */
    }
    case 7: {
        const int64_t values[] = {8, 19, 131, 253};
        WValue parent = new_int_array(8, values, 4);
        return w_array_view(parent, w_int(1), w_int(2));   /* u8 view */
    }
    case 8: {
        const int64_t values[] = {-32768, -11, 32767};
        return new_int_array(116, values, 3);              /* i16 */
    }
    case 9: {
        const int values[] = {1, 0, 1};
        return new_bool_array(values, 3);                  /* bool/u1 */
    }
    case 10: {
        const double values[] = {1.5, -2.25, 3.75};
        return new_float_array(-32, values, 3);            /* f32 */
    }
    case 11: {
        const double values[] = {-1.25, 2.5, -4.75};
        return new_float_array(-64, values, 3);            /* f64 */
    }
    case 12: {
        const int64_t values[] = {23, INT64_C(140737488355328)};
        return new_int_array(64, values, 2);               /* u64 BigInt decode */
    }
    case 13: {
        const int64_t values[] = {-8, -1, 7};
        return new_int_array(-4, values, 3);               /* i4 */
    }
    case 14: {
        WValue array = w_array_new(1, 0);
        return array;                                      /* empty bool/u1 */
    }
    default: {
        WValue array = w_array_new_empty();
        for (int64_t i = 0; i < 20; i++) w_array_push(array, w_int(i * 3 - 7));
        return array;                                      /* grown w64, cap > size */
    }
    }
}

WValue w_array_leaf_ref_size(WValue recv) {
    return w_array_size(recv);
}

WValue w_array_leaf_ref_cap(WValue recv) {
    return w_int(((WArray *)w_as_ptr(recv))->cap);
}

WValue w_array_leaf_ref_empty(WValue recv) {
    return ((WArray *)w_as_ptr(recv))->size == 0 ? W_TRUE : W_FALSE;
}

WValue w_array_leaf_ref_first(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    if (array->size == 0) return W_NIL;
    return w_array_idx(recv, w_int(0));
}

WValue w_array_leaf_ref_last(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    if (array->size == 0) return W_NIL;
    return w_array_idx(recv, w_int(array->size - 1));
}

/* 0 = immediate Int, signed limb count = BigInt, -99 = non-integer. */
WValue w_array_leaf_integer_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-99);
}

WValue w_array_leaf_dispose_integer(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

int64_t w_array_leaf_header_word(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    uint64_t word = (uint64_t)array->flags |
                    ((uint64_t)(uint8_t)array->ebits << 8) |
                    ((uint64_t)(uint32_t)array->start << 16);
    return (int64_t)word;
}

int64_t w_array_leaf_size_cap_word(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    uint64_t word = (uint64_t)(uint32_t)array->size |
                    ((uint64_t)(uint32_t)array->cap << 32);
    return (int64_t)word;
}

int64_t w_array_leaf_slots_word(WValue recv) {
    return (int64_t)(intptr_t)((WArray *)w_as_ptr(recv))->slots;
}

/* Consume an arbitrary decoded element without making BigInt-producing u64
 * cases leak in a timing loop. Other values contribute stable low WValue bits. */
WValue w_array_leaf_consume(WValue value) {
    uint64_t bits;
    if (w_is_bigint(value)) {
        bits = (uint64_t)w_to_i64(value);
        w_value_free(value);
    } else {
        bits = (uint64_t)value;
    }
    return w_int((int64_t)(bits & UINT64_C(0xFF)));
}

WValue w_array_leaf_thread_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) != 0) return w_int(-1);
    return w_int((int64_t)now.tv_sec * INT64_C(1000000000) + now.tv_nsec);
}

/* Benchmark-only native mirror and signed-header fixtures for Mmap#size. */

#include "runtime.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

extern void w_value_free(WValue value);

_Static_assert(W_TYPE_MMAP == 17, "Mmap type discriminator changed");
_Static_assert(offsetof(WMmap, type) == 0, "WMmap.type offset");
_Static_assert(offsetof(WMmap, closed) == 1, "WMmap.closed offset");
_Static_assert(offsetof(WMmap, pad) == 2, "WMmap.pad offset");
_Static_assert(offsetof(WMmap, data) == 8, "WMmap.data offset");
_Static_assert(offsetof(WMmap, size) == 16, "WMmap.size offset");
_Static_assert(sizeof(WMmap) == 24, "WMmap size");
_Static_assert(_Alignof(WMmap) == 8, "WMmap alignment");

static const int64_t W_BENCH_MMAP_SIZES[] = {
    INT64_C(0),
    INT64_C(1),
    INT64_C(7),
    INT64_C(255),
    INT64_C(4096),
    INT64_C(4294967295),
    INT64_C(4294967296),
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

WValue w_ref_mmap_size_relaxed(WValue recv) {
    return __w_mmap_length(recv);
}

WValue w_bench_mmap_size_relaxed_fixture(WValue selector) {
    int64_t index = w_as_int(selector);
    int64_t count = (int64_t)(sizeof(W_BENCH_MMAP_SIZES) /
                              sizeof(W_BENCH_MMAP_SIZES[0]));
    if (index < 0 || index >= count)
        w_raise(w_string("mmap-size relaxed fixture index out of bounds"));

    WMmap *m = (WMmap *)calloc(1, sizeof(WMmap));
    if (!m) w_raise(w_string("mmap-size relaxed fixture allocation failed"));
    m->type = W_TYPE_MMAP;
    m->size = W_BENCH_MMAP_SIZES[index];
    return w_box_ptr(m, W_SUBTAG_GENERIC);
}

int64_t w_bench_mmap_size_relaxed_raw(WValue recv) {
    return ((WMmap *)w_as_ptr(recv))->size;
}

WValue w_bench_mmap_size_relaxed_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-INT64_C(99));
}

WValue w_bench_mmap_size_relaxed_consume(WValue value) {
    int64_t raw = w_to_i64(value);
    if (w_is_bigint(value)) w_value_free(value);
    return w_int(raw & INT64_C(0xFF));
}

WValue w_bench_mmap_size_relaxed_dispose(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

WValue w_bench_mmap_size_relaxed_release(WValue recv) {
    free(w_as_ptr(recv));
    return W_NIL;
}

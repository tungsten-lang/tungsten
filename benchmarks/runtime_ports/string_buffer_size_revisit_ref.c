/* Benchmark-only mirror and signed-header fixtures for StringBuffer#size. */

#include "runtime.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

/* Compiler-generated cleanup calls this exported runtime symbol directly,
 * but it is intentionally absent from runtime.h's embedding surface. */
extern void w_value_free(WValue value);

static const int64_t W_BENCH_STRBUF_SIZES[] = {
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

WValue w_ref_strbuf_size(WValue recv) {
    return w_int(((WStrBuf *)w_as_ptr(recv))->size);
}

WValue w_bench_strbuf_size_fixture(WValue selector) {
    int64_t index = w_as_int(selector);
    int64_t count = (int64_t)(sizeof(W_BENCH_STRBUF_SIZES) /
                              sizeof(W_BENCH_STRBUF_SIZES[0]));
    if (index < 0 || index >= count)
        w_raise(w_string("StringBuffer-size fixture index out of bounds"));

    WStrBuf *sb = (WStrBuf *)calloc(1, sizeof(WStrBuf));
    if (!sb) w_raise(w_string("StringBuffer-size fixture allocation failed"));
    sb->data = (char *)malloc(1);
    if (!sb->data) {
        free(sb);
        w_raise(w_string("StringBuffer-size fixture data allocation failed"));
    }
    sb->flags = 0;
    sb->data[0] = '\0';
    sb->size = W_BENCH_STRBUF_SIZES[index];
    sb->cap = 1;
    return w_box_ptr(sb, W_SUBTAG_STRBUF);
}

int64_t w_bench_strbuf_raw_size(WValue recv) {
    return ((WStrBuf *)w_as_ptr(recv))->size;
}

/* 0 = immediate Int; otherwise the signed BigInt limb count. */
WValue w_bench_strbuf_size_repr(WValue value) {
    if (w_is_int(value)) return w_int(0);
    if (w_is_bigint(value)) return w_int(w_as_bigint(value)->size);
    return w_int(-INT64_C(99));
}

/* Overflow timing creates one canonical BigInt per call. Consume its low byte
 * and free it so the benchmark measures the method rather than heap growth. */
WValue w_bench_strbuf_size_consume(WValue value) {
    int64_t raw = w_to_i64(value);
    if (w_is_bigint(value)) w_value_free(value);
    return w_int(raw & INT64_C(0xFF));
}

WValue w_bench_strbuf_size_dispose(WValue value) {
    if (w_is_bigint(value)) w_value_free(value);
    return W_NIL;
}

WValue w_bench_strbuf_size_release(WValue value) {
    WStrBuf *sb = (WStrBuf *)w_as_ptr(value);
    free(sb->data);
    free(sb);
    return W_NIL;
}

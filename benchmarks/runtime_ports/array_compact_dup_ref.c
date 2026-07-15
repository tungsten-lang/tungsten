/*
 * Benchmark-only references for the current Array#compact and Array#dup ICs.
 *
 * w_array_idx is the exported form of the handlers' ebits-aware decoded load;
 * release LTO can inline it back into these loops. Keep every symbol here out
 * of the production runtime until an independently repeated public-method
 * trial clears the retention gate.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>

WValue w_ref_array_compact(WValue receiver) {
    WArray *source = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < source->size; i++) {
        WValue value = w_array_idx(receiver, w_int(i));
        if (value != W_NIL) w_array_push(result, value);
    }
    return result;
}

WValue w_ref_array_dup(WValue receiver) {
    WArray *source = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < source->size; i++)
        w_array_push(result, w_array_idx(receiver, w_int(i)));
    return result;
}

WValue w_bench_compact_dup_array_start(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->start);
}

WValue w_bench_compact_dup_array_cap(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->cap);
}

WValue w_bench_compact_dup_array_ebits(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->ebits);
}

WValue w_bench_compact_dup_array_flags(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->flags);
}

/* Timed loops retain a bounded batch of escaping results so neither source
 * nor C calls can be deleted. Free only the result headers/backing stores;
 * elements are shallow-borrowed from the long-lived workload input. */
WValue w_bench_compact_dup_release_batch(WValue batch_value,
                                         WValue count_value) {
    if (!w_is_array(batch_value)) abort();
    WArray *batch = (WArray *)w_as_ptr(batch_value);
    int64_t count = w_as_int(count_value);
    if (batch->ebits != 65 || count < 0 || count > batch->size) abort();

    for (int64_t i = 0; i < count; i++) {
        int64_t slot = (int64_t)batch->start + i;
        WValue value = batch->slots[slot];
        if (!w_is_array(value)) abort();
        WArray *result = (WArray *)w_as_ptr(value);
        if ((result->flags & W_FLAG_OWNED) == 0 ||
            (result->flags & W_FLAG_VIEW) != 0 || result->ebits != 65 ||
            result->start != 0) abort();
        free(result->slots);
        free(result);
        batch->slots[slot] = W_NIL;
    }
    return W_NIL;
}

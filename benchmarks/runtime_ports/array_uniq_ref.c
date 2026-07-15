/*
 * Benchmark-only reference for the current Array#uniq IC handler.
 *
 * The candidate keeps Array construction, decoded element access, equality,
 * and pushes at the same exported runtime boundaries that compiled Tungsten
 * uses. Keep every helper here out of production until a candidate passes its
 * correctness and timing gates.
 */

#include "runtime.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

/* The compiler already emits this runtime entry for large integer literals,
 * but it is intentionally not part of runtime.h's public surface. */
extern WValue w_bigint_from_dec_str(WValue text);

WValue w_ref_array_uniq(WValue receiver) {
    if (!w_is_array(receiver)) {
        (void)w_array_size(receiver);
        abort();
    }

    WArray *source = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    WArray *output = (WArray *)w_as_ptr(result);

    /* Both loop conditions reread live sizes, exactly like w_ic_array_uniq. */
    for (int32_t i = 0; i < source->size; i++) {
        WValue value = w_array_idx(receiver, w_int(i));
        int seen = 0;
        for (int32_t j = 0; j < output->size; j++) {
            if (w_eq(output->slots[output->start + j], value) == W_TRUE) {
                seen = 1;
                break;
            }
        }
        if (!seen) w_array_push(result, value);
    }
    return result;
}

WValue w_bench_uniq_nan(void) {
    return w_float(NAN);
}

WValue w_bench_uniq_bigint(void) {
    return w_bigint_from_dec_str(w_string("123456789012345678901234567890"));
}

WValue w_bench_uniq_rational(WValue numerator, WValue denominator) {
    return w_rational((int32_t)w_as_int(numerator),
                      (uint32_t)w_as_int(denominator));
}

WValue w_bench_uniq_ipv6(void) {
    return w_ipv6_parse(w_string("2001:db8::1/64"));
}

WValue w_bench_uniq_mac(void) {
    return w_mac_parse(w_string("02:11:22:33:44:55"));
}

WValue w_bench_uniq_array_start(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->start);
}

WValue w_bench_uniq_array_cap(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->cap);
}

WValue w_bench_uniq_array_ebits(WValue value) {
    return w_int(((WArray *)w_as_ptr(value))->ebits);
}

/* Results are ordinary owning polymorphic arrays. Timed loops retain a
 * bounded batch so allocation cannot be optimized away; release happens
 * outside each measured interval. Elements are borrowed from the input and
 * therefore are not owned or freed here. */
WValue w_bench_uniq_release_batch(WValue batch_value, WValue count_value) {
    if (!w_is_array(batch_value)) abort();
    WArray *batch = (WArray *)w_as_ptr(batch_value);
    int64_t count = w_as_int(count_value);
    if (batch->ebits != 65 || count < 0 || count > batch->size) abort();

    for (int64_t i = 0; i < count; i++) {
        int64_t slot = (int64_t)batch->start + i;
        WValue value = batch->slots[slot];
        if (!w_is_array(value)) abort();
        WArray *result = (WArray *)w_as_ptr(value);
        if ((result->flags & W_FLAG_OWNED) == 0 || result->ebits != 65) abort();
        free(result->slots);
        free(result);
        batch->slots[slot] = W_NIL;
    }
    return W_NIL;
}

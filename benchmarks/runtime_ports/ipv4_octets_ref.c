/*
 * Benchmark-only reference for the current IPv4#octets IC handler.
 *
 * Keep w_ref_ipv4_octets byte-for-byte equivalent in behavior to
 * runtime/runtime.c:w_ipv4_octets.  The release benchmark includes this file
 * through TUNGSTEN_C_INCLUDES; production runtime/core files stay untouched.
 */

#include "runtime.h"

#include <stdlib.h>

WValue w_ref_ipv4_octets(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    WValue arr = w_array_new_empty();
    uint32_t addr = w_unbox_ipv4_addr(ip);
    for (int i = 0; i < 4; i++)
        w_array_push(arr, w_int((addr >> (8 * (3 - i))) & 0xFF));
    return arr;
}

/*
 * Array-returning microbenchmarks otherwise retain every result until process
 * exit.  Release a bounded batch between timed regions so long measurements
 * neither exhaust memory nor accidentally benchmark pool recycling.  The
 * cleanup is deliberately outside clocked intervals and is identical for the
 * C, unique-source, and public paths.
 */
WValue w_ref_ipv4_octets_release_batch(WValue batch_v, WValue count_v) {
    if (!w_is_array(batch_v)) {
        w_raise(w_string("IPv4#octets benchmark batch is not an Array"));
        return W_NIL;
    }
    WArray *batch = (WArray *)w_as_ptr(batch_v);
    int64_t count = w_as_int(count_v);
    if (count < 0 || count > batch->size) {
        w_raise(w_string("IPv4#octets benchmark batch count is out of range"));
        return W_NIL;
    }

    for (int64_t i = 0; i < count; i++) {
        int64_t slot = (int64_t)batch->start + i;
        WValue value = batch->slots[slot];
        if (!w_is_array(value)) {
            w_raise(w_string("IPv4#octets benchmark result is not an Array"));
            return W_NIL;
        }
        WArray *out = (WArray *)w_as_ptr(value);
        if ((out->flags & W_FLAG_OWNED) == 0 ||
            (out->flags & W_FLAG_POOLED) != 0) {
            w_raise(w_string("IPv4#octets benchmark result is not an owned live Array"));
            return W_NIL;
        }
        free(out->slots);
        free(out);
        batch->slots[slot] = W_NIL;
    }
    return W_NIL;
}

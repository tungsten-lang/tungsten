/* In-process A/B driver for the generic and argc-zero cached dispatchers.
 *
 * The caches are thread-local, just like compiler-emitted @.ic slots, and are
 * distinct per target method.  Keeping both dispatch implementations in one
 * release binary permits balanced ABBA/BAAB timing without comparing builds.
 */

#include "runtime.h"

enum { W_BENCH_ZERO_ARG_SLOTS = 2 };

static _Thread_local WInlineCache generic_caches[W_BENCH_ZERO_ARG_SLOTS];
static _Thread_local WInlineCache zero_caches[W_BENCH_ZERO_ARG_SLOTS];

static int bench_slot(WValue slot_value) {
    int64_t slot = w_to_i64(slot_value);
    if (slot < 0 || slot >= W_BENCH_ZERO_ARG_SLOTS) return -1;
    return (int)slot;
}

WValue w_bench_zero_arg_generic(WValue recv, WValue name,
                                WValue iterations, WValue slot_value) {
    int slot = bench_slot(slot_value);
    if (slot < 0) return W_NIL;
    int64_t count = w_to_i64(iterations);
    WValue result = W_NIL;
    for (int64_t i = 0; i < count; i++)
        result = w_method_call_cached(recv, name, NULL, 0,
                                      &generic_caches[slot]);
    return result;
}

WValue w_bench_zero_arg_specialized(WValue recv, WValue name,
                                    WValue iterations, WValue slot_value) {
    int slot = bench_slot(slot_value);
    if (slot < 0) return W_NIL;
    int64_t count = w_to_i64(iterations);
    WValue result = W_NIL;
    for (int64_t i = 0; i < count; i++)
        result = w_method_call_cached_0(recv, name, &zero_caches[slot]);
    return result;
}

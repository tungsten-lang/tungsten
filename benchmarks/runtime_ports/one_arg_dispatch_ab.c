/* Dispatcher-only in-process A/B driver for the generic and argc-one cached
 * dispatchers.
 *
 * The narrow candidate is kept benchmark-local until both source-method and
 * native-wrapper cache shapes clear the runtime-port retention gate.  The
 * dispatch-key code and hit behavior intentionally mirror runtime.c so the
 * only measured variable is the one-argument dispatcher ABI.  The generic
 * leg deliberately builds its one-element argument array once, outside the
 * timed loop: this microbenchmark therefore excludes the production emitter's
 * per-call argument store and scratch-alloca savings.  Those belong in the
 * separate production-shaped benchmark.
 */

#include "runtime.h"

enum { W_BENCH_ONE_ARG_SLOTS = 10 };

static _Thread_local WInlineCache generic_caches[W_BENCH_ONE_ARG_SLOTS];
static _Thread_local WInlineCache one_caches[W_BENCH_ONE_ARG_SLOTS];

/* Hidden but externally linked runtime miss path. */
WValue w_method_call_slow(WValue recv, WValue name, WValue *args_ptr, int argc,
                          WInlineCache *cache, uint64_t key);

static inline uint64_t bench_dispatch_key(WValue v) {
    if (__builtin_expect(v < 0x10, 0)) return 0;
    uint64_t hi = v >> 48;
    if (hi == 0) {
        uint64_t subtag = v & 0xF;
        if (subtag == W_SUBTAG_INSTANCE) {
            WObject *obj = (WObject *)w_as_ptr(v);
            return 0x100000000ULL | (uint64_t)obj->class_id;
        }
        if (subtag == W_SUBTAG_CLASS) {
            WClass *klass = (WClass *)w_as_ptr(v);
            return 0x200000000ULL | (uint64_t)klass->class_id;
        }
        if (subtag == W_SUBTAG_GENERIC) {
            uint8_t type = *(uint8_t *)w_as_ptr(v);
            return 0x80u | (uint64_t)type;
        }
        return subtag;
    }
    if (hi < 0xFFF9) return 0xFF;
    if (hi == 0xFFFE) {
        uint64_t subtype = (v >> 45) & 0x7;
        if (subtype == W_PACKED_NODE)
            return 0x400000000ULL | (uint64_t)w_node_kind(v);
        return 0xE0u | subtype;
    }
    if (hi == 0xFFFC)
        return 0xD0u | (uint64_t)((v >> 46) & 0x3);
    return (uint64_t)(hi & 0xFF);
}

static inline WValue bench_method_call_cached_1(WValue recv, WValue name,
                                                 WValue arg,
                                                 WInlineCache *cache) {
    if (__builtin_expect(w_is_rope(recv), 0)) recv = w_rope_flatten(recv);

    uint64_t key = bench_dispatch_key(recv);
    if (__builtin_expect(key == cache->type_key && cache->fn_ptr != NULL, 1)) {
        if (cache->arity < 0)
            return ((WValue(*)(WValue, WValue *, int))cache->fn_ptr)(recv,
                                                                    &arg, 1);

        typedef WValue (*fn0)(WValue);
        typedef WValue (*fn1)(WValue, WValue);
        typedef WValue (*fn2)(WValue, WValue, WValue);
        typedef WValue (*fn3)(WValue, WValue, WValue, WValue);
        typedef WValue (*fn4)(WValue, WValue, WValue, WValue, WValue);

        if (__builtin_expect(cache->arity == 1, 1))
            return ((fn1)cache->fn_ptr)(recv, arg);

        switch (cache->arity) {
            case 0: return ((fn0)cache->fn_ptr)(recv);
            case 2: return ((fn2)cache->fn_ptr)(recv, arg, W_NIL);
            case 3: return ((fn3)cache->fn_ptr)(recv, arg, W_NIL, W_NIL);
            case 4: return ((fn4)cache->fn_ptr)(recv, arg, W_NIL, W_NIL,
                                                W_NIL);
            default: break;
        }
    }

    return w_method_call_slow(recv, name, &arg, 1, cache, key);
}

static int bench_slot(WValue slot_value) {
    int64_t slot = w_to_i64(slot_value);
    if (slot < 0 || slot >= W_BENCH_ONE_ARG_SLOTS) return -1;
    return (int)slot;
}

WValue w_bench_one_arg_generic(WValue recv, WValue name, WValue arg,
                               WValue iterations, WValue slot_value) {
    int slot = bench_slot(slot_value);
    if (slot < 0) return W_NIL;
    int64_t count = w_to_i64(iterations);
    /* Intentionally hoisted: keep this a dispatcher-only comparison. */
    WValue args[1] = {arg};
    WValue result = W_NIL;
    for (int64_t i = 0; i < count; i++)
        result = w_method_call_cached(recv, name, args, 1,
                                      &generic_caches[slot]);
    return result;
}

WValue w_bench_one_arg_specialized(WValue recv, WValue name, WValue arg,
                                   WValue iterations, WValue slot_value) {
    int slot = bench_slot(slot_value);
    if (slot < 0) return W_NIL;
    int64_t count = w_to_i64(iterations);
    WValue result = W_NIL;
    for (int64_t i = 0; i < count; i++)
        result = bench_method_call_cached_1(recv, name, arg,
                                            &one_caches[slot]);
    return result;
}

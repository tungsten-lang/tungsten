/*
 * Benchmark-only copies of the packed AST-body IC handlers removed from
 * runtime.c. They intentionally operate on the same W_PACKED_BODY receiver so
 * the paired benchmark compares method bodies, not representations.
 */

#include "runtime.h"

static uint32_t ref_offset(WValue body) { return w_unbox_body_offset(body); }
static uint32_t ref_size(WValue body) { return w_unbox_body_length(body); }
static WValue ref_get(WValue body, uint32_t i) {
    return w_body_arena_get(ref_offset(body), i);
}

WValue w_ref_body_size(WValue body) {
    return w_int((int64_t)ref_size(body));
}

WValue w_ref_body_read(WValue body, WValue index) {
    return w_array_get(body, index);
}

WValue w_ref_body_empty_p(WValue body) {
    return ref_size(body) == 0 ? W_TRUE : W_FALSE;
}

WValue w_ref_body_each(WValue body, WValue closure) {
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++)
        w_closure_call_1(closure, ref_get(body, i));
    return body;
}

WValue w_ref_body_map(WValue body, WValue closure) {
    WValue out = w_array_new_empty();
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++)
        w_array_push(out, w_closure_call_1(closure, ref_get(body, i)));
    return out;
}

WValue w_ref_body_select(WValue body, WValue closure) {
    WValue out = w_array_new_empty();
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++) {
        WValue value = ref_get(body, i);
        if (w_truthy(w_closure_call_1(closure, value))) w_array_push(out, value);
    }
    return out;
}

WValue w_ref_body_reject(WValue body, WValue closure) {
    WValue out = w_array_new_empty();
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++) {
        WValue value = ref_get(body, i);
        if (!w_truthy(w_closure_call_1(closure, value))) w_array_push(out, value);
    }
    return out;
}

WValue w_ref_body_find(WValue body, WValue closure) {
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++) {
        WValue value = ref_get(body, i);
        if (w_truthy(w_closure_call_1(closure, value))) return value;
    }
    return W_NIL;
}

WValue w_ref_body_any_p(WValue body, WValue closure) {
    uint32_t n = ref_size(body);
    if (w_is_closure(closure)) {
        for (uint32_t i = 0; i < n; i++)
            if (w_truthy(w_closure_call_1(closure, ref_get(body, i)))) return W_TRUE;
    } else {
        for (uint32_t i = 0; i < n; i++)
            if (w_truthy(ref_get(body, i))) return W_TRUE;
    }
    return W_FALSE;
}

WValue w_ref_body_all_p(WValue body, WValue closure) {
    uint32_t n = ref_size(body);
    if (w_is_closure(closure)) {
        for (uint32_t i = 0; i < n; i++)
            if (!w_truthy(w_closure_call_1(closure, ref_get(body, i)))) return W_FALSE;
    } else {
        for (uint32_t i = 0; i < n; i++)
            if (!w_truthy(ref_get(body, i))) return W_FALSE;
    }
    return W_TRUE;
}

WValue w_ref_body_none_p(WValue body, WValue closure) {
    uint32_t n = ref_size(body);
    if (w_is_closure(closure)) {
        for (uint32_t i = 0; i < n; i++)
            if (w_truthy(w_closure_call_1(closure, ref_get(body, i)))) return W_FALSE;
    } else {
        for (uint32_t i = 0; i < n; i++)
            if (w_truthy(ref_get(body, i))) return W_FALSE;
    }
    return W_TRUE;
}

WValue w_ref_body_reduce(WValue body, WValue init, WValue closure) {
    WValue acc = init;
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++)
        acc = w_closure_call_2(closure, acc, ref_get(body, i));
    return acc;
}

WValue w_ref_body_compact(WValue body) {
    WValue out = w_array_new_empty();
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++) {
        WValue value = ref_get(body, i);
        if (value != W_NIL) w_array_push(out, value);
    }
    return out;
}

WValue w_ref_body_dup(WValue body) {
    WValue out = w_array_new_empty();
    uint32_t n = ref_size(body);
    for (uint32_t i = 0; i < n; i++) w_array_push(out, ref_get(body, i));
    return out;
}

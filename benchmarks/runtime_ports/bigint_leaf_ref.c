/* Benchmark-only references for the current cheap BigInt IC handlers.
 *
 * Keep these bodies in lock-step with runtime/runtime.c. The case factory
 * intentionally includes the non-canonical size-zero representation so a
 * source predicate cannot assume every BigInt has at least one limb.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>

WValue w_ref_bigint_to_i(WValue recv) {
    return recv;
}

WValue w_ref_bigint_prev(WValue recv) {
    return w_sub(recv, w_int(1));
}

WValue w_ref_bigint_succ(WValue recv) {
    return w_add(recv, w_int(1));
}

WValue w_ref_bigint_zero_p(WValue recv) {
    return w_bool(w_as_bigint(recv)->size == 0);
}

WValue w_ref_bigint_even_p(WValue recv) {
    WBigint *b = w_as_bigint(recv);
    int32_t n = b->size < 0 ? -b->size : b->size;
    return w_bool(n == 0 || ((b->limbs[0] & 1ULL) == 0));
}

WValue w_ref_bigint_odd_p(WValue recv) {
    WBigint *b = w_as_bigint(recv);
    int32_t n = b->size < 0 ? -b->size : b->size;
    return w_bool(n > 0 && ((b->limbs[0] & 1ULL) != 0));
}

WValue w_ref_bigint_negative_p(WValue recv) {
    return w_bool(w_as_bigint(recv)->size < 0);
}

WValue w_ref_bigint_positive_p(WValue recv) {
    return w_bool(w_as_bigint(recv)->size > 0);
}

typedef struct {
    int32_t size;
    uint32_t cap;
    uint64_t limbs[4];
} RefBigintCase;

/* Sign, parity, normalization, 47/48/63/64/127/128/191/255-bit boundaries,
 * sparse limbs, and spare capacity. Every non-zero row is normalized. */
static const RefBigintCase REF_BIGINT_CASES[] = {
    { 0, 1, {0, 0, 0, 0}},
    { 1, 1, {UINT64_C(0x0000800000000000), 0, 0, 0}},
    { 1, 1, {UINT64_C(0x0000800000000001), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x0000800000000001), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x0000800000000002), 0, 0, 0}},
    { 1, 1, {UINT64_C(0x7FFFFFFFFFFFFFFF), 0, 0, 0}},
    { 1, 1, {UINT64_C(0x8000000000000000), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x8000000000000000), 0, 0, 0}},
    { 1, 1, {UINT64_C(0xFFFFFFFFFFFFFFFF), 0, 0, 0}},
    {-1, 1, {UINT64_C(0xFFFFFFFFFFFFFFFF), 0, 0, 0}},
    { 2, 2, {0, 1, 0, 0}},
    { 2, 2, {1, 1, 0, 0}},
    {-2, 2, {0, 1, 0, 0}},
    {-2, 2, {1, 1, 0, 0}},
    { 2, 2, {UINT64_MAX, UINT64_MAX, 0, 0}},
    {-2, 2, {UINT64_MAX, UINT64_MAX, 0, 0}},
    { 3, 3, {0, 0, 1, 0}},
    {-3, 3, {0, 0, 1, 0}},
    { 3, 4, {2, 0, UINT64_C(0x8000000000000000), 0}},
    {-3, 4, {2, 0, UINT64_C(0x8000000000000000), 0}},
    { 3, 3, {3, UINT64_MAX, 1, 0}},
    {-3, 3, {3, UINT64_MAX, 1, 0}},
    { 4, 4, {0, 0, 0, UINT64_C(0x8000000000000000)}},
    {-4, 4, {0, 0, 0, UINT64_C(0x8000000000000000)}},
    { 4, 4, {UINT64_MAX, 0, UINT64_MAX, UINT64_MAX}},
    {-4, 4, {UINT64_MAX, 0, UINT64_MAX, UINT64_MAX}},
};

WValue w_ref_bigint_leaf_case(WValue index_value) {
    int64_t index = w_as_int(index_value);
    int64_t count = (int64_t)(sizeof(REF_BIGINT_CASES) /
                              sizeof(REF_BIGINT_CASES[0]));
    if (index < 0 || index >= count) return W_NIL;

    const RefBigintCase *src = &REF_BIGINT_CASES[index];
    size_t bytes = sizeof(WBigint) + (size_t)src->cap * sizeof(uint64_t);
    bytes = (bytes + 15U) & ~(size_t)15U;
    WBigint *value = (WBigint *)calloc(1, bytes);
    if (value == NULL) abort();
    value->type = W_TYPE_BIGINT;
    value->size = src->size;
    value->cap = src->cap;
    for (uint32_t i = 0; i < src->cap; i++) value->limbs[i] = src->limbs[i];
    return w_box_ptr(value, W_SUBTAG_GENERIC);
}

WValue w_ref_bigint_value_p(WValue value) {
    return w_bool(w_is_bigint(value));
}

/* Stable numeric sink for freshly allocated prev/succ/next results. BigInts
 * are consumed here so long timing runs do not retain millions of temporary
 * arithmetic results; inline crossover results require no cleanup. */
WValue w_ref_bigint_consume_low_byte(WValue value) {
    if (w_is_int(value)) {
        int64_t signed_value = w_as_int(value);
        uint64_t magnitude = signed_value < 0
            ? 0ULL - (uint64_t)signed_value
            : (uint64_t)signed_value;
        return w_int((int64_t)(magnitude & UINT64_C(0xFF)));
    }
    WBigint *big = w_as_bigint(value);
    int64_t low = big->size == 0 ? 0 : (int64_t)(big->limbs[0] & UINT64_C(0xFF));
    free(big);
    return w_int(low);
}

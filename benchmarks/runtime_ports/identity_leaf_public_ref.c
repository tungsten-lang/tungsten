/* Matched-root support for the public Float#to_f / BigInt#to_i gate.
 *
 * The Float factory uses normal boxing for every ordinary IEEE input and
 * direct biased WValues for two positive raw NaN payloads. (A biased negative
 * NaN wraps into the heap-object dispatch range and is not a public Float
 * receiver.) The BigInt factory deliberately spans both signs, zero, spare
 * capacity, sparse values, and one through four limbs.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

WValue w_identity_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return w_int(-1);
    return w_int((int64_t)ts.tv_sec * INT64_C(1000000000) + ts.tv_nsec);
}

WValue w_identity_float_case(WValue index_value) {
    /* Every finite IEEE class and sign, both infinities, positive/negative
     * quiet and signaling NaN INPUTS (normal boxing canonicalizes them), two
     * dispatch-safe raw positive NaN payloads, and ordinary fractions. */
    static const uint64_t ieee_bits[] = {
        UINT64_C(0x0000000000000000), /* +0 */
        UINT64_C(0x8000000000000000), /* -0 */
        UINT64_C(0x0000000000000001), /* +minimum subnormal */
        UINT64_C(0x8000000000000001), /* -minimum subnormal */
        UINT64_C(0x000FFFFFFFFFFFFF), /* +maximum subnormal */
        UINT64_C(0x800FFFFFFFFFFFFF), /* -maximum subnormal */
        UINT64_C(0x0010000000000000), /* +minimum normal */
        UINT64_C(0x8010000000000000), /* -minimum normal */
        UINT64_C(0x3FF0000000000000), /* +1 */
        UINT64_C(0xBFF0000000000000), /* -1 */
        UINT64_C(0x7FEFFFFFFFFFFFFF), /* +maximum finite */
        UINT64_C(0xFFEFFFFFFFFFFFFF), /* -maximum finite */
        UINT64_C(0x7FF8000000000001), /* +quiet NaN input */
        UINT64_C(0xFFF8000000000001), /* -quiet NaN input */
        UINT64_C(0x7FF0000000000001), /* +signaling NaN input */
        UINT64_C(0xFFF0000000000001), /* -signaling NaN input */
        UINT64_C(0x7FF0000000000000), /* +infinity */
        UINT64_C(0xFFF0000000000000), /* -infinity */
        UINT64_C(0x7FF8000000001234), /* raw +quiet NaN payload */
        UINT64_C(0x7FF0000000001234), /* raw +signaling NaN payload */
        UINT64_C(0x3FF8000000000000), /* +1.5 */
        UINT64_C(0xBFF8000000000000), /* -1.5 */
    };
    int64_t index = w_as_int(index_value);
    int64_t count = (int64_t)(sizeof(ieee_bits) / sizeof(ieee_bits[0]));
    if (index < 0 || index >= count) return W_NIL;

    if (index == 18 || index == 19) {
        WValue encoded = ieee_bits[index] + W_DOUBLE_BIAS;
        if (!w_is_double(encoded) || (encoded >> 48) == 0) abort();
        return encoded;
    }
    double value;
    memcpy(&value, &ieee_bits[index], sizeof(value));
    return w_box_double(value);
}

WValue w_identity_float_p(WValue value) {
    return w_bool(w_is_double(value));
}

typedef struct {
    int32_t size;
    uint32_t cap;
    uint64_t limbs[4];
} IdentityBigintCase;

/* Sign, parity, normalization, 47/48/63/64/127/128/191/255-bit boundaries,
 * sparse limbs, spare capacity, and the noncanonical heap-zero case. The
 * final noncanonical heap-2 sentinel is reserved for the bounded trailing-
 * block probe and is not part of the 26-case correctness/timing corpus. */
static const IdentityBigintCase IDENTITY_BIGINT_CASES[] = {
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
    { 1, 1, {2, 0, 0, 0}},
};

WValue w_identity_bigint_case(WValue index_value) {
    int64_t index = w_as_int(index_value);
    int64_t count = (int64_t)(sizeof(IDENTITY_BIGINT_CASES) /
                              sizeof(IDENTITY_BIGINT_CASES[0]));
    if (index < 0 || index >= count) return W_NIL;

    const IdentityBigintCase *src = &IDENTITY_BIGINT_CASES[index];
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

WValue w_identity_bigint_p(WValue value) {
    return w_bool(w_is_bigint(value));
}

WValue w_identity_bigint_size(WValue value) {
    if (!w_is_bigint(value)) return W_NIL;
    return w_int(w_as_bigint(value)->size);
}

WValue w_identity_bigint_capacity(WValue value) {
    if (!w_is_bigint(value)) return W_NIL;
    return w_int(w_as_bigint(value)->cap);
}

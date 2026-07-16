/* Public native-IC/source gate fixtures for the five cheap BigInt predicates.
 *
 * The table intentionally includes canonical values, spare capacity, a
 * size-zero allocation with no limb storage, and structurally noncanonical
 * headers. The latter are not produced by arithmetic, but the native ICs are
 * simple representation predicates; preserving their behavior prevents a
 * source port from silently adding normalization assumptions.
 */

#include "runtime.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

_Static_assert(offsetof(WBigint, size) == 4, "WBigint.size offset changed");
_Static_assert(offsetof(WBigint, cap) == 8, "WBigint.cap offset changed");
_Static_assert(offsetof(WBigint, limbs) == 16, "WBigint.limbs offset changed");

typedef struct {
    int32_t size;
    uint32_t cap;
    uint64_t limbs[4];
} BigPredCase;

/* Indices are grouped/documented in bigint_predicate_relaxed_public.w. */
static const BigPredCase BIGPRED_CASES[] = {
    /* size-zero: no storage, odd garbage, and wider spare storage. */
    { 0, 0, {0, 0, 0, 0}},
    { 0, 1, {UINT64_C(0xffffffffffffffff), 0, 0, 0}},
    { 0, 4, {UINT64_C(0xaaaaaaaaaaaaaaaa), 1, 2, 3}},

    /* One-limb positive/negative; 48/63/64-bit and parity boundaries. */
    { 1, 1, {UINT64_C(0x0000800000000000), 0, 0, 0}},
    { 1, 1, {UINT64_C(0x0000800000000001), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x0000800000000002), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x0000800000000003), 0, 0, 0}},
    { 1, 1, {UINT64_C(0x8000000000000000), 0, 0, 0}},
    { 1, 1, {UINT64_C(0xffffffffffffffff), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x8000000000000000), 0, 0, 0}},
    {-1, 1, {UINT64_C(0xffffffffffffffff), 0, 0, 0}},

    /* Two through four limbs, both signs and both low-limb parities. */
    { 2, 2, {0, 1, 0, 0}},
    { 2, 2, {1, 1, 0, 0}},
    {-2, 2, {2, UINT64_MAX, 0, 0}},
    {-2, 2, {3, UINT64_MAX, 0, 0}},
    { 3, 3, {2, 0, 1, 0}},
    { 3, 3, {3, UINT64_MAX, 1, 0}},
    {-3, 3, {4, 0, UINT64_C(0x8000000000000000), 0}},
    {-3, 3, {5, 0, UINT64_C(0x8000000000000000), 0}},
    { 4, 4, {6, 0, 0, 1}},
    { 4, 4, {7, UINT64_MAX, 0, UINT64_MAX}},
    {-4, 4, {8, 0, 0, UINT64_C(0x8000000000000000)}},
    {-4, 4, {9, UINT64_MAX, 0, UINT64_C(0x8000000000000000)}},

    /* Spare capacity. */
    { 1, 4, {UINT64_C(0x0000800000000002), 11, 12, 13}},
    {-1, 4, {UINT64_C(0x0000800000000003), 21, 22, 23}},
    { 3, 4, {10, 0, 1, 31}},
    {-3, 4, {11, 0, 1, 41}},

    /* Noncanonical nonzero headers. The C ICs use signed size and limb 0
     * literally; they do not normalize a zero/leading-zero magnitude. */
    { 1, 1, {0, 0, 0, 0}},
    {-1, 1, {0, 0, 0, 0}},
    { 2, 2, {1, 0, 0, 0}},
    {-2, 2, {2, 0, 0, 0}},
    { 4, 4, {13, 0, 0, 0}},
};

enum { BIGPRED_CASE_COUNT = (int)(sizeof(BIGPRED_CASES) / sizeof(BIGPRED_CASES[0])) };

WValue w_bigpred_fixture(WValue index_value) {
    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= BIGPRED_CASE_COUNT) return W_NIL;
    const BigPredCase *src = &BIGPRED_CASES[index];
    size_t bytes = sizeof(WBigint) + (size_t)src->cap * sizeof(uint64_t);
    bytes = (bytes + 15U) & ~(size_t)15U;
    WBigint *value = (WBigint *)calloc(1, bytes);
    if (value == NULL) abort();
    value->type = W_TYPE_BIGINT;
    value->size = src->size;
    value->cap = src->cap;
    for (uint32_t i = 0; i < src->cap; ++i) value->limbs[i] = src->limbs[i];
    return w_box_ptr(value, W_SUBTAG_GENERIC);
}

/* bit 0 zero, bit 1 even, bit 2 odd, bit 3 negative, bit 4 positive. */
WValue w_bigpred_reference_mask(WValue value) {
    WBigint *b = w_as_bigint(value);
    int32_t n = b->size < 0 ? -b->size : b->size;
    unsigned mask = 0;
    if (b->size == 0) mask |= 1U;
    if (n == 0 || ((b->limbs[0] & 1ULL) == 0)) mask |= 2U;
    if (n > 0 && ((b->limbs[0] & 1ULL) != 0)) mask |= 4U;
    if (b->size < 0) mask |= 8U;
    if (b->size > 0) mask |= 16U;
    return w_int((int64_t)mask);
}

WValue w_bigpred_fixture_matches(WValue value, WValue index_value) {
    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= BIGPRED_CASE_COUNT || !w_is_bigint(value))
        return W_FALSE;
    WBigint *got = w_as_bigint(value);
    const BigPredCase *want = &BIGPRED_CASES[index];
    if (got->type != W_TYPE_BIGINT || got->size != want->size || got->cap != want->cap)
        return W_FALSE;
    for (uint32_t i = 0; i < want->cap; ++i)
        if (got->limbs[i] != want->limbs[i]) return W_FALSE;
    return W_TRUE;
}

WValue w_bigpred_case_count(void) {
    return w_int(BIGPRED_CASE_COUNT);
}

WValue w_bigpred_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) abort();
    uint64_t ns = (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
    return w_u64(ns);
}

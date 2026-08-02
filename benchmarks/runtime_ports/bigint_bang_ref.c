/* Stable fixtures, controls, and observation barrier for BigInt#neg!/abs!.
 * The controls intentionally mirror the pre-port C handlers byte-for-byte at
 * the arithmetic boundary: both operations mutate only WBigint.size.
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
} BigBangCase;

static const BigBangCase BIGBANG_CASES[] = {
    { 1, 1, {UINT64_C(0x0000800000000001), 0, 0, 0}},
    {-1, 1, {UINT64_C(0x0000800000000002), 0, 0, 0}},
    { 1, 1, {UINT64_C(0xffffffffffffffff), 0, 0, 0}},
    {-1, 1, {UINT64_C(0xffffffffffffffff), 0, 0, 0}},
    { 2, 2, {1, 1, 0, 0}},
    {-2, 2, {2, UINT64_MAX, 0, 0}},
    { 2, 4, {3, UINT64_MAX, 91, 92}},
    {-2, 4, {4, UINT64_MAX, 93, 94}},
    { 3, 3, {5, 0, 1, 0}},
    {-3, 3, {6, 0, UINT64_C(0x8000000000000000), 0}},
    { 3, 4, {7, UINT64_MAX, 1, 95}},
    {-3, 4, {8, UINT64_MAX, UINT64_MAX, 96}},
    { 4, 4, {9, 0, 0, 1}},
    {-4, 4, {10, 0, 0, UINT64_C(0x8000000000000000)}},
    { 4, 4, {11, UINT64_MAX, 0, UINT64_MAX}},
    {-4, 4, {12, UINT64_MAX, UINT64_MAX, UINT64_MAX}},
};

enum { BIGBANG_CASE_COUNT =
    (int)(sizeof(BIGBANG_CASES) / sizeof(BIGBANG_CASES[0])) };

WValue w_bigbang_fixture(WValue index_value) {
    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= BIGBANG_CASE_COUNT) return W_NIL;
    const BigBangCase *src = &BIGBANG_CASES[index];
    size_t bytes = sizeof(WBigint) + (size_t)src->cap * sizeof(uint64_t);
    bytes = (bytes + 15U) & ~(size_t)15U;
    WBigint *value = (WBigint *)calloc(1, bytes);
    if (value == NULL) abort();
    value->type = W_TYPE_BIGINT;
    value->size = src->size;
    value->cap = src->cap;
    for (uint32_t i = 0; i < src->cap; ++i) value->limbs[i] = src->limbs[i];
    return w_box_ptr(value, W_SUBTAG_BIGINT);
}

WValue w_bigbang_case_count(void) {
    return w_int(BIGBANG_CASE_COUNT);
}

WValue w_bigbang_expected_size(WValue index_value) {
    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= BIGBANG_CASE_COUNT) return W_NIL;
    return w_int(BIGBANG_CASES[index].size);
}

WValue w_bigbang_signed_size(WValue value) {
    if (!w_is_bigint(value)) abort();
    return w_int(w_as_bigint(value)->size);
}

WValue w_bigbang_set_size(WValue value, WValue size_value) {
    if (!w_is_bigint(value)) abort();
    int64_t size = w_as_int(size_value);
    if (size < INT32_MIN || size > INT32_MAX) abort();
    w_as_bigint(value)->size = (int32_t)size;
    return value;
}

WValue w_bigbang_c_neg(WValue value) {
    WBigint *b = w_as_bigint(value);
    b->size = -b->size;
    return value;
}

WValue w_bigbang_c_abs(WValue value) {
    WBigint *b = w_as_bigint(value);
    if (b->size < 0) b->size = -b->size;
    return value;
}

/* Noinline observation makes every mutation externally visible to LLVM while
 * imposing the same small call cost on the C, source, and public lanes. */
__attribute__((noinline))
WValue w_bigbang_observe(WValue value) {
    if (!w_is_bigint(value)) abort();
    return w_int(w_as_bigint(value)->size);
}

WValue w_bigbang_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) abort();
    uint64_t ns = (uint64_t)ts.tv_sec * UINT64_C(1000000000) +
                  (uint64_t)ts.tv_nsec;
    return w_u64(ns);
}

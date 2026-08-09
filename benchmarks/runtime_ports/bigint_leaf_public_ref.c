/* Benchmark-only observers for the true-public BigInt#prev/succ/next
 * campaign. These are identical in the before (IC-installed) and after
 * (source-dispatch) builds and are never themselves the measured path.
 *
 * The consume sink frees each fresh arithmetic result so 10M+ iteration
 * legs keep a flat heap; results are ordinary malloc-backed WBigint
 * buffers (or inline i48 ints at the demotion crossover), so libc free
 * is the correct disposal on both sides of the port. */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <time.h>

__attribute__((noinline))
WValue w_leafpub_consume_low_byte(WValue value) {
    if (w_is_int(value)) {
        int64_t signed_value = w_as_int(value);
        uint64_t magnitude = signed_value < 0
            ? 0ULL - (uint64_t)signed_value
            : (uint64_t)signed_value;
        return w_int((int64_t)(magnitude & UINT64_C(0xFF)));
    }
    if (!w_is_bigint(value)) abort();
    WBigint *big = w_as_bigint(value);
    int64_t low = big->size == 0 ? 0 : (int64_t)(big->limbs[0] & UINT64_C(0xFF));
    free(big);
    return w_int(low);
}

/* Identity-result sink for alias-return benchmarks. Unlike the fresh-result
 * sink above, this must honor BigInt's shared-count handoff instead of freeing
 * the receiver's storage directly. */
void w_value_free(WValue value);

__attribute__((noinline))
WValue w_leafpub_consume_alias_low_byte(WValue value) {
    if (!w_is_bigint(value)) abort();
    WBigint *big = w_as_bigint(value);
    int64_t low = big->size == 0 ? 0 : (int64_t)(big->limbs[0] & UINT64_C(0xFF));
    w_value_free(value);
    return w_int(low);
}

WValue w_leafpub_is_bigint(WValue value) {
    return w_bool(w_is_bigint(value));
}

WValue w_leafpub_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) abort();
    uint64_t ns = (uint64_t)ts.tv_sec * UINT64_C(1000000000) +
                  (uint64_t)ts.tv_nsec;
    return w_u64(ns);
}

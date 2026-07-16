/* Matched-root reference support for Float#floor/#ceil/#round/#sqrt/#sq. */

#include "runtime.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

WValue w_float_remaining_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return w_int(-1);
    return w_int((int64_t)ts.tv_sec * INT64_C(1000000000) + ts.tv_nsec);
}

WValue w_float_remaining_case(WValue index_value) {
    /* Signed zeros/subnormals/normals, tie points, i48/i64 conversion
     * boundaries, finite extremes, infinities, canonicalized NaN inputs, and
     * two dispatch-safe positive raw NaN payloads. */
    static const uint64_t bits[] = {
        UINT64_C(0x0000000000000000), /* +0 */
        UINT64_C(0x8000000000000000), /* -0 */
        UINT64_C(0x0000000000000001), /* +minimum subnormal */
        UINT64_C(0x8000000000000001), /* -minimum subnormal */
        UINT64_C(0x000FFFFFFFFFFFFF), /* +maximum subnormal */
        UINT64_C(0x800FFFFFFFFFFFFF), /* -maximum subnormal */
        UINT64_C(0x0010000000000000), /* +minimum normal */
        UINT64_C(0x8010000000000000), /* -minimum normal */
        UINT64_C(0x3FD0000000000000), /* +0.25 */
        UINT64_C(0xBFD0000000000000), /* -0.25 */
        UINT64_C(0x3FE0000000000000), /* +0.5 */
        UINT64_C(0xBFE0000000000000), /* -0.5 */
        UINT64_C(0x3FF8000000000000), /* +1.5 */
        UINT64_C(0xBFF8000000000000), /* -1.5 */
        UINT64_C(0x4004000000000000), /* +2.5 */
        UINT64_C(0xC004000000000000), /* -2.5 */
        UINT64_C(0x400D99999999999A), /* +3.7 */
        UINT64_C(0xC00D99999999999A), /* -3.7 */
        UINT64_C(0x42DFFFFFFFFFFFF0), /* +(2^47 - 0.25) */
        UINT64_C(0x42E0000000000000), /* +2^47 */
        UINT64_C(0xC2E0000000000000), /* -2^47 */
        UINT64_C(0xC2E0000000000010), /* -(2^47 + 0.5) */
        UINT64_C(0x43E0000000000000), /* +2^63 */
        UINT64_C(0xC3E0000000000000), /* -2^63 */
        UINT64_C(0x7FEFFFFFFFFFFFFF), /* +maximum finite */
        UINT64_C(0xFFEFFFFFFFFFFFFF), /* -maximum finite */
        UINT64_C(0x7FF0000000000000), /* +infinity */
        UINT64_C(0xFFF0000000000000), /* -infinity */
        UINT64_C(0x7FF8000000000001), /* quiet NaN input */
        UINT64_C(0x7FF0000000000001), /* signaling NaN input */
        UINT64_C(0x7FF8000000001234), /* raw quiet NaN payload */
        UINT64_C(0x7FF0000000001234), /* raw signaling NaN payload */
    };
    int64_t index = w_as_int(index_value);
    int64_t count = (int64_t)(sizeof(bits) / sizeof(bits[0]));
    if (index < 0 || index >= count) return W_NIL;

    if (index >= 30) {
        WValue encoded = bits[index] + W_DOUBLE_BIAS;
        if (!w_is_double(encoded) || (encoded >> 48) == 0) abort();
        return encoded;
    }

    double value;
    memcpy(&value, &bits[index], sizeof(value));
    return w_box_double(value);
}

WValue w_float_remaining_float_p(WValue value) {
    return w_bool(w_is_double(value));
}

WValue w_float_remaining_integer_p(WValue value) {
    return w_bool(w_is_integer_any(value));
}

WValue w_float_remaining_ref_floor(WValue value) {
    return w_int((int64_t)floor(w_as_double(value)));
}

WValue w_float_remaining_ref_ceil(WValue value) {
    return w_int((int64_t)ceil(w_as_double(value)));
}

WValue w_float_remaining_ref_round(WValue value) {
    return w_int((int64_t)round(w_as_double(value)));
}

WValue w_float_remaining_ref_sqrt(WValue value) {
    return w_box_double(sqrt(w_as_double(value)));
}

WValue w_float_remaining_ref_sq(WValue value) {
    return w_mul(value, value);
}

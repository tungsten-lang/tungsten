/* Benchmark-only reference for the current Float#abs IC handler.
 *
 * Keep w_ref_float_abs in lock-step with w_ic_float_abs in runtime/runtime.c.
 * The case helpers cover every IEEE-754 category and also two non-canonical
 * positive NaN WValues.  Those raw values are accepted by w_is_double and
 * therefore expose an important representation rule: Float#abs must retain
 * w_box_double's canonical-NaN result, not merely clear the IEEE sign bit.
 */

#include "runtime.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

#define REF_FLOAT_ABS_CASE_COUNT 22

WValue w_ref_float_abs(WValue recv) {
    return w_box_double(fabs(w_as_double(recv)));
}

static WValue ref_box_ieee(uint64_t bits) {
    double value;
    memcpy(&value, &bits, sizeof(value));
    return w_box_double(value);
}

WValue w_ref_float_abs_case(WValue index_value) {
    static const uint64_t ieee_bits[REF_FLOAT_ABS_CASE_COUNT] = {
        UINT64_C(0x0000000000000000), /* +0 */
        UINT64_C(0x8000000000000000), /* -0 */
        UINT64_C(0x0000000000000001), /* least positive subnormal */
        UINT64_C(0x8000000000000001), /* least negative subnormal */
        UINT64_C(0x000FFFFFFFFFFFFF), /* greatest positive subnormal */
        UINT64_C(0x800FFFFFFFFFFFFF), /* greatest negative subnormal */
        UINT64_C(0x0010000000000000), /* least positive normal */
        UINT64_C(0x8010000000000000), /* least negative normal */
        UINT64_C(0x3FF0000000000000), /* +1 */
        UINT64_C(0xBFF0000000000000), /* -1 */
        UINT64_C(0x7FEFFFFFFFFFFFFF), /* greatest positive finite */
        UINT64_C(0xFFEFFFFFFFFFFFFF), /* greatest negative finite */
        UINT64_C(0x7FF8000000000001), /* positive quiet NaN */
        UINT64_C(0xFFF8000000000001), /* negative quiet NaN */
        UINT64_C(0x7FF0000000000001), /* positive signaling NaN */
        UINT64_C(0xFFF0000000000001), /* negative signaling NaN */
        UINT64_C(0x7FF0000000000000), /* +infinity */
        UINT64_C(0xFFF0000000000000), /* -infinity */
        UINT64_C(0x7FF8000000001234), /* raw positive qNaN payload */
        UINT64_C(0x7FF0000000001234), /* raw positive sNaN payload */
        UINT64_C(0x3FF8000000000000), /* +1.5 */
        UINT64_C(0xBFF8000000000000), /* -1.5 */
    };

    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= REF_FLOAT_ABS_CASE_COUNT) return W_NIL;

    /* Normal construction deliberately canonicalizes the four signed/payload
     * NaNs above.  The last two NaN cases bypass construction so correctness
     * also covers every raw positive-NaN word accepted as a Float WValue. */
    if (index == 18 || index == 19) {
        WValue raw = ieee_bits[index] + W_DOUBLE_BIAS;
        if (!w_is_double(raw)) return W_NIL;
        return raw;
    }
    return ref_box_ieee(ieee_bits[index]);
}

WValue w_ref_float_abs_expected(WValue index_value) {
    static const uint64_t expected_ieee[REF_FLOAT_ABS_CASE_COUNT] = {
        UINT64_C(0x0000000000000000), UINT64_C(0x0000000000000000),
        UINT64_C(0x0000000000000001), UINT64_C(0x0000000000000001),
        UINT64_C(0x000FFFFFFFFFFFFF), UINT64_C(0x000FFFFFFFFFFFFF),
        UINT64_C(0x0010000000000000), UINT64_C(0x0010000000000000),
        UINT64_C(0x3FF0000000000000), UINT64_C(0x3FF0000000000000),
        UINT64_C(0x7FEFFFFFFFFFFFFF), UINT64_C(0x7FEFFFFFFFFFFFFF),
        UINT64_C(0x7FF8000000000000), UINT64_C(0x7FF8000000000000),
        UINT64_C(0x7FF8000000000000), UINT64_C(0x7FF8000000000000),
        UINT64_C(0x7FF0000000000000), UINT64_C(0x7FF0000000000000),
        UINT64_C(0x7FF8000000000000), UINT64_C(0x7FF8000000000000),
        UINT64_C(0x3FF8000000000000), UINT64_C(0x3FF8000000000000),
    };

    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= REF_FLOAT_ABS_CASE_COUNT) return W_NIL;
    return ref_box_ieee(expected_ieee[index]);
}

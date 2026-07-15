/* Benchmark-only reference for the current Float#infinite? IC handler.
 *
 * w_ref_float_infinite_p deliberately preserves the production handler's
 * exact isinf(w_as_double(...)) classification.  The corpus helper constructs
 * exact IEEE-754 cases outside the timed region; w_box_double also exercises
 * the runtime's canonical-NaN representation.
 */

#include "runtime.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

WValue w_ref_float_infinite_p(WValue recv) {
    return w_bool(isinf(w_as_double(recv)));
}

WValue w_ref_float_infinite_case(WValue index_value) {
    static const uint64_t ieee_bits[] = {
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
    };

    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= (int64_t)(sizeof(ieee_bits) / sizeof(ieee_bits[0])))
        return W_NIL;

    double value;
    memcpy(&value, &ieee_bits[index], sizeof(value));
    return w_box_double(value);
}

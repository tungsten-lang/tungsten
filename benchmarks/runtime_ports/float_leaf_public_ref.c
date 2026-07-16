#include "runtime.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

WValue w_ref_float_leaf_abs(WValue recv) {
    return w_box_double(fabs(w_as_double(recv)));
}

WValue w_ref_float_leaf_nan_p(WValue recv) {
    return w_bool(isnan(w_as_double(recv)));
}

WValue w_ref_float_leaf_infinite_p(WValue recv) {
    return w_bool(isinf(w_as_double(recv)));
}

WValue w_ref_float_leaf_case(WValue index_value) {
    static const uint64_t ieee_bits[] = {
        UINT64_C(0x0000000000000000), UINT64_C(0x8000000000000000),
        UINT64_C(0x0000000000000001), UINT64_C(0x8000000000000001),
        UINT64_C(0x000FFFFFFFFFFFFF), UINT64_C(0x800FFFFFFFFFFFFF),
        UINT64_C(0x0010000000000000), UINT64_C(0x8010000000000000),
        UINT64_C(0x3FF0000000000000), UINT64_C(0xBFF0000000000000),
        UINT64_C(0x7FEFFFFFFFFFFFFF), UINT64_C(0xFFEFFFFFFFFFFFFF),
        UINT64_C(0x7FF8000000000001), UINT64_C(0xFFF8000000000001),
        UINT64_C(0x7FF0000000000001), UINT64_C(0xFFF0000000000001),
        UINT64_C(0x7FF0000000000000), UINT64_C(0xFFF0000000000000),
        UINT64_C(0x7FF8000000001234), UINT64_C(0x7FF0000000001234),
        UINT64_C(0x3FF8000000000000), UINT64_C(0xBFF8000000000000),
    };
    int64_t index = w_as_int(index_value);
    if (index < 0 || index >= (int64_t)(sizeof(ieee_bits) / sizeof(ieee_bits[0])))
        return W_NIL;
    if (index == 18 || index == 19) {
        WValue raw = ieee_bits[index] + W_DOUBLE_BIAS;
        return w_is_double(raw) ? raw : W_NIL;
    }
    double value;
    memcpy(&value, &ieee_bits[index], sizeof(value));
    return w_box_double(value);
}

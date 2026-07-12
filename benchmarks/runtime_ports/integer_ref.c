/* Benchmark-only copies of the Integer IC leaf handlers removed from
 * runtime.c. These are called through Tungsten methods so both sides pay the
 * same type-class dispatch/cache cost. */

#include "runtime.h"

#define REF_I48_MIN (-140737488355328LL)
#define REF_I48_MAX ( 140737488355327LL)

static WValue ref_box_i48_checked(int64_t value) {
    if (value >= REF_I48_MIN && value <= REF_I48_MAX) return w_int(value);
    /* Reuse the exact promotion path at the two crossover points. */
    return value < REF_I48_MIN
        ? w_sub(w_int(REF_I48_MIN), w_int(1))
        : w_add(w_int(REF_I48_MAX), w_int(1));
}

WValue w_ref_integer_prev(WValue recv) {
    return ref_box_i48_checked(w_as_int(recv) - 1);
}

WValue w_ref_integer_succ(WValue recv) {
    return ref_box_i48_checked(w_as_int(recv) + 1);
}

WValue w_ref_integer_zero_p(WValue recv) {
    return w_bool(w_as_int(recv) == 0);
}

WValue w_ref_integer_even_p(WValue recv) {
    return w_bool((w_as_int(recv) & 1) == 0);
}

WValue w_ref_integer_odd_p(WValue recv) {
    return w_bool((w_as_int(recv) & 1) != 0);
}

WValue w_ref_integer_negative_p(WValue recv) {
    return w_bool(w_as_int(recv) < 0);
}

WValue w_ref_integer_positive_p(WValue recv) {
    return w_bool(w_as_int(recv) > 0);
}

WValue w_ref_integer_sq(WValue recv) {
    return w_mul(recv, recv);
}

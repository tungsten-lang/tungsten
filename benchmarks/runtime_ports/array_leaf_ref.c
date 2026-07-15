/* Benchmark-only references for the current Array IC leaf handlers.
 *
 * Keep these out of the production runtime: array_leaf_ab.w calls them through
 * class methods so the C and Tungsten candidates have the same outer method
 * dispatch shape.  The bodies mirror w_ic_array_{length,cap,empty,first,last}
 * in runtime/runtime.c.  w_array_idx is the exported form of the same
 * ebits-aware decoded load used by the first/last IC leaves; full LTO in the
 * benchmark inlines it back into the reference body.
 */

#include "runtime.h"

WValue w_ref_array_leaf_size(WValue recv) {
    return w_array_size(recv);
}

WValue w_ref_array_leaf_cap(WValue recv) {
    return w_int(((WArray *)w_as_ptr(recv))->cap);
}

WValue w_ref_array_leaf_empty_p(WValue recv) {
    return ((WArray *)w_as_ptr(recv))->size == 0 ? W_TRUE : W_FALSE;
}

WValue w_ref_array_leaf_first(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    if (array->size == 0) return W_NIL;
    return w_array_idx(recv, w_int(0));
}

WValue w_ref_array_leaf_last(WValue recv) {
    WArray *array = (WArray *)w_as_ptr(recv);
    if (array->size == 0) return W_NIL;
    return w_array_idx(recv, w_int(array->size - 1));
}

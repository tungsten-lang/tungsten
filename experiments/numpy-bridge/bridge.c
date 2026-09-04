/* Optional ABI adapter for the proof of concept, not a Core dependency.
 * Mmap.as_f64 returns a BigArray. Raw f64[] kernels use ordinary WArray
 * headers. Borrow the same mapped pages after checking the 32-bit size bound.
 * The caller owns the mapping and must keep it open until the kernel returns.
 */
#include "runtime.h"
#include <limits.h>

WValue tungsten_numpy_f64_view(WValue mapping) {
    if (!w_is_mmap(mapping)) {
        w_raise(w_string("NumPy input must be an Mmap"));
        return W_NIL;
    }
    WMmap *m = (WMmap *)w_as_ptr(mapping);
    if (m->closed || m->size <= 0 || m->size % 8 != 0 || m->size / 8 > INT_MAX) {
        w_raise(w_string("NumPy input requires an open aligned f64 mapping within Array limits"));
        return W_NIL;
    }
    WValue result = w_array_view_raw((uint8_t *)m->data, -64, m->size / 8);
    w_as_array(result)->flags |= W_FLAG_FROZEN;
    return result;
}

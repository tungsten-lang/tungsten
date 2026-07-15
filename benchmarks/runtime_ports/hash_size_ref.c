/* Benchmark-only mirror of the current Hash#size IC handler. */

#include "runtime.h"

WValue w_ref_hash_size(WValue recv) {
    return w_int(((WHash *)w_as_ptr(recv))->count);
}

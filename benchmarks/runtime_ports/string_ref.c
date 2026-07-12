/* Benchmark-only copy of the removed String#empty? IC handler. It is called
 * through a Tungsten method so both sides pay the same outer dispatch/cache
 * cost; only the old C body and native Tungsten body differ. */

#include "runtime.h"

WValue w_ref_string_empty_p(WValue recv) {
    char inline_buf[6];
    const char *str;
    size_t len;
    w_str_data(recv, inline_buf, &str, &len);
    return w_bool(len == 0);
}

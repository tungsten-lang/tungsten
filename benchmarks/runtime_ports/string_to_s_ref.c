/* Benchmark-only reference body and per-thread CPU clock for the
 * String/Symbol#to_s source-port gate. */

#include "runtime.h"
#include <stdint.h>
#include <time.h>

WValue w_ref_string_symbol_to_s(WValue recv) {
    if (!w_is_string(recv) && !w_is_symbol(recv)) {
        w_raise(w_string("to_s reference expected String or Symbol"));
        return W_NIL;
    }
    return recv & ~(WValue)1;
}

WValue w_to_s_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return w_int(-1);
    return w_int((int64_t)ts.tv_sec * INT64_C(1000000000) + ts.tv_nsec);
}

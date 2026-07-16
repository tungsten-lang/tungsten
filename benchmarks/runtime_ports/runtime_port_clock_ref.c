/* Shared benchmark-only thread CPU clock. Wall time is too noisy on hosts
 * running long compiler/search campaigns; calls happen outside timed loops. */

#include "runtime.h"
#include <stdint.h>
#include <time.h>

WValue w_runtime_port_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return w_int(-1);
    return w_int((int64_t)ts.tv_sec * INT64_C(1000000000) + ts.tv_nsec);
}

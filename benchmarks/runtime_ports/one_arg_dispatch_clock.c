#include "runtime.h"

#include <time.h>

WValue w_bench_one_arg_thread_cpu_clock(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) != 0)
        return w_float(0.0);
    return w_float((double)now.tv_sec + (double)now.tv_nsec / 1e9);
}

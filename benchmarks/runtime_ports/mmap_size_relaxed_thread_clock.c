#include <stdint.h>
#include <time.h>

int64_t w_bench_mmap_relaxed_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return -1;
    return (int64_t)ts.tv_sec * INT64_C(1000000000) + (int64_t)ts.tv_nsec;
}

#include <stdint.h>

#if defined(__APPLE__)
#include <mach/mach.h>

int64_t w_bench_thread_cpu_ns(void) {
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(mach_thread_self(), THREAD_BASIC_INFO,
                    (thread_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }
    int64_t seconds = (int64_t)info.user_time.seconds +
                      (int64_t)info.system_time.seconds;
    int64_t micros = (int64_t)info.user_time.microseconds +
                     (int64_t)info.system_time.microseconds;
    return seconds * 1000000000LL + micros * 1000LL;
}
#else
#include <time.h>

int64_t w_bench_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return 0;
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}
#endif

/* Deterministic OS-thread join deadlines under oversleep and interruption. */
#include <runtime.h>
#include <time.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

static int join_test_clock(clockid_t, struct timespec *);
static int join_test_sleep(const struct timespec *, struct timespec *);
#define clock_gettime join_test_clock
#define nanosleep join_test_sleep
#include <runtime.c>
#undef clock_gettime
#undef nanosleep

static int fake_time, sleep_mode, sleep_calls, finish_after;
static int64_t fake_ns;
static WThread *fake_thread;
static unsigned checks;
#define CHECK(x) do { \
    ++checks; \
    if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } \
} while (0)

static int join_test_clock(clockid_t clock, struct timespec *now) {
    if (!fake_time) return clock_gettime(clock, now);
    CHECK(clock == CLOCK_MONOTONIC);
    now->tv_sec = fake_ns / 1000000000;
    now->tv_nsec = fake_ns % 1000000000;
    return 0;
}

static int join_test_sleep(const struct timespec *request, struct timespec *left) {
    if (!fake_time) return nanosleep(request, left);
    int64_t ns = (int64_t)request->tv_sec * 1000000000 + request->tv_nsec;
    CHECK(ns > 0 && ns <= 10000000);
    ++sleep_calls;
    if (sleep_mode == 1) ns *= 2;  /* scheduler/timer oversleep */
    if (sleep_mode == 2 && ns > 1000000) ns = 1000000;
    fake_ns += ns;
    if (finish_after && sleep_calls == finish_after) fake_thread->alive = 0;
    if (sleep_mode == 2) { errno = EINTR; return -1; }
    return 0;
}

static void reset(WThread *thread, int mode) {
    *thread = (WThread){ .type = W_TYPE_THREAD, .alive = 1, .joined = 1 };
    fake_thread = thread;
    fake_time = 1;
    fake_ns = 999500000; /* cross a seconds boundary */
    sleep_mode = mode;
    sleep_calls = finish_after = 0;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    WThread thread;
    WValue value = w_box_ptr(&thread, W_SUBTAG_GENERIC);
    reset(&thread, 1);
    int64_t start = fake_ns;
    CHECK(w_thread_join_timeout(value, 100) == W_FALSE);
    CHECK(fake_ns - start >= 100000000);
    CHECK(fake_ns - start <= 110000000);

    reset(&thread, 0);
    start = fake_ns;
    CHECK(w_thread_join_timeout(value, 7) == W_FALSE);
    CHECK(fake_ns - start == 7000000);

    reset(&thread, 2);
    start = fake_ns;
    CHECK(w_thread_join_timeout(value, 100) == W_FALSE);
    CHECK(fake_ns - start == 100000000);

    reset(&thread, 0);
    CHECK(w_thread_join_timeout(value, 0) == W_FALSE);
    CHECK(w_thread_join_timeout(value, -1) == W_FALSE);
    CHECK(sleep_calls == 0);

    reset(&thread, 0);
    finish_after = 3;
    CHECK(w_thread_join_timeout(value, 100) == W_TRUE);
    CHECK(sleep_calls == 3);
    CHECK(w_thread_join_timeout(value, 0) == W_TRUE);

    reset(&thread, 0);
    finish_after = 1;
    CHECK(w_thread_join_timeout(value, INT64_MAX) == W_TRUE);
    CHECK(sleep_calls == 1);
    printf("PASS %u thread deadline checks\n", checks);
    return 0;
}

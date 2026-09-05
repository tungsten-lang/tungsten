/* Deadline frontier, wake-before-park and cross-thread wake regression tests. */
#include "../runtime.h"
#include <assert.h>
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); abort(); } checks++; } while (0)

static void test_frontier(void) {
    WEventLoop *a = w_event_init(), *b = w_event_init();
    CHECK(a && b);
    WGoroutine entries[97] = {0};
    int64_t expected[97] = {0};
    uint32_t rng = 0x1248abcd;
    for (int step = 0; step < 30000; step++) {
        rng = rng * 1664525u + 1013904223u;
        unsigned i = (rng >> 8) % 97;
        unsigned op = rng % 5;
        if (op < 3) {
            int64_t value = (rng >> 16) % 127 + 1; /* deliberate ties */
            CHECK(w_event_deadline_set(a, &entries[i], value) == 0);
            CHECK(entries[i].deadline_kind == 1);
            expected[i] = value;
            CHECK(w_event_deadline_set(b, &entries[i], value + 1) == -1);
            CHECK(errno == EINVAL);
        } else if (op == 3) {
            CHECK(w_event_deadline_cancel(a, &entries[i]) == (expected[i] != 0));
            expected[i] = 0;
            CHECK(!entries[i].deadline_linked);
        } else {
            int64_t now = (rng >> 16) % 127 + 1;
            int64_t minimum = 0;
            for (unsigned j = 0; j < 97; j++)
                if (expected[j] && (!minimum || expected[j] < minimum)) minimum = expected[j];
            WGoroutine *g = w_event_deadline_pop(a, now);
            if (minimum && minimum <= now) {
                CHECK(g && g >= entries && g < entries + 97);
                CHECK(expected[g - entries] == minimum);
                CHECK(!g->deadline_linked);
                expected[g - entries] = 0;
            } else CHECK(g == NULL);
        }
        int64_t minimum = 0;
        for (unsigned j = 0; j < 97; j++)
            if (expected[j] && (!minimum || expected[j] < minimum)) minimum = expected[j];
        CHECK(w_event_deadline_next(a) == minimum);
        CHECK(w_event_deadline_next(b) == 0);
    }
    for (unsigned i = 0; i < 97; i++) {
        CHECK(w_event_deadline_cancel(a, &entries[i]) == (expected[i] != 0));
        CHECK(w_event_deadline_set(b, &entries[i], 7) == 0);
    }
    int count = 0;
    while (w_event_deadline_pop(b, 7)) count++;
    CHECK(count == 97); /* equal deadlines are independent obligations */
    CHECK(w_event_deadline_set(a, &entries[0], 0) == -1);
    CHECK(w_event_deadline_next(a) == 0);
    /* No allocation per re-arm; a detached node can immediately be reused. */
    CHECK(w_event_deadline_set(a, &entries[0], 9) == 0);
    CHECK(w_event_deadline_cancel(a, &entries[0]) == 1);
    memset(&entries[0], 0, sizeof(entries[0]));
    CHECK(w_event_deadline_set(a, &entries[0], 3) == 0);
    int64_t sampled = 0;
    CHECK(w_event_deadline_prepare_poll(a, 5000, &sampled) == 5000);
    CHECK(sampled == 3); /* exact snapshot, no redundant rounded clamp */
    w_event_deadline_finish_poll(a, 5000);
    CHECK(w_event_deadline_pop(a, 3) == &entries[0]);
    CHECK(!entries[0].deadline_linked && entries[0].deadline_kind == 1);
    w_event_destroy(a);
    w_event_destroy(b);
}

static int64_t monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

typedef struct {
    WEventLoop *loop;
    int result;
    int64_t elapsed;
} PollThread;

static void *blocking_poll(void *opaque) {
    PollThread *p = opaque;
    WGoroutine *out[1];
    int64_t start = monotonic_ns();
    p->result = w_event_poll(p->loop, 5000, out, 1);
    p->elapsed = monotonic_ns() - start;
    return NULL;
}

static void wait_until_armed(WEventLoop *loop) {
    WEventDeadlineQueue *q = w_event_deadline_queue(loop);
    int64_t until = monotonic_ns() + 1000000000;
    for (;;) {
        pthread_mutex_lock(&q->lock);
        int armed = q->polling;
        pthread_mutex_unlock(&q->lock);
        if (armed) return;
        CHECK(monotonic_ns() < until);
        sched_yield();
    }
}

static void test_wake_and_deadline(void) {
    WEventLoop *loop = w_event_init();
    CHECK(loop != NULL);
    WGoroutine *out[1];
    /* Explicit wake must remain pending when no thread has entered poll yet. */
    for (int i = 0; i < 100; i++) CHECK(w_event_wake(loop) == 0);
    CHECK(w_event_poll(loop, -1, out, 1) == 0);
    CHECK(w_event_poll(loop, 0, out, 1) == 0);
    WGoroutine entry = {0};
    for (int cancel = 0; cancel < 2; cancel++) {
        if (cancel)
            CHECK(w_event_deadline_set(loop, &entry, __w_deadline_ticks_after_seconds(10)) == 0);
        PollThread poller = { .loop = loop };
        pthread_t thread;
        CHECK(pthread_create(&thread, NULL, blocking_poll, &poller) == 0);
        wait_until_armed(loop);
        /* Covers both sides of the snapshot-to-kernel-wait race. The new
         * deadline is far away, so returning promptly requires a wake. */
        if (cancel) CHECK(w_event_deadline_cancel(loop, &entry) == 1);
        else CHECK(w_event_deadline_set(loop, &entry, __w_deadline_ticks_after_seconds(10)) == 0);
        CHECK(pthread_join(thread, NULL) == 0);
        CHECK(poller.result == 0);
        CHECK(poller.elapsed < 1000000000);
        w_event_deadline_cancel(loop, &entry);
    }
    /* Replace an existing frontier, then shorten the new leader in place.
     * The displaced wait remains queued; neither update may be lost while
     * the poll owner transitions into the kernel wait. */
    WGoroutine later = {0};
    CHECK(w_event_deadline_set(loop, &later, __w_deadline_ticks_after_seconds(20)) == 0);
    for (int seconds = 10; seconds >= 5; seconds -= 5) {
        PollThread poller = { .loop = loop };
        pthread_t thread;
        CHECK(pthread_create(&thread, NULL, blocking_poll, &poller) == 0);
        wait_until_armed(loop);
        int64_t earlier = __w_deadline_ticks_after_seconds(seconds);
        CHECK(w_event_deadline_set(loop, &entry, earlier) == 0);
        CHECK(pthread_join(thread, NULL) == 0);
        CHECK(poller.result == 0 && poller.elapsed < 1000000000);
        CHECK(w_event_deadline_next(loop) == earlier);
        CHECK(later.deadline_linked);
    }
    CHECK(w_event_deadline_cancel(loop, &entry) == 1);
    CHECK(w_event_deadline_next(loop) == later.wait_deadline_ticks);
    CHECK(w_event_deadline_cancel(loop, &later) == 1);
    /* Automatic clamping of an otherwise indefinite poll. */
    int64_t due = __w_deadline_ticks_after_seconds(1);
    CHECK(w_event_deadline_set(loop, &entry, due) == 0);
    while (__w_clock_ticks_raw() < due) CHECK(w_event_poll(loop, -1, out, 1) == 0);
    CHECK(w_event_deadline_pop(loop, __w_clock_ticks_raw()) == &entry);
    CHECK(w_event_deadline_next(loop) == 0);
    w_event_destroy(loop);
}

static void test_wake_capacity(void) {
    WEventLoop *loop = w_event_init();
    CHECK(loop != NULL);
    int pipes[2][2];
    WGoroutine entries[2] = {0};
    for (int i = 0; i < 2; i++) {
        CHECK(pipe(pipes[i]) == 0);
        w_event_register(loop, pipes[i][0], W_EVENT_READ, &entries[i]);
        CHECK(write(pipes[i][1], "x", 1) == 1);
    }
    CHECK(w_event_wake(loop) == 0);
    WGoroutine *out[1];
    CHECK(w_event_poll(loop, 0, out, 0) == 0); /* do not consume/disarm */
    int seen[2] = {0};
    for (int attempt = 0; attempt < 5 && !(seen[0] && seen[1]); attempt++) {
        int n = w_event_poll(loop, 50, out, 1);
        CHECK(n >= 0 && n <= 1);
        if (n) {
            CHECK(out[0] == &entries[0] || out[0] == &entries[1]);
            int i = (int)(out[0] - entries);
            CHECK(!seen[i]);
            seen[i] = 1;
        }
    }
    CHECK(seen[0] && seen[1]);
    for (int i = 0; i < 2; i++) { close(pipes[i][0]); close(pipes[i][1]); }
    w_event_destroy(loop);
}

int main(void) {
    alarm(10);
#if defined(__aarch64__) || defined(__arm64__)
    CHECK(sizeof(WGoroutine) == 256);
#endif
    test_frontier();
    test_wake_and_deadline();
    test_wake_capacity();
    printf("event_deadlines: %d checks passed\n", checks);
    return 0;
}

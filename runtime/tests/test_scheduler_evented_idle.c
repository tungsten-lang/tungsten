/* Deterministic cooperative idle-poll regressions. The scheduler's poll is
 * replaced with a controlled event source; platform readiness/wake behavior
 * remains covered by test_event_loop. No elapsed-time threshold is used. */
#include <runtime.h>
#include <event_loop.h>

static void evented_test_hook(int point, WGoroutine *g);
static int evented_test_poll(WEventLoop *loop, int timeout_ms,
                             WGoroutine **out, int max_out);
#define W_SCHEDULER_TEST_HOOK(point, g) evented_test_hook(point, g)
#define w_event_poll evented_test_poll
#include <runtime.c>
#undef w_event_poll

static unsigned evented_checks;
#define CHECK(expr) do { \
    if (!(expr)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); abort(); } \
    evented_checks++; \
} while (0)

enum { POLL_FORBIDDEN, POLL_DEADLINE, POLL_READINESS };
static int poll_mode;
static unsigned poll_calls, park_calls;
static WGoroutine *parked;

static void evented_test_hook(int point, WGoroutine *g) {
    if (point != 2) return;
    CHECK(poll_mode != POLL_FORBIDDEN);
    CHECK(g->state == G_PARKING && !g->queued);
    parked = g;
    park_calls++;
}

static int evented_test_poll(WEventLoop *loop, int timeout_ms,
                             WGoroutine **out, int max_out) {
    CHECK(poll_mode != POLL_FORBIDDEN);
    CHECK(++poll_calls == 1); /* no initial spin probes or post-completion poll */
    CHECK(parked && parked->state == G_WAITING && !parked->queued);
    CHECK(parked->wait_loop == loop && max_out > 0);
    CHECK(timeout_ms != 0); /* readiness and timers can share a blocking wait */

    if (poll_mode == POLL_DEADLINE) {
        CHECK(parked->wait_deadline_ticks > __w_clock_ticks_raw());
        CHECK(w_event_deadline_next(loop) == parked->wait_deadline_ticks);
        int64_t frontier = 0;
        int budget = w_event_deadline_prepare_poll(loop, timeout_ms, &frontier);
        /* The high-resolution backend receives the absolute frontier and
         * applies it directly, without a redundant millisecond conversion. */
        CHECK(budget == timeout_ms);
        CHECK(frontier == parked->wait_deadline_ticks);
        /* Simulate a completed timer wait without sleeping or racing the wall
         * clock. Update through the real heap API, not just the G's field. */
        CHECK(w_event_deadline_set(loop, parked, 1) == 0);
        w_event_deadline_finish_poll(loop, timeout_ms);
        return 0; /* the scheduler's normal expiry drain must wake the G */
    }

    CHECK(poll_mode == POLL_READINESS && parked->wait_deadline_ticks == 0);
    CHECK(timeout_ms == -1); /* no periodic idle tick when only I/O can wake us */
    out[0] = parked;
    return 1;
}

static WValue done_body(WValue *captures) {
    (void)captures;
    return W_NIL;
}

static void test_no_completion_poll(void) {
    poll_mode = POLL_FORBIDDEN;
    poll_calls = park_calls = 0;
    WValue closure = w_closure_new((void *)done_body, NULL, 0);
    w_goroutine_spawn(closure);
    w_scheduler_run();
    CHECK(g_coop_live_goroutines == 0 && poll_calls == 0);
    w_scheduler_run(); /* an already-initialized empty scheduler also exits */
    CHECK(poll_calls == 0);
}

typedef struct {
    _Alignas(16) int fds[2];
    int64_t deadline;
    int expected_ready;
    int finished;
} ParkCase;

static WValue park_body(WValue *captures) {
    ParkCase *test = w_as_ptr(captures[0]);
    CHECK(w_socket_park_until(test->fds[0], W_EVENT_READ, test->deadline)
          == test->expected_ready);
    test->finished++;
    return W_NIL;
}

static void test_single_event_wait(int mode) {
    ParkCase test = {
        .deadline = mode == POLL_DEADLINE ? INT64_MAX / 2 : 0,
        .expected_ready = mode == POLL_READINESS
    };
    CHECK(pipe(test.fds) == 0);
    poll_mode = mode;
    poll_calls = park_calls = 0;
    parked = NULL;
    WValue capture = w_box_ptr(&test, W_SUBTAG_GENERIC);
    WValue closure = w_closure_new((void *)park_body, &capture, 1);
    w_goroutine_spawn(closure);
    w_scheduler_run();
    CHECK(test.finished == 1 && park_calls == 1 && poll_calls == 1);
    CHECK(g_coop_live_goroutines == 0);
    CHECK(parked && !parked->deadline_linked && parked->wait_deadline_ticks == 0);
    CHECK(w_event_deadline_next(g_coop_event_loop) == 0);
    CHECK(close(test.fds[0]) == 0 && close(test.fds[1]) == 0);
    poll_mode = POLL_FORBIDDEN;
    w_scheduler_run();
    CHECK(poll_calls == 1);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    alarm(20);
    CHECK(!g_mp_scheduler_active && p_current == NULL);
    w_scheduler_set_persistent(0);
    test_no_completion_poll();
    test_single_event_wait(POLL_DEADLINE);
    test_single_event_wait(POLL_READINESS);
    w_event_destroy(g_coop_event_loop);
    w_scheduler_set_event_loop(NULL);
    printf("scheduler_evented_idle: %u checks passed\n", evented_checks);
    return 0;
}

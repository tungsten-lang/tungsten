/* Focused FIFO ownership and park/wake publication tests. */
#include <runtime.h>
static void scheduler_test_hook(int point, WGoroutine *g);
#define W_SCHEDULER_TEST_HOOK(point, g) scheduler_test_hook(point, g)
#include <runtime.c>

static _Atomic unsigned test_checks;
#define CHECK(expr) do { \
    if (!(expr)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); abort(); } \
    atomic_fetch_add_explicit(&test_checks, 1, memory_order_relaxed); \
} while (0)

static _Atomic int hook_mode, hook_entered, hook_release;
static WGoroutine *hook_target;

static void scheduler_test_hook(int point, WGoroutine *g) {
    int mode = atomic_load_explicit(&hook_mode, memory_order_relaxed);
    if ((mode == 1 && point == 1 && g == hook_target) || (mode == 2 && point == 2)) {
        if (mode == 2) hook_target = g;
        atomic_store_explicit(&hook_entered, 1, memory_order_release);
        while (!atomic_load_explicit(&hook_release, memory_order_acquire)) sched_yield();
    }
}

static void test_fifo_order_and_wrap(void) {
    WProcessor p = {0};
    WGoroutine gs[W_LOCAL_QUEUE_MAX + 1] = {0};
    g_mp_scheduler_active = 1;
    for (unsigned i = 0; i <= W_LOCAL_QUEUE_MAX; i++) p_local_push(&p, &gs[i]);
    CHECK(g_dequeue() == &gs[W_LOCAL_QUEUE_MAX]); /* full ring overflow */
    for (unsigned i = 0; i < W_LOCAL_QUEUE_MAX; i++) {
        CHECK((i & 1 ? p_steal(&p) : p_local_pop(&p)) == &gs[i]);
        CHECK(gs[i].queued == 0);
    }
    CHECK(p_local_pop(&p) == NULL && p_steal(&p) == NULL);
    CHECK(p.local_head == p.local_tail);
    g_mp_scheduler_active = 0;

    /* Wrapping the unsigned position counters must not affect ring order. */
    p.local_head = UINT64_MAX - 127;
    p.local_tail = UINT64_MAX - 127;
    for (unsigned pass = 0; pass < 4; pass++) {
        for (unsigned i = 0; i < W_LOCAL_QUEUE_MAX; i++) p_local_push(&p, &gs[i]);
        for (unsigned i = 0; i < W_LOCAL_QUEUE_MAX; i++) CHECK(p_local_pop(&p) == &gs[i]);
    }
    /* A yielding goroutine rejoins behind already-runnable local work. */
    p_local_push(&p, &gs[0]);
    CHECK(p_local_pop(&p) == &gs[0]);
    p_local_push(&p, &gs[1]);
    p_local_push(&p, &gs[0]);
    CHECK(p_local_pop(&p) == &gs[1]);
    CHECK(p_local_pop(&p) == &gs[0]);
}

static WProcessor *race_p;
static WGoroutine race_g;
static WGoroutine *race_results[2];
static _Atomic unsigned race_epoch, race_done;
enum { RACE_ROUNDS = 100000 };

static void *queue_racer(void *opaque) {
    unsigned id = (unsigned)(uintptr_t)opaque;
    for (unsigned round = 1; round <= RACE_ROUNDS; round++) {
        while (atomic_load_explicit(&race_epoch, memory_order_acquire) < round) {}
        race_results[id] = id ? p_steal(race_p) : p_local_pop(race_p);
        atomic_fetch_add_explicit(&race_done, 1, memory_order_acq_rel);
    }
    return NULL;
}

static void test_last_item_race(void) {
    CHECK(posix_memalign((void **)&race_p, _Alignof(WProcessor), sizeof(*race_p)) == 0);
    memset(race_p, 0, sizeof(*race_p));
    pthread_t threads[2];
    for (unsigned i = 0; i < 2; i++)
        CHECK(pthread_create(&threads[i], NULL, queue_racer, (void *)(uintptr_t)i) == 0);
    for (unsigned round = 1; round <= RACE_ROUNDS; round++) {
        race_p->local_head = 0;
        race_p->local_tail = 1;
        race_p->local_queue[0] = &race_g;
        race_g.queued = 1;
        atomic_store_explicit(&race_done, 0, memory_order_relaxed);
        atomic_store_explicit(&race_epoch, round, memory_order_release);
        while (atomic_load_explicit(&race_done, memory_order_acquire) != 2) {}
        CHECK((race_results[0] == &race_g) + (race_results[1] == &race_g) == 1);
        CHECK(race_p->local_head == race_p->local_tail);
    }
    for (unsigned i = 0; i < 2; i++) CHECK(pthread_join(threads[i], NULL) == 0);
    free(race_p);
}

enum { STREAM_ITEMS = 100000 };
static WProcessor *stream_p;
static WGoroutine *stream_gs;
static _Atomic unsigned *stream_seen;
static _Atomic unsigned stream_consumed;

static void consume_stream_item(WGoroutine *g) {
    CHECK(g >= stream_gs && g < stream_gs + STREAM_ITEMS);
    size_t i = (size_t)(g - stream_gs);
    CHECK(w_as_int(g->result) == (int64_t)i);
    CHECK(atomic_fetch_add_explicit(&stream_seen[i], 1, memory_order_relaxed) == 0);
    atomic_fetch_add_explicit(&stream_consumed, 1, memory_order_release);
}

static void *stream_thief(void *unused) {
    (void)unused;
    while (atomic_load_explicit(&stream_consumed, memory_order_acquire) < STREAM_ITEMS) {
        WGoroutine *g = p_steal(stream_p);
        if (g) consume_stream_item(g);
        else sched_yield();
    }
    return NULL;
}

static void test_concurrent_ring_reuse(void) {
    CHECK(posix_memalign((void **)&stream_p, _Alignof(WProcessor), sizeof(*stream_p)) == 0);
    memset(stream_p, 0, sizeof(*stream_p));
    stream_gs = calloc(STREAM_ITEMS, sizeof(*stream_gs));
    stream_seen = calloc(STREAM_ITEMS, sizeof(*stream_seen));
    CHECK(stream_gs && stream_seen);
    pthread_t thieves[3];
    for (unsigned i = 0; i < 3; i++)
        CHECK(pthread_create(&thieves[i], NULL, stream_thief, NULL) == 0);
    for (unsigned i = 0; i < STREAM_ITEMS; i++) {
        while (atomic_load_explicit(&stream_p->local_tail, memory_order_relaxed) -
               atomic_load_explicit(&stream_p->local_head, memory_order_acquire) >= W_LOCAL_QUEUE_MAX) {
            WGoroutine *g = p_local_pop(stream_p);
            if (g) consume_stream_item(g);
        }
        stream_gs[i].result = w_int(i);
        p_local_push(stream_p, &stream_gs[i]);
        if ((i & 7u) == 0) {
            WGoroutine *g = p_local_pop(stream_p);
            if (g) consume_stream_item(g);
        }
    }
    for (unsigned i = 0; i < 3; i++) CHECK(pthread_join(thieves[i], NULL) == 0);
    CHECK(stream_consumed == STREAM_ITEMS && stream_p->local_head == stream_p->local_tail);
    for (unsigned i = 0; i < STREAM_ITEMS; i++) CHECK(stream_seen[i] == 1 && !stream_gs[i].queued);
    free(stream_seen);
    free(stream_gs);
    free(stream_p);
}

typedef struct { WGoroutine *g; int result; } WakeArg;
static void *claim_early_wake(void *opaque) {
    WakeArg *arg = opaque;
    arg->result = g_try_wake_waiting(arg->g, 1);
    return NULL;
}

static void test_park_states(void) {
    WGoroutine g = { .wait_fd = -1 };
    g.state = G_PARKING;
    CHECK(g_try_wake_waiting(&g, 1) == 0);
    CHECK(g.state == G_NOTIFIED && !g.queued);
    CHECK(g_try_wake_waiting(&g, 0) == 0); /* losing wake cannot replace result */
    CHECK(g_commit_park(&g) == 1);
    CHECK(g.state == G_RUNNABLE && g.wait_timed_out == 1);

    g.state = G_PARKING;
    CHECK(g_commit_park(&g) == 0 && g.state == G_WAITING);
    CHECK(g_try_wake_waiting(&g, 0) == 1);
    CHECK(g.state == G_RUNNABLE && g.wait_timed_out == 0);

    /* Hold a waker after its claim; committing the saved stack must return
     * without spinning, and transfer exactly one enqueue to that waker. */
    g.state = G_PARKING;
    hook_target = &g;
    hook_entered = hook_release = 0;
    hook_mode = 1;
    WakeArg arg = { .g = &g };
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, claim_early_wake, &arg) == 0);
    while (!atomic_load_explicit(&hook_entered, memory_order_acquire)) sched_yield();
    CHECK(g.state == G_WAKING);
    CHECK(g_commit_park(&g) == 0 && g.state == G_WAKING_PARKED);
    atomic_store_explicit(&hook_release, 1, memory_order_release);
    CHECK(pthread_join(thread, NULL) == 0);
    hook_mode = 0;
    CHECK(arg.result == 1 && g.state == G_RUNNABLE && g.wait_timed_out == 1);
    CHECK(g_try_wake_waiting(&g, 0) == 0);

    g.state = G_YIELDING;
    CHECK(g_after_switch(&g) == 1 && g.state == G_RUNNABLE);
    g_claim_running(&g);
    CHECK(g.state == G_RUNNING);
}

static void test_deadline_unlink(void) {
    WProcessor fake_owner = {0};
    p_current = &fake_owner; /* exercise the cross-worker deadline list */
    WGoroutine gs[4] = {0};
    for (unsigned i = 0; i < 4; i++) {
        gs[i].state = G_PARKING;
        gs[i].wait_fd = -1;
        gs[i].wait_deadline_ticks = INT64_MAX;
        g_deadline_add(&gs[i]);
    }
    CHECK(g_wait_deadline_head == &gs[3]);
    CHECK(gs[3].next == NULL && gs[3].deadline_next == &gs[2]);
    g_deadline_cancel(&gs[2]); /* middle */
    CHECK(gs[3].deadline_next == &gs[1] && gs[1].next == &gs[3]);
    CHECK(!gs[2].deadline_linked && !gs[2].next && !gs[2].deadline_next);
    g_deadline_cancel(&gs[0]); /* tail */
    CHECK(gs[1].deadline_next == NULL);
    g_deadline_cancel(&gs[3]); /* head */
    CHECK(g_wait_deadline_head == &gs[1] && gs[1].next == NULL);
    g_deadline_cancel(&gs[1]); /* singleton */
    CHECK(g_wait_deadline_head == NULL);
    for (unsigned i = 0; i < 4; i++) {
        g_deadline_add(&gs[i]);
        gs[i].wait_deadline_ticks = 1;
    }
    WGoroutine *out[4];
    /* Expiry before context-save records notifications, never runnable Gs. */
    CHECK(g_wake_expired_deadlines(NULL, out, 4) == 0);
    CHECK(g_wait_deadline_head == NULL);
    for (unsigned i = 0; i < 4; i++) {
        CHECK(g_commit_park(&gs[i]) == 1);
        CHECK(gs[i].state == G_RUNNABLE && !gs[i].next && !gs[i].deadline_linked);
    }
    p_current = NULL;
}

static int early_pipe[2], early_finished;
static WValue early_park_body(WValue *captures) {
    (void)captures;
    CHECK(w_socket_park_until(early_pipe[0], W_EVENT_READ, w_deadline_ticks_after_ms(10000)) == 0);
    early_finished++;
    return W_NIL;
}

static void *wake_before_context_save(void *unused) {
    (void)unused;
    while (!atomic_load_explicit(&hook_entered, memory_order_acquire)) sched_yield();
    CHECK(g_try_wake_waiting(hook_target, 1) == 0);
    CHECK(hook_target->state == G_NOTIFIED && !hook_target->queued);
    atomic_store_explicit(&hook_release, 1, memory_order_release);
    return NULL;
}

static void test_actual_early_park(void) {
    CHECK(pipe(early_pipe) == 0);
    _Alignas(16) WClosure cl = { .fn_ptr = early_park_body };
    hook_entered = hook_release = 0;
    hook_mode = 2;
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, wake_before_context_save, NULL) == 0);
    w_goroutine_spawn(w_box_ptr(&cl, W_SUBTAG_CLOSURE));
    w_scheduler_run();
    CHECK(pthread_join(thread, NULL) == 0);
    hook_mode = 0;
    CHECK(early_finished == 1 && g_wait_deadline_head == NULL);
    CHECK(w_event_deadline_next(g_coop_event_loop) == 0);
    close(early_pipe[0]);
    close(early_pipe[1]);
}

static _Atomic int fairness_flag;
static unsigned fairness_yields;
static WValue fairness_yielder(WValue *caps) {
    (void)caps;
    while (!atomic_load_explicit(&fairness_flag, memory_order_acquire)) {
        CHECK(++fairness_yields < 10000);
        w_goroutine_yield();
    }
    atomic_store_explicit(&fairness_flag, 2, memory_order_release);
    return W_NIL;
}
static WValue fairness_setter(WValue *caps) {
    (void)caps;
    atomic_store_explicit(&fairness_flag, 1, memory_order_release);
    return W_NIL;
}

static void test_global_fairness(void) {
    _Alignas(16) WClosure a = { .fn_ptr = fairness_yielder };
    _Alignas(16) WClosure b = { .fn_ptr = fairness_setter };
    w_scheduler_start(w_box_int(1));
    w_goroutine_spawn(w_box_ptr(&a, W_SUBTAG_CLOSURE));
    w_goroutine_spawn(w_box_ptr(&b, W_SUBTAG_CLOSURE));
    while (atomic_load_explicit(&fairness_flag, memory_order_acquire) != 2) sched_yield();
    w_scheduler_stop();
    CHECK(fairness_yields < 10000 && !g_mp_scheduler_active);
}

typedef struct { _Alignas(16) int fds[2]; int finished; } MPWait;
typedef struct { _Alignas(16) WClosure cl; } AlignedClosure;
static _Atomic int mp_done;
static WValue mp_wait_body(WValue *caps) {
    MPWait *arg = w_as_ptr(caps[0]);
    /* The G can migrate. Keep its stable identity rather than letting C hoist
     * a thread-local address across a context switch to a different thread. */
    WGoroutine *self = g_current;
    for (unsigned round = 0; round < 25; round++) {
        CHECK(!w_socket_park_until(arg->fds[0], W_EVENT_READ, w_deadline_ticks_after_ms(1)));
        CHECK(self->wait_deadline_ticks == 0 && !self->deadline_linked);
        arg->finished++;
        w_goroutine_yield();
    }
    atomic_fetch_add_explicit(&mp_done, 1, memory_order_release);
    return W_NIL;
}

static void test_mp_deadline_churn(void) {
    enum { N = 8 };
    MPWait args[N] = {0};
    AlignedClosure cls[N] = {0};
    WValue caps[N];
    for (int i = 0; i < N; i++) {
        CHECK(pipe(args[i].fds) == 0);
        caps[i] = w_box_ptr(&args[i], W_SUBTAG_GENERIC);
        cls[i].cl.fn_ptr = mp_wait_body;
        cls[i].cl.captures = &caps[i];
        cls[i].cl.capture_count = 1;
    }
    w_scheduler_start(w_box_int(4));
    for (int i = 0; i < N; i++) w_goroutine_spawn(w_box_ptr(&cls[i].cl, W_SUBTAG_CLOSURE));
    while (atomic_load_explicit(&mp_done, memory_order_acquire) != N) sched_yield();
    w_scheduler_stop();
    for (int i = 0; i < N; i++) {
        CHECK(args[i].finished == 25);
        close(args[i].fds[0]); close(args[i].fds[1]);
    }
    CHECK(g_wait_deadline_head == NULL && g_coop_live_goroutines == 0);
}

int main(int argc, char **argv) {
    alarm(20);
    test_fifo_order_and_wrap();
    test_last_item_race();
    test_concurrent_ring_reuse();
    test_park_states();
    test_deadline_unlink();
    if (!(argc == 2 && strcmp(argv[1], "--queues-only") == 0)) {
        test_actual_early_park();
        test_global_fairness();
        test_mp_deadline_churn();
    }
#if defined(__aarch64__)
    CHECK(sizeof(WGoroutine) == 256);
    CHECK(sizeof(WProcessor) == 2112);
#endif
    printf("scheduler_fifo_park: %u checks passed\n", atomic_load(&test_checks));
    return 0;
}

/* Deterministic mutex/channel migration regressions. Includes runtime.c so
 * two native workers can hand one saved G back and forth at every yield. */
#include <runtime.c>

static _Atomic unsigned sync_checks;
#define CHECK(expr) do { \
    if (!(expr)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); abort(); } \
    atomic_fetch_add_explicit(&sync_checks, 1, memory_order_relaxed); \
} while (0)

typedef struct {
    WProcessor processor;
    pthread_t thread;
    _Atomic int ready;
    _Atomic int command; /* 0 idle, 1 run one saved context, 2 stop */
    WGoroutine *g;
    int action;
} StepWorker;

static StepWorker workers[2];

static void *step_worker(void *opaque) {
    StepWorker *worker = opaque;
    p_current = &worker->processor;
    atomic_store_explicit(&worker->ready, 1, memory_order_release);
    for (;;) {
        int command = atomic_load_explicit(&worker->command, memory_order_acquire);
        if (command == 2) return NULL;
        if (command == 0) { sched_yield(); continue; }
        WGoroutine *g = worker->g;
        g_claim_running(g);
        g_current = g;
        w_ctx_swap(&g_scheduler_ctx, &g->ctx);
        g_current = NULL;
        worker->action = g_after_switch(g);
        CHECK(worker->action != 0); /* these tests only yield or finish */
        atomic_store_explicit(&worker->command, 0, memory_order_release);
    }
}

static int run_on(unsigned id, WGoroutine *g) {
    StepWorker *worker = &workers[id];
    CHECK(atomic_load_explicit(&worker->command, memory_order_acquire) == 0);
    worker->g = g;
    atomic_store_explicit(&worker->command, 1, memory_order_release);
    while (atomic_load_explicit(&worker->command, memory_order_acquire) != 0) sched_yield();
    return worker->action;
}

typedef struct {
    _Alignas(16) WValue sync;
    WValue result;
    WGoroutine *self;
    int finished;
} SyncCase;

static WGoroutine *spawn_case(WValue (*body)(WValue *), SyncCase *test) {
    WValue capture = w_box_ptr(test, W_SUBTAG_GENERIC);
    WValue closure = w_closure_new((void *)body, &capture, 1);
    WGoroutine *g = w_as_ptr(w_goroutine_spawn(closure));
    CHECK(g_dequeue() == g);
    return g;
}

static WValue mutex_body(WValue *captures) {
    SyncCase *test = w_as_ptr(captures[0]);
    test->self = w_as_ptr(w_goroutine_current());
    w_mutex_lock(test->sync);
    WMutex *mutex = as_mutex(test->sync);
    CHECK(mutex->owner_is_goroutine && mutex->owner_goroutine == test->self);
    w_mutex_unlock(test->sync);
    test->finished = 1;
    return W_NIL;
}

static void test_mutex_migration(void) {
    SyncCase test = { .sync = w_mutex_new() };
    w_mutex_lock(test.sync); /* native owner forces the G's lock loop to yield */
    WGoroutine *g = spawn_case(mutex_body, &test);
    CHECK(run_on(0, g) == 1);
    CHECK(run_on(1, g) == 1);
    CHECK(run_on(0, g) == 1);
    w_mutex_unlock(test.sync);
    CHECK(run_on(1, g) == -1);
    CHECK(test.finished && !as_mutex(test.sync)->locked);
    g_pool_return(g);
}

static WValue sender_body(WValue *captures) {
    SyncCase *test = w_as_ptr(captures[0]);
    w_chan_send(test->sync, w_int(42));
    test->finished = 1;
    return W_NIL;
}

static void test_sender_migration(int capacity) {
    SyncCase test = { .sync = w_chan_new(w_int(capacity)) };
    if (capacity) w_chan_send(test.sync, w_int(7));
    WGoroutine *g = spawn_case(sender_body, &test);
    CHECK(run_on(0, g) == 1);
    CHECK(run_on(1, g) == 1);
    CHECK(run_on(0, g) == 1);
    CHECK(w_as_int(w_chan_recv(test.sync)) == (capacity ? 7 : 42));
    CHECK(run_on(1, g) == -1);
    CHECK(test.finished);
    if (capacity) CHECK(w_as_int(w_chan_recv(test.sync)) == 42);
    g_pool_return(g);
}

static WValue receiver_body(WValue *captures) {
    SyncCase *test = w_as_ptr(captures[0]);
    test->result = w_chan_recv(test->sync);
    test->finished = 1;
    return W_NIL;
}

static void test_receiver_migration(void) {
    SyncCase test = { .sync = w_chan_new(w_int(0)) };
    WChan *channel = as_chan(test.sync);
    WGoroutine *g = spawn_case(receiver_body, &test);
    CHECK(run_on(0, g) == 1);
    CHECK(channel->recv_waiters == 1);
    CHECK(run_on(1, g) == 1);
    CHECK(channel->recv_waiters == 1);
    CHECK(run_on(0, g) == 1);
    CHECK(channel->recv_waiters == 1);
    CHECK(w_chan_try_send(test.sync, w_int(99)) == W_TRUE);
    CHECK(run_on(1, g) == -1);
    CHECK(test.finished && w_as_int(test.result) == 99 && channel->recv_waiters == 0);
    g_pool_return(g);
}

static void *native_receiver(void *opaque) {
    SyncCase *test = opaque;
    w_chan_recv(test->sync);
    return NULL;
}

static void test_native_receiver_cancellation(void) {
    SyncCase test = { .sync = w_chan_new(w_int(0)) };
    WChan *channel = as_chan(test.sync);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, native_receiver, &test) == 0);
    for (;;) {
        pthread_mutex_lock(&channel->lock);
        int waiting = channel->recv_waiters > 0;
        pthread_mutex_unlock(&channel->lock);
        if (waiting) break;
        sched_yield();
    }
    CHECK(pthread_cancel(thread) == 0);
    void *result = NULL;
    CHECK(pthread_join(thread, &result) == 0);
    CHECK(result == PTHREAD_CANCELED && channel->recv_waiters == 0);
    CHECK(w_chan_try_send(test.sync, w_int(1)) == W_FALSE);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    alarm(20);
    g_mp_scheduler_active = 1;
    for (unsigned i = 0; i < 2; i++) {
        workers[i].processor.id = (int)i;
        CHECK(pthread_create(&workers[i].thread, NULL, step_worker, &workers[i]) == 0);
        while (!atomic_load_explicit(&workers[i].ready, memory_order_acquire)) sched_yield();
    }
    for (unsigned round = 0; round < 50; round++) {
        test_mutex_migration();
        test_sender_migration(1);
        test_sender_migration(0);
        test_receiver_migration();
    }
    test_native_receiver_cancellation();
    for (unsigned i = 0; i < 2; i++) {
        atomic_store_explicit(&workers[i].command, 2, memory_order_release);
        CHECK(pthread_join(workers[i].thread, NULL) == 0);
    }
    g_mp_scheduler_active = 0;
    CHECK(g_shared_queue_head == NULL && g_coop_live_goroutines == 0);
    printf("scheduler_sync_migration: %u checks passed\n", atomic_load(&sync_checks));
    return 0;
}

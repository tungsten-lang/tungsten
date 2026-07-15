/*
 * test_threads.c — Phase 1: OS Thread Primitives
 *
 * Tests:
 *   1. __thread exception stack isolation
 *   2. Thread spawn and join
 *   3. Thread sleep
 *   4. Thread alive? check
 *   5. Thread join with timeout
 *   6. Multiple threads with independent exception stacks
 */

#include "../runtime.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


/* ---- Test infrastructure ---- */

static int tests_run = 0;
static int tests_passed = 0;

#define ASSERT(cond, msg) do { \
    tests_run++; \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        tests_passed++; \
    } \
} while (0)

/* ---- Test helpers ---- */

/* A simple closure that returns an int */
static WValue return_42_fn(WValue *captures) {
    (void)captures;
    return w_box_int(42);
}

static WValue return_capture_fn(WValue *captures) {
    return captures[0];
}

/* A closure that sleeps then returns */
static WValue sleep_and_return_fn(WValue *captures) {
    int64_t ms = w_as_int(captures[0]);
    w_thread_sleep_ms(ms);
    return w_box_int(999);
}

/* A closure that raises an exception */
static WValue raise_in_thread_fn(WValue *captures) {
    (void)captures;

    /* Push an exception handler */
    void *buf = w_exception_push();
    if (setjmp(*(jmp_buf *)buf) == 0) {
        /* Normal path: raise an error */
        w_raise(w_string("thread error"));
        return W_NIL;  /* unreachable */
    } else {
        /* Exception caught */
        WValue err = w_exception_error();
        w_exception_pop();
        return err;
    }
}

/* A closure that verifies exception stack is NULL (thread-local) */
static WValue check_exception_stack_fn(WValue *captures) {
    (void)captures;
    /* In a new thread, exception stack should be NULL */
    return w_exception_stack == NULL ? W_TRUE : W_FALSE;
}

/* Block in __w_system so Thread.kill exercises its cancellation cleanup. */
static WValue system_command_fn(WValue *captures) {
    return __w_system(captures[0]);
}

/* ---- Tests ---- */

static void test_thread_local_exception_stack(void) {
    printf("Test 1: __thread exception stack isolation\n");

    /* Push a handler on main thread */
    void *buf = w_exception_push();
    (void)buf;
    ASSERT(w_exception_stack != NULL, "main thread has exception handler");

    /* Spawn a thread that checks its own exception stack */
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = check_exception_stack_fn;
    cl->captures = NULL;
    cl->capture_count = 0;
    WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);

    WValue thread = w_thread_spawn(closure);
    WValue result = w_thread_join(thread);
    ASSERT(result == W_TRUE, "new thread has NULL exception stack (thread-local)");

    /* Main thread's exception stack is still intact */
    ASSERT(w_exception_stack != NULL, "main thread exception stack unchanged");
    w_exception_pop();

    printf("  __thread isolation: OK\n\n");
}

static void test_thread_spawn_join(void) {
    printf("Test 2: Thread spawn and join\n");

    /* Simple spawn: return 42 */
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = return_42_fn;
    cl->captures = NULL;
    cl->capture_count = 0;
    WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);

    WValue thread = w_thread_spawn(closure);
    ASSERT(w_is_thread(thread), "w_thread_spawn returns a thread");

    WValue result = w_thread_join(thread);
    ASSERT(w_is_int(result), "thread returned an int");
    ASSERT(w_as_int(result) == 42, "thread returned 42");

    /* Spawn with captures */
    WValue *caps = calloc(1,sizeof(WValue));
    caps[0] = w_box_int(123);
    WClosure *cl2 = calloc(1,sizeof(WClosure));
    cl2->fn_ptr = return_capture_fn;
    cl2->captures = caps;
    cl2->capture_count = 1;
    WValue closure2 = w_box_ptr(cl2, W_SUBTAG_CLOSURE);

    WValue thread2 = w_thread_spawn(closure2);
    WValue result2 = w_thread_join(thread2);
    ASSERT(w_as_int(result2) == 123, "thread with captures returned captured value");

    printf("  Spawn and join: OK\n\n");
}

static void test_thread_sleep(void) {
    printf("Test 3: Thread sleep\n");

    /* Sleep 50ms — verify it doesn't crash */
    WValue *caps = calloc(1,sizeof(WValue));
    caps[0] = w_box_int(50);
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = sleep_and_return_fn;
    cl->captures = caps;
    cl->capture_count = 1;
    WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);

    WValue thread = w_thread_spawn(closure);
    WValue result = w_thread_join(thread);
    ASSERT(w_as_int(result) == 999, "thread slept then returned");

    printf("  Thread sleep: OK\n\n");
}

static void test_thread_alive(void) {
    printf("Test 4: Thread alive?\n");

    /* Spawn a thread that sleeps for 200ms */
    WValue *caps = calloc(1,sizeof(WValue));
    caps[0] = w_box_int(200);
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = sleep_and_return_fn;
    cl->captures = caps;
    cl->capture_count = 1;
    WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);

    WValue thread = w_thread_spawn(closure);
    ASSERT(w_thread_alive(thread) == W_TRUE, "thread is alive immediately after spawn");

    /* Wait for it to finish */
    w_thread_join(thread);
    ASSERT(w_thread_alive(thread) == W_FALSE, "thread is not alive after join");

    printf("  Thread alive: OK\n\n");
}

static void test_thread_join_timeout(void) {
    printf("Test 5: Thread join with timeout\n");

    /* Spawn a thread that sleeps for 500ms */
    WValue *caps = calloc(1,sizeof(WValue));
    caps[0] = w_box_int(500);
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = sleep_and_return_fn;
    cl->captures = caps;
    cl->capture_count = 1;
    WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);

    WValue thread = w_thread_spawn(closure);

    /* Timeout after 20ms — should fail (thread still running) */
    WValue timedout = w_thread_join_timeout(thread, 20);
    ASSERT(timedout == W_FALSE, "join times out when thread still running");

    /* Wait long enough — should succeed */
    WValue ok = w_thread_join_timeout(thread, 1000);
    ASSERT(ok == W_TRUE, "join succeeds when thread finishes");

    printf("  Join timeout: OK\n\n");
}

static void test_multiple_threads_exceptions(void) {
    printf("Test 6: Multiple threads with independent exception stacks\n");

    #define N_THREADS 10
    WValue threads[N_THREADS];

    for (int i = 0; i < N_THREADS; i++) {
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = raise_in_thread_fn;
        cl->captures = NULL;
        cl->capture_count = 0;
        WValue closure = w_box_ptr(cl, W_SUBTAG_CLOSURE);
        threads[i] = w_thread_spawn(closure);
    }

    int all_caught = 1;
    for (int i = 0; i < N_THREADS; i++) {
        WValue result = w_thread_join(threads[i]);
        /* Each thread should have caught its own exception */
        if (!w_is_string(result) && !w_is_symbol(result)) {
            all_caught = 0;
        }
    }
    ASSERT(all_caught, "all threads caught their own exceptions independently");

    /* Main thread exception stack is unaffected */
    ASSERT(w_exception_stack == NULL, "main thread exception stack still clean");

    printf("  Multiple threads exceptions: OK\n\n");
    #undef N_THREADS
}

static void test_cancel_reaps_system_child(void) {
    printf("Test 7: cancelled system command reaps child process\n");

    char pid_path[256];
    char command[512];
    snprintf(pid_path, sizeof(pid_path), "/tmp/tungsten-thread-child-%ld.pid",
             (long)getpid());
    unlink(pid_path);
    snprintf(command, sizeof(command), "echo $$ > %s; exec sleep 30", pid_path);

    WValue *caps = calloc(1, sizeof(WValue));
    caps[0] = w_string(command);
    WClosure *cl = calloc(1, sizeof(WClosure));
    cl->fn_ptr = system_command_fn;
    cl->captures = caps;
    cl->capture_count = 1;
    WValue thread = w_thread_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));

    pid_t child_pid = -1;
    for (int attempt = 0; attempt < 100 && child_pid <= 0; attempt++) {
        FILE *pid_file = fopen(pid_path, "r");
        if (pid_file) {
            long parsed = -1;
            if (fscanf(pid_file, "%ld", &parsed) == 1) child_pid = (pid_t)parsed;
            fclose(pid_file);
        }
        if (child_pid <= 0) usleep(10000);
    }
    ASSERT(child_pid > 0, "system child published its pid");

    w_thread_kill(thread);
    w_thread_join(thread);
    ASSERT(w_thread_alive(thread) == W_FALSE,
           "cancelled controller is no longer reported alive");

    int gone = 0;
    for (int attempt = 0; attempt < 100; attempt++) {
        if (child_pid > 0 && kill(child_pid, 0) == -1 && errno == ESRCH) {
            gone = 1;
            break;
        }
        usleep(10000);
    }
    ASSERT(gone, "cancelled system child is terminated and waitpid-reaped");
    unlink(pid_path);

    printf("  System child cancellation cleanup: OK\n\n");
}

/* ---- Main ---- */

int main(void) {
    setbuf(stdout, NULL);
    printf("=== Phase 1: OS Thread Primitives ===\n\n");

    test_thread_local_exception_stack();
    test_thread_spawn_join();
    test_thread_sleep();
    test_thread_alive();
    test_thread_join_timeout();
    test_multiple_threads_exceptions();
    test_cancel_reaps_system_child();

    printf("=== Results: %d/%d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}

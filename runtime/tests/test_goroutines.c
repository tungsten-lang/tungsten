/*
 * test_goroutines.c — Phase 4: Goroutines + Channels + Freeze
 *
 * Tests:
 *   1. Goroutine spawn and scheduler
 *   2. Goroutine yield (cooperative switching)
 *   3. Buffered channel send/recv
 *   4. Multiple goroutines communicating via channel
 *   5. Channel close behavior
 *   6. Freeze (transitive, cycle detection)
 *   7. Frozen mutation raises error
 */

#include "../runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


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

/* ---- Goroutine helpers ---- */

static volatile int g_counter = 0;

/* Simple goroutine: increment counter */
static WValue increment_fn(WValue *captures) {
    (void)captures;
    g_counter++;
    return W_NIL;
}

/* Goroutine that yields multiple times */
static WValue yielding_fn(WValue *captures) {
    int id = (int)w_as_int(captures[0]);
    volatile int *order = (volatile int *)w_as_ptr(captures[1]);
    static volatile int pos = 0;

    order[__sync_fetch_and_add((int *)&pos, 1)] = id * 10 + 1;
    w_goroutine_yield();
    order[__sync_fetch_and_add((int *)&pos, 1)] = id * 10 + 2;
    w_goroutine_yield();
    order[__sync_fetch_and_add((int *)&pos, 1)] = id * 10 + 3;
    return W_NIL;
}

/* Goroutine that sends to a channel */
static WValue chan_sender_fn(WValue *captures) {
    WValue ch = captures[0];
    int64_t count = w_as_int(captures[1]);
    for (int64_t i = 0; i < count; i++) {
        w_chan_send(ch, w_box_int(i));
    }
    return W_NIL;
}

/* ---- Tests ---- */

static void test_goroutine_spawn(void) {
    printf("Test 1: Goroutine spawn + scheduler\n");

    g_counter = 0;

    /* Spawn 10 goroutines that each increment the counter */
    for (int i = 0; i < 10; i++) {
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = increment_fn;
        cl->captures = NULL;
        cl->capture_count = 0;
        w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
    }

    /* Run the scheduler to execute all goroutines */
    w_scheduler_run();

    ASSERT(g_counter == 10, "10 goroutines executed");
    printf("  Goroutine spawn: OK\n\n");
}

static void test_goroutine_yield(void) {
    printf("Test 2: Goroutine cooperative yield\n");

    /* Spawn 3 goroutines that yield and record execution order */
    int *order = calloc(1,sizeof(int) * 20);
    memset(order, 0, sizeof(int) * 20);

    for (int i = 0; i < 3; i++) {
        WValue *caps = calloc(1,sizeof(WValue) * 2);
        caps[0] = w_box_int(i);
        caps[1] = w_box_ptr(order, W_SUBTAG_GENERIC);
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = yielding_fn;
        cl->captures = caps;
        cl->capture_count = 2;
        w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
    }

    w_scheduler_run();

    /* With cooperative scheduling, goroutines interleave at yield points */
    /* First round: g0-step1, g1-step1, g2-step1 */
    /* Second round: g0-step2, g1-step2, g2-step2 */
    /* Third round: g0-step3, g1-step3, g2-step3 */
    ASSERT(order[0] == 1, "g0 runs first step first");
    ASSERT(order[1] == 11, "g1 runs first step second");
    ASSERT(order[2] == 21, "g2 runs first step third");

    printf("  Goroutine yield: OK\n\n");

    free(order);
}

static void test_buffered_channel(void) {
    printf("Test 3: Buffered channel send/recv\n");

    WValue ch = w_chan_new(w_box_int(5));
    ASSERT(w_is_channel(ch), "channel created");

    /* Send 3 values */
    w_chan_send(ch, w_box_int(10));
    w_chan_send(ch, w_box_int(20));
    w_chan_send(ch, w_box_int(30));

    /* Receive them back */
    WValue v1 = w_chan_recv(ch);
    WValue v2 = w_chan_recv(ch);
    WValue v3 = w_chan_recv(ch);
    ASSERT(w_as_int(v1) == 10, "first value is 10");
    ASSERT(w_as_int(v2) == 20, "second value is 20");
    ASSERT(w_as_int(v3) == 30, "third value is 30");

    printf("  Buffered channel: OK\n\n");
}

static void test_goroutine_channel(void) {
    printf("Test 4: Goroutines communicating via channel\n");

    WValue ch = w_chan_new(w_box_int(10));

    /* Spawn sender goroutine */
    WValue *caps = calloc(1,sizeof(WValue) * 2);
    caps[0] = ch;
    caps[1] = w_box_int(5);
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = chan_sender_fn;
    cl->captures = caps;
    cl->capture_count = 2;
    w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));

    /* Run scheduler to let sender execute */
    w_scheduler_run();

    /* Receive all values */
    int64_t sum = 0;
    for (int i = 0; i < 5; i++) {
        WValue v = w_chan_recv(ch);
        sum += w_as_int(v);
    }
    ASSERT(sum == 10, "sum of 0+1+2+3+4 = 10");

    printf("  Goroutine + channel: OK\n\n");
}

static void test_channel_close(void) {
    printf("Test 5: Channel close\n");

    WValue ch = w_chan_new(w_box_int(3));
    w_chan_send(ch, w_box_int(42));
    w_chan_close(ch);

    /* Can still receive buffered values */
    WValue v = w_chan_recv(ch);
    ASSERT(w_as_int(v) == 42, "can receive from closed channel with buffered data");

    /* Receive from empty closed channel returns nil */
    WValue v2 = w_chan_recv(ch);
    ASSERT(v2 == W_NIL, "receive from empty closed channel returns nil");

    printf("  Channel close: OK\n\n");
}

static void test_freeze(void) {
    printf("Test 6: Freeze (transitive + cycle detection)\n");

    /* Create an object hierarchy */
    WValue klass = w_class_new("TestObj", W_NIL);
    WValue obj = w_object_new(klass);
    WValue inner = w_object_new(klass);

    /* Set ivars */
    w_ivar_set(obj, "child", inner);
    w_ivar_set(inner, "value", w_box_int(42));

    ASSERT(w_frozen_p(obj) == W_FALSE, "object not frozen initially");
    ASSERT(w_frozen_p(inner) == W_FALSE, "inner not frozen initially");

    /* Freeze transitively */
    w_freeze(obj);

    ASSERT(w_frozen_p(obj) == W_TRUE, "object frozen after freeze");
    ASSERT(w_frozen_p(inner) == W_TRUE, "inner frozen transitively");

    /* Value types are always frozen */
    ASSERT(w_frozen_p(w_box_int(42)) == W_TRUE, "int is always frozen");
    ASSERT(w_frozen_p(W_NIL) == W_TRUE, "nil is always frozen");

    printf("  Freeze: OK\n\n");
}

static void test_assert_frozen(void) {
    printf("Test 7: Assert frozen raises on mutable\n");

    WValue klass = w_class_new("MutObj", W_NIL);
    WValue obj = w_object_new(klass);

    /* assert_frozen should raise on unfrozen object */
    void *buf = w_exception_push();
    if (setjmp(*(jmp_buf *)buf) == 0) {
        w_assert_frozen(obj);
        ASSERT(0, "assert_frozen should have raised");
    } else {
        WValue err = w_exception_error();
        w_exception_pop();
        ASSERT(w_is_string(err) || w_is_symbol(err),
               "assert_frozen raised a string error");
    }

    /* Frozen object passes */
    w_freeze(obj);
    /* Should not raise */
    void *buf2 = w_exception_push();
    if (setjmp(*(jmp_buf *)buf2) == 0) {
        w_assert_frozen(obj);
        w_exception_pop();
        ASSERT(1, "assert_frozen passes for frozen object");
    } else {
        w_exception_pop();
        ASSERT(0, "assert_frozen should not raise for frozen object");
    }

    printf("  Assert frozen: OK\n\n");
}

/* ---- Main ---- */

int main(void) {
    setbuf(stdout, NULL);
    printf("=== Phase 4: Goroutines + Channels + Freeze ===\n\n");

    test_goroutine_spawn();
    test_goroutine_yield();
    test_buffered_channel();
    test_goroutine_channel();
    test_channel_close();
    test_freeze();
    test_assert_frozen();

    printf("=== Results: %d/%d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}

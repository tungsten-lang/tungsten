/*
 * test_atomics.c — Phase 2: Atomics stress test
 *
 * Tests:
 *   1. Basic atomic new/get/set
 *   2. Atomic add (single-threaded)
 *   3. Stress: 1000 threads × atomic add(1) → final value 1000
 *   4. Atomic CAS (compare-and-swap)
 *   5. Atomic increment/decrement
 *   6. CAS contention: multiple threads CAS-incrementing
 */

#include "../runtime.h"
#include <stdio.h>
#include <stdlib.h>


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

/* ---- Shared state for stress tests ---- */

static WValue shared_atomic;

/* Closure: add 1 to shared atomic */
static WValue add_one_fn(WValue *captures) {
    (void)captures;
    w_atomic_add(shared_atomic, w_box_int(1));
    return W_NIL;
}

/* Closure: CAS-increment the shared atomic N times */
static WValue cas_increment_fn(WValue *captures) {
    int64_t count = w_as_int(captures[0]);
    for (int64_t i = 0; i < count; i++) {
        while (1) {
            WValue cur = w_atomic_get(shared_atomic);
            int64_t val = w_as_int(cur);
            WValue ok = w_atomic_cas(shared_atomic, cur, w_box_int(val + 1));
            if (ok == W_TRUE) break;
        }
    }
    return W_NIL;
}

/* ---- Tests ---- */

static void test_atomic_basic(void) {
    printf("Test 1: Atomic new/get/set\n");

    WValue a = w_atomic_new(w_box_int(0));
    ASSERT(w_is_atomic(a), "w_atomic_new returns an atomic");
    ASSERT(w_as_int(w_atomic_get(a)) == 0, "initial value is 0");

    w_atomic_set(a, w_box_int(42));
    ASSERT(w_as_int(w_atomic_get(a)) == 42, "set to 42");

    w_atomic_set(a, w_box_int(-100));
    ASSERT(w_as_int(w_atomic_get(a)) == -100, "set to -100");

    printf("  Basic: OK\n\n");
}

static void test_atomic_add(void) {
    printf("Test 2: Atomic add (single-threaded)\n");

    WValue a = w_atomic_new(w_box_int(10));
    WValue old = w_atomic_add(a, w_box_int(5));
    ASSERT(w_as_int(old) == 10, "add returns old value (10)");
    ASSERT(w_as_int(w_atomic_get(a)) == 15, "value is now 15");

    old = w_atomic_add(a, w_box_int(-3));
    ASSERT(w_as_int(old) == 15, "add returns old value (15)");
    ASSERT(w_as_int(w_atomic_get(a)) == 12, "value is now 12");

    printf("  Add: OK\n\n");
}

static void test_atomic_stress(void) {
    printf("Test 3: Stress — 1000 threads × atomic add(1)\n");

    #define STRESS_THREADS 1000
    shared_atomic = w_atomic_new(w_box_int(0));

    WValue threads[STRESS_THREADS];
    for (int i = 0; i < STRESS_THREADS; i++) {
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = add_one_fn;
        cl->captures = NULL;
        cl->capture_count = 0;
        threads[i] = w_thread_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
    }

    for (int i = 0; i < STRESS_THREADS; i++) {
        w_thread_join(threads[i]);
    }

    int64_t final_val = w_as_int(w_atomic_get(shared_atomic));
    ASSERT(final_val == STRESS_THREADS,
           "final value equals thread count (no lost increments)");
    printf("  Final value: %lld (expected %d)\n", (long long)final_val, STRESS_THREADS);

    printf("  Stress: OK\n\n");
    #undef STRESS_THREADS
}

static void test_atomic_cas(void) {
    printf("Test 4: Atomic CAS\n");

    WValue a = w_atomic_new(w_box_int(10));

    /* Successful CAS: expected matches */
    WValue ok = w_atomic_cas(a, w_box_int(10), w_box_int(20));
    ASSERT(ok == W_TRUE, "CAS succeeds when expected matches");
    ASSERT(w_as_int(w_atomic_get(a)) == 20, "value updated to 20");

    /* Failed CAS: expected doesn't match */
    WValue fail = w_atomic_cas(a, w_box_int(10), w_box_int(30));
    ASSERT(fail == W_FALSE, "CAS fails when expected doesn't match");
    ASSERT(w_as_int(w_atomic_get(a)) == 20, "value unchanged at 20");

    printf("  CAS: OK\n\n");
}

static void test_atomic_inc_dec(void) {
    printf("Test 5: Atomic increment/decrement\n");

    WValue a = w_atomic_new(w_box_int(0));

    WValue v1 = w_atomic_increment(a);
    ASSERT(w_as_int(v1) == 1, "increment returns new value (1)");
    ASSERT(w_as_int(w_atomic_get(a)) == 1, "value is 1");

    WValue v2 = w_atomic_increment(a);
    ASSERT(w_as_int(v2) == 2, "increment returns new value (2)");

    WValue v3 = w_atomic_decrement(a);
    ASSERT(w_as_int(v3) == 1, "decrement returns new value (1)");
    ASSERT(w_as_int(w_atomic_get(a)) == 1, "value is 1 after decrement");

    printf("  Increment/decrement: OK\n\n");
}

static void test_atomic_cas_contention(void) {
    printf("Test 6: CAS contention — 100 threads × 100 CAS increments\n");

    #define CAS_THREADS 100
    #define CAS_OPS 100
    shared_atomic = w_atomic_new(w_box_int(0));

    WValue threads[CAS_THREADS];
    for (int i = 0; i < CAS_THREADS; i++) {
        WValue *caps = calloc(1,sizeof(WValue));
        caps[0] = w_box_int(CAS_OPS);
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = cas_increment_fn;
        cl->captures = caps;
        cl->capture_count = 1;
        threads[i] = w_thread_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
    }

    for (int i = 0; i < CAS_THREADS; i++) {
        w_thread_join(threads[i]);
    }

    int64_t final_val = w_as_int(w_atomic_get(shared_atomic));
    int64_t expected = (int64_t)CAS_THREADS * CAS_OPS;
    ASSERT(final_val == expected,
           "CAS contention: no lost increments");
    printf("  Final value: %lld (expected %lld)\n",
           (long long)final_val, (long long)expected);

    printf("  CAS contention: OK\n\n");
    #undef CAS_THREADS
    #undef CAS_OPS
}

/* ---- Main ---- */

int main(void) {
    setbuf(stdout, NULL);
    printf("=== Phase 2: Atomics ===\n\n");

    test_atomic_basic();
    test_atomic_add();
    test_atomic_stress();
    test_atomic_cas();
    test_atomic_inc_dec();
    test_atomic_cas_contention();

    printf("=== Results: %d/%d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}

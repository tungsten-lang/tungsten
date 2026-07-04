/*
 * bench_args.c — Measure overhead of heap-allocated args array vs stack-passed args
 *
 * Simulates the hot path of Response.new(200, "Hello World\n"):
 *   1. Heap path: w_array_new + 2x w_array_push + w_method_call (current codegen)
 *   2. Pool path: same but with array recycling pool (current optimization)
 *   3. Stack path: args passed directly on C stack (what Go/JVM do)
 *
 * All three call the same handler that reads 2 args and returns a value.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

/* Minimal WValue simulation (NaN-boxed uint64_t) */
typedef uint64_t WValue;
#define W_NIL 0ULL

/* Minimal WArray */
typedef struct {
    WValue *items;
    int64_t length;
    int64_t capacity;
} WArray;

/* ---- Heap path (original codegen, no pool) ---- */

__attribute__((noinline)) static WArray *heap_array_new(void) {
    WArray *arr = calloc(1, sizeof(WArray));
    arr->capacity = 4;
    arr->items = calloc(1, sizeof(WValue) * arr->capacity);
    return arr;
}

__attribute__((noinline)) static void heap_array_push(WArray *arr, WValue val) {
    arr->items[arr->length++] = val;
}

__attribute__((noinline)) static WValue heap_dispatch(WArray *args) {
    /* Simulate reading 2 args */
    WValue a = args->items[0];
    WValue b = args->items[1];
    return a + b;
}

/* ---- Pool path (current optimization) ---- */

#define POOL_MAX 16
static WArray *pool_buf[POOL_MAX];
static int pool_count = 0;

__attribute__((noinline)) static WArray *pool_array_new(void) {
    if (pool_count > 0) {
        WArray *arr = pool_buf[--pool_count];
        arr->length = 0;
        return arr;
    }
    WArray *arr = calloc(1, sizeof(WArray));
    arr->capacity = 4;
    arr->items = calloc(1, sizeof(WValue) * arr->capacity);
    return arr;
}

__attribute__((noinline)) static void pool_array_recycle(WArray *arr) {
    if (pool_count < POOL_MAX) {
        pool_buf[pool_count++] = arr;
    }
}

__attribute__((noinline)) static void pool_array_push(WArray *arr, WValue val) {
    arr->items[arr->length++] = val;
}

__attribute__((noinline)) static WValue pool_dispatch(WArray *args) {
    WValue a = args->items[0];
    WValue b = args->items[1];
    return a + b;
}

/* ---- Stack path (direct args, no array) ---- */

__attribute__((noinline)) static WValue stack_dispatch(WValue arg0, WValue arg1) {
    return arg0 + arg1;
}

/* ---- Benchmark harness ---- */

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

int main(void) {
    const int N = 10000000; /* 10M iterations */
    volatile WValue sink = 0;
    uint64_t t0, t1;
    double ns;

    WValue arg0 = 200;
    WValue arg1 = 42;

    /* Warmup */
    for (int i = 0; i < 1000; i++) {
        WArray *a = pool_array_new();
        pool_array_push(a, arg0);
        pool_array_push(a, arg1);
        sink += pool_dispatch(a);
        pool_array_recycle(a);
    }

    /* 1. Heap path: malloc + free every call */
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        WArray *arr = heap_array_new();
        heap_array_push(arr, arg0);
        heap_array_push(arr, arg1);
        sink += heap_dispatch(arr);
        free(arr->items);
        free(arr);
    }
    t1 = now_ns();
    ns = (double)(t1 - t0) / N;
    printf("heap (malloc+free):  %6.1f ns/call\n", ns);

    /* 2. Heap path: malloc, no free (leak like before pools) */
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        WArray *arr = heap_array_new();
        heap_array_push(arr, arg0);
        heap_array_push(arr, arg1);
        sink += heap_dispatch(arr);
        /* leak */
    }
    t1 = now_ns();
    ns = (double)(t1 - t0) / N;
    printf("heap (malloc+leak):  %6.1f ns/call\n", ns);

    /* 3. Pool path: recycle */
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        WArray *arr = pool_array_new();
        pool_array_push(arr, arg0);
        pool_array_push(arr, arg1);
        sink += pool_dispatch(arr);
        pool_array_recycle(arr);
    }
    t1 = now_ns();
    ns = (double)(t1 - t0) / N;
    printf("pool (recycle):      %6.1f ns/call\n", ns);

    /* 4. Stack path: direct args */
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        sink += stack_dispatch(arg0, arg1);
    }
    t1 = now_ns();
    ns = (double)(t1 - t0) / N;
    printf("stack (direct):      %6.1f ns/call\n", ns);

    (void)sink;
    return 0;
}

// Benchmark: i32 vs i64 for array length/capacity operations
//
// Simulates the hot path of array access: bounds check, index compute,
// push with capacity check, and shift with start offset.
//
// Build: clang -O3 -march=native -o bench_i32_vs_i64 runtime/bench_i32_vs_i64.c
// Run:   ./bench_i32_vs_i64

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

#define ITERS 500000000

// -- i64 array layout (current) --

typedef struct {
    uint64_t *items;
    int64_t start;
    int64_t length;
    int64_t capacity;
} Array64;

// -- i32 array layout (proposed) --

typedef struct {
    uint64_t *items;
    int32_t start;
    int32_t length;
    int32_t capacity;
    int32_t _pad;  // align to 8
} Array32;

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// -- Bounds check (the hottest path: arr[i]) --

static __attribute__((noinline)) uint64_t bench_bounds_i64(Array64 *arr, int n) {
    uint64_t sum = 0;
    for (int i = 0; i < n; i++) {
        int64_t idx = i % arr->length;
        if (idx >= 0 && idx < arr->length) {
            sum += arr->items[arr->start + idx];
        }
    }
    return sum;
}

static __attribute__((noinline)) uint64_t bench_bounds_i32(Array32 *arr, int n) {
    uint64_t sum = 0;
    for (int i = 0; i < n; i++) {
        int32_t idx = i % arr->length;
        if (idx >= 0 && idx < arr->length) {
            sum += arr->items[arr->start + idx];
        }
    }
    return sum;
}

// -- Push simulation (capacity check + store) --

static __attribute__((noinline)) int64_t bench_push_i64(int n) {
    Array64 arr = { .items = malloc(sizeof(uint64_t) * 1024), .start = 0, .length = 0, .capacity = 1024 };
    int64_t ops = 0;
    for (int i = 0; i < n; i++) {
        if (arr.start + arr.length < arr.capacity) {
            arr.items[arr.start + arr.length] = (uint64_t)i;
            arr.length++;
            ops++;
        }
        if (arr.length >= 1000) {
            arr.start = 0;
            arr.length = 0;
        }
    }
    free(arr.items);
    return ops;
}

static __attribute__((noinline)) int64_t bench_push_i32(int n) {
    Array32 arr = { .items = malloc(sizeof(uint64_t) * 1024), .start = 0, .length = 0, .capacity = 1024, ._pad = 0 };
    int64_t ops = 0;
    for (int i = 0; i < n; i++) {
        if (arr.start + arr.length < arr.capacity) {
            arr.items[arr.start + arr.length] = (uint64_t)i;
            arr.length++;
            ops++;
        }
        if (arr.length >= 1000) {
            arr.start = 0;
            arr.length = 0;
        }
    }
    free(arr.items);
    return ops;
}

// -- Shift simulation (increment start) --

static __attribute__((noinline)) int64_t bench_shift_i64(int n) {
    Array64 arr = { .items = NULL, .start = 0, .length = 1000, .capacity = 2000 };
    int64_t sum = 0;
    for (int i = 0; i < n; i++) {
        if (arr.length > 0) {
            arr.start++;
            arr.length--;
            sum += arr.start;
        }
        if (arr.length == 0) {
            arr.start = 0;
            arr.length = 1000;
        }
    }
    return sum;
}

static __attribute__((noinline)) int64_t bench_shift_i32(int n) {
    Array32 arr = { .items = NULL, .start = 0, .length = 1000, .capacity = 2000, ._pad = 0 };
    int64_t sum = 0;
    for (int i = 0; i < n; i++) {
        if (arr.length > 0) {
            arr.start++;
            arr.length--;
            sum += arr.start;
        }
        if (arr.length == 0) {
            arr.start = 0;
            arr.length = 1000;
        }
    }
    return sum;
}

// -- Struct size comparison --

static __attribute__((noinline)) uint64_t bench_iterate_structs_i64(int n) {
    int count = 1024;
    Array64 *arrs = calloc(count, sizeof(Array64));
    for (int i = 0; i < count; i++) { arrs[i].length = i + 1; arrs[i].capacity = i + 8; }
    uint64_t sum = 0;
    for (int iter = 0; iter < n / count; iter++) {
        for (int i = 0; i < count; i++) {
            sum += arrs[i].length + arrs[i].capacity;
        }
    }
    free(arrs);
    return sum;
}

static __attribute__((noinline)) uint64_t bench_iterate_structs_i32(int n) {
    int count = 1024;
    Array32 *arrs = calloc(count, sizeof(Array32));
    for (int i = 0; i < count; i++) { arrs[i].length = i + 1; arrs[i].capacity = i + 8; }
    uint64_t sum = 0;
    for (int iter = 0; iter < n / count; iter++) {
        for (int i = 0; i < count; i++) {
            sum += arrs[i].length + arrs[i].capacity;
        }
    }
    free(arrs);
    return sum;
}

int main(void) {
    printf("Array struct sizes: i64=%zu bytes, i32=%zu bytes (%.0f%% smaller)\n",
           sizeof(Array64), sizeof(Array32),
           (1.0 - (double)sizeof(Array32) / sizeof(Array64)) * 100);
    printf("Iterations: %d\n\n", ITERS);

    double t;
    volatile uint64_t sink;

    // Bounds check
    uint64_t items[1024];
    for (int i = 0; i < 1024; i++) items[i] = i;
    Array64 a64 = { .items = items, .start = 0, .length = 1024, .capacity = 1024 };
    Array32 a32 = { .items = items, .start = 0, .length = 1024, .capacity = 1024 };

    t = now(); sink = bench_bounds_i64(&a64, ITERS); double t_bounds64 = now() - t;
    t = now(); sink = bench_bounds_i32(&a32, ITERS); double t_bounds32 = now() - t;
    printf("Bounds check:  i64 %.3fs  i32 %.3fs  (%+.1f%%)\n",
           t_bounds64, t_bounds32, (t_bounds32 / t_bounds64 - 1) * 100);

    // Push
    t = now(); sink = bench_push_i64(ITERS); double t_push64 = now() - t;
    t = now(); sink = bench_push_i32(ITERS); double t_push32 = now() - t;
    printf("Push:          i64 %.3fs  i32 %.3fs  (%+.1f%%)\n",
           t_push64, t_push32, (t_push32 / t_push64 - 1) * 100);

    // Shift
    t = now(); sink = bench_shift_i64(ITERS); double t_shift64 = now() - t;
    t = now(); sink = bench_shift_i32(ITERS); double t_shift32 = now() - t;
    printf("Shift:         i64 %.3fs  i32 %.3fs  (%+.1f%%)\n",
           t_shift64, t_shift32, (t_shift32 / t_shift64 - 1) * 100);

    // Struct iteration (cache effects)
    t = now(); sink = bench_iterate_structs_i64(ITERS); double t_iter64 = now() - t;
    t = now(); sink = bench_iterate_structs_i32(ITERS); double t_iter32 = now() - t;
    printf("Struct iter:   i64 %.3fs  i32 %.3fs  (%+.1f%%)\n",
           t_iter64, t_iter32, (t_iter32 / t_iter64 - 1) * 100);

    (void)sink;
    return 0;
}

/*
 * bench_location.c — Micro-benchmark for packed source locations.
 *
 * Part of AST task #1: moving per-node source locations off the
 * `g_ast_sparse_meta` side-table into a packed `W_PACKED_LOCATION`
 * WValue held in a real `@loc` slab slot. This harness measures the
 * new hot path — `w_box_location_file` / `w_unbox_location_line` —
 * against a stand-in for the cost it replaces: a hashed per-node
 * line/col side-table insert+probe.
 *
 * The location box/unbox helpers are pure W_PACKED_LOCATION bit math
 * (wvalue.h static inlines, no arena), so unlike bench_node.c this
 * harness is self-contained and links nothing.
 *
 * Compile + run (via runtime/Makefile):
 *   make bench-location
 *
 * Standalone:
 *   clang -O2 bench_location.c -o bench_location
 */

#include "wvalue.h"
#include <stdio.h>
#include <stdint.h>
#include <time.h>

/* ---- Benchmark harness ----
 * One untimed warm-up, then best-of-3 timed runs — the same shape as
 * bench_node.c, so a task's before/after numbers stay comparable
 * across the EXP-1 micro-benchmarks. The fastest run is the least
 * scheduler-perturbed and the most representative of true throughput. */
static double bench(const char *name, void (*fn)(int64_t), int64_t iters) {
    double best = 1e30;
    fn(iters);  /* warm-up — caches, CPU clock, first-touch pages */
    for (int r = 0; r < 3; r++) {
        struct timespec start, end;
        clock_gettime(CLOCK_MONOTONIC, &start);
        fn(iters);
        clock_gettime(CLOCK_MONOTONIC, &end);
        double elapsed = (end.tv_sec - start.tv_sec)
                       + (end.tv_nsec - start.tv_nsec) / 1e9;
        if (elapsed < best) best = elapsed;
    }
    double ops = iters / best;
    printf("  %-32s  %14.0f ops/s  (%7.3f ms)\n", name, ops, best * 1000);
    return ops;
}

/* ---- 1. Packed location box + unbox — the new @loc hot path ----
 * Every location-bearing node construction is one w_box_location_file
 * into a slab slot; every error/tooling read is one w_unbox. Pure bit
 * math on an immediate WValue — no memory traffic at all. */
static void bench_box_unbox(int64_t n) {
    volatile int64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        WValue loc = w_box_location_file((int)(i & 127),
                                         (int)(100 + i % 5000),
                                         (int)(i % 80));
        acc += w_unbox_location_line(loc);
    }
    (void)acc;
}

/* ---- 2. Sparse side-table stand-in — the cost task #1 removes ----
 * Before task #1, a node's :line/:col lived in g_ast_sparse_meta, a
 * hashed side-table: writing a location is a hash probe-to-slot, and
 * reading it back is another. This models that with a minimal
 * open-addressed map kept at a realistic AST load factor (~0.3) and
 * pre-populated, so the probe chains are representative. It is a rough
 * comparator for the box/unbox path above, not a byte-exact replica
 * of the Tungsten Hash-of-Hashes. */
#define SPARSE_CAP   (1 << 17)   /* 131072 slots, power of two */
#define SPARSE_LIVE  40000       /* representative live AST node count */

typedef struct { uint64_t key; int32_t line; int32_t col; } SparseEntry;
static SparseEntry g_sparse[SPARSE_CAP];

/* Slot 0 is the empty sentinel, so keys are stored as `node_id + 1`. */
static inline uint64_t sparse_slot(uint64_t key) {
    return (key * 0x9E3779B97F4A7C15ull) >> (64 - 17);
}

static void sparse_prefill(void) {
    for (int64_t i = 0; i < SPARSE_LIVE; i++) {
        uint64_t key = (uint64_t)i + 1;
        uint64_t h = sparse_slot(key);
        while (g_sparse[h].key != 0)
            h = (h + 1) & (SPARSE_CAP - 1);
        g_sparse[h].key = key;
    }
}

static void bench_sparse_baseline(int64_t n) {
    volatile int64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        uint64_t key = (uint64_t)(i % SPARSE_LIVE) + 1;
        /* write :line + :col — probe to the node's slot */
        uint64_t h = sparse_slot(key);
        while (g_sparse[h].key != key)
            h = (h + 1) & (SPARSE_CAP - 1);
        g_sparse[h].line = (int32_t)(100 + i % 5000);
        g_sparse[h].col  = (int32_t)(i % 80);
        /* read :line back — a second probe */
        uint64_t p = sparse_slot(key);
        while (g_sparse[p].key != key)
            p = (p + 1) & (SPARSE_CAP - 1);
        acc += g_sparse[p].line;
    }
    (void)acc;
}

int main(void) {
    printf("bench_location — packed source-location micro-benchmark\n");
    printf("(AST task #1 — @loc slab slot vs the sparse side-table)\n\n");

    const int64_t N = 20000000;
    bench("box+unbox (packed @loc)",      bench_box_unbox, N);
    sparse_prefill();
    bench("write+read (sparse side-table)", bench_sparse_baseline, N);

    return 0;
}

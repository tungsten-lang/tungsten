/*
 * bench_node.c — Micro-benchmark for the slab AST node arenas.
 *
 * Part of EXP-1 (the AST performance lab). Measures the hot slab-AST
 * operations every roadmap task touches: node allocation across size
 * classes, field store/load, the between-compiles reset+init cycle,
 * and per-size-class peak memory. Gives each AST-improvement task a
 * real before/after number instead of a hunch.
 *
 * Compile + run (via runtime/Makefile):
 *   make bench-node
 *
 * Standalone:
 *   clang -O2 runtime.c <event backend> ... bench_node.c -o bench_node
 */

#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* No-slab node constructors. w_node_inline_payload packs a small payload
 * into the W_PACKED_NODE offset bits; w_node_singleton makes a tag-only
 * node — both allocate nothing (sc=0, no arena touch). Called via
 * ccall_nobox from Tungsten, so they are not in runtime.h; declared here
 * for the benchmark's direct C use. */
int64_t w_node_inline_payload(int64_t kind, int64_t payload);
int64_t w_node_singleton(int64_t kind);

/* ---- Benchmark harness ----
 * One untimed warm-up run, then best-of-3 timed runs. The fastest run
 * is the least scheduler-perturbed and the most representative of true
 * throughput; reporting it keeps run-to-run variance low enough that a
 * 5%-threshold regression tracker (scripts/bench-ast.sh) is meaningful.
 * Single-shot timing swung ~47% run-to-run — useless as a baseline. */
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
    printf("  %-30s  %14.0f ops/s  (%7.3f ms)\n", name, ops, best * 1000);
    return ops;
}

/* Between-compiles cycle. w_node_arena_reset() invalidates handles and
 * rewinds Store cursors while retaining high-water buffers for reuse;
 * w_node_arena_init() remains the paired compatibility boundary. */
static void arena_cycle(void) {
    w_node_arena_reset();
    w_node_arena_init();
}

/* ---- 1. Node allocation throughput ----
 * Pure bump: w_node_alloc is `off = cursor++` plus a bit-pack. Measured
 * on SC_2 (the dominant AST kind) as ONE representative number.
 *
 * NOT split per size class. Bump throughput physically cannot depend on
 * node size, yet a per-SC split produced a stable, unexplained ~68%
 * spread (SC_2 < SC_4 < SC_8) — measurement artifact, not signal, and
 * shipping it would poison every later before/after comparison. What
 * the roadmap's allocation-touching tasks (#2 inline leaves, #8 COW)
 * actually move is node COUNT and peak MEMORY — and report_arena_peak
 * below measures those deterministically (0% run-to-run variance).
 *
 * Batched at 2M (far above every g_node_initial_cap) so the per-batch
 * realloc-doublings and the ~10 reset+init cycles across 20M allocs
 * amortize to nothing; memory stays bounded at ~2M live nodes. */
static void bench_alloc(int64_t n) {
    int64_t i = 0;
    while (i < n) {
        int64_t batch = 2000000;
        if (i + batch > n) batch = n - i;
        for (int64_t j = 0; j < batch; j++) {
            volatile WValue node = w_node_alloc(92 /* one-word Program */, 0);
            (void)node;
        }
        arena_cycle();
        i += batch;
    }
}

/* ---- 1b. No-slab node creation — inline-payload + singleton ----
 * These allocate NOTHING: the node lives entirely in the W_PACKED_NODE
 * bits (sc=0; payload, or 0, in the offset field). This is the path
 * task #2 (inline leaves) moves leaf kinds onto — so these are the
 * "after" numbers for #2, where node_alloc above is the "before". No
 * arena, no cursor, no reset: pure bit-pack. */
static void bench_inline(int64_t n) {
    volatile WValue node = 0;
    for (int64_t i = 0; i < n; i++) {
        node = (WValue)w_node_inline_payload(1 /* kind */, i);
    }
    (void)node;
}
static void bench_singleton(int64_t n) {
    volatile WValue node = 0;
    for (int64_t i = 0; i < n; i++) {
        node = (WValue)w_node_singleton(1 /* kind */);
    }
    (void)node;
}

/* ---- 2. Field store + load — the hot AST field-access path ---- */
static void bench_field(int64_t n) {
    WValue node = w_node_alloc(66 /* seven-word GPU kernel */, 2);
    volatile WValue acc = 0;
    for (int64_t i = 0; i < n; i++) {
        w_node_field_store(node, i % 7, w_box_int(i));
        acc += w_node_field_load(node, i % 7);
    }
    arena_cycle();
}

/* ---- 3. Between-compiles reset+init cost (alloc 256, cycle, repeat) ---- */
static void bench_reset(int64_t n) {
    for (int64_t i = 0; i < n; i++) {
        for (int64_t j = 0; j < 256; j++) {
            volatile WValue node = w_node_alloc(92, 0);
            (void)node;
        }
        arena_cycle();
    }
}

/* ---- Peak arena bytes — the per-size-class memory stat ---- */
static void report_arena_peak(void) {
    arena_cycle();
    /* Same shape as the old report: 100K one-word, 50K three-word, and
     * 25K seven-word nodes. Exact storage is 425K field words. */
    for (int64_t i = 0; i < 100000; i++) {
        w_node_alloc(92, 0);
        if (i % 2 == 0) w_node_alloc(35, 1);
        if (i % 4 == 0) w_node_alloc(66, 2);
    }
    uint64_t words = (uint64_t)g_node_arena.cursor - 1;
    uint64_t bytes = words * sizeof(WValue);
    printf("\nPeak exact arena (100k x1 + 50k x3 + 25k x7):\n");
    printf("  words=%-9llu cap=%-9u live=%9.2f KB reserved=%9.2f KB\n",
           (unsigned long long)words, g_node_arena.cap, bytes / 1024.0,
           (double)g_node_arena.cap * sizeof(WValue) / 1024.0);
    arena_cycle();
}

int main(void) {
    w_node_arena_init();
    printf("bench_node — slab AST arena micro-benchmark\n");
    printf("(EXP-1 perf lab — baseline for the AST-improvement roadmap)\n\n");

    /* reset+init keeps its own (far smaller) count below — it is
     * ~400x slower per op, so N iterations would run for minutes. */
    const int64_t N = 50000000;
    bench("node_alloc (slab)",      bench_alloc,     N);
    bench("inline-payload create",  bench_inline,    N);
    bench("singleton create",       bench_singleton, N);
    bench("field store+load",       bench_field,     N);
    bench("reset+init (/256)",      bench_reset,     200000);

    report_arena_peak();
    return 0;
}

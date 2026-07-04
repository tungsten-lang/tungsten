/*
 * test_node_arena.c — Phase 1 smoke test for the slab-AST node arenas.
 *
 * Verifies:
 *   1. w_node_arena_init() allocates per-SC buffers with the expected caps.
 *   2. w_node_alloc(kind, sc) returns sequential offsets within an SC.
 *   3. The returned W_PACKED_NODE WValue round-trips: w_is_node /
 *      w_node_kind / w_node_size_class / w_node_offset extract the
 *      same values that were boxed in.
 *   4. realloc-doubling fires when cursor reaches cap, and post-realloc
 *      allocations continue from the correct offset.
 *   5. w_node_arena_reset() returns all arenas to a clean state.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include "../runtime.h"  /* pulls in wvalue.h transitively */

static int failures = 0;
#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); failures++; } \
} while (0)

static void test_init_state(void) {
    w_node_arena_init();
    CHECK(g_node_arena[0].base != NULL, "SC_0 base allocated");
    CHECK(g_node_arena[0].cap   == g_node_initial_cap[0], "SC_0 cap matches initial");
    CHECK(g_node_arena[0].cursor == 0, "SC_0 cursor starts at 0");
    CHECK(g_node_arena[1].base != NULL, "SC_1 base allocated");
    CHECK(g_node_arena[1].cap   == g_node_initial_cap[1], "SC_1 cap matches initial");
    CHECK(g_node_arena[2].base != NULL, "SC_2 base allocated");
}

static void test_alloc_roundtrip(void) {
    /* Alloc one node of kind 7 in SC_0; verify all the boxed bits survive. */
    WValue n = w_node_alloc(/*kind=*/7, /*sc=*/0);
    CHECK(w_is_node(n),                "result is W_PACKED_NODE");
    CHECK(w_node_kind(n) == 7,         "kind round-trips");
    CHECK(w_node_size_class(n) == 0,   "size_class round-trips");
    CHECK(w_node_offset(n) == 0,       "first alloc has offset 0");

    /* Three more allocations bump the cursor in order. */
    WValue a = w_node_alloc(11, 0);
    WValue b = w_node_alloc(13, 1);   /* different SC */
    WValue c = w_node_alloc(17, 0);
    CHECK(w_node_offset(a) == 1, "SC_0 second offset is 1");
    CHECK(w_node_offset(b) == 0, "SC_1 first offset is 0");
    CHECK(w_node_offset(c) == 2, "SC_0 third offset is 2");
    CHECK(w_node_kind(a) == 11,  "SC_0 second kind ok");
    CHECK(w_node_kind(b) == 13,  "SC_1 first kind ok");
    CHECK(w_node_kind(c) == 17,  "SC_0 third kind ok");
}

static void test_kind_bits_max(void) {
    /* Kind field is 11 bits → max 2047. Confirm the boundary round-trips. */
    WValue n = w_node_alloc(2047, 1);
    CHECK(w_node_kind(n) == 2047, "kind 2047 (max 11-bit) round-trips");
}

static void test_realloc_doubling(void) {
    /* Force an SC_2 realloc by allocating cap+1 nodes there. SC_2's
     * initial cap is small (1000), so this stays cheap. */
    uint32_t initial_cap = g_node_arena[2].cap;
    CHECK(initial_cap > 0, "SC_2 initial cap is positive");

    /* Burn up to cap-1 (we already have 0 in cursor; just allocate cap). */
    for (uint32_t i = 0; i < initial_cap; i++) {
        WValue n = w_node_alloc(1, 2);
        (void)n;
    }
    CHECK(g_node_arena[2].cursor == initial_cap, "cursor at cap before realloc");
    CHECK(g_node_arena[2].cap    == initial_cap, "cap unchanged before realloc");

    /* Next alloc triggers realloc-doubling. */
    WValue trigger = w_node_alloc(1, 2);
    CHECK(g_node_arena[2].cap == initial_cap * 2, "cap doubled on overflow");
    CHECK(w_node_offset(trigger) == initial_cap,  "offset continues past initial cap");
    /* Read back a slot from BEFORE the realloc to ensure data survived
     * the (potentially-moving) realloc. We didn't write any payload, so
     * just check the base is non-null and the offset is still in range. */
    CHECK(g_node_arena[2].base != NULL, "base still valid post-realloc");
}

static void test_reset(void) {
    w_node_arena_reset();
    CHECK(g_node_arena[0].base == NULL,   "SC_0 base freed");
    CHECK(g_node_arena[0].cursor == 0,    "SC_0 cursor reset");
    CHECK(g_node_arena[0].cap == 0,       "SC_0 cap reset");
    CHECK(g_node_arena[1].base == NULL,   "SC_1 base freed");
    CHECK(g_node_arena[2].base == NULL,   "SC_2 base freed");
}

static void test_reuse_after_reset(void) {
    /* A fresh init+alloc after reset should work like the first time. */
    w_node_arena_init();
    WValue n = w_node_alloc(42, 0);
    CHECK(w_node_kind(n) == 42,        "kind ok after reset+reinit");
    CHECK(w_node_offset(n) == 0,       "offset resets to 0 on reinit");
    w_node_arena_reset();
}

int main(void) {
    test_init_state();
    test_alloc_roundtrip();
    test_kind_bits_max();
    test_realloc_doubling();
    test_reset();
    test_reuse_after_reset();

    if (failures) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    printf("test_node_arena: PASS\n");
    return 0;
}

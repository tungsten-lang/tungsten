/*
 * test_node_arena.c — smoke test for the slab-AST node arenas.
 *
 * Verifies:
 *   1. w_node_arena_init() preserves lazy allocation.
 *   2. w_node_alloc(kind, sc) returns exact-width word offsets.
 *   3. The returned W_PACKED_NODE WValue round-trips: w_is_node /
 *      w_node_kind / w_node_size_class / w_node_offset extract the
 *      same values that were boxed in.
 *   4. realloc-doubling fires when cursor reaches cap, and post-realloc
 *      allocations continue from the correct offset.
 *   5. w_node_arena_reset() invalidates the generation, rewinds the cursor,
 *      and retains the high-water allocation for reuse.
 *   6. Packed WIRE handles use their reserved compact-tier marker, preserve
 *      symbol/value fields, clone independently, and reuse arena capacity.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include "../runtime.h"  /* pulls in wvalue.h transitively */
#include "../ast_schema_generated.h"

static int failures = 0;
#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); failures++; } \
} while (0)

static void test_init_state(void) {
    w_node_arena_init();
    CHECK(g_node_arena.base == NULL, "word arena stays lazy");
    CHECK(g_node_arena.cap == 0, "word arena has no eager capacity");
    CHECK(g_node_arena.cursor == 0, "cursor starts at zero before first touch");
}

static void test_alloc_roundtrip(void) {
    /* Program has one field word. */
    WValue n = w_node_alloc(/*KIND_PROGRAM=*/92, /*layout class=*/0);
    CHECK(w_is_node(n),                "result is W_PACKED_NODE");
    CHECK(w_node_kind(n) == 92,        "kind round-trips");
    CHECK(w_node_size_class(n) == 0,   "size_class round-trips");
    CHECK(w_node_offset(n) == 1,       "first alloc follows reserved offset 0");

    /* Exact widths: And=2, Assign=3, Program=1. */
    WValue a = w_node_alloc(33, 0);
    WValue b = w_node_alloc(35, 1);
    WValue c = w_node_alloc(92, 0);
    CHECK(w_node_offset(a) == 2, "SC_0 second offset is 2");
    CHECK(w_node_offset(b) == 4, "three-word node follows two-word node");
    CHECK(w_node_offset(c) == 7, "one-word node follows exact three words");
    CHECK(w_node_kind(a) == 33,  "second kind ok");
    CHECK(w_node_kind(b) == 35,  "third kind ok");
    CHECK(w_node_kind(c) == 92,  "fourth kind ok");
}

static void test_kind_bits_max(void) {
    /* Confirm the generated schema boundary round-trips. Derive its layout
     * class from the generated width so this test follows future additions. */
    uint32_t width = W_AST_KIND_WIDTH[W_AST_KIND_MAX];
    int sc = width <= 2 ? 0 : (width == 3 ? 1 : 2);
    WValue n = w_node_alloc(W_AST_KIND_MAX, sc);
    CHECK(w_node_kind(n) == W_AST_KIND_MAX, "current maximum kind round-trips");
}

static void test_realloc_doubling(void) {
    /* Fill the exact-width arena with one-word Program nodes. */
    WValue first = w_node_alloc(92, 0);
    (void)first;
    uint32_t initial_cap = g_node_arena.cap;
    CHECK(initial_cap > 0, "initial word capacity is positive");

    /* Fill through the final available offset. */
    while (g_node_arena.cursor < initial_cap) {
        WValue n = w_node_alloc(92, 0);
        (void)n;
    }
    CHECK(g_node_arena.cursor == initial_cap, "cursor at cap before realloc");
    CHECK(g_node_arena.cap == initial_cap, "cap unchanged before realloc");

    /* Next alloc triggers realloc-doubling. */
    WValue trigger = w_node_alloc(92, 0);
    CHECK(g_node_arena.cap == initial_cap * 2, "cap doubled on overflow");
    CHECK(w_node_offset(trigger) == initial_cap,  "offset continues past initial cap");
    /* Read back a slot from BEFORE the realloc to ensure data survived
     * the (potentially-moving) realloc. We didn't write any payload, so
     * just check the base is non-null and the offset is still in range. */
    CHECK(g_node_arena.base != NULL, "base still valid post-realloc");
}

static void test_reset(void) {
    WValue *retained_base = g_node_arena.base;
    uint32_t retained_cap = g_node_arena.cap;
    w_node_arena_reset();
    CHECK(g_node_arena.base == retained_base, "word arena base retained");
    CHECK(g_node_arena.cursor == 1, "cursor preserves offset zero");
    CHECK(g_node_arena.cap == retained_cap, "word arena capacity retained");
}

static void test_reuse_after_reset(void) {
    /* A fresh init+alloc after reset should work like the first time. */
    w_node_arena_init();
    WValue n = w_node_alloc(92, 0);
    CHECK(w_node_kind(n) == 92,        "kind ok after reset+reinit");
    CHECK(w_node_offset(n) == 1,       "offset resets to 1 on reinit");
    w_node_arena_reset();
}

static void test_wire_arena(void) {
    WValue key_op = w_box_int(11);
    WValue key_arg = w_box_int(12);
    WValue original = w_wire_alloc(/*stable opcode kind=*/37, 2);

    CHECK(w_is_wire(original), "WIRE allocation returns a packed WIRE handle");
    CHECK(!w_is_node(original), "WIRE handle is not classified as an AST node");
    CHECK(w_wire_kind(original) == 37, "WIRE opcode kind round-trips");
    CHECK(w_wire_offset(original) == 1, "first WIRE record starts after offset zero");

    w_wire_field_store_at(original, 0, key_op, w_box_int(37));
    w_wire_field_store_at(original, 1, key_arg, w_box_int(99));
    CHECK(w_wire_field_count(original) == 2,
          "WIRE canonical field count round-trips");
    CHECK(w_wire_field_symbol_at(original, 0) == key_op &&
          w_wire_field_symbol_at(original, 1) == key_arg,
          "WIRE canonical field symbols preserve schema order");
    CHECK(w_as_int(w_wire_field_value_at(original, 0)) == 37 &&
          w_as_int(w_wire_field_value_at(original, 1)) == 99,
          "WIRE canonical field values support ordinal walking");
    CHECK(w_as_int(w_wire_field_load(original, key_arg)) == 99,
          "WIRE field lookup round-trips");
    CHECK(w_wire_field_load(original, w_box_int(404)) == W_UNDEF,
          "missing WIRE field returns W_UNDEF");

    WValue clone = w_wire_clone(original);
    w_wire_field_store(clone, key_arg, w_box_int(100));
    CHECK(w_as_int(w_wire_field_load(original, key_arg)) == 99,
          "WIRE clone does not mutate original record");
    CHECK(w_as_int(w_wire_field_load(clone, key_arg)) == 100,
          "WIRE clone accepts in-place field rewrite");

    WValue *retained_base = g_wire_arena.base;
    uint32_t retained_cap = g_wire_arena.cap;
    int64_t retained_mark = w_wire_store_mark();
    WValue retained = original;
    w_wire_store_reset(retained_mark);
    CHECK(g_wire_arena.cursor == (uint32_t)retained_mark,
          "WIRE reset can preserve an immutable prefix");
    CHECK(w_as_int(w_wire_field_load(retained, key_arg)) == 99,
          "WIRE retained-prefix handles remain readable");
    WValue overlay = w_wire_alloc(38, 1);
    CHECK(w_wire_offset(overlay) == (uint32_t)retained_mark,
          "WIRE overlay begins at the retained watermark");
    w_wire_store_reset(0);
    CHECK(g_wire_arena.base == retained_base, "WIRE reset retains high-water buffer");
    CHECK(g_wire_arena.cursor == 1, "WIRE reset rewinds to first valid offset");
    CHECK(g_wire_arena.cap == retained_cap, "WIRE reset retains capacity");
}

int main(void) {
    test_init_state();
    test_alloc_roundtrip();
    test_kind_bits_max();
    test_realloc_doubling();
    test_reset();
    test_reuse_after_reset();
    test_wire_arena();

    if (failures) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    printf("test_node_arena: PASS\n");
    return 0;
}

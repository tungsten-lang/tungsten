/*
 * test_ivars.c — Ivar layout and lookup regression tests
 *
 * Covers WValue-keyed ivar lookup, especially the content-equality fallback
 * for heap strings that have the same bytes but different identities.
 */

#include "../runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int pass_count = 0;
static int test_count = 0;

#define ASSERT(cond, msg) do { \
    test_count++; \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        pass_count++; \
    } \
} while (0)

static WValue heap_string(const char *s) {
    size_t len = strlen(s);
    WString *ws = malloc(sizeof(WString) + len + 1);
    w_heap_string_set_meta(ws, (uint32_t)len, 1);
    memcpy(ws->data, s, len + 1);
    return w_box_heap_str(ws);
}

static void test_heap_string_ivar_lookup_by_content(void) {
    printf("\nTest 1: Heap-string ivar names match by content\n");

    const char *name = "@field_name_long_enough_to_force_heap_storage_and_distinct_identity";
    WValue klass = w_class_new("HeapIvarContentFallback", W_NIL);
    WValue registered_name = heap_string(name);
    WValue lookup_name = heap_string(name);

    ASSERT(registered_name != lookup_name, "fixture creates distinct heap string WValues");

    int offset = w_class_add_ivar_wv(klass, registered_name);
    ASSERT(offset == 0, "first ivar is offset 0");
    ASSERT(w_class_add_ivar_wv(klass, lookup_name) == offset, "duplicate heap name reuses existing offset");
    ASSERT(w_class_ivar_offset_wv(klass, lookup_name) == offset, "offset lookup finds distinct heap string by content");

    WValue obj = w_object_new(klass);
    w_ivar_set_wv(obj, lookup_name, w_int(123));
    ASSERT(w_eq(w_ivar_get_wv(obj, registered_name), w_int(123)) == W_TRUE, "get via original heap name returns stored value");
}

static void test_recycled_object_shell_is_reset(void) {
    printf("\nTest 2: Recycled object shells reset class and ivars\n");

    WValue first_class = w_class_new("ObjectPoolFirst", W_NIL);
    w_class_add_ivar(first_class, "@left");
    w_class_add_ivar(first_class, "@right");
    WValue first = w_object_recycle_or_new(first_class);
    WObject *first_ptr = (WObject *)w_as_ptr(first);
    w_ivar_set_idx(first, 0, w_int(41));
    w_ivar_set_idx(first, 1, w_int(42));
    w_object_recycle(first);

    WValue second_class = w_class_new("ObjectPoolSecond", W_NIL);
    w_class_add_ivar(second_class, "@value");
    WValue second = w_object_recycle_or_new(second_class);
    WObject *second_ptr = (WObject *)w_as_ptr(second);
    WClass *second_class_ptr = (WClass *)w_as_ptr(second_class);

    ASSERT(second_ptr == first_ptr, "common object shell is reused");
    ASSERT(second_ptr->class_id == second_class_ptr->class_id, "reused shell receives the new class id");
    ASSERT(second_ptr->flags == 0, "pooled flag is cleared on reuse");
    ASSERT(w_ivar_get_idx(second, 0) == W_NIL, "old ivar values are cleared");
    ASSERT(w_ivar_get_idx(second, 1) == W_NIL, "all common-shape slots are cleared");

    /* A live shell has already been popped, so a nested allocation cannot
     * alias it even when it has the same class and shape. */
    WValue nested = w_object_recycle_or_new(second_class);
    ASSERT(w_as_ptr(nested) != w_as_ptr(second), "simultaneously live shells remain distinct");
    w_object_recycle(nested);
    w_object_recycle(second);

    /* Frozen instances are deliberately leaked by the ordinary ownership
     * release too: they may have become shared after construction. They must
     * never enter the recycler even when their original allocation used the
     * recyclable entry point. */
    WValue frozen = w_object_recycle_or_new(second_class);
    WObject *frozen_ptr = (WObject *)w_as_ptr(frozen);
    frozen_ptr->flags |= W_OBJ_FLAG_FROZEN;
    w_object_recycle(frozen);
    WValue replacement = w_object_recycle_or_new(second_class);
    ASSERT(w_as_ptr(replacement) != frozen_ptr, "frozen instance is not reused");

    /* A duplicate release and the generic release helper both see the pooled
     * marker and leave the one stack entry intact. */
    WObject *replacement_ptr = (WObject *)w_as_ptr(replacement);
    w_object_recycle(replacement);
    w_object_recycle(replacement);
    w_value_free(replacement);
    WValue reused_once = w_object_recycle_or_new(second_class);
    ASSERT(w_as_ptr(reused_once) == replacement_ptr, "pooled shell survives duplicate release attempts");
    WValue concurrently_live = w_object_recycle_or_new(second_class);
    ASSERT(w_as_ptr(concurrently_live) != replacement_ptr, "pooled shell is popped only once");
    w_object_recycle(concurrently_live);
    w_object_recycle(reused_once);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("=== Ivar Regression Tests ===\n");

    test_heap_string_ivar_lookup_by_content();
    test_recycled_object_shell_is_reset();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

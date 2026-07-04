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
    ws->len = (uint32_t)len;
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

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("=== Ivar Regression Tests ===\n");

    test_heap_string_ivar_lookup_by_content();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

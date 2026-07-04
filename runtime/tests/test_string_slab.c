/*
 * test_string_slab.c — String slab freeze regression tests
 *
 * Verifies that strings loaded into the static slab still resolve to the same
 * WValue after freeze, so builtin method dispatch can compare method names by
 * identity even when the dispatch tables initialize lazily.
 */

#include "../runtime.h"
#include <stdio.h>
#include <string.h>

static int pass_count = 0;
static int test_count = 0;
static const char *k_long_slab_string = "abcdefghijklmnopqrstuvwxyz12345678";

#define ASSERT(cond, msg) do { \
    test_count++; \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        pass_count++; \
    } \
} while (0)

static const char *value_str(WValue v) {
    static char buf[6];
    const char *out;
    size_t len;
    w_str_data(v, buf, &out, &len);
    return out;
}

static void encode_static_slab_string(uint8_t *slab_data, uint32_t slot_index, const char *text) {
    size_t len = strlen(text);
    uint8_t *slot = slab_data + ((size_t)slot_index * W_SLAB_SLOT_SIZE);
    uint8_t flags = W_SFLAG_INLINE;

    if (len > W_SLAB_SSO_MAX) flags |= W_SFLAG_CONTINUATION;
    slot[0] = flags;
    slot[1] = (uint8_t)len;

    size_t first_len = len;
    if (first_len > W_SLAB_INLINE_BYTES) first_len = W_SLAB_INLINE_BYTES;
    memcpy(slot + W_SLAB_DATA_OFFSET, text, first_len);

    if (flags & W_SFLAG_CONTINUATION) {
        uint8_t *cont = slot + W_SLAB_SLOT_SIZE;
        size_t second_len = len - first_len;
        memcpy(cont + W_SLAB_CONT_DATA_OFFSET, text + first_len, second_len);
    }
}

static void load_static_length_string(void) {
    static uint8_t slab_data[W_SLAB_SLOT_SIZE * 7] = {0};
    static int initialized = 0;

    if (!initialized) {
        encode_static_slab_string(slab_data, 1, "length");
        encode_static_slab_string(slab_data, 2, k_long_slab_string);
        encode_static_slab_string(slab_data, 4, "ends_with?");
        encode_static_slab_string(slab_data, 5, "ends_with?");
        encode_static_slab_string(slab_data, 6, "hello world");
        initialized = 1;
    }

    w_slab_init_static(slab_data, 7);
}

static void test_frozen_lookup_returns_static_slab_entry(void) {
    printf("\nTest 1: Frozen lookup reuses static slab entry\n");

    load_static_length_string();
    ASSERT(w_slab_is_frozen() == 0, "slab starts unfrozen after static init");

    WValue before = w_string("length");
    ASSERT(w_is_slab(before), "pre-freeze lookup returns slab string");
    WValue long_before = w_string(k_long_slab_string);
    ASSERT(w_is_slab(long_before), "pre-freeze 2-slot lookup returns slab string");
    ASSERT(strcmp(value_str(long_before), k_long_slab_string) == 0, "pre-freeze 2-slot lookup reads full contents");

    w_slab_freeze();
    ASSERT(w_slab_is_frozen() == 1, "freeze flips slab to frozen");

    WValue after = w_string("length");
    ASSERT(w_is_slab(after), "post-freeze lookup returns slab string");
    ASSERT(before == after, "post-freeze lookup preserves WValue identity");
    WValue long_after = w_string(k_long_slab_string);
    ASSERT(w_is_slab(long_after), "post-freeze 2-slot lookup returns slab string");
    ASSERT(long_before == long_after, "post-freeze 2-slot lookup preserves WValue identity");
    ASSERT(strcmp(value_str(long_after), k_long_slab_string) == 0, "post-freeze 2-slot lookup reads full contents");
}

static void test_builtin_dispatch_after_freeze(void) {
    printf("\nTest 2: Builtin dispatch still matches frozen slab names\n");

    WValue arr = w_array_new_empty();
    w_array_push(arr, w_int(10));
    w_array_push(arr, w_int(20));

    WValue method_name = w_string("length");
    WValue result = w_method_call_fast(arr, method_name, NULL, 0);

    ASSERT(w_eq(result, w_int(2)) == W_TRUE, "Array#length dispatch succeeds after freeze");
}

static void test_string_and_symbol_share_slab_index(void) {
    printf("\nTest 3: Strings and symbols share the same slab entry\n");

    load_static_length_string();

    WValue str = w_string("hello world");
    WValue sym = w_symbol("hello world");

    ASSERT(w_is_slab_str(str), "w_string returns a slab string for hello world");
    ASSERT(w_is_slab_sym(sym), "w_symbol returns a slab symbol for hello world");
    ASSERT(w_as_slab_index(str) == w_as_slab_index(sym), "string and symbol share the same slab index");
}

static void test_duplicate_slab_strings_hash_by_content(void) {
    printf("\nTest 4: Duplicate slab strings still hash by content\n");

    load_static_length_string();

    WValue first = w_box_slab_str(4);
    WValue second = w_box_slab_str(5);
    ASSERT(first != second, "duplicate slab entries have distinct identities");
    ASSERT(w_eq(first, second) == W_FALSE, "duplicate slab entries remain distinct under ==");

    WValue hash = w_hash_new();
    w_hash_set(hash, first, w_int(7));
    ASSERT(w_eq(w_hash_get(hash, second), w_int(7)) == W_TRUE, "hash lookup matches duplicate slab string content");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("=== String Slab Regression Tests ===\n");

    test_frozen_lookup_returns_static_slab_entry();
    test_builtin_dispatch_after_freeze();
    test_string_and_symbol_share_slab_index();
    test_duplicate_slab_strings_hash_by_content();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

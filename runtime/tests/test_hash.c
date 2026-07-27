/*
 * test_hash.c — Hash table regression tests
 *
 * Covers rope-vs-string key equality so hashing and lookup stay consistent
 * across string representations and table growth.
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
} while(0)

static void test_rope_key_lookup(void) {
    printf("\nTest 1: Rope and flat string keys are interchangeable\n");

    WValue hash = w_hash_new();
    WValue rope_key = w_str_concat(
        w_string("function_name_that_is_long_prefix_"),
        w_string("and_even_longer_suffix_value"));
    WValue flat_key = w_string("function_name_that_is_long_prefix_and_even_longer_suffix_value");
    WRope *rope = (WRope *)w_as_ptr(rope_key);

    w_hash_set(hash, rope_key, w_int(42));

    ASSERT(w_is_rope(rope_key), "concat produces a real rope");
    ASSERT(rope->flat == 0, "rope starts unflattened");
    ASSERT(w_eq(rope_key, flat_key) == W_TRUE, "rope key equals flat key");
    ASSERT(rope->flat == 0, "equality does not flatten rope");
    ASSERT(w_hash_has_key(hash, flat_key) == W_TRUE, "flat lookup finds rope-inserted key");
    ASSERT(w_eq(w_hash_get(hash, flat_key), w_int(42)) == W_TRUE, "flat lookup returns stored value");
    ASSERT(rope->flat == 0, "hash lookup does not flatten rope");
}

static void test_rope_keys_survive_growth(void) {
    printf("\nTest 2: Rope keys survive growth and rehash\n");

    WValue hash = w_hash_new();
    char prefix[96];
    char suffix[96];
    char full[192];

    for (int i = 0; i < 512; i++) {
        snprintf(prefix, sizeof(prefix), "compiled_function_name_prefix_component_%03d_", i);
        snprintf(suffix, sizeof(suffix), "very_long_name_suffix_component_%03d", i);
        snprintf(full, sizeof(full), "%s%s", prefix, suffix);
        WValue key = w_str_concat(w_string(prefix), w_string(suffix));
        ASSERT(w_is_rope(key), "growth fixture key is a rope");
        w_hash_set(hash, key, w_int(i));
    }

    for (int i = 0; i < 512; i++) {
        snprintf(prefix, sizeof(prefix), "compiled_function_name_prefix_component_%03d_", i);
        snprintf(suffix, sizeof(suffix), "very_long_name_suffix_component_%03d", i);
        snprintf(full, sizeof(full), "%s%s", prefix, suffix);

        WValue key = w_string(full);
        ASSERT(w_hash_has_key(hash, key) == W_TRUE, "grown table lookup finds flat key");
        ASSERT(w_eq(w_hash_get(hash, key), w_int(i)) == W_TRUE, "grown table returns correct value");
    }
}

static void test_rope_string_ordering(void) {
    printf("\nTest 3: Rope and flat string ordering agree\n");

    WValue rope = w_str_concat(
        w_string("emit_artifact_name_that_is_definitely_long_"),
        w_string("and_continues_past_the_slab_limit"));
    WValue flat = w_string(
        "emit_artifact_name_that_is_definitely_long_and_continues_past_the_slab_limit");
    WValue later = w_string(
        "emit_artifact_name_that_is_definitely_long_and_continues_past_the_slab_zlimit");

    ASSERT(w_is_rope(rope), "ordering fixture value is a rope");
    ASSERT(w_eq(rope, flat) == W_TRUE, "rope equals flat string");
    ASSERT(w_lt(rope, later) == W_TRUE, "rope compares less than later flat string");
    ASSERT(w_gt(later, rope) == W_TRUE, "flat compares greater than rope");
    ASSERT(w_lte(rope, flat) == W_TRUE, "rope is <= equivalent flat string");
    ASSERT(w_gte(flat, rope) == W_TRUE, "flat is >= equivalent rope");
}

static void test_inline_symbol_string_distinct(void) {
    printf("\nTest 4: Inline symbols and strings are distinct types\n");

    WValue hash = w_hash_new();
    WValue symbol_key = w_box_symbol_from_str(w_box_inline_str("op", 2));
    WValue string_key = w_string("op");

    /* Symbol and string with same content are NOT equal */
    ASSERT(w_eq(symbol_key, string_key) == W_FALSE, "inline symbol != inline string");

    /* Both can coexist as separate keys in the same hash */
    w_hash_set(hash, symbol_key, w_int(7));
    w_hash_set(hash, string_key, w_int(42));

    ASSERT(w_eq(w_hash_get(hash, symbol_key), w_int(7)) == W_TRUE, "symbol key retrieves symbol value");
    ASSERT(w_eq(w_hash_get(hash, string_key), w_int(42)) == W_TRUE, "string key retrieves string value");
}

static void test_frozen_dynamic_string_reuses_slab_key(void) {
    printf("\nTest 5: Frozen dynamic strings reuse existing slab keys\n");

    WValue slab_string = w_string("string_i64");
    WValue slab_symbol = w_str_to_sym(slab_string);
    WValue source = w_string("xstring_i64x");
    WValue string_hash = w_hash_new();
    WValue symbol_hash = w_hash_new();

    w_hash_set(string_hash, slab_string, w_int(7));
    w_hash_set(symbol_hash, slab_symbol, w_int(11));
    w_slab_freeze();

    WValue dynamic_string = w_string_slice_raw(source, 1, 10);
    WValue dynamic_symbol = w_str_to_sym(dynamic_string);

    ASSERT(w_is_slab_str(dynamic_string), "frozen dynamic string reuses slab storage");
    ASSERT(dynamic_string == slab_string, "frozen dynamic string preserves canonical identity");
    ASSERT(w_eq(dynamic_string, slab_string) == W_TRUE, "frozen dynamic string equals literal");
    ASSERT(w_hash_has_key(string_hash, dynamic_string) == W_TRUE, "dynamic string finds literal hash key");
    ASSERT(w_eq(w_hash_get(string_hash, dynamic_string), w_int(7)) == W_TRUE,
           "dynamic string returns literal-keyed value");
    ASSERT(dynamic_symbol == slab_symbol, "dynamic symbol preserves canonical identity");
    ASSERT(w_hash_has_key(symbol_hash, dynamic_symbol) == W_TRUE, "dynamic symbol finds literal hash key");
    ASSERT(w_eq(w_hash_get(symbol_hash, dynamic_symbol), w_int(11)) == W_TRUE,
           "dynamic symbol returns literal-keyed value");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("=== Hash Regression Tests ===\n");

    test_rope_key_lookup();
    test_rope_keys_survive_growth();
    test_rope_string_ordering();
    test_inline_symbol_string_distinct();
    test_frozen_dynamic_string_reuses_slab_key();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

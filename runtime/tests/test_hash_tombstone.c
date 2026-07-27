/*
 * test_hash_tombstone.c — delete-heavy hash-table regression tests
 *
 * The selected integer keys cover all eight initial home buckets in the
 * native runtime. Without occupied-bucket maintenance and a bounded probe,
 * deleting each key leaves an all-tombstone table and the next miss spins.
 */

#include "../runtime.h"
#include <stdio.h>

static int pass_count = 0;
static int test_count = 0;

#define ASSERT(cond, msg) do { \
    test_count++; \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        pass_count++; \
    } \
} while (0)

int main(void) {
    static const int64_t keys[] = {0, 1, 2, 6, 10, 17, 61, 64};
    WValue hash_value = w_hash_new();
    WHash *hash = (WHash *)w_as_ptr(hash_value);

    setvbuf(stdout, NULL, _IONBF, 0);

    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        WValue key = w_int(keys[i]);
        w_hash_set(hash_value, key, key);
        ASSERT(w_eq(w_hash_delete(hash_value, key), key) == W_TRUE,
               "delete returns the inserted value");
    }

    ASSERT(hash->count == 0, "all live entries were deleted");
    ASSERT(hash->occupied < hash->cap, "tombstone maintenance retains an empty slot");
    ASSERT(w_hash_get(hash_value, w_int(999)) == W_NIL, "missing lookup terminates");
    ASSERT(w_hash_has_key(hash_value, w_int(999)) == W_FALSE, "missing membership terminates");
    ASSERT(w_hash_delete(hash_value, w_int(999)) == W_NIL, "missing delete terminates");

    w_hash_set(hash_value, w_int(999), w_int(55));
    ASSERT(w_eq(w_hash_get(hash_value, w_int(999)), w_int(55)) == W_TRUE,
           "insertion after delete churn succeeds");
    ASSERT(hash->count == 1, "post-churn insertion updates live count");

    printf("hash tombstone regression: %d/%d passed\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

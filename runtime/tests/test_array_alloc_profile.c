/* Inspect the private counters so constructor/reuse/growth regressions fail
 * independently of the human-readable dump format. */
#include "../runtime.c"
#include <assert.h>

static int enabled;
static int checks;
static long long expected_n[W_ALLOCPROF_COUNT];
static long long expected_b[W_ALLOCPROF_COUNT];

static void expect(int kind, long long count, long long bytes) {
    expected_n[kind] += enabled * count;
    expected_b[kind] += enabled * bytes;
    for (int i = 0; i < W_ALLOCPROF_COUNT; ++i) {
        assert(g_allocprof_n[i] == expected_n[i]);
        assert(g_allocprof_b[i] == expected_b[i]);
    }
    ++checks;
}

static void release(WValue value) {
    WArray *a = w_as_array(value);
    array_release_slots(a->slots, a->ebits, a->cap, a->flags);
    free(a);
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    const char *e = getenv("TUNGSTEN_ALLOC_PROFILE");
    enabled = e && e[0] == '1';
    /* Empty polymorphic arrays allocate eight words on a pool miss, and
     * allocate nothing when the same payload is recycled. Both public
     * constructors must follow the same accounting contract. */
    WValue empty = w_array_new_empty();
    expect(W_ALLOCPROF_ARR, 1, 64);
    w_array_recycle_public(empty);
    WValue recycled_empty = w_array_new_empty();
    assert(recycled_empty == empty);
    expect(W_ALLOCPROF_ARR, 0, 0);
    release(recycled_empty);
    empty = w_array_recycle_or_new_empty();
    expect(W_ALLOCPROF_ARR, 1, 64);
    w_array_recycle_public(empty);
    recycled_empty = w_array_recycle_or_new_empty();
    assert(recycled_empty == empty);
    expect(W_ALLOCPROF_ARR, 0, 0);
    release(recycled_empty);
    /* Seventeen elements force rounding for the packed bool/nibble tiers.
     * Expected byte counts are independent of array_byte_size. */
    const int widths[][2] = {
        {1, 3}, {4, 9}, {-4, 9}, {8, 17}, {108, 17},
        {16, 34}, {116, 34}, {32, 68}, {33, 68},
        {64, 136}, {65, 136}, {66, 136}, {-16, 34},
        {-32, 68}, {-64, 136}, {-116, 34}, {-108, 17},
        {-109, 17}, {-104, 9}
    };
    for (size_t i = 0; i < sizeof(widths) / sizeof(widths[0]); ++i) {
        WValue a = w_array_new(widths[i][0], 17);
        expect(W_ALLOCPROF_ARR, 1, widths[i][1]);
        release(a);
    }
    WValue a = w_array_new(8, 0);
    expect(W_ALLOCPROF_ARR, 1, 8);
    release(a);
    a = w_array_new_uninit_sized(33, 17);
    expect(W_ALLOCPROF_ARR, 1, 68);
    assert(w_as_array(a)->size == 17);
    w_value_free(a);  /* park the same header and payload for reuse */
    WValue reused = w_array_new_uninit(33, 17);
    assert(reused == a);
    expect(W_ALLOCPROF_ARR, 0, 0);
    w_value_free(reused);
    a = w_array_new_uninit(8, 17);  /* parked shape mismatch allocates */
    expect(W_ALLOCPROF_ARR, 1, 17);
    release(a);

    a = w_array_new_inline(33, 17);
    expect(W_ALLOCPROF_ARR, 1, 68);
    release(a);
    a = w_array_new_inline(8, 20000); /* exercises Darwin's fallback */
    expect(W_ALLOCPROF_ARR, 1, 20000);
    release(a);
    a = w_array_new_inline(1, 0);
    expect(W_ALLOCPROF_ARR, 1, 1);
    release(a);

    WValue slot = W_NIL;
    a = w_array_reuse_or_new(&slot, 16, 10);
    expect(W_ALLOCPROF_ARR, 1, 20);
    assert(w_array_reuse_or_new(&slot, 16, 4) == a);
    expect(W_ALLOCPROF_ARR, 0, 0);
    release(a);

    /* Ordinary realloc, inline promotion, and copying with a live view. */
    for (int mode = 0; mode < 3; ++mode) {
        a = mode == 1 ? w_array_new_inline(33, 2) : w_array_new(33, 2);
        expect(W_ALLOCPROF_ARR, 1, 8);
        w_as_array(a)->size = 0;
        w_array_push(a, w_int(1));
        w_array_push(a, w_int(2));
        WValue view = W_NIL;
        if (mode == 2) view = w_array_view(a, w_int(0), w_int(2));
        expect(W_ALLOCPROF_ARR, 0, 0);
        w_array_push(a, w_int(3));
        expect(W_ALLOCPROF_GROW, 1, 16);
        if (mode == 2) assert(w_array_get(view, w_int(1)) == w_int(2));
        /* Views have process-lifetime registry entries; keep their parent. */
        if (mode != 2) release(a);
    }
    a = w_array_new_inline(8, 2);
    expect(W_ALLOCPROF_ARR, 1, 2);
    w_array_set(a, w_int(0), w_int(1));
    w_array_set(a, w_int(1), w_int(2));
    w_array_unshift(a, w_int(0));
    expect(W_ALLOCPROF_GROW, 1, 4);
    release(a);

    a = w_array_new_aligned(w_int(8), w_int(2));
    expect(W_ALLOCPROF_ALIGNED, 1, sysconf(_SC_PAGESIZE));
    w_array_push(a, w_int(3));
    expect(W_ALLOCPROF_GROW, 1, 4);
    release(a);
    printf("array allocation profile: %d checks passed (enabled=%d)\n", checks, enabled);
    return 0;
}

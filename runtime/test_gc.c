#include "runtime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static WValue make_large_str(int idx) {
    char buf[128];
    snprintf(buf, sizeof(buf),
             "gc_heap_string_payload_exceeding_slab_sso61_threshold_item_%08d_end", idx);
    return w_string(buf);
}

static WValue worker_fn(WValue *captures) {
    WValue out_arr = captures[0];
    for (int i = 0; i < 2000; i++) {
        WValue tmp = w_array_new(65, 8);
        w_array_push(tmp, make_large_str(i));
        if (i == 1999) {
            w_array_push(out_arr, make_large_str(777777));
        }
    }
    return w_int(42);
}

int main(void) {
    printf("=== Tungsten GC Test Suite ===\n");

    /* 1. Default off */
    assert(w_gc_enabled_p() == W_FALSE);
    assert(w_gc_tracking_p() == W_FALSE);
    assert(g_gc_track == 0 && g_gc_auto == 0);
    printf("  1. default off (zero-cost state): OK\n");

    /* 2. Enable / Disable toggle */
    assert(w_gc_enable() == W_TRUE);
    assert(w_gc_enabled_p() == W_TRUE);
    assert(w_gc_tracking_p() == W_TRUE);
    assert(w_gc_enable() == W_FALSE);
    assert(w_gc_disable() == W_FALSE);
    assert(w_gc_enabled_p() == W_FALSE);
    assert(w_gc_disable() == W_TRUE);
    assert(w_gc_enable() == W_TRUE);
    printf("  2. GC.enable / GC.disable toggles: OK\n");

    /* 3. Keep arena + mutable keep container referencing young objects */
    WValue keep_hash = w_hash_new();
    WValue keep_leaf = make_large_str(100);
    w_hash_set(keep_hash, w_symbol("boot"), keep_leaf);
    w_gc_keep_all();
    w_gc_wait_sweep();

    /* Mutate keep_hash AFTER keep_all to point to a fresh young string & object */
    WValue cls = w_class_new("GCNode", W_NIL);
    w_class_add_ivar(cls, "payload");
    w_class_add_ivar(cls, "next");
    w_gc_keep(cls);

    WValue young_in_keep = w_object_new(cls);
    w_ivar_set_idx(young_in_keep, 0, make_large_str(2026));
    w_hash_set(keep_hash, w_symbol("dynamic_child"), young_in_keep);

    /* Allocate 10,000 unreachable objects + strings + hashes + arrays */
    for (int i = 0; i < 10000; i++) {
        WValue dead_obj = w_object_new(cls);
        w_ivar_set_idx(dead_obj, 0, make_large_str(i + 5000));
        WValue dead_h = w_hash_new();
        w_hash_set(dead_h, w_int(i), dead_obj);
        WValue dead_a = w_array_new(8, 256);
        (void)dead_a;
    }

    w_gc_minor();
    w_gc_wait_sweep();

    /* Verify child stored inside keep_hash survived and promoted to Old! */
    WValue fetched = w_hash_get(keep_hash, w_symbol("dynamic_child"));
    assert(w_is_instance(fetched));
    WObject *fo = (WObject *)w_as_ptr(fetched);
    assert((fo->gc_flags & W_GC_OLD) != 0);
    WValue fstr = w_ivar_get_idx(fetched, 0);
    assert(w_eq(fstr, make_large_str(2026)) == W_TRUE);
    printf("  3. Keep arena & mutable keep->young retention + minor sweep: OK\n");

    /* 4. Generational Old WHash dirty-bit write barrier */
    WValue old_h = w_hash_new();
    w_hash_set(old_h, w_symbol("a"), w_int(1));
    w_gc_minor(); /* promotes old_h to W_GC_OLD */
    w_gc_wait_sweep();
    WHash *oh_ptr = (WHash *)w_as_ptr(old_h);
    assert((oh_ptr->gc_flags & W_GC_OLD) != 0);
    assert((oh_ptr->gc_flags & W_GC_DIRTY) == 0);

    /* Mutate Old hash with a brand-new young string, verify W_GC_DIRTY sets */
    w_hash_set(old_h, w_symbol("fresh"), make_large_str(99999));
    assert((oh_ptr->gc_flags & W_GC_DIRTY) != 0);

    w_gc_minor();
    w_gc_wait_sweep();
    assert((oh_ptr->gc_flags & W_GC_DIRTY) == 0);
    assert(w_eq(w_hash_get(old_h, w_symbol("fresh")), make_large_str(99999)) == W_TRUE);
    /* Keep old_h live across the assertion above */
    assert(w_as_int(w_hash_get(old_h, w_symbol("a"))) == 1);
    printf("  4. Generational W_GC_OLD + W_GC_DIRTY write barrier: OK\n");

    /* 5. Zero-copy Array view keeps parent buffer alive */
    WValue view_only;
    {
        WValue parent = w_array_new(8, 64);
        WArray *pa = w_as_array(parent);
        pa->size = 64;
        for (int i = 0; i < 64; i++) ((uint8_t *)pa->slots)[i] = (uint8_t)(i + 10);
        view_only = w_array_view(parent, w_int(16), w_int(16));
    }
    w_gc_major();
    w_gc_wait_sweep();
    assert(w_as_int(w_array_get(view_only, w_int(0))) == 26);
    assert(w_as_int(w_array_get(view_only, w_int(15))) == 41);
    printf("  5. Zero-copy slice view -> parent retention: OK\n");

    /* 6. Multi-threaded mutator + parallel mark + concurrent sweep */
    WValue shared_results = w_array_new(65, 8);
    w_gc_keep(shared_results);
    WValue caps[1] = { shared_results };
    WValue cl1 = w_closure_new((void *)worker_fn, caps, 1);
    WValue cl2 = w_closure_new((void *)worker_fn, caps, 1);
    WValue t1 = w_thread_spawn(cl1);
    WValue t2 = w_thread_spawn(cl2);
    w_gc_minor();
    assert(w_as_int(w_thread_join(t1)) == 42);
    assert(w_as_int(w_thread_join(t2)) == 42);
    w_gc_major();
    w_gc_wait_sweep();
    assert(w_as_int(w_array_size(shared_results)) == 2);
    assert(w_eq(w_array_get(shared_results, w_int(0)), make_large_str(777777)) == W_TRUE);

    WValue st = w_gc_stats();
    WValue swept = w_hash_get(st, w_symbol("swept_objects"));
    WValue swept_b = w_hash_get(st, w_symbol("swept_bytes"));
    printf("  6. Multi-threaded GC + stats (swept=%lld objs, %lld bytes): OK\n",
           (long long)w_as_int(swept), (long long)w_as_int(swept_b));
    assert(w_as_int(swept) > 20000);

    printf("=== All GC tests passed! ===\n");
    return 0;
}

/* WTensor CPU helpers — gated companion (@w_tensor_). */
#include "runtime.h"
#include "wvalue.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ---- WTensor (CPU multi-D f32 face) ------------------------------------ */

static int wtensor_is(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return 0;
    WTensor *t = (WTensor *)w_as_ptr(v);
    return t && t->type == W_TYPE_WTENSOR;
}

static int32_t *wtensor_shape_ptr(WTensor *t) {
    return t->rank > W_TENSOR_INLINE_RANK ? t->shape_heap : t->shape_inline;
}
static int32_t *wtensor_strides_ptr(WTensor *t) {
    return t->rank > W_TENSOR_INLINE_RANK ? t->strides_heap : t->strides_inline;
}

static int64_t wtensor_flat_index(WTensor *t, int32_t *idx, int nidx) {
    if (nidx != (int)t->rank) {
        w_raise(w_string("WTensor: index rank mismatch"));
        return 0;
    }
    int32_t *st = wtensor_strides_ptr(t);
    int64_t o = t->offset;
    for (int k = 0; k < nidx; k++) o += (int64_t)idx[k] * st[k];
    return o;
}

WValue w_tensor_zeros_f32(WValue shape_wv) {
    if (!w_is_array(shape_wv)) {
        w_raise(w_string("w_tensor_zeros_f32: shape must be Array"));
        return W_NIL;
    }
    WArray *sh = (WArray *)w_as_ptr(shape_wv);
    int rank = (int)sh->size;
    if (rank < 0 || rank > 16) {
        w_raise(w_string("w_tensor_zeros_f32: bad rank"));
        return W_NIL;
    }
    int64_t nelem = 1;
    int32_t shape_tmp[16];
    for (int i = 0; i < rank; i++) {
        WValue e = ((WValue *)sh->slots)[sh->start + i];
        int64_t d = w_as_int(e);
        if (d <= 0) { w_raise(w_string("w_tensor_zeros_f32: non-positive dim")); return W_NIL; }
        shape_tmp[i] = (int32_t)d;
        nelem *= d;
    }
    /* storage via aligned f32 array */
    WValue stor = w_array_new_aligned(w_int(-32), w_int(nelem));
    WArray *sa = (WArray *)w_as_ptr(stor);

    WTensor *t = NULL;
    if (posix_memalign((void **)&t, 16, sizeof(WTensor)) != 0 || !t) {
        w_raise(w_string("w_tensor_zeros_f32: OOM"));
        return W_NIL;
    }
    memset(t, 0, sizeof(WTensor));
    t->type = W_TYPE_WTENSOR;
    t->flags = 0;
    t->ebits = -32;
    t->rank = (uint8_t)rank;
    t->borrow = 0;
    t->offset = 0;
    t->storage = sa->slots;
    t->storage_elems = nelem;
    if (rank <= W_TENSOR_INLINE_RANK) {
        for (int i = 0; i < rank; i++) t->shape_inline[i] = shape_tmp[i];
        /* C-contiguous strides */
        int32_t acc = 1;
        for (int i = rank - 1; i >= 0; i--) {
            t->strides_inline[i] = acc;
            acc *= shape_tmp[i];
        }
    } else {
        t->shape_heap = calloc((size_t)rank, sizeof(int32_t));
        t->strides_heap = calloc((size_t)rank, sizeof(int32_t));
        for (int i = 0; i < rank; i++) t->shape_heap[i] = shape_tmp[i];
        int32_t acc = 1;
        for (int i = rank - 1; i >= 0; i--) {
            t->strides_heap[i] = acc;
            acc *= shape_tmp[i];
        }
    }
    /* Keep WArray alive: store as borrow and... we leak the WArray header but
     * storage is the mmap region. Mark borrow=0 and free path TBD. */
    (void)stor;
    return w_box_ptr(t, W_SUBTAG_GENERIC);
}

WValue w_tensor_rank(WValue t_wv) {
    if (!wtensor_is(t_wv)) { w_raise(w_string("w_tensor_rank: not a WTensor")); return W_NIL; }
    WTensor *t = (WTensor *)w_as_ptr(t_wv);
    return w_int(t->rank);
}

WValue w_tensor_shape(WValue t_wv) {
    if (!wtensor_is(t_wv)) { w_raise(w_string("w_tensor_shape: not a WTensor")); return W_NIL; }
    WTensor *t = (WTensor *)w_as_ptr(t_wv);
    int32_t *sh = wtensor_shape_ptr(t);
    WValue arr = w_array_new(65, t->rank);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (int i = 0; i < t->rank; i++) {
        ((WValue *)a->slots)[a->start + a->size] = w_int(sh[i]);
        a->size++;
    }
    return arr;
}

WValue w_tensor_at_f32(WValue t_wv, WValue indices_wv) {
    if (!wtensor_is(t_wv) || !w_is_array(indices_wv)) {
        w_raise(w_string("w_tensor_at_f32: bad args"));
        return W_NIL;
    }
    WTensor *t = (WTensor *)w_as_ptr(t_wv);
    WArray *ix = (WArray *)w_as_ptr(indices_wv);
    int32_t idx[16];
    int n = (int)ix->size;
    if (n > 16) n = 16;
    for (int i = 0; i < n; i++)
        idx[i] = (int32_t)w_as_int(((WValue *)ix->slots)[ix->start + i]);
    int64_t fi = wtensor_flat_index(t, idx, n);
    if (fi < 0 || fi >= t->storage_elems) {
        w_raise(w_string("w_tensor_at_f32: out of range"));
        return W_NIL;
    }
    float *base = (float *)t->storage;
    return w_float((double)base[fi]);
}

WValue w_tensor_set_f32(WValue t_wv, WValue indices_wv, WValue val_wv) {
    if (!wtensor_is(t_wv) || !w_is_array(indices_wv)) {
        w_raise(w_string("w_tensor_set_f32: bad args"));
        return W_NIL;
    }
    WTensor *t = (WTensor *)w_as_ptr(t_wv);
    WArray *ix = (WArray *)w_as_ptr(indices_wv);
    int32_t idx[16];
    int n = (int)ix->size;
    if (n > 16) n = 16;
    for (int i = 0; i < n; i++)
        idx[i] = (int32_t)w_as_int(((WValue *)ix->slots)[ix->start + i]);
    int64_t fi = wtensor_flat_index(t, idx, n);
    if (fi < 0 || fi >= t->storage_elems) {
        w_raise(w_string("w_tensor_set_f32: out of range"));
        return W_NIL;
    }
    float *base = (float *)t->storage;
    base[fi] = (float)w_as_double(val_wv);
    return t_wv;
}

/* View: share storage, new offset + shape (C-contiguous strides for new shape).
 * offset_elems is relative to parent's logical origin (parent.offset already applied). */
WValue w_tensor_view_f32(WValue t_wv, WValue offset_wv, WValue shape_wv) {
    if (!wtensor_is(t_wv) || !w_is_array(shape_wv)) {
        w_raise(w_string("w_tensor_view_f32: bad args"));
        return W_NIL;
    }
    WTensor *src = (WTensor *)w_as_ptr(t_wv);
    int64_t rel = w_as_int(offset_wv);
    WArray *sh = (WArray *)w_as_ptr(shape_wv);
    int rank = (int)sh->size;
    if (rank < 0 || rank > 16) {
        w_raise(w_string("w_tensor_view_f32: bad rank"));
        return W_NIL;
    }
    int32_t shape_tmp[16];
    int64_t nelem = 1;
    for (int i = 0; i < rank; i++) {
        int64_t d = w_as_int(((WValue *)sh->slots)[sh->start + i]);
        if (d <= 0) { w_raise(w_string("w_tensor_view_f32: non-positive dim")); return W_NIL; }
        shape_tmp[i] = (int32_t)d;
        nelem *= d;
    }
    int64_t new_off = (int64_t)src->offset + rel;
    if (new_off < 0 || new_off + nelem > src->storage_elems) {
        w_raise(w_string("w_tensor_view_f32: view out of parent bounds"));
        return W_NIL;
    }
    WTensor *t = NULL;
    if (posix_memalign((void **)&t, 16, sizeof(WTensor)) != 0 || !t) {
        w_raise(w_string("w_tensor_view_f32: OOM"));
        return W_NIL;
    }
    memset(t, 0, sizeof(WTensor));
    t->type = W_TYPE_WTENSOR;
    t->flags = 0;
    t->ebits = src->ebits;
    t->rank = (uint8_t)rank;
    t->borrow = 1; /* share storage */
    t->offset = (int32_t)new_off;
    t->storage = src->storage;
    t->storage_elems = src->storage_elems;
    if (rank <= W_TENSOR_INLINE_RANK) {
        for (int i = 0; i < rank; i++) t->shape_inline[i] = shape_tmp[i];
        int32_t acc = 1;
        for (int i = rank - 1; i >= 0; i--) {
            t->strides_inline[i] = acc;
            acc *= shape_tmp[i];
        }
    } else {
        t->shape_heap = calloc((size_t)rank, sizeof(int32_t));
        t->strides_heap = calloc((size_t)rank, sizeof(int32_t));
        for (int i = 0; i < rank; i++) t->shape_heap[i] = shape_tmp[i];
        int32_t acc = 1;
        for (int i = rank - 1; i >= 0; i--) {
            t->strides_heap[i] = acc;
            acc *= shape_tmp[i];
        }
    }
    return w_box_ptr(t, W_SUBTAG_GENERIC);
}

/* Slice axis 0: t[start:stop, ...] → view with reduced outer extent. */
WValue w_tensor_slice0_f32(WValue t_wv, WValue start_wv, WValue stop_wv) {
    if (!wtensor_is(t_wv)) {
        w_raise(w_string("w_tensor_slice0_f32: not a WTensor"));
        return W_NIL;
    }
    WTensor *src = (WTensor *)w_as_ptr(t_wv);
    if (src->rank < 1) {
        w_raise(w_string("w_tensor_slice0_f32: rank < 1"));
        return W_NIL;
    }
    int32_t *sh = wtensor_shape_ptr(src);
    int32_t *st = wtensor_strides_ptr(src);
    int64_t start = w_as_int(start_wv);
    int64_t stop = w_as_int(stop_wv);
    if (start < 0) start = 0;
    if (stop > sh[0]) stop = sh[0];
    if (stop < start) {
        w_raise(w_string("w_tensor_slice0_f32: empty/inverted range"));
        return W_NIL;
    }
    int64_t new_outer = stop - start;
    /* offset moves by start * stride0 */
    int64_t rel = start * (int64_t)st[0];
    /* build shape array as WValue and call view — inline for clarity */
    WTensor *t = NULL;
    if (posix_memalign((void **)&t, 16, sizeof(WTensor)) != 0 || !t) {
        w_raise(w_string("w_tensor_slice0_f32: OOM"));
        return W_NIL;
    }
    memset(t, 0, sizeof(WTensor));
    t->type = W_TYPE_WTENSOR;
    t->ebits = src->ebits;
    t->rank = src->rank;
    t->borrow = 1;
    t->offset = (int32_t)((int64_t)src->offset + rel);
    t->storage = src->storage;
    t->storage_elems = src->storage_elems;
    if (src->rank <= W_TENSOR_INLINE_RANK) {
        for (int i = 0; i < src->rank; i++) {
            t->shape_inline[i] = sh[i];
            t->strides_inline[i] = st[i];
        }
        t->shape_inline[0] = (int32_t)new_outer;
    } else {
        t->shape_heap = calloc(src->rank, sizeof(int32_t));
        t->strides_heap = calloc(src->rank, sizeof(int32_t));
        for (int i = 0; i < src->rank; i++) {
            t->shape_heap[i] = sh[i];
            t->strides_heap[i] = st[i];
        }
        t->shape_heap[0] = (int32_t)new_outer;
    }
    return w_box_ptr(t, W_SUBTAG_GENERIC);
}


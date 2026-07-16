#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <sys/mman.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

static WMmap *mwr_as_mmap(WValue value) {
    if (!w_is_mmap(value)) {
        w_raise(w_string("mmap wrapper fixture expected Mmap"));
    }
    return (WMmap *)w_as_ptr(value);
}

static WBigArray *mwr_as_big_array(WValue value) {
    if (!w_is_big_array(value)) {
        w_raise(w_string("mmap wrapper fixture expected BigArray"));
    }
    return (WBigArray *)w_as_ptr(value);
}

WValue w_mwr_fixture(int64_t length) {
    if (length < 0 || length > 4096) {
        w_raise(w_string("mmap wrapper fixture length out of bounds"));
    }

    uint8_t *data = NULL;
    if (length > 0) {
        data = mmap(NULL, (size_t)length, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (data == MAP_FAILED) {
            w_raise(w_string("mmap wrapper fixture mmap failed"));
        }
        for (int64_t i = 0; i < length; i++) {
            data[i] = (uint8_t)((i * 17 + 3) & 0xff);
        }
        if (mprotect(data, (size_t)length, PROT_READ) != 0) {
            munmap(data, (size_t)length);
            w_raise(w_string("mmap wrapper fixture mprotect failed"));
        }
    }

    WMmap *m = (WMmap *)calloc(1, sizeof(WMmap));
    if (!m) {
        if (data) munmap(data, (size_t)length);
        w_raise(w_string("mmap wrapper fixture allocation failed"));
    }
    m->type = W_TYPE_MMAP;
    m->closed = 0;
    m->data = data;
    m->size = length;
    return w_box_ptr(m, W_SUBTAG_GENERIC);
}

WValue w_mwr_release_mmap(WValue value) {
    WMmap *m = mwr_as_mmap(value);
    if (!m->closed) __w_mmap_close(value);
    free(m);
    return W_NIL;
}

WValue w_mwr_mmap_closed(WValue value) {
    WMmap *m = mwr_as_mmap(value);
    return w_bool(m->closed != 0 && m->data == NULL);
}

WValue w_mwr_view_ebits(WValue value) {
    WBigArray *a = mwr_as_big_array(value);
    return w_int((int64_t)(int8_t)a->ebits);
}

WValue w_mwr_view_size(WValue value) {
    return w_int(mwr_as_big_array(value)->size);
}

WValue w_mwr_view_signature(WValue value) {
    WBigArray *a = mwr_as_big_array(value);
    int64_t signature = (int64_t)(int8_t)a->ebits;
    signature = signature * 257 + a->flags;
    signature = signature * 257 + a->start;
    signature = signature * 257 + a->size;
    signature = signature * 257 + a->cap;
    signature = signature * 257 + (a->slots ? a->slots[0] : 0);
    return w_int(signature);
}

WValue w_mwr_views_share_data(WValue left, WValue right) {
    WBigArray *a = mwr_as_big_array(left);
    WBigArray *b = mwr_as_big_array(right);
    return w_bool(a->slots == b->slots);
}

int64_t w_mwr_consume_release_view(WValue value) {
    WBigArray *a = mwr_as_big_array(value);
    int64_t checksum = (int64_t)(int8_t)a->ebits * 131 + a->size;
    if (a->size > 0 && a->slots) checksum += a->slots[0];
    free(a);
    return checksum;
}

WValue w_mwr_release_view(WValue value) {
    free(mwr_as_big_array(value));
    return W_NIL;
}

WValue w_mwr_ref_close(WValue value) {
    return __w_mmap_close(value);
}

WValue w_mwr_ref_byte_at(WValue value, WValue index) {
    return __w_mmap_byte_at(value, index);
}

#define MWR_TYPED_REF(name, bits)              \
    WValue w_mwr_ref_##name(WValue value) {    \
        return __w_mmap_as_typed(value, bits); \
    }

MWR_TYPED_REF(as_u8,   8)
MWR_TYPED_REF(as_u16, 16)
MWR_TYPED_REF(as_u32, 32)
MWR_TYPED_REF(as_u64, 64)
MWR_TYPED_REF(as_i8, 108)
MWR_TYPED_REF(as_i16, 116)
MWR_TYPED_REF(as_i32, 32)
MWR_TYPED_REF(as_i64, 64)
MWR_TYPED_REF(as_f32, -32)
MWR_TYPED_REF(as_f64, -64)

int64_t w_mwr_thread_cpu_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

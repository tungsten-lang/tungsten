/* runtime/metal.m — Obj-C Metal bridge for `@gpu fn` dispatch.
 *
 * Compiled only on darwin (build.rb gates this) and linked with
 * `-framework Metal -framework Foundation`. Other platforms get the
 * stubs in runtime.c which raise a runtime error.
 *
 * Lifetime: the WValue heap structs hold retained Obj-C `id` references
 * cast to `void *`. v1 leaks them (single-process tools, kernels live
 * for the program's lifetime). A future GC integration would CFRelease
 * via a finalizer.
 *
 * Error handling: anything that can fail (no device, MSL compile error,
 * pipeline build, dispatch) raises a Tungsten exception via w_raise so
 * the host code surfaces it through the normal `--> file:line:col`
 * formatter. */

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <sys/mman.h>     /* madvise(MADV_DONTNEED) for write_from_mmap */
#include <unistd.h>       /* getpagesize */
#include "runtime.h"
#include "wvalue.h"

/* Pull the C-string view of a Tungsten string. The buffer is for
 * inline strings; for slab/heap strings the returned pointer is
 * stable for the lifetime of the value. We allocate per-call to
 * keep things obvious — these calls are off the hot path. */
static const char *metal_string_data(WValue v) {
    if (!w_is_string(v)) return NULL;
    static __thread char buf[6];
    const char *s = NULL;
    size_t len = 0;
    w_str_data(v, buf, &s, &len);
    return s;
}

/* Coerce a numeric WValue to double. Handles native doubles and
 * boxed ints; everything else is a Tungsten error. */
static double metal_to_double(WValue v) {
    if (w_is_double(v)) return w_as_double(v);
    if (w_is_int(v))    return (double)w_to_i64(v);
    w_raise(w_string("Metal: numeric value expected"));
    return 0.0;
}

static WMetalDevice *as_metal_device(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalDevice *d = (WMetalDevice *)w_as_ptr(v);
    if (d->type != W_TYPE_METAL_DEVICE) return NULL;
    return d;
}

static WMetalLibrary *as_metal_library(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalLibrary *l = (WMetalLibrary *)w_as_ptr(v);
    if (l->type != W_TYPE_METAL_LIBRARY) return NULL;
    return l;
}

static WMetalPipeline *as_metal_pipeline(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalPipeline *p = (WMetalPipeline *)w_as_ptr(v);
    if (p->type != W_TYPE_METAL_PIPELINE) return NULL;
    return p;
}

static WMetalBuffer *as_metal_buffer(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalBuffer *b = (WMetalBuffer *)w_as_ptr(v);
    if (b->type != W_TYPE_METAL_BUFFER) return NULL;
    return b;
}

static WMetalQueue *as_metal_queue(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalQueue *q = (WMetalQueue *)w_as_ptr(v);
    if (q->type != W_TYPE_METAL_QUEUE) return NULL;
    return q;
}

/* Scalar autobox cache: int → 1-element i32 MTLBuffer, double → 1-element
 * f32. Keyed on (ebits, raw 32-bit pattern). Lets dispatch sites pass
 * scalar literals directly (`metal_dispatch(queue, pipe, [x, w, y, HIDDEN], …)`)
 * without manually allocating a 4-byte MTLBuffer per scalar arg.
 *
 * Hits are the common case: ML kernels reuse the same hidden_dim,
 * seq_len, scale factor, etc. across many dispatches. Misses fall
 * through to unconditional buffer creation (correctness preserved).
 *
 * Capacity is fixed; eviction is FIFO via a write index. 128 entries
 * covers the working set of every observed ML pipeline; beyond that,
 * the FIFO replaces the coldest slot rather than thrashing. Single-
 * threaded — Tungsten kernel dispatch isn't called from multiple
 * pthreads today; if that changes, gate with a plain mutex. */
/* kind: 0 = empty slot, 1 = int (i32 storage), 2 = float (f32 storage). */
typedef struct {
    uint8_t  kind;
    uint32_t raw;     /* int32 bit pattern OR float32 bit pattern */
    void    *buf;     /* retained id<MTLBuffer> */
} ScalarBoxEntry;

#define SCALAR_BOX_CACHE_CAP 128
static ScalarBoxEntry g_scalar_box_cache[SCALAR_BOX_CACHE_CAP];
static int g_scalar_box_next = 0;

static id<MTLBuffer> scalar_autobox_lookup_or_make(uint8_t kind, uint32_t raw, id<MTLDevice> dev) {
    /* Linear scan — N is small and the hit rate is high. Empty slots
     * (kind == 0) compare unequal to every real key, so they're skipped
     * implicitly without a separate liveness check. */
    for (int i = 0; i < SCALAR_BOX_CACHE_CAP; i++) {
        ScalarBoxEntry *e = &g_scalar_box_cache[i];
        if (e->kind == kind && e->raw == raw && e->buf) {
            return (id<MTLBuffer>)e->buf;
        }
    }
    id<MTLBuffer> buf = [dev newBufferWithBytes:&raw
                                         length:4
                                        options:MTLResourceStorageModeShared];
    if (!buf) return nil;
    /* Retain — entries persist for the lifetime of the cache slot. */
    [buf retain];
    int slot = g_scalar_box_next;
    g_scalar_box_next = (g_scalar_box_next + 1) % SCALAR_BOX_CACHE_CAP;
    if (g_scalar_box_cache[slot].buf) {
        [(id<MTLBuffer>)g_scalar_box_cache[slot].buf release];
    }
    g_scalar_box_cache[slot].kind = kind;
    g_scalar_box_cache[slot].raw  = raw;
    g_scalar_box_cache[slot].buf  = (void *)buf;
    return buf;
}

/* Phase 7d (#12): transparent buffer arg — accept either a WMetalBuffer,
 * a WArray with GPU-eligible ebits, or a scalar int/double (autoboxed).
 * For WArray, wrap on-the-fly via newBufferWithBytesNoCopy (zero-copy
 * when page-aligned) or newBufferWithBytes (copy fallback). Returned
 * MTLBuffer is autoreleased — caller's @autoreleasepool collects it
 * after dispatch (autobox cache holds a separate retain so that copy
 * stays valid across dispatches). Returns nil on type mismatch or
 * non-eligible ebits. */
static id<MTLBuffer> metal_buffer_or_wrap_array(WValue v, id<MTLDevice> dev) {
    WMetalBuffer *b = as_metal_buffer(v);
    if (b) return (id<MTLBuffer>)b->handle;
    /* Scalar autobox: ints → i32, doubles → f32. The 4-byte width matches
     * the most common kernel-arg pattern (seq_len, hidden_dim, scale). */
    if (w_is_int(v)) {
        int64_t n = w_as_int(v);
        int32_t n32 = (int32_t)n;
        uint32_t raw;
        memcpy(&raw, &n32, 4);
        return scalar_autobox_lookup_or_make(/*kind=int*/ 1, raw, dev);
    }
    if (w_is_double(v)) {
        float f = (float)w_as_double(v);
        uint32_t raw;
        memcpy(&raw, &f, 4);
        return scalar_autobox_lookup_or_make(/*kind=float*/ 2, raw, dev);
    }
    if (!w_is_array(v)) return nil;
    WArray *a = (WArray *)w_as_ptr(v);
    int e_int = (int)a->ebits;
    if (e_int != 8 && e_int != 16 && e_int != 32 && e_int != 64 &&
        e_int != -32 && e_int != -64 &&
        e_int != -116 && e_int != -108 && e_int != -109 && e_int != -104 &&
        e_int != 108 && e_int != 116) {
        return nil;
    }
    int64_t bits_per_elt;
    if (e_int == -116 || e_int == 116) bits_per_elt = 16;
    else if (e_int == -108 || e_int == -109 || e_int == 108) bits_per_elt = 8;
    else if (e_int == -104) bits_per_elt = 4;
    else if (e_int < 0) bits_per_elt = -e_int;
    else bits_per_elt = e_int;
    if (a->size <= 0) return nil;
    int64_t byte_length = (a->size * bits_per_elt) / 8;
    void *base = (uint8_t *)a->slots + (a->start * bits_per_elt) / 8;
    NSUInteger page = (NSUInteger)getpagesize();
    id<MTLBuffer> buf;
    if (((uintptr_t)base & (page - 1)) == 0) {
        buf = [dev newBufferWithBytesNoCopy:base
                                     length:(NSUInteger)byte_length
                                    options:MTLResourceStorageModeShared
                                deallocator:nil];
    } else {
        buf = [dev newBufferWithBytes:base
                               length:(NSUInteger)byte_length
                              options:MTLResourceStorageModeShared];
    }
    return [buf autorelease];
}

WValue w_metal_device_default(void) {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) {
        w_raise(w_string("Metal: no default device available"));
    }
    [dev retain];
    WMetalDevice *w = (WMetalDevice *)calloc(1, sizeof(WMetalDevice));
    w->type = W_TYPE_METAL_DEVICE;
    w->handle = (void *)dev;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

/* Build MTLCompileOptions for a kernel compile.
 *   strict == 0 (default): fast math — aggressive FMA contraction, reciprocal
 *     approximations, dropped NaN/Inf handling, invariance off. ~5-10% float win.
 *   strict != 0 (@strictmath): Safe, IEEE-conforming math with preserved
 *     invariance, for kernels that need exact / reproducible float results. */
static MTLCompileOptions *metal_make_compile_opts(int strict) {
    MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
    if (@available(macOS 15.0, *)) {
        opts.mathMode = strict ? MTLMathModeSafe : MTLMathModeFast;
    } else {
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        opts.fastMathEnabled = strict ? NO : YES;
#pragma clang diagnostic pop
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
    }
#endif
    /* Preserve invariance under strict math (reproducible results); allow the
     * compiler to reorder freely otherwise for more aggressive scheduling. */
    if (@available(macOS 11.0, *)) {
        opts.preserveInvariance = strict ? YES : NO;
    }
    return opts;
}

/* Compile MSL with an explicit math mode. math_mode: 0=fast (default), non-0 =
 * strict/IEEE (@strictmath opt-out). w_metal_compile_source keeps the fast
 * 2-arg contract for existing callers. */
WValue w_metal_compile_source_opts(WValue device_v, WValue source_v, WValue math_mode_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) {
        w_raise(w_string("Metal.compile_source: first arg must be a Metal device"));
    }
    if (!w_is_string(source_v)) {
        w_raise(w_string("Metal.compile_source: source must be a string"));
    }
    id<MTLDevice> dev = (id<MTLDevice>)d->handle;
    NSString *src = [NSString stringWithUTF8String:metal_string_data(source_v)];
    NSError *err = nil;
    int strict = (w_is_int(math_mode_v) && w_as_int(math_mode_v) != 0) ? 1 : 0;
    MTLCompileOptions *opts = metal_make_compile_opts(strict);
    id<MTLLibrary> lib = [dev newLibraryWithSource:src options:opts error:&err];
    [opts release];
    if (!lib) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        /* Large generated kernels can emit enough warnings to hide the actual
         * MSL error behind the old 1 KiB truncation. Preserve the diagnostic
         * tail so compiler extensions such as device atomics remain debuggable. */
        char buf[8192];
        snprintf(buf, sizeof(buf), "Metal.compile_source: %s", msg);
        w_raise(w_string(buf));
    }
    WMetalLibrary *w = (WMetalLibrary *)calloc(1, sizeof(WMetalLibrary));
    w->type = W_TYPE_METAL_LIBRARY;
    w->handle = (void *)lib;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

WValue w_metal_compile_source(WValue device_v, WValue source_v) {
    return w_metal_compile_source_opts(device_v, source_v, w_int(0));
}

/* Load an offline-compiled Metal library. Compiling MSL in every adaptive
 * worker leaves the GPU idle and can serialize concurrent compiler
 * invocations; a cached metallib moves that work to the build phase. */
WValue w_metal_library_from_file(WValue device_v, WValue path_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) {
        w_raise(w_string("Metal.load_library: first arg must be a Metal device"));
    }
    if (!w_is_string(path_v)) {
        w_raise(w_string("Metal.load_library: path must be a string"));
    }
    const char *path_c = metal_string_data(path_v);
    if (!path_c || !path_c[0]) {
        w_raise(w_string("Metal.load_library: path must not be empty"));
    }
    NSString *path = [NSString stringWithUTF8String:path_c];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *err = nil;
    id<MTLDevice> dev = (id<MTLDevice>)d->handle;
    id<MTLLibrary> lib = [dev newLibraryWithURL:url error:&err];
    if (!lib) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[1024];
        snprintf(buf, sizeof(buf), "Metal.load_library: %s: %s", path_c, msg);
        w_raise(w_string(buf));
    }
    WMetalLibrary *w = (WMetalLibrary *)calloc(1, sizeof(WMetalLibrary));
    w->type = W_TYPE_METAL_LIBRARY;
    w->handle = (void *)lib;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

WValue w_metal_pipeline_for(WValue library_v, WValue name_v) {
    WMetalLibrary *l = as_metal_library(library_v);
    if (!l) {
        w_raise(w_string("Metal: pipeline_for needs a Metal library"));
    }
    if (!w_is_string(name_v)) {
        w_raise(w_string("Metal: pipeline_for needs a string kernel name"));
    }
    id<MTLLibrary> lib = (id<MTLLibrary>)l->handle;
    NSString *name = [NSString stringWithUTF8String:metal_string_data(name_v)];
    id<MTLFunction> fn = [lib newFunctionWithName:name];
    if (!fn) {
        char buf[256];
        snprintf(buf, sizeof(buf), "Metal: kernel `%s` not found in library", metal_string_data(name_v));
        w_raise(w_string(buf));
    }
    NSError *err = nil;
    id<MTLDevice> dev = [lib device];
    id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:&err];
    [fn release];
    if (!ps) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal: pipeline build failed: %s", msg);
        w_raise(w_string(buf));
    }
    WMetalPipeline *w = (WMetalPipeline *)calloc(1, sizeof(WMetalPipeline));
    w->type = W_TYPE_METAL_PIPELINE;
    w->handle = (void *)ps;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

/* MTLBinaryArchive — caches compiled pipeline state objects so that
 * subsequent `newComputePipelineState` calls skip JIT compilation.
 * Saves ~30s of per-startup compile time on a cold launch (no real
 * effect on per-token decode latency, only startup). */
WValue w_metal_binary_archive_new(WValue device_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) w_raise(w_string("Metal.binary_archive_new: bad device"));
    if (@available(macOS 11.0, *)) {
        id<MTLDevice> dev = (id<MTLDevice>)d->handle;
        MTLBinaryArchiveDescriptor *desc = [[MTLBinaryArchiveDescriptor alloc] init];
        NSError *err = nil;
        id<MTLBinaryArchive> arch = [dev newBinaryArchiveWithDescriptor:desc error:&err];
        [desc release];
        if (!arch) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.binary_archive_new: %s", msg);
            w_raise(w_string(buf));
        }
        WMetalLibrary *w = (WMetalLibrary *)calloc(1, sizeof(WMetalLibrary));
        w->type = W_TYPE_METAL_LIBRARY;
        w->handle = (void *)arch;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    }
    w_raise(w_string("Metal.binary_archive_new: requires macOS 11+"));
    return W_NIL;
}

/* Build a pipeline for kernel `name` with int function constants set
 * at indices 0..n-1 (n = length of `values_array`). Allows the Metal
 * compiler to specialize the kernel: known shapes fold loop bounds,
 * enable unrolling, and eliminate per-arg bookkeeping. */
WValue w_metal_pipeline_for_with_int_constants(WValue library_v, WValue name_v, WValue values_v) {
    WMetalLibrary *l = as_metal_library(library_v);
    if (!l) w_raise(w_string("Metal.pipeline_for_with_int_constants: bad library"));
    if (!w_is_string(name_v)) w_raise(w_string("Metal.pipeline_for_with_int_constants: name must be string"));
    if (!w_is_array(values_v)) w_raise(w_string("Metal.pipeline_for_with_int_constants: values must be array"));
    WArray *vals = (WArray *)w_as_ptr(values_v);
    id<MTLLibrary> lib = (id<MTLLibrary>)l->handle;
    NSString *name = [NSString stringWithUTF8String:metal_string_data(name_v)];

    MTLFunctionConstantValues *fcv = [[MTLFunctionConstantValues alloc] init];
    for (int32_t i = 0; i < vals->size; i++) {
        int32_t v = (int32_t)w_to_i64(vals->slots[vals->start + i]);
        [fcv setConstantValue:&v type:MTLDataTypeInt atIndex:(NSUInteger)i];
    }

    NSError *err = nil;
    id<MTLFunction> fn = [lib newFunctionWithName:name constantValues:fcv error:&err];
    [fcv release];
    if (!fn) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal.pipeline_for_with_int_constants: function fetch failed: %s", msg);
        w_raise(w_string(buf));
    }
    id<MTLDevice> dev = [lib device];
    id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:&err];
    [fn release];
    if (!ps) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal.pipeline_for_with_int_constants: pipeline build failed: %s", msg);
        w_raise(w_string(buf));
    }
    WMetalPipeline *w = (WMetalPipeline *)calloc(1, sizeof(WMetalPipeline));
    w->type = W_TYPE_METAL_PIPELINE;
    w->handle = (void *)ps;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

WValue w_metal_buffer_new(WValue device_v, WValue byte_length_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) {
        w_raise(w_string("Metal.buffer_new: first arg must be a Metal device"));
    }
    int64_t n = w_to_i64(byte_length_v);
    if (n <= 0) {
        w_raise(w_string("Metal.buffer_new: byte length must be positive"));
    }
    id<MTLDevice> dev = (id<MTLDevice>)d->handle;
    id<MTLBuffer> buf = [dev newBufferWithLength:(NSUInteger)n options:MTLResourceStorageModeShared];
    if (!buf) {
        w_raise(w_string("Metal.buffer_new: allocation failed"));
    }
    /* Zero the contents — Metal's newBufferWithLength doesn't promise zeroing. */
    memset([buf contents], 0, (size_t)n);
    WMetalBuffer *w = (WMetalBuffer *)calloc(1, sizeof(WMetalBuffer));
    w->type = W_TYPE_METAL_BUFFER;
    w->handle = (void *)buf;
    w->size = n;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

WValue w_metal_buffer_length(WValue buffer_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.length: not a buffer"));
    return w_int(b->size);
}

/* Phase 7a (#12): zero-copy WArray → MTLBuffer wrap. On Apple Silicon's
 * unified memory architecture, `newBufferWithBytesNoCopy:` makes the
 * GPU see the same physical pages as the CPU's allocation — no copy,
 * no upload. The buffer is a borrowed view; caller is responsible for
 * keeping the WArray alive while the buffer is in use.
 *
 * Gated on ebits suitable for direct GPU consumption:
 *   8, 16, 32, 64, -32, -64 — byte- or element-aligned, dense layout
 * Rejected:
 *   1, 4    — bit-packed; GPU kernels would need to unpack each lane
 *   65      — polymorphic w64 stores NaN-boxed WValues, not raw values
 *             a GPU compute shader could meaningfully read
 *
 * The slots pointer must be page-aligned for the no-copy path. WArray's
 * calloc-backed allocations are typically aligned but not guaranteed —
 * we check at runtime and fall back to copy mode if not aligned. */
WValue w_array_as_metal_buffer(WValue device_v, WValue arr_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) {
        w_raise(w_string("array.as_metal_buffer: first arg must be a Metal device"));
    }
    /* Accepts either WArray (size < 2^32) or WBigArray (int64 size, mmap
     * views).  Field semantics are parallel — extract once, then the rest
     * of the function operates on locals.  BigArray support is the bridge
     * that makes `mmap.view_at(...)` zero-copy weight loads work end-to-end:
     * mmap region → BigArray view → MTLBuffer over the same physical pages. */
    int8_t   e;
    int64_t  logical_size;
    int64_t  logical_start;
    uint8_t *slots_ptr;
    if (w_is_array(arr_v)) {
        WArray *a = (WArray *)w_as_ptr(arr_v);
        e             = a->ebits;
        logical_size  = (int64_t)a->size;
        logical_start = (int64_t)a->start;
        slots_ptr     = (uint8_t *)a->slots;
    } else if (w_is_big_array(arr_v)) {
        WBigArray *a = (WBigArray *)w_as_ptr(arr_v);
        e             = a->ebits;
        logical_size  = a->size;
        logical_start = a->start;
        slots_ptr     = a->slots;
    } else {
        w_raise(w_string("array.as_metal_buffer: receiver must be a typed array or big array"));
    }
    /* Suitable ebits: any fixed-width dense byte/element-aligned format.
     * All float-family ebits are NEGATIVE; storage = abs(value) with
     * special low-precision codes for the wide ones:
     *   8/16/32/64       — unsigned ints, storage = bits
     *   108 / 116        — i8 / i16, storage = 8 / 16
     *   -32 / -64        — f32 / f64, storage = abs(bits)
     *   -116             — bf16, storage = 16
     *   -108 / -109      — fp8 e4m3 / e5m2, storage = 8
     *   -104             — fp4 e2m1, storage = 4
     * Rejected: u1, u4 (bit-packed), 65 (polymorphic w64 stores
     * NaN-boxed WValue metadata, not raw values a kernel can consume). */
    int e_int = (int)e;
    if (e_int != 8 && e_int != 16 && e_int != 32 && e_int != 64 &&
        e_int != 108 && e_int != 116 &&
        e_int != -32 && e_int != -64 &&
        e_int != -116 && e_int != -108 && e_int != -109 && e_int != -104) {
        w_raise(w_string("array.as_metal_buffer: requires fixed-width typed array (u8/i8/u16/i16/u32/u64/f32/f64/bf16/f8/f4)"));
    }
    int64_t bits_per_elt;
    if (e_int == -116) bits_per_elt = 16;
    else if (e_int == -108 || e_int == -109) bits_per_elt = 8;
    else if (e_int == -104) bits_per_elt = 4;
    else if (e_int == 108) bits_per_elt = 8;
    else if (e_int == 116) bits_per_elt = 16;
    else if (e_int < 0) bits_per_elt = -e_int;
    else bits_per_elt = e_int;
    int64_t byte_length = (logical_size * bits_per_elt) / 8;
    if (byte_length <= 0) {
        w_raise(w_string("array.as_metal_buffer: empty array"));
    }
    void *base = slots_ptr + (logical_start * bits_per_elt) / 8;
    /* MTLBuffer requires page-aligned base for no-copy. The runtime
     * check below catches both cases (W_FLAG_PAGE_ALIGNED-marked arrays
     * from w_array_new_aligned AND occasionally-aligned calloc returns
     * for large allocations) — the flag is informational rather than a
     * fast path since `start` could offset the base out of alignment
     * even on flagged arrays. */
    NSUInteger page = (NSUInteger)getpagesize();
    id<MTLDevice> dev = (id<MTLDevice>)d->handle;
    id<MTLBuffer> buf;
    if (((uintptr_t)base & (page - 1)) == 0) {
        buf = [dev newBufferWithBytesNoCopy:base
                                     length:(NSUInteger)byte_length
                                    options:MTLResourceStorageModeShared
                                deallocator:nil];
    } else {
        buf = [dev newBufferWithBytes:base
                               length:(NSUInteger)byte_length
                              options:MTLResourceStorageModeShared];
    }
    if (!buf) {
        w_raise(w_string("array.as_metal_buffer: MTLBuffer allocation failed"));
    }
    WMetalBuffer *w = (WMetalBuffer *)calloc(1, sizeof(WMetalBuffer));
    w->type = W_TYPE_METAL_BUFFER;
    w->handle = (void *)buf;
    w->size = byte_length;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

/* Bulk copy from an mmap region into a Metal buffer.
 *
 *   metal_buffer_write_from_mmap(buf, dst_byte_offset, mmap, src_byte_offset, byte_length)
 *
 * Used by tungsten-llama at GGUF load time to push tensor weights
 * onto the GPU. memcpy under the hood — milliseconds for the whole
 * lm_head (330 MB) on Apple Silicon's unified memory. */
WValue w_metal_buffer_write_from_mmap(WValue buffer_v,
                                      WValue dst_offset_v,
                                      WValue mmap_v,
                                      WValue src_offset_v,
                                      WValue byte_length_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer_write_from_mmap: not a buffer"));
    if (!w_is_mmap(mmap_v)) w_raise(w_string("Metal.buffer_write_from_mmap: third arg must be an Mmap"));
    WMmap *m = (WMmap *)w_as_ptr(mmap_v);
    if (m->closed) w_raise(w_string("Metal.buffer_write_from_mmap: mmap is closed"));
    int64_t dst_off = w_to_i64(dst_offset_v);
    int64_t src_off = w_to_i64(src_offset_v);
    int64_t len     = w_to_i64(byte_length_v);
    if (dst_off < 0 || src_off < 0 || len < 0) w_raise(w_string("Metal.buffer_write_from_mmap: negative arg"));
    if (dst_off + len > b->size) w_raise(w_string("Metal.buffer_write_from_mmap: dst overrun"));
    if (src_off + len > m->size) w_raise(w_string("Metal.buffer_write_from_mmap: src overrun"));
    id<MTLBuffer> buf = (id<MTLBuffer>)b->handle;
    memcpy((char *)[buf contents] + dst_off, m->data + src_off, (size_t)len);
    /* Hint the OS to drop the cached mmap source pages — without this,
     * large repeated write_from_mmap calls (e.g. preloading a 17 GB MoE
     * weight set into MTLBuffers) double-count: pages stay resident in
     * the OS page cache AND get committed in the dst MTLBuffer, OOM-
     * killing memory-constrained systems. madvise on the page-aligned
     * interior slice releases the cached pages back to the OS. Safe
     * because mmap pages are file-backed (re-readable from disk on
     * next access) — NOT applicable to anonymous heap pages. */
    if (len >= 65536) {
        size_t pg = (size_t)getpagesize();
        uintptr_t base = (uintptr_t)(m->data + src_off);
        uintptr_t end  = base + (uintptr_t)len;
        uintptr_t aligned_base = (base + pg - 1) & ~(uintptr_t)(pg - 1);
        uintptr_t aligned_end  = end & ~(uintptr_t)(pg - 1);
        if (aligned_end > aligned_base) {
            madvise((void *)aligned_base, (size_t)(aligned_end - aligned_base), MADV_DONTNEED);
        }
    }
    return W_NIL;
}

/* Dequantize ONE Q8_0 row from mmap directly into a Metal buffer at
 * a given f32 offset. Used by the embedding lookup at inference
 * time: read N blocks (= row's quants / 32), produce N*32 f32 values.
 *
 *   q8_dequant_row(dst_buf, dst_off_in_floats, mmap, src_off_bytes, n_blocks)
 *
 * dst_buf must hold (dst_off_in_floats + n_blocks*32) f32s.
 * src_off_bytes points at the first byte of the row (a Q8_0 block
 * boundary; 34 bytes per block on disk). */
WValue w_q8_dequant_row(WValue dst_buf_v,
                        WValue dst_off_floats_v,
                        WValue mmap_v,
                        WValue src_off_v,
                        WValue n_blocks_v) {
    WMetalBuffer *db = as_metal_buffer(dst_buf_v);
    if (!db) w_raise(w_string("q8_dequant_row: dst must be a Metal buffer"));
    if (!w_is_mmap(mmap_v)) w_raise(w_string("q8_dequant_row: third arg must be an Mmap"));
    WMmap *m = (WMmap *)w_as_ptr(mmap_v);
    if (m->closed) w_raise(w_string("q8_dequant_row: mmap is closed"));
    int64_t dst_off = w_to_i64(dst_off_floats_v);
    int64_t src_off = w_to_i64(src_off_v);
    int64_t n       = w_to_i64(n_blocks_v);
    if (dst_off < 0 || src_off < 0 || n < 0) w_raise(w_string("q8_dequant_row: negative arg"));
    if (src_off + n * 34 > m->size) w_raise(w_string("q8_dequant_row: src overrun"));
    if ((dst_off + n * 32) * (int64_t)sizeof(float) > db->size) w_raise(w_string("q8_dequant_row: dst overrun"));
    const uint8_t *src = m->data + src_off;
    float *dst = (float *)[(id<MTLBuffer>)db->handle contents] + dst_off;
    for (int64_t b = 0; b < n; b++) {
        const uint8_t *blk = src + b * 34;
        /* f16 scale at bytes 0..1, little-endian. Cast through __fp16. */
        uint16_t sbits = (uint16_t)blk[0] | ((uint16_t)blk[1] << 8);
        __fp16 s_h;
        memcpy(&s_h, &sbits, 2);
        float s = (float)s_h;
        const int8_t *quants = (const int8_t *)(blk + 2);
        for (int j = 0; j < 32; j++) {
            dst[b * 32 + j] = s * (float)quants[j];
        }
    }
    return W_NIL;
}

/* Q8_0 deinterleave from interleaved on-disk format into separate
 * scales (f16) + quants (i8) Metal buffers, matching the cooperative
 * kernel's expected layout.
 *
 * GGUF Q8_0 block layout (34 bytes per 32 quants):
 *     bytes 0..1   uint16 scale (interpret as f16)
 *     bytes 2..33  int8[32] quants
 *
 *   q8_split_blocks(scales_buf, quants_buf, mmap, src_byte_offset, n_blocks)
 *
 * scales_buf must hold n_blocks * 2 bytes; quants_buf must hold
 * n_blocks * 32 bytes. Tight C loop — single-shot per tensor at load. */
WValue w_q8_split_blocks(WValue scales_buf_v,
                         WValue quants_buf_v,
                         WValue mmap_v,
                         WValue src_offset_v,
                         WValue n_blocks_v) {
    WMetalBuffer *sb = as_metal_buffer(scales_buf_v);
    WMetalBuffer *qb = as_metal_buffer(quants_buf_v);
    if (!sb || !qb) w_raise(w_string("q8_split_blocks: scales_buf and quants_buf must be Metal buffers"));
    if (!w_is_mmap(mmap_v)) w_raise(w_string("q8_split_blocks: third arg must be an Mmap"));
    WMmap *m = (WMmap *)w_as_ptr(mmap_v);
    if (m->closed) w_raise(w_string("q8_split_blocks: mmap is closed"));
    int64_t src_off = w_to_i64(src_offset_v);
    int64_t n       = w_to_i64(n_blocks_v);
    if (src_off < 0 || n < 0) w_raise(w_string("q8_split_blocks: negative arg"));
    if (src_off + n * 34 > m->size) w_raise(w_string("q8_split_blocks: src overrun"));
    if (n * 2  > sb->size) w_raise(w_string("q8_split_blocks: scales buffer too small"));
    if (n * 32 > qb->size) w_raise(w_string("q8_split_blocks: quants buffer too small"));
    const uint8_t *src = m->data + src_off;
    uint8_t *scales = (uint8_t *)[(id<MTLBuffer>)sb->handle contents];
    uint8_t *quants = (uint8_t *)[(id<MTLBuffer>)qb->handle contents];
    for (int64_t i = 0; i < n; i++) {
        /* scale: 2 bytes */
        scales[i * 2 + 0] = src[i * 34 + 0];
        scales[i * 2 + 1] = src[i * 34 + 1];
        /* quants: 32 bytes */
        memcpy(quants + i * 32, src + i * 34 + 2, 32);
    }
    return W_NIL;
}

WValue w_metal_buffer_write_f32(WValue buffer_v, WValue index_v, WValue value_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.write_f32: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(float);
    if (off < 0 || off + (int64_t)sizeof(float) > b->size) {
        w_raise(w_string("Metal.buffer.write_f32: index out of bounds"));
    }
    float v = (float)metal_to_double(value_v);
    memcpy((char *)[(id<MTLBuffer>)b->handle contents] + off, &v, sizeof(float));
    return W_NIL;
}

WValue w_metal_buffer_write_f16(WValue buffer_v, WValue index_v, WValue value_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.write_f16: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * 2;
    if (off < 0 || off + 2 > b->size) {
        w_raise(w_string("Metal.buffer.write_f16: index out of bounds"));
    }
    __fp16 v = (__fp16)metal_to_double(value_v);
    memcpy((char *)[(id<MTLBuffer>)b->handle contents] + off, &v, 2);
    return W_NIL;
}

WValue w_metal_buffer_read_f16(WValue buffer_v, WValue index_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.read_f16: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * 2;
    if (off < 0 || off + 2 > b->size) {
        w_raise(w_string("Metal.buffer.read_f16: index out of bounds"));
    }
    __fp16 v;
    memcpy(&v, (char *)[(id<MTLBuffer>)b->handle contents] + off, 2);
    return w_float((double)(float)v);
}

WValue w_metal_buffer_read_f32(WValue buffer_v, WValue index_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.read_f32: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(float);
    if (off < 0 || off + (int64_t)sizeof(float) > b->size) {
        w_raise(w_string("Metal.buffer.read_f32: index out of bounds"));
    }
    float v;
    memcpy(&v, (char *)[(id<MTLBuffer>)b->handle contents] + off, sizeof(float));
    return w_float((double)v);
}

WValue w_metal_buffer_write_i32(WValue buffer_v, WValue index_v, WValue value_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.write_i32: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(int32_t);
    if (off < 0 || off + (int64_t)sizeof(int32_t) > b->size) {
        w_raise(w_string("Metal.buffer.write_i32: index out of bounds"));
    }
    int32_t v = (int32_t)w_to_i64(value_v);
    memcpy((char *)[(id<MTLBuffer>)b->handle contents] + off, &v, sizeof(int32_t));
    return W_NIL;
}

WValue w_metal_buffer_read_i32(WValue buffer_v, WValue index_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.read_i32: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(int32_t);
    if (off < 0 || off + (int64_t)sizeof(int32_t) > b->size) {
        w_raise(w_string("Metal.buffer.read_i32: index out of bounds"));
    }
    int32_t v;
    memcpy(&v, (char *)[(id<MTLBuffer>)b->handle contents] + off, sizeof(int32_t));
    return w_int((int64_t)v);
}

WValue w_metal_buffer_write_i64(WValue buffer_v, WValue index_v, WValue value_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.write_i64: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(int64_t);
    if (off < 0 || off + (int64_t)sizeof(int64_t) > b->size) {
        w_raise(w_string("Metal.buffer.write_i64: index out of bounds"));
    }
    int64_t v = w_to_i64(value_v);
    memcpy((char *)[(id<MTLBuffer>)b->handle contents] + off, &v, sizeof(int64_t));
    return W_NIL;
}

WValue w_metal_buffer_read_i64(WValue buffer_v, WValue index_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.read_i64: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * (int64_t)sizeof(int64_t);
    if (off < 0 || off + (int64_t)sizeof(int64_t) > b->size) {
        w_raise(w_string("Metal.buffer.read_i64: index out of bounds"));
    }
    int64_t v;
    memcpy(&v, (char *)[(id<MTLBuffer>)b->handle contents] + off, sizeof(int64_t));
    return w_int(v);
}

/* bfloat16: the top 16 bits of an IEEE float32 (1 sign, 8 exponent, 7 mantissa).
 * Write rounds f32→bf16 round-to-nearest-even; read widens bf16→f32 by zero-
 * filling the low 16 mantissa bits. Used by Tensor's CPU face for the bf16
 * dtype (METAL_DTYPE_BFLOAT16 = 121), the dominant weight format for ML. */
WValue w_metal_buffer_write_bf16(WValue buffer_v, WValue index_v, WValue value_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.write_bf16: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * 2;
    if (off < 0 || off + 2 > b->size) {
        w_raise(w_string("Metal.buffer.write_bf16: index out of bounds"));
    }
    float f = (float)metal_to_double(value_v);
    uint32_t bits;
    memcpy(&bits, &f, sizeof(bits));
    /* round-to-nearest-even on the discarded low 16 bits */
    uint32_t rounding_bias = 0x7FFF + ((bits >> 16) & 1u);
    uint16_t bf = (uint16_t)((bits + rounding_bias) >> 16);
    memcpy((char *)[(id<MTLBuffer>)b->handle contents] + off, &bf, 2);
    return W_NIL;
}

WValue w_metal_buffer_read_bf16(WValue buffer_v, WValue index_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("Metal.buffer.read_bf16: not a buffer"));
    int64_t i = w_to_i64(index_v);
    int64_t off = i * 2;
    if (off < 0 || off + 2 > b->size) {
        w_raise(w_string("Metal.buffer.read_bf16: index out of bounds"));
    }
    uint16_t bf;
    memcpy(&bf, (char *)[(id<MTLBuffer>)b->handle contents] + off, 2);
    uint32_t bits = ((uint32_t)bf) << 16;
    float f;
    memcpy(&f, &bits, sizeof(f));
    return w_float((double)f);
}

/* Zero-copy Tungsten Array view over a buffer's contents. Because buffers are
 * MTLResourceStorageModeShared (unified memory), the returned array aliases the
 * same bytes the GPU sees — used by Tensor.matmul to hand the shared buffers to
 * Accelerate's sgemm without a copy. `ebits` is the array element encoding
 * (-32 = f32, -64 = f64, -116 = bf16); `length` is the element count. */
WValue w_metal_buffer_view(WValue buffer_v, WValue ebits_v, WValue length_v) {
    WMetalBuffer *b = as_metal_buffer(buffer_v);
    if (!b) w_raise(w_string("metal_buffer_view: not a buffer"));
    int64_t ebits  = w_to_i64(ebits_v);
    int64_t length = w_to_i64(length_v);
    if (length < 0) w_raise(w_string("metal_buffer_view: negative length"));
    /* Reject a view that would extend past the backing allocation. Without this
     * a length larger than the buffer yields an Array aliasing heap memory past
     * the buffer's end — an out-of-bounds read/write reachable from any .w
     * program via metal_buffer_view / a Tensor.wrap'd undersized buffer. Width
     * is computed in bits and the comparison is done by division so it stays
     * exact for sub-byte element codes (fp4) and never overflows. */
    int64_t elem_bits = w_array_storage_bits(ebits);
    if (elem_bits <= 0) w_raise(w_string("metal_buffer_view: invalid element width"));
    if (length > (b->size * 8) / elem_bits) {
        w_raise(w_string("metal_buffer_view: length exceeds buffer size"));
    }
    uint8_t *base = (uint8_t *)[(id<MTLBuffer>)b->handle contents];
    return w_array_view_raw(base, ebits, length);
}

WValue w_metal_queue_new(WValue device_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) w_raise(w_string("Metal.queue: first arg must be a Metal device"));
    id<MTLCommandQueue> q = [(id<MTLDevice>)d->handle newCommandQueue];
    if (!q) w_raise(w_string("Metal.queue: command queue creation failed"));
    WMetalQueue *w = (WMetalQueue *)calloc(1, sizeof(WMetalQueue));
    w->type = W_TYPE_METAL_QUEUE;
    w->handle = (void *)q;
    w->batch_cmd = NULL;
    w->batch_encoder = NULL;
    w->batch_pipeline = NULL;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

/* Programmatic Metal frame capture for shader-level profiling.
 *
 *   metal_capture_begin(device, "/tmp/bench.gputrace")
 *   // ... GPU work ...
 *   metal_capture_end
 *
 * Produces a `.gputrace` document that opens in Xcode's Frame Debugger,
 * giving per-kernel performance counters (ALU active %, memory stall %,
 * occupancy, etc.) — the data that's invisible from outside the GPU.
 *
 * Apple gates this behind `METAL_CAPTURE_ENABLED=1` env var when the
 * binary is launched outside Xcode (security: prevents random binaries
 * from spying on other apps' GPU work). If the env var isn't set,
 * startCaptureWithDescriptor: returns false; we surface that as a raise
 * with a remediation hint. */
WValue w_metal_capture_begin(WValue device_v, WValue path_v) {
    WMetalDevice *d = as_metal_device(device_v);
    if (!d) w_raise(w_string("Metal.capture_begin: first arg must be a Metal device"));
    if (!w_is_string(path_v)) w_raise(w_string("Metal.capture_begin: path must be a string"));
    const char *path = metal_string_data(path_v);
    if (!path) w_raise(w_string("Metal.capture_begin: path string read failed"));
    MTLCaptureManager *cm = [MTLCaptureManager sharedCaptureManager];
    MTLCaptureDescriptor *desc = [[[MTLCaptureDescriptor alloc] init] autorelease];
    desc.captureObject = (id<MTLDevice>)d->handle;
    desc.destination = MTLCaptureDestinationGPUTraceDocument;
    desc.outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    NSError *err = nil;
    if (![cm startCaptureWithDescriptor:desc error:&err]) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf),
                 "Metal.capture_begin: %s (set METAL_CAPTURE_ENABLED=1 if launching outside Xcode)",
                 msg);
        w_raise(w_string(buf));
    }
    return W_NIL;
}

WValue w_metal_capture_end(void) {
    MTLCaptureManager *cm = [MTLCaptureManager sharedCaptureManager];
    if ([cm isCapturing]) {
        [cm stopCapture];
    }
    return W_NIL;
}

/* Open a deferred-dispatch batch. While a batch is open on a queue,
 * subsequent metal_dispatch_* calls encode into one shared
 * MTLCommandBuffer + MTLComputeCommandEncoder instead of creating and
 * committing their own. metal_batch_commit ends the encoder, commits
 * the buffer, and waits.
 *
 * Cuts the per-token sync cost from O(dispatches) to O(batches): a
 * single forward pass that previously did 800+ commit/wait round trips
 * can now do 1, modulo CPU-GPU sync points (router top-K read-back). */
WValue w_metal_batch_begin(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_begin: bad queue"));
    if (q->batch_cmd) {
        w_raise(w_string("Metal.batch_begin: batch already open on this queue"));
    }
    id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
    /* The autoreleasepool inside dispatch_n drains at end of call; for
     * the batch, the command buffer must outlive that. Retain explicitly
     * and release in batch_commit. */
    id<MTLCommandBuffer> cmd = [[queue commandBuffer] retain];
    id<MTLComputeCommandEncoder> enc = [[cmd computeCommandEncoder] retain];
    q->batch_cmd = (void *)cmd;
    q->batch_encoder = (void *)enc;
    q->batch_pipeline = NULL;
    return W_NIL;
}

/* Open a *concurrent* batch — same as batch_begin but the encoder is
 * created with MTLDispatchTypeConcurrent. Subsequent dispatches in the
 * batch may execute out of order on the GPU when their data dependencies
 * allow. The caller is responsible for inserting w_metal_batch_barrier
 * between phases that have read-after-write dependencies (e.g. between
 * the gate+up phase and the silu_mul phase that consumes its output). */
WValue w_metal_batch_begin_concurrent(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_begin_concurrent: bad queue"));
    if (q->batch_cmd) {
        w_raise(w_string("Metal.batch_begin_concurrent: batch already open on this queue"));
    }
    id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
    id<MTLCommandBuffer> cmd = [[queue commandBuffer] retain];
    id<MTLComputeCommandEncoder> enc = [[cmd computeCommandEncoderWithDispatchType:MTLDispatchTypeConcurrent] retain];
    q->batch_cmd = (void *)cmd;
    q->batch_encoder = (void *)enc;
    q->batch_pipeline = NULL;
    return W_NIL;
}

/* Issue a memory barrier on the open batch's encoder. All dispatches
 * encoded BEFORE the barrier complete before any dispatch encoded
 * AFTER it begins. Required between phases of a concurrent batch
 * that have RAW data dependencies. No-op (but cheap) on a serial
 * encoder. */
WValue w_metal_batch_barrier(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_barrier: bad queue"));
    if (!q->batch_cmd) {
        w_raise(w_string("Metal.batch_barrier: no batch is open on this queue"));
    }
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc memoryBarrierWithScope:MTLBarrierScopeBuffers];
    return W_NIL;
}

/* Resource-specific memory barrier — barriers only on the listed
 * buffers rather than the encoder's entire buffer scope. Apple
 * documents this as cheaper than memoryBarrierWithScope when only a
 * few resources have RAW deps. Caller passes an array of WMetalBuffers
 * that the upcoming dispatches will read after preceding writes. */
WValue w_metal_batch_barrier_resources(WValue queue_v, WValue bufs_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_barrier_resources: bad queue"));
    if (!q->batch_cmd) w_raise(w_string("Metal.batch_barrier_resources: no batch open"));
    if (!w_is_array(bufs_v)) w_raise(w_string("Metal.batch_barrier_resources: bufs must be array"));
    WArray *bufs = (WArray *)w_as_ptr(bufs_v);
    if (bufs->size == 0) return W_NIL;

    id<MTLResource> res_arr[bufs->size];
    for (int32_t i = 0; i < bufs->size; i++) {
        WMetalBuffer *b = as_metal_buffer(bufs->slots[bufs->start + i]);
        if (!b) w_raise(w_string("Metal.batch_barrier_resources: arg is not a buffer"));
        res_arr[i] = (id<MTLResource>)b->handle;
    }
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc memoryBarrierWithResources:res_arr count:(NSUInteger)bufs->size];
    return W_NIL;
}

/* Allocate `length` bytes of threadgroup-scoped memory at the given
 * binding index for the NEXT dispatch on the open batch's encoder.
 * The kernel must declare a `threadgroup T*` argument with the
 * matching `[[threadgroup(index)]]` attribute. */
WValue w_metal_set_threadgroup_memory(WValue queue_v, WValue length_v, WValue index_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.set_threadgroup_memory: bad queue"));
    if (!q->batch_cmd) {
        w_raise(w_string("Metal.set_threadgroup_memory: no batch is open on this queue"));
    }
    int64_t length = w_to_i64(length_v);
    int64_t index = w_to_i64(index_v);
    if (length <= 0) w_raise(w_string("Metal.set_threadgroup_memory: length must be positive"));
    if (index < 0)   w_raise(w_string("Metal.set_threadgroup_memory: index must be non-negative"));
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index];
    return W_NIL;
}

/* End the open batch's encoder, commit the command buffer, wait for
 * GPU completion. Resets the queue to eager mode. */
WValue w_metal_batch_commit(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_commit: bad queue"));
    if (!q->batch_cmd) {
        w_raise(w_string("Metal.batch_commit: no batch is open on this queue"));
    }
    id<MTLCommandBuffer> cmd = (id<MTLCommandBuffer>)q->batch_cmd;
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    MTLCommandBufferStatus status = [cmd status];
    NSError *err = [cmd error];
    [enc release];
    [cmd release];
    q->batch_cmd = NULL;
    q->batch_encoder = NULL;
    q->batch_pipeline = NULL;
    if (status == MTLCommandBufferStatusError) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal.batch_commit: %s", msg);
        w_raise(w_string(buf));
    }
    return W_NIL;
}

/* Async commit — returns a handle to the in-flight command buffer
 * without waiting. Caller must eventually call w_metal_command_buffer_wait
 * on the handle (which blocks until completion and frees the cmd buffer).
 * Lets the host overlap encoding the next batch while the GPU runs this one. */
WValue w_metal_command_buffer_wait(WValue cb_v);

/* Internal type tag for an in-flight command buffer handle. We piggy-back
 * on the W_TYPE_METAL_BUFFER struct shape since we just need a void* handle. */
typedef struct WMetalCmdBuf {
    uint8_t type;     /* W_TYPE_METAL_BUFFER (reusing existing tag) */
    void *handle;     /* id<MTLCommandBuffer> */
    int64_t size;     /* unused — set to 0 (renamed from length, parallels WMetalBuffer) */
} WMetalCmdBuf;

WValue w_metal_batch_commit_async(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_commit_async: bad queue"));
    if (!q->batch_cmd) {
        w_raise(w_string("Metal.batch_commit_async: no batch is open on this queue"));
    }
    id<MTLCommandBuffer> cmd = (id<MTLCommandBuffer>)q->batch_cmd;
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc endEncoding];
    [cmd commit];
    [enc release];
    q->batch_cmd = NULL;
    q->batch_encoder = NULL;
    q->batch_pipeline = NULL;
    /* Wrap the cmd buffer in a fresh handle (caller waits later). */
    WMetalCmdBuf *w = (WMetalCmdBuf *)calloc(1, sizeof(WMetalCmdBuf));
    w->type = W_TYPE_METAL_BUFFER;  /* reuse — we only use as_ptr from here */
    w->handle = (void *)cmd;        /* already retained by batch_begin */
    w->size = 0;
    return w_box_ptr(w, W_SUBTAG_GENERIC);
}

WValue w_metal_command_buffer_wait(WValue cb_v) {
    WMetalCmdBuf *w = (WMetalCmdBuf *)w_as_ptr(cb_v);
    if (!w || !w->handle) w_raise(w_string("Metal.command_buffer_wait: bad handle"));
    id<MTLCommandBuffer> cmd = (id<MTLCommandBuffer>)w->handle;
    [cmd waitUntilCompleted];
    MTLCommandBufferStatus status = [cmd status];
    NSError *err = [cmd error];
    [cmd release];
    w->handle = NULL;
    free(w);
    if (status == MTLCommandBufferStatusError) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal.command_buffer_wait: %s", msg);
        w_raise(w_string(buf));
    }
    return W_NIL;
}

/* Same as w_metal_batch_commit, but returns the command buffer's GPU
 * elapsed time in milliseconds when Metal provides timestamps. This is
 * a profiling hook; callers can ignore the result and pay only a tiny
 * post-completion timestamp read. */
WValue w_metal_batch_commit_ms(WValue queue_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    if (!q) w_raise(w_string("Metal.batch_commit_ms: bad queue"));
    if (!q->batch_cmd) {
        w_raise(w_string("Metal.batch_commit_ms: no batch is open on this queue"));
    }
    id<MTLCommandBuffer> cmd = (id<MTLCommandBuffer>)q->batch_cmd;
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
    [enc endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    MTLCommandBufferStatus status = [cmd status];
    NSError *err = [cmd error];
    CFTimeInterval start = [cmd GPUStartTime];
    CFTimeInterval end = [cmd GPUEndTime];
    [enc release];
    [cmd release];
    q->batch_cmd = NULL;
    q->batch_encoder = NULL;
    q->batch_pipeline = NULL;
    if (status == MTLCommandBufferStatusError) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
        char buf[512];
        snprintf(buf, sizeof(buf), "Metal.batch_commit_ms: %s", msg);
        w_raise(w_string(buf));
    }
    double ms = 0.0;
    if (end > start) {
        ms = (double)((end - start) * 1000.0);
    }
    return w_float(ms);
}

/* Single-shape dispatcher for the v1 add_one smoke. Encodes 3 buffer
 * args at slots 0/1/2 and dispatches `threads` linearly along x.
 * Larger surface (variable buffer count, 2D/3D grids, threadgroup
 * shape) lands in a follow-up. Synchronous: commits + waits. */
/* Variable-buffer dispatcher. `bufs_v` is a Tungsten array of Metal
 * buffers; each buffer is bound to slot 0..n-1 in declaration order,
 * matching the @gpu kernel's parameter order. `threads` is the linear
 * grid extent along x. Synchronous: commits + waits.
 *
 * Buffer count is bounded only by Metal's argument-table size
 * (typically 31 buffers; bigger needs argument buffers, a v2 concern). */
WValue w_metal_dispatch_n(WValue queue_v,
                          WValue pipeline_v,
                          WValue bufs_v,
                          WValue threads_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    WMetalPipeline *p = as_metal_pipeline(pipeline_v);
    if (!q || !p) {
        w_raise(w_string("Metal.dispatch_n: bad queue or pipeline"));
    }
    if (!w_is_array(bufs_v)) {
        w_raise(w_string("Metal.dispatch_n: buffers must be an array"));
    }
    WArray *bufs = (WArray *)w_as_ptr(bufs_v);
    if (bufs->size <= 0) {
        w_raise(w_string("Metal.dispatch_n: buffer array is empty"));
    }
    int64_t threads = w_to_i64(threads_v);
    if (threads <= 0) {
        w_raise(w_string("Metal.dispatch_n: threads must be positive"));
    }

    if (q->batch_cmd) {
        /* Batched mode — encode into the queue's open command buffer.
         * No commit, no wait. Caller must close the batch with
         * w_metal_batch_commit before reading any output buffer. */
        id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [(id<MTLCommandQueue>)q->handle device];
        if (q->batch_pipeline != (void *)ps) {
            [enc setComputePipelineState:ps];
            q->batch_pipeline = (void *)ps;
        }
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_n: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        MTLSize gridSize = MTLSizeMake((NSUInteger)threads, 1, 1);
        NSUInteger tgw = [ps maxTotalThreadsPerThreadgroup];
        if (tgw > (NSUInteger)threads) tgw = (NSUInteger)threads;
        if (tgw == 0) tgw = 1;
        MTLSize threadgroupSize = MTLSizeMake(tgw, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        return W_NIL;
    }

    @autoreleasepool {
        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [queue device];
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:ps];
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                [enc endEncoding];
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_n: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        MTLSize gridSize = MTLSizeMake((NSUInteger)threads, 1, 1);
        NSUInteger tgw = [ps maxTotalThreadsPerThreadgroup];
        if (tgw > (NSUInteger)threads) tgw = (NSUInteger)threads;
        if (tgw == 0) tgw = 1;
        MTLSize threadgroupSize = MTLSizeMake(tgw, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) {
            NSError *err = [cmd error];
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.dispatch_n: %s", msg);
            w_raise(w_string(buf));
        }
    }
    return W_NIL;
}

/* Dispatch with explicit threadgroup shape. Use this when threads
 * within a threadgroup need to cooperate (simdgroup reductions,
 * threadgroup memory). Total grid threads = n_groups * threads_per_group.
 *
 * `n_groups`: how many threadgroups to launch.
 * `threads_per_group`: threads per threadgroup; must divide evenly into
 *                      Apple's max (typically 1024). For simdgroup-aligned
 *                      kernels pass a multiple of 32. */
WValue w_metal_dispatch_groups(WValue queue_v,
                                WValue pipeline_v,
                                WValue bufs_v,
                                WValue n_groups_v,
                                WValue threads_per_group_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    WMetalPipeline *p = as_metal_pipeline(pipeline_v);
    if (!q || !p) {
        w_raise(w_string("Metal.dispatch_groups: bad queue or pipeline"));
    }
    if (!w_is_array(bufs_v)) {
        w_raise(w_string("Metal.dispatch_groups: buffers must be an array"));
    }
    WArray *bufs = (WArray *)w_as_ptr(bufs_v);
    if (bufs->size <= 0) {
        w_raise(w_string("Metal.dispatch_groups: buffer array is empty"));
    }
    int64_t n_groups = w_to_i64(n_groups_v);
    int64_t threads_per_group = w_to_i64(threads_per_group_v);
    if (n_groups <= 0 || threads_per_group <= 0) {
        w_raise(w_string("Metal.dispatch_groups: n_groups and threads_per_group must be positive"));
    }

    if (q->batch_cmd) {
        /* Batched mode — same logic as dispatch_n's batch path. */
        id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [(id<MTLCommandQueue>)q->handle device];
        if (q->batch_pipeline != (void *)ps) {
            [enc setComputePipelineState:ps];
            q->batch_pipeline = (void *)ps;
        }
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_groups: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        MTLSize gridSize = MTLSizeMake((NSUInteger)(n_groups * threads_per_group), 1, 1);
        MTLSize threadgroupSize = MTLSizeMake((NSUInteger)threads_per_group, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        return W_NIL;
    }

    @autoreleasepool {
        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [queue device];
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:ps];
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                [enc endEncoding];
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_groups: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        MTLSize gridSize = MTLSizeMake((NSUInteger)(n_groups * threads_per_group), 1, 1);
        MTLSize threadgroupSize = MTLSizeMake((NSUInteger)threads_per_group, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) {
            NSError *err = [cmd error];
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.dispatch_groups: %s", msg);
            w_raise(w_string(buf));
        }
    }
    return W_NIL;
}

/* 3D dispatch — `dispatchThreadgroups:threadsPerThreadgroup:` with explicit
 * (x, y, z) for both the TG count and the threads-per-TG. Needed for
 * kernels that index `threadgroup_position_in_grid.y/z` or
 * `thread_position_in_threadgroup.y/z` (e.g. qwen3.6's Mamba/SSM step
 * kernel that uses (32, 4, 1) threads per TG and (1, Dv/4, B*Hv) TGs). */
WValue w_metal_dispatch_groups_3d(WValue queue_v,
                                  WValue pipeline_v,
                                  WValue bufs_v,
                                  WValue n_tg_x_v,
                                  WValue n_tg_y_v,
                                  WValue n_tg_z_v,
                                  WValue threads_x_v,
                                  WValue threads_y_v,
                                  WValue threads_z_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    WMetalPipeline *p = as_metal_pipeline(pipeline_v);
    if (!q || !p) w_raise(w_string("Metal.dispatch_groups_3d: bad queue or pipeline"));
    if (!w_is_array(bufs_v)) w_raise(w_string("Metal.dispatch_groups_3d: buffers must be an array"));
    WArray *bufs = (WArray *)w_as_ptr(bufs_v);
    if (bufs->size <= 0) w_raise(w_string("Metal.dispatch_groups_3d: buffer array is empty"));
    int64_t n_tg_x = w_to_i64(n_tg_x_v);
    int64_t n_tg_y = w_to_i64(n_tg_y_v);
    int64_t n_tg_z = w_to_i64(n_tg_z_v);
    int64_t tx = w_to_i64(threads_x_v);
    int64_t ty = w_to_i64(threads_y_v);
    int64_t tz = w_to_i64(threads_z_v);
    if (n_tg_x <= 0 || n_tg_y <= 0 || n_tg_z <= 0 || tx <= 0 || ty <= 0 || tz <= 0) {
        w_raise(w_string("Metal.dispatch_groups_3d: all dims must be positive"));
    }
    MTLSize tgGrid = MTLSizeMake((NSUInteger)n_tg_x, (NSUInteger)n_tg_y, (NSUInteger)n_tg_z);
    MTLSize tpg    = MTLSizeMake((NSUInteger)tx,     (NSUInteger)ty,     (NSUInteger)tz);

    if (q->batch_cmd) {
        id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)q->batch_encoder;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [(id<MTLCommandQueue>)q->handle device];
        if (q->batch_pipeline != (void *)ps) {
            [enc setComputePipelineState:ps];
            q->batch_pipeline = (void *)ps;
        }
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_groups_3d: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        [enc dispatchThreadgroups:tgGrid threadsPerThreadgroup:tpg];
        return W_NIL;
    }

    @autoreleasepool {
        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [queue device];
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:ps];
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, dev);
            if (!mb) {
                [enc endEncoding];
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.dispatch_groups_3d: arg %d is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        [enc dispatchThreadgroups:tgGrid threadsPerThreadgroup:tpg];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) {
            NSError *err = [cmd error];
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.dispatch_groups_3d: %s", msg);
            w_raise(w_string(buf));
        }
    }
    return W_NIL;
}

WValue w_metal_dispatch1(WValue queue_v,
                         WValue pipeline_v,
                         WValue buf0_v,
                         WValue buf1_v,
                         WValue buf2_v,
                         WValue threads_v) {
    WMetalQueue *q = as_metal_queue(queue_v);
    WMetalPipeline *p = as_metal_pipeline(pipeline_v);
    if (!q || !p) {
        w_raise(w_string("Metal.dispatch: bad queue or pipeline"));
    }
    int64_t threads = w_to_i64(threads_v);
    if (threads <= 0) {
        w_raise(w_string("Metal.dispatch: threads must be positive"));
    }

    @autoreleasepool {
        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)q->handle;
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)p->handle;
        id<MTLDevice> dev = [queue device];
        /* Phase 7d (#12): each buf arg may be a WMetalBuffer or WArray.
         * Wrap arrays inline; the helper returns autoreleased buffers
         * that survive until the @autoreleasepool exits at dispatch end. */
        id<MTLBuffer> mb0 = metal_buffer_or_wrap_array(buf0_v, dev);
        id<MTLBuffer> mb1 = metal_buffer_or_wrap_array(buf1_v, dev);
        id<MTLBuffer> mb2 = metal_buffer_or_wrap_array(buf2_v, dev);
        if (!mb0 || !mb1 || !mb2) {
            w_raise(w_string("Metal.dispatch: each buf arg must be a Metal buffer or GPU-eligible typed array"));
        }
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:ps];
        [enc setBuffer:mb0 offset:0 atIndex:0];
        [enc setBuffer:mb1 offset:0 atIndex:1];
        [enc setBuffer:mb2 offset:0 atIndex:2];
        MTLSize gridSize = MTLSizeMake((NSUInteger)threads, 1, 1);
        NSUInteger tgw = [ps maxTotalThreadsPerThreadgroup];
        if (tgw > (NSUInteger)threads) tgw = (NSUInteger)threads;
        if (tgw == 0) tgw = 1;
        MTLSize threadgroupSize = MTLSizeMake(tgw, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) {
            NSError *err = [cmd error];
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.dispatch: %s", msg);
            w_raise(w_string(buf));
        }
    }
    return W_NIL;
}

/* Phase 7f (#12): explicit sync — copy a Metal buffer's contents back
 * into a typed array. Needed when the array isn't page-aligned (so its
 * earlier wrap took the COPY path) and the GPU has written into the
 * buffer; the CPU-side array won't see those writes without this.
 *
 * For aligned arrays, base pointers are identical — the sync detects
 * that and short-circuits with no memcpy. Safe to call unconditionally
 * after any dispatch where you wrote through to a typed array via the
 * transparent-dispatch path. */
WValue w_metal_sync_array_from_buffer(WValue arr_v, WValue buf_v) {
    if (!w_is_array(arr_v)) {
        w_raise(w_string("Metal.sync: first arg must be a typed array"));
    }
    WMetalBuffer *b = as_metal_buffer(buf_v);
    if (!b) {
        w_raise(w_string("Metal.sync: second arg must be a Metal buffer"));
    }
    WArray *a = (WArray *)w_as_ptr(arr_v);
    int e_int = (int)a->ebits;
    int64_t bits_per_elt;
    if (e_int == -116 || e_int == 116) bits_per_elt = 16;
    else if (e_int == -108 || e_int == -109 || e_int == 108) bits_per_elt = 8;
    else if (e_int == -104) bits_per_elt = 4;
    else if (e_int < 0) bits_per_elt = -e_int;
    else bits_per_elt = e_int;
    if (bits_per_elt <= 0 || a->size <= 0) return W_NIL;
    int64_t byte_length = (a->size * bits_per_elt) / 8;
    if (byte_length > b->size) byte_length = b->size;
    void *arr_base = (uint8_t *)a->slots + (a->start * bits_per_elt) / 8;
    void *buf_base = [(id<MTLBuffer>)b->handle contents];
    /* Aligned (zero-copy) case: the buffer's contents pointer IS the
     * array's slots pointer — no copy needed. */
    if (arr_base == buf_base) return W_NIL;
    memcpy(arr_base, buf_base, (size_t)byte_length);
    return W_NIL;
}

/* Phase 7e (#12): one-shot compute helper.
 *
 *   metal_compute(source, kernel_name, bufs, threads)
 *
 * Compile MSL `source`, look up `kernel_name`, dispatch with `bufs`
 * (each elem may be MTLBuffer or WArray) over `threads` linear threads.
 * Compile + pipeline are cached by source + name so repeated calls
 * skip both. Default device + queue are cached too — first call
 * creates them, subsequent calls reuse.
 *
 * The cache is keyed on the FULL source string + "||" + kernel_name.
 * NSDictionary handles equality via -isEqualToString:; for very long
 * shaders this is O(n) per lookup, fine for typical inference workloads
 * where a few dozen kernels are reused millions of times. */
static NSMutableDictionary<NSString *, id> *g_metal_pipeline_cache = nil;
static id<MTLDevice>                       g_metal_default_device   = nil;
static id<MTLCommandQueue>                 g_metal_default_queue    = nil;

WValue w_metal_compute(WValue source_v, WValue name_v,
                       WValue bufs_v, WValue threads_v) {
    if (!w_is_string(source_v)) {
        w_raise(w_string("Metal.compute: source must be a string"));
    }
    if (!w_is_string(name_v)) {
        w_raise(w_string("Metal.compute: kernel_name must be a string"));
    }
    if (!w_is_array(bufs_v)) {
        w_raise(w_string("Metal.compute: bufs must be an array"));
    }
    int64_t threads = w_to_i64(threads_v);
    if (threads <= 0) {
        w_raise(w_string("Metal.compute: threads must be positive"));
    }

    @autoreleasepool {
        if (g_metal_default_device == nil) {
            g_metal_default_device = MTLCreateSystemDefaultDevice();
            if (!g_metal_default_device) {
                w_raise(w_string("Metal.compute: no default device"));
            }
            [g_metal_default_device retain];
            g_metal_default_queue = [g_metal_default_device newCommandQueue];
        }
        if (g_metal_pipeline_cache == nil) {
            g_metal_pipeline_cache = [[NSMutableDictionary alloc] init];
        }

        NSString *src   = [NSString stringWithUTF8String:metal_string_data(source_v)];
        NSString *kname = [NSString stringWithUTF8String:metal_string_data(name_v)];
        NSString *key   = [NSString stringWithFormat:@"%@||%@", src, kname];

        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)g_metal_pipeline_cache[key];
        if (!ps) {
            NSError *err = nil;
            MTLCompileOptions *opts = metal_make_compile_opts(0);
            id<MTLLibrary> lib = [g_metal_default_device newLibraryWithSource:src options:opts error:&err];
            [opts release];
            if (!lib) {
                const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
                char buf[1024];
                snprintf(buf, sizeof(buf), "Metal.compute: source compile: %s", msg);
                w_raise(w_string(buf));
            }
            id<MTLFunction> fn = [lib newFunctionWithName:kname];
            if (!fn) {
                char buf[256];
                snprintf(buf, sizeof(buf), "Metal.compute: kernel `%s` not found", metal_string_data(name_v));
                w_raise(w_string(buf));
            }
            ps = [g_metal_default_device newComputePipelineStateWithFunction:fn error:&err];
            [fn release];
            [lib release];
            if (!ps) {
                const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
                char buf[512];
                snprintf(buf, sizeof(buf), "Metal.compute: pipeline build: %s", msg);
                w_raise(w_string(buf));
            }
            g_metal_pipeline_cache[key] = ps;
            [ps release];  /* dictionary retained it; balance */
        }

        WArray *bufs = (WArray *)w_as_ptr(bufs_v);
        id<MTLCommandBuffer> cmd = [g_metal_default_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:ps];
        for (int32_t i = 0; i < bufs->size; i++) {
            WValue bv = bufs->slots[bufs->start + i];
            id<MTLBuffer> mb = metal_buffer_or_wrap_array(bv, g_metal_default_device);
            if (!mb) {
                [enc endEncoding];
                char msg[112];
                snprintf(msg, sizeof(msg), "Metal.compute: bufs[%d] is not a Metal buffer or GPU-eligible typed array", i);
                w_raise(w_string(msg));
            }
            [enc setBuffer:mb offset:0 atIndex:(NSUInteger)i];
        }
        MTLSize gridSize = MTLSizeMake((NSUInteger)threads, 1, 1);
        NSUInteger tgw = [ps maxTotalThreadsPerThreadgroup];
        if (tgw > (NSUInteger)threads) tgw = (NSUInteger)threads;
        if (tgw == 0) tgw = 1;
        MTLSize threadgroupSize = MTLSizeMake(tgw, 1, 1);
        [enc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) {
            NSError *err = [cmd error];
            const char *msg = err ? [[err localizedDescription] UTF8String] : "unknown error";
            char buf[512];
            snprintf(buf, sizeof(buf), "Metal.compute: dispatch: %s", msg);
            w_raise(w_string(buf));
        }
    }
    return W_NIL;
}

/* The Metal 4 / MTL4 types below (MTLTensor, MTLTensorDescriptor,
 * MTLTensorExtents, MTL4Compiler, MTL4*, ...) are only declared by the
 * macOS 26 SDK. On older SDKs (e.g. Xcode 16.4 / macOS 15 in CI) they are
 * undeclared identifiers, so the whole section must be compiled out at the
 * SDK level — the runtime `@available` guards only gate execution, not
 * compilation. Public `w_*` entry points get link-compatible stubs in the
 * #else branch so external callers still link on the old SDK. */
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
/* ============================================================
 * Metal 4 tensor + MTL4 command path (macOS 26+)
 *
 * The legacy MTLComputeCommandEncoder has no setTensor / argument-table
 * binding API, so kernel parameters typed as `tensor<...>` (consumed by
 * matmul2d cooperative tensors) require this parallel command stack.
 *
 * Existing buffer-only kernels keep using the legacy path; MTL4 is opt-in
 * per-kernel. All-in-one dispatch (begin → encode → end → commit → wait)
 * keeps the surface narrow until we need finer control.
 * ============================================================ */

API_AVAILABLE(macos(26.0))
static WMetalTensor *as_metal_tensor(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetalTensor *t = (WMetalTensor *)w_as_ptr(v);
    if (t->type != W_TYPE_METAL_TENSOR) return NULL;
    return t;
}

API_AVAILABLE(macos(26.0))
static WMetal4Queue *as_metal4_queue(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetal4Queue *q = (WMetal4Queue *)w_as_ptr(v);
    if (q->type != W_TYPE_METAL4_QUEUE) return NULL;
    return q;
}

API_AVAILABLE(macos(26.0))
static WMetal4Allocator *as_metal4_allocator(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetal4Allocator *a = (WMetal4Allocator *)w_as_ptr(v);
    if (a->type != W_TYPE_METAL4_ALLOCATOR) return NULL;
    return a;
}

API_AVAILABLE(macos(26.0))
static WMetal4ArgTable *as_metal4_argtable(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetal4ArgTable *a = (WMetal4ArgTable *)w_as_ptr(v);
    if (a->type != W_TYPE_METAL4_ARGTABLE) return NULL;
    return a;
}

API_AVAILABLE(macos(26.0))
static WMetal4Compiler *as_metal4_compiler(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WMetal4Compiler *c = (WMetal4Compiler *)w_as_ptr(v);
    if (c->type != W_TYPE_METAL4_COMPILER) return NULL;
    return c;
}

WValue w_metal4_compiler_new(WValue device_v) {
    if (@available(macOS 26.0, *)) {
        WMetalDevice *d = as_metal_device(device_v);
        if (!d) w_raise(w_string("metal4_compiler_new: bad device"));
        id<MTLDevice> dev = (id<MTLDevice>)d->handle;
        MTL4CompilerDescriptor *desc = [[[MTL4CompilerDescriptor alloc] init] autorelease];
        NSError *err = nil;
        id<MTL4Compiler> comp = [dev newCompilerWithDescriptor:desc error:&err];
        if (!comp) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "newCompiler failed";
            char buf[512];
            snprintf(buf, sizeof(buf), "metal4_compiler_new: %s", msg);
            w_raise(w_string(buf));
        }
        WMetal4Compiler *w = (WMetal4Compiler *)calloc(1, sizeof(WMetal4Compiler));
        w->type   = W_TYPE_METAL4_COMPILER;
        w->handle = (void *)comp;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal4_compiler_new: requires macOS 26+"));
        return W_NIL;
    }
}

/* Build a compute pipeline via MTL4Compiler with requiredThreadsPerThreadgroup
 * set — this is mandatory when the kernel uses cooperative tensors (matmul2d).
 * The legacy newComputePipelineStateWithFunction path can't set this property,
 * which is why kernels using `op.run(...)` with cooperative storage silently
 * mis-dispatch tiles when built that way. */
WValue w_metal4_pipeline_for(WValue compiler_v, WValue library_v, WValue name_v,
                             WValue threads_x_v, WValue threads_y_v, WValue threads_z_v) {
    if (@available(macOS 26.0, *)) {
        WMetal4Compiler *c = as_metal4_compiler(compiler_v);
        if (!c) w_raise(w_string("metal4_pipeline_for: bad compiler"));
        WMetalLibrary *l = as_metal_library(library_v);
        if (!l) w_raise(w_string("metal4_pipeline_for: bad library"));
        if (!w_is_string(name_v)) w_raise(w_string("metal4_pipeline_for: name must be a string"));
        int64_t tx = w_to_i64(threads_x_v);
        int64_t ty = w_to_i64(threads_y_v);
        int64_t tz = w_to_i64(threads_z_v);
        if (tx <= 0 || ty <= 0 || tz <= 0) {
            w_raise(w_string("metal4_pipeline_for: threads_per_tg dimensions must be positive"));
        }

        id<MTL4Compiler> comp = (id<MTL4Compiler>)c->handle;
        id<MTLLibrary> lib    = (id<MTLLibrary>)l->handle;
        NSString *fn_name     = [NSString stringWithUTF8String:metal_string_data(name_v)];

        MTL4LibraryFunctionDescriptor *fn_desc = [[[MTL4LibraryFunctionDescriptor alloc] init] autorelease];
        fn_desc.library = lib;
        fn_desc.name    = fn_name;

        MTL4ComputePipelineDescriptor *pd = [[[MTL4ComputePipelineDescriptor alloc] init] autorelease];
        pd.computeFunctionDescriptor       = fn_desc;
        pd.requiredThreadsPerThreadgroup   = MTLSizeMake((NSUInteger)tx, (NSUInteger)ty, (NSUInteger)tz);

        NSError *err = nil;
        id<MTLComputePipelineState> ps = [comp newComputePipelineStateWithDescriptor:pd
                                                                  compilerTaskOptions:nil
                                                                                error:&err];
        if (!ps) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "newComputePipelineState failed";
            char buf[512];
            snprintf(buf, sizeof(buf), "metal4_pipeline_for: %s", msg);
            w_raise(w_string(buf));
        }
        WMetalPipeline *w = (WMetalPipeline *)calloc(1, sizeof(WMetalPipeline));
        w->type   = W_TYPE_METAL_PIPELINE;
        w->handle = (void *)ps;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal4_pipeline_for: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal_tensor_2d(WValue buffer_v, WValue dtype_v,
                         WValue dim_rows_v, WValue dim_cols_v,
                         WValue stride_rows_v, WValue byte_offset_v) {
    if (@available(macOS 26.0, *)) {
        WMetalBuffer *b = as_metal_buffer(buffer_v);
        if (!b) w_raise(w_string("metal_tensor_2d: bad buffer"));
        int64_t dtype       = w_to_i64(dtype_v);
        int64_t dim_rows    = w_to_i64(dim_rows_v);
        int64_t dim_cols    = w_to_i64(dim_cols_v);
        int64_t stride_rows = w_to_i64(stride_rows_v);
        int64_t byte_offset = w_to_i64(byte_offset_v);

        /* Apple convention: dimension index 0 is the *innermost* dim.
         * For a row-major (rows, cols) tensor where columns vary fastest,
         * innermost = cols, then rows. Same for strides — first stride is 1. */
        NSInteger dims[2]    = { (NSInteger)dim_cols, (NSInteger)dim_rows };
        NSInteger strides[2] = { 1, (NSInteger)(stride_rows > 0 ? stride_rows : dim_cols) };

        MTLTensorExtents *extents = [[[MTLTensorExtents alloc] initWithRank:2 values:dims] autorelease];
        MTLTensorExtents *strs    = [[[MTLTensorExtents alloc] initWithRank:2 values:strides] autorelease];

        MTLTensorDescriptor *desc = [[[MTLTensorDescriptor alloc] init] autorelease];
        desc.dimensions = extents;
        desc.strides    = strs;
        desc.dataType   = (MTLTensorDataType)dtype;
        desc.usage      = MTLTensorUsageCompute;

        id<MTLBuffer> mb = (id<MTLBuffer>)b->handle;
        NSError *err = nil;
        id<MTLTensor> tensor = [mb newTensorWithDescriptor:desc offset:(NSUInteger)byte_offset error:&err];
        if (!tensor) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "newTensor failed";
            char buf[512];
            snprintf(buf, sizeof(buf), "metal_tensor_2d: %s", msg);
            w_raise(w_string(buf));
        }
        WMetalTensor *t = (WMetalTensor *)calloc(1, sizeof(WMetalTensor));
        t->type   = W_TYPE_METAL_TENSOR;
        t->handle = (void *)tensor;
        return w_box_ptr(t, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal_tensor_2d: requires macOS 26+"));
        return W_NIL;
    }
}

/* Rank-N generalization of w_metal_tensor_2d. `shape` is a Tungsten Array of
 * dims in row-major (outer→inner) order — the NumPy/PyTorch convention.
 * `strides` is either nil/empty (→ tightly-packed default) or an Array of
 * element strides in the same outer→inner order. We reverse both to Apple's
 * innermost-axis-first MTLTensorExtents convention (dim index 0 = innermost),
 * exactly as the 2-D path does for {cols, rows}. byte_offset is into buffer. */
#define W_TENSOR_MAX_RANK 16
WValue w_metal_tensor_nd(WValue buffer_v, WValue dtype_v,
                         WValue shape_v, WValue strides_v, WValue byte_offset_v) {
    if (@available(macOS 26.0, *)) {
        WMetalBuffer *b = as_metal_buffer(buffer_v);
        if (!b) w_raise(w_string("metal_tensor_nd: bad buffer"));
        /* w_is_array (not just w_is_obj): a non-array heap object would have its
         * arbitrary struct fields read as sh->size/sh->slots — a memory
         * disclosure/crash surface reachable through ccall. */
        if (!w_is_array(shape_v)) w_raise(w_string("metal_tensor_nd: shape must be an Array"));
        WArray *sh = (WArray *)w_as_ptr(shape_v);
        int64_t rank = (int64_t)sh->size;
        if (rank < 1 || rank > W_TENSOR_MAX_RANK) {
            w_raise(w_string("metal_tensor_nd: rank must be in [1, 16]"));
        }
        int64_t dtype       = w_to_i64(dtype_v);
        int64_t byte_offset = w_to_i64(byte_offset_v);
        if (byte_offset < 0) w_raise(w_string("metal_tensor_nd: negative byte_offset"));

        /* Optional explicit strides (outer→inner). Empty/nil → packed default. */
        WArray *st = NULL;
        if (w_is_array(strides_v)) {
            st = (WArray *)w_as_ptr(strides_v);
            if (st->size != 0 && (int64_t)st->size != rank) {
                w_raise(w_string("metal_tensor_nd: strides rank != shape rank"));
            }
            if (st->size == 0) st = NULL;
        }

        /* Build innermost-first dims (apple_dims[0] = innermost = public last). */
        NSInteger dims[W_TENSOR_MAX_RANK];
        NSInteger strides[W_TENSOR_MAX_RANK];
        for (int64_t k = 0; k < rank; k++) {
            int64_t pub = rank - 1 - k;                       /* reverse axis */
            dims[k] = (NSInteger)w_to_i64(sh->slots[sh->start + pub]);
            if (dims[k] <= 0) w_raise(w_string("metal_tensor_nd: dims must be positive"));
        }
        if (st) {
            for (int64_t k = 0; k < rank; k++) {
                int64_t pub = rank - 1 - k;
                strides[k] = (NSInteger)w_to_i64(st->slots[st->start + pub]);
            }
        } else {
            /* tightly-packed: innermost stride 1, each next = prev_dim * prev_stride */
            strides[0] = 1;
            for (int64_t k = 1; k < rank; k++) {
                strides[k] = strides[k - 1] * dims[k - 1];
            }
        }

        MTLTensorExtents *extents = [[[MTLTensorExtents alloc] initWithRank:(NSUInteger)rank values:dims] autorelease];
        MTLTensorExtents *strs    = [[[MTLTensorExtents alloc] initWithRank:(NSUInteger)rank values:strides] autorelease];

        MTLTensorDescriptor *desc = [[[MTLTensorDescriptor alloc] init] autorelease];
        desc.dimensions = extents;
        desc.strides    = strs;
        desc.dataType   = (MTLTensorDataType)dtype;
        desc.usage      = MTLTensorUsageCompute;

        id<MTLBuffer> mb = (id<MTLBuffer>)b->handle;
        NSError *err = nil;
        id<MTLTensor> tensor = [mb newTensorWithDescriptor:desc offset:(NSUInteger)byte_offset error:&err];
        if (!tensor) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "newTensor failed";
            char buf[512];
            snprintf(buf, sizeof(buf), "metal_tensor_nd: %s", msg);
            w_raise(w_string(buf));
        }
        WMetalTensor *t = (WMetalTensor *)calloc(1, sizeof(WMetalTensor));
        t->type   = W_TYPE_METAL_TENSOR;
        t->handle = (void *)tensor;
        return w_box_ptr(t, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal_tensor_nd: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_queue_new(WValue device_v) {
    if (@available(macOS 26.0, *)) {
        WMetalDevice *d = as_metal_device(device_v);
        if (!d) w_raise(w_string("metal4_queue_new: bad device"));
        id<MTLDevice> dev = (id<MTLDevice>)d->handle;
        id<MTL4CommandQueue> q = [dev newMTL4CommandQueue];
        if (!q) w_raise(w_string("metal4_queue_new: newMTL4CommandQueue failed"));
        WMetal4Queue *w = (WMetal4Queue *)calloc(1, sizeof(WMetal4Queue));
        w->type   = W_TYPE_METAL4_QUEUE;
        w->handle = (void *)q;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal4_queue_new: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_allocator_new(WValue device_v) {
    if (@available(macOS 26.0, *)) {
        WMetalDevice *d = as_metal_device(device_v);
        if (!d) w_raise(w_string("metal4_allocator_new: bad device"));
        id<MTLDevice> dev = (id<MTLDevice>)d->handle;
        id<MTL4CommandAllocator> a = [dev newCommandAllocator];
        if (!a) w_raise(w_string("metal4_allocator_new: newCommandAllocator failed"));
        WMetal4Allocator *w = (WMetal4Allocator *)calloc(1, sizeof(WMetal4Allocator));
        w->type   = W_TYPE_METAL4_ALLOCATOR;
        w->handle = (void *)a;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal4_allocator_new: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_argtable_new(WValue device_v, WValue max_buffers_v) {
    if (@available(macOS 26.0, *)) {
        WMetalDevice *d = as_metal_device(device_v);
        if (!d) w_raise(w_string("metal4_argtable_new: bad device"));
        int64_t max_buffers = w_to_i64(max_buffers_v);
        if (max_buffers <= 0 || max_buffers > 31) {
            w_raise(w_string("metal4_argtable_new: max_buffers must be in [1, 31]"));
        }
        id<MTLDevice> dev = (id<MTLDevice>)d->handle;
        MTL4ArgumentTableDescriptor *desc = [[[MTL4ArgumentTableDescriptor alloc] init] autorelease];
        desc.maxBufferBindCount = (NSUInteger)max_buffers;
        desc.initializeBindings = YES;
        NSError *err = nil;
        id<MTL4ArgumentTable> tbl = [dev newArgumentTableWithDescriptor:desc error:&err];
        if (!tbl) {
            const char *msg = err ? [[err localizedDescription] UTF8String] : "newArgumentTable failed";
            char buf[512];
            snprintf(buf, sizeof(buf), "metal4_argtable_new: %s", msg);
            w_raise(w_string(buf));
        }
        WMetal4ArgTable *w = (WMetal4ArgTable *)calloc(1, sizeof(WMetal4ArgTable));
        w->type        = W_TYPE_METAL4_ARGTABLE;
        w->handle      = (void *)tbl;
        w->max_buffers = (int32_t)max_buffers;
        return w_box_ptr(w, W_SUBTAG_GENERIC);
    } else {
        w_raise(w_string("metal4_argtable_new: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_argtable_set_buffer(WValue argtable_v, WValue index_v, WValue buffer_v) {
    if (@available(macOS 26.0, *)) {
        WMetal4ArgTable *t = as_metal4_argtable(argtable_v);
        if (!t) w_raise(w_string("metal4_argtable_set_buffer: bad argtable"));
        WMetalBuffer *b = as_metal_buffer(buffer_v);
        if (!b) w_raise(w_string("metal4_argtable_set_buffer: bad buffer"));
        int64_t idx = w_to_i64(index_v);
        if (idx < 0 || idx >= t->max_buffers) {
            w_raise(w_string("metal4_argtable_set_buffer: index out of range"));
        }
        id<MTL4ArgumentTable> tbl = (id<MTL4ArgumentTable>)t->handle;
        id<MTLBuffer> mb = (id<MTLBuffer>)b->handle;
        [tbl setAddress:[mb gpuAddress] atIndex:(NSUInteger)idx];
        return W_NIL;
    } else {
        w_raise(w_string("metal4_argtable_set_buffer: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_argtable_set_buffer_offset(WValue argtable_v, WValue index_v,
                                           WValue buffer_v, WValue byte_offset_v) {
    if (@available(macOS 26.0, *)) {
        WMetal4ArgTable *t = as_metal4_argtable(argtable_v);
        if (!t) w_raise(w_string("metal4_argtable_set_buffer_offset: bad argtable"));
        WMetalBuffer *b = as_metal_buffer(buffer_v);
        if (!b) w_raise(w_string("metal4_argtable_set_buffer_offset: bad buffer"));
        int64_t idx    = w_to_i64(index_v);
        int64_t offset = w_to_i64(byte_offset_v);
        if (idx < 0 || idx >= t->max_buffers) {
            w_raise(w_string("metal4_argtable_set_buffer_offset: index out of range"));
        }
        id<MTL4ArgumentTable> tbl = (id<MTL4ArgumentTable>)t->handle;
        id<MTLBuffer> mb = (id<MTLBuffer>)b->handle;
        [tbl setAddress:([mb gpuAddress] + (NSUInteger)offset) atIndex:(NSUInteger)idx];
        return W_NIL;
    } else {
        w_raise(w_string("metal4_argtable_set_buffer_offset: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_argtable_set_tensor(WValue argtable_v, WValue index_v, WValue tensor_v) {
    if (@available(macOS 26.0, *)) {
        WMetal4ArgTable *t = as_metal4_argtable(argtable_v);
        if (!t) w_raise(w_string("metal4_argtable_set_tensor: bad argtable"));
        WMetalTensor *te = as_metal_tensor(tensor_v);
        if (!te) w_raise(w_string("metal4_argtable_set_tensor: bad tensor"));
        int64_t idx = w_to_i64(index_v);
        if (idx < 0 || idx >= t->max_buffers) {
            w_raise(w_string("metal4_argtable_set_tensor: index out of range"));
        }
        id<MTL4ArgumentTable> tbl = (id<MTL4ArgumentTable>)t->handle;
        id<MTLTensor> tensor = (id<MTLTensor>)te->handle;
        [tbl setResource:[tensor gpuResourceID] atBufferIndex:(NSUInteger)idx];
        return W_NIL;
    } else {
        w_raise(w_string("metal4_argtable_set_tensor: requires macOS 26+"));
        return W_NIL;
    }
}

WValue w_metal4_dispatch_groups_3d(WValue queue_v, WValue allocator_v,
                                   WValue pipeline_v, WValue argtable_v,
                                   WValue resources_v,
                                   WValue tg_mem_bytes_v,
                                   WValue n_tg_x_v, WValue n_tg_y_v, WValue n_tg_z_v,
                                   WValue threads_x_v, WValue threads_y_v, WValue threads_z_v) {
    if (@available(macOS 26.0, *)) {
        WMetal4Queue *q     = as_metal4_queue(queue_v);
        WMetal4Allocator *a = as_metal4_allocator(allocator_v);
        WMetalPipeline *p   = as_metal_pipeline(pipeline_v);
        WMetal4ArgTable *t  = as_metal4_argtable(argtable_v);
        if (!q || !a || !p || !t) {
            w_raise(w_string("metal4_dispatch_groups_3d: queue / allocator / pipeline / argtable required"));
        }
        if (!w_is_array(resources_v)) {
            w_raise(w_string("metal4_dispatch_groups_3d: resources must be an array of MTLBuffer / MTLTensor"));
        }
        int64_t n_tg_x     = w_to_i64(n_tg_x_v);
        int64_t n_tg_y     = w_to_i64(n_tg_y_v);
        int64_t n_tg_z     = w_to_i64(n_tg_z_v);
        int64_t threads_x  = w_to_i64(threads_x_v);
        int64_t threads_y  = w_to_i64(threads_y_v);
        int64_t threads_z  = w_to_i64(threads_z_v);

        id<MTL4CommandQueue>    q_ = (id<MTL4CommandQueue>)q->handle;
        id<MTL4CommandAllocator> a_ = (id<MTL4CommandAllocator>)a->handle;
        id<MTLComputePipelineState> p_ = (id<MTLComputePipelineState>)p->handle;
        id<MTL4ArgumentTable>   t_ = (id<MTL4ArgumentTable>)t->handle;

        id<MTLDevice> dev = [p_ device];

        /* MTL4 doesn't auto-track residency — every resource bound via the
         * argument table must live in a residency set that's attached to
         * the queue at dispatch time. We build a transient residency set
         * around just this dispatch's resources. */
        WArray *res_arr = (WArray *)w_as_ptr(resources_v);
        MTLResidencySetDescriptor *rs_desc = [[[MTLResidencySetDescriptor alloc] init] autorelease];
        rs_desc.label = @"tungsten.mtl4.dispatch";
        rs_desc.initialCapacity = (NSUInteger)res_arr->size;
        NSError *rs_err = nil;
        id<MTLResidencySet> res_set = [dev newResidencySetWithDescriptor:rs_desc error:&rs_err];
        if (!res_set) {
            const char *msg = rs_err ? [[rs_err localizedDescription] UTF8String] : "newResidencySet failed";
            char buf[256];
            snprintf(buf, sizeof(buf), "metal4_dispatch: %s", msg);
            w_raise(w_string(buf));
        }
        for (int32_t i = 0; i < res_arr->size; i++) {
            WValue rv = res_arr->slots[res_arr->start + i];
            WMetalBuffer *mb = as_metal_buffer(rv);
            WMetalTensor *mt = mb ? NULL : as_metal_tensor(rv);
            if (mb) {
                [res_set addAllocation:(id<MTLAllocation>)(id<MTLBuffer>)mb->handle];
            } else if (mt) {
                /* MTLTensor backed by buffer: residency follows the underlying buffer. */
                id<MTLTensor> tt = (id<MTLTensor>)mt->handle;
                id<MTLBuffer> backing = [tt buffer];
                if (backing) [res_set addAllocation:(id<MTLAllocation>)backing];
            } else {
                char msg[112];
                snprintf(msg, sizeof(msg), "metal4_dispatch: resources[%d] is neither MTLBuffer nor MTLTensor", i);
                w_raise(w_string(msg));
            }
        }
        [res_set commit];
        [q_ addResidencySet:res_set];

        id<MTL4CommandBuffer> cmdbuf = [dev newCommandBuffer];
        if (!cmdbuf) w_raise(w_string("metal4_dispatch: newCommandBuffer failed"));
        [cmdbuf beginCommandBufferWithAllocator:a_];
        id<MTL4ComputeCommandEncoder> enc = [cmdbuf computeCommandEncoder];
        if (!enc) {
            [cmdbuf endCommandBuffer];
            w_raise(w_string("metal4_dispatch: computeCommandEncoder failed"));
        }
        [enc setComputePipelineState:p_];
        [enc setArgumentTable:t_];
        int64_t tg_mem_bytes = w_to_i64(tg_mem_bytes_v);
        if (tg_mem_bytes > 0) {
            [enc setThreadgroupMemoryLength:(NSUInteger)tg_mem_bytes atIndex:0];
        }
        MTLSize tgs = MTLSizeMake((NSUInteger)n_tg_x, (NSUInteger)n_tg_y, (NSUInteger)n_tg_z);
        MTLSize ths = MTLSizeMake((NSUInteger)threads_x, (NSUInteger)threads_y, (NSUInteger)threads_z);
        [enc dispatchThreadgroups:tgs threadsPerThreadgroup:ths];
        [enc endEncoding];
        [cmdbuf endCommandBuffer];

        /* MTL4CommandQueue has no waitUntilCompleted; canonical pattern is
         * signal a shared event after commit and wait host-side. */
        id<MTLSharedEvent> ev = [dev newSharedEvent];
        if (!ev) {
            [a_ reset];
            w_raise(w_string("metal4_dispatch: newSharedEvent failed"));
        }
        id<MTL4CommandBuffer> arr[1] = { cmdbuf };
        [q_ commit:arr count:1];
        [q_ signalEvent:ev value:1];
        if (![ev waitUntilSignaledValue:1 timeoutMS:30000]) {
            [q_ removeResidencySet:res_set];
            [a_ reset];
            w_raise(w_string("metal4_dispatch: timeout waiting for completion"));
        }
        [q_ removeResidencySet:res_set];
        [a_ reset];
        return W_NIL;
    } else {
        w_raise(w_string("metal4_dispatch_groups_3d: requires macOS 26+"));
        return W_NIL;
    }
}

#else  /* __MAC_OS_X_VERSION_MAX_ALLOWED < 260000 — Metal 4 types undeclared.
        * Provide link-compatible stubs for the public entry points so callers
        * built against this runtime still link on the macOS 15 (Xcode 16.4) SDK.
        * Each stub matches its real signature exactly and raises at runtime. */

WValue w_metal4_compiler_new(WValue device_v) {
    w_raise(w_string("metal4_compiler_new: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_pipeline_for(WValue compiler_v, WValue library_v, WValue name_v,
                             WValue threads_x_v, WValue threads_y_v, WValue threads_z_v) {
    w_raise(w_string("metal4_pipeline_for: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal_tensor_2d(WValue buffer_v, WValue dtype_v,
                         WValue dim_rows_v, WValue dim_cols_v,
                         WValue stride_rows_v, WValue byte_offset_v) {
    w_raise(w_string("metal_tensor_2d: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal_tensor_nd(WValue buffer_v, WValue dtype_v,
                         WValue shape_v, WValue strides_v, WValue byte_offset_v) {
    w_raise(w_string("metal_tensor_nd: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_queue_new(WValue device_v) {
    w_raise(w_string("metal4_queue_new: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_allocator_new(WValue device_v) {
    w_raise(w_string("metal4_allocator_new: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_argtable_new(WValue device_v, WValue max_buffers_v) {
    w_raise(w_string("metal4_argtable_new: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_argtable_set_buffer(WValue argtable_v, WValue index_v, WValue buffer_v) {
    w_raise(w_string("metal4_argtable_set_buffer: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_argtable_set_buffer_offset(WValue argtable_v, WValue index_v,
                                           WValue buffer_v, WValue byte_offset_v) {
    w_raise(w_string("metal4_argtable_set_buffer_offset: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_argtable_set_tensor(WValue argtable_v, WValue index_v, WValue tensor_v) {
    w_raise(w_string("metal4_argtable_set_tensor: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

WValue w_metal4_dispatch_groups_3d(WValue queue_v, WValue allocator_v,
                                   WValue pipeline_v, WValue argtable_v,
                                   WValue resources_v,
                                   WValue tg_mem_bytes_v,
                                   WValue n_tg_x_v, WValue n_tg_y_v, WValue n_tg_z_v,
                                   WValue threads_x_v, WValue threads_y_v, WValue threads_z_v) {
    w_raise(w_string("metal4_dispatch_groups_3d: requires the macOS 26 SDK (Metal 4)"));
    return W_NIL;
}

#endif  /* __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000 */

/* ---- Fused elementwise GPU auto-offload ----
 *
 * The compiler's fused elementwise lowering (lowering/ops.w) generates a
 * per-site MSL kernel for arithmetic-only f32 trees and calls this before
 * the CPU parallel path. Returns 1 if the GPU executed the site (out array
 * filled), 0 to fall through to CPU — below threshold, no device, too many
 * args, compile failure, or dispatch error. The out array is only written
 * on the success path, so a 0 return is always safe.
 *
 * blk layout matches the CPU worker's arg block:
 *   blk[0]            out f32[] WValue
 *   blk[1..n_arrs]    leaf f32[] WValues
 *   blk[1+n_arrs..]   scalar f64 bit patterns
 *
 * Buffers are per-site cached MTLBuffers (grown as needed) with memcpy
 * in/out — at the >=2M-element sizes where the GPU wins, the copies are
 * bandwidth-trivial next to dispatch + compute, and copying avoids any
 * page-alignment requirement on the source arrays. Threshold:
 * TUNGSTEN_FUSED_GPU_MIN (default 2097152); TUNGSTEN_FUSED_GPU=0 disables. */

#define W_FUSED_GPU_MAX_SITES 1024
#define W_FUSED_GPU_MAX_ARRS  6
#define W_FUSED_GPU_MAX_SCLS  16

typedef struct {
    void *pipeline;                          /* id<MTLComputePipelineState> */
    int failed;                              /* MSL compile failed — never retry */
    void *bufs[W_FUSED_GPU_MAX_ARRS + 1];    /* copy-fallback buffers */
    int64_t caps[W_FUSED_GPU_MAX_ARRS + 1];  /* their byte capacities */
    /* Cached zero-copy wraps, keyed by (array WValue, base, len): the same
     * live array with unmoved storage means the pages are still mapped, so
     * reusing the wrap is sound and skips the per-dispatch VM wiring. */
    void *wraps[W_FUSED_GPU_MAX_ARRS + 1];   /* retained MTLBuffers */
    WValue wrap_wv[W_FUSED_GPU_MAX_ARRS + 1];
    void *wrap_base[W_FUSED_GPU_MAX_ARRS + 1];
    int64_t wrap_len[W_FUSED_GPU_MAX_ARRS + 1];
    /* Last-seen keys (even when no wrap was made): a repeat with identical
     * keys marks the site's buffers as stable — worth wiring above the
     * window ceiling because the wraps will be cached from then on. */
    WValue seen_wv[W_FUSED_GPU_MAX_ARRS + 1];
    void *seen_base[W_FUSED_GPU_MAX_ARRS + 1];
    void *scl_buf;
    void *n_buf;
} WFusedGpuSite;

static WFusedGpuSite g_fused_sites[W_FUSED_GPU_MAX_SITES];
static id<MTLDevice> g_fused_dev;
static id<MTLCommandQueue> g_fused_queue;
static int64_t g_fused_gpu_min = -1;
static int64_t g_fused_gpu_max = 0;

static void fused_gpu_init(void) {
    if (g_fused_gpu_min >= 0) return;
    /* Measured window (fusion.md sweep, zero-copy wraps): for the
     * semantics-safe GPU candidates (arithmetic-only f32 trees) the GPU
     * wins between ~2M and ~32M elements (1.1-1.4x); below that dispatch
     * latency dominates, above it the per-dispatch VM wiring of fresh
     * multi-GB outputs does (each fused execution allocates a new result
     * array, so its zero-copy wrap re-maps those pages every call).
     * Extending the window upward needs output-buffer reuse. f32 libm
     * trees (where the GPU is ~30x at 10M) stay CPU-side pending the
     * dtype-semantics decision: array .sin() promotes to f64 output and
     * MSL has no double. Env: TUNGSTEN_FUSED_GPU=0 disables,
     * TUNGSTEN_FUSED_GPU_MIN / _MAX move the window. */
    const char *e = getenv("TUNGSTEN_FUSED_GPU");
    if (e && *e && strtoll(e, NULL, 10) == 0) { g_fused_gpu_min = INT64_MAX; return; }
    int64_t mn = 2097152, mx = 33554432;
    e = getenv("TUNGSTEN_FUSED_GPU_MIN");
    if (e && *e) mn = strtoll(e, NULL, 10);
    e = getenv("TUNGSTEN_FUSED_GPU_MAX");
    if (e && *e) mx = strtoll(e, NULL, 10);
    g_fused_gpu_max = mx;
    g_fused_gpu_min = mn;
}

/* Try a zero-copy wrap of a f32 array's storage. macOS large allocations
 * (the only sizes where the GPU tier fires) come back page-aligned from
 * calloc, so this usually succeeds; any failure returns nil and the caller
 * uses the cached copy-buffer for that slot instead. */
static id<MTLBuffer> fused_wrap_nocopy(WArray *a, int64_t bytes) {
    void *base = (uint8_t *)a->slots + (int64_t)a->start * 4;
    NSUInteger page = (NSUInteger)getpagesize();
    if (((uintptr_t)base & (page - 1)) != 0) return nil;
    id<MTLBuffer> buf = [g_fused_dev newBufferWithBytesNoCopy:base
                                                       length:(NSUInteger)bytes
                                                      options:MTLResourceStorageModeShared
                                                  deallocator:nil];
    return buf ? [buf autorelease] : nil;
}

int64_t w_fused_gpu_run(int64_t site_id, WValue msl_v, int64_t blk_addr,
                        int64_t n_arrs, int64_t n_scls, int64_t n) {
    fused_gpu_init();
    if (n < g_fused_gpu_min) return 0;
    if (site_id < 0 || site_id >= W_FUSED_GPU_MAX_SITES) return 0;
    if (n_arrs < 1 || n_arrs > W_FUSED_GPU_MAX_ARRS) return 0;
    if (n_scls > W_FUSED_GPU_MAX_SCLS) return 0;
    WFusedGpuSite *s = &g_fused_sites[site_id];
    if (s->failed) return 0;
    @autoreleasepool {
        if (!g_fused_dev) {
            g_fused_dev = MTLCreateSystemDefaultDevice();
            if (!g_fused_dev) { g_fused_gpu_min = INT64_MAX; return 0; }
            g_fused_queue = [g_fused_dev newCommandQueue];
        }
        if (!s->pipeline) {
            NSString *src = [NSString stringWithUTF8String:metal_string_data(msl_v)];
            NSError *err = nil;
            MTLCompileOptions *opts = metal_make_compile_opts(0);
            id<MTLLibrary> lib = [g_fused_dev newLibraryWithSource:src options:opts error:&err];
            [opts release];
            if (!lib) { s->failed = 1; return 0; }
            id<MTLFunction> fn = [lib newFunctionWithName:@"fuse"];
            if (!fn) { [lib release]; s->failed = 1; return 0; }
            id<MTLComputePipelineState> ps =
                [g_fused_dev newComputePipelineStateWithFunction:fn error:&err];
            [fn release];
            [lib release];
            if (!ps) { s->failed = 1; return 0; }
            s->pipeline = (void *)ps;
            s->scl_buf = (void *)[g_fused_dev newBufferWithLength:W_FUSED_GPU_MAX_SCLS * 4
                                                          options:MTLResourceStorageModeShared];
            s->n_buf = (void *)[g_fused_dev newBufferWithLength:4
                                                        options:MTLResourceStorageModeShared];
        }
        int64_t *blk = (int64_t *)(uintptr_t)blk_addr;
        int64_t bytes = n * 4;
        /* Resolve buffers, zero-copy first. Slot 0..n_arrs-1: inputs;
         * slot n_arrs: out. Pass 1 checks the wrap cache and whether the
         * site's buffers are stable; above the window ceiling we only
         * proceed when every slot is either cached or stable (the one-time
         * wiring then amortizes across repeats). */
        id<MTLBuffer> arg_bufs[W_FUSED_GPU_MAX_ARRS + 1];
        WValue wv_k[W_FUSED_GPU_MAX_ARRS + 1];
        void *base_k[W_FUSED_GPU_MAX_ARRS + 1];
        int cached[W_FUSED_GPU_MAX_ARRS + 1];
        int out_stable;
        for (int64_t k = 0; k <= n_arrs; k++) {
            WValue wv = (WValue)blk[k == n_arrs ? 0 : 1 + k];
            WArray *a = (WArray *)w_as_ptr(wv);
            void *base = (uint8_t *)a->slots + (int64_t)a->start * 4;
            wv_k[k] = wv;
            base_k[k] = base;
            cached[k] = (s->wraps[k] && s->wrap_wv[k] == wv &&
                         s->wrap_base[k] == base && s->wrap_len[k] == bytes);
        }
        /* A stable output buffer (## reuse) means the CPU ladder streams
         * with no allocation or fault-in — measured faster than the GPU at
         * every size for arithmetic trees. The GPU's win is exactly the
         * fresh-output window, where the CPU pays first-touch per call. */
        out_stable = (s->seen_wv[n_arrs] == wv_k[n_arrs] &&
                      s->seen_base[n_arrs] == base_k[n_arrs]);
        s->seen_wv[n_arrs] = wv_k[n_arrs];
        s->seen_base[n_arrs] = base_k[n_arrs];
        if (out_stable || n > g_fused_gpu_max) return 0;
        int copied_out = 0;
        for (int64_t k = 0; k <= n_arrs; k++) {
            if (cached[k]) {
                arg_bufs[k] = (id<MTLBuffer>)s->wraps[k];
                continue;
            }
            WArray *a = (WArray *)w_as_ptr(wv_k[k]);
            id<MTLBuffer> wrap = fused_wrap_nocopy(a, bytes);
            if (wrap) {
                if (s->wraps[k]) [(id<MTLBuffer>)s->wraps[k] release];
                s->wraps[k] = (void *)[wrap retain];
                s->wrap_wv[k] = wv_k[k];
                s->wrap_base[k] = base_k[k];
                s->wrap_len[k] = bytes;
                arg_bufs[k] = wrap;
                continue;
            }
            if (s->caps[k] < bytes) {
                if (s->bufs[k]) [(id<MTLBuffer>)s->bufs[k] release];
                s->bufs[k] = (void *)[g_fused_dev newBufferWithLength:(NSUInteger)bytes
                                                              options:MTLResourceStorageModeShared];
                if (!s->bufs[k]) { s->caps[k] = 0; return 0; }
                s->caps[k] = bytes;
            }
            arg_bufs[k] = (id<MTLBuffer>)s->bufs[k];
            if (k < n_arrs) {
                float *src = (float *)a->slots + a->start;
                memcpy([arg_bufs[k] contents], src, (size_t)bytes);
            } else {
                copied_out = 1;
            }
        }
        float *scl = (float *)[(id<MTLBuffer>)s->scl_buf contents];
        for (int64_t j = 0; j < n_scls; j++) {
            double d;
            memcpy(&d, &blk[1 + n_arrs + j], 8);
            scl[j] = (float)d;
        }
        uint32_t n32 = (uint32_t)n;
        memcpy([(id<MTLBuffer>)s->n_buf contents], &n32, 4);

        id<MTLCommandBuffer> cmd = [g_fused_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        id<MTLComputePipelineState> ps = (id<MTLComputePipelineState>)s->pipeline;
        [enc setComputePipelineState:ps];
        for (int64_t k = 0; k <= n_arrs; k++) {
            [enc setBuffer:arg_bufs[k] offset:0 atIndex:(NSUInteger)k];
        }
        [enc setBuffer:(id<MTLBuffer>)s->scl_buf offset:0 atIndex:(NSUInteger)(n_arrs + 1)];
        [enc setBuffer:(id<MTLBuffer>)s->n_buf offset:0 atIndex:(NSUInteger)(n_arrs + 2)];
        NSUInteger tpg = [ps maxTotalThreadsPerThreadgroup];
        if (tpg > 256) tpg = 256;
        [enc dispatchThreads:MTLSizeMake((NSUInteger)n, 1, 1)
            threadsPerThreadgroup:MTLSizeMake(tpg, 1, 1)];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        if ([cmd status] == MTLCommandBufferStatusError) return 0;

        if (copied_out) {
            WArray *out = (WArray *)w_as_ptr((WValue)blk[0]);
            float *dst = (float *)out->slots + out->start;
            memcpy(dst, [arg_bufs[n_arrs] contents], (size_t)bytes);
        }
        return 1;
    }
}

/* wasm_alloc.c — a small-object allocator for one-shot wasm instances.
 *
 * Replaces wasi-libc's dlmalloc (malloc, free, calloc, realloc,
 * posix_memalign, aligned_alloc, malloc_usable_size and the __libc_*
 * aliases) when linked ahead of libc.a. Profiling allocation-heavy programs
 * under V8 put more than half of their time in dlmalloc and sbrk. Every
 * instance here runs one program and is discarded, so the allocator trades
 * coalescing and memory return for speed:
 *
 *   - 41 size classes (16-byte steps to 128, then four per power of two up to
 *     32 KiB). Each 64 KiB wasm page serves one class and records it in a
 *     16-byte page header, so objects carry no header and free() finds the
 *     class by masking the pointer. Blocks are 16-byte aligned, which the
 *     runtime's NaN-boxed pointers require.
 *   - Freed blocks go on a per-class LIFO list; allocation pops or bumps.
 *   - Larger requests take whole page runs (header in the first page),
 *     reused first-fit with splitting; the run at the top of the heap grows
 *     in place on realloc, which is the array-doubling case.
 *   - Memory comes from [__heap_base, memory.size) and then memory.grow in
 *     chunks. The mmap emulation in wasi_stubs.c also grows memory, so runs
 *     need not be contiguous; nothing assumes they are.
 *
 * Not thread-safe (wasm instances here are single-threaded). */
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define WA_PAGE 65536u
#define WA_HDR 16u
#define WA_CLASSES 41
#define WA_SMALL_MAX 32768u
#define WA_LARGE 0xFFFFu
#define WA_MAGIC 0x57414C43u /* "WALC" */
#define WA_GROW_PAGES 128u   /* 8 MiB per memory.grow */

extern unsigned char __heap_base;

typedef struct WaPage {
    uint32_t magic;
    uint32_t cls;     /* size class, or WA_LARGE */
    uint32_t pages;   /* run length in pages (large runs) */
    uint32_t pad;
} WaPage;

typedef struct WaFree { struct WaFree *next; } WaFree;
typedef struct WaRun { struct WaRun *next; uint32_t pages; } WaRun;

static uint32_t wa_size[WA_CLASSES];
static WaFree *wa_free[WA_CLASSES];
static uintptr_t wa_bump[WA_CLASSES], wa_bump_end[WA_CLASSES];
static uintptr_t wa_cur = 0, wa_end = 0; /* uncarved page region */
static WaRun *wa_runs = 0;                /* free large runs */
static int wa_ready = 0;

static void wa_init(void) {
    for (uint32_t c = 1; c <= 8; c++) wa_size[c] = c * 16u;
    uint32_t c = 9;
    for (uint32_t k = 7; k <= 14; k++)
        for (uint32_t sub = 0; sub < 4; sub++) wa_size[c++] = (4u + sub + 1u) << (k - 2u);
    wa_size[0] = 16u;
    uintptr_t base = ((uintptr_t)&__heap_base + WA_PAGE - 1) & ~(uintptr_t)(WA_PAGE - 1);
    uintptr_t top = (uintptr_t)__builtin_wasm_memory_size(0) * WA_PAGE;
    wa_cur = base;
    wa_end = top > base ? top : base;
    wa_ready = 1;
}

static inline uint32_t wa_class(size_t n) {
    if (n <= 128) return n == 0 ? 1u : (uint32_t)((n + 15) >> 4);
    uint32_t m = (uint32_t)(n - 1);
    uint32_t k = 31u - (uint32_t)__builtin_clz(m);
    return 9u + 4u * (k - 7u) + ((m >> (k - 2u)) & 3u);
}

/* Carve `pages` contiguous pages; returns 0 when memory cannot grow. */
static uintptr_t wa_take_pages(uint32_t pages) {
    uintptr_t need = (uintptr_t)pages * WA_PAGE;
    if (wa_end - wa_cur < need) {
        uint32_t grow = pages > WA_GROW_PAGES ? pages : WA_GROW_PAGES;
        uintptr_t old = (uintptr_t)__builtin_wasm_memory_grow(0, grow);
        if (old == (uintptr_t)-1) {
            grow = pages;
            old = (uintptr_t)__builtin_wasm_memory_grow(0, grow);
            if (old == (uintptr_t)-1) return 0;
        }
        uintptr_t start = old * WA_PAGE;
        if (start != wa_end) wa_cur = start; /* someone else grew memory: skip the gap */
        wa_end = start + (uintptr_t)grow * WA_PAGE;
    }
    uintptr_t p = wa_cur;
    wa_cur += need;
    return p;
}

static void *wa_small(uint32_t c, int *fresh) {
    WaFree *f = wa_free[c];
    if (f) {
        wa_free[c] = f->next;
        *fresh = 0;
        return f;
    }
    uint32_t sz = wa_size[c];
    if (wa_bump_end[c] - wa_bump[c] < sz) {
        uintptr_t page = wa_take_pages(1);
        if (!page) return 0;
        WaPage *h = (WaPage *)page;
        h->magic = WA_MAGIC;
        h->cls = c;
        h->pages = 1;
        h->pad = 0;
        wa_bump[c] = page + WA_HDR;
        wa_bump_end[c] = page + WA_PAGE;
    }
    void *p = (void *)wa_bump[c];
    wa_bump[c] += sz;
    *fresh = 1; /* fresh memory.grow pages are zero */
    return p;
}

static void *wa_large(size_t n, int *fresh) {
    uint32_t pages = (uint32_t)((n + WA_HDR + WA_PAGE - 1) / WA_PAGE);
    WaRun **pp = &wa_runs;
    while (*pp) {
        WaRun *r = *pp;
        if (r->pages >= pages) {
            *pp = r->next;
            if (r->pages > pages) { /* split: the tail goes back on the list */
                WaRun *tail = (WaRun *)((uintptr_t)r + (uintptr_t)pages * WA_PAGE);
                tail->pages = r->pages - pages;
                tail->next = wa_runs;
                wa_runs = tail;
            }
            WaPage *h = (WaPage *)r;
            h->magic = WA_MAGIC;
            h->cls = WA_LARGE;
            h->pages = pages;
            h->pad = 0;
            *fresh = 0;
            return (void *)((uintptr_t)h + WA_HDR);
        }
        pp = &r->next;
    }
    uintptr_t page = wa_take_pages(pages);
    if (!page) return 0;
    WaPage *h = (WaPage *)page;
    h->magic = WA_MAGIC;
    h->cls = WA_LARGE;
    h->pages = pages;
    h->pad = 0;
    *fresh = 1;
    return (void *)(page + WA_HDR);
}

static void *wa_alloc(size_t n, int *fresh) {
    if (!wa_ready) wa_init();
    if (n > 0x7FFF0000u) { errno = ENOMEM; return 0; }
    void *p = n <= WA_SMALL_MAX ? wa_small(wa_class(n), fresh) : wa_large(n, fresh);
    if (!p) errno = ENOMEM;
    return p;
}

static inline WaPage *wa_page_of(void *p) {
    return (WaPage *)((uintptr_t)p & ~(uintptr_t)(WA_PAGE - 1));
}

void *malloc(size_t n) {
    int fresh;
    return wa_alloc(n, &fresh);
}

void free(void *p) {
    if (!p) return;
    WaPage *h = wa_page_of(p);
    if (h->cls == WA_LARGE) {
        WaRun *r = (WaRun *)h;
        uint32_t pages = h->pages;
        r->pages = pages;
        r->next = wa_runs;
        wa_runs = r;
        return;
    }
    WaFree *f = (WaFree *)p;
    f->next = wa_free[h->cls];
    wa_free[h->cls] = f;
}

void *calloc(size_t count, size_t size) {
    if (size && count > SIZE_MAX / size) { errno = ENOMEM; return 0; }
    size_t n = count * size;
    int fresh;
    void *p = wa_alloc(n, &fresh);
    if (p && !fresh) memset(p, 0, n);
    return p;
}

size_t malloc_usable_size(void *p) {
    if (!p) return 0;
    WaPage *h = wa_page_of(p);
    if (h->cls == WA_LARGE)  /* measured from p: aligned blocks sit past the header */
        return (size_t)((uintptr_t)h + (uintptr_t)h->pages * WA_PAGE - (uintptr_t)p);
    return wa_size[h->cls];
}

void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    if (n == 0) { free(p); return malloc(0); }
    WaPage *h = wa_page_of(p);
    size_t have = malloc_usable_size(p);
    if (n <= have) return p;
    if (h->cls == WA_LARGE) {
        /* The topmost run grows in place: the common array-doubling case. */
        uintptr_t run_end = (uintptr_t)h + (uintptr_t)h->pages * WA_PAGE;
        uint32_t want = (uint32_t)((n + WA_HDR + WA_PAGE - 1) / WA_PAGE);
        if (run_end == wa_cur) {
            uint32_t extra = want - h->pages;
            if (wa_end - wa_cur >= (uintptr_t)extra * WA_PAGE) {
                wa_cur += (uintptr_t)extra * WA_PAGE;
                h->pages = want;
                return p;
            }
            if (wa_end == wa_cur) {
                uint32_t grow = extra > WA_GROW_PAGES ? extra : WA_GROW_PAGES;
                uintptr_t old = (uintptr_t)__builtin_wasm_memory_grow(0, grow);
                if (old != (uintptr_t)-1 && old * WA_PAGE == wa_end) {
                    wa_end += (uintptr_t)grow * WA_PAGE;
                    wa_cur += (uintptr_t)extra * WA_PAGE;
                    h->pages = want;
                    return p;
                }
                if (old != (uintptr_t)-1) { /* not contiguous after all */
                    wa_cur = old * WA_PAGE;
                    wa_end = wa_cur + (uintptr_t)grow * WA_PAGE;
                }
            }
        }
    }
    void *q = malloc(n);
    if (!q) return 0;
    memcpy(q, p, have);
    free(p);
    return q;
}

int posix_memalign(void **out, size_t align, size_t n) {
    if (align < sizeof(void *) || (align & (align - 1))) return EINVAL;
    if (align <= 16) {
        void *p = malloc(n);
        if (!p) return ENOMEM;
        *out = p;
        return 0;
    }
    if (align <= WA_PAGE / 2) {
        /* Large run with the block placed at `align` inside its first page,
         * so masking still finds the header. */
        int fresh;
        void *p = wa_large(n + align, &fresh);
        if (!p) return ENOMEM;
        uintptr_t page = (uintptr_t)wa_page_of(p);
        *out = (void *)(page + align);
        return 0;
    }
    return EINVAL;
}

void *aligned_alloc(size_t align, size_t n) {
    void *p = 0;
    return posix_memalign(&p, align, n) == 0 ? p : 0;
}

void *__libc_malloc(size_t n) { return malloc(n); }
void *__libc_calloc(size_t count, size_t size) { return calloc(count, size); }
void __libc_free(void *p) { free(p); }

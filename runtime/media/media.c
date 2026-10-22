/* runtime/media/media.c — VideoToolbox encoder, segments, conversion, parsing.
 *
 * The C half of the media bridge (see media.h): the handle registry, the
 * R'G'B' -> Y'CbCr converter, VideoToolbox compression sessions that emit
 * closed-GOP segments, the segment file format, an H.264/HEVC SPS + VUI
 * parser, and an mmap WAV reader. media_avf.m holds the AVFoundation half.
 *
 * Conversion. Frames arrive as 8-bit RGBA, BGRA, ARGB or RGB24 code values
 * (a Canvas's premultiplied RGBA is taken as composited over black). They are
 * converted here, not inside VideoToolbox, so the matrix, range and chroma
 * siting are ours and checkable: BT.709 (Kr 0.2126, Kb 0.0722), limited
 * range, chroma siting "left" by default (H.264/HEVC chroma_sample_loc_type
 * 0). Codes are computed in fixed point; the few samples whose value lies
 * near a rounding tie are recomputed with core/ycbcr.w's double arithmetic
 * (as the compiled engine evaluates it), so a frame converted here is
 * bit-for-bit YuvFrame.from_rgba(...) on the compiled engine:
 * spec/core/media_spec.w checks every 8-bit RGB triple.
 *
 * Segments. An encoder forces an IDR on the first frame of each segment and
 * never reorders frames (no B-frames), so a segment is a closed GOP whose
 * samples can be appended to any file encoded with the same settings. Frames
 * are emitted asynchronously; a segment's handle is returned at once and the
 * first call that needs its samples waits for them. Parameter sets live in
 * the format description (avcC / hvcC), which VideoToolbox derives from the
 * settings alone: two sessions with equal settings produce byte-identical
 * ones, so segments from separate sessions concatenate under one sample
 * description (the mux checks every segment against the first). */

#include "runtime.h"
#include "wvalue.h"
#include "media.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__) && !defined(TUNGSTEN_MEDIA_STUB)

/* Every exported entry point must be listed in media.h: the stub half is
 * generated from those lists. */
#pragma clang diagnostic error "-Wmissing-prototypes"
/* Bit-exact with core/ycbcr.w: no implicit fused multiply-adds; the exact
 * fallback calls fma() exactly where compiled Tungsten fuses. */
#pragma clang fp contract(off)

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

extern double w_num_to_f64(WValue v);

/* Error codes stored in WMediaSegment.err besides OSStatus values. */
#define W_MEDIA_ERR_DROPPED  (-900001)
#define W_MEDIA_ERR_FORMAT   (-900002)
#define W_MEDIA_ERR_TIMING   (-900003)

/* ======================================================================
   Helpers
   ====================================================================== */

void w_media_raise(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    w_raise(w_string(buf));
    abort();
}

static int m_is_text(WValue v) { return w_is_stringy(v) || w_is_rope(v); }

int w_media_str(WValue v, char *buf, size_t cap) {
    if (!m_is_text(v)) { buf[0] = 0; return 0; }
    char sso[6];
    const char *s;
    size_t n;
    w_str_data(v, sso, &s, &n);
    if (n >= cap) n = cap - 1;
    memcpy(buf, s, n);
    buf[n] = 0;
    return 1;
}

double w_media_num(WValue v, double dflt, const char *what) {
    if (v == W_NIL) return dflt;
    if (w_is_double(v)) return w_as_double(v);
    if (w_is_int(v)) return (double)w_as_int(v);
    if (w_is_bigint(v) || (v & W_TAG_MASK) == W_TAG_DECIMAL || w_is_rational(v) || w_is_domain_obj(v))
        return w_num_to_f64(v);
    w_media_raise("media: %s must be a number", what);
}

static int64_t m_int(WValue v, int64_t dflt, const char *what) {
    if (v == W_NIL) return dflt;
    if (w_is_int(v)) return w_as_int(v);
    return (int64_t)w_media_num(v, (double)dflt, what);
}

static int m_truthy(WValue v) { return v > 1; }

static uint64_t m_now_ns(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return mach_absolute_time() * tb.numer / tb.denom;
}

static WValue m_pair(const char *k, WValue v) {
    WValue p = w_array_new_empty();
    p = w_array_push(p, w_string(k));
    p = w_array_push(p, v);
    return p;
}

static void m_fourcc_str(uint32_t f, char out[5]) {
    out[0] = (char)((f >> 24) & 0xff);
    out[1] = (char)((f >> 16) & 0xff);
    out[2] = (char)((f >> 8) & 0xff);
    out[3] = (char)(f & 0xff);
    out[4] = 0;
}

/* ======================================================================
   Handle registry: slot | generation << 16, shared with media_avf.m
   ====================================================================== */

#define M_SLOTS 65536

typedef struct {
    void    *p;
    uint32_t gen;
    int32_t  kind;
} MSlot;

static MSlot g_slots[M_SLOTS];
static pthread_mutex_t g_reg = PTHREAD_MUTEX_INITIALIZER;
static int32_t g_cursor = 1;
static int64_t g_live[4];

int64_t w_media_handle_new(void *p, int kind) {
    pthread_mutex_lock(&g_reg);
    for (int tries = 0; tries < M_SLOTS; tries++) {
        int32_t s = g_cursor;
        g_cursor = g_cursor + 1 >= M_SLOTS ? 1 : g_cursor + 1;
        if (g_slots[s].p == NULL) {
            g_slots[s].p = p;
            g_slots[s].kind = kind;
            g_slots[s].gen = (g_slots[s].gen + 1) & 0x7fffffff;
            if (g_slots[s].gen == 0) g_slots[s].gen = 1;
            int64_t h = (int64_t)s | ((int64_t)g_slots[s].gen << 16);
            if (kind > 0 && kind < 4) g_live[kind]++;
            pthread_mutex_unlock(&g_reg);
            return h;
        }
    }
    pthread_mutex_unlock(&g_reg);
    w_media_raise("media: too many live handles (%d); release segments you no longer need", M_SLOTS - 1);
}

static void *m_handle_peek(WValue h, int kind) {
    if (!w_is_int(h)) return NULL;
    int64_t v = w_as_int(h);
    int64_t s = v & 0xffff;
    uint32_t gen = (uint32_t)(v >> 16);
    void *p = NULL;
    pthread_mutex_lock(&g_reg);
    if (s > 0 && s < M_SLOTS && g_slots[s].p && g_slots[s].gen == gen && g_slots[s].kind == kind) p = g_slots[s].p;
    pthread_mutex_unlock(&g_reg);
    return p;
}

void *w_media_handle_get(WValue h, int kind, const char *what) {
    void *p = m_handle_peek(h, kind);
    if (!p) {
        const char *k = kind == W_MEDIA_KIND_ENCODER ? "encoder" : kind == W_MEDIA_KIND_SEGMENT ? "segment" : "mux";
        w_media_raise("media: %s: the %s is closed or the handle is unknown", what, k);
    }
    return p;
}

void w_media_handle_drop(WValue h, int kind) {
    if (!w_is_int(h)) return;
    int64_t v = w_as_int(h);
    int64_t s = v & 0xffff;
    uint32_t gen = (uint32_t)(v >> 16);
    pthread_mutex_lock(&g_reg);
    if (s > 0 && s < M_SLOTS && g_slots[s].p && g_slots[s].gen == gen && g_slots[s].kind == kind) {
        g_slots[s].p = NULL;
        if (kind > 0 && kind < 4) g_live[kind]--;
    }
    pthread_mutex_unlock(&g_reg);
}

/* ======================================================================
   R'G'B' -> Y'CbCr (BT.709, limited range), bit-exact with core/ycbcr.w
   ====================================================================== */

enum { M_SITE_LEFT = 0, M_SITE_CENTER = 1, M_SITE_TOPLEFT = 2 };

typedef struct {
    const uint8_t *src;
    size_t         sstride;
    int            bpp, ro, go, bo;
    int            w, h;
    uint8_t       *yp;
    size_t         ystride;
    uint8_t       *cp;        /* interleaved Cb Cr */
    size_t         cstride;
    int            bits;      /* 8 or 10 (10 stored as 16-bit words, MSB-aligned) */
    int            hsub, vsub;
    int            siting;
    int            bands;
} MConv;

static double g_lut[256];
static double g_kr, g_kg, g_kb;
static pthread_once_t g_lut_once = PTHREAD_ONCE_INIT;

static void m_lut_init(void) {
    g_kr = 0.2126;
    g_kb = 0.0722;
    g_kg = 1.0 - g_kr - g_kb;
    for (int k = 0; k < 256; k++) {
        g_lut[k] = (double)k / 255.0;
    }
}

/* Decimation taps around the luma sample under each chroma sample, as
 * YuvFrame.down_taps: co-sited axes use [1 2 1]/4, midway axes [1 1]/2. */
typedef struct { int n; int off[3]; double wt[3]; } MTaps;

static void m_taps(int sub, int cosited, MTaps *t) {
    if (sub == 1) { t->n = 1; t->off[0] = 0; t->wt[0] = 1.0; return; }
    if (cosited) {
        t->n = 3;
        t->off[0] = -1; t->off[1] = 0; t->off[2] = 1;
        t->wt[0] = 0.25; t->wt[1] = 0.5; t->wt[2] = 0.25;
    } else {
        t->n = 2;
        t->off[0] = 0; t->off[1] = 1;
        t->wt[0] = 0.5; t->wt[1] = 0.5;
    }
}

/* ---- exact reference arithmetic (core/ycbcr.w, operation for operation) ----
 *
 * Compiled Tungsten contracts `a * b + c` in typed f64 code into a fused
 * multiply-add (llvm.fmuladd), as C does with contraction on: in YuvFrame's
 * kernels `kr r + kg g + kb b` is fmuladd(kb, b, kr r + kg g) and the
 * quantizer's `e * scale + offset` is fmuladd(e, scale, offset). The
 * tree-walking interpreter does not fuse, so on a near-tie input the two
 * engines' YuvFrame can differ by one code. This mirrors the compiled
 * kernels (the spec checks every RGB triple against them). */

static inline int m_luma_exact(const MConv *c, const uint8_t *p) {
    double e = g_kr * g_lut[p[c->ro]] + g_kg * g_lut[p[c->go]];
    e = fma(g_kb, g_lut[p[c->bo]], e);
    if (c->bits == 8) {
        int64_t v = (int64_t)(fma(e, 219.0, 16.0) + 0.5);
        return (int)(v < 1 ? 1 : v > 254 ? 254 : v);
    }
    int64_t v = (int64_t)(fma(e, 876.0, 64.0) + 0.5);
    return (int)(v < 4 ? 4 : v > 1019 ? 1019 : v);
}

/* Cb, Cr of chroma sample (i, j): the taps summed in YuvFrame's order. */
static inline void m_chroma_exact(const MConv *c, const MTaps *ht, const MTaps *vt, int i, int j, int *cbo, int *cro) {
    double sr = 0.0, sg = 0.0, sb = 0.0;
    for (int b = 0; b < vt->n; b++) {
        int yy = j * c->vsub + vt->off[b];
        yy = yy < 0 ? 0 : yy > c->h - 1 ? c->h - 1 : yy;
        const uint8_t *row = c->src + (size_t)yy * c->sstride;
        for (int a = 0; a < ht->n; a++) {
            int xx = i * c->hsub + ht->off[a];
            xx = xx < 0 ? 0 : xx > c->w - 1 ? c->w - 1 : xx;
            double wt = ht->wt[a] * vt->wt[b];
            const uint8_t *p = row + (size_t)xx * (size_t)c->bpp;
            sr += wt * g_lut[p[c->ro]];
            sg += wt * g_lut[p[c->go]];
            sb += wt * g_lut[p[c->bo]];
        }
    }
    double yv = fma(g_kb, sb, g_kr * sr + g_kg * sg);
    double cbd = 2.0 * (1.0 - g_kb), crd = 2.0 * (1.0 - g_kr);
    double cs = c->bits == 8 ? 224.0 : 896.0, co = c->bits == 8 ? 128.0 : 512.0;
    int lo = c->bits == 8 ? 1 : 4, hi = c->bits == 8 ? 254 : 1019;
    int64_t cb = (int64_t)(fma((sb - yv) / cbd, cs, co) + 0.5);
    int64_t cr = (int64_t)(fma((sr - yv) / crd, cs, co) + 0.5);
    *cbo = (int)(cb < lo ? lo : cb > hi ? hi : cb);
    *cro = (int)(cr < lo ? lo : cr > hi ? hi : cr);
}

/* ---- fixed point with an exact fallback near rounding ties ----
 *
 * code = floor(Y* + 1/2) where Y* = Ys (kr r' + kg g' + kb b') + Yo. In
 * 2^-22 fixed point, v = cR r + cG g + cB b + O (32-bit, so four lanes a
 * vector), each coefficient rounded, so |v - (Y* + 1/2) 2^22| <= (r + g + b
 * + 1) / 2 + tiny <= 384. The double reference is within ~1e-13 of Y*. Where
 * v's fraction is at least YGUARD (2^10) from a multiple of 2^22 both round
 * the same way; otherwise the sample is recomputed with the reference
 * arithmetic. Chroma: the tap sums are integers S (weights scaled to integers
 * summing to D), Cb* = Cs ((1 - kb) Sb - kr Sr - kg Sg) / (cbd D 255) + Co,
 * computed modulo 2^32 (the result is positive and below 2^32), coefficient
 * error <= (Sr + Sg + Sb + 1) / 2 <= 6200 units, CGUARD 2^13. Roughly one
 * luma sample in 2000 and one chroma sample in 250 take the exact path. */

#define M_FIX 22
#define M_FIX_MASK ((1u << M_FIX) - 1)
#define M_YGUARD (1u << 10)
#define M_CGUARD (1u << 13)

typedef struct {
    uint32_t yr, yg, yb, yo;                     /* luma, per code value */
    uint32_t cbb, cbr, cbg, crr, crg, crb, co;   /* chroma, per unit of tap sum */
    int D;
} MFix;

static uint32_t m_fixc(double v) { return (uint32_t)llround(v * (double)(1u << M_FIX)); }

static void m_fix_init(const MConv *c, int D, MFix *f) {
    double m = c->bits == 8 ? 1.0 : 4.0;
    double ys = 219.0 * m, yo = 16.0 * m, cs = 224.0 * m, co = 128.0 * m;
    f->yr = m_fixc(ys * g_kr / 255.0);
    f->yg = m_fixc(ys * g_kg / 255.0);
    f->yb = m_fixc(ys * g_kb / 255.0);
    f->yo = m_fixc(yo + 0.5);
    double cbd = 2.0 * (1.0 - g_kb), crd = 2.0 * (1.0 - g_kr);
    double u = 255.0 * (double)D;
    f->cbb = m_fixc(cs * (1.0 - g_kb) / (cbd * u));
    f->cbr = m_fixc(cs * g_kr / (cbd * u));
    f->cbg = m_fixc(cs * g_kg / (cbd * u));
    f->crr = m_fixc(cs * (1.0 - g_kr) / (crd * u));
    f->crg = m_fixc(cs * g_kg / (crd * u));
    f->crb = m_fixc(cs * g_kb / (crd * u));
    f->co = m_fixc(co + 0.5);
    f->D = D;
}

/* 1 when v's fraction lies within guard of a multiple of 2^M_FIX. */
#define M_TIE(v, guard) ((uint8_t)((((v) & M_FIX_MASK) - (guard)) > (M_FIX_MASK - 2 * (guard))))

/* The fixed-point luma loop for one layout; the constant byte offsets let
 * the compiler vectorize it. tie[x] flags the pixels to redo exactly. */
#define M_LUMA_LOOP(NAME, BPP, RO, GO, BO)                                                            \
    static void NAME(const uint8_t *s, int w, const MFix *f, uint8_t *o8, uint16_t *o16, uint8_t *tie) { \
        uint32_t yr = f->yr, yg = f->yg, yb = f->yb, yo = f->yo;                                      \
        if (o8) {                                                                                     \
            for (int x = 0; x < w; x++) {                                                             \
                const uint8_t *p = s + (size_t)x * BPP;                                               \
                uint32_t v = yr * p[RO] + yg * p[GO] + yb * p[BO] + yo;                               \
                o8[x] = (uint8_t)(v >> M_FIX);                                                        \
                tie[x] = M_TIE(v, M_YGUARD);                                                          \
            }                                                                                         \
        } else {                                                                                      \
            for (int x = 0; x < w; x++) {                                                             \
                const uint8_t *p = s + (size_t)x * BPP;                                               \
                uint32_t v = yr * p[RO] + yg * p[GO] + yb * p[BO] + yo;                               \
                o16[x] = (uint16_t)((v >> M_FIX) << 6);                                               \
                tie[x] = M_TIE(v, M_YGUARD);                                                          \
            }                                                                                         \
        }                                                                                             \
    }
M_LUMA_LOOP(m_luma_rgba, 4, 0, 1, 2)
M_LUMA_LOOP(m_luma_bgra, 4, 2, 1, 0)
M_LUMA_LOOP(m_luma_argb, 4, 1, 2, 3)
M_LUMA_LOOP(m_luma_rgb24, 3, 0, 1, 2)
M_LUMA_LOOP(m_luma_bgr24, 3, 2, 1, 0)
#undef M_LUMA_LOOP

/* Index of the next nonzero flag at or after x (n when none), 8 at a time. */
static inline int m_next_flag(const uint8_t *t, int x, int n) {
    while (x < n && ((uintptr_t)(t + x) & 7)) { if (t[x]) return x; x++; }
    while (x + 8 <= n) {
        uint64_t q;
        memcpy(&q, t + x, 8);
        if (q) break;
        x += 8;
    }
    while (x < n && !t[x]) x++;
    return x;
}

/* One luma row: fixed point, then the rare near-tie pixels exactly. */
static void m_luma_row(const MConv *c, const MFix *f, int y, uint8_t *tie) {
    const uint8_t *s = c->src + (size_t)y * c->sstride;
    int w = c->w;
    uint8_t *o8 = c->bits == 8 ? c->yp + (size_t)y * c->ystride : NULL;
    uint16_t *o16 = c->bits == 8 ? NULL : (uint16_t *)(void *)(c->yp + (size_t)y * c->ystride);
    if (c->bpp == 4 && c->ro == 0) m_luma_rgba(s, w, f, o8, o16, tie);
    else if (c->bpp == 4 && c->ro == 2) m_luma_bgra(s, w, f, o8, o16, tie);
    else if (c->bpp == 4) m_luma_argb(s, w, f, o8, o16, tie);
    else if (c->ro == 0) m_luma_rgb24(s, w, f, o8, o16, tie);
    else m_luma_bgr24(s, w, f, o8, o16, tie);
    for (int x = m_next_flag(tie, 0, w); x < w; x = m_next_flag(tie, x + 1, w)) {
        int code = m_luma_exact(c, s + (size_t)x * (size_t)c->bpp);
        if (o8) o8[x] = (uint8_t)code;
        else o16[x] = (uint16_t)(code << 6);
    }
}

static inline void m_put_c(const MConv *c, uint8_t *o8, int i, int cb, int cr) {
    if (c->bits == 8) {
        o8[2 * i] = (uint8_t)cb;
        o8[2 * i + 1] = (uint8_t)cr;
    } else {
        uint16_t *o16 = (uint16_t *)(void *)o8;
        o16[2 * i] = (uint16_t)(cb << 6);
        o16[2 * i + 1] = (uint16_t)(cr << 6);
    }
}

/* Integer tap weights (scaled so the smallest is 1) and their sum. */
static int m_int_taps(const MTaps *t, int *iw) {
    double mn = t->wt[0];
    for (int a = 1; a < t->n; a++) if (t->wt[a] < mn) mn = t->wt[a];
    int sum = 0;
    for (int a = 0; a < t->n; a++) { iw[a] = (int)(t->wt[a] / mn + 0.5); sum += iw[a]; }
    return sum;
}

/* A band of chroma rows and the luma rows under them. */
static void m_conv_band(void *ctx, size_t band) {
    const MConv *c = ctx;
    int ch = (c->h + c->vsub - 1) / c->vsub;
    int cw = (c->w + c->hsub - 1) / c->hsub;
    int j0 = (int)((int64_t)ch * (int64_t)band / c->bands);
    int j1 = (int)((int64_t)ch * (int64_t)(band + 1) / c->bands);
    if (j0 >= j1) return;
    MTaps ht, vt;
    m_taps(c->hsub, c->siting != M_SITE_CENTER, &ht);
    m_taps(c->vsub, c->siting == M_SITE_TOPLEFT, &vt);
    int hw[3], vw[3];
    int D = m_int_taps(&ht, hw) * m_int_taps(&vt, vw);
    MFix f;
    m_fix_init(c, D, &f);
    int bpp = c->bpp, ro = c->ro, go = c->go, bo = c->bo, w = c->w;
    int left420 = vt.n == 2 && ht.n == 3, left422 = vt.n == 1 && ht.n == 3;
    uint32_t *Sr = malloc(sizeof(uint32_t) * (size_t)cw * 3), *Sg = Sr + cw, *Sb = Sg + cw;
    uint8_t *tie = malloc((size_t)w + 16);
    for (int j = j0; j < j1; j++) {
        for (int k = 0; k < c->vsub; k++) {
            int y = j * c->vsub + k;
            if (y < c->h) m_luma_row(c, &f, y, tie);
        }
        /* integer tap sums */
        if (left420 || left422) {
            const uint8_t *r0 = c->src + (size_t)(j * c->vsub) * c->sstride;
            int y1 = j * c->vsub + 1;
            const uint8_t *r1 = left420 ? c->src + (size_t)(y1 > c->h - 1 ? c->h - 1 : y1) * c->sstride : r0;
            /* first and last columns clamp; the rest run straight */
            for (int i = 0; i < cw; i++) {
                int x = 2 * i, xl = x > 0 ? x - 1 : 0, xr = x + 1 < w ? x + 1 : w - 1;
                const uint8_t *a0 = r0 + (size_t)xl * bpp, *b0 = r0 + (size_t)x * bpp, *c0 = r0 + (size_t)xr * bpp;
                const uint8_t *a1 = r1 + (size_t)xl * bpp, *b1 = r1 + (size_t)x * bpp, *c1 = r1 + (size_t)xr * bpp;
                uint32_t sr = (uint32_t)a0[ro] + 2u * b0[ro] + c0[ro];
                uint32_t sg = (uint32_t)a0[go] + 2u * b0[go] + c0[go];
                uint32_t sb = (uint32_t)a0[bo] + 2u * b0[bo] + c0[bo];
                if (left420) {
                    sr += (uint32_t)a1[ro] + 2u * b1[ro] + c1[ro];
                    sg += (uint32_t)a1[go] + 2u * b1[go] + c1[go];
                    sb += (uint32_t)a1[bo] + 2u * b1[bo] + c1[bo];
                }
                Sr[i] = sr;
                Sg[i] = sg;
                Sb[i] = sb;
            }
        } else {
            for (int i = 0; i < cw; i++) {
                uint32_t sr = 0, sg = 0, sb = 0;
                for (int b = 0; b < vt.n; b++) {
                    int yy = j * c->vsub + vt.off[b];
                    yy = yy < 0 ? 0 : yy > c->h - 1 ? c->h - 1 : yy;
                    const uint8_t *row = c->src + (size_t)yy * c->sstride;
                    for (int a = 0; a < ht.n; a++) {
                        int xx = i * c->hsub + ht.off[a];
                        xx = xx < 0 ? 0 : xx > w - 1 ? w - 1 : xx;
                        const uint8_t *p = row + (size_t)xx * bpp;
                        uint32_t wt = (uint32_t)(hw[a] * vw[b]);
                        sr += wt * p[ro];
                        sg += wt * p[go];
                        sb += wt * p[bo];
                    }
                }
                Sr[i] = sr;
                Sg[i] = sg;
                Sb[i] = sb;
            }
        }
        uint8_t *o8 = c->cp + (size_t)j * c->cstride;
        uint32_t co = f.co, cbb = f.cbb, cbr = f.cbr, cbg = f.cbg, crr = f.crr, crg = f.crg, crb = f.crb;
        if (c->bits == 8) {
            for (int i = 0; i < cw; i++) {
                uint32_t vb = co + cbb * Sb[i] - cbr * Sr[i] - cbg * Sg[i];
                uint32_t vr = co + crr * Sr[i] - crg * Sg[i] - crb * Sb[i];
                o8[2 * i] = (uint8_t)(vb >> M_FIX);
                o8[2 * i + 1] = (uint8_t)(vr >> M_FIX);
                tie[i] = M_TIE(vb, M_CGUARD) | M_TIE(vr, M_CGUARD);
            }
        } else {
            uint16_t *o16 = (uint16_t *)(void *)o8;
            for (int i = 0; i < cw; i++) {
                uint32_t vb = co + cbb * Sb[i] - cbr * Sr[i] - cbg * Sg[i];
                uint32_t vr = co + crr * Sr[i] - crg * Sg[i] - crb * Sb[i];
                o16[2 * i] = (uint16_t)((vb >> M_FIX) << 6);
                o16[2 * i + 1] = (uint16_t)((vr >> M_FIX) << 6);
                tie[i] = M_TIE(vb, M_CGUARD) | M_TIE(vr, M_CGUARD);
            }
        }
        for (int i = m_next_flag(tie, 0, cw); i < cw; i = m_next_flag(tie, i + 1, cw)) {
            int cb, cr;
            m_chroma_exact(c, &ht, &vt, i, j, &cb, &cr);
            m_put_c(c, o8, i, cb, cr);
        }
    }
    free(tie);
    free(Sr);
}

static void m_convert(MConv *c) {
    pthread_once(&g_lut_once, m_lut_init);
    int ch = (c->h + c->vsub - 1) / c->vsub;
    int bands = ch < 16 ? 1 : 16;
    c->bands = bands;
    if (bands == 1) m_conv_band(c, 0);
    else dispatch_apply_f((size_t)bands, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), c, m_conv_band);
}

/* Input layouts: byte offsets of R, G, B and bytes per pixel. */
static int m_input_layout(const char *name, int *bpp, int *ro, int *go, int *bo) {
    if (!name[0] || !strcasecmp(name, "rgba")) { *bpp = 4; *ro = 0; *go = 1; *bo = 2; return 1; }
    if (!strcasecmp(name, "bgra")) { *bpp = 4; *ro = 2; *go = 1; *bo = 0; return 1; }
    if (!strcasecmp(name, "argb")) { *bpp = 4; *ro = 1; *go = 2; *bo = 3; return 1; }
    if (!strcasecmp(name, "rgb24") || !strcasecmp(name, "rgb")) { *bpp = 3; *ro = 0; *go = 1; *bo = 2; return 1; }
    if (!strcasecmp(name, "bgr24") || !strcasecmp(name, "bgr")) { *bpp = 3; *ro = 2; *go = 1; *bo = 0; return 1; }
    return 0;
}

static int m_siting(const char *name) {
    if (!name[0] || !strcasecmp(name, "left")) return M_SITE_LEFT;
    if (!strcasecmp(name, "center") || !strcasecmp(name, "centre")) return M_SITE_CENTER;
    if (!strcasecmp(name, "topleft")) return M_SITE_TOPLEFT;
    return -1;
}

/* A frame source: an Integer address, a ByteArray / u8[] or an Mmap, plus a
 * byte offset. *avail is the readable byte count, or -1 when unknown. */
static const uint8_t *m_source(WValue v, int64_t off, int64_t *avail, const char *what) {
    if (off < 0) w_media_raise("media: %s: negative offset", what);
    if (w_is_int(v)) {
        int64_t a = w_as_int(v);
        if (a == 0) w_media_raise("media: %s: null frame address", what);
        *avail = -1;
        return (const uint8_t *)(uintptr_t)(a + off);
    }
    if (w_is_array(v)) {
        WArray *a = w_as_array(v);
        if (a->ebits != 8) w_media_raise("media: %s: pixels must be a ByteArray or u8[] (got an array of another element type)", what);
        if (off > a->size) w_media_raise("media: %s: offset %lld is past the end (%d bytes)", what, (long long)off, a->size);
        *avail = a->size - off;
        return (const uint8_t *)a->slots + a->start + off;
    }
    if (w_is_mmap(v)) {
        WMmap *m = (WMmap *)w_as_ptr(v);
        if (m->closed) w_media_raise("media: %s: the Mmap is closed", what);
        if (off > m->size) w_media_raise("media: %s: offset %lld is past the end of the mapping", what, (long long)off);
        *avail = m->size - off;
        return m->data + off;
    }
    w_media_raise("media: %s: pixels must be an address (Canvas#data_pointer), a ByteArray, a u8[] or an Mmap", what);
}

/* w_media_convert(src, w, h, stride, input, output, siting) -> ByteArray.
 * output: "nv12" (8-bit 4:2:0), "p010" (10-bit 4:2:0), "nv16" (8-bit 4:2:2),
 * "p210" (10-bit 4:2:2): the Y plane, then interleaved CbCr, no padding,
 * 10-bit codes MSB-aligned in little-endian 16-bit words. */
WValue w_media_convert(WValue srcv, WValue wv, WValue hv, WValue stridev, WValue inv, WValue outv, WValue sitev) {
    char in[16], out[16], site[16];
    w_media_str(inv, in, sizeof in);
    w_media_str(outv, out, sizeof out);
    w_media_str(sitev, site, sizeof site);
    MConv c;
    memset(&c, 0, sizeof c);
    if (!m_input_layout(in, &c.bpp, &c.ro, &c.go, &c.bo)) w_media_raise("media.convert: unknown input layout '%s' (rgba, bgra, argb, rgb24, bgr24)", in);
    c.w = (int)m_int(wv, 0, "width");
    c.h = (int)m_int(hv, 0, "height");
    if (c.w <= 0 || c.h <= 0) w_media_raise("media.convert: bad size %dx%d", c.w, c.h);
    c.sstride = (size_t)m_int(stridev, (int64_t)c.w * c.bpp, "stride");
    int64_t avail;
    c.src = m_source(srcv, 0, &avail, "convert");
    if (avail >= 0 && (int64_t)(c.sstride * (size_t)(c.h - 1) + (size_t)c.w * (size_t)c.bpp) > avail)
        w_media_raise("media.convert: %lld bytes is too few for %dx%d at stride %zu", (long long)avail, c.w, c.h, c.sstride);
    c.siting = m_siting(site);
    if (c.siting < 0) w_media_raise("media.convert: unknown siting '%s' (left, center, topleft)", site);
    c.hsub = 2;
    if (!strcasecmp(out, "nv12")) { c.bits = 8; c.vsub = 2; }
    else if (!strcasecmp(out, "p010")) { c.bits = 10; c.vsub = 2; }
    else if (!strcasecmp(out, "nv16")) { c.bits = 8; c.vsub = 1; }
    else if (!strcasecmp(out, "p210")) { c.bits = 10; c.vsub = 1; }
    else w_media_raise("media.convert: unknown output '%s' (nv12, p010, nv16, p210)", out);
    int bps = c.bits == 8 ? 1 : 2;
    int cw = (c.w + 1) / 2, ch = (c.h + c.vsub - 1) / c.vsub;
    size_t ysz = (size_t)c.w * (size_t)c.h * bps, csz = (size_t)cw * 2 * (size_t)ch * bps;
    uint8_t *buf = malloc(ysz + csz);
    if (!buf) w_media_raise("media.convert: out of memory");
    c.yp = buf;
    c.ystride = (size_t)c.w * bps;
    c.cp = buf + ysz;
    c.cstride = (size_t)cw * 2 * bps;
    m_convert(&c);
    WValue r = w_bytes_from_data(buf, (int64_t)(ysz + csz));
    free(buf);
    return r;
}

/* ======================================================================
   Codecs
   ====================================================================== */

typedef struct {
    const char       *name;
    CMVideoCodecType  type;
    OSType            pix;
    int               bits, vsub;
    const CFStringRef *profile;
    int               quality_ok;   /* constant-quality / bitrate settings apply */
} MCodec;

static const MCodec g_codecs[] = {
    {"h264",           kCMVideoCodecType_H264,             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,  8,  2, &kVTProfileLevel_H264_High_AutoLevel,  1},
    {"hevc",           kCMVideoCodecType_HEVC,             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,  8,  2, &kVTProfileLevel_HEVC_Main_AutoLevel,  1},
    {"hevc10",         kCMVideoCodecType_HEVC,             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, 10, 2, &kVTProfileLevel_HEVC_Main10_AutoLevel, 1},
    {"prores422",      kCMVideoCodecType_AppleProRes422,   kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, 10, 1, NULL, 0},
    {"prores422hq",    kCMVideoCodecType_AppleProRes422HQ, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, 10, 1, NULL, 0},
    {"prores422lt",    kCMVideoCodecType_AppleProRes422LT, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, 10, 1, NULL, 0},
    {"prores422proxy", kCMVideoCodecType_AppleProRes422Proxy, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, 10, 1, NULL, 0},
};
#define M_NCODECS ((int)(sizeof g_codecs / sizeof g_codecs[0]))

static const MCodec *m_codec(const char *name) {
    if (!name[0]) return &g_codecs[0];
    for (int i = 0; i < M_NCODECS; i++)
        if (!strcasecmp(name, g_codecs[i].name)) return &g_codecs[i];
    if (!strcasecmp(name, "avc") || !strcasecmp(name, "h264_high")) return &g_codecs[0];
    if (!strcasecmp(name, "h265") || !strcasecmp(name, "hevc_main")) return &g_codecs[1];
    if (!strcasecmp(name, "hevc_main10")) return &g_codecs[2];
    if (!strcasecmp(name, "prores")) return &g_codecs[3];
    return NULL;
}

/* ======================================================================
   Segments
   ====================================================================== */

typedef struct {
    pthread_mutex_t mu;
    pthread_cond_t  cv;
} MLock;

static pthread_mutex_t g_stat_lock = PTHREAD_MUTEX_INITIALIZER;
static int64_t g_seg_bytes;

static WMediaSegment *m_seg_new(void) {
    WMediaSegment *s = calloc(1, sizeof *s);
    MLock *lk = calloc(1, sizeof *lk);
    if (!s || !lk) w_media_raise("media: out of memory");
    pthread_mutex_init(&lk->mu, NULL);
    pthread_cond_init(&lk->cv, NULL);
    s->lock = lk;
    return s;
}

static void m_seg_reserve(WMediaSegment *s, size_t more) {
    if (s->len + more > s->dcap) {
        size_t cap = s->dcap ? s->dcap : 1 << 20;
        while (cap < s->len + more) cap *= 2;
        uint8_t *d = realloc(s->data, cap);
        if (!d) { s->err = W_MEDIA_ERR_DROPPED; return; }
        pthread_mutex_lock(&g_stat_lock);
        g_seg_bytes += (int64_t)(cap - s->dcap);
        pthread_mutex_unlock(&g_stat_lock);
        s->data = d;
        s->dcap = cap;
    }
    if (s->n == s->cap) {
        int32_t cap = s->cap ? s->cap * 2 : 64;
        WMediaSample *ns = realloc(s->s, sizeof *ns * (size_t)cap);
        if (!ns) { s->err = W_MEDIA_ERR_DROPPED; return; }
        s->s = ns;
        s->cap = cap;
    }
}

static void m_seg_free(WMediaSegment *s) {
    if (!s) return;
    if (s->format) CFRelease((CMFormatDescriptionRef)s->format);
    pthread_mutex_lock(&g_stat_lock);
    g_seg_bytes -= (int64_t)s->dcap;
    pthread_mutex_unlock(&g_stat_lock);
    free(s->data);
    free(s->s);
    MLock *lk = s->lock;
    if (lk) {
        pthread_mutex_destroy(&lk->mu);
        pthread_cond_destroy(&lk->cv);
        free(lk);
    }
    free(s);
}

/* The DTS delay this segment needs: max over samples (decode-order sorted
 * PTS - PTS). 0 without reordering. */
static void m_seg_reorder(WMediaSegment *s) {
    int32_t *sorted = malloc(sizeof(int32_t) * (size_t)(s->n ? s->n : 1));
    for (int i = 0; i < s->n; i++) sorted[i] = s->s[i].pts;
    /* insertion sort: segments are short and nearly sorted */
    for (int i = 1; i < s->n; i++) {
        int32_t v = sorted[i];
        int j = i - 1;
        while (j >= 0 && sorted[j] > v) { sorted[j + 1] = sorted[j]; j--; }
        sorted[j + 1] = v;
    }
    int32_t d = 0;
    for (int i = 0; i < s->n; i++) {
        int32_t k = sorted[i] - s->s[i].pts;
        if (k > d) d = k;
    }
    s->reorder = d;
    free(sorted);
}

/* ======================================================================
   Encoder
   ====================================================================== */

typedef struct MEncoder {
    VTCompressionSessionRef vt;
    const MCodec  *codec;
    int32_t        w, h, num, den;
    int            bpp, ro, go, bo;
    int            siting;
    int64_t        next;           /* next encoder-wide frame index */
    WMediaSegment *cur;
    int64_t        frames, segments;
    double         quality;
    int64_t        bitrate;
    int            gop, reorder, speed;
    uint64_t       conv_ns, submit_ns, wait_ns;
    CFDictionaryRef kf_props;
    CFDictionaryRef attach;
    char           input[16];
} MEncoder;

static int64_t m_frame_of(CMTime t, int32_t num, int32_t den) {
    /* frames = value * num / (timescale * den), rounded to nearest */
    __int128 a = (__int128)t.value * num;
    __int128 b = (__int128)t.timescale * den;
    if (b == 0) return 0;
    __int128 q = (a * 2 + b) / (b * 2);
    if (a < 0 && ((a * 2 + b) % (b * 2)) != 0) q -= 1;
    return (int64_t)q;
}

static void m_output(void *outref, void *frameref, OSStatus st, VTEncodeInfoFlags flags, CMSampleBufferRef sb) {
    MEncoder *e = outref;
    WMediaSegment *s = frameref;
    MLock *lk = s->lock;
    pthread_mutex_lock(&lk->mu);
    if (st != noErr) {
        if (!s->err) s->err = (int32_t)st;
    } else if (!sb || (flags & kVTEncodeInfo_FrameDropped)) {
        if (!s->err) s->err = W_MEDIA_ERR_DROPPED;
    } else {
        CMFormatDescriptionRef fd = CMSampleBufferGetFormatDescription(sb);
        if (!s->format) {
            CFRetain(fd);
            s->format = (void *)fd;
        } else if (!CMFormatDescriptionEqual((CMFormatDescriptionRef)s->format, fd)) {
            if (!s->err) s->err = W_MEDIA_ERR_FORMAT;
        }
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
        size_t len = bb ? CMBlockBufferGetDataLength(bb) : 0;
        m_seg_reserve(s, len);
        if (!s->err && len) {
            CMBlockBufferCopyDataBytes(bb, 0, len, s->data + s->len);
            CMTime p = CMSampleBufferGetPresentationTimeStamp(sb);
            CMTime d = CMSampleBufferGetDecodeTimeStamp(sb);
            int64_t pf = m_frame_of(p, e->num, e->den) - s->first_global;
            int64_t df = CMTIME_IS_VALID(d) ? m_frame_of(d, e->num, e->den) - s->first_global : pf;
            int sync = 1;
            CFArrayRef at = CMSampleBufferGetSampleAttachmentsArray(sb, false);
            if (at && CFArrayGetCount(at) > 0) {
                CFDictionaryRef ad = CFArrayGetValueAtIndex(at, 0);
                CFBooleanRef ns = CFDictionaryGetValue(ad, kCMSampleAttachmentKey_NotSync);
                if (ns && CFBooleanGetValue(ns)) sync = 0;
            }
            if (pf < 0 || pf >= s->submitted) {
                if (!s->err) s->err = W_MEDIA_ERR_TIMING;
            }
            WMediaSample *x = &s->s[s->n++];
            x->offset = s->len;
            x->size = (uint32_t)len;
            x->pts = (int32_t)pf;
            x->dts = (int32_t)df;
            x->sync = (uint8_t)sync;
            s->len += len;
        }
    }
    s->emitted++;
    if (s->finished && s->emitted >= s->submitted) s->enc = NULL;
    pthread_cond_broadcast(&lk->cv);
    pthread_mutex_unlock(&lk->mu);
}

static void m_set_num(VTCompressionSessionRef vt, CFStringRef key, double v, int as_int, const char *what) {
    CFNumberRef n;
    if (as_int) {
        int64_t i = (int64_t)v;
        n = CFNumberCreate(NULL, kCFNumberSInt64Type, &i);
    } else {
        n = CFNumberCreate(NULL, kCFNumberDoubleType, &v);
    }
    OSStatus st = VTSessionSetProperty(vt, key, n);
    CFRelease(n);
    if (st != noErr) w_media_raise("VideoEncoder: VideoToolbox refused %s (OSStatus %d)", what, (int)st);
}

static void m_set(VTCompressionSessionRef vt, CFStringRef key, CFTypeRef v, const char *what, int required) {
    OSStatus st = VTSessionSetProperty(vt, key, v);
    if (st != noErr && required) w_media_raise("VideoEncoder: VideoToolbox refused %s (OSStatus %d)", what, (int)st);
}

static CFDictionaryRef m_dict1(CFStringRef k, CFTypeRef v) {
    const void *ks[1] = {k};
    const void *vs[1] = {v};
    return CFDictionaryCreate(NULL, ks, vs, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

static CFNumberRef m_cfint(int64_t v) { return CFNumberCreate(NULL, kCFNumberSInt64Type, &v); }

static OSStatus m_session_create(const MCodec *codec, int32_t w, int32_t h, void *ref, VTCompressionSessionRef *out) {
    CFMutableDictionaryRef spec = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(spec, kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder, kCFBooleanTrue);
    CFMutableDictionaryRef src = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef pix = m_cfint((int64_t)codec->pix), wn = m_cfint(w), hn = m_cfint(h);
    CFDictionaryRef ios = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(src, kCVPixelBufferPixelFormatTypeKey, pix);
    CFDictionarySetValue(src, kCVPixelBufferWidthKey, wn);
    CFDictionarySetValue(src, kCVPixelBufferHeightKey, hn);
    CFDictionarySetValue(src, kCVPixelBufferIOSurfacePropertiesKey, ios);
    OSStatus st = VTCompressionSessionCreate(NULL, w, h, codec->type, spec, src, NULL, m_output, ref, out);
    CFRelease(pix); CFRelease(wn); CFRelease(hn); CFRelease(ios); CFRelease(src); CFRelease(spec);
    return st;
}

/* w_media_encoder_new(w, h, codec, num, den, quality, bitrate, gop, input,
 * siting, reorder, speed) -> handle. */
WValue w_media_encoder_new(WValue wv, WValue hv, WValue codecv, WValue numv, WValue denv, WValue qv,
                           WValue brv, WValue gopv, WValue inv, WValue sitev, WValue reorderv, WValue speedv) {
    char cname[32], in[16], site[16];
    w_media_str(codecv, cname, sizeof cname);
    w_media_str(inv, in, sizeof in);
    w_media_str(sitev, site, sizeof site);
    const MCodec *codec = m_codec(cname);
    if (!codec) w_media_raise("VideoEncoder: unknown codec '%s' (h264, hevc, hevc10, prores422, prores422hq, prores422lt, prores422proxy)", cname);
    MEncoder *e = calloc(1, sizeof *e);
    if (!e) w_media_raise("VideoEncoder: out of memory");
    e->codec = codec;
    e->w = (int32_t)m_int(wv, 0, "width");
    e->h = (int32_t)m_int(hv, 0, "height");
    e->num = (int32_t)m_int(numv, 24, "rate numerator");
    e->den = (int32_t)m_int(denv, 1, "rate denominator");
    e->quality = w_media_num(qv, -1.0, "quality");
    e->bitrate = m_int(brv, 0, "bitrate");
    e->gop = (int)m_int(gopv, 48, "gop");
    e->reorder = m_truthy(reorderv);
    e->speed = m_truthy(speedv);
    snprintf(e->input, sizeof e->input, "%s", in[0] ? in : "rgba");
    if (e->w <= 0 || e->h <= 0 || (e->w & 1) || (e->h & 1)) { free(e); w_media_raise("VideoEncoder: width and height must be positive and even (got %dx%d)", (int)e->w, (int)e->h); }
    if (e->num <= 0 || e->den <= 0) { free(e); w_media_raise("VideoEncoder: rate must be a positive [num, den]"); }
    if (!m_input_layout(e->input, &e->bpp, &e->ro, &e->go, &e->bo)) { free(e); w_media_raise("VideoEncoder: unknown input layout '%s' (rgba, bgra, argb, rgb24, bgr24)", in); }
    e->siting = m_siting(site);
    if (e->siting < 0) { free(e); w_media_raise("VideoEncoder: unknown chroma siting '%s' (left, center, topleft)", site); }
    if (e->quality > 1.0 || (e->quality < 0 && e->quality != -1.0)) { free(e); w_media_raise("VideoEncoder: quality must be in 0..1"); }
    if (e->gop < 1) { free(e); w_media_raise("VideoEncoder: gop must be at least 1"); }

    OSStatus st = m_session_create(codec, e->w, e->h, e, &e->vt);
    if (st != noErr || !e->vt) {
        int w = e->w, h = e->h;
        free(e);
        w_media_raise("VideoEncoder: VideoToolbox cannot create a %s session at %dx%d (OSStatus %d)", codec->name, w, h, (int)st);
    }
    VTCompressionSessionRef vt = e->vt;
    m_set(vt, kVTCompressionPropertyKey_RealTime, kCFBooleanFalse, "RealTime", 0);
    if (codec->profile) m_set(vt, kVTCompressionPropertyKey_ProfileLevel, *codec->profile, "ProfileLevel", 1);
    if (codec->quality_ok) {
        m_set(vt, kVTCompressionPropertyKey_AllowFrameReordering, e->reorder ? kCFBooleanTrue : kCFBooleanFalse, "AllowFrameReordering", 1);
        /* Keyframes are forced at segment starts; the interval is a backstop
         * for segments longer than gop frames. With reordering VideoToolbox
         * plans keyframes a mini-GOP ahead and would put an extra one a few
         * frames before a forced IDR at gop, so the backstop doubles. */
        m_set_num(vt, kVTCompressionPropertyKey_MaxKeyFrameInterval, e->reorder ? 2 * e->gop : e->gop, 1, "MaxKeyFrameInterval");
        if (codec->type == kCMVideoCodecType_HEVC) m_set(vt, kVTCompressionPropertyKey_AllowOpenGOP, kCFBooleanFalse, "AllowOpenGOP", 0);
        if (codec->type == kCMVideoCodecType_H264) m_set(vt, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC, "H264EntropyMode", 0);
        if (e->bitrate > 0) m_set_num(vt, kVTCompressionPropertyKey_AverageBitRate, (double)e->bitrate, 1, "AverageBitRate");
        else m_set_num(vt, kVTCompressionPropertyKey_Quality, e->quality >= 0 ? e->quality : 0.75, 0, "Quality");
        if (e->speed) m_set(vt, kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue, "PrioritizeEncodingSpeedOverQuality", 0);
    }
    m_set_num(vt, kVTCompressionPropertyKey_ExpectedFrameRate, (double)e->num / (double)e->den, 0, "ExpectedFrameRate");
    m_set(vt, kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2, "ColorPrimaries", 1);
    m_set(vt, kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2, "TransferFunction", 1);
    m_set(vt, kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2, "YCbCrMatrix", 1);
    VTCompressionSessionPrepareToEncodeFrames(vt);

    e->kf_props = m_dict1(kVTEncodeFrameOptionKey_ForceKeyFrame, kCFBooleanTrue);
    CFStringRef loc = e->siting == M_SITE_CENTER ? kCVImageBufferChromaLocation_Center
                    : e->siting == M_SITE_TOPLEFT ? kCVImageBufferChromaLocation_TopLeft
                    : kCVImageBufferChromaLocation_Left;
    const void *ks[5] = {kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey, kCVImageBufferYCbCrMatrixKey,
                         kCVImageBufferChromaLocationTopFieldKey, kCVImageBufferChromaLocationBottomFieldKey};
    const void *vs[5] = {kCVImageBufferColorPrimaries_ITU_R_709_2, kCVImageBufferTransferFunction_ITU_R_709_2,
                         kCVImageBufferYCbCrMatrix_ITU_R_709_2, loc, loc};
    e->attach = CFDictionaryCreate(NULL, ks, vs, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    return w_int(w_media_handle_new(e, W_MEDIA_KIND_ENCODER));
}

/* w_media_encoder_encode(enc, pixels, offset, stride) -> frames in the open segment. */
WValue w_media_encoder_encode(WValue ev, WValue srcv, WValue offv, WValue stridev) {
    MEncoder *e = w_media_handle_get(ev, W_MEDIA_KIND_ENCODER, "VideoEncoder#encode");
    int64_t avail;
    const uint8_t *src = m_source(srcv, m_int(offv, 0, "offset"), &avail, "VideoEncoder#encode");
    size_t stride = (size_t)m_int(stridev, (int64_t)e->w * e->bpp, "stride");
    if (stride < (size_t)e->w * (size_t)e->bpp) w_media_raise("VideoEncoder#encode: stride %zu is less than width x %d bytes", stride, e->bpp);
    if (avail >= 0 && (int64_t)(stride * (size_t)(e->h - 1) + (size_t)e->w * (size_t)e->bpp) > avail)
        w_media_raise("VideoEncoder#encode: %lld bytes is too few for a %dx%d %s frame at stride %zu", (long long)avail, (int)e->w, (int)e->h, e->input, stride);
    if (!e->cur) {
        WMediaSegment *s = m_seg_new();
        s->fourcc = (uint32_t)e->codec->type;
        s->width = e->w;
        s->height = e->h;
        s->rate_num = e->num;
        s->rate_den = e->den;
        s->first_global = e->next;
        s->enc = e;
        s->flags = e->reorder && e->codec->quality_ok ? W_MEDIA_SEG_REORDER : 0;
        e->cur = s;
    }
    WMediaSegment *s = e->cur;
    CVPixelBufferPoolRef pool = VTCompressionSessionGetPixelBufferPool(e->vt);
    if (!pool) w_media_raise("VideoEncoder#encode: VideoToolbox has no pixel buffer pool (session invalid)");
    CVPixelBufferRef pb = NULL;
    CVReturn cr = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pb);
    if (cr != kCVReturnSuccess || !pb) w_media_raise("VideoEncoder#encode: no pixel buffer (CVReturn %d)", (int)cr);
    uint64_t t0 = m_now_ns();
    CVPixelBufferLockBaseAddress(pb, 0);
    MConv c;
    memset(&c, 0, sizeof c);
    c.src = src;
    c.sstride = stride;
    c.bpp = e->bpp; c.ro = e->ro; c.go = e->go; c.bo = e->bo;
    c.w = e->w; c.h = e->h;
    c.yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    c.ystride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    c.cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    c.cstride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    c.bits = e->codec->bits;
    c.hsub = 2;
    c.vsub = e->codec->vsub;
    c.siting = e->siting;
    m_convert(&c);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    CVBufferSetAttachments(pb, e->attach, kCVAttachmentMode_ShouldPropagate);
    uint64_t t1 = m_now_ns();
    MLock *lk = s->lock;
    pthread_mutex_lock(&lk->mu);
    int32_t local = s->submitted++;
    pthread_mutex_unlock(&lk->mu);
    CMTime pts = CMTimeMake(e->next * e->den, e->num);
    CMTime dur = CMTimeMake(e->den, e->num);
    OSStatus st = VTCompressionSessionEncodeFrame(e->vt, pb, pts, dur, local == 0 ? e->kf_props : NULL, s, NULL);
    CVPixelBufferRelease(pb);
    if (st != noErr) {
        pthread_mutex_lock(&lk->mu);
        s->submitted--;
        pthread_mutex_unlock(&lk->mu);
        w_media_raise("VideoEncoder#encode: VideoToolbox failed to encode frame %lld (OSStatus %d)", (long long)e->next, (int)st);
    }
    e->next++;
    e->frames++;
    e->conv_ns += t1 - t0;
    e->submit_ns += m_now_ns() - t1;
    return w_int(local + 1);
}

/* Wait until every submitted frame of s has been emitted. */
static void m_seg_wait(WMediaSegment *s) {
    MLock *lk = s->lock;
    pthread_mutex_lock(&lk->mu);
    if (s->emitted < s->submitted && s->enc) {
        MEncoder *e = s->enc;
        int64_t last = s->first_global + s->submitted - 1;
        pthread_mutex_unlock(&lk->mu);
        uint64_t t0 = m_now_ns();
        VTCompressionSessionCompleteFrames(e->vt, CMTimeMake(last * e->den, e->num));
        e->wait_ns += m_now_ns() - t0;
        pthread_mutex_lock(&lk->mu);
    }
    while (s->emitted < s->submitted) pthread_cond_wait(&lk->cv, &lk->mu);
    s->enc = NULL;
    pthread_mutex_unlock(&lk->mu);
}

static const char *m_err_text(int32_t err, char *buf, size_t cap) {
    if (err == W_MEDIA_ERR_DROPPED) return "VideoToolbox dropped a frame";
    if (err == W_MEDIA_ERR_FORMAT) return "the format description changed inside the segment";
    if (err == W_MEDIA_ERR_TIMING) return "a sample came back with a timestamp outside the segment";
    snprintf(buf, cap, "VideoToolbox error (OSStatus %d)", (int)err);
    return buf;
}

WMediaSegment *w_media_segment_ready(WValue h, const char *what) {
    WMediaSegment *s = w_media_handle_get(h, W_MEDIA_KIND_SEGMENT, what);
    if (s->enc) m_seg_wait(s);
    if (s->err) {
        char buf[96];
        w_media_raise("media: %s: the segment failed to encode: %s", what, m_err_text(s->err, buf, sizeof buf));
    }
    if (s->n != s->submitted && s->submitted > 0)
        w_media_raise("media: %s: the segment has %d samples for %d frames", what, (int)s->n, (int)s->submitted);
    if (s->reorder < 0) m_seg_reorder(s);
    return s;
}

/* w_media_encoder_segment(enc) -> segment handle: closes the open segment.
 * Its frames may still be in flight; the first use of the handle waits. */
WValue w_media_encoder_segment(WValue ev) {
    MEncoder *e = w_media_handle_get(ev, W_MEDIA_KIND_ENCODER, "VideoEncoder#segment");
    WMediaSegment *s = e->cur;
    if (!s) w_media_raise("VideoEncoder#segment: no frames were encoded since the last segment");
    MLock *lk = s->lock;
    pthread_mutex_lock(&lk->mu);
    s->finished = 1;
    s->reorder = -1;
    if (s->emitted >= s->submitted) s->enc = NULL;
    pthread_mutex_unlock(&lk->mu);
    e->cur = NULL;
    e->segments++;
    return w_int(w_media_handle_new(s, W_MEDIA_KIND_SEGMENT));
}

/* w_media_encoder_info(enc, key) */
WValue w_media_encoder_info(WValue ev, WValue keyv) {
    MEncoder *e = w_media_handle_get(ev, W_MEDIA_KIND_ENCODER, "VideoEncoder#info");
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "frames")) return w_int(e->frames);
    if (!strcmp(k, "segments")) return w_int(e->segments);
    if (!strcmp(k, "codec")) return w_string(e->codec->name);
    if (!strcmp(k, "pending")) return w_int(e->cur ? e->cur->submitted : 0);
    if (!strcmp(k, "convert_s")) return w_float((double)e->conv_ns / 1e9);
    if (!strcmp(k, "submit_s")) return w_float((double)e->submit_ns / 1e9);
    if (!strcmp(k, "wait_s")) return w_float((double)e->wait_ns / 1e9);
    if (!strcmp(k, "pixel_format")) {
        char f[5];
        m_fourcc_str((uint32_t)e->codec->pix, f);
        return w_string(f);
    }
    if (!strcmp(k, "bits")) return w_int(e->codec->bits);
    w_media_raise("VideoEncoder#info: unknown key '%s'", k);
}

/* w_media_encoder_close(enc): completes every frame in flight. A segment
 * still open (frames since the last #segment) is discarded. */
WValue w_media_encoder_close(WValue ev) {
    MEncoder *e = m_handle_peek(ev, W_MEDIA_KIND_ENCODER);
    if (!e) return W_NIL;
    VTCompressionSessionCompleteFrames(e->vt, kCMTimeInvalid);
    int64_t dropped = 0;
    if (e->cur) {
        dropped = e->cur->submitted;
        m_seg_free(e->cur);
        e->cur = NULL;
    }
    VTCompressionSessionInvalidate(e->vt);
    CFRelease(e->vt);
    CFRelease(e->kf_props);
    CFRelease(e->attach);
    w_media_handle_drop(ev, W_MEDIA_KIND_ENCODER);
    free(e);
    return w_int(dropped);
}

/* ---- segment queries ---- */

static CFDataRef m_param_atom(WMediaSegment *s) {
    if (!s->format) return NULL;
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s->format);
    if (!ext) return NULL;
    CFDictionaryRef atoms = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
    if (!atoms || CFGetTypeID(atoms) != CFDictionaryGetTypeID()) return NULL;
    CFDataRef d = CFDictionaryGetValue(atoms, CFSTR("avcC"));
    if (!d) d = CFDictionaryGetValue(atoms, CFSTR("hvcC"));
    return d;
}

WValue w_media_segment_info(WValue sv, WValue keyv) {
    WMediaSegment *s = w_media_segment_ready(sv, "VideoSegment#info");
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "frames")) return w_int(s->n);
    if (!strcmp(k, "bytes")) return w_int((int64_t)s->len);
    if (!strcmp(k, "width")) return w_int(s->width);
    if (!strcmp(k, "height")) return w_int(s->height);
    if (!strcmp(k, "reorder")) return w_int(s->reorder);
    if (!strcmp(k, "flags")) return w_int(s->flags);
    if (!strcmp(k, "codec")) {
        char f[5];
        m_fourcc_str(s->fourcc, f);
        return w_string(f);
    }
    if (!strcmp(k, "rate")) {
        WValue a = w_array_new_empty();
        a = w_array_push(a, w_int(s->rate_num));
        a = w_array_push(a, w_int(s->rate_den));
        return a;
    }
    if (!strcmp(k, "keyframes") || !strcmp(k, "sync") || !strcmp(k, "sizes") || !strcmp(k, "pts") || !strcmp(k, "dts")) {
        if (!strcmp(k, "keyframes")) {
            int64_t n = 0;
            for (int i = 0; i < s->n; i++) n += s->s[i].sync;
            return w_int(n);
        }
        WValue a = w_array_new_empty();
        for (int i = 0; i < s->n; i++) {
            int64_t v = !strcmp(k, "sync") ? s->s[i].sync : !strcmp(k, "sizes") ? (int64_t)s->s[i].size
                      : !strcmp(k, "pts") ? s->s[i].pts : s->s[i].dts;
            a = w_array_push(a, w_int(v));
        }
        return a;
    }
    if (!strcmp(k, "param_sets")) {
        CFDataRef d = m_param_atom(s);
        if (!d) return W_NIL;
        return w_bytes_from_data(CFDataGetBytePtr(d), CFDataGetLength(d));
    }
    if (!strcmp(k, "format")) {
        /* The whole format description extension dictionary, serialized. */
        if (!s->format) return W_NIL;
        CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s->format);
        CFDataRef d = ext ? CFPropertyListCreateData(NULL, ext, kCFPropertyListBinaryFormat_v1_0, 0, NULL) : NULL;
        if (!d) return W_NIL;
        WValue r = w_bytes_from_data(CFDataGetBytePtr(d), CFDataGetLength(d));
        CFRelease(d);
        return r;
    }
    w_media_raise("VideoSegment#info: unknown key '%s'", k);
}

WValue w_media_segment_sample(WValue sv, WValue iv) {
    WMediaSegment *s = w_media_segment_ready(sv, "VideoSegment#sample");
    int64_t i = m_int(iv, 0, "index");
    if (i < 0 || i >= s->n) w_media_raise("VideoSegment#sample: index %lld out of range (0...%d)", (long long)i, (int)s->n);
    return w_bytes_from_data(s->data + s->s[i].offset, s->s[i].size);
}

/* ---- segment files ----
 *
 * Little-endian, 64-byte header:
 *   0  "TWMS"            4  u32 version (1)     8  u32 header size (64)
 *   12 u32 codec fourcc  16 i32 width          20 i32 height
 *   24 i32 rate num      28 i32 rate den       32 u32 sample count
 *   36 u32 format bytes  40 u64 data bytes     48 i32 reorder
 *   52 u32 flags (0)     56 u64 reserved
 * then the format description extensions as a binary property list, then
 * one 24-byte record per sample in decode order (u64 offset, u32 size,
 * i32 pts, i32 dts, u8 sync, 3 bytes 0), then the sample data (AVCC/HVCC
 * length-prefixed NAL units, or one ProRes frame per sample). */

static void m_put32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static void m_put64(uint8_t *p, uint64_t v) { m_put32(p, (uint32_t)v); m_put32(p + 4, (uint32_t)(v >> 32)); }
static uint32_t m_get32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t m_get64(const uint8_t *p) { return (uint64_t)m_get32(p) | ((uint64_t)m_get32(p + 4) << 32); }

WValue w_media_segment_save(WValue sv, WValue pathv) {
    WMediaSegment *s = w_media_segment_ready(sv, "VideoSegment#save");
    char path[4096], tmp[4200];
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("VideoSegment#save: path must be a string");
    if (!s->format) w_media_raise("VideoSegment#save: the segment has no frames");
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s->format);
    CFDataRef fmt = ext ? CFPropertyListCreateData(NULL, ext, kCFPropertyListBinaryFormat_v1_0, 0, NULL) : NULL;
    size_t flen = fmt ? (size_t)CFDataGetLength(fmt) : 0;
    uint8_t hdr[64];
    memset(hdr, 0, sizeof hdr);
    memcpy(hdr, "TWMS", 4);
    m_put32(hdr + 4, 1);
    m_put32(hdr + 8, 64);
    m_put32(hdr + 12, s->fourcc);
    m_put32(hdr + 16, (uint32_t)s->width);
    m_put32(hdr + 20, (uint32_t)s->height);
    m_put32(hdr + 24, (uint32_t)s->rate_num);
    m_put32(hdr + 28, (uint32_t)s->rate_den);
    m_put32(hdr + 32, (uint32_t)s->n);
    m_put32(hdr + 36, (uint32_t)flen);
    m_put64(hdr + 40, s->len);
    m_put32(hdr + 48, (uint32_t)s->reorder);
    m_put32(hdr + 52, s->flags);
    uint8_t *rec = calloc((size_t)(s->n ? s->n : 1), 24);
    for (int i = 0; i < s->n; i++) {
        uint8_t *r = rec + 24 * (size_t)i;
        m_put64(r, s->s[i].offset);
        m_put32(r + 8, s->s[i].size);
        m_put32(r + 12, (uint32_t)s->s[i].pts);
        m_put32(r + 16, (uint32_t)s->s[i].dts);
        r[20] = s->s[i].sync;
    }
    snprintf(tmp, sizeof tmp, "%s.tmp%d", path, (int)getpid());
    FILE *f = fopen(tmp, "wb");
    if (!f) { if (fmt) CFRelease(fmt); free(rec); w_media_raise("VideoSegment#save: cannot write %s: %s", tmp, strerror(errno)); }
    int ok = fwrite(hdr, 1, 64, f) == 64;
    if (ok && flen) ok = fwrite(CFDataGetBytePtr(fmt), 1, flen, f) == flen;
    if (ok && s->n) ok = fwrite(rec, 24, (size_t)s->n, f) == (size_t)s->n;
    if (ok && s->len) ok = fwrite(s->data, 1, s->len, f) == s->len;
    ok = (fclose(f) == 0) && ok;
    if (fmt) CFRelease(fmt);
    free(rec);
    if (!ok || rename(tmp, path) != 0) {
        unlink(tmp);
        w_media_raise("VideoSegment#save: writing %s failed: %s", path, strerror(errno));
    }
    return w_int((int64_t)(64 + flen + 24 * (size_t)s->n + s->len));
}

WValue w_media_segment_load(WValue pathv) {
    char path[4096];
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("VideoSegment.load: path must be a string");
    FILE *f = fopen(path, "rb");
    if (!f) w_media_raise("VideoSegment.load: cannot open %s: %s", path, strerror(errno));
    uint8_t hdr[64];
    if (fread(hdr, 1, 64, f) != 64 || memcmp(hdr, "TWMS", 4) != 0 || m_get32(hdr + 4) != 1) {
        fclose(f);
        w_media_raise("VideoSegment.load: %s is not a Tungsten media segment (version 1)", path);
    }
    uint32_t hsz = m_get32(hdr + 8), n = m_get32(hdr + 32), flen = m_get32(hdr + 36);
    uint64_t dlen = m_get64(hdr + 40);
    if (hsz < 64 || n > (1u << 24) || flen > (1u << 24) || dlen > ((uint64_t)1 << 40)) {
        fclose(f);
        w_media_raise("VideoSegment.load: %s has a corrupt header", path);
    }
    fseeko(f, (off_t)hsz, SEEK_SET);
    WMediaSegment *s = m_seg_new();
    s->fourcc = m_get32(hdr + 12);
    s->width = (int32_t)m_get32(hdr + 16);
    s->height = (int32_t)m_get32(hdr + 20);
    s->rate_num = (int32_t)m_get32(hdr + 24);
    s->rate_den = (int32_t)m_get32(hdr + 28);
    s->reorder = (int32_t)m_get32(hdr + 48);
    s->flags = m_get32(hdr + 52);
    uint8_t *fmt = malloc(flen ? flen : 1);
    uint8_t *rec = malloc(24 * (size_t)(n ? n : 1));
    s->data = malloc(dlen ? dlen : 1);
    s->dcap = dlen;
    s->s = malloc(sizeof(WMediaSample) * (n ? n : 1));
    s->cap = (int32_t)(n ? n : 1);
    int ok = fmt && rec && s->data && s->s;
    if (ok && flen) ok = fread(fmt, 1, flen, f) == flen;
    if (ok && n) ok = fread(rec, 24, n, f) == n;
    if (ok && dlen) ok = fread(s->data, 1, dlen, f) == dlen;
    fclose(f);
    if (ok) {
        pthread_mutex_lock(&g_stat_lock);
        g_seg_bytes += (int64_t)dlen;
        pthread_mutex_unlock(&g_stat_lock);
        for (uint32_t i = 0; i < n && ok; i++) {
            const uint8_t *r = rec + 24 * (size_t)i;
            WMediaSample *x = &s->s[i];
            x->offset = m_get64(r);
            x->size = m_get32(r + 8);
            x->pts = (int32_t)m_get32(r + 12);
            x->dts = (int32_t)m_get32(r + 16);
            x->sync = r[20];
            if (x->offset + x->size > dlen) ok = 0;
        }
        s->n = (int32_t)n;
        s->len = dlen;
        s->submitted = s->emitted = (int32_t)n;
        s->finished = 1;
    }
    if (ok) {
        CFDictionaryRef ext = NULL;
        if (flen) {
            CFDataRef d = CFDataCreate(NULL, fmt, flen);
            ext = CFPropertyListCreateWithData(NULL, d, kCFPropertyListImmutable, NULL, NULL);
            CFRelease(d);
            if (ext && CFGetTypeID(ext) != CFDictionaryGetTypeID()) { CFRelease(ext); ext = NULL; ok = 0; }
        }
        if (ok) {
            CMVideoFormatDescriptionRef fd = NULL;
            OSStatus st = CMVideoFormatDescriptionCreate(NULL, s->fourcc, s->width, s->height, ext, &fd);
            if (st != noErr || !fd) ok = 0;
            else s->format = (void *)fd;
        }
        if (ext) CFRelease(ext);
    }
    free(fmt);
    free(rec);
    if (!ok) {
        m_seg_free(s);
        w_media_raise("VideoSegment.load: %s is truncated or corrupt", path);
    }
    return w_int(w_media_handle_new(s, W_MEDIA_KIND_SEGMENT));
}

WValue w_media_segment_release(WValue sv) {
    WMediaSegment *s = m_handle_peek(sv, W_MEDIA_KIND_SEGMENT);
    if (!s) return W_FALSE;
    if (s->enc) m_seg_wait(s);
    w_media_handle_drop(sv, W_MEDIA_KIND_SEGMENT);
    m_seg_free(s);
    return W_TRUE;
}

/* ---- capabilities and stats ---- */

static void m_probe_output(void *a, void *b, OSStatus st, VTEncodeInfoFlags f, CMSampleBufferRef sb) {
    (void)a; (void)b; (void)st; (void)f; (void)sb;
}

WValue w_media_codecs(void) {
    static int probed = 0;
    static int ok[M_NCODECS];
    static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&mu);
    if (!probed) {
        for (int i = 0; i < M_NCODECS; i++) {
            VTCompressionSessionRef s = NULL;
            CFMutableDictionaryRef spec = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictionarySetValue(spec, kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder, kCFBooleanTrue);
            OSStatus st = VTCompressionSessionCreate(NULL, 1920, 1080, g_codecs[i].type, spec, NULL, NULL, m_probe_output, NULL, &s);
            CFRelease(spec);
            ok[i] = st == noErr && s;
            if (s) {
                if (ok[i] && g_codecs[i].profile)
                    ok[i] = VTSessionSetProperty(s, kVTCompressionPropertyKey_ProfileLevel, *g_codecs[i].profile) == noErr;
                VTCompressionSessionInvalidate(s);
                CFRelease(s);
            }
        }
        probed = 1;
    }
    pthread_mutex_unlock(&mu);
    WValue a = w_array_new_empty();
    for (int i = 0; i < M_NCODECS; i++)
        if (ok[i]) a = w_array_push(a, w_string(g_codecs[i].name));
    return a;
}

WValue w_media_stats(void) {
    WValue a = w_array_new_empty();
    pthread_mutex_lock(&g_reg);
    int64_t enc = g_live[W_MEDIA_KIND_ENCODER], seg = g_live[W_MEDIA_KIND_SEGMENT], mux = g_live[W_MEDIA_KIND_MUX];
    pthread_mutex_unlock(&g_reg);
    pthread_mutex_lock(&g_stat_lock);
    int64_t bytes = g_seg_bytes;
    pthread_mutex_unlock(&g_stat_lock);
    a = w_array_push(a, w_int(enc));
    a = w_array_push(a, w_int(seg));
    a = w_array_push(a, w_int(bytes));
    a = w_array_push(a, w_int(mux));
    return a;
}

/* ======================================================================
   SPS / VUI parsing (H.264 7.3.2.1, HEVC 7.3.2.2, VUI Annex E)
   ====================================================================== */

typedef struct {
    uint8_t *p;
    size_t   n;     /* bytes */
    size_t   pos;   /* bits */
    int      err;
} MBits;

static uint32_t mb_u(MBits *b, int k) {
    uint32_t v = 0;
    while (k-- > 0) {
        if (b->pos >= b->n * 8) { b->err = 1; return 0; }
        v = (v << 1) | ((b->p[b->pos >> 3] >> (7 - (b->pos & 7))) & 1u);
        b->pos++;
    }
    return v;
}

static uint32_t mb_ue(MBits *b) {
    int lz = 0;
    while (mb_u(b, 1) == 0) {
        if (b->err || ++lz > 31) { b->err = 1; return 0; }
    }
    if (lz == 0) return 0;
    return ((1u << lz) - 1) + mb_u(b, lz);
}

static int32_t mb_se(MBits *b) {
    uint32_t k = mb_ue(b);
    return (k & 1) ? (int32_t)((k + 1) / 2) : -(int32_t)(k / 2);
}

/* NAL payload (after the header) -> RBSP, emulation-prevention bytes removed. */
static uint8_t *m_rbsp(const uint8_t *nal, size_t len, size_t skip, size_t *out_len) {
    uint8_t *o = malloc(len + 1);
    size_t n = 0;
    int zeros = 0;
    for (size_t i = skip; i < len; i++) {
        if (zeros >= 2 && nal[i] == 3) { zeros = 0; continue; }
        zeros = nal[i] == 0 ? zeros + 1 : 0;
        o[n++] = nal[i];
    }
    *out_len = n;
    return o;
}

static void m_vui_common(MBits *b, WMediaVui *v) {
    v->vui_present = 1;
    if (mb_u(b, 1)) {                       /* aspect_ratio_info_present_flag */
        uint32_t idc = mb_u(b, 8);
        if (idc == 255) { mb_u(b, 16); mb_u(b, 16); }
    }
    if (mb_u(b, 1)) mb_u(b, 1);             /* overscan_info_present / appropriate */
    v->video_signal_type_present = (int)mb_u(b, 1);
    if (v->video_signal_type_present) {
        mb_u(b, 3);                          /* video_format */
        v->full_range = (int)mb_u(b, 1);
        v->colour_description_present = (int)mb_u(b, 1);
        if (v->colour_description_present) {
            v->primaries = (int)mb_u(b, 8);
            v->transfer = (int)mb_u(b, 8);
            v->matrix = (int)mb_u(b, 8);
        }
    }
    v->chroma_loc_present = (int)mb_u(b, 1);
    if (v->chroma_loc_present) {
        v->chroma_loc_top = (int)mb_ue(b);
        v->chroma_loc_bottom = (int)mb_ue(b);
    }
}

static void m_h264_scaling(MBits *b, int size) {
    int last = 8, next = 8;
    for (int j = 0; j < size; j++) {
        if (next != 0) {
            int32_t delta = mb_se(b);
            next = (last + delta + 256) % 256;
        }
        last = next == 0 ? last : next;
    }
}

static void m_parse_h264_sps(uint8_t *r, size_t n, WMediaVui *v) {
    MBits b = {r, n, 0, 0};
    v->profile = (int)mb_u(&b, 8);
    mb_u(&b, 8);
    v->level = (int)mb_u(&b, 8);
    mb_ue(&b);
    v->chroma_format = 1;
    v->bit_depth = 8;
    int p = v->profile;
    if (p == 100 || p == 110 || p == 122 || p == 244 || p == 44 || p == 83 || p == 86 || p == 118 || p == 128 ||
        p == 138 || p == 139 || p == 134 || p == 135) {
        v->chroma_format = (int)mb_ue(&b);
        if (v->chroma_format == 3) mb_u(&b, 1);
        v->bit_depth = 8 + (int)mb_ue(&b);
        mb_ue(&b);
        mb_u(&b, 1);
        if (mb_u(&b, 1)) {
            int lists = v->chroma_format != 3 ? 8 : 12;
            for (int i = 0; i < lists; i++)
                if (mb_u(&b, 1)) m_h264_scaling(&b, i < 6 ? 16 : 64);
        }
    }
    mb_ue(&b);                               /* log2_max_frame_num_minus4 */
    v->poc_type = (int)mb_ue(&b);
    if (v->poc_type == 0) mb_ue(&b);
    else if (v->poc_type == 1) {
        mb_u(&b, 1);
        mb_se(&b);
        mb_se(&b);
        uint32_t k = mb_ue(&b);
        for (uint32_t i = 0; i < k && !b.err; i++) mb_se(&b);
    }
    v->max_ref_frames = (int)mb_ue(&b);
    mb_u(&b, 1);
    int wmb = (int)mb_ue(&b) + 1, hmap = (int)mb_ue(&b) + 1;
    int frame_mbs_only = (int)mb_u(&b, 1);
    if (!frame_mbs_only) mb_u(&b, 1);
    mb_u(&b, 1);
    int cl = 0, cr = 0, ct = 0, cbm = 0;
    if (mb_u(&b, 1)) { cl = (int)mb_ue(&b); cr = (int)mb_ue(&b); ct = (int)mb_ue(&b); cbm = (int)mb_ue(&b); }
    int cux = v->chroma_format == 0 || v->chroma_format == 3 ? 1 : 2;
    int cuy = (v->chroma_format == 1 ? 2 : 1) * (2 - frame_mbs_only);
    v->width = wmb * 16 - cux * (cl + cr);
    v->height = (2 - frame_mbs_only) * hmap * 16 - cuy * (ct + cbm);
    if (mb_u(&b, 1)) {
        m_vui_common(&b, v);
        v->timing_present = (int)mb_u(&b, 1);
        if (v->timing_present) {
            v->num_units_in_tick = mb_u(&b, 32);
            v->time_scale = mb_u(&b, 32);
        }
    }
    v->ok = !b.err;
}

static void m_hevc_ptl(MBits *b, int max_sub_layers_minus1, WMediaVui *v) {
    mb_u(b, 2);
    mb_u(b, 1);
    v->profile = (int)mb_u(b, 5);
    mb_u(b, 32);
    mb_u(b, 16); mb_u(b, 16); mb_u(b, 16);   /* 48 bits of flags */
    v->level = (int)mb_u(b, 8);
    int prof[8] = {0}, lev[8] = {0};
    for (int i = 0; i < max_sub_layers_minus1; i++) { prof[i] = (int)mb_u(b, 1); lev[i] = (int)mb_u(b, 1); }
    if (max_sub_layers_minus1 > 0)
        for (int i = max_sub_layers_minus1; i < 8; i++) mb_u(b, 2);
    for (int i = 0; i < max_sub_layers_minus1; i++) {
        if (prof[i]) { mb_u(b, 32); mb_u(b, 32); mb_u(b, 24); }   /* 88 bits */
        if (lev[i]) mb_u(b, 8);
    }
}

static void m_hevc_scaling(MBits *b) {
    for (int size = 0; size < 4; size++) {
        for (int m = 0; m < 6; m += (size == 3) ? 3 : 1) {
            if (!mb_u(b, 1)) mb_ue(b);
            else {
                int coef = 1 << (4 + (size << 1));
                if (coef > 64) coef = 64;
                if (size > 1) mb_se(b);
                for (int i = 0; i < coef && !b->err; i++) mb_se(b);
            }
        }
    }
}

static void m_parse_hevc_sps(uint8_t *r, size_t n, WMediaVui *v) {
    MBits b = {r, n, 0, 0};
    mb_u(&b, 4);
    int msl = (int)mb_u(&b, 3);
    mb_u(&b, 1);
    m_hevc_ptl(&b, msl, v);
    mb_ue(&b);
    v->chroma_format = (int)mb_ue(&b);
    if (v->chroma_format == 3) mb_u(&b, 1);
    v->width = (int)mb_ue(&b);
    v->height = (int)mb_ue(&b);
    if (mb_u(&b, 1)) {
        int sx = v->chroma_format == 1 || v->chroma_format == 2 ? 2 : 1, sy = v->chroma_format == 1 ? 2 : 1;
        int l = (int)mb_ue(&b), rr = (int)mb_ue(&b), t = (int)mb_ue(&b), bo = (int)mb_ue(&b);
        v->width -= sx * (l + rr);
        v->height -= sy * (t + bo);
    }
    v->bit_depth = 8 + (int)mb_ue(&b);
    mb_ue(&b);
    int log2_poc = (int)mb_ue(&b) + 4;
    int sub_info = (int)mb_u(&b, 1);
    for (int i = sub_info ? 0 : msl; i <= msl && !b.err; i++) {
        uint32_t dec = mb_ue(&b);
        mb_ue(&b);
        mb_ue(&b);
        if (i == msl) v->max_ref_frames = (int)dec + 1;
    }
    mb_ue(&b); mb_ue(&b); mb_ue(&b); mb_ue(&b); mb_ue(&b); mb_ue(&b);
    if (mb_u(&b, 1) && mb_u(&b, 1)) m_hevc_scaling(&b);
    mb_u(&b, 1);                             /* amp_enabled_flag */
    mb_u(&b, 1);                             /* sample_adaptive_offset_enabled_flag */
    if (mb_u(&b, 1)) { mb_u(&b, 4); mb_u(&b, 4); mb_ue(&b); mb_ue(&b); mb_u(&b, 1); }
    int nst = (int)mb_ue(&b);
    if (nst > 64) { b.err = 1; nst = 0; }
    int ndp[65] = {0};
    for (int i = 0; i < nst && !b.err; i++) {
        int inter = i != 0 ? (int)mb_u(&b, 1) : 0;
        if (inter) {
            mb_u(&b, 1);
            mb_ue(&b);
            int ref = i - 1;                 /* delta_idx_minus1 is only coded in slice headers */
            int cnt = 0;
            for (int j = 0; j <= ndp[ref]; j++) {
                int used = (int)mb_u(&b, 1);
                int use_delta = used ? 1 : (int)mb_u(&b, 1);
                if (use_delta) cnt++;
            }
            ndp[i] = cnt;
        } else {
            int neg = (int)mb_ue(&b), pos = (int)mb_ue(&b);
            if (neg > 16 || pos > 16) { b.err = 1; break; }
            for (int k = 0; k < neg + pos; k++) { mb_ue(&b); mb_u(&b, 1); }
            ndp[i] = neg + pos;
        }
    }
    if (mb_u(&b, 1)) {
        int nlt = (int)mb_ue(&b);
        for (int i = 0; i < nlt && !b.err; i++) { mb_u(&b, log2_poc); mb_u(&b, 1); }
    }
    mb_u(&b, 1);                             /* sps_temporal_mvp_enabled_flag */
    mb_u(&b, 1);                             /* strong_intra_smoothing_enabled_flag */
    if (mb_u(&b, 1)) {
        m_vui_common(&b, v);
        mb_u(&b, 1);                         /* neutral_chroma_indication_flag */
        mb_u(&b, 1);                         /* field_seq_flag */
        mb_u(&b, 1);                         /* frame_field_info_present_flag */
        if (mb_u(&b, 1)) { mb_ue(&b); mb_ue(&b); mb_ue(&b); mb_ue(&b); }
        v->timing_present = (int)mb_u(&b, 1);
        if (v->timing_present) {
            v->num_units_in_tick = mb_u(&b, 32);
            v->time_scale = mb_u(&b, 32);
        }
    }
    v->ok = !b.err;
}

int w_media_vui_parse(const uint8_t *rec, size_t len, int hevc, WMediaVui *v) {
    memset(v, 0, sizeof *v);
    v->chroma_loc_top = v->chroma_loc_bottom = -1;
    v->primaries = v->transfer = v->matrix = -1;
    const uint8_t *sps = NULL;
    size_t sps_len = 0;
    if (!hevc) {
        if (len < 7) return 0;
        int nsps = rec[5] & 0x1f;
        size_t off = 6;
        for (int i = 0; i < nsps; i++) {
            if (off + 2 > len) return 0;
            size_t l = ((size_t)rec[off] << 8) | rec[off + 1];
            if (off + 2 + l > len) return 0;
            if (!sps) { sps = rec + off + 2; sps_len = l; }
            off += 2 + l;
        }
        v->sps_count = nsps;
        if (off < len) v->pps_count = rec[off] & 0xff;
        if (!sps || sps_len < 2) return 0;
        size_t rn;
        uint8_t *r = m_rbsp(sps, sps_len, 1, &rn);
        m_parse_h264_sps(r, rn, v);
        free(r);
    } else {
        if (len < 23) return 0;
        int arrays = rec[22];
        size_t off = 23;
        for (int a = 0; a < arrays; a++) {
            if (off + 3 > len) return 0;
            int type = rec[off] & 0x3f;
            int cnt = ((int)rec[off + 1] << 8) | rec[off + 2];
            off += 3;
            for (int i = 0; i < cnt; i++) {
                if (off + 2 > len) return 0;
                size_t l = ((size_t)rec[off] << 8) | rec[off + 1];
                if (off + 2 + l > len) return 0;
                if (type == 33 && !sps) { sps = rec + off + 2; sps_len = l; }
                if (type == 32) v->vps_count++;
                if (type == 33) v->sps_count++;
                if (type == 34) v->pps_count++;
                off += 2 + l;
            }
        }
        if (!sps || sps_len < 3) return 0;
        size_t rn;
        uint8_t *r = m_rbsp(sps, sps_len, 2, &rn);
        m_parse_hevc_sps(r, rn, v);
        free(r);
    }
    return v->ok;
}

/* w_media_parse_sps(record, hevc) -> [[key, value], …] */
WValue w_media_parse_sps(WValue recv, WValue hevcv) {
    int64_t avail;
    const uint8_t *p = m_source(recv, 0, &avail, "parse_sps");
    if (avail < 0) w_media_raise("media.parse_sps: pass the avcC / hvcC record as a ByteArray");
    WMediaVui v;
    w_media_vui_parse(p, (size_t)avail, m_truthy(hevcv), &v);
    WValue a = w_array_new_empty();
    a = w_array_push(a, m_pair("ok", v.ok ? W_TRUE : W_FALSE));
    a = w_array_push(a, m_pair("profile", w_int(v.profile)));
    a = w_array_push(a, m_pair("level", w_int(v.level)));
    a = w_array_push(a, m_pair("bit_depth", w_int(v.bit_depth)));
    a = w_array_push(a, m_pair("chroma_format", w_int(v.chroma_format)));
    a = w_array_push(a, m_pair("width", w_int(v.width)));
    a = w_array_push(a, m_pair("height", w_int(v.height)));
    a = w_array_push(a, m_pair("vui", v.vui_present ? W_TRUE : W_FALSE));
    a = w_array_push(a, m_pair("full_range", w_int(v.full_range)));
    a = w_array_push(a, m_pair("primaries", w_int(v.primaries)));
    a = w_array_push(a, m_pair("transfer", w_int(v.transfer)));
    a = w_array_push(a, m_pair("matrix", w_int(v.matrix)));
    a = w_array_push(a, m_pair("chroma_loc", w_int(v.chroma_loc_top)));
    a = w_array_push(a, m_pair("timing", v.timing_present ? W_TRUE : W_FALSE));
    a = w_array_push(a, m_pair("num_units_in_tick", w_int(v.num_units_in_tick)));
    a = w_array_push(a, m_pair("time_scale", w_int(v.time_scale)));
    a = w_array_push(a, m_pair("poc_type", w_int(v.poc_type)));
    a = w_array_push(a, m_pair("max_ref_frames", w_int(v.max_ref_frames)));
    a = w_array_push(a, m_pair("sps_count", w_int(v.sps_count)));
    a = w_array_push(a, m_pair("pps_count", w_int(v.pps_count)));
    a = w_array_push(a, m_pair("vps_count", w_int(v.vps_count)));
    return a;
}

/* ======================================================================
   WAV reader (RIFF / RF64 / WAVE_FORMAT_EXTENSIBLE), mmap
   ====================================================================== */

static uint16_t m_le16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

int w_media_wav_open(const char *path, WMediaWav *w, char *err, size_t cap) {
    memset(w, 0, sizeof *w);
    int fd = open(path, O_RDONLY);
    if (fd < 0) { snprintf(err, cap, "cannot open %s: %s", path, strerror(errno)); return -1; }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < 44) { close(fd); snprintf(err, cap, "%s is too short to be a WAV file", path); return -1; }
    void *m = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (m == MAP_FAILED) { snprintf(err, cap, "cannot map %s: %s", path, strerror(errno)); return -1; }
    const uint8_t *p = m;
    size_t n = (size_t)st.st_size;
    w->map = m;
    w->map_len = n;
    int rf64 = !memcmp(p, "RF64", 4);
    if ((memcmp(p, "RIFF", 4) && !rf64) || memcmp(p + 8, "WAVE", 4)) {
        w_media_wav_close(w);
        snprintf(err, cap, "%s is not a RIFF/RF64 WAVE file", path);
        return -1;
    }
    uint64_t ds64_data = 0;
    int fmt_ok = 0, tag = 0;
    size_t off = 12;
    while (off + 8 <= n) {
        const uint8_t *c = p + off;
        uint64_t sz = m_get32(c + 4);
        if (!memcmp(c, "ds64", 4) && off + 8 + 16 <= n) ds64_data = m_get64(c + 16);
        if (!memcmp(c, "fmt ", 4) && off + 8 + 16 <= n) {
            tag = m_le16(c + 8);
            w->channels = m_le16(c + 10);
            w->rate = (int32_t)m_get32(c + 12);
            w->block = m_le16(c + 20);
            w->bits = m_le16(c + 22);
            if (tag == 0xFFFE && sz >= 40) tag = m_le16(c + 8 + 24);
            fmt_ok = 1;
        }
        if (!memcmp(c, "data", 4)) {
            if (sz == 0xFFFFFFFFu && ds64_data) sz = ds64_data;
            if (off + 8 + sz > n) sz = n - off - 8;
            w->data = c + 8;
            if (fmt_ok && w->block > 0) w->frames = (int64_t)(sz / (uint64_t)w->block);
            break;
        }
        off += 8 + sz + (sz & 1);
    }
    if (!fmt_ok || !w->data) { w_media_wav_close(w); snprintf(err, cap, "%s has no fmt or data chunk", path); return -1; }
    w->is_float = tag == 3;
    if (!(tag == 1 || tag == 3) || w->channels < 1 || w->channels > 8 ||
        !(w->bits == 16 || w->bits == 24 || w->bits == 32 || (w->bits == 64 && w->is_float)) ||
        w->block != w->channels * (w->bits / 8)) {
        w_media_wav_close(w);
        snprintf(err, cap, "%s: unsupported WAV format (tag %d, %d channels, %d bits); use 16/24/32-bit PCM or 32/64-bit float", path, tag, w->channels, w->bits);
        return -1;
    }
    return 0;
}

void w_media_wav_close(WMediaWav *w) {
    if (w->map) munmap(w->map, w->map_len);
    memset(w, 0, sizeof *w);
}

void w_media_wav_read_f32(const WMediaWav *w, int64_t first, int64_t n, float *out) {
    int ch = w->channels;
    for (int64_t i = 0; i < n; i++) {
        int64_t f = first + i;
        float *o = out + i * ch;
        if (f < 0 || f >= w->frames) { for (int c = 0; c < ch; c++) o[c] = 0.0f; continue; }
        const uint8_t *s = w->data + f * w->block;
        for (int c = 0; c < ch; c++) {
            float v;
            if (w->is_float) {
                if (w->bits == 32) { uint32_t u = m_get32(s); memcpy(&v, &u, 4); }
                else { uint64_t u = m_get64(s); double d; memcpy(&d, &u, 8); v = (float)d; }
            } else if (w->bits == 16) {
                v = (float)(int16_t)m_le16(s) / 32768.0f;
            } else if (w->bits == 24) {
                int32_t x = (int32_t)((uint32_t)s[0] << 8 | (uint32_t)s[1] << 16 | (uint32_t)s[2] << 24) >> 8;
                v = (float)x / 8388608.0f;
            } else {
                v = (float)((double)(int32_t)m_get32(s) / 2147483648.0);
            }
            o[c] = v;
            s += w->bits / 8;
        }
    }
}

/* w_media_wav_info(path) -> [frames, channels, rate, bits, float?] */
WValue w_media_wav_info(WValue pathv) {
    char path[4096], err[512];
    if (!w_media_str(pathv, path, sizeof path)) w_media_raise("media.wav_info: path must be a string");
    WMediaWav w;
    if (w_media_wav_open(path, &w, err, sizeof err) != 0) w_media_raise("media.wav_info: %s", err);
    WValue a = w_array_new_empty();
    a = w_array_push(a, w_int(w.frames));
    a = w_array_push(a, w_int(w.channels));
    a = w_array_push(a, w_int(w.rate));
    a = w_array_push(a, w_int(w.bits));
    a = w_array_push(a, w.is_float ? W_TRUE : W_FALSE);
    w_media_wav_close(&w);
    return a;
}

WValue w_media_available(void) { return W_TRUE; }

#else /* !__APPLE__ — raising stubs, generated from the same lists */

#ifdef __APPLE__
#define M_TARGET "this build (TUNGSTEN_MEDIA_STUB)"
#elif defined(__linux__)
#define M_TARGET "Linux"
#elif defined(__wasm__)
#define M_TARGET "wasm"
#else
#define M_TARGET "this platform"
#endif

__attribute__((noreturn))
static void m_unavailable(const char *fn) {
    char buf[256];
    snprintf(buf, sizeof buf,
             "media needs macOS VideoToolbox/AVFoundation: %s is not available on %s "
             "(runtime/media builds its encoder and muxer only for Apple targets)",
             fn, M_TARGET);
    w_raise(w_string(buf));
    abort();
}

#define W_MEDIA_U __attribute__((unused)) WValue
#define W_MEDIA_NAMED_0 void
#define W_MEDIA_NAMED_1 W_MEDIA_U a0
#define W_MEDIA_NAMED_2 W_MEDIA_NAMED_1, W_MEDIA_U a1
#define W_MEDIA_NAMED_3 W_MEDIA_NAMED_2, W_MEDIA_U a2
#define W_MEDIA_NAMED_4 W_MEDIA_NAMED_3, W_MEDIA_U a3
#define W_MEDIA_NAMED_7 W_MEDIA_NAMED_4, W_MEDIA_U a4, W_MEDIA_U a5, W_MEDIA_U a6
#define W_MEDIA_NAMED_11 W_MEDIA_NAMED_7, W_MEDIA_U a7, W_MEDIA_U a8, W_MEDIA_U a9, W_MEDIA_U a10
#define W_MEDIA_NAMED_12 W_MEDIA_NAMED_11, W_MEDIA_U a11

#define W_MEDIA_STUB(name, n) WValue name(W_MEDIA_NAMED_##n) { m_unavailable(#name); }
W_MEDIA_CCALLS(W_MEDIA_STUB)
#undef W_MEDIA_STUB

WValue w_media_available(void) { return W_FALSE; }

#endif

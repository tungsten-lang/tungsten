/* runtime/media/media_avf.m — AVFoundation half of the media bridge.
 *
 * Mux: AVAssetWriter appends encoded segments passthrough (outputSettings
 * nil), with every PTS rewritten to frame x den/num in a track timescale that
 * makes each frame an integer number of ticks, so the file is CFR with exact
 * timestamps. Audio comes from a WAV file (mmap'd, fed in 100 ms buffers
 * interleaved with the video) and is written as AAC (MP4) or 24-bit PCM
 * (MOV); AVAssetWriter's AAC edit list hides the encoder priming, so audio
 * sample 0 plays with video frame 0, and the mux pads or trims the WAV so
 * the audio is exactly frames x rate x den/num samples long.
 *
 * Timecode: AVAssetWriter accepts a timecode input only for QuickTime movies
 * and needs its one sample's duration before the video is written, so the
 * `tmcd` track is added after AVAssetWriter finishes instead, for MP4 and MOV
 * alike: the moov box is parsed, a timecode trak (and the video trak's tref)
 * is inserted, the 4-byte sample goes in a small mdat at the end, and every
 * chunk offset is moved when the moov moves to the front (faststart). The
 * layout follows ffmpeg's `-timecode` output (nmhd in MP4; gmhd/tcmi in MOV),
 * which ffprobe, QuickTime and AVFoundation read.
 *
 * Probe: AVURLAsset + AVAssetReader facts for MediaVerify (sample timing,
 * colour tags in the container and in the SPS VUI, timecode, audio length),
 * decoded pixel values at chosen points, and a flash/click sync scan.
 *
 * Manual retain/release, like metal.m (the runtime builds without ARC). */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include "runtime.h"
#include "wvalue.h"
#include "media.h"

#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#import <Metal/Metal.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <fcntl.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#pragma clang diagnostic error "-Wmissing-prototypes"
/* The synchronous AVAsset accessors are deprecated in favour of async loads;
 * a command-line encoder wants the blocking forms. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* ======================================================================
   Small helpers
   ====================================================================== */

static WValue a_pair(const char *k, WValue v) {
    WValue p = w_array_new_empty();
    p = w_array_push(p, w_string(k));
    p = w_array_push(p, v);
    return p;
}

static WValue a_time(CMTime t) {
    if (!CMTIME_IS_NUMERIC(t)) return W_NIL;
    WValue p = w_array_new_empty();
    p = w_array_push(p, w_int(t.value));
    p = w_array_push(p, w_int(t.timescale));
    return p;
}

static WValue a_cfstr(CFTypeRef s) {
    if (!s || CFGetTypeID(s) != CFStringGetTypeID()) return W_NIL;
    char buf[256];
    if (!CFStringGetCString((CFStringRef)s, buf, sizeof buf, kCFStringEncodingUTF8)) return W_NIL;
    return w_string(buf);
}

static WValue a_fourcc(uint32_t f) {
    char s[5] = {(char)(f >> 24), (char)(f >> 16), (char)(f >> 8), (char)f, 0};
    return w_string(s);
}

static uint64_t m_avf_now_ns(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return mach_absolute_time() * tb.numer / tb.denom;
}

/* a[i], or nil when a is not an Array or too short */
static WValue m_avf_arr(WValue a, int i) {
    if (!w_is_array(a) || i >= w_as_array(a)->size) return W_NIL;
    return w_array_get(a, w_int(i));
}

static void *m_avf_dest(WValue v, int64_t *avail, const char *what) {
    return (void *)(uintptr_t)w_media_pixels(v, 0, avail, what);
}

static void *m_avf_peek(WValue h, int kind) { return w_media_handle_peek(h, kind); }

static void a_be16(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
static void a_be32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }
static void a_be64(uint8_t *p, uint64_t v) { a_be32(p, (uint32_t)(v >> 32)); a_be32(p + 4, (uint32_t)v); }
static uint32_t a_rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static uint64_t a_rd64(const uint8_t *p) { return ((uint64_t)a_rd32(p) << 32) | a_rd32(p + 4); }
#define A_FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

/* ======================================================================
   MP4 / MOV box tree, for adding a tmcd track after AVAssetWriter
   ====================================================================== */

typedef struct ABox {
    uint32_t     type;
    int          container;
    uint8_t     *raw;        /* leaf: the whole box, header included (owned) */
    size_t       len;
    struct ABox *kid;
    int          nk, ck;
} ABox;

static int a_is_container(uint32_t t) {
    return t == A_FOURCC('m','o','o','v') || t == A_FOURCC('t','r','a','k') || t == A_FOURCC('m','d','i','a') ||
           t == A_FOURCC('m','i','n','f') || t == A_FOURCC('s','t','b','l') || t == A_FOURCC('e','d','t','s') ||
           t == A_FOURCC('d','i','n','f');
}

static ABox *a_box_add(ABox *parent) {
    if (parent->nk == parent->ck) {
        int c = parent->ck ? parent->ck * 2 : 8;
        parent->kid = realloc(parent->kid, sizeof(ABox) * (size_t)c);
        parent->ck = c;
    }
    ABox *b = &parent->kid[parent->nk++];
    memset(b, 0, sizeof *b);
    return b;
}

static int a_box_parse(const uint8_t *p, size_t n, ABox *parent) {
    size_t off = 0;
    while (off + 8 <= n) {
        uint64_t sz = a_rd32(p + off);
        uint32_t t = a_rd32(p + off + 4);
        size_t h = 8;
        if (sz == 1) { if (off + 16 > n) return 0; sz = a_rd64(p + off + 8); h = 16; }
        else if (sz == 0) sz = n - off;
        if (sz < h || off + sz > n) return 0;
        ABox *b = a_box_add(parent);
        b->type = t;
        if (a_is_container(t)) {
            b->container = 1;
            if (!a_box_parse(p + off + h, (size_t)sz - h, b)) return 0;
        } else {
            b->raw = malloc((size_t)sz);
            memcpy(b->raw, p + off, (size_t)sz);
            b->len = (size_t)sz;
        }
        off += (size_t)sz;
    }
    return off == n;
}

static size_t a_box_size(const ABox *b) {
    if (!b->container) return b->len;
    size_t s = 8;
    for (int i = 0; i < b->nk; i++) s += a_box_size(&b->kid[i]);
    return s;
}

static void a_box_write(const ABox *b, uint8_t *out, size_t *pos) {
    if (!b->container) { memcpy(out + *pos, b->raw, b->len); *pos += b->len; return; }
    a_be32(out + *pos, (uint32_t)a_box_size(b));
    a_be32(out + *pos + 4, b->type);
    *pos += 8;
    for (int i = 0; i < b->nk; i++) a_box_write(&b->kid[i], out, pos);
}

static void a_box_free(ABox *b) {
    for (int i = 0; i < b->nk; i++) a_box_free(&b->kid[i]);
    free(b->kid);
    free(b->raw);
    b->kid = NULL;
    b->raw = NULL;
}

static ABox *a_box_find(ABox *b, uint32_t t) {
    for (int i = 0; i < b->nk; i++) if (b->kid[i].type == t) return &b->kid[i];
    return NULL;
}

/* A leaf from bytes (header added). */
static ABox a_leaf(uint32_t type, const uint8_t *payload, size_t n) {
    ABox b;
    memset(&b, 0, sizeof b);
    b.type = type;
    b.len = n + 8;
    b.raw = malloc(b.len);
    a_be32(b.raw, (uint32_t)b.len);
    a_be32(b.raw + 4, type);
    if (n) memcpy(b.raw + 8, payload, n);
    return b;
}

static ABox a_cont(uint32_t type) {
    ABox b;
    memset(&b, 0, sizeof b);
    b.type = type;
    b.container = 1;
    return b;
}

static void a_push(ABox *parent, ABox kid) { *a_box_add(parent) = kid; }

/* Insert kid before the first child of type `before` (or at the end). */
static void a_insert_before(ABox *parent, ABox kid, uint32_t before) {
    a_box_add(parent);
    int at = parent->nk - 1;
    for (int i = 0; i < parent->nk - 1; i++) if (parent->kid[i].type == before) { at = i; break; }
    memmove(&parent->kid[at + 1], &parent->kid[at], sizeof(ABox) * (size_t)(parent->nk - 1 - at));
    parent->kid[at] = kid;
}

typedef struct {
    int64_t old_off, size, new_off;
} ARegion;

/* Map an old file offset to its new one through the moved top-level boxes. */
static uint64_t a_map(uint64_t o, const ARegion *r, int nr, int *ok) {
    for (int i = 0; i < nr; i++)
        if ((int64_t)o >= r[i].old_off && (int64_t)o < r[i].old_off + r[i].size)
            return (uint64_t)((int64_t)o - r[i].old_off + r[i].new_off);
    *ok = 0;
    return o;
}

/* Turn every stco under b whose mapped entries would exceed 32 bits into a
 * co64 holding the same (unmapped) values. Returns how many it widened. */
static int a_widen(ABox *b, const ARegion *r, int nr) {
    int n = 0;
    if (b->container) {
        for (int i = 0; i < b->nk; i++) n += a_widen(&b->kid[i], r, nr);
        return n;
    }
    if (b->type != A_FOURCC('s','t','c','o') || b->len < 16) return 0;
    uint32_t cnt = a_rd32(b->raw + 12);
    if (16 + (size_t)cnt * 4 > b->len) return 0;
    int ok = 1, big = 0;
    for (uint32_t i = 0; i < cnt; i++) if (a_map(a_rd32(b->raw + 16 + 4 * i), r, nr, &ok) > 0xffffffffull) big = 1;
    if (!big) return 0;
    size_t len = 16 + (size_t)cnt * 8;
    uint8_t *nb = malloc(len);
    memcpy(nb, b->raw, 16);
    a_be32(nb, (uint32_t)len);
    a_be32(nb + 4, A_FOURCC('c','o','6','4'));
    for (uint32_t i = 0; i < cnt; i++) a_be64(nb + 16 + 8 * i, a_rd32(b->raw + 16 + 4 * i));
    free(b->raw);
    b->raw = nb;
    b->len = len;
    b->type = A_FOURCC('c','o','6','4');
    return 1;
}

/* Move every stco/co64 entry under b through the region map. Returns 0 if
 * an offset lies outside every region or an stco entry would overflow. */
static int a_patch_offsets(ABox *b, const ARegion *r, int nr) {
    int ok = 1;
    if (b->container) {
        for (int i = 0; i < b->nk; i++) if (!a_patch_offsets(&b->kid[i], r, nr)) ok = 0;
        return ok;
    }
    if (b->type == A_FOURCC('s','t','c','o') && b->len >= 16) {
        uint32_t n = a_rd32(b->raw + 12);
        if (16 + (size_t)n * 4 > b->len) return 0;
        for (uint32_t i = 0; i < n; i++) {
            uint64_t v = a_map(a_rd32(b->raw + 16 + 4 * i), r, nr, &ok);
            if (v > 0xffffffffull) ok = 0;
            a_be32(b->raw + 16 + 4 * i, (uint32_t)v);
        }
    } else if (b->type == A_FOURCC('c','o','6','4') && b->len >= 16) {
        uint32_t n = a_rd32(b->raw + 12);
        if (16 + (size_t)n * 8 > b->len) return 0;
        for (uint32_t i = 0; i < n; i++) a_be64(b->raw + 16 + 8 * i, a_map(a_rd64(b->raw + 16 + 8 * i), r, nr, &ok));
    }
    return ok;
}

/* The timecode trak (ffmpeg's -timecode layout). sample_off is set later. */
static ABox a_tmcd_trak(int mov, uint32_t track_id, uint64_t movie_dur, uint32_t ts, uint64_t media_dur,
                        uint32_t ticks, uint32_t quanta, uint32_t flags) {
    uint8_t p[256];
    ABox trak = a_cont(A_FOURCC('t','r','a','k'));
    /* tkhd v1 (64-bit durations): flags 2 = in movie, not enabled */
    memset(p, 0, 96);
    p[0] = 1; p[3] = 2;
    a_be32(p + 20, track_id);
    a_be64(p + 28, movie_dur);
    a_be32(p + 52, 0x00010000); a_be32(p + 68, 0x00010000); a_be32(p + 84, 0x40000000);   /* identity matrix */
    a_push(&trak, a_leaf(A_FOURCC('t','k','h','d'), p, 96));
    ABox edts = a_cont(A_FOURCC('e','d','t','s'));
    memset(p, 0, 28);
    p[0] = 1;                                   /* elst v1: one edit, media time 0, rate 1 */
    a_be32(p + 4, 1);
    a_be64(p + 8, movie_dur);
    a_be64(p + 16, 0);
    a_be32(p + 24, 0x00010000);
    a_push(&edts, a_leaf(A_FOURCC('e','l','s','t'), p, 28));
    a_push(&trak, edts);
    ABox mdia = a_cont(A_FOURCC('m','d','i','a'));
    memset(p, 0, 36);
    p[0] = 1;                                   /* mdhd v1 */
    a_be32(p + 20, ts);
    a_be64(p + 24, media_dur);
    a_be16(p + 32, 0x55c4);                     /* language: und */
    a_push(&mdia, a_leaf(A_FOURCC('m','d','h','d'), p, 36));
    static const char hname[] = "TimeCodeHandler";
    memset(p, 0, 64);
    size_t hl;
    if (mov) {
        a_be32(p + 4, A_FOURCC('m','h','l','r'));
        a_be32(p + 8, A_FOURCC('t','m','c','d'));
        p[24] = (uint8_t)(sizeof hname - 1);
        memcpy(p + 25, hname, sizeof hname - 1);
        hl = 25 + sizeof hname - 1;
    } else {
        a_be32(p + 8, A_FOURCC('t','m','c','d'));
        memcpy(p + 24, hname, sizeof hname);     /* NUL-terminated */
        hl = 24 + sizeof hname;
    }
    a_push(&mdia, a_leaf(A_FOURCC('h','d','l','r'), p, hl));
    ABox minf = a_cont(A_FOURCC('m','i','n','f'));
    if (mov) {
        ABox gmhd = a_cont(A_FOURCC('g','m','h','d'));
        memset(p, 0, 16);
        a_be16(p + 4, 0x0040);                  /* graphics mode: dither copy */
        a_be16(p + 6, 0x8000); a_be16(p + 8, 0x8000); a_be16(p + 10, 0x8000);
        a_push(&gmhd, a_leaf(A_FOURCC('g','m','i','n'), p, 16));
        memset(p, 0, 36);
        a_be32(p + 0, 0x00010000); a_be32(p + 16, 0x00010000); a_be32(p + 32, 0x40000000);
        a_push(&gmhd, a_leaf(A_FOURCC('t','e','x','t'), p, 36));
        static const char font[] = "Lucida Grande";
        memset(p, 0, 64);
        a_be16(p + 8, 12);                      /* text size */
        a_be16(p + 18, 0xffff); a_be16(p + 20, 0xffff); a_be16(p + 22, 0xffff);
        p[24] = (uint8_t)(sizeof font - 1);
        memcpy(p + 25, font, sizeof font - 1);
        uint8_t tc[80];
        size_t tcmi_len = 8 + 25 + sizeof font - 1;
        a_be32(tc, (uint32_t)tcmi_len);
        a_be32(tc + 4, A_FOURCC('t','c','m','i'));
        memcpy(tc + 8, p, tcmi_len - 8);
        a_push(&gmhd, a_leaf(A_FOURCC('t','m','c','d'), tc, tcmi_len));   /* tmcd holding its tcmi */
        a_push(&minf, gmhd);
        memset(p, 0, 64);
        a_be32(p + 4, A_FOURCC('d','h','l','r'));
        a_be32(p + 8, A_FOURCC('u','r','l',' '));
        static const char dname[] = "DataHandler";
        p[24] = (uint8_t)(sizeof dname - 1);
        memcpy(p + 25, dname, sizeof dname - 1);
        a_push(&minf, a_leaf(A_FOURCC('h','d','l','r'), p, 25 + sizeof dname - 1));
    } else {
        memset(p, 0, 4);
        a_push(&minf, a_leaf(A_FOURCC('n','m','h','d'), p, 4));
    }
    ABox dinf = a_cont(A_FOURCC('d','i','n','f'));
    memset(p, 0, 20);
    a_be32(p + 4, 1);
    a_be32(p + 8, 12);
    a_be32(p + 12, A_FOURCC('u','r','l',' '));
    a_be32(p + 16, 1);                          /* self-contained */
    a_push(&dinf, a_leaf(A_FOURCC('d','r','e','f'), p, 20));
    a_push(&minf, dinf);
    ABox stbl = a_cont(A_FOURCC('s','t','b','l'));
    memset(p, 0, 64);
    a_be32(p + 4, 1);                           /* stsd: one entry */
    a_be32(p + 8, 34);
    a_be32(p + 12, A_FOURCC('t','m','c','d'));
    a_be16(p + 22, 1);                          /* data reference index */
    a_be32(p + 28, flags);
    a_be32(p + 32, ts);
    a_be32(p + 36, ticks);
    p[40] = (uint8_t)quanta;
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','d'), p, 8 + 34));
    memset(p, 0, 16);
    a_be32(p + 4, 1);
    a_be32(p + 8, 1);
    a_be32(p + 12, (uint32_t)media_dur);
    a_push(&stbl, a_leaf(A_FOURCC('s','t','t','s'), p, 16));
    memset(p, 0, 20);
    a_be32(p + 4, 1); a_be32(p + 8, 1); a_be32(p + 12, 1); a_be32(p + 16, 1);
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','c'), p, 20));
    memset(p, 0, 12);
    a_be32(p + 4, 4); a_be32(p + 8, 1);
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','z'), p, 12));
    memset(p, 0, 16);
    a_be32(p + 4, 1);                           /* co64: one chunk, offset patched later */
    a_push(&stbl, a_leaf(A_FOURCC('c','o','6','4'), p, 16));
    a_push(&minf, stbl);
    a_push(&mdia, minf);
    a_push(&trak, mdia);
    return trak;
}

/* A chapter: its title (UTF-8, owned) and first frame. */
typedef struct AChapter {
    char    *title;
    int64_t  frame;
} AChapter;

/* One chapter text sample: u16 length, the UTF-8 title, then an 'encd'
 * atom saying UTF-8 (ffmpeg's chapter samples, which QuickTime, AVFoundation
 * and ffprobe read). */
static size_t a_chap_sample(const char *title, uint8_t *out) {
    static const uint8_t encd[12] = {0, 0, 0, 12, 'e', 'n', 'c', 'd', 0, 0, 1, 0};
    size_t n = strlen(title);
    if (n > 1024) n = 1024;
    if (out) {
        a_be16(out, (uint32_t)n);
        memcpy(out + 2, title, n);
        memcpy(out + 2 + n, encd, sizeof encd);
    }
    return 2 + n + sizeof encd;
}

/* The chapter track: a disabled QuickTime text track whose samples are the
 * chapter titles, each lasting until the next chapter (the last until the
 * end of the video). A first chapter after frame 0 is preceded by an empty
 * edit. Media timescale = the video's, so chapter starts are exact frames.
 * The chunk offset (co64) is set later. */
static ABox a_chap_trak(int mov, uint32_t track_id, uint32_t movie_ts, uint32_t ts, uint32_t ticks, int64_t frames,
                        const AChapter *ch, int n) {
    uint8_t p[256];
    uint64_t lead = (uint64_t)ch[0].frame * ticks;
    uint64_t media_dur = (uint64_t)(frames - ch[0].frame) * ticks;
    uint64_t movie_lead = (uint64_t)((__int128)lead * movie_ts / ts);
    uint64_t movie_media = (uint64_t)((__int128)media_dur * movie_ts / ts);
    ABox trak = a_cont(A_FOURCC('t','r','a','k'));
    memset(p, 0, 96);
    p[0] = 1; p[3] = 2;                         /* tkhd v1: in movie, not enabled */
    a_be32(p + 20, track_id);
    a_be64(p + 28, movie_lead + movie_media);
    a_be32(p + 52, 0x00010000); a_be32(p + 68, 0x00010000); a_be32(p + 84, 0x40000000);
    a_push(&trak, a_leaf(A_FOURCC('t','k','h','d'), p, 96));
    ABox edts = a_cont(A_FOURCC('e','d','t','s'));
    memset(p, 0, 48);
    p[0] = 1;                                   /* elst v1 */
    size_t at = 8;
    if (lead > 0) {
        a_be64(p + at, movie_lead);             /* empty edit up to the first chapter */
        a_be64(p + at + 8, UINT64_MAX);         /* media time -1 */
        a_be32(p + at + 16, 0x00010000);
        at += 20;
    }
    a_be64(p + at, movie_media);
    a_be64(p + at + 8, 0);
    a_be32(p + at + 16, 0x00010000);
    at += 20;
    a_be32(p + 4, lead > 0 ? 2 : 1);
    a_push(&edts, a_leaf(A_FOURCC('e','l','s','t'), p, at));
    a_push(&trak, edts);
    ABox mdia = a_cont(A_FOURCC('m','d','i','a'));
    memset(p, 0, 36);
    p[0] = 1;                                   /* mdhd v1 */
    a_be32(p + 20, ts);
    a_be64(p + 24, media_dur);
    a_be16(p + 32, 0x55c4);                     /* language: und */
    a_push(&mdia, a_leaf(A_FOURCC('m','d','h','d'), p, 36));
    static const char hname[] = "ChapterHandler";
    memset(p, 0, 64);
    size_t hl;
    if (mov) {
        a_be32(p + 4, A_FOURCC('m','h','l','r'));
        a_be32(p + 8, A_FOURCC('t','e','x','t'));
        p[24] = (uint8_t)(sizeof hname - 1);
        memcpy(p + 25, hname, sizeof hname - 1);
        hl = 25 + sizeof hname - 1;
    } else {
        a_be32(p + 8, A_FOURCC('t','e','x','t'));
        memcpy(p + 24, hname, sizeof hname);
        hl = 24 + sizeof hname;
    }
    a_push(&mdia, a_leaf(A_FOURCC('h','d','l','r'), p, hl));
    ABox minf = a_cont(A_FOURCC('m','i','n','f'));
    ABox gmhd = a_cont(A_FOURCC('g','m','h','d'));
    memset(p, 0, 16);
    a_be16(p + 4, 0x0040);
    a_be16(p + 6, 0x8000); a_be16(p + 8, 0x8000); a_be16(p + 10, 0x8000);
    a_push(&gmhd, a_leaf(A_FOURCC('g','m','i','n'), p, 16));
    memset(p, 0, 36);
    a_be32(p + 0, 0x00010000); a_be32(p + 16, 0x00010000); a_be32(p + 32, 0x40000000);
    a_push(&gmhd, a_leaf(A_FOURCC('t','e','x','t'), p, 36));
    a_push(&minf, gmhd);
    if (mov) {
        static const char dname[] = "DataHandler";
        memset(p, 0, 64);
        a_be32(p + 4, A_FOURCC('d','h','l','r'));
        a_be32(p + 8, A_FOURCC('u','r','l',' '));
        p[24] = (uint8_t)(sizeof dname - 1);
        memcpy(p + 25, dname, sizeof dname - 1);
        a_push(&minf, a_leaf(A_FOURCC('h','d','l','r'), p, 25 + sizeof dname - 1));
    }
    ABox dinf = a_cont(A_FOURCC('d','i','n','f'));
    memset(p, 0, 20);
    a_be32(p + 4, 1);
    a_be32(p + 8, 12);
    a_be32(p + 12, A_FOURCC('u','r','l',' '));
    a_be32(p + 16, 1);
    a_push(&dinf, a_leaf(A_FOURCC('d','r','e','f'), p, 20));
    a_push(&minf, dinf);
    ABox stbl = a_cont(A_FOURCC('s','t','b','l'));
    /* stsd: one 'text' entry with ffmpeg's chapter properties (justification 1) */
    memset(p, 0, 80);
    a_be32(p + 4, 1);
    a_be32(p + 8, 8 + 8 + 43);
    a_be32(p + 12, A_FOURCC('t','e','x','t'));
    a_be16(p + 22, 1);                          /* data reference index */
    p[24 + 7] = 1;                              /* text justification */
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','d'), p, 8 + 8 + 8 + 43));
    size_t tl = 8 + 8 * (size_t)n, zl = 12 + 4 * (size_t)n;
    uint8_t *tt = calloc(1, tl), *zz = calloc(1, zl);
    a_be32(tt + 4, (uint32_t)n);
    a_be32(zz + 8, (uint32_t)n);
    for (int i = 0; i < n; i++) {
        int64_t end = i + 1 < n ? ch[i + 1].frame : frames;
        a_be32(tt + 8 + 8 * (size_t)i, 1);
        a_be32(tt + 12 + 8 * (size_t)i, (uint32_t)((uint64_t)(end - ch[i].frame) * ticks));
        a_be32(zz + 12 + 4 * (size_t)i, (uint32_t)a_chap_sample(ch[i].title, NULL));
    }
    a_push(&stbl, a_leaf(A_FOURCC('s','t','t','s'), tt, tl));
    memset(p, 0, 20);
    a_be32(p + 4, 1); a_be32(p + 8, 1); a_be32(p + 12, (uint32_t)n); a_be32(p + 16, 1);
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','c'), p, 20));
    a_push(&stbl, a_leaf(A_FOURCC('s','t','s','z'), zz, zl));
    free(tt);
    free(zz);
    memset(p, 0, 16);
    a_be32(p + 4, 1);
    a_push(&stbl, a_leaf(A_FOURCC('c','o','6','4'), p, 16));
    a_push(&minf, stbl);
    a_push(&mdia, minf);
    a_push(&trak, mdia);
    return trak;
}

/* Nero chapters (moov/udta/chpl, as ffmpeg writes them): version 1, a
 * reserved word, a count (at most 255), then per chapter its start in
 * 100 ns units and a Pascal-string title (at most 255 bytes, cut at a
 * UTF-8 boundary). */
static uint8_t *a_chpl(const AChapter *ch, int n, int32_t num, int32_t den, size_t *len) {
    if (n > 255) n = 255;
    size_t cap = 17 + (size_t)n * (9 + 255);
    uint8_t *b = calloc(1, cap);
    a_be32(b + 4, A_FOURCC('c','h','p','l'));
    a_be32(b + 8, 0x01000000);
    b[16] = (uint8_t)n;
    size_t at = 17;
    for (int i = 0; i < n; i++) {
        __int128 t = (__int128)ch[i].frame * den * 10000000;
        a_be64(b + at, (uint64_t)((t * 2 + num) / (2 * (__int128)num)));
        size_t k = strlen(ch[i].title);
        if (k > 255) {
            k = 255;
            while (k > 0 && ((uint8_t)ch[i].title[k] & 0xC0) == 0x80) k--;
        }
        b[at + 8] = (uint8_t)k;
        memcpy(b + at + 9, ch[i].title, k);
        at += 9 + k;
    }
    a_be32(b, (uint32_t)at);
    *len = at;
    return b;
}

typedef struct {
    uint32_t type;
    int64_t  off, size;
} ATop;

/* What a_patch_moov adds to a file AVAssetWriter wrote. */
typedef struct APatch {
    int             mov;
    uint32_t        ts, ticks;        /* video track timescale, ticks a frame */
    int32_t         num, den;
    int64_t         frames;
    int             has_tc, tc_drop;
    int64_t         tc_frame;
    uint32_t        tc_quanta;
    const AChapter *chap;
    int             nchap;
    int             chpl;             /* also a Nero chpl box (MP4) */
    int             faststart;
} APatch;

/* Read the top-level boxes and parse the moov. 0 on success. */
static int a_read_moov(int fd, const char *src, ATop *top, int *ntop_out, int *moov_i_out, ABox *root, char *err, size_t errcap) {
    struct stat st;
    fstat(fd, &st);
    int ntop = 0, moov_i = -1;
    int64_t off = 0;
    while (off + 8 <= st.st_size && ntop < 64) {
        uint8_t h[16];
        if (pread(fd, h, 16, off) < 8) break;
        int64_t sz = a_rd32(h);
        if (sz == 1) sz = (int64_t)a_rd64(h + 8);
        else if (sz == 0) sz = st.st_size - off;
        if (sz < 8 || off + sz > st.st_size) { snprintf(err, errcap, "%s: bad top-level box at %lld", src, (long long)off); return -1; }
        top[ntop].type = a_rd32(h + 4);
        top[ntop].off = off;
        top[ntop].size = sz;
        if (top[ntop].type == A_FOURCC('m','o','o','v')) moov_i = ntop;
        ntop++;
        off += sz;
    }
    if (moov_i < 0 || ntop == 0 || top[0].type != A_FOURCC('f','t','y','p')) { snprintf(err, errcap, "%s: no ftyp/moov", src); return -1; }
    size_t mlen = (size_t)top[moov_i].size;
    uint8_t *mbuf = malloc(mlen);
    if (!mbuf || pread(fd, mbuf, mlen, top[moov_i].off) != (ssize_t)mlen) { free(mbuf); snprintf(err, errcap, "%s: short read", src); return -1; }
    memset(root, 0, sizeof *root);
    int ok = a_box_parse(mbuf, mlen, root) && root->nk == 1;
    free(mbuf);
    if (!ok) { a_box_free(root); snprintf(err, errcap, "%s: cannot parse moov", src); return -1; }
    *ntop_out = ntop;
    *moov_i_out = moov_i;
    return 0;
}

static uint32_t a_trak_id(ABox *t) {
    ABox *tk = a_box_find(t, A_FOURCC('t','k','h','d'));
    return tk && tk->len >= 32 ? a_rd32(tk->raw + (tk->raw[8] == 1 ? 28 : 20)) : 0;
}

static uint32_t a_trak_handler(ABox *t) {
    ABox *md = a_box_find(t, A_FOURCC('m','d','i','a'));
    ABox *hd = md ? a_box_find(md, A_FOURCC('h','d','l','r')) : NULL;
    return hd && hd->len >= 20 ? a_rd32(hd->raw + 16) : 0;
}

/* Add `refs` (a run of reference boxes) to a trak's tref, creating it
 * before the mdia if there is none. */
static void a_add_tref(ABox *trak, const uint8_t *refs, size_t n) {
    ABox *old = a_box_find(trak, A_FOURCC('t','r','e','f'));
    if (old) {
        size_t len = old->len + n;
        uint8_t *b = malloc(len);
        memcpy(b, old->raw, old->len);
        memcpy(b + old->len, refs, n);
        a_be32(b, (uint32_t)len);
        free(old->raw);
        old->raw = b;
        old->len = len;
        return;
    }
    a_insert_before(trak, a_leaf(A_FOURCC('t','r','e','f'), refs, n), A_FOURCC('m','d','i','a'));
}

/* Append a box to moov/udta (a leaf here), creating the udta at the end of
 * the moov if there is none. A QuickTime udta may end in a 32-bit zero;
 * the box goes before it. */
static void a_add_udta(ABox *moov, const uint8_t *box, size_t n) {
    ABox *u = a_box_find(moov, A_FOURCC('u','d','t','a'));
    if (!u) { a_push(moov, a_leaf(A_FOURCC('u','d','t','a'), box, n)); return; }
    size_t at = u->len;
    if (u->len >= 12 && a_rd32(u->raw + u->len - 4) == 0) {
        /* a trailing terminator, unless the last 4 bytes belong to a box */
        size_t o = 8;
        while (o + 8 <= u->len) {
            uint32_t s = a_rd32(u->raw + o);
            if (s < 8 || o + s > u->len) break;
            o += s;
        }
        if (o == u->len - 4) at = u->len - 4;
    }
    size_t len = u->len + n;
    uint8_t *b = malloc(len);
    memcpy(b, u->raw, at);
    memcpy(b + at, box, n);
    memcpy(b + at + n, u->raw + at, u->len - at);
    a_be32(b, (uint32_t)len);
    free(u->raw);
    u->raw = b;
    u->len = len;
}

/* Add a tmcd track and/or a chapter track (plus chpl) to `src` (written by
 * AVAssetWriter, moov anywhere) and write the result to `dst`, moov first
 * when faststart. The new samples go in a small mdat at the end. 0 on
 * success. */
static int a_patch_moov(const char *src, const char *dst, const APatch *o, char *err, size_t errcap) {
    int fd = open(src, O_RDONLY);
    if (fd < 0) { snprintf(err, errcap, "cannot reopen %s: %s", src, strerror(errno)); return -1; }
    ATop top[64];
    int ntop = 0, moov_i = -1;
    ABox root;
    if (a_read_moov(fd, src, top, &ntop, &moov_i, &root, err, errcap) != 0) { close(fd); return -1; }
    ABox *moov = &root.kid[0];
    ABox *mvhd = a_box_find(moov, A_FOURCC('m','v','h','d'));
    if (!mvhd || mvhd->len < 108) { a_box_free(&root); close(fd); snprintf(err, errcap, "%s: no mvhd", src); return -1; }
    int v1 = mvhd->raw[8] == 1;
    uint32_t movie_ts = a_rd32(mvhd->raw + (v1 ? 28 : 20));
    uint32_t next_id = a_rd32(mvhd->raw + mvhd->len - 4);
    int video_i = -1;
    uint32_t max_id = 0;
    for (int i = 0; i < moov->nk; i++) {
        ABox *t = &moov->kid[i];
        if (t->type != A_FOURCC('t','r','a','k')) continue;
        uint32_t id = a_trak_id(t);
        if (id > max_id) max_id = id;
        if (video_i < 0 && a_trak_handler(t) == A_FOURCC('v','i','d','e')) video_i = i;
    }
    if (video_i < 0) { a_box_free(&root); close(fd); snprintf(err, errcap, "%s: no video track", src); return -1; }

    uint32_t id = next_id > max_id ? next_id : max_id + 1;
    uint32_t tc_id = 0, chap_id = 0;
    uint64_t media_dur = (uint64_t)o->frames * o->ticks;
    uint64_t movie_dur = (uint64_t)((__int128)media_dur * movie_ts / o->ts);
    uint8_t vrefs[24];
    size_t nvref = 0;
    /* new traks go before any udta; remember their types to find them again */
    if (o->has_tc) {
        tc_id = id++;
        uint32_t flags = (o->tc_drop ? 1u : 0u) | 2u;     /* drop frame, 24-hour max */
        a_insert_before(moov, a_tmcd_trak(o->mov, tc_id, movie_dur, o->ts, media_dur, o->ticks, o->tc_quanta, flags), A_FOURCC('u','d','t','a'));
        a_be32(vrefs + nvref, 12);
        a_be32(vrefs + nvref + 4, A_FOURCC('t','m','c','d'));
        a_be32(vrefs + nvref + 8, tc_id);
        nvref += 12;
    }
    if (o->nchap > 0) {
        chap_id = id++;
        a_insert_before(moov, a_chap_trak(o->mov, chap_id, movie_ts, o->ts, o->ticks, o->frames, o->chap, o->nchap), A_FOURCC('u','d','t','a'));
        a_be32(vrefs + nvref, 12);
        a_be32(vrefs + nvref + 4, A_FOURCC('c','h','a','p'));
        a_be32(vrefs + nvref + 8, chap_id);
        nvref += 12;
    }
    a_be32(mvhd->raw + mvhd->len - 4, id);      /* next_track_ID */
    /* the original traks keep their order: new ones were inserted after them (before udta) */
    int added = (o->has_tc ? 1 : 0) + (o->nchap > 0 ? 1 : 0);
    int first_new = -1;
    for (int i = 0; i < moov->nk; i++) {
        uint32_t tid = moov->kid[i].type == A_FOURCC('t','r','a','k') ? a_trak_id(&moov->kid[i]) : 0;
        if (tid && (tid == tc_id || tid == chap_id)) { first_new = i; break; }
    }
    for (int i = 0; i < moov->nk; i++) {
        ABox *t = &moov->kid[i];
        if (t->type != A_FOURCC('t','r','a','k') || (i >= first_new && i < first_new + added)) continue;
        uint32_t h = a_trak_handler(t);
        if (i == video_i) a_add_tref(t, vrefs, nvref);
        else if (chap_id && h == A_FOURCC('s','o','u','n')) {
            uint8_t r[12];
            a_be32(r, 12);
            a_be32(r + 4, A_FOURCC('c','h','a','p'));
            a_be32(r + 8, chap_id);
            a_add_tref(t, r, 12);
        }
    }
    if (o->nchap > 0 && o->chpl) {
        size_t cl;
        uint8_t *cb = a_chpl(o->chap, o->nchap, o->num, o->den, &cl);
        a_add_udta(moov, cb, cl);
        free(cb);
    }
    /* the new samples: [tc frame number][chapter titles] */
    size_t chap_bytes = 0;
    for (int i = 0; i < o->nchap; i++) chap_bytes += a_chap_sample(o->chap[i].title, NULL);
    size_t tail_len = 8 + (o->has_tc ? 4 : 0) + chap_bytes;
    uint8_t *tail = malloc(tail_len);
    a_be32(tail, (uint32_t)tail_len);
    a_be32(tail + 4, A_FOURCC('m','d','a','t'));
    size_t tp = 8;
    if (o->has_tc) { a_be32(tail + tp, (uint32_t)o->tc_frame); tp += 4; }
    for (int i = 0; i < o->nchap; i++) tp += a_chap_sample(o->chap[i].title, tail + tp);

    /* Layout: ftyp, [moov if faststart], the other top-level boxes in their
     * order, [moov otherwise], then the new mdat. Widen any stco whose moved
     * offsets no longer fit 32 bits (that grows the moov, so lay out
     * again), then move every chunk offset once. */
    ARegion reg[64];
    int nr = 0;
    size_t new_moov = 0;
    uint64_t tail_off = 0;
    for (int pass = 0; pass < 8; pass++) {
        new_moov = a_box_size(moov);
        int64_t pos = top[0].size + (o->faststart ? (int64_t)new_moov : 0);
        nr = 0;
        for (int i = 1; i < ntop; i++) {
            if (i == moov_i) continue;
            reg[nr].old_off = top[i].off;
            reg[nr].size = top[i].size;
            reg[nr].new_off = pos;
            pos += top[i].size;
            nr++;
        }
        if (!o->faststart) pos += (int64_t)new_moov;
        tail_off = (uint64_t)pos;
        int widened = 0;
        for (int i = 0; i < moov->nk; i++)
            if (moov->kid[i].type == A_FOURCC('t','r','a','k') && !(i >= first_new && i < first_new + added))
                widened += a_widen(&moov->kid[i], reg, nr);
        if (!widened) break;
    }
    int ok = 1;
    for (int i = 0; i < moov->nk; i++)
        if (moov->kid[i].type == A_FOURCC('t','r','a','k') && !(i >= first_new && i < first_new + added) &&
            !a_patch_offsets(&moov->kid[i], reg, nr)) ok = 0;
    if (!ok || a_box_size(moov) != new_moov) {
        free(tail);
        a_box_free(&root);
        close(fd);
        snprintf(err, errcap, "%s: a chunk offset points outside the media data", src);
        return -1;
    }
    /* the new traks' chunk offsets */
    for (int i = first_new; added > 0 && i < first_new + added; i++) {
        ABox *t = &moov->kid[i];
        ABox *md = a_box_find(t, A_FOURCC('m','d','i','a'));
        ABox *mi = a_box_find(md, A_FOURCC('m','i','n','f'));
        ABox *sb = a_box_find(mi, A_FOURCC('s','t','b','l'));
        ABox *co = a_box_find(sb, A_FOURCC('c','o','6','4'));
        uint64_t at = tail_off + 8;
        if (a_trak_id(t) == chap_id) at += o->has_tc ? 4 : 0;
        a_be64(co->raw + 16, at);
    }

    uint8_t *mo = malloc(new_moov);
    size_t mp = 0;
    a_box_write(moov, mo, &mp);
    a_box_free(&root);

    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { free(tail); free(mo); close(fd); snprintf(err, errcap, "cannot create %s: %s", dst, strerror(errno)); return -1; }
    size_t bufsz = 16u << 20;
    uint8_t *buf = malloc(bufsz);
    int wok = 1;
    {
        ssize_t r = pread(fd, buf, (size_t)top[0].size, 0);
        wok = r == top[0].size && write(out, buf, (size_t)r) == r;
    }
    if (wok && o->faststart) wok = write(out, mo, new_moov) == (ssize_t)new_moov;
    for (int i = 1; i < ntop && wok; i++) {
        if (i == moov_i) continue;
        int64_t left = top[i].size, at = top[i].off;
        while (left > 0 && wok) {
            size_t n = left > (int64_t)bufsz ? bufsz : (size_t)left;
            ssize_t r = pread(fd, buf, n, at);
            if (r <= 0) { wok = 0; break; }
            wok = write(out, buf, (size_t)r) == r;
            left -= r;
            at += r;
        }
    }
    if (wok && !o->faststart) wok = write(out, mo, new_moov) == (ssize_t)new_moov;
    if (wok) wok = write(out, tail, tail_len) == (ssize_t)tail_len;
    free(buf);
    free(mo);
    free(tail);
    close(fd);
    if (close(out) != 0) wok = 0;
    if (!wok) { unlink(dst); snprintf(err, errcap, "writing %s failed: %s", dst, strerror(errno)); return -1; }
    return 0;
}

/* ======================================================================
   Mux
   ====================================================================== */

/* Where the audio comes from: a WAV file (mmap), a media file's first audio
 * track decoded to float PCM (AVAssetReader; re-encoded by the writer), or
 * that track's compressed samples passed through. */
enum { A_AUDIO_WAV = 0, A_AUDIO_DECODE = 1, A_AUDIO_COPY = 2 };

typedef struct AMux {
    char      path[4096];
    char      tmp[4200];
    int       mov;
    int32_t   num, den, ts, ticks;
    AVAssetWriter      *writer;
    AVAssetWriterInput *video, *audio;
    CMFormatDescriptionRef vfmt;
    CMAudioFormatDescriptionRef afmt;
    int       started;
    int64_t   frames;
    int32_t   delay;            /* DTS delay in frames (0 without reordering) */
    int64_t   video_bytes;
    int       has_audio, aac;
    int       audio_kbps;
    /* audio source */
    int       akind;            /* A_AUDIO_* */
    int32_t   arate, ach;       /* sample rate, channels */
    int64_t   aframes;          /* source length in sample frames (decode/copy: from the track duration) */
    WMediaWav wav;
    AVURLAsset *asrc;
    AVAssetReader *areader;
    AVAssetReaderTrackOutput *aout;
    CMFormatDescriptionRef asrc_fmt;
    int64_t   astart;           /* decode/copy: first source sample frame read */
    float    *abuf;             /* decode: leftover PCM */
    size_t    abuf_n, abuf_pos, abuf_cap;
    int       aeof;
    CMSampleBufferRef apend;    /* copy: next compressed buffer, not yet appended */
    int64_t   audio_fed;
    int64_t   total_frames;     /* the caller's promised frame count, or 0 */
    int       audio_done;       /* markAsFinished sent */
    int       has_tc, tc_drop, tc_quanta;
    int64_t   tc_start;
    int       faststart;
    uint32_t  fourcc;
    int32_t   width, height;
    AChapter *chap;             /* chapters (title, first frame), ascending */
    int       nchap;
    int       chpl;             /* also write Nero chpl (MP4; default on) */
} AMux;

static void a_mux_free(AMux *m) {
    if (m->writer) {
        if (m->writer.status == AVAssetWriterStatusWriting) [m->writer cancelWriting];
        [m->writer release];
    }
    if (m->video) [m->video release];
    if (m->audio) [m->audio release];
    if (m->vfmt) CFRelease(m->vfmt);
    if (m->afmt) CFRelease(m->afmt);
    if (m->has_audio && m->akind == A_AUDIO_WAV) w_media_wav_close(&m->wav);
    if (m->areader) { [m->areader cancelReading]; [m->areader release]; }
    if (m->aout) [m->aout release];
    if (m->asrc) [m->asrc release];
    if (m->asrc_fmt) CFRelease(m->asrc_fmt);
    if (m->apend) CFRelease(m->apend);
    free(m->abuf);
    for (int i = 0; i < m->nchap; i++) free(m->chap[i].title);
    free(m->chap);
    free(m);
}

__attribute__((noreturn))
static void a_mux_fail(AMux *m, const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    char werr[512] = "";
    if (m && m->writer && m->writer.error)
        snprintf(werr, sizeof werr, " (AVAssetWriter: %s)", m->writer.error.localizedDescription.UTF8String ?: "?");
    w_media_raise("Mux: %s%s", buf, werr);
}

/* What a mux is opened with. */
typedef struct AMuxOpts {
    const char *path, *format;          /* format "mp4" / "mov", or NULL: from the extension */
    int32_t     num, den;
    const char *audio;                  /* WAV or media file path, or NULL */
    const char *audio_codec;            /* "aac", "pcm", "copy", or NULL (the format's default) */
    int         audio_kbps;             /* 0: 320 stereo, 192 mono */
    int64_t     audio_start_frame;      /* movie audio: start at this video frame's first sample */
    int         has_tc, tc_drop, tc_quanta;
    int64_t     tc_frame;
    int         faststart;
    int64_t     frames;                 /* promised frame count, or 0 */
} AMuxOpts;

static int a_is_wav(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    uint8_t h[12];
    ssize_t n = read(fd, h, 12);
    close(fd);
    return n == 12 && (!memcmp(h, "RIFF", 4) || !memcmp(h, "RF64", 4)) && !memcmp(h + 8, "WAVE", 4);
}

/* Open a media file's first audio track as the source (decode or copy). */
static int64_t a_audio_for(AMux *m, int64_t frames);

static int a_audio_open_asset(AMux *m, const char *path, int copy, int64_t start_frame, char *err, size_t cap) {
    NSString *p = [NSString stringWithUTF8String:path];
    m->asrc = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:p] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    NSArray *at = [m->asrc tracksWithMediaType:AVMediaTypeAudio];
    if (!at.count) { snprintf(err, cap, "%s has no audio track", path); return -1; }
    AVAssetTrack *t = at[0];
    CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
    const AudioStreamBasicDescription *asbd = fd ? CMAudioFormatDescriptionGetStreamBasicDescription(fd) : NULL;
    if (!asbd || asbd->mSampleRate <= 0 || asbd->mChannelsPerFrame == 0) { snprintf(err, cap, "%s: cannot read the audio format", path); return -1; }
    m->arate = (int32_t)asbd->mSampleRate;
    m->ach = (int32_t)asbd->mChannelsPerFrame;
    m->asrc_fmt = fd;
    CFRetain(fd);
    int64_t start = a_audio_for(m, start_frame);
    CMTimeRange tr = t.timeRange;
    m->aframes = (int64_t)llround(CMTimeGetSeconds(CMTimeRangeGetEnd(tr)) * m->arate) - start;
    if (m->aframes < 0) m->aframes = 0;
    m->astart = start;
    NSError *e = nil;
    m->areader = [[AVAssetReader alloc] initWithAsset:m->asrc error:&e];
    if (!m->areader) { snprintf(err, cap, "%s: %s", path, e.localizedDescription.UTF8String ?: "cannot read"); return -1; }
    if (start > 0) m->areader.timeRange = CMTimeRangeMake(CMTimeMake(start, m->arate), kCMTimePositiveInfinity);
    NSDictionary *pcm = copy ? nil : @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32,
                                       AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
    m->aout = [[AVAssetReaderTrackOutput alloc] initWithTrack:t outputSettings:pcm];
    m->aout.alwaysCopiesSampleData = NO;
    [m->areader addOutput:m->aout];
    if (![m->areader startReading]) {
        snprintf(err, cap, "%s: cannot start reading the audio: %s", path, m->areader.error.localizedDescription.UTF8String ?: "?");
        return -1;
    }
    m->akind = copy ? A_AUDIO_COPY : A_AUDIO_DECODE;
    return 0;
}

/* Open a mux; NULL with a message (nothing left behind). */
static AMux *a_mux_open(const AMuxOpts *o, char *err, size_t cap) {
    @autoreleasepool {
        AMux *m = calloc(1, sizeof *m);
        if (!m) { snprintf(err, cap, "out of memory"); return NULL; }
        if (!o->path || !o->path[0]) { free(m); snprintf(err, cap, "path must be a string"); return NULL; }
        snprintf(m->path, sizeof m->path, "%s", o->path);
        char fmt[16];
        snprintf(fmt, sizeof fmt, "%s", o->format ? o->format : "");
        if (!fmt[0]) {
            const char *dot = strrchr(m->path, '.');
            snprintf(fmt, sizeof fmt, "%s", dot && !strcasecmp(dot, ".mov") ? "mov" : "mp4");
        }
        if (!strcasecmp(fmt, "mov")) m->mov = 1;
        else if (strcasecmp(fmt, "mp4")) { free(m); snprintf(err, cap, "format must be :mp4 or :mov (got '%s')", fmt); return NULL; }
        m->num = o->num;
        m->den = o->den;
        if (m->num <= 0 || m->den <= 0) { free(m); snprintf(err, cap, "rate must be a positive [num, den]"); return NULL; }
        /* Track timescale: num (x1000 for small integer rates, so 24 fps is
         * 24000 with 1000 ticks a frame), always an exact multiple. */
        int64_t ts = m->num < 1000 ? (int64_t)m->num * 1000 : m->num;
        m->ts = (int32_t)ts;
        m->ticks = (int32_t)((int64_t)m->den * ts / m->num);
        m->faststart = o->faststart;
        m->total_frames = o->frames > 0 ? o->frames : 0;
        if (o->has_tc) {
            m->has_tc = 1;
            m->tc_start = o->tc_frame;
            m->tc_drop = o->tc_drop;
            m->tc_quanta = o->tc_quanta > 0 ? o->tc_quanta : (int)((m->num + m->den / 2) / m->den);
        }
        if (o->audio && o->audio[0]) {
            char ac[16];
            snprintf(ac, sizeof ac, "%s", o->audio_codec ? o->audio_codec : "");
            int copy = !strcasecmp(ac, "copy") || !strcasecmp(ac, "passthrough");
            if (a_is_wav(o->audio)) {
                if (copy) { free(m); snprintf(err, cap, "audio_codec: :copy passes a movie's audio through; %s is a WAV", o->audio); return NULL; }
                if (w_media_wav_open(o->audio, &m->wav, err, cap) != 0) { free(m); return NULL; }
                m->akind = A_AUDIO_WAV;
                m->arate = m->wav.rate;
                m->ach = m->wav.channels;
                m->aframes = m->wav.frames;
                m->has_audio = 1;
            } else {
                m->has_audio = 1;
                m->akind = copy ? A_AUDIO_COPY : A_AUDIO_DECODE;
                if (copy && o->audio_start_frame > 0) { a_mux_free(m); snprintf(err, cap, "audio :copy starts at frame 0 only (re-encode a range)"); return NULL; }
                if (a_audio_open_asset(m, o->audio, copy, o->audio_start_frame, err, cap) != 0) { a_mux_free(m); return NULL; }
            }
            if (!copy) {
                if (!ac[0]) snprintf(ac, sizeof ac, "%s", m->mov ? "pcm" : "aac");
                if (!strcasecmp(ac, "aac")) m->aac = 1;
                else if (strcasecmp(ac, "pcm")) { a_mux_free(m); snprintf(err, cap, "audio codec must be :aac, :pcm or :copy (got '%s')", ac); return NULL; }
                if (!m->aac && !m->mov) { a_mux_free(m); snprintf(err, cap, "PCM audio needs a .mov (MP4 carries AAC)"); return NULL; }
            }
            m->audio_kbps = o->audio_kbps > 0 ? o->audio_kbps : (m->ach >= 2 ? 320 : 192);
        }
        NSString *target = [NSString stringWithUTF8String:m->path];
        /* a timecode (and chapters, set later) mean a moov rewrite after
         * AVAssetWriter: write a temporary file and patch it into place */
        snprintf(m->tmp, sizeof m->tmp, "%s.tw-mux-%d.%s", m->path, (int)getpid(), m->mov ? "mov" : "mp4");
        m->chpl = !m->mov;
        if (m->has_tc) target = [NSString stringWithUTF8String:m->tmp];
        [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
        NSError *e = nil;
        m->writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:target]
                                              fileType:(m->mov ? AVFileTypeQuickTimeMovie : AVFileTypeMPEG4)
                                                 error:&e];
        if (!m->writer) {
            snprintf(err, cap, "cannot create %s: %s", m->path, e.localizedDescription.UTF8String ?: "?");
            a_mux_free(m);
            return NULL;
        }
        m->writer.movieTimeScale = m->ts;
        /* With a timecode the moov is rewritten afterwards anyway, faststart included. */
        m->writer.shouldOptimizeForNetworkUse = m->faststart && !m->has_tc;
        return m;
    }
}

/* w_media_mux_new(path, format, num, den, audio_path, audio_codec,
 * audio_kbps, tc_start_frame, tc_drop, tc_quanta, faststart, frames) */
WValue w_media_mux_new(WValue pathv, WValue fmtv, WValue numv, WValue denv, WValue audiov, WValue acodecv,
                       WValue akbpsv, WValue tcv, WValue dropv, WValue quantav, WValue fastv, WValue framesv) {
    char path[4096], fmt[16], ac[16], apath[4096];
    AMuxOpts o;
    memset(&o, 0, sizeof o);
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("Mux: path must be a string");
    o.path = path;
    w_media_str(fmtv, fmt, sizeof fmt);
    o.format = fmt[0] ? fmt : NULL;
    o.num = (int32_t)w_media_num(numv, 24, "rate numerator");
    o.den = (int32_t)w_media_num(denv, 1, "rate denominator");
    if (w_media_str(audiov, apath, sizeof apath) && apath[0]) o.audio = apath;
    w_media_str(acodecv, ac, sizeof ac);
    o.audio_codec = ac[0] ? ac : NULL;
    o.audio_kbps = (int)w_media_num(akbpsv, 0, "audio bitrate");
    if (tcv != W_NIL) {
        o.has_tc = 1;
        o.tc_frame = (int64_t)w_media_num(tcv, 0, "timecode start");
        o.tc_drop = dropv > 1;
        o.tc_quanta = (int)w_media_num(quantav, 0, "timecode quanta");
    }
    o.faststart = fastv == W_NIL ? 1 : fastv > 1;
    o.frames = (int64_t)w_media_num(framesv, 0, "frames");
    char err[512];
    AMux *m = a_mux_open(&o, err, sizeof err);
    if (!m) w_media_raise("Mux: %s", err);
    return w_int(w_media_handle_new(m, W_MEDIA_KIND_MUX));
}

static int a_fmt_compatible(CMFormatDescriptionRef a, CMFormatDescriptionRef b) {
    if (CMFormatDescriptionEqual(a, b)) return 1;
    if (CMFormatDescriptionGetMediaSubType(a) != CMFormatDescriptionGetMediaSubType(b)) return 0;
    CMVideoDimensions da = CMVideoFormatDescriptionGetDimensions(a), db = CMVideoFormatDescriptionGetDimensions(b);
    if (da.width != db.width || da.height != db.height) return 0;
    CFDictionaryRef ea = CMFormatDescriptionGetExtensions(a), eb = CMFormatDescriptionGetExtensions(b);
    CFStringRef keys[] = {kCMFormatDescriptionExtension_ColorPrimaries, kCMFormatDescriptionExtension_TransferFunction,
                          kCMFormatDescriptionExtension_YCbCrMatrix, kCMFormatDescriptionExtension_FullRangeVideo,
                          kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++) {
        CFTypeRef x = ea ? CFDictionaryGetValue(ea, keys[i]) : NULL, y = eb ? CFDictionaryGetValue(eb, keys[i]) : NULL;
        if ((x == NULL) != (y == NULL)) return 0;
        if (x && !CFEqual(x, y)) return 0;
    }
    return 1;
}

static AudioChannelLayoutTag a_layout_tag(int ch) {
    switch (ch) {
        case 1: return kAudioChannelLayoutTag_Mono;
        case 2: return kAudioChannelLayoutTag_Stereo;
        case 6: return kAudioChannelLayoutTag_MPEG_5_1_A;
        default: return kAudioChannelLayoutTag_DiscreteInOrder | (AudioChannelLayoutTag)ch;
    }
}

static void a_mux_start(AMux *m, WMediaSegment *s) {
    m->vfmt = (CMFormatDescriptionRef)s->format;
    CFRetain(m->vfmt);
    m->fourcc = s->fourcc;
    m->width = s->width;
    m->height = s->height;
    /* Reserve the DTS delay up front: later segments may reorder deeper
     * than the first (a 1-frame segment needs none). */
    m->delay = s->reorder;
    if ((s->flags & W_MEDIA_SEG_REORDER) && m->delay < W_MEDIA_REORDER_DELAY) m->delay = W_MEDIA_REORDER_DELAY;
    m->video = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:m->vfmt];
    m->video.expectsMediaDataInRealTime = NO;
    m->video.mediaTimeScale = m->ts;
    if (![m->writer canAddInput:m->video]) a_mux_fail(m, "AVAssetWriter cannot take this video format");
    [m->writer addInput:m->video];
    if (m->has_audio && m->akind == A_AUDIO_COPY) {
        m->audio = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:nil sourceFormatHint:m->asrc_fmt];
        m->audio.expectsMediaDataInRealTime = NO;
        if (![m->writer canAddInput:m->audio]) a_mux_fail(m, "AVAssetWriter cannot pass this audio through into a %s", m->mov ? "MOV" : "MP4");
        [m->writer addInput:m->audio];
    } else if (m->has_audio) {
        AudioStreamBasicDescription asbd;
        memset(&asbd, 0, sizeof asbd);
        asbd.mSampleRate = m->arate;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        asbd.mChannelsPerFrame = (UInt32)m->ach;
        asbd.mBitsPerChannel = 32;
        asbd.mBytesPerFrame = 4 * (UInt32)m->ach;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        AudioChannelLayout layout;
        memset(&layout, 0, sizeof layout);
        layout.mChannelLayoutTag = a_layout_tag(m->ach);
        OSStatus st = CMAudioFormatDescriptionCreate(NULL, &asbd, sizeof layout, &layout, 0, NULL, NULL, &m->afmt);
        if (st != noErr) a_mux_fail(m, "cannot describe the audio (OSStatus %d)", (int)st);
        NSData *ld = [NSData dataWithBytes:&layout length:sizeof layout];
        NSDictionary *settings;
        if (m->aac) {
            settings = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @(m->arate),
                         AVNumberOfChannelsKey: @(m->ach), AVEncoderBitRateKey: @(m->audio_kbps * 1000),
                         AVChannelLayoutKey: ld};
        } else {
            settings = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(m->arate),
                         AVNumberOfChannelsKey: @(m->ach), AVLinearPCMBitDepthKey: @24,
                         AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsBigEndianKey: @NO,
                         AVLinearPCMIsNonInterleaved: @NO, AVChannelLayoutKey: ld};
        }
        m->audio = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:settings sourceFormatHint:m->afmt];
        m->audio.expectsMediaDataInRealTime = NO;
        if (![m->writer canAddInput:m->audio]) a_mux_fail(m, "AVAssetWriter cannot take %s audio at %d Hz x %d", m->aac ? "AAC" : "PCM", (int)m->arate, (int)m->ach);
        [m->writer addInput:m->audio];
    }
    if (![m->writer startWriting]) a_mux_fail(m, "cannot start writing");
    [m->writer startSessionAtSourceTime:kCMTimeZero];
    m->started = 1;
}

/* Audio frames that belong to the first `frames` video frames (rounded). */
static int64_t a_audio_for(AMux *m, int64_t frames) {
    __int128 a = (__int128)frames * m->arate * m->den;
    return (int64_t)((a * 2 + m->num) / (2 * (__int128)m->num));
}

/* The most audio the mux may feed when `video_frames` frames are written:
 * the exact total when the caller promised a frame count, else the source's
 * own samples, or silence only as far as the video already reaches. */
static int64_t a_audio_cap(AMux *m, int64_t video_frames) {
    if (m->total_frames > 0) return a_audio_for(m, m->total_frames);
    int64_t need = a_audio_for(m, video_frames);
    return m->aframes > need ? m->aframes : need;
}

/* Decoded source: sample frames [first, first + n) as float32 (sequential
 * reads only), zeros past the end. */
static void a_decode_read(AMux *m, int64_t first, int64_t n, float *out) {
    int ch = m->ach;
    (void)first;
    while (n > 0) {
        if (m->abuf_pos < m->abuf_n) {
            size_t k = m->abuf_n - m->abuf_pos;
            if ((int64_t)k > n) k = (size_t)n;
            memcpy(out, m->abuf + m->abuf_pos * (size_t)ch, k * (size_t)ch * sizeof(float));
            out += k * (size_t)ch;
            m->abuf_pos += k;
            n -= (int64_t)k;
            continue;
        }
        CMSampleBufferRef sb = m->aeof ? NULL : [m->aout copyNextSampleBuffer];
        if (!sb) {
            m->aeof = 1;
            memset(out, 0, (size_t)n * (size_t)ch * sizeof(float));
            return;
        }
        CMItemCount k = CMSampleBufferGetNumSamples(sb);
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
        size_t len = bb ? CMBlockBufferGetDataLength(bb) : 0;
        size_t want = (size_t)k * (size_t)ch * sizeof(float);
        if (len < want) want = len;
        if (m->abuf_cap < (size_t)k * (size_t)ch) {
            m->abuf_cap = (size_t)k * (size_t)ch;
            m->abuf = realloc(m->abuf, m->abuf_cap * sizeof(float));
        }
        if (bb) CMBlockBufferCopyDataBytes(bb, 0, want, m->abuf);
        m->abuf_n = want / ((size_t)ch * sizeof(float));
        m->abuf_pos = 0;
        CFRelease(sb);
    }
}

/* Copy source: the sample frame where a compressed buffer starts. */
static int64_t a_copy_pos(AMux *m, CMSampleBufferRef sb) {
    CMTime p = CMSampleBufferGetPresentationTimeStamp(sb);
    return (int64_t)llround(CMTimeGetSeconds(p) * m->arate) - m->astart;
}

/* Feed audio up to `upto` sample frames while the input takes it. Returns 1
 * if it reached upto. */
static int a_feed_audio(AMux *m, int64_t upto) {
    if (!m->has_audio || m->audio_done) return 1;
    if (m->akind == A_AUDIO_COPY) {
        /* whole compressed buffers, in order, while they start before upto */
        while (m->audio_fed < upto) {
            if (!m->apend) {
                m->apend = m->aeof ? NULL : [m->aout copyNextSampleBuffer];
                if (!m->apend) { m->aeof = 1; m->audio_fed = upto > m->audio_fed ? upto : m->audio_fed; return 1; }
            }
            if (a_copy_pos(m, m->apend) >= upto) { m->audio_fed = upto; return 1; }
            if (!m->audio.readyForMoreMediaData) return 0;
            int64_t pos = a_copy_pos(m, m->apend);
            CMTime d = CMSampleBufferGetDuration(m->apend);
            int64_t dn = CMTIME_IS_NUMERIC(d) ? (int64_t)llround(CMTimeGetSeconds(d) * m->arate) : 0;
            if (m->astart > 0) {
                /* shift to the output timeline */
                CMSampleBufferRef sh = NULL;
                CMItemCount nt = 0;
                CMSampleBufferGetSampleTimingInfoArray(m->apend, 0, NULL, &nt);
                CMSampleTimingInfo *ti = calloc((size_t)(nt ? nt : 1), sizeof *ti);
                CMSampleBufferGetSampleTimingInfoArray(m->apend, nt, ti, &nt);
                CMTime off = CMTimeMake(m->astart, m->arate);
                for (CMItemCount i = 0; i < nt; i++) {
                    if (CMTIME_IS_VALID(ti[i].presentationTimeStamp)) ti[i].presentationTimeStamp = CMTimeSubtract(ti[i].presentationTimeStamp, off);
                    if (CMTIME_IS_VALID(ti[i].decodeTimeStamp)) ti[i].decodeTimeStamp = CMTimeSubtract(ti[i].decodeTimeStamp, off);
                }
                CMSampleBufferCreateCopyWithNewTiming(NULL, m->apend, nt, ti, &sh);
                free(ti);
                if (sh) { CFRelease(m->apend); m->apend = sh; }
            }
            BOOL ok = [m->audio appendSampleBuffer:m->apend];
            CFRelease(m->apend);
            m->apend = NULL;
            if (!ok) a_mux_fail(m, "appending passthrough audio at sample %lld failed", (long long)pos);
            m->audio_fed = pos + dn;
        }
        return 1;
    }
    int ch = m->ach;
    while (m->audio_fed < upto) {
        if (!m->audio.readyForMoreMediaData) return 0;
        int64_t n = upto - m->audio_fed;
        if (n > 4800) n = 4800;
        size_t bytes = (size_t)n * 4 * (size_t)ch;
        CMBlockBufferRef bb = NULL;
        OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, kCFAllocatorDefault, NULL, 0, bytes, kCMBlockBufferAssureMemoryNowFlag, &bb);
        if (st != noErr) a_mux_fail(m, "audio buffer (OSStatus %d)", (int)st);
        void *dst = NULL;
        CMBlockBufferGetDataPointer(bb, 0, NULL, NULL, (char **)&dst);
        if (m->akind == A_AUDIO_WAV) w_media_wav_read_f32(&m->wav, m->audio_fed, n, dst);
        else a_decode_read(m, m->audio_fed, n, dst);
        CMSampleBufferRef sb = NULL;
        st = CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, m->afmt, (CMItemCount)n, CMTimeMake(m->audio_fed, m->arate), NULL, &sb);
        CFRelease(bb);
        if (st != noErr) a_mux_fail(m, "audio sample buffer (OSStatus %d)", (int)st);
        BOOL ok = [m->audio appendSampleBuffer:sb];
        CFRelease(sb);
        if (!ok) a_mux_fail(m, "appending audio at frame %lld failed", (long long)m->audio_fed);
        m->audio_fed += n;
    }
    return 1;
}

/* Wait until the video input takes a sample. AVAssetWriter interleaves in
 * about one-second chunks and holds the video back until the audio is ahead
 * of it, so audio leads by a second and, while the video is still held,
 * grows in 250 ms steps up to the cap. */
static void a_wait_video(AMux *m, int64_t frame) {
    int spins = 0;
    int64_t lead = m->has_audio ? m->arate : 0;
    a_feed_audio(m, MIN(a_audio_for(m, frame + 1) + lead, a_audio_cap(m, frame + 1)));
    while (!m->video.readyForMoreMediaData) {
        if (m->has_audio && !m->audio_done && m->total_frames > 0 && m->audio_fed >= a_audio_for(m, m->total_frames)) {
            /* All the promised audio is in: say so, or the writer keeps
             * waiting for audio past the end. */
            [m->audio markAsFinished];
            m->audio_done = 1;
        }
        if (m->has_audio && !m->audio_done && m->audio.readyForMoreMediaData) {
            int64_t cap = m->total_frames > 0 ? a_audio_cap(m, frame + 1) : MAX(a_audio_cap(m, frame + 1), m->audio_fed + m->arate / 4);
            a_feed_audio(m, MIN(m->audio_fed + m->arate / 4, cap));
        }
        if (m->writer.status != AVAssetWriterStatusWriting) a_mux_fail(m, "the writer stopped");
        usleep(200);
        if (++spins > 100000)
            a_mux_fail(m, "the writer stalled at frame %lld (video input not ready for 20 s; audio fed %lld, audio ready %d)",
                       (long long)frame, (long long)m->audio_fed, m->has_audio ? (int)m->audio.readyForMoreMediaData : -1);
    }
}

/* w_media_mux_set(mux, key, value): "chapters" [[title, first frame], ...]
 * (ascending, the first may be after frame 0), "chpl" true/false (Nero
 * chapters in an MP4's udta as well; default true for MP4). */
static void a_mux_set_chapters(AMux *m, const AChapter *src, int n) {
    for (int i = 0; i < m->nchap; i++) free(m->chap[i].title);
    free(m->chap);
    m->chap = NULL;
    m->nchap = 0;
    if (n <= 0) return;
    m->chap = calloc((size_t)n, sizeof *m->chap);
    for (int i = 0; i < n; i++) {
        m->chap[i].title = strdup(src[i].title);
        m->chap[i].frame = src[i].frame;
    }
    m->nchap = n;
}

/* Parse [[title, frame], ...]; raises on a bad list. Caller frees titles. */
static AChapter *a_chapters_from(WValue v, int *nout, const char *what) {
    *nout = 0;
    if (v == W_NIL) return NULL;
    if (!w_is_array(v)) w_media_raise("%s: chapters must be an array of [title, frame]", what);
    int64_t n = w_as_array(v)->size;
    if (n > 65535) w_media_raise("%s: too many chapters (%lld)", what, (long long)n);
    AChapter *ch = calloc((size_t)(n ? n : 1), sizeof *ch);
    for (int64_t i = 0; i < n; i++) {
        WValue e = w_array_get(v, w_int(i));
        if (!w_is_array(e) || w_as_array(e)->size < 2) {
            for (int64_t j = 0; j < i; j++) free(ch[j].title);
            free(ch);
            w_media_raise("%s: chapter %lld must be [title, frame]", what, (long long)i);
        }
        char title[2048];
        w_media_str(w_array_get(e, w_int(0)), title, sizeof title);
        int64_t f = (int64_t)w_media_num(w_array_get(e, w_int(1)), -1, "chapter frame");
        if (f < 0 || (i > 0 && f <= ch[i - 1].frame)) {
            for (int64_t j = 0; j < i; j++) free(ch[j].title);
            free(ch);
            w_media_raise("%s: chapter %lld ('%s') starts at frame %lld: chapters need distinct, ascending frames >= 0", what, (long long)i, title, (long long)f);
        }
        ch[i].title = strdup(title);
        ch[i].frame = f;
    }
    *nout = (int)n;
    return ch;
}

static void a_chapters_free(AChapter *ch, int n) {
    for (int i = 0; i < n; i++) free(ch[i].title);
    free(ch);
}

WValue w_media_mux_set(WValue mv, WValue keyv, WValue v) {
    AMux *m = w_media_handle_get(mv, W_MEDIA_KIND_MUX, "Mux#set");
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "chpl")) {
        m->chpl = v > 1;
        return W_NIL;
    }
    if (!strcmp(k, "cancel")) {
        /* abandon the file: stop the writer, delete what it wrote */
        char path[4096], tmp[4200];
        snprintf(path, sizeof path, "%s", m->path);
        snprintf(tmp, sizeof tmp, "%s", m->tmp);
        int started = m->started;
        w_media_handle_drop(mv, W_MEDIA_KIND_MUX);
        a_mux_free(m);
        if (started) unlink(path);
        unlink(tmp);
        return W_TRUE;
    }
    if (!strcmp(k, "chapters")) {
        int n = 0;
        AChapter *ch = a_chapters_from(v, &n, "Mux");
        a_mux_set_chapters(m, ch, n);
        a_chapters_free(ch, n);
        return w_int(n);
    }
    w_media_raise("Mux#set: unknown key '%s'", k);
}

/* Append one finished segment. Returns the frames written so far. */
static int64_t a_mux_append(AMux *m, WMediaSegment *s) {
    if (s->n == 0 || !s->format) a_mux_fail(m, "empty segment");
    if (s->rate_num != m->num || s->rate_den != m->den)
        a_mux_fail(m, "segment rate %d/%d differs from the mux rate %d/%d", (int)s->rate_num, (int)s->rate_den, (int)m->num, (int)m->den);
    if (!s->s[0].sync) a_mux_fail(m, "segment does not start with a sync sample (IDR)");
    if (!m->started) a_mux_start(m, s);
    else if (!a_fmt_compatible(m->vfmt, (CMFormatDescriptionRef)s->format))
        a_mux_fail(m, "segment at frame %lld was encoded with different settings (codec, size, colour or parameter sets differ from the first segment); re-encode it with the master's settings", (long long)m->frames);
    if (s->reorder > m->delay)
        a_mux_fail(m, "segment at frame %lld needs a DTS delay of %d frames, more than the %d this file reserved (from its first segment)", (long long)m->frames, (int)s->reorder, (int)m->delay);
    /* decode-order sorted PTS, for DTS = sorted - delay */
    int32_t *sorted = malloc(sizeof(int32_t) * (size_t)s->n);
    for (int i = 0; i < s->n; i++) sorted[i] = s->s[i].pts;
    for (int i = 1; i < s->n; i++) {
        int32_t v = sorted[i];
        int j = i - 1;
        while (j >= 0 && sorted[j] > v) { sorted[j + 1] = sorted[j]; j--; }
        sorted[j + 1] = v;
    }
    for (int i = 0; i < s->n; i++) {
        if (sorted[i] != i) { free(sorted); a_mux_fail(m, "segment frames are not 0..%d", (int)s->n - 1); }
    }
    for (int i = 0; i < s->n; i++) {
        @autoreleasepool {
            const WMediaSample *x = &s->s[i];
            CMBlockBufferRef bb = NULL;
            OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, x->size, kCFAllocatorDefault, NULL, 0, x->size, kCMBlockBufferAssureMemoryNowFlag, &bb);
            if (st == noErr) st = CMBlockBufferReplaceDataBytes(s->data + x->offset, bb, 0, x->size);
            if (st != noErr) { free(sorted); a_mux_fail(m, "sample buffer (OSStatus %d)", (int)st); }
            int64_t f = m->frames + x->pts;
            CMSampleTimingInfo ti;
            ti.duration = CMTimeMake(m->ticks, m->ts);
            ti.presentationTimeStamp = CMTimeMake(f * m->ticks, m->ts);
            ti.decodeTimeStamp = m->delay ? CMTimeMake((m->frames + sorted[i] - m->delay) * m->ticks, m->ts) : kCMTimeInvalid;
            size_t sz = x->size;
            CMSampleBufferRef sb = NULL;
            st = CMSampleBufferCreateReady(NULL, bb, m->vfmt, 1, 1, &ti, 1, &sz, &sb);
            CFRelease(bb);
            if (st != noErr) { free(sorted); a_mux_fail(m, "sample (OSStatus %d)", (int)st); }
            CFArrayRef at = CMSampleBufferGetSampleAttachmentsArray(sb, true);
            if (at && CFArrayGetCount(at) > 0) {
                CFMutableDictionaryRef d = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(at, 0);
                CFDictionarySetValue(d, kCMSampleAttachmentKey_NotSync, x->sync ? kCFBooleanFalse : kCFBooleanTrue);
                CFDictionarySetValue(d, kCMSampleAttachmentKey_DependsOnOthers, x->sync ? kCFBooleanFalse : kCFBooleanTrue);
            }
            a_wait_video(m, f);
            BOOL ok = [m->video appendSampleBuffer:sb];
            CFRelease(sb);
            if (!ok) { free(sorted); a_mux_fail(m, "appending video frame %lld failed", (long long)f); }
            m->video_bytes += x->size;
        }
    }
    free(sorted);
    m->frames += s->n;
    return m->frames;
}

/* w_media_chapterize(src, dst, chapters, [num, den]) -> chapters written.
 * Adds a chapter track (and, for MP4, chpl) to an existing movie without
 * touching its samples: the moov is rewritten (moov first) and the media
 * data copied. The video track must be constant frame rate at `rate` in a
 * timescale where a frame is whole ticks. */
WValue w_media_chapterize(WValue srcv, WValue dstv, WValue chv, WValue ratev) {
    char src[4096], dst[4096], err[512];
    if (!w_media_str(srcv, src, sizeof src) || !src[0] || !w_media_str(dstv, dst, sizeof dst) || !dst[0])
        w_media_raise("Mux.chapterize: source and destination must be paths");
    if (!strcmp(src, dst)) w_media_raise("Mux.chapterize: write a new file (the source is read while the copy is written)");
    int32_t num = (int32_t)w_media_num(m_avf_arr(ratev, 0), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(ratev, 1), 0, "rate");
    if (num <= 0 || den <= 0) w_media_raise("Mux.chapterize: rate must be [num, den]");
    int fd = open(src, O_RDONLY);
    if (fd < 0) w_media_raise("Mux.chapterize: cannot open %s: %s", src, strerror(errno));
    ATop top[64];
    int ntop = 0, moov_i = -1;
    ABox root;
    if (a_read_moov(fd, src, top, &ntop, &moov_i, &root, err, sizeof err) != 0) { close(fd); w_media_raise("Mux.chapterize: %s", err); }
    uint8_t brand[4] = {0, 0, 0, 0};
    pread(fd, brand, 4, top[0].off + 8);
    close(fd);
    ABox *moov = &root.kid[0];
    uint32_t ts = 0;
    uint64_t mdur = 0;
    int has_chap = 0, found = 0;
    for (int i = 0; i < moov->nk; i++) {
        ABox *t = &moov->kid[i];
        if (t->type != A_FOURCC('t','r','a','k')) continue;
        ABox *tr = a_box_find(t, A_FOURCC('t','r','e','f'));
        if (tr) for (size_t o = 8; o + 8 <= tr->len; ) {
            uint32_t sz = a_rd32(tr->raw + o);
            if (sz < 8) break;
            if (a_rd32(tr->raw + o + 4) == A_FOURCC('c','h','a','p')) has_chap = 1;
            o += sz;
        }
        if (!found && a_trak_handler(t) == A_FOURCC('v','i','d','e')) {
            ABox *md = a_box_find(t, A_FOURCC('m','d','i','a'));
            ABox *mh = md ? a_box_find(md, A_FOURCC('m','d','h','d')) : NULL;
            if (mh && mh->len >= 32) {
                int v1 = mh->raw[8] == 1;
                ts = a_rd32(mh->raw + (v1 ? 28 : 20));
                mdur = v1 ? a_rd64(mh->raw + 32) : a_rd32(mh->raw + 24);
                found = 1;
            }
        }
    }
    a_box_free(&root);
    if (!found || ts == 0) w_media_raise("Mux.chapterize: %s has no video track", src);
    if (has_chap) w_media_raise("Mux.chapterize: %s already has a chapter track", src);
    if (((int64_t)ts * den) % num != 0) w_media_raise("Mux.chapterize: a frame at %d/%d is not a whole number of ticks in timescale %u", (int)num, (int)den, ts);
    uint32_t ticks = (uint32_t)((int64_t)ts * den / num);
    int64_t frames = (int64_t)(mdur / ticks);
    int n = 0;
    AChapter *ch = a_chapters_from(chv, &n, "Mux.chapterize");
    for (int i = 0; i < n; i++)
        if (ch[i].frame >= frames) {
            char t[256];
            snprintf(t, sizeof t, "%s", ch[i].title);
            a_chapters_free(ch, n);
            w_media_raise("Mux.chapterize: chapter '%s' starts at or after the last frame (%lld frames)", t, (long long)frames);
        }
    APatch o;
    memset(&o, 0, sizeof o);
    o.mov = !memcmp(brand, "qt  ", 4);
    o.ts = ts; o.ticks = ticks; o.num = num; o.den = den; o.frames = frames;
    o.chap = ch; o.nchap = n; o.chpl = !o.mov; o.faststart = 1;
    int rc = n > 0 ? a_patch_moov(src, dst, &o, err, sizeof err) : -1;
    if (n == 0) snprintf(err, sizeof err, "no chapters");
    a_chapters_free(ch, n);
    if (rc != 0) w_media_raise("Mux.chapterize: %s", err);
    return w_int(n);
}

/* w_media_mux_append(mux, segment) -> frames written so far */
WValue w_media_mux_append(WValue mv, WValue sv) {
    @autoreleasepool {
        AMux *m = w_media_handle_get(mv, W_MEDIA_KIND_MUX, "Mux#append");
        WMediaSegment *s = w_media_segment_ready(sv, "Mux#append");
        return w_int(a_mux_append(m, s));
    }
}

/* Finish the file: the rest of the audio, AVAssetWriter, then the timecode
 * and chapter tracks. out: frames, audio frames written, audio source
 * frames, video bytes, file bytes. Raises on failure (m stays allocated). */
static void a_mux_finish(AMux *m, int64_t out[5]) {
    if (!m->started) a_mux_fail(m, "no segments were appended");
    int64_t audio_total = m->has_audio ? a_audio_for(m, m->frames) : 0;
    if (m->total_frames > 0 && m->total_frames != m->frames)
        a_mux_fail(m, "%lld frames were appended but frames: promised %lld", (long long)m->frames, (long long)m->total_frames);
    if (m->has_audio) {
        int spins = 0;
        while (!a_feed_audio(m, audio_total)) {
            if (m->writer.status != AVAssetWriterStatusWriting) a_mux_fail(m, "the writer stopped while finishing the audio");
            usleep(200);
            if (++spins > 100000) a_mux_fail(m, "the writer stalled finishing the audio");
        }
        if (!m->audio_done) [m->audio markAsFinished];
        m->audio_done = 1;
    }
    [m->video markAsFinished];
    [m->writer endSessionAtSourceTime:CMTimeMake(m->frames * m->ticks, m->ts)];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [m->writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    dispatch_release(sem);
    if (m->writer.status != AVAssetWriterStatusCompleted) a_mux_fail(m, "finishing %s failed", m->path);
    if (m->has_tc || m->nchap > 0) {
        char err[512];
        for (int i = 0; i < m->nchap; i++)
            if (m->chap[i].frame >= m->frames) {
                if (m->has_tc) unlink(m->tmp);
                a_mux_fail(m, "chapter '%s' starts at frame %lld, at or after the last frame (%lld frames)", m->chap[i].title, (long long)m->chap[i].frame, (long long)m->frames);
            }
        APatch o;
        memset(&o, 0, sizeof o);
        o.mov = m->mov; o.ts = (uint32_t)m->ts; o.ticks = (uint32_t)m->ticks; o.num = m->num; o.den = m->den;
        o.frames = m->frames; o.has_tc = m->has_tc; o.tc_drop = m->tc_drop; o.tc_frame = m->tc_start;
        o.tc_quanta = (uint32_t)m->tc_quanta; o.chap = m->chap; o.nchap = m->nchap; o.chpl = m->chpl;
        o.faststart = m->faststart;
        /* without a timecode AVAssetWriter wrote the final path: patch it into the temporary one and move that back */
        const char *from = m->has_tc ? m->tmp : m->path, *to = m->has_tc ? m->path : m->tmp;
        int rc = a_patch_moov(from, to, &o, err, sizeof err);
        if (rc == 0 && !m->has_tc && rename(m->tmp, m->path) != 0) {
            rc = -1;
            snprintf(err, sizeof err, "renaming %s: %s", m->tmp, strerror(errno));
        }
        unlink(m->tmp);
        if (rc != 0) a_mux_fail(m, "adding the timecode/chapter tracks failed: %s", err);
    }
    struct stat st;
    out[0] = m->frames;
    out[1] = audio_total;
    out[2] = m->has_audio ? m->aframes : 0;
    out[3] = m->video_bytes;
    out[4] = stat(m->path, &st) == 0 ? (int64_t)st.st_size : -1;
}

/* w_media_mux_close(mux) -> [frames, audio frames written, audio source frames, bytes, file bytes] */
WValue w_media_mux_close(WValue mv) {
    @autoreleasepool {
        AMux *m = w_media_handle_get(mv, W_MEDIA_KIND_MUX, "Mux#close");
        if (!m->started) {
            w_media_handle_drop(mv, W_MEDIA_KIND_MUX);
            a_mux_free(m);
            w_media_raise("Mux#close: no segments were appended");
        }
        int64_t out[5];
        a_mux_finish(m, out);
        w_media_handle_drop(mv, W_MEDIA_KIND_MUX);
        a_mux_free(m);
        WValue a = w_array_new_empty();
        for (int i = 0; i < 5; i++) a = w_array_push(a, w_int(out[i]));
        return a;
    }
}

/* ======================================================================
   Scaler: Metal backend
   ======================================================================
 *
 * The same weight tables as the CPU backend (media.c), in two compute
 * passes: horizontal (the source rows the vertical pass reads, into a
 * float intermediate) and vertical (every destination pixel: the rect
 * from the intermediate, the fill outside it). Metal.framework is opened
 * on first use with dlopen, so programs that never scale do not load it
 * (and the media link line needs no Metal framework); everything else is
 * Objective-C messaging. Buffers: a page-aligned source or destination is
 * wrapped without a copy; anything else goes through a shared staging
 * buffer. */

static const char *a_msl =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct HP { uint rw, rows, lo, taps, axlo, sstride, alpha, pad; };\n"
    "struct VP { uint dw, dh, rx, ry, rw, rh, taps, lo, dstride, alpha, fill, pad; };\n"
    "static inline float4 ld4(uchar4 u, uint alpha) {\n"
    "  float4 v = float4(u);\n"
    "  if (alpha == 2) { float k = v.w * (1.0f / 255.0f); v.xyz *= k; }\n"
    "  else if (alpha == 3) v.w = 255.0f;\n"
    "  return v;\n"
    "}\n"
    "static inline uint u8(float v) { return uint(clamp(v, 0.0f, 255.0f) + 0.5f); }\n"
    "kernel void h4(device const uchar *src [[buffer(0)]], device const int *xs [[buffer(1)]], device const float *xw [[buffer(2)]],\n"
    "               device float4 *H [[buffer(3)]], constant HP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.rw || g.y >= p.rows) return;\n"
    "  device const uchar4 *row = (device const uchar4 *)(src + (ulong)(p.lo + g.y) * p.sstride);\n"
    "  int s0 = xs[g.x]; device const float *w = xw + (ulong)g.x * p.taps; float4 a = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) a = fma(float4(w[t]), ld4(row[s0 + t], p.alpha), a);\n"
    "  H[(ulong)g.y * p.rw + g.x] = a;\n"
    "}\n"
    "kernel void h2(device const uchar *src [[buffer(0)]], device const int *xs [[buffer(1)]], device const float *xw [[buffer(2)]],\n"
    "               device float2 *H [[buffer(3)]], constant HP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.rw || g.y >= p.rows) return;\n"
    "  device const uchar2 *row = (device const uchar2 *)(src + (ulong)(p.lo + g.y) * p.sstride);\n"
    "  int s0 = xs[g.x]; device const float *w = xw + (ulong)g.x * p.taps; float2 a = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) a = fma(float2(w[t]), float2(row[s0 + t]), a);\n"
    "  H[(ulong)g.y * p.rw + g.x] = a;\n"
    "}\n"
    "kernel void h1(device const uchar *src [[buffer(0)]], device const int *xs [[buffer(1)]], device const float *xw [[buffer(2)]],\n"
    "               device float *H [[buffer(3)]], constant HP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.rw || g.y >= p.rows) return;\n"
    "  device const uchar *row = src + (ulong)(p.lo + g.y) * p.sstride;\n"
    "  int s0 = xs[g.x]; device const float *w = xw + (ulong)g.x * p.taps; float a = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) a = fma(w[t], float(row[s0 + t]), a);\n"
    "  H[(ulong)g.y * p.rw + g.x] = a;\n"
    "}\n"
    "kernel void v4(device const float4 *H [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "               device uchar *dst [[buffer(3)]], constant VP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar4 *o = (device uchar4 *)(dst + (ulong)g.y * p.dstride) + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = as_type<uchar4>(p.fill); return; }\n"
    "  int s0 = ys[y] - int(p.lo); device const float *w = yw + (ulong)y * p.taps;\n"
    "  float4 v = w[0] * H[(ulong)s0 * p.rw + x];\n"
    "  for (uint t = 1; t < p.taps; t++) v = fma(float4(w[t]), H[(ulong)(s0 + t) * p.rw + x], v);\n"
    "  uint4 r;\n"
    "  if (p.alpha == 0) r = uint4(u8(v.x), u8(v.y), u8(v.z), u8(v.w));\n"
    "  else if (p.alpha == 3) r = uint4(u8(v.x), u8(v.y), u8(v.z), 255u);\n"
    "  else {\n"
    "    float A = clamp(v.w, 0.0f, 255.0f); uint a = uint(A + 0.5f);\n"
    "    if (p.alpha == 1) { float af = float(a); r = uint4(uint3(clamp(v.xyz, 0.0f, af) + 0.5f), a); }\n"
    "    else if (a == 0) r = uint4(0);\n"
    "    else { float k = 255.0f / clamp(v.w, 1e-6f, 255.0f); r = uint4(u8(v.x * k), u8(v.y * k), u8(v.z * k), a); }\n"
    "  }\n"
    "  *o = uchar4(r);\n"
    "}\n"
    "kernel void v2(device const float2 *H [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "               device uchar *dst [[buffer(3)]], constant VP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar2 *o = (device uchar2 *)(dst + (ulong)g.y * p.dstride) + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = uchar2(p.fill & 255u, (p.fill >> 8) & 255u); return; }\n"
    "  int s0 = ys[y] - int(p.lo); device const float *w = yw + (ulong)y * p.taps;\n"
    "  float2 v = w[0] * H[(ulong)s0 * p.rw + x];\n"
    "  for (uint t = 1; t < p.taps; t++) v = fma(float2(w[t]), H[(ulong)(s0 + t) * p.rw + x], v);\n"
    "  *o = uchar2(u8(v.x), u8(v.y));\n"
    "}\n"
    "kernel void v1(device const float *H [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "               device uchar *dst [[buffer(3)]], constant VP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar *o = dst + (ulong)g.y * p.dstride + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = uchar(p.fill & 255u); return; }\n"
    "  int s0 = ys[y] - int(p.lo); device const float *w = yw + (ulong)y * p.taps;\n"
    "  float v = w[0] * H[(ulong)s0 * p.rw + x];\n"
    "  for (uint t = 1; t < p.taps; t++) v = fma(w[t], H[(ulong)(s0 + t) * p.rw + x], v);\n"
    "  *o = uchar(u8(v));\n"
    "}\n";

typedef struct { uint32_t rw, rows, lo, taps, axlo, sstride, alpha, pad; } AMtlHP;
typedef struct { uint32_t dw, dh, rx, ry, rw, rh, taps, lo, dstride, alpha, fill, pad; } AMtlVP;

typedef id (*a_mtl_create_fn)(void);
static pthread_once_t g_mtl_once = PTHREAD_ONCE_INIT;
static id g_mtl_dev, g_mtl_queue;
static id g_mtl_h[5], g_mtl_v[5];
static int g_mtl_ok;
static char g_mtl_err[512];
static pthread_mutex_t g_mtl_mu = PTHREAD_MUTEX_INITIALIZER;
static id g_mtl_stage_in, g_mtl_stage_out;   /* shared staging buffers, grown on demand */
static size_t g_mtl_page;

static void a_mtl_load(void) {
    @autoreleasepool {
        g_mtl_page = (size_t)getpagesize();
        void *h = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY | RTLD_LOCAL);
        a_mtl_create_fn create = h ? (a_mtl_create_fn)dlsym(h, "MTLCreateSystemDefaultDevice") : NULL;
        if (!create) { snprintf(g_mtl_err, sizeof g_mtl_err, "Metal.framework could not be loaded"); return; }
        id<MTLDevice> dev = create();
        if (!dev) { snprintf(g_mtl_err, sizeof g_mtl_err, "no Metal device"); return; }
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:a_msl] options:nil error:&err];
        if (!lib) {
            snprintf(g_mtl_err, sizeof g_mtl_err, "compiling the scaler kernels failed: %s", err.localizedDescription.UTF8String ?: "?");
            [dev release];
            return;
        }
        static const char *hn[5] = {NULL, "h1", "h2", NULL, "h4"}, *vn[5] = {NULL, "v1", "v2", NULL, "v4"};
        for (int c = 1; c <= 4; c++) {
            if (!hn[c]) continue;
            id<MTLFunction> fh = [lib newFunctionWithName:[NSString stringWithUTF8String:hn[c]]];
            id<MTLFunction> fv = [lib newFunctionWithName:[NSString stringWithUTF8String:vn[c]]];
            g_mtl_h[c] = fh ? [dev newComputePipelineStateWithFunction:fh error:&err] : nil;
            g_mtl_v[c] = fv ? [dev newComputePipelineStateWithFunction:fv error:&err] : nil;
            [fh release];
            [fv release];
            if (!g_mtl_h[c] || !g_mtl_v[c]) {
                snprintf(g_mtl_err, sizeof g_mtl_err, "building the scaler pipelines failed: %s", err.localizedDescription.UTF8String ?: "?");
                [lib release];
                [dev release];
                return;
            }
        }
        [lib release];
        g_mtl_queue = [dev newCommandQueue];
        g_mtl_dev = dev;
        g_mtl_ok = g_mtl_queue != nil;
    }
}

int w_media_metal_available(void) {
    if (getenv("TUNGSTEN_MEDIA_NO_METAL")) return 0;
    pthread_once(&g_mtl_once, a_mtl_load);
    return g_mtl_ok;
}

/* Per-plan GPU state: the weight tables and the intermediate. */
typedef struct AMtlPlan {
    id xs, xw, ys, yw, H;
} AMtlPlan;

void w_media_scale_metal_release(WMediaScale *s) {
    AMtlPlan *p = s->metal;
    if (!p) return;
    [p->xs release]; [p->xw release]; [p->ys release]; [p->yw release]; [p->H release];
    free(p);
    s->metal = NULL;
}

typedef struct { uint8_t *dst; const uint8_t *src; size_t n; } APCopy;
static void a_pcopy_band(void *ctx, size_t i) {
    APCopy *c = ctx;
    size_t a = c->n * i / 8, b = c->n * (i + 1) / 8;
    memcpy(c->dst + a, c->src + a, b - a);
}

/* memcpy split over 8 threads (staging copies of whole frames) */
static void a_pcopy(uint8_t *dst, const uint8_t *src, size_t n) {
    if (n < (1u << 20)) { memcpy(dst, src, n); return; }
    APCopy c = {dst, src, n};
    dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &c, a_pcopy_band);
}

/* A buffer over [p, p + len): the pages that hold it, wrapped in place (no
 * copy; every page in the range holds part of the caller's buffer, so all
 * of it is mapped) and bound at p's offset into the first page; or, if
 * Metal will not wrap it, the staging buffer (grown as needed), *copied
 * set. */
static id a_mtl_buf(void *p, size_t len, id *stage, int *copied, size_t *offset) {
    size_t pg = g_mtl_page ? g_mtl_page : 16384;
    uintptr_t base = (uintptr_t)p & ~(uintptr_t)(pg - 1);
    size_t off = (size_t)((uintptr_t)p - base);
    size_t rl = (off + len + pg - 1) / pg * pg;
    if (!getenv("TUNGSTEN_MEDIA_METAL_STAGE")) {
        id b = [g_mtl_dev newBufferWithBytesNoCopy:(void *)base length:rl options:MTLResourceStorageModeShared deallocator:nil];
        if (b) { *copied = 0; *offset = off; return b; }
    }
    if (!*stage || [(id<MTLBuffer>)*stage length] < len) {
        [*stage release];
        *stage = [g_mtl_dev newBufferWithLength:(len + pg - 1) / pg * pg options:MTLResourceStorageModeShared];
    }
    *copied = 1;
    *offset = 0;
    return [*stage retain];
}

/* Encode one plan's two passes into ce. Returns 0, or -1 with a message. */
static int a_mtl_encode(id<MTLComputeCommandEncoder> ce, WMediaJob *j, id *keep, int *nkeep, int *copy_out, char *err, size_t cap) {
    WMediaScale *s = j->s;
    id<MTLDevice> dev = g_mtl_dev;
    int C = s->ch;
    if (s->out_bits > 8) { snprintf(err, cap, "Metal writes 8-bit planes only"); return -1; }
    if ((C == 4 && (j->sstride % 4 || j->dstride % 4 || (uintptr_t)j->src % 4 || (uintptr_t)j->dst % 4)) ||
        (C == 2 && (j->sstride % 2 || j->dstride % 2 || (uintptr_t)j->src % 2 || (uintptr_t)j->dst % 2))) {
        snprintf(err, cap, "Metal needs pixel-aligned rows");
        return -1;
    }
    AMtlPlan *p = s->metal;
    int rows = s->ay.hi - s->ay.lo;
    if (!p) {
        p = calloc(1, sizeof *p);
        p->xs = [dev newBufferWithBytes:s->ax.start length:sizeof(int32_t) * (size_t)s->ax.n options:MTLResourceStorageModeShared];
        p->xw = [dev newBufferWithBytes:s->ax.w length:sizeof(float) * (size_t)s->ax.n * (size_t)s->ax.taps options:MTLResourceStorageModeShared];
        p->ys = [dev newBufferWithBytes:s->ay.start length:sizeof(int32_t) * (size_t)s->ay.n options:MTLResourceStorageModeShared];
        p->yw = [dev newBufferWithBytes:s->ay.w length:sizeof(float) * (size_t)s->ay.n * (size_t)s->ay.taps options:MTLResourceStorageModeShared];
        p->H = [dev newBufferWithLength:sizeof(float) * (size_t)C * (size_t)s->rw * (size_t)rows options:MTLResourceStorageModePrivate];
        s->metal = p;
        if (!p->xs || !p->xw || !p->ys || !p->yw || !p->H) {
            w_media_scale_metal_release(s);
            snprintf(err, cap, "Metal: out of memory");
            return -1;
        }
    }
    /* only the source rows the plan reads */
    size_t soff = (size_t)s->ay.lo * j->sstride;
    size_t slen = (size_t)(rows - 1) * j->sstride + (size_t)s->src_w * C;
    if (soff + slen > j->src_len) slen = j->src_len - soff;
    int scopy = 0, dcopy = 0;
    size_t so = 0, dof = 0;
    uint8_t *sbase = (uint8_t *)j->src + soff;
    /* staging is shared: only the first job of a batch may use it */
    id sb = a_mtl_buf(sbase, slen, &g_mtl_stage_in, &scopy, &so);
    id db = a_mtl_buf(j->dst, j->dst_len, &g_mtl_stage_out, &dcopy, &dof);
    if (!sb || !db || ((scopy || dcopy) && *nkeep > 0)) {
        [sb release];
        [db release];
        snprintf(err, cap, "Metal: no buffer");
        return -1;
    }
    keep[(*nkeep)++] = sb;
    keep[(*nkeep)++] = db;
    if (scopy) a_pcopy([(id<MTLBuffer>)sb contents], sbase, slen);
    *copy_out = dcopy;
    AMtlHP hp = {(uint32_t)s->rw, (uint32_t)rows, 0, (uint32_t)s->ax.taps, (uint32_t)s->ax.lo, (uint32_t)j->sstride, (uint32_t)s->alpha, 0};
    id<MTLComputePipelineState> ph = g_mtl_h[C], pv = g_mtl_v[C];
    [ce setComputePipelineState:ph];
    [ce setBuffer:sb offset:so atIndex:0];
    [ce setBuffer:p->xs offset:0 atIndex:1];
    [ce setBuffer:p->xw offset:0 atIndex:2];
    [ce setBuffer:p->H offset:0 atIndex:3];
    [ce setBytes:&hp length:sizeof hp atIndex:4];
    NSUInteger tw = ph.threadExecutionWidth, th = ph.maxTotalThreadsPerThreadgroup / tw;
    [ce dispatchThreads:MTLSizeMake((NSUInteger)s->rw, (NSUInteger)rows, 1) threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    uint32_t fill = (uint32_t)s->fill[0] | ((uint32_t)s->fill[1] << 8) | ((uint32_t)s->fill[2] << 16) | ((uint32_t)s->fill[3] << 24);
    AMtlVP vp = {(uint32_t)s->dst_w, (uint32_t)s->dst_h, (uint32_t)s->rx, (uint32_t)s->ry, (uint32_t)s->rw, (uint32_t)s->rh,
                 (uint32_t)s->ay.taps, (uint32_t)s->ay.lo, (uint32_t)j->dstride, (uint32_t)s->alpha, fill, 0};
    [ce setComputePipelineState:pv];
    [ce setBuffer:p->H offset:0 atIndex:0];
    [ce setBuffer:p->ys offset:0 atIndex:1];
    [ce setBuffer:p->yw offset:0 atIndex:2];
    [ce setBuffer:db offset:dof atIndex:3];
    [ce setBytes:&vp length:sizeof vp atIndex:4];
    tw = pv.threadExecutionWidth;
    th = pv.maxTotalThreadsPerThreadgroup / tw;
    [ce dispatchThreads:MTLSizeMake((NSUInteger)s->dst_w, (NSUInteger)s->dst_h, 1) threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    return 0;
}

/* Several plans in one command buffer (the Y' and CbCr planes of a frame). */
int w_media_scale_metal_jobs(WMediaJob *jobs, int n, char *err, size_t cap) {
    if (!w_media_metal_available()) { snprintf(err, cap, "Metal: %s", g_mtl_err[0] ? g_mtl_err : "not available"); return -1; }
    if (n < 1 || n > 4) { snprintf(err, cap, "Metal: 1 to 4 jobs"); return -1; }
    int rc = 0;
    @autoreleasepool {
        pthread_mutex_lock(&g_mtl_mu);
        id keep[8];
        int nkeep = 0, copy_out[4] = {0, 0, 0, 0};
        id<MTLCommandBuffer> cb = [g_mtl_queue commandBuffer];
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        for (int i = 0; i < n && rc == 0; i++) rc = a_mtl_encode(ce, &jobs[i], keep, &nkeep, &copy_out[i], err, cap);
        [ce endEncoding];
        if (rc == 0) {
            [cb commit];
            [cb waitUntilCompleted];
            if (cb.status != MTLCommandBufferStatusCompleted) {
                rc = -1;
                snprintf(err, cap, "Metal: the command buffer failed (%s)", cb.error.localizedDescription.UTF8String ?: "?");
            }
        }
        for (int i = 0; i < n && rc == 0; i++)
            if (copy_out[i]) {
                WMediaScale *s = jobs[i].s;
                a_pcopy(jobs[i].dst, [(id<MTLBuffer>)keep[2 * i + 1] contents], (size_t)(s->dst_h - 1) * jobs[i].dstride + (size_t)s->dst_w * s->ch);
            }
        for (int i = 0; i < nkeep; i++) [keep[i] release];
        pthread_mutex_unlock(&g_mtl_mu);
    }
    return rc;
}

int w_media_scale_metal(WMediaScale *s, const uint8_t *src, size_t sstride, size_t src_len,
                        uint8_t *dst, size_t dstride, size_t dst_len, char *err, size_t cap) {
    WMediaJob j = {s, src, sstride, src_len, dst, dstride, dst_len};
    return w_media_scale_metal_jobs(&j, 1, err, cap);
}

/* ======================================================================
   Decoder: VTDecompressionSession over a file's video samples (AVAssetReader
   passthrough) or over segment files, frames handed out in presentation
   order
   ======================================================================
 *
 * A producer thread pulls compressed samples in decode order and decodes
 * each one synchronously; decoded frames wait in a small pending list until
 * no frame still to come can precede them (a frame is final once the next
 * sample's decode time passes its presentation time, since DTS <= PTS), then
 * move to a bounded queue the consumer takes them from. */

typedef struct ADecFrame {
    int64_t          pts;      /* source ticks (files) or frame index (segments) */
    CVPixelBufferRef pb;
} ADecFrame;

typedef struct ADec {
    /* source */
    AVURLAsset      *asset;
    AVAssetReader   *reader;
    AVAssetReaderTrackOutput *out;
    char           **segs;
    int              nseg, seg_i, seg_k;
    WMediaSegment   *seg;
    int64_t          seg_base;         /* frame index of the current segment's frame 0 */
    int32_t         *seg_sorted;
    CMFormatDescriptionRef fmt;
    VTDecompressionSessionRef vt;
    OSType           pix;
    int              w, h;
    int32_t          num, den;         /* frame rate */
    int32_t          ts;               /* file: track timescale */
    int64_t          edit;             /* file: presentation = media pts + edit (ticks) */
    int64_t          frames_hint;
    int64_t          start_pts;        /* frames before this presentation time are dropped (files) */
    uint32_t         codec;
    int              siting;           /* source chroma siting (M_SITE_*-like: 0 left, 1 center, 2 topleft) */
    /* thread */
    pthread_t        th;
    int              th_started;
    pthread_mutex_t  mu;
    pthread_cond_t   cv;
    ADecFrame       *pend;             /* decoded, sorted by pts */
    int              npend, cpend;
    int64_t         *fly;              /* [id, pts] of samples fed but not yet output (VideoToolbox may hold frames back) */
    int              nfly, cfly;
    int64_t          next_id;
    ADecFrame       *q;                /* final, in order */
    int              qh, qn, qcap;
    int              eof, stop, debug;
    char             err[512];
    int64_t          decoded, delivered;
    uint64_t         dec_ns;
} ADec;

/* A sample's presentation time on the output timeline (the movie's edit
 * list applied), in source ticks (files) or frames (segments). VideoToolbox
 * reports frames at this time, not at the media time the sample carries. */
static int64_t a_dec_time(ADec *d, CMTime t) {
    if (d->segs) return (int64_t)llround(CMTimeGetSeconds(t) * d->num / d->den);
    return CMTimeConvertScale(t, d->ts, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
}

static void a_dec_output(void *ref, void *frameref, OSStatus st, VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts, CMTime dur) {
    (void)dur;
    ADec *d = ref;
    pthread_mutex_lock(&d->mu);
    /* the frame's time: from the sample it came from (frameref is its id) */
    int64_t id = (int64_t)(intptr_t)frameref, p = a_dec_time(d, pts);
    for (int i = 0; i < d->nfly; i++)
        if (d->fly[2 * i] == id) {
            p = d->fly[2 * i + 1];
            d->nfly--;
            d->fly[2 * i] = d->fly[2 * d->nfly];
            d->fly[2 * i + 1] = d->fly[2 * d->nfly + 1];
            break;
        }
    if (d->debug && d->decoded < 16) fprintf(stderr, "media decoder: output pts %lld (in flight %d)\n", (long long)p, d->nfly);
    if (st != noErr || !img) {
        if (!d->err[0] && !(flags & kVTDecodeInfo_FrameDropped)) snprintf(d->err, sizeof d->err, "VideoToolbox could not decode a frame (OSStatus %d)", (int)st);
        pthread_mutex_unlock(&d->mu);
        return;
    }
    if (d->npend == d->cpend) {
        d->cpend = d->cpend ? d->cpend * 2 : 16;
        d->pend = realloc(d->pend, sizeof(ADecFrame) * (size_t)d->cpend);
    }
    int i = d->npend;
    while (i > 0 && d->pend[i - 1].pts > p) { d->pend[i] = d->pend[i - 1]; i--; }
    d->pend[i].pts = p;
    d->pend[i].pb = (CVPixelBufferRef)CVBufferRetain(img);
    d->npend++;
    d->decoded++;
    pthread_mutex_unlock(&d->mu);
}

static int a_dec_session(ADec *d, CMFormatDescriptionRef fmt) {
    if (d->vt) {
        if (VTDecompressionSessionCanAcceptFormatDescription(d->vt, fmt)) return 0;
        VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
        VTDecompressionSessionInvalidate(d->vt);
        CFRelease(d->vt);
        d->vt = NULL;
    }
    CFMutableDictionaryRef spec = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(spec, kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder, kCFBooleanTrue);
    NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(d->pix), (id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    VTDecompressionOutputCallbackRecord cb = {a_dec_output, d};
    OSStatus st = VTDecompressionSessionCreate(NULL, fmt, spec, (__bridge CFDictionaryRef)attrs, &cb, &d->vt);
    CFRelease(spec);
    if (st != noErr) {
        snprintf(d->err, sizeof d->err, "VideoToolbox cannot decode this stream (OSStatus %d)", (int)st);
        return -1;
    }
    return 0;
}

/* Move final frames (pts < limit) from pending to the queue, waiting for
 * room. Called on the producer thread with d->mu held. */
static void a_dec_release(ADec *d, int64_t limit, int all) {
    for (int i = 0; i < d->nfly; i++) if (d->fly[2 * i + 1] < limit) limit = d->fly[2 * i + 1];
    while (d->npend > 0 && (all || d->pend[0].pts < limit) && !d->stop) {
        ADecFrame f = d->pend[0];
        memmove(d->pend, d->pend + 1, sizeof(ADecFrame) * (size_t)(d->npend - 1));
        d->npend--;
        if (!d->segs && f.pts < d->start_pts) { CVBufferRelease(f.pb); continue; }
        while (d->qn == d->qcap && !d->stop) pthread_cond_wait(&d->cv, &d->mu);
        if (d->stop) { CVBufferRelease(f.pb); break; }
        d->q[(d->qh + d->qn) % d->qcap] = f;
        d->qn++;
        pthread_cond_broadcast(&d->cv);
    }
}

/* The next compressed sample in decode order (retained), its DTS (in the
 * same units as frame pts), or NULL at the end. Producer thread. */
static CMSampleBufferRef a_dec_next_sample(ADec *d, int64_t *dts) {
    if (!d->segs) {
        CMSampleBufferRef sb = [d->out copyNextSampleBuffer];
        if (!sb) {
            if (d->reader.status == AVAssetReaderStatusFailed && !d->err[0])
                snprintf(d->err, sizeof d->err, "reading the video failed: %s", d->reader.error.localizedDescription.UTF8String ?: "?");
            return NULL;
        }
        CMTime t = CMSampleBufferGetOutputDecodeTimeStamp(sb);
        if (!CMTIME_IS_VALID(t)) t = CMSampleBufferGetOutputPresentationTimeStamp(sb);
        *dts = a_dec_time(d, t);
        return sb;
    }
    for (;;) {
        if (d->seg && d->seg_k < d->seg->n) break;
        if (d->seg) {
            d->seg_base += d->seg->n;
            w_media_seg_free(d->seg);
            d->seg = NULL;
            free(d->seg_sorted);
            d->seg_sorted = NULL;
        }
        if (d->seg_i >= d->nseg) return NULL;
        char err[512];
        d->seg = w_media_seg_load(d->segs[d->seg_i++], err, sizeof err);
        if (!d->seg) { snprintf(d->err, sizeof d->err, "%s", err); return NULL; }
        d->seg_k = 0;
        d->seg_sorted = malloc(sizeof(int32_t) * (size_t)(d->seg->n ? d->seg->n : 1));
        for (int i = 0; i < d->seg->n; i++) d->seg_sorted[i] = d->seg->s[i].pts;
        for (int i = 1; i < d->seg->n; i++) {
            int32_t v = d->seg_sorted[i];
            int j = i - 1;
            while (j >= 0 && d->seg_sorted[j] > v) { d->seg_sorted[j + 1] = d->seg_sorted[j]; j--; }
            d->seg_sorted[j + 1] = v;
        }
        if (a_dec_session(d, (CMFormatDescriptionRef)d->seg->format) != 0) return NULL;
    }
    WMediaSegment *s = d->seg;
    const WMediaSample *x = &s->s[d->seg_k];
    int delay = (s->flags & W_MEDIA_SEG_REORDER) ? W_MEDIA_REORDER_DELAY : 0;
    *dts = d->seg_base + d->seg_sorted[d->seg_k] - delay;
    d->seg_k++;
    CMBlockBufferRef bb = NULL;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, s->data + x->offset, x->size, kCFAllocatorNull, NULL, 0, x->size, 0, &bb);
    if (st != noErr) { snprintf(d->err, sizeof d->err, "sample buffer (OSStatus %d)", (int)st); return NULL; }
    CMSampleTimingInfo ti;
    ti.duration = CMTimeMake(d->den, d->num);
    ti.presentationTimeStamp = CMTimeMake((d->seg_base + x->pts) * d->den, d->num);
    ti.decodeTimeStamp = kCMTimeInvalid;
    size_t sz = x->size;
    CMSampleBufferRef sb = NULL;
    st = CMSampleBufferCreateReady(NULL, bb, (CMFormatDescriptionRef)s->format, 1, 1, &ti, 1, &sz, &sb);
    CFRelease(bb);
    if (st != noErr) { snprintf(d->err, sizeof d->err, "sample (OSStatus %d)", (int)st); return NULL; }
    return sb;
}

static void *a_dec_thread(void *arg) {
    ADec *d = arg;
    @autoreleasepool {
        for (;;) {
            int64_t dts = 0;
            CMSampleBufferRef sb = NULL;
            @autoreleasepool { sb = a_dec_next_sample(d, &dts); }
            if (!sb && d->vt) {
                /* frames VideoToolbox still holds back */
                VTDecompressionSessionFinishDelayedFrames(d->vt);
                VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
            }
            pthread_mutex_lock(&d->mu);
            int stop = d->stop || d->err[0];
            if (!sb || stop) {
                if (!stop) a_dec_release(d, 0, 1);
                d->eof = 1;
                pthread_cond_broadcast(&d->cv);
                pthread_mutex_unlock(&d->mu);
                if (sb) CFRelease(sb);
                break;
            }
            a_dec_release(d, dts, 0);
            int64_t id = ++d->next_id;
            if (CMSampleBufferGetNumSamples(sb) > 0) {
                int64_t p = a_dec_time(d, CMSampleBufferGetOutputPresentationTimeStamp(sb));
                if (d->nfly == d->cfly) {
                    d->cfly = d->cfly ? d->cfly * 2 : 16;
                    d->fly = realloc(d->fly, 2 * sizeof(int64_t) * (size_t)d->cfly);
                }
                d->fly[2 * d->nfly] = id;
                d->fly[2 * d->nfly + 1] = p;
                d->nfly++;
                if (d->debug && d->decoded < 16) {
                    CMTime dt = CMSampleBufferGetDecodeTimeStamp(sb);
                    fprintf(stderr, "media decoder: sample pts %lld dts %lld (%s)\n", (long long)p, (long long)dts, CMTIME_IS_VALID(dt) ? "valid" : "none");
                }
            }
            pthread_mutex_unlock(&d->mu);
            if (CMSampleBufferGetNumSamples(sb) > 0) {
                uint64_t t0 = m_avf_now_ns();
                VTDecodeInfoFlags info = 0;
                OSStatus st = VTDecompressionSessionDecodeFrame(d->vt, sb, 0, (void *)(intptr_t)id, &info);
                VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
                d->dec_ns += m_avf_now_ns() - t0;
                if (st != noErr) {
                    pthread_mutex_lock(&d->mu);
                    if (!d->err[0]) snprintf(d->err, sizeof d->err, "VideoToolbox could not decode a sample (OSStatus %d)", (int)st);
                    pthread_cond_broadcast(&d->cv);
                    pthread_mutex_unlock(&d->mu);
                }
            }
            CFRelease(sb);
        }
    }
    return NULL;
}

static void a_dec_free(ADec *d) {
    if (!d) return;
    if (d->th_started) {
        pthread_mutex_lock(&d->mu);
        d->stop = 1;
        pthread_cond_broadcast(&d->cv);
        pthread_mutex_unlock(&d->mu);
        pthread_join(d->th, NULL);
    }
    for (int i = 0; i < d->npend; i++) CVBufferRelease(d->pend[i].pb);
    for (int i = 0; i < d->qn; i++) CVBufferRelease(d->q[(d->qh + i) % d->qcap].pb);
    free(d->pend);
    free(d->fly);
    free(d->q);
    if (d->vt) {
        VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
        VTDecompressionSessionInvalidate(d->vt);
        CFRelease(d->vt);
    }
    if (d->reader) { [d->reader cancelReading]; [d->reader release]; }
    if (d->out) [d->out release];
    if (d->asset) [d->asset release];
    if (d->fmt) CFRelease(d->fmt);
    if (d->seg) w_media_seg_free(d->seg);
    free(d->seg_sorted);
    for (int i = 0; i < d->nseg; i++) free(d->segs[i]);
    free(d->segs);
    pthread_mutex_destroy(&d->mu);
    pthread_cond_destroy(&d->cv);
    free(d);
}

static int a_siting_of(CFTypeRef loc) {
    if (loc && CFGetTypeID(loc) == CFStringGetTypeID()) {
        if (CFEqual(loc, kCVImageBufferChromaLocation_Center)) return 1;
        if (CFEqual(loc, kCVImageBufferChromaLocation_TopLeft)) return 2;
    }
    return 0;
}

/* Open a decoder: path (a movie file) or segs (segment files, with rate),
 * output pixel format pix ('420v' or 'BGRA'), frames before start_frame
 * dropped (files). NULL with a message. */
static ADec *a_dec_open(const char *path, char **segs, int nseg, int32_t num, int32_t den, OSType pix, int64_t start_frame,
                        char *err, size_t cap) {
    ADec *d = calloc(1, sizeof *d);
    pthread_mutex_init(&d->mu, NULL);
    pthread_cond_init(&d->cv, NULL);
    d->pix = pix;
    d->debug = getenv("TUNGSTEN_MEDIA_DEBUG") != NULL;
    d->qcap = 6;
    d->q = calloc((size_t)d->qcap, sizeof(ADecFrame));
    if (path) {
        d->asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]
                                            options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        NSArray *vt = [d->asset tracksWithMediaType:AVMediaTypeVideo];
        if (!vt.count) { snprintf(err, cap, "%s has no video track", path); a_dec_free(d); return NULL; }
        AVAssetTrack *t = vt[0];
        CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
        if (!fd) { snprintf(err, cap, "%s: no video format", path); a_dec_free(d); return NULL; }
        d->fmt = fd;
        CFRetain(fd);
        CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(fd);
        d->w = dim.width;
        d->h = dim.height;
        d->codec = CMFormatDescriptionGetMediaSubType(fd);
        d->ts = t.naturalTimeScale;
        CMTime md = t.minFrameDuration;
        if (num > 0 && den > 0) { d->num = num; d->den = den; }
        else if (CMTIME_IS_NUMERIC(md) && md.value > 0) { d->num = md.timescale; d->den = (int32_t)md.value; }
        else { d->num = 24; d->den = 1; }
        CFDictionaryRef ext = CMFormatDescriptionGetExtensions(fd);
        d->siting = a_siting_of(ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ChromaLocationTopField) : NULL);
        if (t.segments.count >= 1) {
            CMTimeMapping tm = t.segments.firstObject.timeMapping;
            d->edit = CMTimeConvertScale(CMTimeSubtract(tm.target.start, tm.source.start), d->ts, kCMTimeRoundingMethod_Default).value;
        }
        CMTime vdur = t.timeRange.duration;
        d->frames_hint = (int64_t)llround(CMTimeGetSeconds(vdur) * d->num / d->den);
        /* start: read from the sync sample before it (the reader backs up for passthrough) */
        d->start_pts = (int64_t)((__int128)start_frame * d->den * d->ts / d->num);
        NSError *e = nil;
        d->reader = [[AVAssetReader alloc] initWithAsset:d->asset error:&e];
        if (!d->reader) { snprintf(err, cap, "%s: %s", path, e.localizedDescription.UTF8String ?: "cannot read"); a_dec_free(d); return NULL; }
        if (start_frame > 0)
            d->reader.timeRange = CMTimeRangeMake(CMTimeMake((int64_t)((__int128)start_frame * d->den * d->ts / d->num), d->ts), kCMTimePositiveInfinity);
        d->out = [[AVAssetReaderTrackOutput alloc] initWithTrack:t outputSettings:nil];
        d->out.alwaysCopiesSampleData = NO;
        [d->reader addOutput:d->out];
        if (![d->reader startReading]) {
            snprintf(err, cap, "%s: cannot start reading: %s", path, d->reader.error.localizedDescription.UTF8String ?: "?");
            a_dec_free(d);
            return NULL;
        }
        if (a_dec_session(d, fd) != 0) { snprintf(err, cap, "%s", d->err); a_dec_free(d); return NULL; }
    } else {
        if (nseg <= 0) { snprintf(err, cap, "no segments"); a_dec_free(d); return NULL; }
        d->segs = calloc((size_t)nseg, sizeof(char *));
        for (int i = 0; i < nseg; i++) d->segs[i] = strdup(segs[i]);
        d->nseg = nseg;
        /* the first segment gives the size and rate */
        char e2[512];
        WMediaSegment *s0 = w_media_seg_load(segs[0], e2, sizeof e2);
        if (!s0) { snprintf(err, cap, "%s", e2); a_dec_free(d); return NULL; }
        d->w = s0->width;
        d->h = s0->height;
        d->num = s0->rate_num;
        d->den = s0->rate_den;
        d->codec = s0->fourcc;
        CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s0->format);
        d->siting = a_siting_of(ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ChromaLocationTopField) : NULL);
        w_media_seg_free(s0);
        d->frames_hint = -1;
    }
    if (pthread_create(&d->th, NULL, a_dec_thread, d) != 0) { snprintf(err, cap, "cannot start the decoder thread"); a_dec_free(d); return NULL; }
    d->th_started = 1;
    return d;
}

/* The next frame in presentation order: 1 (*pb retained, *frame its index
 * in the output timeline), 0 at the end, -1 with a message. */
static int a_dec_next(ADec *d, CVPixelBufferRef *pb, int64_t *frame, char *err, size_t cap) {
    pthread_mutex_lock(&d->mu);
    while (d->qn == 0 && !d->eof && !d->err[0]) pthread_cond_wait(&d->cv, &d->mu);
    if (d->err[0]) {
        snprintf(err, cap, "%s", d->err);
        pthread_mutex_unlock(&d->mu);
        return -1;
    }
    if (d->qn == 0) { pthread_mutex_unlock(&d->mu); return 0; }
    ADecFrame f = d->q[d->qh];
    d->qh = (d->qh + 1) % d->qcap;
    d->qn--;
    pthread_cond_broadcast(&d->cv);
    pthread_mutex_unlock(&d->mu);
    *pb = f.pb;
    if (d->segs) *frame = f.pts;
    else {
        /* presentation ticks -> frame, rounded to nearest */
        __int128 a = (__int128)f.pts * d->num, b = (__int128)d->ts * d->den;
        *frame = (int64_t)((a * 2 + b) / (2 * b));
        if (a < 0) *frame = -1;
    }
    d->delivered++;
    return 1;
}

/* ======================================================================
   VideoDecoder ccalls
   ====================================================================== */

typedef struct ADecH {
    ADec *d;
    int   rgba;              /* swap B and R for "rgba" */
    int   nv12;
    int64_t last;
} ADecH;

/* Segment paths from an Array of Strings (caller frees). */
static char **a_paths(WValue v, int *n) {
    *n = 0;
    if (!w_is_array(v)) return NULL;
    int64_t k = w_as_array(v)->size;
    char **p = calloc((size_t)(k ? k : 1), sizeof(char *));
    for (int64_t i = 0; i < k; i++) {
        char buf[4096];
        w_media_str(w_array_get(v, w_int(i)), buf, sizeof buf);
        p[i] = strdup(buf);
    }
    *n = (int)k;
    return p;
}

static void a_paths_free(char **p, int n) {
    for (int i = 0; i < n; i++) free(p[i]);
    free(p);
}

/* w_media_decoder_open(source, format, [start_frame, num, den]) -> handle.
 * source: a movie path or an Array of segment paths; format "rgba", "bgra"
 * or "nv12". */
WValue w_media_decoder_open(WValue srcv, WValue fmtv, WValue optv) {
    @autoreleasepool {
        char path[4096], fmt[16], err[512];
        w_media_str(fmtv, fmt, sizeof fmt);
        int nv12 = !strcasecmp(fmt, "nv12") || !strcasecmp(fmt, "420v");
        int rgba = !fmt[0] || !strcasecmp(fmt, "rgba");
        if (!nv12 && !rgba && strcasecmp(fmt, "bgra")) w_media_raise("VideoDecoder: format must be :rgba, :bgra or :nv12 (got '%s')", fmt);
        int64_t start = (int64_t)w_media_num(m_avf_arr(optv, 0), 0, "start");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 1), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(optv, 2), 0, "rate");
        ADec *d;
        OSType pix = nv12 ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_32BGRA;
        if (w_is_array(srcv)) {
            int n = 0;
            char **segs = a_paths(srcv, &n);
            d = a_dec_open(NULL, segs, n, num, den, pix, 0, err, sizeof err);
            a_paths_free(segs, n);
        } else {
            if (!w_media_str(srcv, path, sizeof path) || !path[0]) w_media_raise("VideoDecoder: source must be a path or an array of segment paths");
            if (access(path, R_OK) != 0) w_media_raise("VideoDecoder: cannot read %s: %s", path, strerror(errno));
            d = a_dec_open(path, NULL, 0, num, den, pix, start, err, sizeof err);
        }
        if (!d) w_media_raise("VideoDecoder: %s", err);
        ADecH *h = calloc(1, sizeof *h);
        h->d = d;
        h->rgba = rgba;
        h->nv12 = nv12;
        h->last = -1;
        return w_int(w_media_handle_new(h, W_MEDIA_KIND_DECODER));
    }
}

typedef struct { const uint8_t *src; size_t ss; uint8_t *dst; size_t ds; int w, rows; } ASwap;
static void a_swap_band(void *ctx, size_t b) {
    ASwap *s = ctx;
    int y0 = (int)((int64_t)s->rows * (int64_t)b / 8), y1 = (int)((int64_t)s->rows * (int64_t)(b + 1) / 8);
    for (int y = y0; y < y1; y++) {
        const uint8_t *p = s->src + (size_t)y * s->ss;
        uint8_t *o = s->dst + (size_t)y * s->ds;
        for (int x = 0; x < s->w; x++, p += 4, o += 4) { o[0] = p[2]; o[1] = p[1]; o[2] = p[0]; o[3] = p[3]; }
    }
}

/* w_media_decoder_read(h, dst, stride) -> frame index, or nil at the end.
 * dst: a ByteArray / u8[] / address of width x height x 4 bytes (rgba,
 * bgra; stride default width x 4) or width x height x 3 / 2 (nv12: the Y
 * plane, then interleaved CbCr; stride applies to both). */
WValue w_media_decoder_read(WValue hv, WValue dstv, WValue stridev) {
    ADecH *h = w_media_handle_get(hv, W_MEDIA_KIND_DECODER, "VideoDecoder#read");
    ADec *d = h->d;
    CVPixelBufferRef pb = NULL;
    int64_t frame = 0;
    char err[512];
    int r = a_dec_next(d, &pb, &frame, err, sizeof err);
    if (r < 0) w_media_raise("VideoDecoder#read: %s", err);
    if (r == 0) return W_NIL;
    int64_t avail;
    uint8_t *dst = (uint8_t *)(uintptr_t)m_avf_dest(dstv, &avail, "VideoDecoder#read");
    int w = d->w, hh = d->h;
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    if (h->nv12) {
        size_t ds = (size_t)w_media_num(stridev, (double)w, "stride");
        size_t cw = (size_t)((w + 1) / 2) * 2, ch = (size_t)((hh + 1) / 2);
        size_t need = ds * (size_t)hh + ds * ch;
        if (avail >= 0 && (size_t)avail < need) { CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); CVBufferRelease(pb); w_media_raise("VideoDecoder#read: %lld bytes is too few for a %dx%d nv12 frame", (long long)avail, w, hh); }
        const uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *c = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        for (int i = 0; i < hh; i++) memcpy(dst + (size_t)i * ds, y + (size_t)i * ys, (size_t)w);
        for (size_t i = 0; i < ch; i++) memcpy(dst + ds * (size_t)hh + i * ds, c + i * cs, cw);
    } else {
        size_t ds = (size_t)w_media_num(stridev, (double)w * 4, "stride");
        if (avail >= 0 && (size_t)avail < ds * (size_t)(hh - 1) + (size_t)w * 4) { CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); CVBufferRelease(pb); w_media_raise("VideoDecoder#read: %lld bytes is too few for a %dx%d frame", (long long)avail, w, hh); }
        const uint8_t *p = CVPixelBufferGetBaseAddress(pb);
        size_t ps = CVPixelBufferGetBytesPerRow(pb);
        if (h->rgba) {
            ASwap s = {p, ps, dst, ds, w, hh};
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &s, a_swap_band);
        } else {
            for (int i = 0; i < hh; i++) memcpy(dst + (size_t)i * ds, p + (size_t)i * ps, (size_t)w * 4);
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    CVBufferRelease(pb);
    h->last = frame;
    return w_int(frame);
}

WValue w_media_decoder_info(WValue hv, WValue keyv) {
    ADecH *h = w_media_handle_get(hv, W_MEDIA_KIND_DECODER, "VideoDecoder#info");
    ADec *d = h->d;
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "width")) return w_int(d->w);
    if (!strcmp(k, "height")) return w_int(d->h);
    if (!strcmp(k, "frames")) return d->frames_hint >= 0 ? w_int(d->frames_hint) : W_NIL;
    if (!strcmp(k, "delivered")) return w_int(d->delivered);
    if (!strcmp(k, "decode_s")) return w_float((double)d->dec_ns / 1e9);
    if (!strcmp(k, "codec")) {
        char s[5] = {(char)(d->codec >> 24), (char)(d->codec >> 16), (char)(d->codec >> 8), (char)d->codec, 0};
        return w_string(s);
    }
    if (!strcmp(k, "rate")) {
        WValue a = w_array_new_empty();
        a = w_array_push(a, w_int(d->num));
        a = w_array_push(a, w_int(d->den));
        return a;
    }
    w_media_raise("VideoDecoder#info: unknown key '%s'", k);
}

WValue w_media_decoder_close(WValue hv) {
    ADecH *h = m_avf_peek(hv, W_MEDIA_KIND_DECODER);
    if (!h) return W_FALSE;
    w_media_handle_drop(hv, W_MEDIA_KIND_DECODER);
    a_dec_free(h->d);
    free(h);
    return W_TRUE;
}

/* ======================================================================
   Transcode: decode -> scale -> encode -> mux, no ffmpeg
   ======================================================================
 *
 * Y'CbCr path (default): frames decode to 8-bit 4:2:0 and the Y' and CbCr
 * planes are resampled separately into the encoder's pool buffer (chroma
 * siting honoured on both sides), so there is no colour conversion at all.
 * RGB path (via: "rgb"): frames decode to BGRA (VideoToolbox's BT.709
 * conversion), go through the RGBA scaler and media.c's converter, the way
 * rendered frames do. Segments are cut every gop frames (closed GOPs) and
 * appended one behind, so the encoder keeps working while the mux writes. */

typedef struct ATrans {
    ADec          *dec;
    MEncoder      *enc;
    AMux          *mux;
    int            via_rgb;
    WMediaScale    py, pc, prgb;
    int            planned;
    int            backend, used;
    uint8_t       *rgb;
    size_t         rgb_len;
    int            w, h, sw, sh;
    int            gop;
    int64_t        start, total, done, dups, drops;
    CVPixelBufferRef prev;
    WMediaSegment *q[4];
    int            nq;
    int64_t        seg_frames;
    uint64_t       t0, scale_ns, wait_ns, mux_ns;
    int            finished;
    char           path[4096];
    AChapter      *chap;            /* until handed to the mux */
    int            nchap;
} ATrans;

static void a_trans_free(ATrans *t) {
    if (!t) return;
    if (t->dec) a_dec_free(t->dec);
    if (t->prev) CVBufferRelease(t->prev);
    for (int i = 0; i < t->nq; i++) w_media_seg_free(t->q[i]);
    if (t->enc) w_media_enc_free(t->enc);
    if (t->mux) {
        char tmp[4200];
        snprintf(tmp, sizeof tmp, "%s", t->mux->tmp);
        a_mux_free(t->mux);
        if (!t->finished) { unlink(t->path); unlink(tmp); }
    }
    if (t->planned) {
        if (t->via_rgb) w_media_scale_free(&t->prgb);
        else { w_media_scale_free(&t->py); w_media_scale_free(&t->pc); }
    }
    free(t->rgb);
    a_chapters_free(t->chap, t->nchap);
    free(t);
}

static WValue a_spec(WValue spec, const char *key) {
    if (!w_is_array(spec)) return W_NIL;
    int64_t n = w_as_array(spec)->size;
    for (int64_t i = 0; i < n; i++) {
        WValue p = w_array_get(spec, w_int(i));
        char k[64];
        if (w_is_array(p) && w_as_array(p)->size >= 2 && w_media_str(w_array_get(p, w_int(0)), k, sizeof k) && !strcmp(k, key))
            return w_array_get(p, w_int(1));
    }
    return W_NIL;
}

static void a_trans_raise(ATrans *t, const char *fmt, ...) __attribute__((noreturn, format(printf, 2, 3)));
static void a_trans_raise(ATrans *t, const char *fmt, ...) {
    (void)t;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    w_media_raise("Transcode: %s", buf);
}

/* Append the oldest queued segment to the mux. */
static void a_trans_flush_one(ATrans *t) {
    /* the segment stays queued until appended, so a raise leaves it to a_trans_free */
    WMediaSegment *s = t->q[0];
    char err[256];
    uint64_t a = m_avf_now_ns();
    if (w_media_seg_finish(s, err, sizeof err) != 0) a_trans_raise(t, "%s", err);
    uint64_t b = m_avf_now_ns();
    t->wait_ns += b - a;
    a_mux_append(t->mux, s);
    t->mux_ns += m_avf_now_ns() - b;
    memmove(t->q, t->q + 1, sizeof(t->q[0]) * (size_t)(t->nq - 1));
    t->nq--;
    w_media_seg_free(s);
}

static void a_trans_cut(ATrans *t) {
    WMediaSegment *s = w_media_enc_cut(t->enc);
    t->seg_frames = 0;
    if (!s) return;
    t->q[t->nq++] = s;
    if (t->nq >= 3) a_trans_flush_one(t);
}

/* Scale one decoded frame into the encoder and submit it. */
static void a_trans_encode(ATrans *t, CVPixelBufferRef src) {
    char err[256];
    uint64_t t0 = m_avf_now_ns();
    if ((int)CVPixelBufferGetWidth(src) != t->sw || (int)CVPixelBufferGetHeight(src) != t->sh)
        a_trans_raise(t, "frame %lld is %dx%d, the source began at %dx%d", (long long)t->done, (int)CVPixelBufferGetWidth(src), (int)CVPixelBufferGetHeight(src), t->sw, t->sh);
    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    if (t->via_rgb) {
        const uint8_t *p = CVPixelBufferGetBaseAddress(src);
        size_t ps = CVPixelBufferGetBytesPerRow(src);
        int b = w_media_scale_run(&t->prgb, t->backend, p, ps, ps * CVPixelBufferGetHeight(src), t->rgb, (size_t)t->w * 4, t->rgb_len, err, sizeof err);
        CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
        if (b < 0) a_trans_raise(t, "scaling: %s", err);
        t->used = b;
        uint64_t t1 = m_avf_now_ns();
        t->scale_ns += t1 - t0;
        int st = w_media_enc_encode_rgb(t->enc, t->rgb, (size_t)t->w * 4);
        if (st != 0) a_trans_raise(t, "VideoToolbox could not encode frame %lld (%d)", (long long)t->done, st);
    } else {
        CVPixelBufferRef out = w_media_enc_buffer(t->enc);
        if (!out) { CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly); a_trans_raise(t, "no pixel buffer from the encoder"); }
        CVPixelBufferLockBaseAddress(out, 0);
        const uint8_t *sy = CVPixelBufferGetBaseAddressOfPlane(src, 0), *sc = CVPixelBufferGetBaseAddressOfPlane(src, 1);
        size_t sys = CVPixelBufferGetBytesPerRowOfPlane(src, 0), scs = CVPixelBufferGetBytesPerRowOfPlane(src, 1);
        uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(out, 0), *dc = CVPixelBufferGetBaseAddressOfPlane(out, 1);
        size_t dys = CVPixelBufferGetBytesPerRowOfPlane(out, 0), dcs = CVPixelBufferGetBytesPerRowOfPlane(out, 1);
        size_t syl = sys * CVPixelBufferGetHeightOfPlane(src, 0), scl = scs * CVPixelBufferGetHeightOfPlane(src, 1);
        size_t dyl = dys * CVPixelBufferGetHeightOfPlane(out, 0), dcl = dcs * CVPixelBufferGetHeightOfPlane(out, 1);
        int b, b2;
        int be = t->backend == W_MEDIA_BACKEND_AUTO ? w_media_scale_default_backend(1, t->py.filter) : t->backend;
        if (be == W_MEDIA_BACKEND_METAL && t->py.out_bits == 8) {
            /* both planes in one command buffer */
            WMediaJob jobs[2] = {{&t->py, sy, sys, syl, dy, dys, dyl}, {&t->pc, sc, scs, scl, dc, dcs, dcl}};
            b = b2 = w_media_scale_metal_jobs(jobs, 2, err, sizeof err) == 0 ? W_MEDIA_BACKEND_METAL : -1;
            if (b < 0) {
                /* Metal would not take these buffers: the CPU from now on */
                t->backend = W_MEDIA_BACKEND_CPU;
                b = w_media_scale_run(&t->py, t->backend, sy, sys, syl, dy, dys, dyl, err, sizeof err);
                b2 = b < 0 ? b : w_media_scale_run(&t->pc, t->backend, sc, scs, scl, dc, dcs, dcl, err, sizeof err);
            }
        } else {
            b = w_media_scale_run(&t->py, t->backend, sy, sys, syl, dy, dys, dyl, err, sizeof err);
            b2 = b < 0 ? b : w_media_scale_run(&t->pc, t->backend, sc, scs, scl, dc, dcs, dcl, err, sizeof err);
        }
        CVPixelBufferUnlockBaseAddress(out, 0);
        CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
        if (b2 < 0) { CVPixelBufferRelease(out); a_trans_raise(t, "scaling: %s", err); }
        t->used = b;
        t->scale_ns += m_avf_now_ns() - t0;
        int st = w_media_enc_submit(t->enc, out);
        if (st != 0) a_trans_raise(t, "VideoToolbox could not encode frame %lld (OSStatus %d)", (long long)t->done, st);
    }
    t->done++;
    if (++t->seg_frames == t->gop) a_trans_cut(t);
}

/* w_media_transcode_new([[key, value], ...]) -> handle. Keys: src (path or
 * segment paths), dst, rate [num, den], start, frames, width, height, crop,
 * rect, filter, scale_backend, via ("yuv" / "rgb"), codec, quality,
 * bitrate, gop, reorder, speed, level, format, audio (nil, "aac", "pcm",
 * "copy"), audio_src, audio_kbps, tc (frame or nil), drop, quanta,
 * chapters, faststart. */
WValue w_media_transcode_new(WValue spec) {
    @autoreleasepool {
        char src[4096], dst[4096], buf[64], err[512];
        int nch = 0;
        AChapter *ch = a_chapters_from(a_spec(spec, "chapters"), &nch, "Transcode");
        ATrans *t = calloc(1, sizeof *t);
        t->chap = ch;
        t->nchap = nch;
        t->t0 = m_avf_now_ns();
        WValue srcv = a_spec(spec, "src");
        if (!w_media_str(a_spec(spec, "dst"), dst, sizeof dst) || !dst[0]) { a_trans_free(t); w_media_raise("Transcode: dst must be a path"); }
        snprintf(t->path, sizeof t->path, "%s", dst);
        WValue ratev = a_spec(spec, "rate");
        int32_t num = (int32_t)w_media_num(m_avf_arr(ratev, 0), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(ratev, 1), 0, "rate");
        if (num <= 0 || den <= 0) { a_trans_free(t); w_media_raise("Transcode: rate must be [num, den]"); }
        t->start = (int64_t)w_media_num(a_spec(spec, "start"), 0, "start");
        t->total = (int64_t)w_media_num(a_spec(spec, "frames"), 0, "frames");
        if (t->total <= 0) { a_trans_free(t); w_media_raise("Transcode: frames must be positive"); }
        w_media_str(a_spec(spec, "via"), buf, sizeof buf);
        t->via_rgb = !strcasecmp(buf, "rgb") || !strcasecmp(buf, "rgba");
        OSType pix = t->via_rgb ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        if (w_is_array(srcv)) {
            int n = 0;
            char **segs = a_paths(srcv, &n);
            t->dec = a_dec_open(NULL, segs, n, num, den, pix, 0, err, sizeof err);
            a_paths_free(segs, n);
            if (t->start > 0 && t->dec) { a_trans_free(t); w_media_raise("Transcode: start: is for movie sources (pass the segments you want)"); }
        } else {
            if (!w_media_str(srcv, src, sizeof src) || !src[0]) { a_trans_free(t); w_media_raise("Transcode: src must be a path or an array of segment paths"); }
            if (access(src, R_OK) != 0) { int e = errno; a_trans_free(t); w_media_raise("Transcode: cannot read %s: %s", src, strerror(e)); }
            t->dec = a_dec_open(src, NULL, 0, num, den, pix, t->start, err, sizeof err);
        }
        if (!t->dec) { a_trans_free(t); w_media_raise("Transcode: %s", err); }
        t->sw = t->dec->w;
        t->sh = t->dec->h;
        t->w = (int)w_media_num(a_spec(spec, "width"), t->sw, "width");
        t->h = (int)w_media_num(a_spec(spec, "height"), t->sh, "height");
        t->gop = (int)w_media_num(a_spec(spec, "gop"), 48, "gop");
        if (t->gop < 1) t->gop = 1;
        char codec[32], level[16], filt[32], bk[32], fmt[16], ac[16], apath[4096];
        w_media_str(a_spec(spec, "codec"), codec, sizeof codec);
        w_media_str(a_spec(spec, "level"), level, sizeof level);
        w_media_str(a_spec(spec, "filter"), filt, sizeof filt);
        w_media_str(a_spec(spec, "scale_backend"), bk, sizeof bk);
        int filter = w_media_filter_id(filt), backend = w_media_backend_id(bk);
        if (filter < 0) { a_trans_free(t); w_media_raise("Transcode: unknown filter '%s'", filt); }
        if (backend < 0) { a_trans_free(t); w_media_raise("Transcode: unknown scale backend '%s'", bk); }
        t->backend = backend;
        WValue reorderv = a_spec(spec, "reorder");
        t->enc = w_media_enc_open(codec[0] ? codec : "h264", t->w, t->h, num, den, w_media_num(a_spec(spec, "quality"), -1.0, "quality"),
                                  (int64_t)w_media_num(a_spec(spec, "bitrate"), 0, "bitrate"), t->gop, t->via_rgb ? "bgra" : "rgba", "left",
                                  reorderv == W_NIL ? 1 : reorderv > 1, a_spec(spec, "speed") > 1, level, err, sizeof err);
        if (!t->enc) { a_trans_free(t); w_media_raise("Transcode: %s", err); }
        /* geometry */
        double crop[4] = {0, 0, t->sw, t->sh};
        int rect[4] = {0, 0, t->w, t->h};
        WValue cv = a_spec(spec, "crop"), rv = a_spec(spec, "rect");
        if (cv != W_NIL) for (int i = 0; i < 4; i++) crop[i] = w_media_num(m_avf_arr(cv, i), crop[i], "crop");
        if (rv != W_NIL) for (int i = 0; i < 4; i++) rect[i] = (int)w_media_num(m_avf_arr(rv, i), rect[i], "rect");
        int bits = w_media_enc_bits(t->enc), vsub = w_media_enc_vsub(t->enc);
        int rc;
        if (t->via_rgb) {
            uint8_t fill[4] = {0, 0, 0, 255};
            rc = w_media_scale_plan(&t->prgb, 4, W_MEDIA_ALPHA_OPAQUE, filter, t->sw, t->sh, t->w, t->h, crop, rect, 1, 1, 0.5, 0.5,
                                    1, 1, 0.5, 0.5, fill, 8, err, sizeof err);
            t->rgb_len = (size_t)t->w * 4 * (size_t)t->h;
            if (rc == 0 && posix_memalign((void **)&t->rgb, 16384, (t->rgb_len + 16383) & ~(size_t)16383) != 0) { t->rgb = NULL; rc = -1; snprintf(err, sizeof err, "out of memory"); }
        } else {
            uint8_t fy[4] = {16, 0, 0, 0}, fc[4] = {128, 128, 0, 0};
            int s = t->dec->siting;
            double osx = s == 1 ? 1.0 : 0.5, osy = s == 2 ? 0.5 : 1.0;
            rc = w_media_scale_plan(&t->py, 1, W_MEDIA_ALPHA_NONE, filter, t->sw, t->sh, t->w, t->h, crop, rect, 1, 1, 0.5, 0.5,
                                    1, 1, 0.5, 0.5, fy, bits, err, sizeof err);
            if (rc == 0) {
                rc = w_media_scale_plan(&t->pc, 2, W_MEDIA_ALPHA_NONE, filter, (t->sw + 1) / 2, (t->sh + 1) / 2, t->w / 2, t->h / vsub,
                                        crop, rect, 2, 2, osx, osy, 2, vsub, 0.5, vsub == 2 ? 1.0 : 0.5, fc, bits, err, sizeof err);
                if (rc != 0) w_media_scale_free(&t->py);
            }
        }
        if (rc != 0) { a_trans_free(t); w_media_raise("Transcode: %s", err); }
        t->planned = 1;
        /* mux */
        AMuxOpts o;
        memset(&o, 0, sizeof o);
        o.path = dst;
        w_media_str(a_spec(spec, "format"), fmt, sizeof fmt);
        o.format = fmt[0] ? fmt : NULL;
        o.num = num;
        o.den = den;
        w_media_str(a_spec(spec, "audio"), ac, sizeof ac);
        if (ac[0] && strcasecmp(ac, "none")) {
            if (!w_media_str(a_spec(spec, "audio_src"), apath, sizeof apath) || !apath[0]) snprintf(apath, sizeof apath, "%s", w_is_array(srcv) ? "" : src);
            if (!apath[0]) { a_trans_free(t); w_media_raise("Transcode: audio: segments carry no audio; give audio_src: (a WAV or a movie)"); }
            o.audio = apath;
            o.audio_codec = ac;
            o.audio_kbps = (int)w_media_num(a_spec(spec, "audio_kbps"), 0, "audio_kbps");
            o.audio_start_frame = t->start;
        }
        WValue tcv = a_spec(spec, "tc");
        if (tcv != W_NIL) {
            o.has_tc = 1;
            o.tc_frame = (int64_t)w_media_num(tcv, 0, "tc");
            o.tc_drop = a_spec(spec, "drop") > 1;
            o.tc_quanta = (int)w_media_num(a_spec(spec, "quanta"), 0, "quanta");
        }
        WValue fs = a_spec(spec, "faststart");
        o.faststart = fs == W_NIL ? 1 : fs > 1;
        o.frames = t->total;
        t->mux = a_mux_open(&o, err, sizeof err);
        if (!t->mux) { a_trans_free(t); w_media_raise("Transcode: %s", err); }
        a_mux_set_chapters(t->mux, t->chap, t->nchap);
        a_chapters_free(t->chap, t->nchap);
        t->chap = NULL;
        t->nchap = 0;
        return w_int(w_media_handle_new(t, W_MEDIA_KIND_TRANSCODE));
    }
}

/* w_media_transcode_step(h, max_frames) -> [frames done, frames in total] */
WValue w_media_transcode_step(WValue hv, WValue nv) {
    ATrans *t = w_media_handle_get(hv, W_MEDIA_KIND_TRANSCODE, "Transcode#step");
    int64_t n = (int64_t)w_media_num(nv, 240, "frames");
    @autoreleasepool {
        char err[512];
        int64_t k = 0;
        while (t->done < t->total && k < n) {
            CVPixelBufferRef pb = NULL;
            int64_t f = 0;
            int r = a_dec_next(t->dec, &pb, &f, err, sizeof err);
            if (r < 0) a_trans_raise(t, "decoding: %s", err);
            if (r == 0) {
                /* the source ran out: hold the last frame */
                if (!t->prev) a_trans_raise(t, "the source has no frames");
                a_trans_encode(t, t->prev);
                t->dups++;
                k++;
                continue;
            }
            f -= t->start;
            if (f < t->done) { CVBufferRelease(pb); t->drops++; continue; }
            while (f > t->done && t->prev && t->done < t->total) { a_trans_encode(t, t->prev); t->dups++; k++; }
            if (t->done >= t->total) { CVBufferRelease(pb); break; }
            a_trans_encode(t, pb);
            if (t->prev) CVBufferRelease(t->prev);
            t->prev = pb;
            k++;
        }
        WValue out = w_array_new_empty();
        out = w_array_push(out, w_int(t->done));
        out = w_array_push(out, w_int(t->total));
        return out;
    }
}

/* w_media_transcode_finish(h) -> [[key, value], ...]: finishes the file and
 * frees the transcoder. */
WValue w_media_transcode_finish(WValue hv) {
    ATrans *t = w_media_handle_get(hv, W_MEDIA_KIND_TRANSCODE, "Transcode#finish");
    @autoreleasepool {
        if (t->done < t->total) a_trans_raise(t, "finish after %lld of %lld frames (step until done)", (long long)t->done, (long long)t->total);
        if (t->seg_frames > 0) {
            WMediaSegment *s = w_media_enc_cut(t->enc);
            t->seg_frames = 0;
            if (s) t->q[t->nq++] = s;
        }
        while (t->nq > 0) a_trans_flush_one(t);
        int64_t out[5];
        uint64_t a = m_avf_now_ns();
        a_mux_finish(t->mux, out);
        t->mux_ns += m_avf_now_ns() - a;
        t->finished = 1;
        WValue r = w_array_new_empty();
        r = w_array_push(r, a_pair("frames", w_int(out[0])));
        r = w_array_push(r, a_pair("duplicated", w_int(t->dups)));
        r = w_array_push(r, a_pair("dropped", w_int(t->drops)));
        r = w_array_push(r, a_pair("audio_samples", w_int(out[1])));
        r = w_array_push(r, a_pair("video_bytes", w_int(out[3])));
        r = w_array_push(r, a_pair("file_bytes", w_int(out[4])));
        r = w_array_push(r, a_pair("seconds", w_float((double)(m_avf_now_ns() - t->t0) / 1e9)));
        r = w_array_push(r, a_pair("decode_s", w_float((double)t->dec->dec_ns / 1e9)));
        r = w_array_push(r, a_pair("scale_s", w_float((double)t->scale_ns / 1e9)));
        r = w_array_push(r, a_pair("convert_s", w_float(w_media_enc_seconds(t->enc, 0))));
        r = w_array_push(r, a_pair("submit_s", w_float(w_media_enc_seconds(t->enc, 1))));
        r = w_array_push(r, a_pair("encode_wait_s", w_float(t->wait_ns / 1e9 + w_media_enc_seconds(t->enc, 2))));
        r = w_array_push(r, a_pair("mux_s", w_float((double)t->mux_ns / 1e9)));
        r = w_array_push(r, a_pair("scale_backend", w_string(w_media_backend_name(t->used))));
        r = w_array_push(r, a_pair("via", w_string(t->via_rgb ? "rgb" : "yuv")));
        r = w_array_push(r, a_pair("source", w_string((char[]){(char)(t->dec->codec >> 24), (char)(t->dec->codec >> 16), (char)(t->dec->codec >> 8), (char)t->dec->codec, 0})));
        w_media_handle_drop(hv, W_MEDIA_KIND_TRANSCODE);
        a_trans_free(t);
        return r;
    }
}

/* w_media_transcode_free(h): abandon a transcode (removes the partial file). */
WValue w_media_transcode_free(WValue hv) {
    ATrans *t = m_avf_peek(hv, W_MEDIA_KIND_TRANSCODE);
    if (!t) return W_FALSE;
    w_media_handle_drop(hv, W_MEDIA_KIND_TRANSCODE);
    a_trans_free(t);
    return W_TRUE;
}

/* ======================================================================
   Probe (MediaVerify facts)
   ====================================================================== */

static NSString *a_nspath(WValue pathv, const char *what) {
    char path[4096];
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("%s: path must be a string", what);
    if (access(path, R_OK) != 0) w_media_raise("%s: cannot read %s: %s", what, path, strerror(errno));
    return [NSString stringWithUTF8String:path];
}

/* Top-level boxes: the major brand and whether moov precedes mdat. */
static void a_layout(const char *path, uint32_t *brand, int *moov_first) {
    *brand = 0;
    *moov_first = -1;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return;
    struct stat st;
    fstat(fd, &st);
    int64_t off = 0;
    int seen_moov = 0;
    for (int i = 0; i < 64 && off + 8 <= st.st_size; i++) {
        uint8_t h[16];
        if (pread(fd, h, 16, off) < 12) break;
        int64_t sz = a_rd32(h);
        uint32_t t = a_rd32(h + 4);
        if (sz == 1) sz = (int64_t)a_rd64(h + 8);
        else if (sz == 0) sz = st.st_size - off;
        if (t == A_FOURCC('f','t','y','p')) *brand = a_rd32(h + 8);
        if (t == A_FOURCC('m','o','o','v')) seen_moov = 1;
        if (t == A_FOURCC('m','d','a','t') && *moov_first < 0 && sz > 16) *moov_first = seen_moov;
        if (sz < 8) break;
        off += sz;
    }
    close(fd);
}

static WValue a_ext_str(CFDictionaryRef ext, CFStringRef key) {
    return ext ? a_cfstr(CFDictionaryGetValue(ext, key)) : W_NIL;
}

/* Nero chapters from moov/udta/chpl: [[title, start in 100 ns], ...], or nil. */
static WValue a_probe_chpl(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return W_NIL;
    ATop top[64];
    int ntop = 0, moov_i = -1;
    ABox root;
    char err[256];
    if (a_read_moov(fd, path, top, &ntop, &moov_i, &root, err, sizeof err) != 0) { close(fd); return W_NIL; }
    close(fd);
    WValue out = W_NIL;
    ABox *u = a_box_find(&root.kid[0], A_FOURCC('u','d','t','a'));
    if (u) {
        size_t o = 8;
        while (o + 8 <= u->len) {
            uint32_t sz = a_rd32(u->raw + o), t = a_rd32(u->raw + o + 4);
            if (sz < 8 || o + sz > u->len) break;
            if (t == A_FOURCC('c','h','p','l') && sz >= 17) {
                const uint8_t *b = u->raw + o;
                int n = b[16];
                size_t at = 17;
                out = w_array_new_empty();
                for (int i = 0; i < n && at + 9 <= sz; i++) {
                    uint64_t st = a_rd64(b + at);
                    size_t k = b[at + 8];
                    if (at + 9 + k > sz) break;
                    char title[256];
                    memcpy(title, b + at + 9, k);
                    title[k] = 0;
                    WValue e = w_array_new_empty();
                    e = w_array_push(e, w_string(title));
                    e = w_array_push(e, w_int((int64_t)st));
                    out = w_array_push(out, e);
                    at += 9 + k;
                }
                break;
            }
            o += sz;
        }
    }
    a_box_free(&root);
    return out;
}

/* AVFoundation's chapters: [[title, [start value, timescale], [duration value, timescale]], ...] */
static WValue a_probe_chapters(AVAsset *asset) {
    NSArray *locs = asset.availableChapterLocales;
    NSArray *groups = nil;
    if (locs.count) groups = [asset chapterMetadataGroupsWithTitleLocale:locs.firstObject containingItemsWithCommonKeys:@[]];
    if (!groups.count) groups = [asset chapterMetadataGroupsBestMatchingPreferredLanguages:@[@"und", @"en"]];
    WValue out = w_array_new_empty();
    for (AVTimedMetadataGroup *g in groups) {
        NSString *title = nil;
        for (AVMetadataItem *it in g.items) {
            if ([it.commonKey isEqualToString:AVMetadataCommonKeyTitle] || title == nil) title = it.stringValue;
        }
        WValue e = w_array_new_empty();
        e = w_array_push(e, title ? w_string(title.UTF8String) : W_NIL);
        e = w_array_push(e, a_time(g.timeRange.start));
        e = w_array_push(e, a_time(g.timeRange.duration));
        out = w_array_push(out, e);
    }
    return out;
}

/* w_media_probe(path, read_samples, decode_audio) -> [[key, value], …] */
WValue w_media_probe(WValue pathv, WValue samplesv, WValue audiov) {
    @autoreleasepool {
        NSString *path = a_nspath(pathv, "MediaVerify");
        WValue out = w_array_new_empty();
        uint32_t brand;
        int moov_first;
        a_layout(path.UTF8String, &brand, &moov_first);
        out = w_array_push(out, a_pair("brand", a_fourcc(brand)));
        out = w_array_push(out, a_pair("moov_first", moov_first < 0 ? W_NIL : (moov_first ? W_TRUE : W_FALSE)));
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        out = w_array_push(out, a_pair("duration", a_time(asset.duration)));
        NSArray *vt = [asset tracksWithMediaType:AVMediaTypeVideo];
        NSArray *at = [asset tracksWithMediaType:AVMediaTypeAudio];
        NSArray *tt = [asset tracksWithMediaType:AVMediaTypeTimecode];
        out = w_array_push(out, a_pair("video_tracks", w_int((int64_t)vt.count)));
        out = w_array_push(out, a_pair("audio_tracks", w_int((int64_t)at.count)));
        out = w_array_push(out, a_pair("timecode_tracks", w_int((int64_t)tt.count)));
        out = w_array_push(out, a_pair("text_tracks", w_int((int64_t)[asset tracksWithMediaType:AVMediaTypeText].count)));
        out = w_array_push(out, a_pair("chapter_locales", w_int((int64_t)asset.availableChapterLocales.count)));
        out = w_array_push(out, a_pair("chapters", a_probe_chapters(asset)));
        out = w_array_push(out, a_pair("chpl", a_probe_chpl(path.UTF8String)));
        if (vt.count) {
            AVAssetTrack *v = vt[0];
            out = w_array_push(out, a_pair("sample_descriptions", w_int((int64_t)v.formatDescriptions.count)));
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)v.formatDescriptions.firstObject;
            out = w_array_push(out, a_pair("nominal_fps", w_float(v.nominalFrameRate)));
            out = w_array_push(out, a_pair("min_frame_duration", a_time(v.minFrameDuration)));
            out = w_array_push(out, a_pair("timescale", w_int(v.naturalTimeScale)));
            out = w_array_push(out, a_pair("video_start", a_time(v.timeRange.start)));
            out = w_array_push(out, a_pair("video_duration", a_time(v.timeRange.duration)));
            out = w_array_push(out, a_pair("video_edits", w_int((int64_t)v.segments.count)));
            /* Passthrough reads report media-time PTS; the first edit maps
             * them to the presentation timeline (B-frame files start their
             * media at the DTS delay). */
            int64_t edit_offset = 0;
            if (v.segments.count >= 1) {
                CMTimeMapping tm = v.segments.firstObject.timeMapping;
                CMTime d = CMTimeSubtract(tm.target.start, tm.source.start);
                edit_offset = CMTimeConvertScale(d, v.naturalTimeScale, kCMTimeRoundingMethod_Default).value;
            }
            out = w_array_push(out, a_pair("video_edit_offset", w_int(edit_offset)));
            out = w_array_push(out, a_pair("timecode_associated", w_int((int64_t)[v associatedTracksOfType:AVTrackAssociationTypeTimecode].count)));
            if (fd) {
                uint32_t sub = CMFormatDescriptionGetMediaSubType(fd);
                CMVideoDimensions d = CMVideoFormatDescriptionGetDimensions(fd);
                CFDictionaryRef ext = CMFormatDescriptionGetExtensions(fd);
                out = w_array_push(out, a_pair("codec", a_fourcc(sub)));
                out = w_array_push(out, a_pair("width", w_int(d.width)));
                out = w_array_push(out, a_pair("height", w_int(d.height)));
                out = w_array_push(out, a_pair("primaries", a_ext_str(ext, kCMFormatDescriptionExtension_ColorPrimaries)));
                out = w_array_push(out, a_pair("transfer", a_ext_str(ext, kCMFormatDescriptionExtension_TransferFunction)));
                out = w_array_push(out, a_pair("matrix", a_ext_str(ext, kCMFormatDescriptionExtension_YCbCrMatrix)));
                out = w_array_push(out, a_pair("chroma_location", a_ext_str(ext, kCMFormatDescriptionExtension_ChromaLocationTopField)));
                CFTypeRef fr = ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_FullRangeVideo) : NULL;
                out = w_array_push(out, a_pair("full_range", fr && CFGetTypeID(fr) == CFBooleanGetTypeID() ? (CFBooleanGetValue(fr) ? W_TRUE : W_FALSE) : W_NIL));
                CFDictionaryRef atoms = ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) : NULL;
                CFDataRef rec = NULL;
                int hevc = 0;
                if (atoms && CFGetTypeID(atoms) == CFDictionaryGetTypeID()) {
                    rec = CFDictionaryGetValue(atoms, CFSTR("avcC"));
                    if (!rec) { rec = CFDictionaryGetValue(atoms, CFSTR("hvcC")); hevc = rec != NULL; }
                }
                if (rec) {
                    WMediaVui vui;
                    w_media_vui_parse(CFDataGetBytePtr(rec), (size_t)CFDataGetLength(rec), hevc, &vui);
                    out = w_array_push(out, a_pair("vui_ok", vui.ok ? W_TRUE : W_FALSE));
                    out = w_array_push(out, a_pair("vui_present", vui.vui_present ? W_TRUE : W_FALSE));
                    out = w_array_push(out, a_pair("vui_primaries", w_int(vui.primaries)));
                    out = w_array_push(out, a_pair("vui_transfer", w_int(vui.transfer)));
                    out = w_array_push(out, a_pair("vui_matrix", w_int(vui.matrix)));
                    out = w_array_push(out, a_pair("vui_full_range", vui.video_signal_type_present ? w_int(vui.full_range) : W_NIL));
                    out = w_array_push(out, a_pair("vui_chroma_loc", w_int(vui.chroma_loc_top)));
                    out = w_array_push(out, a_pair("profile", w_int(vui.profile)));
                    out = w_array_push(out, a_pair("level", w_int(vui.level)));
                    out = w_array_push(out, a_pair("bit_depth", w_int(vui.bit_depth)));
                    out = w_array_push(out, a_pair("chroma_format", w_int(vui.chroma_format)));
                    out = w_array_push(out, a_pair("parameter_sets", w_int(vui.vps_count + vui.sps_count + vui.pps_count)));
                }
            }
            if (samplesv > 1) {
                NSError *err = nil;
                AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
                AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:v outputSettings:nil];
                o.alwaysCopiesSampleData = NO;
                [r addOutput:o];
                WValue pts = w_array_new_empty(), dur = w_array_new_empty(), dts = w_array_new_empty();
                int64_t n = 0, sync = 0, bytes = 0, mixed_ts = 0;
                int32_t ts = v.naturalTimeScale;
                if ([r startReading]) {
                    CMSampleBufferRef sb;
                    while ((sb = [o copyNextSampleBuffer])) {
                        CMItemCount cnt = CMSampleBufferGetNumSamples(sb);
                        for (CMItemCount k = 0; k < cnt; k++) {
                            CMSampleTimingInfo ti;
                            if (CMSampleBufferGetSampleTimingInfo(sb, k, &ti) != noErr) continue;
                            CMTime p = CMTimeConvertScale(ti.presentationTimeStamp, ts, kCMTimeRoundingMethod_Default);
                            CMTime d = CMTimeConvertScale(ti.duration, ts, kCMTimeRoundingMethod_Default);
                            if (CMTimeCompare(p, ti.presentationTimeStamp) != 0 || CMTimeCompare(d, ti.duration) != 0) mixed_ts++;
                            pts = w_array_push(pts, w_int(p.value));
                            dur = w_array_push(dur, w_int(d.value));
                            dts = w_array_push(dts, CMTIME_IS_VALID(ti.decodeTimeStamp) ? w_int(CMTimeConvertScale(ti.decodeTimeStamp, ts, kCMTimeRoundingMethod_Default).value) : W_NIL);
                            n++;
                        }
                        CFArrayRef att = CMSampleBufferGetSampleAttachmentsArray(sb, false);
                        int s1 = 1;
                        if (att && CFArrayGetCount(att)) {
                            CFBooleanRef ns = CFDictionaryGetValue(CFArrayGetValueAtIndex(att, 0), kCMSampleAttachmentKey_NotSync);
                            if (ns && CFBooleanGetValue(ns)) s1 = 0;
                        }
                        sync += s1;
                        bytes += (int64_t)CMSampleBufferGetTotalSampleSize(sb);
                        CFRelease(sb);
                    }
                }
                out = w_array_push(out, a_pair("read_status", w_int(r.status)));
                out = w_array_push(out, a_pair("frames", w_int(n)));
                out = w_array_push(out, a_pair("sync_samples", w_int(sync)));
                out = w_array_push(out, a_pair("video_bytes", w_int(bytes)));
                out = w_array_push(out, a_pair("inexact_times", w_int(mixed_ts)));
                out = w_array_push(out, a_pair("pts", pts));
                out = w_array_push(out, a_pair("durations", dur));
                out = w_array_push(out, a_pair("dts", dts));
                [o release];
                [r release];
            }
        }
        if (tt.count) {
            AVAssetTrack *t = tt[0];
            out = w_array_push(out, a_pair("timecode_start", a_time(t.timeRange.start)));
            out = w_array_push(out, a_pair("timecode_duration", a_time(t.timeRange.duration)));
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
            if (fd) {
                out = w_array_push(out, a_pair("timecode_format", a_fourcc(CMFormatDescriptionGetMediaSubType(fd))));
                out = w_array_push(out, a_pair("timecode_flags", w_int(CMTimeCodeFormatDescriptionGetTimeCodeFlags(fd))));
                out = w_array_push(out, a_pair("timecode_quanta", w_int(CMTimeCodeFormatDescriptionGetFrameQuanta(fd))));
                out = w_array_push(out, a_pair("timecode_frame_duration", a_time(CMTimeCodeFormatDescriptionGetFrameDuration(fd))));
            }
            NSError *err = nil;
            AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
            AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:t outputSettings:nil];
            [r addOutput:o];
            int64_t first = -1, count = 0;
            if ([r startReading]) {
                CMSampleBufferRef sb;
                while ((sb = [o copyNextSampleBuffer])) {
                    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
                    if (bb && CMBlockBufferGetDataLength(bb) >= 4 && first < 0) {
                        uint8_t b4[4];
                        CMBlockBufferCopyDataBytes(bb, 0, 4, b4);
                        first = (int32_t)a_rd32(b4);
                    }
                    count += CMSampleBufferGetNumSamples(sb);
                    CFRelease(sb);
                }
            }
            out = w_array_push(out, a_pair("timecode_frame", first >= 0 ? w_int(first) : W_NIL));
            out = w_array_push(out, a_pair("timecode_samples", w_int(count)));
            [o release];
            [r release];
        }
        if (at.count) {
            AVAssetTrack *a = at[0];
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)a.formatDescriptions.firstObject;
            const AudioStreamBasicDescription *asbd = fd ? CMAudioFormatDescriptionGetStreamBasicDescription(fd) : NULL;
            out = w_array_push(out, a_pair("audio_codec", a_fourcc(fd ? CMFormatDescriptionGetMediaSubType(fd) : 0)));
            out = w_array_push(out, a_pair("audio_rate", asbd ? w_int((int64_t)asbd->mSampleRate) : W_NIL));
            out = w_array_push(out, a_pair("audio_channels", asbd ? w_int(asbd->mChannelsPerFrame) : W_NIL));
            out = w_array_push(out, a_pair("audio_start", a_time(a.timeRange.start)));
            out = w_array_push(out, a_pair("audio_duration", a_time(a.timeRange.duration)));
            out = w_array_push(out, a_pair("audio_edits", w_int((int64_t)a.segments.count)));
            if (a.segments.count) {
                AVAssetTrackSegment *seg = a.segments.firstObject;
                out = w_array_push(out, a_pair("audio_edit_media_start", a_time(seg.timeMapping.source.start)));
            }
            if (audiov > 1) {
                NSError *err = nil;
                AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
                NSDictionary *pcm = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32,
                                      AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
                AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:a outputSettings:pcm];
                [r addOutput:o];
                int64_t frames = 0;
                CMTime first = kCMTimeInvalid;
                if ([r startReading]) {
                    CMSampleBufferRef sb;
                    while ((sb = [o copyNextSampleBuffer])) {
                        if (!CMTIME_IS_VALID(first)) first = CMSampleBufferGetPresentationTimeStamp(sb);
                        frames += CMSampleBufferGetNumSamples(sb);
                        CFRelease(sb);
                    }
                }
                out = w_array_push(out, a_pair("audio_decoded_frames", w_int(frames)));
                out = w_array_push(out, a_pair("audio_first_pts", a_time(first)));
                [o release];
                [r release];
            }
        }
        return out;
    }
}

/* Decoded pixel format for a track: 8-bit 4:2:0 for 8-bit codecs, the
 * matching 10-bit bi-planar layout otherwise. */
static OSType a_native_format(CMFormatDescriptionRef fd) {
    uint32_t sub = CMFormatDescriptionGetMediaSubType(fd);
    if (sub == kCMVideoCodecType_AppleProRes422 || sub == kCMVideoCodecType_AppleProRes422HQ ||
        sub == kCMVideoCodecType_AppleProRes422LT || sub == kCMVideoCodecType_AppleProRes422Proxy)
        return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange;
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions(fd);
    CFNumberRef bpc = ext ? CFDictionaryGetValue(ext, CFSTR("BitsPerComponent")) : NULL;
    int bits = 8;
    if (bpc) CFNumberGetValue(bpc, kCFNumberIntType, &bits);
    return bits > 8 ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
}

/* w_media_frame_probe(path, frames, points, mode) -> per frame, per point
 * [Y, Cb, Cr] codes (mode "yuv": the decoder's native bi-planar output, no
 * conversion) or [R, G, B] (mode "rgb": BGRA through the tagged matrix). */
WValue w_media_frame_probe(WValue pathv, WValue framesv, WValue pointsv, WValue modev) {
    @autoreleasepool {
        NSString *path = a_nspath(pathv, "MediaVerify.frame_probe");
        char mode[8];
        w_media_str(modev, mode, sizeof mode);
        int rgb = !strcasecmp(mode, "rgb");
        if (!w_is_array(framesv) || !w_is_array(pointsv)) w_media_raise("MediaVerify.frame_probe: frames and points must be arrays");
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        NSArray *vt = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (!vt.count) w_media_raise("MediaVerify.frame_probe: no video track");
        AVAssetTrack *v = vt[0];
        CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)v.formatDescriptions.firstObject;
        OSType pix = rgb ? kCVPixelFormatType_32BGRA : a_native_format(fd);
        CMTime fdur = v.minFrameDuration;
        int64_t nf = w_as_array(framesv)->size, np = w_as_array(pointsv)->size;
        WValue out = w_array_new_empty();
        for (int64_t fi = 0; fi < nf; fi++) {
            int64_t want = (int64_t)w_media_num(w_array_get(framesv, w_int(fi)), 0, "frame");
            NSError *err = nil;
            AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
            r.timeRange = CMTimeRangeMake(CMTimeMultiply(fdur, (int32_t)want), fdur);
            AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:v outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(pix)}];
            [r addOutput:o];
            WValue row = w_array_new_empty();
            if ([r startReading]) {
                CMSampleBufferRef sb = [o copyNextSampleBuffer];
                if (sb) {
                    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
                    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                    size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
                    for (int64_t pi = 0; pi < np; pi++) {
                        WValue pt = w_array_get(pointsv, w_int(pi));
                        int64_t x = (int64_t)w_media_num(w_array_get(pt, w_int(0)), 0, "x");
                        int64_t y = (int64_t)w_media_num(w_array_get(pt, w_int(1)), 0, "y");
                        if (x < 0) x = 0;
                        if (y < 0) y = 0;
                        if ((size_t)x >= w) x = (int64_t)w - 1;
                        if ((size_t)y >= h) y = (int64_t)h - 1;
                        WValue px = w_array_new_empty();
                        if (rgb) {
                            const uint8_t *b = (const uint8_t *)CVPixelBufferGetBaseAddress(pb) + (size_t)y * CVPixelBufferGetBytesPerRow(pb) + (size_t)x * 4;
                            px = w_array_push(px, w_int(b[2]));
                            px = w_array_push(px, w_int(b[1]));
                            px = w_array_push(px, w_int(b[0]));
                        } else {
                            int ten = pix != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
                            int vsub = pix == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange ? 1 : 2;
                            const uint8_t *yp = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 0) + (size_t)y * CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
                            const uint8_t *cp = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 1) + (size_t)(y / vsub) * CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
                            if (ten) {
                                const uint16_t *y16 = (const uint16_t *)(const void *)yp, *c16 = (const uint16_t *)(const void *)cp;
                                px = w_array_push(px, w_int(y16[x] >> 6));
                                px = w_array_push(px, w_int(c16[(x / 2) * 2] >> 6));
                                px = w_array_push(px, w_int(c16[(x / 2) * 2 + 1] >> 6));
                            } else {
                                px = w_array_push(px, w_int(yp[x]));
                                px = w_array_push(px, w_int(cp[(x / 2) * 2]));
                                px = w_array_push(px, w_int(cp[(x / 2) * 2 + 1]));
                            }
                        }
                        row = w_array_push(row, px);
                    }
                    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                    CFRelease(sb);
                }
            }
            out = w_array_push(out, row);
            [o release];
            [r release];
        }
        return out;
    }
}

/* w_media_sync_scan(path, max_frames, _) -> [mean luma per frame (8-bit
 * scale), click peaks in samples (Float, sub-sample), audio rate, first
 * audio PTS in samples]. Clicks are local maxima of |x| above half the
 * loudest peak, at least 100 ms apart, refined by parabolic interpolation. */
WValue w_media_sync_scan(WValue pathv, WValue maxv, WValue unusedv) {
    (void)unusedv;
    @autoreleasepool {
        NSString *path = a_nspath(pathv, "MediaVerify.sync_scan");
        int limited = maxv != W_NIL;
        int64_t max_frames = limited ? (int64_t)w_media_num(maxv, 0, "max_frames") : INT64_MAX;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        NSArray *vt = [asset tracksWithMediaType:AVMediaTypeVideo];
        NSArray *at = [asset tracksWithMediaType:AVMediaTypeAudio];
        WValue lum = w_array_new_empty();
        CMTime span = kCMTimePositiveInfinity;
        if (vt.count) {
            AVAssetTrack *v = vt[0];
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)v.formatDescriptions.firstObject;
            OSType pix = a_native_format(fd);
            NSError *err = nil;
            AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
            if (limited) {
                span = CMTimeMultiply(v.minFrameDuration, (int32_t)max_frames);
                r.timeRange = CMTimeRangeMake(kCMTimeZero, span);
            }
            AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:v outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(pix)}];
            [r addOutput:o];
            int64_t n = 0;
            if ([r startReading]) {
                CMSampleBufferRef sb;
                while (n < max_frames && (sb = [o copyNextSampleBuffer])) {
                    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
                    if (pb) {
                        CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                        size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), s = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
                        const uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
                        int ten = pix != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
                        double sum = 0;
                        int64_t cnt = 0;
                        for (size_t y = 0; y < h; y += 4) {
                            for (size_t x = 0; x < w; x += 4) {
                                sum += ten ? (double)(((const uint16_t *)(const void *)(yp + y * s))[x] >> 6) / 4.0 : (double)yp[y * s + x];
                                cnt++;
                            }
                        }
                        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                        lum = w_array_push(lum, w_float(cnt ? sum / (double)cnt : 0));
                        n++;
                    }
                    CFRelease(sb);
                }
            }
            [o release];
            [r release];
        }
        WValue clicks = w_array_new_empty();
        int64_t rate = 0;
        double first_pts = 0;
        if (at.count) {
            AVAssetTrack *a = at[0];
            NSError *err = nil;
            AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
            if (limited && CMTIME_IS_NUMERIC(span)) r.timeRange = CMTimeRangeMake(kCMTimeZero, span);
            NSDictionary *pcm = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32,
                                  AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
            AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:a outputSettings:pcm];
            [r addOutput:o];
            float *mono = NULL;
            size_t n = 0, cap = 0;
            int first = 1;
            if ([r startReading]) {
                CMSampleBufferRef sb;
                while ((sb = [o copyNextSampleBuffer])) {
                    CMFormatDescriptionRef afd = CMSampleBufferGetFormatDescription(sb);
                    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afd);
                    int ch = asbd ? (int)asbd->mChannelsPerFrame : 1;
                    rate = asbd ? (int64_t)asbd->mSampleRate : 0;
                    if (first) {
                        CMTime p = CMSampleBufferGetPresentationTimeStamp(sb);
                        first_pts = CMTIME_IS_NUMERIC(p) ? CMTimeGetSeconds(p) * (double)rate : 0;
                        first = 0;
                    }
                    CMItemCount k = CMSampleBufferGetNumSamples(sb);
                    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
                    size_t len = CMBlockBufferGetDataLength(bb);
                    float *tmp = malloc(len ? len : 4);
                    CMBlockBufferCopyDataBytes(bb, 0, len, tmp);
                    if (n + (size_t)k > cap) { cap = (n + (size_t)k) * 2; mono = realloc(mono, cap * sizeof(float)); }
                    for (CMItemCount i = 0; i < k; i++) mono[n + (size_t)i] = tmp[(size_t)i * (size_t)ch];
                    n += (size_t)k;
                    free(tmp);
                    CFRelease(sb);
                }
            }
            float peak = 0;
            for (size_t i = 0; i < n; i++) if (fabsf(mono[i]) > peak) peak = fabsf(mono[i]);
            if (peak > 0.01f && rate > 0) {
                float thr = peak * 0.5f;
                size_t gap = (size_t)rate / 10, i = 1;
                while (i + 1 < n) {
                    if (fabsf(mono[i]) >= thr) {
                        size_t best = i, end = i + gap / 4 < n ? i + gap / 4 : n - 1;
                        for (size_t j = i; j <= end; j++) if (fabsf(mono[j]) > fabsf(mono[best])) best = j;
                        double y0 = fabsf(mono[best > 0 ? best - 1 : best]), y1 = fabsf(mono[best]), y2 = fabsf(mono[best + 1 < n ? best + 1 : best]);
                        double den = y0 - 2 * y1 + y2, off = den != 0 ? 0.5 * (y0 - y2) / den : 0;
                        clicks = w_array_push(clicks, w_float((double)best + off + first_pts));
                        i = best + gap;
                    } else i++;
                }
            }
            free(mono);
            [o release];
            [r release];
        }
        WValue out = w_array_new_empty();
        out = w_array_push(out, lum);
        out = w_array_push(out, clicks);
        out = w_array_push(out, w_int(rate));
        out = w_array_push(out, w_float(first_pts));
        return out;
    }
}

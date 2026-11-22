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
#import <AudioToolbox/AudioToolbox.h>
#import <Metal/Metal.h>
#include <dispatch/dispatch.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/clonefile.h>
#include <sys/file.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif
#include <sys/utsname.h>
#include <sys/sysctl.h>
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
#include <sys/statvfs.h>
#include <unistd.h>
#include <time.h>

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

static uint32_t a_trak_handler(ABox *t);

/* Flatten a single unit-rate edit. Video reordering is represented by
 * signed ctts v1 offsets. Audio priming/trimming and empty chapter edits
 * cannot simply be deleted: strict delivery refuses them. */
static int a_flatten_edits(ABox *trak, uint32_t movie_ts, int strict, char *err, size_t cap) {
    uint32_t handler = a_trak_handler(trak);
    int video = handler == A_FOURCC('v','i','d','e');
    if (!strict && !video) return 0;
    ABox *edts = a_box_find(trak, A_FOURCC('e','d','t','s'));
    if (!edts) return 0;
    ABox *elst = a_box_find(edts, A_FOURCC('e','l','s','t'));
    if (!elst || elst->len < 28 || a_rd32(elst->raw + 12) != 1) goto unsupported;
    int v1 = elst->raw[8] == 1;
    if (elst->raw[8] > 1 || elst->len < (v1 ? 36u : 28u)) goto unsupported;
    uint64_t duration = v1 ? a_rd64(elst->raw + 16) : a_rd32(elst->raw + 16);
    int64_t offset = v1 ? (int64_t)a_rd64(elst->raw + 24) : (int32_t)a_rd32(elst->raw + 20);
    size_t rate_at = v1 ? 32 : 24;
    if (offset < 0 || a_rd32(elst->raw + rate_at) != 0x00010000) goto unsupported;
    ABox *mdia = a_box_find(trak, A_FOURCC('m','d','i','a'));
    ABox *mdhd = mdia ? a_box_find(mdia, A_FOURCC('m','d','h','d')) : NULL;
    if (!mdhd || mdhd->len < 32) goto unsupported;
    int mv1 = mdhd->raw[8] == 1;
    if (mv1 && mdhd->len < 44) goto unsupported;
    uint32_t media_ts = a_rd32(mdhd->raw + (mv1 ? 28 : 20));
    uint64_t media_dur = mv1 ? a_rd64(mdhd->raw + 32) : a_rd32(mdhd->raw + 24);
    if (!video && (offset || (__int128)duration * media_ts != (__int128)media_dur * movie_ts)) goto unsupported;
    if (video && offset) {
        ABox *minf = a_box_find(mdia, A_FOURCC('m','i','n','f'));
        ABox *stbl = minf ? a_box_find(minf, A_FOURCC('s','t','b','l')) : NULL;
        ABox *ctts = stbl ? a_box_find(stbl, A_FOURCC('c','t','t','s')) : NULL;
        if (!ctts || ctts->len < 16 || ctts->raw[8] > 1) goto unsupported;
        uint32_t count = a_rd32(ctts->raw + 12);
        if (count > (ctts->len - 16) / 8) goto unsupported;
        for (uint32_t i = 0; i < count; i++) {
            uint32_t raw = a_rd32(ctts->raw + 20 + 8*i);
            int64_t value = ctts->raw[8] ? (int64_t)(int32_t)raw : (int64_t)raw;
            value -= offset;
            if (value < INT32_MIN || value > INT32_MAX) goto unsupported;
        }
        for (uint32_t i = 0; i < count; i++) {
            uint32_t raw = a_rd32(ctts->raw + 20 + 8*i);
            int64_t value = ctts->raw[8] ? (int64_t)(int32_t)raw : (int64_t)raw;
            a_be32(ctts->raw + 20 + 8*i, (uint32_t)(int32_t)(value - offset));
        }
        ctts->raw[8] = 1;
    }
    int at = (int)(edts - trak->kid);
    a_box_free(edts);
    memmove(trak->kid + at, trak->kid + at + 1, (size_t)(trak->nk-at-1)*sizeof(ABox));
    trak->nk--;
    return 0;
unsupported:
    snprintf(err, cap, "edit_lists:false cannot preserve this track's priming, trimming or empty edit; use PCM audio in MOV and chapters starting at frame 0 (edit_lists:audio removes video edits only)");
    return -1;
}

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
    int             flatten_edits;  /* 1 video only, 2 every track (strict) */
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
        if (i == video_i && nvref) a_add_tref(t, vrefs, nvref);
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
    if (o->flatten_edits) {
        for (int i = 0; i < moov->nk; i++) {
            ABox *t = &moov->kid[i];
            if (t->type == A_FOURCC('t','r','a','k') && a_flatten_edits(t, movie_ts, o->flatten_edits == 2, err, errcap)) {
                a_box_free(&root); close(fd); return -1;
            }
        }
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

    if (!o->faststart && moov_i == ntop - 1 && strcmp(src, dst) != 0 &&
        (int64_t)tail_off == top[moov_i].off + (int64_t)new_moov) {
        int same_offsets = 1;
        for (int r = 0; r < nr; r++) {
            if (reg[r].old_off != reg[r].new_off) { same_offsets = 0; break; }
        }
        if (same_offsets) {
            unlink(dst);
            if (clonefile(src, dst, 0) == 0) {
                int out = open(dst, O_RDWR);
                if (out >= 0) {
                    off_t end_off = (off_t)((int64_t)tail_off + (int64_t)tail_len);
                    int wok = ftruncate(out, end_off) == 0;
                    if (wok) wok = pwrite(out, mo, new_moov, top[moov_i].off) == (ssize_t)new_moov;
                    if (wok) wok = pwrite(out, tail, tail_len, (off_t)tail_off) == (ssize_t)tail_len;
                    if (close(out) != 0) wok = 0;
                    if (wok) {
                        free(mo);
                        free(tail);
                        close(fd);
                        return 0;
                    }
                }
                unlink(dst);
            }
        }
    }

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
    int       audio_kbps, pcm_bits, pcm_float;
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
    dispatch_queue_t aq;        /* serial queue feeding audio concurrently with video */
    pthread_mutex_t  amu;
    pthread_cond_t   acv;
    int              amu_init;
    int              astop;
    int64_t          audio_target;
    char             audio_err[512];
    int       has_tc, tc_drop, tc_quanta;
    int64_t   tc_start;
    int       faststart;
    int       flatten_edits;
    uint32_t  fourcc;
    int32_t   width, height;
    AChapter *chap;             /* chapters (title, first frame), ascending */
    int       nchap;
    int       chpl;             /* also write Nero chpl (MP4; default on) */
} AMux;

static void a_mux_stop_audio_worker(AMux *m) {
    if (m->aq) {
        pthread_mutex_lock(&m->amu);
        m->astop = 1;
        pthread_cond_broadcast(&m->acv);
        pthread_mutex_unlock(&m->amu);
        dispatch_sync(m->aq, ^{});
        dispatch_release(m->aq);
        m->aq = NULL;
    }
}

static void a_mux_free(AMux *m) {
    a_mux_stop_audio_worker(m);
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
    if (m->amu_init) {
        pthread_mutex_destroy(&m->amu);
        pthread_cond_destroy(&m->acv);
    }
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
        pthread_mutex_init(&m->amu, NULL);
        pthread_cond_init(&m->acv, NULL);
        m->amu_init = 1;
        if (!o->path || !o->path[0]) { a_mux_free(m); snprintf(err, cap, "path must be a string"); return NULL; }
        snprintf(m->path, sizeof m->path, "%s", o->path);
        char fmt[16];
        snprintf(fmt, sizeof fmt, "%s", o->format ? o->format : "");
        if (!fmt[0]) {
            const char *dot = strrchr(m->path, '.');
            snprintf(fmt, sizeof fmt, "%s", dot && !strcasecmp(dot, ".mov") ? "mov" : "mp4");
        }
        if (!strcasecmp(fmt, "mov")) m->mov = 1;
        else if (strcasecmp(fmt, "mp4")) { a_mux_free(m); snprintf(err, cap, "format must be :mp4 or :mov (got '%s')", fmt); return NULL; }
        m->pcm_bits = 24;
        m->num = o->num;
        m->den = o->den;
        if (m->num <= 0 || m->den <= 0) { a_mux_free(m); snprintf(err, cap, "rate must be a positive [num, den]"); return NULL; }
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
                if (copy) { a_mux_free(m); snprintf(err, cap, "audio_codec: :copy passes a movie's audio through; %s is a WAV", o->audio); return NULL; }
                if (w_media_wav_open(o->audio, &m->wav, err, cap) != 0) { a_mux_free(m); return NULL; }
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
                else if (!strcasecmp(ac, "pcm_s16le")) m->pcm_bits = 16;
                else if (!strcasecmp(ac, "pcm_s24le")) m->pcm_bits = 24;
                else if (!strcasecmp(ac, "pcm_s32le")) m->pcm_bits = 32;
                else if (!strcasecmp(ac, "pcm_f32le")) { m->pcm_bits = 32; m->pcm_float = 1; }
                else if (strcasecmp(ac, "pcm")) { a_mux_free(m); snprintf(err, cap, "audio codec must be aac, pcm, pcm_s16le/pcm_s24le/pcm_s32le/pcm_f32le or copy (got '%s')", ac); return NULL; }
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

static int a_feed_audio_err(AMux *m, int64_t upto, char *err, size_t errcap);
static int64_t a_audio_cap(AMux *m, int64_t video_frames);

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
                         AVNumberOfChannelsKey: @(m->ach), AVLinearPCMBitDepthKey: @(m->pcm_bits),
                         AVLinearPCMIsFloatKey: @(m->pcm_float), AVLinearPCMIsBigEndianKey: @NO,
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
    if (m->has_audio) {
        m->audio_target = m->total_frames > 0 ? a_audio_for(m, m->total_frames)
                                              : MIN(2 * (int64_t)m->arate, a_audio_cap(m, 1));
        dispatch_queue_attr_t qa = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        m->aq = dispatch_queue_create("tungsten.media.mux.audio", qa);
        AMux *mp = m;
        dispatch_async(m->aq, ^{
            @autoreleasepool {
                pthread_mutex_lock(&mp->amu);
                while (!mp->astop && !mp->audio_done && !mp->audio_err[0]) {
                    int64_t target = mp->audio_target;
                    int64_t total_goal = mp->total_frames > 0 ? a_audio_for(mp, mp->total_frames) : -1;
                    int64_t fed = __atomic_load_n(&mp->audio_fed, __ATOMIC_ACQUIRE);
                    if (fed >= target) {
                        if (total_goal >= 0 && fed >= total_goal) {
                            [mp->audio markAsFinished];
                            mp->audio_done = 1;
                            pthread_cond_broadcast(&mp->acv);
                            break;
                        }
                        pthread_cond_wait(&mp->acv, &mp->amu);
                        continue;
                    }
                    pthread_mutex_unlock(&mp->amu);
                    char aerr[512] = "";
                    int r = 0;
                    @autoreleasepool {
                        r = a_feed_audio_err(mp, target, aerr, sizeof aerr);
                    }
                    pthread_mutex_lock(&mp->amu);
                    pthread_cond_broadcast(&mp->acv);
                    if (r < 0) {
                        snprintf(mp->audio_err, sizeof mp->audio_err, "%s", aerr[0] ? aerr : "audio append failed");
                        break;
                    }
                    fed = __atomic_load_n(&mp->audio_fed, __ATOMIC_ACQUIRE);
                    if (r == 1 && total_goal >= 0 && fed >= total_goal && !mp->audio_done) {
                        [mp->audio markAsFinished];
                        mp->audio_done = 1;
                        pthread_cond_broadcast(&mp->acv);
                        break;
                    }
                    if (r == 0 && !mp->astop) {
                        struct timespec wts;
                        clock_gettime(CLOCK_REALTIME, &wts);
                        wts.tv_nsec += 500000L;
                        if (wts.tv_nsec >= 1000000000L) { wts.tv_sec++; wts.tv_nsec -= 1000000000L; }
                        pthread_cond_timedwait(&mp->acv, &mp->amu, &wts);
                    }
                }
                pthread_mutex_unlock(&mp->amu);
            }
        });
    }
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
 * if it reached upto, 0 if the input is full, or -1 on error (thread-safe). */
static int a_feed_audio_err(AMux *m, int64_t upto, char *err, size_t errcap) {
    if (!m->has_audio || m->audio_done) return 1;
    int64_t fed = __atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE);
    if (m->akind == A_AUDIO_COPY) {
        /* whole compressed buffers, in order, while they start before upto */
        while (fed < upto) {
            if (!m->apend) {
                m->apend = m->aeof ? NULL : [m->aout copyNextSampleBuffer];
                if (!m->apend) {
                    m->aeof = 1;
                    if (upto > fed) fed = upto;
                    __atomic_store_n(&m->audio_fed, fed, __ATOMIC_RELEASE);
                    return 1;
                }
            }
            if (a_copy_pos(m, m->apend) >= upto) {
                fed = upto;
                __atomic_store_n(&m->audio_fed, fed, __ATOMIC_RELEASE);
                return 1;
            }
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
            if (!ok) {
                snprintf(err, errcap, "appending passthrough audio at sample %lld failed", (long long)pos);
                return -1;
            }
            fed = pos + dn;
            __atomic_store_n(&m->audio_fed, fed, __ATOMIC_RELEASE);
        }
        return 1;
    }
    int ch = m->ach;
    while (fed < upto) {
        if (!m->audio.readyForMoreMediaData) return 0;
        int64_t n = upto - fed;
        if (n > 24000) n = 24000;
        size_t bytes = (size_t)n * 4 * (size_t)ch;
        CMBlockBufferRef bb = NULL;
        OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, kCFAllocatorDefault, NULL, 0, bytes, kCMBlockBufferAssureMemoryNowFlag, &bb);
        if (st != noErr) {
            snprintf(err, errcap, "audio buffer (OSStatus %d)", (int)st);
            return -1;
        }
        void *dst = NULL;
        CMBlockBufferGetDataPointer(bb, 0, NULL, NULL, (char **)&dst);
        if (m->akind == A_AUDIO_WAV) w_media_wav_read_f32(&m->wav, fed, n, dst);
        else a_decode_read(m, fed, n, dst);
        CMSampleBufferRef sb = NULL;
        st = CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, m->afmt, (CMItemCount)n, CMTimeMake(fed, m->arate), NULL, &sb);
        CFRelease(bb);
        if (st != noErr) {
            snprintf(err, errcap, "audio sample buffer (OSStatus %d)", (int)st);
            return -1;
        }
        BOOL ok = [m->audio appendSampleBuffer:sb];
        CFRelease(sb);
        if (!ok) {
            snprintf(err, errcap, "appending audio at frame %lld failed", (long long)fed);
            return -1;
        }
        fed += n;
        __atomic_store_n(&m->audio_fed, fed, __ATOMIC_RELEASE);
    }
    return 1;
}

/* Wait until the video input takes a sample. Audio encodes concurrently on
 * m->aq; advance m->audio_target when total_frames was not fixed up front. */
static void a_wait_video(AMux *m, int64_t frame) {
    int spins = 0;
    if (m->has_audio) {
        int64_t lead = 2 * (int64_t)m->arate;
        int64_t want = MIN(a_audio_for(m, frame + 1) + lead, a_audio_cap(m, frame + 1));
        char aerr[512] = "";
        pthread_mutex_lock(&m->amu);
        if (m->audio_err[0]) snprintf(aerr, sizeof aerr, "%s", m->audio_err);
        else if (want > m->audio_target) {
            m->audio_target = want;
            pthread_cond_signal(&m->acv);
        }
        pthread_mutex_unlock(&m->amu);
        if (aerr[0]) { a_mux_stop_audio_worker(m); a_mux_fail(m, "%s", aerr); }
    }
    while (!m->video.readyForMoreMediaData) {
        if (m->has_audio) {
            char aerr[512] = "";
            int64_t fed = __atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE);
            int64_t cap = m->total_frames > 0 ? a_audio_cap(m, frame + 1) : MAX(a_audio_cap(m, frame + 1), fed + m->arate / 4);
            int64_t step_to = MIN(fed + m->arate / 4, cap);
            pthread_mutex_lock(&m->amu);
            if (m->audio_err[0]) snprintf(aerr, sizeof aerr, "%s", m->audio_err);
            else if (!m->audio_done && step_to > m->audio_target) {
                m->audio_target = step_to;
                pthread_cond_signal(&m->acv);
            }
            pthread_mutex_unlock(&m->amu);
            if (aerr[0]) { a_mux_stop_audio_worker(m); a_mux_fail(m, "%s", aerr); }
        }
        if (m->writer.status != AVAssetWriterStatusWriting) {
            a_mux_stop_audio_worker(m);
            a_mux_fail(m, "the writer stopped");
        }
        usleep(spins < 20 ? 50 : 200);
        if (++spins > 100000) {
            int64_t fed = __atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE);
            a_mux_stop_audio_worker(m);
            a_mux_fail(m, "the writer stalled at frame %lld (video input not ready for 20 s; audio fed %lld, audio ready %d)",
                       (long long)frame, (long long)fed, m->has_audio ? (int)m->audio.readyForMoreMediaData : -1);
        }
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
    if (!strcmp(k, "edit_lists")) {
        char mode[32];
        w_media_str(v, mode, sizeof mode);
        m->flatten_edits = v == W_FALSE ? 2 : (!strcmp(mode, "audio") ? 1 : 0);
        return W_NIL;
    }
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
        if (m->aq) {
            pthread_mutex_lock(&m->amu);
            if (audio_total > m->audio_target) {
                m->audio_target = audio_total;
                pthread_cond_signal(&m->acv);
            }
            while (!m->audio_done && !m->audio_err[0] &&
                   __atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE) < audio_total) {
                if (m->writer.status != AVAssetWriterStatusWriting) break;
                if (++spins > 100000) break;
                struct timespec wts;
                clock_gettime(CLOCK_REALTIME, &wts);
                wts.tv_nsec += 200000L;
                if (wts.tv_nsec >= 1000000000L) { wts.tv_sec++; wts.tv_nsec -= 1000000000L; }
                pthread_cond_timedwait(&m->acv, &m->amu, &wts);
            }
            pthread_mutex_unlock(&m->amu);
            a_mux_stop_audio_worker(m);
            if (m->audio_err[0]) a_mux_fail(m, "%s", m->audio_err);
            if (spins > 100000) a_mux_fail(m, "the writer stalled finishing the audio");
            if (m->writer.status != AVAssetWriterStatusWriting && !m->audio_done &&
                __atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE) < audio_total)
                a_mux_fail(m, "the writer stopped while finishing the audio");
        }
        char aerr[512] = "";
        while (__atomic_load_n(&m->audio_fed, __ATOMIC_ACQUIRE) < audio_total && !m->audio_done) {
            int r = a_feed_audio_err(m, audio_total, aerr, sizeof aerr);
            if (r < 0) a_mux_fail(m, "%s", aerr);
            if (r == 1) break;
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
    dispatch_retain(sem);
    [m->writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); dispatch_release(sem); }];
    const char *wait = getenv("TUNGSTEN_MEDIA_WAIT_MS");
    int64_t wait_ms = wait ? strtoll(wait, NULL, 10) : 30000;
    if (wait_ms <= 0) wait_ms = 30000;
    long expired = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, wait_ms * NSEC_PER_MSEC));
    dispatch_release(sem);
    if (expired) a_mux_fail(m, "finishing the writer timed out after %lld ms", (long long)wait_ms);
    if (m->writer.status != AVAssetWriterStatusCompleted) a_mux_fail(m, "finishing %s failed", m->path);
    if (m->has_tc || m->nchap > 0 || m->flatten_edits) {
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
        o.flatten_edits = m->flatten_edits;
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
    "struct VPID { uint dw, dh, rx, ry, rw, rh, taps, lo, sstride, dstride, axlo, alpha, fill, in_bits, out_bits, pad; };\n"
    "static inline float4 ld4(uchar4 u, uint alpha) {\n"
    "  float4 v = float4(u);\n"
    "  if (alpha == 2) { float k = v.w * (1.0f / 255.0f); v.xyz *= k; }\n"
    "  else if (alpha == 3) v.w = 255.0f;\n"
    "  return v;\n"
    "}\n"
    "static inline uint u8(float v) { return uint(clamp(v, 0.0f, 255.0f) + 0.5f); }\n"
    "static inline uchar4 st4(float4 v, uint alpha) {\n"
    "  uint4 r;\n"
    "  if (alpha == 0) r = uint4(u8(v.x), u8(v.y), u8(v.z), u8(v.w));\n"
    "  else if (alpha == 3) r = uint4(u8(v.x), u8(v.y), u8(v.z), 255u);\n"
    "  else {\n"
    "    float A = clamp(v.w, 0.0f, 255.0f); uint a = uint(A + 0.5f);\n"
    "    if (alpha == 1) { float af = float(a); r = uint4(uint3(clamp(v.xyz, 0.0f, af) + 0.5f), a); }\n"
    "    else if (a == 0) r = uint4(0);\n"
    "    else { float k = 255.0f / clamp(v.w, 1e-6f, 255.0f); r = uint4(u8(v.x * k), u8(v.y * k), u8(v.z * k), a); }\n"
    "  }\n"
    "  return uchar4(r);\n"
    "}\n"
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
    "  *o = st4(v, p.alpha);\n"
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
    "}\n"
    "kernel void v4_id(device const uchar *src [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "                  device uchar *dst [[buffer(3)]], constant VPID &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar4 *o = (device uchar4 *)(dst + (ulong)g.y * p.dstride) + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = as_type<uchar4>(p.fill); return; }\n"
    "  int s0 = ys[y] - int(p.lo); ulong sx = (ulong)p.axlo + (ulong)x; device const float *w = yw + (ulong)y * p.taps;\n"
    "  float4 v = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) {\n"
    "    uchar4 px = ((device const uchar4 *)(src + (ulong)(s0 + t) * p.sstride))[sx];\n"
    "    v = fma(float4(w[t]), ld4(px, p.alpha), v);\n"
    "  }\n"
    "  *o = st4(v, p.alpha);\n"
    "}\n"
    "kernel void v2_id(device const uchar *src [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "                  device uchar *dst [[buffer(3)]], constant VPID &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar2 *o = (device uchar2 *)(dst + (ulong)g.y * p.dstride) + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = uchar2(p.fill & 255u, (p.fill >> 8) & 255u); return; }\n"
    "  int s0 = ys[y] - int(p.lo); ulong sx = (ulong)p.axlo + (ulong)x; device const float *w = yw + (ulong)y * p.taps;\n"
    "  float2 v = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) {\n"
    "    uchar2 px = ((device const uchar2 *)(src + (ulong)(s0 + t) * p.sstride))[sx];\n"
    "    v = fma(float2(w[t]), float2(px), v);\n"
    "  }\n"
    "  *o = uchar2(u8(v.x), u8(v.y));\n"
    "}\n"
    "kernel void v1_id(device const uchar *src [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "                  device uchar *dst [[buffer(3)]], constant VPID &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  device uchar *o = dst + (ulong)g.y * p.dstride + g.x;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  if (x < 0 || y < 0 || x >= int(p.rw) || y >= int(p.rh)) { *o = uchar(p.fill & 255u); return; }\n"
    "  int s0 = ys[y] - int(p.lo); ulong sx = (ulong)p.axlo + (ulong)x; device const float *w = yw + (ulong)y * p.taps;\n"
    "  float v = 0.0f;\n"
    "  for (uint t = 0; t < p.taps; t++) v = fma(w[t], float(src[(ulong)(s0 + t) * p.sstride + sx]), v);\n"
    "  *o = uchar(u8(v));\n"
    "}\n"
    "\n"
    "inline float plane_load(device const uchar *src, ulong offset, uint bits) {\n"
    "  return bits == 10 ? float(*((device const ushort *)(src + offset)) >> 6) * 0.25f : float(src[offset]);\n"
    "}\n"
    "inline float2 plane_load2(device const uchar *src, ulong row_off, ulong x, uint bits) {\n"
    "  if (bits == 10) {\n"
    "    ushort2 u = ((device const ushort2 *)(src + row_off))[x];\n"
    "    return float2(u >> 6) * 0.25f;\n"
    "  }\n"
    "  return float2(((device const uchar2 *)(src + row_off))[x]);\n"
    "}\n"
    "kernel void hp(device const uchar *src [[buffer(0)]], device const int *xs [[buffer(1)]], device const float *xw [[buffer(2)]],\n"
    "               device float *H [[buffer(3)]], constant HP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.rw || g.y >= p.rows) return;\n"
    "  uint C = p.alpha;\n"
    "  int first = xs[g.x]; device const float *w = xw + (ulong)g.x * p.taps;\n"
    "  ulong row_off = (ulong)(p.lo + g.y) * p.sstride;\n"
    "  if (C == 2) {\n"
    "    float2 v = 0.0f;\n"
    "    for (uint k = 0; k < p.taps; k++) v = fma(float2(w[k]), plane_load2(src, row_off, (ulong)(first + k), p.pad), v);\n"
    "    ((device float2 *)H)[(ulong)g.y * p.rw + g.x] = v;\n"
    "    return;\n"
    "  }\n"
    "  uint bps = p.pad == 10 ? 2 : 1;\n"
    "  float v = 0.0f;\n"
    "  for (uint k = 0; k < p.taps; k++) v = fma(w[k], plane_load(src, row_off + (ulong)(first + k) * bps, p.pad), v);\n"
    "  H[(ulong)g.y * p.rw + g.x] = v;\n"
    "}\n"
    "kernel void vp(device const float *H [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "               device uchar *dst [[buffer(3)]], constant VP &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  uint C = p.alpha;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  ulong row_off = (ulong)g.y * p.dstride;\n"
    "  if (C == 2) {\n"
    "    float2 v = float2(float(p.fill & 255u), float((p.fill >> 8) & 255u));\n"
    "    if (x >= 0 && y >= 0 && x < int(p.rw) && y < int(p.rh)) {\n"
    "      int first = ys[y] - int(p.lo); device const float *w = yw + (ulong)y * p.taps;\n"
    "      device const float2 *H2 = (device const float2 *)H;\n"
    "      v = w[0] * H2[(ulong)first * p.rw + x];\n"
    "      for (uint k = 1; k < p.taps; k++) v = fma(float2(w[k]), H2[(ulong)(first + k) * p.rw + x], v);\n"
    "    }\n"
    "    if (p.pad == 10) {\n"
    "      uint2 u = uint2(clamp(v * 4.0f, 0.0f, 1023.0f) + 0.5f) << 6;\n"
    "      ((device ushort2 *)(dst + row_off))[g.x] = ushort2(u);\n"
    "    } else {\n"
    "      ((device uchar2 *)(dst + row_off))[g.x] = uchar2(u8(v.x), u8(v.y));\n"
    "    }\n"
    "    return;\n"
    "  }\n"
    "  uint bps = p.pad == 10 ? 2 : 1;\n"
    "  float v = float(p.fill & 255u);\n"
    "  if (x >= 0 && y >= 0 && x < int(p.rw) && y < int(p.rh)) {\n"
    "    int first = ys[y] - int(p.lo); device const float *w = yw + (ulong)y * p.taps;\n"
    "    v = w[0] * H[(ulong)first * p.rw + x];\n"
    "    for (uint k = 1; k < p.taps; k++) v = fma(w[k], H[(ulong)(first + k) * p.rw + x], v);\n"
    "  }\n"
    "  ulong offset = row_off + (ulong)g.x * bps;\n"
    "  if (p.pad == 10) *((device ushort *)(dst + offset)) = ushort(uint(clamp(v * 4.0f, 0.0f, 1023.0f) + 0.5f) << 6);\n"
    "  else dst[offset] = u8(v);\n"
    "}\n"
    "kernel void vp_id(device const uchar *src [[buffer(0)]], device const int *ys [[buffer(1)]], device const float *yw [[buffer(2)]],\n"
    "                  device uchar *dst [[buffer(3)]], constant VPID &p [[buffer(4)]], uint2 g [[thread_position_in_grid]]) {\n"
    "  if (g.x >= p.dw || g.y >= p.dh) return;\n"
    "  uint C = p.alpha;\n"
    "  int x = int(g.x) - int(p.rx), y = int(g.y) - int(p.ry);\n"
    "  ulong row_off = (ulong)g.y * p.dstride;\n"
    "  if (C == 2) {\n"
    "    float2 v = float2(float(p.fill & 255u), float((p.fill >> 8) & 255u));\n"
    "    if (x >= 0 && y >= 0 && x < int(p.rw) && y < int(p.rh)) {\n"
    "      int first = ys[y] - int(p.lo); ulong sx = (ulong)p.axlo + (ulong)x; device const float *w = yw + (ulong)y * p.taps;\n"
    "      v = 0.0f;\n"
    "      for (uint k = 0; k < p.taps; k++) v = fma(float2(w[k]), plane_load2(src, (ulong)(first + k) * p.sstride, sx, p.in_bits), v);\n"
    "    }\n"
    "    if (p.out_bits == 10) {\n"
    "      uint2 u = uint2(clamp(v * 4.0f, 0.0f, 1023.0f) + 0.5f) << 6;\n"
    "      ((device ushort2 *)(dst + row_off))[g.x] = ushort2(u);\n"
    "    } else {\n"
    "      ((device uchar2 *)(dst + row_off))[g.x] = uchar2(u8(v.x), u8(v.y));\n"
    "    }\n"
    "    return;\n"
    "  }\n"
    "  uint ibps = p.in_bits == 10 ? 2 : 1, obps = p.out_bits == 10 ? 2 : 1;\n"
    "  float v = float(p.fill & 255u);\n"
    "  if (x >= 0 && y >= 0 && x < int(p.rw) && y < int(p.rh)) {\n"
    "    int first = ys[y] - int(p.lo); ulong sx = (ulong)p.axlo + (ulong)x; device const float *w = yw + (ulong)y * p.taps;\n"
    "    v = 0.0f;\n"
    "    for (uint k = 0; k < p.taps; k++) v = fma(w[k], plane_load(src, (ulong)(first + k) * p.sstride + sx * ibps, p.in_bits), v);\n"
    "  }\n"
    "  ulong offset = row_off + (ulong)g.x * obps;\n"
    "  if (p.out_bits == 10) *((device ushort *)(dst + offset)) = ushort(uint(clamp(v * 4.0f, 0.0f, 1023.0f) + 0.5f) << 6);\n"
    "  else dst[offset] = u8(v);\n"
    "}\n"
    "";

typedef struct { uint32_t rw, rows, lo, taps, axlo, sstride, alpha, pad; } AMtlHP;
typedef struct { uint32_t dw, dh, rx, ry, rw, rh, taps, lo, dstride, alpha, fill, pad; } AMtlVP;
typedef struct { uint32_t dw, dh, rx, ry, rw, rh, taps, lo, sstride, dstride, axlo, alpha, fill, in_bits, out_bits, pad; } AMtlVPID;

typedef id (*a_mtl_create_fn)(void);
static pthread_once_t g_mtl_once = PTHREAD_ONCE_INIT;
static pthread_once_t g_mtl_pipe_once = PTHREAD_ONCE_INIT;
static id g_mtl_dev, g_mtl_queue;
static id g_mtl_h[5], g_mtl_v[5], g_mtl_vid[5], g_mtl_hp, g_mtl_vp, g_mtl_vpid;
static int g_mtl_ok, g_mtl_pipe_ok;
static char g_mtl_err[512];
static pthread_mutex_t g_mtl_mu = PTHREAD_MUTEX_INITIALIZER;
static id g_mtl_stage_in[4], g_mtl_stage_out[4];   /* per-slot staging buffers, grown on demand */
static size_t g_mtl_page;

static void a_mtl_load(void) {
    @autoreleasepool {
        g_mtl_page = (size_t)getpagesize();
        void *h = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY | RTLD_LOCAL);
        a_mtl_create_fn create = h ? (a_mtl_create_fn)dlsym(h, "MTLCreateSystemDefaultDevice") : NULL;
        if (!create) { snprintf(g_mtl_err, sizeof g_mtl_err, "Metal.framework could not be loaded"); return; }
        id<MTLDevice> dev = create();
        if (!dev) { snprintf(g_mtl_err, sizeof g_mtl_err, "no Metal device"); return; }
        g_mtl_queue = [dev newCommandQueue];
        if (!g_mtl_queue) { [dev release]; snprintf(g_mtl_err, sizeof g_mtl_err, "no Metal command queue"); return; }
        g_mtl_dev = dev;
        g_mtl_ok = 1;
    }
}

static void a_mtl_pipelines_load(void) {
    @autoreleasepool {
        if (!g_mtl_ok) return;
        id<MTLDevice> dev = g_mtl_dev;
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:a_msl] options:nil error:&err];
        if (!lib) {
            snprintf(g_mtl_err, sizeof g_mtl_err, "compiling the scaler kernels failed: %s", err.localizedDescription.UTF8String ?: "?");
            return;
        }
        static const char *hn[5] = {NULL, "h1", "h2", NULL, "h4"};
        static const char *vn[5] = {NULL, "v1", "v2", NULL, "v4"};
        static const char *vidn[5] = {NULL, "v1_id", "v2_id", NULL, "v4_id"};
        for (int c = 1; c <= 4; c++) {
            if (!hn[c]) continue;
            id<MTLFunction> fh = [lib newFunctionWithName:[NSString stringWithUTF8String:hn[c]]];
            id<MTLFunction> fv = [lib newFunctionWithName:[NSString stringWithUTF8String:vn[c]]];
            id<MTLFunction> fi = [lib newFunctionWithName:[NSString stringWithUTF8String:vidn[c]]];
            g_mtl_h[c] = fh ? [dev newComputePipelineStateWithFunction:fh error:&err] : nil;
            g_mtl_v[c] = fv ? [dev newComputePipelineStateWithFunction:fv error:&err] : nil;
            g_mtl_vid[c] = fi ? [dev newComputePipelineStateWithFunction:fi error:&err] : nil;
            [fh release]; [fv release]; [fi release];
            if (!g_mtl_h[c] || !g_mtl_v[c] || !g_mtl_vid[c]) {
                snprintf(g_mtl_err, sizeof g_mtl_err, "building the scaler pipelines failed: %s", err.localizedDescription.UTF8String ?: "?");
                [lib release];
                return;
            }
        }
        id<MTLFunction> hp = [lib newFunctionWithName:@"hp"], vp = [lib newFunctionWithName:@"vp"], vpid = [lib newFunctionWithName:@"vp_id"];
        g_mtl_hp = hp ? [dev newComputePipelineStateWithFunction:hp error:&err] : nil;
        g_mtl_vp = vp ? [dev newComputePipelineStateWithFunction:vp error:&err] : nil;
        g_mtl_vpid = vpid ? [dev newComputePipelineStateWithFunction:vpid error:&err] : nil;
        [hp release]; [vp release]; [vpid release];
        [lib release];
        if (!g_mtl_hp || !g_mtl_vp || !g_mtl_vpid) {
            snprintf(g_mtl_err, sizeof g_mtl_err, "Metal plane kernels: %s", err.localizedDescription.UTF8String ?: "?");
            return;
        }
        g_mtl_pipe_ok = 1;
    }
}

int w_media_metal_available(void) {
    if (getenv("TUNGSTEN_MEDIA_NO_METAL")) return 0;
    pthread_once(&g_mtl_once, a_mtl_load);
    return g_mtl_ok;
}

static int a_mtl_pipelines_ready(void) {
    if (!w_media_metal_available()) return 0;
    pthread_once(&g_mtl_pipe_once, a_mtl_pipelines_load);
    return g_mtl_pipe_ok;
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

static id a_mtl_buf_pb(void *pb, int plane, void *plane_base, size_t plane_len, size_t sub_off, size_t sub_len, id *stage, int *copied, size_t *offset) {
    size_t pg = g_mtl_page ? g_mtl_page : 16384;
    if (pb && !getenv("TUNGSTEN_MEDIA_METAL_STAGE") && plane_len >= sub_off + sub_len) {
        uintptr_t base = (uintptr_t)plane_base & ~(uintptr_t)(pg - 1);
        size_t boff = (size_t)((uintptr_t)plane_base - base);
        size_t rl = (boff + plane_len + pg - 1) / pg * pg;
        CFStringRef key = plane == 0 ? CFSTR("w.mtl.p0") : CFSTR("w.mtl.p1");
        id cached = (id)CVBufferGetAttachment((CVBufferRef)pb, key, NULL);
        if (cached && [(id<MTLBuffer>)cached contents] == (void *)base && [(id<MTLBuffer>)cached length] >= rl) {
            *copied = 0;
            *offset = boff + sub_off;
            return [cached retain];
        }
        id b = [g_mtl_dev newBufferWithBytesNoCopy:(void *)base length:rl options:MTLResourceStorageModeShared deallocator:nil];
        if (b) {
            CVBufferSetAttachment((CVBufferRef)pb, key, (CFTypeRef)b, kCVAttachmentMode_ShouldNotPropagate);
            *copied = 0;
            *offset = boff + sub_off;
            return b;
        }
    }
    void *p = (uint8_t *)plane_base + sub_off;
    uintptr_t base = (uintptr_t)p & ~(uintptr_t)(pg - 1);
    size_t off = (size_t)((uintptr_t)p - base);
    size_t rl = (off + sub_len + pg - 1) / pg * pg;
    if (!getenv("TUNGSTEN_MEDIA_METAL_STAGE")) {
        id b = [g_mtl_dev newBufferWithBytesNoCopy:(void *)base length:rl options:MTLResourceStorageModeShared deallocator:nil];
        if (b) { *copied = 0; *offset = off; return b; }
    }
    if (!*stage || [(id<MTLBuffer>)*stage length] < sub_len) {
        [*stage release];
        *stage = [g_mtl_dev newBufferWithLength:(sub_len + pg - 1) / pg * pg options:MTLResourceStorageModeShared];
    }
    *copied = 1;
    *offset = 0;
    return [*stage retain];
}

/* Encode one plan's pass(es) into ce. Returns 0, or -1 with a message. */
static int a_mtl_encode(id<MTLComputeCommandEncoder> ce, WMediaJob *j, int slot, id *keep, int *nkeep, int *copy_out, char *err, size_t cap) {
    WMediaScale *s = j->s;
    id<MTLDevice> dev = g_mtl_dev;
    int C = s->ch;
    int wide = s->in_bits > 8 || s->out_bits > 8;
    if (wide && C == 4) { snprintf(err, cap, "Metal 10-bit scaling requires one or two channels"); return -1; }
    int ibps = s->in_bits > 8 ? 2 : 1, obps = s->out_bits > 8 ? 2 : 1;
    if (j->sstride % (C * ibps) || j->dstride % (C * obps) || (uintptr_t)j->src % ibps || (uintptr_t)j->dst % obps) {
        snprintf(err, cap, "Metal needs sample-aligned planes"); return -1;
    }
    if ((C == 4 && (j->sstride % 4 || j->dstride % 4 || (uintptr_t)j->src % 4 || (uintptr_t)j->dst % 4)) ||
        (C == 2 && (j->sstride % 2 || j->dstride % 2 || (uintptr_t)j->src % 2 || (uintptr_t)j->dst % 2))) {
        snprintf(err, cap, "Metal needs pixel-aligned rows");
        return -1;
    }
    AMtlPlan *p = s->metal;
    int rows = s->ay.hi - s->ay.lo;
    int x_id = s->ax.id;
    if (!p) {
        p = calloc(1, sizeof *p);
        p->ys = [dev newBufferWithBytes:s->ay.start length:sizeof(int32_t) * (size_t)s->ay.n options:MTLResourceStorageModeShared];
        p->yw = [dev newBufferWithBytes:s->ay.w length:sizeof(float) * (size_t)s->ay.n * (size_t)s->ay.taps options:MTLResourceStorageModeShared];
        if (!x_id) {
            p->xs = [dev newBufferWithBytes:s->ax.start length:sizeof(int32_t) * (size_t)s->ax.n options:MTLResourceStorageModeShared];
            p->xw = [dev newBufferWithBytes:s->ax.w length:sizeof(float) * (size_t)s->ax.n * (size_t)s->ax.taps options:MTLResourceStorageModeShared];
            p->H = [dev newBufferWithLength:sizeof(float) * (size_t)C * (size_t)s->rw * (size_t)rows options:MTLResourceStorageModePrivate];
        }
        s->metal = p;
        if (!p->ys || !p->yw || (!x_id && (!p->xs || !p->xw || !p->H))) {
            w_media_scale_metal_release(s);
            snprintf(err, cap, "Metal: out of memory");
            return -1;
        }
    }
    /* only the source rows the plan reads */
    size_t soff = (size_t)s->ay.lo * j->sstride;
    size_t slen = (size_t)(rows - 1) * j->sstride + (size_t)s->src_w * C * ibps;
    if (j->src_len && soff + slen > j->src_len) slen = j->src_len - soff;
    size_t dlen = j->dst_len ? j->dst_len : (size_t)(s->dst_h - 1) * j->dstride + (size_t)s->dst_w * C * obps;
    int scopy = 0, dcopy = 0;
    size_t so = 0, dof = 0;
    id sb = a_mtl_buf_pb(j->src_pb, j->src_plane, (void *)j->src, j->src_len, soff, slen, &g_mtl_stage_in[slot], &scopy, &so);
    id db = a_mtl_buf_pb(j->dst_pb, j->dst_plane, j->dst, dlen, 0, dlen, &g_mtl_stage_out[slot], &dcopy, &dof);
    if (!sb || !db) {
        [sb release];
        [db release];
        snprintf(err, cap, "Metal: no buffer");
        return -1;
    }
    keep[(*nkeep)++] = sb;
    keep[(*nkeep)++] = db;
    if (scopy) a_pcopy([(id<MTLBuffer>)sb contents], (const uint8_t *)j->src + soff, slen);
    *copy_out = dcopy;
    uint32_t fill = (uint32_t)s->fill[0] | ((uint32_t)s->fill[1] << 8) | ((uint32_t)s->fill[2] << 16) | ((uint32_t)s->fill[3] << 24);
    if (x_id) {
        id<MTLComputePipelineState> pvid = wide ? g_mtl_vpid : g_mtl_vid[C];
        AMtlVPID vpid = {(uint32_t)s->dst_w, (uint32_t)s->dst_h, (uint32_t)s->rx, (uint32_t)s->ry, (uint32_t)s->rw, (uint32_t)s->rh,
                         (uint32_t)s->ay.taps, (uint32_t)s->ay.lo, (uint32_t)j->sstride, (uint32_t)j->dstride, (uint32_t)s->ax.lo,
                         (uint32_t)(wide ? C : s->alpha), fill, (uint32_t)s->in_bits, (uint32_t)s->out_bits, 0};
        [ce setComputePipelineState:pvid];
        [ce setBuffer:sb offset:so atIndex:0];
        [ce setBuffer:p->ys offset:0 atIndex:1];
        [ce setBuffer:p->yw offset:0 atIndex:2];
        [ce setBuffer:db offset:dof atIndex:3];
        [ce setBytes:&vpid length:sizeof vpid atIndex:4];
        NSUInteger tw = 32, th = pvid.maxTotalThreadsPerThreadgroup >= 256 ? 8 : (pvid.maxTotalThreadsPerThreadgroup / tw);
        if (th < 1) th = 1;
        [ce dispatchThreads:MTLSizeMake((NSUInteger)s->dst_w, (NSUInteger)s->dst_h, 1) threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
        return 0;
    }
    AMtlHP hp = {(uint32_t)s->rw, (uint32_t)rows, 0, (uint32_t)s->ax.taps, (uint32_t)s->ax.lo, (uint32_t)j->sstride, (uint32_t)(wide ? C : s->alpha), (uint32_t)s->in_bits};
    id<MTLComputePipelineState> ph = wide ? g_mtl_hp : g_mtl_h[C], pv = wide ? g_mtl_vp : g_mtl_v[C];
    [ce setComputePipelineState:ph];
    [ce setBuffer:sb offset:so atIndex:0];
    [ce setBuffer:p->xs offset:0 atIndex:1];
    [ce setBuffer:p->xw offset:0 atIndex:2];
    [ce setBuffer:p->H offset:0 atIndex:3];
    [ce setBytes:&hp length:sizeof hp atIndex:4];
    NSUInteger tw = 32, th = ph.maxTotalThreadsPerThreadgroup >= 256 ? 8 : (ph.maxTotalThreadsPerThreadgroup / tw);
    if (th < 1) th = 1;
    [ce dispatchThreads:MTLSizeMake((NSUInteger)s->rw, (NSUInteger)rows, 1) threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    AMtlVP vp = {(uint32_t)s->dst_w, (uint32_t)s->dst_h, (uint32_t)s->rx, (uint32_t)s->ry, (uint32_t)s->rw, (uint32_t)s->rh,
                 (uint32_t)s->ay.taps, (uint32_t)s->ay.lo, (uint32_t)j->dstride, (uint32_t)(wide ? C : s->alpha), fill, (uint32_t)s->out_bits};
    [ce setComputePipelineState:pv];
    [ce setBuffer:p->H offset:0 atIndex:0];
    [ce setBuffer:p->ys offset:0 atIndex:1];
    [ce setBuffer:p->yw offset:0 atIndex:2];
    [ce setBuffer:db offset:dof atIndex:3];
    [ce setBytes:&vp length:sizeof vp atIndex:4];
    tw = 32;
    th = pv.maxTotalThreadsPerThreadgroup >= 256 ? 8 : (pv.maxTotalThreadsPerThreadgroup / tw);
    if (th < 1) th = 1;
    [ce dispatchThreads:MTLSizeMake((NSUInteger)s->dst_w, (NSUInteger)s->dst_h, 1) threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    return 0;
}

/* Several plans in one command buffer (the Y' and CbCr planes of a frame). */
int w_media_scale_metal_jobs(WMediaJob *jobs, int n, char *err, size_t cap) {
    if (!a_mtl_pipelines_ready()) { snprintf(err, cap, "Metal: %s", g_mtl_err[0] ? g_mtl_err : "not available"); return -1; }
    if (n < 1 || n > 4) { snprintf(err, cap, "Metal: 1 to 4 jobs"); return -1; }
    int rc = 0;
    @autoreleasepool {
        pthread_mutex_lock(&g_mtl_mu);
        id keep[8];
        int nkeep = 0, copy_out[4] = {0, 0, 0, 0};
        id<MTLCommandBuffer> cb = [g_mtl_queue commandBuffer];
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        for (int i = 0; i < n && rc == 0; i++) rc = a_mtl_encode(ce, &jobs[i], i, keep, &nkeep, &copy_out[i], err, cap);
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
                a_pcopy(jobs[i].dst, [(id<MTLBuffer>)keep[2 * i + 1] contents], (size_t)(s->dst_h - 1) * jobs[i].dstride + (size_t)s->dst_w * s->ch * (s->out_bits > 8 ? 2 : 1));
            }
        for (int i = 0; i < nkeep; i++) [keep[i] release];
        pthread_mutex_unlock(&g_mtl_mu);
    }
    return rc;
}

int w_media_scale_metal(WMediaScale *s, const uint8_t *src, size_t sstride, size_t src_len,
                        uint8_t *dst, size_t dstride, size_t dst_len, char *err, size_t cap) {
    WMediaJob j = {s, src, sstride, src_len, dst, dstride, dst_len, NULL, NULL, 0, 0};
    return w_media_scale_metal_jobs(&j, 1, err, cap);
}

/* ======================================================================
   Decoder: VTDecompressionSession over a file's video samples (AVAssetReader
   passthrough) or over segment files, frames handed out in presentation
   order
   ======================================================================
 *
 * A producer thread pulls compressed samples in decode order and decodes
 * batches asynchronously; decoded frames wait in a small pending list until
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
    WMediaSegment  **mem_segs;
    int              nmem_seg;
    WMediaSegment   *seg;
    int64_t          seg_base;         /* frame index of the current segment's frame 0 */
    int32_t         *seg_sorted;
    CMFormatDescriptionRef fmt;
    VTDecompressionSessionRef vt;
    OSType           pix;
    int              w, h, scale_max_w;
    int32_t          num, den;         /* frame rate */
    int32_t          ts;               /* file: track timescale */
    int64_t          edit;             /* file: presentation = media pts + edit (ticks) */
    int64_t          frames_hint;
    int64_t          start_pts;        /* frames before this presentation time are dropped (files) */
    uint32_t         codec;
    int              siting;           /* source chroma siting (M_SITE_*-like: 0 left, 1 center, 2 topleft) */
    /* thread */
    pthread_t        th;
    int              th_started, refs, timeout_ms;
    pthread_mutex_t  mu;
    pthread_cond_t   cv;
    ADecFrame       *pend;             /* decoded, sorted by pts */
    int              npend, cpend;
    int64_t         *fly;              /* [id, pts] of samples fed but not yet output (VideoToolbox may hold frames back) */
    int              nfly, cfly;
    int64_t          next_id;
    ADecFrame       *q;                /* final, in order */
    int              qh, qn, qcap, peak_qn;
    int              eof, stop, debug, serial;
    char             err[512];
    int64_t          decoded, delivered;
    uint64_t         dec_ns;
} ADec;

static void a_dec_destroy(ADec *d);
static void a_dec_unref(ADec *d) { if (__atomic_sub_fetch(&d->refs, 1, __ATOMIC_ACQ_REL) == 0) a_dec_destroy(d); }

/* A sample's presentation time on the output timeline (the movie's edit
 * list applied), in source ticks (files) or frames (segments). VideoToolbox
 * reports frames at this time, not at the media time the sample carries. */
static int64_t a_dec_time(ADec *d, CMTime t) {
    if (d->segs || d->mem_segs) return (int64_t)llround(CMTimeGetSeconds(t) * d->num / d->den);
    return CMTimeConvertScale(t, d->ts, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
}

static void a_dec_output(void *ref, void *frameref, OSStatus st, VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts, CMTime dur) {
    (void)dur; (void)flags;
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
        if (!d->err[0]) snprintf(d->err, sizeof d->err, "VideoToolbox could not decode a frame (OSStatus %d)", (int)st);
        pthread_cond_broadcast(&d->cv);
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
    VTDecompressionOutputCallbackRecord cb = {a_dec_output, d};
    OSStatus st = -1;
    if (d->scale_max_w > 0 && d->w > d->scale_max_w) {
        int ow = d->scale_max_w;
        int oh = (int)(((int64_t)d->h * ow / (d->w ? d->w : 1)) & ~1LL);
        if (oh < 2) oh = 2;
        NSDictionary *sattrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(d->pix),
                                 (id)kCVPixelBufferWidthKey: @(ow),
                                 (id)kCVPixelBufferHeightKey: @(oh),
                                 (id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        st = VTDecompressionSessionCreate(NULL, fmt, spec, (__bridge CFDictionaryRef)sattrs, &cb, &d->vt);
    }
    if (st != noErr) {
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(d->pix), (id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        st = VTDecompressionSessionCreate(NULL, fmt, spec, (__bridge CFDictionaryRef)attrs, &cb, &d->vt);
    }
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
        if (f.pts < d->start_pts) { CVBufferRelease(f.pb); continue; }
        while (d->qn == d->qcap && !d->stop) pthread_cond_wait(&d->cv, &d->mu);
        if (d->stop) { CVBufferRelease(f.pb); break; }
        d->q[(d->qh + d->qn) % d->qcap] = f;
        d->qn++;
        if (d->qn > d->peak_qn) d->peak_qn = d->qn;
        pthread_cond_broadcast(&d->cv);
    }
}

/* The next compressed sample in decode order (retained), its DTS (in the
 * same units as frame pts), or NULL at the end. Producer thread. */
static CMSampleBufferRef a_dec_next_sample(ADec *d, int64_t *dts) {
    if (!d->segs && !d->mem_segs) {
        CMSampleBufferRef sb = [d->out copyNextSampleBuffer];
        if (!sb) {
            if (d->reader.status == AVAssetReaderStatusFailed && !d->err[0])
                snprintf(d->err, sizeof d->err, "reading the video failed: %s", d->reader.error.localizedDescription.UTF8String ?: "?");
            return NULL;
        }
        CMTime t = CMSampleBufferGetOutputDecodeTimeStamp(sb);
        if (!CMTIME_IS_VALID(t)) t = CMSampleBufferGetOutputPresentationTimeStamp(sb);
        int reorder = (d->codec == kCMVideoCodecType_AppleProRes422 || d->codec == kCMVideoCodecType_AppleProRes422HQ ||
                       d->codec == kCMVideoCodecType_AppleProRes422LT || d->codec == kCMVideoCodecType_AppleProRes422Proxy ||
                       d->codec == kCMVideoCodecType_AppleProRes4444 || d->codec == kCMVideoCodecType_AppleProRes4444XQ) ? 0 : (W_MEDIA_REORDER_DELAY * 2);
        int64_t margin = d->num > 0 ? (int64_t)((__int128)reorder * d->den * d->ts / d->num) : 0;
        *dts = a_dec_time(d, t) - margin;
        return sb;
    }
    for (;;) {
        if (d->seg && d->seg_k < d->seg->n) break;
        if (d->seg) {
            d->seg_base += d->seg->n;
            /* Segment samples borrow this storage. Drain before freeing it. */
            VTDecompressionSessionFinishDelayedFrames(d->vt);
            VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
            if (!d->mem_segs) w_media_seg_free(d->seg);
            d->seg = NULL;
            free(d->seg_sorted);
            d->seg_sorted = NULL;
        }
        if (d->mem_segs) {
            while (d->seg_i < d->nmem_seg && d->start_pts > d->seg_base) {
                uint32_t sn = (uint32_t)d->mem_segs[d->seg_i]->n;
                if (!sn || d->seg_base + (int64_t)sn > d->start_pts) break;
                d->seg_base += (int64_t)sn;
                d->seg_i++;
            }
            if (d->seg_i >= d->nmem_seg) return NULL;
            d->seg = d->mem_segs[d->seg_i++];
        } else {
            while (d->seg_i < d->nseg && d->start_pts > d->seg_base) {
                int sfd = open(d->segs[d->seg_i], O_RDONLY);
                uint8_t shdr[64];
                if (sfd < 0 || read(sfd, shdr, 64) != 64 || memcmp(shdr, "TWMS", 4) != 0) { if (sfd >= 0) close(sfd); break; }
                close(sfd);
                uint32_t sn = (uint32_t)shdr[32] | ((uint32_t)shdr[33] << 8) | ((uint32_t)shdr[34] << 16) | ((uint32_t)shdr[35] << 24);
                if (!sn || d->seg_base + (int64_t)sn > d->start_pts) break;
                d->seg_base += (int64_t)sn;
                d->seg_i++;
            }
            if (d->seg_i >= d->nseg) return NULL;
            char err[512];
            d->seg = w_media_seg_load(d->segs[d->seg_i++], err, sizeof err);
            if (!d->seg) { snprintf(d->err, sizeof d->err, "%s", err); return NULL; }
        }
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
        int batch = 0;
        if (getenv("TUNGSTEN_MEDIA_TEST_STALL_DECODER")) {
            pthread_mutex_lock(&d->mu);
            while (!d->stop) pthread_cond_wait(&d->cv, &d->mu);
            pthread_mutex_unlock(&d->mu);
        }
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
            int64_t sample_pts = CMSampleBufferGetNumSamples(sb) > 0 ? a_dec_time(d, CMSampleBufferGetOutputPresentationTimeStamp(sb)) : INT64_MAX;
            a_dec_release(d, sample_pts < dts ? sample_pts : dts, 0);
            int64_t id = ++d->next_id;
            if (CMSampleBufferGetNumSamples(sb) > 0) {
                int64_t p = sample_pts;
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
                OSStatus st = VTDecompressionSessionDecodeFrame(d->vt, sb, d->serial ? 0 : kVTDecodeFrame_EnableAsynchronousDecompression, (void *)(intptr_t)id, &info);
                /* Bounded batches overlap decoding of adjacent frames without
                 * letting an asynchronous decoder retain the entire movie. */
                if (++batch == (d->serial ? 1 : 8) || st != noErr) {
                    VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
                    batch = 0;
                }
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
    @autoreleasepool { a_dec_unref(d); }
    return NULL;
}

static void a_dec_free(ADec *d) {
    if (!d) return;
    pthread_mutex_lock(&d->mu);
    d->stop = 1;
    pthread_cond_broadcast(&d->cv);
    pthread_mutex_unlock(&d->mu);
    a_dec_unref(d);
}

static void a_dec_destroy(ADec *d) {
    /* Callbacks touch pend/fly and mu, so drain before releasing those. */
    if (d->vt) VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
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
    if (d->seg && !d->mem_segs) w_media_seg_free(d->seg);
    if (d->mem_segs) {
        for (int i = 0; i < d->nmem_seg; i++)
            if (d->mem_segs[i]) w_media_seg_free(d->mem_segs[i]);
        free(d->mem_segs);
    }
    free(d->seg_sorted);
    for (int i = 0; i < d->nseg; i++) free(d->segs[i]);
    free(d->segs);
    pthread_mutex_destroy(&d->mu);
    pthread_cond_destroy(&d->cv);
    free(d);
}

static OSType a_native_format(CMFormatDescriptionRef fd);

/* A decoder pix request meaning "Y'CbCr at the source's own depth": 8-bit
 * sources decode to NV12, 10-bit to P010, ProRes 422 to P210. Transcode and
 * MediaVerify.quality_search use it: VideoToolbox's 8- to 10-bit conversion
 * resamples chroma, so a same-size copy of an 8-bit master through P010 was not
 * exact (v3 Shorts master: PSNR U 49 dB against the source, 77 dB before
 * 4c131512). Every other caller keeps the 10-bit default (pix 0). */
#define A_PIX_NATIVE ((OSType)'natv')

/* Bits per sample of a decoder's Y'CbCr output: 8 for NV12, else 10 (P010/P210, MSB-aligned). */
static int a_dec_bits(ADec *d) {
    return d->pix == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 8 : 10;
}

static int a_dec_vsub(ADec *d) {
    return d->pix == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange ? 1 : 2;
}

static OSType a_dec_yuv_pixel(uint32_t codec) {
    if (codec == kCMVideoCodecType_AppleProRes422 || codec == kCMVideoCodecType_AppleProRes422HQ ||
        codec == kCMVideoCodecType_AppleProRes422LT || codec == kCMVideoCodecType_AppleProRes422Proxy)
        return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange;
    return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
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
static ADec *a_dec_open_ex(const char *path, char **segs, int nseg, int32_t num, int32_t den, OSType pix, int64_t start_frame,
                           int timeout_ms, int queue_cap, int scale_max_w, char *err, size_t cap) {
    ADec *d = calloc(1, sizeof *d);
    d->refs = 1;
    d->timeout_ms = timeout_ms > 0 ? timeout_ms : 30000;
    pthread_mutex_init(&d->mu, NULL);
    pthread_cond_init(&d->cv, NULL);
    d->pix = pix;
    d->scale_max_w = scale_max_w;
    d->debug = getenv("TUNGSTEN_MEDIA_DEBUG") != NULL;
    d->serial = getenv("TUNGSTEN_MEDIA_DECODER_SERIAL") != NULL;
    if (queue_cap < 1 || queue_cap > 32) { snprintf(err, cap, "decode_ahead must be in 1..32"); a_dec_free(d); return NULL; }
    d->qcap = queue_cap;
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
        if (!d->pix) d->pix = a_dec_yuv_pixel(d->codec);
        else if (d->pix == A_PIX_NATIVE) d->pix = a_native_format(fd);
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
        if (!d->pix) d->pix = a_dec_yuv_pixel(d->codec);
        else if (d->pix == A_PIX_NATIVE) d->pix = s0->format ? a_native_format((CMFormatDescriptionRef)s0->format) : a_dec_yuv_pixel(d->codec);
        CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s0->format);
        d->siting = a_siting_of(ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ChromaLocationTopField) : NULL);
        w_media_seg_free(s0);
        d->start_pts = start_frame > 0 ? start_frame : 0;
        d->frames_hint = -1;
    }
    __atomic_add_fetch(&d->refs, 1, __ATOMIC_RELAXED);
    if (pthread_create(&d->th, NULL, a_dec_thread, d) != 0) { __atomic_sub_fetch(&d->refs, 1, __ATOMIC_RELAXED); snprintf(err, cap, "cannot start the decoder thread"); a_dec_free(d); return NULL; }
    d->th_started = 1;
    pthread_detach(d->th);
    return d;
}

static ADec *a_dec_open(const char *path, char **segs, int nseg, int32_t num, int32_t den, OSType pix, int64_t start_frame, int timeout_ms, int queue_cap,
                        char *err, size_t cap) {
    return a_dec_open_ex(path, segs, nseg, num, den, pix, start_frame, timeout_ms, queue_cap, 0, err, cap);
}

/* Open a decoder over finished in-memory WMediaSegment* (takes ownership of segs array and elements). */
static ADec *a_dec_open_mem(WMediaSegment **segs, int nseg, OSType pix, int64_t start_frame, int timeout_ms, int queue_cap,
                            char *err, size_t cap) {
    if (!segs || nseg <= 0 || !segs[0]) {
        if (segs) {
            for (int i = 0; i < nseg; i++) if (segs[i]) w_media_seg_free(segs[i]);
            free(segs);
        }
        snprintf(err, cap, "no in-memory segments");
        return NULL;
    }
    ADec *d = calloc(1, sizeof *d);
    d->refs = 1;
    d->timeout_ms = timeout_ms > 0 ? timeout_ms : 30000;
    pthread_mutex_init(&d->mu, NULL);
    pthread_cond_init(&d->cv, NULL);
    d->pix = pix;
    d->debug = getenv("TUNGSTEN_MEDIA_DEBUG") != NULL;
    d->serial = getenv("TUNGSTEN_MEDIA_DECODER_SERIAL") != NULL;
    d->qcap = (queue_cap < 1 || queue_cap > 32) ? 16 : queue_cap;
    d->q = calloc((size_t)d->qcap, sizeof(ADecFrame));
    d->mem_segs = segs;
    d->nmem_seg = nseg;
    WMediaSegment *s0 = segs[0];
    d->w = s0->width;
    d->h = s0->height;
    d->num = s0->rate_num;
    d->den = s0->rate_den;
    d->codec = s0->fourcc;
    if (!d->pix) d->pix = a_dec_yuv_pixel(d->codec);
    else if (d->pix == A_PIX_NATIVE) d->pix = s0->format ? a_native_format((CMFormatDescriptionRef)s0->format) : a_dec_yuv_pixel(d->codec);
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions((CMFormatDescriptionRef)s0->format);
    d->siting = a_siting_of(ext ? CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ChromaLocationTopField) : NULL);
    d->start_pts = start_frame > 0 ? start_frame : 0;
    d->frames_hint = -1;
    __atomic_add_fetch(&d->refs, 1, __ATOMIC_RELAXED);
    if (pthread_create(&d->th, NULL, a_dec_thread, d) != 0) {
        __atomic_sub_fetch(&d->refs, 1, __ATOMIC_RELAXED);
        snprintf(err, cap, "cannot start the decoder thread");
        a_dec_free(d);
        return NULL;
    }
    d->th_started = 1;
    pthread_detach(d->th);
    return d;
}

/* The next frame in presentation order: 1 (*pb retained, *frame its index
 * in the output timeline), 0 at the end, -1 with a message. */
static int a_dec_next(ADec *d, CVPixelBufferRef *pb, int64_t *frame, char *err, size_t cap) {
    pthread_mutex_lock(&d->mu);
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_sec += d->timeout_ms / 1000;
    until.tv_nsec += (long)(d->timeout_ms % 1000) * 1000000L;
    if (until.tv_nsec >= 1000000000L) { until.tv_sec++; until.tv_nsec -= 1000000000L; }
    while (d->qn == 0 && !d->eof && !d->err[0]) {
        if (pthread_cond_timedwait(&d->cv, &d->mu, &until) == ETIMEDOUT) {
            snprintf(d->err, sizeof d->err, "decoder timed out after %d ms without a frame", d->timeout_ms);
            d->stop = 1; pthread_cond_broadcast(&d->cv); break;
        }
    }
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
        int p010 = !strcasecmp(fmt, "p010"), p210 = !strcasecmp(fmt, "p210");
        int nv12 = p010 || p210 || !strcasecmp(fmt, "nv12") || !strcasecmp(fmt, "420v");
        int rgba = !fmt[0] || !strcasecmp(fmt, "rgba");
        if (!nv12 && !rgba && strcasecmp(fmt, "bgra")) w_media_raise("VideoDecoder: format must be :rgba, :bgra, :nv12 or :p010/:p210 (got '%s')", fmt);
        int64_t start = (int64_t)w_media_num(m_avf_arr(optv, 0), 0, "start");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 1), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(optv, 2), 0, "rate");
        int timeout_ms = (int)w_media_num(m_avf_arr(optv, 3), 30000, "timeout_ms");
        int queue_cap = (int)w_media_num(m_avf_arr(optv, 4), 6, "decode_ahead");
        ADec *d;
        OSType pix = p210 ? kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange : p010 ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : nv12 ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_32BGRA;
        if (w_is_array(srcv)) {
            int n = 0;
            char **segs = a_paths(srcv, &n);
            d = a_dec_open(NULL, segs, n, num, den, pix, start, timeout_ms, queue_cap, err, sizeof err);
            a_paths_free(segs, n);
        } else {
            if (!w_media_str(srcv, path, sizeof path) || !path[0]) w_media_raise("VideoDecoder: source must be a path or an array of segment paths");
            if (access(path, R_OK) != 0) w_media_raise("VideoDecoder: cannot read %s: %s", path, strerror(errno));
            d = a_dec_open(path, NULL, 0, num, den, pix, start, timeout_ms, queue_cap, err, sizeof err);
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
    int64_t avail;
    uint8_t *dst = (uint8_t *)(uintptr_t)m_avf_dest(dstv, &avail, "VideoDecoder#read");
    int w = d->w, hh = d->h;
    size_t bps = d->pix == kCVPixelFormatType_32BGRA || d->pix == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 1 : 2;
    size_t cw = (size_t)((w + 1) / 2) * 2 * bps, ch = (size_t)((hh + a_dec_vsub(d) - 1) / a_dec_vsub(d));
    size_t row = h->nv12 ? cw : (size_t)w * 4;
    double stride = w_media_num(stridev, (double)row, "stride");
    size_t rows = (size_t)hh + (h->nv12 ? ch : 0);
    if (!isfinite(stride) || stride < (double)row || stride > (double)(SIZE_MAX / rows) ||
        stride != floor(stride) || (h->nv12 && bps == 2 && fmod(stride, 2) != 0))
        w_media_raise("VideoDecoder#read: invalid plane stride");
    size_t ds = (size_t)stride, need = ds * (rows - 1) + row;
    if (avail >= 0 && (size_t)avail < need)
        w_media_raise("VideoDecoder#read: %lld bytes is too few for a %dx%d frame at stride %zu", (long long)avail, w, hh, ds);
    int r = a_dec_next(d, &pb, &frame, err, sizeof err);
    if (r < 0) w_media_raise("VideoDecoder#read: %s", err);
    if (r == 0) return W_NIL;
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    if (h->nv12) {
        const uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *c = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        for (int i = 0; i < hh; i++) memcpy(dst + (size_t)i * ds, y + (size_t)i * ys, (size_t)w * bps);
        for (size_t i = 0; i < ch; i++) memcpy(dst + ds * (size_t)hh + i * ds, c + i * cs, cw);
    } else {
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
    if (!strcmp(k, "cancel")) {
        pthread_mutex_lock(&d->mu);
        if (!d->err[0]) snprintf(d->err, sizeof d->err, "decoder cancelled");
        d->stop = 1; pthread_cond_broadcast(&d->cv);
        pthread_mutex_unlock(&d->mu); return W_TRUE;
    }
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
 * Y'CbCr path (default): frames decode to P010 10-bit 4:2:0 and the Y' and CbCr
 * planes are resampled separately into the encoder's pool buffer (chroma
 * siting honoured on both sides), so there is no colour conversion at all.
 * RGB path (via: "rgb"): frames decode to BGRA (VideoToolbox's BT.709
 * conversion), go through the RGBA scaler and media.c's converter, the way
 * rendered frames do. Segments are cut every gop frames (closed GOPs) and
 * appended one behind, so the encoder keeps working while the mux writes. */

static int a_same_file(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino && a->st_size == b->st_size &&
        a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec &&
        a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec;
}

static int a_file_hash(const char *path, char hex[65]) {
    FILE *file = fopen(path, "rb");
    if (!file) return -1;
    struct stat before, after;
    if (fstat(fileno(file), &before)) { fclose(file); return -1; }
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t buffer[65536], hash[CC_SHA256_DIGEST_LENGTH];
    size_t n;
    while ((n = fread(buffer, 1, sizeof buffer, file))) CC_SHA256_Update(&context, buffer, (CC_LONG)n);
    int bad = ferror(file) || fstat(fileno(file), &after) || !a_same_file(&before, &after); fclose(file);
    if (bad) return -1;
    CC_SHA256_Final(hash, &context);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) snprintf(hex + i*2, 3, "%02x", hash[i]);
    return 0;
}

static pthread_once_t a_identity_once = PTHREAD_ONCE_INIT;
static char a_identity[65];
static void a_identity_init(void) {
    Dl_info image;
    char hash[65], model[256] = "unknown", value[4096];
    size_t n = sizeof model;
    struct utsname system;
    if (!dladdr((void *)w_media_transcode_new, &image) || a_file_hash(image.dli_fname, hash) || uname(&system)) return;
    sysctlbyname("hw.model", model, &n, NULL, 0);
    snprintf(value, sizeof value, "%s|%s|%s|%s|%s|%s", hash, system.sysname, system.release, system.version, system.machine, model);
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(value, (CC_LONG)strlen(value), digest);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) snprintf(a_identity + 2*i, 3, "%02x", digest[i]);
}
WValue w_media_runtime_identity(void) {
    pthread_once(&a_identity_once, a_identity_init);
    if (!a_identity[0]) w_media_raise("Transcode: cannot identify the running media implementation");
    return w_string(a_identity);
}

WValue w_media_source_hash(WValue source) {
    char path[4096], hash[65];
    if (!w_media_str(source, path, sizeof path) || a_file_hash(path, hash)) w_media_raise("Transcode: cannot hash source");
    return w_string(hash);
}

typedef struct ATrans {
    char             resume[4096];
    int              cache_fd, resume_dir_fd, cached_segments, next_checkpoint;
    int64_t          resumed;
    char             cancel_file[4096];
    char             source_path[4096], audio_path[4096];
    struct stat      source_stat, audio_stat;
    uint64_t         disk_reserve;
    int              source_checked, audio_checked, queue_segments, peak_segments;

    ADec          *dec;
    MEncoder      *enc;
    AMux          *mux;
    int            via_rgb;
    WMediaScale    py, pc, prgb;
    int            planned;
    int            y_copy, c_copy, out_bits, in_bits;
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

    /* Async checkpoint/finish pipeline + parallel closed-GOP encoders */
    int                  test_sync;
    int                  jobs, par_nw;
    MEncoder            *par_enc[3];
    uint8_t             *par_rgb[3];
    dispatch_semaphore_t par_slot_sem[3];
    int                  par_slot_held[3];
    dispatch_queue_t     io_q;
    dispatch_group_t     par_grp;
    int                  io_in_flight;
    int64_t              next_submit_seq, next_retire_seq;
    WMediaSegment       *retire_ring[8];
    int                  retire_has[8];
    pthread_mutex_t      mux_q_mu;
    pthread_cond_t       mux_q_cv;
    int                  mux_q_mu_init;
    WMediaSegment       *mux_q[16];
    int                  mux_qn;
    CVPixelBufferRef    *gop_batch;
    int                  gop_batch_n;
    int                  bg_failed;
    char                 bg_err[512];
} ATrans;

static void a_trans_free(ATrans *t) {
    if (!t) return;
    if (t->par_grp) {
        __atomic_store_n(&t->bg_failed, 1, __ATOMIC_RELEASE);
        dispatch_group_wait(t->par_grp, DISPATCH_TIME_FOREVER);
    }
    if (t->gop_batch) {
        for (int i = 0; i < t->gop_batch_n; i++)
            if (t->gop_batch[i]) CVBufferRelease(t->gop_batch[i]);
        free(t->gop_batch);
    }
    for (int i = 0; i < 8; i++) {
        if (t->retire_has[i] && t->retire_ring[i]) w_media_seg_free(t->retire_ring[i]);
    }
    for (int i = 0; i < t->mux_qn; i++) {
        if (t->mux_q[i]) w_media_seg_free(t->mux_q[i]);
    }
    if (t->dec) a_dec_free(t->dec);
    if (t->prev) CVBufferRelease(t->prev);
    for (int i = 0; i < t->nq; i++) w_media_seg_free(t->q[i]);
    for (int i = 1; i < t->par_nw; i++) {
        if (t->par_enc[i]) w_media_enc_free(t->par_enc[i]);
        free(t->par_rgb[i]);
    }
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
    for (int i = 0; i < 3; i++) {
        if (t->par_slot_sem[i]) {
            if (t->par_slot_held[i]) dispatch_semaphore_signal(t->par_slot_sem[i]);
            dispatch_release(t->par_slot_sem[i]);
        }
    }
    if (t->par_grp) dispatch_release(t->par_grp);
    if (t->io_q) dispatch_release(t->io_q);
    if (t->mux_q_mu_init) {
        pthread_cond_destroy(&t->mux_q_cv);
        pthread_mutex_destroy(&t->mux_q_mu);
    }
    if (t->resume_dir_fd >= 0) close(t->resume_dir_fd);
    if (t->cache_fd >= 0) close(t->cache_fd);
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

static void a_cache_path(ATrans *t, int index, char path[4200], const char *extension) {
    snprintf(path, 4200, "%s/%08d.%s", t->resume, index, extension);
}

static void a_cache_scan(ATrans *t) {
    char path[4200], meta[4200], hash[65], want[65], err[512];
    while (t->resumed < t->total) {
        a_cache_path(t, t->cached_segments, path, "twms");
        a_cache_path(t, t->cached_segments, meta, "sha256");
        FILE *f = fopen(meta, "r");
        if (!f) break;
        int ok = fscanf(f, "%64s", want) == 1; fclose(f);
        if (!ok || a_file_hash(path, hash) || strcmp(hash, want)) break;
        WMediaSegment *segment = w_media_seg_load(path, err, sizeof err);
        if (!segment) break;
        int64_t expected = t->total - t->resumed;
        if (expected > t->gop) expected = t->gop;
        ok = segment->n == expected && segment->n > 0 && segment->s[0].sync;
        w_media_seg_free(segment);
        if (!ok) break;
        t->resumed += expected; t->cached_segments++;
    }
    t->done = t->resumed;
    t->next_checkpoint = t->cached_segments;
}

static void a_trans_check_inputs(ATrans *t) {
    if (t->disk_reserve) {
        char directory[4096]; snprintf(directory, sizeof directory, "%s", t->path);
        char *slash = strrchr(directory, '/');
        if (slash) { if (slash == directory) slash[1] = 0; else *slash = 0; }
        else snprintf(directory, sizeof directory, ".");
        struct statvfs space;
        if (statvfs(directory, &space) || (long double)space.f_bavail * space.f_frsize < t->disk_reserve)
            a_trans_raise(t, "configured free-disk reserve reached; delivery preserved");
    }
    struct stat current;
    int changed = (t->source_checked && (stat(t->source_path, &current) || !a_same_file(&current, &t->source_stat))) ||
                  (t->audio_checked && (stat(t->audio_path, &current) || !a_same_file(&current, &t->audio_stat)));
    if (!changed) return;
    /* A mutation can invalidate newly encoded GOPs under the original source key. */
    if (t->resume[0]) for (int i = 0; i < t->next_checkpoint; i++) {
        char path[4200]; a_cache_path(t, i, path, "sha256"); unlink(path);
    }
    a_trans_raise(t, "source changed during the job; checkpoints invalidated");
}

/* Deterministic kill/mutation tests stop at real durable boundaries. Inert
 * unless both explicitly test-named environment variables are supplied. */
static void a_test_barrier(const char *point) {
    const char *chosen = getenv("TUNGSTEN_MEDIA_TEST_BARRIER"), *marker = getenv("TUNGSTEN_MEDIA_TEST_MARKER");
    if (!chosen || !marker || strcmp(chosen, point)) return;
    int fd = open(marker, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    (void)write(fd, point, strlen(point)); (void)fsync(fd); close(fd);
    for (int i = 0; i < 6000 && access(marker, F_OK) == 0; i++) usleep(10000);
}

static void a_cache_save(ATrans *t, WMediaSegment *segment) {
    a_trans_check_inputs(t);
    if (!t->resume[0]) return;
    char path[4200], meta[4200], tmp[4220], hash[65], err[512] = "cannot hash checkpoint";
    a_cache_path(t, t->next_checkpoint, path, "twms");
    a_cache_path(t, t->next_checkpoint, meta, "sha256");
    if (w_media_seg_save_hashed(segment, path, hash, err, sizeof err)) a_trans_raise(t, "checkpoint: %s", err);
    a_test_barrier("segment-synced");
    snprintf(tmp, sizeof tmp, "%s.part", meta);
    FILE *f = fopen(tmp, "w");
    if (!f) a_trans_raise(t, "cannot write checkpoint digest");
    int ok = fprintf(f, "%s\n", hash) > 0 && fflush(f) == 0 && fsync(fileno(f)) == 0;
    ok = fclose(f) == 0 && ok;
    if (!ok || rename(tmp, meta)) { unlink(tmp); a_trans_raise(t, "checkpoint digest commit failed"); }
    if (t->resume_dir_fd >= 0) {
        if (fsync(t->resume_dir_fd)) a_trans_raise(t, "checkpoint directory sync failed");
    } else {
        int directory = open(t->resume, O_RDONLY);
        if (directory < 0 || fsync(directory)) { if (directory >= 0) close(directory); a_trans_raise(t, "checkpoint directory sync failed"); }
        close(directory);
    }
    t->next_checkpoint++;
    a_test_barrier("digest-committed");
}

/* Append the oldest queued segment to the mux. */
static void a_trans_flush_one(ATrans *t) {
    /* the segment stays queued until appended, so a raise leaves it to a_trans_free */
    WMediaSegment *s = t->q[0];
    char err[256];
    uint64_t a = m_avf_now_ns();
    if (w_media_seg_finish(s, err, sizeof err) != 0) a_trans_raise(t, "%s", err);
    a_cache_save(t, s);
    uint64_t b = m_avf_now_ns();
    t->wait_ns += b - a;
    a_mux_append(t->mux, s);
    t->mux_ns += m_avf_now_ns() - b;
    memmove(t->q, t->q + 1, sizeof(t->q[0]) * (size_t)(t->nq - 1));
    t->nq--;
    w_media_seg_free(s);
}

static int a_trans_check_inputs_bg(ATrans *t, char *err, size_t errcap) {
    if (t->disk_reserve) {
        char directory[4096]; snprintf(directory, sizeof directory, "%s", t->path);
        char *slash = strrchr(directory, '/');
        if (slash) { if (slash == directory) slash[1] = 0; else *slash = 0; }
        else snprintf(directory, sizeof directory, ".");
        struct statvfs space;
        if (statvfs(directory, &space) || (long double)space.f_bavail * space.f_frsize < t->disk_reserve) {
            snprintf(err, errcap, "configured free-disk reserve reached; delivery preserved");
            return -1;
        }
    }
    struct stat current;
    int changed = (t->source_checked && (stat(t->source_path, &current) || !a_same_file(&current, &t->source_stat))) ||
                  (t->audio_checked && (stat(t->audio_path, &current) || !a_same_file(&current, &t->audio_stat)));
    if (!changed) return 0;
    if (t->resume[0]) for (int i = 0; i < t->next_checkpoint; i++) {
        char path[4200]; a_cache_path(t, i, path, "sha256"); unlink(path);
    }
    snprintf(err, errcap, "source changed during the job; checkpoints invalidated");
    return -1;
}

static int a_cache_save_bg(ATrans *t, WMediaSegment *segment, char *err, size_t errcap) {
    if (a_trans_check_inputs_bg(t, err, errcap) != 0) return -1;
    if (!t->resume[0]) return 0;
    char path[4200], meta[4200], tmp[4220], hash[65], serr[512] = "cannot hash checkpoint";
    a_cache_path(t, t->next_checkpoint, path, "twms");
    a_cache_path(t, t->next_checkpoint, meta, "sha256");
    if (w_media_seg_save_hashed(segment, path, hash, serr, sizeof serr)) {
        snprintf(err, errcap, "checkpoint: %s", serr);
        return -1;
    }
    snprintf(tmp, sizeof tmp, "%s.part", meta);
    FILE *f = fopen(tmp, "w");
    if (!f) { snprintf(err, errcap, "cannot write checkpoint digest"); return -1; }
    int ok = fprintf(f, "%s\n", hash) > 0 && fflush(f) == 0 && fsync(fileno(f)) == 0;
    ok = fclose(f) == 0 && ok;
    if (!ok || rename(tmp, meta)) { unlink(tmp); snprintf(err, errcap, "checkpoint digest commit failed"); return -1; }
    if (t->resume_dir_fd >= 0) {
        if (fsync(t->resume_dir_fd)) { snprintf(err, errcap, "checkpoint directory sync failed"); return -1; }
    }
    t->next_checkpoint++;
    return 0;
}

static void a_trans_bg_fail(ATrans *t, const char *msg) {
    pthread_mutex_lock(&t->mux_q_mu);
    if (!__atomic_load_n(&t->bg_failed, __ATOMIC_RELAXED)) {
        snprintf(t->bg_err, sizeof t->bg_err, "%s", msg);
        __atomic_store_n(&t->bg_failed, 1, __ATOMIC_RELEASE);
    }
    pthread_cond_broadcast(&t->mux_q_cv);
    pthread_mutex_unlock(&t->mux_q_mu);
}

/* Must be called on the main Tungsten thread. */
static void a_trans_drain_mux_ready(ATrans *t, int wait_all) {
    if (wait_all && t->par_grp) dispatch_group_wait(t->par_grp, DISPATCH_TIME_FOREVER);
    if (__atomic_load_n(&t->bg_failed, __ATOMIC_ACQUIRE)) a_trans_raise(t, "%s", t->bg_err);
    for (;;) {
        WMediaSegment *s = NULL;
        pthread_mutex_lock(&t->mux_q_mu);
        if (t->mux_qn > 0) {
            s = t->mux_q[0];
            memmove(t->mux_q, t->mux_q + 1, sizeof(t->mux_q[0]) * (size_t)(t->mux_qn - 1));
            t->mux_qn--;
            t->io_in_flight--;
        }
        pthread_mutex_unlock(&t->mux_q_mu);
        if (!s) break;
        uint64_t b = m_avf_now_ns();
        a_mux_append(t->mux, s);
        t->mux_ns += m_avf_now_ns() - b;
        w_media_seg_free(s);
    }
    if (__atomic_load_n(&t->bg_failed, __ATOMIC_ACQUIRE)) a_trans_raise(t, "%s", t->bg_err);
}

/* Must be called on the main Tungsten thread to reserve one of the 6 bounded
 * in-flight segment slots, draining any completed mux_q segments while waiting. */
static void a_trans_acquire_io_slot(ATrans *t) {
    for (;;) {
        a_trans_drain_mux_ready(t, 0);
        pthread_mutex_lock(&t->mux_q_mu);
        if (t->io_in_flight < 6) {
            t->io_in_flight++;
            pthread_mutex_unlock(&t->mux_q_mu);
            return;
        }
        while (t->io_in_flight >= 6 && t->mux_qn == 0 && !__atomic_load_n(&t->bg_failed, __ATOMIC_ACQUIRE))
            pthread_cond_wait(&t->mux_q_cv, &t->mux_q_mu);
        pthread_mutex_unlock(&t->mux_q_mu);
    }
}

static void a_trans_retire_on_ioq(ATrans *t, int64_t seq, WMediaSegment *s) {
    if (__atomic_load_n(&t->bg_failed, __ATOMIC_ACQUIRE)) {
        w_media_seg_free(s);
        pthread_mutex_lock(&t->mux_q_mu);
        t->io_in_flight--;
        pthread_cond_broadcast(&t->mux_q_cv);
        pthread_mutex_unlock(&t->mux_q_mu);
        return;
    }
    int slot = (int)(seq & 7);
    t->retire_ring[slot] = s;
    t->retire_has[slot] = 1;
    while (t->retire_has[t->next_retire_seq & 7]) {
        int rs = (int)(t->next_retire_seq & 7);
        WMediaSegment *cur = t->retire_ring[rs];
        t->retire_ring[rs] = NULL;
        t->retire_has[rs] = 0;
        t->next_retire_seq++;
        char err[512];
        if (a_cache_save_bg(t, cur, err, sizeof err) != 0) {
            a_trans_bg_fail(t, err);
            w_media_seg_free(cur);
            pthread_mutex_lock(&t->mux_q_mu);
            t->io_in_flight--;
            pthread_cond_broadcast(&t->mux_q_cv);
            pthread_mutex_unlock(&t->mux_q_mu);
        } else {
            pthread_mutex_lock(&t->mux_q_mu);
            t->mux_q[t->mux_qn++] = cur;
            pthread_cond_broadcast(&t->mux_q_cv);
            pthread_mutex_unlock(&t->mux_q_mu);
        }
    }
}

static void a_trans_cut(ATrans *t) {
    WMediaSegment *s = w_media_enc_cut(t->enc);
    t->seg_frames = 0;
    if (!s) return;
    if (t->test_sync || !t->io_q) {
        t->q[t->nq++] = s;
        if (t->nq > t->peak_segments) t->peak_segments = t->nq;
        if (t->nq >= t->queue_segments) a_trans_flush_one(t);
        return;
    }
    a_trans_acquire_io_slot(t);
    int64_t seq = t->next_submit_seq++;
    if (t->peak_segments < 3) t->peak_segments = 3;
    dispatch_group_async(t->par_grp, t->io_q, ^{
        char err[512];
        uint64_t a = m_avf_now_ns();
        if (w_media_seg_finish(s, err, sizeof err) != 0) {
            a_trans_bg_fail(t, err);
            w_media_seg_free(s);
            pthread_mutex_lock(&t->mux_q_mu);
            t->io_in_flight--;
            pthread_cond_broadcast(&t->mux_q_cv);
            pthread_mutex_unlock(&t->mux_q_mu);
            return;
        }
        __atomic_add_fetch(&t->wait_ns, m_avf_now_ns() - a, __ATOMIC_RELAXED);
        a_trans_retire_on_ioq(t, seq, s);
    });
}

/* Bit-exact 1:1 plane copy from MSB-aligned 10-bit words (P010/P210) to 10-bit
 * or 8-bit encoder plane, matching the Lanczos/bicubic/bilinear identity weights. */
static void a_plane_copy_10(const uint8_t *src, size_t sstride, uint8_t *dst, size_t dstride,
                            int nsamples, int rows, int out_bits) {
    if (out_bits == 10) {
        size_t row_bytes = (size_t)nsamples * 2;
        if (sstride == row_bytes && dstride == row_bytes) {
            a_pcopy(dst, src, row_bytes * (size_t)rows);
            return;
        }
        for (int y = 0; y < rows; y++) {
            const uint16_t *sr = (const uint16_t *)(const void *)(src + (size_t)y * sstride);
            uint16_t *dr = (uint16_t *)(void *)(dst + (size_t)y * dstride);
#if defined(__aarch64__)
            int x = 0;
            uint16x8_t mask = vdupq_n_u16(0xFFC0u);
            for (; x + 8 <= nsamples; x += 8)
                vst1q_u16(dr + x, vandq_u16(vld1q_u16(sr + x), mask));
            for (; x < nsamples; x++) dr[x] = sr[x] & 0xFFC0u;
#else
            for (int x = 0; x < nsamples; x++) dr[x] = sr[x] & 0xFFC0u;
#endif
        }
        return;
    }
    for (int y = 0; y < rows; y++) {
        const uint16_t *sr = (const uint16_t *)(const void *)(src + (size_t)y * sstride);
        uint8_t *dr = dst + (size_t)y * dstride;
        int x = 0;
#if defined(__aarch64__)
        for (; x + 16 <= nsamples; x += 16) {
            uint16x8_t w0 = vrshrq_n_u16(vshrq_n_u16(vld1q_u16(sr + x), 6), 2);
            uint16x8_t w1 = vrshrq_n_u16(vshrq_n_u16(vld1q_u16(sr + x + 8), 6), 2);
            vst1q_u8(dr + x, vcombine_u8(vqmovn_u16(w0), vqmovn_u16(w1)));
        }
#endif
        for (; x < nsamples; x++) {
            uint32_t v = ((uint32_t)(sr[x] >> 6) + 2u) >> 2;
            dr[x] = (uint8_t)(v > 255u ? 255u : v);
        }
    }
}

/* Bit-exact 1:1 plane copy from a decoder plane of in_bits (8: NV12 bytes; 10:
 * MSB-aligned P010/P210 words) to an 8- or 10-bit encoder plane. */
static void a_plane_copy(const uint8_t *src, size_t sstride, uint8_t *dst, size_t dstride,
                         int nsamples, int rows, int in_bits, int out_bits) {
    if (in_bits > 8) {
        a_plane_copy_10(src, sstride, dst, dstride, nsamples, rows, out_bits);
        return;
    }
    if (out_bits <= 8) {
        if (sstride == (size_t)nsamples && dstride == (size_t)nsamples) {
            a_pcopy(dst, src, (size_t)nsamples * (size_t)rows);
            return;
        }
        for (int y = 0; y < rows; y++) memcpy(dst + (size_t)y * dstride, src + (size_t)y * sstride, (size_t)nsamples);
        return;
    }
    /* 8 -> 10 bits, MSB-aligned: the 10-bit code is v << 2, stored << 6 */
    for (int y = 0; y < rows; y++) {
        const uint8_t *sr = src + (size_t)y * sstride;
        uint16_t *dr = (uint16_t *)(void *)(dst + (size_t)y * dstride);
        for (int x = 0; x < nsamples; x++) dr[x] = (uint16_t)((uint16_t)sr[x] << 8);
    }
}

/* Scale one decoded frame into `enc` and submit it (0 on success, -1 with message in err). */
static int a_encode_frame_to(ATrans *t, MEncoder *enc, uint8_t *rgb_buf, CVPixelBufferRef src, int64_t fidx,
                             uint64_t *scale_ns_out, int *used_out, char *err, size_t errcap) {
    char serr[256];
    uint64_t t0 = m_avf_now_ns();
    if ((int)CVPixelBufferGetWidth(src) != t->sw || (int)CVPixelBufferGetHeight(src) != t->sh) {
        snprintf(err, errcap, "frame %lld is %dx%d, the source began at %dx%d",
                 (long long)fidx, (int)CVPixelBufferGetWidth(src), (int)CVPixelBufferGetHeight(src), t->sw, t->sh);
        return -1;
    }
    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    if (t->via_rgb) {
        const uint8_t *p = CVPixelBufferGetBaseAddress(src);
        size_t ps = CVPixelBufferGetBytesPerRow(src);
        int b = w_media_scale_run(&t->prgb, t->backend, p, ps, ps * CVPixelBufferGetHeight(src), rgb_buf, (size_t)t->w * 4, t->rgb_len, serr, sizeof serr);
        CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
        if (b < 0) { snprintf(err, errcap, "scaling: %s", serr); return -1; }
        *used_out = b;
        *scale_ns_out += m_avf_now_ns() - t0;
        int st = w_media_enc_encode_rgb(enc, rgb_buf, (size_t)t->w * 4);
        if (st != 0) { snprintf(err, errcap, "VideoToolbox could not encode frame %lld (%d)", (long long)fidx, st); return -1; }
        return 0;
    }
    CVPixelBufferRef out = w_media_enc_buffer(enc);
    if (!out) {
        CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
        snprintf(err, errcap, "no pixel buffer from the encoder");
        return -1;
    }
    CVPixelBufferLockBaseAddress(out, 0);
    const uint8_t *sy = CVPixelBufferGetBaseAddressOfPlane(src, 0), *sc = CVPixelBufferGetBaseAddressOfPlane(src, 1);
    size_t sys = CVPixelBufferGetBytesPerRowOfPlane(src, 0), scs = CVPixelBufferGetBytesPerRowOfPlane(src, 1);
    uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(out, 0), *dc = CVPixelBufferGetBaseAddressOfPlane(out, 1);
    size_t dys = CVPixelBufferGetBytesPerRowOfPlane(out, 0), dcs = CVPixelBufferGetBytesPerRowOfPlane(out, 1);
    size_t syl = sys * CVPixelBufferGetHeightOfPlane(src, 0), scl = scs * CVPixelBufferGetHeightOfPlane(src, 1);
    size_t dyl = dys * CVPixelBufferGetHeightOfPlane(out, 0), dcl = dcs * CVPixelBufferGetHeightOfPlane(out, 1);
    int b = 0, b2 = 0;
    int req_be = __atomic_load_n(&t->backend, __ATOMIC_RELAXED);
    int be = req_be == W_MEDIA_BACKEND_AUTO ? w_media_scale_default_backend(1, t->py.filter) : req_be;
    if (t->y_copy && t->c_copy && !(req_be == W_MEDIA_BACKEND_METAL && !w_media_metal_available())) {
        a_plane_copy(sy, sys, dy, dys, t->w, t->h, t->in_bits, t->out_bits);
        a_plane_copy(sc, scs, dc, dcs, t->pc.dst_w * 2, t->pc.dst_h, t->in_bits, t->out_bits);
        b = b2 = be;
    } else if (t->y_copy && !(req_be == W_MEDIA_BACKEND_METAL && !w_media_metal_available())) {
        a_plane_copy(sy, sys, dy, dys, t->w, t->h, t->in_bits, t->out_bits);
        if (be == W_MEDIA_BACKEND_METAL) {
            WMediaJob job = {&t->pc, sc, scs, scl, dc, dcs, dcl, src, out, 1, 1};
            b = b2 = w_media_scale_metal_jobs(&job, 1, serr, sizeof serr) == 0 ? W_MEDIA_BACKEND_METAL : -1;
            if (b < 0 && req_be == W_MEDIA_BACKEND_METAL) {
                CVPixelBufferUnlockBaseAddress(out, 0);
                CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferRelease(out);
                snprintf(err, errcap, "Metal scaling: %s", serr);
                return -1;
            }
            if (b < 0) {
                __atomic_store_n(&t->backend, W_MEDIA_BACKEND_CPU, __ATOMIC_RELAXED);
                b = b2 = w_media_scale_run(&t->pc, W_MEDIA_BACKEND_CPU, sc, scs, scl, dc, dcs, dcl, serr, sizeof serr);
            }
        } else {
            b = b2 = w_media_scale_run(&t->pc, req_be, sc, scs, scl, dc, dcs, dcl, serr, sizeof serr);
        }
    } else if (be == W_MEDIA_BACKEND_METAL) {
        WMediaJob jobs[2] = {{&t->py, sy, sys, syl, dy, dys, dyl, src, out, 0, 0},
                             {&t->pc, sc, scs, scl, dc, dcs, dcl, src, out, 1, 1}};
        b = b2 = w_media_scale_metal_jobs(jobs, 2, serr, sizeof serr) == 0 ? W_MEDIA_BACKEND_METAL : -1;
        if (b < 0 && req_be == W_MEDIA_BACKEND_METAL) {
            CVPixelBufferUnlockBaseAddress(out, 0);
            CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
            CVPixelBufferRelease(out);
            snprintf(err, errcap, "Metal scaling: %s", serr);
            return -1;
        }
        if (b < 0) {
            __atomic_store_n(&t->backend, W_MEDIA_BACKEND_CPU, __ATOMIC_RELAXED);
            b = w_media_scale_run(&t->py, W_MEDIA_BACKEND_CPU, sy, sys, syl, dy, dys, dyl, serr, sizeof serr);
            b2 = b < 0 ? b : w_media_scale_run(&t->pc, W_MEDIA_BACKEND_CPU, sc, scs, scl, dc, dcs, dcl, serr, sizeof serr);
        }
    } else {
        b = w_media_scale_run(&t->py, req_be, sy, sys, syl, dy, dys, dyl, serr, sizeof serr);
        b2 = b < 0 ? b : w_media_scale_run(&t->pc, req_be, sc, scs, scl, dc, dcs, dcl, serr, sizeof serr);
    }
    CVPixelBufferUnlockBaseAddress(out, 0);
    CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    if (b2 < 0) { CVPixelBufferRelease(out); snprintf(err, errcap, "scaling: %s", serr); return -1; }
    *used_out = b;
    *scale_ns_out += m_avf_now_ns() - t0;
    int st = w_media_enc_submit(enc, out);
    if (st != 0) { snprintf(err, errcap, "VideoToolbox could not encode frame %lld (OSStatus %d)", (long long)fidx, st); return -1; }
    return 0;
}

/* Flush the buffered GOP batch (`t->gop_batch[0..gop_batch_n-1]`) to parallel encoder slot `seq % par_nw`. */
static void a_trans_submit_gop_batch(ATrans *t) {
    int count = t->gop_batch_n;
    if (count <= 0) return;
    int wi = (int)(t->next_submit_seq % t->par_nw);
    dispatch_semaphore_wait(t->par_slot_sem[wi], DISPATCH_TIME_FOREVER);
    t->par_slot_held[wi] = 1;
    a_trans_acquire_io_slot(t);
    CVPixelBufferRef *pbs = malloc((size_t)count * sizeof(CVPixelBufferRef));
    memcpy(pbs, t->gop_batch, (size_t)count * sizeof(CVPixelBufferRef));
    t->gop_batch_n = 0;
    int64_t seq = t->next_submit_seq++;
    int64_t base_fidx = t->done - count;
    if (t->peak_segments < t->par_nw + 1) t->peak_segments = t->par_nw + 1;
    dispatch_group_async(t->par_grp, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            char err[512];
            uint64_t w_scale = 0;
            int w_used = 0, failed = __atomic_load_n(&t->bg_failed, __ATOMIC_ACQUIRE);
            MEncoder *enc = t->par_enc[wi];
            uint8_t *rgb_buf = t->par_rgb[wi];
            for (int i = 0; i < count; i++) {
                if (!failed && a_encode_frame_to(t, enc, rgb_buf, pbs[i], base_fidx + i, &w_scale, &w_used, err, sizeof err) != 0) {
                    a_trans_bg_fail(t, err);
                    failed = 1;
                }
                CVBufferRelease(pbs[i]);
            }
            free(pbs);
            WMediaSegment *s = w_media_enc_cut(enc);
            t->par_slot_held[wi] = 0;
            dispatch_semaphore_signal(t->par_slot_sem[wi]);
            __atomic_add_fetch(&t->scale_ns, w_scale, __ATOMIC_RELAXED);
            if (w_used) __atomic_store_n(&t->used, w_used, __ATOMIC_RELAXED);
            if (failed || !s) {
                if (s) w_media_seg_free(s);
                pthread_mutex_lock(&t->mux_q_mu);
                t->io_in_flight--;
                pthread_cond_broadcast(&t->mux_q_cv);
                pthread_mutex_unlock(&t->mux_q_mu);
                return;
            }
            uint64_t a = m_avf_now_ns();
            if (w_media_seg_finish(s, err, sizeof err) != 0) {
                a_trans_bg_fail(t, err);
                w_media_seg_free(s);
                pthread_mutex_lock(&t->mux_q_mu);
                t->io_in_flight--;
                pthread_cond_broadcast(&t->mux_q_cv);
                pthread_mutex_unlock(&t->mux_q_mu);
                return;
            }
            __atomic_add_fetch(&t->wait_ns, m_avf_now_ns() - a, __ATOMIC_RELAXED);
            dispatch_group_async(t->par_grp, t->io_q, ^{
                a_trans_retire_on_ioq(t, seq, s);
            });
        }
    });
}

/* Scale one decoded frame into the encoder and submit it. */
static void a_trans_encode(ATrans *t, CVPixelBufferRef src) {
    if (t->par_nw > 1) {
        t->gop_batch[t->gop_batch_n++] = (CVPixelBufferRef)CVBufferRetain(src);
        t->done++;
        if (t->gop_batch_n == t->gop) a_trans_submit_gop_batch(t);
        return;
    }
    char err[512];
    if (a_encode_frame_to(t, t->enc, t->rgb, src, t->done, &t->scale_ns, &t->used, err, sizeof err) != 0)
        a_trans_raise(t, "%s", err);
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
        t->cache_fd = -1;
        t->resume_dir_fd = -1;
        double reserve = w_media_num(a_spec(spec, "disk_reserve_bytes"), 0, "disk_reserve_bytes");
        if (!isfinite(reserve) || reserve < 0 || reserve > 1e18) { a_trans_free(t); w_media_raise("Transcode: invalid disk reserve"); }
        t->disk_reserve = (uint64_t)reserve;
        w_media_str(a_spec(spec, "cancel_file"), t->cancel_file, sizeof t->cancel_file);
        t->chap = ch;
        t->nchap = nch;
        t->t0 = m_avf_now_ns();
        int timeout_ms = (int)w_media_num(a_spec(spec, "timeout_ms"), 30000, "timeout_ms");
        int queue_cap = (int)w_media_num(a_spec(spec, "decode_ahead"), 6, "decode_ahead");
        t->queue_segments = (int)w_media_num(a_spec(spec, "segments_ahead"), 3, "segments_ahead");
        if (t->queue_segments < 1 || t->queue_segments > 3) { a_trans_free(t); w_media_raise("Transcode: segments_ahead must be in 1..3"); }
        WValue srcv = a_spec(spec, "src");
        if (!w_media_str(a_spec(spec, "dst"), dst, sizeof dst) || !dst[0]) { a_trans_free(t); w_media_raise("Transcode: dst must be a path"); }
        snprintf(t->path, sizeof t->path, "%s", dst);
        WValue ratev = a_spec(spec, "rate");
        int32_t num = (int32_t)w_media_num(m_avf_arr(ratev, 0), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(ratev, 1), 0, "rate");
        if (num <= 0 || den <= 0) { a_trans_free(t); w_media_raise("Transcode: rate must be [num, den]"); }
        t->start = (int64_t)w_media_num(a_spec(spec, "start"), 0, "start");
        t->total = (int64_t)w_media_num(a_spec(spec, "frames"), 0, "frames");
        if (t->total <= 0) { a_trans_free(t); w_media_raise("Transcode: frames must be positive"); }
        t->gop = (int)w_media_num(a_spec(spec, "gop"), 48, "gop");
        if (t->gop < 1) t->gop = 1;
        w_media_str(a_spec(spec, "resume_dir"), t->resume, sizeof t->resume);
        if (t->resume[0]) {
            char lock[4200]; snprintf(lock, sizeof lock, "%s/.lock", t->resume);
            t->cache_fd = open(lock, O_CREAT | O_RDWR, 0600);
            if (t->cache_fd < 0 || flock(t->cache_fd, LOCK_EX | LOCK_NB)) { a_trans_free(t); w_media_raise("Transcode: resume cache is busy or inaccessible"); }
            t->resume_dir_fd = open(t->resume, O_RDONLY);
            if (t->resume_dir_fd < 0) { a_trans_free(t); w_media_raise("Transcode: resume cache directory is inaccessible"); }
            a_cache_scan(t);
        }
        w_media_str(a_spec(spec, "via"), buf, sizeof buf);
        t->via_rgb = !strcasecmp(buf, "rgb") || !strcasecmp(buf, "rgba");
        OSType pix = t->via_rgb ? kCVPixelFormatType_32BGRA : A_PIX_NATIVE;
        if (w_is_array(srcv)) {
            int n = 0;
            char **segs = a_paths(srcv, &n);
            t->dec = a_dec_open(NULL, segs, n, num, den, pix, t->start + t->resumed, timeout_ms, queue_cap, err, sizeof err);
            a_paths_free(segs, n);
        } else {
            if (!w_media_str(srcv, src, sizeof src) || !src[0]) { a_trans_free(t); w_media_raise("Transcode: src must be a path or an array of segment paths"); }
            if (access(src, R_OK) != 0) { int e = errno; a_trans_free(t); w_media_raise("Transcode: cannot read %s: %s", src, strerror(e)); }
            struct stat before;
            char expected[65], actual[65];
            w_media_str(a_spec(spec, "source_hash"), expected, sizeof expected);
            int src_verified = a_spec(spec, "source_verified") > 1;
            if (stat(src, &before) || (expected[0] && !src_verified && (a_file_hash(src, actual) || strcmp(expected, actual))) ||
                stat(src, &t->source_stat) || !a_same_file(&before, &t->source_stat)) {
                a_trans_free(t); w_media_raise("Transcode: source changed before decoding");
            }
            snprintf(t->source_path, sizeof t->source_path, "%s", src); t->source_checked = 1;
            t->dec = a_dec_open(src, NULL, 0, num, den, pix, t->start + t->resumed, timeout_ms, queue_cap, err, sizeof err);
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
            int source_vsub = a_dec_vsub(t->dec);
            double osx = s == 1 ? 1.0 : 0.5, osy = source_vsub == 1 || s == 2 ? 0.5 : 1.0;
            rc = w_media_scale_plan(&t->py, 1, W_MEDIA_ALPHA_NONE, filter, t->sw, t->sh, t->w, t->h, crop, rect, 1, 1, 0.5, 0.5,
                                    1, 1, 0.5, 0.5, fy, bits, err, sizeof err);
            if (rc == 0) {
                rc = w_media_scale_plan(&t->pc, 2, W_MEDIA_ALPHA_NONE, filter, (t->sw + 1) / 2, (t->sh + source_vsub - 1) / source_vsub, t->w / 2, t->h / vsub,
                                        crop, rect, 2, source_vsub, osx, osy, 2, vsub, 0.5, vsub == 2 ? 1.0 : 0.5, fc, bits, err, sizeof err);
                if (rc != 0) w_media_scale_free(&t->py);
            }
        }
        if (rc != 0) { a_trans_free(t); w_media_raise("Transcode: %s", err); }
        if (!t->via_rgb) {
            t->in_bits = a_dec_bits(t->dec);
            t->py.in_bits = t->pc.in_bits = t->in_bits;
            t->py.vimage_ok = t->pc.vimage_ok = 0;
            t->out_bits = bits;
            int s = t->dec->siting;
            int source_vsub = a_dec_vsub(t->dec);
            double osx = s == 1 ? 1.0 : 0.5, osy = source_vsub == 1 || s == 2 ? 0.5 : 1.0;
            double ody = vsub == 2 ? 1.0 : 0.5;
            if (t->sw == t->w && t->sh == t->h &&
                crop[0] == 0.0 && crop[1] == 0.0 && crop[2] == (double)t->sw && crop[3] == (double)t->sh &&
                rect[0] == 0 && rect[1] == 0 && rect[2] == t->w && rect[3] == t->h) {
                t->y_copy = 1;
                if ((t->w % 2) == 0 && (t->h % vsub) == 0 && source_vsub == vsub && osx == 0.5 && osy == ody)
                    t->c_copy = 1;
            }
        }
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
            if (strcmp(apath, t->source_path)) {
                struct stat before;
                char expected[65], actual[65];
                w_media_str(a_spec(spec, "audio_hash"), expected, sizeof expected);
                int aud_verified = a_spec(spec, "audio_verified") > 1;
                if (stat(apath, &before) || (expected[0] && !aud_verified && (a_file_hash(apath, actual) || strcmp(expected, actual))) ||
                    stat(apath, &t->audio_stat) || !a_same_file(&before, &t->audio_stat)) {
                    a_trans_free(t); w_media_raise("Transcode: audio source changed before decoding");
                }
                snprintf(t->audio_path, sizeof t->audio_path, "%s", apath); t->audio_checked = 1;
            }
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
        WValue edits = a_spec(spec, "edit_lists");
        if (edits == W_FALSE) t->mux->flatten_edits = 2;
        else {
            char mode[32]; w_media_str(edits, mode, sizeof mode);
            if (!strcmp(mode, "audio")) t->mux->flatten_edits = 1;
        }
        a_mux_set_chapters(t->mux, t->chap, t->nchap);
        for (int i = 0; i < t->cached_segments; i++) {
            char checkpoint[4200]; a_cache_path(t, i, checkpoint, "twms");
            WMediaSegment *cached = w_media_seg_load(checkpoint, err, sizeof err);
            if (!cached) { a_trans_free(t); w_media_raise("Transcode: checkpoint changed during reuse"); }
            a_mux_append(t->mux, cached); w_media_seg_free(cached);
        }
        t->test_sync = (getenv("TUNGSTEN_MEDIA_TEST_BARRIER") != NULL ||
                        getenv("TUNGSTEN_MEDIA_TEST_FAIL_AFTER") != NULL ||
                        getenv("TUNGSTEN_MEDIA_TEST_STALL_DECODER") != NULL);
        t->jobs = (int)w_media_num(a_spec(spec, "jobs"), 1, "jobs");
        if (!t->test_sync) {
            pthread_mutex_init(&t->mux_q_mu, NULL);
            pthread_cond_init(&t->mux_q_cv, NULL);
            t->mux_q_mu_init = 1;
            t->io_q = dispatch_queue_create("tungsten.transcode.io", DISPATCH_QUEUE_SERIAL);
            t->par_grp = dispatch_group_create();
            int want_nw = (t->jobs > 1 && (t->total - t->resumed) >= (int64_t)t->gop * 2) ? (t->jobs > 3 ? 3 : t->jobs) : 1;
            t->par_enc[0] = t->enc;
            t->par_rgb[0] = t->rgb;
            t->par_nw = 1;
            if (want_nw > 1) {
                for (int i = 1; i < want_nw; i++) {
                    MEncoder *ew = w_media_enc_open(codec[0] ? codec : "h264", t->w, t->h, num, den,
                                                    w_media_num(a_spec(spec, "quality"), -1.0, "quality"),
                                                    (int64_t)w_media_num(a_spec(spec, "bitrate"), 0, "bitrate"),
                                                    t->gop, t->via_rgb ? "bgra" : "rgba", "left",
                                                    reorderv == W_NIL ? 1 : reorderv > 1, a_spec(spec, "speed") > 1, level, err, sizeof err);
                    if (!ew) break;
                    if (t->via_rgb) {
                        if (posix_memalign((void **)&t->par_rgb[i], 16384, (t->rgb_len + 16383) & ~(size_t)16383) != 0) {
                            t->par_rgb[i] = NULL;
                            w_media_enc_free(ew);
                            break;
                        }
                    }
                    t->par_enc[i] = ew;
                    t->par_nw++;
                }
                if (t->par_nw > 1) {
                    for (int i = 0; i < t->par_nw; i++) t->par_slot_sem[i] = dispatch_semaphore_create(1);
                    t->gop_batch = calloc((size_t)t->gop, sizeof(CVPixelBufferRef));
                }
            }
        }
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
        a_trans_check_inputs(t);
        if (t->io_q) a_trans_drain_mux_ready(t, 0);
        if (t->cancel_file[0] && access(t->cancel_file, F_OK) == 0) a_trans_raise(t, "transcode cancelled");
        while (t->done < t->total && k < n) {
            if (t->cancel_file[0] && access(t->cancel_file, F_OK) == 0) a_trans_raise(t, "transcode cancelled");
            const char *fail = getenv("TUNGSTEN_MEDIA_TEST_FAIL_AFTER");
            if (fail && t->done >= strtoll(fail, NULL, 10)) a_trans_raise(t, "injected media failure after %lld frames", (long long)t->done);
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
        if (t->io_q) a_trans_drain_mux_ready(t, 0);
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
        a_trans_check_inputs(t);
        if (t->done < t->total) a_trans_raise(t, "finish after %lld of %lld frames (step until done)", (long long)t->done, (long long)t->total);
        if (t->par_nw > 1 && t->gop_batch_n > 0) a_trans_submit_gop_batch(t);
        if (t->seg_frames > 0) {
            if (t->io_q && !t->test_sync) {
                a_trans_cut(t);
            } else {
                WMediaSegment *s = w_media_enc_cut(t->enc);
                t->seg_frames = 0;
                if (s) t->q[t->nq++] = s;
            }
        }
        while (t->nq > 0) a_trans_flush_one(t);
        if (t->io_q) a_trans_drain_mux_ready(t, 1);
        double conv_s = w_media_enc_seconds(t->enc, 0), sub_s = w_media_enc_seconds(t->enc, 1), ewait_s = w_media_enc_seconds(t->enc, 2);
        for (int i = 1; i < t->par_nw; i++) {
            conv_s += w_media_enc_seconds(t->par_enc[i], 0);
            sub_s += w_media_enc_seconds(t->par_enc[i], 1);
            ewait_s += w_media_enc_seconds(t->par_enc[i], 2);
        }
        int64_t out[5];
        uint64_t a = m_avf_now_ns();
        a_mux_finish(t->mux, out);
        a_test_barrier("mux-finished");
        t->mux_ns += m_avf_now_ns() - a;
        t->finished = 1;
        WValue r = w_array_new_empty();
        r = w_array_push(r, a_pair("resumed_frames", w_int(t->resumed)));
        r = w_array_push(r, a_pair("frames", w_int(out[0])));
        r = w_array_push(r, a_pair("duplicated", w_int(t->dups)));
        r = w_array_push(r, a_pair("dropped", w_int(t->drops)));
        r = w_array_push(r, a_pair("audio_samples", w_int(out[1])));
        r = w_array_push(r, a_pair("video_bytes", w_int(out[3])));
        r = w_array_push(r, a_pair("file_bytes", w_int(out[4])));
        r = w_array_push(r, a_pair("seconds", w_float((double)(m_avf_now_ns() - t->t0) / 1e9)));
        r = w_array_push(r, a_pair("decode_s", w_float((double)t->dec->dec_ns / 1e9)));
        r = w_array_push(r, a_pair("scale_s", w_float((double)t->scale_ns / 1e9)));
        r = w_array_push(r, a_pair("convert_s", w_float(conv_s)));
        r = w_array_push(r, a_pair("submit_s", w_float(sub_s)));
        r = w_array_push(r, a_pair("encode_wait_s", w_float(t->wait_ns / 1e9 + ewait_s)));
        r = w_array_push(r, a_pair("mux_s", w_float((double)t->mux_ns / 1e9)));
        r = w_array_push(r, a_pair("scale_backend", w_string(w_media_backend_name(t->used))));
        r = w_array_push(r, a_pair("decode_bits", w_int(t->via_rgb ? 8 : 10)));
        r = w_array_push(r, a_pair("decode_chroma", w_string(t->via_rgb ? "rgb" : a_dec_vsub(t->dec) == 1 ? "422" : "420")));
        r = w_array_push(r, a_pair("decoder_queue_peak", w_int(t->dec->peak_qn)));
        r = w_array_push(r, a_pair("segment_queue_peak", w_int(t->peak_segments)));
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
        int edit_fd = open(path.UTF8String, O_RDONLY), edit_count = -1;
        if (edit_fd >= 0) {
            ATop tops[64]; int nt = 0, mi = -1; ABox root; char error[256];
            if (!a_read_moov(edit_fd, path.UTF8String, tops, &nt, &mi, &root, error, sizeof error)) {
                edit_count = 0;
                ABox *moov = &root.kid[0];
                for (int i = 0; i < moov->nk; i++) {
                    ABox *t = &moov->kid[i];
                    if (t->type == A_FOURCC('t','r','a','k') && a_box_find(t, A_FOURCC('e','d','t','s'))) edit_count++;
                }
                a_box_free(&root);
            }
            close(edit_fd);
        }
        out = w_array_push(out, a_pair("edit_lists", w_int(edit_count)));
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
                /* ProRes 422's four registered profiles carry 10-bit 4:2:2. */
                if (sub == kCMVideoCodecType_AppleProRes422 || sub == kCMVideoCodecType_AppleProRes422HQ ||
                    sub == kCMVideoCodecType_AppleProRes422LT || sub == kCMVideoCodecType_AppleProRes422Proxy) {
                    out = w_array_push(out, a_pair("bit_depth", w_int(10)));
                    out = w_array_push(out, a_pair("chroma_format", w_int(2)));
                }
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
            uint32_t sub = fd ? CMFormatDescriptionGetMediaSubType(fd) : 0;
            out = w_array_push(out, a_pair("audio_codec", a_fourcc(sub)));
            if (asbd) {
                char cname[32] = "";
                uint32_t fid = asbd->mFormatID, flags = asbd->mFormatFlags, bits = asbd->mBitsPerChannel;
                if (fid == kAudioFormatMPEG4AAC || sub == A_FOURCC('a','a','c',' ')) snprintf(cname, sizeof cname, "aac");
                else if (fid == kAudioFormatAppleLossless || sub == A_FOURCC('a','l','a','c')) snprintf(cname, sizeof cname, "alac");
                else if (fid == kAudioFormatFLAC || sub == A_FOURCC('f','l','a','c')) snprintf(cname, sizeof cname, "flac");
                else if (fid == kAudioFormatMPEGLayer3 || sub == A_FOURCC('.','m','p','3')) snprintf(cname, sizeof cname, "mp3");
                else if (fid == kAudioFormatOpus || sub == A_FOURCC('o','p','u','s')) snprintf(cname, sizeof cname, "opus");
                else if (fid == kAudioFormatAC3 || sub == A_FOURCC('a','c','-','3')) snprintf(cname, sizeof cname, "ac3");
                else if (fid == kAudioFormatEnhancedAC3 || sub == A_FOURCC('e','c','-','3')) snprintf(cname, sizeof cname, "eac3");
                else if (fid == kAudioFormatLinearPCM) {
                    int be = (flags & kAudioFormatFlagIsBigEndian) != 0;
                    if ((flags & kAudioFormatFlagIsFloat) || sub == A_FOURCC('f','l','3','2') || sub == A_FOURCC('f','l','6','4'))
                        snprintf(cname, sizeof cname, "pcm_f%u%s", bits ? bits : 32u, be ? "be" : "le");
                    else if (bits == 8)
                        snprintf(cname, sizeof cname, "%s", (flags & kAudioFormatFlagIsSignedInteger) ? "pcm_s8" : "pcm_u8");
                    else
                        snprintf(cname, sizeof cname, "pcm_s%u%s", bits ? bits : 16u, be ? "be" : "le");
                }
                if (cname[0]) out = w_array_push(out, a_pair("audio_codec_name", w_string(cname)));
                out = w_array_push(out, a_pair("audio_bits", w_int(bits)));
                out = w_array_push(out, a_pair("audio_float", (flags & kAudioFormatFlagIsFloat) ? W_TRUE : W_FALSE));
            }
            out = w_array_push(out, a_pair("audio_rate", asbd ? w_int((int64_t)llround(asbd->mSampleRate)) : W_NIL));
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
        } else if (!vt.count) {
            WMediaWav wav;
            char werr[256];
            if (w_media_wav_open(path.UTF8String, &wav, werr, sizeof werr) == 0) {
                char cname[32];
                if (wav.is_float) snprintf(cname, sizeof cname, "pcm_f%dle", wav.bits);
                else snprintf(cname, sizeof cname, "pcm_s%dle", wav.bits);
                WValue dur = w_array_new_empty();
                dur = w_array_push(dur, w_int(wav.frames));
                dur = w_array_push(dur, w_int(wav.rate));
                WValue zero = w_array_new_empty();
                zero = w_array_push(zero, w_int(0));
                zero = w_array_push(zero, w_int(wav.rate));
                out = w_array_push(out, a_pair("audio_tracks", w_int(1)));
                out = w_array_push(out, a_pair("audio_codec", w_string("lpcm")));
                out = w_array_push(out, a_pair("audio_codec_name", w_string(cname)));
                out = w_array_push(out, a_pair("audio_bits", w_int(wav.bits)));
                out = w_array_push(out, a_pair("audio_float", wav.is_float ? W_TRUE : W_FALSE));
                out = w_array_push(out, a_pair("audio_rate", w_int(wav.rate)));
                out = w_array_push(out, a_pair("audio_channels", w_int(wav.channels)));
                out = w_array_push(out, a_pair("audio_start", zero));
                out = w_array_push(out, a_pair("audio_duration", dur));
                out = w_array_push(out, a_pair("duration", dur));
                out = w_array_push(out, a_pair("audio_edits", w_int(0)));
                if (audiov > 1) out = w_array_push(out, a_pair("audio_decoded_frames", w_int(wav.frames)));
                w_media_wav_close(&wav);
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

/* ======================================================================
   Native Audio QC, Audio Prep, Video Anomalies, Quality (SSIM/MS-SSIM),
   and Multi-Frame Extraction (zero FFmpeg)
   ====================================================================== */

static void a_fit_geometry(int sw, int sh, int dw, int dh, int fit_code, double crop[4], int rect[4]) {
    crop[0] = 0; crop[1] = 0; crop[2] = sw; crop[3] = sh;
    rect[0] = 0; rect[1] = 0; rect[2] = dw; rect[3] = dh;
    if (fit_code == 1) { /* contain */
        int rw, rh;
        if ((int64_t)dw * sh <= (int64_t)dh * sw) {
            rw = dw;
            rh = (int)((((int64_t)dw * sh * 2 + (int64_t)sw * 2) / ((int64_t)sw * 4)) * 2);
        } else {
            rh = dh;
            rw = (int)((((int64_t)dh * sw * 2 + (int64_t)sh * 2) / ((int64_t)sh * 4)) * 2);
        }
        if (rw > dw) rw = dw;
        if (rh > dh) rh = dh;
        rect[0] = ((dw - rw) / 4) * 2;
        rect[1] = ((dh - rh) / 4) * 2;
        rect[2] = rw;
        rect[3] = rh;
    } else if (fit_code == 2) { /* cover */
        double cw, ch;
        if ((int64_t)dw * sh >= (int64_t)dh * sw) {
            cw = (double)sw;
            ch = ((double)sw * (double)dh) / (double)dw;
        } else {
            ch = (double)sh;
            cw = ((double)sh * (double)dw) / (double)dh;
        }
        crop[0] = ((double)sw - cw) * 0.5;
        crop[1] = ((double)sh - ch) * 0.5;
        crop[2] = cw;
        crop[3] = ch;
    }
}

typedef struct AAudioQC {
    int32_t sr, ch, sub, sub_pos;
    double  sb0, sb1, sb2, sa1, sa2;
    double  hb0, hb1, hb2, ha1, ha2;
    double  x1[8], x2[8], y1[8], y2[8], u1[8], u2[8], v1[8], v2[8];
    double  taps[48], tp_bound, tp_max;
    double  hist[8][24], hist_abs[8][24];
    int     hist_fill, hist_pos;
    double  sub_sum, total_kw_sum;
    double *zs;
    size_t  nb, zcap;
    double  energy[8], silence_thresh;
    int64_t frames, clipped, silence_run, longest_silence;
} AAudioQC;

static void a_audio_qc_init(AAudioQC *q, int32_t sr, int32_t ch, double silence_thresh) {
    memset(q, 0, sizeof *q);
    q->sr = sr;
    q->ch = ch;
    q->sub = sr >= 10 ? sr / 10 : 1;
    q->silence_thresh = silence_thresh;
    if (sr == 48000) {
        q->sb0 =  1.53512485958697; q->sb1 = -2.69169618940638; q->sb2 = 1.19839281085285;
        q->sa1 = -1.69065929318241; q->sa2 =  0.73248077421585;
        q->hb0 =  1.0;              q->hb1 = -2.0;              q->hb2 = 1.0;
        q->ha1 = -1.99004745483398; q->ha2 =  0.99007225036621;
    } else {
        const double pi = 3.14159265358979323846;
        double f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196;
        double K = tan(pi * f0 / (double)sr), Vh = pow(10.0, G / 20.0), Vb = pow(Vh, 0.4996667741545416);
        double a0 = 1.0 + K / Q + K * K;
        q->sb0 = (Vh + Vb * K / Q + K * K) / a0;
        q->sb1 = 2.0 * (K * K - Vh) / a0;
        q->sb2 = (Vh - Vb * K / Q + K * K) / a0;
        q->sa1 = 2.0 * (K * K - 1.0) / a0;
        q->sa2 = (1.0 - K / Q + K * K) / a0;
        double hf0 = 38.13547087602444, hQ = 0.5003270373238773;
        double hK = tan(pi * hf0 / (double)sr);
        double ha0 = 1.0 + hK / hQ + hK * hK;
        q->hb0 =  1.0 / ha0;
        q->hb1 = -2.0 / ha0;
        q->hb2 =  1.0 / ha0;
        q->ha1 = 2.0 * (hK * hK - 1.0) / ha0;
        q->ha2 = (1.0 - hK / hQ + hK * hK) / ha0;
    }
    const double pi = 3.14159265358979323846;
    double best = 0.0;
    for (int p = 0; p < 4; p++) {
        double s = 0.0;
        for (int k = 0; k < 12; k++) {
            double x = (double)(k - 5) - (double)p * 0.25;
            double v = x == 0.0 ? 1.0 : sin(pi * x) / (pi * x);
            double wv = 0.5 + 0.5 * cos(pi * x / 7.0);
            q->taps[p * 12 + k] = v * wv;
            s += v * wv;
        }
        double as = 0.0;
        for (int k = 0; k < 12; k++) {
            q->taps[p * 12 + k] /= s;
            as += fabs(q->taps[p * 12 + k]);
        }
        if (as > best) best = as;
    }
    q->tp_bound = best * (1.0 + 1e-9);
}

static inline void a_audio_qc_tp_step(AAudioQC *q, int c, int pos, double sample, double a0) {
    double *h = q->hist[c], *ha = q->hist_abs[c];
    h[pos] = h[pos + 12] = sample;
    ha[pos] = ha[pos + 12] = a0;
    if (a0 > q->tp_max) q->tp_max = a0;
    if (q->hist_fill < 12) return;
    const double * wa = ha + pos + 1;
    double wmax;
#if defined(__aarch64__)
    float64x2_t m0 = vmaxq_f64(vld1q_f64(wa), vld1q_f64(wa + 2));
    float64x2_t m1 = vmaxq_f64(vld1q_f64(wa + 4), vld1q_f64(wa + 6));
    float64x2_t m2 = vmaxq_f64(vld1q_f64(wa + 8), vld1q_f64(wa + 10));
    m0 = vmaxq_f64(m0, vmaxq_f64(m1, m2));
    wmax = vmaxvq_f64(m0);
#else
    wmax = 0.0;
    for (int k = 0; k < 12; k++) if (wa[k] > wmax) wmax = wa[k];
#endif
    if (wmax * q->tp_bound <= q->tp_max) return;
    const double *wh = h + pos + 1;
    for (int p = 1; p < 4; p++) {
        const double *t = q->taps + p * 12;
        double acc = 0.0;
        for (int k = 0; k < 12; k++) acc += wh[k] * t[k];
        double av = fabs(acc);
        if (av > q->tp_max) q->tp_max = av;
    }
}

static int a_audio_qc_feed(AAudioQC *q, const float *pcm, size_t nframes) {
    int ch = q->ch;
    for (size_t i = 0; i < nframes; i++) {
        double peak = 0.0, kw_frame = 0.0;
        if (q->hist_fill < 12) q->hist_fill++;
        int pos = q->hist_pos;
        q->hist_pos = pos == 11 ? 0 : pos + 1;
#if defined(__aarch64__)
        if (ch == 2) {
            float32x2_t f2 = vld1_f32(pcm + i * 2);
            float64x2_t x = vcvt_f64_f32(f2);
            if (!isfinite(vgetq_lane_f64(x, 0)) || !isfinite(vgetq_lane_f64(x, 1))) return -1;
            float64x2_t ax = vabsq_f64(x);
            double a0 = vgetq_lane_f64(ax, 0), a1 = vgetq_lane_f64(ax, 1);
            q->energy[0] += a0 * a0;
            q->energy[1] += a1 * a1;
            if (a0 >= 1.0 - 1.0 / 32768.0) q->clipped++;
            if (a1 >= 1.0 - 1.0 / 32768.0) q->clipped++;
            peak = a0 > a1 ? a0 : a1;
            float64x2_t x1 = vld1q_f64(q->x1), x2 = vld1q_f64(q->x2), y1 = vld1q_f64(q->y1), y2 = vld1q_f64(q->y2);
            float64x2_t y = vsubq_f64(
                vsubq_f64(vaddq_f64(vaddq_f64(vmulq_n_f64(x, q->sb0), vmulq_n_f64(x1, q->sb1)), vmulq_n_f64(x2, q->sb2)),
                          vmulq_n_f64(y1, q->sa1)),
                vmulq_n_f64(y2, q->sa2));
            vst1q_f64(q->x2, x1); vst1q_f64(q->x1, x); vst1q_f64(q->y2, y1); vst1q_f64(q->y1, y);
            float64x2_t u1 = vld1q_f64(q->u1), u2 = vld1q_f64(q->u2), v1 = vld1q_f64(q->v1), v2 = vld1q_f64(q->v2);
            float64x2_t v = vsubq_f64(
                vsubq_f64(vaddq_f64(vaddq_f64(vmulq_n_f64(y, q->hb0), vmulq_n_f64(u1, q->hb1)), vmulq_n_f64(u2, q->hb2)),
                          vmulq_n_f64(v1, q->ha1)),
                vmulq_n_f64(v2, q->ha2));
            vst1q_f64(q->u2, u1); vst1q_f64(q->u1, y); vst1q_f64(q->v2, v1); vst1q_f64(q->v1, v);
            float64x2_t vsq = vmulq_f64(v, v);
            kw_frame = vgetq_lane_f64(vsq, 0) + vgetq_lane_f64(vsq, 1);
            a_audio_qc_tp_step(q, 0, pos, vgetq_lane_f64(x, 0), a0);
            a_audio_qc_tp_step(q, 1, pos, vgetq_lane_f64(x, 1), a1);
        } else
#endif
        for (int c = 0; c < ch; c++) {
            double x = (double)pcm[i * (size_t)ch + (size_t)c];
            if (!isfinite(x)) return -1;
            double ax = fabs(x);
            q->energy[c] += x * x;
            if (ax >= 1.0 - 1.0 / 32768.0) q->clipped++;
            if (ax > peak) peak = ax;
            double y = q->sb0 * x + q->sb1 * q->x1[c] + q->sb2 * q->x2[c] - q->sa1 * q->y1[c] - q->sa2 * q->y2[c];
            q->x2[c] = q->x1[c]; q->x1[c] = x; q->y2[c] = q->y1[c]; q->y1[c] = y;
            double v = q->hb0 * y + q->hb1 * q->u1[c] + q->hb2 * q->u2[c] - q->ha1 * q->v1[c] - q->ha2 * q->v2[c];
            q->u2[c] = q->u1[c]; q->u1[c] = y; q->v2[c] = q->v1[c]; q->v1[c] = v;
            double g = (ch > 3 && (c == 3 || c == 4)) ? 1.41 : 1.0;
            if (ch > 3 && c == 3 && ch >= 6) g = 0.0; /* LFE excluded in 5.1+ */
            if (ch >= 6 && (c == 4 || c == 5)) g = 1.41;
            kw_frame += g * v * v;
            a_audio_qc_tp_step(q, c, pos, x, ax);
        }
        q->frames++;
        if (peak < q->silence_thresh) {
            q->silence_run++;
            if (q->silence_run > q->longest_silence) q->longest_silence = q->silence_run;
        } else {
            q->silence_run = 0;
        }
        q->sub_sum += kw_frame;
        q->total_kw_sum += kw_frame;
        if (++q->sub_pos == q->sub) {
            if (q->nb == q->zcap) {
                q->zcap = q->zcap ? q->zcap * 2 : 256;
                q->zs = realloc(q->zs, q->zcap * sizeof(double));
            }
            q->zs[q->nb++] = q->sub_sum / (double)q->sub;
            q->sub_sum = 0.0;
            q->sub_pos = 0;
        }
    }
    return 0;
}

/* w_media_audio_qc(path, silence_thresh_linear) -> [[key, val], ...] */
WValue w_media_audio_qc(WValue pathv, WValue threshv) {
    @autoreleasepool {
        NSString *path = a_nspath(pathv, "MediaVerify.audio_qc");
        double thresh = w_media_num(threshv, 0.001, "silence_threshold");
        AAudioQC q;
        WMediaWav wav;
        char werr[256];
        int used_wav = 0;
        if (w_media_wav_open(path.UTF8String, &wav, werr, sizeof werr) == 0) {
            if (wav.channels < 1 || wav.channels > 8) {
                w_media_wav_close(&wav);
                w_media_raise("MediaVerify.audio_qc: unsupported channel count %d", wav.channels);
            }
            a_audio_qc_init(&q, wav.rate, wav.channels, thresh);
            float *buf = malloc(8192 * (size_t)wav.channels * sizeof(float));
            int64_t pos = 0;
            int bad = 0;
            while (pos < wav.frames) {
                int64_t n = wav.frames - pos > 8192 ? 8192 : wav.frames - pos;
                w_media_wav_read_f32(&wav, pos, n, buf);
                if (a_audio_qc_feed(&q, buf, (size_t)n) != 0) { bad = 1; break; }
                pos += n;
            }
            free(buf);
            w_media_wav_close(&wav);
            if (bad) { free(q.zs); w_media_raise("MediaVerify.audio_qc: nonfinite decoded audio"); }
            used_wav = 1;
        }
        if (!used_wav) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
            NSArray *at = [asset tracksWithMediaType:AVMediaTypeAudio];
            if (!at.count) w_media_raise("MediaVerify.audio_qc: no audio track");
            AVAssetTrack *a = at[0];
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)a.formatDescriptions.firstObject;
            const AudioStreamBasicDescription *asbd = fd ? CMAudioFormatDescriptionGetStreamBasicDescription(fd) : NULL;
            int32_t sr = asbd ? (int32_t)llround(asbd->mSampleRate) : 48000;
            int32_t ch = asbd ? (int32_t)asbd->mChannelsPerFrame : 2;
            if (ch < 1 || ch > 8 || sr <= 0) w_media_raise("MediaVerify.audio_qc: invalid audio format (%d Hz x %d)", (int)sr, (int)ch);
            a_audio_qc_init(&q, sr, ch, thresh);
            NSError *err = nil;
            AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
            if (!r) { free(q.zs); w_media_raise("MediaVerify.audio_qc: %s", err.localizedDescription.UTF8String ?: "cannot read"); }
            NSDictionary *pcm = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32,
                                  AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
            AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:a outputSettings:pcm];
            [r addOutput:o];
            if (![r startReading]) {
                NSString *ed = r.error.localizedDescription;
                [o release]; [r release]; free(q.zs);
                w_media_raise("MediaVerify.audio_qc: %s", ed.UTF8String ?: "cannot start reading");
            }
            float *tmp = NULL;
            size_t tcap = 0;
            int bad = 0;
            CMSampleBufferRef sb;
            while ((sb = [o copyNextSampleBuffer])) {
                CMItemCount k = CMSampleBufferGetNumSamples(sb);
                CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
                if (bb && k > 0) {
                    size_t need = (size_t)k * (size_t)ch;
                    size_t bytes = CMBlockBufferGetDataLength(bb);
                    if (bytes < need * sizeof(float)) k = (CMItemCount)(bytes / ((size_t)ch * sizeof(float)));
                    if (k > 0) {
                        if ((size_t)k * (size_t)ch > tcap) {
                            tcap = (size_t)k * (size_t)ch;
                            tmp = realloc(tmp, tcap * sizeof(float));
                        }
                        CMBlockBufferCopyDataBytes(bb, 0, (size_t)k * (size_t)ch * sizeof(float), tmp);
                        if (a_audio_qc_feed(&q, tmp, (size_t)k) != 0) { bad = 1; CFRelease(sb); break; }
                    }
                }
                CFRelease(sb);
            }
            AVAssetReaderStatus rst = r.status;
            NSString *red = r.error.localizedDescription;
            free(tmp);
            [o release];
            [r release];
            if (bad) { free(q.zs); w_media_raise("MediaVerify.audio_qc: nonfinite decoded audio"); }
            if (rst == AVAssetReaderStatusFailed) { free(q.zs); w_media_raise("MediaVerify.audio_qc: %s", red.UTF8String ?: "decode failed"); }
        }
        /* Flush 6 zero frames through true-peak FIR so trailing inter-sample peaks are measured. */
        if (q.frames > 0) {
            for (int pad = 0; pad < 6; pad++) {
                if (q.hist_fill < 12) q.hist_fill++;
                int pos = q.hist_pos;
                q.hist_pos = pos == 11 ? 0 : pos + 1;
                for (int c = 0; c < q.ch; c++) a_audio_qc_tp_step(&q, c, pos, 0.0, 0.0);
            }
        }
        double lufs = -INFINITY;
        if (q.nb >= 4) {
            double sum = 0.0;
            size_t cnt = 0;
            for (size_t b = 0; b + 3 < q.nb; b++) {
                double z = (q.zs[b] + q.zs[b + 1] + q.zs[b + 2] + q.zs[b + 3]) * 0.25;
                double l = -0.691 + 10.0 * log10(z + 1e-20);
                if (l > -70.0) { sum += z; cnt++; }
            }
            if (cnt > 0) {
                double rel = -0.691 + 10.0 * log10(sum / (double)cnt) - 10.0;
                sum = 0.0; cnt = 0;
                for (size_t b = 0; b + 3 < q.nb; b++) {
                    double z = (q.zs[b] + q.zs[b + 1] + q.zs[b + 2] + q.zs[b + 3]) * 0.25;
                    double l = -0.691 + 10.0 * log10(z + 1e-20);
                    if (l > -70.0 && l > rel) { sum += z; cnt++; }
                }
                if (cnt > 0 && sum > 0.0) lufs = -0.691 + 10.0 * log10(sum / (double)cnt);
            }
        } else if (q.frames > 0) {
            double z = q.total_kw_sum / (double)q.frames;
            double l = -0.691 + 10.0 * log10(z + 1e-20);
            if (l > -70.0 && z > 0.0) lufs = -0.691 + 10.0 * log10(z);
        }
        free(q.zs);
        double dbtp = q.tp_max > 0.0 ? 20.0 * log10(q.tp_max) : -INFINITY;
        WValue energy = w_array_new_empty();
        for (int c = 0; c < q.ch; c++) energy = w_array_push(energy, w_float(q.energy[c]));
        WValue out = w_array_new_empty();
        out = w_array_push(out, a_pair("integrated_lufs", isfinite(lufs) ? w_float(lufs) : W_NIL));
        out = w_array_push(out, a_pair("true_peak_dbtp", isfinite(dbtp) ? w_float(dbtp) : W_NIL));
        out = w_array_push(out, a_pair("clipped_samples", w_int(q.clipped)));
        out = w_array_push(out, a_pair("longest_silence_frames", w_int(q.longest_silence)));
        out = w_array_push(out, a_pair("decoded_frames", w_int(q.frames)));
        out = w_array_push(out, a_pair("sample_rate", w_int(q.sr)));
        out = w_array_push(out, a_pair("channels", w_int(q.ch)));
        out = w_array_push(out, a_pair("energy", energy));
        return out;
    }
}

static void a_le16_put(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void a_le32_put(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static void a_le64_put(uint8_t *p, uint64_t v) { a_le32_put(p, (uint32_t)v); a_le32_put(p + 4, (uint32_t)(v >> 32)); }

/* Write a 44-byte RIFF header (rf64 == 0) or an 80-byte RF64 + ds64 header (rf64 == 1). */
static size_t a_wav24_header(uint8_t hdr[80], int rf64, int64_t frames, int32_t sr, int32_t ch) {
    uint64_t data_bytes = (uint64_t)frames * (uint64_t)ch * 3ULL;
    memset(hdr, 0, 80);
    if (!rf64) {
        memcpy(hdr + 0, "RIFF", 4);
        a_le32_put(hdr + 4, (uint32_t)(36ULL + data_bytes));
        memcpy(hdr + 8, "WAVEfmt ", 8);
        a_le32_put(hdr + 16, 16);
        a_le16_put(hdr + 20, 1);
        a_le16_put(hdr + 22, (uint16_t)ch);
        a_le32_put(hdr + 24, (uint32_t)sr);
        a_le32_put(hdr + 28, (uint32_t)(sr * ch * 3));
        a_le16_put(hdr + 32, (uint16_t)(ch * 3));
        a_le16_put(hdr + 34, 24);
        memcpy(hdr + 36, "data", 4);
        a_le32_put(hdr + 40, (uint32_t)data_bytes);
        return 44;
    }
    uint64_t riff_bytes = 72ULL + data_bytes;
    memcpy(hdr + 0, "RF64", 4);
    a_le32_put(hdr + 4, 0xFFFFFFFFu);
    memcpy(hdr + 8, "WAVEds64", 8);
    a_le32_put(hdr + 16, 28);
    a_le64_put(hdr + 20, riff_bytes);
    a_le64_put(hdr + 28, data_bytes);
    a_le64_put(hdr + 36, (uint64_t)frames);
    a_le32_put(hdr + 44, 0);
    memcpy(hdr + 48, "fmt ", 4);
    a_le32_put(hdr + 52, 16);
    a_le16_put(hdr + 56, 1);
    a_le16_put(hdr + 58, (uint16_t)ch);
    a_le32_put(hdr + 60, (uint32_t)sr);
    a_le32_put(hdr + 64, (uint32_t)(sr * ch * 3));
    a_le16_put(hdr + 68, (uint16_t)(ch * 3));
    a_le16_put(hdr + 70, 24);
    memcpy(hdr + 72, "data", 4);
    a_le32_put(hdr + 76, 0xFFFFFFFFu);
    return 80;
}

/* w_media_audio_prepare(src_path, dst_wav_path, [sample_rate, channels, exact_samples]) -> [frames, sr, ch] */
WValue w_media_audio_prepare(WValue srcv, WValue dstv, WValue optv) {
    @autoreleasepool {
        NSString *src = a_nspath(srcv, "MediaVerify.prepare_audio");
        char dst[4096], tmp[4200];
        if (!w_media_str(dstv, dst, sizeof dst) || !dst[0]) w_media_raise("MediaVerify.prepare_audio: dst must be a path");
        int32_t sr = (int32_t)w_media_num(m_avf_arr(optv, 0), 48000, "sample_rate");
        int32_t ch = (int32_t)w_media_num(m_avf_arr(optv, 1), 2, "channels");
        int64_t exact = (int64_t)w_media_num(m_avf_arr(optv, 2), 0, "samples");
        if (sr < 8000 || sr > 192000 || ch < 1 || ch > 8)
            w_media_raise("MediaVerify.prepare_audio: invalid target format (%d Hz x %d)", (int)sr, (int)ch);
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:src] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        NSArray *at = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (!at.count) w_media_raise("MediaVerify.prepare_audio: %s has no audio track", src.UTF8String);
        AVAssetTrack *a = at[0];
        CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)a.formatDescriptions.firstObject;
        const AudioStreamBasicDescription *asbd = fd ? CMAudioFormatDescriptionGetStreamBasicDescription(fd) : NULL;
        int32_t src_sr = asbd ? (int32_t)llround(asbd->mSampleRate) : 0;
        int32_t src_ch = asbd ? (int32_t)asbd->mChannelsPerFrame : 0;
        NSError *err = nil;
        AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
        if (!r) w_media_raise("MediaVerify.prepare_audio: %s", err.localizedDescription.UTF8String ?: "cannot read");
        NSDictionary *pcm = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(sr), AVNumberOfChannelsKey: @(ch),
                              AVLinearPCMBitDepthKey: @32, AVLinearPCMIsFloatKey: @YES,
                              AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
        AVAssetReaderOutput *o = nil;
        if (src_sr == sr && src_ch == ch) {
            NSDictionary *direct = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32,
                                     AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
            o = [[AVAssetReaderTrackOutput alloc] initWithTrack:a outputSettings:direct];
        } else {
            o = [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:@[a] audioSettings:pcm];
        }
        o.alwaysCopiesSampleData = NO;
        [r addOutput:o];
        if (![r startReading]) {
            NSString *ed = r.error.localizedDescription;
            [o release]; [r release];
            w_media_raise("MediaVerify.prepare_audio: %s", ed.UTF8String ?: "cannot start reading");
        }
        double est_dur = CMTimeGetSeconds(asset.duration);
        uint64_t est_frames = exact > 0 ? (uint64_t)exact : (est_dur > 0 ? (uint64_t)(est_dur * sr + 1024) : 0);
        int rf64 = (est_frames * (uint64_t)ch * 3ULL) >= 0xFFFFFF00ULL;
        static _Atomic uint32_t s_dec_seq = 0;
        snprintf(tmp, sizeof tmp, "%s.tmp%d_%u", dst, (int)getpid(),
                 atomic_fetch_add_explicit(&s_dec_seq, 1u, memory_order_relaxed));
        FILE *f = fopen(tmp, "wb");
        if (!f) {
            [r cancelReading]; [o release]; [r release];
            w_media_raise("MediaVerify.prepare_audio: cannot write %s: %s", tmp, strerror(errno));
        }
        uint8_t hdr[80];
        size_t hlen = a_wav24_header(hdr, rf64, exact > 0 ? exact : 0, sr, ch);
        int wok = fwrite(hdr, 1, hlen, f) == hlen;
        float *inbuf = NULL;
        uint8_t *outbuf = NULL;
        size_t cap_frames = 0;
        int64_t written = 0;
        CMSampleBufferRef sb;
        while (wok && (exact <= 0 || written < exact) && (sb = [o copyNextSampleBuffer])) {
            CMItemCount k = CMSampleBufferGetNumSamples(sb);
            CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
            if (bb && k > 0) {
                size_t bytes = CMBlockBufferGetDataLength(bb);
                size_t maxf = bytes / ((size_t)ch * sizeof(float));
                if ((size_t)k > maxf) k = (CMItemCount)maxf;
                if (exact > 0 && written + k > exact) k = (CMItemCount)(exact - written);
                if (k > 0) {
                    if ((size_t)k > cap_frames) {
                        cap_frames = (size_t)k;
                        inbuf = realloc(inbuf, cap_frames * (size_t)ch * sizeof(float));
                        outbuf = realloc(outbuf, cap_frames * (size_t)ch * 3);
                    }
                    CMBlockBufferCopyDataBytes(bb, 0, (size_t)k * (size_t)ch * sizeof(float), inbuf);
                    size_t nsamp = (size_t)k * (size_t)ch;
                    for (size_t i = 0; i < nsamp; i++) {
                        double x = (double)inbuf[i];
                        if (!isfinite(x)) x = 0.0;
                        if (x > 8388607.0 / 8388608.0) x = 8388607.0 / 8388608.0;
                        else if (x < -1.0) x = -1.0;
                        int32_t v = (int32_t)llround(x * 8388608.0);
                        outbuf[3 * i + 0] = (uint8_t)(v & 0xFF);
                        outbuf[3 * i + 1] = (uint8_t)((v >> 8) & 0xFF);
                        outbuf[3 * i + 2] = (uint8_t)((v >> 16) & 0xFF);
                    }
                    size_t wbytes = nsamp * 3;
                    wok = fwrite(outbuf, 1, wbytes, f) == wbytes;
                    written += k;
                }
            }
            CFRelease(sb);
        }
        AVAssetReaderStatus rst = r.status;
        NSString *red = r.error.localizedDescription;
        if (exact > 0 && written == exact && rst == AVAssetReaderStatusReading) [r cancelReading];
        free(inbuf);
        free(outbuf);
        [o release];
        [r release];
        if (rst == AVAssetReaderStatusFailed) {
            fclose(f); unlink(tmp);
            w_media_raise("MediaVerify.prepare_audio: %s", red.UTF8String ?: "audio decode failed");
        }
        if (wok && exact > 0 && written < exact) {
            uint8_t zeros[24576];
            memset(zeros, 0, sizeof zeros);
            size_t zcap = sizeof(zeros) / ((size_t)ch * 3);
            while (wok && written < exact) {
                int64_t n = exact - written > (int64_t)zcap ? (int64_t)zcap : exact - written;
                size_t nb = (size_t)n * (size_t)ch * 3;
                wok = fwrite(zeros, 1, nb, f) == nb;
                written += n;
            }
        }
        uint64_t total_data = (uint64_t)written * (uint64_t)ch * 3ULL;
        if (wok && !rf64 && total_data >= 0xFFFFFF00ULL) {
            fclose(f); unlink(tmp);
            w_media_raise("MediaVerify.prepare_audio: output exceeded 4 GiB without RF64 reservation");
        }
        if (wok) {
            a_wav24_header(hdr, rf64, written, sr, ch);
            wok = fseeko(f, 0, SEEK_SET) == 0 && fwrite(hdr, 1, hlen, f) == hlen && fflush(f) == 0 && fsync(fileno(f)) == 0;
        }
        wok = (fclose(f) == 0) && wok;
        if (!wok || rename(tmp, dst) != 0) {
            unlink(tmp);
            w_media_raise("MediaVerify.prepare_audio: writing %s failed: %s", dst, strerror(errno));
        }
        WValue res = w_array_new_empty();
        res = w_array_push(res, w_int(written));
        res = w_array_push(res, w_int(sr));
        res = w_array_push(res, w_int(ch));
        return res;
    }
}

static ADec *a_open_any_source_scaled(WValue srcv, int32_t num, int32_t den, OSType pix, int64_t start, int scale_max_w, const char *what) {
    char path[4096], err[512];
    ADec *d = NULL;
    if (w_is_array(srcv)) {
        int n = 0;
        char **segs = a_paths(srcv, &n);
        d = a_dec_open_ex(NULL, segs, n, num, den, pix, start, 30000, 16, scale_max_w, err, sizeof err);
        a_paths_free(segs, n);
    } else {
        if (!w_media_str(srcv, path, sizeof path) || !path[0]) w_media_raise("%s: source must be a path or segment array", what);
        if (access(path, R_OK) != 0) w_media_raise("%s: cannot read %s: %s", what, path, strerror(errno));
        d = a_dec_open_ex(path, NULL, 0, num, den, pix, start, 30000, 16, scale_max_w, err, sizeof err);
    }
    if (!d) w_media_raise("%s: %s", what, err);
    return d;
}

static ADec *a_open_any_source(WValue srcv, int32_t num, int32_t den, OSType pix, int64_t start, const char *what) {
    return a_open_any_source_scaled(srcv, num, den, pix, start, 0, what);
}

typedef struct ALumaDownCtx {
    const uint8_t *yp;
    size_t         ys;
    int            sw, sh, dw, dh, ten;
    const int     *x_lo, *x_hi;
    float         *dst;
} ALumaDownCtx;

static void a_downsample_luma_band(void *ctxp, size_t bi) {
    ALumaDownCtx *c = ctxp;
    int dy0 = (int)((int64_t)c->dh * (int64_t)bi / 4);
    int dy1 = (int)((int64_t)c->dh * (int64_t)(bi + 1) / 4);
    uint32_t acc[320];
    for (int dy = dy0; dy < dy1; dy++) {
        int y0 = (int)((int64_t)dy * c->sh / c->dh), y1 = (int)((int64_t)(dy + 1) * c->sh / c->dh);
        if (y1 <= y0) y1 = y0 + 1;
        int hcnt = y1 - y0;
        memset(acc, 0, (size_t)c->dw * sizeof(uint32_t));
        if (c->ten) {
            for (int y = y0; y < y1; y++) {
                const uint16_t *row = (const uint16_t *)(const void *)(c->yp + (size_t)y * c->ys);
                for (int dx = 0; dx < c->dw; dx++) {
                    int x0 = c->x_lo[dx], x1 = c->x_hi[dx];
                    uint32_t s = 0;
                    for (int x = x0; x < x1; x++) s += (uint32_t)(row[x] >> 6);
                    acc[dx] += s;
                }
            }
            for (int dx = 0; dx < c->dw; dx++) {
                float cnt = (float)(hcnt * (c->x_hi[dx] - c->x_lo[dx]));
                float yn = ((float)acc[dx] / cnt - 64.0f) * (1.0f / 876.0f);
                c->dst[dy * c->dw + dx] = yn < 0.0f ? 0.0f : (yn > 1.0f ? 1.0f : yn);
            }
        } else {
            for (int y = y0; y < y1; y++) {
                const uint8_t *row = c->yp + (size_t)y * c->ys;
                for (int dx = 0; dx < c->dw; dx++) {
                    int x0 = c->x_lo[dx], x1 = c->x_hi[dx];
                    uint32_t s = 0;
                    for (int x = x0; x < x1; x++) s += (uint32_t)row[x];
                    acc[dx] += s;
                }
            }
            for (int dx = 0; dx < c->dw; dx++) {
                float cnt = (float)(hcnt * (c->x_hi[dx] - c->x_lo[dx]));
                float yn = ((float)acc[dx] / cnt - 16.0f) * (1.0f / 219.0f);
                c->dst[dy * c->dw + dx] = yn < 0.0f ? 0.0f : (yn > 1.0f ? 1.0f : yn);
            }
        }
    }
}

/* Downsample luma Y' of pb into dst[dw * dh] in limited-range [0, 1] units (dw <= 320). */
static void a_downsample_luma_tv(CVPixelBufferRef pb, int dw, int dh, const int *unused_lo, const int *unused_hi, float *dst) {
    (void)unused_lo; (void)unused_hi;
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    int sw = (int)CVPixelBufferGetWidth(pb), sh = (int)CVPixelBufferGetHeight(pb);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    const uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    OSType fmt = CVPixelBufferGetPixelFormatType(pb);
    int ten = fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    if (sw == dw && sh == dh && !ten) {
        const float sc = 1.0f / 219.0f;
        for (int y = 0; y < dh; y++) {
            const uint8_t *row = yp + (size_t)y * ys;
            float *out = dst + (size_t)y * (size_t)dw;
            int x = 0;
#if defined(__aarch64__)
            float32x4_t v16 = vdupq_n_f32(16.0f), vsc = vdupq_n_f32(sc), v0 = vdupq_n_f32(0.0f), v1 = vdupq_n_f32(1.0f);
            for (; x + 8 <= dw; x += 8) {
                uint16x8_t u16 = vmovl_u8(vld1_u8(row + x));
                float32x4_t f0 = vmulq_f32(vsubq_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(u16))), v16), vsc);
                float32x4_t f1 = vmulq_f32(vsubq_f32(vcvtq_f32_u32(vmovl_u16(vget_high_u16(u16))), v16), vsc);
                vst1q_f32(out + x, vminq_f32(vmaxq_f32(f0, v0), v1));
                vst1q_f32(out + x + 4, vminq_f32(vmaxq_f32(f1, v0), v1));
            }
#endif
            for (; x < dw; x++) {
                float yn = ((float)row[x] - 16.0f) * sc;
                out[x] = yn < 0.0f ? 0.0f : (yn > 1.0f ? 1.0f : yn);
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        return;
    }
    int x_lo[320], x_hi[320];
    for (int dx = 0; dx < dw; dx++) {
        int x0 = (int)((int64_t)dx * sw / dw), x1 = (int)((int64_t)(dx + 1) * sw / dw);
        if (x1 <= x0) x1 = x0 + 1;
        x_lo[dx] = x0;
        x_hi[dx] = x1;
    }
    ALumaDownCtx ctx = {yp, ys, sw, sh, dw, dh, ten, x_lo, x_hi, dst};
    if ((int64_t)sw * sh >= 131072 && dh >= 8)
        dispatch_apply_f(4, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_downsample_luma_band);
    else
        for (size_t b = 0; b < 4; b++) a_downsample_luma_band(&ctx, b);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

static WValue a_anom_event(const char *kind, double s0, double s1) {
    WValue e = w_array_new_empty();
    e = w_array_push(e, w_string(kind));
    e = w_array_push(e, w_float(s0));
    e = w_array_push(e, w_float(s1));
    return e;
}

/* w_media_anomalies(src, [black_min, freeze_min, noise, pix_th, rate_num, rate_den]) -> [frames, events] */
WValue w_media_anomalies(WValue srcv, WValue optv) {
    @autoreleasepool {
        double black_min = w_media_num(m_avf_arr(optv, 0), 1.0, "black_min");
        double freeze_min = w_media_num(m_avf_arr(optv, 1), 3.0, "freeze_min");
        double noise = w_media_num(m_avf_arr(optv, 2), 0.001, "noise");
        double pix_th = w_media_num(m_avf_arr(optv, 3), 0.10, "pix_th");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 4), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(optv, 5), 0, "rate");
        ADec *d = a_open_any_source_scaled(srcv, num, den, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, 0, 320, "MediaVerify.anomalies");
        double dt = (double)d->den / (double)d->num;
        int dw = d->w < 320 ? d->w : 320;
        int dh = (int)(((int64_t)d->h * dw / (d->w ? d->w : 1)) & ~1LL);
        if (dh < 2) dh = 2;
        int npix = dw * dh;
        int x_lo[320], x_hi[320];
        for (int dx = 0; dx < dw; dx++) {
            int x0 = (int)((int64_t)dx * d->w / dw), x1 = (int)((int64_t)(dx + 1) * d->w / dw);
            if (x1 <= x0) x1 = x0 + 1;
            x_lo[dx] = x0;
            x_hi[dx] = x1;
        }
        int black_req = (int)ceil(0.98 * (double)npix);
        float *cur = malloc((size_t)npix * sizeof(float));
        float *ref = malloc((size_t)npix * sizeof(float));
        WValue events = w_array_new_empty();
        int64_t n = 0, black_start = -1, ref_frame = 0;
        int frozen = 0;
        char err[512];
        for (;;) {
            CVPixelBufferRef pb = NULL;
            int64_t frame = 0;
            int r = a_dec_next(d, &pb, &frame, err, sizeof err);
            if (r < 0) {
                free(cur); free(ref); a_dec_free(d);
                w_media_raise("MediaVerify.anomalies: %s", err);
            }
            if (r == 0) break;
            a_downsample_luma_tv(pb, dw, dh, x_lo, x_hi, cur);
            CVBufferRelease(pb);
            int bcnt = 0;
            float pth = (float)pix_th;
            for (int i = 0; i < npix; i++) if (cur[i] <= pth) bcnt++;
            if (bcnt >= black_req) {
                if (black_start < 0) black_start = n;
            } else if (black_start >= 0) {
                double s0 = (double)black_start * dt, s1 = (double)n * dt;
                if (s1 - s0 >= black_min) events = w_array_push(events, a_anom_event("black", s0, s1));
                black_start = -1;
            }
            if (n == 0) {
                memcpy(ref, cur, (size_t)npix * sizeof(float));
                ref_frame = 0;
                frozen = 0;
            } else {
                double diff = 0.0;
                for (int i = 0; i < npix; i++) diff += (double)fabsf(cur[i] - ref[i]);
                double mad = diff / (double)npix;
                if (mad < noise) {
                    frozen = 1;
                } else {
                    if (frozen) {
                        double s0 = (double)ref_frame * dt, s1 = (double)n * dt;
                        if (s1 - s0 >= freeze_min) events = w_array_push(events, a_anom_event("freeze", s0, s1));
                    }
                    memcpy(ref, cur, (size_t)npix * sizeof(float));
                    ref_frame = n;
                    frozen = 0;
                }
            }
            n++;
        }
        if (black_start >= 0) {
            double s0 = (double)black_start * dt, s1 = (double)n * dt;
            if (s1 - s0 >= black_min) events = w_array_push(events, a_anom_event("black", s0, s1));
        }
        if (frozen) {
            double s0 = (double)ref_frame * dt, s1 = (double)n * dt;
            if (s1 - s0 >= freeze_min) events = w_array_push(events, a_anom_event("freeze", s0, s1));
        }
        free(cur);
        free(ref);
        a_dec_free(d);
        WValue out = w_array_new_empty();
        out = w_array_push(out, w_int(n));
        out = w_array_push(out, events);
        return out;
    }
}

/* 11-tap normalized 1D Gaussian (sigma = 1.5) from Wang et al. SSIM / MS-SSIM. */
static const float a_ssim_g11[11] = {
    0.0010283801f, 0.0075987582f, 0.0360007733f, 0.1093606874f, 0.2130055279f,
    0.2660117149f, 0.2130055279f, 0.1093606874f, 0.0360007733f, 0.0075987582f, 0.0010283801f
};

typedef struct ASSIMCtx {
    const float *a, *b;
    int          w, h;
    double       part_l[8], part_cs[8], part_ssim[8];
} ASSIMCtx;

static inline void a_ssim_hrow(const float *ra, const float *rb, int w,
                               float *ta, float *tb, float *taa, float *tbb, float *tab) {
    const float g0 = a_ssim_g11[5], g1 = a_ssim_g11[6], g2 = a_ssim_g11[7],
                g3 = a_ssim_g11[8], g4 = a_ssim_g11[9], g5 = a_ssim_g11[10];
    int x = 0;
    int left_end = w < 5 ? w : 5;
    for (; x < left_end; x++) {
        float sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
        for (int k = -5; k <= 5; k++) {
            int xx = x + k;
            if (xx < 0) xx = 0;
            else if (xx >= w) xx = w - 1;
            float g = a_ssim_g11[k + 5], va = ra[xx], vb = rb[xx];
            sa += g * va; sb += g * vb;
            saa += g * va * va; sbb += g * vb * vb; sab += g * va * vb;
        }
        ta[x] = sa; tb[x] = sb; taa[x] = saa; tbb[x] = sbb; tab[x] = sab;
    }
    int right_start = w - 5;
    if (right_start < x) right_start = x;
#if defined(__aarch64__)
    for (; x + 4 <= right_start; x += 4) {
        float32x4_t va0 = vld1q_f32(ra + x), vb0 = vld1q_f32(rb + x);
        float32x4_t sa = vmulq_n_f32(va0, g0), sb = vmulq_n_f32(vb0, g0);
        float32x4_t saa = vmulq_n_f32(vmulq_f32(va0, va0), g0);
        float32x4_t sbb = vmulq_n_f32(vmulq_f32(vb0, vb0), g0);
        float32x4_t sab = vmulq_n_f32(vmulq_f32(va0, vb0), g0);
#define A_SSIM_HP(k, gk) do { \
            float32x4_t vam = vld1q_f32(ra + x - (k)), vap = vld1q_f32(ra + x + (k)); \
            float32x4_t vbm = vld1q_f32(rb + x - (k)), vbp = vld1q_f32(rb + x + (k)); \
            sa = vfmaq_n_f32(sa, vaddq_f32(vam, vap), (gk)); \
            sb = vfmaq_n_f32(sb, vaddq_f32(vbm, vbp), (gk)); \
            saa = vfmaq_n_f32(saa, vfmaq_f32(vmulq_f32(vam, vam), vap, vap), (gk)); \
            sbb = vfmaq_n_f32(sbb, vfmaq_f32(vmulq_f32(vbm, vbm), vbp, vbp), (gk)); \
            sab = vfmaq_n_f32(sab, vfmaq_f32(vmulq_f32(vam, vbm), vap, vbp), (gk)); \
        } while (0)
        A_SSIM_HP(1, g1);
        A_SSIM_HP(2, g2);
        A_SSIM_HP(3, g3);
        A_SSIM_HP(4, g4);
        A_SSIM_HP(5, g5);
#undef A_SSIM_HP
        vst1q_f32(ta + x, sa);
        vst1q_f32(tb + x, sb);
        vst1q_f32(taa + x, saa);
        vst1q_f32(tbb + x, sbb);
        vst1q_f32(tab + x, sab);
    }
#endif
    for (; x < right_start; x++) {
        float va0 = ra[x], vb0 = rb[x];
        float sa = g0 * va0, sb = g0 * vb0;
        float saa = g0 * va0 * va0, sbb = g0 * vb0 * vb0, sab = g0 * va0 * vb0;
        for (int k = 1; k <= 5; k++) {
            float g = a_ssim_g11[5 + k];
            float vam = ra[x - k], vap = ra[x + k];
            float vbm = rb[x - k], vbp = rb[x + k];
            sa += g * (vam + vap);
            sb += g * (vbm + vbp);
            saa += g * (vam * vam + vap * vap);
            sbb += g * (vbm * vbm + vbp * vbp);
            sab += g * (vam * vbm + vap * vbp);
        }
        ta[x] = sa; tb[x] = sb; taa[x] = saa; tbb[x] = sbb; tab[x] = sab;
    }
    for (; x < w; x++) {
        float sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
        for (int k = -5; k <= 5; k++) {
            int xx = x + k;
            if (xx < 0) xx = 0;
            else if (xx >= w) xx = w - 1;
            float g = a_ssim_g11[k + 5], va = ra[xx], vb = rb[xx];
            sa += g * va; sb += g * vb;
            saa += g * va * va; sbb += g * vb * vb; sab += g * va * vb;
        }
        ta[x] = sa; tb[x] = sb; taa[x] = saa; tbb[x] = sbb; tab[x] = sab;
    }
}

/* Fused 16-row L1 ring-buffer horizontal + symmetric vertical SSIM band pass. */
static void a_ssim_band(void *ctxp, size_t bi) {
    ASSIMCtx *c = ctxp;
    int w = c->w, h = c->h;
    int y0 = (int)((int64_t)h * (int64_t)bi / 8), y1 = (int)((int64_t)h * (int64_t)(bi + 1) / 8);
    if (y0 >= y1) {
        c->part_l[bi] = c->part_cs[bi] = c->part_ssim[bi] = 0.0;
        return;
    }
    static _Thread_local float *tl_ring = NULL;
    static _Thread_local size_t tl_cap_w = 0;
    size_t rw = ((size_t)w + 3u) & ~(size_t)3u;
    if (rw > tl_cap_w) {
        free(tl_ring);
        tl_cap_w = rw < 2048 ? 2048 : rw;
        tl_ring = malloc(16 * 5 * tl_cap_w * sizeof(float));
    }
    size_t stride5 = 5 * rw;
    int slot_y[16];
    for (int i = 0; i < 16; i++) slot_y[i] = -1;
    const float g0 = a_ssim_g11[5], g1 = a_ssim_g11[6], g2 = a_ssim_g11[7],
                g3 = a_ssim_g11[8], g4 = a_ssim_g11[9], g5 = a_ssim_g11[10];
    const float C1 = 0.0001f, C2 = 0.0009f;
    double sum_l = 0.0, sum_cs = 0.0, sum_ssim = 0.0;
#if defined(__aarch64__)
    float64x2_t vsum_l = vdupq_n_f64(0.0), vsum_cs = vdupq_n_f64(0.0), vsum_ss = vdupq_n_f64(0.0);
    float32x4_t vc1 = vdupq_n_f32(C1), vc2 = vdupq_n_f32(C2), vzero = vdupq_n_f32(0.0f), vtwo = vdupq_n_f32(2.0f);
#endif
    for (int y = y0; y < y1; y++) {
        int rslot[11];
        for (int k = -5; k <= 5; k++) {
            int yy = y + k;
            if (yy < 0) yy = 0;
            else if (yy >= h) yy = h - 1;
            int sl = yy & 15;
            if (slot_y[sl] != yy) {
                float *base = tl_ring + (size_t)sl * stride5;
                a_ssim_hrow(c->a + (size_t)yy * (size_t)w, c->b + (size_t)yy * (size_t)w, w,
                            base, base + rw, base + 2 * rw, base + 3 * rw, base + 4 * rw);
                slot_y[sl] = yy;
            }
            rslot[k + 5] = sl;
        }
        const float *b5 = tl_ring + (size_t)rslot[5] * stride5;
        const float *bm1 = tl_ring + (size_t)rslot[4] * stride5, *bp1 = tl_ring + (size_t)rslot[6] * stride5;
        const float *bm2 = tl_ring + (size_t)rslot[3] * stride5, *bp2 = tl_ring + (size_t)rslot[7] * stride5;
        const float *bm3 = tl_ring + (size_t)rslot[2] * stride5, *bp3 = tl_ring + (size_t)rslot[8] * stride5;
        const float *bm4 = tl_ring + (size_t)rslot[1] * stride5, *bp4 = tl_ring + (size_t)rslot[9] * stride5;
        const float *bm5 = tl_ring + (size_t)rslot[0] * stride5, *bp5 = tl_ring + (size_t)rslot[10] * stride5;
        int x = 0;
#if defined(__aarch64__)
        for (; x + 4 <= w; x += 4) {
#define A_SSIM_VPLANE(off) ({ \
                float32x4_t acc = vmulq_n_f32(vld1q_f32(b5 + (off) + x), g0); \
                acc = vfmaq_n_f32(acc, vaddq_f32(vld1q_f32(bm1 + (off) + x), vld1q_f32(bp1 + (off) + x)), g1); \
                acc = vfmaq_n_f32(acc, vaddq_f32(vld1q_f32(bm2 + (off) + x), vld1q_f32(bp2 + (off) + x)), g2); \
                acc = vfmaq_n_f32(acc, vaddq_f32(vld1q_f32(bm3 + (off) + x), vld1q_f32(bp3 + (off) + x)), g3); \
                acc = vfmaq_n_f32(acc, vaddq_f32(vld1q_f32(bm4 + (off) + x), vld1q_f32(bp4 + (off) + x)), g4); \
                acc = vfmaq_n_f32(acc, vaddq_f32(vld1q_f32(bm5 + (off) + x), vld1q_f32(bp5 + (off) + x)), g5); \
                acc; \
            })
            float32x4_t mux = A_SSIM_VPLANE(0);
            float32x4_t muy = A_SSIM_VPLANE(rw);
            float32x4_t exx = A_SSIM_VPLANE(2 * rw);
            float32x4_t eyy = A_SSIM_VPLANE(3 * rw);
            float32x4_t exy = A_SSIM_VPLANE(4 * rw);
#undef A_SSIM_VPLANE
            float32x4_t mx2 = vmulq_f32(mux, mux), my2 = vmulq_f32(muy, muy), mxy = vmulq_f32(mux, muy);
            float32x4_t sx2 = vmaxq_f32(vsubq_f32(exx, mx2), vzero);
            float32x4_t sy2 = vmaxq_f32(vsubq_f32(eyy, my2), vzero);
            float32x4_t sxy = vsubq_f32(exy, mxy);
            float32x4_t vl = vdivq_f32(vfmaq_f32(vc1, mxy, vtwo), vaddq_f32(vaddq_f32(mx2, my2), vc1));
            float32x4_t vcs = vdivq_f32(vfmaq_f32(vc2, sxy, vtwo), vaddq_f32(vaddq_f32(sx2, sy2), vc2));
            float32x4_t vss = vmulq_f32(vl, vcs);
            vsum_l = vaddq_f64(vsum_l, vaddq_f64(vcvt_f64_f32(vget_low_f32(vl)), vcvt_high_f64_f32(vl)));
            vsum_cs = vaddq_f64(vsum_cs, vaddq_f64(vcvt_f64_f32(vget_low_f32(vcs)), vcvt_high_f64_f32(vcs)));
            vsum_ss = vaddq_f64(vsum_ss, vaddq_f64(vcvt_f64_f32(vget_low_f32(vss)), vcvt_high_f64_f32(vss)));
        }
#endif
        for (; x < w; x++) {
#define A_SSIM_VSCALAR(off) \
            (g0 * b5[(off) + x] + \
             g1 * (bm1[(off) + x] + bp1[(off) + x]) + \
             g2 * (bm2[(off) + x] + bp2[(off) + x]) + \
             g3 * (bm3[(off) + x] + bp3[(off) + x]) + \
             g4 * (bm4[(off) + x] + bp4[(off) + x]) + \
             g5 * (bm5[(off) + x] + bp5[(off) + x]))
            float mux = A_SSIM_VSCALAR(0);
            float muy = A_SSIM_VSCALAR(rw);
            float exx = A_SSIM_VSCALAR(2 * rw);
            float eyy = A_SSIM_VSCALAR(3 * rw);
            float exy = A_SSIM_VSCALAR(4 * rw);
#undef A_SSIM_VSCALAR
            float mx2 = mux * mux, my2 = muy * muy, mxy = mux * muy;
            float sx2 = exx - mx2, sy2 = eyy - my2, sxy = exy - mxy;
            if (sx2 < 0.0f) sx2 = 0.0f;
            if (sy2 < 0.0f) sy2 = 0.0f;
            float l = (2.0f * mxy + C1) / (mx2 + my2 + C1);
            float cs = (2.0f * sxy + C2) / (sx2 + sy2 + C2);
            sum_l += (double)l;
            sum_cs += (double)cs;
            sum_ssim += (double)(l * cs);
        }
    }
#if defined(__aarch64__)
    sum_l += vgetq_lane_f64(vsum_l, 0) + vgetq_lane_f64(vsum_l, 1);
    sum_cs += vgetq_lane_f64(vsum_cs, 0) + vgetq_lane_f64(vsum_cs, 1);
    sum_ssim += vgetq_lane_f64(vsum_ss, 0) + vgetq_lane_f64(vsum_ss, 1);
#endif
    c->part_l[bi] = sum_l;
    c->part_cs[bi] = sum_cs;
    c->part_ssim[bi] = sum_ssim;
}

static void a_ssim_scale(const float *a, const float *b, int w, int h, double *out_l, double *out_cs, double *out_ssim) {
    ASSIMCtx ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.a = a; ctx.b = b; ctx.w = w; ctx.h = h;
    if ((int64_t)w * h >= 8192) {
        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_apply_f(8, q, &ctx, a_ssim_band);
    } else {
        for (size_t i = 0; i < 8; i++) a_ssim_band(&ctx, i);
    }
    double sl = 0, scs = 0, ss = 0;
    for (int i = 0; i < 8; i++) { sl += ctx.part_l[i]; scs += ctx.part_cs[i]; ss += ctx.part_ssim[i]; }
    double inv = 1.0 / ((double)w * (double)h);
    *out_l = sl * inv;
    *out_cs = scs * inv;
    *out_ssim = ss * inv;
}

static void a_yplane_to_f32(const uint8_t *yp, size_t ys, int w, int h, int ten, float *dst) {
    if (ten) {
        const float inv = 1.0f / 1023.0f;
        for (int y = 0; y < h; y++) {
            const uint16_t *r = (const uint16_t *)(const void *)(yp + (size_t)y * ys);
            float *o = dst + (size_t)y * (size_t)w;
            int x = 0;
#if defined(__aarch64__)
            for (; x + 8 <= w; x += 8) {
                uint16x8_t v = vshrq_n_u16(vld1q_u16(r + x), 6);
                uint32x4_t lo = vmovl_u16(vget_low_u16(v)), hi = vmovl_u16(vget_high_u16(v));
                vst1q_f32(o + x, vmulq_n_f32(vcvtq_f32_u32(lo), inv));
                vst1q_f32(o + x + 4, vmulq_n_f32(vcvtq_f32_u32(hi), inv));
            }
#endif
            for (; x < w; x++) o[x] = (float)(r[x] >> 6) * inv;
        }
    } else {
        const float inv = 1.0f / 255.0f;
        for (int y = 0; y < h; y++) {
            const uint8_t *r = yp + (size_t)y * ys;
            float *o = dst + (size_t)y * (size_t)w;
            int x = 0;
#if defined(__aarch64__)
            for (; x + 8 <= w; x += 8) {
                uint16x8_t v = vmovl_u8(vld1_u8(r + x));
                uint32x4_t lo = vmovl_u16(vget_low_u16(v)), hi = vmovl_u16(vget_high_u16(v));
                vst1q_f32(o + x, vmulq_n_f32(vcvtq_f32_u32(lo), inv));
                vst1q_f32(o + x + 4, vmulq_n_f32(vcvtq_f32_u32(hi), inv));
            }
#endif
            for (; x < w; x++) o[x] = (float)r[x] * inv;
        }
    }
}

/* Compute MSE, SSIM, and 5-scale MS-SSIM for one frame without mutating ref_y. */
static void a_quality_frame_metrics(const float *ref_y, const float *cand_y,
                                    float *da, float *db, float *ea, float *eb,
                                    int w, int h, double *out_mse, double *out_ssim, double *out_ms) {
    static const double w_ms[5] = {0.0448, 0.2856, 0.3001, 0.2363, 0.1333};
    size_t npix = (size_t)w * (size_t)h;
    double mse = 0.0;
    size_t i = 0;
#if defined(__aarch64__)
    float64x2_t vmse = vdupq_n_f64(0.0);
    for (; i + 4 <= npix; i += 4) {
        float32x4_t d = vsubq_f32(vld1q_f32(ref_y + i), vld1q_f32(cand_y + i));
        float32x4_t d2 = vmulq_f32(d, d);
        vmse = vaddq_f64(vmse, vaddq_f64(vcvt_f64_f32(vget_low_f32(d2)), vcvt_high_f64_f32(d2)));
    }
    mse = vgetq_lane_f64(vmse, 0) + vgetq_lane_f64(vmse, 1);
#endif
    for (; i < npix; i++) {
        double d0 = (double)ref_y[i] - (double)cand_y[i];
        mse += d0 * d0;
    }
    *out_mse = mse / (double)npix;

    double l_s[5], cs_s[5], ssim0 = 0.0;
    int sw_cur = w, sh_cur = h, scales = 0;
    const float *ca = ref_y, *cb = cand_y;
    for (int s = 0; s < 5; s++) {
        double l_val = 0, cs_val = 0, ss_val = 0;
        a_ssim_scale(ca, cb, sw_cur, sh_cur, &l_val, &cs_val, &ss_val);
        if (s == 0) ssim0 = ss_val;
        l_s[s] = l_val < 1e-10 ? 1e-10 : l_val;
        cs_s[s] = cs_val < 1e-10 ? 1e-10 : cs_val;
        scales = s + 1;
        if (s == 4 || sw_cur < 4 || sh_cur < 4) break;
        int nw = sw_cur / 2, nh = sh_cur / 2;
        float *na = (s & 1) ? ea : da;
        float *nb = (s & 1) ? eb : db;
        for (int yy = 0; yy < nh; yy++) {
            const float *r0 = ca + (size_t)(2 * yy) * (size_t)sw_cur, *r1 = r0 + sw_cur;
            const float *q0 = cb + (size_t)(2 * yy) * (size_t)sw_cur, *q1 = q0 + sw_cur;
            float *oa = na + (size_t)yy * (size_t)nw, *ob = nb + (size_t)yy * (size_t)nw;
            int xx = 0;
#if defined(__aarch64__)
            for (; xx + 4 <= nw; xx += 4) {
                float32x4x2_t a0 = vld2q_f32(r0 + 2 * xx), a1 = vld2q_f32(r1 + 2 * xx);
                float32x4x2_t b0 = vld2q_f32(q0 + 2 * xx), b1 = vld2q_f32(q1 + 2 * xx);
                float32x4_t sa = vmulq_n_f32(vaddq_f32(vaddq_f32(a0.val[0], a0.val[1]), vaddq_f32(a1.val[0], a1.val[1])), 0.25f);
                float32x4_t sb = vmulq_n_f32(vaddq_f32(vaddq_f32(b0.val[0], b0.val[1]), vaddq_f32(b1.val[0], b1.val[1])), 0.25f);
                vst1q_f32(oa + xx, sa);
                vst1q_f32(ob + xx, sb);
            }
#endif
            for (; xx < nw; xx++) {
                oa[xx] = 0.25f * (r0[2 * xx] + r0[2 * xx + 1] + r1[2 * xx] + r1[2 * xx + 1]);
                ob[xx] = 0.25f * (q0[2 * xx] + q0[2 * xx + 1] + q1[2 * xx] + q1[2 * xx + 1]);
            }
        }
        ca = na; cb = nb; sw_cur = nw; sh_cur = nh;
    }
    double wsum = 0.0;
    for (int s = 0; s < scales; s++) wsum += w_ms[s];
    double ms = 1.0;
    for (int s = 0; s < scales - 1; s++) ms *= pow(cs_s[s], w_ms[s] / wsum);
    ms *= pow(l_s[scales - 1] * cs_s[scales - 1], w_ms[scales - 1] / wsum);
    *out_ssim = ssim0;
    *out_ms = ms;
}

/* w_media_quality(ref_src, cand_src, [ref_start, cand_start, max_frames, fit_code, rate_num, rate_den]) -> [[key, val], ...] */
WValue w_media_quality(WValue refv, WValue candv, WValue optv) {
    @autoreleasepool {
        int64_t ref_start = (int64_t)w_media_num(m_avf_arr(optv, 0), 0, "ref_start");
        int64_t cand_start = (int64_t)w_media_num(m_avf_arr(optv, 1), 0, "cand_start");
        int64_t max_frames = (int64_t)w_media_num(m_avf_arr(optv, 2), 0, "frames");
        int fit_code = (int)w_media_num(m_avf_arr(optv, 3), 0, "fit");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 4), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(optv, 5), 0, "rate");
        ADec *dr = a_open_any_source(refv, num, den, 0, ref_start, "MediaVerify.quality(reference)");
        ADec *dc = a_open_any_source(candv, num, den, 0, cand_start, "MediaVerify.quality(candidate)");
        int w = dc->w, h = dc->h;
        int need_scale = dr->w != w || dr->h != h || fit_code != 0;
        WMediaScale py;
        memset(&py, 0, sizeof py);
        uint16_t *scaled_y = NULL;
        size_t scaled_bytes = 0;
        char err[512];
        if (need_scale) {
            double crop[4]; int rect[4];
            a_fit_geometry(dr->w, dr->h, w, h, fit_code, crop, rect);
            uint8_t fy[4] = {16, 0, 0, 0};
            if (w_media_scale_plan(&py, 1, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3, dr->w, dr->h, w, h,
                                   crop, rect, 1, 1, 0.5, 0.5, 1, 1, 0.5, 0.5, fy, 10, err, sizeof err) != 0) {
                a_dec_free(dr); a_dec_free(dc);
                w_media_raise("MediaVerify.quality: %s", err);
            }
            py.in_bits = 10;
            py.vimage_ok = 0;
            scaled_bytes = ((size_t)w * (size_t)h * sizeof(uint16_t) + 16383u) & ~(size_t)16383u;
            if (posix_memalign((void **)&scaled_y, 16384, scaled_bytes) != 0) scaled_y = NULL;
            if (!scaled_y) {
                w_media_scale_free(&py); a_dec_free(dr); a_dec_free(dc);
                w_media_raise("MediaVerify.quality: out of memory");
            }
        }
        size_t npix = (size_t)w * (size_t)h;
        float *fa = malloc(npix * sizeof(float)), *fb = malloc(npix * sizeof(float));
        float *da = malloc((npix / 4 + 16) * sizeof(float)), *db = malloc((npix / 4 + 16) * sizeof(float));
        float *ea = malloc((npix / 4 + 16) * sizeof(float)), *eb = malloc((npix / 4 + 16) * sizeof(float));
        double sum_ssim = 0.0, min_ssim = 1.0, sum_ms = 0.0, min_ms = 1.0, sum_mse = 0.0;
        int64_t n = 0;
        while (max_frames <= 0 || n < max_frames) {
            CVPixelBufferRef pbr = NULL, pbc = NULL;
            int64_t fr = 0, fc = 0;
            int rr = a_dec_next(dr, &pbr, &fr, err, sizeof err);
            if (rr < 0) {
                free(fa); free(fb); free(da); free(db); free(ea); free(eb); free(scaled_y);
                if (need_scale) w_media_scale_free(&py);
                a_dec_free(dr); a_dec_free(dc);
                w_media_raise("MediaVerify.quality: %s", err);
            }
            int rc = a_dec_next(dc, &pbc, &fc, err, sizeof err);
            if (rc < 0) {
                if (pbr) CVBufferRelease(pbr);
                free(fa); free(fb); free(da); free(db); free(ea); free(eb); free(scaled_y);
                if (need_scale) w_media_scale_free(&py);
                a_dec_free(dr); a_dec_free(dc);
                w_media_raise("MediaVerify.quality: %s", err);
            }
            if (rr == 0 || rc == 0) {
                if (pbr) CVBufferRelease(pbr);
                if (pbc) CVBufferRelease(pbc);
                break;
            }
            CVPixelBufferLockBaseAddress(pbr, kCVPixelBufferLock_ReadOnly);
            CVPixelBufferLockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
            const uint8_t *ry = CVPixelBufferGetBaseAddressOfPlane(pbr, 0);
            size_t rys = CVPixelBufferGetBytesPerRowOfPlane(pbr, 0);
            int rten = CVPixelBufferGetPixelFormatType(pbr) != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            if (need_scale) {
                if (!rten) {
                    CVPixelBufferUnlockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
                    CVPixelBufferUnlockBaseAddress(pbr, kCVPixelBufferLock_ReadOnly);
                    CVBufferRelease(pbr); CVBufferRelease(pbc);
                    free(fa); free(fb); free(da); free(db); free(ea); free(eb); free(scaled_y);
                    w_media_scale_free(&py); a_dec_free(dr); a_dec_free(dc);
                    w_media_raise("MediaVerify.quality: expected 10-bit decoder plane");
                }
                if (w_media_scale_run(&py, W_MEDIA_BACKEND_AUTO, ry, rys, rys * CVPixelBufferGetHeightOfPlane(pbr, 0),
                                      (uint8_t *)scaled_y, (size_t)w * 2, (size_t)w * 2 * (size_t)h, err, sizeof err) < 0) {
                    CVPixelBufferUnlockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
                    CVPixelBufferUnlockBaseAddress(pbr, kCVPixelBufferLock_ReadOnly);
                    CVBufferRelease(pbr); CVBufferRelease(pbc);
                    free(fa); free(fb); free(da); free(db); free(ea); free(eb); free(scaled_y);
                    w_media_scale_free(&py); a_dec_free(dr); a_dec_free(dc);
                    w_media_raise("MediaVerify.quality: %s", err);
                }
                a_yplane_to_f32((const uint8_t *)scaled_y, (size_t)w * 2, w, h, 1, fa);
            } else {
                a_yplane_to_f32(ry, rys, w, h, rten, fa);
            }
            const uint8_t *cy = CVPixelBufferGetBaseAddressOfPlane(pbc, 0);
            size_t cys = CVPixelBufferGetBytesPerRowOfPlane(pbc, 0);
            int cten = CVPixelBufferGetPixelFormatType(pbc) != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            a_yplane_to_f32(cy, cys, w, h, cten, fb);
            CVPixelBufferUnlockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
            CVPixelBufferUnlockBaseAddress(pbr, kCVPixelBufferLock_ReadOnly);
            CVBufferRelease(pbr);
            CVBufferRelease(pbc);

            double mse = 0.0, ssim0 = 0.0, ms = 0.0;
            a_quality_frame_metrics(fa, fb, da, db, ea, eb, w, h, &mse, &ssim0, &ms);
            sum_mse += mse;
            sum_ssim += ssim0;
            if (ssim0 < min_ssim) min_ssim = ssim0;
            sum_ms += ms;
            if (ms < min_ms) min_ms = ms;
            n++;
        }
        free(fa); free(fb); free(da); free(db); free(ea); free(eb); free(scaled_y);
        if (need_scale) w_media_scale_free(&py);
        a_dec_free(dr);
        a_dec_free(dc);
        if (n <= 0) w_media_raise("MediaVerify.quality: zero overlapping frames decoded");
        double mean_mse = sum_mse / (double)n;
        double psnr = mean_mse <= 1e-12 ? 99.0 : -10.0 * log10(mean_mse);
        WValue out = w_array_new_empty();
        out = w_array_push(out, a_pair("frames", w_int(n)));
        out = w_array_push(out, a_pair("ssim", w_float(sum_ssim / (double)n)));
        out = w_array_push(out, a_pair("min_ssim", w_float(min_ssim)));
        out = w_array_push(out, a_pair("ms_ssim", w_float(sum_ms / (double)n)));
        out = w_array_push(out, a_pair("min_ms_ssim", w_float(min_ms)));
        out = w_array_push(out, a_pair("psnr_y", w_float(psnr)));
        return out;
    }
}

typedef struct AQClip {
    int64_t          start;
    int              want_frames;
    int              n;
    int              ready;
    CVPixelBufferRef *pbs;
    float           **ref_y;
} AQClip;

typedef struct AQClipTrialRes {
    int    nf;
    int    sample_ok;
    int    failed;
    char   err[512];
    double mean_ssim;
    double min_ssim;
    double mean_ms;
    double min_ms;
    double psnr;
} AQClipTrialRes;

typedef struct AQClipTrialCtx {
    AQClip         *clips;
    const char     *codec;
    const char     *level;
    int             w, h;
    int32_t         num, den;
    int64_t         bitrate;
    int             gop, reorder, speed;
    double          min_ssim_req, min_ms_req, min_psnr_req;
    size_t          npix, qpix;
    float          *cand_all;
    float          *da_all, *db_all, *ea_all, *eb_all;
    AQClipTrialRes *res;
} AQClipTrialCtx;

static void a_qclips_free(AQClip *clips, int nclips) {
    if (!clips) return;
    for (int i = 0; i < nclips; i++) {
        if (clips[i].pbs) {
            for (int f = 0; f < clips[i].n; f++)
                if (clips[i].pbs[f]) CVPixelBufferRelease(clips[i].pbs[f]);
            free(clips[i].pbs);
        }
        if (clips[i].ref_y) {
            for (int f = 0; f < clips[i].n; f++) free(clips[i].ref_y[f]);
            free(clips[i].ref_y);
        }
    }
    free(clips);
}

static void a_quality_trial_worker(void *ctxp, size_t idx) {
    @autoreleasepool {
        AQClipTrialCtx *c = ctxp;
        int ci = (int)idx;
        AQClip *cl = &c->clips[ci];
        AQClipTrialRes *r = &c->res[ci];
        memset(r, 0, sizeof *r);

        MEncoder *enc = w_media_enc_open(c->codec, c->w, c->h, c->num, c->den, -1.0, c->bitrate, c->gop,
                                         "rgba", "left", c->reorder, c->speed, c->level, r->err, sizeof r->err);
        if (!enc) { r->failed = 1; return; }

        int max_segs = (cl->n + c->gop - 1) / c->gop + 1;
        WMediaSegment **segs = calloc((size_t)max_segs, sizeof(WMediaSegment *));
        int nseg = 0, seg_f = 0, enc_st = 0;
        for (int f = 0; f < cl->n; f++) {
            CVPixelBufferRetain(cl->pbs[f]);
            enc_st = w_media_enc_submit(enc, cl->pbs[f]);
            if (enc_st != 0) break;
            if (++seg_f == c->gop) {
                WMediaSegment *sg = w_media_enc_cut(enc);
                if (sg) segs[nseg++] = sg;
                seg_f = 0;
            }
        }
        if (enc_st == 0 && seg_f > 0) {
            WMediaSegment *sg = w_media_enc_cut(enc);
            if (sg) segs[nseg++] = sg;
        }
        int fin_ok = (enc_st == 0 && nseg > 0);
        for (int k = 0; k < nseg && fin_ok; k++) {
            if (w_media_seg_finish(segs[k], r->err, sizeof r->err) != 0) fin_ok = 0;
        }
        w_media_enc_free(enc);
        if (!fin_ok) {
            for (int k = 0; k < nseg; k++) if (segs[k]) w_media_seg_free(segs[k]);
            free(segs);
            if (enc_st || !r->err[0]) snprintf(r->err, sizeof r->err, "trial encode failed (%s)", enc_st ? "submit" : "empty");
            r->failed = 1;
            return;
        }

        ADec *dc = a_dec_open_mem(segs, nseg, 0, 0, 30000, 16, r->err, sizeof r->err);
        if (!dc) { r->failed = 1; return; }

        float *cand_y = c->cand_all + (size_t)ci * c->npix;
        float *da = c->da_all + (size_t)ci * c->qpix;
        float *db = c->db_all + (size_t)ci * c->qpix;
        float *ea = c->ea_all + (size_t)ci * c->qpix;
        float *eb = c->eb_all + (size_t)ci * c->qpix;

        double sum_ssim = 0.0, min_ssim = 1.0, sum_ms = 0.0, min_ms = 1.0, sum_mse = 0.0;
        int nf = 0;
        while (nf < cl->n) {
            CVPixelBufferRef pbc = NULL;
            int64_t fc = 0;
            int rc = a_dec_next(dc, &pbc, &fc, r->err, sizeof r->err);
            if (rc < 0) {
                a_dec_free(dc);
                r->failed = 1;
                return;
            }
            if (rc == 0) break;
            CVPixelBufferLockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
            const uint8_t *cy = CVPixelBufferGetBaseAddressOfPlane(pbc, 0);
            size_t cys = CVPixelBufferGetBytesPerRowOfPlane(pbc, 0);
            int cten = CVPixelBufferGetPixelFormatType(pbc) != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            a_yplane_to_f32(cy, cys, c->w, c->h, cten, cand_y);
            CVPixelBufferUnlockBaseAddress(pbc, kCVPixelBufferLock_ReadOnly);
            CVBufferRelease(pbc);

            double mse = 0.0, ssim0 = 0.0, ms = 0.0;
            a_quality_frame_metrics(cl->ref_y[nf], cand_y, da, db, ea, eb, c->w, c->h, &mse, &ssim0, &ms);
            sum_mse += mse;
            sum_ssim += ssim0;
            if (ssim0 < min_ssim) min_ssim = ssim0;
            sum_ms += ms;
            if (ms < min_ms) min_ms = ms;
            nf++;
        }
        a_dec_free(dc);
        if (nf <= 0) {
            snprintf(r->err, sizeof r->err, "trial decoded zero frames");
            r->failed = 1;
            return;
        }
        double mean_mse = sum_mse / (double)nf;
        r->nf = nf;
        r->psnr = mean_mse <= 1e-12 ? 99.0 : -10.0 * log10(mean_mse);
        r->mean_ssim = sum_ssim / (double)nf;
        r->min_ssim = min_ssim;
        r->mean_ms = sum_ms / (double)nf;
        r->min_ms = min_ms;
        r->sample_ok = 1;
        if (c->min_ssim_req > 0.0 && r->mean_ssim < c->min_ssim_req) r->sample_ok = 0;
        if (c->min_ms_req > 0.0 && r->mean_ms < c->min_ms_req) r->sample_ok = 0;
        if (c->min_psnr_req > 0.0 && r->psnr < c->min_psnr_req) r->sample_ok = 0;
    }
}

/* w_media_quality_search(src, [[bitrate, level], ...], spec) -> [chosen_idx, trials_arr] */
WValue w_media_quality_search(WValue srcv, WValue ratesv, WValue spec) {
    @autoreleasepool {
        if (!w_is_array(ratesv) || w_as_array(ratesv)->size == 0)
            w_media_raise("MediaVerify.quality_search: rates must be a non-empty Array");
        int nrates = (int)w_as_array(ratesv)->size;
        WValue clipsv = a_spec(spec, "clips");
        if (!w_is_array(clipsv) || w_as_array(clipsv)->size == 0)
            w_media_raise("MediaVerify.quality_search: clips must be a non-empty Array");
        int nclips = (int)w_as_array(clipsv)->size;

        WValue ratev = a_spec(spec, "rate");
        int32_t num = (int32_t)w_media_num(m_avf_arr(ratev, 0), 24, "rate");
        int32_t den = (int32_t)w_media_num(m_avf_arr(ratev, 1), 1, "rate");
        int w = (int)w_media_num(a_spec(spec, "width"), 0, "width");
        int h = (int)w_media_num(a_spec(spec, "height"), 0, "height");
        int fit_code = (int)w_media_num(a_spec(spec, "fit"), 0, "fit");
        int gop = (int)w_media_num(a_spec(spec, "gop"), 48, "gop");
        if (gop < 1) gop = 1;
        WValue reorderv = a_spec(spec, "reorder");
        int reorder = reorderv == W_NIL ? 1 : reorderv > 1;
        int speed = a_spec(spec, "speed") > 1;
        double min_ssim_req = w_media_num(a_spec(spec, "min_ssim"), 0.0, "min_ssim");
        double min_ms_req = w_media_num(a_spec(spec, "min_ms_ssim"), 0.0, "min_ms_ssim");
        double min_psnr_req = w_media_num(a_spec(spec, "min_psnr"), 0.0, "min_psnr");

        char codec[32], filt[32], err[512];
        w_media_str(a_spec(spec, "codec"), codec, sizeof codec);
        if (!codec[0]) snprintf(codec, sizeof codec, "hevc10");
        w_media_str(a_spec(spec, "filter"), filt, sizeof filt);
        int filter = filt[0] ? w_media_filter_id(filt) : W_MEDIA_FILTER_LANCZOS3;
        if (filter < 0) w_media_raise("MediaVerify.quality_search: unknown filter '%s'", filt);

        AQClip *clips = calloc((size_t)nclips, sizeof *clips);
        for (int ci = 0; ci < nclips; ci++) {
            WValue ce = w_array_get(clipsv, w_int(ci));
            clips[ci].start = (int64_t)w_media_num(m_avf_arr(ce, 0), 0, "clip start");
            clips[ci].want_frames = (int)w_media_num(m_avf_arr(ce, 1), 24, "clip frames");
            if (clips[ci].want_frames < 1) clips[ci].want_frames = 1;
        }

        /* Pre-decode all reference clips once using a single forward ADec pass when clips are close */
        WValue r0 = w_array_get(ratesv, w_int(0));
        int64_t probe_br = w_is_array(r0) ? (int64_t)w_media_num(m_avf_arr(r0, 0), 1000000, "bitrate")
                                          : (int64_t)w_media_num(r0, 1000000, "bitrate");
        char probe_lvl[16] = "";
        if (w_is_array(r0)) w_media_str(m_avf_arr(r0, 1), probe_lvl, sizeof probe_lvl);
        MEncoder *probe_enc = w_media_enc_open(codec, w, h, num, den, -1.0, probe_br > 0 ? probe_br : 1000000, gop,
                                               "rgba", "left", reorder, speed, probe_lvl[0] ? probe_lvl : NULL, err, sizeof err);
        if (!probe_enc) {
            a_qclips_free(clips, nclips);
            w_media_raise("MediaVerify.quality_search: %s", err);
        }

        WMediaScale py, pc, py_ref10;
        memset(&py, 0, sizeof py);
        memset(&pc, 0, sizeof pc);
        memset(&py_ref10, 0, sizeof py_ref10);
        int plans_ready = 0, need_ref10 = 0, y_copy = 0, c_copy = 0;
        int enc_bits = w_media_enc_bits(probe_enc), enc_vsub = w_media_enc_vsub(probe_enc);
        uint16_t *ref10_buf = NULL;
        size_t npix = (size_t)w * (size_t)h;

        ADec *dr = NULL;
        CVPixelBufferRef prev_pb = NULL;
        int64_t last_fidx = -1;
        int eof_hit = 0;

        for (int ci = 0; ci < nclips; ci++) {
            AQClip *cl = &clips[ci];
            if (!dr || eof_hit || cl->start <= last_fidx || cl->start - last_fidx > 300) {
                if (prev_pb) { CVBufferRelease(prev_pb); prev_pb = NULL; }
                if (dr) { a_dec_free(dr); dr = NULL; }
                dr = a_open_any_source(srcv, num, den, 0, cl->start, "MediaVerify.quality_search(reference)");
                last_fidx = cl->start - 1;
                eof_hit = 0;
            }
            if (!plans_ready) {
                double crop[4]; int rect[4];
                a_fit_geometry(dr->w, dr->h, w, h, fit_code, crop, rect);
                uint8_t fy[4] = {16, 0, 0, 0}, fc[4] = {128, 128, 0, 0};
                int src_vsub = a_dec_vsub(dr);
                double osx = dr->siting == 1 ? 1.0 : 0.5;
                double osy = src_vsub == 1 || dr->siting == 2 ? 0.5 : 1.0;
                double ody = enc_vsub == 2 ? 1.0 : 0.5;
                int rc = w_media_scale_plan(&py, 1, W_MEDIA_ALPHA_NONE, filter, dr->w, dr->h, w, h,
                                            crop, rect, 1, 1, 0.5, 0.5, 1, 1, 0.5, 0.5, fy, enc_bits, err, sizeof err);
                if (rc == 0)
                    rc = w_media_scale_plan(&pc, 2, W_MEDIA_ALPHA_NONE, filter,
                                            (dr->w + 1) / 2, (dr->h + src_vsub - 1) / src_vsub, w / 2, h / enc_vsub,
                                            crop, rect, 2, src_vsub, osx, osy, 2, enc_vsub, 0.5, ody, fc, enc_bits, err, sizeof err);
                if (rc == 0 && enc_bits == 8 && (dr->w != w || dr->h != h || fit_code != 0)) {
                    rc = w_media_scale_plan(&py_ref10, 1, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3, dr->w, dr->h, w, h,
                                            crop, rect, 1, 1, 0.5, 0.5, 1, 1, 0.5, 0.5, fy, 10, err, sizeof err);
                    if (rc == 0) {
                        py_ref10.in_bits = 10; py_ref10.vimage_ok = 0; need_ref10 = 1;
                        size_t rbytes = (npix * sizeof(uint16_t) + 16383u) & ~(size_t)16383u;
                        if (posix_memalign((void **)&ref10_buf, 16384, rbytes) != 0) ref10_buf = NULL;
                    }
                }
                if (rc != 0) {
                    if (prev_pb) CVBufferRelease(prev_pb);
                    a_dec_free(dr); w_media_enc_free(probe_enc);
                    free(ref10_buf); a_qclips_free(clips, nclips);
                    w_media_raise("MediaVerify.quality_search: %s", err);
                }
                py.in_bits = pc.in_bits = 10;
                py.vimage_ok = pc.vimage_ok = 0;
                if (dr->w == w && dr->h == h && fit_code == 0) {
                    y_copy = 1;
                    if ((w % 2) == 0 && (h % enc_vsub) == 0 && src_vsub == enc_vsub && osx == 0.5 && osy == ody)
                        c_copy = 1;
                }
                plans_ready = 1;
            }

            cl->pbs = calloc((size_t)cl->want_frames, sizeof(CVPixelBufferRef));
            cl->ref_y = calloc((size_t)cl->want_frames, sizeof(float *));
            int64_t next_idx = 0;
            while (cl->n < cl->want_frames) {
                CVPixelBufferRef spb = NULL;
                int64_t fidx = 0;
                int rr = eof_hit ? 0 : a_dec_next(dr, &spb, &fidx, err, sizeof err);
                if (rr < 0) {
                    if (prev_pb) CVBufferRelease(prev_pb);
                    a_dec_free(dr); w_media_enc_free(probe_enc);
                    free(ref10_buf);
                    w_media_scale_free(&py); w_media_scale_free(&pc); if (need_ref10) w_media_scale_free(&py_ref10);
                    a_qclips_free(clips, nclips);
                    w_media_raise("MediaVerify.quality_search: %s", err);
                }
                if (rr == 0) {
                    eof_hit = 1;
                    if (!prev_pb) break;
                    spb = (CVPixelBufferRef)CVBufferRetain(prev_pb);
                } else {
                    last_fidx = fidx;
                    if (prev_pb) CVBufferRelease(prev_pb);
                    prev_pb = (CVPixelBufferRef)CVBufferRetain(spb);
                    if (fidx < cl->start + next_idx) { CVBufferRelease(spb); continue; }
                }
                CVPixelBufferRef dpb = w_media_enc_buffer(probe_enc);
                if (!dpb) {
                    CVBufferRelease(spb);
                    if (prev_pb) CVBufferRelease(prev_pb);
                    a_dec_free(dr); w_media_enc_free(probe_enc);
                    free(ref10_buf);
                    w_media_scale_free(&py); w_media_scale_free(&pc); if (need_ref10) w_media_scale_free(&py_ref10);
                    a_qclips_free(clips, nclips);
                    w_media_raise("MediaVerify.quality_search: out of encoder pixel buffers");
                }
                CVPixelBufferLockBaseAddress(spb, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferLockBaseAddress(dpb, 0);
                const uint8_t *sy = CVPixelBufferGetBaseAddressOfPlane(spb, 0), *sc = CVPixelBufferGetBaseAddressOfPlane(spb, 1);
                size_t sys = CVPixelBufferGetBytesPerRowOfPlane(spb, 0), scs = CVPixelBufferGetBytesPerRowOfPlane(spb, 1);
                uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(dpb, 0), *dc = CVPixelBufferGetBaseAddressOfPlane(dpb, 1);
                size_t dys = CVPixelBufferGetBytesPerRowOfPlane(dpb, 0), dcs = CVPixelBufferGetBytesPerRowOfPlane(dpb, 1);
                size_t syl = sys * CVPixelBufferGetHeightOfPlane(spb, 0), scl = scs * CVPixelBufferGetHeightOfPlane(spb, 1);
                size_t dyl = dys * CVPixelBufferGetHeightOfPlane(dpb, 0), dcl = dcs * CVPixelBufferGetHeightOfPlane(dpb, 1);
                int b2 = 0;
                if (y_copy && c_copy) {
                    a_plane_copy_10(sy, sys, dy, dys, w, h, enc_bits);
                    a_plane_copy_10(sc, scs, dc, dcs, pc.dst_w * 2, pc.dst_h, enc_bits);
                } else if (w_media_metal_available()) {
                    WMediaJob jobs[2] = {
                        {&py, sy, sys, syl, dy, dys, dyl, spb, dpb, 0, 0},
                        {&pc, sc, scs, scl, dc, dcs, dcl, spb, dpb, 1, 1}
                    };
                    if (w_media_scale_metal_jobs(jobs, 2, err, sizeof err) != 0) {
                        int b1 = w_media_scale_run(&py, W_MEDIA_BACKEND_CPU, sy, sys, syl, dy, dys, dyl, err, sizeof err);
                        b2 = b1 < 0 ? b1 : w_media_scale_run(&pc, W_MEDIA_BACKEND_CPU, sc, scs, scl, dc, dcs, dcl, err, sizeof err);
                    }
                } else {
                    int b1 = w_media_scale_run(&py, W_MEDIA_BACKEND_CPU, sy, sys, syl, dy, dys, dyl, err, sizeof err);
                    b2 = b1 < 0 ? b1 : w_media_scale_run(&pc, W_MEDIA_BACKEND_CPU, sc, scs, scl, dc, dcs, dcl, err, sizeof err);
                }
                float *rf = malloc(npix * sizeof(float));
                if (b2 >= 0) {
                    if (enc_bits == 10) {
                        a_yplane_to_f32(dy, dys, w, h, 1, rf);
                    } else if (y_copy) {
                        a_yplane_to_f32(sy, sys, w, h, 1, rf);
                    } else if (need_ref10 && ref10_buf) {
                        b2 = w_media_scale_run(&py_ref10, W_MEDIA_BACKEND_AUTO, sy, sys, syl,
                                               (uint8_t *)ref10_buf, (size_t)w * 2, (size_t)w * 2 * (size_t)h, err, sizeof err);
                        if (b2 >= 0) a_yplane_to_f32((const uint8_t *)ref10_buf, (size_t)w * 2, w, h, 1, rf);
                    } else {
                        a_yplane_to_f32(dy, dys, w, h, 0, rf);
                    }
                }
                CVPixelBufferUnlockBaseAddress(dpb, 0);
                CVPixelBufferUnlockBaseAddress(spb, kCVPixelBufferLock_ReadOnly);
                CVBufferRelease(spb);
                if (b2 < 0) {
                    free(rf); CVPixelBufferRelease(dpb);
                    if (prev_pb) CVBufferRelease(prev_pb);
                    a_dec_free(dr); w_media_enc_free(probe_enc);
                    free(ref10_buf);
                    w_media_scale_free(&py); w_media_scale_free(&pc); if (need_ref10) w_media_scale_free(&py_ref10);
                    a_qclips_free(clips, nclips);
                    w_media_raise("MediaVerify.quality_search: %s", err);
                }
                cl->pbs[cl->n] = dpb;
                cl->ref_y[cl->n] = rf;
                cl->n++;
                next_idx++;
            }
            if (cl->n == 0) {
                if (prev_pb) CVBufferRelease(prev_pb);
                a_dec_free(dr); w_media_enc_free(probe_enc);
                free(ref10_buf);
                w_media_scale_free(&py); w_media_scale_free(&pc); if (need_ref10) w_media_scale_free(&py_ref10);
                a_qclips_free(clips, nclips);
                w_media_raise("MediaVerify.quality_search: clip %d has zero frames", ci);
            }
            cl->ready = 1;
        }
        if (prev_pb) CVBufferRelease(prev_pb);
        if (dr) a_dec_free(dr);
        w_media_enc_free(probe_enc);
        free(ref10_buf);
        if (plans_ready) { w_media_scale_free(&py); w_media_scale_free(&pc); if (need_ref10) w_media_scale_free(&py_ref10); }

        size_t qpix = npix / 4 + 16;
        float *cand_all = malloc((size_t)nclips * npix * sizeof(float));
        float *da_all = malloc((size_t)nclips * qpix * sizeof(float));
        float *db_all = malloc((size_t)nclips * qpix * sizeof(float));
        float *ea_all = malloc((size_t)nclips * qpix * sizeof(float));
        float *eb_all = malloc((size_t)nclips * qpix * sizeof(float));
        AQClipTrialRes *res = calloc((size_t)nclips, sizeof *res);

        WValue trials_out = w_array_new_empty();
        int lo = 0, hi = nrates - 1, chosen = -1;

        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            WValue re = w_array_get(ratesv, w_int(mid));
            int64_t bitrate = 0;
            char level[16] = "";
            if (w_is_array(re)) {
                bitrate = (int64_t)w_media_num(m_avf_arr(re, 0), 0, "bitrate");
                w_media_str(m_avf_arr(re, 1), level, sizeof level);
            } else {
                bitrate = (int64_t)w_media_num(re, 0, "bitrate");
            }

            AQClipTrialCtx tctx = {
                clips, codec, level[0] ? level : NULL, w, h, num, den, bitrate, gop, reorder, speed,
                min_ssim_req, min_ms_req, min_psnr_req, npix, qpix,
                cand_all, da_all, db_all, ea_all, eb_all, res
            };
            if (nclips > 1)
                dispatch_apply_f((size_t)nclips, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &tctx, a_quality_trial_worker);
            else
                a_quality_trial_worker(&tctx, 0);

            int trial_ok = 1;
            WValue clip_rows = w_array_new_empty();
            for (int ci = 0; ci < nclips; ci++) {
                AQClipTrialRes *r = &res[ci];
                if (r->failed) {
                    char ferr[512];
                    snprintf(ferr, sizeof ferr, "%s", r->err);
                    free(cand_all); free(da_all); free(db_all); free(ea_all); free(eb_all); free(res);
                    a_qclips_free(clips, nclips);
                    w_media_raise("MediaVerify.quality_search: %s", ferr);
                }
                WValue crow = w_array_new_empty();
                crow = w_array_push(crow, w_int(ci));
                crow = w_array_push(crow, w_int(r->nf));
                crow = w_array_push(crow, w_float(r->mean_ssim));
                crow = w_array_push(crow, w_float(r->min_ssim));
                crow = w_array_push(crow, w_float(r->mean_ms));
                crow = w_array_push(crow, w_float(r->min_ms));
                crow = w_array_push(crow, w_float(r->psnr));
                crow = w_array_push(crow, r->sample_ok ? W_TRUE : W_FALSE);
                clip_rows = w_array_push(clip_rows, crow);
                if (!r->sample_ok) {
                    trial_ok = 0;
                    break;
                }
            }

            WValue trow = w_array_new_empty();
            trow = w_array_push(trow, w_int(mid));
            trow = w_array_push(trow, w_int(bitrate));
            trow = w_array_push(trow, trial_ok ? W_TRUE : W_FALSE);
            trow = w_array_push(trow, clip_rows);
            trials_out = w_array_push(trials_out, trow);

            if (trial_ok) {
                chosen = mid;
                hi = mid - 1;
            } else {
                lo = mid + 1;
            }
        }

        free(cand_all); free(da_all); free(db_all); free(ea_all); free(eb_all); free(res);
        a_qclips_free(clips, nclips);

        WValue out = w_array_new_empty();
        out = w_array_push(out, w_int(chosen));
        out = w_array_push(out, trials_out);
        return out;
    }
}

typedef struct AYuvRgbCtx {
    const uint8_t *yp, *cp;
    size_t         ys, cs;
    uint8_t       *dst;
    int            w, h, vsub, depth;
} AYuvRgbCtx;

static void a_yuv10_to_rgb_band(void *ctxp, size_t bi) {
    AYuvRgbCtx *c = ctxp;
    int w = c->w, h = c->h, vsub = c->vsub, depth = c->depth;
    int y0 = (int)((int64_t)h * (int64_t)bi / 8), y1 = (int)((int64_t)h * (int64_t)(bi + 1) / 8);
    int ch_h = (h + vsub - 1) / vsub, cw_pairs = (w + 1) / 2;
    for (int y = y0; y < y1; y++) {
        const uint16_t *yr = (const uint16_t *)(const void *)(c->yp + (size_t)y * c->ys);
        int cy0 = y / vsub, cy1 = cy0;
        double wy = 0.0;
        if (vsub == 2) {
            /* Left chroma siting (0.5, 1.0 in luma units): chroma row k sits between luma rows 2k and 2k+1. */
            double pos = ((double)y + 0.5 - 1.0) * 0.5;
            int base = (int)floor(pos);
            wy = pos - (double)base;
            cy0 = base < 0 ? 0 : (base >= ch_h ? ch_h - 1 : base);
            cy1 = base + 1 < 0 ? 0 : (base + 1 >= ch_h ? ch_h - 1 : base + 1);
        }
        const uint16_t *cr0 = (const uint16_t *)(const void *)(c->cp + (size_t)cy0 * c->cs);
        const uint16_t *cr1 = (const uint16_t *)(const void *)(c->cp + (size_t)cy1 * c->cs);
        uint8_t *out = c->dst + (size_t)y * (size_t)w * (size_t)(depth == 16 ? 6 : 3);
        int x = 0;
#if defined(__aarch64__)
        {
            float wyf = (float)wy, w0f = 1.0f - wyf;
            float32x4_t v64 = vdupq_n_f32(64.0f), v512 = vdupq_n_f32(512.0f);
            float32x4_t vysc = vdupq_n_f32(1.0f / 876.0f), vcsc = vdupq_n_f32(1.0f / 896.0f);
            float32x4_t vkrc = vdupq_n_f32(1.5748f), vkbc = vdupq_n_f32(1.8556f);
            float32x4_t vkgb = vdupq_n_f32(-0.187324273f), vkgr = vdupq_n_f32(-0.468124273f);
            float32x4_t vzero = vdupq_n_f32(0.0f), vone = vdupq_n_f32(1.0f);
            float32x4_t vout_sc = vdupq_n_f32(depth == 16 ? 65535.0f : 255.0f);
            /* Process 8 pixels (4 chroma pairs p..p+3, requiring p+4 < cw_pairs -> x + 9 < w) per iteration */
            for (; x + 9 < w; x += 8) {
                int p = x >> 1;
                uint16x8_t y16 = vshrq_n_u16(vld1q_u16(yr + x), 6);
                float32x4_t y_lo = vmulq_f32(vsubq_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(y16))), v64), vysc);
                float32x4_t y_hi = vmulq_f32(vsubq_f32(vcvtq_f32_u32(vmovl_high_u16(y16)), v64), vysc);

                /* Load 5 (Cb,Cr) pairs at p..p+4 */
                uint16x4x2_t c0_a = vld2_u16(cr0 + 2 * p);
                uint16_t b0_4 = cr0[2 * (p + 4)] >> 6, r0_4 = cr0[2 * (p + 4) + 1] >> 6;
                float32x4_t cb_e, cr_e;
                float cb_4, cr_4;
                if (vsub == 2) {
                    uint16x4x2_t c1_a = vld2_u16(cr1 + 2 * p);
                    uint16_t b1_4 = cr1[2 * (p + 4)] >> 6, r1_4 = cr1[2 * (p + 4) + 1] >> 6;
                    float32x4_t b0f = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c0_a.val[0], 6)));
                    float32x4_t r0f = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c0_a.val[1], 6)));
                    float32x4_t b1f = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c1_a.val[0], 6)));
                    float32x4_t r1f = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c1_a.val[1], 6)));
                    cb_e = vfmaq_n_f32(vmulq_n_f32(b0f, w0f), b1f, wyf);
                    cr_e = vfmaq_n_f32(vmulq_n_f32(r0f, w0f), r1f, wyf);
                    cb_4 = w0f * (float)b0_4 + wyf * (float)b1_4;
                    cr_4 = w0f * (float)r0_4 + wyf * (float)r1_4;
                } else {
                    cb_e = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c0_a.val[0], 6)));
                    cr_e = vcvtq_f32_u32(vmovl_u16(vshr_n_u16(c0_a.val[1], 6)));
                    cb_4 = (float)b0_4;
                    cr_4 = (float)r0_4;
                }
                float32x4_t cb_next = vextq_f32(cb_e, vdupq_n_f32(cb_4), 1);
                float32x4_t cr_next = vextq_f32(cr_e, vdupq_n_f32(cr_4), 1);
                float32x4_t cb_o = vmulq_n_f32(vaddq_f32(cb_e, cb_next), 0.5f);
                float32x4_t cr_o = vmulq_n_f32(vaddq_f32(cr_e, cr_next), 0.5f);

                float32x4x2_t cb_zip = vzipq_f32(cb_e, cb_o);
                float32x4x2_t cr_zip = vzipq_f32(cr_e, cr_o);
                float32x4_t cbn_lo = vmulq_f32(vsubq_f32(cb_zip.val[0], v512), vcsc);
                float32x4_t cbn_hi = vmulq_f32(vsubq_f32(cb_zip.val[1], v512), vcsc);
                float32x4_t crn_lo = vmulq_f32(vsubq_f32(cr_zip.val[0], v512), vcsc);
                float32x4_t crn_hi = vmulq_f32(vsubq_f32(cr_zip.val[1], v512), vcsc);

                float32x4_t rf_lo = vminq_f32(vmaxq_f32(vfmaq_f32(y_lo, vkrc, crn_lo), vzero), vone);
                float32x4_t gf_lo = vminq_f32(vmaxq_f32(vfmaq_f32(vfmaq_f32(y_lo, vkgb, cbn_lo), vkgr, crn_lo), vzero), vone);
                float32x4_t bf_lo = vminq_f32(vmaxq_f32(vfmaq_f32(y_lo, vkbc, cbn_lo), vzero), vone);

                float32x4_t rf_hi = vminq_f32(vmaxq_f32(vfmaq_f32(y_hi, vkrc, crn_hi), vzero), vone);
                float32x4_t gf_hi = vminq_f32(vmaxq_f32(vfmaq_f32(vfmaq_f32(y_hi, vkgb, cbn_hi), vkgr, crn_hi), vzero), vone);
                float32x4_t bf_hi = vminq_f32(vmaxq_f32(vfmaq_f32(y_hi, vkbc, cbn_hi), vzero), vone);

                uint16x8_t ru16 = vcombine_u16(vmovn_u32(vcvtaq_u32_f32(vmulq_f32(rf_lo, vout_sc))),
                                               vmovn_u32(vcvtaq_u32_f32(vmulq_f32(rf_hi, vout_sc))));
                uint16x8_t gu16 = vcombine_u16(vmovn_u32(vcvtaq_u32_f32(vmulq_f32(gf_lo, vout_sc))),
                                               vmovn_u32(vcvtaq_u32_f32(vmulq_f32(gf_hi, vout_sc))));
                uint16x8_t bu16 = vcombine_u16(vmovn_u32(vcvtaq_u32_f32(vmulq_f32(bf_lo, vout_sc))),
                                               vmovn_u32(vcvtaq_u32_f32(vmulq_f32(bf_hi, vout_sc))));
                if (depth == 16) {
                    uint16x8x3_t rgb16 = {{ru16, gu16, bu16}};
                    vst3q_u16((uint16_t *)(void *)(out + (size_t)x * 6), rgb16);
                } else {
                    uint8x8x3_t rgb8 = {{vmovn_u16(ru16), vmovn_u16(gu16), vmovn_u16(bu16)}};
                    vst3_u8(out + (size_t)x * 3, rgb8);
                }
            }
        }
#endif
        for (; x < w; x++) {
            double y10 = (double)(yr[x] >> 6);
            int cx0 = x / 2, cx1 = (x & 1) ? (cx0 + 1 < cw_pairs ? cx0 + 1 : cx0) : cx0;
            double cb0, crv0;
            if (x & 1) {
                double b00 = (double)(cr0[2 * cx0] >> 6), b01 = (double)(cr0[2 * cx1] >> 6);
                double r00 = (double)(cr0[2 * cx0 + 1] >> 6), r01 = (double)(cr0[2 * cx1 + 1] >> 6);
                if (vsub == 2) {
                    double b10 = (double)(cr1[2 * cx0] >> 6), b11 = (double)(cr1[2 * cx1] >> 6);
                    double r10 = (double)(cr1[2 * cx0 + 1] >> 6), r11 = (double)(cr1[2 * cx1 + 1] >> 6);
                    cb0 = (1.0 - wy) * 0.5 * (b00 + b01) + wy * 0.5 * (b10 + b11);
                    crv0 = (1.0 - wy) * 0.5 * (r00 + r01) + wy * 0.5 * (r10 + r11);
                } else {
                    cb0 = 0.5 * (b00 + b01);
                    crv0 = 0.5 * (r00 + r01);
                }
            } else if (vsub == 2) {
                cb0 = (1.0 - wy) * (double)(cr0[2 * cx0] >> 6) + wy * (double)(cr1[2 * cx0] >> 6);
                crv0 = (1.0 - wy) * (double)(cr0[2 * cx0 + 1] >> 6) + wy * (double)(cr1[2 * cx0 + 1] >> 6);
            } else {
                cb0 = (double)(cr0[2 * cx0] >> 6);
                crv0 = (double)(cr0[2 * cx0 + 1] >> 6);
            }
            double yn = (y10 - 64.0) * (1.0 / 876.0);
            double cbn = (cb0 - 512.0) * (1.0 / 896.0);
            double crn = (crv0 - 512.0) * (1.0 / 896.0);
            double rf = yn + 1.5748 * crn;
            double gf = yn - 0.18732427293064876 * cbn - 0.46812427293064876 * crn;
            double bf = yn + 1.8556 * cbn;
            if (rf < 0.0) rf = 0.0; else if (rf > 1.0) rf = 1.0;
            if (gf < 0.0) gf = 0.0; else if (gf > 1.0) gf = 1.0;
            if (bf < 0.0) bf = 0.0; else if (bf > 1.0) bf = 1.0;
            if (depth == 16) {
                uint16_t ru = (uint16_t)llround(rf * 65535.0);
                uint16_t gu = (uint16_t)llround(gf * 65535.0);
                uint16_t bu = (uint16_t)llround(bf * 65535.0);
                size_t o = (size_t)x * 6;
                out[o + 0] = (uint8_t)(ru & 0xFF); out[o + 1] = (uint8_t)(ru >> 8);
                out[o + 2] = (uint8_t)(gu & 0xFF); out[o + 3] = (uint8_t)(gu >> 8);
                out[o + 4] = (uint8_t)(bu & 0xFF); out[o + 5] = (uint8_t)(bu >> 8);
            } else {
                size_t o = (size_t)x * 3;
                out[o + 0] = (uint8_t)llround(rf * 255.0);
                out[o + 1] = (uint8_t)llround(gf * 255.0);
                out[o + 2] = (uint8_t)llround(bf * 255.0);
            }
        }
    }
}

/* w_media_extract_frames(src, sorted_frames, [width, height, fit_code, depth, rate_num, rate_den]) -> [u8[], ...] */
WValue w_media_extract_frames(WValue srcv, WValue framesv, WValue optv) {
    @autoreleasepool {
        if (!w_is_array(framesv)) w_media_raise("MediaVerify.extract_frames: frames must be an Array");
        int64_t nf = w_as_array(framesv)->size;
        if (nf == 0) return w_array_new_empty();
        int req_w = (int)w_media_num(m_avf_arr(optv, 0), 0, "width");
        int req_h = (int)w_media_num(m_avf_arr(optv, 1), 0, "height");
        int fit_code = (int)w_media_num(m_avf_arr(optv, 2), 0, "fit");
        int depth = (int)w_media_num(m_avf_arr(optv, 3), 8, "depth");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 4), 0, "rate"), den = (int32_t)w_media_num(m_avf_arr(optv, 5), 0, "rate");
        if (depth != 8 && depth != 16) w_media_raise("MediaVerify.extract_frames: depth must be 8 or 16");
        int64_t first_want = (int64_t)w_media_num(w_array_get(framesv, w_int(0)), 0, "frame");
        if (first_want < 0) first_want = 0;
        ADec *d = a_open_any_source(srcv, num, den, 0, first_want, "MediaVerify.extract_frames");
        int dw = req_w > 0 ? req_w : d->w;
        int dh = req_h > 0 ? req_h : d->h;
        int src_vsub = a_dec_vsub(d);
        int need_scale = dw != d->w || dh != d->h || fit_code != 0;
        WMediaScale py, pc;
        memset(&py, 0, sizeof py);
        memset(&pc, 0, sizeof pc);
        uint16_t *sy_buf = NULL, *sc_buf = NULL;
        int dst_vsub = src_vsub;
        char err[512];
        if (need_scale) {
            dst_vsub = 1; /* preserve 4:2:2 vertical chroma resolution on scaled extracts */
            double crop[4]; int rect[4];
            a_fit_geometry(d->w, d->h, dw, dh, fit_code, crop, rect);
            uint8_t fy[4] = {16, 0, 0, 0}, fc[4] = {128, 128, 0, 0};
            double osx = d->siting == 1 ? 1.0 : 0.5, osy = src_vsub == 1 || d->siting == 2 ? 0.5 : 1.0;
            int rc = w_media_scale_plan(&py, 1, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3, d->w, d->h, dw, dh,
                                        crop, rect, 1, 1, 0.5, 0.5, 1, 1, 0.5, 0.5, fy, 10, err, sizeof err);
            if (rc == 0) {
                rc = w_media_scale_plan(&pc, 2, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3,
                                        (d->w + 1) / 2, (d->h + src_vsub - 1) / src_vsub, (dw + 1) / 2, dh,
                                        crop, rect, 2, src_vsub, osx, osy, 2, 1, 0.5, 0.5, fc, 10, err, sizeof err);
                if (rc != 0) w_media_scale_free(&py);
            }
            if (rc != 0) {
                a_dec_free(d);
                w_media_raise("MediaVerify.extract_frames: %s", err);
            }
            py.in_bits = pc.in_bits = 10;
            py.vimage_ok = pc.vimage_ok = 0;
            sy_buf = malloc((size_t)dw * (size_t)dh * sizeof(uint16_t));
            sc_buf = malloc((size_t)((dw + 1) / 2) * 2 * (size_t)dh * sizeof(uint16_t));
        }
        WValue out = w_array_new_empty();
        CVPixelBufferRef cur_pb = NULL;
        int64_t cur_frame = -1;
        size_t out_bytes = (size_t)dw * (size_t)dh * (size_t)(depth == 16 ? 6 : 3);
        for (int64_t i = 0; i < nf; i++) {
            int64_t want = (int64_t)w_media_num(w_array_get(framesv, w_int(i)), 0, "frame");
            if (want < 0) want = 0;
            if (i > 0 && want < cur_frame) {
                if (cur_pb) { CVBufferRelease(cur_pb); cur_pb = NULL; }
                a_dec_free(d);
                d = a_open_any_source(srcv, num, den, 0, want, "MediaVerify.extract_frames");
                cur_frame = -1;
            } else if (cur_frame >= 0 && want - cur_frame > 300) {
                if (cur_pb) { CVBufferRelease(cur_pb); cur_pb = NULL; }
                a_dec_free(d);
                d = a_open_any_source(srcv, num, den, 0, want, "MediaVerify.extract_frames");
                cur_frame = -1;
            }
            while (cur_frame < want) {
                CVPixelBufferRef next_pb = NULL;
                int64_t f = 0;
                int r = a_dec_next(d, &next_pb, &f, err, sizeof err);
                if (r < 0) {
                    if (cur_pb) CVBufferRelease(cur_pb);
                    free(sy_buf); free(sc_buf);
                    if (need_scale) { w_media_scale_free(&py); w_media_scale_free(&pc); }
                    a_dec_free(d);
                    w_media_raise("MediaVerify.extract_frames: %s", err);
                }
                if (r == 0) break; /* hold last frame if want is at/past end */
                if (cur_pb) CVBufferRelease(cur_pb);
                cur_pb = next_pb;
                cur_frame = f;
            }
            if (!cur_pb) {
                free(sy_buf); free(sc_buf);
                if (need_scale) { w_media_scale_free(&py); w_media_scale_free(&pc); }
                a_dec_free(d);
                w_media_raise("MediaVerify.extract_frames: could not decode frame %lld", (long long)want);
            }
            WValue bytes = w_bytes_new((int64_t)out_bytes);
            uint8_t *dst_ptr = (uint8_t *)w_as_array(bytes)->slots;
            CVPixelBufferLockBaseAddress(cur_pb, kCVPixelBufferLock_ReadOnly);
            const uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(cur_pb, 0);
            const uint8_t *cp = CVPixelBufferGetBaseAddressOfPlane(cur_pb, 1);
            size_t ys = CVPixelBufferGetBytesPerRowOfPlane(cur_pb, 0);
            size_t cs = CVPixelBufferGetBytesPerRowOfPlane(cur_pb, 1);
            if (need_scale) {
                size_t dys = (size_t)dw * 2, dcs = (size_t)((dw + 1) / 2) * 4;
                int b1 = w_media_scale_run(&py, W_MEDIA_BACKEND_CPU, yp, ys, ys * (size_t)d->h,
                                           (uint8_t *)sy_buf, dys, dys * (size_t)dh, err, sizeof err);
                int b2 = b1 < 0 ? b1 : w_media_scale_run(&pc, W_MEDIA_BACKEND_CPU, cp, cs, cs * (size_t)((d->h + src_vsub - 1) / src_vsub),
                                                         (uint8_t *)sc_buf, dcs, dcs * (size_t)dh, err, sizeof err);
                CVPixelBufferUnlockBaseAddress(cur_pb, kCVPixelBufferLock_ReadOnly);
                if (b2 < 0) {
                    CVBufferRelease(cur_pb);
                    free(sy_buf); free(sc_buf);
                    w_media_scale_free(&py); w_media_scale_free(&pc);
                    a_dec_free(d);
                    w_media_raise("MediaVerify.extract_frames: %s", err);
                }
                AYuvRgbCtx ctx = {(const uint8_t *)sy_buf, (const uint8_t *)sc_buf, dys, dcs, dst_ptr, dw, dh, dst_vsub, depth};
                if ((int64_t)dw * dh >= 32768)
                    dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_yuv10_to_rgb_band);
                else
                    for (size_t b = 0; b < 8; b++) a_yuv10_to_rgb_band(&ctx, b);
            } else {
                AYuvRgbCtx ctx = {yp, cp, ys, cs, dst_ptr, dw, dh, src_vsub, depth};
                if ((int64_t)dw * dh >= 32768)
                    dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_yuv10_to_rgb_band);
                else
                    for (size_t b = 0; b < 8; b++) a_yuv10_to_rgb_band(&ctx, b);
                CVPixelBufferUnlockBaseAddress(cur_pb, kCVPixelBufferLock_ReadOnly);
            }
            out = w_array_push(out, bytes);
        }
        if (cur_pb) CVBufferRelease(cur_pb);
        free(sy_buf);
        free(sc_buf);
        if (need_scale) { w_media_scale_free(&py); w_media_scale_free(&pc); }
        a_dec_free(d);
        return out;
    }
}

typedef struct AScanReq {
    int64_t frame;
    int     req_w, req_h, fit_code, depth;
    int     orig_idx;
} AScanReq;

static WValue a_scan_extract_one(ADec *d, CVPixelBufferRef pb, int req_w, int req_h, int fit_code, int depth,
                                 char *err, size_t errcap) {
    int dw = req_w > 0 ? req_w : d->w;
    int dh = req_h > 0 ? req_h : d->h;
    int src_vsub = a_dec_vsub(d);
    int need_scale = dw != d->w || dh != d->h || fit_code != 0;
    size_t out_bytes = (size_t)dw * (size_t)dh * (size_t)(depth == 16 ? 6 : 3);
    WValue bytes = w_bytes_new((int64_t)out_bytes);
    uint8_t *dst_ptr = (uint8_t *)w_as_array(bytes)->slots;

    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    const uint8_t *cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    size_t cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);

    if (!need_scale) {
        AYuvRgbCtx ctx = {yp, cp, ys, cs, dst_ptr, dw, dh, src_vsub, depth};
        if ((int64_t)dw * dh >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_yuv10_to_rgb_band);
        else
            for (size_t b = 0; b < 8; b++) a_yuv10_to_rgb_band(&ctx, b);
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        return bytes;
    }

    WMediaScale py, pc;
    memset(&py, 0, sizeof py);
    memset(&pc, 0, sizeof pc);
    double crop[4]; int rect[4];
    a_fit_geometry(d->w, d->h, dw, dh, fit_code, crop, rect);
    uint8_t fy[4] = {16, 0, 0, 0}, fc[4] = {128, 128, 0, 0};
    double osx = d->siting == 1 ? 1.0 : 0.5, osy = src_vsub == 1 || d->siting == 2 ? 0.5 : 1.0;
    int rc = w_media_scale_plan(&py, 1, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3, d->w, d->h, dw, dh,
                                crop, rect, 1, 1, 0.5, 0.5, 1, 1, 0.5, 0.5, fy, 10, err, errcap);
    if (rc == 0) {
        rc = w_media_scale_plan(&pc, 2, W_MEDIA_ALPHA_NONE, W_MEDIA_FILTER_LANCZOS3,
                                (d->w + 1) / 2, (d->h + src_vsub - 1) / src_vsub, (dw + 1) / 2, dh,
                                crop, rect, 2, src_vsub, osx, osy, 2, 1, 0.5, 0.5, fc, 10, err, errcap);
        if (rc != 0) w_media_scale_free(&py);
    }
    if (rc != 0) {
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        return W_NIL;
    }
    py.in_bits = pc.in_bits = 10;
    py.vimage_ok = pc.vimage_ok = 0;
    size_t dys = (size_t)dw * 2, dcs = (size_t)((dw + 1) / 2) * 4;
    uint16_t *sy_buf = malloc(dys * (size_t)dh);
    uint16_t *sc_buf = malloc(dcs * (size_t)dh);
    int b1 = w_media_scale_run(&py, W_MEDIA_BACKEND_CPU, yp, ys, ys * (size_t)d->h,
                               (uint8_t *)sy_buf, dys, dys * (size_t)dh, err, errcap);
    int b2 = b1 < 0 ? b1 : w_media_scale_run(&pc, W_MEDIA_BACKEND_CPU, cp, cs, cs * (size_t)((d->h + src_vsub - 1) / src_vsub),
                                             (uint8_t *)sc_buf, dcs, dcs * (size_t)dh, err, errcap);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    w_media_scale_free(&py);
    w_media_scale_free(&pc);
    if (b2 < 0) {
        free(sy_buf); free(sc_buf);
        return W_NIL;
    }
    AYuvRgbCtx ctx = {(const uint8_t *)sy_buf, (const uint8_t *)sc_buf, dys, dcs, dst_ptr, dw, dh, 1, depth};
    if ((int64_t)dw * dh >= 32768)
        dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_yuv10_to_rgb_band);
    else
        for (size_t b = 0; b < 8; b++) a_yuv10_to_rgb_band(&ctx, b);
    free(sy_buf);
    free(sc_buf);
    return bytes;
}

/* w_media_video_scan(src, [want_anom, black_min, freeze_min, noise, pix_th, rate_num, rate_den],
 *                    [[frame_idx, width, height, fit_code, depth], ...]) -> [frames_n, events, [u8[], ...]] */
WValue w_media_video_scan(WValue srcv, WValue optv, WValue reqsv) {
    @autoreleasepool {
        int want_anom = m_avf_arr(optv, 0) > 1;
        double black_min = w_media_num(m_avf_arr(optv, 1), 1.0, "black_min");
        double freeze_min = w_media_num(m_avf_arr(optv, 2), 3.0, "freeze_min");
        double noise = w_media_num(m_avf_arr(optv, 3), 0.001, "noise");
        double pix_th = w_media_num(m_avf_arr(optv, 4), 0.10, "pix_th");
        int32_t num = (int32_t)w_media_num(m_avf_arr(optv, 5), 0, "rate");
        int32_t den = (int32_t)w_media_num(m_avf_arr(optv, 6), 0, "rate");

        int nreq = (w_is_array(reqsv) ? (int)w_as_array(reqsv)->size : 0);
        AScanReq *reqs = nreq > 0 ? calloc((size_t)nreq, sizeof *reqs) : NULL;
        for (int i = 0; i < nreq; i++) {
            WValue rv = w_array_get(reqsv, w_int(i));
            int64_t f = (int64_t)w_media_num(m_avf_arr(rv, 0), 0, "frame");
            reqs[i].frame = f < 0 ? 0 : f;
            reqs[i].req_w = (int)w_media_num(m_avf_arr(rv, 1), 0, "width");
            reqs[i].req_h = (int)w_media_num(m_avf_arr(rv, 2), 0, "height");
            reqs[i].fit_code = (int)w_media_num(m_avf_arr(rv, 3), 0, "fit");
            reqs[i].depth = (int)w_media_num(m_avf_arr(rv, 4), 8, "depth");
            if (reqs[i].depth != 8 && reqs[i].depth != 16) {
                free(reqs);
                w_media_raise("MediaVerify.video_scan: depth must be 8 or 16");
            }
            reqs[i].orig_idx = i;
        }
        /* Insertion sort by ascending frame index so one decode pass serves all requests. */
        for (int i = 1; i < nreq; i++) {
            AScanReq v = reqs[i];
            int j = i - 1;
            while (j >= 0 && reqs[j].frame > v.frame) { reqs[j + 1] = reqs[j]; j--; }
            reqs[j + 1] = v;
        }

        int64_t start_f = (!want_anom && nreq > 0) ? reqs[0].frame : 0;
        ADec *d = (want_anom && nreq == 0)
            ? a_open_any_source_scaled(srcv, num, den, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, start_f, 320, "MediaVerify.video_scan")
            : a_open_any_source(srcv, num, den, 0, start_f, "MediaVerify.video_scan");
        double dt = (double)d->den / (double)d->num;
        int dw = d->w < 320 ? d->w : 320;
        int dh = (int)(((int64_t)d->h * dw / (d->w ? d->w : 1)) & ~1LL);
        if (dh < 2) dh = 2;
        int npix = dw * dh;
        int x_lo[320], x_hi[320];
        if (want_anom) {
            for (int dx = 0; dx < dw; dx++) {
                int x0 = (int)((int64_t)dx * d->w / dw), x1 = (int)((int64_t)(dx + 1) * d->w / dw);
                if (x1 <= x0) x1 = x0 + 1;
                x_lo[dx] = x0;
                x_hi[dx] = x1;
            }
        }
        int black_req = (int)ceil(0.98 * (double)npix);
        float *cur = want_anom ? malloc((size_t)npix * sizeof(float)) : NULL;
        float *ref = want_anom ? malloc((size_t)npix * sizeof(float)) : NULL;
        WValue *extracted = nreq > 0 ? calloc((size_t)nreq, sizeof(WValue)) : NULL;
        for (int i = 0; i < nreq; i++) extracted[i] = W_NIL;
        WValue events = w_array_new_empty();
        int64_t n = 0, black_start = -1, ref_frame = 0;
        int frozen = 0, req_i = 0;
        CVPixelBufferRef last_pb = NULL;
        char err[512];

        for (;;) {
            if (!want_anom && req_i >= nreq) break;
            CVPixelBufferRef pb = NULL;
            int64_t frame = 0;
            int r = a_dec_next(d, &pb, &frame, err, sizeof err);
            if (r < 0) {
                if (last_pb) CVBufferRelease(last_pb);
                free(cur); free(ref); free(reqs); free(extracted);
                a_dec_free(d);
                w_media_raise("MediaVerify.video_scan: %s", err);
            }
            if (r == 0) break;

            if (want_anom) {
                a_downsample_luma_tv(pb, dw, dh, x_lo, x_hi, cur);
                int bcnt = 0;
                float pth = (float)pix_th;
                for (int i = 0; i < npix; i++) if (cur[i] <= pth) bcnt++;
                if (bcnt >= black_req) {
                    if (black_start < 0) black_start = n;
                } else if (black_start >= 0) {
                    double s0 = (double)black_start * dt, s1 = (double)n * dt;
                    if (s1 - s0 >= black_min) events = w_array_push(events, a_anom_event("black", s0, s1));
                    black_start = -1;
                }
                if (n == 0) {
                    memcpy(ref, cur, (size_t)npix * sizeof(float));
                    ref_frame = 0;
                    frozen = 0;
                } else {
                    double diff = 0.0;
                    for (int i = 0; i < npix; i++) diff += (double)fabsf(cur[i] - ref[i]);
                    double mad = diff / (double)npix;
                    if (mad < noise) {
                        frozen = 1;
                    } else {
                        if (frozen) {
                            double s0 = (double)ref_frame * dt, s1 = (double)n * dt;
                            if (s1 - s0 >= freeze_min) events = w_array_push(events, a_anom_event("freeze", s0, s1));
                        }
                        memcpy(ref, cur, (size_t)npix * sizeof(float));
                        ref_frame = n;
                        frozen = 0;
                    }
                }
            }

            while (req_i < nreq && reqs[req_i].frame <= frame) {
                WValue b = a_scan_extract_one(d, pb, reqs[req_i].req_w, reqs[req_i].req_h, reqs[req_i].fit_code, reqs[req_i].depth, err, sizeof err);
                if (b == W_NIL) {
                    CVBufferRelease(pb);
                    if (last_pb) CVBufferRelease(last_pb);
                    free(cur); free(ref); free(reqs); free(extracted);
                    a_dec_free(d);
                    w_media_raise("MediaVerify.video_scan: %s", err);
                }
                extracted[reqs[req_i].orig_idx] = b;
                req_i++;
            }

            if (req_i < nreq) {
                if (last_pb) CVBufferRelease(last_pb);
                last_pb = (CVPixelBufferRef)CVBufferRetain(pb);
            }
            CVBufferRelease(pb);
            n++;
        }

        while (req_i < nreq) {
            if (!last_pb) {
                free(cur); free(ref); free(reqs); free(extracted);
                a_dec_free(d);
                w_media_raise("MediaVerify.video_scan: could not decode frame %lld", (long long)reqs[req_i].frame);
            }
            WValue b = a_scan_extract_one(d, last_pb, reqs[req_i].req_w, reqs[req_i].req_h, reqs[req_i].fit_code, reqs[req_i].depth, err, sizeof err);
            if (b == W_NIL) {
                CVBufferRelease(last_pb);
                free(cur); free(ref); free(reqs); free(extracted);
                a_dec_free(d);
                w_media_raise("MediaVerify.video_scan: %s", err);
            }
            extracted[reqs[req_i].orig_idx] = b;
            req_i++;
        }
        if (last_pb) CVBufferRelease(last_pb);

        if (want_anom) {
            if (black_start >= 0) {
                double s0 = (double)black_start * dt, s1 = (double)n * dt;
                if (s1 - s0 >= black_min) events = w_array_push(events, a_anom_event("black", s0, s1));
            }
            if (frozen) {
                double s0 = (double)ref_frame * dt, s1 = (double)n * dt;
                if (s1 - s0 >= freeze_min) events = w_array_push(events, a_anom_event("freeze", s0, s1));
            }
        }

        WValue ext_out = w_array_new_empty();
        for (int i = 0; i < nreq; i++) ext_out = w_array_push(ext_out, extracted[i]);
        free(cur); free(ref); free(reqs); free(extracted);
        a_dec_free(d);

        WValue out = w_array_new_empty();
        out = w_array_push(out, w_int(n));
        out = w_array_push(out, events);
        out = w_array_push(out, ext_out);
        return out;
    }
}

/* ======================================================================
   Audio out: a minimal player (AVAudioPlayer) for interactive playback
   ======================================================================
 *
 * core/audio: open a sound file (WAV, AIFF, CAF, M4A ...), play it from a
 * time, pause, stop, read the current time, set the volume. Playback runs on
 * AVAudioPlayer's own threads, so a program needs no run loop for it; the
 * time read back is the player's clock (where in the file the output is),
 * which is what a playhead should follow. Handles are registry handles of
 * kind W_MEDIA_KIND_PLAYER; a closed handle raises, close is idempotent. */

typedef struct APlayer {
    AVAudioPlayer *p;   /* retained */
} APlayer;

/* a number argument: a float, an int (boxed or a raw literal), a decimal or a rational */
static double a_num(WValue v) {
    if (w_is_double(v) || w_is_int(v) || w_is_bigint(v) || (v & W_TAG_MASK) == W_TAG_DECIMAL || w_is_rational(v))
        return w_media_num(v, 0, "audio");
    return (double)w_as_int(v);
}

static APlayer *a_player(WValue h, const char *what) {
    return (APlayer *)w_media_handle_get(h, W_MEDIA_KIND_PLAYER, what);
}

WValue w_media_audio_open(WValue path) {
    @autoreleasepool {
        char s[4096];
        if (!w_media_str(path, s, sizeof s) || !s[0]) w_media_raise("audio_open: path must be a string");
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:s]];
        NSError *err = nil;
        AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&err];
        if (!p) {
            char buf[512];
            snprintf(buf, sizeof buf, "audio_open: %s: %s", s,
                     err ? [[err localizedDescription] UTF8String] : "cannot open");
            w_raise(w_string(buf));
            return W_NIL;
        }
        [p prepareToPlay];
        APlayer *a = calloc(1, sizeof *a);
        a->p = p;
        return w_int(w_media_handle_new(a, W_MEDIA_KIND_PLAYER));
    }
}

/* play from t seconds (t < 0: from where it is) */
WValue w_media_audio_play(WValue h, WValue t) {
    APlayer *a = a_player(h, "audio_play");
    double at = a_num(t);
    if (at >= 0) a->p.currentTime = at;
    return [a->p play] ? W_TRUE : W_FALSE;
}

WValue w_media_audio_pause(WValue h) {
    APlayer *a = a_player(h, "audio_pause");
    [a->p pause];
    return W_TRUE;
}

/* stop and rewind to the start */
WValue w_media_audio_stop(WValue h) {
    APlayer *a = a_player(h, "audio_stop");
    [a->p stop];
    a->p.currentTime = 0;
    [a->p prepareToPlay];
    return W_TRUE;
}

WValue w_media_audio_time(WValue h) {
    APlayer *a = a_player(h, "audio_time");
    return w_float(a->p.currentTime);
}

/* volume 0 … 1 (linear gain on the player's output) */
WValue w_media_audio_volume(WValue h, WValue v) {
    APlayer *a = a_player(h, "audio_volume");
    double g = a_num(v);
    if (g < 0) g = 0;
    if (g > 1) g = 1;
    a->p.volume = (float)g;
    return W_TRUE;
}

/* [duration seconds, playing 0/1, sample rate, channels] */
WValue w_media_audio_info(WValue h) {
    APlayer *a = a_player(h, "audio_info");
    NSDictionary *st = a->p.settings;
    WValue out = w_array_new_empty();
    out = w_array_push(out, w_float(a->p.duration));
    out = w_array_push(out, w_int(a->p.playing ? 1 : 0));
    out = w_array_push(out, w_float([st[AVSampleRateKey] doubleValue]));
    out = w_array_push(out, w_int((int64_t)a->p.numberOfChannels));
    return out;
}

WValue w_media_audio_close(WValue h) {
    APlayer *a = m_avf_peek(h, W_MEDIA_KIND_PLAYER);
    if (!a) return W_FALSE;
    w_media_handle_drop(h, W_MEDIA_KIND_PLAYER);
    [a->p stop];
    [a->p release];
    free(a);
    return W_TRUE;
}

/* ======================================================================
   MIDI (CoreMIDI) and a live sampler (AVAudioEngine) for interactive use
   ======================================================================
 *
 * core/midi: the system's MIDI destinations and sources by name, an output
 * to one (or a virtual source other programs can listen to), an input from
 * one (or a virtual destination other programs can send to) whose messages
 * queue up for the program to read, each with its arrival time.
 * core/live: a sampler that plays now: zones of PCM (key and velocity
 * ranges, a root key, a loop) mixed by AVAudioEngine's render thread,
 * notes started and stopped from the program's thread, each voice
 * resampled to its pitch and released with a short fade. CoreMIDI is
 * loaded at the first call (dlopen), so programs that never use MIDI do
 * not link it. */

#include <CoreMIDI/CoreMIDI.h>
#include <os/lock.h>

typedef OSStatus (*m_client_create_f)(CFStringRef, MIDINotifyProc, void *, MIDIClientRef *);
typedef ItemCount (*m_count_f)(void);
typedef MIDIEndpointRef (*m_get_f)(ItemCount);
typedef OSStatus (*m_strprop_f)(MIDIObjectRef, CFStringRef, CFStringRef *);
typedef OSStatus (*m_outport_f)(MIDIClientRef, CFStringRef, MIDIPortRef *);
typedef OSStatus (*m_inport_f)(MIDIClientRef, CFStringRef, MIDIReadProc, void *, MIDIPortRef *);
typedef OSStatus (*m_connect_f)(MIDIPortRef, MIDIEndpointRef, void *);
typedef OSStatus (*m_send_f)(MIDIPortRef, MIDIEndpointRef, const MIDIPacketList *);
typedef OSStatus (*m_received_f)(MIDIEndpointRef, const MIDIPacketList *);
typedef OSStatus (*m_source_create_f)(MIDIClientRef, CFStringRef, MIDIEndpointRef *);
typedef OSStatus (*m_dest_create_f)(MIDIClientRef, CFStringRef, MIDIReadProc, void *, MIDIEndpointRef *);
typedef OSStatus (*m_dispose_f)(MIDIEndpointRef);
typedef OSStatus (*m_port_dispose_f)(MIDIPortRef);
typedef MIDIPacket *(*m_pl_init_f)(MIDIPacketList *);
typedef MIDIPacket *(*m_pl_add_f)(MIDIPacketList *, ByteCount, MIDIPacket *, MIDITimeStamp, ByteCount, const Byte *);

/* an int argument: a raw literal, a boxed int, or any number (default when nil) */
static int64_t a_int(WValue v, int64_t dflt, const char *what) {
    if (v == W_NIL) return dflt;
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_double(v) || (v & W_TAG_MASK) == W_TAG_DECIMAL || w_is_rational(v) || w_is_bigint(v))
        return (int64_t)w_media_num(v, (double)dflt, what);
    return w_as_int(v);
}

static struct {
    int loaded;
    void *lib;
    m_client_create_f client_create;
    m_count_f n_dest, n_src;
    m_get_f get_dest, get_src;
    m_strprop_f strprop;
    m_outport_f outport;
    m_inport_f inport;
    m_connect_f connect;
    m_send_f send;
    m_received_f received;
    m_source_create_f source_create;
    m_dest_create_f dest_create;
    m_dispose_f ep_dispose;
    m_port_dispose_f port_dispose;
    m_pl_init_f pl_init;
    m_pl_add_f pl_add;
    CFStringRef *name_key;
    MIDIClientRef client;
} g_midi;

static void m_midi_load(const char *what) {
    if (g_midi.loaded == 1) return;
    if (g_midi.loaded == -1) w_media_raise("%s: CoreMIDI is not available", what);
    g_midi.lib = dlopen("/System/Library/Frameworks/CoreMIDI.framework/CoreMIDI", RTLD_LAZY);
    if (!g_midi.lib) { g_midi.loaded = -1; w_media_raise("%s: CoreMIDI could not be loaded", what); }
    g_midi.client_create = (m_client_create_f)dlsym(g_midi.lib, "MIDIClientCreate");
    g_midi.n_dest = (m_count_f)dlsym(g_midi.lib, "MIDIGetNumberOfDestinations");
    g_midi.n_src = (m_count_f)dlsym(g_midi.lib, "MIDIGetNumberOfSources");
    g_midi.get_dest = (m_get_f)dlsym(g_midi.lib, "MIDIGetDestination");
    g_midi.get_src = (m_get_f)dlsym(g_midi.lib, "MIDIGetSource");
    g_midi.strprop = (m_strprop_f)dlsym(g_midi.lib, "MIDIObjectGetStringProperty");
    g_midi.outport = (m_outport_f)dlsym(g_midi.lib, "MIDIOutputPortCreate");
    g_midi.inport = (m_inport_f)dlsym(g_midi.lib, "MIDIInputPortCreate");
    g_midi.connect = (m_connect_f)dlsym(g_midi.lib, "MIDIPortConnectSource");
    g_midi.send = (m_send_f)dlsym(g_midi.lib, "MIDISend");
    g_midi.received = (m_received_f)dlsym(g_midi.lib, "MIDIReceived");
    g_midi.source_create = (m_source_create_f)dlsym(g_midi.lib, "MIDISourceCreate");
    g_midi.dest_create = (m_dest_create_f)dlsym(g_midi.lib, "MIDIDestinationCreate");
    g_midi.ep_dispose = (m_dispose_f)dlsym(g_midi.lib, "MIDIEndpointDispose");
    g_midi.port_dispose = (m_port_dispose_f)dlsym(g_midi.lib, "MIDIPortDispose");
    g_midi.name_key = (CFStringRef *)dlsym(g_midi.lib, "kMIDIPropertyDisplayName");
    g_midi.pl_init = (m_pl_init_f)dlsym(g_midi.lib, "MIDIPacketListInit");
    g_midi.pl_add = (m_pl_add_f)dlsym(g_midi.lib, "MIDIPacketListAdd");
    if (!g_midi.client_create || !g_midi.n_dest || !g_midi.get_dest || !g_midi.strprop || !g_midi.outport || !g_midi.inport ||
        !g_midi.connect || !g_midi.send || !g_midi.received || !g_midi.source_create || !g_midi.dest_create || !g_midi.name_key || !g_midi.pl_init || !g_midi.pl_add) {
        g_midi.loaded = -1;
        w_media_raise("%s: CoreMIDI is missing functions", what);
    }
    OSStatus st = g_midi.client_create(CFSTR("Tungsten"), NULL, NULL, &g_midi.client);
    if (st != noErr) { g_midi.loaded = -1; w_media_raise("%s: MIDIClientCreate failed (%d)", what, (int)st); }
    g_midi.loaded = 1;
}

static WValue m_midi_name(MIDIEndpointRef e) {
    CFStringRef s = NULL;
    char buf[256] = "";
    if (g_midi.strprop(e, *g_midi.name_key, &s) == noErr && s) {
        CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
        CFRelease(s);
    }
    return w_string(buf);
}

WValue w_media_midi_destinations(void) {
    m_midi_load("midi_destinations");
    WValue out = w_array_new_empty();
    ItemCount n = g_midi.n_dest();
    for (ItemCount i = 0; i < n; i++) out = w_array_push(out, m_midi_name(g_midi.get_dest(i)));
    return out;
}

WValue w_media_midi_sources(void) {
    m_midi_load("midi_sources");
    WValue out = w_array_new_empty();
    ItemCount n = g_midi.n_src();
    for (ItemCount i = 0; i < n; i++) out = w_array_push(out, m_midi_name(g_midi.get_src(i)));
    return out;
}

typedef struct AMidiOut {
    MIDIPortRef port;
    MIDIEndpointRef dest;      /* a destination, or 0 when virtual */
    MIDIEndpointRef vsrc;      /* our virtual source (index -1) */
} AMidiOut;

/* an output: to destination `index`, or (index < 0) a virtual source named `name` other programs can listen to */
WValue w_media_midi_out_open(WValue indexv, WValue namev) {
    m_midi_load("midi_out");
    int64_t idx = a_int(indexv, -1, "index");
    AMidiOut *o = calloc(1, sizeof *o);
    if (idx < 0) {
        char nm[256];
        if (!w_media_str(namev, nm, sizeof nm) || !nm[0]) strcpy(nm, "Tungsten");
        CFStringRef s = CFStringCreateWithCString(NULL, nm, kCFStringEncodingUTF8);
        OSStatus st = g_midi.source_create(g_midi.client, s, &o->vsrc);
        CFRelease(s);
        if (st != noErr) { free(o); w_media_raise("midi_out: MIDISourceCreate failed (%d)", (int)st); }
    } else {
        if ((ItemCount)idx >= g_midi.n_dest()) { free(o); w_media_raise("midi_out: no destination %lld", (long long)idx); }
        o->dest = g_midi.get_dest((ItemCount)idx);
        OSStatus st = g_midi.outport(g_midi.client, CFSTR("out"), &o->port);
        if (st != noErr) { free(o); w_media_raise("midi_out: MIDIOutputPortCreate failed (%d)", (int)st); }
    }
    return w_int(w_media_handle_new(o, W_MEDIA_KIND_MIDIOUT));
}

static MIDITimeStamp m_host_ticks(double s) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (MIDITimeStamp)(s * 1e9 * (double)tb.denom / (double)tb.numer);
}

/* a message scheduled for a host time (seconds, the clock of midi_now and of input timestamps; 0: now): CoreMIDI delivers
 * it then, so a sequence sent ahead keeps sample-accurate time */
WValue w_media_midi_send_at(WValue hv, WValue whenv, WValue bv) {
    AMidiOut *o = (AMidiOut *)w_media_handle_get(hv, W_MEDIA_KIND_MIDIOUT, "midi_send_at");
    double when = w_media_num(whenv, 0, "when");
    if (!w_is_array(bv)) w_media_raise("midi_send_at: the message is an array of 1 to 3 bytes");
    WArray *a = w_as_array(bv);
    Byte msg[3];
    int n = 0;
    for (int i = 0; i < a->size && i < 3; i++) msg[n++] = (Byte)w_media_num(a->slots[a->start + i], 0, "byte");
    if (n == 0) return W_FALSE;
    Byte buf[64];
    MIDIPacketList *pl = (MIDIPacketList *)buf;
    MIDIPacket *p = g_midi.pl_init(pl);
    p = g_midi.pl_add(pl, sizeof buf, p, when > 0 ? m_host_ticks(when) : 0, n, msg);
    if (!p) return W_FALSE;
    OSStatus st = o->vsrc ? g_midi.received(o->vsrc, pl) : g_midi.send(o->port, o->dest, pl);
    return st == noErr ? W_TRUE : W_FALSE;
}

/* drop what is scheduled and not yet delivered on an output (a stop, a jump) */
WValue w_media_midi_flush(WValue hv) {
    AMidiOut *o = (AMidiOut *)w_media_handle_get(hv, W_MEDIA_KIND_MIDIOUT, "midi_flush");
    typedef OSStatus (*flush_f)(MIDIEndpointRef);
    flush_f fl = (flush_f)dlsym(g_midi.lib, "MIDIFlushOutput");
    if (!fl || !o->dest) return W_FALSE;
    return fl(o->dest) == noErr ? W_TRUE : W_FALSE;
}

/* a message of 1 to 3 bytes now (b1, b2 < 0: left out) */
WValue w_media_midi_send(WValue hv, WValue b0v, WValue b1v, WValue b2v) {
    AMidiOut *o = (AMidiOut *)w_media_handle_get(hv, W_MEDIA_KIND_MIDIOUT, "midi_send");
    Byte msg[3];
    int n = 0;
    msg[n++] = (Byte)a_int(b0v, 0, "status");
    int64_t b1 = a_int(b1v, -1, "data1"), b2 = a_int(b2v, -1, "data2");
    if (b1 >= 0) msg[n++] = (Byte)b1;
    if (b2 >= 0) msg[n++] = (Byte)b2;
    Byte buf[64];
    MIDIPacketList *pl = (MIDIPacketList *)buf;
    MIDIPacket *p = g_midi.pl_init(pl);
    p = g_midi.pl_add(pl, sizeof buf, p, 0, n, msg);
    if (!p) return W_FALSE;
    OSStatus st = o->vsrc ? g_midi.received(o->vsrc, pl) : g_midi.send(o->port, o->dest, pl);
    return st == noErr ? W_TRUE : W_FALSE;
}

typedef struct AMidiIn {
    MIDIPortRef port;
    MIDIEndpointRef vdst;      /* our virtual destination (index -1) */
    os_unfair_lock lock;
    int32_t n, cap;
    struct { uint8_t b[3]; uint8_t len; double t; } *q;
} AMidiIn;

static void m_midi_read(const MIDIPacketList *pl, void *refcon, void *src) {
    (void)src;
    AMidiIn *in = (AMidiIn *)refcon;
    const MIDIPacket *p = &pl->packet[0];
    double now = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    os_unfair_lock_lock(&in->lock);
    for (UInt32 i = 0; i < pl->numPackets; i++) {
        /* the packet's own timestamp (the host clock), else its arrival */
        double pt = p->timeStamp ? (double)p->timeStamp * (double)tb.numer / (double)tb.denom / 1e9 : now;
        UInt16 k = 0;
        while (k < p->length) {
            uint8_t st = p->data[k];
            if (st < 0x80 || st >= 0xF0) { k++; continue; }   /* running status and system messages are skipped */
            int len = (st >= 0xC0 && st < 0xE0) ? 2 : 3;
            if (k + len > p->length) break;
            if (in->n == in->cap) {
                int32_t nc = in->cap ? in->cap * 2 : 256;
                void *nq = realloc(in->q, (size_t)nc * sizeof *in->q);
                if (!nq) break;
                in->q = nq;
                in->cap = nc;
            }
            in->q[in->n].b[0] = st;
            in->q[in->n].b[1] = p->data[k + 1];
            in->q[in->n].b[2] = len == 3 ? p->data[k + 2] : 0;
            in->q[in->n].len = (uint8_t)len;
            in->q[in->n].t = pt;
            in->n++;
            k += len;
        }
        p = MIDIPacketNext(p);
    }
    os_unfair_lock_unlock(&in->lock);
}

/* an input from source `index`, or (index < 0) a virtual destination named `name` other programs can send to */
WValue w_media_midi_in_open(WValue indexv, WValue namev) {
    m_midi_load("midi_in");
    int64_t idx = a_int(indexv, -1, "index");
    AMidiIn *in = calloc(1, sizeof *in);
    in->lock = OS_UNFAIR_LOCK_INIT;
    if (idx < 0) {
        char nm[256];
        if (!w_media_str(namev, nm, sizeof nm) || !nm[0]) strcpy(nm, "Tungsten In");
        CFStringRef s = CFStringCreateWithCString(NULL, nm, kCFStringEncodingUTF8);
        OSStatus st = g_midi.dest_create(g_midi.client, s, (MIDIReadProc)m_midi_read, in, &in->vdst);
        CFRelease(s);
        if (st != noErr) { free(in); w_media_raise("midi_in: MIDIDestinationCreate failed (%d)", (int)st); }
    } else {
        if ((ItemCount)idx >= g_midi.n_src()) { free(in); w_media_raise("midi_in: no source %lld", (long long)idx); }
        OSStatus st = g_midi.inport(g_midi.client, CFSTR("in"), (MIDIReadProc)m_midi_read, in, &in->port);
        if (st != noErr) { free(in); w_media_raise("midi_in: MIDIInputPortCreate failed (%d)", (int)st); }
        g_midi.connect(in->port, g_midi.get_src((ItemCount)idx), NULL);
    }
    return w_int(w_media_handle_new(in, W_MEDIA_KIND_MIDIIN));
}

/* the messages received since the last read: [[status, data1, data2, seconds (uptime)], …] */
WValue w_media_midi_read(WValue hv) {
    AMidiIn *in = (AMidiIn *)w_media_handle_get(hv, W_MEDIA_KIND_MIDIIN, "midi_read");
    WValue out = w_array_new_empty();
    os_unfair_lock_lock(&in->lock);
    for (int32_t i = 0; i < in->n; i++) {
        WValue e = w_array_new_empty();
        e = w_array_push(e, w_int(in->q[i].b[0]));
        e = w_array_push(e, w_int(in->q[i].b[1]));
        e = w_array_push(e, w_int(in->q[i].b[2]));
        e = w_array_push(e, w_float(in->q[i].t));
        out = w_array_push(out, e);
    }
    in->n = 0;
    os_unfair_lock_unlock(&in->lock);
    return out;
}

WValue w_media_midi_close(WValue hv) {
    void *o = m_avf_peek(hv, W_MEDIA_KIND_MIDIOUT);
    if (o) {
        AMidiOut *mo = (AMidiOut *)o;
        w_media_handle_drop(hv, W_MEDIA_KIND_MIDIOUT);
        if (mo->vsrc && g_midi.ep_dispose) g_midi.ep_dispose(mo->vsrc);
        if (mo->port && g_midi.port_dispose) g_midi.port_dispose(mo->port);
        free(mo);
        return W_TRUE;
    }
    void *i = m_avf_peek(hv, W_MEDIA_KIND_MIDIIN);
    if (i) {
        AMidiIn *mi = (AMidiIn *)i;
        w_media_handle_drop(hv, W_MEDIA_KIND_MIDIIN);
        if (mi->vdst && g_midi.ep_dispose) g_midi.ep_dispose(mi->vdst);
        if (mi->port && g_midi.port_dispose) g_midi.port_dispose(mi->port);
        /* the read proc may still be running once: the queue is left allocated (a few KB) */
        return W_TRUE;
    }
    return W_FALSE;
}

/* ---- the live sampler (version 2, 2026-11-04: streaming, scheduled, sinc-interpolated) ----
 *
 * Zones are samples: an audio file (FLAC, WAV, AIFF … read by ExtAudioFile: its head in memory, the rest streamed by a reader
 * thread into each voice's ring as the voice plays), a raw PCM cache (memory-mapped: "TWPCM\0\0\2", rate (i64), frames (i64),
 * int32 stereo interleaved), or PCM handed over (the first API: live_zone with key ranges). The program chooses the zone,
 * pitch ratio and gain of every note (the sound engine's own choice: sampler.w sfz_pick / prr_pick) and schedules it at a host
 * time (the clock MIDI timestamps use); the render thread starts it at that frame. Voices play as sampler.w's play() does: a
 * 64-tap windowed sinc (the table handed over with live_sinc, else linear), a fade-in of 29 samples at 48 kHz, an exponential
 * release with the zone's time constant, a 20 ms fade before the file ends. Pitch bend and a vibrato apply to every voice. */

#include <AudioToolbox/ExtendedAudioFile.h>
#include <stdatomic.h>
#include <sys/mman.h>

/* 256 voices (2026-11-04 night: a whole score in real time, a pedalled piano with an ensemble; 96 was one instrument's) */
#define L_VOICES 256

/* element i of an f64[] or f32[] argument, and its length */
static double a_f64_at(WValue a, int64_t i, const char *what, int64_t *n) {
    (void)what;
    WArray *arr = w_as_array(a);
    *n = arr->size;
    if (i >= arr->size) return 0;
    if (arr->ebits == -64) return ((double *)arr->slots)[arr->start + i];
    if (arr->ebits == -32) return ((float *)arr->slots)[arr->start + i];
    return 0;
}

#define LV_RING 32768
#define LV_RING_PAD 64
#define LV_HEAD_MAX 262144
#define LV_EVENTS 4096
#define LV_DUE_MAX 512
#define LV_ZONE_PAGE_SHIFT 8
#define LV_ZONE_PAGE_SIZE (1 << LV_ZONE_PAGE_SHIFT)
#define LV_ZONE_MAX_PAGES 256
#define LV_READERS 2

typedef struct LZoneF {
    int kind;                  /* 1 file (streamed), 2 raw mmap, 3 memory */
    char path[1024];
    double rate;
    int64_t frames, head_n, first;
    float *hl, *hr;            /* kind 1: the head (+64 overlap); kind 3: everything; [-32..-1] and [end..end+63] zero-padded */
    float *hl_alloc, *hr_alloc;
    const int32_t *raw;        /* kind 2: interleaved stereo int32 (x · 2^31 − 1) */
    size_t raw_len;
    int lo, hi, vlo, vhi, root;
    double gain;
    int64_t loop_s, loop_e;
} LZoneF;

typedef struct LVoiceF {
    _Atomic int state;         /* 0 free, 1 sounding, 2 releasing */
    _Atomic int64_t gen;       /* bumped at every start: the reader thread reopens */
    int zone, key;
    int64_t tag;
    double pos, ratio, amp, env, er, origin;
    int64_t age;
    int started;
    /* streaming (kind 1) */
    float *rl, *rr;            /* LV_RING + LV_RING_PAD: [LV_RING..LV_RING+63] mirrors [0..63] */
    _Atomic int64_t ring_end;  /* the file frame after the last one in the ring */
    _Atomic int64_t rpos;      /* the reader's floor(pos), for the writer */
    int64_t open_gen;          /* the reader thread's: the generation its file is open for */
    ExtAudioFileRef ef;
    int eof;
} LVoiceF;

typedef struct LEvent {
    int type;                  /* 1 play, 2 release, 3 bend, 4 all off, 5 flush+release */
    double when, origin;
    int zone, key;
    int64_t tag;
    double ratio, amp, start, rel, cents;
} LEvent;

struct ALive;
typedef struct LVReaderArg {
    struct ALive *L;
    int tid;
} LVReaderArg;

typedef struct ALive {
    AVAudioEngine *engine;
    AVAudioSourceNode *node;
    double rate;
    os_unfair_lock prod_lock;  /* producer-only lock (never acquired by render callback or reader threads) */
    _Atomic int nz;
    _Atomic(LZoneF *) z_pages[LV_ZONE_MAX_PAGES];
    LVoiceF v[L_VOICES];
    /* Lock-free producer -> render-callback FIFO + render-callback-owned scheduled list */
    LEvent ev_ring[LV_EVENTS];
    _Atomic uint32_t ev_w;
    _Atomic uint32_t ev_r;
    LEvent sched[LV_EVENTS];
    int nsched;
    float volume;
    _Atomic int64_t rendered;
    double bend_mult, vib_depth, vib_rate, vib_phase;
    _Atomic(float *) sinc;     /* (512 + 1) * 64 taps, or NULL */
    float *sinc_retired[16];
    int n_sinc_retired;
    int64_t next_tag;
    /* measurements */
    _Atomic int64_t underruns;
    /* the render callback's own time (its load): seconds spent in it, seconds of audio it made, the worst buffer's share, and
     * the most voices sounding at once */
    double cb_sum, buf_sum, cb_max;
    int voices_max;
    double lat_sum, lat_max, lat_last;
    int64_t lat_n;
    int64_t head_bytes, map_bytes;
    pthread_t readers[LV_READERS];
    LVReaderArg reader_args[LV_READERS];
    _Atomic int quit;
    int buf_frames;
} ALive;

static double lv_now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9; }

static double lv_host_s(uint64_t ht) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)ht * (double)tb.numer / (double)tb.denom / 1e9;
}

static inline LZoneF *lv_zone_at(ALive *L, int idx) {
    if (idx < 0) return NULL;
    int p = idx >> LV_ZONE_PAGE_SHIFT;
    if (p >= LV_ZONE_MAX_PAGES) return NULL;
    LZoneF *pg = atomic_load_explicit(&L->z_pages[p], memory_order_acquire);
    return pg ? &pg[idx & (LV_ZONE_PAGE_SIZE - 1)] : NULL;
}

/* frame q of a voice's zone (0 when it is not there yet: an underrun) */
static inline void lv_frame(ALive *L, LVoiceF *v, LZoneF *z, int64_t q, float *a, float *b) {
    if (q < 0 || q >= z->frames) { *a = 0; *b = 0; return; }
    if (z->kind == 3 || (z->kind == 1 && q < z->head_n)) { *a = z->hl[q]; *b = z->hr[q]; return; }
    if (z->kind == 2) { *a = (float)z->raw[2 * q] * (1.0f / 2147483647.0f); *b = (float)z->raw[2 * q + 1] * (1.0f / 2147483647.0f); return; }
    int64_t e = atomic_load_explicit(&v->ring_end, memory_order_acquire);
    if (q < e && q >= e - LV_RING) { int64_t i = q & (LV_RING - 1); *a = v->rl[i]; *b = v->rr[i]; return; }
    atomic_fetch_add(&L->underruns, 1);
    *a = 0; *b = 0;
}

static int lv_voice_free(ALive *L) {
    for (int i = 0; i < L_VOICES; i++) if (atomic_load(&L->v[i].state) == 0) return i;
    /* steal the oldest releasing voice, else the oldest */
    int best = -1; int64_t age = -1;
    for (int i = 0; i < L_VOICES; i++) if (atomic_load(&L->v[i].state) == 2 && L->v[i].age > age) { best = i; age = L->v[i].age; }
    if (best >= 0) return best;
    for (int i = 0; i < L_VOICES; i++) if (L->v[i].age > age) { best = i; age = L->v[i].age; }
    return best >= 0 ? best : 0;
}

static void lv_apply(ALive *L, LEvent *e, double t_out) {
    if (e->type == 1) {
        int cur_nz = atomic_load_explicit(&L->nz, memory_order_acquire);
        if (e->zone < 0 || e->zone >= cur_nz) return;
        LZoneF *z = lv_zone_at(L, e->zone);
        if (!z) return;
        int vi = lv_voice_free(L);
        LVoiceF *v = &L->v[vi];
        v->zone = e->zone; v->key = e->key; v->tag = e->tag;
        v->pos = e->start; v->ratio = e->ratio; v->amp = e->amp; v->env = 1.0;
        v->er = exp(-1.0 / ((e->rel > 0.001 ? e->rel : 0.001) * L->rate));
        v->origin = e->origin; v->age = 0; v->started = 0;
        if (z->kind == 1) atomic_store_explicit(&v->ring_end, z->head_n, memory_order_release);
        atomic_store(&v->rpos, (int64_t)e->start);
        atomic_fetch_add(&v->gen, 1);
        atomic_store(&v->state, 1);
        (void)t_out;
    } else if (e->type == 2) {
        for (int i = 0; i < L_VOICES; i++) {
            LVoiceF *v = &L->v[i];
            if (atomic_load(&v->state) == 1 && (e->tag == 0 || v->tag == e->tag)) {
                if (e->rel > 0) v->er = exp(-1.0 / (e->rel * L->rate));
                atomic_store(&v->state, 2);
            }
        }
    } else if (e->type == 3) {
        L->bend_mult = pow(2.0, e->cents / 1200.0);
    } else if (e->type == 4) {
        for (int i = 0; i < L_VOICES; i++) if (atomic_load(&L->v[i].state) != 0) atomic_store(&L->v[i].state, 2);
    }
}

static void lv_render_span(ALive *L, float *ol, float *orr, int i0, int i1, double hs) {
    double fin_n = 29.0 * L->rate / 48000.0, fe_n = 0.02 * L->rate;
    double pitch_mod = L->bend_mult;
    if (L->vib_depth > 0) pitch_mod *= pow(2.0, L->vib_depth * sin(L->vib_phase) / 1200.0);
    const float *sinc_tab = atomic_load_explicit(&L->sinc, memory_order_acquire);
    for (int vi = 0; vi < L_VOICES; vi++) {
        LVoiceF *v = &L->v[vi];
        int st = atomic_load_explicit(&v->state, memory_order_acquire);
        if (st == 0) continue;
        LZoneF *z = lv_zone_at(L, v->zone);
        if (!z) continue;
        double base = z->rate / L->rate;
        double step = v->ratio * base * pitch_mod;
        double fe_span = fe_n * step;
        double inv_fe_span = fe_span > 0.0 ? 1.0 / fe_span : 0.0;
        int64_t ring_e = z->kind == 1 ? atomic_load_explicit(&v->ring_end, memory_order_acquire) : 0;
        for (int i = i0; i < i1; i++) {
            double p = floor(v->pos);
            int64_t k = (int64_t)p;
            if (k + 32 >= z->frames) { atomic_store(&v->state, 0); break; }
            if (!v->started) {
                v->started = 1;
                double lat = hs + (double)i / L->rate - v->origin;
                if (v->origin > 0 && lat > -1 && lat < 10) {
                    L->lat_last = lat; L->lat_sum += lat; L->lat_n++;
                    if (lat > L->lat_max) L->lat_max = lat;
                }
            }
            float yl = 0, yr = 0;
            if (sinc_tab) {
                double pf = (v->pos - p) * 512.0;
                double pfl = floor(pf);
                int b0 = (int)pfl * 64;
                float u = (float)(pf - pfl);
                int64_t q0 = k - 31;
                const float *s0 = sinc_tab + b0;
                const float *s1 = s0 + 64;
#if defined(__aarch64__)
                float32x4_t vu = vdupq_n_f32(u);
                if (q0 >= -32 && (z->kind == 3 || (z->kind == 1 && (q0 < z->head_n || z->head_n >= z->frames)))) {
                    /* Guard-padded head/memory buffer covers [-32..-1] (zeros) and [head_n..head_n+63] (64-frame overlap or zeros) */
                    const float *hl = z->hl + q0, *hr = z->hr + q0;
                    float32x4_t al0 = vdupq_n_f32(0.0f), ar0 = vdupq_n_f32(0.0f);
                    float32x4_t al1 = vdupq_n_f32(0.0f), ar1 = vdupq_n_f32(0.0f);
                    for (int j = 0; j < 64; j += 8) {
                        float32x4_t t0 = vld1q_f32(s0 + j), t1 = vld1q_f32(s1 + j);
                        float32x4_t c0 = vfmaq_f32(t0, vsubq_f32(t1, t0), vu);
                        float32x4_t u0 = vld1q_f32(s0 + j + 4), u1 = vld1q_f32(s1 + j + 4);
                        float32x4_t c1 = vfmaq_f32(u0, vsubq_f32(u1, u0), vu);
                        al0 = vfmaq_f32(al0, vld1q_f32(hl + j), c0);
                        ar0 = vfmaq_f32(ar0, vld1q_f32(hr + j), c0);
                        al1 = vfmaq_f32(al1, vld1q_f32(hl + j + 4), c1);
                        ar1 = vfmaq_f32(ar1, vld1q_f32(hr + j + 4), c1);
                    }
                    yl = vaddvq_f32(vaddq_f32(al0, al1));
                    yr = vaddvq_f32(vaddq_f32(ar0, ar1));
                } else if (z->kind == 2) {
                    int32_t pad[128];
                    const int32_t *rp;
                    if (q0 >= 0 && q0 + 64 <= z->frames) {
                        rp = z->raw + 2 * q0;
                    } else {
                        memset(pad, 0, sizeof pad);
                        int64_t a = q0 < 0 ? -q0 : 0;
                        int64_t b = (z->frames - q0) < 64 ? (z->frames - q0) : 64;
                        if (a < 0) a = 0;
                        if (b > a) memcpy(pad + 2 * a, z->raw + 2 * (q0 + a), (size_t)(b - a) * 8);
                        rp = pad;
                    }
                    float32x4_t al0 = vdupq_n_f32(0.0f), ar0 = vdupq_n_f32(0.0f);
                    float32x4_t al1 = vdupq_n_f32(0.0f), ar1 = vdupq_n_f32(0.0f);
                    for (int j = 0; j < 64; j += 8) {
                        float32x4_t t0 = vld1q_f32(s0 + j), t1 = vld1q_f32(s1 + j);
                        float32x4_t c0 = vfmaq_f32(t0, vsubq_f32(t1, t0), vu);
                        float32x4_t u0 = vld1q_f32(s0 + j + 4), u1 = vld1q_f32(s1 + j + 4);
                        float32x4_t c1 = vfmaq_f32(u0, vsubq_f32(u1, u0), vu);
                        int32x4x2_t p0 = vld2q_s32(rp + 2 * j);
                        int32x4x2_t p1 = vld2q_s32(rp + 2 * (j + 4));
                        al0 = vfmaq_f32(al0, vcvtq_f32_s32(p0.val[0]), c0);
                        ar0 = vfmaq_f32(ar0, vcvtq_f32_s32(p0.val[1]), c0);
                        al1 = vfmaq_f32(al1, vcvtq_f32_s32(p1.val[0]), c1);
                        ar1 = vfmaq_f32(ar1, vcvtq_f32_s32(p1.val[1]), c1);
                    }
                    yl = vaddvq_f32(vaddq_f32(al0, al1)) * (1.0f / 2147483647.0f);
                    yr = vaddvq_f32(vaddq_f32(ar0, ar1)) * (1.0f / 2147483647.0f);
                } else if (z->kind == 1 && q0 >= z->head_n) {
                    if (q0 + 64 > ring_e) ring_e = atomic_load_explicit(&v->ring_end, memory_order_acquire);
                    if (q0 >= ring_e - LV_RING && q0 + 64 <= ring_e) {
                        /* v->rl / v->rr mirror [0..63] into [LV_RING..LV_RING+63], so 64-tap NEON never wraps */
                        int64_t ri = q0 & (LV_RING - 1);
                        const float *rl = v->rl + ri, *rr = v->rr + ri;
                        float32x4_t al0 = vdupq_n_f32(0.0f), ar0 = vdupq_n_f32(0.0f);
                        float32x4_t al1 = vdupq_n_f32(0.0f), ar1 = vdupq_n_f32(0.0f);
                        for (int j = 0; j < 64; j += 8) {
                            float32x4_t t0 = vld1q_f32(s0 + j), t1 = vld1q_f32(s1 + j);
                            float32x4_t c0 = vfmaq_f32(t0, vsubq_f32(t1, t0), vu);
                            float32x4_t u0 = vld1q_f32(s0 + j + 4), u1 = vld1q_f32(s1 + j + 4);
                            float32x4_t c1 = vfmaq_f32(u0, vsubq_f32(u1, u0), vu);
                            al0 = vfmaq_f32(al0, vld1q_f32(rl + j), c0);
                            ar0 = vfmaq_f32(ar0, vld1q_f32(rr + j), c0);
                            al1 = vfmaq_f32(al1, vld1q_f32(rl + j + 4), c1);
                            ar1 = vfmaq_f32(ar1, vld1q_f32(rr + j + 4), c1);
                        }
                        yl = vaddvq_f32(vaddq_f32(al0, al1));
                        yr = vaddvq_f32(vaddq_f32(ar0, ar1));
                    } else {
                        for (int j = 0; j < 64; j++) {
                            float a, b;
                            lv_frame(L, v, z, q0 + j, &a, &b);
                            float c = s0[j] + u * (s1[j] - s0[j]);
                            yl += a * c; yr += b * c;
                        }
                    }
                } else
#endif
                {
                    if (z->kind == 1 && q0 + 64 > ring_e) ring_e = atomic_load_explicit(&v->ring_end, memory_order_acquire);
                    for (int j = 0; j < 64; j++) {
                        float a, b;
                        lv_frame(L, v, z, q0 + j, &a, &b);
                        float c = s0[j] + u * (s1[j] - s0[j]);
                        yl += a * c; yr += b * c;
                    }
                }
            } else {
                float a0, b0, a1, b1;
                lv_frame(L, v, z, k, &a0, &b0);
                lv_frame(L, v, z, k + 1, &a1, &b1);
                float fr = (float)(v->pos - p);
                yl = a0 + (a1 - a0) * fr; yr = b0 + (b1 - b0) * fr;
            }
            if (st == 2) {
                v->env *= v->er;
                if (v->env < 0.0001) { atomic_store(&v->state, 0); break; }
            }
            double fi = v->age < fin_n ? (double)v->age / fin_n : 1.0;
            double fe = 1.0, left = (double)(z->frames - 33) - v->pos;
            if (left < fe_span) { fe = left * inv_fe_span; if (fe < 0) fe = 0; }
            double w = v->amp * v->env * fi * fe * L->volume;
            ol[i] += (float)(yl * w);
            if (orr != ol) orr[i] += (float)(yr * w);
            v->pos += step;
            v->age++;
        }
        atomic_store(&v->rpos, (int64_t)v->pos);
    }
}

static void *lv_reader(void *arg) {
    LVReaderArg *ra = (LVReaderArg *)arg;
    ALive *L = ra->L;
    int tid = ra->tid;
    float tmp[2 * 4096];
    while (!atomic_load_explicit(&L->quit, memory_order_acquire)) {
        int cur_nz = atomic_load_explicit(&L->nz, memory_order_acquire);
        int best_vi = -1;
        int64_t best_slack = INT64_MAX;
        int64_t best_g = 0;
        for (int vi = tid; vi < L_VOICES; vi += LV_READERS) {
            LVoiceF *v = &L->v[vi];
            int st = atomic_load_explicit(&v->state, memory_order_acquire);
            int64_t g = atomic_load_explicit(&v->gen, memory_order_acquire);
            if (v->ef && (st == 0 || v->open_gen != g)) { ExtAudioFileDispose(v->ef); v->ef = NULL; }
            if (st == 0) continue;
            int zi = v->zone;
            LZoneF *z = (zi >= 0 && zi < cur_nz) ? lv_zone_at(L, zi) : NULL;
            if (!z || z->kind != 1 || z->head_n >= z->frames) continue;
            if (!v->ef) {
                CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)z->path, (CFIndex)strlen(z->path), false);
                OSStatus os = ExtAudioFileOpenURL(u, &v->ef);
                CFRelease(u);
                if (os != noErr) { v->ef = NULL; continue; }
                AudioStreamBasicDescription c;
                memset(&c, 0, sizeof c);
                c.mSampleRate = z->rate; c.mFormatID = kAudioFormatLinearPCM;
                c.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
                c.mChannelsPerFrame = 2; c.mBitsPerChannel = 32; c.mBytesPerFrame = 8; c.mFramesPerPacket = 1; c.mBytesPerPacket = 8;
                ExtAudioFileSetProperty(v->ef, kExtAudioFileProperty_ClientDataFormat, sizeof c, &c);
                ExtAudioFileSeek(v->ef, z->head_n);
                v->open_gen = g;
                v->eof = 0;
            }
            if (v->eof) continue;
            int64_t e = atomic_load_explicit(&v->ring_end, memory_order_acquire);
            if (e >= z->frames) { v->eof = 1; continue; }
            int64_t rp = atomic_load_explicit(&v->rpos, memory_order_relaxed);
            /* Frames below head_n are served from z->hl, so the ring only needs history >= max(head_n, rp - 64) */
            int64_t floor_q = (rp - 64 > z->head_n) ? (rp - 64) : z->head_n;
            if (e + 4096 - LV_RING <= floor_q) {
                int64_t play_q = rp > z->head_n ? rp : z->head_n;
                int64_t slack = e - play_q;
                if (slack < best_slack) {
                    best_slack = slack;
                    best_vi = vi;
                    best_g = g;
                }
            }
        }
        if (best_vi >= 0) {
            LVoiceF *v = &L->v[best_vi];
            if (atomic_load_explicit(&v->gen, memory_order_acquire) == best_g && v->ef && !v->eof) {
                int64_t e = atomic_load_explicit(&v->ring_end, memory_order_acquire);
                UInt32 n = 4096;
                AudioBufferList abl;
                abl.mNumberBuffers = 1;
                abl.mBuffers[0].mNumberChannels = 2;
                abl.mBuffers[0].mDataByteSize = sizeof tmp;
                abl.mBuffers[0].mData = tmp;
                if (ExtAudioFileRead(v->ef, &n, &abl) != noErr || n == 0) {
                    v->eof = 1;
                } else {
                    UInt32 i = 0;
                    int64_t q0 = e & (LV_RING - 1);
#if defined(__aarch64__)
                    if (q0 + (int64_t)n <= LV_RING) {
                        for (; i + 4 <= n; i += 4) {
                            float32x4x2_t lr = vld2q_f32(tmp + 2 * i);
                            vst1q_f32(v->rl + q0 + i, lr.val[0]);
                            vst1q_f32(v->rr + q0 + i, lr.val[1]);
                        }
                    }
#endif
                    for (; i < n; i++) {
                        int64_t q = (e + i) & (LV_RING - 1);
                        v->rl[q] = tmp[2 * i];
                        v->rr[q] = tmp[2 * i + 1];
                    }
                    if (q0 < LV_RING_PAD || q0 + (int64_t)n > LV_RING) {
                        memcpy(v->rl + LV_RING, v->rl, LV_RING_PAD * sizeof(float));
                        memcpy(v->rr + LV_RING, v->rr, LV_RING_PAD * sizeof(float));
                    }
                    e += n;
                    atomic_store_explicit(&v->ring_end, e, memory_order_release);
                }
            }
        } else {
            usleep(1000);
        }
    }
    return NULL;
}

WValue w_media_live_new(WValue ratev) {
    @autoreleasepool {
        ALive *L = calloc(1, sizeof *L);
        L->prod_lock = OS_UNFAIR_LOCK_INIT;
        L->volume = 1.0f;
        L->bend_mult = 1.0;
        L->vib_rate = 5.5;
        L->next_tag = 1;
        for (int i = 0; i < L_VOICES; i++) {
            L->v[i].rl = calloc(LV_RING + LV_RING_PAD, sizeof(float));
            L->v[i].rr = calloc(LV_RING + LV_RING_PAD, sizeof(float));
            L->v[i].zone = -1;
            L->v[i].open_gen = -1;
        }
        L->engine = [[AVAudioEngine alloc] init];
        AVAudioFormat *out = [L->engine.outputNode outputFormatForBus:0];
        double rate = out.sampleRate > 0 ? out.sampleRate : a_num(ratev);
        if (rate <= 0) rate = 48000;
        L->rate = rate;
        AVAudioFormat *fmt = [[[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:2] autorelease];
        ALive *Lp = L;
        L->node = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount n, AudioBufferList *abl) {
            double cb0 = lv_now();
            float *ol = (float *)abl->mBuffers[0].mData;
            float *orr = abl->mNumberBuffers > 1 ? (float *)abl->mBuffers[1].mData : ol;
            memset(ol, 0, n * sizeof(float));
            if (orr != ol) memset(orr, 0, n * sizeof(float));
            Lp->buf_frames = (int)n;
            double hs = (ts && (ts->mFlags & kAudioTimeStampHostTimeValid)) ? lv_host_s(ts->mHostTime) : lv_now();
            double he = hs + (double)n / Lp->rate;
            /* Drain lock-free producer ring in FIFO order */
            uint32_t r = atomic_load_explicit(&Lp->ev_r, memory_order_relaxed);
            uint32_t w = atomic_load_explicit(&Lp->ev_w, memory_order_acquire);
            while (r != w) {
                LEvent ev = Lp->ev_ring[r & (LV_EVENTS - 1)];
                r++;
                if (ev.type == 5) {
                    Lp->nsched = 0;
                    ev.type = 2;
                    ev.tag = 0;
                }
                if (Lp->nsched < LV_EVENTS) Lp->sched[Lp->nsched++] = ev;
            }
            atomic_store_explicit(&Lp->ev_r, r, memory_order_release);
            /* Partition events due in this buffer, in time order, each at its frame */
            LEvent due[LV_DUE_MAX];
            int nd = 0, sw = 0;
            for (int i = 0; i < Lp->nsched; i++) {
                if (Lp->sched[i].when < he && nd < LV_DUE_MAX) due[nd++] = Lp->sched[i];
                else Lp->sched[sw++] = Lp->sched[i];
            }
            Lp->nsched = sw;
            for (int i = 1; i < nd; i++) { LEvent t = due[i]; int j = i; while (j > 0 && due[j - 1].when > t.when) { due[j] = due[j - 1]; j--; } due[j] = t; }
            int at = 0;
            for (int k = 0; k < nd; k++) {
                int off = (int)((due[k].when - hs) * Lp->rate);
                if (off < at) off = at;
                if (off > (int)n) off = (int)n;
                if (off > at) { lv_render_span(Lp, ol, orr, at, off, hs); at = off; }
                lv_apply(Lp, &due[k], hs + (double)off / Lp->rate);
            }
            if (at < (int)n) lv_render_span(Lp, ol, orr, at, (int)n, hs);
            if (Lp->vib_depth > 0) {
                Lp->vib_phase += 2 * M_PI * Lp->vib_rate * (double)n / Lp->rate;
                if (Lp->vib_phase > 2 * M_PI) Lp->vib_phase -= 2 * M_PI;
            }
            atomic_fetch_add(&Lp->rendered, n);
            {
                int nv = 0;
                for (int i = 0; i < L_VOICES; i++) if (atomic_load_explicit(&Lp->v[i].state, memory_order_relaxed)) nv++;
                if (nv > Lp->voices_max) Lp->voices_max = nv;
                double dt = lv_now() - cb0, bd = (double)n / Lp->rate;
                Lp->cb_sum += dt;
                Lp->buf_sum += bd;
                if (bd > 0 && dt / bd > Lp->cb_max) Lp->cb_max = dt / bd;
            }
            (void)silence;
            return noErr;
        }];
        [L->engine attachNode:L->node];
        [L->engine connect:L->node to:L->engine.mainMixerNode format:fmt];
        /* small output buffers for this program's IO (a live instrument): 256 frames (2.7 ms at 96 kHz, 5.3 at 48) */
        AudioUnit au = L->engine.outputNode.audioUnit;
        if (au) {
            UInt32 bf = 256;
            AudioUnitSetProperty(au, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bf, sizeof bf);
        }
        NSError *err = nil;
        if (![L->engine startAndReturnError:&err]) {
            for (int i = 0; i < L_VOICES; i++) { free(L->v[i].rl); free(L->v[i].rr); }
            [L->node release];
            [L->engine release];
            free(L);
            w_media_raise("live_new: the audio engine did not start: %s", err ? [[err localizedDescription] UTF8String] : "?");
        }
        for (int t = 0; t < LV_READERS; t++) {
            L->reader_args[t].L = L;
            L->reader_args[t].tid = t;
            pthread_create(&L->readers[t], NULL, lv_reader, &L->reader_args[t]);
        }
        return w_int(w_media_handle_new(L, W_MEDIA_KIND_LIVE));
    }
}

static int lv_add_zones_batch(ALive *L, LZoneF *zs, int count) {
    os_unfair_lock_lock(&L->prod_lock);
    int base_idx = atomic_load_explicit(&L->nz, memory_order_relaxed);
    if (base_idx + count > LV_ZONE_MAX_PAGES * LV_ZONE_PAGE_SIZE) {
        os_unfair_lock_unlock(&L->prod_lock);
        w_media_raise("live_zone: zone limit (%d) exceeded", LV_ZONE_MAX_PAGES * LV_ZONE_PAGE_SIZE);
    }
    for (int i = 0; i < count; i++) {
        int idx = base_idx + i;
        int p = idx >> LV_ZONE_PAGE_SHIFT;
        LZoneF *pg = atomic_load_explicit(&L->z_pages[p], memory_order_relaxed);
        if (!pg) {
            pg = calloc(LV_ZONE_PAGE_SIZE, sizeof(LZoneF));
            atomic_store_explicit(&L->z_pages[p], pg, memory_order_release);
        }
        pg[idx & (LV_ZONE_PAGE_SIZE - 1)] = zs[i];
    }
    atomic_store_explicit(&L->nz, base_idx + count, memory_order_release);
    os_unfair_lock_unlock(&L->prod_lock);
    return base_idx;
}

static int lv_add_zone(ALive *L, LZoneF *z) {
    return lv_add_zones_batch(L, z, 1);
}

static int64_t lv_first_sound(const float *l, const float *r, int64_t n, int64_t stride, double rate) {
    (void)rate;
    int64_t i = 0;
#if defined(__aarch64__)
    if (stride == 1) {
        for (; i + 4 <= n; i += 4) {
            float32x4_t m = vmaxq_f32(vabsq_f32(vld1q_f32(l + i)), vabsq_f32(vld1q_f32(r + i)));
            if (vmaxvq_f32(m) > 0.0016f) break;
        }
    }
#endif
    for (; i < n; i++) {
        float a = fabsf(l[i * stride]), b = fabsf(r[i * stride]);
        if (a > 0.0016f || b > 0.0016f) return i - 48 < 0 ? 0 : i - 48;
    }
    return 0;
}

/* the first API: PCM handed over with a key mapping (live_note plays it) */
WValue w_media_live_zone(WValue hv, WValue kv, WValue lv, WValue rv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_zone");
    if (!w_is_array(kv) || !w_is_array(lv) || !w_is_array(rv)) w_media_raise("live_zone: the keys and the two channels are arrays");
    WArray *k = w_as_array(kv);
    if (k->size < 10) w_media_raise("live_zone: [lo, hi, vlo, vhi, root, frames, rate, loop start, loop end, gain]");
    double f[10];
    for (int i = 0; i < 10; i++) f[i] = w_media_num(k->slots[k->start + i], 0, "live_zone");
    int64_t nl = 0, nr = 0;
    (void)a_f64_at(lv, 0, "l", &nl);
    (void)a_f64_at(rv, 0, "r", &nr);
    int64_t frames = (int64_t)f[5];
    if (frames > nl) frames = nl;
    if (frames > nr) frames = nr;
    if (frames < 2) w_media_raise("live_zone: no sample data");
    LZoneF z;
    memset(&z, 0, sizeof z);
    z.kind = 3;
    z.lo = (int)f[0]; z.hi = (int)f[1]; z.vlo = (int)f[2]; z.vhi = (int)f[3]; z.root = (int)f[4];
    z.frames = frames; z.head_n = frames; z.rate = f[6] > 0 ? f[6] : 48000; z.loop_s = (int64_t)f[7]; z.loop_e = (int64_t)f[8]; z.gain = f[9];
    z.hl_alloc = calloc((size_t)(32 + frames + 64), sizeof(float));
    z.hr_alloc = calloc((size_t)(32 + frames + 64), sizeof(float));
    z.hl = z.hl_alloc + 32;
    z.hr = z.hr_alloc + 32;
    for (int64_t i = 0; i < frames; i++) { int64_t d; z.hl[i] = (float)a_f64_at(lv, i, "l", &d); z.hr[i] = (float)a_f64_at(rv, i, "r", &d); }
    z.first = 0;
    L->head_bytes += frames * 8;
    return w_int(lv_add_zone(L, &z));
}

static int lv_load_zone_one(const char *path, int64_t hn, LZoneF *z, int64_t *head_b, int64_t *map_b, char *err, size_t errcap) {
    @autoreleasepool {
        memset(z, 0, sizeof *z);
        *head_b = 0;
        *map_b = 0;
        size_t pl = strlen(path);
        if (pl > 6 && strcmp(path + pl - 6, ".twpcm") == 0) {
            int fd = open(path, O_RDONLY);
            if (fd < 0) { snprintf(err, errcap, "live_zone_file: %s: cannot open", path); return -1; }
            struct stat sb;
            fstat(fd, &sb);
            void *m = mmap(NULL, (size_t)sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
            close(fd);
            if (m == MAP_FAILED || sb.st_size < 24 || memcmp(m, "TWPCM\0\0\2", 8) != 0) {
                if (m != MAP_FAILED) munmap(m, (size_t)sb.st_size);
                snprintf(err, errcap, "live_zone_file: %s: not a PCM cache", path);
                return -1;
            }
            z->kind = 2;
            int64_t ir = 0;
            memcpy(&ir, (char *)m + 8, 8);
            z->rate = (double)ir;
            memcpy(&z->frames, (char *)m + 16, 8);
            int64_t max_fr = ((int64_t)sb.st_size - 24) / 8;
            if (z->frames > max_fr) z->frames = max_fr;
            if (z->frames < 0) z->frames = 0;
            z->raw = (const int32_t *)((char *)m + 24);
            z->raw_len = (size_t)sb.st_size;
            z->head_n = z->frames;
            z->first = 0;
            int64_t scan_lim = z->frames < 96000 ? z->frames : 96000;
            int64_t i = 0;
#if defined(__aarch64__)
            for (; i + 4 <= scan_lim; i += 4) {
                int32x4_t a0 = vqabsq_s32(vld1q_s32(z->raw + 2 * i));
                int32x4_t a1 = vqabsq_s32(vld1q_s32(z->raw + 2 * i + 4));
                if (vmaxvq_s32(vmaxq_s32(a0, a1)) > 3436202) break;
            }
#endif
            for (; i < scan_lim; i++) {
                int64_t l0 = z->raw[2 * i], r0 = z->raw[2 * i + 1];
                if (l0 < 0) l0 = -l0;
                if (r0 < 0) r0 = -r0;
                if (l0 > 3436202 || r0 > 3436202) { z->first = i - 48 < 0 ? 0 : i - 48; break; }
            }
            *map_b = (int64_t)sb.st_size;
        } else {
            CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)pl, false);
            ExtAudioFileRef ef = NULL;
            OSStatus os = ExtAudioFileOpenURL(u, &ef);
            CFRelease(u);
            if (os != noErr || !ef) {
                snprintf(err, errcap, "live_zone_file: %s: cannot open (%d)", path, (int)os);
                return -1;
            }
            AudioStreamBasicDescription f;
            UInt32 sz = sizeof f;
            ExtAudioFileGetProperty(ef, kExtAudioFileProperty_FileDataFormat, &sz, &f);
            SInt64 fr = 0;
            sz = sizeof fr;
            ExtAudioFileGetProperty(ef, kExtAudioFileProperty_FileLengthFrames, &sz, &fr);
            AudioStreamBasicDescription c;
            memset(&c, 0, sizeof c);
            c.mSampleRate = f.mSampleRate; c.mFormatID = kAudioFormatLinearPCM;
            c.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            c.mChannelsPerFrame = 2; c.mBitsPerChannel = 32; c.mBytesPerFrame = 8; c.mFramesPerPacket = 1; c.mBytesPerPacket = 8;
            ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ClientDataFormat, sizeof c, &c);
            /* Decode up to hn + 64 frames so 64-tap NEON sinc across [head_n - 63 .. head_n - 1] never stalls or falls back */
            int64_t read_take = (hn + 64 > fr) ? fr : (hn + 64);
            if (read_take < 0) read_take = 0;
            float *buf = malloc((size_t)(read_take > 0 ? read_take : 1) * 8);
            UInt32 n = (UInt32)read_take;
            AudioBufferList abl;
            abl.mNumberBuffers = 1;
            abl.mBuffers[0].mNumberChannels = 2;
            abl.mBuffers[0].mDataByteSize = (UInt32)(read_take * 8);
            abl.mBuffers[0].mData = buf;
            if (n > 0) ExtAudioFileRead(ef, &n, &abl);
            ExtAudioFileDispose(ef);
            z->kind = 1;
            snprintf(z->path, sizeof z->path, "%s", path);
            z->rate = f.mSampleRate;
            z->frames = fr;
            z->head_n = (int64_t)n > hn ? hn : (int64_t)n;
            size_t alloc_n = (size_t)(n > (UInt32)hn ? n : (UInt32)(hn > 0 ? hn : 1));
            z->hl_alloc = calloc(32 + alloc_n + 64, sizeof(float));
            z->hr_alloc = calloc(32 + alloc_n + 64, sizeof(float));
            z->hl = z->hl_alloc + 32;
            z->hr = z->hr_alloc + 32;
            UInt32 i = 0;
#if defined(__aarch64__)
            for (; i + 4 <= n; i += 4) {
                float32x4x2_t lr = vld2q_f32(buf + 2 * i);
                vst1q_f32(z->hl + i, lr.val[0]);
                vst1q_f32(z->hr + i, lr.val[1]);
            }
#endif
            for (; i < n; i++) { z->hl[i] = buf[2 * i]; z->hr[i] = buf[2 * i + 1]; }
            free(buf);
            z->first = lv_first_sound(z->hl, z->hr, z->head_n, 1, z->rate);
            *head_b = (int64_t)z->head_n * 8;
        }
        return 0;
    }
}

/* a sample file as a zone: its head (head_frames, at most 262144) decoded into memory now, the rest streamed while a voice
 * plays it → [zone index, the file's rate, its frames, its first sound (sampler.w first_sound)] */
WValue w_media_live_zone_file(WValue hv, WValue pathv, WValue headv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_zone_file");
    char path[1024], err[1200];
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("live_zone_file: path must be a string");
    int64_t hn = a_int(headv, 16384, "head frames");
    if (hn < 1024) hn = 1024;
    if (hn > LV_HEAD_MAX) hn = LV_HEAD_MAX;
    LZoneF z;
    int64_t hb = 0, mb = 0;
    if (lv_load_zone_one(path, hn, &z, &hb, &mb, err, sizeof err) != 0) w_media_raise("%s", err);
    L->head_bytes += hb;
    L->map_bytes += mb;
    int idx = lv_add_zone(L, &z);
    WValue out = w_array_new_empty();
    out = w_array_push(out, w_int(idx));
    out = w_array_push(out, w_float(z.rate));
    out = w_array_push(out, w_int(z.frames));
    out = w_array_push(out, w_int(z.first));
    return out;
}

typedef struct LVBatchLoadCtx {
    char   **paths;
    int64_t  hn;
    LZoneF  *zs;
    int64_t *hbs;
    int64_t *mbs;
    int     *errs;
    char   (*emsg)[1200];
} LVBatchLoadCtx;

static void lv_batch_load_worker(void *ctxp, size_t idx) {
    LVBatchLoadCtx *c = ctxp;
    if (lv_load_zone_one(c->paths[idx], c->hn, &c->zs[idx], &c->hbs[idx], &c->mbs[idx], c->emsg[idx], sizeof c->emsg[idx]) != 0)
        c->errs[idx] = 1;
}

/* Batch parallel loader for sample zone files: decodes heads / mmaps .twpcm across GCD cores and registers all zones at once. */
WValue w_media_live_zone_files(WValue hv, WValue pathsv, WValue headv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_zone_files");
    if (!w_is_array(pathsv)) w_media_raise("live_zone_files: paths must be an Array");
    int n = (int)w_as_array(pathsv)->size;
    if (n <= 0) return w_array_new_empty();
    int64_t hn = a_int(headv, 16384, "head frames");
    if (hn < 1024) hn = 1024;
    if (hn > LV_HEAD_MAX) hn = LV_HEAD_MAX;

    char **paths = calloc((size_t)n, sizeof(char *));
    for (int i = 0; i < n; i++) {
        char buf[1024];
        if (!w_media_str(w_array_get(pathsv, w_int(i)), buf, sizeof buf) || !buf[0]) {
            for (int j = 0; j < i; j++) free(paths[j]);
            free(paths);
            w_media_raise("live_zone_files: path %d must be a non-empty string", i);
        }
        paths[i] = strdup(buf);
    }
    LZoneF *zs = calloc((size_t)n, sizeof *zs);
    int64_t *hbs = calloc((size_t)n, sizeof(int64_t));
    int64_t *mbs = calloc((size_t)n, sizeof(int64_t));
    int *errs = calloc((size_t)n, sizeof(int));
    char (*emsg)[1200] = calloc((size_t)n, sizeof *emsg);
    LVBatchLoadCtx ctx = {paths, hn, zs, hbs, mbs, errs, emsg};
    if (n >= 2)
        dispatch_apply_f((size_t)n, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, lv_batch_load_worker);
    else
        lv_batch_load_worker(&ctx, 0);

    int bad = -1;
    for (int i = 0; i < n; i++) {
        free(paths[i]);
        if (errs[i] && bad < 0) bad = i;
    }
    free(paths);
    if (bad >= 0) {
        char msg[1200];
        snprintf(msg, sizeof msg, "%s", emsg[bad]);
        for (int i = 0; i < n; i++) {
            if (!errs[i]) {
                free(zs[i].hl_alloc); free(zs[i].hr_alloc);
                if (zs[i].kind == 2 && zs[i].raw) munmap((void *)((char *)zs[i].raw - 24), zs[i].raw_len);
            }
        }
        free(zs); free(hbs); free(mbs); free(errs); free(emsg);
        w_media_raise("%s", msg);
    }

    int64_t tot_hb = 0, tot_mb = 0;
    for (int i = 0; i < n; i++) { tot_hb += hbs[i]; tot_mb += mbs[i]; }
    L->head_bytes += tot_hb;
    L->map_bytes += tot_mb;
    int base_idx = lv_add_zones_batch(L, zs, n);

    WValue out = w_array_new_empty();
    for (int i = 0; i < n; i++) {
        WValue row = w_array_new_empty();
        row = w_array_push(row, w_int(base_idx + i));
        row = w_array_push(row, w_float(zs[i].rate));
        row = w_array_push(row, w_int(zs[i].frames));
        row = w_array_push(row, w_int(zs[i].first));
        out = w_array_push(out, row);
    }
    free(zs); free(hbs); free(mbs); free(errs); free(emsg);
    return out;
}

/* the sinc table sampler.w interpolates with ((512 + 1) × 64 coefficients, f64[]) */
WValue w_media_live_sinc(WValue hv, WValue tabv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_sinc");
    int64_t n = 0;
    (void)a_f64_at(tabv, 0, "table", &n);
    if (n < 513 * 64) w_media_raise("live_sinc: the table has %lld entries, not 513 x 64", (long long)n);
    float *t = malloc((size_t)n * sizeof(float));
    for (int64_t i = 0; i < n; i++) { int64_t d; t[i] = (float)a_f64_at(tabv, i, "table", &d); }
    os_unfair_lock_lock(&L->prod_lock);
    float *old = atomic_exchange_explicit(&L->sinc, t, memory_order_acq_rel);
    if (old && L->n_sinc_retired < 16) {
        L->sinc_retired[L->n_sinc_retired++] = old;
        old = NULL;
    }
    os_unfair_lock_unlock(&L->prod_lock);
    if (old) { usleep(30000); free(old); }
    return W_TRUE;
}

static int64_t lv_push(ALive *L, LEvent *e) {
    os_unfair_lock_lock(&L->prod_lock);
    if (e->type == 1 && e->tag == 0) e->tag = L->next_tag++;
    int64_t tag = e->tag;
    uint32_t w = atomic_load_explicit(&L->ev_w, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&L->ev_r, memory_order_acquire);
    uint32_t cap = e->type == 5 ? LV_EVENTS : (LV_EVENTS - 1);
    if (w - r < cap) {
        L->ev_ring[w & (LV_EVENTS - 1)] = *e;
        atomic_store_explicit(&L->ev_w, w + 1, memory_order_release);
    }
    os_unfair_lock_unlock(&L->prod_lock);
    return tag;
}

/* a note scheduled: zone, pitch ratio (1 = the sample's own pitch), linear gain, the file frame it starts at, the release
 * time constant (s), the host time it sounds at (0: now) and the host time of what caused it (latency) → its tag */
WValue w_media_live_play(WValue hv, WValue av, WValue whenv, WValue originv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_play");
    if (!w_is_array(av)) w_media_raise("live_play: [zone, key, ratio, gain, start frame, release s]");
    WArray *a = w_as_array(av);
    if (a->size < 6) w_media_raise("live_play: [zone, key, ratio, gain, start frame, release s]");
    LEvent e;
    memset(&e, 0, sizeof e);
    e.type = 1;
    e.zone = (int)w_media_num(a->slots[a->start], 0, "zone");
    e.key = (int)w_media_num(a->slots[a->start + 1], 0, "key");
    e.ratio = w_media_num(a->slots[a->start + 2], 1, "ratio");
    e.amp = w_media_num(a->slots[a->start + 3], 1, "gain");
    e.start = w_media_num(a->slots[a->start + 4], 0, "start");
    e.rel = w_media_num(a->slots[a->start + 5], 0.2, "release");
    e.when = w_media_num(whenv, 0, "when");
    if (e.when <= 0) e.when = lv_now();
    e.origin = w_media_num(originv, 0, "origin");
    return w_int(lv_push(L, &e));
}

/* release a note by its tag (0: every note) at a host time (0: now), with its release time constant (s; 0: the note's own) */
WValue w_media_live_release(WValue hv, WValue tagv, WValue whenv, WValue relv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_release");
    LEvent e;
    memset(&e, 0, sizeof e);
    e.type = 2;
    e.tag = a_int(tagv, 0, "tag");
    e.when = w_media_num(whenv, 0, "when");
    if (e.when <= 0) e.when = lv_now();
    e.rel = w_media_num(relv, 0, "release");
    lv_push(L, &e);
    return W_TRUE;
}

/* a transport's stop (2026-11-04 night): every scheduled event dropped (notes not started yet, releases, bends) and what
 * sounds released now with time constant rel s (0: each voice's own) */
WValue w_media_live_flush(WValue hv, WValue relv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_flush");
    LEvent e;
    memset(&e, 0, sizeof e);
    e.type = 5;
    e.tag = 0;
    e.when = lv_now();
    e.rel = w_media_num(relv, 0, "release");
    lv_push(L, &e);
    return W_TRUE;
}

/* pitch bend in cents for every voice, from a host time (0: now) */
WValue w_media_live_bend(WValue hv, WValue centsv, WValue whenv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_bend");
    LEvent e;
    memset(&e, 0, sizeof e);
    e.type = 3;
    e.cents = w_media_num(centsv, 0, "cents");
    e.when = w_media_num(whenv, 0, "when");
    if (e.when <= 0) e.when = lv_now();
    lv_push(L, &e);
    return W_TRUE;
}

/* a vibrato on every voice: depth in cents (0: none), rate in Hz */
WValue w_media_live_vibrato(WValue hv, WValue depthv, WValue ratev) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_vibrato");
    L->vib_depth = w_media_num(depthv, 0, "depth");
    double r = w_media_num(ratev, 5.5, "rate");
    L->vib_rate = r > 0 ? r : 5.5;
    return W_TRUE;
}

/* the first API's note: velocity 1…127 starts the key's zone (live_zone's key mapping), 0 releases the key */
WValue w_media_live_note(WValue hv, WValue keyv, WValue velv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_note");
    int key = (int)a_int(keyv, 60, "key"), vel = (int)a_int(velv, 0, "velocity");
    if (vel <= 0) {
        for (int i = 0; i < L_VOICES; i++) {
            LVoiceF *v = &L->v[i];
            if (atomic_load(&v->state) == 1 && v->key == key) {
                LEvent e; memset(&e, 0, sizeof e); e.type = 2; e.tag = v->tag; e.when = lv_now(); lv_push(L, &e);
            }
        }
        return W_TRUE;
    }
    int zi = -1;
    int cur_nz = atomic_load_explicit(&L->nz, memory_order_acquire);
    double ratio = 1, gain = 1;
    for (int i = 0; i < cur_nz && zi < 0; i++) {
        LZoneF *z = lv_zone_at(L, i);
        if (z && z->kind == 3 && key >= z->lo && key <= z->hi && vel >= z->vlo && vel <= z->vhi) {
            zi = i;
            ratio = pow(2.0, (key - z->root) / 12.0);
            gain = z->gain * (vel / 127.0) * (vel / 127.0);
        }
    }
    if (zi < 0) return W_FALSE;
    LEvent e;
    memset(&e, 0, sizeof e);
    e.type = 1; e.zone = zi; e.key = key; e.ratio = ratio; e.amp = gain; e.start = 0; e.rel = 0.04; e.when = lv_now();
    lv_push(L, &e);
    return W_TRUE;
}

WValue w_media_live_volume(WValue hv, WValue vv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_volume");
    double g = a_num(vv);
    if (g < 0) g = 0;
    if (g > 4) g = 4;
    L->volume = (float)g;
    return W_TRUE;
}

/* [voices, zones, rate, frames rendered, head bytes, mapped bytes, ring bytes, underruns, latency n, mean s, max s, last s,
 *  the output's presentation latency s, the render buffer's frames, now (host s), the callback's seconds, the audio's seconds
 *  (their ratio is its mean load), the worst buffer's load, the most voices at once, the voices there are] */
WValue w_media_live_info(WValue hv) {
    ALive *L = (ALive *)w_media_handle_get(hv, W_MEDIA_KIND_LIVE, "live_info");
    int n = 0;
    for (int i = 0; i < L_VOICES; i++) if (atomic_load(&L->v[i].state)) n++;
    double pres = 0;
    @autoreleasepool { pres = L->engine.outputNode.presentationLatency; }
    WValue out = w_array_new_empty();
    out = w_array_push(out, w_int(n));
    out = w_array_push(out, w_int(atomic_load_explicit(&L->nz, memory_order_acquire)));
    out = w_array_push(out, w_float(L->rate));
    out = w_array_push(out, w_int(atomic_load(&L->rendered)));
    out = w_array_push(out, w_int(L->head_bytes));
    out = w_array_push(out, w_int(L->map_bytes));
    out = w_array_push(out, w_int((int64_t)L_VOICES * LV_RING * 8));
    out = w_array_push(out, w_int(atomic_load(&L->underruns)));
    out = w_array_push(out, w_int(L->lat_n));
    out = w_array_push(out, w_float(L->lat_n > 0 ? L->lat_sum / (double)L->lat_n : 0));
    out = w_array_push(out, w_float(L->lat_max));
    out = w_array_push(out, w_float(L->lat_last));
    out = w_array_push(out, w_float(pres));
    out = w_array_push(out, w_int(L->buf_frames));
    out = w_array_push(out, w_float(lv_now()));
    out = w_array_push(out, w_float(L->cb_sum));
    out = w_array_push(out, w_float(L->buf_sum));
    out = w_array_push(out, w_float(L->cb_max));
    out = w_array_push(out, w_int(L->voices_max));
    out = w_array_push(out, w_int(L_VOICES));
    return out;
}

WValue w_media_live_close(WValue hv) {
    ALive *L = m_avf_peek(hv, W_MEDIA_KIND_LIVE);
    if (!L) return W_FALSE;
    w_media_handle_drop(hv, W_MEDIA_KIND_LIVE);
    [L->engine stop];
    atomic_store_explicit(&L->quit, 1, memory_order_release);
    for (int t = 0; t < LV_READERS; t++) pthread_join(L->readers[t], NULL);
    for (int i = 0; i < L_VOICES; i++) {
        if (L->v[i].ef) ExtAudioFileDispose(L->v[i].ef);
        free(L->v[i].rl);
        free(L->v[i].rr);
    }
    [L->engine detachNode:L->node];
    [L->node release];
    [L->engine release];
    int cur_nz = atomic_load_explicit(&L->nz, memory_order_relaxed);
    for (int i = 0; i < cur_nz; i++) {
        LZoneF *z = lv_zone_at(L, i);
        if (!z) continue;
        if (z->kind == 2) munmap((void *)((const char *)z->raw - 24), z->raw_len);
        else { free(z->hl_alloc); free(z->hr_alloc); }
    }
    for (int p = 0; p < LV_ZONE_MAX_PAGES; p++) {
        LZoneF *pg = atomic_load_explicit(&L->z_pages[p], memory_order_relaxed);
        if (pg) free(pg);
    }
    float *sc = atomic_load_explicit(&L->sinc, memory_order_relaxed);
    free(sc);
    for (int i = 0; i < L->n_sinc_retired; i++) free(L->sinc_retired[i]);
    free(L);
    return W_TRUE;
}

/* Native NEON .twpcm writer: writes 24-byte header ("TWPCM\0\0\2" + LE int64 rate, frames) + clamped int32 stereo interleaved
 * samples (round-half-up: floor(clamp(x,-1,1) * 2147483647.0 + 0.5)) via atomic tmp-file + rename. */
WValue w_media_live_pcm_write(WValue pathv, WValue ratev, WValue nv, WValue lv, WValue rv) {
    char path[1024];
    if (!w_media_str(pathv, path, sizeof path) || !path[0]) w_media_raise("live_pcm_write: path must be a string");
    if (!w_is_array(lv) || !w_is_array(rv)) w_media_raise("live_pcm_write: left and right must be arrays");
    int64_t rate = a_int(ratev, 48000, "rate");
    int64_t n = a_int(nv, 0, "frames");
    WArray *la = w_as_array(lv), *ra = w_as_array(rv);
    if (n > la->size) n = la->size;
    if (n > ra->size) n = ra->size;
    if (n < 0) n = 0;

    char tmp[1152];
    static _Atomic uint64_t s_seq = 0;
    uint64_t seq = atomic_fetch_add_explicit(&s_seq, 1, memory_order_relaxed);
    snprintf(tmp, sizeof tmp, "%s.tmp.%d.%llu", path, (int)getpid(), (unsigned long long)seq);

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) w_media_raise("live_pcm_write: cannot open %s (%s)", tmp, strerror(errno));

    uint8_t hdr[24];
    memcpy(hdr, "TWPCM\0\0\2", 8);
    for (int b = 0; b < 8; b++) {
        hdr[8 + b] = (uint8_t)(((uint64_t)rate >> (8 * b)) & 0xFFu);
        hdr[16 + b] = (uint8_t)(((uint64_t)n >> (8 * b)) & 0xFFu);
    }
    if (write(fd, hdr, 24) != 24) {
        close(fd);
        unlink(tmp);
        w_media_raise("live_pcm_write: short header write to %s", tmp);
    }

    int32_t chunk[16384]; /* 8192 stereo frames = 64 KiB */
    const int64_t blk = 8192;
    int is_f64 = (la->ebits == -64 && ra->ebits == -64);
    const double *lp = is_f64 ? ((const double *)la->slots + la->start) : NULL;
    const double *rp = is_f64 ? ((const double *)ra->slots + ra->start) : NULL;

    for (int64_t base = 0; base < n; base += blk) {
        int64_t cnt = (n - base) < blk ? (n - base) : blk;
        int64_t i = 0;
#if defined(__aarch64__)
        if (is_f64) {
            float64x2_t vmin = vdupq_n_f64(-1.0);
            float64x2_t vmax = vdupq_n_f64(1.0);
            float64x2_t vsc = vdupq_n_f64(2147483647.0);
            float64x2_t vhalf = vdupq_n_f64(0.5);
            for (; i + 2 <= cnt; i += 2) {
                float64x2_t xl = vld1q_f64(lp + base + i);
                float64x2_t xr = vld1q_f64(rp + base + i);
                /* NaN check: if any lane is NaN, fall back to scalar for this pair */
                uint64x2_t ok = vandq_u64(vceqq_f64(xl, xl), vceqq_f64(xr, xr));
                if (vgetq_lane_u64(ok, 0) != ~0ULL || vgetq_lane_u64(ok, 1) != ~0ULL) break;
                float64x2_t cl = vmaxq_f64(vminq_f64(xl, vmax), vmin);
                float64x2_t cr = vmaxq_f64(vminq_f64(xr, vmax), vmin);
                int64x2_t il = vcvtmq_s64_f64(vaddq_f64(vmulq_f64(cl, vsc), vhalf));
                int64x2_t ir = vcvtmq_s64_f64(vaddq_f64(vmulq_f64(cr, vsc), vhalf));
                int32x2_t sl = vmovn_s64(il);
                int32x2_t sr = vmovn_s64(ir);
                int32x2x2_t zp = vzip_s32(sl, sr);
                vst1q_s32(chunk + 2 * i, vcombine_s32(zp.val[0], zp.val[1]));
            }
        }
#endif
        for (; i < cnt; i++) {
            int64_t dm;
            double xl = is_f64 ? lp[base + i] : a_f64_at(lv, base + i, "l", &dm);
            double xr = is_f64 ? rp[base + i] : a_f64_at(rv, base + i, "r", &dm);
            if (!(xl == xl)) xl = 0.0;
            if (!(xr == xr)) xr = 0.0;
            if (xl > 1.0) xl = 1.0; else if (xl < -1.0) xl = -1.0;
            if (xr > 1.0) xr = 1.0; else if (xr < -1.0) xr = -1.0;
            chunk[2 * i] = (int32_t)(int64_t)floor(xl * 2147483647.0 + 0.5);
            chunk[2 * i + 1] = (int32_t)(int64_t)floor(xr * 2147483647.0 + 0.5);
        }
        size_t need = (size_t)cnt * 8;
        size_t off = 0;
        while (off < need) {
            ssize_t wr = write(fd, (const char *)chunk + off, need - off);
            if (wr <= 0) {
                close(fd);
                unlink(tmp);
                w_media_raise("live_pcm_write: write failed on %s", tmp);
            }
            off += (size_t)wr;
        }
    }
    if (close(fd) != 0 || rename(tmp, path) != 0) {
        unlink(tmp);
        w_media_raise("live_pcm_write: rename failed to %s (%s)", path, strerror(errno));
    }
    return w_int(n);
}

/* the host clock in seconds (the one MIDI timestamps and live_play's `when` use) */
WValue w_media_midi_now(void) { return w_float(lv_now()); }

/* ======================================================================
   Banding QC SIMD/multithreaded kernels (w_media_banding_op)
   ====================================================================== */

static double *a_band_f64_ptr(WValue v, int64_t min_len, const char *what) {
    if (!w_is_array(v)) w_media_raise("banding(%s): expected f64[]", what);
    WArray *a = w_as_array(v);
    if (a->ebits != -64 || a->size < min_len) w_media_raise("banding(%s): expected f64[] of size >= %lld", what, (long long)min_len);
    return (double *)a->slots + a->start;
}

static uint8_t *a_band_u8_ptr(WValue v, int64_t min_len, const char *what) {
    if (!w_is_array(v)) w_media_raise("banding(%s): expected u8[]", what);
    WArray *a = w_as_array(v);
    if (a->ebits != 8 || a->size < min_len) w_media_raise("banding(%s): expected u8[] of size >= %lld", what, (long long)min_len);
    return (uint8_t *)a->slots + a->start;
}

typedef struct ABandIdealCtx {
    double *ideal;
    int     w, h;
    double  cx_px, cy_px, inv_rx, inv_ry, mid, l0, l1, slope0, slope1;
} ABandIdealCtx;

static void a_band_ideal_band(void *ctxp, size_t bi) {
    ABandIdealCtx *c = ctxp;
    int y0 = (int)((int64_t)c->h * (int64_t)bi / 8), y1 = (int)((int64_t)c->h * (int64_t)(bi + 1) / 8);
    for (int y = y0; y < y1; y++) {
        double dy = ((double)y + 0.5 - c->cy_px) * c->inv_ry;
        double dy2 = dy * dy;
        double *row = c->ideal + (size_t)y * (size_t)c->w;
        int x = 0;
#if defined(__aarch64__)
        float64x2_t vdy2 = vdupq_n_f64(dy2), vcx = vdupq_n_f64(c->cx_px), virx = vdupq_n_f64(c->inv_rx);
        float64x2_t vmid = vdupq_n_f64(c->mid), vone = vdupq_n_f64(1.0);
        float64x2_t vl0 = vdupq_n_f64(c->l0), vl1 = vdupq_n_f64(c->l1);
        float64x2_t vs0 = vdupq_n_f64(c->slope0), vs1 = vdupq_n_f64(c->slope1);
        for (; x + 2 <= c->w; x += 2) {
            double x01[2] = {(double)x + 0.5, (double)(x + 1) + 0.5};
            float64x2_t vdx = vmulq_f64(vsubq_f64(vld1q_f64(x01), vcx), virx);
            float64x2_t vt = vminq_f64(vsqrtq_f64(vfmaq_f64(vdy2, vdx, vdx)), vone);
            float64x2_t va = vfmaq_f64(vl0, vs0, vt);
            float64x2_t vb = vfmaq_f64(vl1, vs1, vsubq_f64(vt, vmid));
            uint64x2_t m = vcleq_f64(vt, vmid);
            vst1q_f64(row + x, vbslq_f64(m, va, vb));
        }
#endif
        for (; x < c->w; x++) {
            double dx = ((double)x + 0.5 - c->cx_px) * c->inv_rx;
            double t = sqrt(dx * dx + dy2);
            if (t > 1.0) t = 1.0;
            row[x] = t <= c->mid ? c->l0 + c->slope0 * t : c->l1 + c->slope1 * (t - c->mid);
        }
    }
}

typedef struct ABandResCtx {
    const uint8_t *bytes;
    const double  *ideal;
    const double  *kern;
    double        *out;
    int            w, h, depth;
} ABandResCtx;

static inline void a_band_res_hrow(const uint8_t *bytes, const double *ideal, const double *kern,
                                   int w, int y, int depth, double *hrow) {
    static _Thread_local double *tl_raw = NULL;
    static _Thread_local size_t tl_raw_cap = 0;
    if ((size_t)w > tl_raw_cap) {
        free(tl_raw);
        tl_raw_cap = (size_t)w < 2048 ? 2048 : (size_t)w;
        tl_raw = malloc(tl_raw_cap * sizeof(double));
    }
    const double *id_row = ideal + (size_t)y * (size_t)w;
    if (depth == 16) {
        const double scale16 = 219.0 / (255.0 * 257.0);
        const uint8_t *sr = bytes + (size_t)y * (size_t)w * 6;
        for (int x = 0; x < w; x++) {
            size_t p = (size_t)x * 6;
            double r = (double)((uint32_t)sr[p] + 256u * (uint32_t)sr[p + 1]);
            double g = (double)((uint32_t)sr[p + 2] + 256u * (uint32_t)sr[p + 3]);
            double b = (double)((uint32_t)sr[p + 4] + 256u * (uint32_t)sr[p + 5]);
            tl_raw[x] = (16.0 + (0.2126 * r + 0.7152 * g + 0.0722 * b) * scale16) - id_row[x];
        }
    } else if (ideal) {
        const double scale8 = 219.0 / 255.0;
        const uint8_t *sr = bytes + (size_t)y * (size_t)w * 3;
        for (int x = 0; x < w; x++) {
            size_t p = (size_t)x * 3;
            tl_raw[x] = (16.0 + (0.2126 * (double)sr[p] + 0.7152 * (double)sr[p + 1] + 0.0722 * (double)sr[p + 2]) * scale8) - id_row[x];
        }
    } else {
        /* Pure blur mode when bytes is NULL and ideal holds the f64 input */
        memcpy(tl_raw, id_row, (size_t)w * sizeof(double));
    }

    const double k0 = kern[0], k1 = kern[1], k2 = kern[2], k3 = kern[3], k4 = kern[4], k5 = kern[5], k6 = kern[6];
    int x = 0;
    int left_end = w < 6 ? w : 6;
    for (; x < left_end; x++) {
        double v = 0.0;
        for (int k = -6; k <= 6; k++) {
            int at = x + k;
            if (at < 0) at = 0;
            else if (at >= w) at = w - 1;
            v += tl_raw[at] * kern[k + 6];
        }
        hrow[x] = v;
    }
    int right_start = w - 6;
    if (right_start < x) right_start = x;
#if defined(__aarch64__)
    float64x2_t vk0 = vdupq_n_f64(k0), vk1 = vdupq_n_f64(k1), vk2 = vdupq_n_f64(k2), vk3 = vdupq_n_f64(k3);
    float64x2_t vk4 = vdupq_n_f64(k4), vk5 = vdupq_n_f64(k5), vk6 = vdupq_n_f64(k6);
    for (; x + 2 <= right_start; x += 2) {
        float64x2_t acc = vmulq_f64(vld1q_f64(tl_raw + x), vk6);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 1), vld1q_f64(tl_raw + x + 1)), vk5);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 2), vld1q_f64(tl_raw + x + 2)), vk4);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 3), vld1q_f64(tl_raw + x + 3)), vk3);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 4), vld1q_f64(tl_raw + x + 4)), vk2);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 5), vld1q_f64(tl_raw + x + 5)), vk1);
        acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(tl_raw + x - 6), vld1q_f64(tl_raw + x + 6)), vk0);
        vst1q_f64(hrow + x, acc);
    }
#endif
    for (; x < right_start; x++) {
        hrow[x] = tl_raw[x] * k6 +
                  (tl_raw[x - 1] + tl_raw[x + 1]) * k5 +
                  (tl_raw[x - 2] + tl_raw[x + 2]) * k4 +
                  (tl_raw[x - 3] + tl_raw[x + 3]) * k3 +
                  (tl_raw[x - 4] + tl_raw[x + 4]) * k2 +
                  (tl_raw[x - 5] + tl_raw[x + 5]) * k1 +
                  (tl_raw[x - 6] + tl_raw[x + 6]) * k0;
    }
    for (; x < w; x++) {
        double v = 0.0;
        for (int k = -6; k <= 6; k++) {
            int at = x + k;
            if (at < 0) at = 0;
            else if (at >= w) at = w - 1;
            v += tl_raw[at] * kern[k + 6];
        }
        hrow[x] = v;
    }
}

static void a_band_res_band(void *ctxp, size_t bi) {
    ABandResCtx *c = ctxp;
    int w = c->w, h = c->h;
    int y0 = (int)((int64_t)h * (int64_t)bi / 8), y1 = (int)((int64_t)h * (int64_t)(bi + 1) / 8);
    if (y0 >= y1) return;
    static _Thread_local double *tl_ring = NULL;
    static _Thread_local size_t tl_ring_w = 0;
    size_t rw = ((size_t)w + 1u) & ~(size_t)1u;
    if (rw > tl_ring_w) {
        free(tl_ring);
        tl_ring_w = rw < 2048 ? 2048 : rw;
        tl_ring = malloc(16 * tl_ring_w * sizeof(double));
    }
    int slot_y[16];
    for (int i = 0; i < 16; i++) slot_y[i] = -1;
    const double k0 = c->kern[0], k1 = c->kern[1], k2 = c->kern[2], k3 = c->kern[3],
                 k4 = c->kern[4], k5 = c->kern[5], k6 = c->kern[6];
#if defined(__aarch64__)
    float64x2_t vk0 = vdupq_n_f64(k0), vk1 = vdupq_n_f64(k1), vk2 = vdupq_n_f64(k2), vk3 = vdupq_n_f64(k3);
    float64x2_t vk4 = vdupq_n_f64(k4), vk5 = vdupq_n_f64(k5), vk6 = vdupq_n_f64(k6);
#endif
    for (int y = y0; y < y1; y++) {
        int rslot[13];
        for (int k = -6; k <= 6; k++) {
            int yy = y + k;
            if (yy < 0) yy = 0;
            else if (yy >= h) yy = h - 1;
            int sl = yy & 15;
            if (slot_y[sl] != yy) {
                a_band_res_hrow(c->bytes, c->ideal, c->kern, w, yy, c->depth, tl_ring + (size_t)sl * rw);
                slot_y[sl] = yy;
            }
            rslot[k + 6] = sl;
        }
        double *out_row = c->out + (size_t)y * (size_t)w;
        const double *r6 = tl_ring + (size_t)rslot[6] * rw;
        const double *rm1 = tl_ring + (size_t)rslot[5] * rw, *rp1 = tl_ring + (size_t)rslot[7] * rw;
        const double *rm2 = tl_ring + (size_t)rslot[4] * rw, *rp2 = tl_ring + (size_t)rslot[8] * rw;
        const double *rm3 = tl_ring + (size_t)rslot[3] * rw, *rp3 = tl_ring + (size_t)rslot[9] * rw;
        const double *rm4 = tl_ring + (size_t)rslot[2] * rw, *rp4 = tl_ring + (size_t)rslot[10] * rw;
        const double *rm5 = tl_ring + (size_t)rslot[1] * rw, *rp5 = tl_ring + (size_t)rslot[11] * rw;
        const double *rm6 = tl_ring + (size_t)rslot[0] * rw, *rp6 = tl_ring + (size_t)rslot[12] * rw;
        int x = 0;
#if defined(__aarch64__)
        for (; x + 2 <= w; x += 2) {
            float64x2_t acc = vmulq_f64(vld1q_f64(r6 + x), vk6);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm1 + x), vld1q_f64(rp1 + x)), vk5);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm2 + x), vld1q_f64(rp2 + x)), vk4);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm3 + x), vld1q_f64(rp3 + x)), vk3);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm4 + x), vld1q_f64(rp4 + x)), vk2);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm5 + x), vld1q_f64(rp5 + x)), vk1);
            acc = vfmaq_f64(acc, vaddq_f64(vld1q_f64(rm6 + x), vld1q_f64(rp6 + x)), vk0);
            vst1q_f64(out_row + x, acc);
        }
#endif
        for (; x < w; x++) {
            out_row[x] = r6[x] * k6 +
                         (rm1[x] + rp1[x]) * k5 +
                         (rm2[x] + rp2[x]) * k4 +
                         (rm3[x] + rp3[x]) * k3 +
                         (rm4[x] + rp4[x]) * k2 +
                         (rm5[x] + rp5[x]) * k1 +
                         (rm6[x] + rp6[x]) * k0;
        }
    }
}

typedef struct ABandMaskCtx {
    const uint8_t *src, *bg;
    uint8_t       *diff;
    const int32_t *blocked;
    uint8_t       *out;
    int            w, h, margin, border;
} ABandMaskCtx;

static void a_band_mask_diff_band(void *ctxp, size_t bi) {
    ABandMaskCtx *c = ctxp;
    int y0 = (int)((int64_t)c->h * (int64_t)bi / 8), y1 = (int)((int64_t)c->h * (int64_t)(bi + 1) / 8);
    for (int y = y0; y < y1; y++) {
        size_t off = (size_t)y * (size_t)c->w;
        const uint8_t *s = c->src + off * 3, *b = c->bg + off * 3;
        uint8_t *d = c->diff + off;
        for (int x = 0; x < c->w; x++) {
            size_t p = (size_t)x * 3;
            d[x] = (s[p] != b[p] || s[p + 1] != b[p + 1] || s[p + 2] != b[p + 2]) ? 1 : 0;
        }
    }
}

static void a_band_mask_query_band(void *ctxp, size_t bi) {
    ABandMaskCtx *c = ctxp;
    int y_lo = c->border, y_hi = c->h - c->border;
    if (y_lo >= y_hi) return;
    int span = y_hi - y_lo;
    int y0 = y_lo + (int)((int64_t)span * (int64_t)bi / 8);
    int y1 = y_lo + (int)((int64_t)span * (int64_t)(bi + 1) / 8);
    size_t stride = (size_t)(c->w + 1);
    int x_lo = c->border, x_hi = c->w - c->border;
    for (int y = y0; y < y1; y++) {
        int wy0 = y - c->margin; if (wy0 < 0) wy0 = 0;
        int wy1 = y + c->margin + 1; if (wy1 > c->h) wy1 = c->h;
        const int32_t *r0 = c->blocked + (size_t)wy0 * stride;
        const int32_t *r1 = c->blocked + (size_t)wy1 * stride;
        uint8_t *out_row = c->out + (size_t)y * (size_t)c->w;
        for (int x = x_lo; x < x_hi; x++) {
            int wx0 = x - c->margin; if (wx0 < 0) wx0 = 0;
            int wx1 = x + c->margin + 1; if (wx1 > c->w) wx1 = c->w;
            int32_t cnt = r1[wx1] - r0[wx1] - r1[wx0] + r0[wx0];
            out_row[x] = (cnt == 0) ? 1 : 0;
        }
    }
}

static double a_band_select_kth(double *vals, int64_t n, int64_t k) {
    int64_t lo = 0, hi = n - 1;
    while (lo < hi) {
        int64_t mid = (lo + hi) >> 1;
        double a = vals[lo], b = vals[mid], c = vals[hi], pivot = b;
        if ((a <= b && b <= c) || (c <= b && b <= a)) pivot = b;
        else if ((b <= a && a <= c) || (c <= a && a <= b)) pivot = a;
        else pivot = c;
        int64_t lt = lo, idx = lo, gt = hi;
        while (idx <= gt) {
            double v = vals[idx];
            if (v < pivot) {
                vals[idx] = vals[lt]; vals[lt] = v; lt++; idx++;
            } else if (v > pivot) {
                vals[idx] = vals[gt]; vals[gt] = v; gt--;
            } else {
                idx++;
            }
        }
        if (k < lt) hi = lt - 1;
        else if (k > gt) lo = gt + 1;
        else return pivot;
    }
    return vals[lo];
}

#define A_BAND_HIST_BINS 4096

typedef struct ABandMetCtx {
    const double  *err;
    const uint8_t *mask;
    int            w, h;
    double         total[8], sq[8], bound[8], inter[8];
    int64_t        cnt[8], nb[8], ni[8];
    int32_t       *hists; /* 8 * A_BAND_HIST_BINS */
} ABandMetCtx;

static void a_band_met_band(void *ctxp, size_t bi) {
    ABandMetCtx *c = ctxp;
    int w = c->w, h = c->h;
    int y0 = (int)((int64_t)h * (int64_t)bi / 8), y1 = (int)((int64_t)h * (int64_t)(bi + 1) / 8);
    int32_t *hist = c->hists + bi * (size_t)A_BAND_HIST_BINS;
    double tot = 0.0, sq = 0.0, bnd = 0.0, intr = 0.0;
    int64_t cnt = 0, nb = 0, ni = 0;
    for (int y = y0; y < y1; y++) {
        size_t row = (size_t)y * (size_t)w;
        int yb = y > 0 && ((y & 15) == 0);
        for (int x = 0; x < w; ) {
#if defined(__aarch64__)
            if (x + 16 <= w && vmaxvq_u8(vld1q_u8(c->mask + row + (size_t)x)) == 0) {
                x += 16;
                continue;
            }
#endif
            size_t p = row + (size_t)x;
            if (c->mask[p] != 0) {
                double e = c->err[p];
                double ae = fabs(e);
                tot += e;
                sq += e * e;
                cnt++;
                int64_t b = (int64_t)(ae * 2048.0);
                if (b >= A_BAND_HIST_BINS) b = A_BAND_HIST_BINS - 1;
                hist[b]++;
                if (x > 0 && c->mask[p - 1] != 0) {
                    double d = fabs(e - c->err[p - 1]);
                    if ((x & 15) == 0) { bnd += d; nb++; }
                    else { intr += d; ni++; }
                }
                if (y > 0 && c->mask[p - (size_t)w] != 0) {
                    double d = fabs(e - c->err[p - (size_t)w]);
                    if (yb) { bnd += d; nb++; }
                    else { intr += d; ni++; }
                }
            }
            x++;
        }
    }
    c->total[bi] = tot; c->sq[bi] = sq; c->bound[bi] = bnd; c->inter[bi] = intr;
    c->cnt[bi] = cnt; c->nb[bi] = nb; c->ni[bi] = ni;
}

/* w_media_banding_op(op, arg1, arg2, arg3) */
WValue w_media_banding_op(WValue opv, WValue a1, WValue a2, WValue a3) {
    char op[32];
    w_media_str(opv, op, sizeof op);

    if (!strcmp(op, "ideal")) {
        int w = (int)w_media_num(m_avf_arr(a1, 0), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a1, 1), 0, "height");
        int64_t n = (int64_t)w * (int64_t)h;
        double *ideal = a_band_f64_ptr(a3, n, "ideal");
        double cx = w_media_num(m_avf_arr(a2, 0), 0, "cx");
        double cy = w_media_num(m_avf_arr(a2, 1), 0, "cy");
        double rad = w_media_num(m_avf_arr(a2, 2), 1, "radius");
        double mid = w_media_num(m_avf_arr(a2, 3), 0.5, "mid");
        double l0 = w_media_num(m_avf_arr(a2, 4), 16, "l0");
        double l1 = w_media_num(m_avf_arr(a2, 5), 16, "l1");
        double l2 = w_media_num(m_avf_arr(a2, 6), 16, "l2");
        ABandIdealCtx ctx = {ideal, w, h, cx * w, cy * h, 1.0 / (rad * w), 1.0 / (rad * h),
                             mid, l0, l1, (l1 - l0) / mid, (l2 - l1) / (1.0 - mid)};
        if (n >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_band_ideal_band);
        else
            for (size_t b = 0; b < 8; b++) a_band_ideal_band(&ctx, b);
        return a3;
    }

    if (!strcmp(op, "residual") || !strcmp(op, "blur")) {
        int is_blur = !strcmp(op, "blur");
        int w = (int)w_media_num(m_avf_arr(a3, 0), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a3, 1), 0, "height");
        int depth = is_blur ? 0 : (int)w_media_num(m_avf_arr(a3, 2), 8, "depth");
        int64_t n = (int64_t)w * (int64_t)h;
        const uint8_t *bytes = is_blur ? NULL : a_band_u8_ptr(m_avf_arr(a1, 0), n * (depth == 16 ? 6 : 3), "bytes");
        const double *ideal = a_band_f64_ptr(is_blur ? m_avf_arr(a1, 0) : m_avf_arr(a1, 1), n, "ideal");
        WValue outv = m_avf_arr(a1, is_blur ? 1 : 2);
        double *out = a_band_f64_ptr(outv, n, "out");
        const double *kern = a_band_f64_ptr(a2, 13, "kernel");
        ABandResCtx ctx = {bytes, ideal, kern, out, w, h, depth};
        if (n >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_band_res_band);
        else
            for (size_t b = 0; b < 8; b++) a_band_res_band(&ctx, b);
        return outv;
    }

    if (!strcmp(op, "mask")) {
        int w = (int)w_media_num(m_avf_arr(a3, 0), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a3, 1), 0, "height");
        int margin = (int)w_media_num(m_avf_arr(a3, 2), 8, "margin");
        int border = (int)w_media_num(m_avf_arr(a3, 3), 20, "border");
        int64_t n = (int64_t)w * (int64_t)h;
        const uint8_t *src = a_band_u8_ptr(m_avf_arr(a1, 0), n * 3, "source");
        const uint8_t *bg = a_band_u8_ptr(m_avf_arr(a1, 1), n * 3, "background");
        WValue outv = m_avf_arr(a1, 2);
        uint8_t *out = a_band_u8_ptr(outv, n, "mask");
        memset(out, 0, (size_t)n);
        uint8_t *diff = calloc((size_t)(n > 0 ? n : 1), 1);
        ABandMaskCtx ctx = {src, bg, diff, NULL, out, w, h, margin, border};
        if (n >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_band_mask_diff_band);
        else
            for (size_t b = 0; b < 8; b++) a_band_mask_diff_band(&ctx, b);
        if (w_is_array(a2)) {
            int64_t ne = w_as_array(a2)->size;
            for (int64_t i = 0; i < ne; i++) {
                WValue r = w_array_get(a2, w_int(i));
                int rx0 = (int)w_media_num(m_avf_arr(r, 0), 0, "rx");
                int ry0 = (int)w_media_num(m_avf_arr(r, 1), 0, "ry");
                int rx1 = rx0 + (int)w_media_num(m_avf_arr(r, 2), 0, "rw");
                int ry1 = ry0 + (int)w_media_num(m_avf_arr(r, 3), 0, "rh");
                if (rx0 < 0) rx0 = 0;
                if (ry0 < 0) ry0 = 0;
                if (rx1 > w) rx1 = w;
                if (ry1 > h) ry1 = h;
                if (rx0 < rx1) {
                    for (int ry = ry0; ry < ry1; ry++)
                        memset(diff + (size_t)ry * (size_t)w + (size_t)rx0, 1, (size_t)(rx1 - rx0));
                }
            }
        }
        size_t stride = (size_t)(w + 1);
        int32_t *blocked = calloc(stride * (size_t)(h + 1), sizeof(int32_t));
        for (int y = 0; y < h; y++) {
            int32_t row_sum = 0;
            const uint8_t *dr = diff + (size_t)y * (size_t)w;
            const int32_t *pr = blocked + (size_t)y * stride;
            int32_t *cr = blocked + (size_t)(y + 1) * stride;
            for (int x = 0; x < w; x++) {
                row_sum += dr[x];
                cr[x + 1] = pr[x + 1] + row_sum;
            }
        }
        ctx.blocked = blocked;
        if (n >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_band_mask_query_band);
        else
            for (size_t b = 0; b < 8; b++) a_band_mask_query_band(&ctx, b);
        free(blocked);
        free(diff);
        return outv;
    }

    if (!strcmp(op, "metrics")) {
        int w = (int)w_media_num(m_avf_arr(a3, 0), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a3, 1), 0, "height");
        int64_t n = (int64_t)w * (int64_t)h;
        const double *err = a_band_f64_ptr(a1, n, "error");
        const uint8_t *mask = a_band_u8_ptr(a2, n, "mask");
        ABandMetCtx ctx;
        memset(&ctx, 0, sizeof ctx);
        ctx.err = err; ctx.mask = mask; ctx.w = w; ctx.h = h;
        ctx.hists = calloc(8 * (size_t)A_BAND_HIST_BINS, sizeof(int32_t));
        if (n >= 32768)
            dispatch_apply_f(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_band_met_band);
        else
            for (size_t b = 0; b < 8; b++) a_band_met_band(&ctx, b);
        double total = 0.0, sq = 0.0, bnd = 0.0, intr = 0.0;
        int64_t count = 0, nb = 0, ni = 0;
        int32_t *hist = ctx.hists;
        for (int b = 0; b < 8; b++) {
            total += ctx.total[b]; sq += ctx.sq[b]; bnd += ctx.bound[b]; intr += ctx.inter[b];
            count += ctx.cnt[b]; nb += ctx.nb[b]; ni += ctx.ni[b];
            if (b > 0) {
                const int32_t *hb = ctx.hists + (size_t)b * (size_t)A_BAND_HIST_BINS;
                int k = 0;
#if defined(__aarch64__)
                for (; k + 4 <= A_BAND_HIST_BINS; k += 4)
                    vst1q_s32(hist + k, vaddq_s32(vld1q_s32(hist + k), vld1q_s32(hb + k)));
#endif
                for (; k < A_BAND_HIST_BINS; k++) hist[k] += hb[k];
            }
        }
        WValue out = w_array_new_empty();
        out = w_array_push(out, w_int(count));
        out = w_array_push(out, w_int(nb));
        out = w_array_push(out, w_int(ni));
        if (count < n / 100 || nb == 0 || ni == 0) {
            free(ctx.hists);
            return out;
        }
        double q = 0.99 * (double)(count - 1);
        int64_t lo_rank = (int64_t)q;
        int64_t hi_rank = lo_rank + 1 < count ? lo_rank + 1 : lo_rank;
        int64_t prefix = 0;
        int b_lo = 0;
        while (b_lo < A_BAND_HIST_BINS) {
            int64_t c = hist[b_lo];
            if (prefix + c > lo_rank) break;
            prefix += c;
            b_lo++;
        }
        int64_t bucket_n = b_lo < A_BAND_HIST_BINS ? hist[b_lo] : 0;
        double *bucket = malloc((size_t)(bucket_n > 0 ? bucket_n : 1) * sizeof(double));
        int64_t bi = 0;
        double next_min = 1e300;
        int need_next = hi_rank >= prefix + bucket_n;
        for (int64_t i = 0; i < n; ) {
#if defined(__aarch64__)
            if (i + 16 <= n && vmaxvq_u8(vld1q_u8(mask + i)) == 0) { i += 16; continue; }
#endif
            if (mask[i] != 0) {
                double v = fabs(err[i]);
                int64_t b = (int64_t)(v * 2048.0);
                if (b >= A_BAND_HIST_BINS) b = A_BAND_HIST_BINS - 1;
                if (b == b_lo) bucket[bi++] = v;
                else if (need_next && b > b_lo && v < next_min) next_min = v;
            }
            i++;
        }
        free(ctx.hists);
        int64_t local_lo = lo_rank - prefix;
        double v_lo = a_band_select_kth(bucket, bi, local_lo);
        double v_hi = v_lo;
        if (hi_rank != lo_rank) {
            if (need_next) v_hi = next_min;
            else {
                double m = bucket[local_lo + 1];
                for (int64_t j = local_lo + 2; j < bi; j++)
                    if (bucket[j] < m) m = bucket[j];
                v_hi = m;
            }
        }
        free(bucket);
        double p99 = v_lo + (v_hi - v_lo) * (q - (double)lo_rank);
        double mean = total / (double)count;
        double var = sq / (double)count - mean * mean;
        double iden = intr / (double)ni;
        if (iden < 1e-9) iden = 1e-9;
        out = w_array_push(out, w_float((double)count / (double)n));
        out = w_array_push(out, w_float(sqrt(sq / (double)count)));
        out = w_array_push(out, w_float(mean));
        out = w_array_push(out, w_float(sqrt(var > 0.0 ? var : 0.0)));
        out = w_array_push(out, w_float(p99));
        out = w_array_push(out, w_float((bnd / (double)nb) / iden));
        return out;
    }

    if (!strcmp(op, "text_metrics")) {
        int w = (int)w_media_num(m_avf_arr(a2, 0), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a2, 1), 0, "height");
        int x0 = (int)w_media_num(m_avf_arr(a3, 0), 0, "x0");
        int y0 = (int)w_media_num(m_avf_arr(a3, 1), 0, "y0");
        int x1 = (int)w_media_num(m_avf_arr(a3, 2), 0, "x1");
        int y1 = (int)w_media_num(m_avf_arr(a3, 3), 0, "y1");
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 > w) x1 = w;
        if (y1 > h) y1 = h;
        int rw = x1 - x0, rh = y1 - y0;
        if (rw <= 2 || rh <= 2) {
            WValue out = w_array_new_empty();
            out = w_array_push(out, w_float(0.0));
            out = w_array_push(out, w_float(1.0));
            out = w_array_push(out, w_int(0));
            return out;
        }
        int64_t n3 = (int64_t)w * (int64_t)h * 3;
        const uint8_t *a = a_band_u8_ptr(m_avf_arr(a1, 0), n3, "a");
        const uint8_t *b = a_band_u8_ptr(m_avf_arr(a1, 1), n3, "b");
        double *la_rows = malloc((size_t)rw * 3 * sizeof(double));
        double *lb_rows = malloc((size_t)rw * 3 * sizeof(double));
        double *la0 = la_rows, *la1 = la_rows + rw, *la2 = la_rows + 2 * rw;
        double *lb0 = lb_rows, *lb1 = lb_rows + rw, *lb2 = lb_rows + 2 * rw;
        for (int r = 0; r < 2; r++) {
            double *da = r == 0 ? la0 : la1, *db = r == 0 ? lb0 : lb1;
            const uint8_t *pa = a + ((size_t)(y0 + r) * (size_t)w + (size_t)x0) * 3;
            const uint8_t *pb = b + ((size_t)(y0 + r) * (size_t)w + (size_t)x0) * 3;
            for (int rx = 0; rx < rw; rx++, pa += 3, pb += 3) {
                da[rx] = 16.0 + 219.0 * (0.2126 * pa[0] + 0.7152 * pa[1] + 0.0722 * pa[2]) / 255.0;
                db[rx] = 16.0 + 219.0 * (0.2126 * pb[0] + 0.7152 * pb[1] + 0.0722 * pb[2]) / 255.0;
            }
        }
        int64_t edges = 0, retained = 0, err_sum = 0;
        int64_t count = (int64_t)(rw - 2) * (int64_t)(rh - 2) * 3;
        const double inv438 = 1.0 / 438.0;
        for (int ry = 1; ry < rh - 1; ry++) {
            const uint8_t *pa_next = a + ((size_t)(y0 + ry + 1) * (size_t)w + (size_t)x0) * 3;
            const uint8_t *pb_next = b + ((size_t)(y0 + ry + 1) * (size_t)w + (size_t)x0) * 3;
            for (int rx = 0; rx < rw; rx++, pa_next += 3, pb_next += 3) {
                la2[rx] = 16.0 + 219.0 * (0.2126 * pa_next[0] + 0.7152 * pa_next[1] + 0.0722 * pa_next[2]) / 255.0;
                lb2[rx] = 16.0 + 219.0 * (0.2126 * pb_next[0] + 0.7152 * pb_next[1] + 0.0722 * pb_next[2]) / 255.0;
            }
            for (int rx = 1; rx < rw - 1; rx++) {
                double ax = (la1[rx + 1] - la1[rx - 1]) * inv438;
                double ay = (la2[rx] - la0[rx]) * inv438;
                double bx = (lb1[rx + 1] - lb1[rx - 1]) * inv438;
                double by = (lb2[rx] - lb0[rx]) * inv438;
                if (ax * ax + ay * ay > 0.0064) {
                    edges++;
                    if (bx * bx + by * by > 0.0016) retained++;
                }
            }
            const uint8_t *ra = a + ((size_t)(y0 + ry) * (size_t)w + (size_t)(x0 + 1)) * 3;
            const uint8_t *rb = b + ((size_t)(y0 + ry) * (size_t)w + (size_t)(x0 + 1)) * 3;
            int nbytes = (rw - 2) * 3, bi = 0;
#if defined(__aarch64__)
            uint32x4_t vacc = vdupq_n_u32(0);
            for (; bi + 16 <= nbytes; bi += 16) {
                uint8x16_t d = vabdq_u8(vld1q_u8(ra + bi), vld1q_u8(rb + bi));
                vacc = vpadalq_u16(vacc, vpaddlq_u8(d));
            }
            err_sum += (int64_t)vaddvq_u32(vacc);
#endif
            for (; bi < nbytes; bi++) {
                int d = (int)ra[bi] - (int)rb[bi];
                err_sum += d < 0 ? -d : d;
            }
            double *ta = la0; la0 = la1; la1 = la2; la2 = ta;
            double *tb = lb0; lb0 = lb1; lb1 = lb2; lb2 = tb;
        }
        free(la_rows);
        free(lb_rows);
        WValue out = w_array_new_empty();
        out = w_array_push(out, w_float(edges > 0 ? (double)retained / (double)edges : 0.0));
        out = w_array_push(out, w_float(count > 0 ? ((double)err_sum / 255.0) / (double)count : 1.0));
        out = w_array_push(out, w_int(edges));
        return out;
    }

    if (!strcmp(op, "temporal")) {
        int64_t n = (int64_t)w_media_num(w_is_array(a3) ? m_avf_arr(a3, 0) : a3, 0, "n");
        const double *f0 = a_band_f64_ptr(m_avf_arr(a1, 0), n, "first");
        const double *f1 = a_band_f64_ptr(m_avf_arr(a1, 1), n, "second");
        double *delta = a_band_f64_ptr(m_avf_arr(a1, 2), n, "delta");
        const uint8_t *m0 = a_band_u8_ptr(m_avf_arr(a2, 0), n, "mask");
        const uint8_t *m1 = a_band_u8_ptr(m_avf_arr(a2, 1), n, "next_mask");
        uint8_t *valid = a_band_u8_ptr(m_avf_arr(a2, 2), n, "valid");
        int64_t i = 0;
#if defined(__aarch64__)
        for (; i + 2 <= n; i += 2)
            vst1q_f64(delta + i, vsubq_f64(vld1q_f64(f1 + i), vld1q_f64(f0 + i)));
#endif
        for (; i < n; i++) delta[i] = f1[i] - f0[i];
        int64_t j = 0;
#if defined(__aarch64__)
        for (; j + 16 <= n; j += 16)
            vst1q_u8(valid + j, vandq_u8(vld1q_u8(m0 + j), vld1q_u8(m1 + j)));
#endif
        for (; j < n; j++) valid[j] = m0[j] & m1[j];
        return w_int(n);
    }

    if (!strcmp(op, "paint_panels")) {
        uint8_t *tile = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 0), 0, "tile_ptr");
        int64_t stride = (int64_t)w_media_num(m_avf_arr(a1, 1), 0, "stride");
        int w = (int)w_media_num(m_avf_arr(a1, 2), 0, "width");
        int h = (int)w_media_num(m_avf_arr(a1, 3), 0, "height");
        int rx = (int)w_media_num(m_avf_arr(a1, 4), 0, "rx");
        int ry = (int)w_media_num(m_avf_arr(a1, 5), 0, "ry");
        int rw = (int)w_media_num(m_avf_arr(a1, 6), 0, "rw");
        int rh = (int)w_media_num(m_avf_arr(a1, 7), 0, "rh");
        int64_t n = (int64_t)w * (int64_t)h;
        const uint8_t *src = a_band_u8_ptr(m_avf_arr(a2, 0), n * 3, "source");
        const uint8_t *dec = a_band_u8_ptr(m_avf_arr(a2, 1), n * 6, "decoded");
        const uint8_t *mask = a_band_u8_ptr(m_avf_arr(a2, 2), n, "mask");
        const double *err = a_band_f64_ptr(a3, n, "error");
        for (int py = 0; py < 240; py++) {
            uint32_t *row32 = (uint32_t *)(void *)(tile + (size_t)(24 + py) * (size_t)stride);
            for (int px = 0; px < 960; px++) row32[px] = 0xFF000000u;
        }
        for (int dy = 0; dy < rh; dy++) {
            int sy = (int)(((int64_t)(dy * 2 + 1) * h) / (rh * 2));
            if (sy >= h) sy = h - 1;
            size_t src_row = (size_t)sy * (size_t)w;
            uint8_t *dst_row = tile + (size_t)(24 + ry + dy) * (size_t)stride;
            for (int dx = 0; dx < rw; dx++) {
                int sx = (int)(((int64_t)(dx * 2 + 1) * w) / (rw * 2));
                if (sx >= w) sx = w - 1;
                size_t p = src_row + (size_t)sx;
                size_t p3 = p * 3, p6 = p * 6;
                int heat = mask[p] == 0 ? 128 : (int)llround(128.0 + 7.0 * err[p]);
                if (heat < 0) heat = 0;
                else if (heat > 255) heat = 255;
                uint8_t *o0 = dst_row + (size_t)(rx + dx) * 4;
                uint8_t *o1 = dst_row + (size_t)(320 + rx + dx) * 4;
                uint8_t *o2 = dst_row + (size_t)(640 + rx + dx) * 4;
                o0[0] = src[p3]; o0[1] = src[p3 + 1]; o0[2] = src[p3 + 2]; o0[3] = 255;
                o1[0] = (uint8_t)(((uint32_t)dec[p6] + 256u * (uint32_t)dec[p6 + 1]) / 257u);
                o1[1] = (uint8_t)(((uint32_t)dec[p6 + 2] + 256u * (uint32_t)dec[p6 + 3]) / 257u);
                o1[2] = (uint8_t)(((uint32_t)dec[p6 + 4] + 256u * (uint32_t)dec[p6 + 5]) / 257u);
                o1[3] = 255;
                o2[0] = (uint8_t)heat; o2[1] = (uint8_t)heat; o2[2] = (uint8_t)heat; o2[3] = 255;
            }
        }
        return w_int((int64_t)rw * (int64_t)rh);
    }

    w_media_raise("w_media_banding_op: unknown op '%s'", op);
}

/* ======================================================================
   Studio Audio Native Bridges: ExtAudioFile + Mastering SRC, vDSP FFT, Hardlink
   ====================================================================== */

static size_t a_wav_f32_header(uint8_t hdr[80], int rf64, int64_t frames, int32_t sr, int32_t ch) {
    uint64_t data_bytes = (uint64_t)frames * (uint64_t)ch * 4ULL;
    if (!rf64) {
        memcpy(hdr + 0, "RIFF", 4);
        a_le32_put(hdr + 4, (uint32_t)(36ULL + data_bytes));
        memcpy(hdr + 8, "WAVEfmt ", 8);
        a_le32_put(hdr + 16, 16);
        a_le16_put(hdr + 20, 3); /* WAVE_FORMAT_IEEE_FLOAT */
        a_le16_put(hdr + 22, (uint16_t)ch);
        a_le32_put(hdr + 24, (uint32_t)sr);
        a_le32_put(hdr + 28, (uint32_t)(sr * ch * 4));
        a_le16_put(hdr + 32, (uint16_t)(ch * 4));
        a_le16_put(hdr + 34, 32);
        memcpy(hdr + 36, "data", 4);
        a_le32_put(hdr + 40, (uint32_t)data_bytes);
        return 44;
    }
    uint64_t riff_bytes = 72ULL + data_bytes;
    memcpy(hdr + 0, "RF64", 4);
    a_le32_put(hdr + 4, 0xFFFFFFFFu);
    memcpy(hdr + 8, "WAVEds64", 8);
    a_le32_put(hdr + 16, 28);
    a_le64_put(hdr + 20, riff_bytes);
    a_le64_put(hdr + 28, data_bytes);
    a_le64_put(hdr + 36, (uint64_t)frames);
    a_le32_put(hdr + 44, 0);
    memcpy(hdr + 48, "fmt ", 4);
    a_le32_put(hdr + 52, 16);
    a_le16_put(hdr + 56, 3);
    a_le16_put(hdr + 58, (uint16_t)ch);
    a_le32_put(hdr + 60, (uint32_t)sr);
    a_le32_put(hdr + 64, (uint32_t)(sr * ch * 4));
    a_le16_put(hdr + 68, (uint16_t)(ch * 4));
    a_le16_put(hdr + 70, 32);
    memcpy(hdr + 72, "data", 4);
    a_le32_put(hdr + 76, 0xFFFFFFFFu);
    return 80;
}

typedef struct AAudConvIn {
    const float *pcm;
    int64_t      total_frames;
    int64_t      pos;
    int32_t      ch;
} AAudConvIn;

static OSStatus a_aud_conv_proc(AudioConverterRef conv, UInt32 *io_packets, AudioBufferList *io_data,
                                AudioStreamPacketDescription **out_desc, void *user) {
    (void)conv;
    AAudConvIn *in = user;
    if (out_desc) *out_desc = NULL;
    int64_t rem = in->total_frames - in->pos;
    if (rem <= 0) {
        *io_packets = 0;
        io_data->mBuffers[0].mData = NULL;
        io_data->mBuffers[0].mDataByteSize = 0;
        return noErr;
    }
    UInt32 take = (UInt32)(rem < (int64_t)(*io_packets) ? rem : (int64_t)(*io_packets));
    io_data->mBuffers[0].mNumberChannels = (UInt32)in->ch;
    io_data->mBuffers[0].mDataByteSize = take * (UInt32)in->ch * (UInt32)sizeof(float);
    io_data->mBuffers[0].mData = (void *)(in->pcm + (size_t)in->pos * (size_t)in->ch);
    in->pos += (int64_t)take;
    *io_packets = take;
    return noErr;
}

/* w_media_audio_decode_f32(src_path, dst_wav_path, [target_sr, trim_head_frames, trim_tail_frames]) -> [frames, sr, ch]
 * Decodes via ExtAudioFile at native rate, drops trim_head frames off the start and trim_tail frames off the end,
 * and resamples with AudioConverter mastering ('bats', quality 127) when target_sr > 0 && target_sr != src_sr. */
WValue w_media_audio_decode_f32(WValue srcv, WValue dstv, WValue optv) {
    @autoreleasepool {
        char src[4096], dst[4096], tmp[4200];
        if (!w_media_str(srcv, src, sizeof src) || !src[0]) w_media_raise("audio_decode_f32: src must be a path");
        if (!w_media_str(dstv, dst, sizeof dst) || !dst[0]) w_media_raise("audio_decode_f32: dst must be a path");
        int32_t target_sr = (int32_t)w_media_num(m_avf_arr(optv, 0), 0, "target_sr");
        int64_t trim_head = (int64_t)w_media_num(m_avf_arr(optv, 1), 0, "trim_head");
        int64_t trim_tail = (int64_t)w_media_num(m_avf_arr(optv, 2), 0, "trim_tail");
        if (trim_head < 0) trim_head = 0;
        if (trim_tail < 0) trim_tail = 0;

        CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)src, (CFIndex)strlen(src), false);
        ExtAudioFileRef ef = NULL;
        OSStatus os = url ? ExtAudioFileOpenURL(url, &ef) : -1;
        if (url) CFRelease(url);
        if (os != noErr || !ef) w_media_raise("audio_decode_f32: cannot open %s (OSStatus %d)", src, (int)os);

        AudioStreamBasicDescription ffmt;
        UInt32 fsz = sizeof ffmt;
        memset(&ffmt, 0, sizeof ffmt);
        os = ExtAudioFileGetProperty(ef, kExtAudioFileProperty_FileDataFormat, &fsz, &ffmt);
        int32_t src_sr = (int32_t)llround(ffmt.mSampleRate);
        int32_t ch = (int32_t)ffmt.mChannelsPerFrame;
        if (os != noErr || src_sr <= 0 || ch < 1 || ch > 8) {
            ExtAudioFileDispose(ef);
            w_media_raise("audio_decode_f32: unsupported format in %s", src);
        }

        SInt64 len_hint = 0;
        UInt32 lsz = sizeof len_hint;
        ExtAudioFileGetProperty(ef, kExtAudioFileProperty_FileLengthFrames, &lsz, &len_hint);

        AudioStreamBasicDescription cfmt;
        memset(&cfmt, 0, sizeof cfmt);
        cfmt.mSampleRate = (Float64)src_sr;
        cfmt.mFormatID = kAudioFormatLinearPCM;
        cfmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        cfmt.mChannelsPerFrame = (UInt32)ch;
        cfmt.mBitsPerChannel = 32;
        cfmt.mBytesPerFrame = 4u * (UInt32)ch;
        cfmt.mFramesPerPacket = 1;
        cfmt.mBytesPerPacket = cfmt.mBytesPerFrame;
        os = ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ClientDataFormat, sizeof cfmt, &cfmt);
        if (os != noErr) {
            ExtAudioFileDispose(ef);
            w_media_raise("audio_decode_f32: client format error (OSStatus %d)", (int)os);
        }

        int64_t cap_f = len_hint > 0 ? (int64_t)len_hint + 4096 : 65536;
        float *pcm = malloc((size_t)(cap_f > 0 ? cap_f : 1) * (size_t)ch * sizeof(float));
        float *chunk = malloc(16384u * (size_t)ch * sizeof(float));
        int64_t raw_pos = 0, kept = 0;
        for (;;) {
            UInt32 nf = 16384;
            AudioBufferList abl;
            abl.mNumberBuffers = 1;
            abl.mBuffers[0].mNumberChannels = (UInt32)ch;
            abl.mBuffers[0].mDataByteSize = nf * (UInt32)ch * (UInt32)sizeof(float);
            abl.mBuffers[0].mData = chunk;
            os = ExtAudioFileRead(ef, &nf, &abl);
            if (os != noErr) {
                free(pcm); free(chunk); ExtAudioFileDispose(ef);
                w_media_raise("audio_decode_f32: read failed on %s (OSStatus %d)", src, (int)os);
            }
            if (nf == 0) break;
            int64_t b0 = raw_pos, b1 = raw_pos + (int64_t)nf;
            raw_pos = b1;
            int64_t s0 = b0 < trim_head ? trim_head : b0;
            if (b1 > s0) {
                int64_t take = b1 - s0;
                if (kept + take > cap_f) {
                    cap_f = (kept + take) * 2;
                    pcm = realloc(pcm, (size_t)cap_f * (size_t)ch * sizeof(float));
                }
                memcpy(pcm + (size_t)kept * (size_t)ch,
                       chunk + (size_t)(s0 - b0) * (size_t)ch,
                       (size_t)take * (size_t)ch * sizeof(float));
                kept += take;
            }
        }
        free(chunk);
        ExtAudioFileDispose(ef);
        if (trim_tail > 0) {
            if (kept <= trim_tail) {
                free(pcm);
                w_media_raise("audio_decode_f32: cannot trim %s", src);
            }
            kept -= trim_tail;
        }

        int32_t out_sr = target_sr > 0 ? target_sr : src_sr;
        float *out_pcm = pcm;
        int64_t out_frames = kept;

        if (out_sr != src_sr && kept > 0) {
            AudioStreamBasicDescription ofmt = cfmt;
            ofmt.mSampleRate = (Float64)out_sr;
            AudioConverterRef conv = NULL;
            os = AudioConverterNew(&cfmt, &ofmt, &conv);
            if (os != noErr || !conv) {
                free(pcm);
                w_media_raise("audio_decode_f32: AudioConverterNew %d -> %d Hz failed (OSStatus %d)", (int)src_sr, (int)out_sr, (int)os);
            }
            UInt32 complexity = kAudioConverterSampleRateConverterComplexity_Mastering;
            AudioConverterSetProperty(conv, kAudioConverterSampleRateConverterComplexity, sizeof complexity, &complexity);
            UInt32 qual = kAudioConverterQuality_Max;
            AudioConverterSetProperty(conv, kAudioConverterSampleRateConverterQuality, sizeof qual, &qual);

            int64_t ocap = (int64_t)ceil((double)kept * (double)out_sr / (double)src_sr) + 4096;
            out_pcm = malloc((size_t)ocap * (size_t)ch * sizeof(float));
            out_frames = 0;
            AAudConvIn cin = {pcm, kept, 0, ch};
            for (;;) {
                if (out_frames + 8192 > ocap) {
                    ocap = (out_frames + 8192) * 2;
                    out_pcm = realloc(out_pcm, (size_t)ocap * (size_t)ch * sizeof(float));
                }
                UInt32 pkts = 8192;
                AudioBufferList oabl;
                oabl.mNumberBuffers = 1;
                oabl.mBuffers[0].mNumberChannels = (UInt32)ch;
                oabl.mBuffers[0].mDataByteSize = pkts * (UInt32)ch * (UInt32)sizeof(float);
                oabl.mBuffers[0].mData = out_pcm + (size_t)out_frames * (size_t)ch;
                os = AudioConverterFillComplexBuffer(conv, a_aud_conv_proc, &cin, &pkts, &oabl, NULL);
                if (os != noErr) {
                    AudioConverterDispose(conv); free(pcm); free(out_pcm);
                    w_media_raise("audio_decode_f32: resampling failed (OSStatus %d)", (int)os);
                }
                if (pkts == 0) break;
                out_frames += (int64_t)pkts;
            }
            AudioConverterDispose(conv);
            free(pcm);
        }

        uint64_t data_bytes = (uint64_t)out_frames * (uint64_t)ch * 4ULL;
        int rf64 = data_bytes >= 0xFFFFFF00ULL;
        uint8_t hdr[80];
        size_t hlen = a_wav_f32_header(hdr, rf64, out_frames, out_sr, ch);
        static _Atomic uint32_t s_dec_seq = 0;
        snprintf(tmp, sizeof tmp, "%s.tmp%d_%u", dst, (int)getpid(),
                 atomic_fetch_add_explicit(&s_dec_seq, 1u, memory_order_relaxed));
        FILE *f = fopen(tmp, "wb");
        if (!f) {
            free(out_pcm);
            w_media_raise("audio_decode_f32: cannot create %s: %s", tmp, strerror(errno));
        }
        int wok = fwrite(hdr, 1, hlen, f) == hlen;
        if (wok && data_bytes > 0) wok = fwrite(out_pcm, 1, (size_t)data_bytes, f) == (size_t)data_bytes;
        wok = (fclose(f) == 0) && wok;
        free(out_pcm);
        if (!wok || rename(tmp, dst) != 0) {
            unlink(tmp);
            w_media_raise("audio_decode_f32: writing %s failed: %s", dst, strerror(errno));
        }
        WValue res = w_array_new_empty();
        res = w_array_push(res, w_int(out_frames));
        res = w_array_push(res, w_int(out_sr));
        res = w_array_push(res, w_int(ch));
        return res;
    }
}

typedef struct { double *realp; double *imagp; } AVDSPSplitD;
typedef void *(*a_vdsp_create_fn)(unsigned long, int);
typedef void  (*a_vdsp_zip_fn)(void *, const AVDSPSplitD *, long, unsigned long, int);

static pthread_once_t g_vdsp_once = PTHREAD_ONCE_INIT;
static a_vdsp_create_fn g_vdsp_create = NULL;
static a_vdsp_zip_fn g_vdsp_zip = NULL;
static pthread_mutex_t g_vdsp_mu = PTHREAD_MUTEX_INITIALIZER;
static void *g_vdsp_setup = NULL;
static unsigned long g_vdsp_log2 = 0;

static void a_vdsp_load(void) {
    void *h = dlopen("/System/Library/Frameworks/Accelerate.framework/Accelerate", RTLD_LAZY | RTLD_LOCAL);
    if (!h) return;
    g_vdsp_create = (a_vdsp_create_fn)dlsym(h, "vDSP_create_fftsetupD");
    g_vdsp_zip = (a_vdsp_zip_fn)dlsym(h, "vDSP_fft_zipD");
}

/* w_media_vdsp_fft(re_f64, im_f64, n, dir) -> true/false (dir >= 0 forward, dir < 0 inverse, unscaled) */
WValue w_media_vdsp_fft(WValue rev, WValue imv, WValue nv, WValue dirv) {
    int64_t n = (int64_t)w_media_num(w_is_array(nv) ? m_avf_arr(nv, 0) : nv, 0, "n");
    int dir = (int)w_media_num(w_is_array(dirv) ? m_avf_arr(dirv, 0) : dirv, 1, "dir");
    if (n < 2 || (n & (n - 1)) != 0 || !w_is_array(rev) || !w_is_array(imv)) return W_FALSE;
    WArray *ra = w_as_array(rev), *ia = w_as_array(imv);
    if (ra->ebits != -64 || ia->ebits != -64 || ra->size < n || ia->size < n) return W_FALSE;
    pthread_once(&g_vdsp_once, a_vdsp_load);
    if (!g_vdsp_create || !g_vdsp_zip) return W_FALSE;
    unsigned long log2n = (unsigned long)__builtin_ctzll((unsigned long long)n);
    pthread_mutex_lock(&g_vdsp_mu);
    if (log2n > g_vdsp_log2 || !g_vdsp_setup) {
        unsigned long want = log2n < 18 ? 18 : log2n;
        void *ns = g_vdsp_create(want, 0 /* kFFTRadix2 */);
        if (ns) {
            g_vdsp_setup = ns;
            g_vdsp_log2 = want;
        }
    }
    void *setup = g_vdsp_setup;
    unsigned long cap_log2 = g_vdsp_log2;
    pthread_mutex_unlock(&g_vdsp_mu);
    if (!setup || log2n > cap_log2) return W_FALSE;
    AVDSPSplitD split = {(double *)ra->slots + ra->start, (double *)ia->slots + ia->start};
    g_vdsp_zip(setup, &split, 1, log2n, dir >= 0 ? 1 : -1);
    return W_TRUE;
}

/* w_media_hardlink(src_path, dst_path) -> true/false (if src_path is "", exclusive atomic mkdir(dst_path)) */
WValue w_media_hardlink(WValue srcv, WValue dstv) {
    char src[4096], dst[4096];
    if (!w_media_str(dstv, dst, sizeof dst) || !dst[0] || !w_media_str(srcv, src, sizeof src))
        return W_FALSE;
    if (!src[0])
        return mkdir(dst, 0700) == 0 ? W_TRUE : W_FALSE;
    unlink(dst);
    return link(src, dst) == 0 ? W_TRUE : W_FALSE;
}

/* ======================================================================
   Studio Raster & Audio SIMD/GCD Kernels (w_media_studio_op)
   ====================================================================== */

static float *a_stu_f32_ptr(WValue v, int64_t min_len, const char *what) {
    if (!w_is_array(v)) w_media_raise("studio_op(%s): expected f32[]", what);
    WArray *a = w_as_array(v);
    if (a->ebits != -32 || a->size < min_len)
        w_media_raise("studio_op(%s): expected f32[] of size >= %lld", what, (long long)min_len);
    return (float *)a->slots + a->start;
}

static int32_t *a_stu_i32_ptr(WValue v, int64_t min_len, const char *what) {
    if (!w_is_array(v)) w_media_raise("studio_op(%s): expected i32[]", what);
    WArray *a = w_as_array(v);
    if ((a->ebits != 32 && a->ebits != 33) || a->size < min_len)
        w_media_raise("studio_op(%s): expected i32[] of size >= %lld", what, (long long)min_len);
    return (int32_t *)a->slots + a->start;
}

static double a_stu_num0(WValue v, double def, const char *what) {
    return w_is_array(v) ? w_media_num(m_avf_arr(v, 0), def, what) : w_media_num(v, def, what);
}

typedef struct AStuRgbaCtx {
    const uint8_t *a;
    uint8_t       *b;
    size_t         stride;
    int            w, h;
    double         t;
} AStuRgbaCtx;

static void a_stu_mix_rgba_band(void *ctxp, size_t bi) {
    AStuRgbaCtx *c = ctxp;
    int y0 = (int)((int64_t)c->h * (int64_t)bi / 4), y1 = (int)((int64_t)c->h * (int64_t)(bi + 1) / 4);
    double t = c->t, s = 1.0 - t;
#if defined(__aarch64__)
    float32x4_t vs = vdupq_n_f32((float)s), vt = vdupq_n_f32((float)t), vhalf = vdupq_n_f32(0.5f);
    uint8x16_t v255 = vdupq_n_u8(255);
#endif
    for (int y = y0; y < y1; y++) {
        const uint8_t *ra = c->a + (size_t)y * c->stride;
        uint8_t *rb = c->b + (size_t)y * c->stride;
        int x = 0;
#if defined(__aarch64__)
        for (; x + 16 <= c->w; x += 16) {
            uint8x16x4_t pa = vld4q_u8(ra + (size_t)x * 4);
            uint8x16x4_t pb = vld4q_u8(rb + (size_t)x * 4);
            uint8x16x4_t po;
            for (int ch = 0; ch < 3; ch++) {
                uint16x8_t alo = vmovl_u8(vget_low_u8(pa.val[ch])), ahi = vmovl_high_u8(pa.val[ch]);
                uint16x8_t blo = vmovl_u8(vget_low_u8(pb.val[ch])), bhi = vmovl_high_u8(pb.val[ch]);
                float32x4_t f0 = vfmaq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_u16(vget_low_u16(alo))), vs),
                                           vcvtq_f32_u32(vmovl_u16(vget_low_u16(blo))), vt);
                float32x4_t f1 = vfmaq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_high_u16(alo)), vs),
                                           vcvtq_f32_u32(vmovl_high_u16(blo)), vt);
                float32x4_t f2 = vfmaq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_u16(vget_low_u16(ahi))), vs),
                                           vcvtq_f32_u32(vmovl_u16(vget_low_u16(bhi))), vt);
                float32x4_t f3 = vfmaq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_high_u16(ahi)), vs),
                                           vcvtq_f32_u32(vmovl_high_u16(bhi)), vt);
                uint16x8_t u0 = vcombine_u16(vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f0))),
                                             vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f1))));
                uint16x8_t u1 = vcombine_u16(vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f2))),
                                             vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f3))));
                po.val[ch] = vcombine_u8(vqmovn_u16(u0), vqmovn_u16(u1));
            }
            po.val[3] = v255;
            vst4q_u8(rb + (size_t)x * 4, po);
        }
#endif
        for (; x < c->w; x++) {
            size_t p = (size_t)x * 4;
            for (int ch = 0; ch < 3; ch++) {
                double v = (double)ra[p + ch] * s + (double)rb[p + ch] * t;
                int iv = (int)floor(v + 0.5);
                rb[p + ch] = (uint8_t)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
            }
            rb[p + 3] = 255;
        }
    }
}

static void a_stu_scale_rgba_band(void *ctxp, size_t bi) {
    AStuRgbaCtx *c = ctxp;
    int y0 = (int)((int64_t)c->h * (int64_t)bi / 4), y1 = (int)((int64_t)c->h * (int64_t)(bi + 1) / 4);
    double s = c->t;
#if defined(__aarch64__)
    float32x4_t vs = vdupq_n_f32((float)s), vhalf = vdupq_n_f32(0.5f), vzero = vdupq_n_f32(0.0f);
#endif
    for (int y = y0; y < y1; y++) {
        uint8_t *rb = c->b + (size_t)y * c->stride;
        int x = 0;
#if defined(__aarch64__)
        for (; x + 16 <= c->w; x += 16) {
            uint8x16x4_t pb = vld4q_u8(rb + (size_t)x * 4);
            for (int ch = 0; ch < 3; ch++) {
                uint16x8_t blo = vmovl_u8(vget_low_u8(pb.val[ch])), bhi = vmovl_high_u8(pb.val[ch]);
                float32x4_t f0 = vmaxq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_u16(vget_low_u16(blo))), vs), vzero);
                float32x4_t f1 = vmaxq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_high_u16(blo)), vs), vzero);
                float32x4_t f2 = vmaxq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_u16(vget_low_u16(bhi))), vs), vzero);
                float32x4_t f3 = vmaxq_f32(vfmaq_f32(vhalf, vcvtq_f32_u32(vmovl_high_u16(bhi)), vs), vzero);
                uint16x8_t u0 = vcombine_u16(vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f0))),
                                             vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f1))));
                uint16x8_t u1 = vcombine_u16(vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f2))),
                                             vqmovn_u32(vcvtq_u32_f32(vrndmq_f32(f3))));
                pb.val[ch] = vcombine_u8(vqmovn_u16(u0), vqmovn_u16(u1));
            }
            vst4q_u8(rb + (size_t)x * 4, pb);
        }
#endif
        for (; x < c->w; x++) {
            size_t p = (size_t)x * 4;
            for (int ch = 0; ch < 3; ch++) {
                double v = (double)rb[p + ch] * s;
                int iv = (int)floor(v + 0.5);
                rb[p + ch] = (uint8_t)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
            }
        }
    }
}

#pragma clang fp contract(off)

static double a_stu_tp_at(const float *bus, int64_t i, int c, const double *h) {
    double tp = fabs((double)bus[i * 2 + c]);
    for (int p = 0; p < 4; p++) {
        const double *hp = h + p * 12;
        double acc = 0.0;
        for (int k = 0; k < 12; k++)
            acc += (double)bus[(i + k - 5) * 2 + c] * hp[k];
        acc = fabs(acc);
        if (acc > tp) tp = acc;
    }
    return tp;
}

WValue w_media_studio_op(WValue opv, WValue a1, WValue a2, WValue a3) {
    char op[32];
    w_media_str(opv, op, sizeof op);

    if (!strcmp(op, "mix_rgba")) {
        const uint8_t *a = (const uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 0), 0, "a");
        uint8_t *b = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 1), 0, "b");
        size_t stride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 2), 0, "stride");
        int w = (int)w_media_num(m_avf_arr(a1, 3), 0, "w");
        int h = (int)w_media_num(m_avf_arr(a1, 4), 0, "h");
        double t = a_stu_num0(a2, 0.0, "t");
        AStuRgbaCtx ctx = {a, b, stride, w, h, t};
        if ((int64_t)w * (int64_t)h >= 131072)
            dispatch_apply_f(4, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_stu_mix_rgba_band);
        else
            for (size_t bi = 0; bi < 4; bi++) a_stu_mix_rgba_band(&ctx, bi);
        return w_int(0);
    }

    if (!strcmp(op, "scale_rgba")) {
        uint8_t *dst = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 0), 0, "dst");
        size_t stride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 1), 0, "stride");
        int w = (int)w_media_num(m_avf_arr(a1, 2), 0, "w");
        int h = (int)w_media_num(m_avf_arr(a1, 3), 0, "h");
        double s = a_stu_num0(a2, 1.0, "s");
        AStuRgbaCtx ctx = {NULL, dst, stride, w, h, s};
        if ((int64_t)w * (int64_t)h >= 131072)
            dispatch_apply_f(4, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), &ctx, a_stu_scale_rgba_band);
        else
            for (size_t bi = 0; bi < 4; bi++) a_stu_scale_rgba_band(&ctx, bi);
        return w_int(0);
    }

    if (!strcmp(op, "copy_rgb")) {
        int64_t src_addr = (int64_t)w_media_num(m_avf_arr(a1, 0), 0, "src");
        size_t stride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 1), 0, "stride");
        int w = (int)w_media_num(m_avf_arr(a1, 2), 0, "w");
        int y0 = (int)w_media_num(m_avf_arr(a1, 3), 0, "y0");
        int y1 = (int)w_media_num(m_avf_arr(a1, 4), 0, "y1");
        int depth = (int)w_media_num(m_avf_arr(a1, 5), 8, "depth");
        int bpp = depth == 16 ? 6 : 3;
        if (y1 <= y0 || w <= 0) return w_int(0);
        const uint8_t *src = src_addr != 0
            ? (const uint8_t *)(uintptr_t)src_addr
            : a_band_u8_ptr(a3, (int64_t)(y1 - 1) * (int64_t)stride + (int64_t)w * 4, "src_u8");
        uint8_t *out = a_band_u8_ptr(a2, (int64_t)y1 * (int64_t)w * bpp, "out");
        for (int y = y0; y < y1; y++) {
            const uint8_t *sp = src + (size_t)y * stride;
            uint8_t *dp = out + (size_t)y * (size_t)w * (size_t)bpp;
            int x = 0;
            if (depth == 16) {
#if defined(__aarch64__)
                for (; x + 8 <= w; x += 8) {
                    uint8x8x4_t px = vld4_u8(sp + (size_t)x * 4);
                    uint16x8x3_t o16;
                    o16.val[0] = vorrq_u16(vshll_n_u8(px.val[0], 8), vmovl_u8(px.val[0]));
                    o16.val[1] = vorrq_u16(vshll_n_u8(px.val[1], 8), vmovl_u8(px.val[1]));
                    o16.val[2] = vorrq_u16(vshll_n_u8(px.val[2], 8), vmovl_u8(px.val[2]));
                    vst3q_u16((uint16_t *)(void *)(dp + (size_t)x * 6), o16);
                }
#endif
                for (; x < w; x++) {
                    uint16_t r = (uint16_t)sp[x * 4] * 257u;
                    uint16_t g = (uint16_t)sp[x * 4 + 1] * 257u;
                    uint16_t b = (uint16_t)sp[x * 4 + 2] * 257u;
                    size_t d = (size_t)x * 6;
                    dp[d] = (uint8_t)(r & 0xFF); dp[d + 1] = (uint8_t)(r >> 8);
                    dp[d + 2] = (uint8_t)(g & 0xFF); dp[d + 3] = (uint8_t)(g >> 8);
                    dp[d + 4] = (uint8_t)(b & 0xFF); dp[d + 5] = (uint8_t)(b >> 8);
                }
            } else {
#if defined(__aarch64__)
                for (; x + 16 <= w; x += 16) {
                    uint8x16x4_t px = vld4q_u8(sp + (size_t)x * 4);
                    uint8x16x3_t o8 = {{px.val[0], px.val[1], px.val[2]}};
                    vst3q_u8(dp + (size_t)x * 3, o8);
                }
#endif
                for (; x < w; x++) {
                    dp[x * 3] = sp[x * 4];
                    dp[x * 3 + 1] = sp[x * 4 + 1];
                    dp[x * 3 + 2] = sp[x * 4 + 2];
                }
            }
        }
        return w_int(0);
    }

    if (!strcmp(op, "rgb_to_canvas")) {
        int w = (int)w_media_num(m_avf_arr(a2, 0), 0, "w");
        int y0 = (int)w_media_num(m_avf_arr(a2, 1), 0, "y0");
        int y1 = (int)w_media_num(m_avf_arr(a2, 2), 0, "y1");
        uint8_t *dst = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a2, 3), 0, "dst");
        size_t stride = (size_t)(int64_t)w_media_num(m_avf_arr(a2, 4), 0, "stride");
        if (y1 <= y0 || w <= 0) return w_int(0);
        const uint8_t *src = a_band_u8_ptr(a1, (int64_t)y1 * (int64_t)w * 3, "src");
#if defined(__aarch64__)
        uint8x16_t v255 = vdupq_n_u8(255);
#endif
        for (int y = y0; y < y1; y++) {
            const uint8_t *sp = src + (size_t)y * (size_t)w * 3;
            uint8_t *dp = dst + (size_t)y * stride;
            int x = 0;
#if defined(__aarch64__)
            for (; x + 16 <= w; x += 16) {
                uint8x16x3_t rgb = vld3q_u8(sp + (size_t)x * 3);
                uint8x16x4_t rgba = {{rgb.val[0], rgb.val[1], rgb.val[2], v255}};
                vst4q_u8(dp + (size_t)x * 4, rgba);
            }
#endif
            for (; x < w; x++) {
                dp[x * 4] = sp[x * 3];
                dp[x * 4 + 1] = sp[x * 3 + 1];
                dp[x * 4 + 2] = sp[x * 3 + 2];
                dp[x * 4 + 3] = 255;
            }
        }
        return w_int(0);
    }

    if (!strcmp(op, "copy_rows")) {
        const uint8_t *src = (const uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 0), 0, "src");
        size_t sstride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 1), 0, "sstride");
        size_t xoff = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 2), 0, "xoff");
        uint8_t *dst = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 3), 0, "dst");
        size_t dstride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 4), 0, "dstride");
        size_t rbytes = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 5), 0, "rbytes");
        int rows = (int)w_media_num(m_avf_arr(a1, 6), 0, "rows");
        if (rows <= 0 || rbytes == 0) return w_int(0);
        if (xoff == 0 && sstride == dstride && rbytes == sstride) {
            memcpy(dst, src, (size_t)rows * sstride);
        } else {
            for (int y = 0; y < rows; y++)
                memcpy(dst + (size_t)y * dstride, src + (size_t)y * sstride + xoff, rbytes);
        }
        return w_int(0);
    }

    if (!strcmp(op, "fill_rows")) {
        uint8_t *dst = (uint8_t *)(uintptr_t)(int64_t)w_media_num(m_avf_arr(a1, 0), 0, "dst");
        size_t stride = (size_t)(int64_t)w_media_num(m_avf_arr(a1, 1), 0, "stride");
        int w = (int)w_media_num(m_avf_arr(a1, 2), 0, "w");
        int y0 = (int)w_media_num(m_avf_arr(a1, 3), 0, "y0");
        int y1 = (int)w_media_num(m_avf_arr(a1, 4), 0, "y1");
        uint32_t r = (uint32_t)((int)w_media_num(m_avf_arr(a1, 5), 0, "r") & 255);
        uint32_t g = (uint32_t)((int)w_media_num(m_avf_arr(a1, 6), 0, "g") & 255);
        uint32_t b = (uint32_t)((int)w_media_num(m_avf_arr(a1, 7), 0, "b") & 255);
        uint32_t px = r | (g << 8) | (b << 16) | 0xFF000000u;
#if defined(__aarch64__)
        uint32x4_t vpx = vdupq_n_u32(px);
#endif
        for (int y = y0; y < y1; y++) {
            uint32_t *row = (uint32_t *)(void *)(dst + (size_t)y * stride);
            int x = 0;
#if defined(__aarch64__)
            for (; x + 4 <= w; x += 4) vst1q_u32(row + x, vpx);
#endif
            for (; x < w; x++) row[x] = px;
        }
        return w_int(0);
    }

    if (!strcmp(op, "cmul1")) {
        int64_t n = (int64_t)a_stu_num0(a3, 0, "n");
        double *re = a_band_f64_ptr(m_avf_arr(a1, 0), n, "re");
        double *im = a_band_f64_ptr(m_avf_arr(a1, 1), n, "im");
        const double *hr = a_band_f64_ptr(m_avf_arr(a2, 0), n, "hr");
        const double *hi = a_band_f64_ptr(m_avf_arr(a2, 1), n, "hi");
        int64_t i = 0;
#if defined(__aarch64__)
        for (; i + 2 <= n; i += 2) {
            float64x2_t xr = vld1q_f64(re + i), xi = vld1q_f64(im + i);
            float64x2_t kr = vld1q_f64(hr + i), ki = vld1q_f64(hi + i);
            vst1q_f64(re + i, vsubq_f64(vmulq_f64(xr, kr), vmulq_f64(xi, ki)));
            vst1q_f64(im + i, vaddq_f64(vmulq_f64(xr, ki), vmulq_f64(xi, kr)));
        }
#endif
        for (; i < n; i++) {
            double r = re[i] * hr[i] - im[i] * hi[i];
            double q = re[i] * hi[i] + im[i] * hr[i];
            re[i] = r; im[i] = q;
        }
        return w_int(0);
    }

    if (!strcmp(op, "cmul2")) {
        int64_t n = (int64_t)a_stu_num0(a3, 0, "n");
        double *re = a_band_f64_ptr(m_avf_arr(a1, 0), n, "re");
        double *im = a_band_f64_ptr(m_avf_arr(a1, 1), n, "im");
        double *ar = a_band_f64_ptr(m_avf_arr(a1, 2), n, "ar");
        double *ai = a_band_f64_ptr(m_avf_arr(a1, 3), n, "ai");
        const double *h0r = a_band_f64_ptr(m_avf_arr(a2, 0), n, "h0r");
        const double *h0i = a_band_f64_ptr(m_avf_arr(a2, 1), n, "h0i");
        const double *h1r = a_band_f64_ptr(m_avf_arr(a2, 2), n, "h1r");
        const double *h1i = a_band_f64_ptr(m_avf_arr(a2, 3), n, "h1i");
        int64_t i = 0;
#if defined(__aarch64__)
        for (; i + 2 <= n; i += 2) {
            float64x2_t xr = vld1q_f64(re + i), xi = vld1q_f64(im + i);
            float64x2_t k0r = vld1q_f64(h0r + i), k0i = vld1q_f64(h0i + i);
            float64x2_t k1r = vld1q_f64(h1r + i), k1i = vld1q_f64(h1i + i);
            vst1q_f64(ar + i, vsubq_f64(vmulq_f64(xr, k1r), vmulq_f64(xi, k1i)));
            vst1q_f64(ai + i, vaddq_f64(vmulq_f64(xr, k1i), vmulq_f64(xi, k1r)));
            vst1q_f64(re + i, vsubq_f64(vmulq_f64(xr, k0r), vmulq_f64(xi, k0i)));
            vst1q_f64(im + i, vaddq_f64(vmulq_f64(xr, k0i), vmulq_f64(xi, k0r)));
        }
#endif
        for (; i < n; i++) {
            double xr = re[i], xi = im[i];
            ar[i] = xr * h1r[i] - xi * h1i[i];
            ai[i] = xr * h1i[i] + xi * h1r[i];
            re[i] = xr * h0r[i] - xi * h0i[i];
            im[i] = xr * h0i[i] + xi * h0r[i];
        }
        return w_int(0);
    }

    if (!strcmp(op, "add_run")) {
        int64_t n = (int64_t)w_media_num(m_avf_arr(a2, 0), 0, "n");
        int64_t p0 = (int64_t)w_media_num(m_avf_arr(a2, 1), 0, "p0");
        int64_t m = (int64_t)w_media_num(m_avf_arr(a2, 2), 0, "m");
        int64_t j = p0 < 0 ? -p0 : 0;
        int64_t e = p0 + m > n ? n - p0 : m;
        if (j >= e) return w_int(0);
        double *out = a_band_f64_ptr(m_avf_arr(a1, 0), p0 + e, "out");
        const double *y = a_band_f64_ptr(m_avf_arr(a1, 1), e, "y");
#if defined(__aarch64__)
        for (; j + 2 <= e; j += 2)
            vst1q_f64(out + p0 + j, vaddq_f64(vld1q_f64(out + p0 + j), vld1q_f64(y + j)));
#endif
        for (; j < e; j++) out[p0 + j] += y[j];
        return w_int(0);
    }

    if (!strcmp(op, "reverb_mix")) {
        int64_t n = (int64_t)w_media_num(m_avf_arr(a2, 0), 0, "n");
        int64_t total = (int64_t)w_media_num(m_avf_arr(a2, 1), 0, "total");
        double wet = w_media_num(m_avf_arr(a3, 0), 0.0, "wet");
        double pl = w_media_num(m_avf_arr(a3, 1), 1.0, "pl");
        double pr = w_media_num(m_avf_arr(a3, 2), 1.0, "pr");
        double dry = 1.0 - wet * 0.5;
        const double *x = a_band_f64_ptr(m_avf_arr(a1, 0), n, "x");
        double *outl = a_band_f64_ptr(m_avf_arr(a1, 1), total, "outl");
        double *outr = a_band_f64_ptr(m_avf_arr(a1, 2), total, "outr");
        int64_t lim = n < total ? n : total;
        int64_t i = 0;
#if defined(__aarch64__)
        float64x2_t vdry = vdupq_n_f64(dry), vwet = vdupq_n_f64(wet);
        float64x2_t vpl = vdupq_n_f64(pl), vpr = vdupq_n_f64(pr), vz = vdupq_n_f64(0.0);
        for (; i + 2 <= lim; i += 2) {
            float64x2_t dx = vmulq_f64(vld1q_f64(x + i), vdry);
            vst1q_f64(outl + i, vmulq_f64(vaddq_f64(dx, vmulq_f64(vld1q_f64(outl + i), vwet)), vpl));
            vst1q_f64(outr + i, vmulq_f64(vaddq_f64(dx, vmulq_f64(vld1q_f64(outr + i), vwet)), vpr));
        }
        for (; i < lim; i++) {
            double dx = x[i] * dry;
            outl[i] = (dx + outl[i] * wet) * pl;
            outr[i] = (dx + outr[i] * wet) * pr;
        }
        for (; i + 2 <= total; i += 2) {
            vst1q_f64(outl + i, vmulq_f64(vaddq_f64(vz, vmulq_f64(vld1q_f64(outl + i), vwet)), vpl));
            vst1q_f64(outr + i, vmulq_f64(vaddq_f64(vz, vmulq_f64(vld1q_f64(outr + i), vwet)), vpr));
        }
#endif
        for (; i < total; i++) {
            double d = i < n ? x[i] : 0.0;
            outl[i] = (d * dry + outl[i] * wet) * pl;
            outr[i] = (d * dry + outr[i] * wet) * pr;
        }
        return w_int(0);
    }

    if (!strcmp(op, "k_weight")) {
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "n");
        int64_t sub = (int64_t)w_media_num(m_avf_arr(a3, 1), 4800, "sub");
        int64_t nb = sub > 0 ? n / sub : 0;
        if (nb <= 0) return w_int(0);
        const float *bus = a_stu_f32_ptr(a1, nb * sub * 2, "bus");
        double *zs = a_band_f64_ptr(a2, nb, "zs");
        const double sb0 = 1.53512485958697, sb1 = -2.69169618940638, sb2 = 1.19839281085285;
        const double sa1 = -1.69065929318241, sa2 = 0.73248077421585;
        const double hb0 = 1.0, hb1 = -2.0, hb2 = 1.0;
        const double ha1 = -1.99004745483398, ha2 = 0.99007225036621;
#if defined(__aarch64__)
        float64x2_t vsb0 = vdupq_n_f64(sb0), vsb1 = vdupq_n_f64(sb1), vsb2 = vdupq_n_f64(sb2);
        float64x2_t vsa1 = vdupq_n_f64(sa1), vsa2 = vdupq_n_f64(sa2);
        float64x2_t vhb0 = vdupq_n_f64(hb0), vhb1 = vdupq_n_f64(hb1), vhb2 = vdupq_n_f64(hb2);
        float64x2_t vha1 = vdupq_n_f64(ha1), vha2 = vdupq_n_f64(ha2);
        float64x2_t vx1 = vdupq_n_f64(0.0), vx2 = vdupq_n_f64(0.0), vy1 = vdupq_n_f64(0.0), vy2 = vdupq_n_f64(0.0);
        float64x2_t vu1 = vdupq_n_f64(0.0), vu2 = vdupq_n_f64(0.0), vv1 = vdupq_n_f64(0.0), vv2 = vdupq_n_f64(0.0);
        double dsub = (double)sub;
        for (int64_t b = 0; b < nb; b++) {
            float64x2_t vs = vdupq_n_f64(0.0);
            const float *p = bus + (size_t)(b * sub) * 2;
            for (int64_t i = 0; i < sub; i++, p += 2) {
                float64x2_t vx = vcvt_f64_f32(vld1_f32(p));
                float64x2_t vy = vsubq_f64(vsubq_f64(vaddq_f64(vaddq_f64(vmulq_f64(vsb0, vx), vmulq_f64(vsb1, vx1)), vmulq_f64(vsb2, vx2)),
                                                     vmulq_f64(vsa1, vy1)), vmulq_f64(vsa2, vy2));
                vx2 = vx1; vx1 = vx; vy2 = vy1; vy1 = vy;
                float64x2_t vv = vsubq_f64(vsubq_f64(vaddq_f64(vaddq_f64(vmulq_f64(vhb0, vy), vmulq_f64(vhb1, vu1)), vmulq_f64(vhb2, vu2)),
                                                     vmulq_f64(vha1, vv1)), vmulq_f64(vha2, vv2));
                vu2 = vu1; vu1 = vy; vv2 = vv1; vv1 = vv;
                vs = vaddq_f64(vs, vmulq_f64(vv, vv));
            }
            zs[b] = (vgetq_lane_f64(vs, 0) + vgetq_lane_f64(vs, 1)) / dsub;
        }
#else
        double ax1 = 0, ax2 = 0, ay1 = 0, ay2 = 0, au1 = 0, au2 = 0, av1 = 0, av2 = 0;
        double bx1 = 0, bx2 = 0, by1 = 0, by2 = 0, bu1 = 0, bu2 = 0, bv1 = 0, bv2 = 0;
        for (int64_t b = 0; b < nb; b++) {
            double s0 = 0.0, s1 = 0.0;
            for (int64_t i = b * sub; i < (b + 1) * sub; i++) {
                double xa = bus[i * 2], xb = bus[i * 2 + 1];
                double ya = sb0 * xa + sb1 * ax1 + sb2 * ax2 - sa1 * ay1 - sa2 * ay2;
                double yb = sb0 * xb + sb1 * bx1 + sb2 * bx2 - sa1 * by1 - sa2 * by2;
                ax2 = ax1; ax1 = xa; ay2 = ay1; ay1 = ya;
                bx2 = bx1; bx1 = xb; by2 = by1; by1 = yb;
                double va = hb0 * ya + hb1 * au1 + hb2 * au2 - ha1 * av1 - ha2 * av2;
                double vb = hb0 * yb + hb1 * bu1 + hb2 * bu2 - ha1 * bv1 - ha2 * bv2;
                au2 = au1; au1 = ya; av2 = av1; av1 = va;
                bu2 = bu1; bu1 = yb; bv2 = bv1; bv1 = vb;
                s0 += va * va; s1 += vb * vb;
            }
            zs[b] = (s0 + s1) / (double)sub;
        }
#endif
        return w_int(nb);
    }

    if (!strcmp(op, "tp_gain")) {
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "n");
        double ceil_v = w_media_num(m_avf_arr(a3, 1), 1.0, "ceil");
        WValue gv = m_avf_arr(a3, 2);
        if (n <= 0) return w_float(0.0);
        const float *bus = a_stu_f32_ptr(a1, n * 2, "bus");
        const double *h = a_band_f64_ptr(a2, 48, "h");
        float *g = (gv != W_NIL) ? a_stu_f32_ptr(gv, n, "g") : NULL;
        double bound = 0.0;
        for (int p = 0; p < 4; p++) {
            double s = 0.0;
            for (int k = 0; k < 12; k++) s += fabs(h[p * 12 + k]);
            if (s > bound) bound = s;
        }
        bound *= (1.0 + 1.0e-9);
        double maxtp = 0.0, safe = ceil_v / 1.7;
        int64_t nb = n / 256 + 1;
        double *bm = calloc((size_t)nb, sizeof(double));
        double sm[36];
        for (int64_t b = 0; b < nb; b++) {
            int64_t lo = b * 256, hi = lo + 256 < n ? lo + 256 : n;
            float bmax = 0.0f;
            int64_t i2 = lo * 2, e2 = hi * 2;
#if defined(__aarch64__)
            float32x4_t vm = vdupq_n_f32(0.0f);
            for (; i2 + 4 <= e2; i2 += 4) vm = vmaxq_f32(vm, vabsq_f32(vld1q_f32(bus + i2)));
            bmax = vmaxvq_f32(vm);
#endif
            for (; i2 < e2; i2++) {
                float av = fabsf(bus[i2]);
                if (av > bmax) bmax = av;
            }
            bm[b] = (double)bmax;
        }
        for (int64_t b = 0; b < nb; b++) {
            int64_t lo = b * 256, hi = lo + 256 < n ? lo + 256 : n;
            if (lo >= hi) continue;
            double near = bm[b];
            if (b > 0 && bm[b - 1] > near) near = bm[b - 1];
            if (b + 1 < nb && bm[b + 1] > near) near = bm[b + 1];
            if (near <= safe) {
                if (g) {
                    int64_t i = lo;
#if defined(__aarch64__)
                    float32x4_t vone = vdupq_n_f32(1.0f);
                    for (; i + 4 <= hi; i += 4) vst1q_f32(g + i, vone);
#endif
                    for (; i < hi; i++) g[i] = 1.0f;
                }
            } else {
                int64_t base = lo - 16;
                for (int c = 0; c < 2; c++) {
                    for (int j = 0; j < 18; j++) {
                        int64_t a = base + (int64_t)j * 16, e = a + 16;
                        if (a < 0) a = 0;
                        if (e > n) e = n;
                        double m = 0.0;
                        for (int64_t i = a; i < e; i++) {
                            double v = fabs((double)bus[i * 2 + c]);
                            if (v > m) m = v;
                        }
                        sm[c * 18 + j] = m;
                    }
                }
                for (int64_t i = lo; i < hi; i++) {
                    double gi = 1.0;
                    for (int c = 0; c < 2; c++) {
                        double tp = fabs((double)bus[i * 2 + c]);
                        if (i >= 6 && i + 6 < n) {
                            double wm = sm[c * 18 + (i - 5 - base) / 16];
                            double w2 = sm[c * 18 + (i + 6 - base) / 16];
                            if (w2 > wm) wm = w2;
                            double lim = maxtp < ceil_v ? maxtp : ceil_v;
                            if (wm * bound > lim) tp = a_stu_tp_at(bus, i, c, h);
                        }
                        if (tp > maxtp) maxtp = tp;
                        double q = tp > ceil_v ? ceil_v / tp : 1.0;
                        if (q < gi) gi = q;
                    }
                    if (g) g[i] = (float)gi;
                }
            }
        }
        free(bm);
        return w_float(maxtp);
    }

    if (!strcmp(op, "limit_apply")) {
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "n");
        int64_t w = (int64_t)w_media_num(m_avf_arr(a3, 1), 1, "w");
        double rel = w_media_num(m_avf_arr(a3, 2), 0.0, "release");
        if (n <= 0) return w_int(0);
        float *bus = a_stu_f32_ptr(a1, n * 2, "bus");
        const float *g = a_stu_f32_ptr(a2, n, "g");
        float *m = malloc((size_t)n * sizeof(float));
        /* O(n) monotone deque for exact sliding-window min over [i, min(n - 1, i + 2 * w)] */
        int64_t *dq = malloc((size_t)n * sizeof(int64_t));
        int64_t head = 0, tail = 0;
        int64_t span = 2 * w;
        for (int64_t i = n - 1; i >= 0; i--) {
            int64_t lim = i + span;
            while (head < tail && dq[head] > lim) head++;
            float gi = g[i];
            if (gi >= 1.0f && (head == tail || g[dq[head]] >= 1.0f)) {
                head = tail = 0;
                m[i] = gi;
            } else {
                while (head < tail && g[dq[tail - 1]] >= gi) tail--;
                dq[tail++] = i;
                m[i] = g[dq[head]];
            }
        }
        free(dq);
        double acc = 0.0;
        for (int64_t i = 0; i < w && i < n; i++) acc += (double)m[i];
        double gcur = 1.0, dw = w > 0 ? (double)w : 1.0;
        for (int64_t i = 0; i < n; i++) {
            double avg;
            if (i >= w) {
                acc = acc + (double)m[i] - (double)m[i - w];
                avg = acc / dw;
            } else {
                avg = (double)m[i];
            }
            gcur = gcur + (1.0 - gcur) * rel;
            if (avg < gcur) gcur = avg;
            bus[i * 2] = (float)((double)bus[i * 2] * gcur);
            bus[i * 2 + 1] = (float)((double)bus[i * 2 + 1] * gcur);
        }
        free(m);
        return w_int(0);
    }

    if (!strcmp(op, "place_q28")) {
        int64_t nbus = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "nbus");
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 1), 0, "n");
        int64_t s0 = (int64_t)w_media_num(m_avf_arr(a3, 2), 0, "s0");
        int64_t i = s0 < 0 ? -s0 : 0;
        int64_t e = s0 + n > nbus ? nbus - s0 : n;
        if (i >= e) return w_int(0);
        float *bus = a_stu_f32_ptr(a1, (s0 + e) * 2, "bus");
        const int32_t *src = a_stu_i32_ptr(a2, e * 2, "src");
        const double sc = 1.0 / 268435456.0;
#if defined(__aarch64__)
        float64x2_t vsc = vdupq_n_f64(sc);
        for (; i + 2 <= e; i += 2) {
            int64_t p = s0 + i;
            int32x4_t s4 = vld1q_s32(src + i * 2);
            float64x2_t f0 = vmulq_f64(vcvtq_f64_s64(vmovl_s32(vget_low_s32(s4))), vsc);
            float64x2_t f1 = vmulq_f64(vcvtq_f64_s64(vmovl_high_s32(s4)), vsc);
            float32x4_t b4 = vld1q_f32(bus + p * 2);
            float64x2_t r0 = vaddq_f64(vcvt_f64_f32(vget_low_f32(b4)), f0);
            float64x2_t r1 = vaddq_f64(vcvt_high_f64_f32(b4), f1);
            vst1q_f32(bus + p * 2, vcombine_f32(vcvt_f32_f64(r0), vcvt_f32_f64(r1)));
        }
#endif
        for (; i < e; i++) {
            int64_t p = s0 + i;
            bus[p * 2] = (float)((double)bus[p * 2] + (double)src[i * 2] * sc);
            bus[p * 2 + 1] = (float)((double)bus[p * 2 + 1] + (double)src[i * 2 + 1] * sc);
        }
        return w_int(0);
    }

    if (!strcmp(op, "place_run")) {
        int64_t nbus = (int64_t)w_media_num(m_avf_arr(a2, 0), 0, "nbus");
        int64_t n = (int64_t)w_media_num(m_avf_arr(a2, 1), 0, "n");
        int64_t s0 = (int64_t)w_media_num(m_avf_arr(a2, 2), 0, "s0");
        int64_t nduck = (int64_t)w_media_num(m_avf_arr(a2, 3), 0, "nduck");
        double gain = w_media_num(m_avf_arr(a3, 0), 1.0, "gain");
        double depth = w_media_num(m_avf_arr(a3, 1), 0.0, "depth");
        WValue duckv = m_avf_arr(a3, 2);
        int64_t i = s0 < 0 ? -s0 : 0;
        int64_t e = s0 + n > nbus ? nbus - s0 : n;
        if (i >= e) return w_int(0);
        float *bus = a_stu_f32_ptr(m_avf_arr(a1, 0), (s0 + e) * 2, "bus");
        const double *left = a_band_f64_ptr(m_avf_arr(a1, 1), e, "left");
        const double *right = a_band_f64_ptr(m_avf_arr(a1, 2), e, "right");
        const double *duck = (depth != 0.0 && duckv != W_NIL && nduck > 0) ? a_band_f64_ptr(duckv, nduck, "duck") : NULL;
        if (depth == 0.0) {
#if defined(__aarch64__)
            float64x2_t vg = vdupq_n_f64(gain);
            for (; i + 2 <= e; i += 2) {
                int64_t p = s0 + i;
                float64x2_t f0 = {left[i], right[i]};
                float64x2_t f1 = {left[i + 1], right[i + 1]};
                float32x4_t b4 = vld1q_f32(bus + p * 2);
                float64x2_t r0 = vaddq_f64(vcvt_f64_f32(vget_low_f32(b4)), vmulq_f64(f0, vg));
                float64x2_t r1 = vaddq_f64(vcvt_high_f64_f32(b4), vmulq_f64(f1, vg));
                vst1q_f32(bus + p * 2, vcombine_f32(vcvt_f32_f64(r0), vcvt_f32_f64(r1)));
            }
#endif
            for (; i < e; i++) {
                int64_t p = s0 + i;
                bus[p * 2] = (float)((double)bus[p * 2] + left[i] * gain);
                bus[p * 2 + 1] = (float)((double)bus[p * 2 + 1] + right[i] * gain);
            }
        } else {
            int64_t cb = -1;
            double g = gain;
            for (; i < e; i++) {
                int64_t p = s0 + i;
                int64_t b = p / 64;
                if (b != cb) {
                    cb = b;
                    double d = (duck && b < nduck) ? duck[b] : 0.0;
                    g = gain * exp(depth * d * 0.11512925464970229);
                }
                bus[p * 2] = (float)((double)bus[p * 2] + left[i] * g);
                bus[p * 2 + 1] = (float)((double)bus[p * 2 + 1] + right[i] * g);
            }
        }
        return w_int(0);
    }

    if (!strcmp(op, "duck_env")) {
        int64_t nbus = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "nbus");
        int64_t nb = (int64_t)w_media_num(m_avf_arr(a3, 1), 0, "nb");
        double attack = w_media_num(m_avf_arr(a3, 2), 0.01, "attack");
        double release = w_media_num(m_avf_arr(a3, 3), 0.1, "release");
        double full = w_media_num(m_avf_arr(a3, 4), 1.0, "full");
        int64_t sr = (int64_t)w_media_num(m_avf_arr(a3, 5), 48000, "sr");
        if (nb <= 0) return w_int(0);
        const float *bus = a_stu_f32_ptr(a1, nbus * 2, "bus");
        double *out = a_band_f64_ptr(a2, nb, "out");
        double au = exp(-1.0 / (attack * (double)sr / 64.0));
        double ad = exp(-1.0 / (release * (double)sr / 64.0));
        double acc = 0.0;
        for (int64_t b = 0; b < nb; b++) {
            double mx = 0.0;
            int64_t i = b * 64, e = i + 64 < nbus ? i + 64 : nbus;
#if defined(__aarch64__)
            float64x2_t vmx = vdupq_n_f64(0.0), vhalf = vdupq_n_f64(0.5);
            for (; i + 2 <= e; i += 2) {
                float32x4_t s4 = vabsq_f32(vld1q_f32(bus + i * 2));
                float64x2_t d0 = vcvt_f64_f32(vget_low_f32(s4));
                float64x2_t d1 = vcvt_high_f64_f32(s4);
                float64x2_t sums = vpaddq_f64(d0, d1);
                vmx = vmaxq_f64(vmx, vmulq_f64(sums, vhalf));
            }
            double m0 = vgetq_lane_f64(vmx, 0), m1 = vgetq_lane_f64(vmx, 1);
            mx = m0 > m1 ? m0 : m1;
#endif
            for (; i < e; i++) {
                double v = (fabs((double)bus[i * 2]) + fabs((double)bus[i * 2 + 1])) * 0.5;
                if (v > mx) mx = v;
            }
            acc = mx > acc ? (au * acc + (1.0 - au) * mx) : (ad * acc + (1.0 - ad) * mx);
            double d = acc / full;
            if (d > 1.0) d = 1.0;
            out[b] = d;
        }
        return w_int(0);
    }

    if (!strcmp(op, "pack_s24")) {
        int64_t f0 = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "f0");
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 1), 0, "n");
        if (n <= 0) return w_int(0);
        const float *bus = a_stu_f32_ptr(a1, (f0 + n) * 2, "bus") + (size_t)f0 * 2;
        uint8_t *buf = a_band_u8_ptr(a2, n * 6, "buf");
        int64_t total = n * 2, i = 0;
#if defined(__aarch64__)
        float64x2_t vsc = vdupq_n_f64(8388607.0), vhi = vdupq_n_f64(8388607.0), vlo = vdupq_n_f64(-8388608.0);
        float64x2_t vhalf = vdupq_n_f64(0.5);
        for (; i + 4 <= total; i += 4) {
            float32x4_t b4 = vld1q_f32(bus + i);
            float64x2_t d0 = vminq_f64(vmaxq_f64(vmulq_f64(vcvt_f64_f32(vget_low_f32(b4)), vsc), vlo), vhi);
            float64x2_t d1 = vminq_f64(vmaxq_f64(vmulq_f64(vcvt_high_f64_f32(b4), vsc), vlo), vhi);
            int64x2_t q0 = vcvtq_s64_f64(vrndmq_f64(vaddq_f64(d0, vhalf)));
            int64x2_t q1 = vcvtq_s64_f64(vrndmq_f64(vaddq_f64(d1, vhalf)));
            int64_t qv[4] = {vgetq_lane_s64(q0, 0), vgetq_lane_s64(q0, 1), vgetq_lane_s64(q1, 0), vgetq_lane_s64(q1, 1)};
            uint8_t *o = buf + (size_t)i * 3;
            for (int k = 0; k < 4; k++, o += 3) {
                uint32_t u = (uint32_t)(int32_t)qv[k];
                o[0] = (uint8_t)(u & 0xFFu);
                o[1] = (uint8_t)((u >> 8) & 0xFFu);
                o[2] = (uint8_t)((u >> 16) & 0xFFu);
            }
        }
#endif
        for (; i < total; i++) {
            double v = (double)bus[i] * 8388607.0;
            if (v > 8388607.0) v = 8388607.0;
            if (v < -8388608.0) v = -8388608.0;
            uint32_t u = (uint32_t)(int32_t)(int64_t)floor(v + 0.5);
            buf[i * 3] = (uint8_t)(u & 0xFFu);
            buf[i * 3 + 1] = (uint8_t)((u >> 8) & 0xFFu);
            buf[i * 3 + 2] = (uint8_t)((u >> 16) & 0xFFu);
        }
        return w_int(0);
    }

    if (!strcmp(op, "pack_q28")) {
        int64_t f0 = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "f0");
        int64_t n = (int64_t)w_media_num(m_avf_arr(a3, 1), 0, "n");
        if (n <= 0) return w_int(0);
        const double *left = a_band_f64_ptr(m_avf_arr(a1, 0), f0 + n, "left") + f0;
        const double *right = a_band_f64_ptr(m_avf_arr(a1, 1), f0 + n, "right") + f0;
        uint8_t *buf = a_band_u8_ptr(a2, n * 8, "buf");
        int64_t sat = 0;
        for (int64_t i = 0; i < n; i++) {
            double lr[2] = {left[i] * 268435456.0, right[i] * 268435456.0};
            for (int c = 0; c < 2; c++) {
                double v = lr[c];
                if (v > 2147483647.0) { v = 2147483647.0; sat++; }
                if (v < -2147483648.0) { v = -2147483648.0; sat++; }
                int64_t q = (int64_t)floor(v + 0.5);
                if (q > 2147483647LL) q = 2147483647LL;
                uint32_t u = (uint32_t)(int32_t)q;
                a_le32_put(buf + ((size_t)i * 2 + (size_t)c) * 4, u);
            }
        }
        return w_int(sat);
    }

    if (!strcmp(op, "wav_deinterleave")) {
        int64_t frames = (int64_t)w_media_num(m_avf_arr(a3, 0), 0, "frames");
        int64_t ch = (int64_t)w_media_num(m_avf_arr(a3, 1), 2, "ch");
        if (frames <= 0) return w_int(0);
        const float *fv = a_stu_f32_ptr(a1, frames * ch, "fv");
        double *left = a_band_f64_ptr(m_avf_arr(a2, 0), frames, "left");
        double *right = a_band_f64_ptr(m_avf_arr(a2, 1), frames, "right");
        int64_t i = 0;
        if (ch == 1) {
#if defined(__aarch64__)
            for (; i + 4 <= frames; i += 4) {
                float32x4_t v4 = vld1q_f32(fv + i);
                float64x2_t d0 = vcvt_f64_f32(vget_low_f32(v4)), d1 = vcvt_high_f64_f32(v4);
                vst1q_f64(left + i, d0); vst1q_f64(left + i + 2, d1);
                vst1q_f64(right + i, d0); vst1q_f64(right + i + 2, d1);
            }
#endif
            for (; i < frames; i++) { double v = (double)fv[i]; left[i] = v; right[i] = v; }
        } else if (ch == 2) {
#if defined(__aarch64__)
            for (; i + 4 <= frames; i += 4) {
                float32x4x2_t lr = vld2q_f32(fv + i * 2);
                vst1q_f64(left + i, vcvt_f64_f32(vget_low_f32(lr.val[0])));
                vst1q_f64(left + i + 2, vcvt_high_f64_f32(lr.val[0]));
                vst1q_f64(right + i, vcvt_f64_f32(vget_low_f32(lr.val[1])));
                vst1q_f64(right + i + 2, vcvt_high_f64_f32(lr.val[1]));
            }
#endif
            for (; i < frames; i++) { left[i] = (double)fv[i * 2]; right[i] = (double)fv[i * 2 + 1]; }
        } else {
            for (; i < frames; i++) { left[i] = (double)fv[i * ch]; right[i] = (double)fv[i * ch + 1]; }
        }
        return w_int(frames);
    }

    w_media_raise("w_media_studio_op: unknown op '%s'", op);
}

#pragma clang fp contract(fast)

/* ---- PCM output stream: plays float PCM the program pushes (core/audio_stream.w) ----
 *
 * Output only: an AVAudioSourceNode pulls interleaved float frames from a
 * single-producer / single-consumer ring the program fills with
 * w_media_pcm_write. Nothing here decodes. The clock (w_media_pcm_time) is the
 * position of the frame being heard: the ring read position at the last render
 * callback, advanced by the host clock since that buffer's output time, minus
 * the output's presentation latency, clamped to what was actually rendered, so
 * it stops on an underrun and freezes on pause. Flushed frames do not count:
 * the position restarts at 0 after a flush. Without an output device (engine
 * start fails) a null sink thread consumes frames in real time, so the clock
 * still runs (headless use). */

#define PCM_CAP_SECONDS 4

typedef struct APcm {
    AVAudioEngine     *engine;
    AVAudioSourceNode *node;
    int                ch;
    double             rate;
    float             *ring;        /* cap * ch floats */
    int64_t            cap;         /* frames */
    _Atomic int64_t    wpos, rpos;  /* monotonic frame counters */
    _Atomic int64_t    flush_to;    /* producer's flush target (consumer applies) */
    _Atomic int64_t    base;        /* frame counter of position 0 (the last flush) */
    _Atomic uint32_t   seq;         /* seqlock over the cb_* snapshot */
    int64_t            cb_rpos, pv_rpos;   /* the last render callback, and the one before */
    int64_t            cb_take, pv_take;
    double             cb_host, pv_host;
    _Atomic int        paused;
    _Atomic int64_t    underruns;
    _Atomic int64_t    rendered;    /* frames of real data rendered */
    _Atomic float      volume;
    double             latency;     /* seconds */
    double             frozen;      /* position while paused */
    double             last;        /* last position returned (monotonic) */
    int                nosink;      /* null sink: no device */
    _Atomic int        stop;
    pthread_t          sink_thread;
} APcm;

static double pcm_now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9; }

static double pcm_host_s(uint64_t ht) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)ht * (double)tb.numer / (double)tb.denom / 1e9;
}

/* Pull n frames for output into non-interleaved buffers (outs[c], or NULL). */
static void pcm_render(APcm *P, float **outs, int nout, int64_t n, double host) {
    int64_t ft = atomic_load_explicit(&P->flush_to, memory_order_acquire);
    int64_t r = atomic_load_explicit(&P->rpos, memory_order_relaxed);
    if (ft > r) r = ft;
    int64_t w = atomic_load_explicit(&P->wpos, memory_order_acquire);
    int64_t avail = w - r;
    if (avail < 0) avail = 0;
    int64_t take = avail < n ? avail : n;
    float g = atomic_load_explicit(&P->volume, memory_order_relaxed);
    int ch = P->ch;
    for (int c = 0; c < nout; c++) {
        float *o = outs[c];
        if (!o) continue;
        int sc = c < ch ? c : ch - 1;
        for (int64_t i = 0; i < take; i++) o[i] = P->ring[((r + i) % P->cap) * ch + sc] * g;
        for (int64_t i = take; i < n; i++) o[i] = 0.0f;
    }
    if (take < n && take > 0) atomic_fetch_add_explicit(&P->underruns, 1, memory_order_relaxed);
    uint32_t s = atomic_load_explicit(&P->seq, memory_order_relaxed);
    atomic_store_explicit(&P->seq, s + 1, memory_order_release);
    P->pv_rpos = P->cb_rpos; P->pv_take = P->cb_take; P->pv_host = P->cb_host;
    P->cb_rpos = r;
    P->cb_take = take;
    P->cb_host = host;
    atomic_store_explicit(&P->seq, s + 2, memory_order_release);
    atomic_store_explicit(&P->rpos, r + take, memory_order_release);
    atomic_fetch_add_explicit(&P->rendered, take, memory_order_relaxed);
}

static void *pcm_null_sink(void *arg) {
    APcm *P = arg;
    const int64_t blk = 512;
    double t = pcm_now();
    while (!atomic_load(&P->stop)) {
        if (!atomic_load(&P->paused)) pcm_render(P, NULL, 0, blk, t);
        t += (double)blk / P->rate;
        double d = t - pcm_now();
        if (d > 0) usleep((useconds_t)(d * 1e6));
        else if (d < -0.5) t = pcm_now();
    }
    return NULL;
}

static APcm *pcm_get(WValue h, const char *what) {
    return (APcm *)w_media_handle_get(h, W_MEDIA_KIND_PCM, what);
}

/* open(rate, channels) -> handle */
WValue w_media_pcm_open(WValue ratev, WValue chv) {
    double rate = a_num(ratev);
    int ch = (int)a_num(chv);
    if (rate < 1000 || rate > 768000) w_media_raise("audio_stream_open: sample rate %g out of range", rate);
    if (ch < 1 || ch > 16) w_media_raise("audio_stream_open: %d channels out of range (1-16)", ch);
    APcm *P = calloc(1, sizeof *P);
    P->ch = ch;
    P->rate = rate;
    P->cap = (int64_t)(rate * PCM_CAP_SECONDS);
    P->ring = calloc((size_t)(P->cap * ch), sizeof(float));
    atomic_store(&P->volume, 1.0f);
    @autoreleasepool {
        P->engine = [[AVAudioEngine alloc] init];
        AVAudioFormat *fmt = [[[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:(AVAudioChannelCount)ch] autorelease];
        APcm *Pp = P;
        if (fmt) {
            P->node = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount n, AudioBufferList *abl) {
                float *outs[16];
                int no = (int)abl->mNumberBuffers;
                if (no > 16) no = 16;
                for (int i = 0; i < no; i++) outs[i] = (float *)abl->mBuffers[i].mData;
                double hs = (ts && (ts->mFlags & kAudioTimeStampHostTimeValid)) ? pcm_host_s(ts->mHostTime) : pcm_now();
                pcm_render(Pp, outs, no, (int64_t)n, hs);
                return noErr;
            }];
        }
        int ok = 0;
        if (P->node) {
            [P->engine attachNode:P->node];
            [P->engine connect:P->node to:P->engine.mainMixerNode format:fmt];
            [P->engine prepare];
            NSError *err = nil;
            ok = [P->engine startAndReturnError:&err];
            if (ok) {
                AVAudioOutputNode *on = P->engine.outputNode;
                double lat = on.presentationLatency;
                if (lat < 0 || lat > 1) lat = 0;
                P->latency = lat;
            }
        }
        if (!ok) {
            P->nosink = 1;
            if (P->node) { [P->engine detachNode:P->node]; [P->node release]; P->node = nil; }
            [P->engine release];
            P->engine = nil;
            pthread_create(&P->sink_thread, NULL, pcm_null_sink, P);
        }
    }
    return w_int(w_media_handle_new(P, W_MEDIA_KIND_PCM));
}

/* write(h, samples, first_frame, frames) -> frames accepted (never blocks).
 * samples: interleaved f32[] (or a ByteArray of little-endian float32). */
WValue w_media_pcm_write(WValue h, WValue arr, WValue firstv, WValue nv) {
    APcm *P = pcm_get(h, "audio_stream_write");
    if (!w_is_array(arr)) w_media_raise("audio_stream_write: samples must be an f32[] or ByteArray");
    WArray *a = w_as_array(arr);
    const float *src;
    int64_t total;
    if (a->ebits == -32) { src = (const float *)a->slots + a->start; total = a->size / P->ch; }
    else if (a->ebits == 8) { src = (const float *)((const uint8_t *)a->slots + a->start); total = a->size / 4 / P->ch; }
    else { w_media_raise("audio_stream_write: samples must be an f32[] or ByteArray"); return W_NIL; }
    int64_t first = (int64_t)a_num(firstv);
    int64_t n = (int64_t)a_num(nv);
    if (first < 0) first = 0;
    if (first > total) first = total;
    if (n < 0 || first + n > total) n = total - first;
    int64_t w = atomic_load_explicit(&P->wpos, memory_order_relaxed);
    int64_t r = atomic_load_explicit(&P->rpos, memory_order_acquire);
    int64_t ft = atomic_load_explicit(&P->flush_to, memory_order_relaxed);
    if (ft > r) r = ft;
    int64_t space = P->cap - (w - r);
    if (n > space) n = space;
    int ch = P->ch;
    for (int64_t i = 0; i < n; i++) {
        int64_t slot = ((w + i) % P->cap) * ch;
        memcpy(&P->ring[slot], src + (first + i) * ch, (size_t)ch * sizeof(float));
    }
    atomic_store_explicit(&P->wpos, w + n, memory_order_release);
    return w_int(n);
}

static double pcm_position(APcm *P) {
    int64_t cr, ct, pr, pt; double chost, phost; uint32_t s0, s1;
    do {
        s0 = atomic_load_explicit(&P->seq, memory_order_acquire);
        cr = P->cb_rpos; ct = P->cb_take; chost = P->cb_host;
        pr = P->pv_rpos; pt = P->pv_take; phost = P->pv_host;
        s1 = atomic_load_explicit(&P->seq, memory_order_acquire);
    } while (s0 != s1 || (s0 & 1));
    double heard;
    double now = pcm_now() - P->latency;
    if (chost == 0) heard = 0;
    else if (now >= chost || phost == 0) {
        /* the last buffer is playing (or played out) */
        double adv = (now - chost) * P->rate;
        if (adv < 0) adv = 0;
        if (adv > (double)ct) adv = (double)ct;
        heard = (double)cr + adv;
    } else {
        /* the last buffer is still ahead of the speaker: the one before is playing */
        double adv = (now - phost) * P->rate;
        if (adv < 0) adv = 0;
        if (adv > (double)pt) adv = (double)pt;
        heard = (double)pr + adv;
    }
    int64_t base = atomic_load_explicit(&P->base, memory_order_relaxed);
    double pos = (heard - (double)base) / P->rate;
    if (pos < 0) pos = 0;
    return pos;
}

/* time(h) -> seconds of real audio heard since open / the last flush */
WValue w_media_pcm_time(WValue h) {
    APcm *P = pcm_get(h, "audio_stream_time");
    if (atomic_load(&P->paused)) return w_float(P->frozen);
    double p = pcm_position(P);
    if (p < P->last) p = P->last;
    P->last = p;
    return w_float(p);
}

/* pause(h, on) */
WValue w_media_pcm_pause(WValue h, WValue onv) {
    APcm *P = pcm_get(h, "audio_stream_pause");
    int on = w_truthy(onv) ? 1 : 0;
    if (on == atomic_load(&P->paused)) return W_TRUE;
    if (on) {
        double p = pcm_position(P);
        if (p < P->last) p = P->last;
        P->frozen = p;
        P->last = p;
        atomic_store(&P->paused, 1);
        if (P->engine) [P->engine pause];
        /* the frames the device had not played yet are played again on resume */
        int64_t base = atomic_load(&P->base);
        int64_t at = base + (int64_t)(p * P->rate);
        int64_t r = atomic_load(&P->rpos);
        if (at < r && at >= atomic_load(&P->flush_to)) {
            atomic_store(&P->rpos, at);
            uint32_t s = atomic_load(&P->seq);
            atomic_store(&P->seq, s + 1);
            P->cb_rpos = at; P->cb_take = 0; P->pv_host = 0;
            atomic_store(&P->seq, s + 2);
        }
    } else {
        atomic_store(&P->paused, 0);
        if (P->engine) {
            NSError *err = nil;
            [P->engine startAndReturnError:&err];
        }
    }
    return W_TRUE;
}

/* flush(h): drop every queued frame; the position restarts at 0. */
WValue w_media_pcm_flush(WValue h) {
    APcm *P = pcm_get(h, "audio_stream_flush");
    int64_t w = atomic_load(&P->wpos);
    atomic_store_explicit(&P->flush_to, w, memory_order_release);
    atomic_store(&P->base, w);
    P->last = 0;
    P->frozen = 0;
    if (P->engine && atomic_load(&P->paused)) {
        /* no render callback runs while paused: apply the flush now */
        atomic_store(&P->rpos, w);
    }
    uint32_t s = atomic_load(&P->seq);
    atomic_store(&P->seq, s + 1);
    P->cb_rpos = w; P->cb_take = 0; P->cb_host = pcm_now(); P->pv_host = 0;
    atomic_store(&P->seq, s + 2);
    return W_TRUE;
}

/* volume(h, v): linear gain 0 … 1 */
WValue w_media_pcm_volume(WValue h, WValue vv) {
    APcm *P = pcm_get(h, "audio_stream_volume");
    double v = a_num(vv);
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    atomic_store(&P->volume, (float)v);
    return W_TRUE;
}

/* info(h) -> [queued frames, underruns, rate, channels, latency s, has device 0/1, rendered frames] */
WValue w_media_pcm_info(WValue h) {
    APcm *P = pcm_get(h, "audio_stream_info");
    int64_t w = atomic_load(&P->wpos), r = atomic_load(&P->rpos), ft = atomic_load(&P->flush_to);
    if (ft > r) r = ft;
    WValue a = w_array_new_empty();
    a = w_array_push(a, w_int(w - r));
    a = w_array_push(a, w_int(atomic_load(&P->underruns)));
    a = w_array_push(a, w_float(P->rate));
    a = w_array_push(a, w_int(P->ch));
    a = w_array_push(a, w_float(P->latency));
    a = w_array_push(a, w_int(P->nosink ? 0 : 1));
    a = w_array_push(a, w_int(atomic_load(&P->rendered)));
    return a;
}

WValue w_media_pcm_close(WValue h) {
    if (!w_is_int(h)) return W_NIL;
    APcm *P = (APcm *)m_avf_peek(h, W_MEDIA_KIND_PCM);
    if (!P) return W_NIL;
    w_media_handle_drop(h, W_MEDIA_KIND_PCM);
    @autoreleasepool {
        if (P->engine) {
            [P->engine stop];
            if (P->node) { [P->engine detachNode:P->node]; [P->node release]; }
            [P->engine release];
        }
    }
    if (P->nosink) {
        atomic_store(&P->stop, 1);
        pthread_join(P->sink_thread, NULL);
    }
    free(P->ring);
    free(P);
    return W_NIL;
}

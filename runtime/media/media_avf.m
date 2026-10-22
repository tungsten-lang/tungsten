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
#include <errno.h>
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

typedef struct {
    uint32_t type;
    int64_t  off, size;
} ATop;

/* Add a tmcd track to `src` (written by AVAssetWriter, moov anywhere) and
 * write the result to `dst`, moov first when faststart. 0 on success. */
static int a_add_timecode(const char *src, const char *dst, int mov, uint32_t ts, uint32_t ticks, int64_t frames,
                          int64_t tc_frame, uint32_t quanta, int drop, int faststart, char *err, size_t errcap) {
    int fd = open(src, O_RDONLY);
    if (fd < 0) { snprintf(err, errcap, "cannot reopen %s: %s", src, strerror(errno)); return -1; }
    struct stat st;
    fstat(fd, &st);
    ATop top[64];
    int ntop = 0, moov_i = -1;
    int64_t off = 0;
    while (off + 8 <= st.st_size && ntop < 64) {
        uint8_t h[16];
        if (pread(fd, h, 16, off) < 8) break;
        int64_t sz = a_rd32(h);
        if (sz == 1) sz = (int64_t)a_rd64(h + 8);
        else if (sz == 0) sz = st.st_size - off;
        if (sz < 8 || off + sz > st.st_size) { close(fd); snprintf(err, errcap, "%s: bad top-level box at %lld", src, (long long)off); return -1; }
        top[ntop].type = a_rd32(h + 4);
        top[ntop].off = off;
        top[ntop].size = sz;
        if (top[ntop].type == A_FOURCC('m','o','o','v')) moov_i = ntop;
        ntop++;
        off += sz;
    }
    if (moov_i < 0 || top[0].type != A_FOURCC('f','t','y','p')) { close(fd); snprintf(err, errcap, "%s: no ftyp/moov", src); return -1; }
    size_t mlen = (size_t)top[moov_i].size;
    uint8_t *mbuf = malloc(mlen);
    if (pread(fd, mbuf, mlen, top[moov_i].off) != (ssize_t)mlen) { free(mbuf); close(fd); snprintf(err, errcap, "%s: short read", src); return -1; }
    ABox root;
    memset(&root, 0, sizeof root);
    if (!a_box_parse(mbuf, mlen, &root) || root.nk != 1) { free(mbuf); a_box_free(&root); close(fd); snprintf(err, errcap, "%s: cannot parse moov", src); return -1; }
    free(mbuf);
    ABox *moov = &root.kid[0];
    ABox *mvhd = a_box_find(moov, A_FOURCC('m','v','h','d'));
    if (!mvhd || mvhd->len < 108) { a_box_free(&root); close(fd); snprintf(err, errcap, "%s: no mvhd", src); return -1; }
    int v1 = mvhd->raw[8] == 1;
    uint32_t movie_ts = a_rd32(mvhd->raw + (v1 ? 28 : 20));
    uint32_t next_id = a_rd32(mvhd->raw + mvhd->len - 4);
    ABox *video = NULL;
    uint32_t max_id = 0;
    for (int i = 0; i < moov->nk; i++) {
        ABox *t = &moov->kid[i];
        if (t->type != A_FOURCC('t','r','a','k')) continue;
        ABox *tk = a_box_find(t, A_FOURCC('t','k','h','d'));
        if (tk) {
            uint32_t id = a_rd32(tk->raw + (tk->raw[8] == 1 ? 28 : 20));
            if (id > max_id) max_id = id;
        }
        ABox *md = a_box_find(t, A_FOURCC('m','d','i','a'));
        ABox *hd = md ? a_box_find(md, A_FOURCC('h','d','l','r')) : NULL;
        if (hd && hd->len >= 20 && a_rd32(hd->raw + 16) == A_FOURCC('v','i','d','e') && !video) video = t;
    }
    if (!video) { a_box_free(&root); close(fd); snprintf(err, errcap, "%s: no video track", src); return -1; }
    uint32_t tc_id = next_id > max_id ? next_id : max_id + 1;
    uint64_t media_dur = (uint64_t)frames * ticks;
    uint64_t movie_dur = (uint64_t)((__int128)media_dur * movie_ts / ts);
    uint32_t flags = (drop ? 1u : 0u) | 2u;     /* drop frame, 24-hour max */
    a_push(moov, a_tmcd_trak(mov, tc_id, movie_dur, ts, media_dur, ticks, quanta, flags));
    /* mvhd.next_track_ID */
    a_be32(mvhd->raw + mvhd->len - 4, tc_id + 1);
    /* video tref -> tmcd */
    uint8_t ref[12];
    a_be32(ref, 12);
    a_be32(ref + 4, A_FOURCC('t','m','c','d'));
    a_be32(ref + 8, tc_id);
    ABox tref = a_leaf(A_FOURCC('t','r','e','f'), ref, 12);
    a_insert_before(video, tref, A_FOURCC('m','d','i','a'));

    /* Layout: ftyp, [moov if faststart], the other top-level boxes in their
     * order, [moov otherwise], then the 12-byte mdat holding the tc sample.
     * Widen any stco whose moved offsets no longer fit 32 bits (that grows
     * the moov, so lay out again), then move every chunk offset once. */
    ARegion reg[64];
    int nr = 0;
    size_t new_moov = 0;
    uint64_t tc_off = 0;
    ABox *tc_trak = &moov->kid[moov->nk - 1];
    for (int pass = 0; pass < 8; pass++) {
        new_moov = a_box_size(moov);
        int64_t pos = top[0].size + (faststart ? (int64_t)new_moov : 0);
        nr = 0;
        for (int i = 1; i < ntop; i++) {
            if (i == moov_i) continue;
            reg[nr].old_off = top[i].off;
            reg[nr].size = top[i].size;
            reg[nr].new_off = pos;
            pos += top[i].size;
            nr++;
        }
        if (!faststart) pos += (int64_t)new_moov;
        tc_off = (uint64_t)pos + 8;
        int widened = 0;
        for (int i = 0; i < moov->nk - 1; i++)
            if (moov->kid[i].type == A_FOURCC('t','r','a','k')) widened += a_widen(&moov->kid[i], reg, nr);
        if (!widened) break;
    }
    int ok = 1;
    for (int i = 0; i < moov->nk - 1; i++)
        if (moov->kid[i].type == A_FOURCC('t','r','a','k') && !a_patch_offsets(&moov->kid[i], reg, nr)) ok = 0;
    if (!ok || a_box_size(moov) != new_moov) {
        a_box_free(&root);
        close(fd);
        snprintf(err, errcap, "%s: a chunk offset points outside the media data", src);
        return -1;
    }
    /* the tc sample's chunk offset */
    ABox *md = a_box_find(tc_trak, A_FOURCC('m','d','i','a'));
    ABox *mi = a_box_find(md, A_FOURCC('m','i','n','f'));
    ABox *sb = a_box_find(mi, A_FOURCC('s','t','b','l'));
    ABox *co = a_box_find(sb, A_FOURCC('c','o','6','4'));
    a_be64(co->raw + 16, tc_off);

    uint8_t *mo = malloc(new_moov);
    size_t mp = 0;
    a_box_write(moov, mo, &mp);
    a_box_free(&root);
    uint8_t tcbox[12];
    a_be32(tcbox, 12);
    a_be32(tcbox + 4, A_FOURCC('m','d','a','t'));
    a_be32(tcbox + 8, (uint32_t)tc_frame);

    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { free(mo); close(fd); snprintf(err, errcap, "cannot create %s: %s", dst, strerror(errno)); return -1; }
    size_t bufsz = 16u << 20;
    uint8_t *buf = malloc(bufsz);
    int wok = 1;
    /* ftyp */
    {
        ssize_t r = pread(fd, buf, (size_t)top[0].size, 0);
        wok = r == top[0].size && write(out, buf, (size_t)r) == r;
    }
    if (wok && faststart) wok = write(out, mo, new_moov) == (ssize_t)new_moov;
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
    if (wok && !faststart) wok = write(out, mo, new_moov) == (ssize_t)new_moov;
    if (wok) wok = write(out, tcbox, 12) == 12;
    free(buf);
    free(mo);
    close(fd);
    if (close(out) != 0) wok = 0;
    if (!wok) { unlink(dst); snprintf(err, errcap, "writing %s failed: %s", dst, strerror(errno)); return -1; }
    return 0;
}

/* ======================================================================
   Mux
   ====================================================================== */

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
    WMediaWav wav;
    int64_t   audio_fed;
    int64_t   total_frames;     /* the caller's promised frame count, or 0 */
    int       audio_done;       /* markAsFinished sent */
    int       has_tc, tc_drop, tc_quanta;
    int64_t   tc_start;
    int       faststart;
    uint32_t  fourcc;
    int32_t   width, height;
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
    if (m->has_audio) w_media_wav_close(&m->wav);
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

/* w_media_mux_new(path, format, num, den, audio_path, audio_codec,
 * audio_kbps, tc_start_frame, tc_drop, tc_quanta, faststart, frames) */
WValue w_media_mux_new(WValue pathv, WValue fmtv, WValue numv, WValue denv, WValue audiov, WValue acodecv,
                       WValue akbpsv, WValue tcv, WValue dropv, WValue quantav, WValue fastv, WValue framesv) {
    @autoreleasepool {
        AMux *m = calloc(1, sizeof *m);
        if (!m) w_media_raise("Mux: out of memory");
        if (!w_media_str(pathv, m->path, sizeof m->path) || !m->path[0]) { free(m); w_media_raise("Mux: path must be a string"); }
        char fmt[16], ac[16], apath[4096];
        w_media_str(fmtv, fmt, sizeof fmt);
        if (!fmt[0]) {
            const char *dot = strrchr(m->path, '.');
            snprintf(fmt, sizeof fmt, "%s", dot && !strcasecmp(dot, ".mov") ? "mov" : "mp4");
        }
        if (!strcasecmp(fmt, "mov")) m->mov = 1;
        else if (strcasecmp(fmt, "mp4")) { free(m); w_media_raise("Mux: format must be :mp4 or :mov (got '%s')", fmt); }
        m->num = (int32_t)w_media_num(numv, 24, "rate numerator");
        m->den = (int32_t)w_media_num(denv, 1, "rate denominator");
        if (m->num <= 0 || m->den <= 0) { free(m); w_media_raise("Mux: rate must be a positive [num, den]"); }
        /* Track timescale: num (x1000 for small integer rates, so 24 fps is
         * 24000 with 1000 ticks a frame), always an exact multiple. */
        int64_t ts = m->num < 1000 ? (int64_t)m->num * 1000 : m->num;
        m->ts = (int32_t)ts;
        m->ticks = (int32_t)((int64_t)m->den * ts / m->num);
        m->faststart = fastv == W_NIL ? 1 : fastv > 1;
        m->total_frames = (int64_t)w_media_num(framesv, 0, "frames");
        if (tcv != W_NIL) {
            m->has_tc = 1;
            m->tc_start = (int64_t)w_media_num(tcv, 0, "timecode start");
            m->tc_drop = dropv > 1;
            m->tc_quanta = (int)w_media_num(quantav, (double)((m->num + m->den / 2) / m->den), "timecode quanta");
        }
        if (w_media_str(audiov, apath, sizeof apath) && apath[0]) {
            char err[512];
            if (w_media_wav_open(apath, &m->wav, err, sizeof err) != 0) { free(m); w_media_raise("Mux: %s", err); }
            m->has_audio = 1;
            w_media_str(acodecv, ac, sizeof ac);
            if (!ac[0]) snprintf(ac, sizeof ac, "%s", m->mov ? "pcm" : "aac");
            if (!strcasecmp(ac, "aac")) m->aac = 1;
            else if (strcasecmp(ac, "pcm")) { a_mux_free(m); w_media_raise("Mux: audio codec must be :aac or :pcm (got '%s')", ac); }
            if (!m->aac && !m->mov) { a_mux_free(m); w_media_raise("Mux: PCM audio needs a .mov (MP4 carries AAC)"); }
            m->audio_kbps = (int)w_media_num(akbpsv, m->wav.channels >= 2 ? 320 : 192, "audio bitrate");
        }
        NSString *final = [NSString stringWithUTF8String:m->path];
        NSString *target = final;
        if (m->has_tc) {
            snprintf(m->tmp, sizeof m->tmp, "%s.tw-mux-%d.%s", m->path, (int)getpid(), m->mov ? "mov" : "mp4");
            target = [NSString stringWithUTF8String:m->tmp];
        }
        [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
        NSError *err = nil;
        m->writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:target]
                                              fileType:(m->mov ? AVFileTypeQuickTimeMovie : AVFileTypeMPEG4)
                                                 error:&err];
        if (!m->writer) {
            char e[512];
            snprintf(e, sizeof e, "%s", err.localizedDescription.UTF8String ?: "?");
            a_mux_free(m);
            w_media_raise("Mux: cannot create %s: %s", m->path, e);
        }
        m->writer.movieTimeScale = m->ts;
        /* With a timecode the moov is rewritten afterwards anyway, faststart included. */
        m->writer.shouldOptimizeForNetworkUse = m->faststart && !m->has_tc;
        return w_int(w_media_handle_new(m, W_MEDIA_KIND_MUX));
    }
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
    m->delay = s->reorder;
    m->video = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:m->vfmt];
    m->video.expectsMediaDataInRealTime = NO;
    m->video.mediaTimeScale = m->ts;
    if (![m->writer canAddInput:m->video]) a_mux_fail(m, "AVAssetWriter cannot take this video format");
    [m->writer addInput:m->video];
    if (m->has_audio) {
        AudioStreamBasicDescription asbd;
        memset(&asbd, 0, sizeof asbd);
        asbd.mSampleRate = m->wav.rate;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        asbd.mChannelsPerFrame = (UInt32)m->wav.channels;
        asbd.mBitsPerChannel = 32;
        asbd.mBytesPerFrame = 4 * (UInt32)m->wav.channels;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        AudioChannelLayout layout;
        memset(&layout, 0, sizeof layout);
        layout.mChannelLayoutTag = a_layout_tag(m->wav.channels);
        OSStatus st = CMAudioFormatDescriptionCreate(NULL, &asbd, sizeof layout, &layout, 0, NULL, NULL, &m->afmt);
        if (st != noErr) a_mux_fail(m, "cannot describe the audio (OSStatus %d)", (int)st);
        NSData *ld = [NSData dataWithBytes:&layout length:sizeof layout];
        NSDictionary *settings;
        if (m->aac) {
            settings = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @(m->wav.rate),
                         AVNumberOfChannelsKey: @(m->wav.channels), AVEncoderBitRateKey: @(m->audio_kbps * 1000),
                         AVChannelLayoutKey: ld};
        } else {
            settings = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(m->wav.rate),
                         AVNumberOfChannelsKey: @(m->wav.channels), AVLinearPCMBitDepthKey: @24,
                         AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsBigEndianKey: @NO,
                         AVLinearPCMIsNonInterleaved: @NO, AVChannelLayoutKey: ld};
        }
        m->audio = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:settings sourceFormatHint:m->afmt];
        m->audio.expectsMediaDataInRealTime = NO;
        if (![m->writer canAddInput:m->audio]) a_mux_fail(m, "AVAssetWriter cannot take %s audio at %d Hz x %d", m->aac ? "AAC" : "PCM", (int)m->wav.rate, (int)m->wav.channels);
        [m->writer addInput:m->audio];
    }
    if (![m->writer startWriting]) a_mux_fail(m, "cannot start writing");
    [m->writer startSessionAtSourceTime:kCMTimeZero];
    m->started = 1;
}

/* Audio frames that belong to the first `frames` video frames (rounded). */
static int64_t a_audio_for(AMux *m, int64_t frames) {
    __int128 a = (__int128)frames * m->wav.rate * m->den;
    return (int64_t)((a * 2 + m->num) / (2 * (__int128)m->num));
}

/* The most audio the mux may feed when `video_frames` frames are written:
 * the exact total when the caller promised a frame count, else the WAV's
 * own samples, or silence only as far as the video already reaches. */
static int64_t a_audio_cap(AMux *m, int64_t video_frames) {
    if (m->total_frames > 0) return a_audio_for(m, m->total_frames);
    int64_t need = a_audio_for(m, video_frames);
    return m->wav.frames > need ? m->wav.frames : need;
}

/* Feed audio up to `upto` frames while the input takes it. Returns 1 if it
 * reached upto. */
static int a_feed_audio(AMux *m, int64_t upto) {
    if (!m->has_audio || m->audio_done) return 1;
    int ch = m->wav.channels;
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
        w_media_wav_read_f32(&m->wav, m->audio_fed, n, dst);
        CMSampleBufferRef sb = NULL;
        st = CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, m->afmt, (CMItemCount)n, CMTimeMake(m->audio_fed, m->wav.rate), NULL, &sb);
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
    int64_t lead = m->has_audio ? m->wav.rate : 0;
    a_feed_audio(m, MIN(a_audio_for(m, frame + 1) + lead, a_audio_cap(m, frame + 1)));
    while (!m->video.readyForMoreMediaData) {
        if (m->has_audio && !m->audio_done && m->total_frames > 0 && m->audio_fed >= a_audio_for(m, m->total_frames)) {
            /* All the promised audio is in: say so, or the writer keeps
             * waiting for audio past the end. */
            [m->audio markAsFinished];
            m->audio_done = 1;
        }
        if (m->has_audio && !m->audio_done && m->audio.readyForMoreMediaData) {
            int64_t cap = m->total_frames > 0 ? a_audio_cap(m, frame + 1) : MAX(a_audio_cap(m, frame + 1), m->audio_fed + m->wav.rate / 4);
            a_feed_audio(m, MIN(m->audio_fed + m->wav.rate / 4, cap));
        }
        if (m->writer.status != AVAssetWriterStatusWriting) a_mux_fail(m, "the writer stopped");
        usleep(200);
        if (++spins > 100000)
            a_mux_fail(m, "the writer stalled at frame %lld (video input not ready for 20 s; audio fed %lld, audio ready %d)",
                       (long long)frame, (long long)m->audio_fed, m->has_audio ? (int)m->audio.readyForMoreMediaData : -1);
    }
}

/* w_media_mux_append(mux, segment) -> frames written so far */
WValue w_media_mux_append(WValue mv, WValue sv) {
    @autoreleasepool {
        AMux *m = w_media_handle_get(mv, W_MEDIA_KIND_MUX, "Mux#append");
        WMediaSegment *s = w_media_segment_ready(sv, "Mux#append");
        if (s->n == 0 || !s->format) a_mux_fail(m, "empty segment");
        if (s->rate_num != m->num || s->rate_den != m->den)
            a_mux_fail(m, "segment rate %d/%d differs from the mux rate %d/%d", (int)s->rate_num, (int)s->rate_den, (int)m->num, (int)m->den);
        if (!s->s[0].sync) a_mux_fail(m, "segment does not start with a sync sample (IDR)");
        if (!m->started) a_mux_start(m, s);
        else if (!a_fmt_compatible(m->vfmt, (CMFormatDescriptionRef)s->format))
            a_mux_fail(m, "segment at frame %lld was encoded with different settings (codec, size, colour or parameter sets differ from the first segment); re-encode it with the master's settings", (long long)m->frames);
        if (s->reorder > m->delay)
            a_mux_fail(m, "segment at frame %lld needs a DTS delay of %d frames, more than the first segment's %d", (long long)m->frames, (int)s->reorder, (int)m->delay);
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
        free(sorted);
        m->frames += s->n;
        return w_int(m->frames);
    }
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
        int64_t frames = m->frames, src_frames = m->has_audio ? m->wav.frames : 0;
        if (m->has_tc) {
            char err[512];
            if (a_add_timecode(m->tmp, m->path, m->mov, (uint32_t)m->ts, (uint32_t)m->ticks, m->frames, m->tc_start,
                               (uint32_t)m->tc_quanta, m->tc_drop, m->faststart, err, sizeof err) != 0) {
                unlink(m->tmp);
                w_media_handle_drop(mv, W_MEDIA_KIND_MUX);
                a_mux_free(m);
                w_media_raise("Mux#close: adding the timecode track failed: %s", err);
            }
            unlink(m->tmp);
        }
        struct stat st;
        int64_t fsize = stat(m->path, &st) == 0 ? (int64_t)st.st_size : -1;
        int64_t vbytes = m->video_bytes;
        w_media_handle_drop(mv, W_MEDIA_KIND_MUX);
        a_mux_free(m);
        WValue a = w_array_new_empty();
        a = w_array_push(a, w_int(frames));
        a = w_array_push(a, w_int(audio_total));
        a = w_array_push(a, w_int(src_frames));
        a = w_array_push(a, w_int(vbytes));
        a = w_array_push(a, w_int(fsize));
        return a;
    }
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

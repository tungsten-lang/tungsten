/* runtime/media/media.h — the VideoToolbox / AVFoundation media bridge.
 *
 * The native half of core/media: a VideoToolbox encoder that turns RGBA/BGRA
 * frames into closed-GOP "segments" (compressed samples + the format
 * description), a segment file format, an AVAssetWriter mux that appends
 * segments passthrough with exact rational timing, PCM/AAC audio and a
 * `tmcd` track, and an AVFoundation reader for verification.
 *
 * Two files:
 *   media.c      C: handle registry, RGB -> Y'CbCr conversion, VideoToolbox
 *                sessions, segments and their files, SPS/VUI parsing, the
 *                WAV reader. On non-Apple targets it compiles to raising
 *                stubs for every entry point below (both lists).
 *   media_avf.m  Objective-C (manual retain/release, like metal.m):
 *                AVAssetWriter mux and AVAssetReader probes. Apple only.
 *
 * Linking: the compiler links media.c (every target) and media_avf.m (macOS)
 * only when a program's LLVM IR references a `@w_media_` symbol
 * (ll_needs_media in compiler/lib/driver/ir.w), adding -framework
 * VideoToolbox CoreMedia CoreVideo AVFoundation AudioToolbox Foundation
 * CoreFoundation on macOS. Canvas-only and Metal-only programs never pull
 * these frameworks in.
 *
 * ABI: every ccall entry point takes and returns NaN-boxed WValues. */

#ifndef TUNGSTEN_MEDIA_H
#define TUNGSTEN_MEDIA_H

#include <stddef.h>
#include <stdint.h>

/* ---- ccall entry points ------------------------------------------------ */

/* X(name, arity). Implemented in media.c. w_media_available is not listed: it
 * exists on every target and answers false instead of raising. */
#define W_MEDIA_C_CCALLS(X)            \
    X(w_media_codecs, 0)               \
    X(w_media_stats, 0)                \
    X(w_media_encoder_new, 12)         \
    X(w_media_encoder_encode, 4)       \
    X(w_media_encoder_segment, 1)      \
    X(w_media_encoder_info, 2)         \
    X(w_media_encoder_close, 1)        \
    X(w_media_segment_info, 2)         \
    X(w_media_segment_sample, 2)       \
    X(w_media_segment_save, 2)         \
    X(w_media_segment_load, 1)         \
    X(w_media_segment_release, 1)      \
    X(w_media_convert, 7)              \
    X(w_media_parse_sps, 2)            \
    X(w_media_wav_info, 1)

/* Implemented in media_avf.m (Apple only). */
#define W_MEDIA_AVF_CCALLS(X)          \
    X(w_media_mux_new, 12)             \
    X(w_media_mux_append, 2)           \
    X(w_media_mux_close, 1)            \
    X(w_media_probe, 3)                \
    X(w_media_frame_probe, 4)          \
    X(w_media_sync_scan, 3)

#define W_MEDIA_CCALLS(X) W_MEDIA_C_CCALLS(X) W_MEDIA_AVF_CCALLS(X)

#define W_MEDIA_PARAMS_0 void
#define W_MEDIA_PARAMS_1 WValue
#define W_MEDIA_PARAMS_2 WValue, WValue
#define W_MEDIA_PARAMS_3 WValue, WValue, WValue
#define W_MEDIA_PARAMS_4 WValue, WValue, WValue, WValue
#define W_MEDIA_PARAMS_7 W_MEDIA_PARAMS_4, WValue, WValue, WValue
#define W_MEDIA_PARAMS_11 W_MEDIA_PARAMS_7, WValue, WValue, WValue, WValue
#define W_MEDIA_PARAMS_12 W_MEDIA_PARAMS_11, WValue

#ifdef WVALUE_H
WValue w_media_available(void);
#define W_MEDIA_PROTOTYPE(name, n) WValue name(W_MEDIA_PARAMS_##n);
W_MEDIA_CCALLS(W_MEDIA_PROTOTYPE)
#undef W_MEDIA_PROTOTYPE
#endif

/* ---- shared between media.c and media_avf.m (Apple only) ---------------- */

#if defined(__APPLE__) && defined(WVALUE_H)

/* Handle kinds in the shared registry. */
enum { W_MEDIA_KIND_ENCODER = 1, W_MEDIA_KIND_SEGMENT = 2, W_MEDIA_KIND_MUX = 3 };

/* One compressed sample of a segment, in decode order. pts/dts are frame
 * indices relative to the segment's first frame (dts == pts without
 * reordering). */
typedef struct WMediaSample {
    uint64_t offset;   /* into WMediaSegment.data */
    uint32_t size;
    int32_t  pts;
    int32_t  dts;
    uint8_t  sync;     /* 1 for a sync sample (IDR / keyframe) */
    uint8_t  pad[3];
} WMediaSample;

/* A closed GOP: one IDR, then the frames that depend on it. */
typedef struct WMediaSegment {
    uint32_t      fourcc;      /* 'avc1', 'hvc1', 'apcn', 'apch', ... */
    int32_t       width, height;
    int32_t       rate_num, rate_den;
    void         *format;      /* CMVideoFormatDescriptionRef (retained) */
    int32_t       n, cap;      /* samples */
    WMediaSample *s;
    uint8_t      *data;
    size_t        len, dcap;
    int32_t       reorder;     /* max (sorted pts - pts) over samples: the DTS delay needed */
    /* Encoding state: frames are emitted asynchronously by VideoToolbox. */
    int32_t       submitted, emitted, finished;
    int32_t       err;         /* first OSStatus error, or a W_MEDIA_ERR_* code */
    int64_t       first_global; /* encoder-wide index of local frame 0 */
    void         *enc;         /* WMediaEncoder while frames are pending, else NULL */
    void         *lock;        /* pthread_mutex_t + cond (opaque) */
} WMediaSegment;

/* Registry: a generation-checked integer handle for a native object. */
int64_t w_media_handle_new(void *p, int kind);
void   *w_media_handle_get(WValue h, int kind, const char *what);   /* raises on a stale handle */
void    w_media_handle_drop(WValue h, int kind);

/* The live segment for a handle, after waiting for its frames to be
 * emitted. Raises if the handle is stale or the segment failed to encode. */
WMediaSegment *w_media_segment_ready(WValue h, const char *what);

/* WAV reader shared by the mux: an mmap'd RIFF/RF64 file. */
typedef struct WMediaWav {
    void          *map;        /* mmap base */
    size_t         map_len;
    const uint8_t *data;       /* first sample frame */
    int64_t        frames;     /* sample frames */
    int32_t        channels;
    int32_t        rate;
    int32_t        bits;       /* 16, 24, 32 (int or float), 64 (float) */
    int32_t        is_float;
    int32_t        block;      /* bytes per sample frame */
} WMediaWav;

/* Open/close a WAV file. Returns 0 on success, else writes a message to err. */
int  w_media_wav_open(const char *path, WMediaWav *out, char *err, size_t errcap);
void w_media_wav_close(WMediaWav *w);
/* Convert frames [first, first + n) to interleaved float32 (zeros past the end). */
void w_media_wav_read_f32(const WMediaWav *w, int64_t first, int64_t n, float *out);

/* Bitstream colour/VUI facts from an avcC or hvcC record. */
typedef struct WMediaVui {
    int ok;
    int profile, level, bit_depth, chroma_format;
    int width, height;
    int vui_present;
    int video_signal_type_present, full_range;
    int colour_description_present, primaries, transfer, matrix;
    int chroma_loc_present, chroma_loc_top, chroma_loc_bottom;
    int timing_present;
    uint32_t num_units_in_tick, time_scale;
    int poc_type, max_ref_frames, sps_count, pps_count, vps_count;
} WMediaVui;

int w_media_vui_parse(const uint8_t *rec, size_t len, int hevc, WMediaVui *out);

/* Small helpers media_avf.m shares. */
__attribute__((noreturn, format(printf, 1, 2))) void w_media_raise(const char *fmt, ...);
int    w_media_str(WValue v, char *buf, size_t cap);
double w_media_num(WValue v, double dflt, const char *what);

#endif /* __APPLE__ && WVALUE_H */

#endif /* TUNGSTEN_MEDIA_H */

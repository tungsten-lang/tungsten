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
    X(w_media_encoder_set, 3)          \
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
    X(w_media_wav_info, 1)             \
    X(w_media_scaler_new, 1)           \
    X(w_media_scaler_run, 7)           \
    X(w_media_scaler_info, 2)          \
    X(w_media_scaler_free, 1)

/* Implemented in media_avf.m (Apple only). */
#define W_MEDIA_AVF_CCALLS(X)          \
    X(w_media_mux_new, 12)             \
    X(w_media_mux_set, 3)              \
    X(w_media_chapterize, 4)           \
    X(w_media_mux_append, 2)           \
    X(w_media_mux_close, 1)            \
    X(w_media_probe, 3)                \
    X(w_media_frame_probe, 4)          \
    X(w_media_sync_scan, 3)            \
    X(w_media_decoder_open, 3)         \
    X(w_media_decoder_read, 3)         \
    X(w_media_decoder_info, 2)         \
    X(w_media_decoder_close, 1)        \
    X(w_media_transcode_new, 1)        \
    X(w_media_transcode_step, 2)       \
    X(w_media_transcode_finish, 1)     \
    X(w_media_transcode_free, 1)

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

/* WMediaSegment.flags: encoded with frame reordering (B-frames) allowed, so
 * a mux must reserve W_MEDIA_REORDER_DELAY frames of DTS delay up front. */
#define W_MEDIA_SEG_REORDER   1u
#define W_MEDIA_REORDER_DELAY 4

/* Handle kinds in the shared registry. */
enum { W_MEDIA_KIND_ENCODER = 1, W_MEDIA_KIND_SEGMENT = 2, W_MEDIA_KIND_MUX = 3, W_MEDIA_KIND_SCALER = 4,
       W_MEDIA_KIND_DECODER = 5, W_MEDIA_KIND_TRANSCODE = 6, W_MEDIA_KIND_COUNT = 7 };

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
    uint32_t      flags;       /* W_MEDIA_SEG_* */
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

/* ---- Scaler (media.c; the Metal backend is in media_avf.m) ----
 *
 * Separable resampling of an 8-bit interleaved plane (RGBA: 4 channels, a
 * Y' plane: 1, an interleaved CbCr plane: 2) through precomputed weight
 * tables. A plan maps a source crop (fractional) onto a destination rect
 * and fills the rest of the destination. Every backend uses the same
 * mapping; the CPU and Metal backends also use the same weights. */

enum { W_MEDIA_FILTER_LANCZOS3 = 0, W_MEDIA_FILTER_BICUBIC = 1, W_MEDIA_FILTER_BILINEAR = 2 };
/* RGBA alpha: NONE treats the 4 channels as data; PREMUL (premultiplied,
 * Canvas) filters as is and clamps colour <= alpha; STRAIGHT premultiplies
 * on load and divides on store; OPAQUE ignores the input alpha, writes 255. */
enum { W_MEDIA_ALPHA_NONE = 0, W_MEDIA_ALPHA_PREMUL = 1, W_MEDIA_ALPHA_STRAIGHT = 2, W_MEDIA_ALPHA_OPAQUE = 3 };
enum { W_MEDIA_BACKEND_AUTO = 0, W_MEDIA_BACKEND_CPU = 1, W_MEDIA_BACKEND_VIMAGE = 2, W_MEDIA_BACKEND_METAL = 3 };

/* One axis: output sample j reads source samples start[j] .. start[j] + taps
 * with weights w[j * taps ...] (normalised, edges clamped and folded). */
typedef struct WMediaAxis {
    int      n, taps, nsrc;
    int32_t *start;
    float   *w;
    int      lo, hi;          /* source samples read: [lo, hi) */
} WMediaAxis;

typedef struct WMediaScale {
    int        ch, alpha, filter;
    int        src_w, src_h;  /* source plane, samples */
    int        dst_w, dst_h;  /* destination plane */
    int        rx, ry, rw, rh;    /* destination rect, plane samples */
    int        vimage_ok;     /* integer crop, centre phase, Lanczos-3, 8-bit: vImage can do it */
    int        icx, icy, icw, ich;
    WMediaAxis ax, ay;
    uint8_t    fill[4];
    int        out_bits;      /* 8, or 10 (16-bit words, MSB-aligned) */
    uint64_t   id;            /* unique per plan */
    /* backend state */
    int        bands;
    float     *scratch;
    size_t     scratch_band;  /* floats per band */
    void      *vtemp;
    size_t     vtemp_len;
    void      *metal;         /* media_avf.m's per-plan buffers */
} WMediaScale;

/* Plan one plane. Geometry is in luma (full-resolution) units: crop
 * (x, y, w, h) of the source picture, rect (x, y, w, h) of the destination
 * picture. A plane is subsampled by (sx, sy) with its sample 0 centred at
 * (ox, oy) luma units (0.5, 0.5 for luma and RGBA; 4:2:0 chroma sited left
 * is (0.5, 1.0)). Returns 0, or -1 with a message. */
int  w_media_scale_plan(WMediaScale *s, int ch, int alpha, int filter, int src_w, int src_h, int dst_w, int dst_h,
                        const double crop[4], const int rect[4], int ssx, int ssy, double osx, double osy,
                        int sdx, int sdy, double odx, double ody, const uint8_t fill[4], int out_bits,
                        char *err, size_t cap);
void w_media_scale_free(WMediaScale *s);
/* Run a plan; backend W_MEDIA_BACKEND_*, AUTO picks. Returns the backend
 * used, or -1 with a message. src_len / dst_len are the readable/writable
 * bytes from src / dst (0: unknown). */
int  w_media_scale_run(WMediaScale *s, int backend, const uint8_t *src, size_t sstride, size_t src_len,
                       uint8_t *dst, size_t dstride, size_t dst_len, char *err, size_t cap);
int  w_media_scale_default_backend(int ch, int filter);
/* media_avf.m */
int  w_media_metal_available(void);
int  w_media_scale_metal(WMediaScale *s, const uint8_t *src, size_t sstride, size_t src_len,
                         uint8_t *dst, size_t dstride, size_t dst_len, char *err, size_t cap);
void w_media_scale_metal_release(WMediaScale *s);
/* One plan run: source and destination. */
typedef struct WMediaJob {
    WMediaScale   *s;
    const uint8_t *src;
    size_t         sstride, src_len;
    uint8_t       *dst;
    size_t         dstride, dst_len;
} WMediaJob;
/* Several plans in one Metal command buffer (wrapped buffers only after the first). */
int  w_media_scale_metal_jobs(WMediaJob *jobs, int n, char *err, size_t cap);

/* ---- Encoder internals for the transcoder (media.c) ---- */
typedef struct MEncoder MEncoder;
MEncoder *w_media_enc_open(const char *codec, int w, int h, int num, int den, double quality, int64_t bitrate, int gop,
                           const char *input, const char *siting, int reorder, int speed, const char *profile,
                           char *err, size_t cap);
/* A pixel buffer from the session's pool (CVPixelBufferRef, retained), to
 * fill with Y'CbCr and pass to w_media_enc_submit. */
void *w_media_enc_buffer(MEncoder *e);
int   w_media_enc_bits(MEncoder *e);
int   w_media_enc_vsub(MEncoder *e);
/* Encode a filled pool buffer (releases it). OSStatus. */
int   w_media_enc_submit(MEncoder *e, void *pixel_buffer);
/* Convert R'G'B' pixels (the encoder's input layout) and encode. OSStatus. */
int   w_media_enc_encode_rgb(MEncoder *e, const uint8_t *src, size_t stride);
/* Close the open GOP: the segment, or NULL if no frames are open. */
WMediaSegment *w_media_enc_cut(MEncoder *e);
/* Wait for a segment's frames; 0, or -1 with a message. */
int   w_media_seg_finish(WMediaSegment *s, char *err, size_t cap);
void  w_media_seg_free(WMediaSegment *s);
/* Load a segment file (TWMS); NULL with a message. */
WMediaSegment *w_media_seg_load(const char *path, char *err, size_t cap);
void  w_media_enc_free(MEncoder *e);
double w_media_enc_seconds(MEncoder *e, int which);   /* 0 convert, 1 submit, 2 wait */

/* Shared helpers from media.c. */
void          *w_media_handle_peek(WValue h, int kind);     /* NULL when stale */
const uint8_t *w_media_pixels(WValue v, int64_t off, int64_t *avail, const char *what);
int            w_media_filter_id(const char *name);          /* -1 if unknown */
int            w_media_backend_id(const char *name);         /* -1 if unknown */
const char    *w_media_backend_name(int backend);

/* Small helpers media_avf.m shares. */
__attribute__((noreturn, format(printf, 1, 2))) void w_media_raise(const char *fmt, ...);
int    w_media_str(WValue v, char *buf, size_t cap);
double w_media_num(WValue v, double dflt, const char *what);

#endif /* __APPLE__ && WVALUE_H */

#endif /* TUNGSTEN_MEDIA_H */

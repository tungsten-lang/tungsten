/* runtime/media/media_sysdec.m — Apple's own decoders behind core/codec/system.
 *
 * The system half of core/codec: the same contract as the pure-Tungsten
 * decoders (compressed samples from core/codec's demuxers in, Y'CbCr planes
 * or interleaved f32 PCM out), backed by VideoToolbox (H.264, HEVC; hardware
 * where the machine has it) and AudioToolbox's AudioConverter (AAC-LC,
 * HE-AAC v1/v2, xHE-AAC/USAC, AC-3, E-AC-3, …). core/codec/system registers
 * them as alternatives in the codec registry, so a pipeline can prefer the
 * system decoders for some codecs and fall back to ours (or the reverse).
 *
 * Video:
 *   w_media_vtdec_new(codec, config, [width, height, bits, async, full_range]) -> handle
 *       codec "avc1"/"avc3" (config = avcC), "hvc1"/"hev1" (hvcC), "av01" (av1C)
 *       or "vp09" (vpcC payload incl. version/flags); AV1 / VP9 only where
 *       VideoToolbox has a hardware decoder for them
 *   w_media_vtdec_decode(h, sample, pts_us, dts_us) -> frames waiting
 *       sample: a ByteArray / u8[] holding one access unit (length-prefixed NALs)
 *       VideoToolbox outputs frames in decode order; take reorders them.
 *   w_media_vtdec_take(h, flush, planes) -> [pts_us, width, height, bits] or nil
 *       the next frame in presentation order; planes [Y, Cb, Cr] (u8[] for
 *       8-bit, u16[] for 10-bit, tightly packed) receive it de-interleaved
 *       from NV12/P010, or nil to drop it (throughput measurements).
 *       flush: true after the last sample (waits for every frame).
 *   w_media_vtdec_take_surface(h, flush) -> [pts_us, width, height, bits, surface] or nil
 *       the same frame without a copy: surface is a handle on the decoder's
 *       IOSurface-backed, Metal-compatible CVPixelBuffer (NV12 / P010),
 *       which the caller gives back with w_media_surface_release
 *   w_media_surface_planes(surface, planes) -> true: copy it out as take does
 *   w_media_surface_ptr(surface) -> the CVPixelBufferRef as an integer (for
 *       runtime/graphics.m, which retains what it keeps), 0 when released
 *   w_media_surface_release(surface)
 *   w_media_vtdec_info(h, key) -> "hw" (true when VideoToolbox decodes in
 *       hardware), "decoded", "errors", "status" (last OSStatus)
 *   w_media_vtdec_reset(h)     drop queued frames (after a seek)
 *   w_media_vtdec_close(h)
 *
 * Audio:
 *   w_media_atdec_new(format, cookie, [rate, channels, frames_per_packet]) -> handle
 *       format: "aac " (any MPEG-4 audio: the AudioSpecificConfig decides
 *       LC / HE / HEv2 / USAC), "usac", "ac-3", "ec-3", "mp3 ", …
 *       cookie: the AudioSpecificConfig (wrapped in an ES descriptor here) for
 *       MPEG-4 audio; for AC-3 / E-AC-3 the first packet (its header gives
 *       the format), or nil.
 *   w_media_atdec_decode(h, packet, out) -> frames written to out (f32[],
 *       interleaved, -1..1), at most out.size / channels
 *   w_media_atdec_info(h, key) -> "rate", "channels", "format" (fourcc of the
 *       decoded layer, e.g. "aacp" for HE-AAC v2), "frames_per_packet"
 *   w_media_atdec_reset(h)
 *   w_media_atdec_close(h)
 *
 * Measurement:
 *   w_media_sys_rusage() -> [user_s, system_s, max_rss_bytes, monotonic_s]
 *
 * Nothing here plays sound or touches the display. */

#import <Foundation/Foundation.h>

#include "runtime.h"
#include "wvalue.h"
#include "media.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

#pragma clang diagnostic error "-Wmissing-prototypes"

/* ---- helpers ------------------------------------------------------------ */

static WValue s_arr(WValue a, int i) {
    if (!w_is_array(a) || i >= w_as_array(a)->size) return W_NIL;
    return w_array_get(a, w_int(i));
}

/* the bytes of a ByteArray / u8[] (NULL for nil) */
static const uint8_t *s_bytes(WValue v, size_t *n, const char *what) {
    *n = 0;
    if (v == W_NIL) return NULL;
    if (!w_is_array(v)) w_media_raise("%s: expected a ByteArray / u8[]", what);
    WArray *a = w_as_array(v);
    if (a->ebits != 8) w_media_raise("%s: expected a ByteArray / u8[] (got another element type)", what);
    *n = (size_t)a->size;
    return (const uint8_t *)a->slots + a->start;
}

/* a typed array's element pointer and size; ebits must match */
static void *s_typed(WValue v, int ebits, int64_t *n, const char *what) {
    if (!w_is_array(v)) w_media_raise("%s: expected a typed array", what);
    WArray *a = w_as_array(v);
    if (a->ebits != ebits) w_media_raise("%s: wrong element type (ebits %d, want %d)", what, (int)a->ebits, ebits);
    *n = a->size;
    int esz = ebits == 8 ? 1 : ebits == 16 ? 2 : 4;
    return (uint8_t *)a->slots + (size_t)a->start * (size_t)esz;
}

static double s_now(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)(mach_absolute_time() * tb.numer / tb.denom) / 1e9;
}

WValue w_media_sys_rusage(void) {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    WValue a = w_array_new_empty();
    a = w_array_push(a, w_float((double)ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6));
    a = w_array_push(a, w_float((double)ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6));
    a = w_array_push(a, w_int((int64_t)ru.ru_maxrss));      /* bytes on macOS */
    a = w_array_push(a, w_float(s_now()));
    return a;
}

/* ======================================================================
   VideoToolbox decoder
   ====================================================================== */

typedef struct SFrame {
    int64_t          pts;
    CVPixelBufferRef pb;
} SFrame;

typedef struct SVid {
    CMVideoFormatDescriptionRef fmt;
    VTDecompressionSessionRef   vt;
    pthread_mutex_t mu;
    SFrame *q;                 /* decoded frames, sorted by pts */
    int     n, cap;
    int64_t *fly;              /* [id, pts] of samples submitted but not yet output */
    int     nfly, cfly;
    int64_t next_id;
    int64_t dts;               /* decode time of the latest sample: frames up to it are final */
    int     flushing;          /* after a flush take, until the next decode: every frame is final */
    int     async, bits;
    int64_t decoded, errors;
    OSStatus last;
} SVid;

static void s_vid_output(void *ref, void *frameref, OSStatus st, VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts, CMTime dur) {
    (void)flags; (void)dur;
    SVid *d = ref;
    pthread_mutex_lock(&d->mu);
    int64_t id = (int64_t)(intptr_t)frameref;
    for (int i = 0; i < d->nfly; i++)
        if (d->fly[2 * i] == id) {
            d->fly[2 * i] = d->fly[2 * (d->nfly - 1)];
            d->fly[2 * i + 1] = d->fly[2 * (d->nfly - 1) + 1];
            d->nfly--;
            break;
        }
    if (st != noErr || !img) {
        if (st != noErr) { d->errors++; d->last = st; }
        pthread_mutex_unlock(&d->mu);
        return;
    }
    int64_t p = CMTIME_IS_NUMERIC(pts) ? CMTimeConvertScale(pts, 1000000, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value : d->decoded;
    if (d->n == d->cap) {
        d->cap = d->cap ? d->cap * 2 : 16;
        d->q = realloc(d->q, (size_t)d->cap * sizeof *d->q);
    }
    int i = d->n;
    while (i > 0 && d->q[i - 1].pts > p) { d->q[i] = d->q[i - 1]; i--; }
    d->q[i].pts = p;
    d->q[i].pb = CVPixelBufferRetain(img);
    d->n++;
    d->decoded++;
    pthread_mutex_unlock(&d->mu);
}

static void s_vid_free(SVid *d) {
    if (d->vt) {
        VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
        VTDecompressionSessionInvalidate(d->vt);
        CFRelease(d->vt);
    }
    for (int i = 0; i < d->n; i++) CVPixelBufferRelease(d->q[i].pb);
    free(d->q);
    free(d->fly);
    if (d->fmt) CFRelease(d->fmt);
    pthread_mutex_destroy(&d->mu);
    free(d);
}

WValue w_media_vtdec_new(WValue codecv, WValue cfgv, WValue optv) {
    @autoreleasepool {
        char codec[16];
        w_media_str(codecv, codec, sizeof codec);
        size_t n = 0;
        const uint8_t *cfg = s_bytes(cfgv, &n, "vtdec_new config");
        int hevc = !strcmp(codec, "hvc1") || !strcmp(codec, "hev1");
        int avc = !strcmp(codec, "avc1") || !strcmp(codec, "avc3");
        int av1 = !strcmp(codec, "av01");
        int vp9 = !strcmp(codec, "vp09");
        if (!hevc && !avc && !av1 && !vp9) w_media_raise("vtdec_new: unsupported codec '%s' (avc1, avc3, hvc1, hev1, av01, vp09)", codec);
        CMVideoCodecType ctype = hevc ? kCMVideoCodecType_HEVC : avc ? kCMVideoCodecType_H264 : av1 ? kCMVideoCodecType_AV1 : kCMVideoCodecType_VP9;
        CFStringRef atom = hevc ? CFSTR("hvcC") : avc ? CFSTR("avcC") : av1 ? CFSTR("av1C") : CFSTR("vpcC");
        /* VP9 is a supplemental decoder on macOS (registered on demand); AV1
         * and VP9 decode only where the machine has them (no software path) */
        if (vp9) {
            if (@available(macOS 11.0, *)) VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9);
        }
        if ((av1 || vp9) && !VTIsHardwareDecodeSupported(ctype)) w_media_raise("vtdec_new: no %s decoder on this machine", codec);
        if (!cfg || n < 4 || ((avc || hevc) && n < 7)) w_media_raise("vtdec_new: missing %s record", hevc ? "hvcC" : avc ? "avcC" : av1 ? "av1C" : "vpcC");
        int32_t w = (int32_t)w_media_num(s_arr(optv, 0), 0, "width"), h = (int32_t)w_media_num(s_arr(optv, 1), 0, "height");
        int bits = (int)w_media_num(s_arr(optv, 2), 8, "bits");
        int async = (int)w_media_num(s_arr(optv, 3), 1, "async");
        int full = (int)w_media_num(s_arr(optv, 4), 0, "full_range");
        if (w <= 0 || h <= 0) {
            WMediaVui v;
            if ((avc || hevc) && w_media_vui_parse(cfg, n, hevc, &v) == 0 && v.ok) { w = v.width; h = v.height; }
        }
        if (w <= 0 || h <= 0) w_media_raise("vtdec_new: unknown picture size");

        CFDataRef rec = CFDataCreate(NULL, cfg, (CFIndex)n);
        const void *ak[] = { atom };
        const void *av[] = { rec };
        CFDictionaryRef atoms = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        const void *ek[] = { kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms };
        const void *ev[] = { atoms };
        CFDictionaryRef ext = CFDictionaryCreate(NULL, ek, ev, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CMVideoFormatDescriptionRef fmt = NULL;
        OSStatus st = CMVideoFormatDescriptionCreate(NULL, ctype, w, h, ext, &fmt);
        CFRelease(ext); CFRelease(atoms); CFRelease(rec);
        if (st != noErr) w_media_raise("vtdec_new: CMVideoFormatDescriptionCreate failed (OSStatus %d)", (int)st);

        SVid *d = calloc(1, sizeof *d);
        pthread_mutex_init(&d->mu, NULL);
        d->fmt = fmt;
        d->async = async;
        d->bits = bits > 8 ? 10 : 8;
        d->dts = INT64_MIN;
        OSType pix = d->bits > 8 ? (full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
                                 : (full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
        CFNumberRef pixn = CFNumberCreate(NULL, kCFNumberSInt32Type, &pix);
        /* IOSurface-backed and Metal-compatible, so a frame can be drawn
         * straight from the decoder's buffer (w_media_vtdec_take_surface) */
        CFDictionaryRef ios = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        const void *pk[] = { kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferIOSurfacePropertiesKey, kCVPixelBufferMetalCompatibilityKey };
        const void *pv[] = { pixn, ios, kCFBooleanTrue };
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, pk, pv, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(ios);
        const void *sk[] = { kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder };
        const void *sv[] = { kCFBooleanTrue };
        CFDictionaryRef spec = CFDictionaryCreate(NULL, sk, sv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        VTDecompressionOutputCallbackRecord cb = { s_vid_output, d };
        st = VTDecompressionSessionCreate(NULL, fmt, spec, attrs, &cb, &d->vt);
        CFRelease(spec); CFRelease(attrs); CFRelease(pixn);
        if (st != noErr) {
            d->vt = NULL;
            s_vid_free(d);
            w_media_raise("vtdec_new: VTDecompressionSessionCreate failed (OSStatus %d)", (int)st);
        }
        return w_int(w_media_handle_new(d, W_MEDIA_KIND_SYSVIDEO));
    }
}

WValue w_media_vtdec_decode(WValue hv, WValue samplev, WValue ptsv, WValue dtsv) {
    SVid *d = w_media_handle_get(hv, W_MEDIA_KIND_SYSVIDEO, "vtdec_decode");
    size_t n = 0;
    const uint8_t *src = s_bytes(samplev, &n, "vtdec_decode sample");
    if (!src || n == 0) return w_int(d->n);
    int64_t pts = (int64_t)w_media_num(ptsv, 0, "pts");
    int64_t dts = dtsv == W_NIL ? pts : (int64_t)w_media_num(dtsv, 0, "dts");
    void *mem = malloc(n);
    memcpy(mem, src, n);
    CMBlockBufferRef bb = NULL;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, mem, n, kCFAllocatorMalloc, NULL, 0, n, 0, &bb);
    if (st != noErr) { free(mem); w_media_raise("vtdec_decode: CMBlockBufferCreate failed (%d)", (int)st); }
    CMSampleTimingInfo t = { kCMTimeInvalid, CMTimeMake(pts, 1000000), kCMTimeInvalid };
    CMSampleBufferRef sb = NULL;
    st = CMSampleBufferCreateReady(NULL, bb, d->fmt, 1, 1, &t, 1, &n, &sb);
    CFRelease(bb);
    if (st != noErr) w_media_raise("vtdec_decode: CMSampleBufferCreate failed (%d)", (int)st);
    VTDecodeFrameFlags fl = 0;
    if (d->async) fl |= kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags info = 0;
    pthread_mutex_lock(&d->mu);
    int64_t id = ++d->next_id;
    if (d->nfly == d->cfly) {
        d->cfly = d->cfly ? d->cfly * 2 : 16;
        d->fly = realloc(d->fly, (size_t)d->cfly * 2 * sizeof *d->fly);
    }
    d->fly[2 * d->nfly] = id;
    d->fly[2 * d->nfly + 1] = pts;
    d->nfly++;
    if (dts > d->dts) d->dts = dts;
    d->flushing = 0;
    pthread_mutex_unlock(&d->mu);
    st = VTDecompressionSessionDecodeFrame(d->vt, sb, fl, (void *)(intptr_t)id, &info);
    CFRelease(sb);
    if (st != noErr) {
        pthread_mutex_lock(&d->mu);
        d->errors++; d->last = st;
        for (int i = 0; i < d->nfly; i++)
            if (d->fly[2 * i] == id) { d->fly[2 * i] = d->fly[2 * (d->nfly - 1)]; d->fly[2 * i + 1] = d->fly[2 * (d->nfly - 1) + 1]; d->nfly--; break; }
        pthread_mutex_unlock(&d->mu);
    }
    pthread_mutex_lock(&d->mu);
    int q = d->n;
    pthread_mutex_unlock(&d->mu);
    return w_int(q);
}

/* de-interleave one NV12 / P010 frame into planar Y, Cb, Cr */
static void s_vid_copy(int bits, CVPixelBufferRef pb, WValue planes, int w, int h) {
    int cw = (w + 1) / 2, ch = (h + 1) / 2;
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    int64_t ny, nb, nr;
    if (bits == 8) {
        uint8_t *Y = s_typed(s_arr(planes, 0), 8, &ny, "vtdec_take Y"), *B = s_typed(s_arr(planes, 1), 8, &nb, "vtdec_take Cb"),
                *R = s_typed(s_arr(planes, 2), 8, &nr, "vtdec_take Cr");
        if (ny < (int64_t)w * h || nb < (int64_t)cw * ch || nr < (int64_t)cw * ch) { CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); w_media_raise("vtdec_take: planes too small"); }
        for (int y = 0; y < h; y++) memcpy(Y + (size_t)y * w, yp + (size_t)y * ys, (size_t)w);
        for (int y = 0; y < ch; y++) {
            const uint8_t *s = cp + (size_t)y * cs;
            uint8_t *b = B + (size_t)y * cw, *r = R + (size_t)y * cw;
            for (int x = 0; x < cw; x++) { b[x] = s[2 * x]; r[x] = s[2 * x + 1]; }
        }
    } else {
        uint16_t *Y = s_typed(s_arr(planes, 0), 16, &ny, "vtdec_take Y"), *B = s_typed(s_arr(planes, 1), 16, &nb, "vtdec_take Cb"),
                 *R = s_typed(s_arr(planes, 2), 16, &nr, "vtdec_take Cr");
        if (ny < (int64_t)w * h || nb < (int64_t)cw * ch || nr < (int64_t)cw * ch) { CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); w_media_raise("vtdec_take: planes too small"); }
        for (int y = 0; y < h; y++) {
            const uint16_t *s = (const uint16_t *)(yp + (size_t)y * ys);
            uint16_t *o = Y + (size_t)y * w;
            for (int x = 0; x < w; x++) o[x] = s[x] >> 6;
        }
        for (int y = 0; y < ch; y++) {
            const uint16_t *s = (const uint16_t *)(cp + (size_t)y * cs);
            uint16_t *b = B + (size_t)y * cw, *r = R + (size_t)y * cw;
            for (int x = 0; x < cw; x++) { b[x] = s[2 * x] >> 6; r[x] = s[2 * x + 1] >> 6; }
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

/* the next final frame (retained; NULL when none is ready) */
static CVPixelBufferRef s_vid_next(SVid *d, WValue flushv, int64_t *pts) {
    if (w_truthy(flushv)) {
        VTDecompressionSessionFinishDelayedFrames(d->vt);
        VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
        pthread_mutex_lock(&d->mu);
        d->flushing = 1;
        pthread_mutex_unlock(&d->mu);
    }
    pthread_mutex_lock(&d->mu);
    if (d->n == 0) { pthread_mutex_unlock(&d->mu); return NULL; }
    if (!d->flushing) {
        /* VideoToolbox outputs in decode order: a frame is final once no
         * later sample can precede it (its pts is at most the latest decode
         * time, as pts >= dts) and no sample still in flight has a smaller pts */
        int64_t p = d->q[0].pts;
        int ok = p <= d->dts;
        for (int i = 0; ok && i < d->nfly; i++)
            if (d->fly[2 * i + 1] < p) ok = 0;
        if (!ok) { pthread_mutex_unlock(&d->mu); return NULL; }
    }
    SFrame f = d->q[0];
    memmove(d->q, d->q + 1, (size_t)(d->n - 1) * sizeof *d->q);
    d->n--;
    pthread_mutex_unlock(&d->mu);
    *pts = f.pts;
    return f.pb;
}

static WValue s_vid_result(SVid *d, int64_t pts, int w, int h) {
    WValue r = w_array_new_empty();
    r = w_array_push(r, w_int(pts));
    r = w_array_push(r, w_int(w));
    r = w_array_push(r, w_int(h));
    r = w_array_push(r, w_int(d->bits));
    return r;
}

WValue w_media_vtdec_take(WValue hv, WValue flushv, WValue planes) {
    SVid *d = w_media_handle_get(hv, W_MEDIA_KIND_SYSVIDEO, "vtdec_take");
    int64_t pts = 0;
    CVPixelBufferRef pb = s_vid_next(d, flushv, &pts);
    if (!pb) return W_NIL;
    int w = (int)CVPixelBufferGetWidth(pb), h = (int)CVPixelBufferGetHeight(pb);
    if (planes != W_NIL) s_vid_copy(d->bits, pb, planes, w, h);
    CVPixelBufferRelease(pb);
    return s_vid_result(d, pts, w, h);
}

WValue w_media_vtdec_take_surface(WValue hv, WValue flushv) {
    SVid *d = w_media_handle_get(hv, W_MEDIA_KIND_SYSVIDEO, "vtdec_take_surface");
    int64_t pts = 0;
    CVPixelBufferRef pb = s_vid_next(d, flushv, &pts);
    if (!pb) return W_NIL;
    int w = (int)CVPixelBufferGetWidth(pb), h = (int)CVPixelBufferGetHeight(pb);
    WValue r = s_vid_result(d, pts, w, h);
    return w_array_push(r, w_int(w_media_handle_new(pb, W_MEDIA_KIND_SURFACE)));   /* the handle owns the retain */
}

WValue w_media_surface_planes(WValue sv, WValue planes) {
    CVPixelBufferRef pb = w_media_handle_get(sv, W_MEDIA_KIND_SURFACE, "surface_planes");
    OSType f = CVPixelBufferGetPixelFormatType(pb);
    int bits = (f == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange || f == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) ? 10 : 8;
    s_vid_copy(bits, pb, planes, (int)CVPixelBufferGetWidth(pb), (int)CVPixelBufferGetHeight(pb));
    return W_TRUE;
}

WValue w_media_surface_ptr(WValue sv) {
    void *pb = w_media_handle_peek(sv, W_MEDIA_KIND_SURFACE);
    return w_int((int64_t)(intptr_t)pb);
}

WValue w_media_surface_release(WValue sv) {
    CVPixelBufferRef pb = w_media_handle_peek(sv, W_MEDIA_KIND_SURFACE);
    if (!pb) return W_FALSE;
    w_media_handle_drop(sv, W_MEDIA_KIND_SURFACE);
    CVPixelBufferRelease(pb);
    return W_TRUE;
}

WValue w_media_vtdec_info(WValue hv, WValue keyv) {
    SVid *d = w_media_handle_get(hv, W_MEDIA_KIND_SYSVIDEO, "vtdec_info");
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "hw")) {
        CFBooleanRef b = NULL;
        if (VTSessionCopyProperty(d->vt, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &b) == noErr && b) {
            int on = CFBooleanGetValue(b);
            CFRelease(b);
            return on ? W_TRUE : W_FALSE;
        }
        return W_FALSE;
    }
    if (!strcmp(k, "decoded")) return w_int(d->decoded);
    if (!strcmp(k, "errors")) return w_int(d->errors);
    if (!strcmp(k, "status")) return w_int(d->last);
    if (!strcmp(k, "queued")) return w_int(d->n);
    w_media_raise("vtdec_info: unknown key '%s'", k);
}

WValue w_media_vtdec_reset(WValue hv) {
    SVid *d = w_media_handle_get(hv, W_MEDIA_KIND_SYSVIDEO, "vtdec_reset");
    VTDecompressionSessionWaitForAsynchronousFrames(d->vt);
    pthread_mutex_lock(&d->mu);
    for (int i = 0; i < d->n; i++) CVPixelBufferRelease(d->q[i].pb);
    d->n = 0;
    d->nfly = 0;
    d->dts = INT64_MIN;
    pthread_mutex_unlock(&d->mu);
    return W_TRUE;
}

WValue w_media_vtdec_close(WValue hv) {
    SVid *d = w_media_handle_peek(hv, W_MEDIA_KIND_SYSVIDEO);
    if (!d) return W_FALSE;
    w_media_handle_drop(hv, W_MEDIA_KIND_SYSVIDEO);
    s_vid_free(d);
    return W_TRUE;
}

/* ======================================================================
   AudioConverter decoder
   ====================================================================== */

typedef struct SAud {
    AudioConverterRef conv;
    AudioStreamBasicDescription in, out;
    const uint8_t *pkt;
    UInt32 pkt_len;
    int    fed;
    AudioStreamPacketDescription desc;
} SAud;

#define S_NO_MORE ((OSStatus)0x6e6f6d72)   /* 'nomr': this packet is used up */

static OSStatus s_aud_input(AudioConverterRef c, UInt32 *np, AudioBufferList *bl, AudioStreamPacketDescription **pd, void *ref) {
    (void)c;
    SAud *a = ref;
    if (a->fed || !a->pkt) { *np = 0; return S_NO_MORE; }
    bl->mNumberBuffers = 1;
    bl->mBuffers[0].mData = (void *)a->pkt;
    bl->mBuffers[0].mDataByteSize = a->pkt_len;
    bl->mBuffers[0].mNumberChannels = a->in.mChannelsPerFrame;
    if (pd) {
        a->desc.mStartOffset = 0;
        a->desc.mVariableFramesInPacket = 0;
        a->desc.mDataByteSize = a->pkt_len;
        *pd = &a->desc;
    }
    *np = 1;
    a->fed = 1;
    return noErr;
}

/* ES_Descriptor { DecoderConfigDescriptor { DecSpecificInfo = asc } } — the
 * magic cookie AudioToolbox wants for MPEG-4 audio. */
static size_t s_desc_len(uint8_t *p, size_t len) {
    p[0] = (uint8_t)(0x80 | ((len >> 21) & 0x7f));
    p[1] = (uint8_t)(0x80 | ((len >> 14) & 0x7f));
    p[2] = (uint8_t)(0x80 | ((len >> 7) & 0x7f));
    p[3] = (uint8_t)(len & 0x7f);
    return 4;
}

static uint8_t *s_esds(const uint8_t *asc, size_t n, size_t *out) {
    size_t dsi = 1 + 4 + n, dcd = 1 + 4 + 13 + dsi, sl = 1 + 4 + 1, es = 1 + 4 + 3 + dcd + sl;
    uint8_t *b = calloc(1, es), *p = b;
    *p++ = 0x03; p += s_desc_len(p, es - 5);
    *p++ = 0; *p++ = 0; *p++ = 0;                    /* ES_ID, flags */
    *p++ = 0x04; p += s_desc_len(p, dcd - 5);
    *p++ = 0x40;                                      /* objectTypeIndication: MPEG-4 audio */
    *p++ = 0x15;                                      /* streamType audio << 2 | 1 */
    p += 3 + 4 + 4;                                   /* bufferSizeDB, max/avg bitrate */
    *p++ = 0x05; p += s_desc_len(p, n);
    memcpy(p, asc, n); p += n;
    *p++ = 0x06; p += s_desc_len(p, 1);
    *p++ = 0x02;
    *out = (size_t)(p - b);
    return b;
}

static uint32_t s_fourcc(const char *s) {
    char f[4] = {' ', ' ', ' ', ' '};
    for (int i = 0; i < 4 && s[i]; i++) f[i] = s[i];
    return ((uint32_t)(uint8_t)f[0] << 24) | ((uint32_t)(uint8_t)f[1] << 16) | ((uint32_t)(uint8_t)f[2] << 8) | (uint8_t)f[3];
}

WValue w_media_atdec_new(WValue fmtv, WValue cookiev, WValue optv) {
    char fs[16];
    w_media_str(fmtv, fs, sizeof fs);
    uint32_t fid = s_fourcc(fs);
    size_t cn = 0;
    const uint8_t *cookie = s_bytes(cookiev, &cn, "atdec_new cookie");
    int mpeg4 = fid == kAudioFormatMPEG4AAC || fid == kAudioFormatMPEG4AAC_HE || fid == kAudioFormatMPEG4AAC_HE_V2 ||
                fid == kAudioFormatMPEGD_USAC || fid == kAudioFormatMPEG4AAC_LD || fid == kAudioFormatMPEG4AAC_ELD;
    uint8_t *esds = NULL;
    size_t en = 0;
    if (mpeg4 && cookie && cn > 0) esds = s_esds(cookie, cn, &en);

    AudioStreamBasicDescription in;
    memset(&in, 0, sizeof in);
    in.mFormatID = fid;
    in.mSampleRate = w_media_num(s_arr(optv, 0), 0, "rate");
    in.mChannelsPerFrame = (UInt32)w_media_num(s_arr(optv, 1), 0, "channels");
    in.mFramesPerPacket = (UInt32)w_media_num(s_arr(optv, 2), 0, "frames_per_packet");
    const void *info = esds ? (const void *)esds : (const void *)cookie;
    UInt32 info_n = esds ? (UInt32)en : (UInt32)cn;
    if (info && info_n) {
        AudioStreamBasicDescription f = in;
        UInt32 sz = sizeof f;
        if (AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, info_n, info, &sz, &f) == noErr) in = f;
        if (mpeg4) {
            /* the highest layer the decoder can produce (HE-AAC v2 → stereo at the SBR rate) */
            AudioFormatInfo fi;
            memset(&fi, 0, sizeof fi);
            fi.mASBD = in;
            fi.mMagicCookie = info;
            fi.mMagicCookieSize = info_n;
            UInt32 lsz = 0;
            if (AudioFormatGetPropertyInfo(kAudioFormatProperty_FormatList, sizeof fi, &fi, &lsz) == noErr && lsz >= sizeof(AudioFormatListItem)) {
                AudioFormatListItem *items = malloc(lsz);
                if (AudioFormatGetProperty(kAudioFormatProperty_FormatList, sizeof fi, &fi, &lsz, items) == noErr && lsz >= sizeof(AudioFormatListItem))
                    in = items[0].mASBD;
                free(items);
            }
        }
    }
    if (in.mSampleRate <= 0 || in.mChannelsPerFrame == 0) { free(esds); w_media_raise("atdec_new: cannot determine the stream format of '%s'", fs); }

    SAud *a = calloc(1, sizeof *a);
    a->in = in;
    a->out.mFormatID = kAudioFormatLinearPCM;
    a->out.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    a->out.mSampleRate = in.mSampleRate;
    a->out.mChannelsPerFrame = in.mChannelsPerFrame;
    a->out.mBitsPerChannel = 32;
    a->out.mBytesPerFrame = 4 * in.mChannelsPerFrame;
    a->out.mFramesPerPacket = 1;
    a->out.mBytesPerPacket = a->out.mBytesPerFrame;
    OSStatus st = AudioConverterNew(&a->in, &a->out, &a->conv);
    if (st != noErr) { free(esds); free(a); w_media_raise("atdec_new: AudioConverterNew('%s') failed (OSStatus %d)", fs, (int)st); }
    if (esds) AudioConverterSetProperty(a->conv, kAudioConverterDecompressionMagicCookie, (UInt32)en, esds);
    free(esds);
    /* WAVE channel order (L R C LFE Ls Rs …), the order core/codec's decoders use */
    AudioChannelLayout lay;
    memset(&lay, 0, sizeof lay);
    UInt32 ch = in.mChannelsPerFrame;
    lay.mChannelLayoutTag = ch == 6 ? kAudioChannelLayoutTag_WAVE_5_1_A : ch == 8 ? kAudioChannelLayoutTag_WAVE_7_1 : 0;
    if (lay.mChannelLayoutTag) AudioConverterSetProperty(a->conv, kAudioConverterOutputChannelLayout, sizeof lay, &lay);
    return w_int(w_media_handle_new(a, W_MEDIA_KIND_SYSAUDIO));
}

WValue w_media_atdec_decode(WValue hv, WValue pktv, WValue outv) {
    SAud *a = w_media_handle_get(hv, W_MEDIA_KIND_SYSAUDIO, "atdec_decode");
    size_t n = 0;
    const uint8_t *pkt = s_bytes(pktv, &n, "atdec_decode packet");
    int64_t cap = 0;
    float *out = s_typed(outv, -32, &cap, "atdec_decode out");
    UInt32 ch = a->out.mChannelsPerFrame;
    a->pkt = pkt;
    a->pkt_len = (UInt32)n;
    a->fed = 0;
    int64_t total = 0, room = cap / ch;
    while (room > 0) {
        AudioBufferList bl;
        bl.mNumberBuffers = 1;
        bl.mBuffers[0].mNumberChannels = ch;
        bl.mBuffers[0].mData = out + total * ch;
        bl.mBuffers[0].mDataByteSize = (UInt32)(room * ch * 4);
        UInt32 frames = (UInt32)room;
        OSStatus st = AudioConverterFillComplexBuffer(a->conv, s_aud_input, a, &frames, &bl, NULL);
        total += frames;
        room -= frames;
        if (st == S_NO_MORE || frames == 0) break;
        if (st != noErr) { a->pkt = NULL; w_media_raise("atdec_decode: AudioConverterFillComplexBuffer failed (OSStatus %d)", (int)st); }
        if (a->fed) {
            /* the packet went in; keep draining only while output filled the buffer */
            if (frames < (UInt32)(room + frames)) break;
        }
    }
    a->pkt = NULL;
    return w_int(total);
}

WValue w_media_atdec_info(WValue hv, WValue keyv) {
    SAud *a = w_media_handle_get(hv, W_MEDIA_KIND_SYSAUDIO, "atdec_info");
    char k[32];
    w_media_str(keyv, k, sizeof k);
    if (!strcmp(k, "rate")) return w_int((int64_t)a->out.mSampleRate);
    if (!strcmp(k, "channels")) return w_int(a->out.mChannelsPerFrame);
    if (!strcmp(k, "frames_per_packet")) return w_int(a->in.mFramesPerPacket);
    if (!strcmp(k, "format")) {
        uint32_t f = a->in.mFormatID;
        char s[5] = {(char)(f >> 24), (char)(f >> 16), (char)(f >> 8), (char)f, 0};
        return w_string(s);
    }
    w_media_raise("atdec_info: unknown key '%s'", k);
}

WValue w_media_atdec_reset(WValue hv) {
    SAud *a = w_media_handle_get(hv, W_MEDIA_KIND_SYSAUDIO, "atdec_reset");
    AudioConverterReset(a->conv);
    return W_TRUE;
}

WValue w_media_atdec_close(WValue hv) {
    SAud *a = w_media_handle_peek(hv, W_MEDIA_KIND_SYSAUDIO);
    if (!a) return W_FALSE;
    w_media_handle_drop(hv, W_MEDIA_KIND_SYSAUDIO);
    AudioConverterDispose(a->conv);
    free(a);
    return W_TRUE;
}

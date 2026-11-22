/* runtime/quartz.c — CoreGraphics / CoreText / ImageIO drawing bridge.
 *
 * The native half of core/canvas.w: an RGBA bitmap canvas (CGBitmapContext)
 * with vector paths, solid and gradient paint, strokes, clipping, affine
 * transforms, blend modes, ImageIO image decode with a decode-once cache,
 * CoreText text, and PNG/JPEG/TIFF/HEIC output with the colour space
 * embedded. It replaces the SVG -> rsvg-convert step for video frames.
 *
 * ABI. Every entry point is a ccall target: WValue arguments in, a WValue
 * out (see the list in quartz.h). Numbers arrive boxed — Float, Int, Decimal,
 * Rational or BigInt — and are coerced with cg_num. Colours may be CSS
 * strings ("#rgb", "#rrggbbaa", "rgba(…)", named colours), packed Color
 * values (#FF8A5B literals, Color.rgb), 0xRRGGBB integers, or [r, g, b(, a)]
 * arrays of 0..1 components.
 *
 * Handles. Canvases and images are small integers (slot | generation << 16)
 * into fixed registries, not boxed heap objects: no new WValue type tag, and a
 * closed or stale handle raises instead of touching freed memory. Lookups are
 * lock-free atomic loads; creation and release take a mutex, so separate
 * canvases may be drawn on separate threads.
 *
 * Lifetime. The runtime has no finalizers, so native memory is released by
 * Canvas#close (the pixel buffer is an anonymous mmap, returned to the OS on
 * close) and by the image cache's byte budget / explicit release. Video loops
 * keep one canvas and call clear per frame.
 *
 * Coordinates. User units, y down, origin top-left (like SVG). The base CTM
 * maps them to device pixels at `scale`. The current path is our own
 * CGMutablePath, interpreted under the transform in effect when it is
 * painted, so one path can be filled, stroked and clipped in turn.
 *
 * Colour. Each canvas has a colour space ("srgb", "rec709", "display_p3",
 * "linear_srgb", …). With manage off (the default) every input — colours and
 * image pixels — is taken as code values in that space: exactly what the
 * SVG -> rsvg -> ffmpeg pipeline did, now honestly tagged. With manage on,
 * colours are sRGB (CSS semantics), images keep their embedded profiles, and
 * CoreGraphics colour-matches into the canvas space.
 *
 * Non-Apple targets compile the second half of this file instead: raising
 * stubs generated from W_CG_CCALLS, so a Canvas program links everywhere and
 * fails with a clear message. */

#include "runtime.h"
#include "wvalue.h"
#include "quartz.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__) && !defined(TUNGSTEN_QUARTZ_STUB)

/* Every exported entry point must be declared in W_CG_CCALLS (quartz.h):
 * the stub half is generated from that list, so a function missing from it
 * would link on macOS and be an undefined symbol on Linux. */
#pragma clang diagnostic error "-Wmissing-prototypes"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <dispatch/dispatch.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif
#include <ctype.h>
#include <math.h>
#include <pthread.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

extern double w_num_to_f64(WValue v);

/* ======================================================================
   Small helpers: errors, numbers, strings, flags
   ====================================================================== */

__attribute__((noreturn, format(printf, 1, 2)))
static void cg_raise(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    w_raise(w_string(buf));
    abort(); /* w_raise does not return */
}

static int cg_is_numeric(WValue v) {
    return w_is_double(v) || w_is_int(v) || w_is_bigint(v) ||
           (v & W_TAG_MASK) == W_TAG_DECIMAL || w_is_rational(v) ||
           w_is_domain_obj(v);
}

static double cg_num(WValue v, const char *what) {
    if (w_is_double(v)) return w_as_double(v);
    if (w_is_int(v)) return (double)w_as_int(v);
    if (cg_is_numeric(v)) return w_num_to_f64(v);
    cg_raise("Canvas: %s must be a number", what);
}

/* nil means "use the default" for optional numeric arguments. */
static double cg_num_or(WValue v, double dflt, const char *what) {
    if (v == W_NIL) return dflt;
    return cg_num(v, what);
}

static int cg_truthy(WValue v) { return v > 1; }

static int cg_is_text(WValue v) { return w_is_stringy(v) || w_is_rope(v); }

/* Borrow the bytes of a String/Symbol. `sso` backs inline strings. */
static int cg_str_view(WValue v, char sso[6], const char **s, size_t *n) {
    if (!cg_is_text(v)) return 0;
    w_str_data(v, sso, s, n);
    return 1;
}

/* Copy a short String/Symbol into buf (NUL-terminated, truncated). Returns 0
 * for nil or a non-string. */
static int cg_str(WValue v, char *buf, size_t cap) {
    char sso[6];
    const char *s;
    size_t n;
    if (!cg_str_view(v, sso, &s, &n)) { buf[0] = 0; return 0; }
    if (n >= cap) n = cap - 1;
    memcpy(buf, s, n);
    buf[n] = 0;
    return 1;
}

static CFStringRef cg_cfstring(const char *s, size_t n) {
    CFStringRef r = CFStringCreateWithBytes(NULL, (const UInt8 *)s, (CFIndex)n, kCFStringEncodingUTF8, false);
    return r ? r : CFStringCreateWithCString(NULL, "", kCFStringEncodingUTF8);
}

static WValue cg_wstring_from_cf(CFStringRef s) {
    if (!s) return W_NIL;
    char buf[512];
    if (!CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8)) return W_NIL;
    return w_string(buf);
}

static int cg_eq(const char *a, const char *b) { return strcasecmp(a, b) == 0; }

static WValue cg_float_array(const double *vals, int n) {
    WValue arr = w_array_new_empty();
    for (int i = 0; i < n; i++) arr = w_array_push(arr, w_float(vals[i]));
    return arr;
}

static int64_t cg_array_len(WValue v) {
    if (!w_is_array(v)) return -1;
    return (int64_t)w_as_array(v)->size;
}

static WValue cg_array_at(WValue v, int64_t i) {
    return w_array_get(v, w_int(i));
}

/* ======================================================================
   Colour spaces
   ====================================================================== */

typedef struct {
    const char *name;     /* the Tungsten selector */
    const char *alias;    /* an accepted spelling, or NULL */
    CFStringRef *cg;      /* address of the kCGColorSpace* constant */
} CGSpaceName;

static const CGSpaceName g_spaces[] = {
    {"srgb",                 "sRGB",          (CFStringRef *)&kCGColorSpaceSRGB},
    {"rec709",               "itur_709",      (CFStringRef *)&kCGColorSpaceITUR_709},
    {"display_p3",           "p3",            (CFStringRef *)&kCGColorSpaceDisplayP3},
    {"linear_srgb",          NULL,            (CFStringRef *)&kCGColorSpaceLinearSRGB},
    {"extended_srgb",        NULL,            (CFStringRef *)&kCGColorSpaceExtendedSRGB},
    {"extended_linear_srgb", NULL,            (CFStringRef *)&kCGColorSpaceExtendedLinearSRGB},
    {"linear_display_p3",    NULL,            (CFStringRef *)&kCGColorSpaceLinearDisplayP3},
    {"extended_display_p3",  NULL,            (CFStringRef *)&kCGColorSpaceExtendedDisplayP3},
    {"rec2020",              "itur_2020",     (CFStringRef *)&kCGColorSpaceITUR_2020},
    {"linear_rec2020",       NULL,            (CFStringRef *)&kCGColorSpaceLinearITUR_2020},
    {"dci_p3",               NULL,            (CFStringRef *)&kCGColorSpaceDCIP3},
    {"adobe_rgb",            NULL,            (CFStringRef *)&kCGColorSpaceAdobeRGB1998},
    {"acescg",               "aces_cg",       (CFStringRef *)&kCGColorSpaceACESCGLinear},
};
#define CG_NSPACES ((int)(sizeof g_spaces / sizeof g_spaces[0]))

static int cg_space_index(const char *name) {
    for (int i = 0; i < CG_NSPACES; i++) {
        if (cg_eq(name, g_spaces[i].name)) return i;
        if (g_spaces[i].alias && cg_eq(name, g_spaces[i].alias)) return i;
    }
    return -1;
}

/* The Tungsten selector for a CG colour space, or NULL. */
static const char *cg_space_selector(CGColorSpaceRef cs) {
    if (!cs) return NULL;
    CFStringRef nm = CGColorSpaceCopyName(cs);
    if (!nm) return NULL;
    const char *out = NULL;
    for (int i = 0; i < CG_NSPACES; i++) {
        if (CFEqual(nm, *g_spaces[i].cg)) { out = g_spaces[i].name; break; }
    }
    CFRelease(nm);
    return out;
}

static CGColorSpaceRef g_srgb;
static pthread_once_t g_srgb_once = PTHREAD_ONCE_INIT;

static void cg_srgb_init(void) { g_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); }

static CGColorSpaceRef cg_srgb(void) {
    pthread_once(&g_srgb_once, cg_srgb_init);
    return g_srgb;
}

/* ======================================================================
   Canvas registry
   ====================================================================== */

#define CG_MAX_CANVASES 4096
#define CG_MAX_DEPTH    256
#define CG_GRAD_CACHE   32
#define CG_LINE_SETS    256
#define CG_LINE_WAYS    4
#define CG_LINE_CACHE   (CG_LINE_SETS * CG_LINE_WAYS)

typedef struct {
    double alpha;       /* global alpha (CGContextSetAlpha has no getter) */
    double line_width;  /* for layer bounds of stroked shapes */
    double miter;
    int    has_fill_cache;
    int    has_stroke_cache;
    int    is_solid_butt;
    double fill[4];
    double stroke[4];
} CGStateEntry;

typedef struct {
    CTFontRef font;
    uint32_t  stamp;
    uint8_t   ascii_ok;
    uint8_t   smufl_ok;
    CGGlyph   ascii[256];
    CGGlyph  *smufl;    /* lazy 0x1800 slots for U+E000..U+F7FF */
} CGGlyphMap;

typedef struct {
    uint64_t        hash;
    int             n;
    double         *key;      /* n * 5 doubles: offset, r, g, b, a */
    CGGradientRef   gradient;
} CGGradEntry;

typedef struct {
    uint64_t        hash;
    uint32_t        stamp;
    uint8_t         has_ink;
    CTFontRef       font;     /* retained: pins the pointer used as key */
    double          spacing;
    char           *text;
    size_t          len;
    CTLineRef       line;
    double          width, ascent, descent, leading;
    CGRect          ink;      /* glyph-path bounds, y up, relative to origin (lazy) */
} CGLineEntry;

typedef struct CGCanvas {
    uint32_t          gen;
    uint32_t          line_clock;
    CGContextRef      ctx;
    CGColorSpaceRef   space;        /* canvas space (retained) */
    CGColorSpaceRef   color_space;  /* space input colours are in (retained) */
    int               space_index;
    int               manage;
    void             *data;
    size_t            data_bytes;
    size_t            stride;
    size_t            pw, ph;
    int               bpc;          /* 8, 16, 32 */
    int               is_float;
    double            scale, uw, uh;
    CGAffineTransform base;         /* user -> device at reset */
    CGMutablePathRef  path;
    int               depth;        /* user save depth above the base level */
    CGStateEntry      st[CG_MAX_DEPTH + 1];
    CTFontRef         font;         /* current text font (retained) */
    double            font_size;
    double            spacing;
    CGGradEntry       grads[CG_GRAD_CACHE];
    CGLineEntry       lines[CG_LINE_CACHE];
    CGGlyphMap        gmaps[4];
} CGCanvas;

static CGCanvas *g_canvases[CG_MAX_CANVASES];
static uint32_t  g_canvas_gen[CG_MAX_CANVASES];
static int       g_canvas_live;
static size_t    g_canvas_bytes;
static pthread_mutex_t g_reg_lock = PTHREAD_MUTEX_INITIALIZER;

static CGCanvas *cg_canvas(WValue hv, const char *fn) {
    if (!w_is_int(hv)) cg_raise("Canvas.%s: not a canvas handle", fn);
    int64_t h = w_as_int(hv);
    int64_t slot = (h & 0xFFFF) - 1;
    uint32_t gen = (uint32_t)(h >> 16);
    if (slot < 0 || slot >= CG_MAX_CANVASES) cg_raise("Canvas.%s: not a canvas handle", fn);
    CGCanvas *c = __atomic_load_n(&g_canvases[slot], __ATOMIC_ACQUIRE);
    if (!c || c->gen != gen) cg_raise("Canvas.%s: the canvas is closed", fn);
    return c;
}

static CGStateEntry *cg_state(CGCanvas *c) { return &c->st[c->depth]; }

/* ======================================================================
   Canvas lifecycle
   ====================================================================== */

static void cg_grad_cache_clear(CGCanvas *c) {
    for (int i = 0; i < CG_GRAD_CACHE; i++) {
        if (c->grads[i].gradient) CGGradientRelease(c->grads[i].gradient);
        free(c->grads[i].key);
        memset(&c->grads[i], 0, sizeof c->grads[i]);
    }
}

static void cg_line_entry_clear(CGLineEntry *e) {
    if (e->line) CFRelease(e->line);
    if (e->font) CFRelease(e->font);
    free(e->text);
    memset(e, 0, sizeof *e);
}

static void cg_canvas_free(CGCanvas *c) {
    for (int i = 0; i < 4; i++) {
        if (c->gmaps[i].font) CFRelease(c->gmaps[i].font);
        free(c->gmaps[i].smufl);
    }
    for (int i = 0; i < CG_LINE_CACHE; i++) cg_line_entry_clear(&c->lines[i]);
    cg_grad_cache_clear(c);
    if (c->font) CFRelease(c->font);
    if (c->path) CGPathRelease(c->path);
    if (c->ctx) CGContextRelease(c->ctx);
    if (c->space) CGColorSpaceRelease(c->space);
    if (c->color_space) CGColorSpaceRelease(c->color_space);
    if (c->data) munmap(c->data, c->data_bytes);
    free(c);
}

static CTFontRef cg_font_lookup(const char *families, size_t flen, double weight, int italic, double size);

static void cg_apply_defaults(CGCanvas *c) {
    CGContextRef ctx = c->ctx;
    CGContextSetShouldAntialias(ctx, true);
    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextSetShouldSmoothFonts(ctx, false);
    CGContextSetAllowsFontSmoothing(ctx, false);
    CGContextSetShouldSubpixelPositionFonts(ctx, true);
    CGContextSetAllowsFontSubpixelPositioning(ctx, true);
    CGContextSetShouldSubpixelQuantizeFonts(ctx, false);
    CGContextSetAllowsFontSubpixelQuantization(ctx, false);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextSetMiterLimit(ctx, 4.0);   /* SVG's default */
    CGContextSetFillColorSpace(ctx, c->color_space);
    CGContextSetStrokeColorSpace(ctx, c->color_space);
    const CGFloat black[4] = {0, 0, 0, 1};
    CGContextSetFillColor(ctx, black);
    CGContextSetStrokeColor(ctx, black);
    c->st[0].has_fill_cache = 1;
    c->st[0].has_stroke_cache = 1;
    c->st[0].is_solid_butt = 1;
    c->st[0].fill[0] = 0; c->st[0].fill[1] = 0; c->st[0].fill[2] = 0; c->st[0].fill[3] = 1;
    c->st[0].stroke[0] = 0; c->st[0].stroke[1] = 0; c->st[0].stroke[2] = 0; c->st[0].stroke[3] = 1;
}

/* w_cg_canvas_new(width, height, scale, space, depth, manage) -> handle */

/* Shape with one exact font file and return positioned vector outlines. Unlike
 * family-name selection this never silently accepts a fallback font. */
typedef struct { char *data; size_t size, cap; int failed; } CGOutline;
static void cg_outline_append(CGOutline *b, const char *fmt, ...) {
    if (b->failed) return;
    char text[256]; va_list args; va_start(args,fmt); int n=vsnprintf(text,sizeof text,fmt,args); va_end(args);
    if(n<0 || (size_t)n>=sizeof text || b->size+(size_t)n>16*1024*1024) { b->failed=1; return; }
    if(b->size+(size_t)n+1>b->cap) { size_t cap=(b->size+n+1)*2; char *p=realloc(b->data,cap); if(!p){b->failed=1;return;} b->data=p;b->cap=cap; }
    memcpy(b->data+b->size,text,n+1);b->size+=n;
}
static void cg_outline_element(void *context,const CGPathElement *e) {
    CGOutline *b=context; CGPoint *p=e->points;
    switch(e->type) {
      case kCGPathElementMoveToPoint: cg_outline_append(b,"M%.9g %.9g ",p[0].x,p[0].y);break;
      case kCGPathElementAddLineToPoint: cg_outline_append(b,"L%.9g %.9g ",p[0].x,p[0].y);break;
      case kCGPathElementAddQuadCurveToPoint: cg_outline_append(b,"Q%.9g %.9g %.9g %.9g ",p[0].x,p[0].y,p[1].x,p[1].y);break;
      case kCGPathElementAddCurveToPoint: cg_outline_append(b,"C%.9g %.9g %.9g %.9g %.9g %.9g ",p[0].x,p[0].y,p[1].x,p[1].y,p[2].x,p[2].y);break;
      case kCGPathElementCloseSubpath: cg_outline_append(b,"Z ");break;
    }
}
WValue w_cg_font_shape(WValue file_v,WValue text_v,WValue size_v) {
    char file[4096]; if(!cg_str(file_v,file,sizeof file))cg_raise("font path must be a string");
    char small[6];const char *text;size_t n;if(!cg_str_view(text_v,small,&text,&n)||n>1024*1024)cg_raise("invalid caption string");
    double size=cg_num(size_v,"font size");if(!isfinite(size)||size<=0||size>4096)cg_raise("invalid font size");
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)file,strlen(file),false);
    CFArrayRef descriptors=url?CTFontManagerCreateFontDescriptorsFromURL(url):NULL;
    if(url)CFRelease(url);
    if(!descriptors||CFArrayGetCount(descriptors)==0){if(descriptors)CFRelease(descriptors);cg_raise("cannot load exact font file: %s",file);}
    CTFontRef font=CTFontCreateWithFontDescriptor((CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors,0),size,NULL);CFRelease(descriptors);
    CFStringRef string=cg_cfstring(text,n);const void *keys[]={kCTFontAttributeName};const void *values[]={font};
    CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attributed=CFAttributedStringCreate(NULL,string,attrs);CTLineRef line=CTLineCreateWithAttributedString(attributed);
    CFStringRef requested=CTFontCopyPostScriptName(font);CFArrayRef runs=CTLineGetGlyphRuns(line);
    WValue paths=w_array_new_empty();CGRect bounds=CGRectNull;int missing=0;
    for(CFIndex r=0;r<CFArrayGetCount(runs);r++) {
      CTRunRef run=(CTRunRef)CFArrayGetValueAtIndex(runs,r);CFIndex count=CTRunGetGlyphCount(run);
      CTFontRef actual=(CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run),kCTFontAttributeName);CFStringRef name=CTFontCopyPostScriptName(actual);
      if(!CFEqual(name,requested))missing=1;CFRelease(name);
      CGGlyph *glyphs=calloc(count?count:1,sizeof *glyphs);CGPoint *positions=calloc(count?count:1,sizeof *positions);
      if(!glyphs||!positions){free(glyphs);free(positions);missing=1;break;}CTRunGetGlyphs(run,CFRangeMake(0,0),glyphs);CTRunGetPositions(run,CFRangeMake(0,0),positions);
      for(CFIndex g=0;g<count;g++) {
        if(glyphs[g]==0){missing=1;continue;}
        CGAffineTransform transform=CGAffineTransformMake(1,0,0,-1,positions[g].x,-positions[g].y);
        CGPathRef path=CTFontCreatePathForGlyph(actual,glyphs[g],&transform);if(!path)continue;
        bounds=CGRectUnion(bounds,CGPathGetPathBoundingBox(path));CGOutline b={0};CGPathApply(path,&b,cg_outline_element);CGPathRelease(path);
        if(b.failed){free(b.data);missing=1;continue;}if(b.data)paths=w_array_push(paths,w_string(b.data));free(b.data);
      }
      free(glyphs);free(positions);
    }
    double advance=CTLineGetTypographicBounds(line,NULL,NULL,NULL);CFRelease(requested);CFRelease(line);CFRelease(attributed);CFRelease(attrs);CFRelease(string);CFRelease(font);
    if(missing)cg_raise("caption contains missing glyphs or requires a fallback font: %s",file);
    if(CGRectIsNull(bounds))bounds=CGRectZero;
    WValue result=w_array_new_empty();result=w_array_push(result,w_float(advance));double b[]={bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height};result=w_array_push(result,cg_float_array(b,4));result=w_array_push(result,paths);return result;
}

WValue w_cg_canvas_new(WValue wv, WValue hv, WValue scalev, WValue spacev, WValue depthv, WValue managev) {
    double uw = cg_num(wv, "width");
    double uh = cg_num(hv, "height");
    double scale = cg_num_or(scalev, 1.0, "scale");
    if (!(uw > 0) || !(uh > 0)) cg_raise("Canvas.new: width and height must be positive (got %g x %g)", uw, uh);
    if (!(scale > 0) || scale > 64) cg_raise("Canvas.new: scale must be in (0, 64] (got %g)", scale);
    double pwd = round(uw * scale), phd = round(uh * scale);
    if (pwd < 1) pwd = 1;
    if (phd < 1) phd = 1;
    if (pwd > 32768 || phd > 32768) cg_raise("Canvas.new: %g x %g pixels is larger than 32768 on a side", pwd, phd);

    char sname[48] = "srgb";
    if (spacev != W_NIL && !cg_str(spacev, sname, sizeof sname))
        cg_raise("Canvas.new: space must be a String or Symbol");
    int si = cg_space_index(sname);
    if (si < 0) {
        char known[512] = "";
        for (int i = 0; i < CG_NSPACES; i++) {
            strlcat(known, i ? ", " : "", sizeof known);
            strlcat(known, g_spaces[i].name, sizeof known);
        }
        cg_raise("Canvas.new: unknown colour space \"%s\" (known: %s)", sname, known);
    }

    int bpc = 8, is_float = 0;
    if (depthv != W_NIL) {
        char dn[16];
        if (cg_str(depthv, dn, sizeof dn)) {
            if (cg_eq(dn, "half") || cg_eq(dn, "f16")) { bpc = 16; is_float = 1; }
            else if (cg_eq(dn, "float") || cg_eq(dn, "f32")) { bpc = 32; is_float = 1; }
            else if (cg_eq(dn, "8")) bpc = 8;
            else if (cg_eq(dn, "16")) bpc = 16;
            else cg_raise("Canvas.new: depth must be 8, 16, \"half\" or \"float\" (got \"%s\")", dn);
        } else {
            double d = cg_num(depthv, "depth");
            if (d == 8) bpc = 8;
            else if (d == 16) bpc = 16;
            else if (d == 32) { bpc = 32; is_float = 1; }
            else cg_raise("Canvas.new: depth must be 8, 16, \"half\" or \"float\" (got %g)", d);
        }
    }

    size_t pw = (size_t)pwd, ph = (size_t)phd;
    size_t bpp = 4 * (size_t)bpc / 8;
    size_t stride = (pw * bpp + 63) & ~(size_t)63;
    size_t bytes = stride * ph;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    size_t map_bytes = (bytes + page - 1) & ~(page - 1);

    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    if (bpc == 8) info |= kCGBitmapByteOrder32Big;
    else if (bpc == 16) info |= kCGBitmapByteOrder16Little | (is_float ? kCGBitmapFloatComponents : 0);
    else info |= kCGBitmapByteOrder32Little | kCGBitmapFloatComponents;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(*g_spaces[si].cg);
    if (!space) cg_raise("Canvas.new: colour space \"%s\" is not available on this system", g_spaces[si].name);
    void *data = mmap(NULL, map_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (data == MAP_FAILED) {
        CGColorSpaceRelease(space);
        cg_raise("Canvas.new: cannot allocate %zu bytes for %zu x %zu pixels", map_bytes, pw, ph);
    }
    CGContextRef ctx = CGBitmapContextCreate(data, pw, ph, (size_t)bpc, stride, space, info);
    if (!ctx) {
        munmap(data, map_bytes);
        CGColorSpaceRelease(space);
        cg_raise("Canvas.new: CoreGraphics has no %d-bit%s RGBA bitmap format for colour space \"%s\"",
                 bpc, is_float ? " float" : "", g_spaces[si].name);
    }

    CGCanvas *c = calloc(1, sizeof *c);
    if (!c) {
        CGContextRelease(ctx);
        munmap(data, map_bytes);
        CGColorSpaceRelease(space);
        cg_raise("Canvas.new: out of memory");
    }
    c->ctx = ctx;
    c->space = space;
    c->space_index = si;
    c->manage = cg_truthy(managev);
    c->color_space = c->manage ? CGColorSpaceRetain(cg_srgb()) : CGColorSpaceRetain(space);
    c->data = data;
    c->data_bytes = map_bytes;
    c->stride = stride;
    c->pw = pw;
    c->ph = ph;
    c->bpc = bpc;
    c->is_float = is_float;
    c->scale = scale;
    c->uw = uw;
    c->uh = uh;
    c->path = CGPathCreateMutable();
    c->st[0].alpha = 1.0;
    c->st[0].line_width = 1.0;
    c->st[0].miter = 4.0;
    c->spacing = 0.0;
    c->font_size = 16.0;
    c->font = cg_font_lookup("Helvetica", 9, 400, 0, 16.0);

    /* User space: y down, origin top-left, `scale` device pixels per unit. */
    CGContextTranslateCTM(ctx, 0, (CGFloat)ph);
    CGContextScaleCTM(ctx, (CGFloat)scale, (CGFloat)-scale);
    c->base = CGContextGetCTM(ctx);
    cg_apply_defaults(c);
    CGContextSaveGState(ctx);   /* the base level `reset` returns to */

    pthread_mutex_lock(&g_reg_lock);
    int slot = -1;
    for (int i = 0; i < CG_MAX_CANVASES; i++) {
        if (!g_canvases[i]) { slot = i; break; }
    }
    if (slot < 0) {
        pthread_mutex_unlock(&g_reg_lock);
        cg_canvas_free(c);
        cg_raise("Canvas.new: %d canvases are open; close some (Canvas#close)", CG_MAX_CANVASES);
    }
    uint32_t gen = ++g_canvas_gen[slot];
    if (gen > 0x7FFFFFFF) gen = g_canvas_gen[slot] = 1;
    c->gen = gen;
    __atomic_store_n(&g_canvases[slot], c, __ATOMIC_RELEASE);
    g_canvas_live++;
    g_canvas_bytes += map_bytes;
    pthread_mutex_unlock(&g_reg_lock);
    return w_int(((int64_t)gen << 16) | (int64_t)(slot + 1));
}

/* Closing twice, or closing a stale handle, is a no-op. */
WValue w_cg_canvas_close(WValue hv) {
    if (!w_is_int(hv)) return W_NIL;
    int64_t h = w_as_int(hv);
    int64_t slot = (h & 0xFFFF) - 1;
    uint32_t gen = (uint32_t)(h >> 16);
    if (slot < 0 || slot >= CG_MAX_CANVASES) return W_NIL;
    pthread_mutex_lock(&g_reg_lock);
    CGCanvas *c = g_canvases[slot];
    if (!c || c->gen != gen) {
        pthread_mutex_unlock(&g_reg_lock);
        return W_NIL;
    }
    __atomic_store_n(&g_canvases[slot], NULL, __ATOMIC_RELEASE);
    g_canvas_live--;
    g_canvas_bytes -= c->data_bytes;
    pthread_mutex_unlock(&g_reg_lock);
    cg_canvas_free(c);
    return W_TRUE;
}

static const char *cg_depth_name(CGCanvas *c) {
    if (!c->is_float) return c->bpc == 8 ? "8" : "16";
    return c->bpc == 16 ? "half" : "float";
}

/* w_cg_canvas_info(h, key): pixel_width, pixel_height, stride, bits, depth,
 * space, float, manage. */
WValue w_cg_canvas_info(WValue hv, WValue keyv) {
    CGCanvas *c = cg_canvas(hv, "info");
    char key[32];
    cg_str(keyv, key, sizeof key);
    if (cg_eq(key, "pixel_width")) return w_int((int64_t)c->pw);
    if (cg_eq(key, "pixel_height")) return w_int((int64_t)c->ph);
    if (cg_eq(key, "stride")) return w_int((int64_t)c->stride);
    if (cg_eq(key, "bits")) return w_int(c->bpc);
    if (cg_eq(key, "depth")) return w_string(cg_depth_name(c));
    if (cg_eq(key, "space")) return w_string(g_spaces[c->space_index].name);
    if (cg_eq(key, "float")) return w_bool(c->is_float);
    if (cg_eq(key, "manage")) return w_bool(c->manage);
    cg_raise("Canvas.info: unknown key \"%s\"", key);
}

/* ======================================================================
   State: save / restore / reset, transforms, alpha, blend, quality
   ====================================================================== */

WValue w_cg_save(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "save");
    if (c->depth >= CG_MAX_DEPTH) cg_raise("Canvas.save: more than %d nested saves", CG_MAX_DEPTH);
    CGContextSaveGState(c->ctx);
    c->st[c->depth + 1] = c->st[c->depth];
    c->depth++;
    return W_NIL;
}

WValue w_cg_restore(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "restore");
    if (c->depth == 0) cg_raise("Canvas.restore: no matching save");
    CGContextRestoreGState(c->ctx);
    c->depth--;
    return W_NIL;
}

/* Back to the state of a fresh canvas: pops every save, identity user
 * transform, no clip, alpha 1, normal blend, empty path. Pixels are kept. */
WValue w_cg_reset(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "reset");
    while (c->depth > 0) { CGContextRestoreGState(c->ctx); c->depth--; }
    CGContextRestoreGState(c->ctx);
    CGContextSaveGState(c->ctx);
    c->st[0].alpha = 1.0;
    c->st[0].line_width = 1.0;
    c->st[0].miter = 4.0;
    c->st[0].has_fill_cache = 1;
    c->st[0].has_stroke_cache = 1;
    c->st[0].is_solid_butt = 1;
    c->st[0].fill[0] = 0; c->st[0].fill[1] = 0; c->st[0].fill[2] = 0; c->st[0].fill[3] = 1;
    c->st[0].stroke[0] = 0; c->st[0].stroke[1] = 0; c->st[0].stroke[2] = 0; c->st[0].stroke[3] = 1;
    CGPathRelease(c->path);
    c->path = CGPathCreateMutable();
    return W_NIL;
}

WValue w_cg_translate(WValue hv, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "translate");
    CGContextTranslateCTM(c->ctx, cg_num(xv, "x"), cg_num(yv, "y"));
    return W_NIL;
}

WValue w_cg_scale(WValue hv, WValue sxv, WValue syv) {
    CGCanvas *c = cg_canvas(hv, "scale");
    double sx = cg_num(sxv, "sx");
    double sy = cg_num_or(syv, sx, "sy");
    CGContextScaleCTM(c->ctx, sx, sy);
    return W_NIL;
}

/* Radians; positive turns clockwise on screen (y down), as SVG's rotate. */
WValue w_cg_rotate(WValue hv, WValue av) {
    CGCanvas *c = cg_canvas(hv, "rotate");
    CGContextRotateCTM(c->ctx, cg_num(av, "angle"));
    return W_NIL;
}

/* SVG matrix(a b c d e f): x' = a x + c y + e, y' = b x + d y + f. */
WValue w_cg_concat(WValue hv, WValue a, WValue b, WValue cc, WValue d, WValue e, WValue f) {
    CGCanvas *c = cg_canvas(hv, "transform");
    CGAffineTransform t = CGAffineTransformMake(cg_num(a, "a"), cg_num(b, "b"), cg_num(cc, "c"),
                                                cg_num(d, "d"), cg_num(e, "e"), cg_num(f, "f"));
    CGContextConcatCTM(c->ctx, t);
    return W_NIL;
}

/* The user transform (relative to the base), as [a, b, c, d, e, f]. */
WValue w_cg_ctm(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "ctm");
    CGAffineTransform full = CGContextGetCTM(c->ctx);
    CGAffineTransform user = CGAffineTransformConcat(full, CGAffineTransformInvert(c->base));
    double v[6] = {user.a, user.b, user.c, user.d, user.tx, user.ty};
    return cg_float_array(v, 6);
}

WValue w_cg_set_alpha(WValue hv, WValue av) {
    CGCanvas *c = cg_canvas(hv, "alpha=");
    double a = cg_num(av, "alpha");
    if (a < 0) a = 0;
    if (a > 1) a = 1;
    cg_state(c)->alpha = a;
    CGContextSetAlpha(c->ctx, a);
    return W_NIL;
}

typedef struct { const char *name; CGBlendMode mode; } CGBlendName;
static const CGBlendName g_blends[] = {
    {"normal", kCGBlendModeNormal},          {"source_over", kCGBlendModeNormal},
    {"multiply", kCGBlendModeMultiply},      {"screen", kCGBlendModeScreen},
    {"overlay", kCGBlendModeOverlay},        {"darken", kCGBlendModeDarken},
    {"lighten", kCGBlendModeLighten},        {"color_dodge", kCGBlendModeColorDodge},
    {"color_burn", kCGBlendModeColorBurn},   {"soft_light", kCGBlendModeSoftLight},
    {"hard_light", kCGBlendModeHardLight},   {"difference", kCGBlendModeDifference},
    {"exclusion", kCGBlendModeExclusion},    {"hue", kCGBlendModeHue},
    {"saturation", kCGBlendModeSaturation},  {"color", kCGBlendModeColor},
    {"luminosity", kCGBlendModeLuminosity},  {"clear", kCGBlendModeClear},
    {"copy", kCGBlendModeCopy},              {"source_in", kCGBlendModeSourceIn},
    {"source_out", kCGBlendModeSourceOut},   {"source_atop", kCGBlendModeSourceAtop},
    {"destination_over", kCGBlendModeDestinationOver},
    {"destination_in", kCGBlendModeDestinationIn},
    {"destination_out", kCGBlendModeDestinationOut},
    {"destination_atop", kCGBlendModeDestinationAtop},
    {"xor", kCGBlendModeXOR},                {"plus_darker", kCGBlendModePlusDarker},
    {"plus_lighter", kCGBlendModePlusLighter}, {"add", kCGBlendModePlusLighter},
};

WValue w_cg_set_blend(WValue hv, WValue mv) {
    CGCanvas *c = cg_canvas(hv, "blend=");
    char name[32];
    if (mv == W_NIL) strcpy(name, "normal");
    else if (!cg_str(mv, name, sizeof name)) cg_raise("Canvas.blend=: blend mode must be a String or Symbol");
    for (char *p = name; *p; p++) if (*p == '-') *p = '_';
    for (size_t i = 0; i < sizeof g_blends / sizeof g_blends[0]; i++) {
        if (cg_eq(name, g_blends[i].name)) {
            CGContextSetBlendMode(c->ctx, g_blends[i].mode);
            return W_NIL;
        }
    }
    cg_raise("Canvas.blend=: unknown blend mode \"%s\"", name);
}

static CGInterpolationQuality cg_quality(WValue qv, int *ok) {
    char q[16];
    *ok = 1;
    if (qv == W_NIL) return kCGInterpolationHigh;
    if (!cg_str(qv, q, sizeof q)) { *ok = 0; return kCGInterpolationHigh; }
    if (cg_eq(q, "none") || cg_eq(q, "nearest")) return kCGInterpolationNone;
    if (cg_eq(q, "low")) return kCGInterpolationLow;
    if (cg_eq(q, "medium")) return kCGInterpolationMedium;
    if (cg_eq(q, "high")) return kCGInterpolationHigh;
    if (cg_eq(q, "default")) return kCGInterpolationDefault;
    *ok = 0;
    return kCGInterpolationHigh;
}

WValue w_cg_set_quality(WValue hv, WValue qv) {
    CGCanvas *c = cg_canvas(hv, "quality=");
    int ok;
    CGInterpolationQuality q = cg_quality(qv, &ok);
    if (!ok) cg_raise("Canvas.quality=: use none, low, medium, high or default");
    CGContextSetInterpolationQuality(c->ctx, q);
    return W_NIL;
}

WValue w_cg_set_antialias(WValue hv, WValue onv) {
    CGCanvas *c = cg_canvas(hv, "antialias=");
    CGContextSetShouldAntialias(c->ctx, cg_truthy(onv));
    return W_NIL;
}

/* ======================================================================
   Paths
   ====================================================================== */

WValue w_cg_path_begin(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "begin_path");
    CGPathRelease(c->path);
    c->path = CGPathCreateMutable();
    return W_NIL;
}

WValue w_cg_move_to(WValue hv, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "move_to");
    CGPathMoveToPoint(c->path, NULL, cg_num(xv, "x"), cg_num(yv, "y"));
    return W_NIL;
}

/* Like HTML canvas, a segment with no current point starts one. */
static void cg_ensure_point(CGCanvas *c, double x, double y) {
    if (CGPathIsEmpty(c->path)) CGPathMoveToPoint(c->path, NULL, x, y);
}

WValue w_cg_line_to(WValue hv, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "line_to");
    double x = cg_num(xv, "x"), y = cg_num(yv, "y");
    cg_ensure_point(c, x, y);
    CGPathAddLineToPoint(c->path, NULL, x, y);
    return W_NIL;
}

WValue w_cg_quad_to(WValue hv, WValue cxv, WValue cyv, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "quad_to");
    double cx = cg_num(cxv, "cx"), cy = cg_num(cyv, "cy");
    cg_ensure_point(c, cx, cy);
    CGPathAddQuadCurveToPoint(c->path, NULL, cx, cy, cg_num(xv, "x"), cg_num(yv, "y"));
    return W_NIL;
}

WValue w_cg_curve_to(WValue hv, WValue c1x, WValue c1y, WValue c2x, WValue c2y, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "curve_to");
    double ax = cg_num(c1x, "c1x"), ay = cg_num(c1y, "c1y");
    cg_ensure_point(c, ax, ay);
    CGPathAddCurveToPoint(c->path, NULL, ax, ay, cg_num(c2x, "c2x"), cg_num(c2y, "c2y"),
                          cg_num(xv, "x"), cg_num(yv, "y"));
    return W_NIL;
}

/* HTML canvas arc: angles in radians, increasing clockwise on screen. A line
 * joins the current point to the arc's start. */
WValue w_cg_arc(WValue hv, WValue cxv, WValue cyv, WValue rv, WValue a0v, WValue a1v, WValue ccwv) {
    CGCanvas *c = cg_canvas(hv, "arc");
    double r = cg_num(rv, "radius");
    if (r < 0) cg_raise("Canvas.arc: negative radius %g", r);
    /* The path's numbers are y-down screen units, so "increasing angle" is
     * CG's counter-clockwise (clockwise == false). */
    CGPathAddArc(c->path, NULL, cg_num(cxv, "cx"), cg_num(cyv, "cy"), r,
                 cg_num(a0v, "start"), cg_num(a1v, "end"), cg_truthy(ccwv));
    return W_NIL;
}

WValue w_cg_arc_to(WValue hv, WValue x1v, WValue y1v, WValue x2v, WValue y2v, WValue rv) {
    CGCanvas *c = cg_canvas(hv, "arc_to");
    double x1 = cg_num(x1v, "x1"), y1 = cg_num(y1v, "y1");
    double r = cg_num(rv, "radius");
    if (r < 0) cg_raise("Canvas.arc_to: negative radius %g", r);
    cg_ensure_point(c, x1, y1);
    CGPathAddArcToPoint(c->path, NULL, x1, y1, cg_num(x2v, "x2"), cg_num(y2v, "y2"), r);
    return W_NIL;
}

WValue w_cg_path_close(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "close_path");
    if (!CGPathIsEmpty(c->path)) CGPathCloseSubpath(c->path);
    return W_NIL;
}

WValue w_cg_add_rect(WValue hv, WValue xv, WValue yv, WValue wv, WValue hgtv) {
    CGCanvas *c = cg_canvas(hv, "add_rect");
    CGPathAddRect(c->path, NULL, CGRectMake(cg_num(xv, "x"), cg_num(yv, "y"), cg_num(wv, "w"), cg_num(hgtv, "h")));
    return W_NIL;
}

/* SVG rect rx/ry semantics: a missing radius copies the other; both clamp to
 * half the side. */
WValue w_cg_add_round_rect(WValue hv, WValue xv, WValue yv, WValue wv, WValue hgtv, WValue rxv, WValue ryv) {
    CGCanvas *c = cg_canvas(hv, "add_round_rect");
    double x = cg_num(xv, "x"), y = cg_num(yv, "y"), w = cg_num(wv, "w"), h = cg_num(hgtv, "h");
    double rx = cg_num_or(rxv, -1, "rx"), ry = cg_num_or(ryv, -1, "ry");
    if (rx < 0 && ry < 0) rx = ry = 0;
    else if (rx < 0) rx = ry;
    else if (ry < 0) ry = rx;
    if (w < 0) { x += w; w = -w; }
    if (h < 0) { y += h; h = -h; }
    if (rx > w / 2) rx = w / 2;
    if (ry > h / 2) ry = h / 2;
    CGRect r = CGRectMake(x, y, w, h);
    if (rx <= 0 || ry <= 0 || w == 0 || h == 0) CGPathAddRect(c->path, NULL, r);
    else CGPathAddRoundedRect(c->path, NULL, r, rx, ry);
    return W_NIL;
}

WValue w_cg_add_ellipse(WValue hv, WValue cxv, WValue cyv, WValue rxv, WValue ryv) {
    CGCanvas *c = cg_canvas(hv, "add_ellipse");
    double cx = cg_num(cxv, "cx"), cy = cg_num(cyv, "cy");
    double rx = cg_num(rxv, "rx"), ry = cg_num_or(ryv, rx, "ry");
    if (rx < 0 || ry < 0) cg_raise("Canvas.ellipse: negative radius");
    CGPathAddEllipseInRect(c->path, NULL, CGRectMake(cx - rx, cy - ry, 2 * rx, 2 * ry));
    return W_NIL;
}

/* ---- SVG path data ---------------------------------------------------- */

typedef struct {
    const char *s;
    size_t      n, i;
} CGSvgParser;

static void svg_skip(CGSvgParser *p) {
    while (p->i < p->n && (isspace((unsigned char)p->s[p->i]) || p->s[p->i] == ',')) p->i++;
}

static int svg_at_number(CGSvgParser *p) {
    svg_skip(p);
    if (p->i >= p->n) return 0;
    char ch = p->s[p->i];
    return isdigit((unsigned char)ch) || ch == '-' || ch == '+' || ch == '.';
}

static int svg_number(CGSvgParser *p, double *out) {
    svg_skip(p);
    size_t j = p->i;
    if (j < p->n && (p->s[j] == '+' || p->s[j] == '-')) j++;
    size_t digits = 0;
    while (j < p->n && isdigit((unsigned char)p->s[j])) { j++; digits++; }
    if (j < p->n && p->s[j] == '.') {
        j++;
        while (j < p->n && isdigit((unsigned char)p->s[j])) { j++; digits++; }
    }
    if (digits == 0) return 0;
    if (j < p->n && (p->s[j] == 'e' || p->s[j] == 'E')) {
        size_t k = j + 1;
        if (k < p->n && (p->s[k] == '+' || p->s[k] == '-')) k++;
        if (k < p->n && isdigit((unsigned char)p->s[k])) {
            while (k < p->n && isdigit((unsigned char)p->s[k])) k++;
            j = k;
        }
    }
    char buf[64];
    size_t len = j - p->i;
    if (len >= sizeof buf) return 0;
    memcpy(buf, p->s + p->i, len);
    buf[len] = 0;
    *out = strtod(buf, NULL);
    p->i = j;
    return 1;
}

static int svg_flag(CGSvgParser *p, int *out) {
    svg_skip(p);
    if (p->i < p->n && (p->s[p->i] == '0' || p->s[p->i] == '1')) {
        *out = p->s[p->i] == '1';
        p->i++;
        return 1;
    }
    return 0;
}

/* SVG 1.1 F.6.5: endpoint to centre parameterisation, then CG arcs on the
 * unit circle under translate(c) rotate(phi) scale(rx, ry). */
static void svg_arc(CGMutablePathRef path, double x1, double y1, double rx, double ry, double phi_deg,
                    int large, int sweep, double x2, double y2) {
    if (x1 == x2 && y1 == y2) return;
    rx = fabs(rx);
    ry = fabs(ry);
    if (rx == 0 || ry == 0) { CGPathAddLineToPoint(path, NULL, x2, y2); return; }
    double phi = phi_deg * M_PI / 180.0;
    double cp = cos(phi), sp = sin(phi);
    double dx2 = (x1 - x2) / 2, dy2 = (y1 - y2) / 2;
    double x1p = cp * dx2 + sp * dy2, y1p = -sp * dx2 + cp * dy2;
    double lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1) { double s = sqrt(lam); rx *= s; ry *= s; }
    double num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    double den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    double coef = den == 0 ? 0 : sqrt(fmax(0, num / den));
    if (large == sweep) coef = -coef;
    double cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx;
    double cx = cp * cxp - sp * cyp + (x1 + x2) / 2;
    double cy = sp * cxp + cp * cyp + (y1 + y2) / 2;
    double ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    double vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
    double th1 = atan2(uy, ux);
    double dth = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep && dth > 0) dth -= 2 * M_PI;
    else if (sweep && dth < 0) dth += 2 * M_PI;
    CGAffineTransform t = CGAffineTransformMakeTranslation(cx, cy);
    t = CGAffineTransformRotate(t, phi);
    t = CGAffineTransformScale(t, rx, ry);
    CGPathAddArc(path, &t, 0, 0, 1, th1, th1 + dth, dth < 0);
}

/* Parses into `path`; on error writes a message and returns 0. */
static int svg_parse(CGMutablePathRef path, const char *s, size_t n, char *err, size_t errcap) {
    CGSvgParser p = {s, n, 0};
    double cx = 0, cy = 0, sx = 0, sy = 0;   /* current point, subpath start */
    double lcx = 0, lcy = 0;                 /* last control point (S/T reflection) */
    char prev = 0, cmd = 0;
    int have_point = 0;
    for (;;) {
        svg_skip(&p);
        if (p.i >= p.n) break;
        char ch = s[p.i];
        if (isalpha((unsigned char)ch)) {
            cmd = ch;
            p.i++;
        } else if (!cmd) {
            snprintf(err, errcap, "path data must start with a command (at offset %zu)", p.i);
            return 0;
        } else if (cmd == 'Z' || cmd == 'z') {
            snprintf(err, errcap, "unexpected number after Z (at offset %zu)", p.i);
            return 0;
        }
        int rel = islower((unsigned char)cmd);
        char up = (char)toupper((unsigned char)cmd);
        double a[7];
        int nargs;
        switch (up) {
            case 'Z':
                if (have_point) CGPathCloseSubpath(path);
                cx = sx; cy = sy;
                prev = 'Z';
                continue;
            case 'M': case 'L': case 'T': nargs = 2; break;
            case 'H': case 'V': nargs = 1; break;
            case 'S': case 'Q': nargs = 4; break;
            case 'C': nargs = 6; break;
            case 'A': nargs = 7; break;
            default:
                snprintf(err, errcap, "unknown path command '%c' (at offset %zu)", cmd, p.i - 1);
                return 0;
        }
        /* One command letter may be followed by several argument groups. */
        int groups = 0;
        while (groups == 0 || svg_at_number(&p)) {
            for (int k = 0; k < nargs; k++) {
                int ok;
                if (up == 'A' && (k == 3 || k == 4)) {
                    int f;
                    ok = svg_flag(&p, &f);
                    a[k] = f;
                } else {
                    ok = svg_number(&p, &a[k]);
                }
                if (!ok) {
                    snprintf(err, errcap, "command '%c' expects %d numbers (at offset %zu)", cmd, nargs, p.i);
                    return 0;
                }
            }
            groups++;
            double ox = rel ? cx : 0, oy = rel ? cy : 0;
            if (!have_point && up != 'M') {
                CGPathMoveToPoint(path, NULL, cx, cy);
                have_point = 1;
            }
            switch (up) {
                case 'M':
                    if (groups == 1) {
                        cx = ox + a[0]; cy = oy + a[1];
                        CGPathMoveToPoint(path, NULL, cx, cy);
                        sx = cx; sy = cy;
                        have_point = 1;
                        prev = 'M';
                    } else {
                        cx = ox + a[0]; cy = oy + a[1];
                        CGPathAddLineToPoint(path, NULL, cx, cy);
                        prev = 'L';
                    }
                    break;
                case 'L':
                    cx = ox + a[0]; cy = oy + a[1];
                    CGPathAddLineToPoint(path, NULL, cx, cy);
                    prev = 'L';
                    break;
                case 'H':
                    cx = (rel ? cx : 0) + a[0];
                    CGPathAddLineToPoint(path, NULL, cx, cy);
                    prev = 'L';
                    break;
                case 'V':
                    cy = (rel ? cy : 0) + a[0];
                    CGPathAddLineToPoint(path, NULL, cx, cy);
                    prev = 'L';
                    break;
                case 'C': {
                    double x1 = ox + a[0], y1 = oy + a[1], x2 = ox + a[2], y2 = oy + a[3];
                    double x = ox + a[4], y = oy + a[5];
                    CGPathAddCurveToPoint(path, NULL, x1, y1, x2, y2, x, y);
                    lcx = x2; lcy = y2; cx = x; cy = y;
                    prev = 'C';
                    break;
                }
                case 'S': {
                    double x1 = cx, y1 = cy;
                    if (prev == 'C') { x1 = 2 * cx - lcx; y1 = 2 * cy - lcy; }
                    double x2 = ox + a[0], y2 = oy + a[1], x = ox + a[2], y = oy + a[3];
                    CGPathAddCurveToPoint(path, NULL, x1, y1, x2, y2, x, y);
                    lcx = x2; lcy = y2; cx = x; cy = y;
                    prev = 'C';
                    break;
                }
                case 'Q': {
                    double x1 = ox + a[0], y1 = oy + a[1], x = ox + a[2], y = oy + a[3];
                    CGPathAddQuadCurveToPoint(path, NULL, x1, y1, x, y);
                    lcx = x1; lcy = y1; cx = x; cy = y;
                    prev = 'Q';
                    break;
                }
                case 'T': {
                    double x1 = cx, y1 = cy;
                    if (prev == 'Q') { x1 = 2 * cx - lcx; y1 = 2 * cy - lcy; }
                    double x = ox + a[0], y = oy + a[1];
                    CGPathAddQuadCurveToPoint(path, NULL, x1, y1, x, y);
                    lcx = x1; lcy = y1; cx = x; cy = y;
                    prev = 'Q';
                    break;
                }
                case 'A': {
                    double x = ox + a[5], y = oy + a[6];
                    svg_arc(path, cx, cy, a[0], a[1], a[2], (int)a[3], (int)a[4], x, y);
                    cx = x; cy = y;
                    prev = 'A';
                    break;
                }
            }
        }
    }
    return 1;
}

/* w_cg_add_svg(h, d): append SVG path data ("M 10 20 C …") to the path. */
WValue w_cg_add_svg(WValue hv, WValue dv) {
    CGCanvas *c = cg_canvas(hv, "path");
    char sso[6];
    const char *s;
    size_t n;
    if (!cg_str_view(dv, sso, &s, &n)) cg_raise("Canvas.path: path data must be a String");
    CGMutablePathRef tmp = CGPathCreateMutable();
    char err[160];
    if (!svg_parse(tmp, s, n, err, sizeof err)) {
        CGPathRelease(tmp);
        cg_raise("Canvas.path: %s", err);
    }
    CGPathAddPath(c->path, NULL, tmp);
    CGPathRelease(tmp);
    return W_NIL;
}

/* w_cg_add_points(h, pts, close): pts is [[x, y], …] or a flat [x0, y0, x1,
 * y1, …] (plain or typed array). Starts a new subpath. */
WValue w_cg_add_points(WValue hv, WValue ptsv, WValue closev) {
    CGCanvas *c = cg_canvas(hv, "points");
    int64_t n = cg_array_len(ptsv);
    if (n < 0) cg_raise("Canvas.polyline: points must be an Array");
    if (n == 0) return W_NIL;
    WValue first = cg_array_at(ptsv, 0);
    int pairs = w_is_array(first);
    int64_t count = pairs ? n : n / 2;
    if (!pairs && (n % 2) != 0) cg_raise("Canvas.polyline: a flat point list needs an even length (got %lld)", (long long)n);
    for (int64_t i = 0; i < count; i++) {
        double x, y;
        if (pairs) {
            WValue pt = cg_array_at(ptsv, i);
            if (cg_array_len(pt) < 2) cg_raise("Canvas.polyline: point %lld is not an [x, y] pair", (long long)i);
            x = cg_num(cg_array_at(pt, 0), "x");
            y = cg_num(cg_array_at(pt, 1), "y");
        } else {
            x = cg_num(cg_array_at(ptsv, 2 * i), "x");
            y = cg_num(cg_array_at(ptsv, 2 * i + 1), "y");
        }
        if (i == 0) CGPathMoveToPoint(c->path, NULL, x, y);
        else CGPathAddLineToPoint(c->path, NULL, x, y);
    }
    if (cg_truthy(closev)) CGPathCloseSubpath(c->path);
    return W_NIL;
}

/* [x, y, w, h] of the current path in user units (control points excluded). */
WValue w_cg_path_bounds(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "path_bounds");
    if (CGPathIsEmpty(c->path)) return W_NIL;
    CGRect r = CGPathGetPathBoundingBox(c->path);
    double v[4] = {r.origin.x, r.origin.y, r.size.width, r.size.height};
    return cg_float_array(v, 4);
}

WValue w_cg_path_contains(WValue hv, WValue xv, WValue yv, WValue eov) {
    CGCanvas *c = cg_canvas(hv, "path_contains?");
    return w_bool(CGPathContainsPoint(c->path, NULL, CGPointMake(cg_num(xv, "x"), cg_num(yv, "y")), cg_truthy(eov)));
}

/* ======================================================================
   Colours
   ====================================================================== */

typedef struct { const char *name; uint32_t rgb; } CGNamedColor;
static const CGNamedColor g_named_colors[] = {
    {"aliceblue", 0xf0f8ff}, {"antiquewhite", 0xfaebd7}, {"aqua", 0x00ffff}, {"aquamarine", 0x7fffd4},
    {"azure", 0xf0ffff}, {"beige", 0xf5f5dc}, {"bisque", 0xffe4c4}, {"black", 0x000000},
    {"blanchedalmond", 0xffebcd}, {"blue", 0x0000ff}, {"blueviolet", 0x8a2be2}, {"brown", 0xa52a2a},
    {"burlywood", 0xdeb887}, {"cadetblue", 0x5f9ea0}, {"chartreuse", 0x7fff00}, {"chocolate", 0xd2691e},
    {"coral", 0xff7f50}, {"cornflowerblue", 0x6495ed}, {"cornsilk", 0xfff8dc}, {"crimson", 0xdc143c},
    {"cyan", 0x00ffff}, {"darkblue", 0x00008b}, {"darkcyan", 0x008b8b}, {"darkgoldenrod", 0xb8860b},
    {"darkgray", 0xa9a9a9}, {"darkgreen", 0x006400}, {"darkgrey", 0xa9a9a9}, {"darkkhaki", 0xbdb76b},
    {"darkmagenta", 0x8b008b}, {"darkolivegreen", 0x556b2f}, {"darkorange", 0xff8c00}, {"darkorchid", 0x9932cc},
    {"darkred", 0x8b0000}, {"darksalmon", 0xe9967a}, {"darkseagreen", 0x8fbc8f}, {"darkslateblue", 0x483d8b},
    {"darkslategray", 0x2f4f4f}, {"darkslategrey", 0x2f4f4f}, {"darkturquoise", 0x00ced1}, {"darkviolet", 0x9400d3},
    {"deeppink", 0xff1493}, {"deepskyblue", 0x00bfff}, {"dimgray", 0x696969}, {"dimgrey", 0x696969},
    {"dodgerblue", 0x1e90ff}, {"firebrick", 0xb22222}, {"floralwhite", 0xfffaf0}, {"forestgreen", 0x228b22},
    {"fuchsia", 0xff00ff}, {"gainsboro", 0xdcdcdc}, {"ghostwhite", 0xf8f8ff}, {"gold", 0xffd700},
    {"goldenrod", 0xdaa520}, {"gray", 0x808080}, {"green", 0x008000}, {"greenyellow", 0xadff2f},
    {"grey", 0x808080}, {"honeydew", 0xf0fff0}, {"hotpink", 0xff69b4}, {"indianred", 0xcd5c5c},
    {"indigo", 0x4b0082}, {"ivory", 0xfffff0}, {"khaki", 0xf0e68c}, {"lavender", 0xe6e6fa},
    {"lavenderblush", 0xfff0f5}, {"lawngreen", 0x7cfc00}, {"lemonchiffon", 0xfffacd}, {"lightblue", 0xadd8e6},
    {"lightcoral", 0xf08080}, {"lightcyan", 0xe0ffff}, {"lightgoldenrodyellow", 0xfafad2}, {"lightgray", 0xd3d3d3},
    {"lightgreen", 0x90ee90}, {"lightgrey", 0xd3d3d3}, {"lightpink", 0xffb6c1}, {"lightsalmon", 0xffa07a},
    {"lightseagreen", 0x20b2aa}, {"lightskyblue", 0x87cefa}, {"lightslategray", 0x778899}, {"lightslategrey", 0x778899},
    {"lightsteelblue", 0xb0c4de}, {"lightyellow", 0xffffe0}, {"lime", 0x00ff00}, {"limegreen", 0x32cd32},
    {"linen", 0xfaf0e6}, {"magenta", 0xff00ff}, {"maroon", 0x800000}, {"mediumaquamarine", 0x66cdaa},
    {"mediumblue", 0x0000cd}, {"mediumorchid", 0xba55d3}, {"mediumpurple", 0x9370db}, {"mediumseagreen", 0x3cb371},
    {"mediumslateblue", 0x7b68ee}, {"mediumspringgreen", 0x00fa9a}, {"mediumturquoise", 0x48d1cc},
    {"mediumvioletred", 0xc71585}, {"midnightblue", 0x191970}, {"mintcream", 0xf5fffa}, {"mistyrose", 0xffe4e1},
    {"moccasin", 0xffe4b5}, {"navajowhite", 0xffdead}, {"navy", 0x000080}, {"oldlace", 0xfdf5e6},
    {"olive", 0x808000}, {"olivedrab", 0x6b8e23}, {"orange", 0xffa500}, {"orangered", 0xff4500},
    {"orchid", 0xda70d6}, {"palegoldenrod", 0xeee8aa}, {"palegreen", 0x98fb98}, {"paleturquoise", 0xafeeee},
    {"palevioletred", 0xdb7093}, {"papayawhip", 0xffefd5}, {"peachpuff", 0xffdab9}, {"peru", 0xcd853f},
    {"pink", 0xffc0cb}, {"plum", 0xdda0dd}, {"powderblue", 0xb0e0e6}, {"purple", 0x800080},
    {"rebeccapurple", 0x663399}, {"red", 0xff0000}, {"rosybrown", 0xbc8f8f}, {"royalblue", 0x4169e1},
    {"saddlebrown", 0x8b4513}, {"salmon", 0xfa8072}, {"sandybrown", 0xf4a460}, {"seagreen", 0x2e8b57},
    {"seashell", 0xfff5ee}, {"sienna", 0xa0522d}, {"silver", 0xc0c0c0}, {"skyblue", 0x87ceeb},
    {"slateblue", 0x6a5acd}, {"slategray", 0x708090}, {"slategrey", 0x708090}, {"snow", 0xfffafa},
    {"springgreen", 0x00ff7f}, {"steelblue", 0x4682b4}, {"tan", 0xd2b48c}, {"teal", 0x008080},
    {"thistle", 0xd8bfd8}, {"tomato", 0xff6347}, {"turquoise", 0x40e0d0}, {"violet", 0xee82ee},
    {"wheat", 0xf5deb3}, {"white", 0xffffff}, {"whitesmoke", 0xf5f5f5}, {"yellow", 0xffff00},
    {"yellowgreen", 0x9acd32},
};

static int hexval(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

/* "rgb(…)"/"rgba(…)": comma- or space-separated, % or 0..255 channels, alpha
 * as 0..1 or %, optional "/ alpha". */
static int cg_parse_rgb_fn(const char *s, double out[4]) {
    const char *p = strchr(s, '(');
    if (!p) return 0;
    p++;
    double v[4] = {0, 0, 0, 1};
    int n = 0;
    while (*p && n < 4) {
        while (*p == ' ' || *p == ',' || *p == '/' || *p == '\t') p++;
        if (*p == ')' || !*p) break;
        char *end;
        double x = strtod(p, &end);
        if (end == p) return 0;
        p = end;
        if (*p == '%') { x = (n < 3 ? x * 2.55 : x / 100.0); p++; }
        v[n++] = x;
    }
    if (n < 3) return 0;
    out[0] = v[0] / 255.0;
    out[1] = v[1] / 255.0;
    out[2] = v[2] / 255.0;
    out[3] = n == 4 ? v[3] : 1.0;
    return 1;
}

/* Parse a paint colour. Returns 1 with RGBA (0..1) in out, 0 for "none"
 * (nil, false, "none", "transparent"); raises on garbage. */
static int cg_color(WValue v, double out[4], const char *what) {
    if (v == W_NIL || v == W_FALSE) return 0;
    if (w_is_color(v)) {
        if (w_color_mode(v) == 0) {
            out[0] = w_unbox_color_r(v) / 255.0;
            out[1] = w_unbox_color_g(v) / 255.0;
            out[2] = w_unbox_color_b(v) / 255.0;
            out[3] = w_unbox_color_a(v) / 255.0;
        } else {
            out[0] = w_unbox_color_hdr_r(v) / 1023.0;
            out[1] = w_unbox_color_hdr_g(v) / 1023.0;
            out[2] = w_unbox_color_hdr_b(v) / 1023.0;
            out[3] = w_unbox_color_hdr_a(v) / 1023.0;
        }
        return 1;
    }
    if (w_is_int(v)) {
        int64_t x = w_as_int(v);
        if (x < 0 || x > 0xFFFFFF) cg_raise("Canvas: %s integer colour must be 0xRRGGBB", what);
        out[0] = ((x >> 16) & 0xFF) / 255.0;
        out[1] = ((x >> 8) & 0xFF) / 255.0;
        out[2] = (x & 0xFF) / 255.0;
        out[3] = 1.0;
        return 1;
    }
    if (w_is_array(v)) {
        int64_t n = cg_array_len(v);
        if (n != 3 && n != 4) cg_raise("Canvas: %s colour array must be [r, g, b] or [r, g, b, a] in 0..1", what);
        for (int i = 0; i < 3; i++) out[i] = cg_num(cg_array_at(v, i), "colour component");
        out[3] = n == 4 ? cg_num(cg_array_at(v, 3), "alpha") : 1.0;
        return 1;
    }
    char buf[64];
    if (!cg_str(v, buf, sizeof buf)) cg_raise("Canvas: %s must be a colour (\"#rrggbb\", a Color, 0xRRGGBB or [r, g, b])", what);
    char *s = buf;
    while (*s == ' ') s++;
    size_t len = strlen(s);
    while (len && s[len - 1] == ' ') s[--len] = 0;
    if (s[0] == '#') {
        int d[8];
        size_t nd = len - 1;
        if (nd != 3 && nd != 4 && nd != 6 && nd != 8) cg_raise("Canvas: bad %s colour \"%s\"", what, s);
        for (size_t i = 0; i < nd; i++) {
            d[i] = hexval(s[1 + i]);
            if (d[i] < 0) cg_raise("Canvas: bad %s colour \"%s\"", what, s);
        }
        if (nd <= 4) {
            for (int i = 0; i < 3; i++) out[i] = d[i] * 17 / 255.0;
            out[3] = nd == 4 ? d[3] * 17 / 255.0 : 1.0;
        } else {
            for (int i = 0; i < 3; i++) out[i] = (d[2 * i] * 16 + d[2 * i + 1]) / 255.0;
            out[3] = nd == 8 ? (d[6] * 16 + d[7]) / 255.0 : 1.0;
        }
        return 1;
    }
    if (cg_eq(s, "none") || cg_eq(s, "transparent") || len == 0) return 0;
    if (strncasecmp(s, "rgb", 3) == 0) {
        if (cg_parse_rgb_fn(s, out)) return 1;
        cg_raise("Canvas: bad %s colour \"%s\"", what, s);
    }
    for (size_t i = 0; i < sizeof g_named_colors / sizeof g_named_colors[0]; i++) {
        if (cg_eq(s, g_named_colors[i].name)) {
            uint32_t x = g_named_colors[i].rgb;
            out[0] = ((x >> 16) & 0xFF) / 255.0;
            out[1] = ((x >> 8) & 0xFF) / 255.0;
            out[2] = (x & 0xFF) / 255.0;
            out[3] = 1.0;
            return 1;
        }
    }
    cg_raise("Canvas: unknown %s colour \"%s\"", what, s);
}

static void cg_set_fill(CGCanvas *c, const double rgba[4]) {
    CGStateEntry *st = cg_state(c);
    if (st->has_fill_cache &&
        st->fill[0] == rgba[0] && st->fill[1] == rgba[1] &&
        st->fill[2] == rgba[2] && st->fill[3] == rgba[3]) {
        return;
    }
    const CGFloat comps[4] = {rgba[0], rgba[1], rgba[2], rgba[3]};
    CGContextSetFillColor(c->ctx, comps);
    memcpy(st->fill, rgba, sizeof st->fill);
    st->has_fill_cache = 1;
}

static void cg_set_stroke(CGCanvas *c, const double rgba[4]) {
    CGStateEntry *st = cg_state(c);
    if (st->has_stroke_cache &&
        st->stroke[0] == rgba[0] && st->stroke[1] == rgba[1] &&
        st->stroke[2] == rgba[2] && st->stroke[3] == rgba[3]) {
        return;
    }
    const CGFloat comps[4] = {rgba[0], rgba[1], rgba[2], rgba[3]};
    CGContextSetStrokeColor(c->ctx, comps);
    memcpy(st->stroke, rgba, sizeof st->stroke);
    st->has_stroke_cache = 1;
}

/* ======================================================================
   Line style, paint, gradients, clip, layers
   ====================================================================== */

/* Parse a dash pattern (nil, "none", "10 8", or [10, 8]) into out; returns
 * the count, 0 for solid. */
static int cg_dash(WValue v, CGFloat *out, int cap) {
    if (v == W_NIL || v == W_FALSE) return 0;
    int n = 0;
    if (w_is_array(v)) {
        int64_t len = cg_array_len(v);
        for (int64_t i = 0; i < len && n < cap; i++) out[n++] = cg_num(cg_array_at(v, i), "dash length");
    } else if (cg_is_numeric(v)) {
        out[n++] = cg_num(v, "dash length");
    } else {
        char buf[256];
        if (!cg_str(v, buf, sizeof buf)) cg_raise("Canvas: dash must be an Array or a String like \"10 8\"");
        if (cg_eq(buf, "none")) return 0;
        char *p = buf;
        while (*p && n < cap) {
            while (*p == ' ' || *p == ',') p++;
            if (!*p) break;
            char *end;
            double x = strtod(p, &end);
            if (end == p) cg_raise("Canvas: bad dash pattern \"%s\"", buf);
            out[n++] = x;
            p = end;
        }
    }
    double sum = 0;
    for (int i = 0; i < n; i++) {
        if (out[i] < 0) cg_raise("Canvas: negative dash length");
        sum += out[i];
    }
    if (sum == 0) return 0;
    /* SVG repeats an odd-length list to make it even. */
    if (n % 2 == 1 && 2 * n <= cap) {
        for (int i = 0; i < n; i++) out[n + i] = out[i];
        n *= 2;
    }
    return n;
}

/* w_cg_set_line(h, width, cap, join, miter, dash, dash_offset). nil keeps
 * SVG's default for that field (1, butt, miter, 4, solid, 0). */
WValue w_cg_set_line(WValue hv, WValue wv, WValue capv, WValue joinv, WValue miterv, WValue dashv, WValue offv) {
    CGCanvas *c = cg_canvas(hv, "set_line");
    double w = cg_num_or(wv, 1.0, "stroke width");
    if (w < 0) cg_raise("Canvas: negative stroke width %g", w);
    char cap[16] = "butt", join[16] = "miter";
    if (capv != W_NIL && !cg_str(capv, cap, sizeof cap)) cg_raise("Canvas: linecap must be butt, round or square");
    if (joinv != W_NIL && !cg_str(joinv, join, sizeof join)) cg_raise("Canvas: linejoin must be miter, round or bevel");
    CGLineCap lc;
    if (cg_eq(cap, "butt")) lc = kCGLineCapButt;
    else if (cg_eq(cap, "round")) lc = kCGLineCapRound;
    else if (cg_eq(cap, "square")) lc = kCGLineCapSquare;
    else cg_raise("Canvas: linecap must be butt, round or square (got \"%s\")", cap);
    CGLineJoin lj;
    if (cg_eq(join, "miter") || cg_eq(join, "miter-clip") || cg_eq(join, "arcs")) lj = kCGLineJoinMiter;
    else if (cg_eq(join, "round")) lj = kCGLineJoinRound;
    else if (cg_eq(join, "bevel")) lj = kCGLineJoinBevel;
    else cg_raise("Canvas: linejoin must be miter, round or bevel (got \"%s\")", join);
    double miter = cg_num_or(miterv, 4.0, "miter limit");
    CGFloat dash[64];
    int nd = cg_dash(dashv, dash, 64);
    double off = cg_num_or(offv, 0.0, "dash offset");
    CGContextSetLineWidth(c->ctx, w);
    CGContextSetLineCap(c->ctx, lc);
    CGContextSetLineJoin(c->ctx, lj);
    CGContextSetMiterLimit(c->ctx, miter);
    CGContextSetLineDash(c->ctx, off, nd ? dash : NULL, (size_t)nd);
    cg_state(c)->line_width = w;
    cg_state(c)->miter = miter;
    cg_state(c)->is_solid_butt = (lc == kCGLineCapButt && nd == 0);
    return W_NIL;
}

/* Bounds of what painting the path touches, for transparency layers. */
static CGRect cg_paint_bounds(CGCanvas *c, int stroked) {
    CGRect r = CGPathGetPathBoundingBox(c->path);
    if (stroked) {
        CGStateEntry *st = cg_state(c);
        double m = st->line_width * 0.5 * fmax(1.0, st->miter) + 1;
        r = CGRectInset(r, -m, -m);
    }
    return CGRectInset(r, -1, -1);
}

static void cg_layer_begin_rect(CGCanvas *c, double opacity, CGRect rect, int whole) {
    if (c->depth >= CG_MAX_DEPTH) cg_raise("Canvas: more than %d nested saves/layers", CG_MAX_DEPTH);
    CGContextSaveGState(c->ctx);
    c->st[c->depth + 1] = c->st[c->depth];
    c->depth++;
    CGContextSetAlpha(c->ctx, c->st[c->depth - 1].alpha * opacity);
    if (whole) CGContextBeginTransparencyLayer(c->ctx, NULL);
    else CGContextBeginTransparencyLayerWithRect(c->ctx, rect, NULL);
    /* Inside a layer CG resets alpha to 1 and blend to normal. */
    cg_state(c)->alpha = 1.0;
    cg_state(c)->has_fill_cache = 0;
    cg_state(c)->has_stroke_cache = 0;
}

static void cg_layer_end(CGCanvas *c) {
    CGContextEndTransparencyLayer(c->ctx);
    CGContextRestoreGState(c->ctx);
    c->depth--;
}

/* w_cg_layer_begin(h, opacity): everything drawn until layer_end composites
 * as one group at `opacity` (SVG group opacity). */
WValue w_cg_layer_begin(WValue hv, WValue opv) {
    CGCanvas *c = cg_canvas(hv, "layer");
    double op = cg_num_or(opv, 1.0, "opacity");
    cg_layer_begin_rect(c, op < 0 ? 0 : (op > 1 ? 1 : op), CGRectNull, 1);
    return W_NIL;
}

WValue w_cg_layer_end(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "layer_end");
    if (c->depth == 0) cg_raise("Canvas.layer_end: no open layer");
    cg_layer_end(c);
    return W_NIL;
}

/* w_cg_paint(h, fill, fill_opacity, stroke, stroke_opacity, opacity, evenodd)
 * paints the current path with SVG order and semantics: fill, then stroke;
 * `opacity` applies to the pair as a group. Returns whether anything was
 * painted. The path is kept. */
WValue w_cg_paint(WValue hv, WValue fillv, WValue fopv, WValue strokev, WValue sopv, WValue opv, WValue eov) {
    CGCanvas *c = cg_canvas(hv, "paint");
    double fc[4], sc[4];
    int has_fill = cg_color(fillv, fc, "fill");
    int has_stroke = cg_color(strokev, sc, "stroke");
    double fop = cg_num_or(fopv, 1.0, "fill_opacity");
    double sop = cg_num_or(sopv, 1.0, "stroke_opacity");
    double op = cg_num_or(opv, 1.0, "opacity");
    if (op <= 0 || CGPathIsEmpty(c->path)) return W_FALSE;
    fc[3] *= fop;
    sc[3] *= sop;
    if (has_fill && fc[3] <= 0) has_fill = 0;
    if (has_stroke && (sc[3] <= 0 || cg_state(c)->line_width <= 0)) has_stroke = 0;
    if (!has_fill && !has_stroke) return W_FALSE;
    int group = has_fill && has_stroke && op < 1;
    if (group) {
        cg_layer_begin_rect(c, op, cg_paint_bounds(c, 1), 0);
    } else {
        fc[3] *= op;
        sc[3] *= op;
    }
    if (has_fill) {
        cg_set_fill(c, fc);
        CGContextAddPath(c->ctx, c->path);
        if (cg_truthy(eov)) CGContextEOFillPath(c->ctx);
        else CGContextFillPath(c->ctx);
    }
    if (has_stroke) {
        cg_set_stroke(c, sc);
        CGContextAddPath(c->ctx, c->path);
        CGContextStrokePath(c->ctx);
    }
    if (group) cg_layer_end(c);
    return W_TRUE;
}

static uint64_t cg_fnv(const void *p, size_t n, uint64_t h) {
    const uint8_t *b = p;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ULL; }
    return h;
}

/* Build (or fetch from the per-canvas cache) a CGGradient for stops
 * [[offset, colour(, opacity)], …], every alpha scaled by `opacity`. */
static CGGradientRef cg_gradient_for(CGCanvas *c, WValue stopsv, double opacity) {
    int64_t n = cg_array_len(stopsv);
    if (n < 1) cg_raise("Canvas: gradient stops must be a non-empty Array of [offset, colour(, opacity)]");
    if (n > 256) cg_raise("Canvas: at most 256 gradient stops");
    double key[256 * 5];
    double last = 0;
    for (int64_t i = 0; i < n; i++) {
        WValue st = cg_array_at(stopsv, i);
        int64_t m = cg_array_len(st);
        if (m < 2) cg_raise("Canvas: gradient stop %lld must be [offset, colour(, opacity)]", (long long)i);
        double off = cg_num(cg_array_at(st, 0), "stop offset");
        if (off < 0) off = 0;
        if (off > 1) off = 1;
        if (off < last) off = last;   /* SVG: offsets never decrease */
        last = off;
        double rgba[4];
        if (!cg_color(cg_array_at(st, 1), rgba, "gradient stop")) rgba[0] = rgba[1] = rgba[2] = rgba[3] = 0;
        double sop = m >= 3 ? cg_num_or(cg_array_at(st, 2), 1.0, "stop opacity") : 1.0;
        double *k = &key[i * 5];
        k[0] = off;
        k[1] = rgba[0];
        k[2] = rgba[1];
        k[3] = rgba[2];
        k[4] = rgba[3] * sop * opacity;
    }
    size_t kb = (size_t)n * 5 * sizeof(double);
    uint64_t h = cg_fnv(key, kb, 14695981039346656037ULL);
    CGGradEntry *e = &c->grads[h % CG_GRAD_CACHE];
    if (e->gradient && e->hash == h && e->n == n && memcmp(e->key, key, kb) == 0) return e->gradient;
    CGFloat comps[256 * 4], locs[256];
    for (int64_t i = 0; i < n; i++) {
        locs[i] = key[i * 5];
        for (int j = 0; j < 4; j++) comps[i * 4 + j] = key[i * 5 + 1 + j];
    }
    CGGradientRef g = CGGradientCreateWithColorComponents(c->color_space, comps, locs, (size_t)n);
    if (!g) cg_raise("Canvas: CoreGraphics could not build the gradient");
    if (e->gradient) CGGradientRelease(e->gradient);
    free(e->key);
    e->key = malloc(kb);
    memcpy(e->key, key, kb);
    e->n = (int)n;
    e->hash = h;
    e->gradient = g;
    return g;
}

/* w_cg_gradient(h, target, kind, a, b, c, d, e, f, stops, opacity, evenodd, bbox, spread)
 *   target "fill" | "stroke"; kind "linear" (a..d = x1 y1 x2 y2) or "radial"
 *   (a..f = cx cy r fx fy fr; nil focus = centre). bbox: coordinates are
 *   fractions of the path's bounding box (SVG objectBoundingBox). spread:
 *   "pad" (default) extends the end colours; "none" paints only between. */
WValue w_cg_gradient(WValue hv, WValue targetv, WValue kindv, WValue av, WValue bv, WValue cv, WValue dv,
                     WValue ev, WValue fv, WValue stopsv, WValue opv, WValue eov, WValue bboxv, WValue spreadv) {
    CGCanvas *c = cg_canvas(hv, "gradient");
    char target[16], kind[16], spread[16] = "pad";
    cg_str(targetv, target, sizeof target);
    cg_str(kindv, kind, sizeof kind);
    if (spreadv != W_NIL) cg_str(spreadv, spread, sizeof spread);
    int stroke = cg_eq(target, "stroke");
    int radial = cg_eq(kind, "radial");
    if (!radial && !cg_eq(kind, "linear")) cg_raise("Canvas: gradient kind must be linear or radial");
    double op = cg_num_or(opv, 1.0, "opacity");
    double a = cg_num(av, "gradient coordinate"), b = cg_num(bv, "gradient coordinate");
    double cc = cg_num(cv, "gradient coordinate");
    double d = radial ? cg_num_or(dv, a, "fx") : cg_num(dv, "gradient coordinate");
    double e = radial ? cg_num_or(ev, b, "fy") : 0;
    double f = radial ? cg_num_or(fv, 0, "fr") : 0;
    if (op <= 0 || CGPathIsEmpty(c->path)) return W_FALSE;
    if (stroke && cg_state(c)->line_width <= 0) return W_FALSE;
    CGGradientRef g = cg_gradient_for(c, stopsv, op);
    CGRect bb = CGPathGetPathBoundingBox(c->path);
    int bbox = cg_truthy(bboxv);
    if (bbox && (bb.size.width <= 0 || bb.size.height <= 0)) return W_FALSE;  /* SVG: not rendered */
    CGGradientDrawingOptions opts = cg_eq(spread, "none") ? 0
        : (kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextSaveGState(c->ctx);
    CGContextAddPath(c->ctx, c->path);
    if (stroke) {
        CGContextReplacePathWithStrokedPath(c->ctx);
        CGContextClip(c->ctx);
    } else if (cg_truthy(eov)) {
        CGContextEOClip(c->ctx);
    } else {
        CGContextClip(c->ctx);
    }
    if (bbox) CGContextConcatCTM(c->ctx, CGAffineTransformMake(bb.size.width, 0, 0, bb.size.height, bb.origin.x, bb.origin.y));
    if (radial) CGContextDrawRadialGradient(c->ctx, g, CGPointMake(d, e), f, CGPointMake(a, b), cc, opts);
    else CGContextDrawLinearGradient(c->ctx, g, CGPointMake(a, b), CGPointMake(cc, d), opts);
    CGContextRestoreGState(c->ctx);
    return W_TRUE;
}

/* Intersect the clip with the current path, then clear the path (as CG and
 * HTML canvas do). Undo with restore. */
WValue w_cg_clip(WValue hv, WValue eov) {
    CGCanvas *c = cg_canvas(hv, "clip");
    CGContextAddPath(c->ctx, c->path);
    if (CGPathIsEmpty(c->path)) {
        CGContextClipToRect(c->ctx, CGRectZero);
    } else if (cg_truthy(eov)) {
        CGContextEOClip(c->ctx);
    } else {
        CGContextClip(c->ctx);
    }
    CGPathRelease(c->path);
    c->path = CGPathCreateMutable();
    return W_NIL;
}

/* ======================================================================
   Fonts and text
   ====================================================================== */

#define CG_FONT_BUCKETS 512

typedef struct CGFontEntry {
    struct CGFontEntry *next;
    uint64_t            hash;
    char               *key;
    CTFontRef           font;
} CGFontEntry;

static CGFontEntry *g_fonts[CG_FONT_BUCKETS];
static int g_font_count;
static pthread_mutex_t g_font_lock = PTHREAD_MUTEX_INITIALIZER;

/* CT weight trait (-1..1) to CSS weight, through Apple's NSFontWeight
 * anchors (ultraLight -0.8 … black 0.62). */
static double cg_css_from_trait(double t) {
    static const double tr[] = {-1.0, -0.8, -0.6, -0.4, 0.0, 0.23, 0.3, 0.4, 0.56, 0.62, 1.0};
    static const double css[] = {1, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000};
    if (t <= tr[0]) return css[0];
    for (int i = 1; i < 11; i++) {
        if (t <= tr[i]) return css[i - 1] + (css[i] - css[i - 1]) * (t - tr[i - 1]) / (tr[i] - tr[i - 1]);
    }
    return 1000;
}

static double cg_trait_from_css(double w) {
    static const double tr[] = {-1.0, -0.8, -0.6, -0.4, 0.0, 0.23, 0.3, 0.4, 0.56, 0.62, 1.0};
    static const double css[] = {1, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000};
    if (w <= css[0]) return tr[0];
    for (int i = 1; i < 11; i++) {
        if (w <= css[i]) return tr[i - 1] + (tr[i] - tr[i - 1]) * (w - css[i - 1]) / (css[i] - css[i - 1]);
    }
    return 1.0;
}

static double cg_dict_num(CFDictionaryRef d, CFStringRef key) {
    double v = 0;
    if (!d) return 0;
    CFNumberRef n = CFDictionaryGetValue(d, key);
    if (n) CFNumberGetValue(n, kCFNumberDoubleType, &v);
    return v;
}

/* Best face of `family` for a CSS weight and italic flag, or NULL. */
static CTFontDescriptorRef cg_family_face(CFStringRef family, double weight, int italic) {
    const void *k[] = {kCTFontFamilyNameAttribute};
    const void *v[] = {family};
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef want = CTFontDescriptorCreateWithAttributes(attrs);
    CFSetRef mandatory = CFSetCreate(NULL, k, 1, &kCFTypeSetCallBacks);
    CFArrayRef faces = CTFontDescriptorCreateMatchingFontDescriptors(want, mandatory);
    CFRelease(mandatory);
    CFRelease(want);
    CFRelease(attrs);
    if (!faces) return NULL;
    CTFontDescriptorRef best = NULL;
    double best_score = 1e18;
    for (CFIndex i = 0; i < CFArrayGetCount(faces); i++) {
        CTFontDescriptorRef fd = CFArrayGetValueAtIndex(faces, i);
        CFDictionaryRef tr = CTFontDescriptorCopyAttribute(fd, kCTFontTraitsAttribute);
        double css = cg_css_from_trait(cg_dict_num(tr, kCTFontWeightTrait));
        double width = cg_dict_num(tr, kCTFontWidthTrait);
        uint32_t sym = 0;
        if (tr) {
            CFNumberRef sn = CFDictionaryGetValue(tr, kCTFontSymbolicTrait);
            if (sn) CFNumberGetValue(sn, kCFNumberSInt32Type, &sym);
            CFRelease(tr);
        }
        int is_italic = (sym & kCTFontItalicTrait) != 0;
        /* CSS font matching, approximately: exact style first, then the
         * nearest weight, leaning lighter below 400/500 and heavier above. */
        double score = (is_italic != italic) ? 10000 : 0;
        score += fabs(width) * 2000;
        double dw = css - weight;
        score += fabs(dw);
        if (weight > 500 && dw < 0) score += 50;
        if (weight < 400 && dw > 0) score += 50;
        if ((weight == 400 || weight == 500) && dw < 0) score += 25;
        if (score < best_score) { best_score = score; best = fd; }
    }
    if (best) CFRetain(best);
    CFRelease(faces);
    return best;
}

static CFStringRef cg_generic_family(const char *name) {
    if (cg_eq(name, "sans-serif") || cg_eq(name, "sans")) return CFSTR("Helvetica");
    if (cg_eq(name, "serif")) return CFSTR("Times");
    if (cg_eq(name, "monospace") || cg_eq(name, "ui-monospace")) return CFSTR("Menlo");
    if (cg_eq(name, "cursive")) return CFSTR("Apple Chancery");
    if (cg_eq(name, "fantasy")) return CFSTR("Papyrus");
    if (cg_eq(name, "math")) return CFSTR("STIX Two Math");
    return NULL;
}

/* A variable font with a 'wght' axis, set to the CSS weight (clamped to the
 * axis range); any other font is returned as is. Takes ownership of font.
 * Without this a variable face resolved by PostScript name (a web font's
 * default instance) draws every weight at its default, and a face matched by
 * family snaps to the nearest named instance. */
static CTFontRef cg_font_weighted(CTFontRef font, double weight, double size) {
    if (!font) return NULL;
    CFArrayRef axes = CTFontCopyVariationAxes(font);
    if (!axes) return font;
    const uint32_t wght = ('w' << 24) | ('g' << 16) | ('h' << 8) | 't';
    CTFontRef out = font;
    for (CFIndex i = 0; i < CFArrayGetCount(axes); i++) {
        CFDictionaryRef ax = CFArrayGetValueAtIndex(axes, i);
        CFNumberRef idn = CFDictionaryGetValue(ax, kCTFontVariationAxisIdentifierKey);
        int64_t id = 0;
        if (!idn || !CFNumberGetValue(idn, kCFNumberSInt64Type, &id) || (uint32_t)id != wght) continue;
        double lo = cg_dict_num(ax, kCTFontVariationAxisMinimumValueKey);
        double hi = cg_dict_num(ax, kCTFontVariationAxisMaximumValueKey);
        double v = weight < lo ? lo : (weight > hi ? hi : weight);
        CFNumberRef key = CFNumberCreate(NULL, kCFNumberSInt64Type, &id);
        CFNumberRef val = CFNumberCreate(NULL, kCFNumberDoubleType, &v);
        const void *vk[] = {key};
        const void *vv[] = {val};
        CFDictionaryRef var = CFDictionaryCreate(NULL, vk, vv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        const void *ak[] = {kCTFontVariationAttribute};
        const void *av[] = {var};
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes(attrs);
        CTFontRef f = CTFontCreateCopyWithAttributes(font, size, NULL, d);
        CFRelease(d); CFRelease(attrs); CFRelease(var); CFRelease(val); CFRelease(key);
        if (f) { CFRelease(font); out = f; }
        break;
    }
    CFRelease(axes);
    return out;
}

/* Resolve one family name (or PostScript name) to a sized font. */
static CTFontRef cg_font_one(const char *name, double weight, int italic, double size) {
    if (cg_eq(name, "system-ui") || cg_eq(name, "-apple-system") || cg_eq(name, "ui-sans-serif")) {
        CTFontRef sys = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
        if (!sys) return NULL;
        CTFontDescriptorRef d = CTFontCopyFontDescriptor(sys);
        CFRelease(sys);
        double t = cg_trait_from_css(weight);
        CFNumberRef wn = CFNumberCreate(NULL, kCFNumberDoubleType, &t);
        uint32_t symv = italic ? kCTFontItalicTrait : 0;
        CFNumberRef sn = CFNumberCreate(NULL, kCFNumberSInt32Type, &symv);
        const void *tk[] = {kCTFontWeightTrait, kCTFontSymbolicTrait};
        const void *tv[] = {wn, sn};
        CFDictionaryRef traits = CFDictionaryCreate(NULL, tk, tv, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        const void *ak[] = {kCTFontTraitsAttribute};
        const void *av[] = {traits};
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CTFontDescriptorRef d2 = CTFontDescriptorCreateCopyWithAttributes(d, attrs);
        CTFontRef f = CTFontCreateWithFontDescriptor(d2, size, NULL);
        CFRelease(d2); CFRelease(attrs); CFRelease(traits); CFRelease(sn); CFRelease(wn); CFRelease(d);
        return f;
    }
    CFStringRef generic = cg_generic_family(name);
    CFStringRef cfname = generic ? (CFStringRef)CFRetain(generic) : CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    if (!cfname) return NULL;
    CTFontDescriptorRef face = cg_family_face(cfname, weight, italic);
    CTFontRef font = NULL;
    if (face) {
        font = CTFontCreateWithFontDescriptor(face, size, NULL);
        CFRelease(face);
    } else {
        /* Not a family: accept it only as an exact PostScript name, since
         * CTFontCreateWithName silently substitutes a fallback otherwise. */
        CTFontRef f = CTFontCreateWithName(cfname, size, NULL);
        if (f) {
            CFStringRef ps = CTFontCopyPostScriptName(f);
            if (ps && CFStringCompare(ps, cfname, kCFCompareCaseInsensitive) == kCFCompareEqualTo) font = f;
            else CFRelease(f);
            if (ps) CFRelease(ps);
        }
    }
    CFRelease(cfname);
    return cg_font_weighted(font, weight, size);
}

/* The next name in a CSS font-family list at p (quotes and spaces trimmed) into
 * name ("" when empty or too long); returns where the following name starts. */
static const char *cg_next_family(const char *p, const char *end, char *name, size_t cap) {
    const char *q = memchr(p, ',', (size_t)(end - p));
    if (!q) q = end;
    const char *a = p, *b = q;
    while (a < b && (*a == ' ' || *a == '"' || *a == '\'')) a++;
    while (b > a && (b[-1] == ' ' || b[-1] == '"' || b[-1] == '\'')) b--;
    size_t n = (size_t)(b - a);
    name[0] = 0;
    if (n > 0 && n < cap) { memcpy(name, a, n); name[n] = 0; }
    return q < end ? q + 1 : end;
}

/* families: a CSS font-family list ("Helvetica Neue, Helvetica, Arial,
 * sans-serif"). Cached by (list, weight, italic, size). Returns a +1
 * reference: the caller releases it (the cache keeps its own). */
static CTFontRef cg_font_lookup(const char *families, size_t flen, double weight, int italic, double size) {
    char key[600];
    if (flen > 512) flen = 512;
    int kn = snprintf(key, sizeof key, "%.*s|%g|%d|%.17g", (int)flen, families, weight, italic, size);
    uint64_t h = cg_fnv(key, (size_t)kn, 14695981039346656037ULL);
    pthread_mutex_lock(&g_font_lock);
    for (CGFontEntry *e = g_fonts[h % CG_FONT_BUCKETS]; e; e = e->next) {
        if (e->hash == h && strcmp(e->key, key) == 0) {
            CTFontRef f = (CTFontRef)CFRetain(e->font);
            pthread_mutex_unlock(&g_font_lock);
            return f;
        }
    }
    pthread_mutex_unlock(&g_font_lock);

    CTFontRef font = NULL;
    const char *p = families, *end = families + flen;
    while (p < end && !font) {
        char name[256];
        p = cg_next_family(p, end, name, sizeof name);
        if (name[0]) font = cg_font_one(name, weight, italic, size);
    }
    /* CSS falls back per character through the rest of the list: hand the
     * remaining families to CoreText as the font's cascade list (CoreText
     * tries them, in order, for characters the font lacks, before the system
     * cascade). */
    if (font && p < end) {
        CFMutableArrayRef cascade = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
        CFStringRef first = CTFontCopyPostScriptName(font);
        while (p < end && CFArrayGetCount(cascade) < 8) {
            char name[256];
            p = cg_next_family(p, end, name, sizeof name);
            if (!name[0] || cg_eq(name, "system-ui") || cg_eq(name, "-apple-system") || cg_eq(name, "ui-sans-serif")) continue;
            CTFontRef f = cg_font_one(name, weight, italic, size);
            if (!f) continue;
            CFStringRef ps = CTFontCopyPostScriptName(f);
            int dup = ps && first && CFStringCompare(ps, first, 0) == kCFCompareEqualTo;
            if (ps) CFRelease(ps);
            if (!dup) {
                CTFontDescriptorRef d = CTFontCopyFontDescriptor(f);
                if (d) { CFArrayAppendValue(cascade, d); CFRelease(d); }
            }
            CFRelease(f);
        }
        if (first) CFRelease(first);
        if (CFArrayGetCount(cascade) > 0) {
            const void *ak[] = {kCTFontCascadeListAttribute};
            const void *av[] = {cascade};
            CFDictionaryRef attrs = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes(attrs);
            CTFontRef f = CTFontCreateCopyWithAttributes(font, size, NULL, d);
            CFRelease(d); CFRelease(attrs);
            if (f) { CFRelease(font); font = f; }
        }
        CFRelease(cascade);
    }
    if (!font) font = cg_font_one("Helvetica", weight, italic, size);
    if (!font) font = CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);

    pthread_mutex_lock(&g_font_lock);
    /* Another thread may have raced us here; either result is equivalent. */
    if (g_font_count >= 4096) {
        /* A runaway set of sizes: drop everything. Canvases hold their own
         * retains, so nothing in use is freed. */
        for (int i = 0; i < CG_FONT_BUCKETS; i++) {
            CGFontEntry *e = g_fonts[i];
            while (e) { CGFontEntry *nx = e->next; CFRelease(e->font); free(e->key); free(e); e = nx; }
            g_fonts[i] = NULL;
        }
        g_font_count = 0;
    }
    CGFontEntry *e = calloc(1, sizeof *e);
    e->hash = h;
    e->key = strdup(key);
    e->font = (CTFontRef)CFRetain(font);
    e->next = g_fonts[h % CG_FONT_BUCKETS];
    g_fonts[h % CG_FONT_BUCKETS] = e;
    g_font_count++;
    pthread_mutex_unlock(&g_font_lock);
    return font;
}

static double cg_weight(WValue v) {
    if (v == W_NIL) return 400;
    if (cg_is_numeric(v)) return cg_num(v, "weight");
    char b[32];
    if (!cg_str(v, b, sizeof b)) cg_raise("Canvas: font weight must be a number or a String");
    if (cg_eq(b, "normal") || cg_eq(b, "regular") || cg_eq(b, "book")) return 400;
    if (cg_eq(b, "bold")) return 700;
    if (cg_eq(b, "bolder") || cg_eq(b, "heavy")) return 800;
    if (cg_eq(b, "lighter") || cg_eq(b, "light")) return 300;
    if (cg_eq(b, "thin")) return 100;
    if (cg_eq(b, "ultralight") || cg_eq(b, "extralight")) return 200;
    if (cg_eq(b, "medium")) return 500;
    if (cg_eq(b, "semibold") || cg_eq(b, "demibold")) return 600;
    if (cg_eq(b, "black")) return 900;
    char *end;
    double w = strtod(b, &end);
    if (end != b && *end == 0) return w;
    cg_raise("Canvas: unknown font weight \"%s\"", b);
}

static int cg_italic(WValue v) {
    if (v == W_NIL || v == W_FALSE) return 0;
    if (v == W_TRUE) return 1;
    char b[16];
    if (!cg_str(v, b, sizeof b)) return cg_truthy(v);
    return cg_eq(b, "italic") || cg_eq(b, "oblique");
}

/* w_cg_font_name(families, weight, style) -> PostScript name of the face the
 * list resolves to (after fallback). */
WValue w_cg_font_name(WValue famv, WValue weightv, WValue stylev) {
    char sso[6];
    const char *fs = "Helvetica";
    size_t fn = 9;
    if (famv != W_NIL && !cg_str_view(famv, sso, &fs, &fn)) cg_raise("Canvas.font_name: family must be a String");
    double weight = cg_weight(weightv);
    int italic = cg_italic(stylev);
    CTFontRef f = cg_font_lookup(fs, fn, weight, italic, 16.0);
    CFStringRef ps = CTFontCopyPostScriptName(f);
    CFRelease(f);
    WValue out = cg_wstring_from_cf(ps);
    if (ps) CFRelease(ps);
    return out;
}

/* w_cg_text_style(h, families, size, weight, style, spacing): the font and
 * letter spacing used by later text/text_measure calls. */
WValue w_cg_text_style(WValue hv, WValue famv, WValue sizev, WValue weightv, WValue stylev, WValue spacingv) {
    CGCanvas *c = cg_canvas(hv, "text_style");
    char sso[6];
    const char *fs = "Helvetica";
    size_t fn = 9;
    if (famv != W_NIL && !cg_str_view(famv, sso, &fs, &fn)) cg_raise("Canvas: font family must be a String");
    double size = cg_num_or(sizev, 16.0, "font size");
    if (!(size > 0)) cg_raise("Canvas: font size must be positive (got %g)", size);
    double weight = cg_weight(weightv);
    int italic = cg_italic(stylev);
    double spacing = cg_num_or(spacingv, 0.0, "letter spacing");
    CTFontRef f = cg_font_lookup(fs, fn, weight, italic, size);
    if (f != c->font) {
        if (c->font) CFRelease(c->font);
        c->font = f;
    } else {
        CFRelease(f);
    }
    c->font_size = size;
    c->spacing = spacing;
    return W_NIL;
}

/* A laid-out line for text in the canvas's current font, cached per canvas
 * in a 1,024-slot 4-way set-associative cache with lazy ink-bounds computation. */
static CGRect cg_line_ink(CGLineEntry *e) {
    if (!e->has_ink) {
        e->ink = CTLineGetBoundsWithOptions(e->line, kCTLineBoundsUseGlyphPathBounds);
        e->has_ink = 1;
    }
    return e->ink;
}

static CGLineEntry *cg_line(CGCanvas *c, WValue sv, const char *fn) {
    char sso[6];
    const char *s;
    size_t n;
    if (!cg_str_view(sv, sso, &s, &n)) cg_raise("Canvas.%s: text must be a String", fn);
    uint64_t h = cg_fnv(s, n, 14695981039346656037ULL);
    h = cg_fnv(&c->font, sizeof c->font, h);
    h = cg_fnv(&c->spacing, sizeof c->spacing, h);
    CGLineEntry *set = &c->lines[(h % CG_LINE_SETS) * CG_LINE_WAYS];
    CGLineEntry *victim = &set[0];
    for (int w = 0; w < CG_LINE_WAYS; w++) {
        CGLineEntry *cand = &set[w];
        if (cand->line && cand->hash == h && cand->font == c->font &&
            cand->spacing == c->spacing && cand->len == n && memcmp(cand->text, s, n) == 0) {
            cand->stamp = ++c->line_clock;
            return cand;
        }
        if (!cand->line) {
            victim = cand;
            break;
        }
        if (cand->stamp < victim->stamp) victim = cand;
    }
    CGLineEntry *e = victim;
    cg_line_entry_clear(e);
    CFStringRef str = cg_cfstring(s, n);
    CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(NULL, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attrs, kCTFontAttributeName, c->font);
    CFDictionarySetValue(attrs, kCTForegroundColorFromContextAttributeName, kCFBooleanTrue);
    if (c->spacing != 0) {
        CGFloat k = c->spacing;
        CFNumberRef kn = CFNumberCreate(NULL, kCFNumberCGFloatType, &k);
        CFDictionarySetValue(attrs, kCTKernAttributeName, kn);
        CFRelease(kn);
    }
    CFAttributedStringRef as = CFAttributedStringCreate(NULL, str, attrs);
    CTLineRef line = CTLineCreateWithAttributedString(as);
    CFRelease(as);
    CFRelease(attrs);
    CFRelease(str);
    if (!line) cg_raise("Canvas.%s: CoreText could not lay out the text", fn);
    e->hash = h;
    e->stamp = ++c->line_clock;
    e->has_ink = 0;
    e->font = (CTFontRef)CFRetain(c->font);
    e->spacing = c->spacing;
    e->text = malloc(n ? n : 1);
    memcpy(e->text, s, n);
    e->len = n;
    e->line = line;
    CGFloat asc = 0, desc = 0, lead = 0;
    e->width = CTLineGetTypographicBounds(line, &asc, &desc, &lead);
    e->ascent = asc;
    e->descent = desc;
    e->leading = lead;
    return e;
}

/* Baseline origin for an anchor ("start" | "middle" | "end") and a
 * dominant-baseline ("alphabetic" | "middle"/"central" | "hanging"/"top" |
 * "bottom"/"text-after-edge"/"ideographic"). */
static void cg_text_origin(CGLineEntry *e, WValue anchorv, WValue baselinev, double *x, double *y) {
    char anchor[16] = "start", base[24] = "alphabetic";
    if (anchorv != W_NIL) cg_str(anchorv, anchor, sizeof anchor);
    if (baselinev != W_NIL) cg_str(baselinev, base, sizeof base);
    if (cg_eq(anchor, "middle") || cg_eq(anchor, "center")) *x -= e->width / 2;
    else if (cg_eq(anchor, "end") || cg_eq(anchor, "right")) *x -= e->width;
    else if (!(cg_eq(anchor, "start") || cg_eq(anchor, "left"))) cg_raise("Canvas.text: anchor must be start, middle or end (got \"%s\")", anchor);
    if (cg_eq(base, "middle") || cg_eq(base, "central")) *y += (e->ascent - e->descent) / 2;
    else if (cg_eq(base, "hanging") || cg_eq(base, "top") || cg_eq(base, "text-before-edge")) *y += e->ascent;
    else if (cg_eq(base, "bottom") || cg_eq(base, "text-after-edge") || cg_eq(base, "ideographic")) *y -= e->descent;
    else if (!(cg_eq(base, "alphabetic") || cg_eq(base, "auto") || cg_eq(base, "baseline")))
        cg_raise("Canvas.text: unknown baseline \"%s\"", base);
}

static void cg_draw_line_at(CGCanvas *c, CGLineEntry *e, double x, double y, CGTextDrawingMode mode) {
    CGContextSetTextDrawingMode(c->ctx, mode);
    /* The CTM is y-down; flip the text matrix so glyphs stand upright. The
     * text matrix is not part of the gstate, so set it every time. */
    CGContextSetTextMatrix(c->ctx, CGAffineTransformMakeScale(1.0, -1.0));
    CGContextSetTextPosition(c->ctx, x, y);
    CTLineDraw(e->line, c->ctx);
}

/* w_cg_text(h, x, y, s, anchor, baseline, fill, fill_opacity, stroke,
 * stroke_opacity, opacity): draw one line with the current text style; the
 * stroke (width/join from set_line) goes under the fill, like SVG
 * paint-order="stroke". Returns the advance width. */
WValue w_cg_text(WValue hv, WValue xv, WValue yv, WValue sv, WValue anchorv, WValue baselinev,
                 WValue fillv, WValue fopv, WValue strokev, WValue sopv, WValue opv) {
    CGCanvas *c = cg_canvas(hv, "text");
    double x = cg_num(xv, "x"), y = cg_num(yv, "y");
    double fc[4], sc[4];
    int has_fill = cg_color(fillv, fc, "fill");
    int has_stroke = cg_color(strokev, sc, "stroke");
    double fop = cg_num_or(fopv, 1.0, "fill_opacity");
    double sop = cg_num_or(sopv, 1.0, "stroke_opacity");
    double op = cg_num_or(opv, 1.0, "opacity");
    CGLineEntry *e = cg_line(c, sv, "text");
    cg_text_origin(e, anchorv, baselinev, &x, &y);
    fc[3] *= fop;
    sc[3] *= sop;
    if (has_fill && fc[3] <= 0) has_fill = 0;
    if (has_stroke && (sc[3] <= 0 || cg_state(c)->line_width <= 0)) has_stroke = 0;
    if (op <= 0 || (!has_fill && !has_stroke) || e->len == 0) return w_float(e->width);
    int group = has_fill && has_stroke && op < 1;
    if (group) {
        CGRect ink = cg_line_ink(e);
        double m = cg_state(c)->line_width * fmax(1.0, cg_state(c)->miter) + 2;
        CGRect r = CGRectMake(x + ink.origin.x - m, y - (ink.origin.y + ink.size.height) - m,
                              ink.size.width + 2 * m, ink.size.height + 2 * m);
        cg_layer_begin_rect(c, op, r, 0);
    } else {
        fc[3] *= op;
        sc[3] *= op;
    }
    if (has_stroke) {
        cg_set_stroke(c, sc);
        cg_draw_line_at(c, e, x, y, kCGTextStroke);
    }
    if (has_fill) {
        cg_set_fill(c, fc);
        cg_draw_line_at(c, e, x, y, kCGTextFill);
    } else {
        CGContextSetTextDrawingMode(c->ctx, kCGTextFill);
    }
    if (group) cg_layer_end(c);
    return w_float(e->width);
}

/* w_cg_text_clip(h, x, y, s, anchor, baseline): intersect the clip with the
 * glyph outlines (for gradient- or image-filled text). Undo with restore. */
WValue w_cg_text_clip(WValue hv, WValue xv, WValue yv, WValue sv, WValue anchorv, WValue baselinev) {
    CGCanvas *c = cg_canvas(hv, "text_clip");
    double x = cg_num(xv, "x"), y = cg_num(yv, "y");
    CGLineEntry *e = cg_line(c, sv, "text_clip");
    cg_text_origin(e, anchorv, baselinev, &x, &y);
    if (e->len == 0) {
        CGContextClipToRect(c->ctx, CGRectZero);
        return W_NIL;
    }
    cg_draw_line_at(c, e, x, y, kCGTextClip);
    CGContextSetTextDrawingMode(c->ctx, kCGTextFill);
    return W_NIL;
}

/* [advance, ascent, descent, leading, ink_left, ink_top, ink_right,
 * ink_bottom] in user units; ink is relative to the baseline origin, y down
 * (ink_top is negative for glyphs above the baseline). */
WValue w_cg_text_measure(WValue hv, WValue sv) {
    CGCanvas *c = cg_canvas(hv, "measure_text");
    CGLineEntry *e = cg_line(c, sv, "measure_text");
    CGRect ink = cg_line_ink(e);
    double v[8] = {e->width, e->ascent, e->descent, e->leading,
                   ink.origin.x, -(ink.origin.y + ink.size.height),
                   ink.origin.x + ink.size.width, -ink.origin.y};
    if (CGRectIsNull(ink) || CGRectIsEmpty(ink)) v[4] = v[5] = v[6] = v[7] = 0;
    return cg_float_array(v, 8);
}

/* ======================================================================
   Images: decode-once cache
   ====================================================================== */

#define CG_MAX_IMAGES   16384
#define CG_MAX_VARIANTS 4
#define CG_MAX_SCALED   2

typedef struct {
    CGColorSpaceRef space;   /* canvas space this variant is for (retained) */
    int             bpc, is_float, manage;
    CGImageRef      image;
    size_t          bytes;   /* pixel bytes this variant owns (0 if shared) */
} CGImgVariant;

typedef struct CGImg {
    uint32_t        gen;
    char           *path;    /* NULL for canvas snapshots */
    int64_t         mtime_ns, fsize;
    CGImageRef      image;   /* decoded, raw-bitmap backed */
    size_t          w, h, bytes;
    int             nvar, next_var;
    CGImgVariant    var[CG_MAX_VARIANTS];
    /* copies resampled to the device size they are drawn at (cg_img_scaled) */
    CGImageRef      sc_img[CG_MAX_SCALED], sc_src[CG_MAX_SCALED];
    size_t          sc_w[CG_MAX_SCALED], sc_h[CG_MAX_SCALED], sc_bytes[CG_MAX_SCALED];
    int             sc_next;
    CGImageRef      sc_pend_src;     /* the last uncached draw size: cached when drawn again */
    size_t          sc_pend_w, sc_pend_h;
} CGImg;

static CGImg   *g_images[CG_MAX_IMAGES];
static uint32_t g_image_gen[CG_MAX_IMAGES];
static int      g_image_live;
static int      g_image_hi;       /* one past the highest slot ever used */
static size_t   g_image_bytes;
static size_t   g_image_budget = (size_t)4 << 30;   /* 4 GiB of decoded pixels */
static pthread_mutex_t g_img_lock = PTHREAD_MUTEX_INITIALIZER;

static void cg_img_free(CGImg *im) {
    for (int i = 0; i < im->nvar; i++) {
        if (im->var[i].image) CGImageRelease(im->var[i].image);
        if (im->var[i].space) CGColorSpaceRelease(im->var[i].space);
    }
    for (int i = 0; i < CG_MAX_SCALED; i++)
        if (im->sc_img[i]) CGImageRelease(im->sc_img[i]);
    if (im->image) CGImageRelease(im->image);
    free(im->path);
    free(im);
}

static size_t cg_img_total(CGImg *im) {
    size_t t = im->bytes;
    for (int i = 0; i < im->nvar; i++) t += im->var[i].bytes;
    for (int i = 0; i < CG_MAX_SCALED; i++) t += im->sc_bytes[i];
    return t;
}

/* Requires g_img_lock. */
static void cg_img_unregister(int slot) {
    CGImg *im = g_images[slot];
    __atomic_store_n(&g_images[slot], NULL, __ATOMIC_RELEASE);
    g_image_live--;
    g_image_bytes -= cg_img_total(im);
    cg_img_free(im);
}

static CGImg *cg_image(WValue hv, const char *fn) {
    if (!w_is_int(hv)) cg_raise("Canvas.%s: not an image handle", fn);
    int64_t h = w_as_int(hv);
    int64_t slot = (h & 0xFFFF) - 1;
    uint32_t gen = (uint32_t)(h >> 16);
    if (slot < 0 || slot >= CG_MAX_IMAGES) cg_raise("Canvas.%s: not an image handle", fn);
    CGImg *im = __atomic_load_n(&g_images[slot], __ATOMIC_ACQUIRE);
    if (!im || im->gen != gen) cg_raise("Canvas.%s: the image was released", fn);
    return im;
}

/* Render `src` into a premultiplied RGBA bitmap (bpc/float as asked) in
 * `space`, returning a CGImage that owns raw pixels: drawing it never
 * decodes again. */
static CGImageRef cg_render_bitmap(CGImageRef src, CGColorSpaceRef space, int bpc, int is_float, size_t *bytes_out) {
    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    if (bpc == 8) info |= kCGBitmapByteOrder32Big;
    else if (bpc == 16) info |= kCGBitmapByteOrder16Little | (is_float ? kCGBitmapFloatComponents : 0);
    else info |= kCGBitmapByteOrder32Little | kCGBitmapFloatComponents;
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, (size_t)bpc, 0, space, info);
    if (!ctx) return NULL;
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), src);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    if (bytes_out) *bytes_out = CGBitmapContextGetBytesPerRow(ctx) * h;
    CGContextRelease(ctx);
    return out;
}

static WValue cg_img_register(CGImg *im) {
    pthread_mutex_lock(&g_img_lock);
    int slot = -1;
    for (int i = 0; i < CG_MAX_IMAGES; i++) {
        if (!g_images[i]) { slot = i; break; }
    }
    if (slot >= g_image_hi) g_image_hi = slot + 1;
    if (slot < 0) {
        pthread_mutex_unlock(&g_img_lock);
        cg_img_free(im);
        cg_raise("Canvas.image: %d images are loaded; release some", CG_MAX_IMAGES);
    }
    uint32_t gen = ++g_image_gen[slot];
    if (gen > 0x7FFFFFFF) gen = g_image_gen[slot] = 1;
    im->gen = gen;
    __atomic_store_n(&g_images[slot], im, __ATOMIC_RELEASE);
    g_image_live++;
    g_image_bytes += cg_img_total(im);
    /* Over budget: drop least-recently-loaded path images (not this one).
     * Their handles go stale and raise if used again. */
    for (int i = 0; i < g_image_hi && g_image_bytes > g_image_budget; i++) {
        if (i != slot && g_images[i] && g_images[i]->path) cg_img_unregister(i);
    }
    pthread_mutex_unlock(&g_img_lock);
    return w_int(((int64_t)gen << 16) | (int64_t)(slot + 1));
}

/* w_cg_image_load(path) -> handle. Decodes once (PNG, JPEG, HEIC, TIFF, GIF,
 * OpenEXR, … — anything ImageIO reads); later loads of the same unchanged file
 * return the same handle. */
WValue w_cg_image_load(WValue pathv) {
    char path[4096];
    if (!cg_str(pathv, path, sizeof path)) cg_raise("Canvas.image: path must be a String");
    struct stat st;
    if (stat(path, &st) != 0) cg_raise("Canvas.image: cannot read %s", path);
    int64_t mt = (int64_t)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
    pthread_mutex_lock(&g_img_lock);
    for (int i = 0; i < g_image_hi; i++) {
        CGImg *im = g_images[i];
        if (im && im->path && strcmp(im->path, path) == 0) {
            if (im->mtime_ns == mt && im->fsize == (int64_t)st.st_size) {
                WValue hv = w_int(((int64_t)im->gen << 16) | (int64_t)(i + 1));
                pthread_mutex_unlock(&g_img_lock);
                return hv;
            }
            cg_img_unregister(i);   /* the file changed: decode again */
            break;
        }
    }
    pthread_mutex_unlock(&g_img_lock);

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageSourceRef src = url ? CGImageSourceCreateWithURL(url, NULL) : NULL;
    if (url) CFRelease(url);
    if (!src) cg_raise("Canvas.image: cannot open %s", path);
    CGImageRef raw = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!raw) cg_raise("Canvas.image: cannot decode %s", path);
    CGColorSpaceRef cs = CGImageGetColorSpace(raw);
    CGColorSpaceRef target = (cs && CGColorSpaceGetModel(cs) == kCGColorSpaceModelRGB) ? CGColorSpaceRetain(cs)
                                                                                      : CGColorSpaceRetain(cg_srgb());
    size_t sbpc = CGImageGetBitsPerComponent(raw);
    int fl = (CGImageGetBitmapInfo(raw) & kCGBitmapFloatComponents) != 0;
    int bpc = fl ? 32 : (sbpc > 8 ? 16 : 8);
    size_t bytes = 0;
    CGImageRef img = cg_render_bitmap(raw, target, bpc, fl, &bytes);
    if (!img && bpc != 8) img = cg_render_bitmap(raw, target, 8, 0, &bytes);
    CGColorSpaceRelease(target);
    CGImageRelease(raw);
    if (!img) cg_raise("Canvas.image: cannot convert %s to an RGBA bitmap", path);
    CGImg *im = calloc(1, sizeof *im);
    im->path = strdup(path);
    im->mtime_ns = mt;
    im->fsize = (int64_t)st.st_size;
    im->image = img;
    im->w = CGImageGetWidth(img);
    im->h = CGImageGetHeight(img);
    im->bytes = bytes;
    return cg_img_register(im);
}

/* w_cg_image_from_canvas(h) -> handle: a snapshot of the canvas pixels, to
 * draw onto other canvases (pre-rendered backgrounds, layers). */
WValue w_cg_image_from_canvas(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "snapshot");
    CGImageRef img = CGBitmapContextCreateImage(c->ctx);
    if (!img) cg_raise("Canvas.snapshot: CoreGraphics could not copy the canvas");
    CGImg *im = calloc(1, sizeof *im);
    im->image = img;
    im->w = c->pw;
    im->h = c->ph;
    im->bytes = c->stride * c->ph;
    return cg_img_register(im);
}

static void cg_free_pixels(void *info, const void *data, size_t size) {
    (void)info; (void)size;
    free((void *)data);
}

/* w_cg_image_from_rgba(buf, w, h) -> handle: an image from straight
 * (unpremultiplied) 8-bit RGBA pixels in sRGB, row-major with no padding (a
 * ByteArray of w * h * 4, or a data-pointer Integer to as many bytes). The
 * pixels are copied (premultiplied, the layout every other image uses), so
 * the buffer may be reused or freed at once. For decoders written in
 * Tungsten: nothing touches the disk and ImageIO is not involved. */
static WValue cg_image_adopt_rgba(uint8_t *px, size_t w, size_t h, int opaque);

/* w_cg_image_from_premultiplied(buf, w, h, opaque) -> handle: like
 * image_from_rgba for pixels a decoder already premultiplied (RGBA8, the
 * canvas's own format): one memcpy, no per-pixel work. opaque: every alpha
 * is 255 (stored as RGBX; drawn without blending). */
WValue w_cg_image_from_premultiplied(WValue bufv, WValue wv, WValue hv, WValue opaquev) {
    double dw = cg_num(wv, "width"), dh = cg_num(hv, "height");
    if (!(dw >= 1 && dh >= 1 && dw <= 1048576 && dh <= 1048576) || dw * dh > 4.0e9 / 4)
        cg_raise("Canvas.image_from_premultiplied: bad size %gx%g", dw, dh);
    size_t w = (size_t)dw, h = (size_t)dh, n = w * h * 4;
    const uint8_t *src = NULL;
    if (w_is_int(bufv)) {
        src = (const uint8_t *)(uintptr_t)w_as_int(bufv);
    } else if (w_is_array(bufv)) {
        WArray *a = w_as_array(bufv);
        if (a->ebits != 8) cg_raise("Canvas.image_from_premultiplied: pixels must be a ByteArray (u8[])");
        if ((size_t)a->size < n)
            cg_raise("Canvas.image_from_premultiplied: buffer has %lld bytes, need %zu", (long long)a->size, n);
        src = (const uint8_t *)a->slots + (size_t)a->start;
    }
    if (!src) cg_raise("Canvas.image_from_premultiplied: pixels must be a ByteArray or data pointer Integer");
    uint8_t *px = malloc(n);
    if (!px) cg_raise("Canvas.image_from_premultiplied: out of memory");
    memcpy(px, src, n);
    return cg_image_adopt_rgba(px, w, h, cg_truthy(opaquev));
}

WValue w_cg_image_from_rgba(WValue bufv, WValue wv, WValue hv) {
    double dw = cg_num(wv, "width"), dh = cg_num(hv, "height");
    if (!(dw >= 1 && dh >= 1 && dw <= 1048576 && dh <= 1048576) || dw * dh > 4.0e9 / 4)
        cg_raise("Canvas.image_from_rgba: bad size %gx%g", dw, dh);
    size_t w = (size_t)dw, h = (size_t)dh, n = w * h * 4;
    const uint8_t *src = NULL;
    if (w_is_int(bufv)) {
        src = (const uint8_t *)(uintptr_t)w_as_int(bufv);
        if (!src) cg_raise("Canvas.image_from_rgba: null data pointer");
    } else if (w_is_array(bufv)) {
        WArray *a = w_as_array(bufv);
        if (a->ebits != 8) cg_raise("Canvas.image_from_rgba: pixels must be a ByteArray (u8[])");
        if ((size_t)a->size < n)
            cg_raise("Canvas.image_from_rgba: buffer has %lld bytes, need %zu", (long long)a->size, n);
        src = (const uint8_t *)a->slots + (size_t)a->start;
    } else {
        cg_raise("Canvas.image_from_rgba: pixels must be a ByteArray or data pointer Integer");
    }
    uint8_t *px = malloc(n);
    if (!px) cg_raise("Canvas.image_from_rgba: out of memory");
    /* Opaque images (every alpha 255: JPEG, video, most photos) are a plain
     * copy, stored as RGBX so CoreGraphics composites them without blending;
     * otherwise a branch-free premultiply the compiler vectorises:
     * round(c * a / 255) = (t + (t >> 8)) >> 8 with t = c * a + 128, exact
     * for a = 255 too. */
    int opaque = 1;
    for (size_t i = 3; i < n; i += 4) {
        if (src[i] != 255) { opaque = 0; break; }
    }
    if (opaque) {
        memcpy(px, src, n);
    } else {
        for (size_t i = 0; i < n; i += 4) {
            unsigned a = src[i + 3], t;
            t = src[i] * a + 128;     px[i]     = (uint8_t)((t + (t >> 8)) >> 8);
            t = src[i + 1] * a + 128; px[i + 1] = (uint8_t)((t + (t >> 8)) >> 8);
            t = src[i + 2] * a + 128; px[i + 2] = (uint8_t)((t + (t >> 8)) >> 8);
            px[i + 3] = (uint8_t)a;
        }
    }
    return cg_image_adopt_rgba(px, w, h, opaque);
}

/* An image over px (w * h RGBA8 premultiplied, malloc'd: the image frees it). */
static WValue cg_image_adopt_rgba(uint8_t *px, size_t w, size_t h, int opaque) {
    size_t n = w * h * 4;
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, px, n, cg_free_pixels);
    if (!prov) { free(px); cg_raise("Canvas.image_from_rgba: CGDataProviderCreateWithData failed"); }
    CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, cg_srgb(),
                                   (CGBitmapInfo)(opaque ? kCGImageAlphaNoneSkipLast : kCGImageAlphaPremultipliedLast) | kCGBitmapByteOrder32Big,
                                   prov, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(prov);
    if (!img) cg_raise("Canvas.image_from_rgba: CGImageCreate failed");
    CGImg *im = calloc(1, sizeof *im);
    im->image = img;
    im->w = w;
    im->h = h;
    im->bytes = n;
    return cg_img_register(im);
}

WValue w_cg_image_info(WValue imv, WValue keyv) {
    CGImg *im = cg_image(imv, "image_info");
    char key[32];
    cg_str(keyv, key, sizeof key);
    if (cg_eq(key, "width")) return w_int((int64_t)im->w);
    if (cg_eq(key, "height")) return w_int((int64_t)im->h);
    if (cg_eq(key, "bytes")) return w_int((int64_t)cg_img_total(im));
    if (cg_eq(key, "bits")) return w_int((int64_t)CGImageGetBitsPerComponent(im->image));
    if (cg_eq(key, "path")) return im->path ? w_string(im->path) : W_NIL;
    if (cg_eq(key, "space")) {
        const char *sel = cg_space_selector(CGImageGetColorSpace(im->image));
        if (sel) return w_string(sel);
        CFStringRef nm = CGColorSpaceCopyName(CGImageGetColorSpace(im->image));
        WValue out = nm ? cg_wstring_from_cf(nm) : W_NIL;
        if (nm) CFRelease(nm);
        return out;
    }
    cg_raise("Canvas.image_info: unknown key \"%s\"", key);
}

/* The image prepared for drawing into canvas c: same colour space (assigned
 * or colour-matched once, per c->manage), cached on the image. */
static CGImageRef cg_img_for(CGImg *im, CGCanvas *c) {
    CGColorSpaceRef ics = CGImageGetColorSpace(im->image);
    if (ics && CFEqual(ics, c->space)) return im->image;
    pthread_mutex_lock(&g_img_lock);
    for (int i = 0; i < im->nvar; i++) {
        CGImgVariant *v = &im->var[i];
        if (v->manage == c->manage && v->bpc == c->bpc && v->is_float == c->is_float && CFEqual(v->space, c->space)) {
            CGImageRef r = v->image;
            pthread_mutex_unlock(&g_img_lock);
            return r;
        }
    }
    pthread_mutex_unlock(&g_img_lock);
    CGImageRef made;
    size_t bytes = 0;
    if (!c->manage) {
        /* Reinterpret the code values in the canvas space: no pixel copy. */
        made = CGImageCreateCopyWithColorSpace(im->image, c->space);
        if (!made) made = cg_render_bitmap(im->image, c->space, c->bpc, c->is_float, &bytes);
    } else {
        made = cg_render_bitmap(im->image, c->space, c->bpc, c->is_float, &bytes);
    }
    if (!made) return im->image;
    pthread_mutex_lock(&g_img_lock);
    int slot = im->nvar < CG_MAX_VARIANTS ? im->nvar++ : (im->next_var++ % CG_MAX_VARIANTS);
    CGImgVariant *v = &im->var[slot];
    if (v->image) {
        g_image_bytes -= v->bytes;
        CGImageRelease(v->image);
        CGColorSpaceRelease(v->space);
    }
    v->image = made;
    v->space = CGColorSpaceRetain(c->space);
    v->bpc = c->bpc;
    v->is_float = c->is_float;
    v->manage = c->manage;
    v->bytes = bytes;
    g_image_bytes += bytes;
    pthread_mutex_unlock(&g_img_lock);
    return made;
}

/* ---- quality "exact": a true sub-pixel resample (studio camera moves) -------------------------------
 * CGContextDrawImage snaps an axis-aligned image draw to the device pixel grid (measured 2026-11-01:
 * a draw moved by 0.16 px a frame stays put for five frames, then jumps 0.8 px; at unit scale it moves
 * in ~0.37 px steps), so a slow push or pan steps and a sub-pixel jitter turns into whole-pixel jumps.
 * "exact" resamples in C instead: separable Keys cubic (a = -0.5, PIL's BICUBIC), widened by the
 * downscale factor (so a reduction is antialiased), at the exact fractional position the current CTM
 * gives, composited source-over (premultiplied) at the draw's opacity. It applies to an 8-bit canvas,
 * a stretched draw ("fill") of the whole image and an axis-aligned CTM (translate/scale/flip); anything
 * else falls back to CoreGraphics. Clip paths and blend modes are not applied on this path. */
#define CG_EXACT_CACHE 8
typedef struct { const CGImg *im; uint32_t gen; CGImageRef key; CFDataRef data; size_t w, h, stride; } CGExactSrc;
static CGExactSrc g_exact_src[CG_EXACT_CACHE];
static int g_exact_next;
static pthread_mutex_t g_exact_lock = PTHREAD_MUTEX_INITIALIZER;

/* RGBA8 premultiplied pixels (R,G,B,A in memory, as the 8-bit canvas) of img, cached for recent images. */
static int cg_exact_source(const CGImg *im, CGImageRef img, CGCanvas *c, const uint8_t **px, size_t *stride) {
    pthread_mutex_lock(&g_exact_lock);
    for (int i = 0; i < CG_EXACT_CACHE; i++) {
        CGExactSrc *e = &g_exact_src[i];
        if (e->data && e->im == im && e->gen == im->gen && e->key == img) {
            *px = CFDataGetBytePtr(e->data);
            *stride = e->stride;
            pthread_mutex_unlock(&g_exact_lock);
            return 1;
        }
    }
    pthread_mutex_unlock(&g_exact_lock);
    CGImageRef use = img, made = NULL;
    CGBitmapInfo bi = CGImageGetBitmapInfo(img);
    int ok = CGImageGetBitsPerComponent(img) == 8 && CGImageGetBitsPerPixel(img) == 32 &&
             CGImageGetAlphaInfo(img) == kCGImageAlphaPremultipliedLast &&
             ((bi & kCGBitmapByteOrderMask) == kCGBitmapByteOrder32Big || (bi & kCGBitmapByteOrderMask) == kCGBitmapByteOrderDefault);
    if (!ok) {
        made = cg_render_bitmap(img, c->space, 8, 0, NULL);
        if (!made) return 0;
        use = made;
    }
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(use));
    size_t st = CGImageGetBytesPerRow(use);
    if (made) CGImageRelease(made);
    if (!data) return 0;
    pthread_mutex_lock(&g_exact_lock);
    CGExactSrc *e = &g_exact_src[g_exact_next];
    g_exact_next = (g_exact_next + 1) % CG_EXACT_CACHE;
    if (e->data) CFRelease(e->data);
    e->im = im; e->gen = im->gen; e->key = img; e->data = data;
    e->w = CGImageGetWidth(img); e->h = CGImageGetHeight(img); e->stride = st;
    *px = CFDataGetBytePtr(data);
    *stride = st;
    pthread_mutex_unlock(&g_exact_lock);
    return 1;
}

static double cg_keys(double t) {          /* Keys cubic convolution, a = -0.5 */
    t = fabs(t);
    if (t < 1) return (1.5 * t - 2.5) * t * t + 1;
    if (t < 2) return ((-0.5 * t + 2.5) * t - 4) * t + 2;
    return 0;
}

/* Weights for n outputs: output o samples the source (length len) at pos0 + o * step (pixel-centre units).
 * Fills first[o], count[o] and w[o * maxt ..]; returns maxt (taps per output). */
static int cg_exact_weights(int n, double pos0, double step, int len, int **first_out, int **count_out, float **w_out) {
    double f = fabs(step) > 1 ? fabs(step) : 1;   /* widen the kernel when reducing */
    double sup = 2 * f;
    int maxt = (int)ceil(2 * sup) + 2;
    int *first = malloc(sizeof(int) * (size_t)n), *count = malloc(sizeof(int) * (size_t)n);
    float *w = malloc(sizeof(float) * (size_t)n * (size_t)maxt);
    if (!first || !count || !w) { free(first); free(count); free(w); return 0; }
    for (int o = 0; o < n; o++) {
        double p = pos0 + o * step;
        int i0 = (int)ceil(p - sup), i1 = (int)floor(p + sup);
        if (i1 - i0 + 1 > maxt) i1 = i0 + maxt - 1;
        double sum = 0;
        int k = 0;
        for (int i = i0; i <= i1; i++, k++) {
            double v = cg_keys((i - p) / f);
            w[o * maxt + k] = (float)v;
            sum += v;
        }
        if (sum != 0) for (int j = 0; j < k; j++) w[o * maxt + j] = (float)(w[o * maxt + j] / sum);
        first[o] = i0;
        count[o] = k;
        (void)len;
    }
    *first_out = first; *count_out = count; *w_out = w;
    return maxt;
}

static inline int cg_clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

typedef struct {
    const uint8_t *src;
    uint8_t *dst;
    size_t sst, dst_stride;
    int iw, ih, q0, r0, nq, nr, ht, vt;
    const int *hf, *hc, *vf, *vc;
    const float *hw, *vw;
    float opf;
} CGExactJob;

static _Thread_local float *g_exact_tls;
static _Thread_local size_t g_exact_tls_cap;

static void cg_exact_band(void *ctx, size_t bi) {
    const CGExactJob *j = (const CGExactJob *)ctx;
    int ro0 = (int)(bi * 16), ro1 = ro0 + 16;
    if (ro0 >= j->nr) return;
    if (ro1 > j->nr) ro1 = j->nr;
    int nq = j->nq, ht = j->ht, vt = j->vt, maxx = j->iw - 1, maxy = j->ih - 1;
    int sr0 = j->ih, sr1 = -1;
    for (int o = ro0; o < ro1; o++) {
        int a = cg_clampi(j->vf[o], 0, maxy), b = cg_clampi(j->vf[o] + j->vc[o] - 1, 0, maxy);
        if (a < sr0) sr0 = a;
        if (b > sr1) sr1 = b;
    }
    int nsr = sr1 - sr0 + 1;
    if (nsr <= 0) return;
    int sx0 = j->iw, sx1 = -1;
    for (int o = 0; o < nq; o++) {
        int a = cg_clampi(j->hf[o], 0, maxx), b = cg_clampi(j->hf[o] + j->hc[o] - 1, 0, maxx);
        if (a < sx0) sx0 = a;
        if (b > sx1) sx1 = b;
    }
    int nsx = sx1 >= sx0 ? sx1 - sx0 + 1 : 0;
    size_t need = (size_t)(nsr + 1) * (size_t)nq * 4 + (size_t)(nsx + 4) * 4;
    float *buf = g_exact_tls;
    if (need > g_exact_tls_cap) {
        float *nb = realloc(buf, need * sizeof(float));
        if (!nb) return;
        g_exact_tls = buf = nb;
        g_exact_tls_cap = need;
    }
    float *tmp = buf;
    float *acc = buf + (size_t)nsr * (size_t)nq * 4;
    float *srow = acc + (size_t)nq * 4;
    for (int y = 0; y < nsr; y++) {
        const uint8_t *row = j->src + (size_t)(sr0 + y) * j->sst;
        float *out = tmp + (size_t)y * (size_t)nq * 4;
#if defined(__aarch64__)
        int xi = 0;
        const uint8_t *sp0 = row + (size_t)sx0 * 4;
        for (; xi + 4 <= nsx; xi += 4) {
            uint8x16_t u = vld1q_u8(sp0 + (size_t)xi * 4);
            uint16x8_t lo = vmovl_u8(vget_low_u8(u)), hi = vmovl_u8(vget_high_u8(u));
            vst1q_f32(srow + (size_t)xi * 4,      vcvtq_f32_u32(vmovl_u16(vget_low_u16(lo))));
            vst1q_f32(srow + (size_t)xi * 4 + 4,  vcvtq_f32_u32(vmovl_u16(vget_high_u16(lo))));
            vst1q_f32(srow + (size_t)xi * 4 + 8,  vcvtq_f32_u32(vmovl_u16(vget_low_u16(hi))));
            vst1q_f32(srow + (size_t)xi * 4 + 12, vcvtq_f32_u32(vmovl_u16(vget_high_u16(hi))));
        }
        for (; xi < nsx; xi++) {
            const uint8_t *p = sp0 + (size_t)xi * 4;
            float *d = srow + (size_t)xi * 4;
            d[0] = p[0]; d[1] = p[1]; d[2] = p[2]; d[3] = p[3];
        }
        for (int o = 0; o < nq; o++) {
            const float *w = j->hw + (size_t)o * (size_t)ht;
            int f0 = j->hf[o], n = j->hc[o];
            float32x4_t av = vdupq_n_f32(0.0f);
            if (f0 >= 0 && f0 + n - 1 <= maxx) {
                const float *sf = srow + (size_t)(f0 - sx0) * 4;
                for (int k = 0; k < n; k++, sf += 4) av = vmlaq_n_f32(av, vld1q_f32(sf), w[k]);
            } else {
                for (int k = 0; k < n; k++) {
                    const float *sf = srow + (size_t)(cg_clampi(f0 + k, 0, maxx) - sx0) * 4;
                    av = vmlaq_n_f32(av, vld1q_f32(sf), w[k]);
                }
            }
            vst1q_f32(out + o * 4, av);
        }
#else
        for (int o = 0; o < nq; o++) {
            const float *w = j->hw + (size_t)o * (size_t)ht;
            int f0 = j->hf[o], n = j->hc[o];
            float a0 = 0, a1 = 0, a2 = 0, a3 = 0;
            if (f0 >= 0 && f0 + n - 1 <= maxx) {
                const uint8_t *s = row + (size_t)f0 * 4;
                for (int k = 0; k < n; k++, s += 4) {
                    float wk = w[k];
                    a0 += wk * s[0]; a1 += wk * s[1]; a2 += wk * s[2]; a3 += wk * s[3];
                }
            } else {
                for (int k = 0; k < n; k++) {
                    const uint8_t *s = row + (size_t)cg_clampi(f0 + k, 0, maxx) * 4;
                    float wk = w[k];
                    a0 += wk * s[0]; a1 += wk * s[1]; a2 += wk * s[2]; a3 += wk * s[3];
                }
            }
            out[o * 4] = a0; out[o * 4 + 1] = a1; out[o * 4 + 2] = a2; out[o * 4 + 3] = a3;
        }
#endif
    }
    float opf = j->opf;
    int n4 = nq * 4;
    for (int o = ro0; o < ro1; o++) {
        const float *w = j->vw + (size_t)o * (size_t)vt;
        int f0 = j->vf[o], n = j->vc[o];
        if (n <= 0) {
            memset(acc, 0, (size_t)n4 * sizeof(float));
        } else {
            int sy0 = cg_clampi(f0, 0, maxy) - sr0;
            const float *tr0 = tmp + (size_t)sy0 * (size_t)n4;
            float w0 = w[0];
#if defined(__aarch64__)
            for (int c = 0; c < n4; c += 4) vst1q_f32(acc + c, vmulq_n_f32(vld1q_f32(tr0 + c), w0));
            for (int k = 1; k < n; k++) {
                int sy = cg_clampi(f0 + k, 0, maxy) - sr0;
                const float *tr = tmp + (size_t)sy * (size_t)n4;
                float wk = w[k];
                for (int c = 0; c < n4; c += 4) {
                    vst1q_f32(acc + c, vmlaq_n_f32(vld1q_f32(acc + c), vld1q_f32(tr + c), wk));
                }
            }
#else
            for (int c = 0; c < n4; c++) acc[c] = w0 * tr0[c];
            for (int k = 1; k < n; k++) {
                int sy = cg_clampi(f0 + k, 0, maxy) - sr0;
                const float *tr = tmp + (size_t)sy * (size_t)n4;
                float wk = w[k];
                for (int c = 0; c < n4; c++) acc[c] += wk * tr[c];
            }
#endif
        }
        uint8_t *drow = j->dst + (size_t)(j->r0 + o) * j->dst_stride + (size_t)j->q0 * 4;
        int q = 0;
#if defined(__aarch64__)
        float32x4_t vzero = vdupq_n_f32(0.0f), vmax8 = vdupq_n_f32(255.0f), vhalf = vdupq_n_f32(0.5f);
        uint32x4_t valpha_ff = vdupq_n_u32(0xFF000000u);
        for (; q + 4 <= nq; q += 4) {
            float32x4_t p0 = vmulq_n_f32(vld1q_f32(acc + q * 4), opf);
            float32x4_t p1 = vmulq_n_f32(vld1q_f32(acc + q * 4 + 4), opf);
            float32x4_t p2 = vmulq_n_f32(vld1q_f32(acc + q * 4 + 8), opf);
            float32x4_t p3 = vmulq_n_f32(vld1q_f32(acc + q * 4 + 12), opf);
            if (vgetq_lane_f32(p0, 3) >= 254.999f && vgetq_lane_f32(p1, 3) >= 254.999f &&
                vgetq_lane_f32(p2, 3) >= 254.999f && vgetq_lane_f32(p3, 3) >= 254.999f) {
                uint16x8_t u01 = vcombine_u16(
                    vmovn_u32(vcvtq_u32_f32(vaddq_f32(vminq_f32(vmaxq_f32(p0, vzero), vmax8), vhalf))),
                    vmovn_u32(vcvtq_u32_f32(vaddq_f32(vminq_f32(vmaxq_f32(p1, vzero), vmax8), vhalf))));
                uint16x8_t u23 = vcombine_u16(
                    vmovn_u32(vcvtq_u32_f32(vaddq_f32(vminq_f32(vmaxq_f32(p2, vzero), vmax8), vhalf))),
                    vmovn_u32(vcvtq_u32_f32(vaddq_f32(vminq_f32(vmaxq_f32(p3, vzero), vmax8), vhalf))));
                uint8x16_t b8 = vcombine_u8(vmovn_u16(u01), vmovn_u16(u23));
                vst1q_u8(drow + q * 4, vreinterpretq_u8_u32(vorrq_u32(vreinterpretq_u32_u8(b8), valpha_ff)));
                continue;
            }
            for (int sub = 0; sub < 4; sub++) {
                int qq = q + sub;
                float sa = acc[qq * 4 + 3] * opf;
                if (sa > 255.0f) sa = 255.0f;
                if (sa < 0.0f) sa = 0.0f;
                if (sa >= 254.999f) {
                    for (int ch = 0; ch < 3; ch++) {
                        float sv = acc[qq * 4 + ch] * opf;
                        if (sv < 0.0f) sv = 0.0f;
                        if (sv > 255.0f) sv = 255.0f;
                        drow[qq * 4 + ch] = (uint8_t)(int)(sv + 0.5f);
                    }
                    drow[qq * 4 + 3] = 255;
                } else {
                    float keep = 1.0f - sa / 255.0f;
                    for (int ch = 0; ch < 4; ch++) {
                        float sv = ch == 3 ? sa : acc[qq * 4 + ch] * opf;
                        if (sv < 0.0f) sv = 0.0f;
                        if (sv > sa && ch != 3) sv = sa;
                        float v = sv + drow[qq * 4 + ch] * keep;
                        int iv = (int)(v + 0.5f);
                        drow[qq * 4 + ch] = (uint8_t)(iv > 255 ? 255 : iv < 0 ? 0 : iv);
                    }
                }
            }
        }
#endif
        for (; q < nq; q++) {
            float sa = acc[q * 4 + 3] * opf;
            if (sa > 255.0f) sa = 255.0f;
            if (sa < 0.0f) sa = 0.0f;
            if (sa >= 254.999f) {
                for (int ch = 0; ch < 3; ch++) {
                    float sv = acc[q * 4 + ch] * opf;
                    if (sv < 0.0f) sv = 0.0f;
                    if (sv > 255.0f) sv = 255.0f;
                    drow[q * 4 + ch] = (uint8_t)(int)(sv + 0.5f);
                }
                drow[q * 4 + 3] = 255;
            } else {
                float keep = 1.0f - sa / 255.0f;
                for (int ch = 0; ch < 4; ch++) {
                    float sv = ch == 3 ? sa : acc[q * 4 + ch] * opf;
                    if (sv < 0.0f) sv = 0.0f;
                    if (sv > sa && ch != 3) sv = sa;              /* premultiplied: colour <= alpha */
                    float v = sv + drow[q * 4 + ch] * keep;
                    int iv = (int)(v + 0.5f);
                    drow[q * 4 + ch] = (uint8_t)(iv > 255 ? 255 : iv < 0 ? 0 : iv);
                }
            }
        }
    }
}

/* Draw the whole image stretched over the user rect (dx, dy, dw, dh) (y down, as w_cg_image_draw) at
 * opacity op. Returns 1 when drawn, 0 to fall back to CoreGraphics. */
static int cg_image_draw_exact(CGCanvas *c, CGImg *im, CGImageRef img, double dx, double dy, double dw, double dh, double op) {
    if (c->bpc != 8 || c->is_float || !c->data) return 0;
    CGAffineTransform m = CGContextGetCTM(c->ctx);          /* user -> device (y up, origin bottom-left) */
    if (fabs(m.b) > 1e-9 || fabs(m.c) > 1e-9 || m.a == 0 || m.d == 0) return 0;
    size_t iw = CGImageGetWidth(img), ih = CGImageGetHeight(img);
    if (iw == 0 || ih == 0) return 0;
    const uint8_t *src;
    size_t sst;
    if (!cg_exact_source(im, img, c, &src, &sst)) return 0;
    int W = (int)c->pw, H = (int)c->ph;
    /* device column q (centre q + 0.5) -> user x -> image x; memory row r (device y = H - r - 0.5) -> user y -> image y */
    double ux0 = (0.5 - m.tx) / m.a, uxs = 1.0 / m.a;              /* user x of column q = ux0 + q * uxs */
    double uy0 = ((H - 0.5) - m.ty) / m.d, uys = -1.0 / m.d;       /* user y of row r = uy0 + r * uys */
    double sxs = (double)iw / dw, sys = (double)ih / dh;
    double px0 = (ux0 - dx) * sxs - 0.5, pxs = uxs * sxs;          /* image sample x of column q */
    double py0 = (uy0 - dy) * sys - 0.5, pys = uys * sys;          /* image sample y of row r */
    /* the device columns / rows the image covers */
    double qa = (dx - ux0) / uxs, qb = (dx + dw - ux0) / uxs;
    double ra = (dy - uy0) / uys, rb = (dy + dh - uy0) / uys;
    int q0 = cg_clampi((int)floor(fmin(qa, qb) + 0.5), 0, W), q1 = cg_clampi((int)ceil(fmax(qa, qb) - 0.5), 0, W);
    int r0 = cg_clampi((int)floor(fmin(ra, rb) + 0.5), 0, H), r1 = cg_clampi((int)ceil(fmax(ra, rb) - 0.5), 0, H);
    int nq = q1 - q0, nr = r1 - r0;
    if (nq <= 0 || nr <= 0) return 1;
    /* Exact 1:1 integer-aligned copy/blend fast path (avoids 6x6 Keys cubic convolution). */
    if (op >= 0.999999 && fabs(pxs - 1.0) < 1e-9 && fabs(pys - 1.0) < 1e-9 &&
        fabs((px0 + q0 * pxs) - floor(px0 + q0 * pxs + 0.5)) < 1e-6 &&
        fabs((py0 + r0 * pys) - floor(py0 + r0 * pys + 0.5)) < 1e-6) {
        int sx_start = (int)floor(px0 + q0 * pxs + 0.5);
        int sy_start = (int)floor(py0 + r0 * pys + 0.5);
        if (sx_start >= 0 && sy_start >= 0 && sx_start + nq <= (int)iw && sy_start + nr <= (int)ih) {
            CGImageAlphaInfo ai = CGImageGetAlphaInfo(img);
            int opaque_src = (ai == kCGImageAlphaNone || ai == kCGImageAlphaNoneSkipLast || ai == kCGImageAlphaNoneSkipFirst);
            for (int o = 0; o < nr; o++) {
                const uint8_t *srow = src + (size_t)(sy_start + o) * sst + (size_t)sx_start * 4;
                uint8_t *drow = (uint8_t *)c->data + (size_t)(r0 + o) * c->stride + (size_t)q0 * 4;
                if (opaque_src) {
                    memcpy(drow, srow, (size_t)nq * 4);
                } else {
                    int q = 0;
#if defined(__aarch64__)
                    for (; q + 4 <= nq; q += 4) {
                        uint32x4_t spx = vld1q_u32((const uint32_t *)(const void *)(srow + q * 4));
                        if (vminvq_u32(vshrq_n_u32(spx, 24)) == 255u) {
                            vst1q_u32((uint32_t *)(void *)(drow + q * 4), spx);
                            continue;
                        }
                        for (int sub = 0; sub < 4; sub++) {
                            int qq = q + sub;
                            uint8_t sa = srow[qq * 4 + 3];
                            if (sa == 255) { memcpy(drow + qq * 4, srow + qq * 4, 4); }
                            else if (sa > 0) {
                                float keep = 1.0f - (float)sa / 255.0f;
                                for (int ch = 0; ch < 4; ch++) {
                                    float v = (float)srow[qq * 4 + ch] + (float)drow[qq * 4 + ch] * keep;
                                    int iv = (int)(v + 0.5f);
                                    drow[qq * 4 + ch] = (uint8_t)(iv > 255 ? 255 : iv < 0 ? 0 : iv);
                                }
                            }
                        }
                    }
#endif
                    for (; q < nq; q++) {
                        uint8_t sa = srow[q * 4 + 3];
                        if (sa == 255) { memcpy(drow + q * 4, srow + q * 4, 4); }
                        else if (sa > 0) {
                            float keep = 1.0f - (float)sa / 255.0f;
                            for (int ch = 0; ch < 4; ch++) {
                                float v = (float)srow[q * 4 + ch] + (float)drow[q * 4 + ch] * keep;
                                int iv = (int)(v + 0.5f);
                                drow[q * 4 + ch] = (uint8_t)(iv > 255 ? 255 : iv < 0 ? 0 : iv);
                            }
                        }
                    }
                }
            }
            return 1;
        }
    }
    int *hf, *hc, *vf, *vc;
    float *hw, *vw;
    int ht = cg_exact_weights(nq, px0 + q0 * pxs, pxs, (int)iw, &hf, &hc, &hw);
    if (!ht) return 0;
    int vt = cg_exact_weights(nr, py0 + r0 * pys, pys, (int)ih, &vf, &vc, &vw);
    if (!vt) { free(hf); free(hc); free(hw); return 0; }
    CGExactJob job = {
        .src = src, .dst = (uint8_t *)c->data, .sst = sst, .dst_stride = c->stride,
        .iw = (int)iw, .ih = (int)ih, .q0 = q0, .r0 = r0, .nq = nq, .nr = nr,
        .ht = ht, .vt = vt, .hf = hf, .hc = hc, .vf = vf, .vc = vc, .hw = hw, .vw = vw,
        .opf = (float)(op < 0 ? 0 : op > 1 ? 1 : op)
    };
    size_t nbands = (size_t)((nr + 15) / 16);
    if ((int64_t)nq * (int64_t)nr >= 16384 && nbands > 1) {
        dispatch_apply_f(nbands, DISPATCH_APPLY_AUTO, &job, cg_exact_band);
    } else {
        for (size_t bi = 0; bi < nbands; bi++) cg_exact_band(&job, bi);
    }
    free(hf); free(hc); free(hw); free(vf); free(vc); free(vw);
    return 1;
}

/* w_cg_image_draw(h, img, x, y, w, h, fit, align, opacity, quality, sx, sy, sw, sh)
 *   fit: "meet" (default, SVG's), "slice" (cover, clipped to the box), or
 *   "fill"/"none" (stretch); align: SVG preserveAspectRatio alignment
 *   ("xMidYMid", "xMinYMax", …). sx..sh crop the source in image pixels
 *   (sw nil or <= 0 = whole image). w/h nil = the image's own size. */
/* ---- drawn-size cache ----
 * A large image drawn much smaller (a 3000 px photo in a 600 px box) is
 * resampled by CoreGraphics on every draw — every tile repaint, every scroll
 * frame that paints. Instead it is resampled once (at the canvas's quality)
 * to the device size it is drawn at and the copy is drawn about 1:1, which
 * CoreGraphics does as a near-copy. The copy is made on the second draw at a
 * size (a single draw is left to CoreGraphics). Two sizes are kept per image
 * (bytes count toward the image budget). TUNGSTEN_CG_SCALE_CACHE=0 turns it off. */
static int g_scale_cache = -1;

static CGImageRef cg_img_scaled(CGImg *im, CGImageRef src, CGCanvas *c, size_t tw, size_t th, CGInterpolationQuality q) {
    if (g_scale_cache < 0) {
        const char *e = getenv("TUNGSTEN_CG_SCALE_CACHE");
        g_scale_cache = (e && e[0] == '0') ? 0 : 1;
    }
    if (!g_scale_cache) return NULL;
    pthread_mutex_lock(&g_img_lock);
    for (int i = 0; i < CG_MAX_SCALED; i++) {
        if (im->sc_img[i] && im->sc_src[i] == src && im->sc_w[i] == tw && im->sc_h[i] == th) {
            CGImageRef r = CGImageRetain(im->sc_img[i]);
            pthread_mutex_unlock(&g_img_lock);
            return r;
        }
    }
    /* first draw at this size: no copy yet (a one-off draw would pay a whole-image
     * resample for what may be a tile's worth of it); the second draw makes one */
    if (!(im->sc_pend_src == src && im->sc_pend_w == tw && im->sc_pend_h == th)) {
        im->sc_pend_src = src;
        im->sc_pend_w = tw;
        im->sc_pend_h = th;
        pthread_mutex_unlock(&g_img_lock);
        return NULL;
    }
    pthread_mutex_unlock(&g_img_lock);
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    if (c->bpc == 8) info |= kCGBitmapByteOrder32Big;
    else if (c->bpc == 16) info |= kCGBitmapByteOrder16Little | (c->is_float ? kCGBitmapFloatComponents : 0);
    else info |= kCGBitmapByteOrder32Little | kCGBitmapFloatComponents;
    CGContextRef ctx = CGBitmapContextCreate(NULL, tw, th, (size_t)c->bpc, 0, c->space, info);
    if (!ctx) return NULL;
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextSetInterpolationQuality(ctx, q);
    CGContextDrawImage(ctx, CGRectMake(0, 0, tw, th), src);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    size_t bytes = CGBitmapContextGetBytesPerRow(ctx) * th;
    CGContextRelease(ctx);
    if (!out) return NULL;
    pthread_mutex_lock(&g_img_lock);
    int k = im->sc_next++ % CG_MAX_SCALED;
    if (im->sc_img[k]) {
        CGImageRelease(im->sc_img[k]);
        g_image_bytes -= im->sc_bytes[k];
    }
    im->sc_img[k] = CGImageRetain(out);
    im->sc_src[k] = src;
    im->sc_w[k] = tw;
    im->sc_h[k] = th;
    im->sc_bytes[k] = bytes;
    g_image_bytes += bytes;
    pthread_mutex_unlock(&g_img_lock);
    return out;
}

WValue w_cg_image_draw(WValue hv, WValue imv, WValue xv, WValue yv, WValue wv, WValue hgtv,
                       WValue fitv, WValue alignv, WValue opv, WValue qv,
                       WValue sxv, WValue syv, WValue swv, WValue shv) {
    CGCanvas *c = cg_canvas(hv, "image");
    CGImg *im = cg_image(imv, "image");
    double x = cg_num(xv, "x"), y = cg_num(yv, "y");
    double sw = cg_num_or(swv, 0, "source width"), sh = cg_num_or(shv, 0, "source height");
    double sx = cg_num_or(sxv, 0, "source x"), sy = cg_num_or(syv, 0, "source y");
    int crop = sw > 0 && sh > 0;
    double iw = crop ? sw : (double)im->w, ih = crop ? sh : (double)im->h;
    double w = cg_num_or(wv, iw, "width"), h = cg_num_or(hgtv, ih, "height");
    double op = cg_num_or(opv, 1.0, "opacity");
    char fit[16] = "meet", align[16] = "xMidYMid";
    if (fitv != W_NIL) cg_str(fitv, fit, sizeof fit);
    if (alignv != W_NIL) cg_str(alignv, align, sizeof align);
    int ok, exact = 0;
    char qs[16];
    if (qv != W_NIL && cg_str(qv, qs, sizeof qs) && cg_eq(qs, "exact")) { exact = 1; qv = W_NIL; }
    CGInterpolationQuality q = cg_quality(qv, &ok);
    if (!ok) cg_raise("Canvas.image: quality must be none, low, medium, high, default or exact");
    if (w <= 0 || h <= 0 || op <= 0 || iw <= 0 || ih <= 0) return W_FALSE;
    int slice = 0, stretch = 0;
    if (cg_eq(fit, "slice") || cg_eq(fit, "cover")) slice = 1;
    else if (cg_eq(fit, "fill") || cg_eq(fit, "none") || cg_eq(fit, "stretch")) stretch = 1;
    else if (!(cg_eq(fit, "meet") || cg_eq(fit, "contain"))) cg_raise("Canvas.image: fit must be meet, slice or fill (got \"%s\")", fit);
    if (cg_eq(align, "none")) stretch = 1;
    double dx = x, dy = y, dw = w, dh = h;
    if (!stretch) {
        double s = slice ? fmax(w / iw, h / ih) : fmin(w / iw, h / ih);
        dw = iw * s;
        dh = ih * s;
        double ax = 0.5, ay = 0.5;
        if (strlen(align) >= 8) {
            if (strncasecmp(align, "xMin", 4) == 0) ax = 0;
            else if (strncasecmp(align, "xMax", 4) == 0) ax = 1;
            if (strncasecmp(align + 4, "YMin", 4) == 0) ay = 0;
            else if (strncasecmp(align + 4, "YMax", 4) == 0) ay = 1;
        }
        dx = x + (w - dw) * ax;
        dy = y + (h - dh) * ay;
    }
    CGImageRef img = cg_img_for(im, c);
    if (exact && stretch && !crop && cg_image_draw_exact(c, im, img, dx, dy, dw, dh, op * cg_state(c)->alpha)) return W_TRUE;
    CGImageRef part = NULL;
    if (crop) {
        part = CGImageCreateWithImageInRect(img, CGRectMake(sx, sy, sw, sh));
        if (!part) return W_FALSE;
        img = part;
    } else if (q != kCGInterpolationNone && iw * ih >= 65536) {
        /* drawn well below its size on an axis-aligned CTM: draw a copy resampled to that size */
        CGAffineTransform m = CGContextGetCTM(c->ctx);
        if (m.b == 0 && m.c == 0) {
            double pw = fabs(m.a) * dw, ph = fabs(m.d) * dh;
            if (pw >= 1 && ph >= 1 && pw < 0.75 * iw && ph < 0.75 * ih) {
                part = cg_img_scaled(im, img, c, (size_t)lround(pw), (size_t)lround(ph), q);
                if (part) img = part;
            }
        }
    }
    CGContextSaveGState(c->ctx);
    if (slice) CGContextClipToRect(c->ctx, CGRectMake(x, y, w, h));
    if (op < 1) CGContextSetAlpha(c->ctx, cg_state(c)->alpha * op);
    CGContextSetInterpolationQuality(c->ctx, q);
    /* CGContextDrawImage assumes y up: flip locally so the image is upright. */
    CGContextTranslateCTM(c->ctx, dx, dy + dh);
    CGContextScaleCTM(c->ctx, 1, -1);
    CGContextDrawImage(c->ctx, CGRectMake(0, 0, dw, dh), img);
    CGContextRestoreGState(c->ctx);
    if (part) CGImageRelease(part);
    return W_TRUE;
}

static void cg_unpremultiply8(uint8_t *p, size_t npix) {
    for (size_t i = 0; i < npix; i++, p += 4) {
        unsigned a = p[3];
        if (a == 0 || a == 255) continue;
        for (int k = 0; k < 3; k++) {
            unsigned v = (p[k] * 255u + a / 2) / a;
            p[k] = (uint8_t)(v > 255 ? 255 : v);
        }
    }
}

static int cg_image_try_direct_rgba8(CGImageRef img, size_t w, size_t h, uint8_t *dst_rgba, uint8_t *dst_rgb8, uint8_t *dst_rgb16, int bg_black) {
    if (CGImageGetBitsPerComponent(img) != 8) return 0;
    size_t bpp = CGImageGetBitsPerPixel(img), st = CGImageGetBytesPerRow(img);
    if (bpp != 24 && bpp != 32) return 0;
    CGColorSpaceRef cs = CGImageGetColorSpace(img);
    if (cs && CGColorSpaceGetModel(cs) != kCGColorSpaceModelRGB) return 0;
    CGBitmapInfo bi = CGImageGetBitmapInfo(img);
    if (bi & kCGBitmapFloatComponents) return 0;
    CGBitmapInfo ord = bi & kCGBitmapByteOrderMask;
    CGImageAlphaInfo ai = CGImageGetAlphaInfo(img);
    int r_off = 0, g_off = 1, b_off = 2, a_off = -1, premul = 0, step = (int)(bpp / 8);
    if (bpp == 24) {
        if (ai != kCGImageAlphaNone || ord == kCGBitmapByteOrder32Little) return 0;
    } else if (ord == kCGBitmapByteOrderDefault || ord == kCGBitmapByteOrder32Big) {
        if (ai == kCGImageAlphaNoneSkipLast) { r_off = 0; g_off = 1; b_off = 2; a_off = -1; }
        else if (ai == kCGImageAlphaLast) { r_off = 0; g_off = 1; b_off = 2; a_off = 3; }
        else if (ai == kCGImageAlphaPremultipliedLast) { r_off = 0; g_off = 1; b_off = 2; a_off = 3; premul = 1; }
        else if (ai == kCGImageAlphaNoneSkipFirst) { r_off = 1; g_off = 2; b_off = 3; a_off = -1; }
        else if (ai == kCGImageAlphaFirst) { r_off = 1; g_off = 2; b_off = 3; a_off = 0; }
        else if (ai == kCGImageAlphaPremultipliedFirst) { r_off = 1; g_off = 2; b_off = 3; a_off = 0; premul = 1; }
        else return 0;
    } else if (ord == kCGBitmapByteOrder32Little) {
        if (ai == kCGImageAlphaNoneSkipFirst) { r_off = 2; g_off = 1; b_off = 0; a_off = -1; }
        else if (ai == kCGImageAlphaFirst) { r_off = 2; g_off = 1; b_off = 0; a_off = 3; }
        else if (ai == kCGImageAlphaPremultipliedFirst) { r_off = 2; g_off = 1; b_off = 0; a_off = 3; premul = 1; }
        else if (ai == kCGImageAlphaNoneSkipLast) { r_off = 3; g_off = 2; b_off = 1; a_off = -1; }
        else if (ai == kCGImageAlphaLast) { r_off = 3; g_off = 2; b_off = 1; a_off = 0; }
        else if (ai == kCGImageAlphaPremultipliedLast) { r_off = 3; g_off = 2; b_off = 1; a_off = 0; premul = 1; }
        else return 0;
    } else {
        return 0;
    }
    CGDataProviderRef prov = CGImageGetDataProvider(img);
    CFDataRef data = prov ? CGDataProviderCopyData(prov) : NULL;
    if (!data) return 0;
    size_t need = h > 0 ? (h - 1) * st + w * (size_t)step : 0;
    if ((size_t)CFDataGetLength(data) < need) { CFRelease(data); return 0; }
    const uint8_t *src = CFDataGetBytePtr(data);
    if (dst_rgb8) {
        if (step == 3 && r_off == 0 && st == w * 3) {
            memcpy(dst_rgb8, src, w * h * 3);
        } else if (a_off < 0 || (bg_black && premul)) {
            for (size_t y = 0; y < h; y++) {
                const uint8_t *s = src + y * st;
                uint8_t *d = dst_rgb8 + y * w * 3;
                size_t x = 0;
#if defined(__aarch64__)
                if (step == 4) {
                    for (; x + 16 <= w; x += 16, s += 64, d += 48) {
                        uint8x16x4_t p = vld4q_u8(s);
                        uint8x16x3_t o = {{p.val[r_off], p.val[g_off], p.val[b_off]}};
                        vst3q_u8(d, o);
                    }
                }
#endif
                for (; x < w; x++, s += step, d += 3) {
                    d[0] = s[r_off]; d[1] = s[g_off]; d[2] = s[b_off];
                }
            }
        } else {
            for (size_t y = 0; y < h; y++) {
                const uint8_t *s = src + y * st;
                uint8_t *d = dst_rgb8 + y * w * 3;
                size_t x = 0;
#if defined(__aarch64__)
                if (step == 4 && bg_black) {
                    uint16x8_t v127 = vdupq_n_u16(127), v1 = vdupq_n_u16(1);
                    for (; x + 16 <= w; x += 16, s += 64, d += 48) {
                        uint8x16x4_t p = vld4q_u8(s);
                        uint8x16_t a = p.val[a_off];
                        if (vminvq_u8(a) == 255) {
                            uint8x16x3_t o = {{p.val[r_off], p.val[g_off], p.val[b_off]}};
                            vst3q_u8(d, o);
                        } else {
                            uint8x8_t al = vget_low_u8(a), ah = vget_high_u8(a);
                            uint16x8_t rl = vaddq_u16(vmull_u8(vget_low_u8(p.val[r_off]), al), v127);
                            uint16x8_t rh = vaddq_u16(vmull_u8(vget_high_u8(p.val[r_off]), ah), v127);
                            uint16x8_t gl = vaddq_u16(vmull_u8(vget_low_u8(p.val[g_off]), al), v127);
                            uint16x8_t gh = vaddq_u16(vmull_u8(vget_high_u8(p.val[g_off]), ah), v127);
                            uint16x8_t bl = vaddq_u16(vmull_u8(vget_low_u8(p.val[b_off]), al), v127);
                            uint16x8_t bh = vaddq_u16(vmull_u8(vget_high_u8(p.val[b_off]), ah), v127);
                            uint8x16x3_t o = {{
                                vcombine_u8(vshrn_n_u16(vaddq_u16(vaddq_u16(rl, vshrq_n_u16(rl, 8)), v1), 8),
                                            vshrn_n_u16(vaddq_u16(vaddq_u16(rh, vshrq_n_u16(rh, 8)), v1), 8)),
                                vcombine_u8(vshrn_n_u16(vaddq_u16(vaddq_u16(gl, vshrq_n_u16(gl, 8)), v1), 8),
                                            vshrn_n_u16(vaddq_u16(vaddq_u16(gh, vshrq_n_u16(gh, 8)), v1), 8)),
                                vcombine_u8(vshrn_n_u16(vaddq_u16(vaddq_u16(bl, vshrq_n_u16(bl, 8)), v1), 8),
                                            vshrn_n_u16(vaddq_u16(vaddq_u16(bh, vshrq_n_u16(bh, 8)), v1), 8))
                            }};
                            vst3q_u8(d, o);
                        }
                    }
                }
#endif
                for (; x < w; x++, s += step, d += 3) {
                    unsigned a = s[a_off];
                    if (bg_black) {
                        d[0] = (uint8_t)((s[r_off] * a + 127u) / 255u);
                        d[1] = (uint8_t)((s[g_off] * a + 127u) / 255u);
                        d[2] = (uint8_t)((s[b_off] * a + 127u) / 255u);
                    } else if (!premul || a == 0 || a == 255) {
                        d[0] = s[r_off]; d[1] = s[g_off]; d[2] = s[b_off];
                    } else {
                        unsigned vr = (s[r_off] * 255u + a / 2) / a;
                        unsigned vg = (s[g_off] * 255u + a / 2) / a;
                        unsigned vb = (s[b_off] * 255u + a / 2) / a;
                        d[0] = (uint8_t)(vr > 255 ? 255 : vr);
                        d[1] = (uint8_t)(vg > 255 ? 255 : vg);
                        d[2] = (uint8_t)(vb > 255 ? 255 : vb);
                    }
                }
            }
        }
    } else if (dst_rgb16) {
        for (size_t y = 0; y < h; y++) {
            const uint8_t *s = src + y * st;
            uint8_t *d = dst_rgb16 + y * w * 6;
            size_t x = 0;
#if defined(__aarch64__)
            if (step == 4 && (a_off < 0 || !bg_black || premul)) {
                for (; x + 8 <= w; x += 8, s += 32, d += 48) {
                    uint8x8x4_t p = vld4_u8(s);
                    uint16x8x3_t o = {{
                        vorrq_u16(vmovl_u8(p.val[r_off]), vshll_n_u8(p.val[r_off], 8)),
                        vorrq_u16(vmovl_u8(p.val[g_off]), vshll_n_u8(p.val[g_off], 8)),
                        vorrq_u16(vmovl_u8(p.val[b_off]), vshll_n_u8(p.val[b_off], 8))
                    }};
                    vst3q_u16((uint16_t *)(void *)d, o);
                }
            }
#endif
            for (; x < w; x++, s += step, d += 6) {
                unsigned r = s[r_off], g = s[g_off], b = s[b_off];
                if (a_off >= 0 && bg_black && !premul) {
                    unsigned a = s[a_off];
                    r = (r * a + 127u) / 255u;
                    g = (g * a + 127u) / 255u;
                    b = (b * a + 127u) / 255u;
                }
                unsigned r16 = r * 257u, g16 = g * 257u, b16 = b * 257u;
                d[0] = (uint8_t)(r16 & 255u); d[1] = (uint8_t)(r16 >> 8);
                d[2] = (uint8_t)(g16 & 255u); d[3] = (uint8_t)(g16 >> 8);
                d[4] = (uint8_t)(b16 & 255u); d[5] = (uint8_t)(b16 >> 8);
            }
        }
    } else if (dst_rgba) {
        if (step == 4 && r_off == 0 && g_off == 1 && b_off == 2 && a_off == 3 && !premul && st == w * 4) {
            memcpy(dst_rgba, src, w * h * 4);
        } else {
            for (size_t y = 0; y < h; y++) {
                const uint8_t *s = src + y * st;
                uint8_t *d = dst_rgba + y * w * 4;
                for (size_t x = 0; x < w; x++, s += step, d += 4) {
                    unsigned a = a_off >= 0 ? s[a_off] : 255u;
                    d[0] = s[r_off]; d[1] = s[g_off]; d[2] = s[b_off]; d[3] = (uint8_t)a;
                }
            }
            if (premul) cg_unpremultiply8(dst_rgba, w * h);
        }
    }
    CFRelease(data);
    return 1;
}

/* w_cg_image_bytes(img) -> ByteArray of RGBA8, unpremultiplied, in the
 * image's own colour space (row-major, no padding). */
WValue w_cg_image_bytes(WValue imv) {
    CGImg *im = cg_image(imv, "image_bytes");
    size_t w = im->w, h = im->h;
    uint8_t *buf = malloc(w * h * 4 > 0 ? w * h * 4 : 1);
    if (!buf) cg_raise("Canvas.image_bytes: out of memory");
    if (!cg_image_try_direct_rgba8(im->image, w, h, buf, NULL, NULL, 0)) {
        memset(buf, 0, w * h * 4);
        CGColorSpaceRef cs = CGImageGetColorSpace(im->image);
        if (!cs || CGColorSpaceGetModel(cs) != kCGColorSpaceModelRGB) cs = cg_srgb();
        CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (!ctx) { free(buf); cg_raise("Canvas.image_bytes: no RGBA8 format for this image's colour space"); }
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), im->image);
        CGContextRelease(ctx);
        cg_unpremultiply8(buf, w * h);
    }
    WValue out = w_bytes_from_data(buf, (int64_t)(w * h * 4));
    free(buf);
    return out;
}

/* w_cg_image_rgb(img, depth) -> ByteArray of RGB24 (depth=8) or RGB48LE (depth=16)
 * composited over black in sRGB/source RGB without allocating a Canvas when possible. */
WValue w_cg_image_rgb(WValue imv, WValue depthv) {
    CGImg *im = cg_image(imv, "image_rgb");
    int depth = (int)cg_num_or(depthv, 8, "depth");
    if (depth != 8 && depth != 16) cg_raise("Canvas.image_rgb: depth must be 8 or 16");
    size_t w = im->w, h = im->h;
    size_t bpp = depth == 16 ? 6 : 3;
    uint8_t *buf = malloc(w * h * bpp > 0 ? w * h * bpp : 1);
    if (!buf) cg_raise("Canvas.image_rgb: out of memory");
    int ok = depth == 16
        ? cg_image_try_direct_rgba8(im->image, w, h, NULL, NULL, buf, 1)
        : cg_image_try_direct_rgba8(im->image, w, h, NULL, buf, NULL, 1);
    if (!ok) {
        uint8_t *rgba = calloc(w * h > 0 ? w * h : 1, 4);
        if (!rgba) { free(buf); cg_raise("Canvas.image_rgb: out of memory"); }
        CGContextRef ctx = CGBitmapContextCreate(rgba, w, h, 8, w * 4, cg_srgb(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (!ctx) { free(rgba); free(buf); cg_raise("Canvas.image_rgb: CGBitmapContextCreate failed"); }
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), im->image);
        CGContextRelease(ctx);
        if (depth == 16) {
            for (size_t i = 0; i < w * h; i++) {
                unsigned r16 = rgba[i * 4] * 257u, g16 = rgba[i * 4 + 1] * 257u, b16 = rgba[i * 4 + 2] * 257u;
                buf[i * 6] = (uint8_t)(r16 & 255u); buf[i * 6 + 1] = (uint8_t)(r16 >> 8);
                buf[i * 6 + 2] = (uint8_t)(g16 & 255u); buf[i * 6 + 3] = (uint8_t)(g16 >> 8);
                buf[i * 6 + 4] = (uint8_t)(b16 & 255u); buf[i * 6 + 5] = (uint8_t)(b16 >> 8);
            }
        } else {
            for (size_t i = 0; i < w * h; i++) {
                buf[i * 3] = rgba[i * 4];
                buf[i * 3 + 1] = rgba[i * 4 + 1];
                buf[i * 3 + 2] = rgba[i * 4 + 2];
            }
        }
        free(rgba);
    }
    WValue out = w_bytes_from_data(buf, (int64_t)(w * h * bpp));
    free(buf);
    return out;
}

WValue w_cg_image_release(WValue imv) {
    if (!w_is_int(imv)) return W_NIL;
    int64_t h = w_as_int(imv);
    int64_t slot = (h & 0xFFFF) - 1;
    uint32_t gen = (uint32_t)(h >> 16);
    if (slot < 0 || slot >= CG_MAX_IMAGES) return W_NIL;
    pthread_mutex_lock(&g_img_lock);
    if (g_images[slot] && g_images[slot]->gen == gen) cg_img_unregister((int)slot);
    pthread_mutex_unlock(&g_img_lock);
    return W_NIL;
}

/* Release every cached image; returns how many there were. */
WValue w_cg_image_purge(void) {
    pthread_mutex_lock(&g_img_lock);
    int n = 0;
    for (int i = 0; i < g_image_hi; i++) {
        if (g_images[i]) { cg_img_unregister(i); n++; }
    }
    pthread_mutex_unlock(&g_img_lock);
    return w_int(n);
}

/* [live canvases, canvas pixel bytes, cached images, image bytes, cached
 * font faces] — for leak checks and cache sizing. */
WValue w_cg_stats(void) {
    pthread_mutex_lock(&g_reg_lock);
    double a = g_canvas_live, b = (double)g_canvas_bytes;
    pthread_mutex_unlock(&g_reg_lock);
    pthread_mutex_lock(&g_img_lock);
    double c = g_image_live, d = (double)g_image_bytes;
    pthread_mutex_unlock(&g_img_lock);
    pthread_mutex_lock(&g_font_lock);
    double e = g_font_count;
    pthread_mutex_unlock(&g_font_lock);
    WValue arr = w_array_new_empty();
    arr = w_array_push(arr, w_int((int64_t)a));
    arr = w_array_push(arr, w_int((int64_t)b));
    arr = w_array_push(arr, w_int((int64_t)c));
    arr = w_array_push(arr, w_int((int64_t)d));
    arr = w_array_push(arr, w_int((int64_t)e));
    return arr;
}

/* ======================================================================
   Pixels and output
   ====================================================================== */

static float cg_half_to_float(uint16_t h) {
    __fp16 f;
    memcpy(&f, &h, 2);
    return (float)f;
}

static uint16_t cg_float_to_half(float x) {
    __fp16 f = (__fp16)x;
    uint16_t h;
    memcpy(&h, &f, 2);
    return h;
}

/* Premultiplied RGBA of pixel (px, py) as floats (0..1 for integer depths). */
static void cg_read_px(CGCanvas *c, size_t px, size_t py, double out[4]) {
    uint8_t *row = (uint8_t *)c->data + py * c->stride;
    if (c->bpc == 8) {
        uint8_t *p = row + px * 4;
        for (int k = 0; k < 4; k++) out[k] = p[k] / 255.0;
    } else if (c->bpc == 16 && !c->is_float) {
        uint16_t *p = (uint16_t *)(row + px * 8);
        for (int k = 0; k < 4; k++) out[k] = p[k] / 65535.0;
    } else if (c->bpc == 16) {
        uint16_t *p = (uint16_t *)(row + px * 8);
        for (int k = 0; k < 4; k++) out[k] = cg_half_to_float(p[k]);
    } else {
        float *p = (float *)(row + px * 16);
        for (int k = 0; k < 4; k++) out[k] = p[k];
    }
}

/* w_cg_clear(h, colour): set every pixel (ignoring transform, clip, alpha and
 * blend) to the colour, or to transparent for nil/"none". */
WValue w_cg_clear(WValue hv, WValue colorv) {
    CGCanvas *c = cg_canvas(hv, "clear");
    double rgba[4] = {0, 0, 0, 0};
    if (cg_color(colorv, rgba, "clear")) {
        if (c->color_space != c->space) {
            const CGFloat comps[4] = {rgba[0], rgba[1], rgba[2], 1.0};
            CGColorRef src = CGColorCreate(c->color_space, comps);
            CGColorRef dst = CGColorCreateCopyByMatchingToColorSpace(c->space, kCGRenderingIntentDefault, src, NULL);
            if (dst && CGColorGetNumberOfComponents(dst) == 4) {
                const CGFloat *dc = CGColorGetComponents(dst);
                rgba[0] = dc[0]; rgba[1] = dc[1]; rgba[2] = dc[2];
            }
            if (dst) CGColorRelease(dst);
            CGColorRelease(src);
        }
    }
    double a = rgba[3];
    double pm[4] = {rgba[0] * a, rgba[1] * a, rgba[2] * a, a};
    size_t pw = c->pw, ph = c->ph;
    if (a == 0) {
        for (size_t y = 0; y < ph; y++) memset((uint8_t *)c->data + y * c->stride, 0, pw * 4 * (size_t)c->bpc / 8);
        return W_NIL;
    }
    if (c->bpc == 8) {
        uint8_t px[4];
        for (int k = 0; k < 4; k++) {
            double v = round(pm[k] * 255.0);
            px[k] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
        }
        uint32_t word;
        memcpy(&word, px, 4);
        for (size_t y = 0; y < ph; y++) {
            uint32_t *row = (uint32_t *)((uint8_t *)c->data + y * c->stride);
            for (size_t x = 0; x < pw; x++) row[x] = word;
        }
    } else if (c->bpc == 16) {
        uint16_t px[4];
        for (int k = 0; k < 4; k++) {
            if (c->is_float) px[k] = cg_float_to_half((float)pm[k]);
            else {
                double v = round(pm[k] * 65535.0);
                px[k] = (uint16_t)(v < 0 ? 0 : v > 65535 ? 65535 : v);
            }
        }
        uint64_t word;
        memcpy(&word, px, 8);
        for (size_t y = 0; y < ph; y++) {
            uint64_t *row = (uint64_t *)((uint8_t *)c->data + y * c->stride);
            for (size_t x = 0; x < pw; x++) row[x] = word;
        }
    } else {
        float px[4] = {(float)pm[0], (float)pm[1], (float)pm[2], (float)pm[3]};
        for (size_t y = 0; y < ph; y++) {
            float *row = (float *)((uint8_t *)c->data + y * c->stride);
            for (size_t x = 0; x < pw; x++) memcpy(row + 4 * x, px, 16);
        }
    }
    return W_NIL;
}

/* w_cg_pixel(h, px, py) -> [r, g, b, a], unpremultiplied, at device pixel
 * (px, py) from the top-left: Integers 0..255 (8-bit), 0..65535 (16-bit), or
 * Floats (half/float canvases). nil outside the canvas. */
WValue w_cg_pixel(WValue hv, WValue xv, WValue yv) {
    CGCanvas *c = cg_canvas(hv, "pixel");
    double fx = cg_num(xv, "x"), fy = cg_num(yv, "y");
    if (fx < 0 || fy < 0 || fx >= (double)c->pw || fy >= (double)c->ph) return W_NIL;
    size_t px = (size_t)fx, py = (size_t)fy;
    WValue arr = w_array_new_empty();
    uint8_t *row = (uint8_t *)c->data + py * c->stride;
    if (c->bpc == 8) {
        uint8_t p[4];
        memcpy(p, row + px * 4, 4);
        cg_unpremultiply8(p, 1);
        for (int k = 0; k < 4; k++) arr = w_array_push(arr, w_int(p[k]));
    } else if (c->bpc == 16 && !c->is_float) {
        uint16_t *p = (uint16_t *)(row + px * 8);
        unsigned a = p[3];
        for (int k = 0; k < 3; k++) {
            unsigned v = a == 0 ? 0 : (unsigned)(((uint64_t)p[k] * 65535u + a / 2) / a);
            arr = w_array_push(arr, w_int(v > 65535 ? 65535 : v));
        }
        arr = w_array_push(arr, w_int(a));
    } else {
        double v[4];
        cg_read_px(c, px, py, v);
        for (int k = 0; k < 3; k++) arr = w_array_push(arr, w_float(v[3] > 0 ? v[k] / v[3] : 0));
        arr = w_array_push(arr, w_float(v[3]));
    }
    return arr;
}

/* RGBA8 copy of the canvas (tightly packed rows), unpremultiplied unless
 * asked. Deeper canvases are rounded to 8 bits (clamped to 0..1). */
static uint8_t *cg_rgba8(CGCanvas *c, int premultiplied) {
    size_t pw = c->pw, ph = c->ph;
    uint8_t *buf = malloc(pw * ph * 4);
    if (!buf) cg_raise("Canvas.bytes: out of memory");
    if (c->bpc == 8) {
        for (size_t y = 0; y < ph; y++) memcpy(buf + y * pw * 4, (uint8_t *)c->data + y * c->stride, pw * 4);
        if (!premultiplied) cg_unpremultiply8(buf, pw * ph);
        return buf;
    }
    for (size_t y = 0; y < ph; y++) {
        for (size_t x = 0; x < pw; x++) {
            double v[4];
            cg_read_px(c, x, y, v);
            uint8_t *o = buf + (y * pw + x) * 4;
            double a = v[3];
            for (int k = 0; k < 4; k++) {
                double u = v[k];
                if (!premultiplied && k < 3) u = a > 0 ? u / a : 0;
                u = round(u * 255.0);
                o[k] = (uint8_t)(u < 0 ? 0 : u > 255 ? 255 : u);
            }
        }
    }
    return buf;
}

/* w_cg_bytes(h, premultiplied) -> ByteArray, width*height*4 RGBA8. */
WValue w_cg_bytes(WValue hv, WValue pmv) {
    CGCanvas *c = cg_canvas(hv, "bytes");
    CGContextFlush(c->ctx);
    uint8_t *buf = cg_rgba8(c, cg_truthy(pmv));
    WValue out = w_bytes_from_data(buf, (int64_t)(c->pw * c->ph * 4));
    free(buf);
    return out;
}

/* w_cg_to_raster(h, pixels, background): composite the canvas over the
 * 0xRRGGBB background into a Raster's i64[] pixel array (width*height). */
WValue w_cg_to_raster(WValue hv, WValue arrv, WValue bgv) {
    CGCanvas *c = cg_canvas(hv, "to_raster");
    if (!w_is_array(arrv)) cg_raise("Canvas.to_raster: pixels must be an i64[] array");
    WArray *a = w_as_array(arrv);
    if (a->ebits != 66 && a->ebits != 64) cg_raise("Canvas.to_raster: pixels must be an i64[] array (Raster#pixels)");
    if ((size_t)a->size < c->pw * c->ph) cg_raise("Canvas.to_raster: the Raster is smaller than the canvas");
    int64_t bg = w_is_int(bgv) ? w_as_int(bgv) : 0xFFFFFF;
    double br = ((bg >> 16) & 0xFF) / 255.0, bgg = ((bg >> 8) & 0xFF) / 255.0, bb = (bg & 0xFF) / 255.0;
    int64_t *px = (int64_t *)a->slots + a->start;
    for (size_t y = 0; y < c->ph; y++) {
        for (size_t x = 0; x < c->pw; x++) {
            double v[4];
            cg_read_px(c, x, y, v);
            double ia = 1.0 - v[3];
            int r = (int)lround(fmin(1, fmax(0, v[0] + br * ia)) * 255.0);
            int g = (int)lround(fmin(1, fmax(0, v[1] + bgg * ia)) * 255.0);
            int b = (int)lround(fmin(1, fmax(0, v[2] + bb * ia)) * 255.0);
            px[y * c->pw + x] = ((int64_t)r << 16) | ((int64_t)g << 8) | b;
        }
    }
    return W_NIL;
}

/* The pixel buffer's address as an Integer, for native encoders that take a
 * pointer (see also w_cg_canvas_buffer in quartz.h). */
WValue w_cg_data_ptr(WValue hv) {
    CGCanvas *c = cg_canvas(hv, "data_pointer");
    CGContextFlush(c->ctx);
    return w_int((int64_t)(uintptr_t)c->data);
}

/* A CGImage of the canvas; with alpha off, composited over black. */
static CGImageRef cg_snapshot(CGCanvas *c, int alpha) {
    CGContextFlush(c->ctx);
    CGImageRef img = CGBitmapContextCreateImage(c->ctx);
    if (!img || alpha) return img;
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaNoneSkipLast;
    if (c->bpc == 8) info |= kCGBitmapByteOrder32Big;
    else if (c->bpc == 16) info |= kCGBitmapByteOrder16Little | (c->is_float ? kCGBitmapFloatComponents : 0);
    else info |= kCGBitmapByteOrder32Little | kCGBitmapFloatComponents;
    CGContextRef ctx = CGBitmapContextCreate(NULL, c->pw, c->ph, (size_t)c->bpc, 0, c->space, info);
    if (!ctx && c->is_float) {
        info = (CGBitmapInfo)kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder16Little;
        ctx = CGBitmapContextCreate(NULL, c->pw, c->ph, 16, 0, c->space, info);
    }
    if (!ctx) return img;
    CGContextDrawImage(ctx, CGRectMake(0, 0, c->pw, c->ph), img);
    CGImageRelease(img);
    img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

static CFStringRef cg_uti(const char *type) {
    if (cg_eq(type, "png")) return CFSTR("public.png");
    if (cg_eq(type, "jpeg") || cg_eq(type, "jpg")) return CFSTR("public.jpeg");
    if (cg_eq(type, "tiff") || cg_eq(type, "tif")) return CFSTR("public.tiff");
    if (cg_eq(type, "heic")) return CFSTR("public.heic");
    return NULL;
}

/* Borrow a CGImage view of c->data for immediate encoding (caller must release
 * the returned CGImage while c remains live and unmutated). Falls back to
 * cg_snapshot for non-8-bit canvases. */
static CGImageRef cg_borrow_for_encode(CGCanvas *c, int alpha) {
    if (c->bpc != 8 || c->is_float || !c->data) return cg_snapshot(c, alpha);
    CGContextFlush(c->ctx);
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, c->data, c->ph * c->stride, NULL);
    if (!prov) return cg_snapshot(c, alpha);
    CGBitmapInfo info = (CGBitmapInfo)(alpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast) | kCGBitmapByteOrder32Big;
    CGImageRef img = CGImageCreate(c->pw, c->ph, 8, 32, c->stride, c->space, info, prov, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(prov);
    return img ? img : cg_snapshot(c, alpha);
}

static CFDictionaryRef cg_dest_props(const char *type, double quality) {
    if (type && cg_eq(type, "png") && quality >= 0 && quality < 0.5) {
        int flt = IMAGEIO_PNG_NO_FILTERS;
        CFNumberRef fn = CFNumberCreate(NULL, kCFNumberIntType, &flt);
        const void *pk[] = {kCGImagePropertyPNGCompressionFilter};
        const void *pv[] = {fn};
        CFDictionaryRef pd = CFDictionaryCreate(NULL, pk, pv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(fn);
        const void *k[] = {kCGImagePropertyPNGDictionary};
        const void *v[] = {pd};
        CFDictionaryRef d = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(pd);
        return d;
    }
    if (!(quality >= 0 && quality <= 1)) return NULL;
    CGFloat q = quality;
    CFNumberRef qn = CFNumberCreate(NULL, kCFNumberCGFloatType, &q);
    const void *k[] = {kCGImageDestinationLossyCompressionQuality};
    const void *v[] = {qn};
    CFDictionaryRef d = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(qn);
    return d;
}

/* w_cg_write(h, path, type, quality, alpha): write png/jpeg/tiff/heic via
 * ImageIO with the canvas colour space embedded (ICC profile). quality nil =
 * the encoder default (lossy types only). */
WValue w_cg_write(WValue hv, WValue pathv, WValue typev, WValue qv, WValue alphav) {
    CGCanvas *c = cg_canvas(hv, "write");
    char path[4096], type[16] = "png";
    if (!cg_str(pathv, path, sizeof path)) cg_raise("Canvas.write: path must be a String");
    if (typev != W_NIL) cg_str(typev, type, sizeof type);
    CFStringRef uti = cg_uti(type);
    if (!uti) cg_raise("Canvas.write: type must be png, jpeg, tiff or heic (got \"%s\")", type);
    double q = cg_num_or(qv, -1, "quality");
    int alpha = alphav == W_NIL ? !cg_eq(type, "jpeg") && !cg_eq(type, "jpg") : cg_truthy(alphav);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef dest = url ? CGImageDestinationCreateWithURL(url, uti, 1, NULL) : NULL;
    if (url) CFRelease(url);
    if (!dest) cg_raise("Canvas.write: cannot create %s", path);
    CGImageRef img = cg_borrow_for_encode(c, alpha);
    CFDictionaryRef props = cg_dest_props(type, q);
    CGImageDestinationAddImage(dest, img, props);
    bool ok = CGImageDestinationFinalize(dest);
    if (props) CFRelease(props);
    CGImageRelease(img);
    CFRelease(dest);
    if (!ok) cg_raise("Canvas.write: ImageIO failed to write %s", path);
    return W_TRUE;
}

/* w_cg_encode(h, type, quality, alpha) -> ByteArray of the encoded file. */
WValue w_cg_encode(WValue hv, WValue typev, WValue qv, WValue alphav) {
    CGCanvas *c = cg_canvas(hv, "encode");
    char type[16] = "png";
    if (typev != W_NIL) cg_str(typev, type, sizeof type);
    CFStringRef uti = cg_uti(type);
    if (!uti) cg_raise("Canvas.encode: type must be png, jpeg, tiff or heic (got \"%s\")", type);
    double q = cg_num_or(qv, -1, "quality");
    int alpha = alphav == W_NIL ? !cg_eq(type, "jpeg") && !cg_eq(type, "jpg") : cg_truthy(alphav);
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(data, uti, 1, NULL);
    if (!dest) { CFRelease(data); cg_raise("Canvas.encode: ImageIO has no %s encoder", type); }
    CGImageRef img = cg_borrow_for_encode(c, alpha);
    CFDictionaryRef props = cg_dest_props(type, q);
    CGImageDestinationAddImage(dest, img, props);
    bool ok = CGImageDestinationFinalize(dest);
    if (props) CFRelease(props);
    CGImageRelease(img);
    CFRelease(dest);
    if (!ok) { CFRelease(data); cg_raise("Canvas.encode: ImageIO failed to encode %s", type); }
    WValue out = w_bytes_from_data(CFDataGetBytePtr(data), (int64_t)CFDataGetLength(data));
    CFRelease(data);
    return out;
}

/* ---- Batch primitives & direct pixel/font helpers ---------------------- */

typedef struct CGRegFont {
    struct CGRegFont *next;
    char             *path;
} CGRegFont;

static CGRegFont *g_reg_fonts;

/* w_cg_register_font_data(bytes): register an sfnt (TrueType/OpenType bytes in a
 * ByteArray or String) for the current process without a file; returns its
 * PostScript name, or nil when CoreText rejects it. CoreText copies the bytes.
 * Registering the same PostScript name again is accepted and returns it. */
WValue w_cg_register_font_data(WValue datav) {
    const uint8_t *ptr = NULL;
    size_t n = 0;
    char sso[6];
    if (w_is_array(datav)) {
        WArray *a = w_as_array(datav);
        if (a->ebits != 8) cg_raise("Canvas.register_font_data: data must be a ByteArray (u8[]) or String");
        ptr = (const uint8_t *)a->slots + (size_t)a->start;
        n = (size_t)a->size;
    } else {
        const char *sp = NULL;
        if (!cg_str_view(datav, sso, &sp, &n)) cg_raise("Canvas.register_font_data: data must be a ByteArray (u8[]) or String");
        ptr = (const uint8_t *)sp;
    }
    if (n < 12) return W_NIL;
    CFDataRef data = CFDataCreate(NULL, ptr, (CFIndex)n);
    if (!data) return W_NIL;
    CGDataProviderRef prov = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    if (!prov) return W_NIL;
    CGFontRef cgf = CGFontCreateWithDataProvider(prov);
    CGDataProviderRelease(prov);
    if (!cgf) return W_NIL;
    CFStringRef ps = CGFontCopyPostScriptName(cgf);
    CFErrorRef err = NULL;
    /* Deprecated in macOS 15 in favour of descriptor registration, which has no
     * in-memory equivalent that registers synchronously; it still works. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    bool ok = CTFontManagerRegisterGraphicsFont(cgf, &err);
#pragma clang diagnostic pop
    if (!ok && err) {
        CFIndex code = CFErrorGetCode(err);
        if (code == kCTFontManagerErrorAlreadyRegistered || code == kCTFontManagerErrorDuplicatedName) ok = true;
    }
    if (err) CFRelease(err);
    CGFontRelease(cgf);
    WValue out = W_NIL;
    if (ok && ps) {
        pthread_mutex_lock(&g_font_lock);
        for (int i = 0; i < CG_FONT_BUCKETS; i++) {
            CGFontEntry *e = g_fonts[i];
            while (e) { CGFontEntry *nx = e->next; CFRelease(e->font); free(e->key); free(e); e = nx; }
            g_fonts[i] = NULL;
        }
        g_font_count = 0;
        pthread_mutex_unlock(&g_font_lock);
        out = cg_wstring_from_cf(ps);
    }
    if (ps) CFRelease(ps);
    return out;
}

/* w_cg_register_font(path): process-scoped CTFontManager registration with
 * path deduplication so custom score/UI fonts (e.g. Bravura.otf) resolve by
 * family name in Canvas#text and Canvas#glyphs. */
WValue w_cg_register_font(WValue pathv) {
    char path[4096];
    if (!cg_str(pathv, path, sizeof path) || path[0] == 0)
        cg_raise("Canvas.register_font: path must be a non-empty String");
    pthread_mutex_lock(&g_font_lock);
    for (CGRegFont *r = g_reg_fonts; r; r = r->next) {
        if (strcmp(r->path, path) == 0) {
            pthread_mutex_unlock(&g_font_lock);
            return W_TRUE;
        }
    }
    pthread_mutex_unlock(&g_font_lock);

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    if (!url) return W_FALSE;
    CFErrorRef err = NULL;
    bool ok = CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, &err);
    if (!ok && err) {
        CFIndex code = CFErrorGetCode(err);
        if (code == kCTFontManagerErrorAlreadyRegistered) ok = true;
    }
    if (err) CFRelease(err);
    CFRelease(url);
    if (!ok) return W_FALSE;

    pthread_mutex_lock(&g_font_lock);
    int seen = 0;
    for (CGRegFont *r = g_reg_fonts; r; r = r->next) {
        if (strcmp(r->path, path) == 0) { seen = 1; break; }
    }
    if (!seen) {
        CGRegFont *r = calloc(1, sizeof *r);
        if (r) {
            r->path = strdup(path);
            r->next = g_reg_fonts;
            g_reg_fonts = r;
        }
        /* Flush cached lookups so any earlier fallback for this family resolves
         * to the newly registered font; live canvases hold their own retains. */
        for (int i = 0; i < CG_FONT_BUCKETS; i++) {
            CGFontEntry *e = g_fonts[i];
            while (e) { CGFontEntry *nx = e->next; CFRelease(e->font); free(e->key); free(e); e = nx; }
            g_fonts[i] = NULL;
        }
        g_font_count = 0;
    }
    pthread_mutex_unlock(&g_font_lock);
    return W_TRUE;
}

/* w_cg_segments(h, coords, count, stroke, width): stroke `count` independent
 * line segments from `coords` ([x1, y1, x2, y2, ...] as f64[] or Array) in one
 * CGContextStrokeLineSegments call. */
WValue w_cg_segments(WValue hv, WValue coordsv, WValue countv, WValue strokev, WValue widthv) {
    _Static_assert(sizeof(CGPoint) == 2 * sizeof(double), "CGPoint must be 2 doubles");
    CGCanvas *c = cg_canvas(hv, "segments");
    int64_t count = countv == W_NIL ? -1 : (int64_t)cg_num(countv, "count");
    if (!w_is_array(coordsv)) cg_raise("Canvas.segments: coords must be an Array or f64[]");
    WArray *a = w_as_array(coordsv);
    int64_t avail = (int64_t)a->size / 4;
    if (count < 0 || count > avail) count = avail;
    if (count <= 0) return W_FALSE;

    double sc[4];
    if (!cg_color(strokev, sc, "stroke") || sc[3] <= 0) return W_FALSE;
    double w = widthv == W_NIL ? cg_state(c)->line_width : cg_num(widthv, "width");
    if (w <= 0) return W_FALSE;

    CGStateEntry *st = cg_state(c);
    if (!st->is_solid_butt) {
        CGContextSetLineCap(c->ctx, kCGLineCapButt);
        CGContextSetLineDash(c->ctx, 0, NULL, 0);
        st->is_solid_butt = 1;
    }
    if (w != st->line_width) {
        CGContextSetLineWidth(c->ctx, w);
        st->line_width = w;
    }
    cg_set_stroke(c, sc);

    if (a->ebits == -64) {
        const CGPoint *pts = (const CGPoint *)((const double *)a->slots + a->start);
        CGContextStrokeLineSegments(c->ctx, pts, (size_t)(2 * count));
        return W_TRUE;
    }
    CGPoint stack_pts[256];
    CGPoint *pts = count <= 128 ? stack_pts : (CGPoint *)malloc((size_t)(2 * count) * sizeof(CGPoint));
    if (!pts) cg_raise("Canvas.segments: out of memory");
    for (int64_t i = 0; i < 2 * count; i++) {
        pts[i].x = cg_num(cg_array_at(coordsv, 2 * i), "x");
        pts[i].y = cg_num(cg_array_at(coordsv, 2 * i + 1), "y");
    }
    CGContextStrokeLineSegments(c->ctx, pts, (size_t)(2 * count));
    if (pts != stack_pts) free(pts);
    return W_TRUE;
}

static CGGlyphMap *cg_glyph_map_for(CGCanvas *c, CTFontRef font) {
    CGGlyphMap *victim = &c->gmaps[0];
    for (int i = 0; i < 4; i++) {
        CGGlyphMap *gm = &c->gmaps[i];
        if (gm->font == font) {
            gm->stamp = ++c->line_clock;
            return gm;
        }
        if (!gm->font) { victim = gm; break; }
        if (gm->stamp < victim->stamp) victim = gm;
    }
    if (victim->font) CFRelease(victim->font);
    free(victim->smufl);
    memset(victim, 0, sizeof *victim);
    victim->font = (CTFontRef)CFRetain(font);
    victim->stamp = ++c->line_clock;
    return victim;
}

static CGGlyph cg_map_codepoint(CGGlyphMap *gm, uint32_t cp) {
    if (cp < 256) {
        if (!gm->ascii_ok) {
            UniChar uc[256];
            for (int i = 0; i < 256; i++) uc[i] = (UniChar)i;
            CTFontGetGlyphsForCharacters(gm->font, uc, gm->ascii, 256);
            gm->ascii_ok = 1;
        }
        return gm->ascii[cp];
    }
    if (cp >= 0xE000 && cp < 0xF800) {
        if (!gm->smufl_ok) {
            gm->smufl = calloc(0x1800, sizeof(CGGlyph));
            if (gm->smufl) {
                UniChar *uc = malloc(0x1800 * sizeof(UniChar));
                if (uc) {
                    for (int i = 0; i < 0x1800; i++) uc[i] = (UniChar)(0xE000 + i);
                    CTFontGetGlyphsForCharacters(gm->font, uc, gm->smufl, 0x1800);
                    free(uc);
                }
            }
            gm->smufl_ok = 1;
        }
        return gm->smufl ? gm->smufl[cp - 0xE000] : 0;
    }
    if (cp <= 0xFFFF) {
        UniChar u = (UniChar)cp;
        CGGlyph g = 0;
        CTFontGetGlyphsForCharacters(gm->font, &u, &g, 1);
        return g;
    }
    if (cp <= 0x10FFFF) {
        uint32_t v = cp - 0x10000;
        UniChar u[2] = { (UniChar)(0xD800 | (v >> 10)), (UniChar)(0xDC00 | (v & 0x3FF)) };
        CGGlyph g[2] = {0, 0};
        CTFontGetGlyphsForCharacters(gm->font, u, g, 2);
        return g[0];
    }
    return 0;
}

/* w_cg_glyphs(h, cps, xy, count, family, size, fill): draw `count` positioned
 * Unicode codepoints directly via CTFontDrawGlyphs with cached ASCII + SMuFL
 * (U+E000..U+F7FF) CGGlyph tables, bypassing string allocation and shaping. */
WValue w_cg_glyphs(WValue hv, WValue cpsv, WValue xyv, WValue countv, WValue famv, WValue sizev, WValue fillv) {
    CGCanvas *c = cg_canvas(hv, "glyphs");
    if (!w_is_array(cpsv) || !w_is_array(xyv))
        cg_raise("Canvas.glyphs: cps and xy must be Arrays");
    WArray *ca = w_as_array(cpsv);
    WArray *xa = w_as_array(xyv);
    int64_t count = countv == W_NIL ? (int64_t)ca->size : (int64_t)cg_num(countv, "count");
    if (count > (int64_t)ca->size) count = (int64_t)ca->size;
    if (count > (int64_t)xa->size / 2) count = (int64_t)xa->size / 2;
    if (count <= 0) return W_FALSE;

    double fc[4];
    if (!cg_color(fillv, fc, "fill") || fc[3] <= 0) return W_FALSE;

    CTFontRef font = NULL;
    int release_font = 0;
    if (famv == W_NIL && sizev == W_NIL) {
        font = c->font;
    } else {
        char sso[6];
        const char *fs = "Bravura";
        size_t fn = 7;
        if (famv != W_NIL && !cg_str_view(famv, sso, &fs, &fn))
            cg_raise("Canvas.glyphs: family must be a String");
        double sz = cg_num_or(sizev, c->font_size, "size");
        if (!(sz > 0)) cg_raise("Canvas.glyphs: size must be positive");
        font = cg_font_lookup(fs, fn, 400, 0, sz);
        release_font = 1;
    }

    CGGlyphMap *gm = cg_glyph_map_for(c, font);
    CGGlyph stack_g[256];
    CGPoint stack_p[256];
    CGGlyph *glyphs = count <= 256 ? stack_g : (CGGlyph *)malloc((size_t)count * sizeof(CGGlyph));
    CGPoint *pts    = count <= 256 ? stack_p : (CGPoint *)malloc((size_t)count * sizeof(CGPoint));
    if (!glyphs || !pts) {
        if (glyphs != stack_g) free(glyphs);
        if (pts != stack_p) free(pts);
        if (release_font) CFRelease(font);
        cg_raise("Canvas.glyphs: out of memory");
    }

    const int64_t *cp_i64 = (ca->ebits == 66 || ca->ebits == 64) ? ((const int64_t *)ca->slots + ca->start) : NULL;
    const int32_t *cp_i32 = (ca->ebits == 33 || ca->ebits == 32) ? ((const int32_t *)ca->slots + ca->start) : NULL;
    const double  *xy_f64 = (xa->ebits == -64) ? ((const double *)xa->slots + xa->start) : NULL;

    int64_t out_n = 0;
    for (int64_t i = 0; i < count; i++) {
        uint32_t cp;
        if (cp_i64) cp = (uint32_t)cp_i64[i];
        else if (cp_i32) cp = (uint32_t)cp_i32[i];
        else cp = (uint32_t)cg_num(cg_array_at(cpsv, i), "codepoint");
        CGGlyph g = cg_map_codepoint(gm, cp);
        if (g == 0) continue;
        double ux = xy_f64 ? xy_f64[2 * i]     : cg_num(cg_array_at(xyv, 2 * i), "x");
        double uy = xy_f64 ? xy_f64[2 * i + 1] : cg_num(cg_array_at(xyv, 2 * i + 1), "y");
        glyphs[out_n] = g;
        pts[out_n] = CGPointMake(ux, -uy);
        out_n++;
    }

    if (out_n > 0) {
        cg_set_fill(c, fc);
        CGContextSetTextDrawingMode(c->ctx, kCGTextFill);
        CGContextSetTextMatrix(c->ctx, CGAffineTransformMakeScale(1.0, -1.0));
        CTFontDrawGlyphs(font, glyphs, pts, (size_t)out_n, c->ctx);
    }

    if (glyphs != stack_g) free(glyphs);
    if (pts != stack_p) free(pts);
    if (release_font) CFRelease(font);
    return out_n > 0 ? W_TRUE : W_FALSE;
}

/* w_cg_write_pixels(buf, w, h, stride, path, bgra, quality): write a raw 8-bit
 * RGBA or BGRA pixel buffer (either a pointer Integer or a ByteArray/u32[])
 * directly via ImageIO without allocating a Canvas or copying rows. Passing
 * quality in [0, 0.5) writes PNG with IMAGEIO_PNG_NO_FILTERS. */
WValue w_cg_write_pixels(WValue bufv, WValue wv, WValue hv, WValue stridev, WValue pathv, WValue bgrav, WValue qv) {
    int64_t w = (int64_t)cg_num(wv, "width");
    int64_t h = (int64_t)cg_num(hv, "height");
    if (w <= 0 || h <= 0) cg_raise("Canvas.write_pixels: width and height must be positive");
    int64_t stride = stridev == W_NIL ? w * 4 : (int64_t)cg_num(stridev, "stride");
    if (stride < w * 4) cg_raise("Canvas.write_pixels: stride (%lld) < width * 4 (%lld)", (long long)stride, (long long)(w * 4));

    const void *ptr = NULL;
    size_t min_bytes = (size_t)(h - 1) * (size_t)stride + (size_t)w * 4;
    if (w_is_int(bufv)) {
        ptr = (const void *)(uintptr_t)w_as_int(bufv);
        if (!ptr) cg_raise("Canvas.write_pixels: null data pointer");
    } else if (w_is_array(bufv)) {
        WArray *a = w_as_array(bufv);
        size_t elem = a->ebits == 8 ? 1 : ((a->ebits == 32 || a->ebits == 33) ? 4 : 0);
        if (elem == 0) cg_raise("Canvas.write_pixels: buffer array must be ByteArray (u8[]) or u32[]/i32[]");
        size_t have = (size_t)a->size * elem;
        if (have < min_bytes) cg_raise("Canvas.write_pixels: buffer has %zu bytes, need %zu", have, min_bytes);
        ptr = (const uint8_t *)a->slots + (size_t)a->start * elem;
    } else {
        cg_raise("Canvas.write_pixels: buffer must be a ByteArray or data pointer Integer");
    }

    char path[4096];
    if (!cg_str(pathv, path, sizeof path) || path[0] == 0)
        cg_raise("Canvas.write_pixels: path must be a non-empty String");
    const char *ext = strrchr(path, '.');
    const char *type = "png";
    if (ext) {
        if (cg_eq(ext, ".jpg") || cg_eq(ext, ".jpeg")) type = "jpeg";
        else if (cg_eq(ext, ".tif") || cg_eq(ext, ".tiff")) type = "tiff";
        else if (cg_eq(ext, ".heic")) type = "heic";
    }
    CFStringRef uti = cg_uti(type);
    double q = cg_num_or(qv, -1.0, "quality");
    int bgra = cg_truthy(bgrav);
    CGBitmapInfo info = bgra
        ? ((CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst)
        : ((CGBitmapInfo)kCGBitmapByteOrder32Big    | (CGBitmapInfo)kCGImageAlphaPremultipliedLast);

    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, ptr, (size_t)h * (size_t)stride, NULL);
    if (!prov) cg_raise("Canvas.write_pixels: CGDataProviderCreateWithData failed");
    CGImageRef img = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)stride, cg_srgb(), info,
                                   prov, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(prov);
    if (!img) cg_raise("Canvas.write_pixels: CGImageCreate failed");

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef dest = url ? CGImageDestinationCreateWithURL(url, uti, 1, NULL) : NULL;
    if (url) CFRelease(url);
    if (!dest) {
        CGImageRelease(img);
        cg_raise("Canvas.write_pixels: cannot create %s", path);
    }
    CFDictionaryRef props = cg_dest_props(type, q);
    CGImageDestinationAddImage(dest, img, props);
    bool ok = CGImageDestinationFinalize(dest);
    if (props) CFRelease(props);
    CGImageRelease(img);
    CFRelease(dest);
    if (!ok) cg_raise("Canvas.write_pixels: ImageIO failed to write %s", path);
    return W_TRUE;
}

/* ---- C API ------------------------------------------------------------- */

int w_cg_canvas_buffer(int64_t handle, WCGBufferInfo *out) {
    int64_t slot = (handle & 0xFFFF) - 1;
    uint32_t gen = (uint32_t)(handle >> 16);
    if (slot < 0 || slot >= CG_MAX_CANVASES || !out) return 0;
    CGCanvas *c = __atomic_load_n(&g_canvases[slot], __ATOMIC_ACQUIRE);
    if (!c || c->gen != gen) return 0;
    CGContextFlush(c->ctx);
    out->data = c->data;
    out->width = c->pw;
    out->height = c->ph;
    out->stride = c->stride;
    out->bits_per_component = c->bpc;
    out->is_float = c->is_float;
    out->premultiplied = 1;
    out->space = g_spaces[c->space_index].name;
    out->cg_context = c->ctx;
    out->cg_colorspace = c->space;
    return 1;
}

WValue w_cg_available(void) { return W_TRUE; }

#else /* !__APPLE__ — raising stubs, generated from the same list */

#ifdef __APPLE__
#define CG_TARGET "this build (TUNGSTEN_QUARTZ_STUB)"
#elif defined(__linux__)
#define CG_TARGET "Linux"
#elif defined(__wasm__)
#define CG_TARGET "wasm"
#else
#define CG_TARGET "this platform"
#endif

__attribute__((noreturn))
static void cg_unavailable(const char *fn) {
    char buf[256];
    snprintf(buf, sizeof buf,
             "Canvas needs macOS CoreGraphics/CoreText: %s is not available on %s "
             "(runtime/quartz.c builds its drawing bridge only for Apple targets)",
             fn, CG_TARGET);
    w_raise(w_string(buf));
    abort();
}

#define W_CG_U __attribute__((unused)) WValue
#define W_CG_NAMED_0 void
#define W_CG_NAMED_1 W_CG_U a0
#define W_CG_NAMED_2 W_CG_NAMED_1, W_CG_U a1
#define W_CG_NAMED_3 W_CG_NAMED_2, W_CG_U a2
#define W_CG_NAMED_4 W_CG_NAMED_3, W_CG_U a3
#define W_CG_NAMED_5 W_CG_NAMED_4, W_CG_U a4
#define W_CG_NAMED_6 W_CG_NAMED_5, W_CG_U a5
#define W_CG_NAMED_7 W_CG_NAMED_6, W_CG_U a6
#define W_CG_NAMED_11 W_CG_NAMED_7, W_CG_U a7, W_CG_U a8, W_CG_U a9, W_CG_U a10
#define W_CG_NAMED_14 W_CG_NAMED_11, W_CG_U a11, W_CG_U a12, W_CG_U a13

#define W_CG_STUB(name, n) WValue name(W_CG_NAMED_##n) { cg_unavailable(#name); }
W_CG_CCALLS(W_CG_STUB)
#undef W_CG_STUB

int w_cg_canvas_buffer(int64_t handle, WCGBufferInfo *out) {
    (void)handle;
    (void)out;
    return 0;
}

WValue w_cg_available(void) { return W_FALSE; }

#endif

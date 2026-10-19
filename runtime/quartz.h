/* runtime/quartz.h — the CoreGraphics / CoreText / ImageIO drawing bridge.
 *
 * Two surfaces:
 *
 *   1. The ccall entry points (`w_cg_*`) behind core/canvas.w. Every one of
 *      them takes and returns NaN-boxed WValues, as ccall passes them; numbers
 *      arrive as boxed Floats/Ints/Decimals and are coerced in C. They are
 *      listed once, with their arity, in W_CG_CCALLS below. runtime/quartz.c
 *      implements them on Apple targets and generates raising stubs from the
 *      same list everywhere else, so a non-macOS program that uses Canvas
 *      links and then fails with a clear "needs macOS" error.
 *
 *   2. A plain C API for other runtime modules (future video encoders) that
 *      want a canvas's pixels without copying: w_cg_canvas_buffer.
 *
 * Linking: the compiler links runtime/quartz.c only when a program's LLVM IR
 * references a `@w_cg_` symbol (ll_needs_quartz in compiler/lib/driver/ir.w),
 * with -framework CoreGraphics/CoreText/ImageIO/CoreFoundation on macOS. A
 * Metal-only program never pulls these frameworks in, and a Canvas program
 * never pulls in Metal/AppKit. */

#ifndef TUNGSTEN_QUARTZ_H
#define TUNGSTEN_QUARTZ_H

#include <stddef.h>
#include <stdint.h>

/* ---- C API for other runtime modules ---------------------------------- */

typedef struct WCGBufferInfo {
    void       *data;               /* first byte of row 0 (the top row) */
    size_t      width;              /* pixels */
    size_t      height;             /* pixels */
    size_t      stride;             /* bytes per row (>= width * bytes per pixel) */
    int         bits_per_component; /* 8, 16 or 32 */
    int         is_float;           /* 1 for half (16) or float (32) components */
    int         premultiplied;      /* always 1: RGBA, alpha last, premultiplied */
    const char *space;              /* "srgb", "rec709", "display_p3", ... */
    void       *cg_context;         /* CGContextRef (borrowed) */
    void       *cg_colorspace;      /* CGColorSpaceRef (borrowed) */
} WCGBufferInfo;

/* Fill *out for the live canvas `handle` (the integer a Canvas holds in
 * @handle). Returns 1 on success, 0 if the handle is closed or unknown (or on
 * a non-Apple build). The buffer stays valid until the canvas is closed;
 * drawing into the canvas while an encoder reads it is the caller's race. */
int w_cg_canvas_buffer(int64_t handle, WCGBufferInfo *out);

/* ---- ccall entry points ------------------------------------------------ */

/* X(name, arity). w_cg_available is not listed: it exists on every target and
 * answers false instead of raising when the bridge is a stub. */
#define W_CG_CCALLS(X)            \
    X(w_cg_canvas_new, 6)         \
    X(w_cg_canvas_close, 1)       \
    X(w_cg_canvas_info, 2)        \
    X(w_cg_stats, 0)              \
    X(w_cg_save, 1)               \
    X(w_cg_restore, 1)            \
    X(w_cg_reset, 1)              \
    X(w_cg_translate, 3)          \
    X(w_cg_scale, 3)              \
    X(w_cg_rotate, 2)             \
    X(w_cg_concat, 7)             \
    X(w_cg_ctm, 1)                \
    X(w_cg_set_alpha, 2)          \
    X(w_cg_set_blend, 2)          \
    X(w_cg_set_quality, 2)        \
    X(w_cg_set_antialias, 2)      \
    X(w_cg_path_begin, 1)         \
    X(w_cg_move_to, 3)            \
    X(w_cg_line_to, 3)            \
    X(w_cg_quad_to, 5)            \
    X(w_cg_curve_to, 7)           \
    X(w_cg_arc, 7)                \
    X(w_cg_arc_to, 6)             \
    X(w_cg_path_close, 1)         \
    X(w_cg_add_rect, 5)           \
    X(w_cg_add_round_rect, 7)     \
    X(w_cg_add_ellipse, 5)        \
    X(w_cg_add_svg, 2)            \
    X(w_cg_add_points, 3)         \
    X(w_cg_path_bounds, 1)        \
    X(w_cg_path_contains, 4)      \
    X(w_cg_set_line, 7)           \
    X(w_cg_paint, 7)              \
    X(w_cg_gradient, 14)          \
    X(w_cg_clip, 2)               \
    X(w_cg_layer_begin, 2)        \
    X(w_cg_layer_end, 1)          \
    X(w_cg_font_name, 3)          \
    X(w_cg_text_style, 6)         \
    X(w_cg_text, 11)              \
    X(w_cg_text_clip, 6)          \
    X(w_cg_text_measure, 2)       \
    X(w_cg_image_load, 1)         \
    X(w_cg_image_from_canvas, 1)  \
    X(w_cg_image_info, 2)         \
    X(w_cg_image_draw, 14)        \
    X(w_cg_image_bytes, 1)        \
    X(w_cg_image_release, 1)      \
    X(w_cg_image_purge, 0)        \
    X(w_cg_clear, 2)              \
    X(w_cg_pixel, 3)              \
    X(w_cg_bytes, 2)              \
    X(w_cg_to_raster, 3)          \
    X(w_cg_data_ptr, 1)           \
    X(w_cg_write, 5)              \
    X(w_cg_encode, 4)

#define W_CG_PARAMS_0 void
#define W_CG_PARAMS_1 WValue
#define W_CG_PARAMS_2 WValue, WValue
#define W_CG_PARAMS_3 WValue, WValue, WValue
#define W_CG_PARAMS_4 WValue, WValue, WValue, WValue
#define W_CG_PARAMS_5 WValue, WValue, WValue, WValue, WValue
#define W_CG_PARAMS_6 WValue, WValue, WValue, WValue, WValue, WValue
#define W_CG_PARAMS_7 WValue, WValue, WValue, WValue, WValue, WValue, WValue
#define W_CG_PARAMS_11 W_CG_PARAMS_7, WValue, WValue, WValue, WValue
#define W_CG_PARAMS_14 W_CG_PARAMS_7, W_CG_PARAMS_7

#ifdef WVALUE_H
WValue w_cg_available(void);
#define W_CG_PROTOTYPE(name, n) WValue name(W_CG_PARAMS_##n);
W_CG_CCALLS(W_CG_PROTOTYPE)
#undef W_CG_PROTOTYPE
#endif

#endif /* TUNGSTEN_QUARTZ_H */

/* runtime/graphics.m — Obj-C windowing + present bridge for Tungsten.
 *
 * The Metal bridge in runtime/metal.m is compute-only: it dispatches
 * `@gpu fn` kernels into buffers, with no way to put pixels on screen.
 * This file adds the missing windowing half — a real Cocoa NSWindow
 * backed by a CAMetalLayer — so a Tungsten program can:
 *
 *   1. open a window               (w_gfx_window_new, w_gfx_window_open)
 *   2. pump OS events / input      (w_gfx_poll, w_gfx_wait, w_gfx_key_down, …)
 *   3. blit a pixel buffer to it   (w_gfx_present, w_gfx_present_wait)
 *
 * The rendering model is deliberately minimal and reuses the existing
 * compute path: a `@gpu` kernel (or a CPU renderer) writes one pixel per
 * thread into a shared MTLBuffer (one uint per pixel), and w_gfx_present
 * copies that buffer into the next drawable with a blit encoder and
 * presents it. No vertex/fragment pipeline, no render pass — just
 * compute → buffer → blit → screen. On Apple Silicon's unified memory
 * the buffer the kernel wrote and the blit source are the same bytes.
 *
 * Compiled only on darwin (gated in compiler/tungsten.w + runtime/Makefile)
 * and linked with -framework AppKit -framework QuartzCore -framework Metal.
 *
 * Lifetime: like metal.m, v1 leaks the window/queue (a graphics demo
 * holds one window for its whole run).
 *
 * Two input models share one view:
 *
 *  - Game style (unchanged since v1): the view records key state into a
 *    256-entry pressed[] table keyed by hardware keyCode (so WASD tracks
 *    physical key positions regardless of layout) and accumulates relative
 *    mouse motion; w_gfx_mouse_dx/dy return the delta since the last read
 *    and reset it.
 *
 *  - Editor style (2026-11-04): every input also lands in a per-window event
 *    queue (w_gfx_next_event + w_gfx_event_* read it): key down/up with
 *    modifiers and repeat, typed text, mouse down/up/move/drag at absolute
 *    positions (points from the content's top-left) with button and click
 *    count, scroll and trackpad deltas (precise flag, phases), pinch
 *    magnification, resize and backing-scale changes, close requests, menu
 *    commands and focus. Consecutive moves, drags and scrolls coalesce, and
 *    a full queue drops its oldest event.
 *
 * Windows opened with w_gfx_window_open take flags: GFX_HIDPI (the drawable
 * follows the view's size times the backing scale, so a Retina window
 * presents full-resolution pixels), GFX_HIDDEN (never shown or activated:
 * specs and headless runs), GFX_BGRA (a BGRA8 layer, so CoreGraphics or
 * cairo pixels present without a swizzle), GFX_KEEP_OPEN (the close button
 * and Quit post a close event and leave the window to the program, which
 * may ask about unsaved work and then call w_gfx_close).
 *
 * Also here: the menu bar (w_gfx_menu_add / w_gfx_menu_set; an app menu
 * with Hide and Quit is made on first use), open and save panels
 * (w_gfx_open_panel / w_gfx_save_panel, modal; w_gfx_panel_answer scripts
 * the next one), alerts (w_gfx_alert; w_gfx_alert_answer), the cursor, the title, the content size, and
 * w_gfx_post_event, which builds a real NSEvent and hands it to the view's
 * handlers (specs and scripted UI runs). */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <objc/message.h>
#include "runtime.h"
#include "wvalue.h"

/* ---- Event queue (editor-style input) ---- */

enum {
    GFX_EV_NONE = 0, GFX_EV_KEY_DOWN = 1, GFX_EV_KEY_UP = 2, GFX_EV_TEXT = 3,
    GFX_EV_MOUSE_DOWN = 4, GFX_EV_MOUSE_UP = 5, GFX_EV_MOUSE_MOVE = 6,
    GFX_EV_MOUSE_DRAG = 7, GFX_EV_SCROLL = 8, GFX_EV_MAGNIFY = 9,
    GFX_EV_RESIZE = 10, GFX_EV_CLOSE = 11, GFX_EV_MENU = 12, GFX_EV_FOCUS = 13,
    GFX_EV_MODS = 14, GFX_EV_OPEN = 15
};

enum { GFX_MOD_SHIFT = 1, GFX_MOD_CTRL = 2, GFX_MOD_ALT = 4, GFX_MOD_CMD = 8,
       GFX_MOD_CAPS = 16, GFX_MOD_FN = 32 };

enum { GFX_HIDPI = 1, GFX_HIDDEN = 2, GFX_BGRA = 4, GFX_KEEP_OPEN = 8, GFX_DROP_FILES = 16 };

/* the menu event ids of the standard items the runtime makes (Settings..., <App> Help) */
enum { GFX_MENU_SETTINGS = -2, GFX_MENU_HELP = -3 };

#define GFX_QUEUE_CAP 1024
#define GFX_TEXT_CAP 64

typedef struct GfxEvent {
    int    kind;
    double x, y;          /* points from the content's top-left */
    double dx, dy;        /* scroll / drag deltas (points), magnification in dx */
    int    button;        /* 0 left, 1 right, 2+ other */
    int    clicks;        /* click count (double click = 2) */
    int    mods;          /* GFX_MOD_* */
    int    key;           /* hardware keyCode */
    int    repeat;        /* key auto-repeat */
    int    phase;         /* scroll/magnify: 0 none, 1 began, 2 changed, 3 ended, 4 momentum */
    int    precise;       /* scroll: trackpad/precise deltas */
    double w, h, scale;   /* resize: content points and backing scale */
    int64_t id;           /* menu command id; focus 1/0; close 1 = Quit */
    char   text[GFX_TEXT_CAP]; /* UTF-8: typed text, or the key's characters */
} GfxEvent;

/* ---- Input state shared between the view and the C bridge ---- */

typedef struct GfxInput {
    bool   pressed[256];   /* keyed by NSEvent.keyCode */
    double mouse_dx;       /* accumulated since last read, then zeroed */
    double mouse_dy;
    bool   should_close;   /* set on window close */
    bool   mouse_captured;
    /* editor-style queue */
    GfxEvent q[GFX_QUEUE_CAP];
    int    qhead, qcount;
    GfxEvent cur;          /* the event w_gfx_next_event returned */
    int    last_mods;
    double mouse_x, mouse_y;
    int    synth;          /* a posted scroll's position (w_gfx_post_event) */
    double synth_x, synth_y;
} GfxInput;

static void gfx_push(GfxInput *in, const GfxEvent *e) {
    if (!in) return;
    /* coalesce a run of moves, drags or scrolls into the newest */
    if (in->qcount > 0) {
        GfxEvent *last = &in->q[(in->qhead + in->qcount - 1) % GFX_QUEUE_CAP];
        if (last->kind == e->kind && last->mods == e->mods &&
            ((e->kind == GFX_EV_MOUSE_MOVE) ||
             (e->kind == GFX_EV_MOUSE_DRAG && last->button == e->button) ||
             (e->kind == GFX_EV_SCROLL && last->phase == e->phase && last->precise == e->precise))) {
            double dx = last->dx + e->dx, dy = last->dy + e->dy;
            *last = *e;
            last->dx = dx; last->dy = dy;
            return;
        }
    }
    if (in->qcount == GFX_QUEUE_CAP) {          /* full: drop the oldest */
        in->qhead = (in->qhead + 1) % GFX_QUEUE_CAP;
        in->qcount--;
    }
    in->q[(in->qhead + in->qcount) % GFX_QUEUE_CAP] = *e;
    in->qcount++;
}

static int gfx_mods_of(NSEventModifierFlags f) {
    int m = 0;
    if (f & NSEventModifierFlagShift)    m |= GFX_MOD_SHIFT;
    if (f & NSEventModifierFlagControl)  m |= GFX_MOD_CTRL;
    if (f & NSEventModifierFlagOption)   m |= GFX_MOD_ALT;
    if (f & NSEventModifierFlagCommand)  m |= GFX_MOD_CMD;
    if (f & NSEventModifierFlagCapsLock) m |= GFX_MOD_CAPS;
    if (f & NSEventModifierFlagFunction) m |= GFX_MOD_FN;
    return m;
}

static NSEventModifierFlags gfx_flags_of(int m) {
    NSEventModifierFlags f = 0;
    if (m & GFX_MOD_SHIFT) f |= NSEventModifierFlagShift;
    if (m & GFX_MOD_CTRL)  f |= NSEventModifierFlagControl;
    if (m & GFX_MOD_ALT)   f |= NSEventModifierFlagOption;
    if (m & GFX_MOD_CMD)   f |= NSEventModifierFlagCommand;
    if (m & GFX_MOD_CAPS)  f |= NSEventModifierFlagCapsLock;
    if (m & GFX_MOD_FN)    f |= NSEventModifierFlagFunction;
    return f;
}

static void gfx_copy_text(char *dst, NSString *s) {
    dst[0] = 0;
    if (!s) return;
    const char *u = [s UTF8String];
    if (!u) return;
    size_t n = strlen(u);
    if (n >= GFX_TEXT_CAP) {                 /* cut at a character boundary */
        n = GFX_TEXT_CAP - 1;
        while (n > 0 && (((unsigned char)u[n]) & 0xC0) == 0x80) n--;
    }
    memcpy(dst, u, n);
    dst[n] = 0;
}

/* typed text: printable characters only (no control keys, no arrows or
 * other function keys in the private-use range), and not a shortcut */
static bool gfx_is_text(NSString *s, int mods) {
    if (!s || [s length] == 0) return false;
    if (mods & (GFX_MOD_CMD | GFX_MOD_CTRL)) return false;
    unichar c = [s characterAtIndex:0];
    if (c < 0x20 || c == 0x7F) return false;
    if (c >= 0xF700 && c <= 0xF8FF) return false;
    return true;
}

/* ---- The content view: first responder for key + mouse events ---- */

static BOOL gfx_drop_received(NSView *view, NSArray *urls);

@interface TungstenView : NSView
@property (nonatomic, assign) GfxInput *input;
@property (nonatomic, retain) NSTrackingArea *hoverTracking;
@end

@implementation TungstenView
- (NSArray *)gfxDraggedFileURLs:(id<NSDraggingInfo>)sender {
    if (!self.input || ![[self registeredDraggedTypes] containsObject:NSPasteboardTypeFileURL]) return @[];
    return [[sender draggingPasteboard] readObjectsForClasses:@[[NSURL class]]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ?: @[];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (!([sender draggingSourceOperationMask] & NSDragOperationCopy)) return NSDragOperationNone;
    return [[self gfxDraggedFileURLs:sender] count] ? NSDragOperationCopy : NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return [self draggingEntered:sender]; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return [self draggingEntered:sender] != NSDragOperationNone; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    if ([self draggingEntered:sender] == NSDragOperationNone) return NO;
    return gfx_drop_received(self, [self gfxDraggedFileURLs:sender]);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTracking) [self removeTrackingArea:self.hoverTracking];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    self.hoverTracking = area;
    [self addTrackingArea:area];
    [area release];
}
- (void)dealloc {
    if (_hoverTracking) [self removeTrackingArea:_hoverTracking];
    [_hoverTracking release];
    [super dealloc];
}
- (void)mouseEntered:(NSEvent *)ev {
    [self gfxMouse:ev kind:GFX_EV_MOUSE_MOVE button:0];
}
- (void)mouseExited:(NSEvent *)ev {
    if (!self.input) return;
    self.input->mouse_x = -1.0; self.input->mouse_y = -1.0;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_MOUSE_MOVE; e.x = -1.0; e.y = -1.0;
    e.mods = gfx_mods_of([ev modifierFlags]);
    gfx_push(self.input, &e);
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)ev { (void)ev; return YES; }

/* an event's position in points from the content's top-left */
- (NSPoint)gfxPoint:(NSEvent *)ev {
    NSPoint p = [self convertPoint:[ev locationInWindow] fromView:nil];
    return NSMakePoint(p.x, [self bounds].size.height - p.y);
}

- (void)keyDown:(NSEvent *)ev {
    /* Swallow the event (no super call) so the system doesn't beep on
     * keys we handle ourselves. Repeats keep pressed[] true. */
    NSUInteger code = [ev keyCode];
    if (self.input && code < 256) self.input->pressed[code] = true;
    if (!self.input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_KEY_DOWN;
    e.key = (int)code;
    e.mods = gfx_mods_of([ev modifierFlags]);
    e.repeat = [ev isARepeat] ? 1 : 0;
    e.x = self.input->mouse_x; e.y = self.input->mouse_y;
    gfx_copy_text(e.text, [ev charactersIgnoringModifiers]);
    gfx_push(self.input, &e);
    NSString *chars = [ev characters];
    if (gfx_is_text(chars, e.mods)) {
        GfxEvent t = e;
        t.kind = GFX_EV_TEXT;
        gfx_copy_text(t.text, chars);
        gfx_push(self.input, &t);
    }
}
- (void)keyUp:(NSEvent *)ev {
    NSUInteger code = [ev keyCode];
    if (self.input && code < 256) self.input->pressed[code] = false;
    if (!self.input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_KEY_UP;
    e.key = (int)code;
    e.mods = gfx_mods_of([ev modifierFlags]);
    e.x = self.input->mouse_x; e.y = self.input->mouse_y;
    gfx_copy_text(e.text, [ev charactersIgnoringModifiers]);
    gfx_push(self.input, &e);
}
- (void)flagsChanged:(NSEvent *)ev {
    NSUInteger code = [ev keyCode];
    int m = gfx_mods_of([ev modifierFlags]);
    if (self.input && code < 256) {
        /* modifier keys have no keyUp: held = its flag is set */
        int bit = 0;
        if (code == 56 || code == 60) bit = GFX_MOD_SHIFT;
        else if (code == 59 || code == 62) bit = GFX_MOD_CTRL;
        else if (code == 58 || code == 61) bit = GFX_MOD_ALT;
        else if (code == 55 || code == 54) bit = GFX_MOD_CMD;
        if (bit) self.input->pressed[code] = (m & bit) != 0;
    }
    if (!self.input) return;
    if (m == self.input->last_mods) return;
    self.input->last_mods = m;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_MODS;
    e.key = (int)code;
    e.mods = m;
    e.x = self.input->mouse_x; e.y = self.input->mouse_y;
    gfx_push(self.input, &e);
}

- (void)gfxMouse:(NSEvent *)ev kind:(int)kind button:(int)button {
    if (!self.input) return;
    NSPoint p = [self gfxPoint:ev];
    self.input->mouse_x = p.x; self.input->mouse_y = p.y;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = kind;
    e.x = p.x; e.y = p.y;
    e.button = button;
    e.mods = gfx_mods_of([ev modifierFlags]);
    if (kind == GFX_EV_MOUSE_DOWN || kind == GFX_EV_MOUSE_UP) e.clicks = (int)[ev clickCount];
    if (kind == GFX_EV_MOUSE_MOVE || kind == GFX_EV_MOUSE_DRAG) { e.dx = [ev deltaX]; e.dy = [ev deltaY]; }
    gfx_push(self.input, &e);
}

- (void)mouseMoved:(NSEvent *)ev {
    if (self.input) { self.input->mouse_dx += [ev deltaX]; self.input->mouse_dy += [ev deltaY]; }
    [self gfxMouse:ev kind:GFX_EV_MOUSE_MOVE button:0];
}
/* Track motion while a button is held too, so drag-look works. */
- (void)mouseDragged:(NSEvent *)ev {
    if (self.input) { self.input->mouse_dx += [ev deltaX]; self.input->mouse_dy += [ev deltaY]; }
    [self gfxMouse:ev kind:GFX_EV_MOUSE_DRAG button:0];
}
- (void)rightMouseDragged:(NSEvent *)ev {
    if (self.input) { self.input->mouse_dx += [ev deltaX]; self.input->mouse_dy += [ev deltaY]; }
    [self gfxMouse:ev kind:GFX_EV_MOUSE_DRAG button:1];
}
- (void)otherMouseDragged:(NSEvent *)ev {
    if (self.input) { self.input->mouse_dx += [ev deltaX]; self.input->mouse_dy += [ev deltaY]; }
    [self gfxMouse:ev kind:GFX_EV_MOUSE_DRAG button:(int)[ev buttonNumber]];
}
- (void)mouseDown:(NSEvent *)ev        { [self gfxMouse:ev kind:GFX_EV_MOUSE_DOWN button:0]; }
- (void)mouseUp:(NSEvent *)ev          { [self gfxMouse:ev kind:GFX_EV_MOUSE_UP button:0]; }
- (void)rightMouseDown:(NSEvent *)ev   { [self gfxMouse:ev kind:GFX_EV_MOUSE_DOWN button:1]; }
- (void)rightMouseUp:(NSEvent *)ev     { [self gfxMouse:ev kind:GFX_EV_MOUSE_UP button:1]; }
- (void)otherMouseDown:(NSEvent *)ev   { [self gfxMouse:ev kind:GFX_EV_MOUSE_DOWN button:(int)[ev buttonNumber]]; }
- (void)otherMouseUp:(NSEvent *)ev     { [self gfxMouse:ev kind:GFX_EV_MOUSE_UP button:(int)[ev buttonNumber]]; }

static int gfx_phase_of(NSEventPhase ph, NSEventPhase mom) {
    if (mom != NSEventPhaseNone) return 4;
    if (ph & NSEventPhaseBegan) return 1;
    if (ph & (NSEventPhaseEnded | NSEventPhaseCancelled)) return 3;
    if (ph & NSEventPhaseChanged) return 2;
    return 0;
}

- (void)scrollWheel:(NSEvent *)ev {
    if (!self.input) return;
    NSPoint p;
    if (self.input->synth) p = NSMakePoint(self.input->synth_x, self.input->synth_y);
    else p = [self gfxPoint:ev];
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_SCROLL;
    e.x = p.x; e.y = p.y;
    e.precise = [ev hasPreciseScrollingDeltas] ? 1 : 0;
    /* wheel clicks arrive in lines: report points (10 a line), as AppKit's scroll views do */
    double k = e.precise ? 1.0 : 10.0;
    e.dx = [ev scrollingDeltaX] * k;
    e.dy = [ev scrollingDeltaY] * k;
    e.mods = gfx_mods_of([ev modifierFlags]);
    e.phase = gfx_phase_of([ev phase], [ev momentumPhase]);
    gfx_push(self.input, &e);
}

- (void)magnifyWithEvent:(NSEvent *)ev {
    if (!self.input) return;
    NSPoint p = [self gfxPoint:ev];
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_MAGNIFY;
    e.x = p.x; e.y = p.y;
    e.dx = [ev magnification];
    e.mods = gfx_mods_of([ev modifierFlags]);
    e.phase = gfx_phase_of([ev phase], NSEventPhaseNone);
    gfx_push(self.input, &e);
}
@end

/* ---- Boxed window handle (same convention as runtime/metal.m) ---- */

#define GFX_MAX_TEX 1024

typedef struct WGfxWindow {
    uint8_t type;             /* W_TYPE_GFX_WINDOW */
    void   *window;           /* NSWindow*           (retained) */
    void   *layer;            /* CAMetalLayer*       (retained) */
    void   *view;             /* TungstenView*       (retained) */
    void   *delegate;         /* window delegate     (retained) */
    void   *device;           /* id<MTLDevice>       (retained) */
    void   *queue;            /* id<MTLCommandQueue> (retained, for blits) */
    int32_t width;            /* drawable width  in pixels */
    int32_t height;           /* drawable height in pixels */
    int32_t flags;            /* GFX_* (w_gfx_window_open); 0 for w_gfx_window_new */
    bool    closed;           /* w_gfx_close ran */
    double  scale;            /* backing scale the drawable follows (GFX_HIDPI) */
    char   *panel_answer;     /* the next panel's scripted answer (w_gfx_panel_answer) */
    bool    panel_scripted;
    int     alert_answer;     /* the next alert's scripted answer (w_gfx_alert_answer) */
    bool    alert_scripted;
    bool    prompt_scripted;  /* the next prompt / choice's scripted answer (w_gfx_prompt_answer) */
    int     prompt_button;
    int     prompt_item;
    char   *prompt_text;
    NSArray *form_values; /* owned immutable strings: safe across runtime GC */
    bool    menu_scripted;    /* the next context menu's scripted answer (w_gfx_context_menu_answer) */
    int     menu_answer;
    int     form_button;
    /* GPU layer/quad compositor state */
    void   *pso_tile;         /* id<MTLRenderPipelineState> programmable tile blend */
    void   *pso_alpha;        /* id<MTLRenderPipelineState> fixed-function fallback */
    void   *sampler;          /* id<MTLSamplerState> linear/nearest clamp */
    void   *dummy_tex;        /* 1x1 white MTLTexture bound when a quad has no tex */
    void   *quad_buf[3];      /* triple-buffered shared GfxQuad instance buffers */
    size_t  quad_cap[3];
    dispatch_semaphore_t frame_sem;
    uint64_t next_cb_seq;
    uint64_t done_cb_seq;
    void    *tex[GFX_MAX_TEX];
    uint64_t tex_used_seq[GFX_MAX_TEX];
    uint8_t  tex_bgra[GFX_MAX_TEX];
    /* planar Y'CbCr video textures (w_gfx_tex_new_yuv): tex[slot] is the luma
     * plane, tex_cb/tex_cr the chroma planes; tex_yuv the shader's conversion
     * parameters (GfxYuv); tex_fmt the plane pixel format (0 R8, 1 R16). */
    void    *tex_cb[GFX_MAX_TEX];
    void    *tex_cr[GFX_MAX_TEX];
    float    tex_yuv[GFX_MAX_TEX][24];
    uint8_t  tex_planar[GFX_MAX_TEX];
    uint8_t  tex_fmt[GFX_MAX_TEX];
    /* yuv slots drawn straight from a decoder's CVPixelBuffer (w_gfx_tex_set_surface):
     * [CVMetalTexture luma, CVMetalTexture chroma, CVPixelBuffer]; tex_cb == tex_cr then
     * (the interleaved CbCr plane). A replaced surface the GPU may still be sampling
     * waits in surf_dead until its command buffer completes. */
    void    *tex_surf[GFX_MAX_TEX][3];
    void    *cv_cache;
    struct { uint64_t seq; void *r[3]; } surf_dead[64];
    int      n_surf_dead;
    /* colour management: the layer's colour space (0 sRGB, 1 Display P3) and
     * each RGBA texture's (0 sRGB: converted by the shader when the layer is
     * P3; 1 Display P3: drawn as is) */
    int      out_space;
    uint8_t  tex_space[GFX_MAX_TEX];
    void    *sampler_lin;      /* id<MTLSamplerState> bilinear clamp (video planes) */
    bool     capture_next;     /* w_gfx_capture_next: copy the next present_layers frame back */
    void    *capture_buf;      /* id<MTLBuffer> the captured frame (drawable pixel format) */
    int32_t  capture_w, capture_h;
    GfxInput input;
} WGfxWindow;

static void gfx_surf_release3(void **r);
static void gfx_surf_retire(WGfxWindow *gw, int slot);

static WGfxWindow *as_gfx_window(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WGfxWindow *w = (WGfxWindow *)w_as_ptr(v);
    if (w->type != W_TYPE_GFX_WINDOW) return NULL;
    return w;
}

static WGfxWindow *gfx_active_window = NULL;
static void gfx_activate_window(WGfxWindow *gw);
static GfxInput *gfx_menu_input(GfxInput *fallback);
static void gfx_retarget_closed(WGfxWindow *gw);

/* Size the drawable from the view (GFX_HIDPI): points x backing scale. */
static void gfx_fit_drawable(WGfxWindow *gw) {
    if (!(gw->flags & GFX_HIDPI) || !gw->view || !gw->window) return;
    NSView *view = (NSView *)gw->view;
    NSWindow *win = (NSWindow *)gw->window;
    double s = [win backingScaleFactor];
    if (s <= 0) s = 1.0;
    NSSize sz = [view bounds].size;
    int pw = (int)(sz.width * s + 0.5), ph = (int)(sz.height * s + 0.5);
    if (pw < 1) pw = 1;
    if (ph < 1) ph = 1;
    CAMetalLayer *layer = (CAMetalLayer *)gw->layer;
    layer.contentsScale = s;
    layer.contentsGravity = [layer contentsAreFlipped] ? kCAGravityBottomLeft : kCAGravityTopLeft;
    layer.drawableSize = CGSizeMake(pw, ph);
    gw->width = pw;
    gw->height = ph;
    gw->scale = s;
}

static void gfx_push_resize(WGfxWindow *gw) {
    NSView *view = (NSView *)gw->view;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_RESIZE;
    NSSize sz = [view bounds].size;
    e.w = sz.width; e.h = sz.height;
    e.scale = (gw->flags & GFX_HIDPI) ? gw->scale : 1.0;
    gfx_push(&gw->input, &e);
}

/* ---- Window delegate: close, resize, backing scale, focus ---- */

@interface TungstenWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) GfxInput *input;
@property (nonatomic, assign) WGfxWindow *gw;
@end

@implementation TungstenWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    if (self.gw && (self.gw->flags & GFX_KEEP_OPEN)) {
        /* the program decides: a close event, and the window stays */
        if (self.input) {
            self.input->should_close = true;
            GfxEvent e; memset(&e, 0, sizeof e);
            e.kind = GFX_EV_CLOSE;
            gfx_push(self.input, &e);
        }
        return NO;
    }
    return YES;
}
- (void)windowWillClose:(NSNotification *)note {
    (void)note;
    if (self.input) self.input->should_close = true;
}
- (void)windowDidResize:(NSNotification *)note {
    (void)note;
    if (!self.gw) return;
    gfx_fit_drawable(self.gw);
    gfx_push_resize(self.gw);
}
- (void)windowDidChangeBackingProperties:(NSNotification *)note {
    (void)note;
    if (!self.gw) return;
    gfx_fit_drawable(self.gw);
    gfx_push_resize(self.gw);
}
- (void)windowDidBecomeKey:(NSNotification *)note {
    (void)note;
    if (self.gw) gfx_activate_window(self.gw);
    if (!self.input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_FOCUS; e.id = 1;
    gfx_push(self.input, &e);
}
- (void)windowDidResignKey:(NSNotification *)note {
    (void)note;
    if (!self.input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_FOCUS; e.id = 0;
    gfx_push(self.input, &e);
}
@end

/* Pull the id<MTLDevice> out of a WMetalDevice WValue (defined in
 * runtime.h, boxed by runtime/metal.m). */
static id<MTLDevice> gfx_device_handle(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return nil;
    WMetalDevice *d = (WMetalDevice *)w_as_ptr(v);
    if (d->type != W_TYPE_METAL_DEVICE) return nil;
    return (id<MTLDevice>)d->handle;
}

static NSString *gfx_string_or(WValue v, NSString *dflt) {
    /* Concatenated strings can be ropes. AppKit needs their UTF-8 bytes just
     * as it needs a flat String's; rejecting the representation blanked long
     * recent-file labels, dialog text and other dynamically built titles. */
    if (w_is_rope(v)) v = w_rope_flatten(v);
    if (!w_is_string(v)) return dflt;
    char buf[6];
    const char *s = NULL; size_t len = 0;
    w_str_data(v, buf, &s, &len);
    if (!s) return dflt;
    NSString *r = [[[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding] autorelease];
    return r ? r : dflt;
}

static NSString *gfx_string(WValue v) { return gfx_string_or(v, @"Tungsten"); }

/* An int argument. ccall passes an int literal raw (unboxed; see the ABI
 * note in compiler/lib/lowering/calls.w) and a variable boxed, so read both:
 * a boxed int, a double, else a raw small int (w_as_int ignores the tag). */
static int64_t gfx_int(WValue v) {
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_double(v)) return (int64_t)w_as_double(v);
    return w_as_int(v);
}

static double gfx_num(WValue v, const char *what) {
    (void)what;
    if (w_is_double(v)) return w_as_double(v);
    return (double)gfx_int(v);
}

/* Ensure NSApp exists and is a GUI app even though we were launched as a
 * plain CLI binary (no .app bundle). Idempotent. A first window that is
 * hidden (specs, headless runs) makes an accessory app that never takes
 * focus or shows in the Dock; a visible window later promotes it. */
static void gfx_install_app_delegate(void);
static void gfx_open_target(WGfxWindow *gw);
static NSMutableArray *gfx_open_paths = nil;     /* every path an open-documents request named, by event id */
static NSUInteger gfx_open_queued = 0;           /* how many of them are queued as GFX_EV_OPEN events */
static WGfxWindow *gfx_open_window = NULL;       /* the active document window, or the first at launch */

static void gfx_ensure_app_visible(bool visible) {
    static bool started = false;
    static bool regular = false;
    if (!started) {
        started = true;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:(visible ? NSApplicationActivationPolicyRegular
                                            : NSApplicationActivationPolicyAccessory)];
        /* the delegate before finishLaunching: the documents an app is launched with (a double-click in Finder, `open`) come
         * as an open-documents Apple event during launch, and without a delegate that takes them AppKit hands them to
         * NSDocumentController, which has no document class and says the app cannot open files of that format */
        gfx_install_app_delegate();
        [NSApp finishLaunching];
        regular = visible;
        if (visible) [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    if (visible && !regular) {
        regular = true;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

static void gfx_ensure_app(void) { gfx_ensure_app_visible(true); }

static void gfx_require_main_thread(const char *operation) {
    if (![NSThread isMainThread]) {
        char message[256];
        snprintf(message, sizeof(message), "%s: must run on the process main thread",
                 operation);
        w_raise(w_string(message));
    }
}

static WGfxWindow *gfx_window_arg(WValue v, const char *operation) {
    WGfxWindow *gw = as_gfx_window(v);
    if (!gw) {
        char message[160];
        snprintf(message, sizeof(message), "%s: not a window", operation);
        w_raise(w_string(message));
    }
    return gw;
}

/* ---- opening a window ---- */

static WValue gfx_open(WValue device_v, WValue title_v, int w, int h, int flags, const char *op) {
    id<MTLDevice> dev = gfx_device_handle(device_v);
    if (!dev) {
        char message[160];
        snprintf(message, sizeof(message), "%s: first arg must be a Metal device", op);
        w_raise(w_string(message));
    }
    if (w <= 0 || h <= 0) {
        char message[160];
        snprintf(message, sizeof(message), "%s: width/height must be positive", op);
        w_raise(w_string(message));
    }

    gfx_require_main_thread(op);
    gfx_ensure_app_visible(!(flags & GFX_HIDDEN));

    WGfxWindow *gw = (WGfxWindow *)calloc(1, sizeof(WGfxWindow));
    gw->type = W_TYPE_GFX_WINDOW;
    gw->width = w;
    gw->height = h;
    gw->flags = flags;
    gw->scale = 1.0;
    gw->device = (void *)[dev retain];

    __block WGfxWindow *captured = gw;
    /* All AppKit work remains on the process main thread. */
    void (^build)(void) = ^{
        NSRect frame = NSMakeRect(0, 0, captured->width, captured->height);
        NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable |
                                  NSWindowStyleMaskResizable;
        NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:style
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        [win setTitle:gfx_string(title_v)];
        [win center];
        /* the handle keeps the window: a closed window stays a valid object
         * (calls on it after a close are harmless, never a freed pointer) */
        [win setReleasedWhenClosed:NO];

        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = (id<MTLDevice>)captured->device;
        layer.pixelFormat = (flags & GFX_BGRA) ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA8Unorm;
        layer.framebufferOnly = NO;     /* allow blit-into-drawable */
        /* the pixels are sRGB unless gfx_set_color_space says otherwise: tag
         * them, so the window server matches them to the display (a nil
         * colorspace sends sRGB code values to a P3 panel unconverted) */
        {
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            layer.colorspace = cs;
            CGColorSpaceRelease(cs);
        }
        layer.drawableSize = CGSizeMake(captured->width, captured->height);
        layer.opaque = YES;
        /* Keep the last presented pixels at their native scale while AppKit
         * tracks a live resize. The default resize gravity stretches the old
         * frame, including fixed-width editor sidebars, before the next frame. */
        layer.contentsGravity = kCAGravityTopLeft;
        layer.actions = @{ @"bounds": [NSNull null], @"position": [NSNull null],
                           @"contents": [NSNull null] };

        TungstenView *view = [[TungstenView alloc] initWithFrame:frame];
        view.input = &captured->input;
        if (flags & GFX_DROP_FILES) [view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        view.wantsLayer = YES;
        view.layer = layer;

        TungstenWindowDelegate *del = [[TungstenWindowDelegate alloc] init];
        del.input = &captured->input;
        del.gw = captured;
        [win setDelegate:del];

        [win setContentView:view];
        [win setAcceptsMouseMovedEvents:YES];
        [win makeFirstResponder:view];
        if (!(flags & GFX_HIDDEN)) [win makeKeyAndOrderFront:nil];

        captured->window = (void *)win;
        captured->layer = (void *)[layer retain];
        captured->view = (void *)view;
        captured->delegate = (void *)del;
    };
    build();
    gfx_fit_drawable(gw);
    gfx_open_target(gw);

    id<MTLCommandQueue> queue = [dev newCommandQueue];
    if (!queue) {
        char message[160];
        snprintf(message, sizeof(message), "%s: could not create Metal command queue", op);
        w_raise(w_string(message));
    }
    gw->queue = (void *)queue;

    return w_box_ptr(gw, W_SUBTAG_GENERIC);
}

/* ---- w_gfx_window_new(device, title, width, height) ----
 * The v1 window: a width x height pixel drawable, RGBA8, shown at once. */

WValue w_gfx_window_new(WValue device_v, WValue title_v, WValue width_v, WValue height_v) {
    int w = (int)gfx_int(width_v);
    int h = (int)gfx_int(height_v);
    return gfx_open(device_v, title_v, w, h, 0, "gfx.window_new");
}

/* ---- w_gfx_window_open(device, title, width, height, flags) ----
 * width x height content points; flags GFX_HIDPI | GFX_HIDDEN | GFX_BGRA | GFX_KEEP_OPEN. */

WValue w_gfx_window_open(WValue device_v, WValue title_v, WValue width_v, WValue height_v, WValue flags_v) {
    int w = (int)gfx_num(width_v, "gfx.window_open");
    int h = (int)gfx_num(height_v, "gfx.window_open");
    int flags = (int)gfx_int(flags_v);
    return gfx_open(device_v, title_v, w, h, flags, "gfx.window_open");
}

/* ---- w_gfx_poll(window) — drain the OS event queue ---- */

static int gfx_pump(double wait_seconds) {
    int n = 0;
    @autoreleasepool {
        NSEvent *ev;
        NSDate *until = wait_seconds > 0 ? [NSDate dateWithTimeIntervalSinceNow:wait_seconds]
                                         : [NSDate distantPast];
        while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:until
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES])) {
            [NSApp sendEvent:ev];
            n++;
            until = [NSDate distantPast];    /* after the first, drain without waiting */
        }
    }
    return n;
}

WValue w_gfx_poll(WValue window_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.poll: not a window"));
    gfx_require_main_thread("gfx.poll");
    gfx_pump(0);
    return W_NIL;
}

/* ---- w_gfx_wait(window, seconds) — sleep until input arrives ----
 * Pumps the OS queue, waiting up to `seconds` for the first OS event when
 * the window's own queue is empty. Returns the number of queued events. An
 * editor's loop calls this instead of spinning: it redraws on change. */

WValue w_gfx_wait(WValue window_v, WValue seconds_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.wait");
    gfx_require_main_thread("gfx.wait");
    double s = gfx_num(seconds_v, "gfx.wait");
    if (gw->input.qcount > 0) s = 0;
    gfx_pump(s);
    return w_int(gw->input.qcount);
}

/* ---- the event queue ---- */

WValue w_gfx_next_event(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.next_event");
    GfxInput *in = &gw->input;
    if (in->qcount == 0) {
        memset(&in->cur, 0, sizeof in->cur);
        return w_int(GFX_EV_NONE);
    }
    in->cur = in->q[in->qhead];
    in->qhead = (in->qhead + 1) % GFX_QUEUE_CAP;
    in->qcount--;
    return w_int(in->cur.kind);
}

/* one field of the current event: 0 kind, 1 x, 2 y, 3 dx, 4 dy, 5 button,
 * 6 clicks, 7 mods, 8 key, 9 repeat, 10 phase, 11 precise, 12 w, 13 h,
 * 14 scale, 15 id */
WValue w_gfx_event_field(WValue window_v, WValue field_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.event_field");
    GfxEvent *e = &gw->input.cur;
    switch ((int)gfx_int(field_v)) {
        case 0:  return w_int(e->kind);
        case 1:  return w_float(e->x);
        case 2:  return w_float(e->y);
        case 3:  return w_float(e->dx);
        case 4:  return w_float(e->dy);
        case 5:  return w_int(e->button);
        case 6:  return w_int(e->clicks);
        case 7:  return w_int(e->mods);
        case 8:  return w_int(e->key);
        case 9:  return w_int(e->repeat);
        case 10: return w_int(e->phase);
        case 11: return w_int(e->precise);
        case 12: return w_float(e->w);
        case 13: return w_float(e->h);
        case 14: return w_float(e->scale);
        case 15: return w_int(e->id);
        default: break;
    }
    w_raise(w_string("gfx.event_field: unknown field"));
    return W_NIL;
}

WValue w_gfx_event_text(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.event_text");
    return w_string(gw->input.cur.text);
}

/* the whole path of the current GFX_EV_OPEN event ("" for any other event) */
WValue w_gfx_event_path(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.event_path");
    GfxEvent *e = &gw->input.cur;
    if (e->kind != GFX_EV_OPEN || !gfx_open_paths || e->id < 0 || (NSUInteger)e->id >= [gfx_open_paths count])
        return w_string("");
    const char *p = [[gfx_open_paths objectAtIndex:(NSUInteger)e->id] UTF8String];
    return w_string(p ? p : "");
}

/* ---- input queries ---- */

WValue w_gfx_key_down(WValue window_v, WValue keycode_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.key_down: not a window"));
    int64_t code = gfx_int(keycode_v);
    bool down = (code >= 0 && code < 256) ? gw->input.pressed[code] : false;
    return w_bool(down ? 1 : 0);
}

WValue w_gfx_mouse_dx(WValue window_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.mouse_dx: not a window"));
    double d = gw->input.mouse_dx;
    gw->input.mouse_dx = 0.0;
    return w_float(d);
}

WValue w_gfx_mouse_dy(WValue window_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.mouse_dy: not a window"));
    double d = gw->input.mouse_dy;
    gw->input.mouse_dy = 0.0;
    return w_float(d);
}

WValue w_gfx_should_close(WValue window_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.should_close: not a window"));
    return w_bool(gw->input.should_close ? 1 : 0);
}

/* Hide/show the cursor and decouple it from mouse motion so relative
 * deltas keep flowing for FPS-style look (no screen-edge clamping). */
WValue w_gfx_set_mouse_capture(WValue window_v, WValue on_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.set_mouse_capture: not a window"));
    gfx_require_main_thread("gfx.set_mouse_capture");
    bool on = gfx_int(on_v) != 0;
    if (on == gw->input.mouse_captured) return W_NIL;
    gw->input.mouse_captured = on;
    if (on) {
        CGDisplayHideCursor(kCGDirectMainDisplay);
        CGAssociateMouseAndMouseCursorPosition(false);
    } else {
        CGAssociateMouseAndMouseCursorPosition(true);
        CGDisplayShowCursor(kCGDirectMainDisplay);
    }
    return W_NIL;
}

/* ---- the window's metrics, title, size, cursor, close ---- */

/* 0 drawable width (pixels), 1 drawable height, 2 content width (points),
 * 3 content height, 4 backing scale (the drawable's pixels per point) */
WValue w_gfx_metric(WValue window_v, WValue which_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.metric");
    NSView *view = (NSView *)gw->view;
    NSSize sz = [view bounds].size;
    switch ((int)gfx_int(which_v)) {
        case 0: return w_int(gw->width);
        case 1: return w_int(gw->height);
        case 2: return w_float(sz.width);
        case 3: return w_float(sz.height);
        case 4: return w_float((gw->flags & GFX_HIDPI) ? gw->scale : 1.0);
        default: break;
    }
    w_raise(w_string("gfx.metric: unknown metric"));
    return W_NIL;
}

WValue w_gfx_set_title(WValue window_v, WValue title_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.set_title");
    gfx_require_main_thread("gfx.set_title");
    [(NSWindow *)gw->window setTitle:gfx_string(title_v)];
    return W_NIL;
}

/* resize the content to width x height points (a resize event follows) */
/* Activate a document window; hidden test windows stay hidden. */
WValue w_gfx_focus(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.focus");
    gfx_require_main_thread("gfx.focus");
    if (gw->closed) return W_NIL;
    gfx_activate_window(gw);
    if (!(gw->flags & GFX_HIDDEN)) {
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    } else {
        GfxEvent e; memset(&e, 0, sizeof e);
        e.kind = GFX_EV_FOCUS; e.id = 1;
        gfx_push(&gw->input, &e);
    }
    return W_NIL;
}

WValue w_gfx_set_size(WValue window_v, WValue width_v, WValue height_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.set_size");
    gfx_require_main_thread("gfx.set_size");
    double w = gfx_num(width_v, "gfx.set_size"), h = gfx_num(height_v, "gfx.set_size");
    if (w < 1 || h < 1) w_raise(w_string("gfx.set_size: width/height must be positive"));
    [(NSWindow *)gw->window setContentSize:NSMakeSize(w, h)];
    /* a hidden window gets no resize notification from the window server */
    if ((gw->flags & GFX_HIDDEN)) {
        gfx_fit_drawable(gw);
        gfx_push_resize(gw);
    }
    return W_NIL;
}

/* 0 arrow, 1 I-beam, 2 pointing hand, 3 open hand, 4 closed hand,
 * 5 crosshair, 6 resize left-right, 7 resize up-down */
WValue w_gfx_set_cursor(WValue window_v, WValue kind_v) {
    (void)gfx_window_arg(window_v, "gfx.set_cursor");
    gfx_require_main_thread("gfx.set_cursor");
    NSCursor *c = [NSCursor arrowCursor];
    switch ((int)gfx_int(kind_v)) {
        case 1: c = [NSCursor IBeamCursor]; break;
        case 2: c = [NSCursor pointingHandCursor]; break;
        case 3: c = [NSCursor openHandCursor]; break;
        case 4: c = [NSCursor closedHandCursor]; break;
        case 5: c = [NSCursor crosshairCursor]; break;
        case 6: c = [NSCursor resizeLeftRightCursor]; break;
        case 7: c = [NSCursor resizeUpDownCursor]; break;
        default: break;
    }
    [c set];
    return W_NIL;
}

/* close the window now (a GFX_KEEP_OPEN window after the program decided) */
WValue w_gfx_close(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.close");
    gfx_require_main_thread("gfx.close");
    if (gw->closed) return W_NIL;
    gw->closed = true;
    gfx_retarget_closed(gw);
    [gw->form_values release]; gw->form_values = nil;
    gw->input.should_close = true;
    NSWindow *win = (NSWindow *)gw->window;
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        if (gw->tex[i]) {
            [(id<MTLTexture>)gw->tex[i] release];
            gw->tex[i] = NULL;
        }
        if (gw->tex_cb[i]) { [(id<MTLTexture>)gw->tex_cb[i] release]; gw->tex_cb[i] = NULL; }
        if (gw->tex_cr[i]) { [(id<MTLTexture>)gw->tex_cr[i] release]; gw->tex_cr[i] = NULL; }
        gfx_surf_release3(gw->tex_surf[i]);
        gw->tex_planar[i] = 0;
        gw->tex_space[i] = 0;
    }
    for (int i = 0; i < gw->n_surf_dead; i++) gfx_surf_release3(gw->surf_dead[i].r);
    gw->n_surf_dead = 0;
    if (gw->cv_cache) { CFRelease((CVMetalTextureCacheRef)gw->cv_cache); gw->cv_cache = NULL; }
    [win setDelegate:nil];
    [win orderOut:nil];
    [win close];
    return W_NIL;
}

/* ---- the menu bar ---- */

@interface TungstenMenuTarget : NSObject
@property (nonatomic, assign) GfxInput *input;
@end

@implementation TungstenMenuTarget
- (void)fire:(id)sender {
    GfxInput *input = gfx_menu_input(self.input);
    if (!input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_MENU;
    e.id = (int64_t)[sender tag];
    gfx_push(input, &e);
}
- (void)quit:(id)sender {
    (void)sender;
    GfxInput *input = gfx_menu_input(self.input);
    if (!input) return;
    input->should_close = true;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_CLOSE;
    e.id = 1;
    gfx_push(input, &e);
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return [item isEnabled]; }
@end

static TungstenMenuTarget *gfx_menu_target = nil;

/* The application delegate: Quit (the menu's terminate:, the Dock, log out)
 * on a program that keeps its window open (GFX_KEEP_OPEN) is handed to the
 * program as a GFX_EV_CLOSE with id 1, which decides (a save-changes alert)
 * and closes; any other program quits at once. */
@interface TungstenAppDelegate : NSObject <NSApplicationDelegate>
@end

/* ---- documents to open (Finder, the Dock, `open`, any app sending open-documents) ----
 * The delegate's application:openURLs: (at launch and while running) records each file URL's path and queues a GFX_EV_OPEN
 * on the open target: the active document window (initially the first opened). Paths that arrive before any window (at launch, inside
 * finishLaunching) wait and are queued when the first window opens. The event's id indexes gfx_open_paths;
 * w_gfx_event_path returns the whole path (the event's text is only 64 bytes). */
/* (gfx_open_paths, gfx_open_queued and gfx_open_window are declared with the windows, above) */

static void gfx_open_flush(void) {
    WGfxWindow *gw = gfx_open_window;
    if (!gfx_open_paths || !gw || gw->closed) return;
    while (gfx_open_queued < [gfx_open_paths count]) {
        GfxEvent e; memset(&e, 0, sizeof e);
        e.kind = GFX_EV_OPEN;
        e.id = (int64_t)gfx_open_queued;
        gfx_push(&gw->input, &e);
        gfx_open_queued++;
    }
}

static void gfx_open_target(WGfxWindow *gw) {
    if (!gfx_open_window || gfx_open_window->closed) gfx_open_window = gw;
    gfx_open_flush();
}

static void gfx_activate_window(WGfxWindow *gw) {
    if (!gw || gw->closed) return;
    gfx_active_window = gw;
    gfx_open_window = gw;
    if (gfx_menu_target) gfx_menu_target.input = &gw->input;
    gfx_open_flush();
}

static GfxInput *gfx_menu_input(GfxInput *fallback) {
    NSWindow *key = [NSApp keyWindow];
    id delegate = [key delegate];
    if ([delegate isKindOfClass:[TungstenWindowDelegate class]]) {
        WGfxWindow *gw = [(TungstenWindowDelegate *)delegate gw];
        if (gw && !gw->closed) return &gw->input;
    }
    if (gfx_active_window && !gfx_active_window->closed) return &gfx_active_window->input;
    return fallback;
}

static void gfx_retarget_closed(WGfxWindow *closed) {
    if (gfx_active_window != closed && gfx_open_window != closed) return;
    if (gfx_active_window == closed) gfx_active_window = NULL;
    if (gfx_open_window == closed) gfx_open_window = NULL;
    if (gfx_menu_target && gfx_menu_target.input == &closed->input) gfx_menu_target.input = NULL;
    for (NSWindow *window in [NSApp windows]) {
        id delegate = [window delegate];
        if (![delegate isKindOfClass:[TungstenWindowDelegate class]]) continue;
        WGfxWindow *gw = [(TungstenWindowDelegate *)delegate gw];
        if (gw && !gw->closed) { gfx_activate_window(gw); break; }
    }
}

static void gfx_open_received(NSArray *urls) {
    if (!gfx_open_paths) gfx_open_paths = [[NSMutableArray alloc] init];
    for (NSURL *u in urls) {
        if (![u isKindOfClass:[NSURL class]] || ![u isFileURL]) continue;
        /* standardized (no . or ..) and precomposed (NSURL hands back decomposed accents; text and recent lists are NFC) */
        NSString *p = [[[u URLByStandardizingPath] path] precomposedStringWithCanonicalMapping];
        if ([p length] > 0) [gfx_open_paths addObject:p];
    }
    gfx_open_flush();
}

/* A drop belongs to its destination, even when another document is key. */
static BOOL gfx_drop_received(NSView *view, NSArray *urls) {
    id delegate = [[view window] delegate];
    if (![delegate isKindOfClass:[TungstenWindowDelegate class]] || [urls count] == 0) return NO;
    WGfxWindow *gw = [(TungstenWindowDelegate *)delegate gw];
    if (!gw || gw->closed || !(gw->flags & GFX_DROP_FILES)) return NO;
    if (!(gw->flags & GFX_HIDDEN)) [(NSWindow *)gw->window makeKeyWindow];
    gfx_activate_window(gw);
    gfx_open_received(urls);
    return YES;
}

@implementation TungstenAppDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    (void)app;
    if (gfx_menu_target && gfx_menu_target.input) {
        [gfx_menu_target quit:nil];
        return NSTerminateCancel;
    }
    return NSTerminateNow;
}
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    (void)app;
    gfx_open_received(urls);
}
@end

static TungstenAppDelegate *gfx_app_delegate = nil;

static void gfx_install_app_delegate(void) {
    if (!gfx_app_delegate && [NSApp delegate] == nil) {
        gfx_app_delegate = [[TungstenAppDelegate alloc] init];
        [NSApp setDelegate:gfx_app_delegate];
    }
}

/* The application's name: the bundle's CFBundleName, else the process name. */
static NSString *gfx_app_name(void) {
    NSString *n = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    if ([n isKindOfClass:[NSString class]] && [n length] > 0) return n;
    return [[NSProcessInfo processInfo] processName];
}

static NSMenuItem *gfx_add_role(NSMenu *m, NSString *title, SEL action, NSString *key, NSEventModifierFlags f) {
    NSMenuItem *it = [m addItemWithTitle:title action:action keyEquivalent:key];
    if ([key length] > 0) [it setKeyEquivalentModifierMask:f];
    return it;
}

/* The standard menu bar, made with the first menu item a program adds:
 *   <App>   About <App> (the standard About panel: CFBundleShortVersionString and the build, CFBundleVersion), Settings...
 *           (Command-comma; a GFX_EV_MENU with id GFX_MENU_SETTINGS), Services, Hide <App> (Command-H), Hide Others
 *           (Option-Command-H), Show All, Quit <App> (Command-Q, terminate: through the delegate above)
 *   Window  Minimize (Command-M), Zoom, Bring All to Front (NSApp's windows menu)
 *   Help    <App> Help (a GFX_EV_MENU with id GFX_MENU_HELP; NSApp's help menu)
 * The program's own menus go between the application menu and Window, in the order it names them.
 * Made once (a flag, not "is there a main menu yet"): on macOS 27 [NSApp finishLaunching] gives a regular app without a nib a
 * placeholder main menu, one application item with an empty menu, so a bar that was "already there" left a launched app with an
 * empty application menu, no Quit and no Window or Help menus (hidden-window runs are accessory apps and get no placeholder).
 * The placeholder is replaced; any top-level menus after its application item are kept, before Window. */
static bool gfx_menu_bar_made = false;

static void gfx_menu_bar(WGfxWindow *gw) {
    if (!gfx_menu_target) {
        gfx_menu_target = [[TungstenMenuTarget alloc] init];
    }
    gfx_menu_target.input = &gw->input;
    gfx_install_app_delegate();
    if (gfx_menu_bar_made) return;
    gfx_menu_bar_made = true;
    NSMenu *previous = [NSApp mainMenu];
    NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    NSMenu *bar = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSString *name = gfx_app_name();
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:name] autorelease];
    gfx_add_role(appMenu, [@"About " stringByAppendingString:name], @selector(orderFrontStandardAboutPanel:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settings = gfx_add_role(appMenu, @"Settings\u2026", @selector(fire:), @",", cmd);
    [settings setTarget:gfx_menu_target];
    [settings setTag:GFX_MENU_SETTINGS];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *svc = [appMenu addItemWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *svcMenu = [[[NSMenu alloc] initWithTitle:@"Services"] autorelease];
    [svc setSubmenu:svcMenu];
    [NSApp setServicesMenu:svcMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    gfx_add_role(appMenu, [@"Hide " stringByAppendingString:name], @selector(hide:), @"h", cmd);
    gfx_add_role(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"h", cmd | NSEventModifierFlagOption);
    gfx_add_role(appMenu, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    gfx_add_role(appMenu, [@"Quit " stringByAppendingString:name], @selector(terminate:), @"q", cmd);
    [appItem setSubmenu:appMenu];
    [bar addItem:appItem];

    NSMenuItem *winItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    NSMenu *winMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    gfx_add_role(winMenu, @"Minimize", @selector(performMiniaturize:), @"m", cmd);
    gfx_add_role(winMenu, @"Zoom", @selector(performZoom:), @"", 0);
    [winMenu addItem:[NSMenuItem separatorItem]];
    gfx_add_role(winMenu, @"Bring All to Front", @selector(arrangeInFront:), @"", 0);
    [winItem setSubmenu:winMenu];
    [bar addItem:winItem];
    [NSApp setWindowsMenu:winMenu];

    NSMenuItem *helpItem = [[[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""] autorelease];
    NSMenu *helpMenu = [[[NSMenu alloc] initWithTitle:@"Help"] autorelease];
    NSMenuItem *help = gfx_add_role(helpMenu, [name stringByAppendingString:@" Help"], @selector(fire:), @"?", cmd);
    [help setTarget:gfx_menu_target];
    [help setTag:GFX_MENU_HELP];
    [helpItem setSubmenu:helpMenu];
    [bar addItem:helpItem];
    [NSApp setHelpMenu:helpMenu];

    if (previous && previous != bar) {
        NSArray *kept = [[previous itemArray] copy];
        for (NSUInteger i = 1; i < [kept count]; i++) {
            NSMenuItem *it = [kept objectAtIndex:i];
            [it retain];
            [previous removeItem:it];
            [bar insertItem:it atIndex:[bar indexOfItem:winItem]];
            [it release];
        }
        [kept release];
    }
    [NSApp setMainMenu:bar];
    /* The first visible window predates this menu. AppKit registers later
     * windows automatically, but that first document needs adding here. */
    for (NSWindow *window in [NSApp windows]) {
        if ([window isVisible] && ![window isExcludedFromWindowsMenu])
            [NSApp addWindowsItem:window title:[window title] filename:NO];
    }
}

/* The menu a "Top" or "Top/Sub/..." path names, made on first use: a new top-level menu goes before Window (so
 * Window and Help stay last), a new submenu at the end of its parent. */
static NSMenu *gfx_menu_path(NSString *path) {
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    NSMenu *bar = [NSApp mainMenu];
    NSMenu *cur = bar;
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *t = parts[i];
        NSMenuItem *it = nil;
        for (NSMenuItem *x in [cur itemArray]) {
            if ([x submenu] && [[x title] isEqualToString:t]) { it = x; break; }
        }
        if (!it) {
            it = [[[NSMenuItem alloc] initWithTitle:t action:nil keyEquivalent:@""] autorelease];
            NSMenu *sub = [[[NSMenu alloc] initWithTitle:t] autorelease];
            [sub setAutoenablesItems:NO];
            [it setSubmenu:sub];
            NSInteger at = -1;
            if (cur == bar) {
                NSInteger wi = [bar indexOfItemWithSubmenu:[NSApp windowsMenu]];
                if (wi >= 0) at = wi;
            }
            if (at >= 0) [cur insertItem:it atIndex:at];
            else [cur addItem:it];
        }
        cur = [it submenu];
    }
    return cur;
}

/* the key equivalent a name gives: one character, or up/down/left/right,
 * return, tab, space, delete, escape, home, end, pageup, pagedown, f1-f12 */
static NSString *gfx_key_equiv(NSString *k) {
    if ([k length] <= 1) return k;
    unichar c = 0;
    if ([k isEqualToString:@"up"]) c = NSUpArrowFunctionKey;
    else if ([k isEqualToString:@"down"]) c = NSDownArrowFunctionKey;
    else if ([k isEqualToString:@"left"]) c = NSLeftArrowFunctionKey;
    else if ([k isEqualToString:@"right"]) c = NSRightArrowFunctionKey;
    else if ([k isEqualToString:@"return"]) c = '\r';
    else if ([k isEqualToString:@"tab"]) c = '\t';
    else if ([k isEqualToString:@"space"]) c = ' ';
    else if ([k isEqualToString:@"delete"]) c = 0x08;
    else if ([k isEqualToString:@"escape"]) c = 0x1b;
    else if ([k isEqualToString:@"home"]) c = NSHomeFunctionKey;
    else if ([k isEqualToString:@"end"]) c = NSEndFunctionKey;
    else if ([k isEqualToString:@"pageup"]) c = NSPageUpFunctionKey;
    else if ([k isEqualToString:@"pagedown"]) c = NSPageDownFunctionKey;
    else if ([k length] >= 2 && [k characterAtIndex:0] == 'f') {
        int n = [[k substringFromIndex:1] intValue];
        if (n >= 1 && n <= 12) c = (unichar)(NSF1FunctionKey + n - 1);
    }
    if (c == 0) return @"";
    return [NSString stringWithCharacters:&c length:1];
}

static NSMenuItem *gfx_find_item(NSMenu *m, NSInteger tag) {
    for (NSMenuItem *it in [m itemArray]) {
        if ([it action] == @selector(fire:) && [it tag] == tag) return it;
        if ([it submenu]) {
            NSMenuItem *r = gfx_find_item([it submenu], tag);
            if (r) return r;
        }
    }
    return nil;
}

/* w_gfx_menu_add(window, menu, title, key, mods, id): an item at the end of
 * the top-level menu named `menu` (made, in order, on first use); title "-"
 * is a separator; key "" for none; mods GFX_MOD_* (0 means Command when a key
 * is given, -1 the plain key). Choosing it posts a menu event with `id`. */
WValue w_gfx_menu_add(WValue window_v, WValue menu_v, WValue title_v, WValue key_v,
                      WValue mods_v, WValue id_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.menu_add");
    gfx_require_main_thread("gfx.menu_add");
    gfx_menu_bar(gw);
    NSString *mname = gfx_string_or(menu_v, @"Menu");
    NSString *title = gfx_string_or(title_v, @"");
    NSString *key = gfx_key_equiv(gfx_string_or(key_v, @""));
    int mods = (int)gfx_int(mods_v);
    /* Shift with a letter: AppKit matches the capital (Command-Shift-Z is "Z") */
    if (mods > 0 && (mods & GFX_MOD_SHIFT) && [key length] == 1) key = [key uppercaseString];
    NSInteger tag = (NSInteger)gfx_int(id_v);
    NSMenu *sub = gfx_menu_path(mname);
    if ([title isEqualToString:@"-"]) {
        [sub addItem:[NSMenuItem separatorItem]];
        return W_NIL;
    }
    NSMenuItem *it = [[[NSMenuItem alloc] initWithTitle:title action:@selector(fire:) keyEquivalent:key] autorelease];
    [it setTarget:gfx_menu_target];
    [it setTag:tag];
    [it setEnabled:YES];
    if ([key length] > 0) {
        NSEventModifierFlags f = gfx_flags_of(mods);
        if (mods == 0) f = NSEventModifierFlagCommand;
        if (mods < 0) f = 0;                 /* a plain key (space, return) */
        [it setKeyEquivalentModifierMask:f];
    }
    [sub addItem:it];
    return W_NIL;
}

/* w_gfx_menu_clear(window, menu): remove every item of the menu (or "Top/Sub" submenu) that path names, so a program can
 * refill it (Open Recent); the menu itself stays where it is. */
WValue w_gfx_menu_clear(WValue window_v, WValue menu_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.menu_clear");
    gfx_require_main_thread("gfx.menu_clear");
    gfx_menu_bar(gw);
    NSMenu *m = gfx_menu_path(gfx_string_or(menu_v, @"Menu"));
    [m removeAllItems];
    return W_NIL;
}

/* w_gfx_menu_items(window, menu): the titles of a menu's items ("" for a separator), or of the menu bar's menus for ""
 * (introspection for specs and scripted checks) */
WValue w_gfx_menu_items(WValue window_v, WValue menu_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.menu_items");
    gfx_require_main_thread("gfx.menu_items");
    gfx_menu_bar(gw);
    NSString *path = gfx_string_or(menu_v, @"");
    NSMenu *m = [path length] == 0 ? [NSApp mainMenu] : gfx_menu_path(path);
    WValue out = w_array_new_empty();
    for (NSMenuItem *it in [m itemArray]) {
        const char *t = [it isSeparatorItem] ? "" : [[it title] UTF8String];
        out = w_array_push(out, w_string(t ? t : ""));
    }
    return out;
}

/* enabled / checked state of the item with that id (-1 leaves one unchanged) */
WValue w_gfx_menu_set(WValue window_v, WValue id_v, WValue enabled_v, WValue checked_v) {
    (void)gfx_window_arg(window_v, "gfx.menu_set");
    gfx_require_main_thread("gfx.menu_set");
    NSMenuItem *it = gfx_find_item([NSApp mainMenu], (NSInteger)gfx_int(id_v));
    if (!it) return w_bool(0);
    int en = (int)gfx_int(enabled_v), ch = (int)gfx_int(checked_v);
    if (en >= 0) [it setEnabled:en ? YES : NO];
    if (ch >= 0) [it setState:ch ? NSControlStateValueOn : NSControlStateValueOff];
    return w_bool(1);
}

/* ---- open and save panels (modal) ---- */

static NSArray *gfx_types(WValue types_v) {
    NSString *t = gfx_string_or(types_v, @"");
    if ([t length] == 0) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *s in [t componentsSeparatedByString:@","]) {
        NSString *x = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([x hasPrefix:@"."]) x = [x substringFromIndex:1];
        if ([x length] > 0) [out addObject:x];
    }
    return [out count] ? out : nil;
}

static bool gfx_panel_scripted(WGfxWindow *gw, WValue *out) {
    if (!gw->panel_scripted) return false;
    gw->panel_scripted = false;
    if (gw->panel_answer) {
        *out = w_string(gw->panel_answer);
        free(gw->panel_answer);
        gw->panel_answer = NULL;
    } else {
        *out = W_NIL;
    }
    return true;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* w_gfx_open_panel(window, title, types, dir): the chosen file's path, or nil
 * when cancelled; types "arr,txt" (extensions, "" for any); dir "" for the
 * panel's own choice */
WValue w_gfx_open_panel(WValue window_v, WValue title_v, WValue types_v, WValue dir_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.open_panel");
    gfx_require_main_thread("gfx.open_panel");
    WValue scripted;
    if (gfx_panel_scripted(gw, &scripted)) return scripted;
    if (gw->flags & GFX_HIDDEN) return W_NIL;
    WValue result = W_NIL;
    @autoreleasepool {
        NSOpenPanel *p = [NSOpenPanel openPanel];
        [p setCanChooseFiles:YES];
        [p setCanChooseDirectories:NO];
        [p setAllowsMultipleSelection:NO];
        NSString *title = gfx_string_or(title_v, @"");
        if ([title length]) [p setMessage:title];
        NSArray *types = gfx_types(types_v);
        if (types) [p setAllowedFileTypes:types];
        NSString *dir = gfx_string_or(dir_v, @"");
        if ([dir length]) [p setDirectoryURL:[NSURL fileURLWithPath:dir isDirectory:YES]];
        [NSApp activateIgnoringOtherApps:YES];
        if ([p runModal] == NSModalResponseOK) {
            NSURL *u = [[p URLs] firstObject];
            if (u) result = w_string([[u path] UTF8String]);
        }
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return result;
}

/* w_gfx_clipboard_text(): the general pasteboard's plain text, or nil. Needs
 * no window and works from any thread (NSPasteboard is thread safe). */
WValue w_gfx_clipboard_text(void) {
    WValue result = W_NIL;
    @autoreleasepool {
        NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        if (s) result = w_string([s UTF8String]);
    }
    return result;
}

/* w_gfx_clipboard_set_text(s): replace the general pasteboard with plain text;
 * true on success. */
WValue w_gfx_clipboard_set_text(WValue text_v) {
    BOOL ok = NO;
    @autoreleasepool {
        NSString *s = gfx_string_or(text_v, @"");
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        ok = [pb setString:s forType:NSPasteboardTypeString];
    }
    return ok ? W_TRUE : W_FALSE;
}

/* w_gfx_save_panel(window, title, name, types, dir): the path to save to, or
 * nil when cancelled; name the suggested file name */
WValue w_gfx_save_panel(WValue window_v, WValue title_v, WValue name_v, WValue types_v, WValue dir_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.save_panel");
    gfx_require_main_thread("gfx.save_panel");
    WValue scripted;
    if (gfx_panel_scripted(gw, &scripted)) return scripted;
    if (gw->flags & GFX_HIDDEN) return W_NIL;
    WValue result = W_NIL;
    @autoreleasepool {
        NSSavePanel *p = [NSSavePanel savePanel];
        NSString *title = gfx_string_or(title_v, @"");
        if ([title length]) [p setMessage:title];
        NSString *name = gfx_string_or(name_v, @"");
        if ([name length]) [p setNameFieldStringValue:name];
        NSArray *types = gfx_types(types_v);
        if (types) [p setAllowedFileTypes:types];
        NSString *dir = gfx_string_or(dir_v, @"");
        if ([dir length]) [p setDirectoryURL:[NSURL fileURLWithPath:dir isDirectory:YES]];
        [NSApp activateIgnoringOtherApps:YES];
        if ([p runModal] == NSModalResponseOK) {
            NSURL *u = [p URL];
            if (u) result = w_string([[u path] UTF8String]);
        }
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return result;
}

#pragma clang diagnostic pop

/* the next panel returns `path` (nil: cancelled) without showing anything:
 * specs and scripted runs */
WValue w_gfx_panel_answer(WValue window_v, WValue path_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.panel_answer");
    if (gw->panel_answer) { free(gw->panel_answer); gw->panel_answer = NULL; }
    gw->panel_scripted = true;
    if (w_is_string(path_v)) {
        char buf[6];
        const char *s = NULL; size_t len = 0;
        w_str_data(path_v, buf, &s, &len);
        gw->panel_answer = (char *)malloc(len + 1);
        if (s && len) memcpy(gw->panel_answer, s, len);
        gw->panel_answer[len] = 0;
    }
    return W_NIL;
}

/* ---- alerts (modal) ----
 * w_gfx_alert(window, message, info, buttons): a modal alert with the
 * comma-separated buttons (the first is the default); returns the chosen
 * button's index, or -1 on a hidden window with no scripted answer. */
WValue w_gfx_alert(WValue window_v, WValue message_v, WValue info_v, WValue buttons_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.alert");
    gfx_require_main_thread("gfx.alert");
    if (gw->alert_scripted) {
        gw->alert_scripted = false;
        return w_int(gw->alert_answer);
    }
    if (gw->flags & GFX_HIDDEN) return w_int(-1);
    NSInteger chosen = -1;
    @autoreleasepool {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText:gfx_string_or(message_v, @"")];
        NSString *info = gfx_string_or(info_v, @"");
        if ([info length]) [a setInformativeText:info];
        NSString *bs = gfx_string_or(buttons_v, @"OK");
        for (NSString *b in [bs componentsSeparatedByString:@","]) {
            NSString *t = [b stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([t length]) [a addButtonWithTitle:t];
        }
        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse r = [a runModal];
        chosen = (NSInteger)(r - NSAlertFirstButtonReturn);
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return w_int((int64_t)chosen);
}

/* the next alert returns `index` without showing (specs, scripted runs) */
WValue w_gfx_alert_answer(WValue window_v, WValue index_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.alert_answer");
    gw->alert_scripted = true;
    gw->alert_answer = (int)gfx_int(index_v);
    return W_NIL;
}

/* ---- prompts: a line of text, or a choice from a list (modal) ----
 * w_gfx_prompt(window, message, info, default, buttons): an alert with a text
 * field holding `default`; returns [button index, the text], [-1, default] on a
 * hidden window with no scripted answer.
 * w_gfx_choose(window, message, info, items, buttons): an alert with a pop-up
 * of the comma-separated `items` (a "-" item is a separator); returns [button
 * index, item index], [-1, -1] on a hidden window with no scripted answer.
 * w_gfx_prompt_answer(window, button, text, item): the next prompt or choice
 * returns those without showing (specs, scripted runs). */
static NSArray *gfx_button_list(WValue buttons_v) {
    NSMutableArray *out = [NSMutableArray array];
    NSString *bs = gfx_string_or(buttons_v, @"OK,Cancel");
    for (NSString *b in [bs componentsSeparatedByString:@","]) {
        NSString *t = [b stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t length]) [out addObject:t];
    }
    return out;
}

static WValue gfx_pair(int64_t a, WValue b) {
    WValue r = w_array_new_empty();
    r = w_array_push(r, w_int(a));
    r = w_array_push(r, b);
    return r;
}

WValue w_gfx_prompt(WValue window_v, WValue message_v, WValue info_v, WValue default_v, WValue buttons_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.prompt");
    gfx_require_main_thread("gfx.prompt");
    NSString *dflt = gfx_string_or(default_v, @"");
    if (gw->prompt_scripted) {
        gw->prompt_scripted = false;
        WValue t = gw->prompt_text ? w_string(gw->prompt_text) : w_string([dflt UTF8String]);
        return gfx_pair(gw->prompt_button, t);
    }
    if (gw->flags & GFX_HIDDEN) return gfx_pair(-1, w_string([dflt UTF8String]));
    NSInteger chosen = -1;
    WValue text = W_NIL;
    @autoreleasepool {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText:gfx_string_or(message_v, @"")];
        NSString *info = gfx_string_or(info_v, @"");
        if ([info length]) [a setInformativeText:info];
        for (NSString *b in gfx_button_list(buttons_v)) [a addButtonWithTitle:b];
        NSTextField *f = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)] autorelease];
        [f setStringValue:dflt];
        [a setAccessoryView:f];
        [[a window] setInitialFirstResponder:f];
        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse r = [a runModal];
        chosen = (NSInteger)(r - NSAlertFirstButtonReturn);
        const char *u = [[f stringValue] UTF8String];
        text = w_string(u ? u : "");
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return gfx_pair((int64_t)chosen, text);
}

WValue w_gfx_form_answer(WValue window_v, WValue button_v, WValue values_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.form_answer");
    gfx_require_main_thread("gfx.form_answer");
    int64_t n = gfx_int(w_array_size(values_v));
    if (n > 16) w_raise(w_string("gfx.form_answer: at most 16 values"));
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    for (int64_t i = 0; i < n; i++)
        [values addObject:gfx_string_or(w_array_get(values_v, w_int(i)), @"")];
    [gw->form_values release];
    gw->form_values = [values copy];
    gw->form_button = (int)gfx_int(button_v);
    return W_NIL;
}

WValue w_gfx_form(WValue window_v, WValue message_v, WValue info_v,
                   WValue labels_v, WValue defaults_v, WValue buttons_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.form");
    gfx_require_main_thread("gfx.form");
    int64_t n = gfx_int(w_array_size(labels_v));
    if (n > 16 || gfx_int(w_array_size(defaults_v)) != n)
        w_raise(w_string("gfx.form: labels and defaults must have the same length, at most 16"));
    WValue values = w_array_new_empty();
    if (gw->form_values) {
        if ((int64_t)[gw->form_values count] != n)
            w_raise(w_string("gfx.form: scripted values must match the number of fields"));
        for (int64_t i = 0; i < n; i++)
            values = w_array_push(values, w_string([[gw->form_values objectAtIndex:(NSUInteger)i] UTF8String]));
        int button = gw->form_button;
        [gw->form_values release]; gw->form_values = nil;
        return gfx_pair(button, values);
    }
    if (gw->flags & GFX_HIDDEN) {
        for (int64_t i = 0; i < n; i++)
            values = w_array_push(values, w_string([gfx_string_or(w_array_get(defaults_v, w_int(i)), @"") UTF8String]));
        return gfx_pair(-1, values);
    }
    NSInteger chosen = -1;
    @autoreleasepool {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText:gfx_string_or(message_v, @"")];
        [a setInformativeText:gfx_string_or(info_v, @"")];
        for (NSString *b in gfx_button_list(buttons_v)) [a addButtonWithTitle:b];
        NSInteger columns = MIN((NSInteger)n, 2);
        NSInteger rows = n ? ((NSInteger)n + columns - 1) / columns : 0;
        NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, columns * 188, rows * 58)] autorelease];
        NSMutableArray *fields = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
        for (int64_t i = 0; i < n; i++) {
            CGFloat x = (i % columns) * 188, y = (rows - 1 - i / columns) * 58;
            NSTextField *label = [NSTextField labelWithString:gfx_string_or(w_array_get(labels_v, w_int(i)), @"")];
            [label setFrame:NSMakeRect(x, y + 30, 180, 20)];
            [label setFont:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]];
            NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(x, y + 2, 180, 25)] autorelease];
            [field setStringValue:gfx_string_or(w_array_get(defaults_v, w_int(i)), @"")];
            [field setAccessibilityLabel:[label stringValue]];
            [accessory addSubview:label]; [accessory addSubview:field];
            [fields addObject:field];
        }
        for (NSUInteger i = 0; i < [fields count]; i++)
            [[fields objectAtIndex:i] setNextKeyView:[fields objectAtIndex:(i + 1) % [fields count]]];
        if (n) {
            [a setAccessoryView:accessory];
            [[a window] setInitialFirstResponder:[fields objectAtIndex:0]];
        }
        [NSApp activateIgnoringOtherApps:YES];
        chosen = [a runModal] - NSAlertFirstButtonReturn;
        for (NSTextField *f in fields)
            values = w_array_push(values, w_string([[f stringValue] UTF8String]));
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return gfx_pair((int64_t)chosen, values);
}

WValue w_gfx_choose(WValue window_v, WValue message_v, WValue info_v, WValue items_v, WValue buttons_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.choose");
    gfx_require_main_thread("gfx.choose");
    if (gw->prompt_scripted) {
        gw->prompt_scripted = false;
        return gfx_pair(gw->prompt_button, w_int(gw->prompt_item));
    }
    if (gw->flags & GFX_HIDDEN) return gfx_pair(-1, w_int(-1));
    NSInteger chosen = -1, item = -1;
    @autoreleasepool {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText:gfx_string_or(message_v, @"")];
        NSString *info = gfx_string_or(info_v, @"");
        if ([info length]) [a setInformativeText:info];
        for (NSString *b in gfx_button_list(buttons_v)) [a addButtonWithTitle:b];
        NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 26) pullsDown:NO] autorelease];
        NSArray *its = [gfx_string_or(items_v, @"") componentsSeparatedByString:@","];
        NSInteger idx = 0;
        for (NSString *t in its) {
            if ([t isEqualToString:@"-"]) { [[p menu] addItem:[NSMenuItem separatorItem]]; continue; }
            [p addItemWithTitle:t];
            [[p lastItem] setTag:idx];
            idx++;
        }
        [a setAccessoryView:p];
        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse r = [a runModal];
        chosen = (NSInteger)(r - NSAlertFirstButtonReturn);
        item = [[p selectedItem] tag];
        [(NSWindow *)gw->window makeKeyAndOrderFront:nil];
    }
    return gfx_pair((int64_t)chosen, w_int((int64_t)item));
}

WValue w_gfx_prompt_answer(WValue window_v, WValue button_v, WValue text_v, WValue item_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.prompt_answer");
    gw->prompt_scripted = true;
    gw->prompt_button = (int)gfx_int(button_v);
    gw->prompt_item = (int)gfx_int(item_v);
    if (gw->prompt_text) { free(gw->prompt_text); gw->prompt_text = NULL; }
    if (w_is_string(text_v)) {
        char buf[6];
        const char *s = NULL; size_t len = 0;
        w_str_data(text_v, buf, &s, &len);
        gw->prompt_text = (char *)malloc(len + 1);
        if (s && len) memcpy(gw->prompt_text, s, len);
        gw->prompt_text[len] = 0;
    }
    return W_NIL;
}

/* ---- context menus (modal) ----
 * w_gfx_context_menu(window, x, y, items): a native pop-up menu at (x, y)
 * content points (top-left origin), as a right-click shows. items is an
 * Array of titles: "-" is a separator, a leading "!" shows the item
 * disabled. Returns the chosen item's index in items, or -1 when dismissed
 * (and on a hidden window with no scripted answer).
 * w_gfx_context_menu_answer(window, index): the next menu returns `index`
 * without showing (specs, scripted runs). */
@interface TungstenMenuPick : NSObject
@property (nonatomic) NSInteger picked;
- (void)pick:(id)sender;
@end
@implementation TungstenMenuPick
- (void)pick:(id)sender { self.picked = [(NSMenuItem *)sender tag]; }
@end

WValue w_gfx_context_menu(WValue window_v, WValue x_v, WValue y_v, WValue items_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.context_menu");
    gfx_require_main_thread("gfx.context_menu");
    if (gw->menu_scripted) {
        gw->menu_scripted = false;
        return w_int(gw->menu_answer);
    }
    if (gw->flags & GFX_HIDDEN) return w_int(-1);
    NSInteger picked = -1;
    @autoreleasepool {
        TungstenMenuPick *target = [[[TungstenMenuPick alloc] init] autorelease];
        target.picked = -1;
        NSMenu *m = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        [m setAutoenablesItems:NO];
        int64_t n = gfx_int(w_array_size(items_v));
        for (int64_t i = 0; i < n; i++) {
            NSString *t = gfx_string_or(w_array_get(items_v, w_int(i)), @"");
            if ([t isEqualToString:@"-"]) { [m addItem:[NSMenuItem separatorItem]]; continue; }
            BOOL enabled = YES;
            if ([t hasPrefix:@"!"]) { enabled = NO; t = [t substringFromIndex:1]; }
            NSMenuItem *it = [[[NSMenuItem alloc] initWithTitle:t action:@selector(pick:) keyEquivalent:@""] autorelease];
            [it setTarget:target];
            [it setTag:(NSInteger)i];
            [it setEnabled:enabled];
            [m addItem:it];
        }
        NSView *v = (NSView *)gw->view;
        double x = gfx_num(x_v, "gfx.context_menu"), y = gfx_num(y_v, "gfx.context_menu");
        NSPoint p = NSMakePoint(x, [v isFlipped] ? y : [v bounds].size.height - y);
        [m popUpMenuPositioningItem:nil atLocation:p inView:v];
        picked = target.picked;
    }
    return w_int((int64_t)picked);
}

WValue w_gfx_context_menu_answer(WValue window_v, WValue index_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.context_menu_answer");
    gw->menu_scripted = true;
    gw->menu_answer = (int)gfx_int(index_v);
    return W_NIL;
}

/* ---- Photos ----
 * w_gfx_photos_add(path): add an image or video file to the Photos library
 * (asking for add-only access the first time; the app's Info.plist needs
 * NSPhotoLibraryAddUsageDescription — a Bitfile app's photos_usage:).
 * Returns a ticket at once; the import runs in the background.
 * w_gfx_photos_status(ticket): nil while pending, true when added, or an
 * error message. PhotoKit is loaded on first use, so programs that never
 * call this don't link it. */
static NSMutableDictionary *gfx_photo_results = nil;
static int64_t gfx_photo_next = 1;

static void gfx_photo_done(int64_t ticket, id result) {
    @synchronized ([NSProcessInfo processInfo]) {
        [gfx_photo_results setObject:result forKey:@(ticket)];
    }
}

WValue w_gfx_photos_add(WValue path_v) {
    int64_t ticket;
    NSString *path = [[gfx_string_or(path_v, @"") copy] autorelease];
    @synchronized ([NSProcessInfo processInfo]) {
        if (!gfx_photo_results) gfx_photo_results = [[NSMutableDictionary alloc] init];
        ticket = gfx_photo_next++;
    }
    dlopen("/System/Library/Frameworks/Photos.framework/Photos", RTLD_LAZY);
    id lib = (id)NSClassFromString(@"PHPhotoLibrary");
    id req = (id)NSClassFromString(@"PHAssetChangeRequest");
    if (!lib || !req) {
        gfx_photo_done(ticket, @"Photos isn't available");
        return w_int(ticket);
    }
    [path retain];
    NSString *ext = [[path pathExtension] lowercaseString];
    BOOL video = [@[@"mov", @"mp4", @"m4v", @"webm"] containsObject:ext];
    void (^handler)(NSInteger) = ^(NSInteger status) {
        /* PHAuthorizationStatusAuthorized = 3, Limited = 4 */
        if (status != 3 && status != 4) {
            gfx_photo_done(ticket, @"Not allowed to add to Photos (System Settings > Privacy & Security > Photos)");
            [path release];
            return;
        }
        NSError *err = nil;
        NSURL *url = [NSURL fileURLWithPath:path];
        BOOL ok = [[lib performSelector:@selector(sharedPhotoLibrary)] performChangesAndWait:^{
            if (video) [req performSelector:@selector(creationRequestForAssetFromVideoAtFileURL:) withObject:url];
            else [req performSelector:@selector(creationRequestForAssetFromImageAtFileURL:) withObject:url];
        } error:&err];
        gfx_photo_done(ticket, ok ? (id)@YES : (id)(err ? [err localizedDescription] : @"Photos refused the file"));
        [path release];
    };
    /* PHAccessLevelAddOnly = 1 */
    ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(lib, @selector(requestAuthorizationForAccessLevel:handler:), 1, handler);
    return w_int(ticket);
}

WValue w_gfx_photos_status(WValue ticket_v) {
    id r = nil;
    @synchronized ([NSProcessInfo processInfo]) {
        r = [[[gfx_photo_results objectForKey:@(gfx_int(ticket_v))] retain] autorelease];
    }
    if (!r) return W_NIL;
    if ([r isKindOfClass:[NSNumber class]]) return W_TRUE;
    return w_string([(NSString *)r UTF8String]);
}

/* ---- synthesized input (specs, scripted UI runs) ----
 * w_gfx_post_event(window, kind, x, y, a, b, mods, text) builds the AppKit
 * event and hands it to the view's handlers (Command keys to the menu bar
 * first), so it takes the same path into the queue as real input:
 *   mouse down/up/move/drag  x, y points; a = button; b = click count
 *   key down/up              a = keyCode; text = its characters (Command
 *                            shortcuts go through the menu bar first)
 *   scroll                   a, b = dx, dy points (precise)
 *   magnify                  a = magnification
 *   menu                     a = the item's id (the item's action runs)
 *   close                    the close button
 *   open                     text = a file path, through the application delegate's application:openURLs: as Finder's
 *                            open-documents event goes (a GFX_EV_OPEN on the open target);
 *                            a=1 instead simulates a file URL drop onto this specific window */
/* Scripted file drops still traverse the real pasteboard/drag callbacks. */
@interface TungstenSyntheticFileDrag : NSObject
@property (nonatomic, retain) NSPasteboard *pasteboard;
@end
@implementation TungstenSyntheticFileDrag
- (NSPasteboard *)draggingPasteboard { return self.pasteboard; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy; }
- (void)dealloc { [_pasteboard release]; [super dealloc]; }
@end

WValue w_gfx_post_event(WValue window_v, WValue kind_v, WValue x_v, WValue y_v,
                        WValue a_v, WValue b_v, WValue mods_v, WValue text_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.post_event");
    gfx_require_main_thread("gfx.post_event");
    int kind = (int)gfx_int(kind_v);
    double x = gfx_num(x_v, "gfx.post_event"), y = gfx_num(y_v, "gfx.post_event");
    double a = gfx_num(a_v, "gfx.post_event"), b = gfx_num(b_v, "gfx.post_event");
    int mods = (int)gfx_int(mods_v);
    NSWindow *win = (NSWindow *)gw->window;
    TungstenView *view = (TungstenView *)gw->view;
    NSEventModifierFlags flags = gfx_flags_of(mods);
    NSPoint wp = [view convertPoint:NSMakePoint(x, [view bounds].size.height - y) toView:nil];
    NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
    @autoreleasepool {
        if (kind == GFX_EV_MOUSE_DOWN || kind == GFX_EV_MOUSE_UP ||
            kind == GFX_EV_MOUSE_MOVE || kind == GFX_EV_MOUSE_DRAG) {
            int button = (int)a;
            NSEventType t = NSEventTypeMouseMoved;
            if (kind == GFX_EV_MOUSE_DOWN) t = button == 1 ? NSEventTypeRightMouseDown : (button >= 2 ? NSEventTypeOtherMouseDown : NSEventTypeLeftMouseDown);
            if (kind == GFX_EV_MOUSE_UP) t = button == 1 ? NSEventTypeRightMouseUp : (button >= 2 ? NSEventTypeOtherMouseUp : NSEventTypeLeftMouseUp);
            if (kind == GFX_EV_MOUSE_DRAG) t = button == 1 ? NSEventTypeRightMouseDragged : (button >= 2 ? NSEventTypeOtherMouseDragged : NSEventTypeLeftMouseDragged);
            NSEvent *ev = [NSEvent mouseEventWithType:t location:wp modifierFlags:flags timestamp:ts
                                         windowNumber:[win windowNumber] context:nil eventNumber:0
                                           clickCount:(NSInteger)(b > 0 ? b : 1) pressure:(kind == GFX_EV_MOUSE_UP ? 0.0 : 1.0)];
            /* straight to the view's handlers (a window that is not on screen
             * does not route synthesized mouse events) */
            switch (t) {
                case NSEventTypeLeftMouseDown:     [view mouseDown:ev]; break;
                case NSEventTypeLeftMouseUp:       [view mouseUp:ev]; break;
                case NSEventTypeLeftMouseDragged:  [view mouseDragged:ev]; break;
                case NSEventTypeRightMouseDown:    [view rightMouseDown:ev]; break;
                case NSEventTypeRightMouseUp:      [view rightMouseUp:ev]; break;
                case NSEventTypeRightMouseDragged: [view rightMouseDragged:ev]; break;
                case NSEventTypeOtherMouseDown:    [view otherMouseDown:ev]; break;
                case NSEventTypeOtherMouseUp:      [view otherMouseUp:ev]; break;
                case NSEventTypeOtherMouseDragged: [view otherMouseDragged:ev]; break;
                default:
                    if (x < 0.0 || y < 0.0 || x >= [view bounds].size.width || y >= [view bounds].size.height)
                        [view mouseExited:ev];
                    else [view mouseMoved:ev];
                    break;
            }
        } else if (kind == GFX_EV_KEY_DOWN || kind == GFX_EV_KEY_UP) {
            NSString *chars = gfx_string_or(text_v, @"");
            /* no text given: the characters a real key event carries for the
             * keys that are not letters (arrows and the other function keys
             * also carry the Function flag, as from a keyboard) */
            if ([chars length] == 0) {
                unichar c = 0;
                bool fn = false;
                switch ((int)a) {
                    case 123: c = NSLeftArrowFunctionKey; fn = true; break;
                    case 124: c = NSRightArrowFunctionKey; fn = true; break;
                    case 125: c = NSDownArrowFunctionKey; fn = true; break;
                    case 126: c = NSUpArrowFunctionKey; fn = true; break;
                    case 115: c = NSHomeFunctionKey; fn = true; break;
                    case 119: c = NSEndFunctionKey; fn = true; break;
                    case 116: c = NSPageUpFunctionKey; fn = true; break;
                    case 121: c = NSPageDownFunctionKey; fn = true; break;
                    case 117: c = NSDeleteFunctionKey; fn = true; break;
                    case 36:  c = '\r'; break;
                    case 48:  c = '\t'; break;
                    case 49:  c = ' '; break;
                    case 51:  c = 0x7F; break;
                    case 53:  c = 0x1B; break;
                    default: break;
                }
                if (c) chars = [NSString stringWithCharacters:&c length:1];
                if (fn) flags |= NSEventModifierFlagFunction;
            }
            NSEvent *ev = [NSEvent keyEventWithType:(kind == GFX_EV_KEY_DOWN ? NSEventTypeKeyDown : NSEventTypeKeyUp)
                                           location:wp modifierFlags:flags timestamp:ts
                                       windowNumber:[win windowNumber] context:nil
                                         characters:chars charactersIgnoringModifiers:chars
                                          isARepeat:NO keyCode:(unsigned short)a];
            if (kind == GFX_EV_KEY_DOWN && (mods & GFX_MOD_CMD) && [[NSApp mainMenu] performKeyEquivalent:ev]) {
                /* a menu shortcut: its item fired */
            } else if (kind == GFX_EV_KEY_DOWN) {
                [view keyDown:ev];
            } else {
                [view keyUp:ev];
            }
        } else if (kind == GFX_EV_SCROLL) {
            CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, (int32_t)b, (int32_t)a);
            if (cg) {
                CGEventSetFlags(cg, (CGEventFlags)flags);
                NSEvent *ev = [NSEvent eventWithCGEvent:cg];
                gw->input.synth = 1;
                gw->input.synth_x = x; gw->input.synth_y = y;
                [view scrollWheel:ev];
                gw->input.synth = 0;
                CFRelease(cg);
            }
        } else if (kind == GFX_EV_MAGNIFY) {
            GfxEvent e; memset(&e, 0, sizeof e);
            e.kind = GFX_EV_MAGNIFY; e.x = x; e.y = y; e.dx = a; e.mods = mods;
            gfx_push(&gw->input, &e);
        } else if (kind == GFX_EV_OPEN) {
            /* as Finder's open-documents does: through the application delegate */
            NSString *path = gfx_string_or(text_v, @"");
            if ([path length] == 0) return w_bool(0);
            if (a == 1) {
                NSURL *url = [path containsString:@"://"] ? [NSURL URLWithString:path] : [NSURL fileURLWithPath:path];
                if (!url) return w_bool(0);
                NSPasteboard *pb = [NSPasteboard pasteboardWithUniqueName];
                [pb clearContents];
                [pb writeObjects:@[url]];
                TungstenSyntheticFileDrag *drag = [[TungstenSyntheticFileDrag alloc] init];
                drag.pasteboard = pb;
                BOOL ok = [view prepareForDragOperation:(id<NSDraggingInfo>)drag] &&
                          [view performDragOperation:(id<NSDraggingInfo>)drag];
                [drag release];
                [pb releaseGlobally];
                return w_bool(ok);
            }
            id<NSApplicationDelegate> d = [NSApp delegate];
            if (![d respondsToSelector:@selector(application:openURLs:)]) return w_bool(0);
            [d application:NSApp openURLs:@[[NSURL fileURLWithPath:path]]];
        } else if (kind == GFX_EV_MENU) {
            NSMenuItem *it = gfx_find_item([NSApp mainMenu], (NSInteger)a);
            if (!it || ![it isEnabled]) return w_bool(0);   /* a disabled item cannot be chosen */
            NSMenu *m = [it menu];
            [m performActionForItemAtIndex:[m indexOfItem:it]];
        } else if (kind == GFX_EV_CLOSE) {
            if (!(gw->flags & GFX_HIDDEN)) {
                [win performClose:nil];
            } else {
                /* performClose beeps instead of asking the delegate on a
                 * window that is not on screen: ask it directly */
                TungstenWindowDelegate *del = (TungstenWindowDelegate *)gw->delegate;
                if ([del windowShouldClose:win]) gw->input.should_close = true;
            }
        } else {
            w_raise(w_string("gfx.post_event: unknown event kind"));
        }
    }
    return w_bool(1);
}

/* ---- present helpers ----
 * Blit a 4-byte-per-pixel MTLBuffer (row-major, width*height pixels, in the
 * layer's byte order: RGBA8, or BGRA8 for a GFX_BGRA window) into the next
 * drawable and present it. The copy is clipped to the drawable, so a frame
 * drawn just before a resize still presents. The synchronous entry point
 * waits for completion so CPU-authored shared buffers are safe to overwrite
 * immediately after it returns. */
static WValue gfx_present_impl(WValue window_v, WValue buffer_v,
                               WValue width_v, WValue height_v,
                               bool wait_for_completion) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.present: not a window"));

    if (!w_is_obj(buffer_v) || w_subtag(buffer_v) != W_SUBTAG_GENERIC)
        w_raise(w_string("gfx.present: second arg must be a Metal buffer"));
    WMetalBuffer *b = (WMetalBuffer *)w_as_ptr(buffer_v);
    if (b->type != W_TYPE_METAL_BUFFER)
        w_raise(w_string("gfx.present: second arg must be a Metal buffer"));

    int w = (int)gfx_int(width_v);
    int h = (int)gfx_int(height_v);
    if (w <= 0 || h <= 0) return W_NIL;
    int64_t need = (int64_t)w * (int64_t)h * 4;
    if (b->size < need) w_raise(w_string("gfx.present: buffer smaller than width*height*4"));
    if (gw->closed) return w_bool(0);

    gfx_require_main_thread("gfx.present");
    @autoreleasepool {
        CAMetalLayer *layer = (CAMetalLayer *)gw->layer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) return w_bool(0); /* dropped frame — try again next tick */

        int cw = w, ch = h;
        if ((NSUInteger)cw > drawable.texture.width) cw = (int)drawable.texture.width;
        if ((NSUInteger)ch > drawable.texture.height) ch = (int)drawable.texture.height;

        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)gw->queue;
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        if (!cb) w_raise(w_string("gfx.present: could not create Metal command buffer"));
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        if (!blit) w_raise(w_string("gfx.present: could not create Metal blit encoder"));
        [blit copyFromBuffer:(id<MTLBuffer>)b->handle
                sourceOffset:(NSUInteger)b->offset
           sourceBytesPerRow:(NSUInteger)(w * 4)
         sourceBytesPerImage:(NSUInteger)need
                  sourceSize:MTLSizeMake(cw, ch, 1)
                   toTexture:drawable.texture
            destinationSlice:0
            destinationLevel:0
           destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
        [cb presentDrawable:drawable];
        [cb commit];

        if (wait_for_completion) {
            [cb waitUntilCompleted];
            if ([cb status] == MTLCommandBufferStatusError) {
                NSError *err = [cb error];
                const char *detail = err ? [[err localizedDescription] UTF8String]
                                         : "unknown error";
                char message[1024];
                snprintf(message, sizeof(message),
                         "gfx.present_wait: command buffer failed: %s", detail);
                w_raise(w_string(message));
            }
        }
    }
    return w_bool(1);
}

/* Asynchronous compatibility path. Existing callers retain responsibility for
 * keeping the source buffer unchanged until the GPU has consumed it. */
WValue w_gfx_present(WValue window_v, WValue buffer_v,
                     WValue width_v, WValue height_v) {
    return gfx_present_impl(window_v, buffer_v, width_v, height_v, false);
}

/* Blocking path for deterministic previews and other CPU-authored buffers. */
WValue w_gfx_present_wait(WValue window_v, WValue buffer_v,
                          WValue width_v, WValue height_v) {
    return gfx_present_impl(window_v, buffer_v, width_v, height_v, true);
}

/* ---- Retained MTLTexture & 2D Quad/Layer GPU Compositor ---- */

typedef struct GfxQuad {
    float dst[4];   /* x0_ndc, y0_ndc, x1_ndc, y1_ndc */
    float uv[4];    /* u0, v0, u1, v1 */
    float col[4];   /* r, g, b, a */
    float aux[4];   /* paper_r, paper_g, paper_b, mode */
} GfxQuad;

static NSString * const kGfxLayerMSL =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "struct GfxQuad {\n"
     "    float4 dst;\n"
     "    float4 uv;\n"
     "    float4 col;\n"
     "    float4 aux;\n"
     "};\n"
     "struct GfxYuv {\n"
     "    float4 a;   /* code scale (255 or 65535), ys, yo, co */\n"
     "    float4 b;   /* crr, cbg, crg, cbb (0..255 output units per code) */\n"
     "    float4 c;   /* kind (0 Y'CbCr, 1 grey, 2 GBR planes), CICP transfer (0: output is sRGB already), hdr */\n"
     "    float4 m0;  /* source-primaries linear RGB -> linear sRGB, row-major */\n"
     "    float4 m1;\n"
     "    float4 m2;\n"
     "};\n"
     "static inline float gfx_eotf(float tr, float v) {\n"
     "    v = max(v, 0.0f);\n"
     "    if (tr == 13.0f) return v <= 0.04045f ? v / 12.92f : pow((v + 0.055f) / 1.055f, 2.4f);\n"
     "    if (tr == 1.0f || tr == 6.0f || tr == 14.0f || tr == 15.0f) return v < 0.081f ? v / 4.5f : pow((v + 0.099f) / 1.099f, 1.0f / 0.45f);\n"
     "    if (tr == 4.0f) return pow(v, 2.2f);\n"
     "    if (tr == 5.0f) return pow(v, 2.8f);\n"
     "    if (tr == 8.0f) return v;\n"
     "    if (tr == 16.0f) {\n"
     "        float p = pow(v, 1.0f / 78.84375f);\n"
     "        float num = max(p - 0.8359375f, 0.0f);\n"
     "        return pow(num / (18.8515625f - 18.6875f * p), 1.0f / 0.1593017578125f) * (10000.0f / 203.0f);\n"
     "    }\n"
     "    float lin = v <= 0.5f ? (v * v) / 3.0f : (exp((v - 0.55991073f) / 0.17883277f) + 0.28466892f) / 12.0f;\n"
     "    return lin * 3.7743f;\n"
     "}\n"
     "static inline float gfx_srgb_oetf(float l) {\n"
     "    l = clamp(l, 0.0f, 1.0f);\n"
     "    return l <= 0.0031308f ? l * 12.92f : 1.055f * pow(l, 1.0f / 2.4f) - 0.055f;\n"
     "}\n"
     "static inline float3 gfx_yuv_rgb(float2 uv, texture2d<float> ty, texture2d<float> tu,\n"
     "                                 texture2d<float> tv, sampler lin, constant GfxYuv &p) {\n"
     "    float y = ty.sample(lin, uv).r * p.a.x;\n"
     "    float2 c2 = tu.sample(lin, uv).rg;\n"
     "    float u = c2.x * p.a.x;\n"
     "    float v = (p.c.w != 0.0f ? c2.y : tv.sample(lin, uv).r) * p.a.x;\n"
     "    float3 rgb;\n"
     "    if (p.c.x == 2.0f) {\n"
     "        rgb = float3(v, y, u) * p.a.y;\n"
     "    } else {\n"
     "        float l = p.a.y * (y - p.a.z);\n"
     "        if (p.c.x == 1.0f) {\n"
     "            rgb = float3(l);\n"
     "        } else {\n"
     "            u -= p.a.w;\n"
     "            v -= p.a.w;\n"
     "            rgb = float3(l + p.b.x * v, l - p.b.y * u - p.b.z * v, l + p.b.w * u);\n"
     "        }\n"
     "    }\n"
     "    rgb = clamp(rgb * (1.0f / 255.0f), 0.0f, 1.0f);\n"
     "    if (p.c.y != 0.0f) {\n"
     "        float3 li = float3(gfx_eotf(p.c.y, rgb.r), gfx_eotf(p.c.y, rgb.g), gfx_eotf(p.c.y, rgb.b));\n"
     "        float3 o = float3(dot(p.m0.xyz, li), dot(p.m1.xyz, li), dot(p.m2.xyz, li));\n"
     "        if (p.c.z != 0.0f) {\n"
     "            float mx = max(o.r, max(o.g, o.b));\n"
     "            if (mx > 0.8f) {\n"
     "                float t = mx - 0.8f;\n"
     "                o *= (0.8f + 0.2f * t / (t + 0.2f)) / mx;\n"
     "            }\n"
     "        }\n"
     "        rgb = float3(gfx_srgb_oetf(o.r), gfx_srgb_oetf(o.g), gfx_srgb_oetf(o.b));\n"
     "    }\n"
     "    return rgb;\n"
     "}\n"
     "static inline float3 gfx_srgb_to_p3(float3 c) {\n"
     "    float3 l = float3(gfx_eotf(13.0f, c.r), gfx_eotf(13.0f, c.g), gfx_eotf(13.0f, c.b));\n"
     "    float3 o = float3(dot(float3(0.8224621f, 0.1775380f, 0.0f), l),\n"
     "                      dot(float3(0.0331941f, 0.9668058f, 0.0f), l),\n"
     "                      dot(float3(0.0170827f, 0.0723974f, 0.9105199f), l));\n"
     "    return float3(gfx_srgb_oetf(o.r), gfx_srgb_oetf(o.g), gfx_srgb_oetf(o.b));\n"
     "}\n"
     "static inline float4 gfx_tex_p3(float4 s, bool premul) {\n"
     "    if (s.a <= 0.0f) return s;\n"
     "    float3 c = premul ? s.rgb / s.a : s.rgb;\n"
     "    c = gfx_srgb_to_p3(c);\n"
     "    return float4(premul ? c * s.a : c, s.a);\n"
     "}\n"
     "struct VSOut {\n"
     "    float4 pos [[position]];\n"
     "    float2 uv;\n"
     "    float4 col;\n"
     "    float4 aux;\n"
     "};\n"
     "vertex VSOut gfx_layer_vs(uint vid [[vertex_id]], uint iid [[instance_id]],\n"
     "                          device const GfxQuad *quads [[buffer(0)]]) {\n"
     "    GfxQuad q = quads[iid];\n"
     "    float2 c = float2((vid & 1u) ? q.dst.z : q.dst.x,\n"
     "                      (vid & 2u) ? q.dst.w : q.dst.y);\n"
     "    float2 t = float2((vid & 1u) ? q.uv.z  : q.uv.x,\n"
     "                      (vid & 2u) ? q.uv.w  : q.uv.y);\n"
     "    VSOut o;\n"
     "    o.pos = float4(c, 0.0f, 1.0f);\n"
     "    o.uv  = t;\n"
     "    o.col = q.col;\n"
     "    o.aux = q.aux;\n"
     "    return o;\n"
     "}\n"
     "fragment float4 gfx_layer_fs_tile(VSOut in [[stage_in]],\n"
     "                                  texture2d<float> tex [[texture(0)]],\n"
     "                                  texture2d<float> tex_u [[texture(1)]],\n"
     "                                  texture2d<float> tex_v [[texture(2)]],\n"
     "                                  sampler smp [[sampler(0)]],\n"
     "                                  sampler lin [[sampler(1)]],\n"
     "                                  constant GfxYuv &yuv [[buffer(0)]],\n"
     "                                  float4 dst [[color(0)]]) {\n"
     "    int mode = int(rint(in.aux.w));\n"
     "    if (mode == 5) {\n"
     "        float3 rgb = gfx_yuv_rgb(in.uv, tex, tex_u, tex_v, lin, yuv);\n"
     "        return float4(mix(dst.rgb, rgb, in.col.a), 1.0f);\n"
     "    } else if (mode == 0) {\n"
     "        float4 s = tex.sample(smp, in.uv);\n"
     "        if (in.aux.x > 0.5f) s = gfx_tex_p3(s, true);\n"
     "        s *= in.col.a;\n"
     "        return float4(s.rgb + dst.rgb * (1.0f - s.a), 1.0f);\n"
     "    } else if (mode == 1) {\n"
     "        float4 s = tex.sample(smp, in.uv);\n"
     "        if (in.aux.x > 0.5f) s = gfx_tex_p3(s, false);\n"
     "        float a = s.a * in.col.a;\n"
     "        return float4(s.rgb * a + dst.rgb * (1.0f - a), 1.0f);\n"
     "    } else if (mode == 2) {\n"
     "        return float4(mix(dst.rgb, in.col.rgb, in.col.a), 1.0f);\n"
     "    } else if (mode == 3) {\n"
     "        bool exposed = all(abs(dst.rgb - in.aux.rgb) < (0.5f / 255.0f));\n"
     "        return exposed ? float4(mix(in.aux.rgb, in.col.rgb, in.col.a), 1.0f) : dst;\n"
     "    } else {\n"
     "        float m = tex.sample(smp, in.uv).b;\n"
     "        float a = m * in.col.a;\n"
     "        return float4(mix(dst.rgb, in.col.rgb, a), 1.0f);\n"
     "    }\n"
     "}\n"
     "fragment float4 gfx_layer_fs_alpha(VSOut in [[stage_in]],\n"
     "                                   texture2d<float> tex [[texture(0)]],\n"
     "                                   texture2d<float> tex_u [[texture(1)]],\n"
     "                                   texture2d<float> tex_v [[texture(2)]],\n"
     "                                   sampler smp [[sampler(0)]],\n"
     "                                   sampler lin [[sampler(1)]],\n"
     "                                   constant GfxYuv &yuv [[buffer(0)]]) {\n"
     "    int mode = int(rint(in.aux.w));\n"
     "    if (mode == 5) {\n"
     "        float3 rgb = gfx_yuv_rgb(in.uv, tex, tex_u, tex_v, lin, yuv);\n"
     "        return float4(rgb * in.col.a, in.col.a);\n"
     "    } else if (mode == 0) {\n"
     "        float4 s = tex.sample(smp, in.uv);\n"
     "        if (in.aux.x > 0.5f) s = gfx_tex_p3(s, true);\n"
     "        return s * in.col.a;\n"
     "    } else if (mode == 1) {\n"
     "        float4 s = tex.sample(smp, in.uv);\n"
     "        if (in.aux.x > 0.5f) s = gfx_tex_p3(s, false);\n"
     "        float a = s.a * in.col.a;\n"
     "        return float4(s.rgb * a, a);\n"
     "    } else if (mode == 4) {\n"
     "        float a = tex.sample(smp, in.uv).b * in.col.a;\n"
     "        return float4(in.col.rgb * a, a);\n"
     "    } else {\n"
     "        return float4(in.col.rgb * in.col.a, in.col.a);\n"
     "    }\n"
     "}\n";

static void gfx_ensure_compositor(WGfxWindow *gw) {
    if (gw->pso_tile || gw->pso_alpha) return;
    id<MTLDevice> dev = (id<MTLDevice>)gw->device;
    CAMetalLayer *layer = (CAMetalLayer *)gw->layer;
    MTLPixelFormat pf = layer.pixelFormat;

    if (!gw->frame_sem) gw->frame_sem = dispatch_semaphore_create(3);

    if (!gw->sampler) {
        MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
        sd.minFilter = MTLSamplerMinMagFilterNearest;
        sd.magFilter = MTLSamplerMinMagFilterNearest;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        gw->sampler = (void *)[dev newSamplerStateWithDescriptor:sd];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        gw->sampler_lin = (void *)[dev newSamplerStateWithDescriptor:sd];
        [sd release];
    }
    if (!gw->dummy_tex) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:1 height:1 mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeShared;
        id<MTLTexture> dt = [dev newTextureWithDescriptor:td];
        uint32_t white = 0xFFFFFFFFu;
        [dt replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&white bytesPerRow:4];
        gw->dummy_tex = (void *)dt;
    }

    NSError *err = nil;
    MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
    id<MTLLibrary> lib = [dev newLibraryWithSource:kGfxLayerMSL options:opts error:&err];
    [opts release];
    if (!lib) {
        const char *msg = err ? [[err localizedDescription] UTF8String] : "shader compile error";
        char buf[512];
        snprintf(buf, sizeof buf, "gfx.present_layers: %s", msg);
        w_raise(w_string(buf));
    }
    id<MTLFunction> vs = [lib newFunctionWithName:@"gfx_layer_vs"];
    if ([dev supportsFamily:MTLGPUFamilyApple1]) {
        id<MTLFunction> fs_tile = [lib newFunctionWithName:@"gfx_layer_fs_tile"];
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vs;
        pd.fragmentFunction = fs_tile;
        pd.colorAttachments[0].pixelFormat = pf;
        pd.colorAttachments[0].blendingEnabled = NO;
        NSError *perr = nil;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&perr];
        [pd release];
        [fs_tile release];
        if (pso) gw->pso_tile = (void *)pso;
    }
    if (!gw->pso_tile) {
        id<MTLFunction> fs_a = [lib newFunctionWithName:@"gfx_layer_fs_alpha"];
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vs;
        pd.fragmentFunction = fs_a;
        pd.colorAttachments[0].pixelFormat = pf;
        pd.colorAttachments[0].blendingEnabled = YES;
        pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        NSError *perr = nil;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&perr];
        [pd release];
        [fs_a release];
        if (!pso) {
            [vs release];
            [lib release];
            w_raise(w_string("gfx.present_layers: failed to create render pipeline"));
        }
        gw->pso_alpha = (void *)pso;
    }
    [vs release];
    [lib release];
}

static id<MTLTexture> gfx_make_tex(id<MTLDevice> dev, int w, int h, int bgra) {
    MTLPixelFormat pf = bgra ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA8Unorm;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                                                  width:(NSUInteger)w
                                                                                 height:(NSUInteger)h
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    return [dev newTextureWithDescriptor:td];
}

WValue w_gfx_tex_new(WValue window_v, WValue width_v, WValue height_v, WValue bgra_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_new");
    int w = (int)gfx_int(width_v);
    int h = (int)gfx_int(height_v);
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384)
        w_raise(w_string("gfx.tex_new: width/height must be in 1..16384"));
    int bgra = (bgra_v != W_NIL && bgra_v != W_FALSE && !(w_is_int(bgra_v) && w_as_int(bgra_v) == 0)) ? 1 : 0;
    int slot = -1;
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        if (!gw->tex[i]) { slot = i; break; }
    }
    if (slot < 0) w_raise(w_string("gfx.tex_new: texture table full (1024)"));
    @autoreleasepool {
        id<MTLTexture> t = gfx_make_tex((id<MTLDevice>)gw->device, w, h, bgra);
        if (!t) w_raise(w_string("gfx.tex_new: Metal texture allocation failed"));
        gw->tex[slot] = (void *)t;
        gw->tex_used_seq[slot] = 0;
        gw->tex_bgra[slot] = (uint8_t)bgra;
        gw->tex_space[slot] = 0;
    }
    return w_int(slot + 1);
}

WValue w_gfx_tex_upload(WValue window_v, WValue tex_id_v, WValue src_v, WValue stride_v,
                        WValue x_v, WValue y_v, WValue w_v, WValue h_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_upload");
    int slot = (int)gfx_int(tex_id_v) - 1;
    if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot]) return w_bool(0);
    id<MTLTexture> tex = (id<MTLTexture>)gw->tex[slot];
    int tw = (int)tex.width, th = (int)tex.height;
    int x = x_v == W_NIL ? 0 : (int)gfx_int(x_v);
    int y = y_v == W_NIL ? 0 : (int)gfx_int(y_v);
    int w = w_v == W_NIL ? (tw - x) : (int)gfx_int(w_v);
    int h = h_v == W_NIL ? (th - y) : (int)gfx_int(h_v);
    if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > tw || y + h > th) return w_bool(0);
    int stride = stride_v == W_NIL ? (w * 4) : (int)gfx_int(stride_v);
    if (stride < w * 4) w_raise(w_string("gfx.tex_upload: stride < width * 4"));

    const void *ptr = NULL;
    size_t min_bytes = (size_t)(h - 1) * (size_t)stride + (size_t)w * 4;
    if (w_is_int(src_v)) {
        ptr = (const void *)(uintptr_t)w_as_int(src_v);
    } else if (w_is_array(src_v)) {
        WArray *a = w_as_array(src_v);
        size_t elem = a->ebits == 8 ? 1 : ((a->ebits == 32 || a->ebits == 33) ? 4 : 0);
        if (elem == 0) w_raise(w_string("gfx.tex_upload: array must be ByteArray or u32[]/i32[]"));
        if ((size_t)a->size * elem < min_bytes) w_raise(w_string("gfx.tex_upload: array smaller than upload region"));
        ptr = (const uint8_t *)a->slots + (size_t)a->start * elem;
    } else if (w_is_obj(src_v) && w_subtag(src_v) == W_SUBTAG_GENERIC) {
        WMetalBuffer *b = (WMetalBuffer *)w_as_ptr(src_v);
        if (b->type == W_TYPE_METAL_BUFFER && (size_t)b->size >= min_bytes) {
            ptr = (const uint8_t *)[(id<MTLBuffer>)b->handle contents] + b->offset;
        }
    }
    if (!ptr) w_raise(w_string("gfx.tex_upload: invalid pixel source"));

    @autoreleasepool {
        uint64_t done = __atomic_load_n(&gw->done_cb_seq, __ATOMIC_ACQUIRE);
        if (gw->tex_used_seq[slot] > done && x == 0 && y == 0 && w == tw && h == th) {
            /* In-flight CB still references `tex`: swap in a fresh shared texture so
             * CPU upload never races GPU sampling, and let Metal release the old one. */
            id<MTLTexture> fresh = gfx_make_tex((id<MTLDevice>)gw->device, tw, th, gw->tex_bgra[slot]);
            if (fresh) {
                [tex release];
                tex = fresh;
                gw->tex[slot] = (void *)tex;
                gw->tex_used_seq[slot] = 0;
            }
        }
        [tex replaceRegion:MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, (NSUInteger)w, (NSUInteger)h)
               mipmapLevel:0
                 withBytes:ptr
               bytesPerRow:(NSUInteger)stride];
    }
    return w_bool(1);
}

WValue w_gfx_tex_free(WValue window_v, WValue tex_id_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_free");
    int slot = (int)gfx_int(tex_id_v) - 1;
    if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot]) return w_bool(0);
    @autoreleasepool {
        gfx_surf_retire(gw, slot);
        [(id<MTLTexture>)gw->tex[slot] release];
        gw->tex[slot] = NULL;
        gw->tex_used_seq[slot] = 0;
        if (gw->tex_cb[slot]) { [(id<MTLTexture>)gw->tex_cb[slot] release]; gw->tex_cb[slot] = NULL; }
        if (gw->tex_cr[slot]) { [(id<MTLTexture>)gw->tex_cr[slot] release]; gw->tex_cr[slot] = NULL; }
        gw->tex_planar[slot] = 0;
        gw->tex_space[slot] = 0;
    }
    return w_bool(1);
}

/* ---- colour management ----
 * w_gfx_set_color_space(window, "srgb" | "display_p3") tags the layer. In a
 * Display P3 window the compositor converts what is sRGB into P3 as it draws:
 * RGBA textures not marked P3 (w_gfx_tex_set_space), colour quads, the
 * background, and video (its CICP matrix retargeted to P3 primaries; untagged
 * video is taken as BT.709/sRGB). Returns the space now in effect. */
static const double GFX_SRGB_P3[9] = {0.8224621, 0.1775380, 0.0000000,
                                      0.0331941, 0.9668058, 0.0000000,
                                      0.0170827, 0.0723974, 0.9105199};

static double gfx_srgb_lin(double v) { return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4); }
static double gfx_srgb_enc(double l) {
    if (l <= 0) return 0;
    if (l >= 1) return 1;
    return l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1.0 / 2.4) - 0.055;
}

/* An sRGB colour (0..1, gamma-encoded) in Display P3, in place. */
static void gfx_rgb_to_p3(float *c) {
    double l[3] = {gfx_srgb_lin(c[0]), gfx_srgb_lin(c[1]), gfx_srgb_lin(c[2])};
    for (int i = 0; i < 3; i++)
        c[i] = (float)gfx_srgb_enc(GFX_SRGB_P3[i * 3] * l[0] + GFX_SRGB_P3[i * 3 + 1] * l[1] + GFX_SRGB_P3[i * 3 + 2] * l[2]);
}

WValue w_gfx_set_color_space(WValue window_v, WValue name_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.set_color_space");
    gfx_require_main_thread("gfx.set_color_space");
    NSString *nm = gfx_string_or(name_v, @"srgb");
    int p3 = [nm isEqualToString:@"display_p3"] || [nm isEqualToString:@"p3"];
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(p3 ? kCGColorSpaceDisplayP3 : kCGColorSpaceSRGB);
    ((CAMetalLayer *)gw->layer).colorspace = cs;
    CGColorSpaceRelease(cs);
    gw->out_space = p3;
    return w_string(p3 ? "display_p3" : "srgb");
}

/* The gamut of the screen the window is on: "p3" when it can show Display P3,
 * else "srgb". */
WValue w_gfx_display_gamut(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.display_gamut");
    NSScreen *sc = [(NSWindow *)gw->window screen];
    if (!sc) sc = [NSScreen mainScreen];
    return w_string(sc && [sc canRepresentDisplayGamut:NSDisplayGamutP3] ? "p3" : "srgb");
}

/* EDR headroom of the window's screen: 1.0 for SDR, >1 when it can show HDR
 * highlights (maximumPotentialExtendedDynamicRangeColorComponentValue). */
WValue w_gfx_display_headroom(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.display_headroom");
    NSScreen *sc = [(NSWindow *)gw->window screen];
    if (!sc) sc = [NSScreen mainScreen];
    double v = sc ? (double)[sc maximumPotentialExtendedDynamicRangeColorComponentValue] : 1.0;
    return w_float(v);
}

/* w_gfx_tex_set_space(window, id, "srgb" | "display_p3"): the colour space of
 * an RGBA texture's pixels (default sRGB). */
WValue w_gfx_tex_set_space(WValue window_v, WValue tex_id_v, WValue name_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_set_space");
    int slot = (int)gfx_int(tex_id_v) - 1;
    if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot]) return w_bool(0);
    NSString *nm = gfx_string_or(name_v, @"srgb");
    gw->tex_space[slot] = ([nm isEqualToString:@"display_p3"] || [nm isEqualToString:@"p3"]) ? 1 : 0;
    return w_bool(1);
}

/* ---- planar Y'CbCr video textures ----
 * A video frame goes to the GPU as its three planes (R8Unorm, or R16Unorm for
 * 9..16-bit samples) and is converted to RGB by the compositor's fragment
 * shader while it is drawn (bilinear chroma upsampling and scaling for free):
 * no CPU RGBA, no CPU colour conversion, one memcpy per plane per frame.
 * A yuv texture id is drawn by the same present_layers kinds as an RGBA one
 * (0 premultiplied / 4 straight: the frame is opaque, param0 is its alpha). */

static id<MTLTexture> gfx_make_plane(id<MTLDevice> dev, int w, int h, int fmt16) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:(fmt16 ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm)
                                                                                  width:(NSUInteger)w
                                                                                 height:(NSUInteger)h
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    return [dev newTextureWithDescriptor:td];
}

/* surface-backed slots: release what a slot holds of a decoder surface, now
 * or (when an in-flight frame still samples it) once that frame completes */
static void gfx_surf_release3(void **r) {
    if (r[0]) CFRelease((CVMetalTextureRef)r[0]);
    if (r[1]) CFRelease((CVMetalTextureRef)r[1]);
    if (r[2]) CVPixelBufferRelease((CVPixelBufferRef)r[2]);
    r[0] = r[1] = r[2] = NULL;
}

static void gfx_surf_reap(WGfxWindow *gw) {
    uint64_t done = __atomic_load_n(&gw->done_cb_seq, __ATOMIC_ACQUIRE);
    int k = 0;
    for (int i = 0; i < gw->n_surf_dead; i++) {
        if (gw->surf_dead[i].seq <= done) gfx_surf_release3(gw->surf_dead[i].r);
        else gw->surf_dead[k++] = gw->surf_dead[i];
    }
    gw->n_surf_dead = k;
}

static void gfx_surf_retire(WGfxWindow *gw, int slot) {
    void **r = gw->tex_surf[slot];
    if (!r[0] && !r[1] && !r[2]) return;
    gfx_surf_reap(gw);
    uint64_t done = __atomic_load_n(&gw->done_cb_seq, __ATOMIC_ACQUIRE);
    if (gw->tex_used_seq[slot] > done && gw->n_surf_dead < 64) {
        int n = gw->n_surf_dead++;
        gw->surf_dead[n].seq = gw->tex_used_seq[slot];
        for (int i = 0; i < 3; i++) { gw->surf_dead[n].r[i] = r[i]; r[i] = NULL; }
    } else {
        gfx_surf_release3(r);
    }
}

/* w_gfx_tex_new_yuv(window, width, height, chroma_w, chroma_h, sixteen) -> id */
WValue w_gfx_tex_new_yuv(WValue window_v, WValue width_v, WValue height_v,
                         WValue cw_v, WValue ch_v, WValue sixteen_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_new_yuv");
    int w = (int)gfx_int(width_v), h = (int)gfx_int(height_v);
    int cw = (int)gfx_int(cw_v), ch = (int)gfx_int(ch_v);
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384 || cw <= 0 || ch <= 0 || cw > w || ch > h)
        w_raise(w_string("gfx.tex_new_yuv: bad plane sizes"));
    int fmt16 = (sixteen_v != W_NIL && sixteen_v != W_FALSE && !(w_is_int(sixteen_v) && w_as_int(sixteen_v) == 0)) ? 1 : 0;
    int slot = -1;
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        if (!gw->tex[i]) { slot = i; break; }
    }
    if (slot < 0) w_raise(w_string("gfx.tex_new_yuv: texture table full (1024)"));
    @autoreleasepool {
        id<MTLDevice> dev = (id<MTLDevice>)gw->device;
        id<MTLTexture> ty = gfx_make_plane(dev, w, h, fmt16);
        id<MTLTexture> tu = gfx_make_plane(dev, cw, ch, fmt16);
        id<MTLTexture> tv = gfx_make_plane(dev, cw, ch, fmt16);
        if (!ty || !tu || !tv) {
            [ty release]; [tu release]; [tv release];
            w_raise(w_string("gfx.tex_new_yuv: Metal texture allocation failed"));
        }
        gw->tex[slot] = (void *)ty;
        gw->tex_cb[slot] = (void *)tu;
        gw->tex_cr[slot] = (void *)tv;
        gw->tex_used_seq[slot] = 0;
        gw->tex_bgra[slot] = 0;
        gw->tex_planar[slot] = 1;
        gw->tex_fmt[slot] = (uint8_t)fmt16;
        memset(gw->tex_yuv[slot], 0, sizeof gw->tex_yuv[slot]);
    }
    return w_int(slot + 1);
}

static const uint8_t *gfx_plane_ptr(WValue v, size_t esize, size_t need, const char *what) {
    if (!w_is_array(v)) w_raise(w_string("gfx.tex_upload_yuv: planes must be u8[] / u16[] arrays"));
    WArray *a = w_as_array(v);
    size_t elem = (a->ebits == 8 || a->ebits == 108) ? 1 : ((a->ebits == 16 || a->ebits == 116) ? 2 : 0);
    if (elem != esize) w_raise(w_string("gfx.tex_upload_yuv: plane element size does not match the texture (u8[] for 8-bit, u16[] otherwise)"));
    if ((size_t)a->size < need) {
        char buf[160];
        snprintf(buf, sizeof buf, "gfx.tex_upload_yuv: %s plane has %lld samples, need %zu", what, (long long)a->size, need);
        w_raise(w_string(buf));
    }
    return (const uint8_t *)a->slots + (size_t)a->start * elem;
}

/* w_gfx_tex_upload_yuv(window, id, planes, params):
 *   planes  [y, cb, cr] (u8[] for an R8 texture, u16[] for R16; cb/cr ignored
 *           for grey frames but must be present)
 *   params  f64[] / Array: [y_stride, c_stride, x0, y0, cx0, cy0,
 *           scale, ys, yo, co, crr, cbg, crg, cbb, kind
 *           (, transfer, m00 m01 m02 m10 m11 m12 m20 m21 m22)]
 *           the optional 10 a CICP conversion to sRGB after the matrix
 *           (core/codec/cicp: transfer code, linear primaries matrix);
 *           strides in samples; (x0, y0) / (cx0, cy0) the top-left visible
 *           sample of the luma / chroma planes (crop); scale the code value of
 *           a sample of 1.0 (255 or 65535); the rest as GfxYuv.
 * Returns true. A texture an in-flight frame still samples is replaced by
 * fresh planes (the CPU never writes what the GPU is reading). */
WValue w_gfx_tex_upload_yuv(WValue window_v, WValue tex_id_v, WValue planes_v, WValue params_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_upload_yuv");
    int slot = (int)gfx_int(tex_id_v) - 1;
    if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot] || !gw->tex_planar[slot]) return w_bool(0);
    if (!w_is_array(planes_v) || w_as_array(planes_v)->size < 3) w_raise(w_string("gfx.tex_upload_yuv: planes must be [y, cb, cr]"));
    if (!w_is_array(params_v) || w_as_array(params_v)->size < 15) w_raise(w_string("gfx.tex_upload_yuv: params needs 15 numbers"));
    double pr[25] = {0};
    int npr = w_as_array(params_v)->size >= 25 ? 25 : 15;
    for (int i = 0; i < npr; i++) pr[i] = gfx_num(w_array_get(params_v, w_int(i)), "param");
    id<MTLTexture> ty = (id<MTLTexture>)gw->tex[slot];
    id<MTLTexture> tu = (id<MTLTexture>)gw->tex_cb[slot];
    id<MTLTexture> tv = (id<MTLTexture>)gw->tex_cr[slot];
    size_t es = gw->tex_fmt[slot] ? 2 : 1;
    size_t w = ty.width, h = ty.height, cw = tu.width, ch = tu.height;
    size_t ys = (size_t)pr[0], cs = (size_t)pr[1];
    size_t x0 = (size_t)pr[2], y0 = (size_t)pr[3], cx0 = (size_t)pr[4], cy0 = (size_t)pr[5];
    if (ys < x0 + w || (pr[14] != 1.0 && cs < cx0 + cw)) w_raise(w_string("gfx.tex_upload_yuv: stride smaller than the visible width"));
    const uint8_t *py = gfx_plane_ptr(w_array_get(planes_v, w_int(0)), es, (y0 + h - 1) * ys + x0 + w, "luma");
    const uint8_t *pu = NULL, *pv = NULL;
    if (pr[14] != 1.0) {
        pu = gfx_plane_ptr(w_array_get(planes_v, w_int(1)), es, (cy0 + ch - 1) * cs + cx0 + cw, "cb");
        pv = gfx_plane_ptr(w_array_get(planes_v, w_int(2)), es, (cy0 + ch - 1) * cs + cx0 + cw, "cr");
    }
    @autoreleasepool {
        uint64_t done = __atomic_load_n(&gw->done_cb_seq, __ATOMIC_ACQUIRE);
        if (gw->tex_surf[slot][2]) {
            /* the slot shows a decoder surface: never write into it, draw into new planes */
            gfx_surf_retire(gw, slot);
            id<MTLDevice> dev = (id<MTLDevice>)gw->device;
            int f16 = gw->tex_fmt[slot];
            [ty release]; [tu release]; [tv release];
            ty = gfx_make_plane(dev, (int)w, (int)h, f16);
            tu = gfx_make_plane(dev, (int)cw, (int)ch, f16);
            tv = gfx_make_plane(dev, (int)cw, (int)ch, f16);
            gw->tex[slot] = (void *)ty;
            gw->tex_cb[slot] = (void *)tu;
            gw->tex_cr[slot] = (void *)tv;
            gw->tex_used_seq[slot] = 0;
            if (!ty || !tu || !tv) return w_bool(0);
        } else if (gw->tex_used_seq[slot] > done) {
            id<MTLDevice> dev = (id<MTLDevice>)gw->device;
            id<MTLTexture> ny = gfx_make_plane(dev, (int)w, (int)h, gw->tex_fmt[slot]);
            id<MTLTexture> nu = gfx_make_plane(dev, (int)cw, (int)ch, gw->tex_fmt[slot]);
            id<MTLTexture> nv = gfx_make_plane(dev, (int)cw, (int)ch, gw->tex_fmt[slot]);
            if (ny && nu && nv) {
                [ty release]; [tu release]; [tv release];
                ty = ny; tu = nu; tv = nv;
                gw->tex[slot] = (void *)ty;
                gw->tex_cb[slot] = (void *)tu;
                gw->tex_cr[slot] = (void *)tv;
                gw->tex_used_seq[slot] = 0;
            } else {
                [ny release]; [nu release]; [nv release];
            }
        }
        [ty replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0
                withBytes:py + (y0 * ys + x0) * es bytesPerRow:ys * es];
        if (pu) {
            [tu replaceRegion:MTLRegionMake2D(0, 0, cw, ch) mipmapLevel:0
                    withBytes:pu + (cy0 * cs + cx0) * es bytesPerRow:cs * es];
            [tv replaceRegion:MTLRegionMake2D(0, 0, cw, ch) mipmapLevel:0
                    withBytes:pv + (cy0 * cs + cx0) * es bytesPerRow:cs * es];
        }
        float *p = gw->tex_yuv[slot];
        memset(p, 0, sizeof gw->tex_yuv[slot]);
        for (int i = 0; i < 8; i++) p[i] = (float)pr[6 + i];
        p[8] = (float)pr[14];
        p[9] = (float)pr[15];                                   /* transfer (0: none) */
        p[10] = (pr[15] == 16.0 || pr[15] == 18.0) ? 1.0f : 0.0f;  /* hdr shoulder */
        for (int r = 0; r < 3; r++)
            for (int k = 0; k < 3; k++) p[12 + r * 4 + k] = (float)pr[16 + r * 3 + k];
    }
    return w_bool(1);
}

/* w_gfx_tex_set_surface(window, id, pixel_buffer, params): show a decoder's
 * CVPixelBuffer (NV12 / P010, IOSurface-backed: core/codec/system with
 * cfg.surfaces; pixel_buffer is runtime/media's w_media_surface_ptr) in a yuv
 * slot with no copy: its planes become the slot's textures through a
 * CVMetalTextureCache (luma R8/R16, interleaved chroma RG8/RG16) and the
 * shader reads Cb/Cr from one texture. The slot retains the buffer until it is
 * replaced and the GPU is done with it. params as for w_gfx_tex_upload_yuv
 * (strides and crop are ignored; scale is the code value of 1.0 at the
 * stream's bit depth). The slot's size follows the buffer's. Returns false
 * when the buffer cannot be wrapped (the caller copies the planes instead). */
WValue w_gfx_tex_set_surface(WValue window_v, WValue tex_id_v, WValue pb_v, WValue params_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.tex_set_surface");
    int slot = (int)gfx_int(tex_id_v) - 1;
    if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot] || !gw->tex_planar[slot]) return w_bool(0);
    CVPixelBufferRef pb = (CVPixelBufferRef)(intptr_t)gfx_int(pb_v);
    if (!pb || CVPixelBufferGetPlaneCount(pb) != 2) return w_bool(0);
    if (!w_is_array(params_v) || w_as_array(params_v)->size < 15) w_raise(w_string("gfx.tex_set_surface: params needs 15 numbers"));
    double pr[25] = {0};
    int npr = w_as_array(params_v)->size >= 25 ? 25 : 15;
    for (int i = 0; i < npr; i++) pr[i] = gfx_num(w_array_get(params_v, w_int(i)), "param");
    OSType f = CVPixelBufferGetPixelFormatType(pb);
    int f16 = (f == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || f == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) ? 1 : 0;
    if (!f16 && f != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && f != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) return w_bool(0);
    @autoreleasepool {
        if (!gw->cv_cache) {
            CVMetalTextureCacheRef c = NULL;
            if (CVMetalTextureCacheCreate(NULL, NULL, (id<MTLDevice>)gw->device, NULL, &c) != kCVReturnSuccess) return w_bool(0);
            gw->cv_cache = c;
        }
        CVMetalTextureCacheRef cache = (CVMetalTextureCacheRef)gw->cv_cache;
        CVMetalTextureRef cy = NULL, cc = NULL;
        size_t w0 = CVPixelBufferGetWidthOfPlane(pb, 0), h0 = CVPixelBufferGetHeightOfPlane(pb, 0);
        size_t w1 = CVPixelBufferGetWidthOfPlane(pb, 1), h1 = CVPixelBufferGetHeightOfPlane(pb, 1);
        CVReturn r0 = CVMetalTextureCacheCreateTextureFromImage(NULL, cache, pb, NULL, f16 ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm, w0, h0, 0, &cy);
        CVReturn r1 = CVMetalTextureCacheCreateTextureFromImage(NULL, cache, pb, NULL, f16 ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm, w1, h1, 1, &cc);
        id<MTLTexture> ty = cy ? CVMetalTextureGetTexture(cy) : nil, tc = cc ? CVMetalTextureGetTexture(cc) : nil;
        if (r0 != kCVReturnSuccess || r1 != kCVReturnSuccess || !ty || !tc) {
            if (cy) CFRelease(cy);
            if (cc) CFRelease(cc);
            return w_bool(0);
        }
        gfx_surf_retire(gw, slot);
        [(id<MTLTexture>)gw->tex[slot] release];
        if (gw->tex_cb[slot]) [(id<MTLTexture>)gw->tex_cb[slot] release];
        if (gw->tex_cr[slot]) [(id<MTLTexture>)gw->tex_cr[slot] release];
        gw->tex[slot] = (void *)[ty retain];
        gw->tex_cb[slot] = (void *)[tc retain];
        gw->tex_cr[slot] = (void *)[tc retain];
        gw->tex_used_seq[slot] = 0;
        gw->tex_fmt[slot] = (uint8_t)f16;
        gw->tex_surf[slot][0] = cy;
        gw->tex_surf[slot][1] = cc;
        gw->tex_surf[slot][2] = CVPixelBufferRetain(pb);
        float *p = gw->tex_yuv[slot];
        memset(p, 0, sizeof gw->tex_yuv[slot]);
        for (int i = 0; i < 8; i++) p[i] = (float)pr[6 + i];
        /* R16 samples of P010 hold the code in their top 10 bits */
        p[0] = (float)(f16 ? 65535.0 / 64.0 : 255.0);
        p[8] = (float)pr[14];
        p[9] = (float)pr[15];
        p[10] = (pr[15] == 16.0 || pr[15] == 18.0) ? 1.0f : 0.0f;
        p[11] = 1.0f;                                           /* interleaved Cb/Cr */
        for (int r = 0; r < 3; r++)
            for (int k = 0; k < 3; k++) p[12 + r * 4 + k] = (float)pr[16 + r * 3 + k];
        static int flushes;
        if ((++flushes & 63) == 0) CVMetalTextureCacheFlush(cache, 0);
    }
    return w_bool(1);
}

/* Tests: w_gfx_capture_next(window) makes the next present_layers frame wait
 * for the GPU and keep a copy; w_gfx_capture_take(window) returns it as
 * [width, height, ByteArray] in the layer's pixel order (RGBA, or BGRA for a
 * GFX_BGRA window), or nil when nothing was captured. */
WValue w_gfx_capture_next(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.capture_next");
    gw->capture_next = true;
    return W_NIL;
}

WValue w_gfx_capture_take(WValue window_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.capture_take");
    if (!gw->capture_buf) return W_NIL;
    id<MTLBuffer> b = (id<MTLBuffer>)gw->capture_buf;
    size_t n = (size_t)gw->capture_w * (size_t)gw->capture_h * 4;
    WValue bytes = w_bytes_from_data((const uint8_t *)[b contents], (int64_t)n);
    [b release];
    gw->capture_buf = NULL;
    WValue out = w_array_new_empty();
    out = w_array_push(out, w_int(gw->capture_w));
    out = w_array_push(out, w_int(gw->capture_h));
    out = w_array_push(out, bytes);
    return out;
}

/* w_gfx_present_layers(window, bg_u32, cmds_f64, n_cmds, wait_flag):
 * Each command is 16 doubles in `cmds_f64`:
 *   [0] kind: 0 = premul tex, 1 = fill/blend color, 2 = under-paper blend,
 *             3 = mask-blend tex, 4 = straight-alpha tex
 *   [1] tex_id (for kind 0,3,4) or color_u32 0xAARRGGBB (for kind 1,2)
 *   [2..5]  dx, dy, dw, dh (drawable pixels, top-left origin)
 *   [6..9]  sx, sy, sw, sh (source texture pixels; <=0 means full texture)
 *   [10..13] clip_x, clip_y, clip_w, clip_h (scissor; <=0 means full drawable)
 *   [14] param0: alpha (0..1) for kind 0,4; paper_u32 for kind 2; color_u32 for kind 3
 *   [15] param1: alpha (0..1) for kind 3 (or reserved) */
WValue w_gfx_present_layers(WValue window_v, WValue bg_v, WValue cmds_v, WValue n_cmds_v, WValue wait_v) {
    WGfxWindow *gw = gfx_window_arg(window_v, "gfx.present_layers");
    if (gw->closed) return w_bool(0);
    gfx_require_main_thread("gfx.present_layers");

    int64_t n_cmds = n_cmds_v == W_NIL ? 0 : gfx_int(n_cmds_v);
    const double *raw = NULL;
    if (n_cmds > 0) {
        if (!w_is_array(cmds_v)) w_raise(w_string("gfx.present_layers: cmds must be an f64[] or Array"));
        WArray *a = w_as_array(cmds_v);
        int64_t avail = (int64_t)a->size / 16;
        if (n_cmds > avail) n_cmds = avail;
        if (a->ebits == -64) raw = (const double *)a->slots + a->start;
    }

    bool wait_done = (wait_v != W_NIL && wait_v != W_FALSE && !(w_is_int(wait_v) && w_as_int(wait_v) == 0));

    @autoreleasepool {
        gfx_ensure_compositor(gw);
        CAMetalLayer *layer = (CAMetalLayer *)gw->layer;
        if (!wait_done) {
            dispatch_semaphore_wait(gw->frame_sem, dispatch_time(DISPATCH_TIME_NOW, 32 * NSEC_PER_MSEC));
        }
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            if (!wait_done) dispatch_semaphore_signal(gw->frame_sem);
            return w_bool(0);
        }

        NSUInteger dw = drawable.texture.width;
        NSUInteger dh = drawable.texture.height;
        if (dw == 0 || dh == 0) {
            if (!wait_done) dispatch_semaphore_signal(gw->frame_sem);
            return w_bool(0);
        }
        float inv_dw = 2.0f / (float)dw;
        float inv_dh = 2.0f / (float)dh;

        uint64_t seq = ++gw->next_cb_seq;
        int ring = (int)(seq % 3);

        size_t need_bytes = (size_t)(n_cmds > 0 ? n_cmds : 1) * sizeof(GfxQuad);
        if (need_bytes > gw->quad_cap[ring]) {
            size_t cap = gw->quad_cap[ring] ? gw->quad_cap[ring] * 2 : 16384;
            while (cap < need_bytes) cap *= 2;
            if (gw->quad_buf[ring]) [(id<MTLBuffer>)gw->quad_buf[ring] release];
            id<MTLBuffer> nb = [(id<MTLDevice>)gw->device newBufferWithLength:cap options:MTLResourceStorageModeShared];
            if (!nb) {
                if (!wait_done) dispatch_semaphore_signal(gw->frame_sem);
                w_raise(w_string("gfx.present_layers: quad buffer allocation failed"));
            }
            gw->quad_buf[ring] = (void *)nb;
            gw->quad_cap[ring] = cap;
        }
        GfxQuad *quads = (GfxQuad *)[(id<MTLBuffer>)gw->quad_buf[ring] contents];

        typedef struct { int tex_slot; MTLScissorRect sc; } GfxCmdMeta;
        GfxCmdMeta stack_meta[256];
        GfxCmdMeta *meta = n_cmds <= 256 ? stack_meta : (GfxCmdMeta *)malloc((size_t)n_cmds * sizeof(GfxCmdMeta));
        int out_n = 0;

        for (int64_t i = 0; i < n_cmds; i++) {
            double c[16];
            if (raw) {
                memcpy(c, raw + i * 16, 16 * sizeof(double));
            } else {
                for (int j = 0; j < 16; j++) c[j] = gfx_num(w_array_get(cmds_v, w_int(i * 16 + j)), "cmd");
            }
            int kind = (int)c[0];
            double qx = c[2], qy = c[3], qw = c[4], qh = c[5];
            if (qw <= 0.0 || qh <= 0.0) continue;

            int sc_x = 0, sc_y = 0, sc_w = (int)dw, sc_h = (int)dh;
            if (c[12] > 0.0 && c[13] > 0.0) {
                int cx0 = (int)llround(c[10]), cy0 = (int)llround(c[11]);
                int cx1 = (int)llround(c[10] + c[12]), cy1 = (int)llround(c[11] + c[13]);
                if (cx0 < 0) cx0 = 0;
                if (cy0 < 0) cy0 = 0;
                if (cx1 > (int)dw) cx1 = (int)dw;
                if (cy1 > (int)dh) cy1 = (int)dh;
                if (cx1 <= cx0 || cy1 <= cy0) continue;
                sc_x = cx0; sc_y = cy0; sc_w = cx1 - cx0; sc_h = cy1 - cy0;
            }
            if (qx + qw <= sc_x || qx >= sc_x + sc_w || qy + qh <= sc_y || qy >= sc_y + sc_h) continue;

            GfxQuad q;
            q.dst[0] = (float)qx * inv_dw - 1.0f;
            q.dst[1] = 1.0f - (float)qy * inv_dh;
            q.dst[2] = (float)(qx + qw) * inv_dw - 1.0f;
            q.dst[3] = 1.0f - (float)(qy + qh) * inv_dh;

            int tex_slot = -1;
            if (kind == 0 || kind == 3 || kind == 4) {
                int slot = (int)llround(c[1]) - 1;
                if (slot < 0 || slot >= GFX_MAX_TEX || !gw->tex[slot]) continue;
                id<MTLTexture> t = (id<MTLTexture>)gw->tex[slot];
                gw->tex_used_seq[slot] = seq;
                tex_slot = slot;
                double tw = (double)t.width, th = (double)t.height;
                double sx = c[6], sy = c[7], sw = c[8], sh = c[9];
                if (sw <= 0.0 || sh <= 0.0) { sx = 0.0; sy = 0.0; sw = tw; sh = th; }
                q.uv[0] = (float)(sx / tw);
                q.uv[1] = (float)(sy / th);
                q.uv[2] = (float)((sx + sw) / tw);
                q.uv[3] = (float)((sy + sh) / th);
                if (kind == 3) {
                    uint32_t u = (uint32_t)(int64_t)c[14];
                    float a = (float)(c[15] > 0.0 ? c[15] : 1.0);
                    q.col[0] = ((u >> 16) & 0xFF) / 255.0f;
                    q.col[1] = ((u >> 8)  & 0xFF) / 255.0f;
                    q.col[2] = (u & 0xFF)         / 255.0f;
                    q.col[3] = a;
                    if (gw->out_space) gfx_rgb_to_p3(q.col);
                    q.aux[0] = q.aux[1] = q.aux[2] = 0.0f;
                    q.aux[3] = 4.0f;
                } else {
                    float a = (float)(c[14] > 0.0 ? c[14] : 1.0);
                    q.col[0] = q.col[1] = q.col[2] = 1.0f;
                    q.col[3] = a;
                    q.aux[0] = q.aux[1] = q.aux[2] = 0.0f;
                    q.aux[3] = gw->tex_planar[slot] ? 5.0f : ((kind == 4) ? 1.0f : 0.0f);
                    /* an sRGB texture in a P3 window: the shader converts it */
                    if (gw->out_space && !gw->tex_planar[slot] && !gw->tex_space[slot]) q.aux[0] = 1.0f;
                }
            } else {
                q.uv[0] = 0.0f; q.uv[1] = 0.0f; q.uv[2] = 1.0f; q.uv[3] = 1.0f;
                uint32_t u = (uint32_t)(int64_t)c[1];
                uint32_t ua = (u >> 24) & 0xFF;
                q.col[0] = ((u >> 16) & 0xFF) / 255.0f;
                q.col[1] = ((u >> 8)  & 0xFF) / 255.0f;
                q.col[2] = (u & 0xFF)         / 255.0f;
                q.col[3] = ua / 255.0f;
                if (gw->out_space) gfx_rgb_to_p3(q.col);
                if (kind == 2 && gw->pso_tile) {
                    uint32_t pu = (uint32_t)(int64_t)c[14];
                    q.aux[0] = ((pu >> 16) & 0xFF) / 255.0f;
                    q.aux[1] = ((pu >> 8)  & 0xFF) / 255.0f;
                    q.aux[2] = (pu & 0xFF)         / 255.0f;
                    if (gw->out_space) gfx_rgb_to_p3(q.aux);
                    q.aux[3] = 3.0f;
                } else {
                    q.aux[0] = q.aux[1] = q.aux[2] = 0.0f;
                    q.aux[3] = 2.0f;
                }
            }

            quads[out_n] = q;
            meta[out_n].tex_slot = tex_slot;
            meta[out_n].sc = (MTLScissorRect){ (NSUInteger)sc_x, (NSUInteger)sc_y, (NSUInteger)sc_w, (NSUInteger)sc_h };
            out_n++;
        }

        uint32_t bg = (uint32_t)gfx_int(bg_v);
        double bgr = ((bg >> 16) & 0xFF) / 255.0;
        double bgg = ((bg >> 8)  & 0xFF) / 255.0;
        double bgb = (bg & 0xFF)         / 255.0;
        if (gw->out_space) {
            float bc[3] = {(float)bgr, (float)bgg, (float)bgb};
            gfx_rgb_to_p3(bc);
            bgr = bc[0]; bgg = bc[1]; bgb = bc[2];
        }

        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = drawable.texture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(bgr, bgg, bgb, 1.0);

        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)gw->queue;
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:(id<MTLRenderPipelineState>)(gw->pso_tile ? gw->pso_tile : gw->pso_alpha)];
        [enc setVertexBuffer:(id<MTLBuffer>)gw->quad_buf[ring] offset:0 atIndex:0];
        [enc setFragmentSamplerState:(id<MTLSamplerState>)gw->sampler atIndex:0];

        id<MTLTexture> cur_tex = (id<MTLTexture>)gw->dummy_tex;
        [enc setFragmentTexture:cur_tex atIndex:0];
        [enc setFragmentTexture:cur_tex atIndex:1];
        [enc setFragmentTexture:cur_tex atIndex:2];
        [enc setFragmentSamplerState:(id<MTLSamplerState>)gw->sampler_lin atIndex:1];
        {
            float zero_yuv[24] = {0};
            [enc setFragmentBytes:zero_yuv length:sizeof zero_yuv atIndex:0];
        }
        MTLScissorRect cur_sc = { 0, 0, dw, dh };
        [enc setScissorRect:cur_sc];

        int i = 0;
        while (i < out_n) {
            int ts = meta[i].tex_slot;
            id<MTLTexture> want_tex = ts >= 0 ? (id<MTLTexture>)gw->tex[ts] : cur_tex;
            MTLScissorRect sc = meta[i].sc;
            int j = i + 1;
            while (j < out_n &&
                   sc.x == meta[j].sc.x && sc.y == meta[j].sc.y &&
                   sc.width == meta[j].sc.width && sc.height == meta[j].sc.height &&
                   (meta[j].tex_slot < 0 || meta[j].tex_slot == ts || ts < 0)) {
                if (ts < 0 && meta[j].tex_slot >= 0) {
                    ts = meta[j].tex_slot;
                    want_tex = (id<MTLTexture>)gw->tex[ts];
                }
                j++;
            }
            if (want_tex != cur_tex) {
                cur_tex = want_tex;
                [enc setFragmentTexture:cur_tex atIndex:0];
                if (ts >= 0 && gw->tex_planar[ts]) {
                    [enc setFragmentTexture:(id<MTLTexture>)gw->tex_cb[ts] atIndex:1];
                    [enc setFragmentTexture:(id<MTLTexture>)gw->tex_cr[ts] atIndex:2];
                    if (gw->out_space) {
                        /* P3 window: retarget the conversion to P3 primaries (untagged
                         * video as BT.709 with the sRGB-ish curve it was drawn with) */
                        float py[24];
                        memcpy(py, gw->tex_yuv[ts], sizeof py);
                        if (py[9] == 0.0f) {
                            py[9] = 13.0f;
                            for (int r = 0; r < 3; r++)
                                for (int k = 0; k < 3; k++) py[12 + r * 4 + k] = (r == k) ? 1.0f : 0.0f;
                        }
                        float m[9];
                        for (int r = 0; r < 3; r++)
                            for (int k = 0; k < 3; k++)
                                m[r * 3 + k] = (float)(GFX_SRGB_P3[r * 3] * py[12 + k] + GFX_SRGB_P3[r * 3 + 1] * py[16 + k] + GFX_SRGB_P3[r * 3 + 2] * py[20 + k]);
                        for (int r = 0; r < 3; r++)
                            for (int k = 0; k < 3; k++) py[12 + r * 4 + k] = m[r * 3 + k];
                        [enc setFragmentBytes:py length:sizeof py atIndex:0];
                    } else {
                        [enc setFragmentBytes:gw->tex_yuv[ts] length:sizeof gw->tex_yuv[ts] atIndex:0];
                    }
                }
            }
            if (sc.x != cur_sc.x || sc.y != cur_sc.y || sc.width != cur_sc.width || sc.height != cur_sc.height) {
                cur_sc = sc;
                [enc setScissorRect:cur_sc];
            }
            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                    vertexStart:0
                    vertexCount:4
                  instanceCount:(NSUInteger)(j - i)
                   baseInstance:(NSUInteger)i];
            i = j;
        }

        [enc endEncoding];
        bool capturing = gw->capture_next;
        if (capturing) {
            /* tests: read the composited frame back (the layer is not framebufferOnly) */
            gw->capture_next = false;
            if (gw->capture_buf) { [(id<MTLBuffer>)gw->capture_buf release]; gw->capture_buf = NULL; }
            id<MTLBuffer> cbuf = [(id<MTLDevice>)gw->device newBufferWithLength:dw * dh * 4 options:MTLResourceStorageModeShared];
            if (cbuf) {
                id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
                [bl copyFromTexture:drawable.texture sourceSlice:0 sourceLevel:0
                       sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(dw, dh, 1)
                           toBuffer:cbuf destinationOffset:0 destinationBytesPerRow:dw * 4
                destinationBytesPerImage:dw * dh * 4];
                [bl endEncoding];
                gw->capture_buf = (void *)cbuf;
                gw->capture_w = (int32_t)dw;
                gw->capture_h = (int32_t)dh;
            }
        }
        [cb presentDrawable:drawable];

        WGfxWindow *gw_ptr = gw;
        dispatch_semaphore_t sem = gw->frame_sem;
        bool sig_sem = !wait_done;
        [cb addCompletedHandler:^(id<MTLCommandBuffer> _cb) {
            (void)_cb;
            uint64_t prev = __atomic_load_n(&gw_ptr->done_cb_seq, __ATOMIC_RELAXED);
            while (seq > prev && !__atomic_compare_exchange_n(&gw_ptr->done_cb_seq, &prev, seq, true, __ATOMIC_RELEASE, __ATOMIC_RELAXED)) {}
            if (sig_sem) dispatch_semaphore_signal(sem);
        }];
        [cb commit];
        if (wait_done || capturing) [cb waitUntilCompleted];
        if (meta != stack_meta) free(meta);
    }
    return w_bool(1);
}

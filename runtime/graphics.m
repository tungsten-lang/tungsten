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
#include <stdio.h>
#include <string.h>
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

enum { GFX_HIDPI = 1, GFX_HIDDEN = 2, GFX_BGRA = 4, GFX_KEEP_OPEN = 8 };

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

@interface TungstenView : NSView
@property (nonatomic, assign) GfxInput *input;
@end

@implementation TungstenView
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
    GfxInput input;
} WGfxWindow;

static WGfxWindow *as_gfx_window(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WGfxWindow *w = (WGfxWindow *)w_as_ptr(v);
    if (w->type != W_TYPE_GFX_WINDOW) return NULL;
    return w;
}

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
static WGfxWindow *gfx_open_window = NULL;       /* the window they go to: the first opened that is still open */

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
        layer.drawableSize = CGSizeMake(captured->width, captured->height);
        layer.opaque = YES;

        TungstenView *view = [[TungstenView alloc] initWithFrame:frame];
        view.input = &captured->input;
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
    gw->input.should_close = true;
    NSWindow *win = (NSWindow *)gw->window;
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
    if (!self.input) return;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_MENU;
    e.id = (int64_t)[sender tag];
    gfx_push(self.input, &e);
}
- (void)quit:(id)sender {
    (void)sender;
    if (!self.input) return;
    self.input->should_close = true;
    GfxEvent e; memset(&e, 0, sizeof e);
    e.kind = GFX_EV_CLOSE;
    e.id = 1;
    gfx_push(self.input, &e);
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
 * on the open target: the first window opened that is still open. Paths that arrive before any window (at launch, inside
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
 *                            open-documents event goes (a GFX_EV_OPEN on the open target) */
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
                default:                           [view mouseMoved:ev]; break;
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

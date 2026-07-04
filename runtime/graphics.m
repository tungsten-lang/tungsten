/* runtime/graphics.m — Obj-C windowing + present bridge for Tungsten.
 *
 * The Metal bridge in runtime/metal.m is compute-only: it dispatches
 * `@gpu fn` kernels into buffers, with no way to put pixels on screen.
 * This file adds the missing windowing half — a real Cocoa NSWindow
 * backed by a CAMetalLayer — so a Tungsten program can:
 *
 *   1. open a window               (w_gfx_window_new)
 *   2. pump OS events / input      (w_gfx_poll, w_gfx_key_down, …)
 *   3. blit an RGBA buffer to it   (w_gfx_present)
 *
 * The rendering model is deliberately minimal and reuses the existing
 * compute path: a `@gpu` kernel renders one pixel per thread into a
 * shared MTLBuffer (RGBA8, one uint per pixel), and w_gfx_present
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
 * Input model: the content view subclass records key state into a
 * 256-entry pressed[] table keyed by hardware keyCode (so WASD tracks
 * physical key positions regardless of layout) and accumulates relative
 * mouse motion. w_gfx_mouse_dx/dy return the delta since the last read
 * and reset it, which is exactly what a frame's mouse-look wants. */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#include "runtime.h"
#include "wvalue.h"

/* ---- Input state shared between the view and the C bridge ---- */

typedef struct GfxInput {
    bool   pressed[256];   /* keyed by NSEvent.keyCode */
    double mouse_dx;       /* accumulated since last read, then zeroed */
    double mouse_dy;
    bool   should_close;   /* set on window close */
    bool   mouse_captured;
} GfxInput;

/* ---- The content view: first responder for key + mouse events ---- */

@interface TungstenView : NSView
@property (nonatomic, assign) GfxInput *input;
@end

@implementation TungstenView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)keyDown:(NSEvent *)ev {
    /* Swallow the event (no super call) so the system doesn't beep on
     * keys we handle ourselves. Repeats keep pressed[] true. */
    NSUInteger code = [ev keyCode];
    if (self.input && code < 256) self.input->pressed[code] = true;
}
- (void)keyUp:(NSEvent *)ev {
    NSUInteger code = [ev keyCode];
    if (self.input && code < 256) self.input->pressed[code] = false;
}
- (void)mouseMoved:(NSEvent *)ev {
    if (self.input) { self.input->mouse_dx += [ev deltaX]; self.input->mouse_dy += [ev deltaY]; }
}
/* Track motion while a button is held too, so drag-look works. */
- (void)mouseDragged:(NSEvent *)ev        { [self mouseMoved:ev]; }
- (void)rightMouseDragged:(NSEvent *)ev   { [self mouseMoved:ev]; }
- (void)otherMouseDragged:(NSEvent *)ev   { [self mouseMoved:ev]; }
@end

/* ---- Window delegate: catch the red close button ---- */

@interface TungstenWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) GfxInput *input;
@end

@implementation TungstenWindowDelegate
- (void)windowWillClose:(NSNotification *)note {
    if (self.input) self.input->should_close = true;
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
    GfxInput input;
} WGfxWindow;

static WGfxWindow *as_gfx_window(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WGfxWindow *w = (WGfxWindow *)w_as_ptr(v);
    if (w->type != W_TYPE_GFX_WINDOW) return NULL;
    return w;
}

/* Pull the id<MTLDevice> out of a WMetalDevice WValue (defined in
 * runtime.h, boxed by runtime/metal.m). */
static id<MTLDevice> gfx_device_handle(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return nil;
    WMetalDevice *d = (WMetalDevice *)w_as_ptr(v);
    if (d->type != W_TYPE_METAL_DEVICE) return nil;
    return (id<MTLDevice>)d->handle;
}

static NSString *gfx_string(WValue v) {
    if (!w_is_string(v)) return @"Tungsten";
    char buf[6];
    const char *s = NULL; size_t len = 0;
    w_str_data(v, buf, &s, &len);
    if (!s) return @"Tungsten";
    return [[[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding] autorelease];
}

/* Ensure NSApp exists and is a regular, activatable GUI app even though
 * we were launched as a plain CLI binary (no .app bundle). Idempotent. */
static void gfx_ensure_app(void) {
    static bool started = false;
    if (started) return;
    started = true;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];
}

/* ---- w_gfx_window_new(device, title, width, height) ---- */

WValue w_gfx_window_new(WValue device_v, WValue title_v, WValue width_v, WValue height_v) {
    id<MTLDevice> dev = gfx_device_handle(device_v);
    if (!dev) w_raise(w_string("gfx.window_new: first arg must be a Metal device"));
    int w = (int)w_to_i64(width_v);
    int h = (int)w_to_i64(height_v);
    if (w <= 0 || h <= 0) w_raise(w_string("gfx.window_new: width/height must be positive"));

    gfx_ensure_app();

    WGfxWindow *gw = (WGfxWindow *)calloc(1, sizeof(WGfxWindow));
    gw->type = W_TYPE_GFX_WINDOW;
    gw->width = w;
    gw->height = h;
    gw->device = (void *)[dev retain];

    __block WGfxWindow *captured = gw;
    /* All AppKit object creation must happen on the main thread. The
     * Tungsten program's main runs on the process main thread, so a
     * direct call is fine; dispatch_sync guards the rare embedded case. */
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

        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = (id<MTLDevice>)captured->device;
        layer.pixelFormat = MTLPixelFormatRGBA8Unorm;
        layer.framebufferOnly = NO;     /* allow blit-into-drawable */
        layer.drawableSize = CGSizeMake(captured->width, captured->height);
        layer.opaque = YES;

        TungstenView *view = [[TungstenView alloc] initWithFrame:frame];
        view.input = &captured->input;
        view.wantsLayer = YES;
        view.layer = layer;

        TungstenWindowDelegate *del = [[TungstenWindowDelegate alloc] init];
        del.input = &captured->input;
        [win setDelegate:del];

        [win setContentView:view];
        [win setAcceptsMouseMovedEvents:YES];
        [win makeFirstResponder:view];
        [win makeKeyAndOrderFront:nil];

        captured->window = (void *)win;
        captured->layer = (void *)[layer retain];
        captured->view = (void *)view;
        captured->delegate = (void *)del;
    };
    if ([NSThread isMainThread]) build();
    else dispatch_sync(dispatch_get_main_queue(), build);

    gw->queue = (void *)[[dev newCommandQueue] retain];

    return w_box_ptr(gw, W_SUBTAG_GENERIC);
}

/* ---- w_gfx_poll(window) — drain the OS event queue ---- */

WValue w_gfx_poll(WValue window_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.poll: not a window"));
    @autoreleasepool {
        NSEvent *ev;
        while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:[NSDate distantPast]
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES])) {
            [NSApp sendEvent:ev];
        }
    }
    return W_NIL;
}

/* ---- input queries ---- */

WValue w_gfx_key_down(WValue window_v, WValue keycode_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.key_down: not a window"));
    int64_t code = w_to_i64(keycode_v);
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
    bool on = w_to_i64(on_v) != 0;
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

/* ---- w_gfx_present(window, buffer, width, height) ----
 * Blit an RGBA8 MTLBuffer (one uint per pixel, row-major, width*height
 * pixels) into the next drawable and present it. */
WValue w_gfx_present(WValue window_v, WValue buffer_v, WValue width_v, WValue height_v) {
    WGfxWindow *gw = as_gfx_window(window_v);
    if (!gw) w_raise(w_string("gfx.present: not a window"));

    if (!w_is_obj(buffer_v) || w_subtag(buffer_v) != W_SUBTAG_GENERIC)
        w_raise(w_string("gfx.present: second arg must be a Metal buffer"));
    WMetalBuffer *b = (WMetalBuffer *)w_as_ptr(buffer_v);
    if (b->type != W_TYPE_METAL_BUFFER)
        w_raise(w_string("gfx.present: second arg must be a Metal buffer"));

    int w = (int)w_to_i64(width_v);
    int h = (int)w_to_i64(height_v);
    if (w <= 0 || h <= 0) return W_NIL;
    int64_t need = (int64_t)w * (int64_t)h * 4;
    if (b->size < need) w_raise(w_string("gfx.present: buffer smaller than width*height*4"));

    @autoreleasepool {
        CAMetalLayer *layer = (CAMetalLayer *)gw->layer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) return W_NIL;   /* dropped frame — try again next tick */

        id<MTLCommandQueue> queue = (id<MTLCommandQueue>)gw->queue;
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit copyFromBuffer:(id<MTLBuffer>)b->handle
                sourceOffset:0
           sourceBytesPerRow:(NSUInteger)(w * 4)
         sourceBytesPerImage:(NSUInteger)need
                  sourceSize:MTLSizeMake(w, h, 1)
                   toTexture:drawable.texture
            destinationSlice:0
            destinationLevel:0
           destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
        [cb presentDrawable:drawable];
        [cb commit];
    }
    return W_NIL;
}

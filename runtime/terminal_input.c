#include "runtime.h"

#include <poll.h>
#include <stdatomic.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

/* ---- Raw-terminal primitives (for the REPL line editor) ---- */
static struct termios g_saved_termios;
static int g_raw_active = 0;

/* Put stdin into raw mode (no echo, no line-buffering, keypresses delivered one
 * at a time, Ctrl-C/Z/etc. delivered as bytes not signals). No-op on a non-tty
 * (piped input keeps cooked line reads). */
WValue w_term_raw_enable(void) {
    if (!isatty(0)) return W_NIL;
    if (g_raw_active) return W_NIL;
    if (tcgetattr(0, &g_saved_termios) != 0) return W_NIL;
    struct termios raw = g_saved_termios;
    raw.c_lflag &= ~((tcflag_t)(ECHO | ICANON | ISIG | IEXTEN));
    raw.c_iflag &= ~((tcflag_t)(IXON | ICRNL | BRKINT | INPCK | ISTRIP));
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    /* TCSANOW (not TCSAFLUSH): apply immediately WITHOUT discarding pending
     * input, so type-ahead entered before the prompt is preserved. */
    if (tcsetattr(0, TCSANOW, &raw) != 0) return W_NIL;
    g_raw_active = 1;
    return W_NIL;
}

/* Restore the terminal to the mode saved by w_term_raw_enable. */
WValue w_term_raw_disable(void) {
    if (g_raw_active) {
        tcsetattr(0, TCSADRAIN, &g_saved_termios);
        g_raw_active = 0;
    }
    return W_NIL;
}

/* Read one byte/keypress from stdin. Returns the byte value (0..255), or -1 on
 * EOF. In raw mode this returns per keypress; escape sequences (arrow keys)
 * arrive as the bytes 27, '[', 'A'/'B'/'C'/'D' across successive calls. */
WValue w_read_key(void) {
    fflush(stdout);   /* flush the prompt / echoed chars before blocking */
    unsigned char c;
    ssize_t n = read(0, &c, 1);
    if (n <= 0) return w_int(-1);
    return w_int((int64_t)c);
}

/* True if stdin is a terminal (use the raw editor) vs a pipe/file (cooked). */
WValue w_isatty_stdin(void) {
    return w_bool(isatty(0) ? 1 : 0);
}

WValue w_isatty_stdout(void) {
    return w_bool(isatty(1) ? 1 : 0);
}

/* Terminal width in columns (for line redraw); 80 if unavailable. */
WValue w_term_cols(void) {
    struct winsize ws;
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        return w_int((int64_t)ws.ws_col);
    }
    return w_int(80);
}

/* ---- HID input multiplexing (Stream Deck + dials) ----------------------------
 * A background reader thread (runtime/hid_bridge.m on darwin) decodes USB-HID
 * reports into POD HIDEvent structs and pushes them into this lock-free SPSC
 * ring; the REPL main thread drains the ring in w_input_poll alongside stdin.
 * One producer (the HID callback thread) + one consumer (the main thread) makes
 * acquire/release sufficient — no mutex. The producer must never allocate
 * WValues; only the consumer boxes. A self-pipe lets the producer wake the
 * consumer's poll() so dial ticks have sub-millisecond latency. Cross-platform:
 * with no device the pipe stays -1 and w_input_poll just polls stdin. */
#define HID_RING_CAP 256u                  /* power of two */
static HIDEvent         g_hid_ring[HID_RING_CAP];
static _Atomic uint32_t g_hid_head = 0;    /* consumer (main thread) */
static _Atomic uint32_t g_hid_tail = 0;    /* producer (HID thread)  */
int                     g_hid_pipe[2] = { -1, -1 };  /* see runtime.h */

/* Producer side — called from the HID callback thread. POD only, no allocation.
 * On a full ring the newest event is dropped (one lost tick, harmless). */
void w_hid_ring_push(HIDEvent ev) {
    uint32_t tail = atomic_load_explicit(&g_hid_tail, memory_order_relaxed);
    uint32_t next = (tail + 1u) & (HID_RING_CAP - 1u);
    if (next == atomic_load_explicit(&g_hid_head, memory_order_acquire)) {
        return;                            /* full → drop */
    }
    g_hid_ring[tail] = ev;
    atomic_store_explicit(&g_hid_tail, next, memory_order_release);
    if (g_hid_pipe[1] >= 0) {              /* best-effort wakeup (pipe is O_NONBLOCK) */
        unsigned char b = 1;
        ssize_t r = write(g_hid_pipe[1], &b, 1);
        (void)r;
    }
}

/* Consumer side — main thread only. Returns 1 and fills *out, or 0 if empty. */
static int hid_ring_pop(HIDEvent *out) {
    uint32_t head = atomic_load_explicit(&g_hid_head, memory_order_relaxed);
    if (head == atomic_load_explicit(&g_hid_tail, memory_order_acquire)) {
        return 0;                          /* empty */
    }
    *out = g_hid_ring[head];
    atomic_store_explicit(&g_hid_head, (head + 1u) & (HID_RING_CAP - 1u),
                          memory_order_release);
    return 1;
}

/* Pack a decoded HID event into the tagged-int protocol below. kind >= 1 so the
 * result is always >= 0x10000, distinguishing it from keyboard bytes. */
static int64_t hid_encode(HIDEvent ev) {
    return ((int64_t)ev.kind << 16) | ((int64_t)ev.index << 8)
           | (int64_t)((uint8_t)ev.value);   /* low8: ROTATE two's-complement int8; PRESS/KEY 0/1 */
}

/* Unified REPL input for the scrub loop. Returns the next event as a tagged int:
 *   -2          stdin EOF (Ctrl-D)
 *   -1          timeout / no event
 *   0..255      keyboard byte (same convention as w_read_key)
 *   >= 0x10000  device: (kind<<16) | (index<<8) | low8
 *                 kind 1 ROTATE: low8 = signed int8 tick delta (two's complement)
 *                 kind 2 PRESS : low8 = 0/1 (dial-button edge)
 *                 kind 3 KEY   : low8 = 0/1 (LCD-key edge)
 * Drains a queued dial event first (zero-latency path); otherwise blocks in ONE
 * poll() over both stdin and the HID self-pipe, up to timeout_ms (negative =
 * block forever). poll() before read() means VMIN=1 raw mode never blocks us. */
WValue w_input_poll(int64_t timeout_ms) {
    fflush(stdout);

    HIDEvent ev;
    if (hid_ring_pop(&ev)) return w_int(hid_encode(ev));

    struct pollfd pfd[2];
    pfd[0].fd = 0;             pfd[0].events = POLLIN; pfd[0].revents = 0;
    pfd[1].fd = g_hid_pipe[0]; pfd[1].events = POLLIN; pfd[1].revents = 0;
    nfds_t n = (g_hid_pipe[0] >= 0) ? 2 : 1;   /* keyboard-only when no device */

    int r = poll(pfd, n, (int)timeout_ms);
    if (r <= 0) return w_int(-1);              /* timeout or EINTR → nothing */

    if (n == 2 && (pfd[1].revents & POLLIN)) { /* drain wake bytes (level-trigger) */
        char drain[64];
        while (read(g_hid_pipe[0], drain, sizeof drain) > 0) { }
    }
    if (hid_ring_pop(&ev)) return w_int(hid_encode(ev));

    if (pfd[0].revents & POLLIN) {             /* fd 0 readable → read won't block */
        unsigned char c;
        ssize_t k = read(0, &c, 1);
        if (k <= 0) return w_int(-2);          /* EOF (Ctrl-D) */
        return w_int((int64_t)c);
    }
    return w_int(-1);
}

/* WEAK HID stubs: the real producer lives in hid_bridge.m, linked only when
 * the IR references bridge symbols; keyboard-only builds keep the pipe at
 * {-1,-1}, so w_input_poll polls stdin alone. */
__attribute__((weak)) WValue w_hid_streamdeck_open(void)        { return W_NIL; }
__attribute__((weak)) WValue w_hid_streamdeck_close(WValue dev) { (void)dev; return W_NIL; }
__attribute__((weak)) WValue w_hid_device_present(WValue dev)   { (void)dev; return w_bool(0); }


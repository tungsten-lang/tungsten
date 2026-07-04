/*
 * event_kqueue.c — macOS kqueue event loop backend
 *
 * Provides non-blocking I/O multiplexing for goroutine parking.
 * Each registered fd uses EV_ONESHOT so the goroutine must re-register
 * after being woken (natural for retry-on-EAGAIN patterns).
 */

#ifdef __APPLE__

#include "event_loop.h"
#include "runtime.h"
#include <sys/event.h>
#include <sys/time.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

struct WEventLoop {
    int kq;
};

WEventLoop *w_event_init(void) {
    int kq = kqueue();
    if (kq < 0) return NULL;

    WEventLoop *el = malloc(sizeof(WEventLoop));
    el->kq = kq;
    return el;
}

void w_event_destroy(WEventLoop *el) {
    if (!el) return;
    close(el->kq);
    free(el);
}

void w_event_register(WEventLoop *el, int fd, int events, WGoroutine *g) {
    struct kevent changes[2];
    int nchanges = 0;

    if (events & W_EVENT_READ) {
        EV_SET(&changes[nchanges], fd, EVFILT_READ,
               EV_ADD | EV_ONESHOT, 0, 0, g);
        nchanges++;
    }
    if (events & W_EVENT_WRITE) {
        EV_SET(&changes[nchanges], fd, EVFILT_WRITE,
               EV_ADD | EV_ONESHOT, 0, 0, g);
        nchanges++;
    }

    kevent(el->kq, changes, nchanges, NULL, 0, NULL);
}

void w_event_unregister(WEventLoop *el, int fd) {
    struct kevent changes[2];
    EV_SET(&changes[0], fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    EV_SET(&changes[1], fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
    /* Ignore errors — fd may not be registered for both filters */
    kevent(el->kq, changes, 2, NULL, 0, NULL);
}

int w_event_poll(WEventLoop *el, int timeout_ms, WGoroutine **out, int max_out) {
    struct kevent events[64];
    int nevents = max_out < 64 ? max_out : 64;

    struct timespec ts;
    struct timespec *tsp = NULL;
    if (timeout_ms >= 0) {
        ts.tv_sec = timeout_ms / 1000;
        ts.tv_nsec = (timeout_ms % 1000) * 1000000L;
        tsp = &ts;
    }

    int n = kevent(el->kq, NULL, 0, events, nevents, tsp);
    if (n < 0) {
        if (errno == EINTR) return 0;
        return -1;
    }

    /* Deduplicate: a goroutine may appear for both READ and WRITE */
    int count = 0;
    for (int i = 0; i < n && count < max_out; i++) {
        WGoroutine *g = (WGoroutine *)events[i].udata;
        if (!g) continue;

        /* Check if already in output list */
        int dup = 0;
        for (int j = 0; j < count; j++) {
            if (out[j] == g) { dup = 1; break; }
        }
        if (!dup) {
            out[count++] = g;
        }
    }
    return count;
}

/* ---- Completion API stubs (io_uring only — never called on kqueue) ---- */

/* Phase 1 */
int w_event_submit_recv(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_send(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_accept(WEventLoop *el, int fd, struct sockaddr *addr, socklen_t *addrlen, WGoroutine *g) {
    (void)el; (void)fd; (void)addr; (void)addrlen; (void)g; return -1;
}

/* Phase 4 */
int w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g) {
    (void)el; (void)fd; (void)g; return -1;
}
int w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
void w_event_return_buf(WEventLoop *el, int buf_id) {
    (void)el; (void)buf_id;
}

/* Phase 5 */
int w_event_send_buf_alloc(WEventLoop *el) { (void)el; return -1; }
void w_event_send_buf_free(WEventLoop *el, int buf_id) { (void)el; (void)buf_id; }
void *w_event_send_buf_ptr(WEventLoop *el, int buf_id) { (void)el; (void)buf_id; return NULL; }
int w_event_submit_send_fixed(WEventLoop *el, int fd, int buf_id, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf_id; (void)len; (void)g; return -1;
}
int w_event_submit_accept_multishot(WEventLoop *el, int fd, struct sockaddr *addr, socklen_t *addrlen, WGoroutine *g) {
    (void)el; (void)fd; (void)addr; (void)addrlen; (void)g; return -1;
}
int w_event_submit_recv_timeout(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g, int timeout_ms) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; (void)timeout_ms; return -1;
}
int w_event_submit_send_and_close(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}

#endif /* __APPLE__ */

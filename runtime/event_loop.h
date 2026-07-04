#ifndef TUNGSTEN_EVENT_LOOP_H
#define TUNGSTEN_EVENT_LOOP_H

/* Forward declaration — full definition in runtime.h */
typedef struct WGoroutine WGoroutine;

/* Event interest flags */
#define W_EVENT_READ  1
#define W_EVENT_WRITE 2

/* Opaque event loop handle */
typedef struct WEventLoop WEventLoop;

/* Create a new platform event loop (kqueue on macOS, epoll on Linux) */
WEventLoop *w_event_init(void);

/* Destroy event loop and release resources */
void w_event_destroy(WEventLoop *el);

/* Register interest: when fd becomes ready for events, wake goroutine g.
 * Uses oneshot semantics — must re-register after each wakeup. */
void w_event_register(WEventLoop *el, int fd, int events, WGoroutine *g);

/* Remove all interest for fd */
void w_event_unregister(WEventLoop *el, int fd);

/* Poll for ready goroutines. Returns count of woken goroutines (up to max_out).
 * timeout_ms: -1 = block, 0 = non-blocking, >0 = milliseconds */
int w_event_poll(WEventLoop *el, int timeout_ms, WGoroutine **out, int max_out);

/* ---- Completion I/O API (io_uring only, stubs on epoll/kqueue) ----
 *
 * Submit a completion I/O operation. Returns 0 on success, -1 on error.
 * When the operation completes, goroutine g is woken with the result
 * stored in g->io_result (bytes transferred, or negative errno).
 * Callers MUST check return value — if -1, fall back to readiness path. */
#include <sys/socket.h>  /* struct sockaddr, socklen_t */

int w_event_submit_recv(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g);
int w_event_submit_send(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g);
int w_event_submit_accept(WEventLoop *el, int fd, struct sockaddr *addr,
                           socklen_t *addrlen, WGoroutine *g);

/* ---- Phase 4: Provided buffers + multi-shot recv + zero-copy send ---- */
int  w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g);
int  w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g);
void w_event_return_buf(WEventLoop *el, int buf_id);

/* ---- Phase 5: Registered send buffers + multi-shot accept + linked SQEs ---- */
int  w_event_send_buf_alloc(WEventLoop *el);
void w_event_send_buf_free(WEventLoop *el, int buf_id);
void *w_event_send_buf_ptr(WEventLoop *el, int buf_id);
int  w_event_submit_send_fixed(WEventLoop *el, int fd, int buf_id, size_t len, WGoroutine *g);
int  w_event_submit_accept_multishot(WEventLoop *el, int fd, struct sockaddr *addr,
                                      socklen_t *addrlen, WGoroutine *g);
int  w_event_submit_recv_timeout(WEventLoop *el, int fd, void *buf, size_t len,
                                  WGoroutine *g, int timeout_ms);
int  w_event_submit_send_and_close(WEventLoop *el, int fd, const void *buf,
                                    size_t len, WGoroutine *g);

#endif /* TUNGSTEN_EVENT_LOOP_H */

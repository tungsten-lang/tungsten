#ifndef TUNGSTEN_EVENT_LOOP_H
#define TUNGSTEN_EVENT_LOOP_H

#include <stdint.h>

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

/* Interrupt a poll, including a wake issued just before it blocks. Wakeups
 * may coalesce and never appear as a goroutine in out[]. One polling thread
 * owns each loop; wake and deadline updates may come from other threads.
 * Destroy requires the poller and all producers to have stopped. */
int w_event_wake(WEventLoop *el);

/* Absolute deadlines use __w_clock_ticks_raw(), NOT wall time or milliseconds.
 * Set inserts or updates (in either direction); cancel/pop eagerly detach.
 * A goroutine must stay alive until detached, and may belong to only one loop.
 * Cross-loop migration requires external synchronization after detachment.
 * These APIs manage the frontier, not goroutine state or scheduler admission.
 * Set returns 0 on success, -1 on invalid input or allocation failure.
 * Cancel returns whether the entry was present; next returns 0 for empty.
 * w_event_poll automatically bounds its timeout by this loop's next deadline;
 * the owner then pops due entries and claims/schedules the winning waits. */
int w_event_deadline_set(WEventLoop *el, WGoroutine *g, int64_t ticks);
int w_event_deadline_cancel(WEventLoop *el, WGoroutine *g);
int64_t w_event_deadline_next(WEventLoop *el);
WGoroutine *w_event_deadline_pop(WEventLoop *el, int64_t now);

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

/* ---- Provided buffers + multi-shot recv + zero-copy send ---- */
int  w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g);
int  w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g);
void w_event_return_buf(WEventLoop *el, int buf_id);

/* ---- Registered send buffers + multi-shot accept + linked SQEs ---- */
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

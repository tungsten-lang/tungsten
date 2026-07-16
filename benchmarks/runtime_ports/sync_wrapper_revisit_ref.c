#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

int64_t w_syncwrap_thread_cpu_ns(void) {
#if defined(__APPLE__)
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(mach_thread_self(), THREAD_BASIC_INFO,
                    (thread_info_t)&info, &count) != KERN_SUCCESS)
        return 0;
    int64_t seconds = (int64_t)info.user_time.seconds +
                      (int64_t)info.system_time.seconds;
    int64_t micros = (int64_t)info.user_time.microseconds +
                     (int64_t)info.system_time.microseconds;
    return seconds * 1000000000LL + micros * 1000LL;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return 0;
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

/* Unique factories keep the benchmark receiver opaque to the loader. */
WValue w_syncwrap_atomic_fixture(WValue initial) {
    return w_atomic_new(initial);
}

WValue w_syncwrap_release_atomic(WValue value) {
    if (w_is_atomic(value)) free(w_as_ptr(value));
    return W_NIL;
}

WValue w_syncwrap_ref_atomic_cas(WValue value, WValue expected, WValue desired) {
    return w_atomic_cas(value, expected, desired);
}

WValue w_syncwrap_ref_atomic_get(WValue value) {
    return w_atomic_get(value);
}

WValue w_syncwrap_ref_atomic_set(WValue value, WValue next) {
    return w_atomic_set(value, next);
}

WValue w_syncwrap_ref_atomic_increment(WValue value) {
    return w_atomic_increment(value);
}

WValue w_syncwrap_ref_atomic_decrement(WValue value) {
    return w_atomic_decrement(value);
}

WValue w_syncwrap_ref_atomic_add(WValue value, WValue delta) {
    return w_atomic_add(value, delta);
}

WValue w_syncwrap_channel_fixture(WValue capacity) {
    return w_chan_new(capacity);
}

WValue w_syncwrap_ref_channel_send(WValue channel, WValue value) {
    return w_chan_send(channel, value);
}

WValue w_syncwrap_ref_channel_recv(WValue channel) {
    return w_chan_recv(channel);
}

WValue w_syncwrap_ref_channel_close(WValue channel) {
    return w_chan_close(channel);
}

WValue w_syncwrap_channel_reopen(WValue channel) {
    if (!w_is_channel(channel)) return W_FALSE;
    WChan *ch = (WChan *)w_as_ptr(channel);
    pthread_mutex_lock(&ch->lock);
    ch->closed = 0;
    pthread_mutex_unlock(&ch->lock);
    return W_TRUE;
}

WValue w_syncwrap_channel_closed(WValue channel) {
    if (!w_is_channel(channel)) return w_int(-1);
    WChan *ch = (WChan *)w_as_ptr(channel);
    pthread_mutex_lock(&ch->lock);
    int closed = ch->closed;
    pthread_mutex_unlock(&ch->lock);
    return w_int(closed);
}

WValue w_syncwrap_release_channel(WValue channel) {
    if (!w_is_channel(channel)) return W_FALSE;
    WChan *ch = (WChan *)w_as_ptr(channel);
    pthread_mutex_destroy(&ch->lock);
    free(ch->buffer);
    free(ch);
    return W_TRUE;
}

/* A completed, already-joined fixture makes join/alive dispatch measurable
 * without mixing pthread creation latency into every sample. */
WValue w_syncwrap_dead_thread_fixture(WValue result) {
    WThread *thread = calloc(1, sizeof(WThread));
    thread->type = W_TYPE_THREAD;
    thread->closure = W_NIL;
    atomic_store(&thread->alive, 0);
    atomic_store(&thread->cancel, 0);
    thread->joined = 1;
    thread->result = result;
    return w_box_ptr(thread, W_SUBTAG_GENERIC);
}

WValue w_syncwrap_release_dead_thread(WValue value) {
    if (w_is_thread(value)) free(w_as_ptr(value));
    return W_NIL;
}

static void w_syncwrap_live_cleanup(void *arg) {
    WThread *thread = (WThread *)arg;
    atomic_store(&thread->alive, 0);
}

static void *w_syncwrap_live_entry(void *arg) {
    WThread *thread = (WThread *)arg;
    pthread_cleanup_push(w_syncwrap_live_cleanup, thread);
    for (;;) {
        struct timespec delay = {0, 1000000};
        nanosleep(&delay, NULL);
        pthread_testcancel();
    }
    pthread_cleanup_pop(1);
    return NULL;
}

WValue w_syncwrap_live_thread_fixture(void) {
    WThread *thread = calloc(1, sizeof(WThread));
    thread->type = W_TYPE_THREAD;
    thread->closure = W_NIL;
    atomic_store(&thread->alive, 1);
    atomic_store(&thread->cancel, 0);
    thread->joined = 0;
    thread->result = W_NIL;
    if (pthread_create(&thread->handle, NULL, w_syncwrap_live_entry, thread) != 0) {
        free(thread);
        return W_NIL;
    }
    return w_box_ptr(thread, W_SUBTAG_GENERIC);
}

WValue w_syncwrap_ref_thread_join(WValue thread) {
    return w_thread_join(thread);
}

WValue w_syncwrap_ref_thread_join_timeout(WValue thread, WValue milliseconds) {
    /* Match the removed IC wrapper exactly: signed 48-bit payload extraction. */
    return w_thread_join_timeout(thread, w_as_int(milliseconds));
}

WValue w_syncwrap_ref_thread_alive(WValue thread) {
    return w_thread_alive(thread);
}

WValue w_syncwrap_ref_thread_kill(WValue thread) {
    return w_thread_kill(thread);
}

WValue w_syncwrap_join_release_live_thread(WValue thread) {
    return w_thread_join_release(thread);
}

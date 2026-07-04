/* runtime/hid_bridge.m — USB-HID input bridge for Tungsten (Elgato Stream Deck +).
 *
 * Reads the Stream Deck +'s four rotary dials (rotate + press), so the compiled
 * REPL's live "scrub" mode can bind each dial to a scrubbable field. This file
 * is ONLY the IOKit producer half; the cross-platform consumer half (the SPSC
 * ring, the self-pipe, w_input_poll, and non-darwin stubs) lives in runtime.c.
 *
 * Threading model (see runtime.c for the GC/allocation rules): the REPL main
 * thread blocks in poll() during scrubbing and so cannot pump a CFRunLoop. We
 * therefore run IOHIDManager on a dedicated pthread with its OWN CFRunLoopRun.
 * The input-report callback fires on that thread, decodes the report into POD
 * HIDEvent structs, and hands them to w_hid_ring_push (which never allocates
 * WValues — only the main thread boxes). A self-pipe wakes the consumer's poll.
 *
 * Stream Deck + HID protocol (Elgato docs): input report id 0x01, command byte
 * at +1. Encoder report = cmd 0x03: +4 is 0x01 ROTATE (4 signed-int8 tick deltas
 * at +5..+8) or 0x00 BTN (4 0/1 states). LCD-key report = cmd 0x00 (8 states at
 * +4). Touchscreen (cmd 0x02) is out of scope v0.
 *
 * Compiled only on darwin (gated in runtime/Makefile + bin/commands/compile.rb)
 * and linked with -framework IOKit -framework CoreFoundation. Lifetime: v1 opens
 * the device per scrub session and closes it on every exit path.
 */

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#include <fcntl.h>
#include <unistd.h>
#include "runtime.h"
#include "wvalue.h"

#define SD_VID 0x0FD9
#define SD_PID 0x0084
#define HID_REPORT_BUF_LEN 512

/* Single-Stream-Deck assumption: one live device per process. */
static WHIDDevice *g_hid = NULL;

/* Edge-state for press/key events (the device re-sends full state per report;
 * we only emit on a 0↔1 transition). Producer-thread-only, no sync needed. */
static uint8_t prev_dial_btn[4] = {0, 0, 0, 0};
static uint8_t prev_lcd_key[8]  = {0};

static WHIDDevice *as_hid_device(WValue v) {
    if (!w_is_obj(v) || w_subtag(v) != W_SUBTAG_GENERIC) return NULL;
    WHIDDevice *d = (WHIDDevice *)w_as_ptr(v);
    if (d->type != W_TYPE_HID_DEVICE) return NULL;
    return d;
}

static void set_nonblock(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0) fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

/* ---- Producer thread: decode reports → ring ---- */

static void hid_report_cb(void *ctx, IOReturn res, void *sender,
                          IOHIDReportType type, uint32_t reportID,
                          uint8_t *report, CFIndex len) {
    (void)ctx; (void)sender; (void)type; (void)reportID;
    if (res != kIOReturnSuccess || len < 5 || report[0] != 0x01) return;
    uint8_t cmd = report[1];

    if (cmd == 0x03) {                       /* encoder */
        if (len < 9) return;
        uint8_t sub = report[4];
        if (sub == 0x01) {                   /* ROTATE: 4 signed int8 at [5..8] */
            for (int i = 0; i < 4; i++) {
                int8_t d = (int8_t)report[5 + i];
                if (d != 0) {
                    HIDEvent ev = { HID_ROTATE, (uint8_t)i, (int16_t)d };
                    w_hid_ring_push(ev);
                }
            }
        } else if (sub == 0x00) {            /* BTN: 4 states at [5..8], edge */
            for (int i = 0; i < 4; i++) {
                uint8_t s = report[5 + i] ? 1 : 0;
                if (s != prev_dial_btn[i]) {
                    prev_dial_btn[i] = s;
                    HIDEvent ev = { HID_PRESS, (uint8_t)i, (int16_t)s };
                    w_hid_ring_push(ev);
                }
            }
        }
    } else if (cmd == 0x00) {                /* LCD keys: 8 states at [4..11], edge */
        if (len < 12) return;
        for (int i = 0; i < 8; i++) {
            uint8_t s = report[4 + i] ? 1 : 0;
            if (s != prev_lcd_key[i]) {
                prev_lcd_key[i] = s;
                HIDEvent ev = { HID_KEY, (uint8_t)i, (int16_t)s };
                w_hid_ring_push(ev);
            }
        }
    }
    /* cmd == 0x02 touchscreen: out of scope v0 (ignored). */
}

static void hid_matched_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev) {
    (void)res; (void)sender;
    WHIDDevice *d = (WHIDDevice *)ctx;
    atomic_fetch_add(&d->device_count, 1);
    /* The report buffer must outlive the device; d->report_buf does. */
    IOHIDDeviceRegisterInputReportCallback(dev, d->report_buf, HID_REPORT_BUF_LEN,
                                           hid_report_cb, d);
}

static void hid_removed_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev) {
    (void)res; (void)sender; (void)dev;
    WHIDDevice *d = (WHIDDevice *)ctx;
    atomic_fetch_sub(&d->device_count, 1);
}

/* Publish the open result + runloop, then wake w_hid_streamdeck_open. */
static void hid_publish_started(WHIDDevice *d, int open_ok) {
    pthread_mutex_lock(&d->lock);
    d->open_ok = open_ok;
    d->started = 1;
    pthread_cond_signal(&d->ready);
    pthread_mutex_unlock(&d->lock);
}

static void *hid_thread_main(void *arg) {
    WHIDDevice *d = (WHIDDevice *)arg;
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);

    int vid = SD_VID, pid = SD_PID;
    CFNumberRef vidN = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFNumberRef pidN = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    const void *vals[] = { vidN, pidN };
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(mgr, match);
    CFRelease(match); CFRelease(vidN); CFRelease(pidN);

    IOHIDManagerRegisterDeviceMatchingCallback(mgr, hid_matched_cb, d);
    IOHIDManagerRegisterDeviceRemovalCallback(mgr, hid_removed_cb, d);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOReturn opened = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

    if (opened != kIOReturnSuccess && getenv("TUNGSTEN_HID_DEBUG")) {
        const char *hint = "";
        if (opened == kIOReturnExclusiveAccess)      /* 0xe00002c5 */
            hint = " — the Elgato Stream Deck app has the device; quit it to read dials directly";
        else if (opened == kIOReturnNotPermitted)    /* 0xe00002e2 */
            hint = " — grant Input Monitoring to your terminal (System Settings ▸ Privacy & Security)";
        fprintf(stderr, "[hid] IOHIDManagerOpen failed: 0x%08x%s\n", opened, hint);
    }
    d->manager = (void *)mgr;
    d->runloop = (void *)CFRunLoopGetCurrent();
    hid_publish_started(d, opened == kIOReturnSuccess);

    if (opened == kIOReturnSuccess) {
        CFRunLoopRun();                      /* blocks until CFRunLoopStop (close) */
    }

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
    CFRelease(mgr);
    return NULL;
}

/* ---- Public API (declared in runtime.h) ---- */

WValue w_hid_streamdeck_open(void) {
    if (g_hid) return w_box_ptr(g_hid, W_SUBTAG_GENERIC);   /* idempotent */

    if (g_hid_pipe[0] < 0) {
        if (pipe(g_hid_pipe) != 0) return W_NIL;
        set_nonblock(g_hid_pipe[0]);
        set_nonblock(g_hid_pipe[1]);
    }

    WHIDDevice *d = (WHIDDevice *)calloc(1, sizeof(WHIDDevice));
    d->type = W_TYPE_HID_DEVICE;
    d->report_buf = (uint8_t *)malloc(HID_REPORT_BUF_LEN);
    pthread_mutex_init(&d->lock, NULL);
    pthread_cond_init(&d->ready, NULL);
    d->started = 0;
    d->open_ok = 0;

    if (pthread_create(&d->thread, NULL, hid_thread_main, d) != 0) {
        pthread_mutex_destroy(&d->lock);
        pthread_cond_destroy(&d->ready);
        free(d->report_buf);
        free(d);
        return W_NIL;
    }

    /* Wait until the reader thread has published its runloop + open result, so
     * close() always has a valid CFRunLoopRef and we know whether open worked. */
    pthread_mutex_lock(&d->lock);
    while (!d->started) pthread_cond_wait(&d->ready, &d->lock);
    int ok = d->open_ok;
    pthread_mutex_unlock(&d->lock);

    if (!ok) {
        /* Open failed: the thread skipped CFRunLoopRun and is returning. */
        pthread_join(d->thread, NULL);
        pthread_mutex_destroy(&d->lock);
        pthread_cond_destroy(&d->ready);
        free(d->report_buf);
        free(d);
        return W_NIL;
    }

    g_hid = d;
    return w_box_ptr(d, W_SUBTAG_GENERIC);
}

WValue w_hid_streamdeck_close(WValue dev_v) {
    WHIDDevice *d = as_hid_device(dev_v);
    if (!d) return W_NIL;
    if (d->runloop) CFRunLoopStop((CFRunLoopRef)d->runloop);  /* wakes CFRunLoopRun */
    pthread_join(d->thread, NULL);
    pthread_mutex_destroy(&d->lock);
    pthread_cond_destroy(&d->ready);
    free(d->report_buf);
    free(d);
    if (g_hid == d) g_hid = NULL;
    return W_NIL;
}

WValue w_hid_device_present(WValue dev_v) {
    WHIDDevice *d = as_hid_device(dev_v);
    return w_bool(d && atomic_load(&d->device_count) > 0 ? 1 : 0);
}

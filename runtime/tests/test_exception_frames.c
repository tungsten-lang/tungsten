/* Regression tests for exception cleanup and non-local block-return frames. */

#include "../runtime.h"

#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int cleanup_log[8];
static int cleanup_count;
static void *abandoned_outer;
static void *abandoned_inner;

static void fail(const char *message) {
    fprintf(stderr, "FAIL exception-frame regression: %s\n", message);
    exit(1);
}

static void require(int condition, const char *message) {
    if (!condition) fail(message);
}

static void record_cleanup(WValue value) {
    cleanup_log[cleanup_count++] = (int)w_as_int(value);
}

/* The exception handler lives in the caller. Both block-return setjmp
 * environments therefore become invalid when w_raise jumps out of here. */
static void raise_across_nested_blocks(void) {
    void *outer = w_block_return_push();
    abandoned_outer = outer;
    if (_setjmp(*(jmp_buf *)outer) == 0) {
        /* Put a younger exception frame between the two blocks, then pop it
         * before raising to the caller's handler. The inner block's saved
         * exception-stack pointer must still be recognized as descending
         * from the target handler. */
        (void)w_exception_push();
        void *inner = w_block_return_push();
        abandoned_inner = inner;
        if (_setjmp(*(jmp_buf *)inner) == 0) {
            w_exception_pop();
            w_raise(w_string("crossed block frames"));
        }
    }
    fail("exception returned to an abandoned block frame");
}

static void require_inactive_block(void *block) {
    WExceptionFrame handler;
    w_exception_frame_push(&handler);
    if (_setjmp(handler.buf) == 0) {
        w_block_return_signal((uint64_t)(uintptr_t)block, w_box_int(99));
        fail("signal to abandoned block returned normally");
    }

    require(w_is_string(w_exception_error()),
            "signal to abandoned block did not raise a string error");
    w_exception_pop();
}

static void test_stack_frame_cleanup_snapshot(void) {
    cleanup_count = 0;
    w_cleanup_push(w_box_int(10), record_cleanup);

    WExceptionFrame handler;
    w_exception_frame_push(&handler);
    if (_setjmp(handler.buf) == 0) {
        w_cleanup_push(w_box_int(20), record_cleanup);
        w_cleanup_push(w_box_int(30), record_cleanup);
        w_raise(w_string("cleanup"));
    }

    require(cleanup_count == 2, "wrong cleanup count at stack handler");
    require(cleanup_log[0] == 30 && cleanup_log[1] == 20,
            "stack handler did not unwind cleanups in LIFO order");
    w_exception_pop();

    /* The cleanup predating the handler was retained rather than run. */
    w_cleanup_pop();
}

static void test_exception_abandons_block_frames(void) {
    abandoned_outer = NULL;
    abandoned_inner = NULL;
    WExceptionFrame handler;
    w_exception_frame_push(&handler);
    if (_setjmp(handler.buf) == 0) {
        raise_across_nested_blocks();
    }

    require(abandoned_outer != NULL && abandoned_inner != NULL,
            "nested block frames were not saved");
    require(w_is_string(w_exception_error()), "crossing exception was not caught");
    w_exception_pop();

    /* These calls must raise. Before the fix, the TLS stack still marked the
     * frames active and attempted to longjmp into raise_across_nested_blocks's
     * dead C stack. */
    require_inactive_block(abandoned_inner);
    require_inactive_block(abandoned_outer);
}

static void test_inner_handler_preserves_enclosing_block(void) {
    void *block = w_block_return_push();
    if (_setjmp(*(jmp_buf *)block) == 0) {
        WExceptionFrame handler;
        w_exception_frame_push(&handler);
        if (_setjmp(handler.buf) == 0) {
            w_raise(w_string("handled inside block"));
        }

        require(w_is_string(w_exception_error()), "inner exception was not caught");
        w_exception_pop();
        w_block_return_signal((uint64_t)(uintptr_t)block, w_box_int(123));
        fail("active block signal returned normally");
    }

    require(w_as_int(w_block_return_value(block)) == 123,
            "inner handler incorrectly deactivated its enclosing block");
    w_block_return_pop(block);
}

int main(void) {
    test_stack_frame_cleanup_snapshot();
    test_exception_abandons_block_frames();
    test_inner_handler_preserves_enclosing_block();
    require(w_exception_stack == NULL, "exception stack was not restored");
    puts("PASS exception-frame cleanup and block-return unwind");
    return 0;
}

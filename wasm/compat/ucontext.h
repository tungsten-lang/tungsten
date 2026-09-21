/* wasm32-wasi compat: WebAssembly has no stack switching, so ucontext (the
 * goroutine fallback in runtime.c) is declared but traps politely when used.
 * Definitions live in wasm/wasi_stubs.c. */
#ifndef TUNGSTEN_WASI_UCONTEXT_H
#define TUNGSTEN_WASI_UCONTEXT_H
#include <stddef.h>
typedef struct {
    void *ss_sp;
    int ss_flags;
    size_t ss_size;
} w_wasi_stack_t;
typedef struct ucontext_t {
    struct ucontext_t *uc_link;
    w_wasi_stack_t uc_stack;
} ucontext_t;
int getcontext(ucontext_t *ucp);
int setcontext(const ucontext_t *ucp);
void makecontext(ucontext_t *ucp, void (*func)(void), int argc, ...);
int swapcontext(ucontext_t *oucp, const ucontext_t *ucp);
#endif

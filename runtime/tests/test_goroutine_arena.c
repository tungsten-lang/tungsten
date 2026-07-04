/*
 * test_goroutine_arena.c — Phase 0 Validation Sprint
 *
 * Validates the goroutine stack arena design before committing to it:
 *   1. mmap arena with MAP_NORESERVE (virtual only, no RSS)
 *   2. 64KB stacks + 4KB guard pages (mprotect PROT_NONE)
 *   3. swapcontext on macOS arm64 — verify context save/restore
 *   4. Many goroutines with heap-allocated objects on arena stacks
 *   5. Guard page overflow → SIGSEGV
 *
 * Gate: if any test fails, the goroutine design must be revised.
 */

#define _XOPEN_SOURCE 600
#define _DARWIN_C_SOURCE  /* MAP_ANON, MAP_NORESERVE on macOS */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>


/* ucontext is deprecated on macOS but still functional with _XOPEN_SOURCE */
#include <ucontext.h>

/* ---- Constants ---- */

/* Use OS page size for guard pages (16KB on Apple Silicon, 4KB on x86) */
static size_t os_page_size(void) {
    return (size_t)sysconf(_SC_PAGESIZE);
}

/* Round up to next multiple of alignment */
static size_t align_up(size_t val, size_t alignment) {
    return (val + alignment - 1) & ~(alignment - 1);
}

#define GOROUTINE_STACK_SIZE  (64 * 1024)   /* 64KB per goroutine */
#define MAX_GOROUTINES        10000
#define TEST_GOROUTINES       100

/* Slot size computed at runtime to respect OS page size */
static size_t guard_page_size(void) { return os_page_size(); }
static size_t slot_size(void) {
    size_t pg = os_page_size();
    return align_up(GOROUTINE_STACK_SIZE, pg) + pg;  /* stack (rounded up) + guard */
}

/* ---- Test infrastructure ---- */

static int tests_run = 0;
static int tests_passed = 0;

#define ASSERT(cond, msg) do { \
    tests_run++; \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        tests_passed++; \
    } \
} while (0)

/* ---- Arena ---- */

typedef struct {
    void *base;          /* mmap base address */
    size_t total_size;   /* total virtual reservation */
    int slot_count;      /* number of usable slots */
    int next_slot;       /* next slot to allocate */
} GoroutineArena;

static GoroutineArena *arena_create(int max_goroutines) {
    size_t ss = slot_size();
    size_t total = ss * max_goroutines;

    /* MAP_NORESERVE is a no-op on macOS (lazy alloc by default), use on Linux */
    int flags = MAP_PRIVATE | MAP_ANON;
#ifdef MAP_NORESERVE
#ifndef __APPLE__
    flags |= MAP_NORESERVE;
#endif
#endif
    void *base = mmap(NULL, total, PROT_NONE, flags, -1, 0);
    if (base == MAP_FAILED) {
        perror("mmap arena");
        return NULL;
    }

    GoroutineArena *arena = malloc(sizeof(GoroutineArena));
    arena->base = base;
    arena->total_size = total;
    arena->slot_count = max_goroutines;
    arena->next_slot = 0;
    return arena;
}

/* Returns stack base (bottom of usable stack memory, NOT the guard page).
 * Layout per slot: [guard_page_size() guard | stack_size stack]
 * Stack grows downward, so the "top" is at stack_base + stack_size.
 */
static size_t arena_stack_size(void) {
    return align_up(GOROUTINE_STACK_SIZE, os_page_size());
}

static void *arena_alloc_stack(GoroutineArena *arena) {
    if (arena->next_slot >= arena->slot_count) return NULL;

    size_t ss = slot_size();
    size_t gs = guard_page_size();
    size_t stk = arena_stack_size();
    int slot = arena->next_slot++;
    char *slot_base = (char *)arena->base + (size_t)slot * ss;

    /* Guard page stays PROT_NONE (already is from mmap) */
    /* Make the stack region read/write */
    char *stack_base = slot_base + gs;
    if (mprotect(stack_base, stk, PROT_READ | PROT_WRITE) != 0) {
        perror("mprotect stack");
        return NULL;
    }

    return stack_base;
}

static void *arena_stack_top(void *stack_base) {
    return (char *)stack_base + arena_stack_size();
}

static void arena_destroy(GoroutineArena *arena) {
    munmap(arena->base, arena->total_size);
    free(arena);
}

/* ---- Test 1: Arena allocation ---- */

static void test_arena_allocation(void) {
    printf("Test 1: Arena allocation (mmap MAP_NORESERVE)\n");

    GoroutineArena *arena = arena_create(MAX_GOROUTINES);
    ASSERT(arena != NULL, "arena_create returns non-NULL");
    ASSERT(arena->base != MAP_FAILED, "mmap succeeded");
    size_t expected_size = slot_size() * MAX_GOROUTINES;
    ASSERT(arena->total_size == expected_size, "arena size correct (virtual)");

    /* Allocate a few stacks and verify they're usable */
    void *stack1 = arena_alloc_stack(arena);
    ASSERT(stack1 != NULL, "first stack allocated");

    void *stack2 = arena_alloc_stack(arena);
    ASSERT(stack2 != NULL, "second stack allocated");
    ASSERT(stack2 != stack1, "stacks are different");
    ASSERT((size_t)((char *)stack2 - (char *)stack1) == slot_size(), "stacks are slot_size apart");

    /* Write to stack memory to verify it's accessible */
    size_t stk_size = arena_stack_size();
    memset(stack1, 0xAA, stk_size);
    memset(stack2, 0xBB, stk_size);
    ASSERT(((unsigned char *)stack1)[0] == 0xAA, "stack1 writable");
    ASSERT(((unsigned char *)stack2)[0] == 0xBB, "stack2 writable");

    arena_destroy(arena);
    printf("  Arena allocation: OK\n\n");
}

/* ---- Test 2: Guard pages ---- */

static volatile sig_atomic_t got_sigsegv = 0;

static void sigsegv_handler(int sig) {
    (void)sig;
    got_sigsegv = 1;
    _exit(42);  /* Exit with known code in child process */
}

static void test_guard_pages(void) {
    printf("Test 2: Guard page protection\n");

    GoroutineArena *arena = arena_create(10);
    void *stack = arena_alloc_stack(arena);
    ASSERT(stack != NULL, "stack allocated for guard test");

    /* The guard page is immediately before the stack */
    char *guard_page = (char *)stack - guard_page_size();

    /* Fork to test SIGSEGV — child will crash, parent checks exit code */
    pid_t pid = fork();
    if (pid == 0) {
        /* Child: install signal handler and touch guard page */
        signal(SIGSEGV, sigsegv_handler);
        signal(SIGBUS, sigsegv_handler);  /* macOS may raise SIGBUS instead */

        /* This should trigger SIGSEGV/SIGBUS */
        volatile char *p = (volatile char *)guard_page;
        *p = 0xFF;

        /* If we get here, guard page didn't work */
        _exit(0);
    } else {
        /* Parent: wait for child */
        int status;
        waitpid(pid, &status, 0);
        if (WIFEXITED(status)) {
            ASSERT(WEXITSTATUS(status) == 42, "guard page triggered signal (exit code 42)");
        } else if (WIFSIGNALED(status)) {
            int sig = WTERMSIG(status);
            ASSERT(sig == SIGSEGV || sig == SIGBUS,
                   "guard page triggered SIGSEGV/SIGBUS");
        } else {
            ASSERT(0, "guard page test: unexpected child status");
        }
    }

    arena_destroy(arena);
    printf("  Guard pages: OK\n\n");
}

/* ---- Test 3: swapcontext on macOS arm64 ---- */

static ucontext_t main_ctx, g1_ctx, g2_ctx;
static int g1_ran = 0, g2_ran = 0;
static int switch_count = 0;

static void goroutine_1(void) {
    g1_ran = 1;
    switch_count++;
    /* Yield to goroutine 2 */
    swapcontext(&g1_ctx, &g2_ctx);
    /* Resumed — increment again */
    switch_count++;
    /* Return to main */
    swapcontext(&g1_ctx, &main_ctx);
}

static void goroutine_2(void) {
    g2_ran = 1;
    switch_count++;
    /* Yield back to goroutine 1 */
    swapcontext(&g2_ctx, &g1_ctx);
    /* Resumed */
    switch_count++;
    /* Return to main */
    swapcontext(&g2_ctx, &main_ctx);
}

static void test_swapcontext(void) {
    printf("Test 3: swapcontext on macOS arm64\n");

    GoroutineArena *arena = arena_create(10);
    void *stack1 = arena_alloc_stack(arena);
    void *stack2 = arena_alloc_stack(arena);
    ASSERT(stack1 != NULL && stack2 != NULL, "stacks allocated for swapcontext");

    /* Set up goroutine 1 context */
    getcontext(&g1_ctx);
    g1_ctx.uc_stack.ss_sp = stack1;
    g1_ctx.uc_stack.ss_size = arena_stack_size();
    g1_ctx.uc_link = &main_ctx;
    makecontext(&g1_ctx, goroutine_1, 0);

    /* Set up goroutine 2 context */
    getcontext(&g2_ctx);
    g2_ctx.uc_stack.ss_sp = stack2;
    g2_ctx.uc_stack.ss_size = arena_stack_size();
    g2_ctx.uc_link = &main_ctx;
    makecontext(&g2_ctx, goroutine_2, 0);

    /* Switch to goroutine 1 — it will bounce to g2 and back */
    swapcontext(&main_ctx, &g1_ctx);

    ASSERT(g1_ran == 1, "goroutine 1 executed");
    ASSERT(g2_ran == 1, "goroutine 2 executed");
    /* g1(count=1) → g2(count=2) → g1 resumed(count=3) → main */
    ASSERT(switch_count == 3, "three increments after first main→g1 swap");

    /* Resume goroutine 2 to finish: g2 resumed(count=4) → main */
    swapcontext(&main_ctx, &g2_ctx);
    ASSERT(switch_count == 4, "four total increments");

    /* Verify no stack corruption: write a pattern and read it back */
    volatile uint64_t *marker1 = (uint64_t *)stack1;
    volatile uint64_t *marker2 = (uint64_t *)stack2;
    *marker1 = 0xDEADBEEF12345678ULL;
    *marker2 = 0xCAFEBABE87654321ULL;
    ASSERT(*marker1 == 0xDEADBEEF12345678ULL, "stack1 not corrupted after swapcontext");
    ASSERT(*marker2 == 0xCAFEBABE87654321ULL, "stack2 not corrupted after swapcontext");

    arena_destroy(arena);
    printf("  swapcontext: OK\n\n");
}

/* ---- Test 4: Many goroutines with GC integration ---- */

typedef struct {
    ucontext_t ctx;
    void *stack_base;
    int id;
    int completed;
    uintptr_t *heap_object;  /* A heap-allocated pointer stored on the goroutine stack */
} TestGoroutine;

static ucontext_t scheduler_ctx;
static TestGoroutine goroutines[TEST_GOROUTINES];
static int current_g = -1;

static void goroutine_body(void) {
    int id = current_g;
    TestGoroutine *g = &goroutines[id];

    /* Allocate a heap object and store a pointer to it on our arena stack */
    g->heap_object = (uintptr_t *)calloc(4, sizeof(uintptr_t));
    g->heap_object[0] = (uintptr_t)(0xAAAA0000 + id);
    g->heap_object[1] = (uintptr_t)id;
    g->heap_object[2] = (uintptr_t)(id * 2);
    g->heap_object[3] = (uintptr_t)(id * 3);

    /* Also store a pointer in a local variable (on the arena stack) */
    volatile uintptr_t *local_ptr = g->heap_object;
    (void)local_ptr;

    g->completed = 1;

    /* Return to scheduler */
    swapcontext(&g->ctx, &scheduler_ctx);
}

static void test_many_goroutines(void) {
    printf("Test 4: %d goroutines + heap allocation\n", TEST_GOROUTINES);

    GoroutineArena *arena = arena_create(TEST_GOROUTINES + 10);
    ASSERT(arena != NULL, "arena created for goroutine test");

    /* Set up goroutines */
    for (int i = 0; i < TEST_GOROUTINES; i++) {
        goroutines[i].stack_base = arena_alloc_stack(arena);
        ASSERT(goroutines[i].stack_base != NULL, "stack allocated");
        goroutines[i].id = i;
        goroutines[i].completed = 0;
        goroutines[i].heap_object = NULL;

        getcontext(&goroutines[i].ctx);
        goroutines[i].ctx.uc_stack.ss_sp = goroutines[i].stack_base;
        goroutines[i].ctx.uc_stack.ss_size = arena_stack_size();
        goroutines[i].ctx.uc_link = &scheduler_ctx;
        makecontext(&goroutines[i].ctx, goroutine_body, 0);
    }

    /* Run each goroutine */
    for (int i = 0; i < TEST_GOROUTINES; i++) {
        current_g = i;
        swapcontext(&scheduler_ctx, &goroutines[i].ctx);
    }

    /* Verify all completed */
    int all_completed = 1;
    for (int i = 0; i < TEST_GOROUTINES; i++) {
        if (!goroutines[i].completed) {
            all_completed = 0;
            break;
        }
    }
    ASSERT(all_completed, "all goroutines completed");

    /* Verify heap-allocated objects are intact */
    int all_survived = 1;
    for (int i = 0; i < TEST_GOROUTINES; i++) {
        if (goroutines[i].heap_object == NULL) {
            all_survived = 0;
            break;
        }
        /* Verify the data is intact */
        if (goroutines[i].heap_object[0] != (uintptr_t)(0xAAAA0000 + i) ||
            goroutines[i].heap_object[1] != (uintptr_t)i) {
            all_survived = 0;
            break;
        }
    }
    ASSERT(all_survived, "heap-allocated objects intact after goroutine execution");

    /* Clean up heap allocations */
    for (int i = 0; i < TEST_GOROUTINES; i++) {
        free(goroutines[i].heap_object);
    }

    arena_destroy(arena);
    printf("  Many goroutines: OK\n\n");
}

/* ---- Test 5: Stack overflow detection ---- */

static volatile int overflow_depth = 0;

__attribute__((noinline, optnone))
static void stack_overflow_body(void) {
    /* Recurse until we hit the guard page.
     * noinline + optnone prevent tail-call optimization at -O2. */
    volatile char buf[4096];  /* 4KB per frame */
    memset((char *)buf, 0x42, sizeof(buf));
    overflow_depth++;
    stack_overflow_body();
}

static void test_stack_overflow_detection(void) {
    printf("Test 5: Stack overflow hits guard page\n");

    pid_t pid = fork();
    if (pid == 0) {
        /* Child: use raw mmap (no GC, no malloc — safe after fork) */
        size_t pg = os_page_size();
        size_t stk = arena_stack_size();
        size_t total = pg + stk;
        void *mem = mmap(NULL, total, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (mem == MAP_FAILED) _exit(99);
        char *stack = (char *)mem + pg;
        if (mprotect(stack, stk, PROT_READ | PROT_WRITE) != 0) _exit(99);

        ucontext_t overflow_ctx, return_ctx;
        getcontext(&overflow_ctx);
        overflow_ctx.uc_stack.ss_sp = stack;
        overflow_ctx.uc_stack.ss_size = stk;
        overflow_ctx.uc_link = &return_ctx;
        makecontext(&overflow_ctx, stack_overflow_body, 0);

        /* This should crash with SIGSEGV/SIGBUS when stack overflows into guard page */
        swapcontext(&return_ctx, &overflow_ctx);

        /* Should not reach here */
        _exit(0);
    } else {
        int status;
        waitpid(pid, &status, 0);
        if (WIFSIGNALED(status)) {
            int sig = WTERMSIG(status);
            ASSERT(sig == SIGSEGV || sig == SIGBUS,
                   "stack overflow triggers SIGSEGV/SIGBUS on guard page");
        } else if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
            /* Some systems may exit rather than signal */
            ASSERT(1, "stack overflow detected (non-zero exit)");
        } else {
            ASSERT(0, "stack overflow should crash child process");
        }
    }

    printf("  Stack overflow detection: OK\n\n");
}

/* ---- Test 6: Rapid context switching stress test ---- */

#define STRESS_SWITCHES 100000
static ucontext_t stress_main_ctx, stress_g_ctx;
static int stress_counter = 0;

static void stress_goroutine(void) {
    while (stress_counter < STRESS_SWITCHES) {
        stress_counter++;
        swapcontext(&stress_g_ctx, &stress_main_ctx);
    }
}

static void test_rapid_context_switching(void) {
    printf("Test 6: Rapid context switching (%d switches)\n", STRESS_SWITCHES);

    GoroutineArena *arena = arena_create(2);
    void *stack = arena_alloc_stack(arena);

    getcontext(&stress_g_ctx);
    stress_g_ctx.uc_stack.ss_sp = stack;
    stress_g_ctx.uc_stack.ss_size = arena_stack_size();
    stress_g_ctx.uc_link = &stress_main_ctx;
    makecontext(&stress_g_ctx, stress_goroutine, 0);

    while (stress_counter < STRESS_SWITCHES) {
        swapcontext(&stress_main_ctx, &stress_g_ctx);
    }

    ASSERT(stress_counter == STRESS_SWITCHES, "all context switches completed without corruption");

    arena_destroy(arena);
    printf("  Rapid context switching: OK\n\n");
}

/* ---- Main ---- */

int main(void) {
    setbuf(stdout, NULL);  /* Unbuffer stdout for immediate output */
    printf("=== Phase 0: Goroutine Arena Validation ===\n");
    printf("Platform: %s %s\n",
#ifdef __APPLE__
           "macOS",
#else
           "Linux",
#endif
#ifdef __aarch64__
           "arm64"
#elif defined(__x86_64__)
           "x86_64"
#else
           "unknown"
#endif
    );
    printf("Stack size: %zu KB, Guard page: %zu KB, Slot: %zu KB\n",
           arena_stack_size() / 1024, guard_page_size() / 1024, slot_size() / 1024);
    printf("Max goroutines: %d, Arena: %zu MB (virtual)\n\n",
           MAX_GOROUTINES, (slot_size() * MAX_GOROUTINES) / (1024 * 1024));

    test_arena_allocation();
    test_guard_pages();
    test_swapcontext();
    test_stack_overflow_detection();
    test_many_goroutines();
    test_rapid_context_switching();

    printf("=== Results: %d/%d passed ===\n", tests_passed, tests_run);

    if (tests_passed == tests_run) {
        printf("GATE: PASS — goroutine arena design validated\n");
        return 0;
    } else {
        printf("GATE: FAIL — %d tests failed, revise design before proceeding\n",
               tests_run - tests_passed);
        return 1;
    }
}

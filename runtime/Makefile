LLC = /opt/homebrew/opt/llvm/bin/llc
CLANG = clang
ZSTD_CFLAGS = $(shell pkg-config --cflags libzstd 2>/dev/null || echo -I/opt/homebrew/include)
ZSTD_LDFLAGS = $(shell pkg-config --libs libzstd 2>/dev/null || echo -L/opt/homebrew/lib -lzstd)
ONIG_CFLAGS = $(shell pkg-config --cflags oniguruma 2>/dev/null || test -f /opt/homebrew/include/oniguruma.h && echo -I/opt/homebrew/include)
ONIG_LDFLAGS = $(shell pkg-config --libs oniguruma 2>/dev/null || test -f /opt/homebrew/lib/libonig.dylib -o -f /opt/homebrew/lib/libonig.a && echo -L/opt/homebrew/lib -lonig)
ifneq ($(strip $(ONIG_CFLAGS)),)
  ONIG_CFLAGS += -DTUNGSTEN_ONIG
endif
BENCH_FLAGS = -O3 -mcpu=native

# GC removed — using malloc/calloc directly
GC_CFLAGS =
GC_LDFLAGS =

# ucontext is deprecated on macOS but functional — suppress warnings
WARN_FLAGS = -Wno-deprecated-declarations

RUNTIME_DIR = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Platform-specific event loop backend
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  EVENT_SRC = event_kqueue.c
  # Metal compute primitives — runtime/metal.m only on darwin.
  # graphics.m adds the windowing/present half (NSWindow + CAMetalLayer).
  # Linking the frameworks unconditionally is harmless for binaries
  # that don't actually use any @gpu fn / window.
  # hid_bridge.m: USB-HID input (Elgato Stream Deck + dials) for the REPL scrub
  # loop. IOKit hosts IOHIDManager; CoreFoundation for CFRunLoop/CFNumber/CFDict.
  METAL_SRC = metal.m graphics.m hid_bridge.m blas_bridge.c
  METAL_LDFLAGS = -framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework IOKit -framework CoreFoundation
  BLAS_LDFLAGS = -framework Accelerate
  PLATFORM_LDFLAGS = $(METAL_LDFLAGS) $(BLAS_LDFLAGS)
else ifeq ($(UNAME_S),Linux)
  EVENT_SRC = event_epoll.c
  METAL_SRC =
  METAL_LDFLAGS =
  # libm is a separate library on Linux (macOS bundles it into libSystem);
  # runtime.c uses sqrt/pow/ceil/floor/round, so link it explicitly. Goes in
  # RUNTIME_LDFLAGS (end of the link line) so it follows the objects.
  PLATFORM_LDFLAGS = -lm
endif

# TLS support (optional: set TLS=1 to enable)
ifdef TLS
  ifeq ($(UNAME_S),Darwin)
    OPENSSL_PREFIX = $(shell brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)
    TLS_CFLAGS = -DTUNGSTEN_TLS -I$(OPENSSL_PREFIX)/include
    TLS_LDFLAGS = -L$(OPENSSL_PREFIX)/lib -lssl -lcrypto
  else
    TLS_CFLAGS = -DTUNGSTEN_TLS
    TLS_LDFLAGS = -lssl -lcrypto
  endif
  TLS_IMPL = tls.c
else
  TLS_CFLAGS =
  TLS_LDFLAGS =
  TLS_IMPL =
endif

# Common runtime sources (runtime.c + event backend + TLS + optional AKS + Metal on darwin)
RUNTIME_SRCS = runtime.c ssmr_witness.c lexchar_tables.c $(EVENT_SRC) tls_stub.c $(TLS_IMPL) aks.c $(METAL_SRC)
RUNTIME_DEPS = runtime.c ssmr_witness.c runtime.h wvalue.h event_loop.h $(EVENT_SRC) tls_stub.c $(TLS_IMPL) aks.c $(METAL_SRC)
RUNTIME_CFLAGS = $(WARN_FLAGS) $(GC_CFLAGS) $(TLS_CFLAGS) $(ONIG_CFLAGS)
RUNTIME_LDFLAGS = $(GC_LDFLAGS) $(TLS_LDFLAGS) $(ONIG_LDFLAGS) $(PLATFORM_LDFLAGS)

# Usage: make compile SRC=path/to/file.ll
# Produces an executable next to the .ll file
compile: $(SRC:.ll=)

%: %.ll $(RUNTIME_DIR)runtime.c $(RUNTIME_DIR)$(EVENT_SRC) $(RUNTIME_DIR)tls_stub.c $(RUNTIME_DIR)aks.c $(if $(TLS_IMPL),$(RUNTIME_DIR)$(TLS_IMPL)) $(addprefix $(RUNTIME_DIR),$(METAL_SRC))
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_DIR)runtime.c $(RUNTIME_DIR)$(EVENT_SRC) $(RUNTIME_DIR)tls_stub.c $(if $(TLS_IMPL),$(RUNTIME_DIR)$(TLS_IMPL)) $(RUNTIME_DIR)aks.c $(addprefix $(RUNTIME_DIR),$(METAL_SRC)) $< $(RUNTIME_LDFLAGS) -o $@

# Build just the runtime object for linking
runtime.o: $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -c runtime.c -o runtime.o

# Build and run NaN-boxing tests
test: test_nanbox
	./test_nanbox

test_nanbox: test_nanbox.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) test_nanbox.c $(RUNTIME_LDFLAGS) -o test_nanbox

# Build and run benchmarks
bench: bench_wvalue
	./bench_wvalue

bench_wvalue: bench_wvalue.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_wvalue.c $(RUNTIME_LDFLAGS) -o bench_wvalue

bench-bigint: bench_bigint
	./bench_bigint

bench_bigint: bench_bigint.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) $(RUNTIME_CFLAGS) bench_bigint.c ssmr_witness.c $(EVENT_SRC) tls_stub.c $(TLS_IMPL) aks.c $(METAL_SRC) $(RUNTIME_LDFLAGS) -o bench_bigint

tune-bigint:
	../benchmarks/big_math/tune_bigint_thresholds.sh

# Build and run the slab AST arena micro-benchmark (EXP-1 perf lab)
bench-node: bench_node
	./bench_node

bench_node: bench_node.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_node.c $(RUNTIME_LDFLAGS) -o bench_node

# Build and run the packed source-location micro-benchmark (AST task #1).
# Self-contained: bench_location.c needs only wvalue.h's static inlines
# (W_PACKED_LOCATION is an immediate — no arena), so it links nothing.
bench-location: bench_location
	./bench_location

bench_location: bench_location.c wvalue.h
	$(CLANG) -O2 $(WARN_FLAGS) bench_location.c -o bench_location

bench-slab-init: bench_slab_init
	./bench_slab_init

bench_slab_init: bench_slab_init.c runtime.h wvalue.h event_loop.h
	$(CLANG) $(BENCH_FLAGS) $(WARN_FLAGS) $(ZSTD_CFLAGS) bench_slab_init.c -lz $(ZSTD_LDFLAGS) -o bench_slab_init

# Build and run "before" benchmarks (old 16-byte tagged union)
bench-before: bench_before
	./bench_before

bench_before: bench_before.c
	$(CLANG) -O2 bench_before.c -o bench_before

# Build and run HTTP request processing benchmark
bench-http: bench_http
	./bench_http

bench_http: bench_http.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_http.c $(RUNTIME_LDFLAGS) -o bench_http

# Build and run before/after HTTP comparison
bench-http-compare: bench_http_before bench_http
	@./bench_http_before
	@./bench_http

bench_http_before: bench_http_before.c
	$(CLANG) -O2 $(GC_CFLAGS) $(GC_LDFLAGS) bench_http_before.c -o bench_http_before

# Run both side by side
bench-compare: bench_before bench_wvalue
	@echo ""
	@./bench_before
	@./bench_wvalue
	@echo ""

# Phase 0: Goroutine arena validation
test-arena: tests/test_goroutine_arena
	./tests/test_goroutine_arena

tests/test_goroutine_arena: tests/test_goroutine_arena.c
	$(CLANG) -O2 $(WARN_FLAGS) $(GC_CFLAGS) $(GC_LDFLAGS) tests/test_goroutine_arena.c -o tests/test_goroutine_arena

# Phase 1: Thread primitives test
test-threads: tests/test_threads
	./tests/test_threads

tests/test_threads: tests/test_threads.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_threads.c $(RUNTIME_LDFLAGS) -o tests/test_threads

# Phase 2: Atomics stress test
test-atomics: tests/test_atomics
	./tests/test_atomics

tests/test_atomics: tests/test_atomics.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_atomics.c $(RUNTIME_LDFLAGS) -o tests/test_atomics

# Phase 3: Socket + FFI test
test-sockets: tests/test_sockets
	./tests/test_sockets

tests/test_sockets: tests/test_sockets.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_sockets.c $(RUNTIME_LDFLAGS) -o tests/test_sockets

# Phase 4: Goroutine + channel test
test-goroutines: tests/test_goroutines
	./tests/test_goroutines

tests/test_goroutines: tests/test_goroutines.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_goroutines.c $(RUNTIME_LDFLAGS) -o tests/test_goroutines

# Phase 6: Event loop + non-blocking I/O test
test-event-loop: tests/test_event_loop
	./tests/test_event_loop

tests/test_event_loop: tests/test_event_loop.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_event_loop.c $(RUNTIME_LDFLAGS) -o tests/test_event_loop

# Phase 7: Integration test (HTTP server + goroutines)
test-integration: tests/test_integration
	./tests/test_integration

tests/test_integration: tests/test_integration.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_integration.c $(RUNTIME_LDFLAGS) -o tests/test_integration

# Hash table regression tests
test-hash: tests/test_hash
	./tests/test_hash

tests/test_hash: tests/test_hash.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_hash.c $(RUNTIME_LDFLAGS) -o tests/test_hash

# String slab freeze regression tests
test-string-slab: tests/test_string_slab
	./tests/test_string_slab

tests/test_string_slab: tests/test_string_slab.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_string_slab.c $(RUNTIME_LDFLAGS) -o tests/test_string_slab

# Ivar lookup regression tests
test-ivars: tests/test_ivars
	./tests/test_ivars

tests/test_ivars: tests/test_ivars.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_ivars.c $(RUNTIME_LDFLAGS) -o tests/test_ivars

# AST node arena (PR #2 Phase 1) regression tests
test-node-arena: tests/test_node_arena
	./tests/test_node_arena

tests/test_node_arena: tests/test_node_arena.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_node_arena.c $(RUNTIME_LDFLAGS) -o tests/test_node_arena

# Run all tests
test-all: test test-arena test-threads test-atomics test-sockets test-goroutines test-event-loop test-integration test-hash test-string-slab test-ivars test-node-arena

clean:
	rm -f runtime.o test_nanbox bench_wvalue bench_bigint bench_node bench_location bench_slab_init bench_before bench_http bench_http_before
	rm -f tests/test_goroutine_arena tests/test_threads tests/test_atomics tests/test_sockets tests/test_goroutines tests/test_event_loop tests/test_integration tests/test_hash tests/test_string_slab tests/test_ivars tests/test_node_arena

.PHONY: compile clean test test-arena test-threads test-atomics test-sockets test-goroutines test-event-loop test-integration test-hash test-string-slab test-ivars test-node-arena test-all bench bench-bigint bench-node bench-location bench-slab-init bench-before bench-compare

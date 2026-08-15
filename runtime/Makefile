CLANG = clang
HOMEBREW_PREFIX := $(shell brew --prefix 2>/dev/null)
ZSTD_CFLAGS = $(shell pkg-config --cflags libzstd 2>/dev/null || { test -n "$(HOMEBREW_PREFIX)" && test -f "$(HOMEBREW_PREFIX)/include/zstd.h" && printf '%s\n' '-I$(HOMEBREW_PREFIX)/include'; })
ZSTD_LDFLAGS = $(shell pkg-config --libs libzstd 2>/dev/null || { if test -n "$(HOMEBREW_PREFIX)" && { test -f "$(HOMEBREW_PREFIX)/lib/libzstd.dylib" || test -f "$(HOMEBREW_PREFIX)/lib/libzstd.a"; }; then printf '%s\n' '-L$(HOMEBREW_PREFIX)/lib -lzstd'; else printf '%s\n' '-lzstd'; fi; })
ONIG_CFLAGS = $(shell pkg-config --cflags oniguruma 2>/dev/null || { test -n "$(HOMEBREW_PREFIX)" && test -f "$(HOMEBREW_PREFIX)/include/oniguruma.h" && printf '%s\n' '-I$(HOMEBREW_PREFIX)/include'; })
ONIG_LDFLAGS = $(shell pkg-config --libs oniguruma 2>/dev/null || { test -n "$(HOMEBREW_PREFIX)" && { test -f "$(HOMEBREW_PREFIX)/lib/libonig.dylib" || test -f "$(HOMEBREW_PREFIX)/lib/libonig.a"; } && printf '%s\n' '-L$(HOMEBREW_PREFIX)/lib -lonig'; })
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
    OPENSSL_PREFIX = $(shell brew --prefix openssl@3 2>/dev/null)
    TLS_CFLAGS = -DTUNGSTEN_TLS $(if $(OPENSSL_PREFIX),-I$(OPENSSL_PREFIX)/include)
    TLS_LDFLAGS = $(if $(OPENSSL_PREFIX),-L$(OPENSSL_PREFIX)/lib) -lssl -lcrypto
  else
    TLS_CFLAGS = -DTUNGSTEN_TLS
    TLS_LDFLAGS = -lssl -lcrypto
  endif
  TLS_IMPL = tls.c
else
  TLS_CFLAGS =
  TLS_LDFLAGS =
  TLS_IMPL = tls_stub.c
endif

# Common runtime sources (core + terminal input + event/TLS + optional companions)
RUNTIME_SRCS = runtime.c terminal_input.c ssmr_witness.c lexchar_tables.c $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC)
RUNTIME_DEPS = runtime.c terminal_input.c ssmr_witness.c runtime.h wvalue.h ast_schema_generated.h event_loop.h $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC)
RUNTIME_CFLAGS = $(WARN_FLAGS) $(GC_CFLAGS) $(TLS_CFLAGS) $(ONIG_CFLAGS)
RUNTIME_LDFLAGS = $(GC_LDFLAGS) $(TLS_LDFLAGS) $(ONIG_LDFLAGS) $(PLATFORM_LDFLAGS)

# Usage: make compile SRC=path/to/file.ll
# Produces an executable next to the .ll file
compile: $(SRC:.ll=)

%: %.ll $(RUNTIME_DIR)runtime.c $(RUNTIME_DIR)terminal_input.c $(RUNTIME_DIR)$(EVENT_SRC) $(RUNTIME_DIR)$(TLS_IMPL) $(RUNTIME_DIR)aks.c $(addprefix $(RUNTIME_DIR),$(METAL_SRC))
	$(CLANG) -O2 $(RUNTIME_CFLAGS) $(RUNTIME_DIR)runtime.c $(RUNTIME_DIR)terminal_input.c $(RUNTIME_DIR)$(EVENT_SRC) $(RUNTIME_DIR)$(TLS_IMPL) $(RUNTIME_DIR)aks.c $(addprefix $(RUNTIME_DIR),$(METAL_SRC)) $< $(RUNTIME_LDFLAGS) -o $@

# Build the split runtime objects for callers that do not use RUNTIME_SRCS.
runtime-objects: runtime.o terminal_input.o

runtime.o: $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -c runtime.c -o runtime.o

terminal_input.o: terminal_input.c runtime.h wvalue.h
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -c terminal_input.c -o terminal_input.o

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
	$(CLANG) $(BENCH_FLAGS) $(RUNTIME_CFLAGS) bench_bigint.c terminal_input.c ssmr_witness.c $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC) $(RUNTIME_LDFLAGS) -o bench_bigint

# Benchmark the Int#prime? trial-division/Montgomery-FJ cutoff. The source
# includes runtime.c directly so it can exercise the exact private tier helpers;
# link only the companion runtime translation units here.
bench-prime-sweep: bench_prime_sweep
	./bench_prime_sweep

bench_prime_sweep: ../benchmarks/primes/prime_sweep.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) $(RUNTIME_CFLAGS) ../benchmarks/primes/prime_sweep.c terminal_input.c ssmr_witness.c lexchar_tables.c $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC) $(RUNTIME_LDFLAGS) -o bench_prime_sweep

# Compare WArray capacity policies against the host allocator and probe
# whether moved/freed small buffers are immediately recycled by size class.
bench-array-growth: bench_array_growth
	./bench_array_growth

bench_array_growth: bench_array_growth.c
	$(CLANG) $(BENCH_FLAGS) $(WARN_FLAGS) bench_array_growth.c -o bench_array_growth

# Matched A/B using the production WArray path. The macros change only the
# growth threshold/policy; all other runtime/compiler flags stay identical.
bench-array-push-ab: bench_array_push_double bench_array_push_eighth_1k bench_array_push_eighth_4k bench_array_push_quarter_8k bench_array_push_quarter_16k bench_array_push_half_8k
	./bench_array_push_double "2x baseline"
	./bench_array_push_eighth_1k "2x < 1024, then 1.125x"
	./bench_array_push_eighth_4k "2x < 4096, then 1.125x"
	./bench_array_push_quarter_8k "2x < 8192, then 1.25x"
	./bench_array_push_quarter_16k "2x < 16384, then 1.25x"
	./bench_array_push_half_8k "2x < 8192, then 1.5x"

bench_array_push_double: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=0 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_double

bench_array_push_eighth_1k: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=1 -DW_ARRAY_QUARTER_GROWTH_THRESHOLD=1024 -DW_ARRAY_GROWTH_NUMERATOR=9 -DW_ARRAY_GROWTH_DENOMINATOR=8 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_eighth_1k

bench_array_push_eighth_4k: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=1 -DW_ARRAY_QUARTER_GROWTH_THRESHOLD=4096 -DW_ARRAY_GROWTH_NUMERATOR=9 -DW_ARRAY_GROWTH_DENOMINATOR=8 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_eighth_4k

bench_array_push_quarter_8k: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=1 -DW_ARRAY_QUARTER_GROWTH_THRESHOLD=8192 -DW_ARRAY_GROWTH_NUMERATOR=5 -DW_ARRAY_GROWTH_DENOMINATOR=4 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_quarter_8k

bench_array_push_quarter_16k: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=1 -DW_ARRAY_QUARTER_GROWTH_THRESHOLD=16384 -DW_ARRAY_GROWTH_NUMERATOR=5 -DW_ARRAY_GROWTH_DENOMINATOR=4 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_quarter_16k

bench_array_push_half_8k: bench_array_push.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) -DW_ARRAY_QUARTER_GROWTH=1 -DW_ARRAY_QUARTER_GROWTH_THRESHOLD=8192 -DW_ARRAY_GROWTH_NUMERATOR=3 -DW_ARRAY_GROWTH_DENOMINATOR=2 $(RUNTIME_CFLAGS) $(RUNTIME_SRCS) bench_array_push.c $(RUNTIME_LDFLAGS) -o bench_array_push_half_8k

# Matched same-binary A/B for runtime hot paths. The source includes
# runtime.c directly to reach private reference kernels, like bench_bigint.
bench-runtime-hotpaths: bench_runtime_hotpaths
	./bench_runtime_hotpaths

bench_runtime_hotpaths: bench_runtime_hotpaths.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) $(RUNTIME_CFLAGS) bench_runtime_hotpaths.c terminal_input.c ssmr_witness.c lexchar_tables.c $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC) $(RUNTIME_LDFLAGS) -o bench_runtime_hotpaths

# Compare today's dynamic slab/heap String construction with a hypothetical
# exact-seven-character printable-ASCII immediate encoding.
bench-string-encoding: bench_string_encoding
	./bench_string_encoding

bench_string_encoding: bench_string_encoding.c $(RUNTIME_DEPS) w_char_table.c
	$(CLANG) $(BENCH_FLAGS) $(RUNTIME_CFLAGS) bench_string_encoding.c terminal_input.c ssmr_witness.c lexchar_tables.c $(EVENT_SRC) $(TLS_IMPL) aks.c $(METAL_SRC) $(RUNTIME_LDFLAGS) -o bench_string_encoding

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

# Goroutine arena validation
test-arena: tests/test_goroutine_arena
	./tests/test_goroutine_arena

tests/test_goroutine_arena: tests/test_goroutine_arena.c
	$(CLANG) -O2 $(WARN_FLAGS) $(GC_CFLAGS) $(GC_LDFLAGS) tests/test_goroutine_arena.c -o tests/test_goroutine_arena

# Thread primitives test
test-threads: tests/test_threads
	./tests/test_threads

tests/test_threads: tests/test_threads.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_threads.c $(RUNTIME_LDFLAGS) -o tests/test_threads

# Atomics stress test
test-atomics: tests/test_atomics
	./tests/test_atomics

tests/test_atomics: tests/test_atomics.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_atomics.c $(RUNTIME_LDFLAGS) -o tests/test_atomics

# Socket + FFI test
test-sockets: tests/test_sockets
	./tests/test_sockets

tests/test_sockets: tests/test_sockets.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_sockets.c $(RUNTIME_LDFLAGS) -o tests/test_sockets

# Goroutine + channel test
test-goroutines: tests/test_goroutines
	./tests/test_goroutines

tests/test_goroutines: tests/test_goroutines.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_goroutines.c $(RUNTIME_LDFLAGS) -o tests/test_goroutines

# Event loop + non-blocking I/O test
test-event-loop: tests/test_event_loop
	./tests/test_event_loop

tests/test_event_loop: tests/test_event_loop.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_event_loop.c $(RUNTIME_LDFLAGS) -o tests/test_event_loop

# Integration test (HTTP server + goroutines)
test-integration: tests/test_integration
	./tests/test_integration

tests/test_integration: tests/test_integration.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_integration.c $(RUNTIME_LDFLAGS) -o tests/test_integration

# Hash table regression tests
test-hash: tests/test_hash
	./tests/test_hash

tests/test_hash: tests/test_hash.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_hash.c $(RUNTIME_LDFLAGS) -o tests/test_hash

test-hash-tombstone: tests/test_hash_tombstone
	./tests/test_hash_tombstone

tests/test_hash_tombstone: tests/test_hash_tombstone.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_hash_tombstone.c $(RUNTIME_LDFLAGS) -o tests/test_hash_tombstone

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

# AST node arena (PR #2) regression tests
test-node-arena: tests/test_node_arena
	./tests/test_node_arena

tests/test_node_arena: tests/test_node_arena.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_node_arena.c $(RUNTIME_LDFLAGS) -o tests/test_node_arena

# Exception cleanup / non-local block-return stack regression tests
test-exception-frames: tests/test_exception_frames
	./tests/test_exception_frames

tests/test_exception_frames: tests/test_exception_frames.c $(RUNTIME_DEPS)
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread $(RUNTIME_SRCS) tests/test_exception_frames.c $(RUNTIME_LDFLAGS) -o tests/test_exception_frames

# Run all tests
test-all: test test-arena test-threads test-atomics test-sockets test-goroutines test-event-loop test-integration test-hash test-hash-tombstone test-string-slab test-ivars test-node-arena test-exception-frames

clean:
	rm -f runtime.o terminal_input.o test_nanbox bench_wvalue bench_bigint bench_prime_sweep bench_array_growth bench_array_push_double bench_array_push_quarter bench_array_push_quarter_4k bench_array_push_eighth_1k bench_array_push_eighth_4k bench_array_push_quarter_8k bench_array_push_quarter_16k bench_array_push_half_8k bench_runtime_hotpaths bench_string_encoding bench_node bench_location bench_slab_init bench_before bench_http bench_http_before
	rm -f tests/test_goroutine_arena tests/test_threads tests/test_atomics tests/test_sockets tests/test_goroutines tests/test_event_loop tests/test_integration tests/test_hash tests/test_hash_tombstone tests/test_string_slab tests/test_ivars tests/test_node_arena tests/test_exception_frames

.PHONY: compile runtime-objects clean test test-arena test-threads test-atomics test-sockets test-goroutines test-event-loop test-integration test-hash test-hash-tombstone test-string-slab test-ivars test-node-arena test-exception-frames test-all bench bench-bigint bench-prime-sweep bench-array-growth bench-array-push-ab bench-runtime-hotpaths bench-string-encoding bench-node bench-location bench-slab-init bench-before bench-compare

ifeq ($(origin CC), default)
  CC := clang
endif
# Release CFLAGS tuned for end-to-end stage0+stage1 wallclock (the C VM
# is built once per --c-vm bootstrap and used to compile compiler/tungsten.w
# once). Re-benchmarked 2026-07-03 on the slab-AST workload (stage 1
# ~13s VM time; the old 4.3s-era table that picked -Os is obsolete):
#
#   -O2 no-LTO:      stage1-VM 12.0s   (winner)
#   -O3 no-LTO:      stage1-VM 12.1s
#   -Os no-LTO:      stage1-VM 13.1s   (prior winner, now ~8% slower)
#
# Emitted stage-1 .ll verified byte-identical across all three. The
# slab-AST dispatch path benefits from -O2's extra inlining more than
# the old hash-node workload did; i-cache pressure no longer dominates.
# LTO across translation units adds 200-400ms of compile time without
# speeding up the dispatch loop meaningfully — the dispatch is already
# in one TU. -DNDEBUG strips assert(); -march=native lets clang use the
# host's full instruction set for the bit-twiddling hot ops (kind tag
# tests, NaN-box decode).
# Host-ISA gate: -march=native miscompiles the bytecode-dispatch hot path on
# x86 Linux. A latent intra-struct OOB in the operand-stack fast path (UBSAN
# flags the L_ARITH fast path in vm.c: an out-of-bounds vm.stack[] index that
# aliases the struct's adjacent `ip` field) gets exploited by the host-ISA
# codegen and intermittently corrupts the VM, derailing stage-1 self-compilation
# (`unsupported runtime call: ... receiver=String ... fn=lower_*`, segfault, or
# hang). The C VM is a throwaway bootstrap tool, so on Linux build it for a
# portable baseline; macOS/arm64 — proven stable and green in CI — keeps
# -march=native.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  ARCH_FLAGS ?= -march=native -mtune=native
else
  ARCH_FLAGS ?= -mtune=generic
endif
# No -g: this binary is a throwaway stage0 host. Debug info bloated the image
# and did not pay for itself on the stage1 wallclock (measured 2026-07-10).
CFLAGS ?= -O2 $(ARCH_FLAGS) -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic
# -D_DEFAULT_SOURCE: with strict -std=c11, glibc hides every POSIX prototype
# (strdup, realpath, popen, …); implicit declarations truncate returned
# pointers to int on x86_64 and the VM segfaults at startup on Linux.
# Darwin ignores the macro.
CPPFLAGS ?= -Iinclude -I../../runtime -D_DEFAULT_SOURCE
BUILD_DIR ?= build
BIN := $(BUILD_DIR)/tungsten-c
SRC := $(wildcard src/*.c)
OBJ := $(SRC:src/%.c=$(BUILD_DIR)/%.o)
DEP := $(OBJ:.o=.d)

.PHONY: all bootstrap-lex bootstrap-parse bootstrap-tokens bootstrap-ast clean test

all: $(BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: src/%.c include/tc.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) $(OBJ) -o $@

-include $(DEP)

test: $(BIN)
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/smoke.w

bootstrap-lex: $(BIN)
	@for f in ../../compiler/tungsten.w ../../compiler/lib/*.w; do \
		printf '%s: ' "$$f"; \
		TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-lex "$$f" || exit 1; \
	done

bootstrap-tokens: $(BIN)
	@for f in ../../compiler/tungsten.w ../../compiler/lib/*.w; do \
		printf '%s: ' "$$f"; \
		TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-syntax-tokens "$$f" || exit 1; \
	done

bootstrap-parse: $(BIN)
	@for f in ../../compiler/tungsten.w ../../compiler/lib/*.w; do \
		printf '%s: ' "$$f"; \
		TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-parse "$$f" || exit 1; \
	done

bootstrap-ast: $(BIN)
	@for f in ../../compiler/tungsten.w ../../compiler/lib/*.w; do \
		printf '%s: ' "$$f"; \
		TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-ast "$$f" || exit 1; \
	done

clean:
	rm -rf $(BUILD_DIR)

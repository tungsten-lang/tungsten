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
# Host-ISA gate: -march=native exposed an operand-stack OOB in the x86 Linux
# bytecode-dispatch path. A pop to sp == 0 refreshed the TOS cache from
# vm.stack[sp - 1], aliasing the adjacent `ip` field and intermittently
# derailing stage-1 self-compilation. NEXT now skips that reload on an empty
# stack, but retain the portable Linux baseline until the sanitizer build and
# full stage-1 identity path have also passed on x86_64. macOS/arm64 — validated
# with the sanitizer and release builds — keeps -march=native.
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

$(BUILD_DIR)/lexer.o: include/unit_mixed_case_names.inc

# vm_call_body.inc is included twice by vm.c for the cached/non-cached call
# paths. The generic object rule cannot discover that dependency until vm.c is
# compiled, and older .d files did not list it, so an edited dispatch body
# could otherwise leave a stale stage-0 VM even under `tungsten build --force`.
$(BUILD_DIR)/vm.o: src/vm_call_body.inc

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) $(OBJ) -o $@

-include $(DEP)

test: $(BIN)
	@for spelling in camelCase _camelCase @camelCase @@camelCase '$$camelCase'; do \
		output="$$(TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --syntax-tokens-only -e "$$spelling = 1" 2>&1)"; rc=$$?; \
		if [ "$$rc" -eq 0 ]; then echo "$$spelling unexpectedly lexed" >&2; exit 1; fi; \
		printf '%s\n' "$$output" | grep -F "uppercase ASCII is not valid in identifiers: '$$spelling'" >/dev/null || exit 1; \
	done
	@TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --syntax-tokens-only -e 'eV mmHg kWh' >/dev/null
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/smoke.w
	@TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/exit_status.w; \
		status=$$?; \
		if [ "$$status" -ne 37 ]; then \
			echo "exit status regression: expected 37, got $$status" >&2; \
			exit 1; \
		fi
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/hash_delete.w | \
		diff -u tests/hash_delete.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/positional_arity.w | \
		diff -u tests/positional_arity.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/string_buffer_size.w | \
		diff -u tests/string_buffer_size.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/bit_count_intrinsics.w | \
		diff -u tests/bit_count_intrinsics.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/compound_assignment_ops.w | \
		diff -u tests/compound_assignment_ops.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/operand_stack_empty_transition.w | \
		diff -u tests/operand_stack_empty_transition.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-ast tests/parenthesized_type_hint.w
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --dump-ast tests/parenthesized_type_hint.w | \
		diff -u tests/parenthesized_type_hint.expected -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/parenthesized_type_hint.w | \
		diff -u tests/parenthesized_type_hint.output -
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) --check-ast tests/operator_method_name.w
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/embedded_ll_vector_const.w | \
		diff -u tests/embedded_ll_vector_const.expected -
	@test "$$(TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 \
		$(BIN) --dump-ast tests/embedded_ll_vector_const.w | grep -o ':node => :fn_def' | wc -l | tr -d ' ')" = 1
	@test "$$(TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 \
		$(BIN) --dump-ast tests/embedded_ll_vector_const.w | grep -o ':node => :method_def' | wc -l | tr -d ' ')" = 2
	@test "$$(TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 \
		$(BIN) --dump-ast tests/embedded_ll_vector_const.w | grep -o ':from_fn => true' | wc -l | tr -d ' ')" = 2
	@test "$$(TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 \
		$(BIN) --dump-ast tests/yield_ast.w | grep -o ':node => :yield' | wc -l | tr -d ' ')" = 3
	TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 $(BIN) tests/yield_ast.w
	cd ../.. && TUNGSTEN_LEX64_TABLE=languages/tungsten/tungsten.lex64 \
		implementations/c/build/tungsten-c implementations/c/tests/project_relative_use.w
	bash ../../scripts/test-bootstrap-stage1-artifact.sh

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

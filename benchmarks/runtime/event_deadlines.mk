# Extra makefile layered over a checkout's runtime/Makefile. Execute with
# -C CHECKOUT/runtime -f Makefile -f THIS_FILE so the matched harness compiles
# with that checkout's runtime source list and platform flags. The harness
# includes runtime.c itself. Driven by `make -C runtime bench-event-deadlines-build`.
.PHONY: event-deadlines-bench-exe
event-deadlines-bench-exe:
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread -I. "$(DEADLINE_BENCH_SOURCE)" $(filter-out runtime.c,$(RUNTIME_SRCS)) $(RUNTIME_LDFLAGS) -o "$(DEADLINE_BENCH_OUTPUT)"

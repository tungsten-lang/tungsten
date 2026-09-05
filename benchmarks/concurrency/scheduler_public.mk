# Extra makefile layered over runtime/Makefile. Execute with -C RUNTIME_DIR;
# runtime source lists and platform flags remain owned by that checkout.
.PHONY: scheduler-bench-exe
scheduler-bench-exe:
	$(CLANG) -O2 $(RUNTIME_CFLAGS) -pthread -I. $(RUNTIME_SRCS) "$(SCHED_BENCH_SOURCE)" $(RUNTIME_LDFLAGS) -o "$(SCHED_BENCH_OUTPUT)"

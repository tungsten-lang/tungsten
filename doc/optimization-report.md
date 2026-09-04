# Explaining lowering costs

`bin/tungsten --optimizations program.w` reports dynamic calls, guarded direct
calls, numeric fallback helpers, explicit floating-array conversions, and
selected allocation requests in the entry source. `--optimizations-json`
returns schema version 1 for editor tooling, suppressing verbose output.
Neither command links or executes the program.

The report inspects actual WIRE **before the mid-end and LLVM passes**. It is
not a profiler or a claim that a cost survives optimization. Guarded fallback
instructions are not evidence that the fallback runs. Allocation requests
may disappear. Measure the identified workload before changing its semantics.
Source positions are classified as an exact call location, the preceding
runtime location marker, or a function declaration fallback. The JSON keeps
that distinction; imported library sites are excluded.

Use `--tags` alongside this report for overload routing decisions. Future
backend optimization remarks and profile data should be separate evidence
fields, rather than inferred from this static report.

Focused verification: rebuild with `bin/tungsten build --no-bits`, then run
`python3 scripts/test-optimization-report.py` with the pre-change compiler
saved as `build/reports/compiler-baseline`.

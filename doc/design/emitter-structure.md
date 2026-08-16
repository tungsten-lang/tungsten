# LLVM emitter structure

`compiler/lib/emitter.w` is a thin import orchestrator. The implementation is
split by responsibility under `compiler/lib/emitter/`:

- `primitives.w` owns string slabs, runtime declarations, and small LLVM helper
  bodies;
- `analysis.w` owns declaration filtering, metadata, render-cache policy,
  call-site tables, and WIRE call-contract verification;
- `artifact.w` owns whole-module and per-function emission;
- `numeric_instructions.w` renders memory, arithmetic, vector, and conversion
  instructions;
- `runtime_instructions.w` renders constants, calls, control flow, ownership,
  and object operations; and
- `instructions.w` is the stable `render_instruction` entry point.

The two instruction workers deliberately preserve the existing case arms. The
dispatcher first asks the numeric family and uses the runtime/object family on
a miss. Unknown operations are still diagnosed by the final family. This keeps
the split mechanical: it does not change WIRE, LLVM spelling, declaration
selection, metadata numbering, or debug-frame policy.

Every worker is between 1,041 and 1,631 lines; the orchestrator is 18 lines.
That makes declaration analysis, module assembly, and opcode rendering
independent review and future parsed-file-cache boundaries without introducing
a code-generation partition or an LTO boundary.

## Validation and measurement

The split compiler reached an exact two-stage self-host fixed point (SHA-256
`c6e757081f8341940c9cd978f0e8fb8dc636cc84c7eace761c9a0d2ac653f4a8`).
Before/after emitters produced byte-identical release LLVM for the protected
Core fixture and the pure-Tungsten bignum program, and byte-identical debug LLVM
with `uwtable`, full frame pointers, `noinline`, and disabled tail calls.

Eight alternating artifact-only self-compile pairs used
`--release --native --fast --no-debug`. Median wall time was 3.945s before and
3.920s after (-0.63%; -1.02% by paired median). Compiler phase time was
3.3265s and 3.3100s (-0.50%); emission was 0.9010s and 0.8865s (-1.61%). These
small movements are treated as neutral. The retained result is a structural
boundary with no measured performance regression, not a speedup claim.

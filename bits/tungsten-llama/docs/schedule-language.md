# Schedule language design (P3.4)

Phase 3 deliverable from the plan: "Halide-style schedule primitives:
`.tile`, `.vectorize`, `.parallelize`, `.threadgroup`, `.unroll`,
`.split`. Same algorithm definition declares multiple named schedules.
Compiler pass transforms kernel IR per schedule before MSL emission.
Verify on Phase 2's Q8 matvec: one algorithm, three schedules, three
measurably-different MSL outputs + three measurably-different GPU
times."

## Core decision: imperative + axis tags, *not* full Halide

Halide-style separation requires the algorithm to be a pure expression
DAG (`block_acc[m, b] = sum_axis(:j, ...)`); the schedule then names
axes and decides how each is realized in hardware. That's the
textbook design but is a big departure from the imperative kernels
we already write — it's effectively a second sub-language.

Proposed alternative: **imperative kernels with explicit axis tags**.
The kernel body still reads as ordinary Tungsten code with named
loops; a separate `@schedule` block names how each tagged axis maps
to GPU hardware, and the compiler rewrites the imperative form
accordingly.

**Why this over full Halide:**

- Phase 2 already showed we can hand-write the cooperative imperative
  kernel in 50 lines. The schedule pass only needs to *generate* that
  imperative form from a default + transformations, not synthesize
  imperative loops from a pure DAG.
- Backwards compatible — existing `@gpu fn` files keep working as
  the `:default` schedule.
- The transformation patterns we need (`m → threadgroup`,
  `b → simdgroup_lane stride: 32`, `acc → simd_sum`) are local
  rewrites on the imperative IR. Pure-DAG → imperative would be a
  whole separate scheduling pass on top.

**Tradeoff accepted:** schedules can't restructure loops as freely
as Halide. We can rewrite axis bindings, loop bounds/strides, and
inject reductions, but we can't (initially) split a single loop into
two nested ones, fuse loops, or reorder. Those land if/when we need
them; the cooperative + tiled patterns are what Phase 5 uses.

## Proposed syntax

### Algorithm — the existing `@gpu fn` shape with axis tags

```tungsten
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = axis :m ## i32                 # tagged: schedulable
  nb = k_dim / 32 ## i32

  acc = 0.0 ## f32
  loop b in axis :b, 0..nb           # tagged loop
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32                     # untagged: stays sequential
      block_acc = block_acc + w_q[m * k_dim + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc

  y[m] = acc
```

Two new constructs:

- `axis :name` — declares a value bound to a schedulable axis. Default
  meaning: `gpu.thread_position_in_grid.<dim>` (one thread per axis
  index). The `:m` axis here would become `int m = int(__tid);` in
  the default-schedule MSL.
- `loop var in axis :name, range` — a loop over a tagged axis.
  Default: `for (int var = range.start; var < range.end; var++) { ... }`.

Untagged code (the `j` while loop above) is not schedulable — it's
emitted as written.

### Schedule — separate declarative block

```tungsten
@schedule q8_matvec.naive
  # Empty schedule = use defaults. Equivalent to the v0 baseline.

@schedule q8_matvec.packed
  # No reparallelization — just a buffer-layout swap. Lowers
  # `w_q ## i8[]` → `w_q ## i32[]` plus inline sign-extend.
  reshape :w_q, :i32_packed_q8

@schedule q8_matvec.cooperative
  # The v2 transformation: 1 threadgroup per output row, 32 threads
  # per row cooperating over the K reduction.
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc
  reshape :w_q, :i32_packed_q8
```

The compiler emits one MSL kernel per schedule, named
`q8_matvec_naive`, `q8_matvec_packed`, `q8_matvec_cooperative`.

### Schedule primitives (initial set)

| Primitive | What it does |
|-----------|--------------|
| `axis :a, parallelize: :thread` (default) | `int a = int(__tid)`; one thread per axis index |
| `axis :a, parallelize: :threadgroup` | `int a = int(__tg_id)`; one threadgroup per axis index |
| `axis :a, parallelize: :simdgroup_lane, stride: N` | `int a = lane; ...; a += N` rewriting the loop |
| `axis :a, reduce: :simd_sum, into: :acc` | After the loop: `acc = simd_sum(acc); if (lane == 0) ...` guards the writeback |
| `reshape :buf, :type_packed_q8` | Buffer becomes `i32[]`, reads inline-unpack as `((p << s) >> 24)` |

Future (not in v0): `tile`, `vectorize`, `unroll`, `split`, `fuse`,
`reorder`. These compose if/when we need them.

## Worked example: three schedules, three MSL outputs, three GPU times

The plan-required verification. From the same algorithm:

**`naive` schedule** → v0 baseline kernel from
`bits/tungsten-llama/lib/q8_matvec.w`. ~162 GB/s at lm_head.

**`packed` schedule** → v1 kernel from `q8_matvec_packed.w`. ~273 GB/s
at lm_head.

**`cooperative` schedule** → v2 kernel from `q8_matvec_coop.w`.
~285 GB/s at lm_head.

The scheduling pass is *correct* if the MSL byte-output for each
schedule is identical (modulo whitespace / variable names) to the
hand-written kernel. Three distinct MSL → three distinct measured
GB/s values demonstrates the schedule actually controls the
generated code.

## Implementation slices

Five-week budget. Suggested ordering:

**Slice 1 (week 1) — Algorithm parsing.** New AST node `:axis` (for
`m = axis :m`) and `:axis_loop` (for `loop b in axis :b, range`).
Parser changes only; no semantic effect yet. Default-schedule
emission produces the same MSL as today.

**Slice 2 (week 1) — Schedule parsing.** New AST node
`:schedule_def` keyed by `kernel_name.schedule_name`. Parser changes
only; lookup table populated, no transformation yet.

**Slice 3 (week 2) — `parallelize :threadgroup` transformation.**
Compiler pass that, given a kernel and a schedule, walks the kernel
AST and rewrites `axis :m` references from `__tid` to `__tg_id`.
Demo: `naive` and `tg_only` schedules produce two distinct MSL
outputs. End-to-end smoke that the dispatched kernel still
computes the right answer.

**Slice 4 (week 2-3) — `parallelize :simdgroup_lane stride:` +
`reduce :simd_sum`.** The two transformations needed for the
cooperative pattern. Apply both → MSL byte-equal to the hand-written
v2 kernel (modulo identifier names).

**Slice 5 (week 3-4) — `reshape :i32_packed_q8`.** Buffer-type swap
plus inline byte-unpack rewrite of the inner-loop array indexing.
This is the hardest one because it changes the kernel's *interface*
(buffer types) as well as its body. Apply with cooperative → matches
v2 perf numbers.

**Slice 6 (week 4-5) — Tooling.** `tungsten compile --schedule
<name>` flag picks one schedule for the .metal sidecar. Bench
harness loops over schedules, writes a CSV. The plan-required
verification table.

## Resolved design choices

1. **Algorithm form: imperative + axis annotations** (the proposal in
   the "Core decision" section above). Halide-style would have a
   higher long-term ceiling because of producer-consumer fusion
   (especially for attention kernels), but full fusion is multi-month
   compiler work — not realistic for a 5-week phase. Imperative+tags
   reaches llama.cpp parity *now* on Q8_0 matvec; if/when attention
   needs fusion, a Halide-style algorithm DAG can be added on top
   that lowers down to this same imperative+tags form. The tag-based
   IR is the lowered form Halide would target anyway.

2. **Axis-tag syntax: annotation form.** The kernel body uses
   `m = gpu.thread_position_in_grid.x ## axis :m` — extending the
   existing `## type` annotation with `## axis :name`. Examples
   throughout the doc updated to this form. No new keyword,
   no method-call collision; the parser only has to recognize a
   second form of `##`-trailing annotation.

3. **Schedule scope: top-level by name.** `@schedule kernel.variant`
   blocks at file scope, referring back to a previously-defined
   `@gpu fn` by name. Multiple schedules of the same kernel produce
   multiple emitted kernels (`q8_matvec_default`, `q8_matvec_coop`).
   Nested-under-kernel form is rejected — keeps the algorithm
   definition uncluttered.

4. **Buffer reshape: separate `@layout` block.** Layout transforms
   change the kernel's *interface* (buffer types) — that's a
   different kind of decision than how axes map to threads.
   `@layout kernel.variant` is its own block; a single emitted
   kernel can apply both a `@schedule` and a `@layout`. Example:

   ```
   @layout q8_matvec.packed_q8
     buffer :w_q, from: :i8[], to: :i32[], unpack: :sign_extend_per_byte

   @schedule q8_matvec.coop
     axis :m, parallelize: :threadgroup
     axis :b, parallelize: :simdgroup_lane, stride: 32
     axis :b, reduce: :simd_sum, into: :acc

   # The cooperative kernel from P3.3 = layout :packed_q8 + schedule :coop.
   @kernel q8_matvec.cooperative
     layout: :packed_q8
     schedule: :coop
   ```

5. **Verification: three distinct MSL + perf within 5%.** Plan says
   "three distinct MSL outputs + three distinct GPU times" — that's
   the floor. Adding a perf-match check (within 5% of the
   hand-written reference at lm_head) catches schedule bugs that
   produce *valid but slow* MSL. Byte-equality of MSL would be too
   brittle (variable names + register allocation differ).

## Annotation form, finalized

```tungsten
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## axis :m
  nb = k_dim / 32 ## i32
  acc = 0.0 ## f32
  b = 0 ## axis :b, i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32
      block_acc = block_acc + w_q[m * k_dim + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc

@layout q8_matvec.packed_q8
  buffer :w_q, from: :i8[], to: :i32[], unpack: :sign_extend_per_byte

@schedule q8_matvec.coop
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

@kernel q8_matvec.cooperative
  layout: :packed_q8
  schedule: :coop
```

The kernel body parses the same as today plus the `## axis :name`
extension. With no schedule/layout, the kernel emits as the v0
baseline (`m → __tid`, `b` is sequential). Each named `@kernel`
combines a layout and a schedule and emits one MSL output.

## Implementation slices (revised)

**Slice 1 (week 1) — `## axis :name` parser/AST.** Extend the type
annotation parser to recognize `## axis :name [, type]`. Store the
axis name in the AST node. Default-schedule emission is unchanged
(annotations are no-ops when no schedule applies). End state:
existing kernels keep working; can add axis tags freely.

**Slice 2 (week 1) — `@schedule` and `@layout` parser/AST.**
File-scope blocks. Each parses into a hash keyed by
`kernel_name.variant_name`. No transformation pass yet — just
populates a registry. End state: parsing is complete; lookup table
populated.

**Slice 3 (week 2) — `axis :m, parallelize: :threadgroup` pass.**
Walk the `@gpu fn` AST. For each axis tag matched by a schedule
entry, rewrite the binding expression
(`gpu.thread_position_in_grid.x` → `gpu.threadgroup_position_in_grid.x`).
Demo: same kernel, two named variants, two distinct .metal
outputs. Smoke-test that both produce the right answer.

**Slice 4 (week 2-3) — `simdgroup_lane stride:` + `reduce :simd_sum`.**
The two transformations needed for the cooperative pattern. Apply
both → MSL output that runs at the same perf as the hand-written v2
kernel.

**Slice 5 (week 3-4) — `@layout` buffer reshape pass.** Transform
buffer types (`i8[] → i32[]`) and rewrite indexing reads to use
inline byte unpack. The hardest one because it changes the kernel's
interface; needs to update `dispatch_n` callers as well as the
kernel body.

**Slice 6 (week 4-5) — Tooling.** `tungsten compile --kernel <name>`
flag to pick a named variant for the .metal sidecar. Bench harness
loops over registered variants, writes a CSV. The plan-required
verification: three named kernels of `q8_matvec` produce three
distinct MSL files and three distinct GB/s rows.

Starting slice 1 now.

# When LTO Refuses to Inline Across `-march=native`

A debugging story about an 18% performance regression that turned out to be
caused by a single missing function attribute in an LLVM IR emitter — and
how the fix was a 30-line probe, not a compiler change.

## The setup

A custom programming language emits LLVM IR text (`.ll` files) directly,
then hands them to clang for the final link step:

```bash
clang -O3 -flto -march=native -mtune=native bench.ll runtime.a -o bench
```

The `runtime.a` archive contains C functions compiled with the same flags.
Some of those C functions are NEON-vectorized hot loops that the language's
generated code calls into via `ccall`-style direct calls. The expectation:
LTO sees both modules as bitcode, the inliner folds the runtime helpers into
the language's hot paths, and the final binary has no function-call boundaries
in the inner loops.

The reality: the final binary had every runtime helper as a *separate
symbol*, with `bl` instructions in the language's hot loops calling out to
them. LTO was running but not inlining anything across the boundary.

## The first wrong theory: ccall overhead is just expensive

For a while we assumed the `bl` overhead (frame setup, argument marshalling
through registers, indirect jump, return) was an inherent cost of the
language calling into C. We tried micro-optimizations to reduce the *number*
of calls per second: hoisting work out of inner loops, batching multiple
operations into one call, etc. They helped a little. But the absolute throughput
ceiling stayed stubbornly below where simple per-cycle math said it should be.

The actual fix turned out to require none of that work. LTO was supposed to
make the calls free in the first place.

## Finding the smoking gun

LLVM's optimization remarks output is the single most useful debugging tool
for "why didn't optimization X happen?" questions. To get inliner remarks at
LTO link time:

```bash
clang -O3 -flto runtime.a bench.ll -o bench \
    -Wl,-mllvm,-pass-remarks-missed=inline
```

The output was hundreds of lines of inlining decisions, but two specific
remarks repeated for every helper:

```
ld: warning: LTO remark: 'w_lex32_scan_flag' not inlined
into '__w_lexer_main_loop' because it should never be inlined
(cost=never): conflicting attributes
```

`cost=never` means LLVM didn't even *consider* the cost — it refused
unconditionally. The reason was `conflicting attributes`.

## The actual cause: target-features mismatch

LLVM's inliner has a pre-check called `areInlineCompatible`. For each
`(caller, callee)` pair, it asks the target backend: "are these two functions
compatible enough to inline together?" The aarch64 backend implements this as:

```cpp
// From llvm/lib/Target/AArch64/AArch64TargetTransformInfo.cpp
bool areInlineCompatible(const Function *Caller, const Function *Callee) const {
  const auto &CallerBits = ...;
  const auto &CalleeBits = ...;
  // Inline a callee if its target-features are a subset of the caller's.
  return (CallerBits & CalleeBits) == CalleeBits;
}
```

The rule: **the caller's `target-features` must be a superset of the
callee's**. If the callee uses features the caller doesn't have, inlining is
unsound (the caller might run on a CPU that can't execute the callee's
intrinsics) so the inliner refuses with `cost=never`.

The mystery, then, is *what* features differed between the language's IR and
the C runtime's IR.

## What clang stamps on C functions

When clang compiles `runtime.c` with `-march=native` on an Apple Silicon
machine, it doesn't just generate native code — it stamps every function
with an LLVM attribute set that records exactly which target features the
backend is allowed to use for codegen:

```llvm
attributes #0 = {
  nounwind ssp memory(read) uwtable(sync)
  "frame-pointer"="non-leaf"
  "target-cpu"="apple-m1"
  "target-features"="+bf16,+bti,+ccidx,+complxnum,+crc,+dit,+dotprod,
                     +flagm,+fp-armv8,+i8mm,+jsconv,+lse,+neon,+pauth,
                     +predres,+ras,+rcpc,+rdm,+sb,+ssbs,+v8.1a,+v8.2a,
                     +v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8a,+zcm,+zcz"
  "tune-cpu"="apple-m3"
}
```

These attributes follow the function into bitcode and survive LTO. They
encode "this function was compiled assuming the CPU supports these features."

## What the custom IR emitter was stamping

The custom emitter — being a small handwritten thing focused on getting the
control flow and instruction selection right — wasn't stamping target
attributes at all. Every emitted function was just:

```llvm
define i64 @hot_loop(i64 %arg) nounwind {
  ...
}
```

Bare `nounwind`. No `target-cpu`. No `target-features`. From LLVM's
perspective, this function "doesn't claim any target features" — which the
inliner reads as "the caller has no features," which fails the superset
check against the C runtime's feature-rich set. **Inline blocked.**

## Why `-flto` on the link command line doesn't help

The natural reflex is to add `-march=native` to every clang invocation,
including the link step. We tried this. It didn't help.

The reason: **`-march=native` is a front-end directive**. It tells clang's
C compiler "when you lower C source to IR, stamp these target attributes on
each function." When clang is handed a pre-existing `.ll` file at link time,
it isn't running the C front-end — it's just passing the IR through to the
backend. The function attributes that already exist in the `.ll` are
preserved verbatim. There's no retroactive stamping.

This is a deliberate design choice in LLVM: target-features aren't compile
flags, they're *correctness invariants on the IR itself*. A function tagged
`+neon` is allowed to contain `@llvm.aarch64.neon.*` intrinsics that would
be illegal without the feature. If LLVM let you flip target-features via
command-line flags after the fact, you could silently promote a function
into an ISA it wasn't written for. So LLVM intentionally refuses to do this.

## The fix: probe clang at compile time

Since the caller's `target-features` must come from inside the IR — not from
the link command line — the IR emitter has to stamp them itself, with the
same set that clang's C front-end would stamp. The cleanest way to know what
that set is: **ask clang**.

Compile a one-line empty C probe through the same flags the runtime uses,
emit IR text, and grep the resulting `attributes #0` block:

```bash
echo 'void __probe(void){}' | \
  clang -O3 -march=native -mtune=native -S -emit-llvm -xc - -o - 2>/dev/null \
  | awk '/^attributes #0 / {
       for (i=1; i<=NF; i++)
         if ($i ~ /^"target-(cpu|features)"=/ || $i ~ /^"tune-cpu"=/)
           printf "%s ", $i
     }'
```

Output on Apple Silicon:

```
"target-cpu"="apple-m1" "target-features"="+bf16,+bti,..." "tune-cpu"="apple-m3"
```

This is exactly the attribute fragment that the IR emitter needs to stamp on
every function. The probe runs once per compile (~30 ms), parses the result,
and the emitter appends the fragment to every `define` line.

A simpler-looking variant — `clang -### -xc -c /dev/null` to print the cc1
invocation — does *not* work. The `-###` output shows the *driver-level*
target-features list, which is a strict subset of what cc1 then expands when
it walks the subtarget feature graph (e.g., `+v8.6a` implies `+v8.5a`,
`+v8.4a`, etc., and cc1 expands the closure). Probing through actual IR
generation captures the expanded set.

## After the fix

Stamping every function with the matching attribute set, **without changing
any other code**, restored LTO inlining across the language→runtime boundary.
The runtime helpers vanished from the symbol table (folded into their
callers) and the inner loops became straight-line NEON instead of `bl ...;
ret`. Single-thread throughput on the affected hot path jumped 18% in one
build.

## Why this matters beyond this one project

Custom LLVM IR emitters are getting more common — every JIT, every
non-clang front-end, every "we generate IR directly from a higher-level
representation" pipeline. The conventional wisdom is that LTO "just works"
across language boundaries as long as everything is bitcode. **It doesn't —
not unless every function carries target-feature attributes that survive the
inliner's compatibility check.**

If you're writing a custom emitter and your generated functions ever call
into clang-compiled C functions, you almost certainly have this bug. The
symptom is "everything looks inlinable but the inliner mysteriously doesn't."
The diagnosis is one `-pass-remarks-missed=inline` away. The fix is one
probe at compile time.

## Lessons

1. **`-Wl,-mllvm,-pass-remarks-missed=inline` is the first thing to try when
   inlining doesn't happen at LTO link time.** The LLVM inliner emits
   structured remarks for every decision. They tell you *exactly* why
   something wasn't inlined — `cost=...`, `conflicting attributes`,
   `not enough budget`, etc.

2. **Function-level `target-features` attributes are correctness invariants,
   not compile flags.** They live in the IR, not in command-line state.
   Custom IR emitters MUST stamp them. The inliner uses them to enforce
   "the caller can run any code the callee can run."

3. **`-march=native` on a clang command line only stamps attributes during
   *C-to-IR* translation.** When clang is consuming an existing `.ll`, the
   flag affects driver decisions but doesn't retroactively rewrite IR
   attributes. There's no clang flag that does this — by design.

4. **The detection mechanism is `clang -O3 -march=native -S -emit-llvm`** on
   a one-line probe file, then grep `attributes #0`. Not `clang -###`, which
   shows the driver-level subset. Not `cpuid` or `sysctl`, which show the
   hardware features but not the specific subset clang chooses to expand.
   The IR-level probe is the only thing that captures exactly what clang
   will stamp on real C functions.

5. **An IR emitter that doesn't stamp target attributes is opaque to LTO's
   inliner.** This is the kind of bug that doesn't show up in any test
   except a benchmark — and even then, only in the form of "we're slower
   than we should be" with no obvious culprit. The disassembly check is
   the ground truth.

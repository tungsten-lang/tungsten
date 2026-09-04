# Item 10: separate effects from memoization

Proposal, not implemented syntax. Keep `fn` behavior compatible in this branch.
Use the existing `##` annotation family for two independent declarations:

```w
-> square(x) (f64) f64 ## pure
  x * x

## memo(max_entries: 4096)
-> fib(n) ## pure
  n < 2 ? n : fib(n - 1) + fib(n - 2)

-> make_buffer(n) ## effects(fresh)
  f64[n]
```

`pure` means deterministic return values, no mutation visible to callers, no
clock/random/environment/I/O reads, no resource creation, and no unknown
foreign calls. Local temporary allocation is allowed if it cannot escape or
be observed. A fresh mutable result is a distinct `fresh` effect, not eligible
for memoization: two calls must not unexpectedly return the same buffer.
Throwing is tracked separately (`may_raise`); purity does not imply totality.
Version 1 caches successful results only, never exceptions.

Memoization requires checked purity, immutable keys with stable equality and
hashing, and an immutable shareable result. Identity-sensitive arguments,
mutable arrays, foreign pointers, fresh results, and dynamic calls without a
closed checked effect contract are rejected. Cache scope is process-local,
thread-safe, bounded by entries, with defined eviction. Cache statistics and
clear operations are tooling, not observable semantics available to pure code.
A result too large for the configured cache budget may be left uncached.

The compiler should infer effects as a conservative fixed point over call-graph
SCCs. Unknown dispatch/FFI starts effectful. FFI declarations own representation,
read/write/escape/fresh facts in one registry shared with ownership lowering.
User annotations are checked claims, not trusted shortcuts. A diagnostic shows
the first effectful call and its transitive path.

Implementation order:

1. Add the effect lattice and machine-readable report, with no optimizer use.
2. Audit Core and foreign contracts, especially constructors and device APIs.
3. Parse/check `## pure` and `## effects(...)`; cross-check interpreter/native.
4. Add separately bounded memo tables and explicit eligibility diagnostics.
5. Offer a migration tool translating legacy `fn` to explicit declarations;
   reserve removal of legacy behavior for a separately announced language edition.

Acceptance includes recursive effects, mutation through aliases, unknown FFI,
exceptions, concurrent cache access, eviction, and two fresh arrays remaining
independent. A pure scalar wrapper must have no memo lookup unless requested.

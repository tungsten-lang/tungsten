# Atomic / Channel / Thread source-wrapper revisit

Date: 2026-07-15

Status: **retained and integrated**. The full correctness/load-impact audit and
two independently rebuilt 10-observation timing campaigns passed. Production
retains exactly `Atomic#increment`, `Atomic#decrement`, `Channel#recv`, and
`Thread#alive?`; all other synchronization methods remain native.

Matched detached roots (same `f62869bff0fc22fdc0a3179c82fb5da158d987d6`):

- baseline: `/tmp/tungsten-sync-wrapper-baseline`
- candidate: `/tmp/tungsten-sync-wrapper-candidate`

## Static classification

| class | source candidates | retained native | reason for boundary |
|---|---|---|---|
| Atomic | `increment`, `decrement` | `cas`, `get`, `set`, `add` | the candidates are bounded and call unchanged atomic primitives directly; `cas` has hard-fatal missing-argument behavior, while the other retained names are too ubiquitous for sound autoload |
| Channel | `recv` | `send`, `close` | `recv` is a bounded synchronization selector; `send` has hard-fatal missing-argument behavior and `close` is ubiquitous |
| Thread | `alive?` | `join/0`, `join/1`, `kill` | `alive?` is a bounded predicate; `join` and `kill` are ubiquitous, and timed join also crosses a mixed WValue/raw-integer ABI |

This leaves exactly four source candidates and eight retained-native selectors
(nine method/overload controls). The candidate removes only the four
corresponding IC handlers and keeps every remaining table dense. Constructors,
storage, scheduler behavior, atomic
operations, cancellation, and channel algorithms remain in C.
The now-unused runtime method-name constants/interning for those four selectors
are removed as well, avoiding dead initialization work.

`Atomic#cas` and `Channel#send` were explicitly rejected as source candidates.
Although lower-arity source overloads can reproduce their messages and
unhandled exit status, source `raise` is catchable by `begin`/`rescue`; the old
IC wrappers call `die()` and hard-exit. Both wrappers, their IC rows, and their
method-name constants therefore remain native. No generic fatal primitive was
added merely to enable this migration.

## Atomic ordering parity

The source bodies call the same `w_atomic_*` primitives as the removed C
wrappers. Those primitives still use the default C11 operations
`atomic_load`, `atomic_store`, `atomic_fetch_add`, `atomic_fetch_sub`, and
`atomic_compare_exchange_strong`, hence sequential consistency is unchanged.
The runner pins these primitive expressions so a future memory-order change
cannot be mistaken for wrapper-only performance work.

## Rejected timed-join trial

An exact source spelling for `Thread#join(ms)` was explored. The historical C
wrapper passes `w_as_int(a[0])`, which is precisely a sign extension of the low
48 payload bits, not general numeric coercion. The semantically matching source
trial used `wvalue_bits`, `<< 16`, arithmetic `>> 16`, and then
`ccall_rawargs("w_thread_join_timeout", self, raw_ms)`.

That trial was rejected from the production candidate. A `join` method-name
gate would autoload Thread for unrelated user APIs, while opaque Thread values
cannot be covered solely by receiver inference. The native wrapper therefore
remains the exact specification for timeout coercion, surplus-argument
selection, and error behavior. `join/0`, `join/1`, and `kill` remain in the
benchmark workload only as unchanged-native controls.

## Autoload and interpreter routing

The loader has narrow unresolved-selector gates only for:

- `increment` and `decrement` -> Atomic
- `recv` -> Channel
- `alive?` -> Thread

It deliberately has no synchronization gate for `cas`, `get`, `set`, `add`,
`send`, `close`, `join`, or `kill`. Exact result provenance additionally maps
`w_atomic_new`, `w_chan_new`, `w_thread_spawn`, and `w_thread_spawn_slots` to
their source facades. Atomic, Channel, and Thread each have their own unresolved
flag, so one class does not drag in the other two.

Public `type()` / `.class_name` behavior is byte-for-byte unchanged: native
Atomic, Channel, and Thread handles continue to report `Unknown`. A hidden,
numeric `w_sync_handle_kind_support` boundary distinguishes only those three
kinds for the compiler tree walker and factory audit. The tree walker
allowlists the required lower primitives and constructors, routes the four
migrated candidates through source methods, and retains direct fallbacks for
the eight native selectors through the unchanged runtime method dispatcher. A
synchronous fake Thread model exercises source `alive?` without claiming
concurrent interpreter semantics.

The integrated interpreter calls the private discriminator only when public
`type()` is `Unknown`; known native classes continue directly to their existing
`w_type_name` fallback. This removes needless support calls without changing
the isolated runtime benchmark path.

## Prepared evidence

- `sync_wrapper_revisit_public.w`: use-free public workload with opaque native
  fixtures; independently times the four candidates and can diagnose all nine
  retained method/overload controls with `ONLY=...`.
- `sync_wrapper_revisit_ref.c`: neutral reference functions, lifecycle helpers,
  live/dead Thread fixtures, per-thread CPU time, and unchanged primitives.
- `sync_wrapper_revisit_interpreter.w`: native Atomic/Channel result routing and
  fake Thread routing through the tree walker.
- `sync_wrapper_revisit_exact_factory.w`: proves exact native-result autoload
  and private handle discrimination without mentioning any public
  synchronization selector, while pinning public `.class_name` to `Unknown`.
- `sync_wrapper_revisit_load_probe_{atomic,channel,thread}.w`: isolates each
  narrow selector gate on unrelated user objects.
- `sync_wrapper_revisit_load_probe_factories.w`: isolates the combined cost
  of exact native-result provenance without public selector calls.
- `sync_wrapper_revisit_load_probe_retained.w`: proves all eight retained
  selectors load no synchronization facade.
- `sync_wrapper_revisit_load_probe.w`: measures the combined false-positive
  cost.
- `run_sync_wrapper_revisit.sh`: exact static delta audit; WIRE/LLVM routing;
  value, mutation, missing/surplus-argument, and trailing-block parity;
  interpreter and exact-factory checks; fresh-cache compiler wall-time and
  application/compiler binary-size probes; balanced four-leg method samples;
  a prefilled Channel that keeps sends outside the `recv` timing window; and a
  fixed `candidate / baseline <= 1.10` gate.

Successful trailing-block strata cover Integer-returning methods. Fatal parity
modes cover Bool and nil results, pinning the remaining implicit-result-`each`
behavior without folding block work into method-body timing.

## Timing ledger

Ratios are candidate/source divided by matched native baseline using thread CPU
inside the neutral harness. Every retained method is below the fixed 1.10 gate
in both independently rebuilt campaigns.

| method | first | repeat | decision |
|---|---:|---:|---|
| `Atomic#increment` | 1.00461 | 0.996906 | retain |
| `Atomic#decrement` | 1.00227 | 1.00141 | retain |
| `Channel#recv` | 0.974415 | 0.976986 | retain |
| `Thread#alive?` | 0.920427 | 0.918999 | retain |

The worst fresh-cache compiler/load ratio was 1.0122 and the rebuilt compiler
binary-size ratio was 1.00006. Exact raw observations are archived in the
`first_results` and `repeat_results` files beside this audit.

Reproduction:

```sh
STATIC_ONLY=0 CHECK_ONLY=1 BOOTSTRAP_COMPILER=/absolute/bin/tungsten \
  benchmarks/runtime_ports/run_sync_wrapper_revisit.sh
STATIC_ONLY=0 CHECK_ONLY=0 REPEAT=0 BOOTSTRAP_COMPILER=/absolute/bin/tungsten \
  benchmarks/runtime_ports/run_sync_wrapper_revisit.sh
STATIC_ONLY=0 CHECK_ONLY=0 REPEAT=1 BOOTSTRAP_COMPILER=/absolute/bin/tungsten \
  benchmarks/runtime_ports/run_sync_wrapper_revisit.sh
```

## Syntax wishlist (not implemented)

No language syntax changed. Three additions would make this boundary clearer:

- typed foreign-function declarations that can state `(WValue, i64) -> WValue`
  instead of spelling mixed calls with `ccall_rawargs`;
- an explicit native-result annotation for opaque factories, allowing autoload
  provenance to live beside the foreign declaration instead of in loader name
  tables;
- distinct syntax for passing a block into a method versus applying a trailing
  block to the method's result; the current signature-dependent interpretation
  makes nil/Bool failure behavior surprisingly implicit.

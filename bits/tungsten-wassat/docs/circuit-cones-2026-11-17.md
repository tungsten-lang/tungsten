# Comparison-circuit cone specialist: research status

The native library in `lib/circuit_cones.w`, `circuit_cone_sim.w`,
`circuit_cone_refine.w` and `circuit_cone_search.w` now runs beside ordinary
final search in the CLI's plain DRAT mode and alongside the fast portfolio.
It has refuted the original SC2025
`b17` and `b18` instances with independently checked RUP proofs. The source
requires experimental `WASSAT_CIRCUIT_CONES=1` to admit the worker. Automatic
admission was suspended after measuring cumulative local-query memory growth;
the base scratch estimate does not qualify total RSS. Sequential, hinted and dual-proof modes use their existing
routes. The installed Wassat executable
has not been replaced by this work.

## The mathematical structure

The recognizer checks every original clause, deriving dimensions rather than
looking up a filename or benchmark hash. It accepts complete, topologically
ordered AND definitions, followed by comparison gadgets and a reduction tree.
For each compared signal pair `p,q`, the gadget contains:

```
a => p & ~q
b => ~p & q
c | a | b
```

Proving `p=q` therefore justifies original-variable units `~a`, `~b`, and `c`.
Once every comparison is proved equal, the checked reduction tree conflicts
with the original negative root assertion by unit propagation. Unsupported
layouts and incomplete proofs fall through without a formula verdict.

Bit-parallel simulation only proposes equivalences, including complements.
For each proposal, a compact cone is extracted from the checked circuit and
previously proved aliases. Native Wassat checks both mismatch directions under
assumptions. Its RUP additions are lifted back to original variable identifiers;
deletion hints are omitted. An alias is installed only after both directions
refute. The final result includes a complete original-CNF DRAT text containing
only RUP additions. Ordinary RAT proofs of a weakened formula cannot simply be
reused after restoring the final assertion.

## Evidence

The experiment directory is `build/sc2025-resume-20261117/case146/`.

* `b18`: 167755 variables, 473169 clauses, 3357 primary inputs, 151047 AND
  gates and 3338 comparisons. The autonomous baseline resolved every output
  in 16.48 seconds with 640025 conflicts. Forward RUP-only checking against
  the original CNF and a separate hinted LSR replay both accepted the proof.
  `native-autonomous-result.json` records source, executable and proof hashes.
* Held-out `b19_1`: the same recognizer accepts 6666 inputs, 295879 gates and
  6657 comparisons. At two million conflicts the baseline leaves 556 output
  comparisons unresolved, with no complete proof or accepted verdict.
* `spec/circuit_cones_spec.w` covers malformed layouts, compact variable maps,
  signed alias composition, exhausted budgets, SAT inputs, original proof
  replay, raw simulation parity and rare separating assignments.

These are bounded local experiments, not a whole-corpus speed claim.

## Query profiling and rejected hypotheses

Optional aggregate query diagnostics distinguish capacity declines, cancellation,
malformed cones, proved equivalences, SAT separations and exhausted queries. They
also separate extraction, solver construction, first/second assumption queries
and proof lifting. The ordinary search allocates no diagnostic array and reads
no per-query clocks. Stage snapshots copy their counters so later queries cannot
change earlier measurements.

An instrumented `b19_1` run at the same two-million-conflict budget finished
UNKNOWN in 59.04 seconds, with 556 unresolved comparisons and 109544 queries.
There were **zero capacity declines**; the largest compact cone had 8243
variables, below the 16384 limit. Cumulative query time was 8.62 seconds for
extraction, 12.63 for construction, 34.53 for the first assumption query, 2.83
for the second, and 0.26 for proof lifting. This rules out capacity as the cause
in this run. Counters include assumptions as decisions and conflicts; their
zero-decision/zero-conflict totals do not establish whether a cheaper unit
propagation precheck would help. `query-profile-result.json` records the source,
executable and complete stage counters.

Two subsequent bounded experiments were insufficient for default use:

* Exact four-input cut nominations yielded 24807 rewrites in 1.77 seconds.
  Native Wassat proved all 24774 nonconstant nominations in another 1.59 seconds.
  Seeding these before the ordinary sweep reduced unresolved comparisons from
  556 to 549 at the same two-million-conflict allowance. This small improvement
  does not justify adopting the external nomination pipeline.
* Simulation skips constant-looking signals. Of 30404 such `b19_1` nominations,
  native queries with a 16-conflict allowance proved only 90 constants, found
  28325 SAT separations and left 1989 inconclusive. This added 5.92 seconds and
  the whole run reached the 60-second deadline before final accounting. The
  reported 6657 unresolved field was the initialized total, not a measured
  residual. The constant proof prefix independently passed original-CNF forward
  RUP-only checking (`s VALID`, no empty clause). Constant nominations remain
  outside default search.

The optional constant table accepts only previously proved signed units, cuts
their fan-in during extraction, and includes those units in the compact formula.
False proposals, exhausted queries and cancellation publish no unit or formula
verdict. The default path, with no table, still produces the byte-identical
independently certified `b18` proof (16.39-second instrumented observation).
These timings are local observations, not controlled universal speed ratios.

There are now 43 semantic examples passing compiled and interpreted, plus seven
native lifecycle/accounting examples. Experimental retention of local output
solvers across UNKNOWN retries is opt-in through an internal checkpoint field;
it is not selected by CLI or fast portfolio defaults. Retained solvers keep
their original compact formula and complete proof prefix, and each retry charges
only its additional cumulative conflicts. Memory qualification is required
before any default activation.

Retained output solvers reduced `b18` from 640025 to 481806 conflicts in a
same-binary pair (17.20 versus 14.09 seconds). The new original-CNF proof
independently passed forward RUP-only checking, SHA256
`854bfe67a4da4a0b0c349b8c0d9e31531da1ffe8a385a82585228c6ed03e017f`.
On `b19_1`, retention leaves 547 comparisons unresolved at the same two-million
conflicts; that remains UNKNOWN. The retry option remains off by default.

A separate streamed refinement experiment uses one 128-conflict internal sweep
with a monotonically increasing original-gate cursor. After each validated batch,
it rebuilds nominations and resumes at the first future gate, avoiding the earlier
whole-sweep restarts. On `b19_1`, it proves 55338 internal aliases and leaves 543
comparisons unresolved at two million conflicts in 57.73 seconds. This is a
modest bounded improvement, not a solution or a default change. It also remains
an internal research option.

## Newly measured storage lifetime problem

On macOS, fresh-parent `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` measured
30.82GB for an uncached `b18` research run, including a binary built before retry
retention existed. The retained variant measured 29.94GB. Thus this growth
predates retention. With the input fixed, 4516 queries peak at 2.39GB and 7499
at 4.17GB; allocation counters and query-variable volume also grow. The streamed
`b19_1` run peaks at 67.30GB. These are process peaks, not cumulative allocation
counter totals.

The actual previously qualified default fast executable also peaks at 33.27GB
on `b18` while winning through comparison cones. Its planning function reports
only about 235MB of base scratch. The runtime has no GC, and its documented
instance/container release is shallow: private fields and nested clause arrays
can outlive each query. A bounded/reusable lifetime for that storage is therefore
required; more RAM or a larger scratch constant would not fix this cause.

The source now makes the worker explicit opt-in again, with a TODO at the
admission helper naming this lifetime problem. Earlier correctness/proof and
local timing evidence remains valid, but does not establish memory qualification.
The private fast candidate must not be installed as a default-enabled replacement
until this is addressed. The installed solver remains unchanged. Measurements
and source/result manifests are under `case146/*memory*`, `retry-result.json`
and `stream-b19-run.json`.

## Explicit private query ownership

Fresh compact clauses, solver fields, temporary results and private proof buffers
now belong to an explicit query lifetime. Retained UNKNOWN queries keep their
owner until retirement. Borrowed original formulas and shared stop/conflict cells
are excluded. Proof lifting detaches original-variable additions before disposal.
The decimal lifter avoids per-token strings and uses owned typed byte copies;
Array slices are borrowed views and cannot serve as disposable proof buffers.
The ordinary solver constructor still uses its existing allocation path.

Four native ownership examples, 43 semantic examples and seven native
cancellation/accounting examples pass with AddressSanitizer applied to both the
runtime and every emitted LLVM function. Two portable lifetime API examples
also pass compiled, interpreted and Ruby. Full Ruby cone tests remain unqualified
because of pre-existing clock and exception-matcher issues.

The final standalone b18 observation is 18.22 seconds, 464142336 peak RSS bytes,
52833 queries and 640025 conflicts. Its proof is byte-identical to the independently
checked original proof, SHA256
`109523433e7176fa5b62dc479dff94d74f12bc13b0a367cfee9244a546432428`.
The larger b19 observation also bounds peak RSS at 489766912 bytes after
109273 queries; it stops at 60 seconds and 1351533 conflicts, still UNKNOWN.
Its initialized residual field is not a measured residual after cancellation.
The fast diagnostic now labels whether that field was measured.
The pre-fix standalone peak was 30.82GB. A finite 500000-conflict fast run on the
new source peaks at 2.44GB for the entire portfolio versus 21.79GB for the old
candidate, with similar 16–17 second wall times. These are local observations.
The new worker advances further at that cap, but a full default fast attempt
still timed out at 60 seconds. Automatic admission remains off while phase
throughput is investigated; the installed executable remains unchanged.

Frozen generic controls verify 16 original-CNF SAT models and four independently
checked original UNSAT proofs. Six-family propagation comparisons preserve exact
search counters; mixed timing results do not support a general speed claim.
An explicit retained-query fast research plan wins the two-raw-plus-OTFS
portfolio in 24.23 seconds (23.91-second worker phase), using 481806 cone
conflicts and 1.355GB total peak RSS. Its complete original-CNF proof is
byte-identical to the retained proof above and freshly passes independent
forward RUP-only checking. Seven fast lifecycle/accounting examples pass,
including retained proof publication and disposal when an ordinary arm wins.
The earlier late-layout antibandwidth timing concern does not reproduce in
three fresh interleaved pairs: baseline median 657ms, candidate 660ms, with
identical search counters. This is focused evidence, not whole-suite timing
qualification. The full private CLI portfolio with retention and a 45-second phase finishes
b18 in 37.67 seconds at 3.000GB total peak RSS, with the same 481806 cone
conflicts and 52822 queries. Its one-million-cone-conflict allowance and
60-second external watchdog are unchanged. With a 30-second phase the worker
stops at 425028 conflicts and the CLI times out. This isolates the internal
phase cutoff as a remaining policy issue, not extra conflict-search capacity.
Retention remains an explicit research-plan option; production admission still
needs to reserve its retained-owner memory. The production factory remains at
30 seconds and automatic admission remains off. This is a private configuration
qualification, not an installed release or whole-corpus claim.

Detailed query timers can be enabled for fast research runs with
`WASSAT_CONE_PROFILE_QUERIES=1`; ordinary search does not allocate those counters.

## Counterexample-guided refinement

An optional mode retains the same initial 1024 random simulation patterns and
reserves another 1024 bits for local SAT counterexamples. Each compact model is
projected to primary inputs and evaluated through the original complete
network. Its queried signed signals must actually differ before it can split
a signature class. Missing inputs are false; an empty list is a valid all-false
assignment and differs from a missing counterexample. These samples never
become axioms or proof steps.

The first variant regressed `b18` from 16.48 to 36.10 seconds and timed out
during internal processing on `b19_1`, before output proof search. It remains
disabled. Stage profiling on `b18` found 122063 internal queries, including
47819 SAT separations, over the 2/16/128-conflict rounds. A subsequent search
filter caches exact canonical signed pairs already disproved by SAT, avoiding
repeated attempts after refinement slots fill. This cache cannot establish
an equality or an UNSAT result. It skips 28592 repeated queries on `b18` and
reduces refinement time to 30.32 seconds with a byte-identical independently
checked proof. That still loses to the 16.48-second baseline. On `b19_1` it
again exhausts 60 seconds before output search: the first two internal rounds
take 39.65 and 20.26 seconds. Neither refinement variant is selected by default.
At that checkpoint, 29 focused examples passed on both compiled and interpreted
engines. The simpler baseline is used for CLI integration below;
`b19_1` remains unsolved.

## Cancellation contract

The library now accepts an optional caller-owned atomic cancellation cell.
Circuit decoding, simulation, proposal rebuilding, cone extraction, proof
lifting and native assumption solvers all poll it. A local SAT or failed-core
UNSAT result does not publish to that cell. The caller must cancel the cell
at its wall deadline to interrupt an in-flight SAT query; clock checks alone
bound scans and work between queries. The DRAT coordinator in
`circuit_cone_parallel.w` now owns that lifecycle.

Four native lifecycle examples pass in addition to the 29 semantic examples
on both engines. They cover pre-cancelled work, private SAT/UNSAT assumption
results, live simulation cancellation and live cancellation of a complete
PHP(11,10) circuit query. Simulation and the query stopped within 2ms in the
first measurement; this is observed latency, not a hard platform guarantee.

## CLI coordinator and qualification

The cone worker gets a private cancellation cell, a 30-second phase window and
its own one-million-conflict ceiling. Ordinary search runs alongside it. A
specialist timeout cancels and joins only that worker; ordinary search retains
its state and continues. An ordinary answer cancels the specialist promptly.
Both workers share the existing atomic conflict ticket pool for finite public
`--conflicts` limits. Every new compact solver reuses the cone arm's contribution
slot, and already-spent tickets remain charged across successive queries.

Only complete original-formula results publish a winner. After joining both
workers, a cone win replaces the serial preprocessor/search prefix with its
own original-CNF proof in the reserved temporary output, then uses the usual
atomic publication. SAT and UNKNOWN remove the proof destination. The ordinary
solver retains its own certificate if it wins. Local assumption verdicts never
publish a global answer.

Six native coordinator examples verify ordinary SAT/model handling, a forced
specialist win with independent proof replay, pre-spent shared tickets, exact
1/7/31-conflict aggregate limits, timeout fallthrough and resumed serial search.
Three CLI examples cover file/stdout/dual proof output, stale-file cleanup,
explicit research activation, default fallthrough, aggregate caps and sequential mode.

One frozen-binary on/off pair on `b17`: 9.01 seconds without the worker and
5.25 seconds with it. Both original-CNF proofs independently check. On `b18`,
the baseline timed out at 40 seconds and the worker-enabled CLI solved in
19.43 seconds, with the original RUP proof independently checked. Earlier CLI
qualification solved it in 18.24 seconds. These are local measurements on a
shared host, not universal speed ratios.

Generated controls span pigeonhole, planted random 3-SAT, planted coloring,
contradictory parity and associative circuit miters, including SAT mutations.
All 54 alternating on/off runs produce checked original models or RUP proofs
(24 SAT models, 30 UNSAT proofs). Four larger SC2026 proof-mode controls time
out at 20 seconds on both settings; those censored runs do not establish a
performance improvement. Frozen source-build fast-route controls are separate
because a same-binary environment switch cannot measure code-layout effects.
Those frozen fast-route controls retain all eight original-CNF-checked SAT
models across antibandwidth, argumentation, xorshift and signed cubes. Single
pairs show ordinary shared-host timing variation (including a large reversal
on the argumentation instance), so they support retained behavior rather than
a general speed claim. The frozen trees differ only in `lib/wassat.w`;
all solver, policy and cube sources are identical in both builds.

## Fast portfolio

`circuit_cone_fast.w` adds a separate worker after the existing arms have been
planned. The existing raw, preprocessed, circuit and SLS slots remain intact.
Experimental admission checks structural shape, spare CPUs and base scratch
memory. It requires explicit opt-in until cumulative storage lifetime is fixed.
Explicit arm pins and sequential mode retain their existing execution width.

The cone worker performs boxed dispatch, so it must join before the ordinary
coordinator scores or reallocates arms. A checkpoint preserves the decoded
network, simulation proposals, proved aliases, proof prefix and cumulative
conflict charges. An interrupted local query is retried. Each round has a
private cancellation cell; a timed join cancels only the cone worker at its
phase deadline. This preserves the ordinary allocation policy rather than
disabling its barriers. Final gadget units are appended transactionally.

31 semantic examples pass compiled and interpreted, including byte-identical
proofs across one-query slices. Seven native fast-portfolio examples cover
checked publication, ordinary SAT models, exact finite ticket sums, unlimited
aggregate reporting, allocation barriers, deadline fallback and sequential
exclusion. A full `b18` run with active allocation completed across three
slices: 651904 cone conflicts and 52835 local queries. Its final proof is
byte-identical to the independently checked original-CNF baseline; the extra
11879 conflicts from interrupted queries remain charged.

The first default fast trial exposed a resource-planning bottleneck: a fixed
2.5 GiB ceiling declined this worker on a machine with 128 GiB RAM and 18 CPUs.
The shared planner now uses its existing one-third-of-physical-RAM budget
without that absolute ceiling, and the CLI reports the same value. Unknown
capacity still declines optional arenas. Three resource examples pass on both
engines, testing the same reservation on 8/128 GiB hosts and charging each
resident arena type. Five native domain-worker examples also pass after the
budget boundary update. This changes optional-arm admission on large hosts.

Unlimited race reporting previously omitted losing CDCL arms. It now includes
banked work from prior/retired rounds and each final telemetry delta, excluding
the scout continuation's offset. The real `b18` run reports 1921132 conflicts:
1280504 raw/preprocessed conflicts + 640025 cone conflicts + 603 earlier scout
conflicts. Finite limits continue to use the exact shared atomic ticket count.

Final frozen source-build fast controls differ only in `policy.w`,
`portfolio.w`, `wassat.w` and `circuit_cone_search.w`:

| Input | Baseline | Candidate |
| --- | ---: | ---: |
| `b17` | 8.07 s | 7.09 s |
| `b18` | timeout at 60 s | 23.70 s |
| `b18`, one comparison negated | 0.141 s | 0.141 s |
| `b18`, another comparison negated | 0.145 s | 0.141 s |

All twelve SAT models from six paired controls pass independent original-CNF
replay (including both 473169-clause mutations). Antibandwidth, argumentation,
xorshift and signed-cube controls retain their answers. Strong argumentation
timing variation and single pairs limit any wider speed claim. Both original
UNSAT inputs have independently checked RUP certificates. Evidence is in
`case146/fast-final-controls/` and `case146/fast-resumed-b18.*` under the
campaign build directory. `b19_1` and hinted-proof integration remain pending.

The selective cone queries and simulation/refinement approach are informed by
circuit equivalence checking and the circuit-native SAT research supplied by
the user. The native implementation does not copy unlicensed LymphoSAT
specialists, import an external solver, or embed instance-specific answers.

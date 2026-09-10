# Automatic native cleanup of wide composition outputs

The ordinary native composition path now applies shared-factor matrix
compression to each distinct verified output. This closes the specific
integration gap exposed by the [backtracking audit](NATIVE-FEEDBACK-BACKTRACKING-2026-09-10.md).
It reproduces the existing **19x27x28/r8129** witness from r8169, with full
native input/output tensor checks and independent replay. This is **not a
new bound or world record**: the retained bound already includes r8129 and
the saved external comparison remains r7983.

## Runtime behavior and limits

The new `composition/matrix_cleanup.w` operates directly on term-major
32-bit-limb arrays, up to the existing 1,024-bit factor / 16,384-term limits.
For each shared U, V or W factor, it factors the remaining binary matrix
using a deterministic column basis. Only strict rank decreases are accepted.
Axes 0,1,2 repeat until no rank decreases or the algebra budget is exhausted.
This is a tensor-preserving proposal operator, not an optimal-rank oracle.

Grouping keeps full factor equality, not just a hash bucket. Scratch columns
and echelon rows are initialized on demand. A 32-bit avalanche mixes high
coordinate bits into low bucket bits; without it sparse coordinate masks
produce long collision chains. Scratch and term capacities are validated
before access. No live CPU/GPU walker state, RNG, or flip counter is modified.

`ffbc_finish_task` first verifies and stores the original composition as
before. It then runs the bounded reduction in the same low-priority native
child. Any smaller result must pass a second full coefficient check before
publication to `composition/objects`, `best` and `by-shape`. The original
MFC/MFM result remains byte-for-byte unchanged; it is not rewritten to pretend
the recipe itself had the smaller rank. There is no Ruby/Python runtime
dependency and no additional worker.

`composition/cleanup/results/<source-id>` stores a canonical `MFW_CLEAN1`
record binding both identities, shape, input/proposed/admitted rank, status,
charged work, completed axes and reduction counts. Duplicate sources reuse
this record, but the cached output still undergoes strict parsing, digest,
shape/rank and full tensor checks. Missing/corrupt outputs fail closed.
Objects committed before an interrupted completion can be safely replayed.

Both algebra and exact verification retain a 20,000,000-work-unit limit.
The algebra budget charges matrix/hash work; bounded copies, sorting and
validation are separate. The verifier now skips XORs of zero W limbs, while
still comparing every coefficient in every fiber, including off-support zeros.
Its budget counts nonzero limb XORs, not CPU instructions or elapsed time.

Status is explicit:

- 1: this deterministic matrix operator reached a fixed point;
- 2: algebra stopped at its work limit; only completed group replacements
  are retained and checked, with unfinished groups copied intact;
- 3: the reduced proposal exceeded the verification limit; only the already
  verified original is retained, with no claimed rank saving.

The TUI names these states and status text exports `compose_wide_status` and
`compose_wide_saved`. These describe the latest attempt, not cumulative
discoveries. A limited attempt is not called complete cleanup; there is no
automatic unbounded retry. Previously completed archives are not silently
rescanned. Wide outputs remain indexed artifacts, not 63-bit live flip seeds.
Recursive wide basis changes, projections and composition feedback remain
future work; this change does not claim the entire offline campaign is native.

## Evidence

The independent Python row-equation oracle checks 96 randomized inputs over
31..1,024-bit vectors, each with unlimited and three bounded runs. The retained
16-construction corpus adds two runs per input: **416 runs total**, including
partial-budget tensor-preservation checks. Unlimited outputs match the oracle
exactly; all 16 corpus inputs also reach those outputs under the default
algebra budget. The corpus checks 48 complete input/output tensor identities.

All 16 inputs additionally pass the actual native post-construction admission
path and its independent full-tensor replay. For 19x27x28:

- input r8169; output r8129; 40 strict group reductions;
- final algebra work 7,722,319, versus 153,207,666 in the initial dense-scratch
  implementation; both unlimited runs produce identical terms;
- the earlier dense-limb verifier hit its 20M budget; skipping zero XORs
  admits both source and output without raising that budget;
- canonical `MFW1` result SHA-256:
  `63bcd57bef699e6d924a891cd1496dbde25d5303ad7e798046e2831bc2bc3865`.

The MFW digest differs from the earlier decimal snapshot solely because it
uses a different canonical serialization. The complete tensor terms match.
A five-trial, alternating-order CLI comparison on all 16 inputs measured
76.68 ms -> 63.14 ms median for the large regression, including process startup,
parse and output. Smaller cases are mixed/noisy; this is not a blanket speedup
or a live-fleet throughput result. Work-counter reduction is not a CPU-speedup
measurement. A separate full admission replay took about 155 ms on that input.

Focused gates also pass:

- packed limb boundaries, full identities, malformed canonical input and
  undersized source/scratch/status buffers;
- automatic 66->65 synthetic wide reduction, immutable originals, cached
  replay, stop, rehashed false tensors, and missing/corrupt cached witnesses;
- original pair/group composition queues, paged/legacy records, recipe
  corruption and crash recovery;
- all six mixed planner/domain versions, reservation/backpressure, deferred
  coordinator and scale-one substitution checks;
- native refinement replay and public executable tests on 5x5 and 2x5x6,
  including restart, same-shape seed feedback, disabled control, status/TUI
  fields and no surviving search child.

The brief one-CPU/no-GPU live checks retain 150 distinct narrow objects and
22 wide objects on 22 shapes. Independent full checks and comparison against
the latest 5,984-shape local closure find **no new bound**. These integration
objects are a separate cohort, not silently added to the prior 4,286-parent /
215,226-context flip study. Deferred disk tickets remain visible after the
bounded test ends; this is not a claim that those queues were exhausted.

Evidence is compressed outside the checkout at
`~/.local/share/tungsten-metaflip/evidence/2026-09-10-native-wide-refinement.tar.gz`.
The sealed archive is **19,797,139 bytes**, SHA-256
`0411943d3dc335715b34487d3615ee9167fe7e071a6a6f0c0ebce734fbddad9f`.
All 2,526 payloads (plus the manifest) were rehashed from the archive. It
contains source pins, native binaries, the small replay/checker closure, all
16 input/output witnesses, live probe artifacts and comparison reports.
The portable `cold_replay.py` independently repeats the 416 checks, 16 fresh
native admissions and retained live-output audit using only packaged paths;
that replay passes. The binaries were built with `--release --native` against
the local worktree compiler/runtime, not a separate clean compiler build;
the provenance records their hashes and the unchanged unrelated-work diff.
No canonical seeds, bulk benchmark corpus, GPU run, publication or world-record
claim is included. The package retains the pre-seal audit source to avoid a
circular digest.

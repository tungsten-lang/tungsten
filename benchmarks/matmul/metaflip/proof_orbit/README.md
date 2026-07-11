# Stabilizer-orbit lower-bound prototype

This note records the 2026-07-11 experiment against Chengu Wang's tensor-rank
lower-bound prover. It is a research prototype, not a new lower-bound
certificate. In particular, **it does not prove**
`R_F2(<3,3,3>) >= 21`.

## Source baseline

- Upstream: <https://github.com/wcgbg/tensor-rank-lower-bound>
- Tested `main`/`HEAD`: `efd22070269157e65aaf8d61a21da253a4000c61`
- Published 3x3 certificate SHA-256:
  `25595a883ce877eecd802139ff4e07646e154b2797ad6fe7f9ec737ab0c6135d`
- Published 3x3 BTP archive SHA-256:
  `4e824eb13c235e69045881d173d8ababe622421055a238005afce413aabe3289`
- Prototype source SHA-256 after the final probe:
  `2cb622a7223500ed0e1d1cf4c00a77eb96fa32c8bb2a003b1736dceec23a2219`

The prototype was kept out of this repository because it changes proof
traversal and is not yet a standalone certificate format. It added one
temporary binary, `search/stabilizer_orbit_prototype_main.cc`, plus a Bazel
target. The final experimental runner was 866 lines / 32,251 bytes, including
diagnostic hitting-set reporting and success-only legacy checkpointing.

## Why the obvious three-branch patch is unsound

At the unconstrained 3x3 root there are 511 nonzero binary 3x3 matrix forms,
but only three orbits under

```text
G = (GL(3,2) x GL(3,2)) semidirect C2,
|G| = 2 * 168 * 168 = 56,448.
```

The orbit representatives are packed matrices `1`, `10`, and `84`, of ranks
1, 2, and 3. Nevertheless, replacing the existing prover's 511 first choices
by those three representatives is not sound. Its recursive loop permits only
candidate indices less than or equal to the current index. A symmetry taking
one first choice to another generally does not take that numeric prefix to the
other prefix.

## Sound traversal

For a base constraint subspace `S`, let

```text
H_S = {g in G : g(S) = S}
C_S = nonzero projective forms in V/S.
```

Over F2, `C_S` is just the set of nonzero cosets. A search state is a multiset
of occurrences from `C_S`; multiplicities must be retained. A state is closed
when some submultiset `I` satisfies

```text
|I| + certified_lower_bound(S + span(I)) >= target.
```

This predicate is constant on `H_S`-orbits. It is also upward closed: every
extension of a closed multiset contains the same proving submultiset. A sound
search therefore proceeds one multiset size at a time, keeps one `H_S`-orbit
representative of each unclosed state, and expands it by every possible next
form. At depth `known_bound`, every state must be closed to prove
`known_bound + 1`.

This traversal directly encodes the same pigeonhole/substitution argument as
the legacy ordered DFS, without its non-invariant numeric-prefix state.

## Meet-in-the-middle orbit test

Explicitly canonicalizing every multiset under all 56,448 group elements was
correct but slow. The final prototype used the prover's Query/Store split.
Two multisets `M,N` are equivalent under `H_S` exactly when a query element
`q` and store element `s` satisfy

```text
RREF(q(S)) = RREF(s(S))
Normalize_q(S)(q(N)) = Normalize_s(S)(s(M))
```

as quotient multisets. Thus the layer deduper inserts the 168 Store keys of
each retained state and probes the 336 Query keys of each candidate. A hit
gives `q^-1 s` in `H_S`; coverage of `Query^-1 Store` gives the converse. This
works for nonzero `S` as well as the root.

The final implementation packed short transformed multisets into fixed-width
keys and used a flat hash table. Relative to the first explicit-group version,
this reduced the time to construct the active depth-four root frontier from
about 55 seconds to about 1.3 seconds.

## Equivalence and replay checks

The prototype emitted one deterministic record for every processed orbit
state. A nonzero mask is a substitution leaf with the normal Query/Store
witness. Mask zero says that the verifier must expand the state. An independent
replay path reconstructed every frontier, checked orbit coverage, recovered
the canonical constrained orbit from each witness, and checked the leaf bound.

| Problem | Increment | No symmetry | Stabilizer quotient | Replay |
|---|---:|---:|---:|---|
| 2x2 root | 6 -> 7 | 15 size-one cases / 16 records | 2 size-one cases / 3 records | pass |
| 2x2 constrained orbit 6 | 5 -> 6 | 20 processed states | 7 processed states | pass |
| 3x3 root | 19 -> 20 | 511 size-one cases / 512 records | 3 size-one cases / 4 records | pass |

The constrained 2x2 test is multi-level: its quotient frontiers were
`1,1,2,2,1`, versus `1,3,6,7,3` without symmetry. It checks more than the
trivial root transitivity case.

The downloaded full 2x2 certificate used for that test had SHA-256
`27b0dc70d76e64054e51705cb04c6b6658701a3dd8193962a65de1865e216a7d`.

## 3x3 target-21 probe

Using the published rank-20 certificate as the baseline, the active
symmetry-quotiented frontiers were:

| Multiset depth | Active states |
|---:|---:|
| 0 | 1 |
| 1 | 3 |
| 2 | 27 |
| 3 | 760 |
| 4 | 43,300 |
| 5 | 1,917,713 |

At depths through four, 44,091 states were processed. Of those, 34,501 closed
and 9,590 required expansion. The latter produced 4,900,490 raw children,
which reduced to 1,917,713 active depth-five orbits. Constructing the complete
depth-five frontier took 96.9 seconds and peaked at about 14.1 GB RSS on the
M5 Max host. The run was intentionally stopped before expanding depth five.
Its log SHA-256 was
`dd4a27944ff94645a6db4ddb349135ed34d1ba1534b02faac3948d6a427d84f5`.

This is a measurable reduction, but not yet a practical route to 21: the
active frontier grows by roughly 44x from depth four to depth five.

A leaf-only pass then tested all nonempty submultisets of every depth-five
state without constructing depth six. It closed 1,737,759 states and left
179,954; every survivor had best substitution score exactly 20, hence was one
certified rank point short. A greedy hitting set of constrained orbits covered
every survivor:

| Constrained orbit | Dimension | Requested increment | Newly covered states |
|---:|---:|---:|---:|
| 492 | 1 | 19 -> 20 | 172,338 |
| 493 | 1 | 19 -> 20 | 7,472 |
| 482 | 2 | 18 -> 19 | 144 |

Consequently, independently proving those three increments would make the
depth-five root argument a complete proof of rank at least 21. The profiling
log SHA-256 was
`e8d5eab5877cb268d9a43d7f52d0cd357de5e24b20a30312a0f4deb960a3a994`.

Using the separately verified checkpoint that already raises orbit 478 from
17 to 18, the dominant orbit-492 subproblem was profiled in the same way at
multiset depth four. Its 60,440 surviving states all had score 19. They are
covered by raising five dimension-two orbits from 18 to 19, in greedy order:
483, 481, 480, 482, and 478. Thus orbit 492 has a concrete dependency chain,
but it is not a single-child proof.

The tracked rank-23 scheme gives the following immediate projected upper
bounds after enumerating the 56,448 relative matrix symmetries. These do not
rule out any requested increment; in particular, successful 19 lower bounds
for 478 and 480 would be exact results.

| Orbit | Best projected upper bound |
|---:|---:|
| 478 | 19 |
| 480 | 19 |
| 481 | 20 |
| 482 | 21 |
| 483 | 20 |

### Direct orbit-478 symmetry traversal

Applying the sound multiset quotient directly to the strengthened orbit 478
(known 18, target 19) produced active frontiers
`1, 7, 83, 1,336, 27,469, 582,909` through depth five.  A leaf-only scan closed
187,356 of the depth-five states and left 395,553: 394,896 had best score 18
and 657 had best score 17.  Thus it did not prove 19, and depth six would still
require a large expansion.  The bounded run took 26.6 seconds, peaked at
3.31 GB RSS, and its log SHA-256 was
`1e5d71dec6f23e04c88696edfe4c2ef07af9133f8fa94278a62bcd3dc49c3d66`.
Orbit 480 was not expanded similarly because orbit 478 did not close.

## Targeted legacy searches

The earlier dimension-two campaign produced a verifier-accepted checkpoint
that raises orbit 478 from 17 to 18. Its certificate and BTP SHA-256 hashes are,
respectively,
`77f3fd0ad79d674621f0b0657aa0f2188018bda972044dbf67567226720c75d7`
and
`0df38f3daca792e8b5b30e7b1471ee2abe9f2606d7c943ca494cee5490ae568f`.

The temporary runner was then extended with an orbit selector and success-only
checkpointing. Three focused legacy DFS probes returned no proof:

| Orbit | Target | Step cap | Search time | Peak RSS | Result |
|---:|---:|---:|---:|---:|---|
| 478 | 18 -> 19 | 1,000,000,000 | 833.3 s | 33.9 GB | no proof |
| 480 | 18 -> 19 | 1,000,000,000 | 386.9 s | 35.5 GB | no proof |
| 492 | 19 -> 20 | 250,000,000 | 73.0 s | 11.6 GB | no proof |

A later selector-only `/tmp` patch tested the two previously untried root
dependencies without repeating those probes.  Official upstream `main` was
still exactly `efd22070269157e65aaf8d61a21da253a4000c61`; the trusted verifier
again accepted the published rank-20 certificate in 2.01 seconds.

| Orbit | Target | Step cap | Search time | Peak RSS | Result |
|---:|---:|---:|---:|---:|---|
| 493 | 19 -> 20 | 1,000,000,000 | 300.1 s | 36.1 GB | no proof |
| 482 | 18 -> 19 | 100,000,000 | 19.7 s | 5.36 GB | no proof |

The orbit-493 run first reproduced and verifier-checked the known orbit-478
17→18 prerequisite, byte-for-byte matching the checkpoint hashes above.  Both
new searches left that input certificate/BTP unchanged, so they are capped
negatives, not failed certificates and not impossibility results.  Simple
flatten/forced-product/degenerate passes recovered only 18 for orbit 493 and
17 for orbit 482.

The best next proof experiment is not a larger blind DFS.  Orbit 493 accounts
for 7,472 remaining root states, yet unlike orbit 492 it has no child dependency
profile.  A stabilizer-quotiented frontier/leaf pass for 493 should extract its
hitting set first.  Orbit 482 is the fallback because it has dual leverage: it
closes 144 root survivors directly and is one of orbit 492's five required
dimension-two children.

The three earlier 478/480/492 log SHA-256 hashes were
`27623b33af382ada9d36566a0dd355467748fb308e30a29598905c430f75c139`,
`034068dce495b1f194462789affc1b427d1b56230b1807289e33ed4d7aa897bc`,
and
`5fafc8199a5b3096c15db1bdd868024fd6aeb625e20bd971a1ca1be249213ed4`.
These are capped search failures, not upper bounds or impossibility results.
No output checkpoint was created because `returned_rank=0` and
`proof_size=0` in each case. Therefore the rigorous global 3x3 lower bound
remains 20; none of these targeted runs produced a new proof certificate.

The simpler root-wrapper route would prove 21 if all three dimension-one
matrix-rank orbits could first be raised from 19 to 20. It appears worse in the
current tables: the rank-one hyperplane alone had active frontiers
`1,6,103,3429,157124` through depth four and did not close in a bounded probe.

## Reproduction commands

After adding the temporary source and Bazel target to the upstream checkout,
the 3x3 binary was built and invoked as follows. The `-fno-lto` flags work
around an Apple `ld64.lld` stack-probing failure on the test host and should be
omitted where ordinary `--config=opt` links successfully.

```sh
bazel build --config=opt --copt=-fno-lto --linkopt=-fno-lto \
  '--per_file_copt=.*_main\.cc@-DCP_MATRIX,-DCP_P=2,-DCP_M=1,-DCP_N0=3,-DCP_N1=3,-DCP_N2=3' \
  //search:stabilizer_orbit_prototype_main

bazel-bin/search/stabilizer_orbit_prototype_main \
  certs/matrix/cert_matrix_q02_n333.pb.txt \
  --known_bound=19 --target=20 --use_symmetry=true

bazel-bin/search/stabilizer_orbit_prototype_main \
  certs/matrix/cert_matrix_q02_n333.pb.txt \
  --known_bound=20 --target=21 --use_symmetry=true \
  --max_states=44091 --max_seconds=300
```

## Certificate changes required before upstreaming

The experiment should not be merged into the trusted path unchanged:

1. Add an explicit backtracking traversal mode to `certificate.proto`, with
   proto3's default remaining the legacy DFS so published BTP files retain
   their meaning.
2. Teach the trusted verifier to reconstruct the multiset frontiers and the
   Query/Store orbit-dedup keys independently. The search implementation must
   remain outside the trust base.
3. Preserve the already-certified baseline bound. A `20 -> 21` multiset proof
   is conditional on rank at least 20, while the current oneof stores only the
   final proof. Either nest/reference the baseline proof or define a delta
   certificate pinned to the input certificate and BTP hashes above.
4. Treat `mask == 0` as an expansion record only in the new traversal mode;
   legacy backtracking leaves always have nonzero masks.
5. Add golden tests that compare unquotiented and quotiented frontiers for all
   small matrix orbits, plus mutation tests for multiplicity, base-image RREF,
   quotient normalization, and Query/Store witness direction.

Until those changes exist, this result is evidence for an optimization and a
map of the remaining search barrier—not a raised lower bound.

# Tungsten Wrat

An independent checker for UNSAT certificates. Give it a formula and a
refutation and it re-derives every step; a solver's "unsatisfiable" is a claim,
a checked proof is evidence.

Reads Tungsten-native hinted `.wrat`, packed `.wratb`, `.lrat`, and plain
`.drat` so it works with proofs from existing solvers. File verification is
streamed from a read-only mmap: the proof is never split into a retained tree
of lines, token strings, and step hashes.

## Installation

Add to your `Bitfile`:

```
bit "tungsten-wrat", "~> 0.0.1"
```

## Usage

```sh
wrat problem.cnf proof.wrat      # hinted (near-linear)
wrat problem.cnf proof.wratb     # same proof, packed varints
wrat problem.cnf proof.drat      # plain DRAT, from any solver
wrat pack proof.wrat proof.wratb # lossless hinted-proof packing
```

```
c format: wratb, steps checked: 6491
c storage: peak 8001 live clauses / 31422 live literals; record buffers 8 literals / 41 hints
s VERIFIED
```

Exit status is `0` for `s VERIFIED` and `1` for `s NOT VERIFIED`, so it drops
into CI directly.

As a library:

```tungsten
use wrat

result = wrat_verify(cnf_text, proof_text)
<< result["verified"]     # true / false
<< result["reason"]       # why it failed, when it did
<< result["format"]       # "wrat" | "lrat" | "drat"
```

## What it checks

Each added clause must be redundant with respect to the clauses already
accepted. Two tests are implemented:

- **RUP** (reverse unit propagation) — assume the negation of the clause and
  unit-propagate; the clause is redundant if that yields a conflict.
- **RAT** (resolution asymmetric tautology) — if RUP fails, every resolvent on
  the pivot literal must itself be RUP. This is what lets Wrat accept proofs
  containing preprocessing steps.

A proof is accepted only when it derives the empty clause.

## Formats

| format | shape | checking |
|---|---|---|
| `.wrat` | `wrat 1` header, then `<id> <lits> 0 <hints> 0` | near-linear — replays the hint chain |
| `.wratb` | `WRATB` magic, version byte, delta-coded varints | the same hinted replay without decimal/token overhead |
| `.lrat` | same body, no header | near-linear |
| `.drat` | `<lits> 0` / `d <lits> 0` | searches for the propagation; RAT fallback |

The dialect is detected automatically, so you rarely pass a flag.

WRATB preserves the logical records exactly. Addition ids are implicit and
sequential; signed literals use zigzag varints; clause references use zigzag
deltas from the preceding reference. A zero byte terminates each list. The
packer rejects a hinted proof whose addition ids are not sequential rather
than silently changing it. Text WRAT and LRAT remain the interchange and audit
formats; WRATB is the compact archival/replay format.

Hints are the whole point. Without them a checker must rediscover, for every
step, which clauses propagate — the expensive part of checking DRAT. With them
it replays exactly the sequence the solver named:

| proof steps | hinted | unhinted | speedup |
|---:|---:|---:|---:|
| 141 | 4 ms | 13 ms | 3× |
| 773 | 8.5 ms | 207 ms | 24× |
| 5264 | 46 ms | 10,210 ms | **220×** |

## Why it shares no code with the solver

A checker is only worth running if it can disagree with the thing it audits.
Wrat therefore duplicates the DIMACS parser rather than importing one from
`tungsten-wassat`: a shared parser bug could make both agree on a formula that
is not the one on disk. The duplication is deliberate, and so is keeping the
checking core small, heuristic-free and readable — it is meant to be audited by
a person, not just trusted.

The text and binary scanners live in `lib/stream.w`; `lib/checker.w` contains
the semantic RUP/RAT checker. The scanner retains only the current literal and
hint buffers. The checker also avoids DRAT content indexes and watched-literal
tables until an unhinted operation actually needs them. Deletions release their
literal arrays while retaining stable clause ids.

This already earned its keep. During development Wassat reported UNSAT on
PHP(4,3) with a proof that never reached the empty clause; Wrat rejected it and
exposed a real bug in the solver's proof logging.

## Correctness

The specs are built on well-known propositional cases and pair every positive
example with a negative one — a checker that accepts everything would pass all
the "verifies a real proof" tests and still be worthless. It rejects bogus empty
clauses, hint chains naming nonexistent clauses, chains that never conflict, and
non-redundant intermediate clauses.

```sh
tungsten spec/checker_spec.w
```

Wrat also verifies refutations produced by CaDiCaL, and agrees with `drat-trim`
on the proofs both can read.

## Measured memory and allocation work

The representative \(k=13,p=181\) hinted certificate has 149,751 additions,
709 deletions, and 5,262,789 peak live literals. On the reference 128-GiB
Apple host, native `/usr/bin/time -l` and Tungsten Flame measurements were:

| checker/input | proof bytes | wall time | maximum RSS | Flame allocation share |
|---|---:|---:|---:|---:|
| old whole-proof WRAT | 80,298,747 | 7.37 s | 7,008,878,592 B | 37.1% |
| streaming WRAT | 80,298,747 | 3.11 s | 234,242,048 B | — |
| streaming WRATB | 32,173,525 | 2.02 s | 186,089,472 B | 5.4% |

That is a 97.3% RSS reduction and a 59.9% certificate-size reduction for the
packed replay. The dominant bugs were not mathematical: the old path
materialized the whole proof, allocated a classification Hash for every
hint, replaced the assignment trail Array on every step, and built
DRAT-only indexes for hinted proofs.

The CLI storage comment reports logical database and record-buffer peaks.
Those are deterministic counters, not allocator-byte estimates. Tungsten
Flame remains the allocator-level profiler:

```sh
bin/tungsten flame -d 4 --top 20 --output /tmp/wrat.svg -- \
  wrat problem.cnf proof.wratb
```

Large research certificates are opt-in replays. The default suite uses small
proof identities and format round-trips; a replay whose expected footprint is
measured in tens of gigabytes must never become a standard regression test.
Keeping a durable witness is useful. Requiring every contributor or CI job to
materialize a 60-GB verification is not.

## Status

v0.0.2. The hinted path is the fast one. Unhinted DRAT uses persistent
two-watched-literal propagation plus RAT fallback, but remains less optimized
than `drat-trim` on large proofs. A future certified toolchain should emit LRAT
or WRAT hints directly; packing after production reduces storage, not the
producer's own peak memory.

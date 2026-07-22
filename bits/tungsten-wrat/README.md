# Tungsten Wrat

An independent checker for UNSAT certificates. Give it a formula and a
refutation and it re-derives every step; a solver's "unsatisfiable" is a claim,
a checked proof is evidence.

Reads Tungsten-native hinted `.wrat`, plus `.lrat` and plain `.drat` so it works
with proofs from existing solvers.

## Installation

Add to your `Bitfile`:

```
bit "tungsten-wrat", "~> 0.0.1"
```

## Usage

```sh
wrat problem.cnf proof.wrat      # hinted (near-linear)
wrat problem.cnf proof.drat      # plain DRAT, from any solver
```

```
c format: wrat, steps checked: 6491
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
| `.lrat` | same body, no header | near-linear |
| `.drat` | `<lits> 0` / `d <lits> 0` | searches for the propagation; RAT fallback |

The dialect is detected automatically, so you rarely pass a flag.

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

## Status

v0.0.1. The hinted path is the fast one; the unhinted DRAT path is a correct
reference implementation using full propagation rather than watched literals, so
it is slower than `drat-trim` on large unhinted proofs. Emitting `.lrat` for
verified toolchains such as `cake_lpr` is the natural next step.

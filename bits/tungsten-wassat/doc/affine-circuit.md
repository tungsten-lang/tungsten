# Affine constraints in model-only circuits

`affine_circuit.w` recovers a small primary input space inside a much larger
Boolean arithmetic circuit. Local XOR constraints over affine gate expressions
become equations over GF(2). Gaussian elimination reduces the independent
choices; the remaining choices are simulated in batches of 64. A surviving
candidate must satisfy **every original clause** before the worker publishes SAT.
The worker never publishes UNSAT, including when elimination is inconsistent or
all enumerated candidates fail. Unsupported encodings and all resource limits
fall through to ordinary solving.

This is useful for integer equations: their least significant bits already give
linear parity constraints, while carries and higher bits distinguish the few
remaining assignments. It does not require recovering or trusting integer
coefficients, a filename, an instance hash, or a saved assignment.

The common `model_circuit.w` decoder reconstructs bounded one-, two-, and
three-input truth tables in numerical topological order. The partition heuristic
uses the same decoder and retains its original bounds. Affine expressions use a
60-variable bit mask plus a constant bit; unknown nonlinear gates stay unknown.
Each added parity relation requires its complete forbidden-tuple clauses from
the original input. Other clauses are enforced by the final packed replay.

Admission inspects only the bounded first clause, an all-negative contiguous
primary-input list. It allows at most 60 primary inputs, one million variables,
four million clauses, and sixteen million literals. Decoding permits at most
32 short clauses per output and 512 literals per clause. Enumeration admits at
most 12 free inputs. Clause work, gate evaluations and replayed clauses have
separate 64-million limits, with a five-second worker deadline and cancellation
checks throughout. All search buffers are fixed and reused across batches.
The memory reservation includes decoder scratch, search buffers and the result
slice, and charges already admitted solver arenas.

The scout runs this worker concurrently, with no grace wait. An interrupted
attempt can retry in an unused late circuit slot. Existing solver arms are
preserved. Proof modes and finite conflict budgets keep their existing paths.
`WASSAT_AFFINE_CIRCUIT=0` disables the feature;
`WASSAT_AFFINE_CIRCUIT_SCOUT=0` tests late admission alone.

`WASSAT_PROFILE=1` reports reconstructed gates, local truth-table attempts,
affine gates, rank, free inputs, candidate batches, gate evaluations, clause
visits, verified clauses, phase timings and stop reasons. Runtime allocation
counters are enabled separately with `TUNGSTEN_ALLOC_PROFILE=1` and
`TUNGSTEN_POOL_STATS=1`; release builds retain `--ast-stats` metadata.

The model API returns typed integer arrays for both success and an empty miss.
A TODO records a frozen-compiler issue in mixed ordinary/typed-array return
inference exposed by the standalone model printer; this change does not claim
to fix that compiler lowering bug.

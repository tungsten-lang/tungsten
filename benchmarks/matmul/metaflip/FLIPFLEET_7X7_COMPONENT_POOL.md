# 7x7 rectangular component pool

The native `flipfleet` 7x7 adaptive campaign reserves two real Metal children
inside logical GPU role 10:

- `rect-3x3x4`, seeded by `matmul_3x3x4_rank29_gf2.txt`;
- `rect-3x4x4`, seeded by `matmul_3x4x4_rank38_gf2.txt`.

They are enabled automatically only for `--tensor 7x7` with GPU enabled and
the default `--gpu-policy adaptive`. `--no-gpu`, `--gpu-policy single`, and all
other tensor sizes leave the component subfleet off.

## Lane accounting

The children do not increase `--gpu-walkers`. They occupy physical execution
slots 13 and 14 under the existing role-10 pool reserve; the three ordinary
pool-family children remain in slots 10 through 12. At the default 4,096 GPU
walkers, role 10 retains its 1,536-lane budget:

| Child set | Cold allocation |
|---|---:|
| 3x3x4 | 256 lanes |
| 3x4x4 | 256 lanes |
| Three rotating square pool families | 1,024 lanes total |

Each available component always retains at least one 32-lane quantum. After
that evidence floor, its share of the fixed component reserve follows its
propagated reward per occupied lane-100ms. With no useful evidence, the split
is equal. The ordinary pool water-fills the exact remainder, so all physical
allocations still sum to at most the role-10 reserve.

## Correctness and adoption

The checked-in 334/344 Metal bundles specialize capacity, threadgroup width,
and each factor's independent bit mask. Their host relays perform complete
rectangular reconstruction before writing a candidate. The coordinator then
reloads every output through `ffr_load_scheme_cap`, which performs another
exhaustive reconstruction gate.

Each component owns a distinct exact state, bounded archive, checkpoint,
reward/exposure history, failure counter, and retry clock. A component rank
drop receives three times the ordinary rank reward because the Sedoglavic
composition contains three copies of that rectangular leaf.

If a canonical component checkpoint is malformed or inexact, FlipFleet first
atomically renames it to `.corrupt.RUN_TAG`, preserving its bytes for diagnosis.
It then atomically writes the exact bundled component back to the canonical
name. Improvements therefore remain discoverable through the same canonical
path on every later restart.

After a component improvement, native FlipFleet:

1. atomically saves `flipfleet_3x3x4_best.txt` or
   `flipfleet_3x4x4_best.txt`;
2. recomposes the current rank-47 4x4 and both rectangular checkpoints with
   `ffsc_compose_files`;
3. exhaustively reloads the resulting 7x7 scheme through the square worker;
4. passes it through the normal fleet-best, timeline, bank-rebase, and durable
   checkpoint path.

A rectangular result is never installed directly as a square result.

The prior exact rank-250 7x7 scheme is retained as a real `near2` shoulder
when rank 248 is the frontier, preserving a distant variable-rank basin that
cannot be recovered by merely splitting the new composition.

## Health and display

The two entries appear as one fixed-width row beneath the ordinary GPU pool.
Active entries are bright; waiting entries are dim; missing seeds or bundles
show `unavailable`. Their labels contain allocation, component rank, archive
size, rank drops, propagated reward, fixed-width failure count, and composition
failure count without changing the table's column geometry. A child inside its
retry window says `retry`; a failed square recomposition is shown as `cfailN`.

A missing optional component does not mark the whole fleet `DEGRADED`; its
unused reserve returns to the ordinary pool. A runtime failure backs off only
that child. Both component threads participate in clean epoch barriers and
are joined, exact-gated, checkpointed, and recomposed during shutdown.

The pure-Tungsten `flipfleet_7x7_pool_test.w` covers lane conservation,
reward-biased component allocation, independent retry masking, composition
retry timing, logical role-10 context aggregation, fixed-width component rows,
and exact admission of the retained rank-250 shoulder.

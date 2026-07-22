# Adaptive rectangular CPU portfolio policy

`flipfleet_rect_portfolio_policy.w` is the pure-Tungsten allocator used by the
`flipfleet --rect` coordinator. It remains independent of I/O, worker state,
and rendering, so policy tests do not start campaigns or touch the TUI.

The current 13-shape default is ordered as `2x2x5`, `2x2x6`, `2x2x7`,
`2x2x8`, `2x2x9`, `4x5x7`, `3x4x6`, `4x5x6`, `4x4x6`, `4x4x5`,
`2x5x6`, `3x4x7`, and `3x5x6`. The adjacent two-wide ladder makes the
small-host rotating floor visit every explicit primitive frontier rather than
pinning a historical prefix. Its leverage units are, in that order,
`2500, 400, 1, 1, 800, 2043, 1679, 1683, 1106, 1411, 734, 1458, 1638`.

The two-wide values are mathematical-closure priorities rather than block
composition counts. In particular, `2x2x5` is the certified one-term gap and
`2x2x9` starts at the public rank-32 integer witness, so a rank-31 hit would
improve every supported field. Among the larger leaves, `4x5x7` and `4x5x6`
carry the largest audited impact; `3x4x6` is only four leverage units behind
`4x5x6` while using a much smaller rank/factor state. `4x4x5` has three
independently exact basins and 109 guaranteed saved-formula improvements,
which makes it a stronger immediate campaign than raw leverage alone implies.
`2x5x6` is the leading small-cross primitive and carries 734 downstream terms
(82 guaranteed saved plus 652 strict-audit terms).

The default grew from an earlier seven-shape composition tranche to nine
shapes, and then to thirteen when the full `2x2x5..9` primitive ladder was
made explicit. The historical matched one-core 100M-move audit that motivated
the larger-leaf replacements measured:

| shape | moves/s | audited leverage | leverage-weighted attempts/s |
|---|---:|---:|---:|
| `3x4x7` | 16.1M | 1,342 (then-current) | 21.6B |
| `3x5x6` | 14.1M | 1,277 (then-current) | 17.9B |
| `3x4x4` | 14.5M | 258 | 3.73B |
| `3x3x4` | 16.4M | 3 | 0.049B |

The replacements also win after multiplying accepted states per second by
leverage, so the decision is not an artifact of counting cheap rejected
attempts. The six-profile benchmark produced no rank drop, but did yield exact
same-rank density leaders for 347, 458, 466, and 468.

The admitted but non-default `4x6x7` and `5x6x7` profiles carry 2,002 and
1,579 units. The non-default 357/458/466/468 profiles carry
1,223/1,325/1,176/1,202 units. The tiny `2x3x4` and `2x4x5` campaigns are also admitted but
non-default. Neither occurs in the current materialized/audited local formula
set, so each receives only the minimum positive leverage score of one;
`2x3x4` was scientifically attractive as a rank-19 closure campaign; the
independently replayed quotient-rank proof has now established exact GF(2)
rank 20. It remains available for density and basin work but receives no
rank-drop priority. Callers may replace these values with a newer composition
audit without changing the policy.

## API

```text
ffrpp_fill_defaults(shapes, ready, gpu_capable, leverage) -> count

ffrpp_allocate(
  total_j, epoch,
  shapes, ready, gpu_capable,
  rank_drops, density_gains, leverage, exposure, failures,
  allocation, scores
) -> allocated

ffrpp_allocation_valid(total_j, ready, allocation, count) -> 0|1
ffrpp_report(epoch, shapes, ready, gpu_capable, allocation, scores) -> String
```

All statistic arrays are cumulative nonnegative integers. `exposure` should
use a consistent allocation quantum such as CPU-thread epochs or
thread-seconds. `density_gains` is the number of same-rank factor bits removed.
A caller should set `ready[i]=0` during a hard failure/backoff; historical
`failures` is only a soft score penalty. `gpu_capable` discounts CPU score by
one quarter because a separate GPU engine can provide coverage, but never
removes the CPU starvation floor.

When `total_j` is at least the number of ready shapes, every ready shape gets
one CPU worker. When it is smaller, `epoch` rotates the ready-only floor window
so a fixed array prefix cannot monopolize a small machine. Remaining workers
use deterministic D'Hondt allocation over bounded integer scores combining:

- static shape priority and supplied downstream leverage;
- exact rank drops per exposure;
- same-rank density gain per exposure;
- an underexposure exploration term;
- GPU coverage and failure discounts.

Thus any nonempty ready set conserves exactly `total_j`, unavailable shapes
receive zero, and repeated calls with identical inputs and epoch are identical.
The coordinator adds one conservation-preserving postcondition when Metal is
enabled: if a small-`J` floor chose only CPU-only shapes, one CPU host slot is
moved to a rotating GPU-capable shape so the independently allocated GPU lanes
do not sit idle. The policy's returned total is unchanged.

## Test

```sh
bin/tungsten -o /tmp/flipfleet-rect-portfolio-policy-test \
  benchmarks/matmul/metaflip/flipfleet_rect_portfolio_policy_test.w \
  --release --native --fast --lto
/tmp/flipfleet-rect-portfolio-policy-test
```

The regression covers default metadata, every `J=0..64`, hard readiness,
large- and small-fleet starvation floors, epoch rotation, rank/density
adaptation, exposure normalization, failure penalties, GPU coverage,
determinism, malformed input, and a 192-vCPU report.

# Parent renewal: exact candidates and corrected comparisons

The [retained audit](../../../benchmarks/matmul/metaflip/parent_renewal_audit_2026_09_07/README.md)
contains 38 independently verified GF(2) constructions. Eighteen beat the available
ranks in three checked reference sets; none is declared a confirmed world record.

Examples: 4×16×18=753, 8×12×32=1855, 14×28×32=6916, and 14×32×32=7740.
The known-parent shared-factor construction was reused with stronger leaf costs;
the production fleet and canonical archives were not changed.

The closure tool now accepts repeatable `--extra-basis-report PATH` arguments
alongside `--basis-report`. It fully verifies and pins every additional baseline
before comparing new candidates. This corrects a missed-comparator problem:
older retained witnesses 7×12×12=657, 12×12×15=1315, and 14×14×16=1881
were absent from the recent propagation basis. Their recovery is not a discovery.

The 7283-combination parent study also preserves term-distinct minimum-rank
variants. A single rank/density representative loses on 156 of its 203 improving
target formulas. This is bounded coverage evidence with unequal computation,
not a throughput comparison or a dominance theorem.

Source and map replay, comparison hashes, exact recipes, focused tests, remaining
unmaterialized formulas, and reproducible commands are in the audit. No new
canonical seed, commit, publication, or submission is implied.

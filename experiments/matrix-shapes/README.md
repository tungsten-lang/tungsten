# Shape checks and performance (item 18)

Mat2/3/4 constructors now reject storage with a length other than 4/9/16.
Checks occur once per construction, outside scalar arithmetic. They preserve
the existing element conversion and ownership behavior. Empty, short, long
and correct inputs were exercised through native programs.

The size hint `T[N]` currently normalizes to the typed-array family; it was
not an enforced constructor-length guarantee. This patch checks that boundary.
It does not prevent a caller resizing the publicly exposed `elements` later,
or introduce full dependent shape types. A complete invariant requires
fixed-length storage/borrows, followed by checks at dynamic operation boundaries
and compile-time elimination where dimensions are proved.

**Will it affect performance?** A dynamic check has a cost. Known sizes may be
optimized away, but that must be verified in emitted code; this change does
not claim zero overhead. `result.json` records six alternating pre/post binary
pairs per size for 50,000 fresh-result f64 additions, with identical fixture
source and release/no-LTO settings. These unreserved-host loop measurements
include allocation and arithmetic; small timing differences are inconclusive.

Reproduce at parent commit `0bf03804` with
`python3 scripts/test-matrix-shapes.py --capture`, then apply this constructor
change and run `python3 scripts/test-matrix-shapes.py`. Captured artifacts live
under `build/reports/matrix-shapes`. The separate item-17 result covers reusable
output, which doesn't reconstruct matrices in the hot loop.

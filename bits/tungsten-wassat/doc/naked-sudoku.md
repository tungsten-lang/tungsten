# Checked naked-single progress certificates

This fast-mode worker recognizes an order-encoded Sudoku construction problem:
choose the values at fixed clue positions so naked singles can make progress
for a prescribed number of stages, or finish the board earlier. It does not
assume that every formula mentioning Sudoku has these semantics. Variable
arithmetic only proposes a map; the original clauses must imply every rule
used below. Unsupported maps and failed checks return no answer.

The worker supports rank two and three, at most 64 stages, one million
variables, three million clauses and twelve million literals. Admission reads
at most eight prefix clauses and reserves memory and a spare CPU worker.
Like the existing bounded resource and roster workers, it charges every
resident arena and uses at most one third of RAM, capped at six GiB. The
index, checks and search run beside ordinary solving arms. The scout gives it
no grace wait. An interrupted attempt can retry in the full portfolio; a
completed miss or exhausted bound is not repeated. `WASSAT_NAKED_SUDOKU=0`
disables it. Proof modes retain CDCL because this certificate is not DRAT.

## What the clauses must establish

Each cell has an order-encoded value X (zero means unfilled), and Boolean
candidate variables Y for every digit. Clues have a nonzero initial value and
persist through all stages. Non-clues start unfilled. The checker verifies:

* Every order chain, all stage/value persistence implications, and the rule
  that a new positive placement requires the corresponding naked-single gate.
* A naked-single gate holds exactly when all other candidates for that cell
  were eliminated at the preceding stage; that gate forces its digit.
* Four elimination gates, for a different digit already in this cell, or the
  same digit in another cell of its row, column or box. Each gate is checked in
  both directions against the appropriate value predicates.
* A candidate remains exactly when none of those eliminations applies and the
  preceding candidate remains. Clue candidates persist from stage zero.
  Every cell at every stage has at least one candidate.
* Every required stage either changes a non-clue candidate or has filled all
  non-clues. This last condition is recovered from checked gated-XOR clauses
  and the completion implications, not inferred from the formula's label.

Only these necessary consequences of the original CNF are needed for a
refutation. Other clauses can further restrict assignments. The checker uses
exact clause equality, original binary implications, verified order chains,
and original covering clauses whose literals each imply the requested
predicate. Hash collisions are resolved by checking every distinct literal.
No assumption about an auxiliary variable's truth is taken from its number.
Flat buffers, offsets, widths and literal ranges are checked before indexing.

## Why the search bound refutes the transition system

Placements persist and candidate sets shrink. The checked elimination
biconditionals imply that a stage changing candidates needs at least one new
non-clue placement. A filled cell cannot change digit. Nonempty candidate
sets enforce consistency of all placements with their Sudoku peers.

Before the first non-clue placement, only clue digits can eliminate its
candidates. Thus a possible first naked single needs at least N-1 clue peers.
With no such cell and at least one unfilled cell, the first progress condition
is impossible. The search otherwise requires exactly one possible first cell
and exactly N-1 clue peers. Their digits must all differ. Digit symmetry of
the checked semantic system lets the search fix those peer digits to 1..N-1.
This is not a permutation of Boolean threshold literals in the original CNF.

The search branches on remaining clue values and repeatedly places naked
singles. It gives each unassigned clue peer credit for one additional digit.
If no unfilled non-clue cell can reach N-1 eliminated digits even with that
credit, no extension of the partial clue assignment can start further
progress. The branch can stop without assigning its remaining clues. This is
an upper bound: counting repeated or conflicting possible digits separately
can only weaken pruning.

Every consistent completion of the remaining clue assignment is represented
by the branching or by such a no-further-progress leaf. Forced clue digits
are safe because every valid extension must use them. Contradictory branches
cannot satisfy the checked transition system. The search tracks the maximum
number of non-clue placements across all explored closures. It may refute
only after exhaustion, with no full completion, and only when that maximum
is smaller than both the required stage count and the number of non-clues.
A completion, node/work cap, deadline, or cancellation yields no refutation.

The finite-stage bound matters: a clue layout that cannot complete Sudoku can
still satisfy a formula asking for only one progress stage. The focused tests
include precisely that SAT boundary and the adjacent two-stage UNSAT case.

## Resource and validation discipline

The clause index and search use fixed typed arrays. Recursive calls reuse
values, row/column/box masks and an undo trail; they allocate no search nodes.
The clause checker has a billion-operation cap, the search a million-node
cap, and the worker a ten-second deadline. Safe-point polls cover decoding,
index construction, implication scans and recursive search. Publication checks
cancellation again and uses the ordinary atomic portfolio result protocol.

Profile counters include phase, checked clauses/literals/queries, hash probes,
literal comparisons, binary and covering-clause visits, total work, polls,
stop reason, nodes, branches, propagation, progress prunes, maximum non-clue
placements, scratch reservation and elapsed time. The full CLI reports the
answer-to-join tail. Allocation and AST statistics come from the usual runtime
and compiler profiling flags.

`naked_sudoku_spec.w` checks semantic boundaries, missing obligations, malformed
flat buffers, hash collisions, deadlines, cancellation and the node cap. Its
independent small encoder uses different helper grouping from the competition
CNF. For memory-constrained tree-walking runs, use the standard spec sharding
variables with one example per process; the native suite runs in one process.

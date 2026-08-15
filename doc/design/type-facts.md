# Mid-end type facts

The compiler now preserves four facts that lowering previously approached but
did not model consistently.

## SCC return inference

Return inference builds the direct top-level call graph, condenses it into
strongly connected components, and visits callees before callers. A recursive
component iterates to convergence, bounded by the component size plus two.
Explicit returns and tail branches provide base-case evidence, so mutually
recursive functions can acquire a return type without depending on source
order. Ambiguous or conflicting evidence remains unknown.

The analysis is intentionally conservative. It does not resolve dynamic method
dispatch into call-graph edges and it does not guess through overloaded names.

## Final source methods

`@final -> method(...)` declares a normal instance method whose implementation
cannot be replaced in that class or a subclass. Lowering registers a direct
target for the method, allowing calls on exact and compatible source-class
facts to bypass the method inline cache. Reopening or overriding a final method
is a compile-time error.

`@final` does not imply private visibility. A separate access-control design is
still needed.

## Exact and compatible locals

Local source-class knowledge is represented as a fact with a class and a
certainty:

* a constructor result is `exact`;
* a source-class annotation and `self` are `compatible`;
* copying a local preserves its certainty;
* an unknown assignment clears the fact.

Both facts can call a final method directly. Non-final source-method fast paths
retain their runtime class guard and generic fallback.

This is a lowering fact, not yet a surface type or an SSA lattice. Control-flow
joins therefore remain conservative.

## Core ABI boundary

The parser records each definition's source path. Call-site parameter
observations are whole-program optimization hints, so definitions loaded from
the canonical `core/` tree never consume them. Core annotations and inferred
facts may influence callers; user call sites cannot specialize a core
function's calling convention.

This boundary is required before a lowered core prelude can be cached and
reused across unrelated programs.

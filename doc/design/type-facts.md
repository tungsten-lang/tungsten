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

## Developer-chosen closed world

Tungsten deliberately does not treat a library's `final` annotation as an
unbreakable language guarantee. A caller may intentionally replace library
behavior. Consequently such an annotation cannot soundly justify deleting
dynamic dispatch.

The executable owner can instead declare two process contracts:

```tungsten
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
```

Both are zero-argument, top-level entry-program declarations. A dependency is
rejected if it tries to impose either contract on its caller.

`PROTECT_THE_CORE!` checks the fully loaded source graph and rejects user
reopens or replacements of definitions owned by the canonical `core/` tree.
It is the provenance boundary required for a reusable lowered Core: user call
sites cannot change a Core ABI, and the program promises it did not patch the
implementation behind that ABI. By itself this is a checked source assertion;
pair it with the method-table lock to exclude later native registration too.

`LOCK_THE_DOORS!` must appear after every type and method definition. The AOT
startup registers that complete set and then irreversibly closes both instance
and static runtime method tables before user statements run. Any later native
or interpreted registration raises an error.

Once the doors are locked, a constructor-derived `exact` receiver whose only
write is a straight-line assignment dominating the call selects a permanent
method implementation. The same proof now covers a fresh constructor
expression and a chain of such local copies. Assignments nested in a branch or
loop remain guarded even when they are the binding's only lexical write; a
single write does not prove the assignment executes. Lowering emits a plain
direct call with no class guard, inline cache, method-name materialization, or
generic fallback.

`self` is a sound `compatible` fact rather than an unchecked source hint: the
runtime entered the method through the defining class or one of its subclasses.
Under the lock, lowering may call a `self` helper directly when every known
descendant resolves that selector and arity to the same plain worker. A known
subclass override keeps the guarded dynamic call. Other compatible facts and
reassigned exact facts also keep their guards; exact ivar facts do so until
definite initialization is modeled.

## Exact and compatible locals

Local source-class knowledge is represented as a fact with a class and a
certainty:

* a constructor result is `exact`;
* a source-class annotation and `self` are `compatible`;
* copying a local preserves its certainty;
* an unknown assignment clears the fact.

Before the method-table barrier, source-method fast paths retain their runtime
class guard and generic fallback. After it, exact facts can call directly;
compatible facts retain dynamic dispatch.

This is a lowering fact, not yet a surface type or an SSA lattice. Control-flow
joins therefore remain conservative.

## Core ABI boundary

The parser records source ownership for definitions and occurrence-local
top-level statements. With `PROTECT_THE_CORE!`, lowering partitions that stream
before registration: Core overload grouping and SCC return inference complete
before user declarations exist, then user inference may consume the frozen
Core results. Top-level Core bindings are always exported rather than letting a
user read decide whether Core emits a global mirror.

Call-site parameter observations are also directional. Core functions may
consume unanimous facts from Core call sites, recovering the same typed-array
and float fast paths available to user functions. User sites cannot contribute
to those observations or change a Core calling convention. Without the
protection contract, Core remains ineligible for call-site specialization.

After WIRE lowering, the compiler emits a deterministic Core ABI fingerprint
covering Core worker signatures, raw-return modes, class inheritance and ivar
layouts, exported globals, and the method-table contract. Programs with the
same loaded Core closure and contract therefore expose the same compatibility
key even when their user functions differ.

Some valid programs still require monolithic lowering. The WIRE report names a
fallback reason for user subclasses of Core classes, user-dependent Core
generic specializations, Core-global shadowing, missing provenance, and program
`constant_alias` declarations. These are cache restrictions, not language
restrictions. Fast/precise math, static-slab mode, build defines, and the method
lock are deterministic compatibility-key fields instead: each exact variant
may have its own reusable Core, but variants can never alias one another.

This boundary is required before a lowered core prelude can be cached and
reused across unrelated programs. It does not itself reuse WIRE yet; that is
the next incremental-lowering stage.

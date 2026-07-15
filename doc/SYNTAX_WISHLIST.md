# Syntax wishlist (not implemented)

This is a parking lot for language-surface ideas discovered while optimizing
the runtime and compiler. The optimization loop must not change Tungsten syntax;
items belong here until they can be considered as a separate language-design
project.

## Explicit nested block parameters

Nested iterator bodies currently lean on implicit names such as `item` and `i`.
They are concise for one block but become error-prone when blocks nest or a
method is copied between iterator forms. A compact, mandatory parameter form for
nested blocks would make capture and shadowing visible at the call site.

Iterator forms should likewise expose an index as an ordinary declared block
parameter. Compiler code currently depends on implicit or method-specific index
names, which makes capture analysis and mechanical refactoring needlessly
fragile.

## Exhaustive AST pattern matching

Compiler passes repeatedly ask for an AST kind and then fetch several named
fields. An exhaustive match form with field destructuring would make missing
kinds visible, remove duplicated `ast_kind`/`ast_get` chains, and give lowering
a direct route to efficient packed-node reads.

## Unambiguous overload sets

Several definitions with the same operator name can silently shadow one another
when one is untyped, and inherited overloads can conflict with concrete vector
or matrix overloads. It would be preferable for the declaration syntax to make
"add to this overload set" distinct from "replace this method", with ambiguity
reported at definition time.

Dispatch within such a set should select the most-specific compatible receiver
and parameter types. This is particularly important for numeric containers,
where `Matrix < Number` scalar operations and matrix-to-matrix operations can
otherwise shadow each other.

## Non-virtual internal methods

There is no declaration-level way to say that a helper is private to a class
and cannot be overridden. Calls such as `at_type?(...)` inside `Parser`
therefore use the same inline-cache dispatch as an open public method, even
though direct self-dispatch would be both safe and substantially cheaper.

A `private`/`final` (or otherwise explicitly non-virtual) method form should
let lowering emit a direct call while preserving ordinary open dispatch for
public methods. Hot parser helpers currently have to move to top-level
functions to obtain that code shape, which sacrifices encapsulation for
performance and makes access to instance state awkward. The lexer has the
same issue for its pure token-symbol mapping: `emit`/`emit_at` cannot request
a direct call while leaving the public compatibility method virtual.

## Exact and immutable local type facts

There is no surface distinction between “this binding is exactly an instance
of this source class” and “this value currently appears to have this class.”
Constructor-derived facts can therefore enable a guarded source-method fast
path, but ordinary reassignment and branch merging must retain a compatibility
fallback because the local is mutable and type tracking is conservative.

An immutable local declaration, or an explicit exact-class assertion distinct
from a coercing cast, would let lowering preserve the fact through SSA and use
a direct source-method call when the method is also final. Mutable declarations
should instead widen at control-flow joins, making the loss of exactness visible
rather than leaving it implicit in function-wide inference.

The surface should also distinguish a checked class assertion from an
unchecked optimizer promise. `## Class` is currently treated as a trusted
contract at some container-recovery boundaries; a wrong promise remains
semantically safe only because optimized dispatch retains a generic fallback,
but it can quietly lose performance. Separate spellings would make both the
runtime-check cost and the unsafe trust boundary explicit in review.

## Distinguish type parameters from value parameters

`Mat<T, M, N>` uses one scalar type parameter and two compile-time integer shape
parameters in the same generic argument list. Dedicated value-parameter syntax
would prevent `M` and `N` from being treated as ordinary type names and would
make specialization rules much clearer.

## Expression continuation

Long formulas cannot begin a continuation line with an operator, which forces
determinants and similar expressions onto one long line or into temporary
assignments. A visually explicit continuation form would improve mathematical
code without making whitespace ambiguous.

Continuation inside parentheses should also be unconditional and consistent;
indentation should not terminate an expression while a delimiter remains open.

## Clearer representation casts

`##` currently covers several jobs: numeric conversion, typed array annotation,
generic element coercion, and raw-machine intent. Separate surface forms for
value conversion, static type assertion, and representation reinterpretation
would make low-level core code easier to audit.

## Checked raw-integer boxing

Core code sometimes has a machine `i64` but must return Tungsten's exact
Integer representation: an immediate signed i48 when possible and a canonical
BigInt otherwise. Today an optimized source body must either call `w_int`
unconditionally or hand-spell NaN-box tag constants and the signed range
check. A first-class checked boxing operation—distinct from a reinterpret
cast—would expose that intent and let lowering inline the common i48 arm while
retaining the canonical overflow fallback.

## Explicit lexical resource lifetimes

`## recycle` currently asks lowering to infer a value's cleanup scope from CFG
structure. That works for straight-line code, but an inlined iterator body,
`break`/`next`, exception, or nonlocal block return can leave through several
different edges. The compiler must reconstruct lexical ownership after the AST
has already been expanded into sibling control-flow regions.

A declaration or block form that explicitly binds cleanup to a lexical region
would make the lifetime part of the program instead of an optimizer inference.
It should define exactly-once cleanup for normal fallthrough and every transfer,
while still allowing pool-backed allocation to lower without general-purpose
RAII objects or closures.

The eventual spelling should also be a real postfix annotation rather than a
line comment.  In a nested expression, today's `## recycle` consumes the rest
of the physical line, so closing parentheses must move to a surprising later
line.  That makes the lifetime boundary harder to read precisely where branch
and exception behavior matters most.  A structured annotation could also name
or delimit the intended region and give escape analysis something explicit to
reject when the pooled value is returned, stored, or captured past that region.

## Explicit call-arity compatibility

Runtime builtins historically ignore surplus arguments, while source overload
selection can depend on declaration order when exact arity is unavailable.
`Array#join` currently has to place its one-argument overload before its
zero-argument overload to preserve that behavior, and a default parameter is
not equivalent because explicit `nil` has different semantics. Definitions
should be able to state their surplus-argument policy explicitly, and overload
resolution should not encode compatibility behavior in source order.

## Unambiguous postfix rescue precedence

`result = expression rescue fallback` currently parses as a rescue around the
whole assignment.  If `expression` raises, `fallback` is evaluated but is not
assigned to `result`.  That is internally consistent, yet it is visually easy
to read as `result = (expression rescue fallback)`; even a compiler regression
probe made that mistaken assumption.

An explicit expression-level rescue form, or syntax that visibly delimits the
protected expression and its result, would remove the precedence trap.  Until
then, code that needs the fallback assigned should spell that assignment in the
fallback or use a structured `begin`/`rescue` block.

## Explicit low-level field views

Core implementations use magic-looking `$value`, `$size`, and `$field` names to
reach packed runtime layouts. A declared low-level view/access form would make
the unsafe boundary visible and allow the compiler to validate offsets and
boxing expectations more aggressively.

The same form should work symmetrically for an explicitly named receiver and
for stores. Today a view field can be read from another object, but assignment
targets only admit the implicit-self `$field` spelling. That forced an
otherwise source-level `Array#join` buffer reset through a tiny C storage
helper. A checked spelling such as an explicit unsafe/view block would let core
code say “store this raw `i64` field on this `StringBuffer`” without making
ordinary object fields or assignments less safe.

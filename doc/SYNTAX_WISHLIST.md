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

Numeric result types also need to distinguish an exact machine integer from a
boxed `Integer` union that may be either an immediate value or a heap BigInt.
For example, `to_i` is mathematically integral but is not proof that its result
can be NaN-unboxed: BigInt identity preserves the heap object. A surface type
for this representation union, carried precisely through assignments and CFG
joins, would prevent optimization facts from silently becoming layout claims.

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

## Direct method aliases

Core APIs often expose two names for the same leaf operation, such as String
`size` and `length`. Expressing one body as `length -> size()` adds a second
virtual lookup and can measurably change a method that previously shared one C
handler; copying the body preserves speed but lets the aliases drift apart.

A declaration-level alias should install a second name for the same resolved
implementation and arity contract without generating a forwarding call. It
should say explicitly whether later overriding of the original name also
changes the alias, and it should compose with inherited overload sets. This is
only a design wish; no alias syntax has been added.

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

Native layouts should also be able to declare their C offsets and hidden
headers explicitly. Generic runtime objects currently rely on compiler-owned
knowledge that a discriminator byte precedes the source-visible view, while
the declaration hand-spells alignment padding. An offset-checked layout would
make that contract local, reject drift against the runtime struct, and avoid
using synthetic fields merely to reach the next real field.

Flexible-array tails need an equally explicit view. `BigInt` predicates only
need `limbs[0]`, but source currently represents that word as an ordinary
`u64 limb0` field at the known tail offset. A checked flexible-tail declaration
and indexed raw access would state the real C layout, distinguish logical
length from allocated capacity, and let the compiler prove that a zero-length
short circuit dominates the first-element load.

## Explicit native method declarations

A bodyless method in a runtime-backed class currently doubles as documentation
and an implicit request to fall through to a C dispatch entry. That meaning is
not visible in the declaration, and the interpreter must special-case classes
whose source-backed and native methods share one method table.

An explicit `native`/`extern` method declaration should name or bind the
runtime implementation and state its arity. Removing a native implementation
would then be mechanically checkable, and compiled and interpreted dispatch
could share the same declared fallback rule instead of inferring it from an
empty body. This is a design note only; no spelling has been selected.

## Representation-keyed core extensions

Moving a native method into source currently creates an all-or-nothing loader
problem. A receiver from an opaque parameter or foreign return has a runtime
dispatch key but no statically discoverable class AST. Loading a full class on
the method spelling alone is tolerable for a unique name, but disastrous for
ubiquitous names such as `[]`, `size`, `get`, `set`, `close`, `inspect`, or
`to_s`. Keeping the C row is then the only sound way to preserve the opaque
boundary without bloating unrelated programs.

A small extension/facade declaration should be able to attach selected source
methods directly to a runtime representation key, independently of the full
class implementation and without pretending to define or reopen a different
class identity. It must compose with inheritance and dual representations
(Regex, for example, has both native and ordinary source instances), expose
its autoload cost to the compiler, and define precedence against retained
native fallbacks. Such a form would make narrow core migrations possible
without global method-name gates. This remains a design wish only.

## Separate purity, effects, and memoization

`fn` currently combines two different promises: the body is pure, and calls
with the same arguments may be memoized. Core wrappers around allocation,
mutation, and device operations sometimes use ordinary `->` solely to avoid
memoization. A missed C symbol in the compiler's impure-call table has also
caused two nominally fresh allocations to alias through the same memo entry.

Function declarations should express purity independently from caching. A
general effect contract could additionally describe fresh results, reads,
writes, argument escape, and resource creation, with unknown foreign calls
remaining impure by default. Memoization should be an explicit, separately
reviewable request rather than an automatic consequence of the purity marker.
This effect and memoization surface is an unimplemented design idea.

## Typed and effectful foreign interfaces

Core code currently calls foreign functions through string-valued
`ccall("name", ...)` and `ccall_nobox("name", ...)` forms. The compiler then
uses separate hard-coded name tables to recover result representation and
side-effect facts. The parsed `extern lib` declarations do not yet provide a
complete replacement for that boundary.

A foreign declaration should state native parameter and result types, whether
the result is boxed or raw, ownership or freshness, argument alias/escape
behavior, mutation, and platform availability. Calls could then use an ordinary
declared name, and lowering, escape analysis, and the interpreter could share
one checked contract. This typed FFI surface is not implemented, and no
particular spelling is proposed here.

Raw result types should compose through nested intrinsic calls. Float rounding
currently needs a narrow compiler peephole to keep
`w_numeric_to_i64(Math.floor(x))` as libm `double` followed by `fptosi`; without
a typed interface, the generic path boxes the Math result only to call C and
unbox it again. Declared raw signatures would make that optimization a normal
type-directed lowering rule instead of a spelling-specific exception.

## Name-bound typed signatures

Typed methods can currently put a positional type list after the ordinary
parameter list, as in `(value, flag) (i64 bool) i64`. The type and parameter
names can drift apart during editing, and the parser needs lookahead to decide
whether the second parenthesized form is a signature or an expression.

Each parameter's type should instead be visibly attached to that parameter,
with the result type separated by an unambiguous delimiter. The same form
should cover methods, functions, block parameters, typed arrays, and GPU helper
functions. Name-bound signature syntax remains unimplemented.

## Scoped storage borrows and pins

Low-level codecs obtain raw pointers into String or typed-array storage only
after completing every allocation that might invalidate those pointers. Metal
buffer views similarly require the caller to keep an Array alive and avoid a
growth operation that reallocates its storage. Those lifetime rules currently
live in comments and calling convention.

A lexical borrow or pin region should keep the owner alive, expose a bounded
typed slice, reject pointer escape, and prevent storage-invalidating mutation
for the duration. Mutable output borrows should make their exclusive write
scope equally explicit. Scoped borrowing and pinning are unimplemented ideas,
not permissions for ordinary code to use unchecked pointers today.

## First-class wide and carry arithmetic

Fast multiword arithmetic currently depends on compiler-recognized call names
such as `mulhi`, `addcarry`, and `subborrow`. Their raw result types and lowering
rules are repeated across analysis, lowering, and emission, while an
interpreter implementation has to recognize the same otherwise-undeclared
spelling.

The language or its intrinsic-declaration surface should represent widening
multiplication and add/subtract-with-carry as typed operations, ideally exposing
both halves or both result and carry without recomputation. Signedness and
overflow behavior must be explicit and identical in compiled and interpreted
execution. First-class wide/carry operations are not implemented.

## Uniform structured attributes

The comment-like `##` channel currently carries local machine types, class
promises, typed-array shape, representation intent, stack/reuse/recycle
lifetime hints, and scheduling metadata. These annotations have different
semantics but share a line-oriented form that is difficult to compose and can
consume closing syntax unexpectedly.

A real attribute grammar should attach structured, independently validated
metadata to declarations, bindings, expressions, and lexical blocks. It should
distinguish checked semantic requirements from unsafe optimizer promises and
from optional performance hints. This would provide a common home for several
wishlist items above without merging their meanings. Uniform attributes remain
an unimplemented language-design proposal.

## Lexically closed arity suffixes and numeric units

Operator-method declarations currently encode arity beside the name, as in
`<=>/1 to_s`. Numeric literals also accept a space-separated unit suffix. At
that boundary the lexer can consume the leading `t` of `to_s` as the known
tonne unit, producing a quantity token for `1 t` instead of the integer arity
followed by an identifier. A reentrant parse of `core/symbol.w` exposed this
while answering an interpreted `Symbol#is_a?` query.

Method arity should have a lexically closed form that cannot be extended by the
following declaration token. Unit suffixes should likewise require an
unambiguous boundary and must never consume a prefix of a longer identifier.
Whether that is expressed by punctuation, delimiter rules, or a stricter unit
token is deliberately left open; this loop does not change either syntax.

## Distinguish method blocks from result application

A trailing block can be interpreted either as the block argument to a method
or as an operation applied to the method's returned value, with the distinction
depending on the resolved signature. This makes failure and surplus-block
behavior hard to read at native/source wrapper boundaries, especially for
methods returning `nil` or Bool.

The grammar should make those two intentions visibly distinct while retaining
ordinary block-taking calls as the concise common case. This is a syntax wish
only; the synchronization-wrapper migration preserves the current behavior.

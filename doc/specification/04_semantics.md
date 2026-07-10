# 4. Semantics

This chapter describes the meaning of Tungsten programs: how expressions are evaluated, how names resolve, how control structures transfer control, and how values behave. It is written in precise informal English. Runtime representation details appear only when they affect observable language behavior; the bit-level encoding of values is specified separately in the WValue documents.

Version: 2026.07.04

## 4.1 Evaluation model

A Tungsten system executes a program by evaluating a sequence of top-level forms in order. Evaluation of a form produces a _value_. Values are objects (see _Object Model_); every value has a class that determines its methods.

Evaluation is ordinarily strict (eager): operands of an operator or arguments of a call are evaluated before the operation or call proceeds, except where a construct is defined to be lazy or short-circuiting.

Side effects (I/O, mutation of objects, assignment to variables) occur in the order implied by left-to-right evaluation of subexpressions and sequential execution of statements in a block, unless a construct specifies otherwise (for example, short-circuit boolean operators or concurrent forms).

### 4.1.1 Program entry

There is no required entry-point function. A source file is a script:

1. Load and parse the file as a program.
2. Evaluate each top-level form from first to last.
3. After the last form, the process exits. The exit status is `0` on success, non-zero on fatal error (implementation-defined codes include syntax failure).

Definitions (`+ Class`, `trait`, `-> method`, `fn`, `use`) take effect when evaluated: classes and methods become available to later forms in the same program. Mutual recursion among methods is permitted once all participating definitions have been evaluated.

When a program is compiled to a native binary, the same top-to-bottom order is preserved for initialization; the resulting executable then runs that initialization and any residual top-level expressions as program startup.

### 4.1.2 `use` and loading

Evaluating `use path` loads another compilation unit, evaluates it (unless already loaded, at the implementation's discretion for caching), and makes its exported definitions available. Cyclic loads and duplicate loads are handled in an implementation-defined manner; a conforming implementation **must** document whether re-`use` re-executes the file or is a no-op.

## 4.2 Values and truthiness

Every expression yields a value. The set of values includes at least:

* the singletons `nil`, `false`, and `true`
* integers (fixed-width inline integers and arbitrary-precision integers)
* floating-point numbers and exact decimals
* strings, symbols, arrays, hashes, ranges, and other core objects
* user-defined class instances
* classes and modules themselves (as objects)
* closures / blocks

### 4.2.1 Truthiness

Conditional contexts — `if`, `unless`, `while`, `until`, `case` guards, boolean operators that branch, and any construct described as testing a condition — interpret values as true or false according to **truthiness**.

**Only `nil` and `false` are falsey.** Every other value is truthy, including:

* `true`
* `0` and `0.0`
* empty strings `""`
* empty arrays `[]` and empty hashes `{}`
* user objects

This rule matches the WValue design invariant: truthiness is the unsigned comparison _value > 1_ on the encoded representation, where `nil` and `false` occupy the two lowest singleton encodings. See [WValue overview](../WVALUE.md) and [WValue encoding](wvalue_encoding.md).

Equivalently, at the language level:

    truthy?(v)  ≡  (v != nil) && (v != false)

### 4.2.2 Equality and identity

`==` and related comparisons are methods (or built-in fast paths that preserve method semantics for core types). The default on `Object` defines `!=` in terms of `==`. Case dispatch may use `===` (case equality), which defaults to `==` unless overridden.

Identity versus structural equality for collections is defined by the classes involved; a strictly conforming program **must not** assume pointer identity for immutable immediates that the runtime may intern or tag.

## 4.3 Scoping and environments

Names are resolved in an _environment_: a chain of variable maps with a current _self_ (the receiver of the active method).

### 4.3.1 Kinds of names

| Kind | Written as | Scope |
|------|------------|--------|
| Local variable | `name` | Innermost block / method / program scope that assigned it |
| Method / function | `name` | Class, trait, module, or top-level, as defined |
| Instance field | `@name` | Current object (`self`) |
| Positional arg (arity form) | `@1`, `@2`, … | Current method with arity shorthand |
| Class / constant | `Name`, `A:B` | Lexical / namespace lookup |
| Keyword singleton | `self`, `true`, `false`, `nil` | Language-defined |

Assignment to a bare identifier creates or updates a local variable in the current local scope. Reading an unbound local is an error.

### 4.3.2 Method scope

On entry to a method:

1. A new local environment is created, chained to the appropriate outer environment for closures.
2. Parameters are bound to argument values.
3. `self` is bound to the receiver.
4. For parameters written `@x`, the corresponding instance field on `self` is assigned.
5. The method body is evaluated.
6. The value of the last expression, or of an explicit `return`, is the method's result.

Class methods bind `self` to the class object.

### 4.3.3 Blocks and closures

A block or lambda captures its surrounding local environment. When the block is invoked (`yield`, `.call`, or an implicit block argument), its parameters are bound and its body runs with that captured environment (plus any block-local bindings). Closures may outlive the activation that created them.

### 4.3.4 `self` and `super`

* `self` denotes the current receiver.
* A bare method call with no explicit receiver is sent to `self` (or resolved as a local / top-level function, according to lookup order below).
* `super` invokes the inherited implementation of the current method.

## 4.4 Assignment

### 4.4.1 Simple assignment

    x = expression

evaluates _expression_, binds the result to the local name `x` in the current scope, and yields that result as the value of the assignment expression.

### 4.4.2 Instance assignment

    @field = expression

stores into the named field of `self`. Reading `@field` loads that field. Accessing an undefined field is implementation-defined (typically `nil` or an error); a conforming implementation **must** document the choice.

### 4.4.3 Compound and multi-assignment

Compound assignment `x += y` evaluates as updating `x` with the result of the corresponding binary operator. Multi-assignment binds multiple targets from an aggregate on the right-hand side when the grammar form is used.

### 4.4.4 Attribute writes

A call written as a setter (`obj.name = value`) is a method send of `name=` with argument `value`.

## 4.5 Method dispatch

### 4.5.1 Overview

A method call has a receiver, a method name, arguments, and an optional block. Dispatch proceeds as follows:

1. Evaluate the receiver (defaulting to the implicit receiver for bare calls).
2. Evaluate the arguments left to right.
3. Locate a method implementation for the receiver's class (or for the class object, when the receiver is a class and the method is a class method).
4. If the receiver is a closure and the name is `call`, invoke the closure.
5. If the name is `new` and the receiver is a class, allocate and initialize an instance.
6. Otherwise invoke the located method with `self` bound to the receiver.
7. If no method is found, the call fails (via `method_missing` where supported, or with a fatal error).

Lookup walks the class's own methods, then included trait methods as merged into the class, then the superclass chain, toward the root (`Object`, then `BlankSlate`, unless an alternate hierarchy is used).

Details of metaclasses, singleton methods, and arity overloading are in _Object Model_.

### 4.5.2 Operators as methods

Binary operators on user-defined objects are evaluated by sending the operator's method name to the left operand:

| Expression | Method send |
|------------|-------------|
| `a + b` | `a.+(b)` |
| `a - b` | `a.-(b)` |
| `a * b` | `a.*(b)` |
| `a / b` | `a./(b)` |
| `a % b` | `a.%(b)` |
| `a ** b` | `a.**(b)` |
| `a <=> b` | `a.<=>(b)` |

Built-in numeric and string types may use optimized primitives that are observationally equivalent to these sends for the operations they implement. Operator methods on core classes are part of the core library, not special forms.

Unary `!` is logical negation of truthiness (or a method where overloaded). Unary minus and other unary operators follow the same object-oriented pattern.

### 4.5.3 Blocks in calls

If a call supplies a block, the callee may `yield` to it zero or more times. Methods defined with `/&` or an explicit block parameter expect such a block. Invoking a method that yields when no block was given is an error.

## 4.6 Control flow semantics

### 4.6.1 Sequencing

A block evaluates its statements in order. The value of the block is the value of its last expression, unless a control transfer exits the block earlier.

### 4.6.2 `if` / `unless`

* `if c` evaluates `c`; if truthy, evaluates the then-branch; otherwise tries each `elsif` in order; if none match, evaluates `else` if present; otherwise the value is `nil`.
* `unless c` is equivalent to `if` with a negated condition.
* Suffix `expr if c` evaluates `c` and, if truthy, evaluates `expr`; otherwise yields `nil` (and does not evaluate `expr`).

### 4.6.3 Loops

* `while c` / `until c` repeatedly evaluate the condition and body while the condition is truthy / falsey, respectively.
* `loop` is `while true`.
* `with x in coll` iterates `coll` (via the collection's iteration protocol, typically `each`), binding `x` on each iteration and running the body.
* `parallel with x in coll` may execute iterations concurrently; races on shared data are the programmer's responsibility. The implementation **must** document memory and completion guarantees.

`break` terminates the nearest enclosing loop. `next` (and `continue`, where accepted as a synonym) skips to the next iteration. `redo` restarts the current iteration without re-evaluating the iteration step, where supported.

Suffix `expr while c` repeats evaluation of `expr` while `c` remains truthy.

### 4.6.4 `case`

**Condition `case`** (no subject): each `when` guard is evaluated in order; the body of the first truthy guard runs; else runs the `else` body or yields `nil`.

**Value `case`** (with subject): the subject is evaluated once; each `when` pattern is tested against it (commonly by equality, or by `===`); the first matching arm runs.

`recase` re-enters the nearest enclosing `case` with an optional new subject value, where supported.

### 4.6.5 `begin` / `rescue` / `ensure`

1. Evaluate the `begin` body.
2. If a non-local error is raised and a `rescue` clause is present, bind the exception (when a name is given) and evaluate the rescue body.
3. Whether the body completed or was rescued, evaluate `ensure` if present.
4. If the error was not rescued, propagate it after `ensure`.

`raise` constructs or re-raises an error and transfers control to the nearest handler.

### 4.6.6 `return` and `yield`

* `return expr` exits the enclosing method (or lambda, according to implementation rules for block returns) with value `expr` (or `nil` if omitted).
* `yield args…` invokes the current block with the given arguments and yields the block's result as the value of the `yield` expression.

## 4.7 Integers and bignums

### 4.7.1 Inline integers

Small integers are represented as tagged immediate values (48-bit signed range in the standard WValue encoding). Arithmetic on values that remain inside that range stays on the fast path.

### 4.7.2 Overflow and BigInt

Values that exceed the inline integer range become heap-allocated `BigInt` objects (arbitrary precision). A conforming implementation **must**:

* accept integer literals of any magnitude permitted by available memory
* produce a mathematically correct integer result for standard arithmetic when using the language's default integer policy, either by promoting to `BigInt` or by an explicitly selected overflow mode

Lexical overflow modes may be selected with scoped forms such as:

* `Math.promote -> …` — promote to `BigInt` on overflow
* `Math.trap -> …` — trap / abort on overflow
* `Math.wrap -> …` — wrap with native modular arithmetic

The default mode for a compilation unit is implementation-defined and **must** be documented. Mixed operations between inline integers and `BigInt` promote as needed to preserve correctness under the active mode.

### 4.7.3 Other numerics

Bare fractional literals are **exact decimals**, not binary floats. Machine floating-point values are written with a leading `~` (for example `~3.14`). Floating-point evaluation is further governed by the math mode in force (precise, strict, or fast); see _Floating-Point Math Modes_.

## 4.8 Boolean operators and short-circuiting

Logical forms that combine conditions **must** short-circuit:

* A conjunction evaluates its right operand only if the left is truthy.
* A disjunction evaluates its right operand only if the left is falsey.

The value of a short-circuit expression is that of the last operand evaluated (not necessarily a boolean), unless a particular operator is defined to coerce to `true` / `false`.

Unary `!` yields `true` when its operand is falsey and `false` when its operand is truthy.

## 4.9 Printing and passthrough

`<< expression` evaluates its operand(s) and writes a textual representation to standard output (one value per line when multiple operands are given). The value of the print expression is implementation-defined (commonly `nil` or the printed value).

A top-level expression that is not a definition is evaluated for its side effects; its value may be discarded, except in a REPL where the implementation typically displays it.

## 4.10 Errors

Errors raised with `raise`, or by the system (type errors, undefined methods, division by zero under trap modes, and so on), propagate until rescued or until they become fatal. Fatal errors terminate the program with a non-zero status unless a rescuable fatal handler is installed (see _Introduction_ for the taxonomy of fatal / rescuable / non-fatal errors).

A strictly conforming program **must not** rely on the precise text of system error messages.

## 4.11 Concurrency (summary)

The language provides concurrent forms such as `go` (asynchronous execution) and `parallel with`. Scheduling, fairness, and the memory model are implementation-defined in this edition. Programs that share mutable state across concurrent tasks **must** use synchronization appropriate to the implementation.

## 4.12 Undefined behavior

Behavior is undefined when this specification says so, when a **must** / **must not** rule is violated, or when a program depends on unspecified evaluation order beyond the guarantees above. Conforming implementations may diagnose such programs but are not required to.

## 4.13 Cross-references

* Syntax of the constructs above — _Grammar_
* Objects, classes, traits, fields — _Object Model_
* Value bit patterns and the truthiness encoding — [WValue encoding](wvalue_encoding.md), [WValue overview](../WVALUE.md)
* Float contraction and reassociation — _Floating-Point Math Modes_

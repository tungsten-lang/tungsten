# Tungsten error explanations

Used by `tungsten explain CODE` (and the `explain:` footer on compile errors).
Each section is headed by the error code; the body is cause + fix.

## E_PARSE_UNEXPECTED_TOKEN

The parser saw a token that is not legal in this position.

**Fix:** Check indentation (blocks close by dedent), missing commas, and
operators that need spaces (`n / 2` vs map `arr/map`). See
`doc/getting-started/06-gotchas.md`.

## E_PARSE_INVALID_ASSIGN_TARGET

The left-hand side of `=` is not something that can be assigned (for example
a bare expression, a call that is not `[]=` / a setter, or a PascalCase
name).

**Fix:** Assign to a local, `@ivar`, `@@cvar`, `$global`, or a call of the form
`obj.field =` / `arr[i] =`.

**PascalCase pitfall:** identifiers that look like class names
(`FooBar`, `Wit`, `WIT_keys` — any name with an uppercase letter followed
later by a lowercase letter) parse as `class_ref` and cannot be assigned.
Use `snake_case` (`wit_keys`) or `SCREAMING_SNAKE` (`WIT_KEYS`, `GOOD_7`)
for variables and constants.

## E_PARSE_INVALID_TYPE_NAME

The parser recognized a type annotation spelling that is not a Tungsten type.
In particular, `str` is not an alias: Tungsten's text type is `string`.

**Fix:** Replace `## str` with `## string` (and `str[]` with `string[]`).
This diagnostic concerns source type names; the compiler's internal `:str`
interpolation marker is unrelated.

## E_LEX_UNEXPECTED_CHAR

The lexer hit a character that does not start any token.

**Fix:** Check for smart quotes, stray control characters, or a half-written
operator. `#` starts a comment unless it is a hex color (`#FF0000`).

## E_LEX_INVALID_IDENTIFIER

The source joined a lowercase identifier directly to uppercase ASCII, such as
`camelCase` or `@camelCase`. Tungsten local, instance, class, and global
variables and methods use `snake_case`; PascalCase names are class references
and SCREAMING_SNAKE names are constants. Registered mixed-case unit spellings
remain valid only on unit-expecting surfaces.

**Fix:** Rename the identifier using `snake_case` (for example,
`camel_case`).

## E_LEX_NON_ASCII_LITERAL

An ASCII literal contains a byte outside ASCII (`0x00` through `0x7F`). ASCII
literals are deliberately strict, non-interpolating, and non-escaping.

**Fix:** Use double quotes for Unicode text.

## E_LEX_UNTERMINATED_ASCII_LITERAL

The lexer reached the end of the source before the closing single quote.
Backslash does not escape a quote inside this literal form.

**Fix:** Add the closing quote, or use a double-quoted string when the value
must contain a single quote.

## E_LOWER_FOREIGN_IDIOM

Lowering recognized a name or pattern common in another language that Tungsten
spells differently (for example `print`, `def`, `class`).

**Fix:** Use Tungsten surface forms: `<<` to print, `->` for methods, `+ Name`
for classes. See `doc/TUNGSTEN_FOR_LLMs.md`.

## E_LOWER_TYPED_ARG_MISMATCH

A function with this name and arity is declared with a typed signature, but the
call's inferred argument types match none of its declared signatures. Only
exactly-matching types resolve; there is no implicit widening or conversion.

Watch for typed arrays in particular: `i64[]` and `i32[]` are the same handle
at the LLVM level but different element widths, so a callee declared `i64[]`
strides 8 bytes through an `i32[]`'s 4-byte slots. Before this diagnostic
existed the call fell through to an unmangled symbol and failed at link time
with `Undefined symbols: ___w_NAME`.

**Fix:** Declare the parameter with the element width you actually pass
(`i32[]` for a 32-bit array), convert the argument, or add an overload for the
types at the call site. Note that the *actual* element width is what matters —
`i32[8]`, `Array.zeros` variants, and Metal buffer views each pin their own.

## E_LOWER_ARITY

A call passes more arguments than the callee declares, or fewer than its
required (non-defaulted, non-keyword) leading parameters, and the callee was
resolved at compile time: a source function, a constructor, a class static,
or an instance method on a receiver whose class is exactly known. Tungsten
never silently drops extra arguments or pads missing ones with nil; the
interpreter raises the same error when it binds parameters. Dynamic dispatch
on an unknown receiver is not checked at runtime.

**Fix:** Fix the call, or give the definition a default (`b = 10`), a `*rest`
splat, or a block parameter if it is meant to be variadic. `TUNGSTEN_ARITY=off`
disables the check for triage only.

## E_LOWER_UNKNOWN_TRAIT

A class says `is TraitName` but that trait was not found at lower time.

**Fix:** Define the trait (`trait Name`), `use` the file that defines it, or
register a stdlib trait via `core/tungsten.w` autoload.

## E_LOWER_CARRY_UNROLL

`TUNGSTEN_CARRY_UNROLL` was set to an invalid LLVM loop-unroll count. The
compiler accepts integers from 0 through 64; 0 disables the carry-chain hint,
and an unset variable uses the measured default of 8.

**Fix:** Unset the variable, or set it to a decimal integer in the accepted
range. Benchmark with `--release`; do not compare unoptimized builds.

## E_LOWER_GENERIC_ARITY

A generic class or parametric superclass received the wrong number of type
arguments. This is checked when the generic is defined as well as when it is
specialized.

**Fix:** Supply exactly one type argument per declared parameter. For example,
`Pair<T, U>` must be used as `Pair<Key, Value>`, including in a parent clause
such as `Child<T> < Pair<T, i32>`.

## E_LOWER_GENERIC_CONSTRAINT

A generic constraint is malformed or a type argument violates it. Constraint
parameters must exist, cannot be declared twice, and must contain at least one
allowed type. A child generic may inherit or narrow a parent's constraint but
cannot widen it.

**Fix:** Correct the `with T in (...)` declaration or use an allowed type. For
parametric inheritance, ensure every concrete or child parameter passed to the
parent satisfies the parent's bound.

## E_TYPE_MISMATCH

A value’s type is not compatible with the expected type at this site
(annotations, operators, or unit dimensions).

**Fix:** Add or correct a `## Type` annotation, convert with a method
(`to_i` / `to_f`), or fix unit dimensions (`2 m + 2 lbs` is illegal).

## E_LOAD_NOT_FOUND

A `use` path could not be resolved to a `.w` file.

**Fix:** Check the path relative to the project, install deps with `bit install`
(looks under `vendor/bits`), or set `BIT_HOME` for monorepo bits.

## E_GPU_KERNEL_UNSUPPORTED

An `@gpu fn` feature is not available for the selected GPU dialect
(Metal / CUDA / WGSL).

**Fix:** Use portable GPU surface (`gpu.thread_position_in_grid`, shared
arrays, simple control flow), or set `TUNGSTEN_GPU_DIALECTS` appropriately.
See `doc/gpu-cuda.md`.

## E_GPU_DIALECTS

`TUNGSTEN_GPU_DIALECTS` contained an unknown, duplicate, or contradictory
dialect selection. Accepted names are `metal`, `cuda`, `wgsl`, and `none`;
`none` must appear by itself. Metal source is always emitted for `@gpu fn`, so
including `metal` is explicit but does not change the artifact set.

**Fix:** Use a unique comma-separated list such as `cuda,wgsl`, use `none` by
itself to suppress extra sidecars, or unset the variable for the default.

## LINT_USAGE

The `tungsten lint` command received a missing path, unknown option, invalid
format, unknown lint code, or invalid severity override.

**Fix:** Run `tungsten lint --help`. Severity overrides use
`--severity CODE=off|warning|error`.

## LINT_TAB_INDENT

A source line uses a tab in its leading indentation. Tabs inside strings and
comments after source text are not flagged.

**Fix:** Replace indentation tabs with spaces, or configure this rule with
`--severity LINT_TAB_INDENT=off|warning|error`.

## LINT_TRAILING_WHITESPACE

A source line ends with one or more spaces or tabs.

**Fix:** Remove the trailing whitespace, or configure this rule with
`--severity LINT_TRAILING_WHITESPACE=off|warning|error`.

## LINT_FINAL_NEWLINE

A non-empty source file does not end with a newline.

**Fix:** Add one final newline, or configure this rule with
`--severity LINT_FINAL_NEWLINE=off|warning|error`.

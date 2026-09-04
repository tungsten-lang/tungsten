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

## E_TYPE_CANNOT_ADD

`+` with a statically known date or time on the left and an operand that has
no additive meaning on the right: another date or time, an IP address, a
rational, or a UUID. `date + duration` and `date + int` (days) are fine.

**Fix:** Add a `Duration` (`d + 3 d`, `t + 90 min`) or an integer day count.
To measure the gap between two dates, subtract them: `later - earlier` is a
`Duration`.

## E_TYPE_CANNOT_SUBTRACT

`-` with a statically known date or time on the left and an IP address, a
UUID, or a string on the right. `date - date` yields a `Duration` and
`date - duration` yields a date; both are allowed.

**Fix:** Subtract a `Duration`, an integer day count, or another date/time.
Parse a string into a date first (`Date.parse(s)`) if that is what you meant.

## E_TYPE_CANNOT_USE_OP

Arithmetic (`+ - * /`) with a statically known IPv4 or IPv6 address on the left
and a date, time, string, rational, or UUID on the right. Addresses only take
integer offsets (`10.0.0.1 + 5`).

**Fix:** Offset an address with an integer, or convert it with `to_i` / `to_s`
before combining it with anything else.

## E_TYPE_UUID_ARITHMETIC

`+ - * /` applied to a statically known UUID. UUIDs are opaque identities, not
numbers; there is no meaningful sum or product of two identifiers.

**Fix:** Compare UUIDs with `==`, use them as keys, or convert with `to_s`.
If you need a numeric derivation, take `uuid.to_s` and hash or slice it
explicitly.

## E_LOAD_MISSING_FILE

A `use` path resolved to a filesystem location, but no readable `.w` file is
there. The message names both the spelling you wrote and the path it resolved
to, so the two can be compared.

**Fix:** Check the path relative to the requiring file and the project root,
install dependencies with `bit install` (bits resolve under `vendor/bits`), or
set `BIT_HOME` for monorepo bits. Paths omit the `.w` extension.

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

## E_PARSE_EXPECTED_TOKEN

The parser required a specific token here — a closing `)` or `]`, a keyword,
a name — and found something else (often the end of the line or file). The
message names the token it expected and the one it saw.

**Fix:** Look at the caret: an unclosed paren or bracket on that line is the
usual cause, followed by a missing keyword (`in` after `parallel with x`) or a
generic type list with an empty slot (`Matrix<>`). The `with T in (...)`
constraint clause is only legal inside a class or trait body.

## E_PARSE_EXPECTED_METHOD_NAME

After `->` the parser expected a method name and found a token that cannot
name a method. Names, `[]`, `[]=`, and the overloadable operators (`+ - * /
== < >` and friends) are all accepted.

**Fix:** Check the method definition line: `-> name`, `-> name(@a, @b)`,
`-> name/2`, or `-> .class_method`. A closure is `-> (x) ...`, not `-> x`.

## E_PARSE_BAD_PARAM_TYPE

Inside a positional type list such as `(i64 string)` the parser found a token
that is not a type name.

**Fix:** Type lists are whitespace-separated type names with no commas:
`-> add(a, b) (i64 i64) i64`. Array types are spelled `i64[]`, and the text
type is `string`, not `str`.

## E_PARSE_EXPECTED_DATA_FIELD_TYPE

A line inside a `- data` block did not start with a field type. Each field is
`type name`, where the type is a machine type (`u8`, `i64`, `f64`, `w64`), a
fixed array (`u8[2]`), or a type parameter.

**Fix:** Write `u32 size` rather than `size u32`, and keep field declarations
one per line under `- data`.

## E_PARSE_EXPECTED_IVAR

A line inside a `- ivars` block does not start with an `@name` instance
variable.

**Fix:** List one `@ivar` per line; declare accessors with `ro` / `rw` in the
class body, not in the `- ivars` block.

## E_PARSE_IN_EXPECTS_TUPLE

The membership operator `in` needs a parenthesized, whitespace-separated
tuple on its right: `x in (1 2 3)`, `op in (:plus :minus)`.

**Fix:** Parenthesize the alternatives and separate them with spaces, not
commas. To test membership in an array value, call `arr.include?(x)`.

## E_PARSE_IN_EMPTY_TUPLE

`x in ()` — the tuple on the right of `in` has no elements, so the test could
never be true.

**Fix:** List at least one alternative, or remove the test.

## E_PARSE_PARALLEL_WITH_SINGLE_BINDING

`parallel with` accepts exactly one binding; a comma after the collection
introduced a second one (`parallel with a in xs, b in ys`).

**Fix:** Iterate one collection and index into the other, or zip them first:
`parallel with pair in xs.zip(ys)`.

## E_PARSE_SELF_METHOD_DEF

A class method was written Ruby-style as `-> self.name`. Tungsten spells class
methods with a leading dot.

**Fix:** Write `-> .name` (and call it as `Klass.name`).

## E_PARSE_UNEXPECTED_KEYWORD

A keyword appeared where no statement can start with it — `end`, `then`,
`else` without an `if`, or a reserved word used as a variable name (`ro`, `rw`,
`on`, `enum`).

**Fix:** Tungsten closes blocks by dedent, so delete stray `end` lines. Rename
variables that collide with reserved words.

## E_LEX_UNTERMINATED_STRING

A double-quoted string reached the end of the source without its closing
quote. The location points at the opening quote.

**Fix:** Close the string. For multi-line text use a heredoc (`<<~TEXT` ...
`TEXT`), and escape embedded quotes as `\"`.

## E_LEX_HEREDOC_NO_DELIM

`<<~` was not followed by a delimiter name (a letter or underscore, then name
characters).

**Fix:** Write `<<~TEXT` (any identifier-shaped name) and end the body with a
line containing only that name.

## E_LEX_UNTERMINATED_HEREDOC

The heredoc body ran to the end of the file; the closing delimiter line never
appeared. The location is the heredoc's opening line.

**Fix:** Add a line containing exactly the delimiter (`TEXT`) after the body.
The terminator's indentation is stripped from every body line, so it may be
indented to match the surrounding code.

## E_LEX_EMPTY_KEY

A key literal `#[ ]` has nothing between the brackets.

**Fix:** Put a key inside (`#[name]`) or use a symbol (`:name`) or string.

## E_LEX_UNTERMINATED_KEY

A `#[...]` key literal hit a newline or the end of the file before its closing
bracket.

**Fix:** Close the bracket on the same line; key literals cannot span lines.

## E_LEX_BYTEARRAY_BAD_CHAR

Inside a byte-array literal the lexer found a character that is neither a
separator nor a one- or two-digit hex byte.

**Fix:** Byte arrays hold hex bytes separated by whitespace: `%b[de ad be
ef]`. Write decimal values as two hex digits (`0a`, not `10`).

## E_LEX_UNTERMINATED_BYTEARRAY

The byte-array literal never saw its closing bracket.

**Fix:** Close the `]`. Long byte arrays may wrap across lines.

## E_LEX_UNTERMINATED_PW

A `%w[...]` word-array literal never saw its closing bracket.

**Fix:** Close the `]`. Words are whitespace-separated: `%w[alpha beta]`.

## E_LEX_UNTERMINATED_PI

A `%i[...]` symbol-array literal never saw its closing bracket.

**Fix:** Close the `]`. Elements are bare names: `%i[plus minus]` is
`[:plus, :minus]`.

## E_LEX_UNTERMINATED_PD

A `%d[...]` decimal-array literal never saw its closing bracket.

**Fix:** Close the `]`. Elements are space-separated exact decimals:
`%d[1.5 2.25]`.

## E_LEX_UNTERMINATED_PF

A `%f32[...]` or `%f64[...]` typed float-array literal never saw its closing
bracket.

**Fix:** Close the `]`. Elements are space-separated float literals:
`%f64[1.0 2.5]`.

## E_LEX_UNTERMINATED_PH

A `%h<dim>-<type>[...]` hypercomplex literal never saw its closing bracket.

**Fix:** Close the `]`. Components are space-separated numbers.

## E_LEX_CHAR_HEX_LENGTH

A `U+XXXX` codepoint literal needs four to six hex digits after `U+`.

**Fix:** Pad short codepoints to four digits (`U+0041`, not `U+41`) and check
that longer ones do not exceed six.

## E_LEX_CHAR_SURROGATE

The codepoint is in the UTF-16 surrogate range `D800`–`DFFF`. Surrogates
are an encoding artifact, not Unicode scalar values, so no character has that
number.

**Fix:** Write the character you meant directly in a string, or use its real
scalar value (a supplementary-plane character is one codepoint above
`U+FFFF`, not two surrogates).

## E_LEX_CHAR_UNICODE_RANGE

The codepoint is above `U+10FFFF`, the last Unicode scalar value.

**Fix:** Check the hex digits; a stray digit is the usual cause.

## E_LEX_WVALUE_HEX_LENGTH

A WValue literal (`u0x...`) must be exactly one 64-bit word: sixteen hex
digits, not followed by another digit or underscore.

**Fix:** Zero-pad to sixteen digits. WValue literals are a compiler-internal
spelling for NaN-boxed words; ordinary programs want an integer literal.

## E_LOWER_UNKNOWN_FN

A bare call names a function that does not exist: no source `fn` or `->`
definition, no class of that name (constructor sugar), no typed overload
group, and no runtime bridge. Reporting it here beats fabricating a symbol
that fails at link time.

**Fix:** Check the spelling and that the defining file is reached through
`use` or the autoload manifest. Methods on an object need a receiver
(`obj.name`), and class methods need the class (`Klass.name`).

## E_LOWER_CLOSURE_CALL_ARITY

A closure or block value was invoked with three or more arguments; the direct
closure-call path supports zero through two.

**Fix:** Pass an array or a small object for wider argument lists, or split
the closure. `f.call(a, b)` is the widest direct form.

## E_LOWER_CTOR_ARITY

`Klass.new(...)` was called with fewer arguments than its constructor
requires. A missing constructor argument used to be nil-padded, leaving the
field unset and failing far away as a nil read.

**Fix:** Pass every required argument, or give the constructor parameter a
default (`-> new(@x, @y = 0)`). Constructors are found by walking the
superclass chain.

## E_LOWER_CVAR_OUTSIDE_CLASS

A class variable (`@@name`) was read or written at top level or inside a plain
`fn`, where there is no enclosing class to own it.

**Fix:** Move the code into a class body or method, or use a top-level
variable / `$global` instead.

## E_LOWER_DUP_DEF

Two definitions produce the same symbol: an untyped function defined twice,
or two typed definitions with identical signatures. Overloads must differ in
their declared parameter types.

**Fix:** Rename one definition, or give the overloads distinct typed
signatures (`-> f(a) (i64) i64` and `-> f(a) (f64) f64`).

## E_LOWER_RESERVED_INTRINSIC

User code called a compiler-internal intrinsic (`__compiler_overload_is_a`,
`__compiler_overload_worker`). These are synthesized by the compiler and carry
a marker a hand-written call lacks.

**Fix:** Call the public method instead; the intrinsics are not part of the
language.

## E_LOWER_SYMBOL_TOO_LONG

A `:symbol` literal exceeds 61 UTF-8 bytes, the slab-interning limit. A
longer symbol would get an allocator-dependent identity, so `==` between two
spellings could not be trusted.

**Fix:** Use a string for long names. If you need a stable handle, intern it
yourself (a hash keyed by the string).

## E_LOWER_UNKNOWN_MAGIC

A `__NAME__` magic constant other than `__FILE__`, `__DIR__`, or `__LINE__`.

**Fix:** Use one of the three supported constants, or a plain variable.

## E_LOWER_EMBEDDED_BODY

An embedded `ll "..."` or `asm "..."` function body violates its ABI: a
parameter that is neither a machine integer (`## i64` / `## u64`) nor a typed
array, more than eight `asm` parameters (registers `x0`–`x7`), or a return
type other than `i64`, `u64`, `i128`, or `u128`.

**Fix:** Type every parameter as a machine integer or typed array, keep `asm`
bodies to at most eight parameters, and return a machine integer. Box or
unbox at the call site in ordinary Tungsten.

## E_LOWER_TYPED_ARRAY_UNSUPPORTED

The element type is accepted by the lexer but the runtime has no storage for
it (`fp8`, `fp4`, `i128` arrays and similar).

**Fix:** Use one of `u1 i1 u4 i4 u8 i8 u16 i16 u32 i32 u64 i64 f16 f32 f64 bf16
w64 bool`, and convert on load/store if the narrower format matters.

## E_LOWER_QUANTITY_DIMENSION

`+` or `-` between two statically known quantities whose units have different
dimensions (`2 m + 2 lbs`). The one deliberate exception is information plus
energy (`1 PB + 1 J`), kept for the information-thermodynamics use case.

**Fix:** Convert one side to the other's dimension, or multiply/divide
(dimensions combine under `*` and `/`). Quantities built at runtime are
checked when they are added.

## E_LOWER_QUANTITY_EQUIVALENCE

`q.equivalent(...)` / `q.equivalent_to(...)` takes exactly two arguments: the
target unit and the named bridge that relates the two dimensions.

**Fix:** `energy.equivalent(kg, :mass_energy)`. See `doc/mathematics.md` for
the registered bridges.

## E_LOWER_TENSOR_UNIT_TYPE

`Tensor<...>.zeros(shape)` must name two type arguments — the dtype and the
unit — and take one shape argument, and the unit argument must be a registered
unit expression.

**Fix:** `Tensor<f32, m/s>.zeros([3, 3])`. Check the unit spelling against
`data/units.tsv`.

## E_LOWER_TOO_MANY_UNITS

The module exhausted the id space for user-defined units.

**Fix:** Reuse unit spellings instead of generating fresh ones (each distinct
spelling costs an id), or split the program into modules.

## E_LOWER_RATIONAL_ZERO_DENOM

A rational literal `n/0` has a zero denominator.

**Fix:** Every rational needs a non-zero denominator; write `1/2`, `3/4`, and
so on. Division by a runtime zero raises `ZeroDivisionError` instead.

## E_LOWER_DATE_INVALID_MONTH

A `YYYY-MM-DD` date literal's month is not in 1..12.

**Fix:** Check the digit order — the literal is year, then month, then day.

## E_LOWER_DATE_INVALID_DAY

A `YYYY-MM-DD` date literal's day is below 1 or past the end of that month.
February is checked against the leap-year rule.

**Fix:** Correct the day; `2025-02-29` is invalid but `2024-02-29` is fine.

## E_LOWER_DATE_INVALID_ORDINAL

A `YYYY-DDD` ordinal date literal's day-of-year is outside 1..366.

**Fix:** Ordinal days run from `001` to `365` (`366` in leap years).

## E_LOWER_TIME_INVALID_HOUR

A time literal's hour is outside 0..23.

**Fix:** Use 24-hour time; there is no `am`/`pm` suffix.

## E_LOWER_TIME_INVALID_MINUTE

A time literal's minute is outside 0..59.

**Fix:** Check the field order — hours, then minutes, then seconds.

## E_LOWER_TIME_INVALID_SECOND

A time literal's second is outside 0..59. Leap seconds are not representable
in literals.

**Fix:** Correct the value; `23:59:60` is rejected.

## E_LOWER_DURATION_INVALID_UNIT

A compact duration literal (`2h30m`, `500ms`, `1y2mo3d`) contains a unit
suffix that is not one of `ns us ms s m h d w mo y` at that position.

**Fix:** Spell minutes `m` and months `mo`; there is no `min` or `sec` in the
compact form. Spaced quantities (`90 min`) are unit literals, not durations.

## E_LOWER_VIEW_NO_LAYOUT

A `$field` native-data access has no layout to resolve against: the enclosing
class declares no `- data` layout, or the explicit receiver's type is unknown
to the compiler.

**Fix:** Access `$field` only inside a class with a `- data` block, or give the
receiver a type hint (`buf ## WArray`) so the layout is known. Outside such a
class, `$name` is not a global — use a top-level variable.

## E_LOWER_VIEW_UNKNOWN_FIELD

The class has a `- data` layout, but no field of that name.

**Fix:** Check the spelling against the `- data` block; fields must be
declared there before they can be read or written.

## E_CONTRACT_ARITY

A program contract (`Tungsten.PROTECT_THE_CORE!`, `Tungsten.STOP_THE_PRESS!`,
`Tungsten.LOCK_THE_DOORS!`) was written with arguments or a block. Contracts
are nullary markers.

**Fix:** Write the bare call on its own line: `Tungsten.LOCK_THE_DOORS!`.

## E_CONTRACT_DEPENDENCY

A file reached through `use` declared a program contract. Only the entry
program may close the world; a library cannot close its caller's method
tables.

**Fix:** Move the contract to the program's entry file, after its `use`
lines.

## E_CONTRACT_TOP_LEVEL

A contract call was nested inside a method body, an `if`, or a block. Contracts
are top-level declarations of the entry program.

**Fix:** Move the call to the top level of the entry file.

## E_CONTRACT_LOCK_ORDER

A function, method, class, module, or trait definition appears after
`Tungsten.LOCK_THE_DOORS!`. Locking the doors freezes the method tables, so
nothing may be defined afterwards.

**Fix:** Move every definition above the contract, or move the contract to
the end of the file.

## E_CONTRACT_TYPE_ORDER

After `Tungsten.STOP_THE_PRESS!` a class, module, or trait introduced a NEW
type name. Reopening an existing type is allowed; adding one is not.

**Fix:** Define all types before the contract; reopen them freely after it.

## E_CONTRACT_CORE_MUTATION

Under `Tungsten.PROTECT_THE_CORE!` a non-core file reopened or redefined a
name the standard library owns (a class in the autoload manifest, or a method
already defined by a `core/**.w` source).

**Fix:** Subclass or wrap the core type instead of reopening it, or drop the
contract if the program deliberately patches core.


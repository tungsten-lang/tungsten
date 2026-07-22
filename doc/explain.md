# Tungsten error explanations

Used by `tungsten --explain CODE` (and the `explain:` footer on compile errors).
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

## E_LEX_UNEXPECTED_CHAR

The lexer hit a character that does not start any token.

**Fix:** Check for smart quotes, stray control characters, or a half-written
operator. `#` starts a comment unless it is a hex color (`#FF0000`).

## E_LOWER_FOREIGN_IDIOM

Lowering recognized a name or pattern common in another language that Tungsten
spells differently (for example `print`, `def`, `class`).

**Fix:** Use Tungsten surface forms: `<<` to print, `->` for methods, `+ Name`
for classes. See `doc/TUNGSTEN_FOR_LLMs.md`.

## E_LOWER_UNKNOWN_TRAIT

A class says `is TraitName` but that trait was not found at lower time.

**Fix:** Define the trait (`trait Name`), `use` the file that defines it, or
register a stdlib trait via `core/tungsten.w` autoload.

## E_TYPE_MISMATCH

A value’s type is not compatible with the expected type at this site
(annotations, operators, or unit dimensions).

**Fix:** Add or correct a `## Type` annotation, convert with a method
(`to_i` / `to_f`), or fix unit dimensions (`2 m + 2 lbs` is illegal).

## E_LOAD_NOT_FOUND

A `use` path could not be resolved to a `.w` file.

**Fix:** Check the path relative to the project, install deps with `bit install`
(looks under `vendor/bits`), or set `BIT_HOME` for monorepo bits.

## E_GPU_UNSUPPORTED

An `@gpu fn` feature is not available for the selected GPU dialect
(Metal / CUDA / WGSL).

**Fix:** Use portable GPU surface (`gpu.thread_position_in_grid`, shared
arrays, simple control flow), or set `TUNGSTEN_GPU_DIALECTS` appropriately.
See `doc/gpu-cuda.md`.

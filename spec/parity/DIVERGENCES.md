# Cross-engine divergences (parity ledger)

One row per `## parity xfail` spec in this directory. Outputs are the
transcripts of `scripts/parity.sh --verbose` on 2026-09-02 (interp =
`bin/tungsten run --interpret`, compiled = `bin/tungsten compile`). When a
row's engines start to agree the run reports XPASS: drop the spec's header
and its row here in the same change. "Where to look" names the two code
paths that implement the surface independently.

| Area | Spec | Interpreter | Compiled | Hypothesis | Where to look |
|---|---|---|---|---|---|
| Inference | `integer_to_i_bignum_spec.w` | `to_i.plus 100000000000000000000` | `to_i.plus 7766279631452241920` | String#to_i promotes past i64 but its compiled lowering yields a raw i64 typed :i64; the next op unboxes the bignum as machine bits. Fix: lower String#to_i to a boxed promotable result typed :int. | `compiler/lib/lowering/inference.w` (`to_i` arm); the string to_i conversion lowering |
| Arity | `arity_extra_args_named_spec.w` | raises `'g' takes 1..2 arguments, got 3` at the call (after earlier lines) | compile error `E_LOWER_ARITY`, no output | Same contract on both engines; the compiled engine enforces it at compile time. By design. | `compiler/lib/lowering/signatures.w` check_static_call_arity; `compiler/lib/interpreter.w` call_w_method |
| Arity | `arity_missing_args_spec.w` | raises `'add' takes 2 arguments, got 1` at the call | compile error `E_LOWER_ARITY`, no output | Same contract on both engines; compile-time vs call-time. By design. | same |
| Units | `units_unary_minus_spec.w` | `runtime error: expected int, got numeric` (in `eval_unary_op`) | `neg.lit -3 m` (all three lines) | Quantity is a packed numeric tag, not an `:object` Hash, so the interpreter's unary minus falls into the primitive `0 - x` arm instead of dispatching `-@`; compiled goes through `w_neg`. | `compiler/lib/interpreter.w:2956` (`eval_unary_op`); runtime `w_neg` |
| Floats | `float_division_by_zero_spec.w` | `runtime error: division by zero` on `~1.0 / ~0.0` | `flt.inf inf`, then `runtime error: division by zero` on `-~1.0 / ~0.0` | Compiled folds/natively divides the literal case (IEEE inf) but the negated operand reaches the runtime divide which dies; the interpreter always takes the runtime path. Two rules inside one engine. | `runtime/runtime.c:13132`; `lowering/ops.w` float div; `interpreter.w:2785` (`apply_binary_op`) |
| Floats | `float_negative_zero_spec.w` | `negzero 0` | `negzero -0` | Both print through `%.17g`; the interpreter negates as `0 - x` (yielding +0.0) where compiled emits `fneg`. | `interpreter.w:2956`; `runtime/runtime.c:43998` |
| Integers | `integer_i64_wrap_spec.w` | promotes: `9223372036854775808`, `147573952589675364352`, `13835058055282163712` | wraps: `-9223372036854775808`, `-1048576`, `-4611686018427387904` | `## i64` locals lower to native add/shl with silent-wrap semantics by design; the interpreter ignores the hint and keeps promotable ints. | `lowering/ops.w:786` (silent-wrap note); interpreter hint handling |
| Integers | `integer_literal_i64_overflow_spec.w` | `9223372036854775808`, `-9223372036854775808`, `121932631136585886175176` | `-9223372036854775808`, `9223372036854775808`, `-347190634250006584` (yet `type` says `BigInt` on both) | i64-range literal arithmetic is const-typed as machine int on i48 inference and wraps natively; `-9223372036854775808` is unary minus applied to 2^63, which wraps to itself. | `lowering/ops.w:786`, `lowering/inference.w`, `lowering/literals.w` |
| Printing | `container_string_quoting_spec.w` | `["a", "b"]`, `{name: "Alice", age: 30}`, `{"b": 2}` | `[a, b]`, `{name: Alice, age: 30}`, `{b: 2}` | The interpreter formats container elements inspect-style (quoted strings) while runtime `w_to_s` recurses with plain `to_s`; `w_inspect` exists but `<<` never uses it. Affects every printed array/hash holding strings. | `runtime/runtime.c:43933` (`w_to_s`), `:61323` (`w_inspect`); `interpreter.w:1122` |
| Printing | `nil_display_spec.w` | `nil` everywhere: `[nil, 1]`, `{a: nil}`, `k:1,nil`, bare `<< nil` | empty: `[, 1]`, `{a: }`, `k:1,`, blank line | Interpreter's value-to-string returns `"nil"`; runtime `w_to_s(nil)` returns `""`. Same root as the row above. | `interpreter.w:1122,1160`; `runtime/runtime.c:43933` |
| Strings | `string_padding_spec.w` | `ljust hi   \|`, `rjust    hi`, `center   hi  \|` | `undefined method 'ljust' for String` | `ljust`/`rjust`/`center` exist only as interpreter builtins; `core/string.w` has no definition (grep finds none under `core/`). | `compiler/lib/interpreter.w` string builtins; `core/string.w` |
| Ranges | `range_type_name_spec.w` | `type(1..2)` → `Hash` | `Range` | Interpreter ranges are Hash records and `type()` reports the host container; the runtime has a dedicated `Range` type name. | `interpreter.w:78` (`type` names); `runtime/runtime.c:48580` |
| Control flow | `case_range_when_spec.w` | `when 3..9` never matches (`5` → `big`) | matches (`medium`) | `eval_case` compares the `when` value with `==` (a Hash-backed range never equals an int) instead of membership; lowering emits bound checks for range arms. | `interpreter.w:3121` (`eval_case`); `lowering/control_flow.w` (~778) |
| Control flow | `nonlocal_return_from_block_spec.w` | `return` in a block leaves only the block → `-1` | leaves the method → `4` | Lowering has explicit non-local block-return support; the interpreter's block `return` only unwinds the lambda frame. | `lowering/blocks.w:611` (`has_nonlocal_block_return_in_node`); interpreter block `:return` handling |
| Errors | `error_uncaught_format_spec.w` | `error: unhandled boom` + bare `--> file` | `unhandled exception: unhandled boom` + source excerpt + C backtrace with addresses | Two independent top-level error printers. | `compiler/tungsten.w:2620` (`format_runtime_error`); `runtime/runtime.c:48286` |
| Classes | `object_equality_default_spec.w` | `Point.new(1,2) == Point.new(1,2)` → `true` | `false` | Interpreter objects are `{rt: :object}` Hashes so `==` becomes structural Hash equality; runtime `w_eq` compares object identity. | `interpreter.w:2785` (`apply_binary_op`); `runtime/runtime.c:42969` (`w_eq`) |
| Classes | `class_generics_spec.w` | `type(Box<Integer>.new(1))` → `Box` | `Box$Integer` | Monomorphization mangles the specialized class name and `type()` reports it; the interpreter never specializes (generics are compiled-only). | `lowering/monomorphize.w:42` (`mangled_specialized_name`) |
| Blocks | `block_passthrough_spec.w` | trailing block on a block-less method is dropped → `0 0 0` | iterates the result → `60 4 5` | The parser marks these calls `:passthrough` and lowering rewrites them to `.each`; the interpreter ignores the marker. | `compiler/lib/parser.w:1013`; `lowering/analysis.w:194,540`; interpreter (no passthrough arm) |
| Arity | `arity_mixed_call_sites_spec.w` | drops extras at each site: `h:1,2` ×4 | compile error `WIRE call contract mismatch … i64(i64,i64) in @main vs i64(i64,i64,i64) in @main` | Direct WIRE calls carry a per-site contract keyed on argument count, so two call sites of one function with different arities collide at emit time — while a *single* wrong-arity site is silently accepted (`arity_extra_args_named_spec.w`, `arity_missing_args_spec.w` pass on both engines). | `compiler/lib/emitter/analysis.w:1255`; `lowering/calls.w` |

## Found but not seeded

| Area | Program | Interpreter | Compiled | Hypothesis | Where to look |
|---|---|---|---|---|---|
| Ranges | `Σ(2x⁷ + 3x², 1..10)` (prefix sigma form) | `36162005` | `error: unknown function 'Σ'` (E_LOWER_UNKNOWN_FN); `bin/tungsten -c` rejects the file, so it cannot live in this suite | The interpreter's `sigma_closed_form` recognises the prefix call; `lowering/poly_sum.w` only handles the postfix `range/Σ(…)` form (which agrees on both engines — see `range_closed_form_sums_spec.w`). | `interpreter.w:952`; `lowering/poly_sum.w`; unknown-fn path in `lowering/calls.w` |

## Ruby tree-walker as a third column (survey, not a default lane)

`scripts/parity.sh --engines interp,compiled,ruby --jobs 6 --verbose` on
2026-09-02 reported **12 pass, 20 xfail, 27 fail, 0 xpass**. The 20 xfail
specs stay green on their interp-vs-compiled reason, so the Ruby column was
only *examined* over the 39 specs where interp and compiled already agree —
and it disagreed on 27 of them. That is why `ruby` is off by default: it
would drown the interp-vs-compiled signal the suite exists to protect. Run
it on purpose when working on `implementations/ruby/`.

Every row below is "interp == compiled, ruby differs".

| Area | Spec | interp + compiled | ruby | Note |
|---|---|---|---|---|
| Arity | `arity_extra_args_named_spec.w` | extras silently dropped: `named.extra k:1,2` | `error: too many arguments for 'k' (3 for 2)`, exit 1 | Ruby is the *stricter* engine: these two specs pass on the default pair only because both native engines are equally lax about arity. |
| Arity | `arity_missing_args_spec.w` | missing args become nil/defaults | `error: missing argument: __arg2`, exit 1 | Same; the `__arg2` name leaks the desugaring of `@2`. |
| Numbers | `integer_boundaries_spec.w`, `integer_int_hint_spec.w` | `type` says `BigInt` past 2^47 | always `Int`; `int.tof` → `9.007199254740992e+15` | Ruby has one unbounded Integer, so the Int/BigInt boundary the other two expose does not exist. |
| Numbers | `integer_ops_spec.w` | `-7 / 2` → `-3`, `-7 % 2` → `-1` | `-4`, `1` (and `2 ** -1` → `1/2`, not `0.5`) | **Semantic, not cosmetic**: Ruby floor-divides where interp/compiled truncate toward zero, and returns a Rational for a negative power. |
| Numbers | `decimal_arithmetic_spec.w` | `1/3` → 12 significant digits | 32 digits (`0.3333…`) | Different default Decimal precision. |
| Numbers | `decimal_printing_spec.w`, `float_printing_spec.w`, `units_printing_spec.w`, `array_basics_spec.w`, `array_equality_sort_spec.w` | `0.5`, `5`, `123456789012345680`, `0.10000000000000001` | `0.5e0`, `5.0`, `1.2345678901234568e+17`, `0.1`; array elements inspect as `0.3e1`, `:sym` | Ruby prints through BigDecimal/Float `inspect`; the native engines print `%.17g` with a trailing-zero trim. Cosmetic but pervasive. |
| Containers | `hash_insertion_order_spec.w` | symbol-normalized keys, `{a: 1}`, `has true` | `{"a" => 1}`, `"name"` and `:name` are *distinct* keys, `has false`, then `error: undefined method '>'` | Ruby hashes do not fold string/symbol keys, so insertion order and size diverge as well as the printing. |
| Containers | `string_interpolation_spec.w` | `hash.interp {a: 1, b: 2}` | `{"a" => 1, "b" => 2}` | Same root. |
| Missing feature | `control_begin_rescue_spec.w` | full rescue matrix | `syntax on line 50: unexpected token ","` on `raise ArgumentError, "bad arg"` | The Ruby lexer/parser has no two-argument `raise`. |
| Missing feature | `control_case_recase_spec.w` | `recase` re-dispatches | `undefined local variable or method 'recase'` | `recase` was never ported to the Ruby engine. |
| Missing feature | `range_closed_form_sums_spec.w` | closed-form Σ sums | `can't lex anymore: Σ(x²)` | The Ruby lexer rejects the Σ/superscript surface entirely. |
| Missing feature | `string_unicode_spec.w` | `graphemes`, `upcase` of `ß`, emoji sizes | `undefined method 'graphemes'` | The UAX-29 grapheme work landed in `core/` only. |
| Missing feature | `datetime_timezone_spec.w` | `.tz` → `-300` | `undefined method 'tz'` | |
| Missing feature | `units_conversion_spec.w` | `2 km`, `6.242×10¹⁸ eV` | `undefined local variable or method 'km'`; `6241509074460760000.000000 eV` | Bare-unit attachment and scientific formatting are unported. |
| Missing feature | `date_arithmetic_spec.w` | `date + 210 days` | `cannot add Tungsten::Date to Quantity` | Date/Quantity arithmetic is unported. |
| Types | `cidr_ipv4_spec.w` | `type` → `IPv4`; `2001:db8:0:0:0:0:0:1` | `Tungsten::IP4` / `Tungsten::CIDR4`; `2001:db8::1` | Ruby leaks host class names through `type`, and compresses IPv6 where the others expand. |
| Types | `percent_spec.w` | `type` → `Quantity`; `30% of 100` → `3000%` | `Percentage`; `30.0` | Two different models of `%`; note the native engines' `3000%` is itself suspicious. |
| Classes | `class_constructors_spec.w` | `op.plus (4, 5)`, `to_s (3, 4)` | `to_s #<Point>`, then `undefined method '+'` — printing a **multi-kilobyte dump of the raw `WObject`/`WClass` Ruby objects** | Operator methods on user classes are not dispatched, and the error path inspects interpreter internals instead of the value. |
| Units | `units_derived_spec.w` | `100 ft²`, `1 cm³`, `10 m/s * 5 s` → `50 m` | `100 sqft`, `1 mL`, and **`15 zhang`** | The unit algebra picks a wrong derived unit (`zhang` is a Chinese length unit) — the most alarming single result in the survey. |
| Units | `units_arithmetic_spec.w` | `mul.float 0.5`, `eq.mixed false` | `1 m`, `true` | Scalar×quantity and cross-unit equality both differ. |
| Units | `currency_spec.w` | `-$2.25`, `$1234567.89` | `$-2.25`, `≈$1234568` | Sign placement, and the Ruby engine rounds the amount to an approximation. |
| Units | `duration_display_spec.w` | `1y2mo72h`, `500ms`, `210 d`, `2.0083333333333 h` | `1y2mo3d`, `500 ms`, `210 days`, `2.0083̅ h` | Duration normalization and unit pluralization differ; Ruby prints a repeating-decimal overline. |

### What the third column caught that the default pair cannot

- `(2.345).round(2)` prints `2` on **both** native engines (the digit
  argument is ignored and the value is rounded to an integer) where Ruby
  prints `2.35`; likewise `(~2.567).round(2)` → `3` vs `2.57`. A shared
  bug, invisible to interp-vs-compiled — added to the list below.
- The two arity specs (`arity_extra_args_named`, `arity_missing_args`) pass
  on the default pair only because both native engines accept wrong-arity
  calls; Ruby rejects them. Cf. the `arity_mixed_call_sites` xfail row,
  where the compiled path *does* reject — but only at emit time, and only
  when two call sites of one function disagree.

## Shared bugs (not parity — both engines fail the same way)

Kept out of the specs because a divergence spec needs at least one engine
to run to completion: `$10.00 / 3`, `$5.00 < $6.00`, `5.5 % 2`,
`2024-01-15 < 2024-02-01` (all "expected int, got numeric/packed"),
`super + "!"` in a value-returning override (super returns nil),
`e.message` on a builtin `TypeError`, `"banana".count("a")`.

Agreed-but-wrong (both engines produce the same answer, and it is the wrong
one — so the specs below stay green and the bug is recorded here instead):
`(2.345).round(2)` → `2` and `(~2.567).round(2)` → `3`; the digit argument
to `round` is dropped and the value is rounded to an integer. Caught by the
Ruby column (`2.35` / `2.57`); see `spec/parity/decimal_arithmetic_spec.w`
line 10 and `spec/parity/float_printing_spec.w` line 21.

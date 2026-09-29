# Cross-engine divergences (parity ledger)

One row per `## parity xfail` spec in this directory. Outputs are the
transcripts of `scripts/parity.sh --verbose` on 2026-09-02 (interp =
`bin/tungsten run --interpret`, compiled = `bin/tungsten compile`). When a
row's engines start to agree the run reports XPASS: drop the spec's header
and its row here in the same change. "Where to look" names the two code
paths that implement the surface independently.

| Area | Spec | Interpreter | Compiled | Hypothesis | Where to look |
|---|---|---|---|---|---|
| Arity | `arity_extra_args_named_spec.w` | raises `'g' takes 1..2 arguments, got 3` at the call (after earlier lines) | compile error `E_LOWER_ARITY`, no output | Same contract on both engines; the compiled engine enforces it at compile time. By design. | `compiler/lib/lowering/signatures.w` check_static_call_arity; `compiler/lib/interpreter.w` call_w_method |
| Arity | `arity_missing_args_spec.w` | raises `'add' takes 2 arguments, got 1` at the call | compile error `E_LOWER_ARITY`, no output | Same contract on both engines; compile-time vs call-time. By design. | same |
| Errors | `error_uncaught_format_spec.w` | `error: unhandled boom` + bare `--> file` | `unhandled exception: unhandled boom` + source excerpt + C backtrace with addresses | Two independent top-level error printers. | `compiler/tungsten.w:2620` (`format_runtime_error`); `runtime/runtime.c:48286` |
| Classes | `class_generics_spec.w` | `type(Box<Integer>.new(1))` → `Box` | `Box$Integer` | Monomorphization mangles the specialized class name and `type()` reports it; the interpreter never specializes (generics are compiled-only). | `lowering/monomorphize.w:42` (`mangled_specialized_name`) |
| Arity | `arity_mixed_call_sites_spec.w` | prints `slash.exact h:1,2`, then raises `'h' takes 2 arguments, got 3` | compile error `E_LOWER_ARITY`, no output | Same contract on both engines. The extra call is rejected before a second WIRE signature is emitted. Compile-time vs call-time. By design. | `compiler/lib/lowering/signatures.w` check_static_call_arity; `compiler/lib/interpreter.w` call_w_method |

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
| Numbers | `integer_boundaries_spec.w`, `integer_int_hint_spec.w` | `type` says `BigInt` past 2^47 | always `Int`; `int.tof` → `9.007199254740992e+15` | Ruby has one unbounded Integer, so the Int/BigInt boundary the other two expose does not exist. |
| Numbers | `integer_ops_spec.w` | `-7 / 2` → `-3`, `-7 % 2` → `-1` | `-4`, `1` (and `2 ** -1` → `1/2`, not `0.5`) | **Semantic, not cosmetic**: Ruby floor-divides where interp/compiled truncate toward zero, and returns a Rational for a negative power. |
| Numbers | `decimal_arithmetic_spec.w` | `1/3` → 12 significant digits | 32 digits (`0.3333…`) | Different default Decimal precision. Round digits now agree (`2.35`). |
| Numbers | `decimal_printing_spec.w`, `float_printing_spec.w`, `units_printing_spec.w`, `array_basics_spec.w`, `array_equality_sort_spec.w` | `0.5`, `5`, `123456789012345680`, `0.10000000000000001` | `0.5e0`, `5.0`, `1.2345678901234568e+17`, `0.1`; array elements inspect as `0.3e1`, `:sym` | Ruby prints through BigDecimal/Float `inspect`; the native engines print `%.17g` with a trailing-zero trim. Cosmetic but pervasive. |
| Containers | `hash_insertion_order_spec.w` | symbol-normalized keys, `{a: 1}`, `has true` | `{"a" => 1}`, `"name"` and `:name` are *distinct* keys, `has false`, then `error: undefined method '>'` | Ruby hashes do not fold string/symbol keys, so insertion order and size diverge as well as the printing. |
| Containers | `string_interpolation_spec.w` | `hash.interp {a: 1, b: 2}` | `{"a" => 1, "b" => 2}` | Same root. |
| Missing feature | `control_begin_rescue_spec.w` | full rescue matrix | `syntax on line 50: unexpected token ","` on `raise ArgumentError, "bad arg"` | The Ruby lexer/parser has no two-argument `raise`. |
| Types | `cidr_ipv4_spec.w` | `type` → `IPv4`; `2001:db8:0:0:0:0:0:1` | `Tungsten::IP4` / `Tungsten::CIDR4`; `2001:db8::1` | Ruby leaks host class names through `type`, and compresses IPv6 where the others expand. |
| Classes | `class_constructors_spec.w` | `op.plus (4, 5)`, `to_s (3, 4)` | `to_s #<Point>`, then `undefined method '+'` — printing a **multi-kilobyte dump of the raw `WObject`/`WClass` Ruby objects** | Operator methods on user classes are not dispatched, and the error path inspects interpreter internals instead of the value. |
| Units | `units_arithmetic_spec.w` | `mul.float 0.5`, `eq.mixed true` | `1 m`, `true` | `~0.5 m * 2` still prints `0.5` natively vs `1 m` in Ruby. Cross-unit `==` now agrees (`1 km == 1000 m`). |
| Units | `duration_display_spec.w` | `1y2mo72h`, `500ms`, `210 d`, `2.0083333333333 h` | `1y2mo3d`, `500 ms`, `210 days`, `2.0083̅ h` | Duration normalization and unit pluralization differ; Ruby prints a repeating-decimal overline. |

Ported and now agreeing (dropped from the table): recase, Σ/superscript sums, graphemes, DateTime `.tz`, unit conversion/`km/h`/eV, date+quantity arithmetic, currency sign, percent `200 * 15%` / `200 + 15%`, derived units (`50 m` not `15 zhang`).

### What the third column caught that the default pair cannot

- The two arity specs (`arity_extra_args_named`, `arity_missing_args`) used
  to pass on the default pair only because both native engines were lax;
  extra/missing arity is now rejected (compiled at compile time, interp at
  the call). Remaining xfail is transcript shape, not the contract.
- `(2.345).round(2)` / `(~2.567).round(2)` used to drop the digit count on
  both native engines; Decimal#round now honors digits via the runtime IC
  (`w_decimal_round`), and Float#round already scaled by `10^digits`.

## Shared bugs (not parity — both engines fail the same way)

Kept out of the specs because a divergence spec needs at least one engine
to run to completion: `$5.00 < $6.00`, `5.5 % 2`
(both "expected int, got numeric"),
`e.message` on a builtin `TypeError`, `"banana".count("a")`.

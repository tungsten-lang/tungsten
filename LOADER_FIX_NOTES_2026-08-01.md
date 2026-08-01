# Loader: stdlib resolution no longer depends on the working directory — FIXED

**Status: fixed and verified.** `use algebra` now resolves from any working
directory. Verified from `~/math`, `/tmp`, and `/`, with
`spec/core/algebra_{s_units,quartics,descent}_spec.w` all passing as controls.

| Item | Status |
|---|---|
| Loader / stdlib resolution | **Fixed** — §1–§3 |
| BigInt subtag migration | **Was never broken** — §4 |
| The build | **Was never broken** — I was using the wrong command — §5 |

## 1. Symptom

```sh
cd ~/tungsten && bin/tungsten run ~/math/foo.w   # worked
cd ~/math     && tungsten run foo.w              # runtime error:
                                                 # undefined method 'starts_with?' for nil
```

for any `foo.w` containing `use algebra`. Programs with no imports worked
everywhere. The message names neither the module nor the path, so it reads
like a library defect; the library was fine throughout.

## 2. Root cause

Found by symbolicating the crash backtrace against
`bin/tungsten-compiler.sidemap` (the mangled frames were
`__wy_148b869c` → `Interpreter#eval_use`, `__wy_8bae1b83` →
`Interpreter#parse_source`, `__wy_620bb40f` → `strip_bash_shebang`).

`bin/tungsten run` executes through **`compiler/lib/interpreter.w`**, which
has its **own** module resolver — `Interpreter#resolve_use_path` — entirely
separate from `compiler/lib/loader.w`. Its root finder,
`find_use_project_root`, is anchored **only** on a `Bitfile`:

```
if dir != ""            # walk the source file's ancestry for a Bitfile
  ...
if file?("Bitfile")     # else fall back to the *current working directory*
  return "."
""                      # else give up
```

It has **no `core/tungsten.w` anchor and no `TUNGSTEN_ROOT` fallback** —
unlike `loader.w:find_core_root`, which has both. So for a script outside any
Tungsten project:

1. ancestry has no `Bitfile` → `""`;
2. cwd has no `Bitfile` → still `""`;
3. every `if project_root != ""` stdlib branch is skipped;
4. resolution falls through to `return path` — a nonexistent sibling
   `~/math/algebra.w`;
5. `read_file` returns `nil`;
6. `parse_source(nil)` → `strip_bash_shebang(nil)` → **`starts_with?` on nil.**

It appeared to work from `~/tungsten` for one reason only: that directory
contains a `Bitfile`, so step 2 succeeded. The dependency on cwd was the
symptom, not the cause.

## 3. The fix

In `compiler/lib/interpreter.w`:

- Added **`find_use_core_root(dir)`**, mirroring `loader.w:find_core_root`:
  walk the source ancestry for `core/tungsten.w`, then the cwd, then fall back
  to `env("TUNGSTEN_ROOT")` (which `bin/tungsten` exports at line 30).
- The `core/`-prefixed branch now uses it instead of `find_use_project_root`.
- Added a final stdlib lookup anchored on that root, after the existing
  Bitfile-anchored one, guarded by `core_root != project_root` so it only runs
  when it would resolve somewhere new.

This gives the intended split: **local project files resolve against the
program's own root; core files resolve against the install root.** A project's
own `core/` still wins, so in-tree development is unchanged.

A parallel change is also present in `compiler/lib/loader.w` (the compiled
path's stdlib lookup, which had the same Bitfile-only gating). It was not what
fixed `run`, but it closes the same hole on the compile path and is retained.

## 4. BigInt subtag migration: healthy, do not revert

`runtime/wvalue.h` promotes BigInt to its own object subtag (slot 2) with
`W_TYPE_BIGINT = 11` demoted to a live/parked allocation marker. Runtime and
compiler agree (`runtime.c` boxes with `w_box_ptr(b, W_SUBTAG_BIGINT)`;
`runtime.h:1682` tests the subtag; `runtime.c:35920` dispatches on it;
`compiler/lib/lowering/types.w:82` maps `"BigInt" => 0x02`, committed). The
runtime's own NaN-box self-test passes completely:

```sh
A=$(ls -t build/cache/bootstrap-runtime-*.a | head -1)
cc -O1 -I runtime -o /tmp/test_nanbox runtime/test_nanbox.c "$A" && /tmp/test_nanbox
```

Reverting the header alone breaks the runtime C build (`event_kqueue.c`) — the
migration spans more files and is coherent as it stands.

## 5. Three traps that cost me most of this session

1. **`bootstrap` is not `build`.** `bin/tungsten bootstrap` builds stage 1
   only and produced a compiler that failed on trivial programs; I repeatedly
   misread that as "the worktree is broken." **`bin/tungsten build`** (full
   stage1+stage2 + bits) produces a working compiler and is what to use.
2. **`cp` over a signed arm64 binary invalidates its signature**, after which
   macOS `SIGKILL`s it at exec — exit 137, no output, no message. Any binary
   moved into place by copy needs `codesign -s - -f <binary>`.
3. **`<<` is the accumulator-append operator, not a general print.** A method
   signature ending in `[]` or `""` (see `core/traits/enumerable.w`:
   `-> to_a() []`, `-> map(&block) []`, `-> join(sep = "") ""`) declares an
   implicit `out` accumulator that the method returns. At top level `out` is
   stdout. Emitting `<<` inside a method that declares no accumulator fails
   with `undefined method 'out' for Object` — which is what my first
   instrumentation attempt did, wasting a rebuild and a wrong diagnosis.

One genuine build fix was required along the way and is applied:
`bin/commands/bootstrap_helpers.sh` expanded `"${external_inputs[@]}"` on a
possibly-empty array under `set -u`, fatal on the macOS system bash 3.2.
Guarded with `${arr[@]+"${arr[@]}"}`.

## 6. Verification

```sh
cd ~/tungsten && bin/tungsten build && codesign -s - -f bin/tungsten-compiler
printf 'use algebra\n<< FiniteField.new(11).order.to_s\n' > ~/math/_t.w
cd ~/math && tungsten run _t.w    # => 11
cd /tmp   && tungsten run ~/math/_t.w
cd /      && tungsten run ~/math/_t.w
```

All three print. Controls: `algebra_s_units_spec`, `algebra_quartics_spec`,
and `algebra_descent_spec` all pass, and
`~/math/cubic-shells/shell_width_zeta_jacobian_order.w` runs from `~/math`,
giving `#J(F_5) = 222`, `#J(F_7) = 556`, `#J(F_11) = 912`, `#J(F_17) = 6478`.

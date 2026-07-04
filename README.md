# The Tungsten Programming Language

**Pseudocode that runs.**

*Currency and percentages*

```tungsten
price = $499.99

<< price - 15%           # => ≈$424.99
<< price - 15% + 8.25%   # => ≈$460.05

<< $3.50 - 25¢           # =>  $3.25
<< 20% - 15%             # =>  5%
```

*Units of measurement*

```tungsten
c = 299_792_458 m/s
m = 1 kg

<< e = m·c²              # => ≈8.988×10¹⁶ J

<< 3 ft + 12 in          # => 4 ft
<< 10 ft * 10 ft         # => 100 ft²
<< 1 cm * 1 cm * 1 cm    # => 1 cm³

<< 2 m + 2 lbs           # => error: dimension mismatch
```

*Unit conversion with `|` (or `»`)*

```tungsten
c = 299_792_458 m/s

<< 1 acre | sqft         # => 43560 sqft
<< 6 ft + 2 in | cm(2)   # => 187.96 cm
# (2) rounds to 2 decimal places
<< 5 kg + 3 kg | lb(2)   # => 17.64 lb

# light travels this far in one nanosecond
<< c * 1 ns | cm(2)      # => 29.98 cm

# a mass of one gram contains this much energy
<< 1 g · c²  | J         # => 89875517873681.764 J

# string interpolation with inline conversion
<< "Light travels [c * 1 s | km] in one second"   # => Light travels 299792.458 km in one second
<< "A marathon is [42195 m | mi(1)]"              # => A marathon is 26.2 mi
```

> **Preview status:** temperature (`350 °F | °C`) and compound-unit
> (`60 mi/h | km/h`) conversions run on the Ruby reference engine
> (`bin/tungsten --ruby`) today; compiler support is landing.

*Classes without the noise*

```tungsten
+ Point
  -> new(@x, @y, @z) ro

  -> distance/1
    dx = x - x'
    dy = y - y'
    dz = z - z'

    (dx.sq + dy.sq + dz.sq).sqrt

  # or, if you prefer
  -> distance/1
    √(Δx² + Δy² + Δz²)

<< Point(3, 4, 0).distance(Point(0, 0, 0))   # => 5
```

The constructor binds `@x, @y, @z` straight to fields; the trailing `ro`
generates the readers. `-> distance/1` declares a one-argument method; the
prime (`x'`) reads the argument's same-named property — "my x minus their
x" — and `Δx` is shorthand for exactly that difference. `Point(3, 4, 0)`
constructs without `.new`.

Tungsten is an object-oriented language that reads like the pseudocode in your notebook. Fewer tokens than the alternatives — for humans and LLMs alike.

For scientists, mathematicians, and anyone who thinks in code.

No ends. No braces. No colons. No return. Just the algorithm.

| Feature       | Tungsten               | Python                       | Ruby                          |
|---------------|------------------------|------------------------------|-------------------------------|
| Output        | `<< x`                 | `print(x)`                   | `puts x`                      |
| Class         | `+ Point`              | `class Point:`               | `class Point ... end`         |
| Method        | `-> distance/1`        | `def distance(self, other):` | `def distance(other) ... end` |
| Map           | `list.map -> item ** 2` | `[x ** 2 for x in list]`    | `list.map { it ** 2 }`        |
| Swap          | `a <> b`               | `a, b = b, a`                | `a, b = b, a`                 |
| Interpolation | `"[name]"`             | `f"{name}"`                  | `"#{name}"`                   |
| Block ending  | (dedent)               | (dedent)                     | `end`                         |

*Compile-time frees*

The compiler runs an escape analysis at build time: heap values that
provably never escape their scope get their `free` inserted automatically,
so short-lived values are reclaimed deterministically the moment they go
out of scope. It's on by default (`TUNGSTEN_FREE=0` disables it) and costs
nothing at runtime — the decision is made when the binary is built, not
while it runs.

## Install & Run

**One-line install** (macOS or Linux):

```bash
curl -fsSL https://tungsten-lang.org/install | sh
```

**Or build from source:**

```bash
git clone https://github.com/tungsten-lang/tungsten
cd tungsten
bin/tungsten start          # orient: a map + your next step (works before building)
bin/tungsten build          # bootstraps the self-hosted compiler
```

Then run your first program:

```bash
bin/tungsten -e '<< 1 + 1'          # => 2

echo '<< "hello world"' > hi.w
bin/tungsten hi.w                   # => hello world
```

New here? `bin/tungsten start` prints a map of the language and tooling and
points you at the next step, and the [Getting Started guide][guide] walks you
through it. Building an AI agent against Tungsten? `bin/tungsten start --agent`.

## Build & Run Flags

`bin/tungsten FILE.w` picks the fastest path automatically. When you want an
explicit mode:

| Flag | What it does |
|------|--------------|
| *(none)* `bin/tungsten f.w` | Run `f.w` (compiles or interprets as needed). |
| `-e '<expr>'` | Evaluate a one-liner. |
| `-o OUT f.w` | Compile `f.w` to a native binary `OUT` (via LLVM → clang). |
| `-c`, `--check` | Syntax-check only; prints `200 OK`. |
| `--repl` | Interactive REPL (`wit`). |
| `--ast` / `--ll` | Print the AST / the emitted LLVM IR (don't run). |
| `--ruby` | Run via the Ruby tree-walking interpreter (no native compile). |
| `-j N` | Parallel jobs (defaults to CPU count). |

**Performance flags** (for `-o` native builds):

| Flag | What it does |
|------|--------------|
| `--fast` (`-fast`) | Fast floating-point: FMA + reassociation + reciprocals + `nnan`/`ninf`, **and** passes `-ffast-math` to the backend so LLVM auto-vectorizes clean scalar float loops (reductions/maps over typed `f64[]`/`f32[]`) into SIMD — NEON, AVX2/AVX-512, or SVE per the target. Changes FP semantics, so it's opt-in. |
| `--release` | Whole-program optimization build (`-O3 -flto -march=native`); clang inlines runtime helpers into hot paths. |
| `--no-lto` | Skip link-time optimization (faster edit-compile loop, slower runtime). |

**Rule of thumb:** numeric / array-heavy code → `bin/tungsten --fast -o out f.w`.
The compiler always targets `-march=native`, so it uses whatever vector ISA the
build host exposes; `--fast` is what unlocks the auto-vectorizer for
floating-point (integer loops vectorize without it).

**See the REPL live:** an 11-second real session —
[repl-demo.cast](sites/tungsten-lang.org/repl-demo.cast)
(`asciinema play sites/tungsten-lang.org/repl-demo.cast`; re-record with
`ruby scripts/record-repl-demo.rb`, GIF via [`agg`](https://github.com/asciinema/agg)).

**Prerequisites:** `git`, `clang`/LLVM, `make`, and Ruby (drives the bootstrap).
Run `bin/tungsten doctor` to check your toolchain.

**Editor support** (VS Code extension + LSP for Neovim/Helix/anything):
see [doc/editors.md](doc/editors.md).

> **On Windows?** Tungsten targets macOS and Linux today — use
> [WSL2](doc/wsl2.md) for a full Linux environment, then follow the Linux steps.

## About

`/ˈtʌŋstən/ TUNG-stən;`

From the Swedish _tung sten_ — literally _heavy stone_. Tungsten is also element <small>__₇₄W__</small>. The shorthand <small>__W__</small> appears throughout: for file extensions `.w`, `.ws`, and `.wd`; reserved identifiers `W_`; and in tool names like <small>_`wit`_</small> and <small>_`wake`_</small>.

Tungsten Carbide, <small>__WC__</small>, is a bit harder than Ruby.

## Ecosystem

__Bit__ is Tungsten's package manager. Find, install, and test shared code.

See [tungsten-lang.org][home] for the [Specification][spec], [Documentation][docs], [Getting Started Guide][guide], [Tutorial][tutorial], and [Release Notes][changes].


[home]:     https://www.tungsten-lang.org
[spec]:     https://www.tungsten-lang.org/specification
[docs]:     https://www.tungsten-lang.org/documentation
[guide]:    https://www.tungsten-lang.org/guides/getting-started
[tutorial]: https://www.tungsten-lang.org/tutorial/primer
[changes]:  https://www.tungsten-lang.org/changelog
[slack]:    https://tungsten.slack.com

## Compiler Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TUNGSTEN_FREE` | on | Compile-time free insertion for non-escaped heap values. Set `TUNGSTEN_FREE=0` to disable. |
| `TUNGSTEN_CLANG_OPT` | `-O3` | Optimization flags handed to the backend clang for `-o` native builds. `--fast` defaults this to `-O3 -ffast-math`; set it explicitly to override (e.g. `-O2`, or `-O3 -ffast-math` to force auto-vectorization without `--fast`'s other effects). |
| `TUNGSTEN_MARCH_ARGS` | `-march=native -mtune=native` | Target CPU/features for codegen. Set to a portable baseline (e.g. `-march=x86-64-v3`) for distributable binaries. |
| `TUNGSTEN_BACKTRACE` | off | Set to `1` to include the full C backtrace in runtime error dumps (default shows only the Tungsten-level frames). |

## Community

Questions or suggestions? Open an issue on GitHub or join the slack group at [tungsten.slack.com][slack].

## Contributing

1. Fork it (https://github.com/tungsten-lang/tungsten/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Read the [contributing guide](https://github.com/tungsten-lang/tungsten/blob/master/doc/CONTRIBUTING.md) for details.

## License

Tungsten is licensed under either of

* Apache License, Version 2.0, with the LLVM Exception
  ([LICENSE-APACHE](LICENSE-APACHE) or <https://www.apache.org/licenses/LICENSE-2.0>;
  exception at <https://spdx.org/licenses/LLVM-exception.html>)
* MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

at your option — in [SPDX](https://spdx.dev) terms,
`MIT OR Apache-2.0 WITH LLVM-exception`.

The LLVM Exception waives the Apache attribution requirements (Sections 4(a),
4(b), 4(d)) for runtime-library code that the compiler embeds into your compiled
binaries, so programs built with Tungsten carry no attribution obligation for
the embedded runtime.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in Tungsten by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.

## Author

Tungsten is designed and maintained by Erik Peterson.

[The Book of Uncertain Light](https://uncertainlight.com)

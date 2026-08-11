# The Tungsten Programming Language

`/ˈtʌŋstən/ TUNG-stən;`

From the Swedish _tung sten_ — literally _heavy stone_. Tungsten is also element <small>__₇₄W__</small>. The shorthand <small>__W__</small> appears throughout: for file extensions `.w`; reserved identifiers `W_`; and in tool names like <small>_`wit`_</small> and <small>_`wake`_</small>.

Tungsten Carbide, <small>__WC__</small>, is a bit harder than Ruby.

Built for scientists, mathematicians, and anyone who thinks in code.

## Installation

**One-line install** (macOS or Linux):

```bash
curl -fsSL https://tungsten-lang.org/install | sh
```

or, build from source:

```bash
git clone https://github.com/tungsten-lang/tungsten

cd tungsten

bin/tungsten bootstrap
```

Run your first program:

```bash
bin/tungsten -e '<< 1 + 1'          # => 2

echo '<< "hello world"' > hello.w
bin/tungsten hello.w                # => hello world
```

then, see some next steps:

```bash
bin/tungsten start
```

_Are you an agent?_

```bash
bin/tungsten start --agent
```

## Ecosystem

__Bit__ is Tungsten's package manager. Find, install, and manage shared code.

See [tungsten-lang.org][home] for more information.

[home]:     https://www.tungsten-lang.org


## Getting Started

New to Tungsten? Read the [Getting Started](doc/getting-started/) guide.

**Currency and percentages**

```tungsten
price = $499.99

<< price - 15%           # => ≈$424.99
<< price - 15% + 8.25%   # => ≈$460.05

<< $3.50 - 25¢           # =>  $3.25
<< 20% - 15%             # =>  5%
```

**Units of measurement**

```tungsten
c = 299_792_458 m/s
m = 1 kg

<< e = m·c²              # => ≈8.988×10¹⁶ J

<< 3 ft + 12 in          # => 4 ft
<< 10 ft * 10 ft         # => 100 ft²
<< 1 cm * 1 cm * 1 cm    # => 1 cm³

<< 2 m + 2 lbs           # => error: dimension mismatch
```

**Unit conversion with pipe** (or `»`)

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

**Classes without the noise**

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

## Language Comparison

Tungsten is an object-oriented language that reads like the pseudocode in your notebook. Token efficient, for humans and LLMs alike.


<small>

| Feature         | Tungsten                 | Python                         | Ruby                            |
| --------------- | ------------------------ | ------------------------------ | ------------------------------- |
| Output          | `<< x`                   | `print(x)`                     | `puts x`                        |
| Class           | `+ Point`                | `class Point:`                 | `class Point ... end`           |
| Method          | `-> distance/1`          | `def distance(self, other):`   | `def distance(other) ... end`   |
| Map             | `list/sq`                | `[x ** 2 for x in list]`       | `list.map { it ** 2 }`          |
| Swap            | `a <> b`                 | `a, b = b, a`                  | `a, b = b, a`                   |
| Interpolation   | `"[name]"`               | `f"{name}"`                    | `"#{name}"`                     |
| Block ending    | (dedent)                 | (dedent)                       | `end`                           |

</small>

## Usage

**Prerequisites:** `git`, `clang`, `LLVM`, `make` (and `lld` + `libzstd` headers). LLVM/Clang 22 or newer is recommended.

To check your toolchain:

```
bin/tungsten doctor
```

On a fresh clone, build the compiler with:

```
bin/tungsten bootstrap
```

Run a Tungsten program:

```
bin/tungsten FILE.w
```

When you want an explicit mode:

<small>

| Flag                           | What it does                                                   |
| ------------------------------ | -------------------------------------------------------------- |
| `-e EXPRESSION`                | Evaluate an expression                                         |
| `-o OUT FILE.w`                | Compile `FILE.w` to a native binary named `OUT`                |
| `-c`, `--check`                | Syntax-check only; prints `200 OK`                             |
| `console`                      | Interactive REPL (Read-Evaluate-Print-Loop)                    |
| `--ast`                        | Skip execution and print the AST                               |
| `--ll`                         | Skip execution and print the LLVM IR                           |

</small>

**Developer options**
<small>

| Flag       | What it does                                                                 |
| ---------- | ---------------------------------------------------------------------------- |
| `--ruby`   | Ruby tree-walking interpreter, or Ruby stage-1 bootstrap for `build`.        |
| `--spinel` | Spinel stage-0 bootstrap for `build` (experimental; mutually exclusive with `--ruby`). |

Ruby is **not** required for normal; it is needed for the `--ruby` developer option.

</small>


**Build profiles and targets** (`build`, `bootstrap`, and `-o` native builds):

<small>

| Flag              | What it does |
| ----------------- | ------------ |
| `--release`       | Release profile: `-O3`, full LTO, no development safety checks, and reduced runtime metadata. Defaults to `--no-debug`. |
| `--debug`         | Include debug symbols, safety checks, and full runtime/source-location metadata. Overrides the release profile's no-debug default. |
| `--no-debug`      | Omit debug symbols and development checks. |
| `--cpu CPU`       | Optimize for a CPU or ISA group. `v1`, `v2`, `v3`, `v4`, and `native` are shorthand for the corresponding x86-64 group/native host; LLVM names such as `apple-m5` and `neoverse-v2` are also accepted. |
| `--native`        | Compatibility shorthand for `--cpu native`. Local builds use the configured CPU, or native when none is configured. |
| `--target TRIPLE` | Generate code for another target triple. Combine with `--cpu` to mean “runs on this target, optimized for this CPU variant.” A cross target without `--cpu` uses clang's target baseline. |
| `--portable`      | On `build`/`bootstrap`, emit both documented release binaries: x86-64-v2 and x86-64-v3 under `build/releases/<triple>/<cpu>/`. |
| `--fast`          | Enable fast, non-IEEE floating-point transformations. |
| `--no-lto`        | Skip link-time optimization for a direct compile. |

</small>

CPU and optimization profile are independent. For example:

```bash
bin/tungsten build --release --cpu apple-m5
bin/tungsten build --release --target x86_64-unknown-linux-gnu --cpu v3
bin/tungsten build --portable
```

`bin/tungsten release [VERSION]` runs the root `rake` gate, creates and pushes
an annotated version tag, and lets GitHub build and attest the native release
matrix. ARM64 uses each target's portable baseline; x86_64 ships both v2 and
v3 packages on macOS and Linux. Use `--dry-run` to validate without tagging.

Tungsten's documented x86-64 release set is:

| Artifact | Minimum ISA | Representative minimum CPUs |
| -------- | ----------- | ---------------------------- |
| `x86-64-v2` | <small>SSE3, SSSE3, SSE4.1/4.2, POPCNT, CMPXCHG16B, LAHF/SAHF</small> | Intel Nehalem (2008) or AMD Bulldozer (2011) and newer |
| `x86-64-v3` | <small>v2 plus AVX/AVX2, BMI1/2, F16C, FMA, LZCNT, MOVBE, OSXSAVE</small> | Intel Haswell (2013) or AMD Excavator/Zen-class CPUs and newer |

The ISA feature group—not the marketing name—is authoritative, especially in virtual machines where the hypervisor may hide features.

Local defaults live in `~/.tungsten/config`:

```toml
[build]
cpu = apple-m5
cc = clang
```

For Homebrew LLVM, run `brew --prefix llvm` and set `cc` to that prefix
followed by `/bin/clang`; Tungsten does not assume a Homebrew install root.


> **_On Windows?_** Tungsten targets macOS and Linux
> Use [WSL2](doc/WSL2.md) for a full Linux environment, then follow the Linux steps.

### Environment Variables

| Variable              | Default                       | Description                                                                                                 |
| --------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `TUNGSTEN_FREE`       | 1                             | Compile-time free insertion for non-escaped heap values. Set `TUNGSTEN_FREE=0` to disable.                  |
| `TUNGSTEN_CLANG_OPT`  | `-O3`                         | Optimization flags for clang. `--fast` defaults this to `-O3 -ffast-math`                                   |
| `TUNGSTEN_CPU`        | `native`                      | CPU name used when `--cpu` is absent; normally loaded from `[build] cpu` in `~/.tungsten/config`. |
| `TUNGSTEN_CC`         | `clang`                       | C/LLVM driver; normally loaded from `[build] cc` when configured. |
| `TUNGSTEN_MARCH_ARGS` | derived from CPU              | Legacy low-level override for clang CPU flags. Prefer `--cpu` or `[build] cpu`. |
| `TUNGSTEN_BACKTRACE`  | off                           | Set to `1` to include full C backtrace in error dumps (defaults to only Tungsten-level frames).             |

## Contributing

1. [Fork the Tungsten repo](https://github.com/tungsten-lang/tungsten/fork)
2. `git checkout -b new-feature`
3. `git commit -am 'Add some feature'`
4. `git push origin new-feature`
5. Create a new Pull Request

Read the [contributing guide](https://github.com/tungsten-lang/tungsten/blob/master/doc/CONTRIBUTING.md) for details.

## Feedback

Issues, questions, or suggestions? Open an issue on GitHub.

## License

Tungsten is licensed under your choice of:

* [Apache License](https://www.apache.org/licenses/LICENSE-2.0), Version 2.0, with the [LLVM Exception](https://spdx.org/licenses/LLVM-exception.html)
* [MIT License](https://opensource.org/licenses/MIT)

In [SPDX](https://spdx.dev) terms:

> `MIT OR Apache-2.0 WITH LLVM-exception`

> The LLVM Exception waives the Apache attribution requirements (Sections 4(a),
> 4(b), 4(d)) for runtime-library code that the compiler embeds into your compiled
> binaries, so programs built with Tungsten carry no attribution obligation for
> the embedded runtime.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in Tungsten by you, as defined in the Apache license, shall be
dual licensed as above, without any additional terms or conditions.

If you do state otherwise, your contribution will likely be rejected.

## Author

Tungsten is designed and implemented by Erik Peterson.

Feed your LLMs: [The Book of Uncertain Light](https://uncertainlight.com)

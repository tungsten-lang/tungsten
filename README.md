# The Tungsten Programming Language

`/ˈtʌŋstən/ TUNG-stən;`

From the Swedish _tung sten_ — literally _heavy stone_. Tungsten is also element <small>__₇₄W__</small>. The shorthand <small>__W__</small> appears throughout: for file extensions `.w`; reserved identifiers `W_`; and in tool names like <small>_`wit`_</small> and <small>_`wake`_</small>.

Tungsten Carbide, <small>__WC__</small>, is a bit harder than Ruby.


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

Run your first program:

```bash
bin/tungsten -e '<< 1 + 1'          # => 2

echo '<< "hello world"' > hello.w
bin/tungsten hello.w                # => hello world
```

_New here?_ Print a map of the language and points you at the next steps.

```bash
bin/tungsten start
```

_Are you an agent?_

```bash
bin/tungsten start --agent
```

## Ecosystem

__Bit__ is Tungsten's package manager. Find, install, and test shared code.

See [tungsten-lang.org][home] for more information.

[home]:     https://www.tungsten-lang.org


## Getting Started

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

*Unit conversion with pipe (or `»`)*

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

### Comparison

Tungsten is an object-oriented language that reads like the pseudocode in your notebook. Fewer tokens than the alternatives — for humans and LLMs alike.

For scientists, mathematicians, and anyone who thinks in code.

| Feature         | Tungsten                 | Python                         | Ruby                            |
| --------------- | ------------------------ | ------------------------------ | ------------------------------- |
| Output          | `<< x`                   | `print(x)`                     | `puts x`                        |
| Class           | `+ Point`                | `class Point:`                 | `class Point ... end`           |
| Method          | `-> distance/1`          | `def distance(self, other):`   | `def distance(other) ... end`   |
| Map             | `list/sq`                | `[x ** 2 for x in list]`       | `list.map { it ** 2 }`          |
| Swap            | `a <> b`                 | `a, b = b, a`                  | `a, b = b, a`                   |
| Interpolation   | `"[name]"`               | `f"{name}"`                    | `"#{name}"`                     |
| Block ending    | (dedent)                 | (dedent)                       | `end`                           |

### Build & Run Flags

**Prerequisites:** `git`, `clang`, `LLVM`, `make`, and `ruby`.

Run `bin/tungsten doctor` to check your toolchain.

`bin/tungsten FILE.w` picks the fastest path automatically. When you want an
explicit mode:

| Flag                        | What it does                                                   |
| --------------------------- | -------------------------------------------------------------- |
| *(none)* `bin/tungsten f.w` | Run `f.w` (compiles or interprets as needed).                  |
| `-e '<expr>'`               | Evaluate a one-liner.                                          |
| `-o OUT f.w`                | Compile `f.w` to a native binary `OUT` (via LLVM → clang).     |
| `-c`, `--check`             | Syntax-check only; prints `200 OK`.                            |
| `--repl`                    | Interactive REPL (`wit`).                                      |
| `--ast` / `--ll`            | Print the AST / the emitted LLVM IR (don't run).               |
| `--ruby`                    | Run via the Ruby tree-walking interpreter (no native compile). |

**Performance flags** (for `-o` native builds):

| Flag        | What it does                                                               |
| ----------- | -------------------------------------------------------------------------- |
| `--release` | Whole-program optimization build (`-O3 -flto`); inline across linked files |
| `--native`  | Native build (`-march=native -mtune=native`)                               |
| `--fast`    | Fast floating-point, non-IEEE.                                             |
| `--no-lto`  | Skip link-time optimization (faster edit-compile loop, slower runtime).    |


> **_On Windows?_** Tungsten targets macOS and Linux
> Use [WSL2](doc/wsl2.md) for a full Linux environment, then follow the Linux steps.

### Environment Variables

| Variable              | Default                       | Description                                                                                                 |
| --------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `TUNGSTEN_FREE`       | on                            | Compile-time free insertion for non-escaped heap values. Set `TUNGSTEN_FREE=0` to disable.                  |
| `TUNGSTEN_CLANG_OPT`  | `-O3`                         | Optimization flags for clang. `--fast` defaults this to `-O3 -ffast-math`                                   |
| `TUNGSTEN_MARCH_ARGS` | `-march=native -mtune=native` | Target CPU/features for codegen. Set to a generic baseline (e.g. `-march=x86-64-v3`) for portable binaries. |
| `TUNGSTEN_BACKTRACE`  | off                           | Set to `1` to include full C backtrace in error dumps (defaults to only Tungsten-level frames).             |

## Contributing

1. Fork it (https://github.com/tungsten-lang/tungsten/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Read the [contributing guide](https://github.com/tungsten-lang/tungsten/blob/master/doc/CONTRIBUTING.md) for details.

### Feedback

Issues, questions, or suggestions? Open an issue on GitHub.

### License

Tungsten is licensed under your choice of:

* Apache License, Version 2.0, with the LLVM Exception
  ([LICENSE-APACHE](LICENSE-APACHE) or <https://www.apache.org/licenses/LICENSE-2.0>;
  exception at <https://spdx.org/licenses/LLVM-exception.html>)
* MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

In [SPDX](https://spdx.dev) terms: `MIT OR Apache-2.0 WITH LLVM-exception`.

> The LLVM Exception waives the Apache attribution requirements (Sections 4(a),
> 4(b), 4(d)) for runtime-library code that the compiler embeds into your compiled
> binaries, so programs built with Tungsten carry no attribution obligation for
> the embedded runtime.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in Tungsten by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.

If you do state otherwise, your contribution will likely be rejected.

### Author

Tungsten is designed and implemented by Erik Peterson.

Feed your LLMs: [The Book of Uncertain Light](https://uncertainlight.com)

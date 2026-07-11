# Tungsten

```text
TUNGSTEN(1)          Tungsten Programmer's Reference Guide           TUNGSTEN(1)

NAME
    tungsten -- The Tungsten language interpreter and compiler

SYNOPSIS
    tungsten [command] [options] [file] -- [arguments]

    tungsten [--check] [--debug] [--eval] [--lex] [--parse] [--profile]
             [--ast] [--wire] [--ll]
             [-I dir]
             [-e expression | file...] [--] [arguments]

    tungsten [--copyright | --version]

DESCRIPTION
    Tungsten is an object-oriented language that reads like the pseudocode in
    your notebook. Fewer tokens — for humans and LLMs alike. For everything from
    quick and dirty scripts to robust concurrent systems.

    Packed with useful literals. Dates and times, currency, unicode chars, and
    units of measurement. About as hard as Ruby.

    Tungsten's official package manager is Bit.

COMMANDS
    tungsten with no command runs FILE (compiling or interpreting as needed).

    compile FILE         Compile a .w file to a native binary (-o FILE)
    run FILE             Interpret a .w file
    console              Interactive REPL (also: wit(1))
    start                First-run welcome: what Tungsten is + your next step
    new NAME             Scaffold a new project
    bootstrap            Stage-1 compiler via C VM (bash; no Ruby). Runs doctor
                         first. Fresh-clone entry point.
    build                Full self-host: stage 1 + stage 2 (byte-identical IR),
                         install, bits. Same stage-1 path as before; not replaced
                         by bootstrap.
    doctor               Check your toolchain (clang, make, lld, zstd, compiler)
                         Implemented in bash — works without a built compiler.
    fmt FILE             Format .w source
    bit ...              The Bit package manager (install, new, search, ...)
    ai / symbolicate / forge / flame
                         Additional tools

    doctor and bootstrap are pure bash (bin/commands/*.sh) and work on a fresh
    clone. compile, run, console, start, new, fmt, forge, flame, bit, ai, and
    symbolicate use the compiled CLI when present. `build` still uses the
    Ruby bootstrap driver for the full pipeline; see DEVELOPER OPTIONS.

    The REPL is started with `tungsten console` or the `wit` binary — not
    `tungsten --repl`.

EXAMPLES
    tungsten --version
    tungsten --check file.w
    tungsten -e "<< 'hello world'"
    tungsten start
    tungsten bootstrap
    tungsten build
    tungsten console
    wit

OPTIONS
        --copyright
        Print the copyright notice.

        --version
        Print version of Tungsten language and interpreter.

        --ast
        Print the abstract syntax tree (AST). Does not run the program.

    -a, --autosplit

        When used with -n or -p, executes `$F = $_.split` at the beginning of
        each loop.

    -c, --check
        Check syntax and exit without executing. Prints '200 OK' on success.

    -C, --[no-]color
        Enable color output, on by default.

    -d, --debug
        Enable debug mode.

    -e, --eval EXPRESSION
        Execute an expression, often for CLI one-liners.

    -E, --[no-]environment
        Ignore environment variables that modify the behavior of the interpreter.

    -F, --field PATTERN
        Specify Tungsten.input_field_separator.

        Enables auto-split mode when used with -n or -p.

        Splits input line into fields and assigns to $1, $2, etc.

    -h, -?, --help
        Print help message.

    -i, --interactive
        Interactive mode. If -e is passed, start REPL after evaluating expression.

    -I, --include DIR
        Expand DIR and add to Tungsten.load_paths.

    -j, --jobs N
        Number of parallel jobs to spawn. Defaults to the CPU count.

        --lex
        Lex the input and print the tokens. Does not run the program.

        --ll
        Print the LLVM IR. Does not run the program.

    -n
        Causes Tungsten to assume the following loop around your
        script, which makes it iterate over filename arguments
        somewhat like sed -n or awk.

            ... while gets

    -p, --print
        Similar to -n, but print the result for each loop.

    -P, --profile
        Profile with tungsten-flame

    -O, --optimize
        Enable optimizations.

    -q, --quiet
        Enable quiet mode.

    -r, --release
        Compile in release mode.

        Equivalent: --no-debug --no-warning

    -t, --threads
        Max number of threads.

    -v
        Enables verbose mode. Tungsten will print its version at the
        beginning. If this switch is given, and no other switches are
        present, Tungsten quits after printing its version.

        --verbose
        Enable verbose mode.

    -o, --out FILE
        Write compiled binary to FILE (for .w files).

    -w, --[no-]warnings
        Enable warnings.

        --wire
        Print the lowered Tungsten IR (WIRE).

    -x, --coverage
        Enable code coverage.

    -X, --no-rc
        Skip loading ~/.tungstenrc.

DEVELOPER OPTIONS
    These flags are for compiler authors and bootstrap maintainers. Day-to-day
    use of Tungsten does not need them. Default bootstrap is the C bytecode VM
    (implementations/c/); stage 1 and stage 2 must still emit byte-identical IR.

        --ruby
        Use the Ruby tree-walking interpreter (implementations/ruby/) for stage
        1 of `tungsten build`, or run a program through that interpreter when
        passed to `tungsten` / `tungsten run` / `tungsten compile`. Requires a
        Ruby install and the gem bundle under implementations/ruby/.

        --spinel
        Bootstrap stage 1 via the Spinel-compiled stage-0 path instead of the
        default C VM. Implies the experimental implementations/spinel/ tree.
        Mutually exclusive with --ruby. Used only with `tungsten build`.

    Equivalent environment overrides for the build driver:

        TUNGSTEN_BOOTSTRAP=ruby
        TUNGSTEN_BOOTSTRAP=spinel

EXIT STATUS
    0 success
    1 error
    2 syntax error

ENVIRONMENT
    W_DEBUG
    W_HOME
    W_PATH
    W_VERBOSE
    TUNGSTEN_GPU_DIALECTS
        Comma list of extra GPU dialect sidecars to emit for @gpu fn
        (e.g. cuda,wgsl). Metal is always emitted when kernels are present;
        CUDA is also emitted by default on non-Darwin hosts.

FEATURES
    Native literals
        Currency ($, ¢), percentages (%), units of measurement (m/s, kg, ft).

    Unicode math
        √, Δ, ², ·, and prime notation (x') in source code.
        Σ(2x⁷ + 3x², 1..10) sums a polynomial; (1..10)/Σ(2x⁷ + 3x²) is the
        pipeline form. ∫(x², 0..2) integrates numerically; in the REPL,
        `? ∫(x², 0..2)` plots the curve and shades the area under it.

    Pattern matching
        Multi-clause function definitions with destructuring.

    Significant indentation
        No end keywords, no braces, no colons.

    Operator polymorphism
        Operators are method calls on the receiver.

    Generics
        monomorphized, invariant with compile-time reification and type-checking at definition

    UTF-8 source
        Full Unicode support for identifiers and literals.

RECIPES
    Tungsten Carbide can be prepared by reaction of tungsten metal and carbon
    at 1,400 – 2,000 °C.

AVAILABILITY
    Tungsten is available for MacOS and Linux.

AUTHOR
    Tungsten is designed and maintained by:
    Erik Peterson <thecompanygardener@gmail.com>.

SEE ALSO
    bit(1) carbide(1) hammer(1) forge(1) wake(1) wit(1)

SOURCE
    https://github.com/tungsten-lang/tungsten

INTERNET RESOURCES
    tungsten-lang.org    Tungsten Home
    bits.tungsten-lang.org  Tungsten Bits

BUGS
    You will not always agree with Tungsten.

NOTES
    The official Tungsten motto is "tl;dr - tungsten lang defines right."

tungsten v2026.07.04                2026.07.04                       TUNGSTEN(1)
```

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
    repl                 Interactive REPL, a.k.a. wit  (alias: console)
    start                First-run welcome: what Tungsten is + your next step
    new NAME             Scaffold a new project
    build                Bootstrap the self-hosted compiler
                         (stage 1 and stage 2 must emit byte-identical IR)
    doctor               Check your toolchain (clang, LLVM, Ruby)
    fmt FILE             Format .w source
    bit ...              The Bit package manager (install, new, search, ...)
    ai / symbolicate / forge / flame
                         Additional tools

    compile, run, and repl execute in the compiled CLI. The remaining commands
    are currently delegated to the Ruby driver (bin/tungsten.rb) and move into
    the compiled CLI as they are ported.

EXAMPLES
    tungsten --version
    tungsten --check file.w
    tungsten -e "<< 'hello world'"
    tungsten start
    tungsten repl

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

        --ruby
        Use the Ruby interpreter

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

        --repl
        Start interactive REPL.

    -w, --[no-]warnings
        Enable warnings.

        --wire
        Print the lowered Tungsten IR (WIRE).

    -x, --coverage
        Enable code coverage.

    -X, --no-rc
        Skip loading ~/.tungstenrc.

EXIT STATUS
    0 success
    1 error
    2 syntax error

ENVIRONMENT
    W_DEBUG
    W_HOME
    W_PATH
    W_VERBOSE

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

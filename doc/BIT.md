## Bit

```text
BIT(1)                        Bit Package Manager                        BIT(1)

NAME
    bit - Tungsten Package Management

DESCRIPTION
    Bit is the official package manager for the Tungsten Programmers Language.

SYNOPSIS
    bit COMMAND [options] [ARGS]

OPTIONS
    -c, --copyright Print the copyright notice
    -v, --verbose   Print version and enable verbose mode

    -h, --help      Show help

COMMANDS
    bit help                Show help
    bit help commands       List all commands

    bit new <name>          Create a new bit project
    bit init                Initialize a bit in the current directory

    bit search <query>      Search the registry
    bit info <name>         Show bit details (versions, dependencies, author)
    bit install             Install dependencies from Bitfile
    bit uninstall <name>    Remove a dependency
    bit update              Update dependencies to latest allowed versions
    bit outdated            Show dependencies with newer versions available
    bit prune               Remove unused dependencies

    bit build               Compile the bit
    bit clean               Remove build artifacts
    bit spec                Run the spec suite
    bit bench               Run benchmarks
    bit lint                Run the linter
    bit console             Start a REPL with the bit's dependencies loaded

    bit exec <cmd>          Run a command in the bit's environment
    bit generate <type>     Scaffold files (e.g. class, spec)

    bit sign                Sign the bit archive for publishing
    bit publish             Publish to the registry
    bit unpublish           Remove a version from the registry
    bit deprecate           Mark a version as deprecated (still installable)

    bit author              Manage author identity and registry credentials
    bit config              View and set bit configuration
    bit bundle              Vendor dependencies into the bit
    bit list                List installed dependencies
    bit open <name>         Open a dependency's source in $EDITOR
    bit viz                 Visualize the dependency graph

PROJECT STRUCTURE

    bit new pg

        pg
        ├─ bin
        │  └─ pg*
        ├─ spec
        │  ├─ support/
        │  └─ pg_spec.w
        ├─ lib
        │  ├─ pg
        │  │  └─ version.w
        │  └─ pg.w
        ├─ Bitfile
        ├─ LICENSE
        └─ README.md

    lib/<name>.w        Main entry point. This is what `use <name>` loads.
    lib/<name>/         Internal modules.
    lib/<name>/version.w  Version constant (conventional, not required).
    bin/<name>          CLI binary (optional). Must match the bit name.
    spec/               Test files. `bit test` discovers *_spec.w here.
    spec/support/       Test helpers, loaded before specs.

BITFILE

    The Bitfile declares the Tungsten version, dependencies, and metadata.

        tungsten "~> 0.1"

        external "ruby", "4.0.2"
        external "llvm", "current"
        external "openssl", "current"

        bit "tungsten-carbide", "~> 0.0.1"
        bit "tungsten-parser",  local: true

        group :development ->
          bit "tungsten-console"

    tungsten <constraint>
        Declares which Tungsten versions this bit is compatible with.
        Accepts any valid version constraint (see VERSION CONSTRAINTS).
        The registry runs the bit's test suite against its Tungsten version
        matrix and marks incompatible versions automatically.

    bit <name>, <constraint>, [options]
        Declares a dependency.

        Options:
          local: true       Use the local copy (monorepo development).
          git: <url>        Install from a git repository.
          branch: <name>    Git branch (with git: option).

    source <url>
        Set the registry URL. Default: https://bits.tungsten-lang.org

    external <name>, <version>
        Declares a non-bit dependency that should be kept in `src/`.
        `rake deps` downloads the declared version and also the latest
        upstream release when it differs, so you can test both.

        Supported names:
          ruby
          llvm
          openssl

        Supported version forms:
          "4.0.2"         Exact version
          "current"       Latest upstream release

    group <name> -> ... end
        Group dependencies by purpose. Groups can be excluded during
        install (e.g. `bit install --without development`).

        Common groups: :development, :test, :production

    constant_alias <name>
        Register a short constant alias for the bit's top-level module.

VALID BIT NAMES
    /^
       [a-z]         # Begins with lowercase letter
      ([a-z0-9]+-?)* # Dash separated lowercase alpha-numeric, no double dashes
       [a-z0-9]      # No ending dash, no single character names
    $/x

VALID VERSIONS
    /^
      (?<major> 0 | [1-9][0-9]* ) \.
      (?<minor> 0 | [1-9][0-9]* ) \.
      (?<tiny>  0 | [1-9][0-9]* )
      (?<note>
        \. ( alpha | beta | rc)
           ( [1-9][0-9]* )?
      )?
    $/x

    Pre-release ordering:
        1.0.0.alpha  < 1.0.0.alpha2 < 1.0.0.beta < 1.0.0.beta2
                     < 1.0.0.rc     < 1.0.0.rc2  < 1.0.0

    A bare pre-release tag (e.g. 1.0.0.alpha) is equivalent to
    1.0.0.alpha1 for sorting purposes.

VERSION CONSTRAINTS
    "1.0.0"             Exact version.
    ">= 1.0.0"          Minimum version.
    "< 2.0.0"           Maximum version (exclusive).
    "~> 1.2"            Pessimistic: >= 1.2.0 and < 2.0.0.
    "~> 1.2.3"          Pessimistic: >= 1.2.3 and < 1.3.0.
    ">= 1.0", "< 3"    Multiple constraints (all must be satisfied).

RESERVED BIT NAMES
    /^(w-|tungsten)/

    Names beginning with `w-` are reserved for the Tungsten standard
    library. Names beginning with `tungsten` are reserved for official
    Tungsten project packages.

COMMAND LINE BINARIES
    A bit can have one and only one CLI command, which matches the bit
    name. Related commands should be exposed as subcommands:

        pg migrate
        pg console
        pg dump

    This prevents PATH pollution and keeps one bit = one command.
    If two tools are genuinely unrelated, they belong in two bits.

EASTER EGGS
    bit
      and pieces
      bucket, burger, by a spider, by charlie
      coin, comet
      depth driver
      e
      fenix
      ing
      key, keeper
      lord, ly
      me, mining, moji, my cheek, my finger, my tongue
      news
      o honey, of a pickle
      pay
      quest, quick
      rate, rot
      shift, stamp
      ter, ters, tersweet, torrent
      umen, uminous, under the weather
      wise
      xor

SEE ALSO
    tungsten(1)

SOURCE
    https://github.com/tungsten-lang/bit

AUTHORS
    Bit is developed and maintained by Erik Peterson.
```

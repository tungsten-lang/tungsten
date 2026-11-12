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

INSTALL STORAGE

    bit install writes immutable package versions beneath:

        $BIT_HOME/<name>/<version>/

    BIT_HOME defaults to $TUNGSTEN_HOME/bits, and TUNGSTEN_HOME defaults to
    ~/.tungsten. Bitfile.lock selects the exact version in both interpreted
    and compiled programs. A current symlink supports standalone programs
    without a project lockfile.

    Use --dir DIR for another user-owned root. System-wide installation is
    explicit: --system uses /usr/local/lib/tungsten/bits, and
    --system --prefix DIR selects another shared root.

    Remote lock entries require SHA256 metadata. Archives are verified before
    unpacking, unsafe member paths are rejected, and optional SSH signatures
    are verified when their metadata is present.

TUNGSTEN BUILD

    `tungsten build` builds what the current folder is part of:

    - in a checkout of the Tungsten repository (any clone or worktree, known by
      compiler/tungsten.w, core/tungsten.w and bin/commands/build.w at its
      root): that checkout's compiler, the self-host build. Another checkout
      than the CLI's own is built by its own bin/tungsten. A bit folder inside
      the checkout builds that bit, as before.
    - anywhere else: the nearest folder at or above it with a Bitfile (a
      project or a bit). Its `executable` lines are built into bin/, and on
      macOS each `app` line becomes bin/<Name>.app.
    - with neither, it stops with an error that says what it looked for.

    `tungsten build --which` prints what it would build (self, checkout, bit or
    none) and the folder.

    An executable is rebuilt when anything it is built from changes: the
    project's own tree, its Bitfile, the compiler and runtime, and the .w
    files its entry reaches through relative or absolute `use` lines outside
    the project (a shared engine next door: `use ../../engine/notation`).

    An app is declared in the Bitfile, one line, after the executable it wraps:

        executable "arranger", source: "lib/arranger.w"
        app "Arranger", executable: "arranger", id: "org.example.arranger", icon: "res/icon.png", documents: "arr", version: "0.1"

    The bundle holds Contents/MacOS/<executable> (the built binary),
    Contents/Info.plist (name, identifier, version, the build — `build:`,
    else the time of the build as YYYYMMDD.HHMM — Retina, the document
    types), Contents/Resources/<Name>.icns (made from the PNG with sips and
    iconutil) and PkgInfo, and is signed ad hoc. The system frameworks the
    program links (AppKit, Metal, QuartzCore, CoreGraphics) need no copying.
    Each `documents:` extension becomes a document type the app owns (role
    Editor, `LSHandlerRank` Owner, `LSItemContentTypes`) and an exported type
    `<id>.<ext>` (`UTExportedTypeDeclarations`, conforming to `public.data`),
    and the bundle is registered with Launch Services when it is built, so a
    double-click in Finder opens the file in the app: the program gets it as
    a `GFX_EV_OPEN` event with `:path` (doc/graphics.md, "Opening documents"),
    at launch and while it runs. (Launch Services does not bind document types
    to apps in temporary folders such as /tmp: check the routing with a bundle
    elsewhere.)

    An executable line can ask for the compiler's debug information without
    giving up its profile's optimization:

        executable "arranger", source: "lib/arranger.w", profile: "release", debug: true

    The build passes --debug instead of the profile's --no-debug, so a
    runtime error's report shows the failing source line and the Tungsten
    frames (`at fn (file:line:col)`) instead of C frames with the Tungsten
    ones inlined into main: what an app's crash log needs. It costs a few
    percent (the Arranger's frame times, 2026-11-05). --debug or --no-debug
    on the command line still decides. `debug:` is true or false.

    A project can name the oldest Tungsten main it builds correctly with, so
    a stale toolchain stops the build (before anything is replaced) instead
    of producing an app that silently lacks what it needs:

        tungsten_main "1a2b3c4d5"                      # the runtime/ and core/ built against must contain it
        tungsten_main "1a2b3c4d5", compiler: "6e7f8a9b0"   # and the compiler must be built from a tree with that one

    The checkout the build compiles against (the CLI's own) must have the
    commit in its history; `compiler:` also checks bin/tungsten-compiler, by
    the commit in its build record (build/compiler-build.profile, written
    by the self-host build) or, without one, by its
    file time (a compiler built before the commit cannot contain it). The
    message says what to run: update that checkout to main, or rebuild its
    compiler (`cd <checkout> && bin/tungsten build`). A checkout that is not
    a git repository cannot be checked, and the build says so.

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

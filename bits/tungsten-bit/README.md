# bit

`bit` is the package manager for the [Tungsten programming language](https://tungsten-lang.org). It creates, builds, tests, publishes, and consumes Tungsten packages (called "bits").

```
bit install                 # install dependencies from Bitfile
bit new myapp               # scaffold a new bit project
bit spec                    # run tests
bit create                  # create a registry profile
bit push                    # sign, test, and publish to the registry
```

## Install

`bit` ships with Tungsten. If you have `tungsten` on your PATH, you have `bit`.

```
bit --version
```

Standalone install or alternative versions can be managed with `bit-install(1)`.

## Quick start

Create a new bit:

```sh
bit new pg
cd pg
```

This generates:

```
pg
├─ bin
│  └─ pg*                 # CLI binary (optional)
├─ spec
│  ├─ support/            # loaded before specs
│  └─ pg_spec.w
├─ lib
│  ├─ pg
│  │  └─ version.w        # version constant (convention)
│  └─ pg.w                # main entry point — `use pg` loads this
├─ Bitfile                # dependency manifest
├─ LICENSE
└─ README.md
```

Run tests:

```sh
bit spec
```

Add a dependency — edit `Bitfile`:

```tungsten
source "https://bits.tungsten-lang.org"
tungsten "~> 0.1"

bit "tungsten-carbide", "~> 0.0.1"
```

Install:

```sh
bit install
```

Ship:

```sh
bit build
bit create --yes
bit pack --sign
bit push
```

Remote publishing uses the registry at `https://bits.tungsten-lang.org` by
default. `bit create` creates a profile using your git email and SSH `*.pub`
key as defaults. `bit login --token TOKEN` also works for existing accounts.
Tokens are read from `BIT_TOKEN`, `TUNGSTEN_BITS_TOKEN`, `TUNGSTEN_BIT_TOKEN`,
or `~/.bit/credentials`.

## Command reference

### Help

| Command | What it does |
|---------|--------------|
| `bit help` | Show help |
| `bit help commands` | List all commands |
| `bit env` | Show local bit environment info |
| `bit doctor` | Check local and publish readiness |

### Project lifecycle

| Command | What it does |
|---------|--------------|
| `bit new NAME` | Create a new bit project |
| `bit init` | Initialize a bit in the current directory |

### Dependencies

| Command | What it does |
|---------|--------------|
| `bit search QUERY` | Search the registry |
| `bit info NAME` | Show bit details (versions, deps, author, security status) |
| `bit install` | Install dependencies from `Bitfile` |
| `bit uninstall NAME` | Remove a dependency |
| `bit update` | Update to latest allowed versions |
| `bit outdated` | Show dependencies with newer versions |
| `bit audit` | Audit locked dependency security metadata |
| `bit prune` | Remove unused dependencies |
| `bit list` | List installed dependencies |
| `bit bundle` | Vendor dependencies into the bit |
| `bit open NAME` | Open a dependency's source in `$EDITOR` |
| `bit viz` | Visualize the dependency graph |

### Build and test

| Command | What it does |
|---------|--------------|
| `bit pack` | Create `pkg/NAME-VERSION.bit` and SHA256 metadata |
| `bit build` | Compile the bit |
| `bit clean` | Remove build artifacts |
| `bit spec` | Run the spec suite |
| `bit bench` | Run benchmarks |
| `bit lint` | Run the linter |
| `bit console` | REPL with the bit's deps loaded |
| `bit exec CMD` | Run `CMD` in the bit's environment |
| `bit generate TYPE` | Scaffold files (class, spec, etc.) |

### Publishing

| Command | What it does |
|---------|--------------|
| `bit create` / `bit signup` | Create a registry profile |
| `bit login` | Store an API token or log in |
| `bit sign` | Sign the bit archive for publishing |
| `bit push` / `bit publish` | Run CI grid, sign, and publish |
| `bit yank` | Yank a published version |
| `bit unpublish` | Remove a version from the registry |
| `bit deprecate` | Mark a version as deprecated (still installable) |

`bit push` refuses to overwrite an existing version. If a version needs to be
removed from the registry, run `bit yank NAME VERSION`, then bump the Bitfile
version before pushing again. Before upload, `bit push` runs the CI grid from
`BIT_CI_TUNGSTEN`, `TUNGSTEN_CI_RELEASES`, `.tungsten/releases`, or the Bitfile
`tungsten` requirement. Override the command with `--ci-command`.
Use `--security` or `--release-type security` for security releases; security
releases bypass source cooldowns.

### Identity and config

| Command | What it does |
|---------|--------------|
| `bit author` | Manage author identity and registry credentials |
| `bit config` | View and set configuration |
| `bit env` | Show registry, profile, key, toolchain, and project paths |
| `bit doctor` | Check Bitfile, lockfile, tools, auth, and signing setup |

## The Bitfile

Each bit has a `Bitfile` at its root. It's evaluated as Tungsten code in a DSL context.

```tungsten
source "https://bits.tungsten-lang.org", cooldown: 7
tungsten "~> 0.1"

external "ruby",    "4.0.2"
external "llvm",    "current"
external "openssl", "current"

executable "my-tool", source: "lib/my_tool.w"
asset "assets"

bit "tungsten-carbide", "~> 0.0.1"
bit "tungsten-parser",  local: true

group :development ->
  bit "tungsten-console"
```

### Directives

**`source URL`** — Registry to resolve from. Default: `https://bits.tungsten-lang.org`.
Options:

| Option | Effect |
|--------|--------|
| `cooldown: DAYS` | Wait this many days before feature releases are offered by `bit outdated`, `bit update`, or `bit upgrade` |
| `trusted: true` | Trust this source for immediate upgrades |

Security releases are always eligible immediately. Local sources are also
eligible immediately. Git/GitHub dependencies may bypass cooldown only when
marked trusted.

**`tungsten CONSTRAINT`** — Which Tungsten versions this bit supports. The registry runs your test suite against its Tungsten version matrix and auto-flags incompatible versions.

**`executable NAME, source: PATH`** — Build a runnable application entry point.
Repeat the directive for multiple programs. `bit build` writes each program to
`build/bin/NAME`; when `source:` is omitted it defaults to `lib/NAME.w`.

**`asset PATH`** — Include a package-relative file or directory in archives and
copy it to the same relative path under `build/`. Repeat it for multiple paths.
The conventional `assets/` directory is included automatically when present.
Absolute paths and paths containing `..` are rejected.

**`bit NAME, CONSTRAINT, [options]`** — A dependency. Options:

| Option | Effect |
|--------|--------|
| `local: true` | Use the local copy (monorepo-style development) |
| `git: URL` | Install from a git repository |
| `branch: NAME` | Git branch (pairs with `git:`) |
| `trusted: true` | Allow immediate upgrades for this trusted source |
| `cooldown: DAYS` | Override the source cooldown for this dependency |

**`external NAME, VERSION`** — A non-bit native dependency vendored under `src/`. `rake deps` fetches both the declared version and the latest upstream so you can test both. Supported names: `ruby`, `llvm`, `openssl`. Version forms: exact (`"4.0.2"`) or `"current"`.

**`group NAME -> ... end`** — Scope dependencies by purpose. Common groups: `:development`, `:test`, `:production`. Exclude at install time with `bit install --without development`.

**`constant_alias NAME`** — Short constant alias for the bit's top-level module.

See `Bitfile(5)` for the complete reference.

`bit build` locates the compiler through `TUNGSTEN_COMPILER` (or `TUNGSTEN`),
`TUNGSTEN_ROOT`, an in-tree `bin/tungsten`, or `tungsten` on `PATH`, in that
order. Archives preserve common single- and dual-license files such as
`LICENSE`, `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`, and `THIRD_PARTY`.

## The Bitfile.lock

`bit install`, `bit update`, and `bit upgrade` write `Bitfile.lock` with the resolved version and source provenance for each dependency:

```tungsten
bit "tungsten-json", "0.1.5", source: "remote", path: "https://bits.tungsten-lang.org/api/v1/downloads/tungsten-json-0.1.5.bit", sha256: "...", signature: "...", public_key: "...", release_type: "feature", published_at: "1782990000"
```

The lockfile pins the exact version used by `bit install`. Remote entries also
carry SHA256 and signing metadata; remote installs verify SHA256, and verify SSH
signatures when signature metadata is present, before unpacking. Older
two-column lock entries like `tungsten-json 0.1.5` are still accepted.

## Version constraints

| Constraint | Meaning |
|-----------|---------|
| `"1.0.0"` | Exact |
| `">= 1.0.0"` | Minimum |
| `"< 2.0.0"` | Maximum (exclusive) |
| `"~> 1.2"` | Pessimistic: `>= 1.2.0` and `< 2.0.0` |
| `"~> 1.2.3"` | Pessimistic: `>= 1.2.3` and `< 1.3.0` |
| `">= 1.0", "< 3"` | Multiple constraints (all must hold) |

## Version format

```
/^
  (?<major> 0 | [1-9][0-9]* ) \.
  (?<minor> 0 | [1-9][0-9]* ) \.
  (?<tiny>  0 | [1-9][0-9]* )
  (?<note>
    \. ( alpha | beta | rc )
       ( [1-9][0-9]* )?
  )?
$/x
```

Pre-release ordering:

```
1.0.0.alpha < 1.0.0.alpha2 < 1.0.0.beta < 1.0.0.beta2
            < 1.0.0.rc    < 1.0.0.rc2  < 1.0.0
```

A bare pre-release tag like `1.0.0.alpha` sorts as `1.0.0.alpha1`.

## Naming rules

Valid bit name:

```
/^
   [a-z]         # Lowercase start
  ([a-z0-9]+-?)* # Dash-separated lowercase alphanumerics, no double dashes
   [a-z0-9]      # No trailing dash, no single-character names
$/x
```

Reserved prefixes:

- `w-` — Reserved for the Tungsten standard library.
- `tungsten` — Reserved for official Tungsten project packages.

## One bit, one command

A bit may expose at most one CLI command, and its name must match the bit name. Related commands go in as subcommands:

```sh
pg migrate
pg console
pg dump
```

This keeps PATH clean and enforces the "one bit = one tool" invariant. Two genuinely unrelated tools belong in two bits.

## Man pages

- `bit(1)` — this command
- `bit-install(1)` — install options and flags
- `Bitfile(5)` — Bitfile format reference

## Source

<https://github.com/tungsten-lang/bit>

## License

See [LICENSE](LICENSE).

## Author

Erik Peterson.

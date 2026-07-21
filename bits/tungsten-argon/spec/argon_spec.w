# Argon spec — self-contained assertions.
#
# The tungsten-spec framework does not yet load under the interpreter
# (its `in Tungsten:Spec` submodules fail to resolve), so this spec uses a
# tiny local checker and exits nonzero on failure.
#
# Run from the repo root:
#   bin/tungsten bits/tungsten-argon/spec/argon_spec.w

use argon

+ Check
  ro :passed
  ro :failed

  -> new
    @passed = 0
    @failed = 0

  # Compare with == first, then via to_s — compiled Array == is
  # identity-based, so the string form catches structurally equal arrays.
  -> eq(label, actual, expected)
    same = actual == expected
    if !same
      same = actual.to_s() == expected.to_s()
    if same
      @passed = @passed + 1
    else
      @failed = @failed + 1
      << "FAIL: " + label
      << "  expected: " + show(expected)
      << "  actual:   " + show(actual)

  # Interpreted Float#to_s can return nil (literal floats); print safely.
  -> show(v)
    s = v.to_s()
    if s == nil
      return "(unprintable)"
    s

  -> done
    << @passed.to_s() + " passed, " + @failed.to_s() + " failed"
    if @failed > 0
      exit 1
    << "OK"

MAN = "NAME
    probe -- exercise the Argon parser

SYNOPSIS
    probe \[options] \[--] file

OPTIONS
    -C, --\[no-]color
        Enable color output, on by default.

    -d, --debug
        Enable debug mode.

    -o, --out FILE
        Write output to FILE.

    -j, --jobs N
        Number of parallel jobs (default: 8).

    -t, --tag VERSION
        A version tag.

    -r, --rate HZ
        Sample rate.

    --files \[FILE ...]
        Input files.

    -p, --profile \[MODE]
        Profile, optionally in MODE.
"

t = Check.new
cli = Argon.new(MAN)

# ---- Manpage extraction ----
t.eq("extracts name from NAME section", cli.name, "probe")

color = cli.find_by_key("color")
files = cli.find_by_key("files")
profile = cli.find_by_key("profile")

t.eq("negatable flag is negatable", color[:negatable], true)
t.eq("negatable flag takes no value (\[no-] is not a value bracket)", color[:takes_value], false)
t.eq("\[FILE ...] is an array option", files[:array], true)
t.eq("\[MODE] is an optional-value option", profile[:optional_value], true)

# ---- Boolean flags ----
opts = cli.parse(["--debug", "file.w"])
t.eq("long flag sets flag?", opts.flag?(:debug), true)
t.eq("unset flag is false", opts.flag?(:color), false)
t.eq("flag does not eat positionals", opts.args, ["file.w"])

opts = cli.parse(["--color", "file.w"])
t.eq("negatable long flag sets flag?", opts.flag?(:color), true)
t.eq("negatable long flag keeps positional", opts.args, ["file.w"])

opts = cli.parse(["-C", "file.w"])
t.eq("negatable short flag sets flag?", opts.flag?(:color), true)
t.eq("negatable short flag keeps positional", opts.args, ["file.w"])

opts = cli.parse(["--no-color"])
t.eq("--no-X negates", opts.negated?(:color), true)
t.eq("--no-X is not flag?", opts.flag?(:color), false)

opts = cli.parse(["--frobnicate"])
t.eq("unknown long flag still recorded", opts.flag?(:frobnicate), true)

# ---- Value options ----
opts = cli.parse(["-o", "a.bin"])
t.eq("short option takes value", opts.get(:out), "a.bin")

opts = cli.parse(["--out", "b.bin"])
t.eq("long option takes value", opts.get(:out), "b.bin")

opts = cli.parse(["--out=c.bin"])
t.eq("--key=value form", opts.get(:out), "c.bin")

opts = cli.parse(["--out", "d.bin", "file.w"])
t.eq("value option leaves later positionals", opts.args, ["file.w"])

# ---- Casting ----
opts = cli.parse(["--jobs", "4"])
t.eq("integer value is cast", opts.get(:jobs), 4)

opts = cli.parse(["--rate", "2.5"])
t.eq("float value is cast", opts.get(:rate), 2.5)

opts = cli.parse(["--tag", "1.2.3"])
t.eq("multi-dot value stays a string", opts.get(:tag), "1.2.3")

opts = cli.parse(["--tag", "v2"])
t.eq("non-numeric value stays a string", opts.get(:tag), "v2")

# ---- Defaults ----
opts = cli.parse([])
t.eq("manpage (default: N) is used", opts.get(:jobs), 8)
t.eq("explicit default beats nil", opts.get(:out, "a.out"), "a.out")
t.eq("missing option with no default is nil", opts.get(:tag) == nil, true)

# ---- Inline defaults ----
# "(default: N)" on the option line itself (hammer-style manpages).
# Precedence is inline-first: an option-line default beats one in the
# description lines below.
MAN2 = "NAME
    inline -- exercise inline (default: N) extraction

SYNOPSIS
    inline \[options] file

OPTIONS
    -c, --connections N  Connections to open (default: 100)

    -m, --mode NAME  Operating mode (default: fast)

    -r, --rate HZ  Sample rate (default: 2.5)

    --\[no-]cache  Enable the cache (default: 1)

    -j, --jobs N  Parallel jobs (default: 8)
        Description-line default loses to the inline one (default: 4).

    -o, --out FILE
        Write output to FILE (default: a.out).
"

cli2 = Argon.new(MAN2)

opts = cli2.parse([])
t.eq("inline int default", opts.get(:connections), 100)
t.eq("inline string default", opts.get(:mode), "fast")
t.eq("inline float default", opts.get(:rate), 2.5)
t.eq("inline default on a negatable flag line", opts.get(:cache), 1)
t.eq("inline default beats description-line default", opts.get(:jobs), 8)
t.eq("description-line default still extracted when no inline", opts.get(:out), "a.out")

cache = cli2.find_by_key("cache")
t.eq("inline text keeps flag negatable", cache[:negatable], true)
t.eq("inline text does not make a flag take a value", cache[:takes_value], false)

opts = cli2.parse(["--connections", "9"])
t.eq("explicit value overrides inline default", opts.get(:connections), 9)

opts = cli2.parse(["--no-cache"])
t.eq("negation still parses with inline default present", opts.negated?(:cache), true)

# ---- Array options ----
opts = cli.parse(["--files", "a", "b", "c"])
t.eq("array option consumes following args", opts.get(:files), ["a", "b", "c"])

opts = cli.parse(["--files", "a", "--files", "b"])
t.eq("repeated array option appends", opts.get(:files), ["a", "b"])

# ---- Optional-value options ----
opts = cli.parse(["--profile", "fast"])
t.eq("optional value consumed when present", opts.get(:profile), "fast")

opts = cli.parse(["--profile", "--debug"])
t.eq("optional value skipped before a flag", opts.get(:profile), true)
t.eq("flag after optional-value option still parsed", opts.flag?(:debug), true)

# ---- Positionals, command, passthrough ----
opts = cli.parse(["run", "x.w", "-d", "--", "-v", "abc"])
t.eq("command is first positional", opts.command, "run")
t.eq("arguments are the rest", opts.arguments, ["x.w"])
t.eq("flags mixed with positionals", opts.flag?(:debug), true)
t.eq("passthrough after --", opts.passthrough, ["-v", "abc"])

opts = cli.parse([])
t.eq("empty argv: no command", opts.command == nil, true)
t.eq("empty argv: no args", opts.args, [])

# ---- Short-flag bundling + negative numbers ----
# getopt conventions: "-abc" == "-a -b -c"; a value-taking letter consumes the
# rest of the bundle (or the next token) as its value; "-5" is a value/positional
# unless "5" is itself a defined short flag.
MAN3 = "NAME
    bundle -- exercise short-flag bundling and negative numbers

SYNOPSIS
    bundle \[options] file

OPTIONS
    -a
        Boolean flag a.

    -b
        Boolean flag b.

    -c
        Boolean flag c.

    -v, --verbose
        Verbose output.

    -o, --out FILE
        Output file.

    -n, --offset N
        Numeric offset.

    -5, --high-five
        A short flag literally named 5.

    --nums \[N ...]
        A list of numbers.
"

cli3 = Argon.new(MAN3)

opts = cli3.parse(["-abc"])
t.eq("bundle sets first flag", opts.flag?(:a), true)
t.eq("bundle sets middle flag", opts.flag?(:b), true)
t.eq("bundle sets last flag", opts.flag?(:c), true)

opts = cli3.parse(["-ab", "file.w"])
t.eq("bundle does not eat positionals", opts.args, ["file.w"])
t.eq("bundled flag a set alongside positional", opts.flag?(:a), true)

# Bundle ending in a value-flag: the next argv token is its value.
opts = cli3.parse(["-abo", "out.bin"])
t.eq("bundle prefix flags set before a value-flag", opts.flag?(:b), true)
t.eq("value-flag ending a bundle takes the next token", opts.get(:out), "out.bin")

# getopt "-ovalue": the rest of the bundle is the value.
opts = cli3.parse(["-oout.bin"])
t.eq("value-flag consumes the rest of the bundle as its value", opts.get(:out), "out.bin")

opts = cli3.parse(["-n5"])
t.eq("attached numeric value in a bundle is cast", opts.get(:offset), 5)

# Unknown letter in a bundle is recorded as a set flag (lenient — same as the
# single unknown-short-flag path).
opts = cli3.parse(["-az"])
t.eq("known bundled flag still set with an unknown neighbor", opts.flag?(:a), true)
t.eq("unknown bundled letter recorded as a flag", opts.flag?(:z), true)

# Bare "-5" with no "5" flag defined is a positional, not an unknown flag.
opts = cli.parse(["-5"])
t.eq("bare negative number is a positional", opts.args, ["-5"])

opts = cli.parse(["build", "-5"])
t.eq("negative number stays a positional after a command", opts.arguments, ["-5"])

# A value option happily consumes a negative-number value.
opts = cli3.parse(["--offset", "-5"])
t.eq("long value option takes a negative number", opts.get(:offset), -5)

opts = cli3.parse(["-n", "-5"])
t.eq("short value option takes a negative number", opts.get(:offset), -5)

# Array options accept negative numbers as elements, stopping only at genuine flags.
opts = cli3.parse(["--nums", "1", "-2", "3"])
t.eq("array option accepts negative numbers as elements", opts.get(:nums), [1, -2, 3])

opts = cli3.parse(["--nums", "1", "2", "-v"])
t.eq("array option stops at a genuine flag", opts.get(:nums), [1, 2])
t.eq("flag after an array option still parses", opts.flag?(:verbose), true)

# "-5" as a defined short flag (getopt edge): it IS a flag when 5 is documented.
opts = cli3.parse(["-5"])
t.eq("-5 is a flag when 5 is defined", opts.flag?(:high_five), true)
t.eq("-5 flag does not leak into positionals", opts.args, [])

# A defined digit-flag is a genuine flag, so it stops array consumption.
opts = cli3.parse(["--nums", "1", "-5"])
t.eq("defined digit-flag stops array consumption", opts.get(:nums), [1])
t.eq("defined digit-flag after an array is set", opts.flag?(:high_five), true)

# Optional-value option consumes a negative number (original MAN has no "5").
opts = cli.parse(["--profile", "-5"])
t.eq("optional-value option consumes a negative number", opts.get(:profile), -5)

# ---- Validation (manpage-driven constraints) ----
# Parsing stays lenient; validation is opt-in via errors / valid?. Constraints
# are read from the manpage: "(required)" marks a mandatory option, and
# "(one of: ...)" / "(choices: ...)" restricts accepted values. Unknown options
# (typos, stray flags) and value options left without a value are also reported.

# A known-good parse against the original manpage is valid; a typo is not —
# note the unknown flag is still *recorded* (lenient), yet flagged invalid.
t.eq("known usage is valid", cli.parse(["--debug", "file.w"]).valid?, true)
t.eq("unknown long flag makes input invalid", cli.parse(["--frobnicate"]).valid?, false)
t.eq("skipped optional value is not a missing-value error", cli.parse(["--profile", "--debug"]).valid?, true)

MAN4 = "NAME
    validate -- exercise argon validation

SYNOPSIS
    validate \[options] file

OPTIONS
    -i, --input FILE
        Input file. (required)

    -m, --mode MODE
        Operating mode. (one of: fast, slow, thorough)

    -l, --level N
        Verbosity level. (choices: 1, 2, 3)

    -o, --out FILE
        Output file.

    -v, --verbose
        Verbose output.
"

cli4 = Argon.new(MAN4)

# Constraint extraction from the manpage.
t.eq("(required) annotation marks option required", cli4.find_by_key("input")[:required], true)
t.eq("unannotated option is not required", cli4.find_by_key("out")[:required], false)
t.eq("(one of: ...) extracts string choices", cli4.find_by_key("mode")[:choices], ["fast", "slow", "thorough"])
t.eq("(choices: ...) casts numeric choices", cli4.find_by_key("level")[:choices], [1, 2, 3])
t.eq("no choices annotation leaves choices nil", cli4.find_by_key("out")[:choices] == nil, true)

# A fully correct invocation validates clean.
opts = cli4.parse(["--input", "a.txt", "--mode", "fast", "--level", "2", "-v"])
t.eq("complete valid invocation is valid", opts.valid?, true)
t.eq("valid invocation has no errors", opts.errors, [])

# Missing required option.
opts = cli4.parse(["--mode", "fast"])
t.eq("missing required option is invalid", opts.valid?, false)
t.eq("missing required option is reported", opts.errors.include?("missing required option: --input"), true)

# Invalid choice (string).
opts = cli4.parse(["--input", "a.txt", "--mode", "wat"])
t.eq("bad string choice is invalid", opts.valid?, false)
t.eq("bad string choice is reported with the allowed set", opts.errors.include?("invalid value for --mode: wat (expected one of: fast, slow, thorough)"), true)

# Numeric choice: casted value must be a member.
opts = cli4.parse(["--input", "a.txt", "--level", "2"])
t.eq("valid numeric choice passes", opts.valid?, true)
opts = cli4.parse(["--input", "a.txt", "--level", "5"])
t.eq("out-of-set numeric choice is invalid", opts.valid?, false)
t.eq("bad numeric choice reported after casting", opts.errors.include?("invalid value for --level: 5 (expected one of: 1, 2, 3)"), true)

# A value option left without a value degrades to true — validation catches it.
opts = cli4.parse(["--input"])
t.eq("value option missing its value is invalid", opts.valid?, false)
t.eq("missing value is reported", opts.errors.include?("missing value for option: --input"), true)

# Unknown options are surfaced, formatted as they appeared on the command line.
opts = cli4.parse(["--input", "a.txt", "--frobnicate", "-z"])
t.eq("unknown long+short options collected", opts.unknown, ["--frobnicate", "-z"])
t.eq("unknown options make input invalid", opts.valid?, false)
t.eq("unknown long option is reported", opts.errors.include?("unknown option: --frobnicate"), true)
t.eq("unknown short option is reported", opts.errors.include?("unknown option: -z"), true)

# Several problems at once accumulate independently.
opts = cli4.parse(["--mode", "nope", "--typo"])
t.eq("multiple problems accumulate", opts.errors.size(), 3)
t.eq("error? is the negation of valid?", opts.error?, true)

# ---- Count flags (repeated boolean flags accumulate: the -vvv idiom) ----
# A boolean flag given more than once records how many times it appeared, so a
# CLI can read a verbosity/quiet LEVEL rather than a mere on/off. flag? still
# reports the boolean; occurrences reports the tally.

opts = cli3.parse(["-vvv"])
t.eq("bundled repeats count up", opts.occurrences(:verbose), 3)
t.eq("a counted flag is still flag?-true", opts.flag?(:verbose), true)

opts = cli3.parse(["-v"])
t.eq("a single occurrence counts 1", opts.occurrences(:verbose), 1)

opts = cli3.parse([])
t.eq("an absent flag counts 0", opts.occurrences(:verbose), 0)

opts = cli3.parse(["-v", "-v"])
t.eq("separate short flags accumulate", opts.occurrences(:verbose), 2)

opts = cli3.parse(["--verbose", "--verbose"])
t.eq("repeated long flags accumulate", opts.occurrences(:verbose), 2)

# One letter's repeats are counted independently within a mixed bundle.
opts = cli3.parse(["-vva"])
t.eq("count tracks one letter in a mixed bundle", opts.occurrences(:verbose), 2)
t.eq("another bundled flag is still set", opts.flag?(:a), true)
t.eq("the singly-set letter counts 1", opts.occurrences(:a), 1)

# Repeats before a value-flag ending the bundle are still counted, and the
# value-flag still consumes its next token.
opts = cli3.parse(["-vvo", "out.bin"])
t.eq("repeats before a value-flag are counted", opts.occurrences(:verbose), 2)
t.eq("the value-flag after repeats still takes its value", opts.get(:out), "out.bin")

# Negations set the flag false and are deliberately not counted; an explicit
# enable of the same negatable flag does count.
opts = cli.parse(["--no-color"])
t.eq("a negation contributes no count", opts.occurrences(:color), 0)

opts = cli.parse(["-C", "-C"])
t.eq("repeated enable of a negatable flag counts", opts.occurrences(:color), 2)

# ---- Environment-variable fallback ("(env: VAR)") ----
# An option the manpage annotates "(env: VAR)" draws its value from $VAR when
# it is absent from argv. Resolution order is command line > environment >
# default, and the env string is cast with the same rules as a parsed value.
# HOME is used for the "present" cases because it is reliably set; a
# deliberately-unset variable name exercises the fall-through-to-default path.

MAN5 = "NAME
    envy -- exercise environment-variable fallback

SYNOPSIS
    envy \[options] file

OPTIONS
    -H, --homedir DIR
        Home directory. (env: HOME)

    -k, --token TOKEN
        API token. (env: ARGON_UNSET_TOKEN_XYZ) (default: anonymous)

    -c, --config FILE  Config path. (env: ARGON_INLINE_ENV)
        A fallback described here also names (env: ARGON_DESC_ENV).

    -o, --out FILE
        Output file.
"

cli5 = Argon.new(MAN5)

# Annotation extraction.
t.eq("(env: VAR) annotation is extracted", cli5.find_by_key("homedir")[:env], "HOME")
t.eq("(env: VAR) extracted alongside a default", cli5.find_by_key("token")[:env], "ARGON_UNSET_TOKEN_XYZ")
t.eq("no env annotation leaves env nil", cli5.find_by_key("out")[:env] == nil, true)
t.eq("inline env annotation wins over the description", cli5.find_by_key("config")[:env], "ARGON_INLINE_ENV")

# Value resolution.
opts = cli5.parse([])
t.eq("env fallback draws from a set variable", opts.get(:homedir), env("HOME"))
t.eq("unset env variable falls through to the manpage default", opts.get(:token), "anonymous")
t.eq("an option with neither value, env, nor default is nil", opts.get(:out) == nil, true)

opts = cli5.parse(["--homedir", "/custom"])
t.eq("command-line value beats the environment", opts.get(:homedir), "/custom")

opts = cli5.parse([])
t.eq("environment beats an explicit default argument", opts.get(:homedir, "/fallback"), env("HOME"))

# ---- Mutually exclusive options ("(conflicts with: ...)") ----
# An option annotated "(conflicts with: X)" may not be supplied together with X.
# The check is symmetric: declaring the conflict on either side is enough, and a
# pair is reported once, in a deterministic (sorted-by-label) order. Parsing
# itself stays lenient — the clash only surfaces through errors / valid?.

MAN6 = "NAME
    router -- exercise mutually exclusive options

SYNOPSIS
    router \[options] file

OPTIONS
    -v, --verbose
        Verbose output. (conflicts with: quiet)

    -q, --quiet
        Quiet output. (conflicts with: verbose)

    --json
        JSON output.

    --yaml
        YAML output. (conflicts with: json)

    -o, --out FILE  Output file. (conflicts with: quiet)

    --strict
        Strict mode. (conflicts with: quiet, plain)

    --plain
        Plain output.

    --long-flag-a
        First long flag. (conflicts with: --long-flag-b)

    --long-flag-b
        Second long flag.

    -s, --squash
        Squash output. (conflicts with: -q)
"

cli6 = Argon.new(MAN6)

# Annotation extraction (names normalized to key form).
t.eq("(conflicts with: X) extracts a single conflict", cli6.find_by_key("verbose")[:conflicts], ["quiet"])
t.eq("one-sided conflict annotation is extracted", cli6.find_by_key("yaml")[:conflicts], ["json"])
t.eq("inline conflict annotation on the option line is extracted", cli6.find_by_key("out")[:conflicts], ["quiet"])
t.eq("(conflicts with: A, B) extracts a list", cli6.find_by_key("strict")[:conflicts], ["quiet", "plain"])
t.eq("dashed conflict name is normalized to key form", cli6.find_by_key("long_flag_a")[:conflicts], ["long_flag_b"])
t.eq("no conflict annotation leaves conflicts nil", cli6.find_by_key("plain")[:conflicts] == nil, true)
t.eq("undeclared side leaves conflicts nil", cli6.find_by_key("json")[:conflicts] == nil, true)

# Supplying only one side, or neither, is fine.
t.eq("one conflicting option alone is valid", cli6.parse(["--verbose"]).valid?, true)
t.eq("neither conflicting option is valid", cli6.parse(["--plain"]).valid?, true)

# Supplying both sides is a single, deterministic error.
opts = cli6.parse(["--verbose", "--quiet"])
t.eq("mutually exclusive options make input invalid", opts.valid?, false)
t.eq("conflict is reported once (both sides declare it)", opts.errors.size(), 1)
t.eq("conflict message is sorted and deterministic", opts.errors.include?("mutually exclusive options: --quiet and --verbose"), true)

# Short-flag forms of the same pair also clash.
opts = cli6.parse(["-v", "-q"])
t.eq("short-flag forms clash too", opts.errors.include?("mutually exclusive options: --quiet and --verbose"), true)

# The check is symmetric even when only one side declares the conflict.
opts = cli6.parse(["--json", "--yaml"])
t.eq("conflict fires when only the other side declares it", opts.valid?, false)
t.eq("one-sided conflict reported once", opts.errors.include?("mutually exclusive options: --json and --yaml"), true)

# A value option can conflict with a flag (inline annotation).
opts = cli6.parse(["-o", "a.bin", "--quiet"])
t.eq("value option conflicting with a flag is caught", opts.valid?, false)
t.eq("value/flag conflict is reported", opts.errors.include?("mutually exclusive options: --out and --quiet"), true)

# A multi-conflict list fires against whichever member is present.
opts = cli6.parse(["--strict", "--plain"])
t.eq("multi-conflict list catches --plain", opts.errors.include?("mutually exclusive options: --plain and --strict"), true)
opts = cli6.parse(["--strict", "--quiet"])
t.eq("multi-conflict list catches --quiet", opts.errors.include?("mutually exclusive options: --quiet and --strict"), true)

# Dashed long-name conflict resolves and reports with full labels.
opts = cli6.parse(["--long-flag-a", "--long-flag-b"])
t.eq("dashed long-name conflict is caught", opts.errors.include?("mutually exclusive options: --long-flag-a and --long-flag-b"), true)

# A conflict may name its target by SHORT flag ("(conflicts with: -q)"). The
# annotation strips leading dashes, leaving a bare letter, so the lookup has to
# fall back from the canonical key to the short flag — otherwise the whole
# constraint silently evaporates.
t.eq("short-flag conflict name is extracted as a bare letter", cli6.find_by_key("squash")[:conflicts], ["q"])
opts = cli6.parse(["--squash", "--quiet"])
t.eq("short-flag-named conflict fires", opts.valid?, false)
t.eq("short-flag-named conflict reports canonical labels", opts.errors.include?("mutually exclusive options: --quiet and --squash"), true)
t.eq("short-flag-named conflict is reported once", opts.errors.size(), 1)
t.eq("short-flag-named conflict fires from the short side too", cli6.parse(["-s", "-q"]).errors.include?("mutually exclusive options: --quiet and --squash"), true)
t.eq("short-flag-named conflict stays quiet when alone", cli6.parse(["--squash"]).valid?, true)

# Abbreviation composes with conflicts: an abbreviated option records under its
# canonical key, so the constraint still sees it.
t.eq("abbreviated options still clash", cli6.parse(["--verb", "--qui"]).errors.include?("mutually exclusive options: --quiet and --verbose"), true)

# A conflict error accumulates alongside other validation errors.
opts = cli6.parse(["--verbose", "--quiet", "--bogus"])
t.eq("conflict and unknown-option errors accumulate", opts.errors.size(), 2)

# ---- Named positional arguments (from the SYNOPSIS) ----
# The SYNOPSIS line names each operand; argon exposes them by name with typed
# access. Bracketed "\[NAME]" operands are optional, "<NAME>" required, and a
# trailing "NAME..." (or "\[NAME ...]") is variadic. Values are cast like option
# values, so a numeric operand arrives typed. Fixed operands consume one argv
# positional each, left to right; the variadic operand takes the rest.

MAN7 = "NAME
    build -- exercise named positional arguments

SYNOPSIS
    build \[options] TARGET \[OUTPUT] \[FILE ...]

OPTIONS
    -v, --verbose
        Verbose output.

    -o, --opt VALUE
        Some option that takes a value.
"

cli7 = Argon.new(MAN7)

# Extraction from the SYNOPSIS.
pdefs = cli7.positional_defs
t.eq("synopsis declares three operands", pdefs.size(), 3)
t.eq("[options] placeholder is not an operand", pdefs[0][:name], "TARGET")
t.eq("first operand keyed from its synopsis name", pdefs[0][:key], "target")
t.eq("bare operand is required", pdefs[0][:required], true)
t.eq("bracketed operand is optional", pdefs[1][:required], false)
t.eq("bracketed operand is not variadic", pdefs[1][:variadic], false)
t.eq("trailing ellipsis operand is variadic", pdefs[2][:variadic], true)
t.eq("variadic operand keyed from its name", pdefs[2][:key], "file")

# Named access, order-mapped.
opts = cli7.parse(["app", "out.bin", "a.txt", "b.txt"])
t.eq("first operand by name", opts.positional(:target), "app")
t.eq("second operand by name", opts.positional(:output), "out.bin")
t.eq("variadic operand returns the rest", opts.positional(:file), ["a.txt", "b.txt"])

# Typed casting of operands.
opts = cli7.parse(["42"])
t.eq("numeric operand is cast typed", opts.positional(:target), 42)

# Absent operands.
opts = cli7.parse(["app"])
t.eq("absent optional operand is nil", opts.positional(:output) == nil, true)
t.eq("absent variadic operand is empty", opts.positional(:file), [])
t.eq("unknown operand name is nil", opts.positional(:nope) == nil, true)

# Operands coexist with flags and value options (which consume their own argv).
opts = cli7.parse(["-v", "app", "out.bin"])
t.eq("operand resolves past a boolean flag", opts.positional(:target), "app")
t.eq("flag alongside operands is still set", opts.flag?(:verbose), true)

opts = cli7.parse(["--opt", "X", "app"])
t.eq("value option does not steal an operand", opts.positional(:target), "app")

# Deterministic operand-name listing.
t.eq("operand names listed in synopsis order", cli7.parse([]).positional_names, ["target", "output", "file"])

# Opt-in missing-required-operand reporting (does not affect valid?).
t.eq("missing required operand is reported", cli7.parse([]).missing_arguments, ["TARGET"])
t.eq("supplied required operand is not missing", cli7.parse(["app"]).missing_arguments, [])
t.eq("operands stay out of lenient valid?", cli7.parse([]).valid?, true)

# Angle-bracketed <NAME> is required; a bare "NAME..." (no brackets) is variadic.
MAN8 = "NAME
    cat -- exercise angle-bracket and bare-ellipsis operands

SYNOPSIS
    cat <SOURCE> DEST...

OPTIONS
    -n, --number
        Number the output lines.
"

cli8 = Argon.new(MAN8)
pd8 = cli8.positional_defs
t.eq("angle-bracket operand extracted", pd8[0][:key], "source")
t.eq("angle-bracket operand is required", pd8[0][:required], true)
t.eq("bare-ellipsis operand is variadic", pd8[1][:variadic], true)
t.eq("bare-ellipsis operand is required", pd8[1][:required], true)

opts = cli8.parse(["in.txt", "a", "b", "c"])
t.eq("angle-bracket operand value", opts.positional(:source), "in.txt")
t.eq("bare-ellipsis variadic collects the rest", opts.positional(:dest), ["a", "b", "c"])

# A space-separated lone "..." attaches to the preceding operand.
MAN9 = "NAME
    rm -- exercise a space-separated ellipsis

SYNOPSIS
    rm \[options] FILE ...

OPTIONS
    -f, --force
        Force removal.
"

cli9 = Argon.new(MAN9)
pd9 = cli9.positional_defs
t.eq("spaced ellipsis yields one operand", pd9.size(), 1)
t.eq("spaced ellipsis marks the operand variadic", pd9[0][:variadic], true)
t.eq("spaced-ellipsis operand keeps its name", pd9[0][:key], "file")

opts = cli9.parse(["-f", "a", "b"])
t.eq("spaced-ellipsis variadic collects operands", opts.positional(:file), ["a", "b"])

# ---- Generated usage synopsis ----
# Argon generates an argparse/getopt-style "usage:" line straight from the
# parsed option and operand definitions, so it can never drift from what the
# parser accepts. Options appear in manpage order, bracketed unless "(required)":
# value options show their metavar, array options an ellipsis, optional-value
# options a nested bracket. Named operands from the SYNOPSIS follow, bracketed
# when optional and suffixed "..." when variadic. It is reachable from both the
# parser and the parse result (the latter delegates), ideal for prefixing errors.

# The value placeholder ("metavar") is now captured from the option line.
t.eq("value option captures its metavar", cli.find_by_key("out")[:value_name], "FILE")
t.eq("single-letter metavar captured", cli.find_by_key("jobs")[:value_name], "N")
t.eq("array option captures its bracketed metavar", cli.find_by_key("files")[:value_name], "FILE")
t.eq("optional-value option captures its metavar", cli.find_by_key("profile")[:value_name], "MODE")
t.eq("negatable flag has no metavar", cli.find_by_key("color")[:value_name] == nil, true)
t.eq("boolean flag has no metavar", cli.find_by_key("debug")[:value_name] == nil, true)

# The full synopsis for the probe manpage, exact form.
t.eq("full usage synopsis is generated in manpage order", cli.usage(), "usage: probe \[-C] \[-d] \[-o FILE] \[-j N] \[-t VERSION] \[-r HZ] \[--files FILE...] \[-p \[MODE]] file")

# It begins with "usage:" and the program name.
t.eq("usage line names the program", cli.usage().starts_with?("usage: probe"), true)

# Short form is preferred when present; long form used when there is no short.
t.eq("short form preferred in usage", cli.usage().index("\[-o FILE]") != nil, true)
t.eq("long form used when no short flag exists", cli.usage().index("\[--files FILE...]") != nil, true)

# Optional-value options render a nested bracket.
t.eq("optional-value option renders nested brackets", cli.usage().index("\[-p \[MODE]]") != nil, true)

# The required operand "file" trails, unbracketed.
t.eq("required operand trails the usage line unbracketed", cli.usage().ends_with?(" file"), true)

# The parse result delegates to the same generated usage.
t.eq("result usage delegates to the parser", cli.parse([]).usage(), cli.usage())

# A "(required)" option is shown WITHOUT brackets; optionals keep theirs.
t.eq("required option is unbracketed in usage", cli4.usage().index("-i FILE") != nil, true)
t.eq("required option has no leading bracket", cli4.usage().index("\[-i FILE]") == nil, true)
t.eq("non-required option stays bracketed alongside a required one", cli4.usage().index("\[-o FILE]") != nil, true)

# Named operands: required bare, optional bracketed, variadic suffixed "...".
t.eq("required operand appears bare in usage", cli7.usage().index(" TARGET ") != nil, true)
t.eq("optional operand is bracketed in usage", cli7.usage().index("\[OUTPUT]") != nil, true)
t.eq("variadic operand is suffixed with an ellipsis", cli7.usage().index("\[FILE...]") != nil, true)

# A required variadic operand (bare-ellipsis SYNOPSIS) is unbracketed + "...".
t.eq("required variadic operand is unbracketed with ellipsis", cli8.usage().ends_with?(" DEST..."), true)

# Array metavar renders with an ellipsis mid-line, ahead of the operand.
t.eq("array metavar renders inline with an ellipsis", cli3.usage().index("\[--nums N...]") != nil, true)
t.eq("operand still trails after an array option", cli3.usage().ends_with?(" file"), true)

# ---- Generated help body (--help) ----
# Building on the usage synopsis, argon renders a full --help body: the usage
# line, a blank line, then an aligned "Options:" table pairing each option's
# flag forms (both short and long, with metavar) against the description text
# extracted from the manpage. Like usage(), it is derived from the same defs
# parse() uses, so it can never drift from what the parser accepts. It is
# reachable from both the parser and the parse result (the latter delegates).

help = cli.help_text()

# The body opens with the generated usage synopsis, then a blank line and the
# option table heading.
t.eq("help body begins with the usage synopsis", help.starts_with?(cli.usage()), true)
t.eq("help body has a blank-line-separated Options heading", help.index("\n\nOptions:") != nil, true)

# Each option row shows BOTH flag forms and its metavar (unlike the bracketed
# usage synopsis, no outer brackets are drawn — the column handles layout).
t.eq("value option row shows both forms and its metavar", help.index("-o, --out FILE") != nil, true)
t.eq("boolean flag row shows both forms and no metavar", help.index("-d, --debug ") != nil, true)

# A negatable flag advertises negation with a \[no-] prefix in the table.
t.eq("negatable flag row shows the \[no-] prefix", help.index("-C, --\[no-]color") != nil, true)

# Array and optional-value metavars render as they do in the synopsis, minus
# the outer bracket: an ellipsis for arrays, a nested bracket for optionals.
t.eq("array option row renders an ellipsis metavar", help.index("--files FILE...") != nil, true)
t.eq("optional-value option row renders a nested-bracket metavar", help.index("-p, --profile \[MODE]") != nil, true)

# The manpage description text is carried into each row.
t.eq("description text is rendered in the help body", help.index("Write output to FILE.") != nil, true)

# The widest option row determines the column; its description follows after a
# two-space gap (exact form).
t.eq("widest option row has a two-space gap before its description", help.index("-p, --profile \[MODE]  Profile, optionally in MODE.") != nil, true)

# Descriptions align into a shared column across rows of differing label width.
hrows = help.split("\n")
t.eq("descriptions align to a shared column across rows", hrows[4].index("Enable debug mode."), hrows[5].index("Write output to FILE."))

# The generated body is distinct from the raw-manpage passthrough (help()).
t.eq("generated help body differs from the raw manpage", help == cli.help(), false)

# The parse result delegates to the same generated help body.
t.eq("result help_text delegates to the parser", cli.parse([]).help_text(), help)

# A manpage that declares no options renders the usage line alone (no table).
MAN10 = "NAME
    bare -- a command with no options

SYNOPSIS
    bare FILE
"
cli10 = Argon.new(MAN10)
t.eq("no-options help body is the usage line alone", cli10.help_text(), cli10.usage())
t.eq("no-options help body has no Options heading", cli10.help_text().index("Options:") == nil, true)

# ---- Comma-separated list values ("(list)") ----
# An option annotated "(list)" takes a single comma-separated token and splits
# it into a typed array (the common "--tags a,b,c" idiom). This differs from an
# "\[NAME ...]" array option, which consumes multiple argv tokens; a list travels
# in one token. Elements are cast with the usual rules and whitespace-trimmed,
# repeated uses accumulate, and it works across every value form (=, space,
# short, attached-short) and composes with choices validation.

MAN11 = "NAME
    tagger -- exercise comma-separated list values

SYNOPSIS
    tagger \[options] file

OPTIONS
    -t, --tags LIST
        Comma-separated tags. (list)

    -p, --ports LIST
        Comma-separated ports. (list)

    -m, --mode MODE
        Operating mode. (list) (one of: fast, slow)

    -b, --bare
        A list option declared without a metavar. (list)

    -o, --out FILE
        A plain, non-list value option.
"

cli11 = Argon.new(MAN11)

# Annotation extraction.
t.eq("(list) annotation marks an option as a list", cli11.find_by_key("tags")[:list], true)
t.eq("a plain value option is not a list", cli11.find_by_key("out")[:list], false)
t.eq("(list) with no metavar still takes a value", cli11.find_by_key("bare")[:takes_value], true)
t.eq("a list option is not an \[NAME ...] array", cli11.find_by_key("tags")[:array], false)

# Splitting a single token into a typed array across every value form.
opts = cli11.parse(["--tags", "a,b,c"])
t.eq("space form splits a comma list", opts.get(:tags), ["a", "b", "c"])

opts = cli11.parse(["--tags=a,b,c"])
t.eq("=value form splits a comma list", opts.get(:tags), ["a", "b", "c"])

opts = cli11.parse(["-t", "a,b,c"])
t.eq("short form splits a comma list", opts.get(:tags), ["a", "b", "c"])

opts = cli11.parse(["-ta,b,c"])
t.eq("attached-short form splits a comma list", opts.get(:tags), ["a", "b", "c"])

# Elements are cast with the usual rules; whitespace around each is trimmed.
opts = cli11.parse(["--ports", "8080,9090,443"])
t.eq("list elements are cast to their types", opts.get(:ports), [8080, 9090, 443])

opts = cli11.parse(["--tags", "a, b , c"])
t.eq("list elements are whitespace-trimmed", opts.get(:tags), ["a", "b", "c"])

# A single element (no comma) still yields a one-element array.
opts = cli11.parse(["--tags", "solo"])
t.eq("a single value is a one-element list", opts.get(:tags), ["solo"])

# A list travels in one token — it does NOT swallow following positionals.
opts = cli11.parse(["--tags", "a,b", "file.w"])
t.eq("a list consumes one token, leaving positionals", opts.args, ["file.w"])

# Repeated list options accumulate their elements.
opts = cli11.parse(["--tags", "a,b", "--tags", "c,d"])
t.eq("repeated list options accumulate elements", opts.get(:tags), ["a", "b", "c", "d"])

# A list composes with choices validation, checked element-wise.
t.eq("list with all-valid choice elements is valid", cli11.parse(["--mode", "fast,slow"]).valid?, true)
t.eq("list with an invalid choice element is invalid", cli11.parse(["--mode", "fast,nope"]).valid?, false)

# An absent list option falls through to its (here nil) default.
t.eq("absent list option is nil", cli11.parse([]).get(:tags) == nil, true)

# A list option renders as a plain value option in the usage synopsis.
t.eq("list option appears with its metavar in usage", cli11.usage().index("\[-t LIST]") != nil, true)

# ---- Long-option abbreviation (getopt_long unambiguous-prefix matching) ----
# An unambiguous prefix of a long option is accepted ("--verb" for "--verbose").
# An exact match always wins over a prefix; a prefix shared by two or more
# options is left unresolved and surfaces through validation as an ambiguous
# option, naming the candidates. Resolution records under the option's canonical
# key, so the shortened form is invisible to flag?/get/occurrences. It applies
# to both the space and "=value" long forms.

MAN12 = "NAME
    abbr -- exercise long-option abbreviation

SYNOPSIS
    abbr \[options] file

OPTIONS
    -v, --verbose
        Verbose output.

    --version
        Print version and exit.

    -c, --color
        Colorize output.

    --config FILE
        Read configuration from FILE.

    --count N
        Repeat count.

    -o, --output FILE
        Write to FILE.

    --sort
        Sort output.

    --sort-keys
        Sort by keys.
"

cli12 = Argon.new(MAN12)

# An unambiguous prefix resolves to the canonical key (flag is invisible-shortened).
opts = cli12.parse(["--verb"])
t.eq("unambiguous prefix resolves a flag", opts.flag?(:verbose), true)
t.eq("resolved abbreviation is valid", opts.valid?, true)
t.eq("resolved abbreviation is not collected as unknown", opts.unknown, [])

# The full name still works unchanged.
t.eq("exact long name still resolves", cli12.parse(["--verbose"]).flag?(:verbose), true)

# A prefix that singles out the LONGER of two similar names resolves it.
t.eq("longer-name prefix resolves the longer option", cli12.parse(["--vers"]).flag?(:version), true)
t.eq("longer-name prefix does not set the shorter option", cli12.parse(["--vers"]).flag?(:verbose), false)

# An unambiguous prefix resolves a value option, both space and =value forms.
t.eq("prefix resolves a value option (space form)", cli12.parse(["--conf", "f.cfg"]).get(:config), "f.cfg")
t.eq("prefix resolves a value option (=value form)", cli12.parse(["--conf=f.cfg"]).get(:config), "f.cfg")

# The resolved value is cast and reachable under the canonical key.
t.eq("prefix-resolved value option is cast under its canonical key", cli12.parse(["--cou", "3"]).get(:count), 3)
t.eq("prefix resolves the long output option", cli12.parse(["--out", "x"]).get(:output), "x")

# An exact match wins over being a prefix of a longer option ("--sort" is exact
# even though "sort" prefixes "sort-keys").
opts = cli12.parse(["--sort"])
t.eq("exact match wins over a longer option it prefixes", opts.flag?(:sort), true)
t.eq("exact match does not set the longer option", opts.flag?(:sort_keys), false)

# A longer unambiguous prefix reaches the dashed long name.
t.eq("longer unique prefix resolves a dashed long option", cli12.parse(["--sort-k"]).flag?(:sort_keys), true)

# An ambiguous prefix is left unresolved and reported by validation.
opts = cli12.parse(["--ver"])
t.eq("ambiguous prefix makes input invalid", opts.valid?, false)
t.eq("ambiguous prefix reported with sorted candidates", opts.errors.include?("ambiguous option: --ver (matches --verbose, --version)"), true)

# Ambiguity across three candidates, sorted.
t.eq("three-way ambiguous prefix names all candidates", cli12.parse(["--co"]).errors.include?("ambiguous option: --co (matches --color, --config, --count)"), true)

# Ambiguity in the =value form is caught too.
t.eq("ambiguous =value prefix is invalid", cli12.parse(["--co=1"]).valid?, false)

# An ambiguous prefix of two dashed-name options.
t.eq("ambiguous prefix of dashed names reports both", cli12.parse(["--sor"]).errors.include?("ambiguous option: --sor (matches --sort, --sort-keys)"), true)

# A genuinely unrecognized long option is still an unknown option, not ambiguous.
t.eq("unmatched long option is still unknown, not ambiguous", cli12.parse(["--xyzzy"]).errors.include?("unknown option: --xyzzy"), true)

# Abbreviation works on the original probe manpage too: the positive form of a
# negatable flag, and an optional-value / value option, all abbreviate.
t.eq("prefix resolves the positive form of a negatable flag", cli.parse(["--col"]).flag?(:color), true)
t.eq("prefix resolves an optional-value option", cli.parse(["--pro", "fast"]).get(:profile), "fast")
t.eq("prefix resolves a value option on the probe manpage", cli.parse(["--jo", "4"]).get(:jobs), 4)

# ---- Abbreviation x "--no-" forms ----
# "--no-X" is read as a negation only when it is not itself a defined option.
# Both halves of that decision go through the abbreviation resolver: an
# abbreviated real option ("--no-cac" for "--no-cache") must not be mistaken for
# a negation, and the negated form of a negatable flag abbreviates too
# ("--no-col" negates "--\[no-]color"), recording under the canonical key. An
# unresolvable "--no-X" keeps the lenient path.

MAN13 = "NAME
    npmish -- exercise --no- prefixed options alongside negation

SYNOPSIS
    npmish \[options] file

OPTIONS
    --no-cache
        Disable the cache. An option whose real name begins with no-.

    -C, --\[no-]color
        Colorize output.

    --network
        Use the network.
"

cli13 = Argon.new(MAN13)

# An option literally named "--no-cache" is a flag, not a negation of "--cache".
t.eq("--no-X option name is keyed whole", cli13.find_by_key("no_cache")[:long], "no-cache")
opts = cli13.parse(["--no-cache"])
t.eq("exact --no-X option sets its flag", opts.flag?(:no_cache), true)
t.eq("exact --no-X option is not an unknown option", opts.unknown, [])

# ...and it stays reachable when abbreviated, instead of being swallowed as a
# negation of the nonexistent "--cac".
opts = cli13.parse(["--no-cac"])
t.eq("abbreviated --no-X option resolves to its canonical key", opts.flag?(:no_cache), true)
t.eq("abbreviated --no-X option is not read as a negation", opts.negated?(:cac), false)
t.eq("abbreviated --no-X option is valid", opts.valid?, true)

# A genuine negation still negates, abbreviated or not.
t.eq("exact negation still negates", cli13.parse(["--no-color"]).negated?(:color), true)
opts = cli13.parse(["--no-col"])
t.eq("abbreviated negation negates under the canonical key", opts.negated?(:color), true)
t.eq("abbreviated negation is not flag?-true", opts.flag?(:color), false)
t.eq("abbreviated negation is valid", opts.valid?, true)

# The positive abbreviation of the same flag is unaffected.
t.eq("positive abbreviation of a negatable flag still sets it", cli13.parse(["--col"]).flag?(:color), true)

# An unresolvable "--no-X" keeps the lenient path: recorded as a negation of X,
# and surfaced by validation as an unknown option.
opts = cli13.parse(["--no-frobnicate"])
t.eq("unknown --no-X is still recorded as a negation", opts.negated?(:frobnicate), true)
t.eq("unknown --no-X is reported as an unknown option", opts.unknown, ["--frobnicate"])

# ---- Inline descriptions containing a comma ----
# An option line's flag forms are comma-separated, and argon also accepts the
# description inline on that same line ("hammer-style"). A comma inside that
# description therefore splits into a part that can itself begin with a
# flag-shaped token ("..., -q for quiet" / "..., --stdout prints instead").
# First form wins for both names, so trailing prose cannot redefine the
# option's short letter or its key.

MAN14 = "NAME
    hammer -- exercise inline descriptions that contain commas

SYNOPSIS
    hammer \[options] file

OPTIONS
    -v, --verbose  Verbose output, -q for quiet

    -o, --out FILE  Write to FILE, --stdout prints instead

    -j, --jobs N  Parallel jobs, --serial disables (default: 8)
"

cli14 = Argon.new(MAN14)

# A short flag named in the prose does not become the option's short form.
t.eq("prose short flag does not steal the short form", cli14.find_by_key("verbose")[:short], "v")
opts = cli14.parse(["-v"])
t.eq("documented short flag still parses", opts.flag?(:verbose), true)
t.eq("documented short flag is not unknown", opts.unknown, [])

# A long flag named in the prose does not become the option's key.
t.eq("prose long flag does not steal the key", cli14.find_by_key("out")[:long], "out")
t.eq("prose long flag does not steal the metavar", cli14.find_by_key("out")[:value_name], "FILE")
t.eq("documented long option still parses", cli14.parse(["--out", "x"]).get(:out), "x")
t.eq("documented short form of it still parses", cli14.parse(["-o", "x"]).get(:out), "x")

# The inline "(default: N)" on such a line is still extracted, under the right key.
t.eq("inline default survives a comma in the description", cli14.parse([]).get(:jobs), 8)
t.eq("value option after a prose comma still takes its value", cli14.parse(["-j", "2"]).get(:jobs), 2)

# The generated usage advertises the documented forms.
t.eq("usage advertises the documented short form", cli14.usage(), "usage: hammer \[-v] \[-o FILE] \[-j N] file")

# ---- Degenerate and empty values ----
# An empty "=value" is a value: it must beat the manpage default rather than
# fall through it, and a zero must not read as "absent" either.

t.eq("empty =value is preserved, not replaced by the default", cli2.parse(["--out="]).get(:out), "")
t.eq("empty =value is preserved over an explicit default too", cli2.parse(["--out="]).get(:out, "a.out"), "")
t.eq("a zero value does not fall through to the default", cli.parse(["--jobs", "0"]).get(:jobs), 0)
t.eq("empty argv leaves no rest", cli.parse([]).passthrough, [])

# ---- "--" and the =value form against array options ----
# "--" is not value-like, so it stops array consumption and everything past it
# is passthrough; the "=value" form of an array option appends like the spaced
# form does.

opts = cli.parse(["--files", "a", "--", "b"])
t.eq("-- stops array-option consumption", opts.get(:files), ["a"])
t.eq("tokens after -- are passthrough, not array elements", opts.passthrough, ["b"])

opts = cli.parse(["--profile", "--", "x"])
t.eq("-- is not an optional value", opts.get(:profile), true)
t.eq("-- after an optional-value option still separates", opts.passthrough, ["x"])

t.eq("=value form of an array option accumulates", cli.parse(["--files=a", "--files=b"]).get(:files), ["a", "b"])
t.eq("=value form appends to a spaced array option", cli.parse(["--files", "a", "b", "--files=c"]).get(:files), ["a", "b", "c"])

t.done

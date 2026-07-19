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

t.done

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

t.done

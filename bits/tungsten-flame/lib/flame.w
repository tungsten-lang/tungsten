# tungsten-flame — Flame graph profiler
# CLI: tungsten flame <file.w> [options]
#
# Entrypoint: parses argv via Argon, dispatches to a profile mode,
# runs Builder → Sampler → FlameAnalyzer.

# NOTE: the worker classes live in the Tungsten:Flame namespace, and
# top-level statements do NOT inherit an `in` scope (in either engine),
# so every cross-class call below must be fully qualified
# (Tungsten:Flame:Sampler etc.). Argon is a root-namespace class.

use argon
use sidemap
use analyzer
use perf_script
use xctrace_xml
use builder
use sampler
use flame_svg
use flame_diff
use speedscope
use hot_frames
use flame_filter

# ---- Read and parse the manpage ----
# Prefer TUNGSTEN_ROOT (set by the CLI); __DIR__ is not always populated
# for compile-to-binary entry points.

manpage = nil
root = env("TUNGSTEN_ROOT")
if root != nil && root != ""
  manpage = read_file(root + "/bits/tungsten-flame/man/flame.5.wd")
if manpage == nil
  # Dev fallback when running the .w source via the interpreter
  if __DIR__ != nil
    manpage = read_file(__DIR__ + "/../man/flame.5.wd")
if manpage == nil
  << "tungsten flame: could not read manpage (set TUNGSTEN_ROOT)"
  exit(1)
cli = Argon.new(manpage)

# ============================================================
# Parse argv and dispatch.
# ============================================================

opts = cli.parse(argv())

if opts.flag?("help") || opts.flag?("h")
  opts.help!

# Bind argv options to locals.  Stable surface for later stages.
fl_duration = opts.get("duration")
if fl_duration == nil
  fl_duration = "5"
fl_duration = fl_duration.to_i
fl_rate_raw = opts.get("rate")
if fl_rate_raw == nil
  fl_rate_raw = ""
fl_rate = nil
if fl_rate_raw != ""
  fl_rate = fl_rate_raw.to_i
fl_top = opts.get("top")
if fl_top == nil
  fl_top = "10"
fl_top = fl_top.to_i
fl_pid_raw = opts.get("pid")
if fl_pid_raw == nil
  fl_pid_raw = ""
fl_pid = nil
if fl_pid_raw != ""
  fl_pid = fl_pid_raw.to_i
fl_focus = opts.get("focus")
if fl_focus == nil
  fl_focus = ""
fl_grep = opts.get("grep")
if fl_grep == nil
  fl_grep = ""
fl_prune = opts.get("prune")
if fl_prune == nil
  fl_prune = ""
fl_subtree = opts.get("subtree")
if fl_subtree == nil
  fl_subtree = ""
fl_output = opts.get("output")
if fl_output == nil
  fl_output = ""
fl_keeper      = opts.get("keeper")
fl_lex         = opts.flag?("lex")
fl_ruby        = opts.flag?("ruby")
fl_parse       = opts.flag?("parse")
fl_execution   = opts.flag?("execution")
fl_build_only  = opts.flag?("build_only")
fl_silent      = opts.flag?("silent")
fl_diff        = opts.flag?("diff")
fl_hot         = opts.flag?("hot")
fl_speedscope  = opts.flag?("speedscope")
fl_files       = opts.args
fl_passthrough = opts.passthrough

# Mode dispatch.

# Differential mode: compare two already-collected folded profiles
# (`flame --diff BEFORE.folded AFTER.folded`). Operates purely on folded
# text — no compile, no profiling — so it works on any folded stacks,
# whoever produced them. Prints a normalized regressed/improved summary;
# with -o, also writes the folded "stack delta" diff for downstream tools.
if fl_diff
  if fl_files.size < 2
    << "tungsten flame --diff: need two folded files (BEFORE AFTER)"
    exit(1)
  before_path = fl_files[0]
  after_path = fl_files[1]
  before_text = read_file(before_path)
  if before_text == nil
    << "tungsten flame: cannot read " + before_path
    exit(1)
  after_text = read_file(after_path)
  if after_text == nil
    << "tungsten flame: cannot read " + after_path
    exit(1)
  << Tungsten:Flame:FlameDiff.report(before_text, after_text, fl_top, !fl_silent)
  if fl_output != ""
    write_file(fl_output, Tungsten:Flame:FlameDiff.diff_normalized(before_text, after_text))
    if !fl_silent
      << "wrote diff folded: " + fl_output
  exit(0)

# Hot-frames mode: a flat "self vs total" profile from one or more folded
# files (`flame --hot FILE.folded [MORE.folded ...]`). Like --diff, it
# operates purely on folded text — no compile, no profiling — so it works
# on any folded stacks, whoever produced them. Multiple files aggregate:
# concatenated folded text sums duplicate stacks, combining N runs into one
# report. Ranks frames by inclusive (total) time, showing self alongside —
# the view the self-only "Top Functions" list and the SVG picture omit.
if fl_hot
  if fl_files.size < 1
    << "tungsten flame --hot: need at least one folded file"
    exit(1)
  combined = ""
  hi = 0
  while hi < fl_files.size
    ftext = read_file(fl_files[hi])
    if ftext == nil
      << "tungsten flame: cannot read " + fl_files[hi]
      exit(1)
    if combined != ""
      combined = combined + "\n"
    combined = combined + ftext
    hi = hi + 1
  << Tungsten:Flame:HotFrames.report(combined, fl_top, !fl_silent)
  exit(0)

# Filter mode: reshape one folded profile before viewing it — include
# (`--grep PAT`), exclude (`--prune PAT`), or zoom into a subtree
# (`--subtree PAT`). Like --diff / --hot, a pure folded-text mode (no compile,
# no profiling) that works on any folded stacks. Emits folded text — pipe it
# into another view (`flame --grep parse x.folded > sub.folded`). With -o the
# result is written to the file instead of stdout.
if fl_grep != "" || fl_prune != "" || fl_subtree != ""
  if fl_files.size < 1
    << "tungsten flame: filter needs one folded file"
    exit(1)
  ftext = read_file(fl_files[0])
  if ftext == nil
    << "tungsten flame: cannot read " + fl_files[0]
    exit(1)
  filtered = Tungsten:Flame:FlameFilter.apply(ftext, fl_grep, fl_prune, fl_subtree)
  if fl_output != ""
    write_file(fl_output, filtered)
    if !fl_silent
      << "wrote filtered folded: " + fl_output + " (" + Tungsten:Flame:FlameFilter.stack_count(filtered).to_s() + " stacks)"
  else
    << filtered
  exit(0)

if fl_pid != nil
  << "TODO: attach to pid " + fl_pid.to_s + " for " + fl_duration.to_s + "s"
  exit(0)

if fl_passthrough.size > 0
  << "TODO: profile external command: " + fl_passthrough.join(" ")
  exit(0)

if fl_lex
  << "TODO: profile lexer over " + fl_files.size.to_s + " file(s)"
  exit(0)

if fl_files.size == 0
  << "tungsten flame v0.3.0"
  << ""
  help_text = cli.help
  if help_text != nil
    << help_text
  exit(0)

if fl_ruby
  << "TODO: profile ruby interpreter on " + fl_files[0]
  exit(0)

# ---- Compile + profile + display ----
source = fl_files[0]
if !file?(source)
  << "tungsten flame: source not found: " + source
  exit(1)

tmpdir = Tungsten:Flame:Sampler.mktmpdir

if fl_build_only
  build_out = (fl_output != "") ? fl_output : ("flame_" + Tungsten:Flame:Sampler.basename_noext(source))
  ok = Tungsten:Flame:Builder.compile(source, build_out)
  if !ok
    << "tungsten flame: build failed"
    exit(1)
  << "built " + build_out
  exit(0)

bin_path = tmpdir + "/flame_bin"
build_ok = Tungsten:Flame:Builder.compile(source, bin_path)
if !build_ok
  << "tungsten flame: build failed"
  exit(1)

metrics = Tungsten:Flame:Sampler.profile(bin_path, fl_duration, fl_rate)
metric_names = metrics.keys
if metric_names.size == 0
  << "tungsten flame: profiling produced no samples"
  exit(1)

use_color = !fl_silent

# Primary metric: prefer "cycles" (Linux) then "samples" (macOS time
# profile) then "branches" (slot 0 of the counter template — the
# steadiest time proxy of the PMC set); else fall back to the first key.
# The explicit chain matters: metrics.keys comes back in hash order, so
# metric_names[0] alone would make the primary pick nondeterministic.
primary = "cycles"
if !metrics.has_key?(primary)
  primary = "samples"
  if !metrics.has_key?(primary)
    primary = "branches"
    if !metrics.has_key?(primary)
      primary = metric_names[0]

# Map deduped `__wy_*` symbols back to real names via the sidemap the
# compiler wrote next to the binary we just built, then write each
# metric to its own folded file under tmpdir. Rewriting the folded
# text itself (not just the display) means SVG flame graphs and any
# later consumer of the .folded files inherit the real names too.
wy_names = Tungsten:Flame:Sidemap.load(bin_path + ".sidemap")
i = 0
while i < metric_names.size
  m = metric_names[i]
  write_file(tmpdir + "/" + m + ".folded", Tungsten:Flame:Sidemap.rewrite_folded(metrics[m], wy_names))
  i = i + 1

# Interactive output for the primary metric, from its sidemap-rewritten
# folded stacks (so frames carry real names).
#
# --speedscope exports a speedscope.app JSON profile (Time-Order,
# Left-Heavy, and Sandwich views in the standard web viewer) — to
# --output when given, else a default `<base>.speedscope.json`. Otherwise
# -o writes the self-contained SVG flame graph (the namesake output; `-o`
# with no extension still produces a valid SVG).
if fl_speedscope
  ss_path = (fl_output != "") ? fl_output : ("flame_" + Tungsten:Flame:Sampler.basename_noext(source) + ".speedscope.json")
  primary_folded = read_file(tmpdir + "/" + primary + ".folded")
  ss_name = Tungsten:Flame:Sampler.basename_noext(source) + " (" + primary + ")"
  write_file(ss_path, Tungsten:Flame:Speedscope.export(primary_folded, ss_name))
  if !fl_silent
    << "wrote speedscope profile: " + ss_path
    << "open at https://www.speedscope.app"
elsif fl_output != ""
  svg_path = fl_output
  primary_folded = read_file(tmpdir + "/" + primary + ".folded")
  svg_title = "Flame Graph — " + Tungsten:Flame:Sampler.basename_noext(source) + " (" + primary + ")"
  write_file(svg_path, Tungsten:Flame:FlameSvg.render(primary_folded, svg_title))
  if !fl_silent
    << "wrote flame graph: " + svg_path

# Full breakdown for primary metric (Top + caller/callee + categories).
Tungsten:Flame:FlameAnalyzer.display_metric(tmpdir + "/" + primary + ".folded", fl_top, "general", fl_focus, use_color, primary)

# Compact Top-N per secondary metric.
i = 0
while i < metric_names.size
  m = metric_names[i]
  if m != primary
    Tungsten:Flame:FlameAnalyzer.display_top_only(tmpdir + "/" + m + ".folded", fl_top, m, use_color)
  i = i + 1

exit(0)

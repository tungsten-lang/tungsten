# tungsten-flame — Flame graph profiler
# CLI: tungsten flame <file.w> [options]
#
# Entrypoint: parses argv via Argon, dispatches to a profile mode,
# runs Builder → Sampler → FlameAnalyzer.

use argon
use analyzer
use perf_script
use xctrace_xml
use builder
use sampler

# Boot marker (also forces top-level statements after uses).
# << "flame boot"

module Flame
  VERSION = "0.3.0"

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
fl_duration = fl_duration.to_i()
fl_rate_raw = opts.get("rate")
if fl_rate_raw == nil
  fl_rate_raw = ""
fl_rate = nil
if fl_rate_raw != ""
  fl_rate = fl_rate_raw.to_i()
fl_top = opts.get("top")
if fl_top == nil
  fl_top = "10"
fl_top = fl_top.to_i()
fl_pid_raw = opts.get("pid")
if fl_pid_raw == nil
  fl_pid_raw = ""
fl_pid = nil
if fl_pid_raw != ""
  fl_pid = fl_pid_raw.to_i()
fl_focus = opts.get("focus")
if fl_focus == nil
  fl_focus = ""
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
fl_files       = opts.args()
fl_passthrough = opts.passthrough()

# Mode dispatch.
if fl_pid != nil
  << "TODO: attach to pid " + fl_pid.to_s() + " for " + fl_duration.to_s() + "s"
  exit(0)

if fl_passthrough.size() > 0
  << "TODO: profile external command: " + fl_passthrough.join(" ")
  exit(0)

if fl_lex
  << "TODO: profile lexer over " + fl_files.size().to_s() + " file(s)"
  exit(0)

if fl_files.size() == 0
  << "tungsten flame v0.3.0"
  << ""
  help_text = cli.help()
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

tmpdir = Sampler.mktmpdir()

if fl_build_only
  build_out = (fl_output != "") ? fl_output : ("flame_" + Sampler.basename_noext(source))
  ok = Builder.compile(source, build_out)
  if !ok
    << "tungsten flame: build failed"
    exit(1)
  << "built " + build_out
  exit(0)

bin_path = tmpdir + "/flame_bin"
build_ok = Builder.compile(source, bin_path)
if !build_ok
  << "tungsten flame: build failed"
  exit(1)

metrics = Sampler.profile(bin_path, fl_duration, fl_rate)
metric_names = metrics.keys()
if metric_names.size() == 0
  << "tungsten flame: profiling produced no samples"
  exit(1)

use_color = !fl_silent

# Primary metric: prefer "cycles" (Linux) then "samples" (macOS), else
# fall back to first key.
primary = "cycles"
if !metrics.has_key?(primary)
  primary = "samples"
  if !metrics.has_key?(primary)
    primary = metric_names[0]

# Write each metric to its own folded file under tmpdir.
i = 0
while i < metric_names.size()
  m = metric_names[i]
  write_file(tmpdir + "/" + m + ".folded", metrics[m])
  i = i + 1

# Full breakdown for primary metric (Top + caller/callee + categories).
FlameAnalyzer.display(tmpdir + "/" + primary + ".folded", fl_top, "general", fl_focus, use_color)

# Compact Top-N per secondary metric.
i = 0
while i < metric_names.size()
  m = metric_names[i]
  if m != primary
    FlameAnalyzer.display_top_only(tmpdir + "/" + m + ".folded", fl_top, m, use_color)
  i = i + 1

exit(0)

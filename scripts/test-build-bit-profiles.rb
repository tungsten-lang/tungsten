#!/usr/bin/env ruby
# Run the actual native build-driver helpers without invoking a compiler
# bootstrap or rebuilding the runtime. Native assertions verify the resolved
# optimization environment and flags; package fixtures exercise entry parsing.
require "fileutils"
require "open3"
require "shellwords"
require "tmpdir"

root = File.expand_path("..", __dir__)
compiler = ENV.fetch("TUNGSTEN_COMPILER", File.join(root, "bin/tungsten-compiler"))
source = File.read(File.join(root, "bin/commands/build.w"))
names = %w[last_slash basename_of shq split_ws extract_quoted strip_bitfile_comment bit_option_tail bit_option_value bit_valid_opt_level bit_entry_points bit_relative_path? bit_profile_release bit_profile_flags bit_profile_clang_opt bit_native_flags bit_cflags_opt]
helpers = names.map do |name|
  source[/^-> #{Regexp.escape(name)}(?:\(|\s).*?(?=^-> |^CWD =|\z)/m] or raise "missing build helper #{name}"
end.join("\n")

Dir.mktmpdir("tungsten-bit-profiles-") do |directory|
  package = File.join(directory, "tungsten-probe")
  FileUtils.mkdir_p(package)
  File.write(File.join(package, "Bitfile"), <<~BITFILE)
    executable "hot", source: "bin/main.w", cflags: '-DNAME="hot" -Dtext=profile:debug -Dsource=source:bad #literal -O1', profile: "release", native: true, opt_level: "3" # outside comment
    executable "ordinary", source: "lib/main.w"
  BITFILE
  probe_source = File.join(directory, "probe.w")
  probe_binary = File.join(directory, "probe")
  File.write(probe_source, <<~W)
    -> die(message)
      << message
      exit(2)
    #{helpers}
    -> expect_profile(label, condition)
      if !condition
        << "FAIL " + label
        exit(1)
      1
    args = argv()
    if args[0] == "--quote-probe"
      << bit_cflags_opt("-O3", args[1], "", "", false, false)
      exit(0)
    entries = bit_entry_points(args[0])
    z = expect_profile("entry paths", entries.size == 2 && entries[0][:source] == "bin/main.w" && entries[1][:source] == "lib/main.w")
    z = expect_profile("entry profiles", entries[0][:profile] == "release" && entries[1][:profile] == "")
    z = expect_profile("entry native and optimization", entries[0][:native] && entries[0][:opt_level] == "3" && !entries[1][:native] && entries[1][:cflags] == "")
    z = expect_profile("quote-aware metadata and comment parsing", entries[0][:cflags].include?("#literal") && entries[0][:cflags].include?("profile:debug") && entries[0][:source] == "bin/main.w")
    defaults = ["--cpu", "native", "--debug"]
    optimized = bit_profile_flags(entries[0][:profile], defaults, false, false)
    z = expect_profile("release metadata", optimized.include?("--release") && optimized.include?("--no-debug") && !optimized.include?("--debug"))
    z = expect_profile("base flags retained", defaults.include?("--debug") && !defaults.include?("--release"))
    z = expect_profile("release optimization", bit_profile_clang_opt("release", "-O0", "", false, false, false) == "-O3")
    z = expect_profile("explicit fast only", bit_profile_clang_opt("release", "-O0 -ffast-math", "", false, false, true) == "-O3 -ffast-math")
    ordinary = bit_profile_flags(entries[1][:profile], defaults, false, false)
    z = expect_profile("ordinary unchanged", ordinary == defaults && bit_profile_clang_opt("", "-O0", "", false, false, false) == "-O0")
    debug = bit_profile_flags("release", defaults, false, true)
    z = expect_profile("explicit debug wins", debug == defaults && bit_profile_clang_opt("release", "-O0", "", false, true, false) == "-O0")
    z = expect_profile("explicit clang wins", bit_profile_clang_opt("release", "-O1 -g", "-O1 -g", false, false, false) == "-O1 -g")
    explicit_release = ["--release", "--debug"]
    z = expect_profile("explicit release/debug combination", bit_profile_flags("release", explicit_release, true, true) == explicit_release)
    z = expect_profile("debug profile overridden", bit_profile_flags("debug", explicit_release, true, false) == explicit_release)
    native = bit_native_flags(["--cpu", "host-default", "--debug"], true, false)
    z = expect_profile("native replaces inferred CPU", native == ["--debug", "--native"])
    z = expect_profile("explicit CPU target portable wins", bit_native_flags(defaults, true, true) == defaults)
    z = expect_profile("native absent unchanged", bit_native_flags(defaults, false, false) == defaults)
    flags = "-O1 -funroll-loops"
    z = expect_profile("manifest cflags can set optimization", bit_cflags_opt("-O0", flags, "", "", false, false) == "-O0 '-O1' '-funroll-loops'")
    z = expect_profile("manifest opt level wins", bit_cflags_opt("-O0", flags, "s", "", false, false) == "-O0 '-funroll-loops' -Os")
    z = expect_profile("explicit release wins", bit_cflags_opt("-O3", flags, "s", "", true, false) == "-O3 '-funroll-loops'")
    z = expect_profile("explicit debug wins", bit_cflags_opt("-O0", flags, "3", "", false, true) == "-O0 '-funroll-loops'")
    z = expect_profile("environment full override", bit_cflags_opt("-O2 -g", flags, "3", "-O2 -g", false, true) == "-O2 -g")
    << "PASS native bit profile resolution"
  W
  output, status = Open3.capture2e(compiler, "compile", probe_source, "--out", probe_binary, "--no-lto", chdir: root)
  raise output unless status.success?
  output, status = Open3.capture2e(probe_binary, package)
  raise output unless status.success?
  puts output

  {
    'profile: "typo"' => "profile must be release or debug",
    'native: "yes"' => "native must be true or false",
    'opt_level: "fastest"' => "opt_level must be",
    'cflags: -O3' => "cflags must be a quoted",
    'cflags: "unterminated' => "Missing value"
  }.each do |metadata, message|
    File.write(File.join(package, "Bitfile"), %(executable "bad", source: "lib/main.w", #{metadata}\n))
    output, status = Open3.capture2e(probe_binary, package)
    raise "invalid #{metadata} accepted: #{output}" unless status.exitstatus == 2 && output.include?(message)
  end

  marker = File.join(directory, "injected")
  hostile = %(-DNAME="solver" -DQUOTE=a'b -DX=$(touch${IFS}#{marker}) -DY=`touch${IFS}#{marker}` -DZ=abc;touch${IFS}#{marker} -Dhash=#literal\t-funroll-loops)
  encoded, status = Open3.capture2e(probe_binary, "--quote-probe", hostile)
  raise encoded unless status.success?
  # Exercise the same second shell parsing boundary used by the native compiler.
  arguments, status = Open3.capture2e("/bin/sh", "-c", %(set -- #{encoded.strip}; printf '%s\\n' "$@"))
  raise "cflags shell quoting changed arguments" unless status.success? && arguments.lines.map(&:chomp) == ["-O3", *hostile.split]
  raise "cflags executed shell code" if File.exist?(marker)
  puts "PASS literal macro quotes and shell metacharacters"
end

# These integration seams make per-entry resolved options affect the actual
# compiler invocation and cache, rather than merely existing as dead helpers.
raise "compiler lost per-entry flags" unless source.include?("flags_to_cmd(compiler_flags_arg)")
raise "bit-only compile lost profile" unless source.include?("compile_bit(bit_root_found, entry, out_bin, entry_clang_opt, entry_flags, toolchain_env_prefix)")
raise "root build lost profile" unless source.include?("compile_bit(bit_path, entry, out_bin, entry_clang_opt, entry_flags, toolchain_env_prefix)")
raise "profile cache version missing" unless source.include?("bit-entrypoints-v4-build-flags")
raise "cache lost resolved entry options" unless source.scan(/bit_sha =.*entry_clang_opt.*entry_flags/).length == 2
raise "target/portable no longer suppress manifest native" unless source.scan("native_mode || cpu_name != nil || target_triple != \"\" || portable_mode").length == 2
puts "PASS native build invocation/cache profile wiring"

#!/usr/bin/env ruby
# frozen_string_literal: true

# Contracts of the self-host build, through the real compiled build driver in
# an isolated checkout with a fake stage-0 VM, fake stage compilers and a fake
# C toolchain (as test-build-bit-driver.rb): no bootstrap, no native
# compilation.
#
# Stage identity:
#   - stage 1 .ll == stage 2 .ll: VERIFIED, stage 2 installed, exit 0;
#   - a mismatch on a plain local build: WARNING, stage 2 still installed (the
#     developer keeps a working compiler), profile records verified=0, exit 0;
#   - a mismatch under CI, --strict, --install, --pgo or a release artifact
#     build (--target / --portable): ERROR, nothing installed, no later phase
#     runs, exit 1.
#
# Release artifacts:
#   - every artifact compiler gets its own repl and metal images beside it,
#     compiled for the artifact's target and CPU (the host's images are built
#     for this machine and cannot be packaged).
#
# Usage: ruby scripts/test-build-self-host.rb bin/commands/build
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

driver = File.expand_path(ARGV.fetch(0))
raise "expected a compiled bin/commands/build.w driver" unless File.executable?(driver)

def write_tool(path, body)
  File.write(path, "#!#{RbConfig.ruby}\n" + body)
  FileUtils.chmod(0o755, path)
end

passed = 0
check = lambda do |name, ok, detail = ""|
  raise "FAIL #{name}\n#{detail}" unless ok
  passed += 1
  puts "PASS #{name}"
end

Dir.mktmpdir("tungsten-stage-identity-") do |directory|
  directory = File.realpath(directory)
  root = File.join(directory, "root")
  tools = File.join(directory, "tools")
  home = File.join(directory, "home")
  log = File.join(directory, "stages.jsonl")
  store = File.join(directory, "store")
  FileUtils.mkdir_p([File.join(root, "bin/commands"), File.join(root, "runtime"), File.join(root, "compiler"),
                     File.join(root, "core"), File.join(root, "languages/tungsten"),
                     File.join(root, "implementations/c"), tools, home])
  %w[compiler/tungsten.w core/tungsten.w bin/commands/build.w].each do |marker|
    File.write(File.join(root, marker), "# marker\n")
  end
  File.write(File.join(root, "bin/commands/cache_gc.sh"), "exit 0\n")
  # the real location/key policy script (the driver asks it for fingerprints and the tuning environment)
  FileUtils.cp(File.expand_path("../bin/commands/store.sh", __dir__), File.join(root, "bin/commands/store.sh"))
  File.write(File.join(root, "languages/tungsten/tungsten.lex64"), "fixture table\n")
  File.write(File.join(root, "VERSION"), "2026.01.01\n")

  # One program plays the stage-0 VM, the stage-1 compiler it "compiles", and
  # the stage-2 compiler that one "compiles": each writes a copy of itself to
  # --out and a fixture module to TUNGSTEN_LL_PATH. FAKE_STAGE2_DRIFT=1 makes
  # the stage-2 module differ from stage 1's.
  stage_program = File.join(root, "implementations/c/fake-vm")
  write_tool(stage_program, <<~'RUBY')
    require "fileutils"
    require "json"
    exit 0 if ENV["TUNGSTEN_PREFLIGHT"]
    File.open(ENV.fetch("FAKE_STAGE_LOG"), "a") { |f| f.puts(JSON.generate(argv: ARGV)) }
    if (index = ARGV.index("--out"))
      output = ARGV.fetch(index + 1)
      FileUtils.mkdir_p(File.dirname(output))
      FileUtils.cp(__FILE__, output)
      FileUtils.chmod(0o755, output)
      ll = ENV["TUNGSTEN_LL_PATH"].to_s
      unless ll.empty?
        FileUtils.mkdir_p(File.dirname(ll))
        text = "; fixture module\n"
        text += "; stage 2 drift\n" if File.basename(ll).start_with?("stage2") && ENV["FAKE_STAGE2_DRIFT"] == "1"
        File.write(ll, text)
      end
    end
  RUBY
  File.write(File.join(root, "implementations/c/Makefile"), <<~MAKE)
    BUILD_DIR ?= build
    all:
    \tmkdir -p $(BUILD_DIR)
    \tcp fake-vm $(BUILD_DIR)/tungsten-c
    \tchmod 755 $(BUILD_DIR)/tungsten-c
  MAKE

  write_tool(File.join(tools, "cc"), <<~'RUBY')
    require "fileutils"
    if ARGV.include?("--version")
      puts "fixture clang 1"
    elsif (index = ARGV.index("-o"))
      output = ARGV.fetch(index + 1)
      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, "fixture object\n")
    end
  RUBY
  write_tool(File.join(tools, "ar"), <<~'RUBY')
    if ARGV.include?("--version")
      puts "fixture ar 1"
    else
      File.write(ARGV.fetch(1), "fixture archive\n")
    end
  RUBY
  %w[brew pkg-config].each { |tool| write_tool(File.join(tools, tool), "exit 1\n") }
  write_tool(File.join(tools, "codesign"), "exit 0\n")

  environment = {
    "TUNGSTEN_ROOT" => root, "TUNGSTEN_CONFIG" => File.join(directory, "no-config"),
    "TUNGSTEN_CC" => File.join(tools, "cc"), "TUNGSTEN_AR" => File.join(tools, "ar"),
    "TUNGSTEN_RANLIB" => "/usr/bin/true", "TUNGSTEN_BITS_CLANG_OPT" => "", "TUNGSTEN_CLANG_OPT" => "",
    "TUNGSTEN_BOOTSTRAP_HANDOFF" => "", "TUNGSTEN_BOOTSTRAP" => "", "TUNGSTEN_CPU" => "", "TUNGSTEN_COMPILER" => "",
    "TUNGSTEN_BUILD_MANIFEST" => "", "TUNGSTEN_C_FAST_PARSE" => "", "TUNGSTEN_LEX64_TABLE" => "",
    "HOME" => home, "TUNGSTEN_HOME" => File.join(home, ".tungsten"), "TUNGSTEN_BIN" => File.join(home, "bin"),
    "TUNGSTEN_BUILD_STORE" => store, "TUNGSTEN_CACHE_DIR" => "",
    "FAKE_STAGE_LOG" => log, "FAKE_STAGE2_DRIFT" => nil, "CI" => nil, "NO_COLOR" => "1", "MAKEFLAGS" => nil,
    "PATH" => tools + File::PATH_SEPARATOR + ENV.fetch("PATH")
  }
  installed = File.join(root, "bin/tungsten-compiler")
  profile = File.join(root, "build/compiler-build.profile")

  # Every scenario starts from a checkout with no compiler and an empty build
  # store, so "installed" always means "installed by this run".
  run = lambda do |arguments = [], overrides = {}|
    FileUtils.rm_rf([File.join(root, "build"), File.join(root, "implementations/c/build"), store])
    FileUtils.rm_f([installed, installed + ".sidemap", log])
    out, status = Open3.capture2e(environment.merge(overrides), driver, *arguments, chdir: root)
    records = File.exist?(log) ? File.readlines(log).map { |line| JSON.parse(line)["argv"] } : []
    [out, status, records]
  end
  drift = { "FAKE_STAGE2_DRIFT" => "1" }

  out, status, = run.call
  check.call("identical stages verify, install and exit 0",
             status.success? && out.include?("VERIFIED stage 1 .ll == stage 2 .ll") && out.include?("==> Done") &&
             File.executable?(installed) && File.read(profile).include?("verified=1"), out)

  out, status, = run.call([], "CI" => "true")
  check.call("identical stages pass under CI", status.success? && out.include?("VERIFIED") && File.executable?(installed), out)

  out, status, = run.call([], drift)
  check.call("a local mismatch warns, still installs stage 2 and exits 0",
             status.success? && out.include?("WARNING stage 1 and stage 2 .ll differ!") && !out.include?("VERIFIED") &&
             out.include?("==> Done") && File.executable?(installed) && File.read(profile).include?("verified=0"), out)

  %w[0 false].each do |value|
    out, status, = run.call([], drift.merge("CI" => value))
    check.call("CI=#{value} is not a CI run", status.success? && out.include?("WARNING") && File.executable?(installed), out)
  end

  strict = lambda do |name, arguments, overrides, absent|
    version_before = File.read(File.join(root, "VERSION"))
    out, status, records = run.call(arguments, drift.merge(overrides))
    later = records.any? { |argv| argv.include?("build-image") || argv.include?("--target") }
    check.call("a mismatch fails #{name}",
               status.exitstatus == 1 && out.include?("ERROR stage 1 and stage 2 .ll differ!") &&
               !out.include?("WARNING") && !out.include?("==> Done") && !out.include?(absent) &&
               !File.exist?(installed) && !File.exist?(profile) && !later &&
               File.read(File.join(root, "VERSION")) == version_before && !File.exist?(File.join(home, ".tungsten")),
               out + "\n" + records.inspect)
  end
  strict.call("under CI", [], { "CI" => "true" }, "==> Compiler images")
  strict.call("under CI=1", [], { "CI" => "1" }, "==> Compiler images")
  strict.call("with --strict", ["--strict"], {}, "==> Compiler images")
  strict.call("with --pgo", ["--pgo"], {}, "==> PGO")
  strict.call("with --target (a release artifact)", ["--target", "aarch64-linux-gnu"], {}, "==> Release artifacts")
  strict.call("with --portable (release artifacts)", ["--portable"], {}, "==> Release artifacts")
  strict.call("with --install", ["--install"], {}, "==> Install")

  out, status, = run.call(["--strict"], drift)
  check.call("the failure names both modules for diffing",
             out =~ %r{stage 1 \.ll: \h{64} +/\S+/ll/stage1-c\.ll} && out =~ %r{stage 2 \.ll: \h{64} +/\S+/ll/stage2-c\.ll}, out)

  # An artifact's images: one compile per kind, of that kind's source (by
  # relative path from the root, as every shared build is), with the
  # release/no-LTO image profile and the artifact's own target and CPU.
  image_compile = lambda do |records, release_dir, kind, source|
    output = File.join(release_dir, "compiler-images", "tungsten-#{kind}")
    argv = records.find { |candidate| candidate.include?(output) }
    return nil unless argv && File.executable?(output) && argv.include?("compile") &&
                      argv.include?(File.join("compiler", source))
    argv
  end
  images_for = lambda do |records, release_dir, target, cpu|
    [%w[repl repl.w], %w[metal tungsten_metal.w]].all? do |kind, source|
      argv = image_compile.call(records, release_dir, kind, source)
      argv && %w[--release --no-debug --no-lto].all? { |flag| argv.include?(flag) } &&
        argv.each_cons(2).include?(["--target", target]) &&
        (cpu ? argv.each_cons(2).include?(["--cpu", cpu]) : !argv.include?("--cpu"))
    end
  end

  out, status, records = run.call(["--target", "aarch64-linux-gnu"])
  release_dir = File.join(root, "build/releases/aarch64-linux-gnu/default")
  check.call("a --target artifact is built with its repl and metal images",
             status.success? && out.include?("VERIFIED") && out.include?("==> Release artifacts") &&
             File.executable?(File.join(release_dir, "tungsten-compiler")) &&
             images_for.call(records, release_dir, "aarch64-linux-gnu", nil), out + "\n" + records.inspect)

  out, status, records = run.call(["--target", "x86_64-unknown-linux-gnu", "--cpu", "x86-64-v3", "--sysroot", "/fixture/sysroot"])
  release_dir = File.join(root, "build/releases/x86_64-unknown-linux-gnu/x86-64-v3")
  sysroot = [%w[repl repl.w], %w[metal tungsten_metal.w]].all? do |kind, source|
    argv = image_compile.call(records, release_dir, kind, source)
    argv && argv.each_cons(2).include?(["--sysroot", "/fixture/sysroot"])
  end
  check.call("artifact images take the artifact's --cpu and --sysroot",
             status.success? && images_for.call(records, release_dir, "x86_64-unknown-linux-gnu", "x86-64-v3") && sysroot,
             out + "\n" + records.inspect)

  out, status, records = run.call(["--portable"])
  portable = Dir.glob(File.join(root, "build/releases/*/x86-64-v{2,3}")).sort
  check.call("--portable builds images for both x86-64 levels",
             status.success? && portable.size == 2 &&
             portable.all? { |dir| images_for.call(records, dir, File.basename(File.dirname(dir)), File.basename(dir)) },
             out + "\n" + records.inspect)
end

puts "self-host build contracts: #{passed} checks passed"

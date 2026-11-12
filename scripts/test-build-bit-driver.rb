#!/usr/bin/env ruby
# End-to-end build-driver contract: real compiled orchestration, isolated fake
# compiler/toolchain, no bootstrap or expensive native program compilation.
# Bit executables live in the build store (an isolated one here) under a
# fingerprint of their sources, compiler, runtime and flags; bin/<name> is a
# copy. The fake compiler reports no dependency list, so its entries are only
# ever reused at the location that built them.
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

driver = File.expand_path(ARGV.fetch(0))
raise "expected a compiled bin/commands/build.w driver" unless File.executable?(driver)

def write_tool(path, body)
  File.write(path, "#!#{RbConfig.ruby}\n" + body)
  FileUtils.chmod(0o755, path)
end

Dir.mktmpdir("tungsten-bit-driver-") do |directory|
  directory = File.realpath(directory)
  root = File.join(directory, "root")
  package = File.join(directory, "app")
  tools = File.join(directory, "tools")
  FileUtils.mkdir_p([File.join(root, "bin/commands"), File.join(root, "runtime"), File.join(root, "bits"), File.join(package, "lib"), tools])
  log = File.join(directory, "compiler.jsonl")
  store = File.join(directory, "store")
  File.write(File.join(root, "bin/commands/cache_gc.sh"), "exit 0\n")
  # the real location/key policy script (the driver asks it for the tuning environment)
  FileUtils.cp(File.expand_path("../bin/commands/store.sh", __dir__), File.join(root, "bin/commands/store.sh"))
  # the runtime source manifest and its reader: the driver selects the compiler's runtime sources from them
  %w[runtime/sources.txt runtime/sources.sh].each { |f| FileUtils.cp(File.expand_path("../#{f}", __dir__), File.join(root, f)) }
  File.write(File.join(package, "lib/main.w"), "<< 1\n")
  write_tool(File.join(root, "bin/tungsten-compiler"), <<~'RUBY')
    require "fileutils"
    require "json"
    if ARGV.include?("--version")
      puts "test compiler 1"
      exit
    end
    File.open(ENV.fetch("FAKE_BUILD_LOG"), "a") { |f| f.puts(JSON.generate(argv: ARGV, clang_opt: ENV["TUNGSTEN_CLANG_OPT"])) }
    output = ARGV.fetch(ARGV.index("--out") + 1)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, output)
  RUBY
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
    "TUNGSTEN_BUILD_STORE" => store, "TUNGSTEN_CACHE_DIR" => "",
    "TUNGSTEN_CC" => File.join(tools, "cc"), "TUNGSTEN_AR" => File.join(tools, "ar"),
    "TUNGSTEN_RANLIB" => "/usr/bin/true", "TUNGSTEN_BITS_CLANG_OPT" => "", "TUNGSTEN_CLANG_OPT" => "",
    "TUNGSTEN_BOOTSTRAP_HANDOFF" => "", "TUNGSTEN_CPU" => "", "TUNGSTEN_COMPILER" => "", "FAKE_BUILD_LOG" => log, "NO_COLOR" => "1",
    "PATH" => tools + File::PATH_SEPARATOR + ENV.fetch("PATH")
  }
  manifest = File.join(package, "Bitfile")
  write_manifest = lambda do |flags|
    File.write(manifest, %(executable "hot", source: "lib/main.w", profile: "release", native: true, cflags: "#{flags}"\nexecutable "ordinary", source: "lib/main.w"\n))
  end
  run = lambda do |arguments = [], overrides = {}, where = package|
    before = File.exist?(log) ? File.readlines(log).size : 0
    out, status = Open3.capture2e(environment.merge(overrides), driver, *arguments, chdir: where)
    raise "driver failed: #{arguments.inspect}\n#{out}" unless status.success?
    records = File.exist?(log) ? File.readlines(log).drop(before).map { |line| JSON.parse(line) } : []
    records.select { |entry| entry["argv"].include?(File.join(where, "lib/main.w")) }
  end
  hot = lambda do |records|
    records.find { |entry| entry["argv"].include?(File.join(package, "bin/hot")) } or raise "missing hot executable invocation"
  end
  write_manifest.call("-funroll-loops -O1")
  first = run.call
  entry = hot.call(first)
  raise "manifest native/release not used" unless entry["argv"].include?("--release") && entry["argv"].include?("--native") && !entry["argv"].include?("--cpu")
  raise "manifest cflags not used" unless Shellwords.split(entry["clang_opt"]) == %w[-O3 -funroll-loops -O1]
  ordinary = first.find { |item| item["argv"].include?(File.join(package, "bin/ordinary")) }
  raise "other executable defaults changed" unless ordinary && ordinary["clang_opt"] == "-O0" && !ordinary["argv"].include?("--release")
  raise "unchanged build missed cache" unless run.call.empty?
  # The executables are in the store, each beside the manifest of the sources
  # it was built from; the package's bin/ holds copies and their manifests.
  %w[hot ordinary].each do |name|
    entries = Dir.glob(File.join(store, "bits", "#{name}-*", "*.deps"))
    raise "#{name} is not in the build store" if entries.empty?
    deps = File.read(File.join(package, "bin", "#{name}.deps"))
    raise "bin/#{name}.deps is not the store manifest" unless entries.any? { |entry| File.read(entry) == deps }
    raise "the manifest does not list the entry source" unless deps.include?("lib/main.w")
  end
  raise "the project grew a cache of its own" if File.exist?(File.join(package, "build"))
  raise "the toolchain root grew a build/cache" if File.exist?(File.join(root, "build", "cache"))
  # A deleted executable comes back from the store without a compile ...
  FileUtils.rm_f(File.join(package, "bin/hot"))
  raise "a store hit recompiled" unless run.call.empty?
  raise "the store hit did not reinstall bin/hot" unless File.executable?(File.join(package, "bin/hot"))
  # ... an edited source does not match its manifest any more ...
  File.write(File.join(package, "lib/main.w"), "<< 2\n")
  raise "an edited source was served from the store" unless run.call.size == 2
  # ... and going back to the first contents is a hit again (two entries now).
  File.write(File.join(package, "lib/main.w"), "<< 1\n")
  raise "returning to stored contents recompiled" unless run.call.empty?
  # A compiler switch in the environment changes what is built, so it must
  # not be served the plain build, nor leave its own build under the plain key.
  raise "a build under TUNGSTEN_FREE=0 was served the plain executable" unless run.call([], "TUNGSTEN_FREE" => "0").size == 2
  raise "the TUNGSTEN_FREE=0 build missed its own cache" unless run.call([], "TUNGSTEN_FREE" => "0").empty?
  raise "the plain build was replaced by the TUNGSTEN_FREE=0 one" unless run.call.empty?
  # A second project with the same sources elsewhere: without a dependency
  # list from the compiler nothing proves the two read the same files, so it
  # builds its own.
  twin = File.join(directory, "twin")
  FileUtils.mkdir_p(File.join(twin, "lib"))
  FileUtils.cp(File.join(package, "lib/main.w"), File.join(twin, "lib/main.w"))
  FileUtils.cp(manifest, File.join(twin, "Bitfile"))
  raise "a project elsewhere was handed another location's executable" unless run.call([], {}, twin).size == 2
  raise "the twin's own build missed its cache" unless run.call([], {}, twin).empty?
  # Two builders of one entry: the first complete entry stays, and the builder
  # that compiled it a second time installs that entry, so an executable and
  # its sidemap always come from one build. Simulated: the stored executable
  # differs from what this compiler writes (an equally valid build) and its
  # manifest is not there yet, so the next build misses and compiles. (The
  # TUNGSTEN_FREE=0 build above left a second key directory with the same
  # manifest; both are treated alike.)
  marker = "# the first builder's bytes\n"
  hot_deps = Dir.glob(File.join(store, "bits", "hot-*", "*.deps")).select { |path| File.read(path) == File.read(File.join(package, "bin/hot.deps")) }
  hot_stored = hot_deps.flat_map { |deps| Dir.glob(deps.delete_suffix(".deps") + "@*").reject { |path| File.basename(path).include?(".") } }
  raise "bin/hot has no store entry" if hot_stored.empty?
  hot_stored.each { |path| File.write(path, File.read(path) + marker) }
  FileUtils.rm_f(hot_deps)
  raise "a store entry without its manifest was not a miss" unless run.call.size == 1
  raise "a second publish replaced the complete store entry" unless hot_stored.all? { |path| File.read(path).end_with?(marker) }
  raise "the second builder did not install the kept entry" unless File.read(File.join(package, "bin/hot")).end_with?(marker)
  raise "the kept entry's manifest was not written" unless hot_deps.any? { |path| File.exist?(path) }
  raise "the kept entry missed afterwards" unless run.call.empty?
  raise "--force did not rebuild" unless run.call(["--force"]).size == 2
  raise "--force did not replace the store entry" if File.read(File.join(package, "bin/hot")).end_with?(marker) || hot_stored.all? { |path| File.read(path).end_with?(marker) }
  # Companion sources are not part of the base runtime archive. Their contents,
  # including Objective-C, still have to invalidate the outer executable stamp.
  bridge = File.join(root, "runtime", "graphics.m")
  File.write(bridge, "// native bridge one\n")
  raise "new native companion did not invalidate package cache" unless run.call.size == 2
  raise "unchanged native companion missed cache" unless run.call.empty?
  bridge_mtime = File.mtime(bridge)
  File.write(bridge, "// native bridge two\n")
  File.utime(bridge_mtime, bridge_mtime, bridge)
  raise "same-size/same-mtime Objective-C edit missed package cache" unless run.call.size == 2
  raise "rebuilt native companion did not cache" unless run.call.empty?
  write_manifest.call("-fno-omit-frame-pointer -O1")
  changed = hot.call(run.call)
  raise "changed manifest cflags missed cache invalidation" unless changed["clang_opt"].include?("-fno-omit-frame-pointer")
  entry = hot.call(run.call(["--debug"]))
  raise "explicit debug optimization lost" unless Shellwords.split(entry["clang_opt"]) == %w[-O0 -fno-omit-frame-pointer] && entry["argv"].include?("--debug") && !entry["argv"].include?("--release")
  entry = hot.call(run.call(["--release", "--cpu", "generic"]))
  raise "explicit release/CPU lost" unless Shellwords.split(entry["clang_opt"]) == %w[-O3 -fno-omit-frame-pointer] && entry["argv"].include?("generic") && !entry["argv"].include?("--native")
  entry = hot.call(run.call([], "TUNGSTEN_BITS_CLANG_OPT" => "-O2 -g"))
  raise "environment override lost" unless entry["clang_opt"] == "-O2 -g"
  %w[--portable --target].each do |mode|
    args = mode == "--portable" ? [mode] : [mode, "aarch64-linux-gnu"]
    entry = hot.call(run.call(args))
    raise "manifest native leaked into #{mode}" if entry["argv"].include?("--native")
  end
  puts "PASS actual build driver: scoped defaults, flags, explicit overrides, target/portable suppression, and cache hits/invalidation"
end

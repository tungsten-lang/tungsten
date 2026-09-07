#!/usr/bin/env ruby
# End-to-end build-driver contract: real compiled orchestration, isolated fake
# compiler/toolchain, no bootstrap or expensive native program compilation.
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
  File.write(File.join(root, "bin/commands/cache_gc.sh"), "exit 0\n")
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
    "TUNGSTEN_CC" => File.join(tools, "cc"), "TUNGSTEN_AR" => File.join(tools, "ar"),
    "TUNGSTEN_RANLIB" => "/usr/bin/true", "TUNGSTEN_BITS_CLANG_OPT" => "", "TUNGSTEN_CLANG_OPT" => "",
    "TUNGSTEN_BOOTSTRAP_HANDOFF" => "", "TUNGSTEN_CPU" => "", "TUNGSTEN_COMPILER" => "", "FAKE_BUILD_LOG" => log, "NO_COLOR" => "1",
    "PATH" => tools + File::PATH_SEPARATOR + ENV.fetch("PATH")
  }
  manifest = File.join(package, "Bitfile")
  write_manifest = lambda do |flags|
    File.write(manifest, %(executable "hot", source: "lib/main.w", profile: "release", native: true, cflags: "#{flags}"\nexecutable "ordinary", source: "lib/main.w"\n))
  end
  run = lambda do |arguments = [], overrides = {}|
    before = File.exist?(log) ? File.readlines(log).size : 0
    out, status = Open3.capture2e(environment.merge(overrides), driver, *arguments, chdir: package)
    raise "driver failed: #{arguments.inspect}\n#{out}" unless status.success?
    records = File.exist?(log) ? File.readlines(log).drop(before).map { |line| JSON.parse(line) } : []
    records.select { |entry| entry["argv"].include?(File.join(package, "lib/main.w")) }
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

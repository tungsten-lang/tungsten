#!/usr/bin/env ruby
# frozen_string_literal: true

# Focused real-driver coverage: package builds must compile manifest commands,
# not the side-effect-free library, and must never bootstrap the compiler.
require "fileutils"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
DRIVER = File.join(ROOT, "bin/tungsten")
COMPILER = File.join(ROOT, "bin/tungsten-compiler")

abort "Build the compiler before running this check" unless File.executable?(COMPILER)

def build_at(directory)
  out, err, status = Open3.capture3({"TUNGSTEN_BUILD_JOBS" => "1"}, DRIVER, "build", chdir: directory)
  raise "Package build failed:\n#{out}\n#{err}" unless status.success?
  raise "Package build bootstrapped the compiler:\n#{out}" if out.match?(/==> Stage [012]:/)
  out
end

def assert_output(path, expected)
  raise "Missing executable: #{path}" unless File.executable?(path)
  out, err, status = Open3.capture3(path)
  raise "Unexpected output from #{path}: #{out.inspect}, #{err}" unless status.success? && out == expected
end

compiler_stat = File.stat(COMPILER)
Dir.mktmpdir("tungsten-bit-entrypoints-") do |tmp|
  package = File.join(tmp, "tungsten-sample")
  FileUtils.mkdir_p(File.join(package, "lib"))
  FileUtils.mkdir_p(File.join(package, "commands", "nested"))
  File.write(File.join(package, "lib/sample.w"), "<< \"library only\"\n")
  File.write(File.join(package, "lib/helper.w"), "<< \"helper\"\n")
  File.write(File.join(package, "commands/nested/main.w"), "<< \"application\"\n")
  manifest = <<~BITFILE
    name "tungsten-sample"
    executable "sample", source: "commands/nested/main.w"
    executable "helper"
  BITFILE
  File.write(File.join(package, "Bitfile"), manifest)

  build_at(File.join(package, "commands/nested"))
  assert_output(File.join(package, "bin/sample"), "application\n")
  assert_output(File.join(package, "bin/helper"), "helper\n")

  binary_mtime = File.mtime(File.join(package, "bin/sample"))
  cached = build_at(package)
  raise "Repeated build did not hit the entry-point cache" unless cached.include?("skip") && File.mtime(File.join(package, "bin/sample")) == binary_mtime

  # A manifest-only source change must invalidate the cache, even though the
  # source tree and executable name did not change.
  File.write(File.join(package, "Bitfile"), manifest.sub("commands/nested/main.w", "lib/sample.w"))
  build_at(package)
  assert_output(File.join(package, "bin/sample"), "library only\n")

  # Old-style packages without executable declarations retain their lib entry.
  File.write(File.join(package, "Bitfile"), "name \"tungsten-sample\"\n")
  build_at(package)
  assert_output(File.join(package, "bin/sample"), "library only\n")
end

after = File.stat(COMPILER)
raise "Package build modified the installed compiler" unless [after.ino, after.mtime, after.size] == [compiler_stat.ino, compiler_stat.mtime, compiler_stat.size]

puts "package build entry points: ok"

#!/usr/bin/env ruby
# What `tungsten build` builds from the current directory (2026-11-04), through the real compiled build driver with an isolated
# fake compiler and toolchain (as test-build-bit-driver.rb):
#   - in the driver's own checkout: the self-host build (`--which` says "self"), unchanged;
#   - in another checkout of the Tungsten repo (known by its root markers, not its path): delegated to that checkout's own
#     bin/tungsten build, with the same arguments;
#   - anywhere else: the nearest Bitfile above the directory (a project or bit): its executables, and each `app` line as a
#     macOS bin/<Name>.app (Info.plist, icon, the executable in Contents/MacOS, signed);
#   - nowhere to build: a clear error naming what it looked for, exit 1.
# Usage: ruby scripts/test-build-targets.rb bin/commands/build   (the compiled driver; bin/tungsten build compiles it)
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

driver = File.expand_path(ARGV.fetch(0))
raise "expected a compiled bin/commands/build.w driver" unless File.executable?(driver)

def write_tool(path, body)
  File.write(path, "#!#{RbConfig.ruby}\n" + body)
  FileUtils.chmod(0o755, path)
end

def checkout(dir)
  %w[compiler/tungsten.w core/tungsten.w bin/commands/build.w].each do |marker|
    FileUtils.mkdir_p(File.dirname(File.join(dir, marker)))
    File.write(File.join(dir, marker), "# marker\n")
  end
end

passed = 0
check = lambda do |name, ok, detail = ""|
  raise "FAIL #{name}\n#{detail}" unless ok
  passed += 1
  puts "PASS #{name}"
end

Dir.mktmpdir("tungsten-build-targets-") do |directory|
  directory = File.realpath(directory)
  root = File.join(directory, "root")
  other = File.join(directory, "other-checkout")
  package = File.join(directory, "app")
  empty = File.join(directory, "empty")
  inner_bit = File.join(root, "bits", "tungsten-inner")
  tools = File.join(directory, "tools")
  FileUtils.mkdir_p([File.join(root, "bin/commands"), File.join(root, "runtime"), File.join(package, "lib"), File.join(package, "res"), File.join(package, "sub/deeper"), empty, File.join(inner_bit, "lib"), tools])
  checkout(root)
  checkout(other)
  File.write(File.join(root, "bin/commands/cache_gc.sh"), "exit 0\n")
  File.write(File.join(inner_bit, "Bitfile"), %(name "tungsten-inner"\n))
  File.write(File.join(package, "lib/main.w"), "<< 1\n")
  File.write(File.join(package, "Bitfile"), <<~BITFILE)
    name "demo"
    executable "demo", source: "lib/main.w"
    app "Demo", executable: "demo", id: "test.tungsten.demo", icon: "res/icon.png", documents: "demo", version: "1.2"
  BITFILE
  # a 64 x 64 PNG made by the system's own sips (from a 1 x 1 seed written as bytes)
  seed = ["89504e470d0a1a0a0000000d4948445200000001000000010806000000" \
          "1f15c4890000000d49444154789c63f8cfc0f01f0005000201a5ad6b7a0000000049454e44ae426082"].pack("H*")
  File.binwrite(File.join(directory, "seed.png"), seed)
  system("sips", "-z", "64", "64", File.join(directory, "seed.png"), "--out", File.join(package, "res/icon.png"), out: File::NULL, err: File::NULL)
  log = File.join(directory, "calls.log")
  write_tool(File.join(root, "bin/tungsten-compiler"), <<~'RUBY')
    require "fileutils"
    if ARGV.include?("--version")
      puts "test compiler 1"
      exit
    end
    output = ARGV.fetch(ARGV.index("--out") + 1)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, output)
  RUBY
  # the other checkout's own CLI records how it was called
  write_tool(File.join(other, "bin/tungsten"), <<~RUBY)
    File.open(#{log.inspect}, "a") { |f| f.puts(Dir.pwd + " " + ARGV.join(" ")) }
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
    "TUNGSTEN_BOOTSTRAP_HANDOFF" => "", "TUNGSTEN_CPU" => "", "TUNGSTEN_COMPILER" => "", "NO_COLOR" => "1",
    "PATH" => tools + File::PATH_SEPARATOR + ENV.fetch("PATH")
  }
  run = lambda do |dir, arguments = []|
    Open3.capture2e(environment, driver, *arguments, chdir: dir)
  end
  which = lambda do |dir|
    out, status = run.call(dir, ["--which"])
    [out.lines.last.to_s.strip, status.exitstatus]
  end

  out, code = which.call(root)
  check.call("the driver's own checkout is the self-host build", out == "self #{root}" && code == 0, out)
  out, code = which.call(File.join(root, "runtime"))
  check.call("a folder inside the checkout is still the self-host build", out == "self #{root}" && code == 0, out)
  out, code = which.call(inner_bit)
  check.call("a bit inside the checkout builds that bit (as before)", out == "bit #{inner_bit}" && code == 0, out)
  out, code = which.call(other)
  check.call("another checkout is recognised by its markers", out == "checkout #{other}" && code == 0, out)
  out, code = which.call(File.join(package, "sub/deeper"))
  check.call("anywhere else the nearest Bitfile above is the project", out == "bit #{package}" && code == 0, out)
  out, code = which.call(empty)
  check.call("nothing to build reports none", out == "none #{empty}" && code == 1, out)

  out, status = run.call(empty)
  check.call("nothing to build is an error", status.exitstatus == 1, out)
  check.call("the error says what it looked for", out.include?("nothing to build in #{empty}") && out.include?("Bitfile") && out.include?("compiler/tungsten.w"), out)

  out, status = run.call(other, ["--release", "--no-bits"])
  called = File.exist?(log) ? File.read(log).strip : ""
  check.call("another checkout builds itself through its own bin/tungsten", status.success? && called == "#{other} build --release --no-bits", out + "\n" + called)

  out, status = run.call(package)
  bundle = File.join(package, "bin/Demo.app/Contents")
  check.call("the project builds", status.success?, out)
  check.call("its executable is built", File.executable?(File.join(package, "bin/demo")), out)
  check.call("the app holds the executable", File.executable?(File.join(bundle, "MacOS/demo")), out)
  plist = File.exist?(File.join(bundle, "Info.plist")) ? File.read(File.join(bundle, "Info.plist")) : ""
  check.call("Info.plist names the executable and id", plist.include?("<key>CFBundleExecutable</key><string>demo</string>") && plist.include?("<string>test.tungsten.demo</string>"), plist)
  check.call("Info.plist carries the version, Retina and the document type", plist.include?("<string>1.2</string>") && plist.include?("NSHighResolutionCapable") && plist.include?("<string>demo</string></array>"), plist)
  check.call("the icon is made", File.size?(File.join(bundle, "Resources/Demo.icns")).to_i > 0 && plist.include?("<key>CFBundleIconFile</key><string>Demo</string>"), out)
  check.call("plutil reads the Info.plist", system("plutil", "-lint", "-s", File.join(bundle, "Info.plist")), plist)
end
puts "build targets: #{passed} passed"

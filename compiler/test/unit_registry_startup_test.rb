# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

root = File.expand_path("../..", __dir__)
Dir.mktmpdir("tungsten-unit-startup") do |tmp|
  install = File.join(tmp, "install")
  cwd = File.join(tmp, "project")
  explicit_root = File.join(tmp, "root")
  [install, cwd, explicit_root].each { |dir| FileUtils.mkdir_p(File.join(dir, "data")) }
  # LexChar flags are a separate external lexer dependency. Supply them in
  # cwd while varying only unit-registry discovery in these tests.
  FileUtils.ln_s(File.join(root, "languages"), File.join(cwd, "languages"))
  FileUtils.mkdir_p(File.join(install, "bin"))
  binary = File.join(install, "bin", "probe")
  out, err, status = Open3.capture3({"TUNGSTEN_UNIT_NAMES" => nil}, File.join(root, "bin/tungsten"),
    "compile", "--no-lto", File.join(__dir__, "unit_registry_loader.w"), "--out", binary, chdir: root)
  abort out + err unless status.success?
  good = "startup_probe\nm\nµm\n"
  installed = File.join(install, "data/unit_names.txt")
  rooted = File.join(explicit_root, "data/unit_names.txt")
  override = File.join(tmp, "override.txt")
  File.write(File.join(cwd, "data/unit_names.txt"), "bad\nbad\n")
  cases = [
    ["executable beats cwd", nil, nil, installed, good, nil],
    ["root beats executable", explicit_root, nil, rooted, good, nil],
    ["explicit file beats root", "/missing-root", override, override, good, nil],
    ["CRLF and no final newline", nil, override, override, "startup_probe\r\nµm\r\nm", nil],
    ["duplicate", nil, override, override, "m\nm\n", ":2: duplicate unit name m"],
    ["whitespace", nil, override, override, " m\n", ":1: leading or trailing whitespace"],
    ["control", nil, override, override, "m\tx\n", ":1: control character"],
    ["reserved keyword", nil, override, override, "in\n", ":1: reserved unit spelling in"],
    ["reserved percent", nil, override, override, "%\n", ":1: reserved unit spelling %"],
    ["empty", nil, override, override, "\n", ":1: unit-name registry is empty"],
    ["long name", nil, override, override, "x" * 1025, ":1: unit name exceeds"],
    ["large file", nil, override, override, "x" * 1_048_577, ":1: unit-name registry exceeds"],
    ["invalid UTF-8", nil, override, override, "\xff".b, "must be valid UTF-8"],
    ["missing explicit path", nil, File.join(tmp, "missing"), nil, nil, "missing unit-name registry"],
    ["missing explicit root", "/missing-unit-root", nil, nil, nil, "missing unit-name registry /missing-unit-root"],
  ]
  cases.each do |label, env_root, env_file, path, content, error|
    File.write(installed, "bad\nbad\n") unless path == installed
    File.binwrite(path, content) if path
    out, err, status = Open3.capture3({"TUNGSTEN_ROOT" => env_root, "TUNGSTEN_UNIT_NAMES" => env_file}, binary, chdir: cwd)
    passed = error ? !status.success? && (out + err).include?(error) : status.success? && out.include?("unit registry snapshot: PASS")
    abort "FAIL #{label}\n#{out}#{err}" unless passed
    puts "PASS #{label}"
  end
end

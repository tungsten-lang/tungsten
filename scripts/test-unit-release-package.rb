# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

root = File.expand_path("..", __dir__)
label = "unit-registry-test"
version = File.read(File.join(root, "VERSION")).strip
package = "tungsten-#{version}-#{label}"
required = %w[VERSION bin/tungsten bin/tungsten-compiler core/tungsten.w
              data/units.tsv data/unit_names.txt data/unit_registry.json
              data/unit_metadata.tsv data/substance_densities.json doc/CORE.md runtime/runtime.c
              languages/tungsten/tungsten.lex64]
Dir.mktmpdir("tungsten-release-unit-test") do |tmp|
  package_root = File.join(tmp, package)
  required.each do |path|
    target = File.join(package_root, path)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(root, path), target, preserve: true)
  end
  archive = File.join(tmp, package + ".tar.gz")
  # A complete extracted package must lex and display external unit history
  # without a root environment or repository access through its invocation cwd.
  [nil, "data/unit_names.txt", "data/unit_registry.json", "data/unit_metadata.tsv"].each do |missing|
    FileUtils.rm(File.join(package_root, missing)) if missing
    out, err, status = Open3.capture3("tar", "-czf", archive, "-C", tmp, package)
    abort out + err unless status.success?
    out, err, status = Open3.capture3("bash", File.join(root, "scripts/validate-release-package.sh"), archive, label)
    if missing
      abort "missing file accepted: #{missing}\n#{out}#{err}" if status.success? || !(out + err).include?("missing #{missing}")
      FileUtils.cp(File.join(root, missing), File.join(package_root, missing))
    else
      abort out + err unless status.success?
    end
    puts "PASS release registry #{missing || 'relocation, lexing, and external history'}"
  end
end

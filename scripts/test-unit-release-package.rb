# frozen_string_literal: true

# The release package, end to end, from this checkout: scripts/package-release.sh
# builds it from HEAD's tree plus the installed compiler and its compiler
# images, and scripts/validate-release-package.sh must accept it in full mode
# (structure, unit registry lexing, the REPL image's external unit history,
# the Metal image starting, and a program compiled, linked and run by the
# packaged launcher), then reject it when a required file is taken away.
#
# The images stand in for a release artifact's: here they are the host's own
# (build/compiler-images), which is fine for a package that never
# leaves this machine.
#
# Needs a built compiler and images (bin/tungsten build) and a committed tree:
# the package is cut from HEAD, not from the working files.

require "fileutils"
require "open3"
require "shellwords"
require "tmpdir"

root = File.expand_path("..", __dir__)
label = "unit-registry-test"
version = File.read(File.join(root, "VERSION")).strip
package = "tungsten-#{version}-#{label}"
kinds = %w[repl metal]
host_images = File.join(root, "build/compiler-images")
compiler = File.join(root, "bin/tungsten-compiler")
abort "no compiler at #{compiler}: run bin/tungsten build" unless File.executable?(compiler)
kinds.each do |kind|
  image = File.join(host_images, "tungsten-#{kind}")
  abort "no #{kind} compiler image at #{image}: run bin/tungsten build" unless File.executable?(image)
end

Dir.mktmpdir("tungsten-release-unit-test") do |tmp|
  # One release artifact directory, as `tungsten build --target` lays it out.
  artifact = File.join(tmp, "artifact")
  FileUtils.mkdir_p(File.join(artifact, "compiler-images"))
  FileUtils.cp(compiler, File.join(artifact, "tungsten-compiler"), preserve: true)
  package_script = File.join(root, "scripts/package-release.sh")
  packages = File.join(tmp, "packages")

  out, err, status = Open3.capture3("bash", package_script, File.join(artifact, "tungsten-compiler"), label, packages)
  abort "a compiler without its images was packaged\n#{out}#{err}" if status.success? || !(out + err).include?("compiler image is missing")
  puts "PASS release package refuses an artifact without compiler images"

  kinds.each do |kind|
    Dir.glob(File.join(host_images, "tungsten-#{kind}{,.sidemap}")).each do |path|
      FileUtils.cp(path, File.join(artifact, "compiler-images", File.basename(path)), preserve: true)
    end
  end
  out, err, status = Open3.capture3("bash", package_script, File.join(artifact, "tungsten-compiler"), label, packages)
  abort out + err unless status.success?
  archive = File.join(packages, package + ".tar.gz")
  abort "package-release.sh did not write #{archive}\n#{out}#{err}" unless File.file?(archive)

  out, err, status = Open3.capture3("tar", "-xzf", archive, "-C", tmp)
  abort out + err unless status.success?
  package_root = File.join(tmp, package)
  repacked = File.join(tmp, package + ".tar.gz")

  # A complete extracted package must lex and display external unit history
  # without a root environment or repository access through its invocation
  # cwd, start both images, and build a program that runs. Each required file
  # is then removed in turn; the validator must name it.
  [nil, "data/unit_names.txt", "data/unit_registry.json", "data/unit_metadata.tsv",
   "build/compiler-images/tungsten-repl", "build/compiler-images/tungsten-metal"].each do |missing|
    saved = File.join(tmp, "saved")
    FileUtils.mv(File.join(package_root, missing), saved) if missing
    # The tree is repacked once per case; the fastest gzip level keeps that cheap.
    repack = "tar -cf - -C #{tmp.shellescape} #{package.shellescape} | gzip -1 > #{repacked.shellescape}"
    out, err, status = Open3.capture3("bash", "-o", "pipefail", "-c", repack)
    abort out + err unless status.success?
    out, err, status = Open3.capture3("bash", File.join(root, "scripts/validate-release-package.sh"), repacked, label)
    if missing
      abort "missing file accepted: #{missing}\n#{out}#{err}" if status.success? || !(out + err).include?("missing #{missing}")
      FileUtils.mv(saved, File.join(package_root, missing))
    else
      abort out + err unless status.success?
    end
    puts "PASS release registry #{missing || 'relocation, lexing, external history, images, and a linked program'}"
  end
end

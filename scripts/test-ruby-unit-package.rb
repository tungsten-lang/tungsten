# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

root = File.expand_path("..", __dir__)
ruby_root = File.join(root, "implementations/ruby")
out, err, status = Open3.capture3({"BUNDLE_GEMFILE" => File.join(ruby_root, "Gemfile")},
  "bundle", "exec", "rake", "build", chdir: ruby_root)
abort out + err unless status.success?
version = File.read(File.join(root, "VERSION")).strip
package = File.join(ruby_root, "pkg/tungsten-lang-#{version}.gem")
metadata_count = File.foreach(File.join(root, "data/unit_metadata.tsv")).count { |line| !line.strip.empty? && !line.start_with?("#") }
Dir.mktmpdir("tungsten-ruby-unit-package") do |tmp|
  Gem::Package.new(package).extract_files(tmp)
  %w[unit_registry.json unit_metadata.tsv substance_densities.json].each do |name|
    unless File.binread(File.join(root, "data", name)) == File.binread(File.join(tmp, "data", name))
      abort "packaged #{name} differs from the authoritative data"
    end
  end
  unless File.binread(File.join(root, "scripts/lib/unit_registry.rb")) ==
         File.binread(File.join(tmp, "lib/tungsten/generated_unit_registry.rb"))
    abort "packaged reader differs from the shared reader"
  end
  probe = <<~RUBY
    require "tungsten"
    raise "conversion changed" unless Tungsten.run("1 eV | J").value == Rational(1602176634, 10**28)
    raise "missing metadata" unless Tungsten::Units::UNIT_METADATA.size == #{metadata_count}
    raise "missing etymology" if Tungsten::Units::UNIT_METADATA.fetch("m").fetch(:etymology).empty?
    raise "missing history" if Tungsten::Units::UNIT_METADATA.fetch("m").fetch(:history).empty?
    raise "used checkout data" unless Tungsten::Units::REGISTRY_PATH.start_with?(Dir.pwd + "/")
    raise "missing packaged reader" unless $LOADED_FEATURES.any? { |f| f.end_with?("/generated_unit_registry.rb") }
    puts "standalone Ruby unit registry package: PASS"
  RUBY
  out, err, status = Open3.capture3({"RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil},
    RbConfig.ruby, "-I", File.join(tmp, "lib"), "-e", probe, chdir: tmp)
  abort out + err unless status.success?
  puts out
end

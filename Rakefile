require "colored"
require "bundler"
require_relative "lib/tungsten/external_dependencies"

ROOT = __dir__

def resolve_example_path(name)
  needle = name.to_s.strip
  raise ArgumentError, "usage: rake 'examples[99_bottles]'" if needle.empty?

  needle = needle.delete_suffix(".w")
  needle = needle.downcase.gsub(/[[:space:]-]+/, "_")

  candidates = Dir[
    File.join(ROOT, "doc", "examples", "**", "#{needle}.w"),
    File.join(ROOT, "doc", "rosetta_code", "**", "#{needle}.w")
  ].sort

  raise ArgumentError, "no example matched #{needle.inspect}" if candidates.empty?
  raise ArgumentError, "multiple examples matched #{needle.inspect}: #{candidates.map { |path| path.delete_prefix("#{ROOT}/") }.join(', ')}" if candidates.length > 1

  candidates.first.delete_prefix("#{ROOT}/")
end

def run_command(*cmd, chdir: nil, env: nil)
  ok =
    if chdir
      Dir.chdir(chdir) { env ? system(env, *cmd) : system(*cmd) }
    else
      env ? system(env, *cmd) : system(*cmd)
    end

  return if ok

  status = $?
  exit(status&.exitstatus || 1)
end

desc "Build compiler and run all test suites"
task default: %i[check:units check:layouts check:core_doc build:tungsten test:ruby test:wvalue test:parity]

desc "Linux leg: assert we're on Linux, then run the full default suite"
task :linux do
  abort "rake linux must run on a Linux host (this is #{RUBY_PLATFORM})" unless RUBY_PLATFORM.match?(/linux/)
  Rake::Task[:default].invoke
end

namespace :build do
  desc "Build the Tungsten compiler"
  task :tungsten do
    Bundler.with_unbundled_env do
      run_command "bin/tungsten", "build"
    end
  end
end

namespace :check do
  desc "Verify generated unit lookup tables match data/units.tsv"
  task :units do
    run_command "ruby", File.join(ROOT, "scripts/gen_units.rb"), "--check"
  end

  desc "Verify Tungsten data layouts match backing C structs"
  task :layouts do
    run_command "ruby", File.join(ROOT, "scripts/check_layouts.rb")
  end

  desc "Verify doc/CORE.md is in sync with the core/tungsten.w autoload manifest"
  task :core_doc do
    run_command "ruby", File.join(ROOT, "scripts/gen_core_doc.rb"), "--check"
  end
end

namespace :doc do
  desc "Regenerate doc/CORE.md from the core/tungsten.w autoload manifest"
  task :core do
    run_command "ruby", File.join(ROOT, "scripts/gen_core_doc.rb")
  end
end

namespace :test do
  desc "Run implementations/ruby specs (RSpec)"
  task :ruby do
    Bundler.with_unbundled_env do
      run_command "bundle", "exec", "rake", "spec", chdir: File.join(ROOT, "implementations/ruby")
    end
  end

  desc "Run one embedded example expectation by relative path"
  task :example, [:path] do |_task, args|
    path = args[:path].to_s.strip
    raise ArgumentError, "usage: rake 'test:example[examples/rosetta_code/99_bottles.w]'" if path.empty?

    Bundler.with_unbundled_env do
      run_command(
        "bundle", "exec", "rspec",
        "--require", "./spec/spec_helper",
        "spec/examples_embedded_expectations_spec.rb",
        "--example", path,
        chdir: File.join(ROOT, "implementations/ruby")
      )
    end
  end

  desc "Run WValue C runtime tests"
  task :wvalue do
    run_command "make", "test_nanbox", chdir: File.join(ROOT, "runtime")
    run_command "./test_nanbox", chdir: File.join(ROOT, "runtime")
  end

  desc "Run WIRE pipeline parity tests"
  task :parity do
    run_command "bash", File.join(ROOT, "compiler/test/parity_test.sh")
  end
end

desc "Download external dependencies declared in Bitfile into src/"
task :deps do
  manager = Tungsten::ExternalDependencies::Manager.new(root: ROOT)
  bitfile = File.join(ROOT, "Bitfile")
  plan = manager.plan_for_bitfile(bitfile)

  if plan.empty?
    puts "No external dependencies declared in Bitfile"
    next
  end

  puts "External dependencies from Bitfile:"
  plan.each do |item|
    roles = item.roles.map(&:to_s).sort.join(", ")
    puts "  #{item.label} (#{roles})"
  end
  puts

  manager.install_from_bitfile(bitfile)
end

desc "Run one embedded example expectation by example name, e.g. rake 'examples[99_bottles]'"
task :examples, [:name] do |_task, args|
  Rake::Task["test:example"].reenable
  Rake::Task["test:example"].invoke(resolve_example_path(args[:name]))
end

desc "Print list of items marked @todo"
task :notes do
  files = Dir['**/*.w*']
  notes = Hash.new { |hash,key| hash[key] = [] }

  max = 0

  files.each do |filename|
    File.open(filename) do |file|
      file.each do |line|
        if line.include?('@todo') || line.include?('TODO')
          notes[filename] << [file.lineno.to_s, line.strip]
          max = filename.length if filename.length > max
        end
      end
    end
  end

  notes.keys.sort.each do |file|
    puts
    puts file.yellow
    notes[file].each do |note|
      puts "%#{max}s:%-5s %s" % [file, note.first, note.last.gsub(/(@todo|TODO):?\s*/, '')]
    end
  end
end

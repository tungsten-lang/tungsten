require "colored"
require "bundler"
require "tmpdir"
require_relative "implementations/ruby/lib/tungsten/external_dependencies"

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
  raise ArgumentError, "multiple examples matched #{needle.inspect}: #{candidates.map { |path| path.delete_prefix("#{ROOT}/") }.join(', ')}" if candidates.size > 1

  candidates.first.delete_prefix("#{ROOT}/")
end

def run_command(*cmd, chdir: nil, env: nil)
  # `test:remaining` is a multitask. Dir.chdir is process-global, so using it
  # here lets concurrent tasks launch in one another's directories. Pass the
  # working directory to the child process atomically instead.
  options = chdir ? { chdir: chdir } : {}
  ok = env ? system(env, *cmd, **options) : system(*cmd, **options)

  return if ok

  status = $?
  exit(status&.exitstatus || 1)
end

desc "Build compiler and run all test suites"
task default: %i[check:all build:tungsten test:all spec:bits]

desc "Linux leg: assert we're on Linux, then run the full default suite"
task :linux do
  abort "rake linux must run on a Linux host (this is #{RUBY_PLATFORM})" unless RUBY_PLATFORM.match?(/linux/)
  Rake::Task[:default].invoke
end

namespace :build do
  desc "Build the Tungsten compiler"
  task tungsten: "check:dispatch_contracts" do
    # bootstrap works on a cold checkout (no compiler yet) and chains into
    # the full `tungsten build` pipeline; build alone requires a compiler.
    Bundler.with_unbundled_env do
      run_command "bin/tungsten", "bootstrap"
    end
  end
end

namespace :check do
  desc "Run generated-data and layout consistency checks in parallel"
  multitask all: %i[units layouts core_doc claims ast_schema dispatch_contracts]

  desc "Verify runtime-backed Core dispatch tables and compiler whitelists"
  task :dispatch_contracts do
    run_command "ruby", File.join(ROOT, "scripts/check-core-dispatch-contracts.rb")
  end

  desc "Verify generated slab-AST ABI tables match compiler/lib/ast.w"
  task :ast_schema do
    run_command "ruby", File.join(ROOT, "scripts/gen_ast_schema.rb"), "--check"
  end

  desc "Verify capability comments have not gone stale against the code"
  task :claims do
    run_command "ruby", File.join(ROOT, "scripts/check_claim_staleness.rb")
  end

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
  # Ruby compiler specs may create shared runtime archives on a cold checkout,
  # and the Tungsten specs warm the native dev archive. Run those first; only
  # then overlap the independent C-runtime and parity legs.
  desc "Run all default non-hardware test suites"
  task all: %i[ruby tungsten remaining]

  multitask remaining: %i[wvalue parity unit_registry_superset regex_lexer_parity c_vm ccall_contracts cli_contracts fmt http_tls lint repl_contracts bit_install cache_gc frontend_fuzz fast_parse_parity]

  desc "Verify generated C-call ABI contracts and the WIRE consistency guard"
  task :ccall_contracts do
    run_command "ruby", File.join(ROOT, "scripts/verify-ccall-contracts.rb")
    run_command File.join(ROOT, "bin/tungsten-compiler"), "run",
                File.join(ROOT, "compiler/test/wire_call_contracts.w")
    run_command File.join(ROOT, "bin/tungsten-compiler"), "run",
                File.join(ROOT, "compiler/test/content_hash_symbol_collision.w")
    run_command File.join(ROOT, "bin/tungsten-compiler"), "run",
                File.join(ROOT, "compiler/test/portable_asm_lowering.w")
    run_command File.join(ROOT, "bin/tungsten-compiler"), "run",
                File.join(ROOT, "compiler/test/static_method_registry_guard.w")
  end

  desc "Run CLI exit-status, check-mode, and explain contracts"
  task :cli_contracts do
    run_command "bash", File.join(ROOT, "scripts/test-cli-contracts.sh")
  end

  desc "Run self-hosted formatter snapshot, idempotence, and AST contracts"
  task :fmt do
    run_command "bash", File.join(ROOT, "scripts/test-fmt.sh")
  end

  desc "Run verified in-process HTTPS client contracts against local OpenSSL"
  task :http_tls do
    run_command "bash", File.join(ROOT, "scripts/test-http-tls.sh")
  end

  desc "Run self-hosted lint diagnostic and no-mutation contracts"
  task :lint do
    run_command "bash", File.join(ROOT, "scripts/test-lint.sh")
  end

  desc "Run self-hosted REPL launcher, history, and error-recovery contracts"
  task :repl_contracts do
    run_command "python3", File.join(ROOT, "spec/repl/core_pty_spec.py")
  end

  desc "Run Bit lockfile, checksum, and versioned-prefix install contracts"
  task :bit_install do
    run_command "python3", File.join(ROOT, "scripts/test-bit-install.py")
  end

  desc "Run build/cache garbage-collection retention contracts"
  task :cache_gc do
    run_command "bash", File.join(ROOT, "scripts/test-cache-gc.sh")
  end

  desc "Run the stage-0 C VM and bootstrap contract tests"
  task :c_vm do
    run_command "make", "test", chdir: File.join(ROOT, "implementations/c")
    run_command "ruby", File.join(ROOT, "scripts/test-build-stage1-cache-identity.rb")
  end

  desc "Differential-fuzz active lexer/parser/execution frontends"
  task frontend_fuzz: :c_vm do
    run_command "ruby", File.join(ROOT, "scripts/fuzz-frontends.rb")
  end

  desc "Prove the fast C parser emits canonical stage-1 IR"
  task :fast_parse_parity do
    run_command "bash", File.join(ROOT, "scripts/test-fast-parse-parity.sh")
  end

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

  desc "Exhaustively test the union of Ruby and compiled unit registries"
  task :unit_registry_superset do
    run_command "ruby", File.join(ROOT, "compiler/test/unit_registry_superset_test.rb")
  end

  desc "Compare the self-hosted RegexLexer with the production packed lexer"
  task :regex_lexer_parity do
    Dir.mktmpdir("tungsten-regex-lexer") do |dir|
      binary = File.join(dir, "lex-parity")
      run_command File.join(ROOT, "bin/tungsten"), "compile", "--no-lto",
                  File.join(ROOT, "compiler/lex_parity.w"), "--out", binary
      fixtures = Dir[File.join(ROOT, "compiler/test/fixtures/*.w")].sort
      run_command binary, *fixtures, env: { "TUNGSTEN_ROOT" => ROOT }
    end
  end

  desc "Run compiled/interpreted Tungsten specs, including core runtime specs"
  task :tungsten do
    run_command "make", "specs", env: { "RUN_CORE_SPECS" => "1" }
    run_command "bash", File.join(ROOT, "scripts/test-bit-count-intrinsics.sh")
    run_command "bash", File.join(ROOT, "scripts/test-carry-unroll.sh")
    run_command "bash", File.join(ROOT, "scripts/test-gpu-dialects.sh")
    run_command "bash", File.join(ROOT, "scripts/test-native-arm-crypto-features.sh")
    run_command "bash", File.join(ROOT, "scripts/test-raw-static-machine-return-wire.sh")
    run_command "bash", File.join(ROOT, "scripts/test-small-array-wide-element-boxing-wire.sh")
  end
end

namespace :spec do
  desc "Run every tracked bit spec, with specialized Wassat/Wrat execution"
  task :bits do
    run_command "bash", File.join(ROOT, "scripts/test-bit-specs.sh")
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
          max = filename.size if filename.size > max
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

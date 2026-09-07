#!/usr/bin/env ruby
# frozen_string_literal: true

# Guard the stage-cache source-input contract in bin/commands/build.w (the
# Tungsten build orchestrator): every source family that can affect a
# self-hosted compiler stage must be hashed into the stage identity, and the
# driver must key caches on ITSELF via its .w path (not the retired
# build.rb) so driver edits invalidate stages.

ROOT = File.expand_path("..", __dir__)

build_source = File.read(File.join(ROOT, "bin/commands/build.w")).gsub(/\s+/, " ")
bootstrap_source = File.read(File.join(ROOT, "bin/commands/bootstrap.sh")).gsub(/\s+/, " ")
release_workflow = File.read(File.join(ROOT, ".github/workflows/release.yml")).gsub(/\s+/, " ")

# The compiler-source families (mirrors the retired TungstenBuildCacheInputs):
# <compiler-dir>/tungsten.w, <compiler-dir>/lib, core, languages/tungsten/lexers.
required_uses = [
  'compiler_source_paths.push(compiler_dir_name + "/tungsten.w")',
  'compiler_source_paths.push(compiler_dir_name + "/lib")',
  'compiler_source_paths.push("core")',
  'compiler_source_paths.push("languages/tungsten/lexers")',
  # C-path stage identity hashes the compiler sources.
  "c_stage1_sources_sha = tree_sha(compiler_source_paths)",
  # Ruby-path stage inputs include the ruby implementation and the driver.
  'stage1_input_paths.push("implementations/ruby")',
  'stage1_input_paths.push("bin/commands/build.w")',
  'stage2_input_paths.push("bin/commands/build.w")',
  # Carry-loop tuning changes generated LLVM and must invalidate both direct
  # binary caches and compiler-stage caches.
  'env_or_empty("TUNGSTEN_CARRY_UNROLL")',
  # The opt-in PGO build uses a versioned, source-controlled corpus and avoids
  # target links while collecting compiler profiles.
  'PGO_TRAINING_VERSION = "compiler-pgo-v2"',
  'training_labels = ["self", "numeric", "string", "debug"]',
  'compiler/test/fixtures/pgo_protected_numeric.w',
  'compiler/test/fixtures/pgo_string_slice.w',
  'compiler/test/fixtures/locked_no_raise_rescue.w',
  'compile-batch --emit-ll --jobs 1 --batch-worker-dir',
  'reported = capture(shq(cc) + " --print-prog-name=llvm-profdata 2>/dev/null")',
  'llvm_profdata = pgo_profdata_tool()',
  'pgo_build && target_triple == "" && !portable_mode',
  'pgo_binary = run_pgo_post_step(stage2, "release " + artifact_target',
  '"TUNGSTEN_MARCH_ARGS=\'\' "',
  '-Werror=backend-plugin',
  'atomic_write("tungsten-compiler-pgo-v1\\nprofile=" + PGO_TRAINING_VERSION',
]
required_uses.each do |source|
  raise "build.w does not use compiler source contract: #{source}" unless build_source.include?(source)
end

unless bootstrap_source.include?('--pgo) PGO=1') && bootstrap_source.include?('build_flags+=(--pgo)')
  raise "bootstrap does not propagate --pgo to the self-hosted build"
end
unless release_workflow.include?('args=(--release --pgo --target "$TARGET")') &&
       release_workflow.include?('profile=compiler-pgo-v2') &&
       release_workflow.include?('compiler_sha256=$compiler_sha')
  raise "tagged release workflow does not build and verify PGO artifacts"
end

# tree_sha must keep the source-extension filter and the prune list — losing
# either silently narrows or bloats every stage cache key.
%w[*.rb *.w *.c *.h *.gemspec *.lock].each do |ext|
  raise "build.w tree_sha lost the #{ext} extension filter" unless build_source.include?("-name '#{ext}'")
end
%w[.git .bundle .cache node_modules tmp].each do |dir|
  raise "build.w tree_sha lost the #{dir} prune" unless build_source.include?("-name #{dir}")
end

puts "build stage1/stage2 source-cache contracts: ok"

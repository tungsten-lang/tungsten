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
  'compiler_source_paths.push(compiler_dir_name + "/tungsten_driver.w")',
  'compiler_source_paths.push(compiler_dir_name + "/lib")',
  # Stages are shared between checkouts through the build store, so they are
  # compiled by relative path with TUNGSTEN_ROOT unset (their bytes must not
  # name the checkout) and a stage that names it anyway is not published.
  'STAGE_ENTRY = compiler_dir_name + "/tungsten.w"',
  'STAGE_CD = "cd " + shq(ROOT) + " && env -u TUNGSTEN_ROOT " + STAGE_UNIT_NAMES',
  's1_cmd = STAGE_CD + s1_env + shq(c_interp_for_build) + " " + shq(STAGE_ENTRY) + " compile " + shq(STAGE_ENTRY)',
  's2_cmd = STAGE_CD + s2_env + shq(stage1) + " compile " + shq(STAGE_ENTRY)',
  'if names_this_checkout?(built_bin)',
  'c_stage1_cached = STAGE_STORE_DIR + "/c-vm-stage1-" + c_stage1_identity',
  'c_stage2_cached = STAGE_STORE_DIR + "/c-vm-stage2-" + c_stage2_identity',
  # The Ruby host compiles by absolute path: its stage keys carry the root.
  'env_or_empty("TUNGSTEN_CARRY_UNROLL") + ":" + ROOT).slice(0, 16)',
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

# bootstrap.sh builds stage 1 the same way (its .ll is compared with the
# stage 2 that build.w compiles), from the same store, over the same sources.
helpers_source = File.read(File.join(ROOT, "bin/commands/bootstrap_helpers.sh")).gsub(/\s+/, " ")
[
  'COMPILER_ENTRY="compiler/tungsten.w"',
  'env -u TUNGSTEN_ROOT TUNGSTEN_UNIT_NAMES="${TUNGSTEN_UNIT_NAMES:-$ROOT/data/unit_names.txt}" \\ TUNGSTEN_LL_PATH="$stage1_tmp.ll" \\ "$C_INTERP" "$COMPILER_ENTRY" compile "$COMPILER_ENTRY"',
  'CACHE="$STORE/stages"',
].each do |source|
  raise "bootstrap.sh lost the shared-store stage contract: #{source}" unless bootstrap_source.include?(source)
end
unless helpers_source.include?('tungsten_driver.w') && helpers_source.include?('data/units.tsv')
  raise "bootstrap stage-1 source inputs must hash the compiler driver and the unit data"
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

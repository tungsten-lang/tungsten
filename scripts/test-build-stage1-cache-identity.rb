#!/usr/bin/env ruby
# frozen_string_literal: true

# Guard the stage-cache source-input contract in bin/commands/build.w (the
# Tungsten build orchestrator): every source family that can affect a
# self-hosted compiler stage must be hashed into the stage identity, and the
# driver must key caches on ITSELF via its .w path (not the retired
# build.rb) so driver edits invalidate stages.

ROOT = File.expand_path("..", __dir__)

build_source = File.read(File.join(ROOT, "bin/commands/build.w")).gsub(/\s+/, " ")

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
]
required_uses.each do |source|
  raise "build.w does not use compiler source contract: #{source}" unless build_source.include?(source)
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

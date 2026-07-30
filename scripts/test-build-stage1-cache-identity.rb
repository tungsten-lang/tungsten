#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "bin/commands/build_cache_inputs")

SOURCE_EXTENSIONS = %w[.rb .w .c .h .gemspec .lock].freeze

def source_identity(root, paths)
  sha = Digest::SHA256.new
  paths.each do |path|
    full = File.join(root, path)
    files =
      if File.directory?(full)
        found = []
        Find.find(full) do |candidate|
          next unless File.file?(candidate)
          next unless SOURCE_EXTENSIONS.include?(File.extname(candidate))

          found << candidate
        end
        found.sort
      else
        [full]
      end

    files.each do |file|
      sha.update(file.delete_prefix("#{root}/"))
      sha.update("\0")
      sha.update(Digest::SHA256.file(file).hexdigest)
      sha.update("\0")
    end
  end
  sha.hexdigest
end

Dir.mktmpdir("tungsten-build-cache-identity.") do |tmp|
  paths = TungstenBuildCacheInputs.compiler_source_paths("compiler-next")
  expected = [
    "compiler-next/tungsten.w",
    "compiler-next/lib",
    "core",
    "languages/tungsten/lexers"
  ]
  raise "compiler source paths differ: #{paths.inspect}" unless paths == expected

  files = {
    "compiler-next/tungsten.w" => "compiler\n",
    "compiler-next/lib/lexer.w" => "lexer\n",
    "core/integer.w" => "integer\n",
    "languages/tungsten/lexers/regex_helpers.w" => "helpers\n"
  }
  files.each do |relative, contents|
    path = File.join(tmp, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  original = source_identity(tmp, paths)
  File.write(File.join(tmp, "core/integer.w"), "integer changed\n")
  after_core = source_identity(tmp, paths)
  raise "core edit did not invalidate compiler source identity" if original == after_core

  File.write(
    File.join(tmp, "languages/tungsten/lexers/regex_helpers.w"),
    "helpers changed\n"
  )
  after_lexer = source_identity(tmp, paths)
  if after_core == after_lexer
    raise "lexer-helper edit did not invalidate compiler source identity"
  end

  File.write(File.join(tmp, "core/notes.txt"), "not a build source\n")
  after_non_source = source_identity(tmp, paths)
  if after_lexer != after_non_source
    raise "non-source file unexpectedly invalidated compiler source identity"
  end
end

build_source =
  File.read(File.join(ROOT, "bin/commands/build.rb")).gsub(/\s+/, " ")
required_uses = [
  "TungstenBuildCacheInputs.compiler_source_paths(COMPILER_DIR_NAME)",
  "c_stage1_sources_sha = tree_sha(*compiler_source_paths)",
  "stage1_input_sha = tree_sha(\"implementations/ruby\", *compiler_source_paths,",
  "stage2_input_sha = tree_sha(*compiler_source_paths,"
]
required_uses.each do |source|
  raise "build.rb does not use compiler source contract: #{source}" unless build_source.include?(source)
end

puts "build stage1/stage2 source-cache contracts: ok"

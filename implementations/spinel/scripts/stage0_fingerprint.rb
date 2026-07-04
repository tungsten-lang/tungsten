#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "rbconfig"

SOURCE_EXTENSIONS = %w[.rb .w .c .h .gemspec .lock .a].freeze
SKIP_DIRS = %w[.git .bundle .cache node_modules tmp].freeze
MODE_KEYS = %w[
  SPINEL_STAGE0_FULL
  SPINEL_STAGE0_REAL_TOKEN
  SPINEL_STAGE0_REAL_LEXER
  SPINEL_STAGE0_REAL_PARSER
  SPINEL_STAGE0_FULL_REAL_PARSER
  SPINEL_STAGE0_REAL_ENV
  SPINEL_STAGE0_REAL_LOADER
  SPINEL_STAGE0_REAL_INTERPRETER
  SPINEL_STAGE0_FULL_RUBY_INTERPRETER
  SPINEL_STAGE0_NO_FULL_INTERPRETER_COMPAT
  TUNGSTEN_SPINEL_STAGE0_CLANG_OPT
  TUNGSTEN_SPINEL_STAGE0_NO_GC
  TUNGSTEN_SPINEL_STAGE0_GC_THRESHOLD
].freeze

root_arg = ARGV.shift
cache_arg = ARGV.shift
ruby_fp_path = ARGV.shift
abort "usage: stage0_fingerprint.rb ROOT CACHE RUBY_FP PATH..." unless root_arg && cache_arg && ruby_fp_path

root = File.expand_path(root_arg)
cache_path = File.expand_path(cache_arg)
ruby_fp_path = File.expand_path(ruby_fp_path)

$file_digest_cache =
  begin
    cache = File.file?(cache_path) ? Marshal.load(File.binread(cache_path)) : {}
    cache.is_a?(Hash) ? cache : {}
  rescue StandardError
    {}
  end
$file_digest_cache_dirty = false

def source_file?(path)
  SOURCE_EXTENSIONS.include?(File.extname(path)) || File.basename(path) == "spinel"
end

def skipped_dir?(path)
  SKIP_DIRS.include?(File.basename(path))
end

def relative_path(root, path)
  File.expand_path(path).delete_prefix("#{root}/")
end

def file_digest(path)
  full = File.expand_path(path)
  return "missing:#{path}" unless File.file?(full)

  stat = File.stat(full)
  sig = [stat.size, stat.mtime.to_i, stat.mtime.nsec]
  entry = $file_digest_cache[full]
  if entry && entry[0] == sig[0] && entry[1] == sig[1] && entry[2] == sig[2]
    return entry[3]
  end

  digest = Digest::SHA256.file(full).hexdigest
  $file_digest_cache[full] = [sig[0], sig[1], sig[2], digest]
  $file_digest_cache_dirty = true
  digest
end

def tree_digest(root, paths)
  sha = Digest::SHA256.new
  paths.each do |path|
    full = path.start_with?("/") ? path : File.join(root, path)
    if File.directory?(full)
      Find.find(full) do |file|
        if File.directory?(file)
          Find.prune if skipped_dir?(file)
          next
        end
        next unless File.file?(file)
        next unless source_file?(file)

        sha.update(relative_path(root, file))
        sha.update("\0")
        sha.update(file_digest(file))
        sha.update("\0")
      end
    elsif File.file?(full)
      sha.update(relative_path(root, full))
      sha.update("\0")
      sha.update(file_digest(full))
      sha.update("\0")
    else
      sha.update(path)
      sha.update("\0missing")
    end
  end
  sha.hexdigest
end

ruby = RbConfig.ruby
ruby_fp = +"path=#{ruby}\nversion=#{RUBY_DESCRIPTION}\n"
ruby_fp << "sha256=#{file_digest(ruby)}\n" if File.file?(ruby)

if !File.file?(ruby_fp_path) || File.binread(ruby_fp_path) != ruby_fp
  FileUtils.mkdir_p(File.dirname(ruby_fp_path))
  File.binwrite(ruby_fp_path, ruby_fp)
end

src_sha = tree_digest(root, ARGV)
input = +"#{ruby_fp}"
MODE_KEYS.each do |key|
  input << "#{key}=#{ENV.fetch(key, "")}\n"
end
input << "src=#{src_sha}\n"

if $file_digest_cache_dirty
  FileUtils.mkdir_p(File.dirname(cache_path))
  tmp = "#{cache_path}.#{$$}.tmp"
  File.binwrite(tmp, Marshal.dump($file_digest_cache))
  FileUtils.mv(tmp, cache_path)
end

puts Digest::SHA256.hexdigest(input)

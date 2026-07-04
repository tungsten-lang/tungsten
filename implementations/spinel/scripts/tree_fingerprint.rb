#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"

SOURCE_EXTENSIONS = %w[.rb .w .c .h .gemspec .lock .a].freeze
SKIP_DIRS = %w[.git .bundle .cache node_modules tmp].freeze

root_arg = ARGV.shift
cache_arg = ARGV.shift
abort "usage: tree_fingerprint.rb ROOT CACHE PATH..." unless root_arg && cache_arg

root = File.expand_path(root_arg)
cache_path = File.expand_path(cache_arg)

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

def relative_path(root, path)
  full = File.expand_path(path)
  full.delete_prefix("#{root}/")
end

def skipped_dir?(path)
  SKIP_DIRS.include?(File.basename(path))
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

sha = Digest::SHA256.new
ARGV.each do |path|
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

if $file_digest_cache_dirty
  FileUtils.mkdir_p(File.dirname(cache_path))
  tmp = "#{cache_path}.#{$$}.tmp"
  File.binwrite(tmp, Marshal.dump($file_digest_cache))
  FileUtils.mv(tmp, cache_path)
end

puts sha.hexdigest

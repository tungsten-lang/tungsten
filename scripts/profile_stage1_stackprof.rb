#!/usr/bin/env ruby

require "fileutils"
require "stackprof"

require_relative "profile_stage1"

mode = ARGV.fetch(0) do
  warn "usage: ruby scripts/profile_stage1_stackprof.rb [lex|parse|interpret] OUTPUT_DUMP"
  exit 1
end
out_path = ARGV.fetch(1) do
  warn "usage: ruby scripts/profile_stage1_stackprof.rb [lex|parse|interpret] OUTPUT_DUMP"
  exit 1
end

FileUtils.mkdir_p(File.dirname(out_path))

StackProf.run(mode: :cpu, interval: 1000, out: out_path, raw: true) do
  Stage1Profile.run(mode)
end

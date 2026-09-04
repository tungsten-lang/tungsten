#!/usr/bin/env ruby
# frozen_string_literal: true

# Every diagnostic code the compiler can emit must have a lesson in
# doc/explain.md, and every lesson must name a code that still exists — the
# `explain:` footer on each error tells the user to run
# `tungsten explain CODE`, so a missing lesson is a dead end and a stale one
# is misinformation. Run by `rake check:explain` (part of `check:all`).
#
# Codes are E_<AREA>_<NAME> and LINT_<NAME> symbols or strings referenced in
# compiler/lib, compiler/tungsten.w, bin, and core. The leading word boundary
# matters: without it TUNGSTEN_CACHE_MAX_AGE_DAYS would read as E_MAX_AGE_DAYS.

ROOT = File.expand_path("..", __dir__)
REGISTRY = File.join(ROOT, "doc/explain.md")
SCAN_ROOTS = %w[compiler/lib compiler/tungsten.w bin core].freeze
CODE_RE = /(?<![A-Za-z0-9_])(?:E_[A-Z0-9]+_[A-Z0-9_]+|LINT_[A-Z0-9_]+)/
# Strings that match the shape but are not diagnostics the compiler raises.
IGNORED = %w[E_UNKNOWN E_VIEW_PARTIAL_ELEMENT].freeze

def source_files
  SCAN_ROOTS.flat_map do |rel|
    path = File.join(ROOT, rel)
    if File.directory?(path)
      Dir.glob(File.join(path, "**", "*.{w,rb,sh}"))
    else
      [path]
    end
  end
end

referenced = source_files.each_with_object({}) do |file, acc|
  File.foreach(file) do |line|
    line.scan(CODE_RE) { |code| (acc[code] ||= []) << File.basename(file) }
  end
end
referenced.reject! { |code, _| IGNORED.include?(code) }

lines = File.readlines(REGISTRY, chomp: true)
headings = lines.each_with_index.select { |l, _| l.start_with?("## ") }
lessons = headings.map { |l, _| l[3..] }

problems = []
lessons.each_with_index do |code, i|
  problems << "heading #{i + 1} has stray whitespace: #{code.inspect}" if code != code.strip
end
dupes = lessons.group_by(&:itself).select { |_, v| v.size > 1 }.keys
dupes.each { |code| problems << "duplicate lesson for #{code}" }

missing = referenced.keys.sort - lessons
stale = lessons.map(&:strip).uniq - referenced.keys
missing.each { |code| problems << "no lesson for #{code} (referenced in #{referenced[code].uniq.join(', ')})" }
stale.each { |code| problems << "stale lesson #{code}: no code with that name is referenced anywhere" }

# Each lesson body needs a Fix paragraph so the footer never points at a bare cause.
headings.each_with_index do |(heading, idx), i|
  stop = i + 1 < headings.size ? headings[i + 1][1] : lines.size
  body = lines[(idx + 1)...stop].join("\n")
  problems << "lesson #{heading[3..]} has no **Fix:** paragraph" unless body.include?("**Fix:**")
end

if problems.empty?
  puts "explain coverage OK: #{lessons.size} lessons cover #{referenced.size} diagnostic codes"
  exit 0
end

warn "doc/explain.md is out of sync with the diagnostic codes in the compiler:"
problems.each { |p| warn "  - #{p}" }
warn "Add a `## CODE` section with a **Fix:** paragraph for each missing code, and remove or rename stale ones."
exit 1

#!/usr/bin/env ruby
require_relative "bud_products"

# Materialize every positive formula from bench_public_parents.rb. Each result
# includes its checked leaves and substitution recipe; no archive is promoted.
B = MetaflipBudProducts
screen_root, closure_root, root = ARGV.map { |p| File.expand_path(p) }
raise "usage: materialize_public_parents.rb SCREEN_DIR CLOSURE_DIR NEW_OUTPUT_DIR" unless ARGV.length == 3
raise "output exists" if File.exist?(root)
pins = {}
read = lambda do |path|
  raw = File.binread(path)
  pins[File.realpath(path)] = Digest::SHA256.hexdigest(raw)
  raw
end
screen = JSON.parse(read.call(File.join(screen_root, "report.json")))
baseline = JSON.parse(read.call(File.join(closure_root, "report.json")))
[screen, baseline].each do |r|
  raise "incomplete source" unless r.fetch("complete") && r.fetch("field") == "GF(2)" && !r.fetch("record_claim")
end
raise "wrong baseline" unless screen.fetch("source_sha256").fetch(File.realpath(File.join(closure_root, "report.json"))) ==
  pins.fetch(File.realpath(File.join(closure_root, "report.json")))
parents = screen.fetch("parents").map do |row|
  e = row.fetch("snapshot")
  raw = read.call(File.join(screen_root, e.fetch("path")))
  raise "parent hash mismatch" unless Digest::SHA256.hexdigest(raw) == e.fetch("sha256")
  s = B::Scheme.new(e.fetch("shape"), raw)
  raise "parent identity mismatch" unless s.canonical_id == row.fetch("canonical_id")
  s
end
schemes = baseline.fetch("basis").each_with_index.map do |row, i|
  e = row.fetch("snapshot")
  raw = read.call(File.join(closure_root, e.fetch("path")))
  raise "basis hash mismatch" unless Digest::SHA256.hexdigest(raw) == e.fetch("sha256")
  s = B::Scheme.new(e.fetch("shape"), raw)
  raise "basis rank mismatch" unless s.rank == row.fetch("rank")
  if (i+1) % 100 == 0
    puts JSON.generate(basis_verified: i+1); $stdout.flush
  end
  s
end
library = B::Library.new(schemes, products: true)
FileUtils.mkdir_p(File.join(root, "tools"))
FileUtils.cp_r(File.join(screen_root, "parents"), root)
%w[materialize_public_parents.rb bud_products.rb verify_tensor.rb].each do |name|
  File.binwrite(File.join(root, "tools", name), read.call(File.join(__dir__, name)))
end
FileUtils.cp(File.join(screen_root, "report.json"), File.join(root, "screen.json"))
File.write(File.join(root, "baseline-grid.json"), JSON.generate(baseline.slice("complete", "field", "record_claim", "rows")) + "\n")
selected = screen.fetch("selected").select { |r| r.fetch("gain").positive? }.sort_by { |r| r.fetch("target") }
role = screen.fetch('options').fetch('candidate_role', 'public')
raise 'invalid candidate role' unless %w[public search].include?(role)
report = { schema: 1, kind: "#{role}-parent-composition", complete: false, field: "GF(2)", record_claim: false,
  redistribution_cleared: false, canonical_archive_changed: false, materialized_targets: 0,
  source_sha256: pins, outputs: [] }
save = lambda { File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n") }
save.call
selected.each do |row|
  groups = JSON.parse(JSON.generate(row.fetch("groups")), symbolize_names: true)
  raise "formula mismatch" unless B.score(groups, row.fetch("scale"), library) == row.fetch("formula")
  raise "baseline mismatch" unless library.rank(row.fetch("target")) == row.fetch("baseline")
  s, recipe = B.export(File.join(root, "outputs", row.fetch("target").join("x")),
    parents.fetch(row.fetch("parent")), row.fetch("scale"), groups, library)
  B.replay(recipe)
  result = row.slice("parent", "target", "scale", "formula", "baseline", "gain").merge(
    "rank"=>s.rank, "density"=>s.audit[:density], "recipe"=>recipe.delete_prefix(root+"/"))
  report[:outputs] << result
  report[:materialized_targets] += 1
  save.call
  puts JSON.generate(result); $stdout.flush
end
raise "source changed" unless pins.all? { |path, hash| Digest::SHA256.file(path).hexdigest == hash }
report[:complete] = true
save.call
puts JSON.generate(complete: true, materialized: report[:materialized_targets])

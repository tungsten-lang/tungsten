require "json"
require_relative "../../tools/verify_tensor"

root = __dir__
variants = %w[metaflip.V0 metaflip.legal-pair]
records = variants.map do |variant|
  rows = File.readlines(File.join(root, "#{variant}.jsonl")).map { |line| JSON.parse(line) }
  raise "incomplete arm" unless rows.size == 72
  rows.each do |r|
    raise "run error" unless r.fetch("status") == "ok"
    next unless r.fetch("hit")
    path = File.join(root, "schemes", variant, "#{r.fetch('task')}-#{r.fetch('seed')}.mfw")
    result = MetaflipTensorVerifier.verify(path, *r.fetch("task").split("x").map(&:to_i))
    raise "certificate or rank mismatch" unless result[:sha256] == r.fetch("scheme_sha256") && result[:rank] <= r.fetch("target_rank") && r.fetch("exact")
  end
  rows.group_by { |r| r.fetch("task") }
end

puts "shape\tbudget\tv0_hits\tpair_hits\tv0_ert\tpair_ert\tratio\tpair_faster_seeds\tv0_M_proposals_per_s\tpair_M_proposals_per_s\tv0_mean_proposals\tpair_mean_proposals"
records.first.each_key do |shape|
  arms = records.map { |r| r.fetch(shape).sort_by { |row| row.fetch("seed") } }
  identities = arms.map { |rows| rows.map { |r| r.values_at("seed", "target_rank", "budget_cpu_s", "start_sha256") } }
  raise "unpaired" unless identities.uniq.size == 1 && identities.first.uniq.size == 12
  hits = arms.map { |rows| rows.count { |r| r.fetch("hit") } }
  costs = arms.map { |rows| rows.map { |r| r.fetch(r.fetch("hit") ? "cpu_s_to_hit" : "budget_cpu_s") } }
  ert = costs.zip(hits).map { |c, h| c.sum.to_f / h }
  faster = costs.first.zip(costs.last).count { |v, p| p < v }
  rate = arms.map { |rows| rows.sum { |r| r.fetch("proposals_total") } / rows.sum { |r| r.fetch("cpu_s_total") } / 1e6 }
  proposals = arms.map { |rows| rows.sum { |r| r.fetch("proposals_total") } / rows.size.to_f }
  puts [shape, identities.first.first[2], *hits, *ert, ert.last/ert.first, faster, *rate, *proposals].join("\t")
end

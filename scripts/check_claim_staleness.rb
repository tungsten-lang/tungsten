#!/usr/bin/env ruby
# frozen_string_literal: true

# Comment-truth staleness gate (runs in check:all).
#
# Comments that describe capabilities rot silently: the SSA header claimed
# "no sqrt(2) trick" for weeks while ssa_shl_half shipped it, and
# w_value_free's header said hashes are never freed after the hash branch
# landed. A planning session took both claims at face value and scoped work
# around building things that already existed. Each entry pins one such
# claim to the code fact that would contradict it; add an entry whenever a
# doc-drift bug is fixed so it cannot regress.

ROOT = File.expand_path("..", __dir__)

# Each check: file, a code fact (regex) that must be true, and a stale
# claim (regex) that must NOT appear while the fact holds.
CHECKS = [
  {
    file: "runtime/runtime.c",
    fact: /^static void ssa_shl_half\(/,
    stale: /no (?:√2|sqrt\(?2\)?) trick/,
    message: "ssa_shl_half ships the sqrt(2) trick; the SSA header must not claim it is missing"
  },
  {
    file: "runtime/runtime.c",
    fact: /if \(w_is_hash\(v\)\) \{/,
    stale: /hashes, objects have more complex lifetimes and are not freed/,
    message: "w_value_free frees hashes now; its header must not say otherwise"
  },
  {
    file: "runtime/runtime.c",
    fact: /BN_BIGINT_HYBRID_QUANTUM % 8 == 0/,
    stale: /\(both must be powers of two\)/,
    message: "the hybrid quantum is any multiple of 8; the comment must not require a power of two"
  },
  {
    file: "bin/commands/bench-bignum.py",
    fact: /target_ms = 110\.0/,
    stale: /accurate.*20ms|target_ms = 20\.0/,
    message: "--accurate means >=110ms regions; a 20ms default resurrects the phantom-loss trap"
  },
  {
    file: "compiler/lib/emitter.w",
    fact: /w_bigint_add_mut/,
    stale: /declare_fn_attrs\("w_bigint_(?:add|sub|mul)_mut"[^\n]*memory\((?:read|none)\)/,
    message: "the mutate-if-unique entries WRITE their receiver's limbs; a readonly-family attribute licenses LLVM to CSE across mutations"
  }
].freeze

failures = []
CHECKS.each do |check|
  path = File.join(ROOT, check[:file])
  text = File.read(path)
  next unless text.match?(check[:fact])
  failures << "#{check[:file]}: #{check[:message]}" if text.match?(check[:stale])
end

if failures.empty?
  puts "claim staleness: #{CHECKS.size} pinned claims consistent"
else
  warn failures.join("\n")
  exit 1
end

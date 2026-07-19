# tungsten-spec smoke test — exercises the framework end to end.
# Contains DELIBERATE failures: expect exit code 1 and "2 failed".
#
# Run from the repo root:
#   bin/tungsten bits/tungsten-spec/spec/smoke_spec.w
# Expected: 8 examples: 6 passed, 2 failed (+ 1 pending), exit code 1.

use spec

$hook_log = []

# Raises on both engines (a bare undefined identifier only raises
# interpreted — compiled it resolves at build time or not at all).
-> smoke_boom
  <! "smoke boom"

describe "TungstenSpec smoke" ->
  describe "equality" ->
    it "passes on equal ints" ->
      expect(1 + 1).to eq(2)

    it "FAILS on unequal ints (deliberate)" ->
      expect(1 + 1).to eq(3)

    it "compares arrays structurally" ->
      expect([1, 2, 3]).to eq([1, 2, 3])

  describe "matchers" ->
    it "supports be_nil and not_to" ->
      expect(nil).to be_nil
      expect(5).not_to be_nil

    it "supports be_true and include" ->
      expect(2 > 1).to be_true
      expect([10, 20, 30]).to include(20)

    it "supports raise_error" ->
      expect(-> () smoke_boom).to raise_error

  describe "hooks" ->
    # NOTE: `before_each ->` (paren-less, zero-arg) parses as the
    # implicit-.each iteration syntax — zero-arg DSL calls that take a
    # block need explicit parens: `before_each() ->`.
    before_each() ->
      $hook_log.push("before")

    it "ran the before_each hook" ->
      expect($hook_log.size).to be_gt(0)

    it "FAILS with a runtime error (deliberate)" ->
      smoke_boom

  pending "pending example is counted, not run"

spec_summary

use spec
use ../lib/circuit_cone_search
use ../../tungsten-wrat/lib/wrat

use circuit_cone_fixtures

describe "Wassat comparison circuit decoder" ->
  it "infers a complete circuit and a single comparison" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    expect(d["recognized"]).to eq(true)
    expect(d["inputs"]).to eq(2)
    expect(d["gates"]).to eq(2)
    expect(d["comparisons"]).to eq([[7, 5, 6, 3, 4]])
    expect(d["ga"][3]).to eq(1)
    expect(d["gb"][3]).to eq(2)

  it "accepts literal permutations and a complete reduction tree" ->
    rows = cone_fixture_rows(3)
    rows = rows.map -> (c) c.reverse
    d = wassat_cone_decode(cone_fixture_flat(rows, 15))
    expect(d["recognized"]).to eq(true)
    expect(d["comparisons"].size).to eq(3)
    expect(d["tree_start"]).to eq(21)

  it "recognizes a satisfiable comparison without claiming a verdict" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows(1, 1), 7))
    expect(d["recognized"]).to eq(true)
    expect(d.has_key?("status")).to eq(false)
    expect(d["comparisons"][0][4]).to eq(1)

  it "rejects a missing implication in a complete gate" ->
    rows = cone_fixture_rows
    rows[0] = [-3, -1]
    expect(wassat_cone_decode(cone_fixture_flat(rows, 7))["recognized"]).to eq(false)

  it "rejects a malformed comparison minterm" ->
    rows = cone_fixture_rows
    rows[8] = [-6, 3]
    expect(wassat_cone_decode(cone_fixture_flat(rows, 7))["recognized"]).to eq(false)

  it "rejects a reduction that bypasses a comparison" ->
    rows = cone_fixture_rows(2)
    rows[16] = [11, -7, -7]
    expect(wassat_cone_decode(cone_fixture_flat(rows, 11))["recognized"]).to eq(false)

  it "rejects an extra assertion and a flipped final assertion" ->
    rows = cone_fixture_rows
    rows.push([1])
    expect(wassat_cone_decode(cone_fixture_flat(rows, 7))["recognized"]).to eq(false)
    rows = cone_fixture_rows
    rows[11] = [7]
    expect(wassat_cone_decode(cone_fixture_flat(rows, 7))["recognized"]).to eq(false)

  it "declines with a stopped flag when its deadline has passed" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7), 1)
    expect(d["recognized"]).to eq(false)
    expect(d["stopped"]).to eq(true)

describe "Wassat compact circuit cones" ->
  it "extracts just the queried nodes with compact numbering" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]
    ws = wassat_cone_workspace(d, 8)
    c = wassat_cone_compact(d, aliases, ws, 3, 4)
    expect(c["recognized"]).to eq(true)
    expect(c["nodes"]).to eq([1, 2, 3, 4])
    expect(c["clauses"].size).to eq(6)
    expect(c["left"]).to eq(3)
    expect(c["right"]).to eq(4)
    # Reuse must not keep stale marks from the previous query.
    c = wassat_cone_compact(d, aliases, ws, 1, -2)
    expect(c["nodes"]).to eq([1, 2])
    expect(c["clauses"].empty?).to eq(true)
    expect(c["right"]).to eq(-2)

  it "declines a capacity miss and a cyclic alias" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]
    c = wassat_cone_compact(d, aliases, wassat_cone_workspace(d, 2), 3, 4)
    expect(c["recognized"]).to eq(false)
    expect(c["stopped"]).to eq(true)
    aliases[3] = 4
    c = wassat_cone_compact(d, aliases, wassat_cone_workspace(d), 3, 4)
    expect(c["recognized"]).to eq(false)

  it "lifts both local failed cores into a checked original refutation" ->
    rows = cone_fixture_rows
    d = wassat_cone_decode(cone_fixture_flat(rows, 7))
    aliases = i64[8]
    r = wassat_cone_prove(d, aliases, wassat_cone_workspace(d), 3, 4, 100)
    expect(r["equivalent"]).to eq(true)
    expect(r["variables"]).to eq(4)
    expect(aliases[3]).to eq(0)
    text = "p cnf 7 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    prefix = r["drat"].join("\n") + "\n"
    check = wrat_verify(text, prefix)
    expect(check["verified"]).to eq(false)
    expect(check["reason"].include?("without deriving")).to eq(true)
    expect(check["steps"]).to eq(r["drat"].size)
    check = wrat_verify(text, prefix + "-5 0\n-6 0\n7 0\n0\n")
    expect(check["verified"]).to eq(true)

  it "keeps false and exhausted equivalence queries inconclusive" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows(1, 1), 7))
    aliases = i64[8]
    r = wassat_cone_prove(d, aliases, wassat_cone_workspace(d), 3, 1, 100)
    expect(r["equivalent"]).to eq(false)
    expect(r["drat"].empty?).to eq(true)
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    r = wassat_cone_prove(d, aliases, wassat_cone_workspace(d), 3, 4, 1)
    expect(r["conflicts"] <= 1).to eq(true)
    expect(r["equivalent"]).to eq(false)

  it "proves negated duplicate-input gates through a nontrivial variable map" ->
    rows = cone_fixture_rows
    rows[0] = [-3, -1]
    rows[1] = [-3, -1]
    rows[2] = [3, 1, 1]
    rows[3] = [-4, -1]
    rows[4] = [-4, -1]
    rows[5] = [4, 1, 1]
    d = wassat_cone_decode(cone_fixture_flat(rows, 7))
    expect(d["recognized"]).to eq(true)
    aliases = i64[8]
    ws = wassat_cone_workspace(d)
    expect(wassat_cone_compact(d, aliases, ws, 3, 4)["nodes"]).to eq([1, 3, 4])
    result = wassat_cone_prove(d, aliases, ws, 3, 4, 100)
    expect(result["equivalent"]).to eq(true)
    text = "p cnf 7 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    proof = result["drat"].join("\n") + "\n-5 0\n-6 0\n7 0\n0\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)

  it "stops an expired equivalence query before allocating a solver" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]
    result = wassat_cone_prove(d, aliases, wassat_cone_workspace(d), 3, 4, 100, 1)
    expect(result["equivalent"]).to eq(false)
    expect(result["stopped"]).to eq(true)
    expect(result["conflicts"]).to eq(0)

  it "composes signed aliases and rejects non-descending chains" ->
    aliases = i64[5]
    aliases[4] = -3
    aliases[3] = -1
    expect(wassat_cone_representative(4, aliases)).to eq(1)
    expect(wassat_cone_representative(-4, aliases)).to eq(-1)
    expect(wassat_cone_representative(2, aliases)).to eq(2)
    aliases[3] = 4
    expect(-> () wassat_cone_representative(4, aliases)).to raise_error

  it "bounds proof lifting and ignores deletion hints" ->
    expect(wassat_cone_lift_drat(["d 1 0", "-1 2 0"], [7, 9])).to eq(["-7 9 0"])
    expect(-> () wassat_cone_lift_drat(["3 0"], [7, 9])).to raise_error
    expect(-> () wassat_cone_lift_drat(["1"], [7, 9])).to raise_error

describe "Wassat internal circuit proposals" ->
  it "reproduces raw 64-bit patterns on both engines" ->
    state = i64[1]
    state[0] = 88172645463325252
    expect(wassat_cone_random(state)).to eq(8748534153485358512)
    expect(wassat_cone_random(state)).to eq(3040900993826735515)
    expect(wassat_cone_random(state)).to eq(3453997556048239312)
    expect(wassat_cone_random(state)).to eq(0 - 2015011221783540763)

  it "nominates matching functions without assigning aliases or verdicts" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    p = wassat_cone_sim_candidates(d, 2)
    expect(p["recognized"]).to eq(true)
    expect(p["count"]).to eq(1)
    expect(p["left"][0]).to eq(4)
    expect(p["right"][0]).to eq(3)
    expect(p.has_key?("status")).to eq(false)
    expect(p.has_key?("aliases")).to eq(false)
    sig = p["signatures"]
    j = 0
    while j < 2
      expect(sig[3 * 2 + j]).to eq(sig[1 * 2 + j] & sig[2 * 2 + j])
      j += 1

  it "matches complements to the same primary input class" ->
    rows = cone_fixture_rows
    rows[0] = [-3, -1]; rows[1] = [-3, -1]; rows[2] = [3, 1, 1]
    rows[3] = [-4, 1]; rows[4] = [-4, 1]; rows[5] = [4, -1, -1]
    d = wassat_cone_decode(cone_fixture_flat(rows, 7))
    p = wassat_cone_sim_candidates(d, 2)
    expect(p["count"]).to eq(2)
    expect(p["left"][0]).to eq(3)
    expect(p["right"][0]).to eq(-1)
    expect(p["left"][1]).to eq(4)
    expect(p["right"][1]).to eq(1)

  it "compares every signature after a hash collision" ->
    sig = i64[5]
    sig[1] = 2; sig[2] = 18; sig[3] = 2; sig[4] = 18
    left = i64[2]; right = i64[2]; stats = i64[4]
    expect(wassat_cone_nominate(sig, 2, 4, 1, i64[8], left, right, stats, 0)).to eq(1)
    expect(stats[0]).to eq(2)
    expect(right[0]).to eq(1)
    expect(right[1]).to eq(2)
    expect(stats[1] >= 3).to eq(true)

  it "rejects invalid sampling sizes and stops expired work" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    expect(wassat_cone_sim_candidates(d, 0)["recognized"]).to eq(false)
    expect(wassat_cone_sim_candidates(d, 33)["recognized"]).to eq(false)
    p = wassat_cone_sim_candidates(d, 2, 1)
    expect(p["recognized"]).to eq(false)
    expect(p["stopped"]).to eq(true)

describe "Wassat autonomous cone search" ->
  it "produces a checked original-CNF proof with no external hints" ->
    rows = cone_fixture_rows(3)
    f = cone_fixture_flat(rows, 15)
    result = wassat_cone_search(f, 1000)
    expect(result["status"]).to eq(-1)
    expect(result["unresolved"]).to eq(0)
    text = "p cnf 15 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    expect(wrat_verify(text, result["drat_text"])["verified"]).to eq(true)

  it "falls through on satisfiable, malformed and exhausted inputs" ->
    f = cone_fixture_flat(cone_fixture_rows(1, 1), 7)
    expect(wassat_cone_search(f, 1000)["status"]).to eq(0)
    rows = cone_fixture_rows
    rows[0] = [-3, -1]
    f = cone_fixture_flat(rows, 7)
    expect(wassat_cone_search(f, 1000)["recognized"]).to eq(false)
    f = cone_fixture_flat(cone_fixture_rows, 7)
    result = wassat_cone_search(f, 1)
    expect(result["status"]).to eq(0)
    expect(result["conflicts"] <= 1).to eq(true)
    expect(result["drat_text"]).to eq("")
    expect(wassat_cone_search(f, 0)["conflicts"]).to eq(0)

describe "Wassat counterexample refinement" ->
  it "retains distinct signed disproved pairs through collisions and a full cache" ->
    table = i64[8]
    expect(wassat_cone_known_difference(table, 62, -1)).to eq(false)
    known = wassat_cone_known_difference(table, 62, -1, true)
    expect(wassat_cone_known_difference(table, 62, -1)).to eq(true)
    expect(wassat_cone_known_difference(table, 62, 1)).to eq(false)
    expect(wassat_cone_known_difference(table, 63, -1)).to eq(false)
    known = wassat_cone_known_difference(table, 2000000, -1999999, true)
    expect(wassat_cone_known_difference(table, 2000000, -1999999)).to eq(true)
    i = 100
    while i < 132
      known = wassat_cone_known_difference(table, i, i - 1, true)
      i += 1
    expect(wassat_cone_known_difference(table, 62, -1)).to eq(true)
    expect(wassat_cone_known_difference(table, 1000, -1)).to eq(false)

  it "reserves signature words without changing the initial classes" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    a = wassat_cone_sim_candidates(d, 1)
    b = wassat_cone_sim_candidates(d, 2, 0, 1)
    expect(a["count"]).to eq(b["count"])
    v = 1
    while v <= 4
      expect(b["signatures"][v * 2]).to eq(a["signatures"][v])
      expect(b["signatures"][v * 2 + 1]).to eq(a["signatures"][v])
      v += 1

  it "extracts and validates a rare separating primary assignment" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_rare_rows, 66))
    expect(d["recognized"]).to eq(true)
    aliases = i64[67]
    q = wassat_cone_prove(d, aliases, wassat_cone_workspace(d), 62, -1, 100, 0, true)
    expect(q["equivalent"]).to eq(false)
    expect(q["counterexample"] != nil).to eq(true)
    expect(q["counterexample"].size).to eq(30)
    expect(q["counterexample"].include?(1)).to eq(false)
    p = wassat_cone_sim_candidates(d, 32, 0, 16)
    expect(wassat_cone_refine(d, p, [q["counterexample"]], [62], [-1], 16)).to eq(true)
    expect(p["refinements"]).to eq(1)
    i = 0
    bad = false
    while i < p["count"]
      bad = true if p["left"][i] == 62 && p["right"][i] == -1
      i += 1
    expect(bad).to eq(false)
    # An all-false assignment does not separate this pair.
    p = wassat_cone_sim_candidates(d, 32, 0, 16)
    expect(wassat_cone_refine(d, p, [[]], [62], [-1], 16)).to eq(false)
    expect(p["refinements"]).to eq(0)

  it "distinguishes an all-false counterexample from no counterexample" ->
    rows = cone_fixture_rows
    rows[0] = [-3, -1]; rows[1] = [-3, -1]; rows[2] = [3, 1, 1]
    d = wassat_cone_decode(cone_fixture_flat(rows, 7))
    q = wassat_cone_prove(d, i64[8], wassat_cone_workspace(d), 3, 1, 100, 0, true)
    expect(q["counterexample"] == nil).to eq(false)
    expect(q["counterexample"].empty?).to eq(true)

  it "keeps the biased SAT miter inconclusive after real refinement" ->
    f = cone_fixture_flat(cone_rare_rows, 66)
    r = wassat_cone_search(f, 10000, 0, true)
    expect(r["recognized"]).to eq(true)
    expect(r["status"]).to eq(0)
    expect(r["refinements"] > 0).to eq(true)
    expect(r["counterexamples"] > 0).to eq(true)
    expect(r["drat_text"]).to eq("")

  it "retains a checked full refutation in refinement mode" ->
    rows = cone_fixture_rows(3)
    r = wassat_cone_search(cone_fixture_flat(rows, 15), 1000, 0, true)
    text = "p cnf 15 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    expect(r["status"]).to eq(-1)
    expect(wrat_verify(text, r["drat_text"])["verified"]).to eq(true)

describe "Wassat resumable cone search" ->
  it "preserves the exact checked proof across one-query round slices" ->
    rows = cone_fixture_rows(3)
    f = cone_fixture_flat(rows, 15)
    direct = wassat_cone_search(f, 1000)
    checkpoint = wassat_cone_checkpoint(f, 1000)
    turns = 0
    while !checkpoint["finished"] && turns < 100
      result = wassat_cone_resume(checkpoint, nil, 1)
      turns += 1
    expect(checkpoint["finished"]).to eq(true)
    expect(turns > 1).to eq(true)
    expect(result["status"]).to eq(-1)
    expect(result["drat_text"]).to eq(direct["drat_text"])
    expect(result["conflicts"]).to eq(direct["conflicts"])

  it "finishes exhausted and unsupported checkpoints without inventing proofs" ->
    f = cone_fixture_flat(cone_fixture_rows(1, 1), 7)
    checkpoint = wassat_cone_checkpoint(f, 1)
    result = wassat_cone_resume(checkpoint)
    expect(checkpoint["finished"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["conflicts"] <= 1).to eq(true)
    expect(result["drat_text"]).to eq("")
    f["flat_ncl"] = 0
    checkpoint = wassat_cone_checkpoint(f, 1000)
    result = wassat_cone_resume(checkpoint)
    expect(checkpoint["finished"]).to eq(true)
    expect(result["recognized"]).to eq(false)

describe "Wassat cone query diagnostics" ->
  it "preserves a checked proof and records immutable stage snapshots" ->
    f = cone_fixture_flat(cone_fixture_rows(3), 15)
    expected = wassat_cone_search(f, 1000)
    checkpoint = wassat_cone_checkpoint(f, 1000)
    checkpoint["profile_queries"] = true
    result = wassat_cone_resume(checkpoint)
    expect(result["drat_text"]).to eq(expected["drat_text"])
    profile = checkpoint["workspace"]["query_profile"]
    expect(profile[0]).to eq(result["queries"])
    expect(profile[1] + profile[2] + profile[3] + profile[11] + profile[12] + profile[13]).to eq(profile[0])
    recorded = result["stages"][0]["query_profile"][0]
    profile[0] += 100
    expect(result["stages"][0]["query_profile"][0]).to eq(recorded)

  it "distinguishes capacity declines, deadlines, bad aliases and SAT separations" ->
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]
    work = wassat_cone_workspace(d, 2)
    profile = i64[24]; work["query_profile"] = profile
    result = wassat_cone_prove(d, aliases, work, 4, 3, 100)
    expect(result["capacity"]).to eq(true)
    expect(profile[1]).to eq(1)
    expect(profile[2]).to eq(0)
    work = wassat_cone_workspace(d)
    work["query_profile"] = profile
    result = wassat_cone_prove(d, aliases, work, 4, 3, 100, clock_ms() - 1)
    expect(profile[2]).to eq(1)
    aliases[4] = 4
    result = wassat_cone_prove(d, aliases, work, 4, 3, 100)
    expect(profile[3]).to eq(1)
    aliases[4] = 0
    result = wassat_cone_prove(d, aliases, work, 4, 1, 100)
    expect(result["separated"]).to eq(true)
    expect(profile[12]).to eq(1)
    expect(profile[0]).to eq(4)

describe "Wassat certified cone constants" ->
  it "lifts false and true constant proofs into an original refutation" ->
    rows = cone_fixture_rows(1, -4)
    rows[0] = [-3, 1]; rows[1] = [-3, -1]; rows[2] = [3, -1, 1]
    rows[3] = [-4, -3]; rows[4] = [-4, -3]; rows[5] = [4, 3, 3]
    decoded = wassat_cone_decode(cone_fixture_flat(rows, 7))
    expect(decoded["recognized"]).to eq(true)
    aliases = i64[8]
    workspace = wassat_cone_workspace(decoded)
    constants = i64[8]; workspace["constants"] = constants
    first = wassat_cone_prove_constant(decoded, aliases, workspace, 3, -1, 100)
    expect(first["equivalent"]).to eq(true)
    expect(constants[3]).to eq(0)
    constants[3] = -1
    second = wassat_cone_prove_constant(decoded, aliases, workspace, 4, 1, 100)
    expect(second["equivalent"]).to eq(true)
    constants[4] = 1
    cone = wassat_cone_compact(decoded, aliases, workspace, 4, 3)
    expect(cone["nodes"]).to eq([3, 4])
    expect(cone["clauses"]).to eq([[-1], [2]])
    text = "p cnf 7 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    proof = (first["drat"] + second["drat"]).join("\n") + "\n-5 0\n-6 0\n7 0\n0\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)

  it "declines a rare false constant nomination and publishes no unit" ->
    decoded = wassat_cone_decode(cone_fixture_flat(cone_rare_rows, 66))
    result = wassat_cone_prove_constant(decoded, i64[67], wassat_cone_workspace(decoded), 61, -1, 100)
    expect(result["equivalent"]).to eq(false)
    expect(result["separated"]).to eq(true)
    expect(result["drat"].empty?).to eq(true)

  it "keeps exhausted and cancelled constant proposals inconclusive" ->
    decoded = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]; workspace = wassat_cone_workspace(decoded)
    result = wassat_cone_prove_constant(decoded, aliases, workspace, 3, -1, 0)
    expect(result["equivalent"]).to eq(false)
    expect(result["conflicts"]).to eq(0)
    result = wassat_cone_prove_constant(decoded, aliases, workspace, 3, -1, 100, clock_ms() - 1)
    expect(result["stopped"]).to eq(true)
    expect(result["drat"].empty?).to eq(true)

  it "rejects malformed constant tables before using them as axioms" ->
    decoded = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]; workspace = wassat_cone_workspace(decoded)
    workspace["constants"] = i64[2]
    expect(wassat_cone_compact(decoded, aliases, workspace, 3, 4)["recognized"]).to eq(false)
    constants = i64[8]; constants[3] = 2; workspace["constants"] = constants
    expect(wassat_cone_compact(decoded, aliases, workspace, 3, 4)["recognized"]).to eq(false)

describe "Wassat retained cone retries" ->
  it "retains a proved mismatch direction and lifts its complete original proof" ->
    rows = cone_fixture_rows
    decoded = wassat_cone_decode(cone_fixture_flat(rows, 7))
    aliases = i64[8]; workspace = wassat_cone_workspace(decoded)
    cache = wassat_cone_retry_cache(1)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    first = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 1)
    expect(first["equivalent"]).to eq(false)
    expect(first["conflicts"]).to eq(1)
    expect(cache["resident"]).to eq(1)
    expect(cache["bytes"] > 0).to eq(true)
    second = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 100)
    expect(second["equivalent"]).to eq(true)
    expect(cache["hits"]).to eq(1)
    expect(cache["first_skipped"]).to eq(1)
    expect(cache["resident"]).to eq(0)
    expect(cache["bytes"]).to eq(0)
    expect(first["conflicts"] + second["conflicts"] <= 2).to eq(true)
    text = "p cnf 7 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    proof = second["drat"].join("\n") + "\n-5 0\n-6 0\n7 0\n0\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)

  it "evicts SAT separations and falls through when no retry slots are allowed" ->
    decoded = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    aliases = i64[8]; workspace = wassat_cone_workspace(decoded)
    cache = wassat_cone_retry_cache(1)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    result = wassat_cone_prove(decoded, aliases, workspace, 4, 1, 100)
    expect(result["separated"]).to eq(true)
    expect(cache["resident"]).to eq(0)
    cache["limit"] = 0
    result = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 1)
    expect(result["equivalent"]).to eq(false)
    expect(cache["resident"]).to eq(0)
    expect(wassat_cone_prove(decoded, aliases, workspace, 4, 3, 100)["equivalent"]).to eq(true)

  it "disposes an UNKNOWN owner that exceeds the byte reservation without losing sound fallback" ->
    rows = cone_fixture_rows
    decoded = wassat_cone_decode(cone_fixture_flat(rows, 7))
    aliases = i64[8]; workspace = wassat_cone_workspace(decoded)
    cache = wassat_cone_retry_cache(10, 1)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    first = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 1)
    expect(first["equivalent"]).to eq(false)
    expect(first["conflicts"]).to eq(1)
    expect(cache["resident"]).to eq(0)
    expect(cache["bytes"]).to eq(0)
    expect(cache["declined"]).to eq(1)
    expect(aliases[4]).to eq(0)
    second = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 100)
    expect(second["equivalent"]).to eq(true)
    expect(cache["hits"]).to eq(0)
    text = "p cnf 7 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    proof = second["drat"].join("\n") + "\n-5 0\n-6 0\n7 0\n0\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)

  it "accepts an exact retained reservation and returns every charge on retirement" ->
    decoded = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    workspace = wassat_cone_workspace(decoded)
    cache = wassat_cone_retry_cache(2)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    aliases = i64[8]
    first = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 1)
    bytes = cache["bytes"]
    expect(bytes > 0).to eq(true)
    z = wassat_cone_retry_release(workspace)
    expect(cache["bytes"]).to eq(0)
    cache["max_bytes"] = bytes
    again = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 1)
    expect(again["equivalent"]).to eq(false)
    expect(cache["resident"]).to eq(1)
    expect(cache["bytes"]).to eq(bytes)
    cache["max_bytes"] = 0
    last = wassat_cone_prove(decoded, aliases, workspace, 4, 3, 100)
    expect(last["equivalent"]).to eq(true)
    expect(cache["bytes"]).to eq(0)
    z = wassat_cone_retry_release(workspace)
    expect(cache["bytes"]).to eq(0)

describe "Wassat streamed signature refinement" ->
  it "refines a rare SAT difference without inventing an original verdict" ->
    formula = cone_fixture_flat(cone_rare_rows, 66)
    checkpoint = wassat_cone_checkpoint(formula, 10000)
    checkpoint["stream_refinement"] = true; checkpoint["stream_batch"] = 1
    result = wassat_cone_resume(checkpoint)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["counterexamples"] > 0).to eq(true)
    expect(result["drat_text"]).to eq("")
    expect(result["conflicts"] <= 10000).to eq(true)

  it "preserves a checked complete proof for genuinely equivalent outputs" ->
    rows = cone_fixture_rows(3)
    checkpoint = wassat_cone_checkpoint(cone_fixture_flat(rows, 15), 1000)
    checkpoint["stream_refinement"] = true
    result = wassat_cone_resume(checkpoint)
    expect(result["status"]).to eq(-1)
    text = "p cnf 15 [rows.size]\n"
    rows.each -> (c) text += c.join(" ") + " 0\n"
    expect(wrat_verify(text, result["drat_text"])["verified"]).to eq(true)

describe "Wassat decimal proof lifting" ->
  it "copies signed long identifiers and grows for repeated literals" ->
    lines = ["  +1 -2 0  ", "d 1 0", "", "0"]
    lifted = wassat_cone_lift_drat(lines, [123456, 987654])
    expect(lifted).to eq(["123456 -987654 0", "0"])
    repeated = []
    i = 0
    while i < 40
      repeated.push("1"); i += 1
    line = repeated.join(" ") + " 0"
    result = wassat_cone_lift_drat([line], [123456])
    expect(result[0].split(" ").size).to eq(41)
    expect(result[0].starts_with?("123456 123456 ")).to eq(true)

  it "rejects malformed, overflowing and trailing proof tokens" ->
    ["1x 0", "- 0", "9999999999999999999999 0", "1 00", "1 -0", "1 0 2"].each -> (line)
      expect(-> () wassat_cone_lift_drat([line], [7])).to raise_error

spec_summary

use spec
use ../lib/wassat

describe "Circular score sweeps" ->
  it "matches weighted edge sums at every label, including wrapping and half circles" ->
    n = 4
    checked = 0
    while n <= 14
      ne = n - 1
      left = i32[ne]; right = i32[ne]; heads = i32[n + 1]
      occ = i32[2 * ne]; fill = i32[n]; matrix = i8[n * n]
      v = 1
      while v < n
        matrix[v] = 1; matrix[v * n] = 1
        v += 1
      wassat_cycle_graph(n, matrix, left, right, heads, occ, fill)
      perm = i32[n]; weights = i32[ne]
      v = 0
      while v < n
        perm[v] = (v + 2) % n
        v += 1
      e = 0
      while e < ne
        weights[e] = 1000000000 - e * 17
        e += 1
      scores = i64[n]; plain = i64[n]; adjacent = i32[n]
      width = 1
      while width <= n / 2
        u = 0
        while u < n
          wassat_cycle_scores(n, width, u, left, right, heads, occ, perm, weights, scores, plain, adjacent)
          label = 0
          while label < n
            weighted = 0; raw = 0
            at = heads[u]
            while at < heads[u + 1]
              e = occ[at]; z = left[e] ^ right[e] ^ u
              distance = label - perm[z]
              distance = -distance if distance < 0
              distance = n - distance if distance > n - distance
              cost = distance < width ? width - distance : 0
              weighted += weights[e] * cost
              raw += cost
              expect(adjacent[z]).to eq(e + 1)
              at += 1
            expect(scores[label]).to eq(weighted)
            expect(plain[label]).to eq(raw)
            checked += 1
            label += 1
          u += 1
        width += 1
      n += 1
    expect(checked).to eq(5272)

  it "clears reused scores and adjacency for a vertex with no edges" ->
    n = 6
    scores = i64[n]; plain = i64[n]; adjacent = i32[n]
    v = 0
    while v < n
      scores[v] = 100; plain[v] = 10; adjacent[v] = 4
      v += 1
    wassat_cycle_scores(n, 3, 0, i32[0], i32[0], i32[n + 1], i32[0], i32[n], i32[0], scores, plain, adjacent)
    v = 0
    while v < n
      expect(scores[v]).to eq(0)
      expect(plain[v]).to eq(0)
      expect(adjacent[v]).to eq(0)
      v += 1

  it "resets the bound verifier poll cursor before counting sweep work" ->
    n = 4
    matrix = i8[n * n]
    u = 0
    while u < n
      v = 0
      while v < n
        matrix[u * n + v] = 1 if u != v
        v += 1
      u += 1
    left = i32[6]; right = i32[6]; heads = i32[5]; occ = i32[12]
    wassat_cycle_graph(n, matrix, left, right, heads, occ, i32[n])
    rng = i64[1]; rng[0] = 1
    m = i64[24]; m[23] = 16384
    wassat_cycle_trial(n, 6, 2, left, right, heads, occ, i32[n], i32[n], i32[6], i32[6], i32[6], rng, m, i64[4], 0, 1, 1)
    expect(m[7]).to eq(1)
    expected = env("WASSAT_CYCLIC_SWEEP") == "0" ? 0 : 3
    expect(m[23]).to eq(expected)

spec_summary

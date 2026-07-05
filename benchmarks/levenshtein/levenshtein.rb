def levenshtein(s, t)
  return t.length if s.empty?
  return s.length if t.empty?

  n = t.length
  prev = (0..n).to_a
  curr = Array.new(n + 1, 0)

  s.each_char.with_index do |sc, i|
    curr[0] = i + 1
    t.each_char.with_index do |tc, j|
      cost = sc == tc ? 0 : 1
      ins = curr[j] + 1
      del = prev[j + 1] + 1
      sub = prev[j] + cost
      m = ins < del ? ins : del
      curr[j + 1] = sub < m ? sub : m
    end
    prev, curr = curr, prev
  end

  prev[n]
end

s = "the quick brown fox jumps over the lazy dog" * 20
t = "the slow brown fox leaps over the lazy cat" * 20
puts levenshtein(s, t)

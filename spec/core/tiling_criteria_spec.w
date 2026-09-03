# Boundary words, the translation and Conway criteria, periodic tilings.
# Run:
#   bin/tungsten spec/core/tiling_criteria_spec.w

use geometry

-> tiling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> letters_in_range?(word, n)
  i = 0
  while i < word.size
    return false if word[i] < 0 || word[i] >= n
    i += 1
  true

square2 = Polyform.parse("O 0 0 1 0 0 1 1 1")
tiling_check("word.square2", BoundaryWord.of(square2) == [0, 0, 1, 1, 2, 2, 3, 3])
ell = Polyform.parse("O 0 0 0 1 0 2 1 0")
tiling_check("word.ell_length", BoundaryWord.of(ell).size == 10)
tiling_check("word.hex_cell", BoundaryWord.of(Polyform.parse("H 0 0")).size == 6)
tiling_check("word.triangle", BoundaryWord.of(Polyform.parse("I 0 0")).size == 3)
eleven = Polyform.parse("H -3 2 -3 4 -2 2 -2 4 -1 1 -1 3 0 0 0 1 0 2 0 3 1 0")
w11 = BoundaryWord.of(eleven)
tiling_check("word.eleven_hex_letters", letters_in_range?(w11, 6))
# A closed walk: the letter counts of opposite directions agree.
balanced = true
d = 0
while d < 3
  balanced = false if w11.select(->(x) x == d).size != w11.select(->(x) x == d + 3).size
  d += 1
tiling_check("word.eleven_hex_closed", balanced)

# Tilers the criteria recognise.
tiling_check("criterion.square2", TilingCriteria.tiles?(square2) == :translation)
tiling_check("criterion.ell", TilingCriteria.tiles?(ell) == :translation)
tiling_check("criterion.hex_cell", TilingCriteria.tiles?(Polyform.parse("H 0 0")) == :translation)
tiling_check("criterion.triangle_conway", TilingCriteria.tiles?(Polyform.parse("I 0 0")) == :conway)
tiling_check("criterion.t_tetromino", TilingCriteria.tiles?(Polyform.parse("O 0 0 1 0 2 0 1 1")) != nil)
tiling_check("criterion.hex_bar", TilingCriteria.tiles?(Polyform.parse("H 0 0 1 0 2 0")) == :translation)

# Census non-tilers are never called tilers.
nontilers = ["H -2 2 -1 1 0 0 1 0 2 0 2 1", "H -1 1 0 0 1 0 2 0 3 0 3 1",
             "H -2 2 -1 1 0 0 1 0 1 1 1 2", "H -3 1 -2 1 -2 2 -2 3 -1 1 0 0",
             "O 1 0 1 1 0 2 1 2 1 3 2 3 3 3", "O 0 0 4 0 0 1 1 1 2 1 3 1 4 1",
             "O 2 0 2 1 0 2 1 2 2 2 3 2 2 3", "I -8 1 -6 0 -3 -3 -2 -5 -5 1 -3 0 -2 -2",
             "H -3 2 -3 4 -2 2 -2 4 -1 1 -1 3 0 0 0 1 0 2 0 3 1 0"]
sound = true
nontilers.each ->(text)
  sound = false if TilingCriteria.tiles?(Polyform.parse(text)) != nil
tiling_check("criterion.sound_on_census_nontilers", sound)

# ---- periodic tilings ------------------------------------------------------

found = PeriodicTiling.find(ell, 4)
tiling_check("periodic.ell", found != nil && found["k"] == 1 && PeriodicTiling.valid?(ell, found))
tee = Polyform.parse("O 0 0 1 0 2 0 1 1")
found = PeriodicTiling.find(tee, 4)
tiling_check("periodic.t_tetromino", found != nil && PeriodicTiling.valid?(tee, found))
tri = Polyform.parse("I 0 0")
found = PeriodicTiling.find(tri, 4)
tiling_check("periodic.triangle", found != nil && found["k"] == 2 && PeriodicTiling.valid?(tri, found))
flower = Polyform.parse("H 0 0 1 0 0 1 -1 1 -1 0 0 -1 1 -1")
found = PeriodicTiling.find(flower, 4)
tiling_check("periodic.hex_flower", found != nil && found["k"] == 1 && PeriodicTiling.valid?(flower, found))
tiling_check("periodic.nontiler_miss", PeriodicTiling.find(Polyform.parse("H -2 2 -1 1 0 0 1 0 2 0 2 1"), 4) == nil)
tiling_check("periodic.lattices", PeriodicTiling.lattices(4).size == 7)

<< "tiling criteria spec: all checks passed"

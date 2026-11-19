use ../lib/satori

# Re-enter the printed proposition and compare its elaborated kernel term.
s = Session.new(".")
s.quiet = true
statements = [
  "∀ m n : ℕ, (m : ℝ) ≤ (n : ℝ)",
  "∀ z : ℤ, z ≤ 7 → (z : ℝ) < 9",
  "∀ (n : ℕ) (q : ℚ), (n : ℝ) ≤ (q : ℝ)",
  "∀ n : ℕ, ((n - 2 : ℕ) : ℝ) = 4",
  "((1 / 2 : ℕ) : ℝ) = 0",
  "∀ (f : ℕ → ℤ) (i : ℕ), (f i : ℝ) = 1",
  "(fun (x : ℤ) => (x : ℝ)) = (fun (x : ℤ) => (x : ℝ))",
  "∀ z : ℤ, (nat_of_int z : ℚ) = 3",
  "int_of_nat = int_of_nat"]
i = 0
statements.each -> (statement)
  name = "case" + i.to_s
  s.run_source("axiom " + name + " : " + statement)
  original = s.theorems[name].concl
  shown = tm_show(original)
  s.run_source("axiom " + name + "_shown : " + shown)
  copy = s.theorems[name + "_shown"]
  if copy == nil || !tm_eq(copy.concl, original)
    raise "cast display changed the statement: " + shown
  i += 1
<< "Cast display round trips passed"

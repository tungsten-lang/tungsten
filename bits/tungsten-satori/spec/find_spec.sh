#!/bin/sh
# Lookup reads declarations, including their conditions, in unimported modules.
set -eu
bin=${1:?usage: find_spec.sh SATORI_BINARY}
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
prelude="$root/bits/tungsten-satori/prelude"
mkdir -p "$prelude/nested"
touch "$prelude/prelude.sat"
cat > "$prelude/nested/scan.sat" <<'SAT'
@[auto] + swap (F : ℕ → ℕ → ℚ) (n m : ℕ)
    : (∑ i < n, ∑ j < m, F i j) = (∑ j < m, ∑ i < n, F i j) := by missing_tactic
+ wrong_indices (F : ℕ → ℕ → ℚ) (n m : ℕ) :
    (∑ i < n, ∑ j < m, F i j) = (∑ j < m, ∑ i < n, F j i) := by sorry
axiom guarded (x : ℝ) (good : safe x) : certified x
theorem unrelated (x : ℕ) (unused : ℝ) : certified x := by sorry
lemma opposite (x : ℝ) (bad : ¬ safe x) : certified x := by sorry
+ after_colon : ∀ (value : ℚ), safe value → accepted value := by sorry
+ bounded_form (n : ℕ) : ∀ k < n, fits k n := by sorry
+ independent (F : ℕ → ℕ) : ∀ i j, probe (F i) (F j) := by sorry
+ shadow (P : ℕ → ℕ → Prop) : ∀ x, ∃ x, P x x := by sorry
+ outer (P : ℕ → ℕ → Prop) : ∀ x, ∃ y, P x y := by sorry
SAT
out="$root/out"
"$bin" find '(f : ℕ → ℕ → ℚ) : (∑ i < n, ∑ j < m, f i j) = (∑ j < m, ∑ i < n, f i j)' >"$out"
grep -F 'import arith  ·  + sum_below.swap.rat' "$out" >/dev/null
if grep -F 'sum_below.swap.nat' "$out" >/dev/null; then exit 1; fi
export SATORI_ROOT="$root"
"$bin" find '(table : ℕ → ℕ → ℚ) :
  (∑ a < rows, ∑ b < cols, table a b) = (∑ b < cols, ∑ a < rows, table a b)' >"$out"
test "$(wc -l <"$out")" -eq 1
grep -F 'import nested.scan  ·  @[auto] + swap' "$out" >/dev/null
if grep -F ':=' "$out" >/dev/null; then exit 1; fi
"$bin" find '(∑ e < 163, ∑ t < 127, h s e * (D e t * c t)) = (∑ t < 127, ∑ e < 163, h s e * (D e t * c t))' >"$out"
test "$(wc -l <"$out")" -eq 1
grep -F '+ swap' "$out" >/dev/null
"$bin" find '∀ a b, probe (a + 1) (b + 1)' >"$out"
grep -F '+ independent' "$out" >/dev/null
"$bin" find '∀ a b, probe (a + b) (b + a)' >"$out"
grep -Fx 'no matching library declaration' "$out" >/dev/null
"$bin" find '∀ a b, probe (a + 1) (b + 2)' >"$out"
grep -Fx 'no matching library declaration' "$out" >/dev/null
"$bin" find '(v : ℝ) (h : safe v) : certified v' >"$out"
test "$(wc -l <"$out")" -eq 1
grep -F 'axiom guarded (x : ℝ) (good : safe x) : certified x' "$out" >/dev/null
"$bin" find '(v : ℝ) : certified v' >"$out"
test "$(wc -l <"$out")" -eq 2
grep -F 'lemma opposite' "$out" >/dev/null
"$bin" find '(v : ℚ) (h : safe v) : accepted v' >"$out"
grep -F '+ after_colon' "$out" >/dev/null
"$bin" find '(h : a < m) : fits a m' >"$out"
grep -F '+ bounded_form' "$out" >/dev/null
"$bin" find '(h : m < a) : fits a m' >"$out"
grep -Fx 'no matching library declaration' "$out" >/dev/null
"$bin" find 'certified _' >"$out"
test "$(wc -l <"$out")" -eq 3
"$bin" find '∀ a, ∃ b, Rel b b' >"$out"
head -n 1 "$out" | grep -F '+ shadow' >/dev/null
grep -F '+ outer' "$out" >/dev/null
"$bin" find '(p : ℤ) : certified p' >"$out"
grep -Fx 'no matching library declaration' "$out" >/dev/null
if "$bin" find 'x +' >"$out"; then exit 1; fi
if "$bin" find >"$out"; then exit 1; fi
i=0
while [ "$i" -lt 15 ]; do
  echo "axiom extra$i : marker" >>"$prelude/nested/scan.sat"
  i=$((i + 1))
done
"$bin" find marker >"$out"
test "$(wc -l <"$out")" -eq 13
grep -Fx '3 more matches (use --all)' "$out" >/dev/null
"$bin" find --all marker >"$out"
test "$(wc -l <"$out")" -eq 15
test ! -e "$root/bits/tungsten-satori/.satori-cache"

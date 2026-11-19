#!/bin/sh
# Pass a freshly built Satori binary as the first argument.
set -eu
bin=${1:?usage: cli_spec.sh SATORI_BINARY}
fixture=bits/tungsten-satori/examples/hello.sat

"$bin" check --no-cache bits/tungsten-satori/spec/auto_quantified_hints.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_quantified_hints_failure.sat >/dev/null; then
  echo "auto accepted an invalid quantified hint" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_quantified_hints.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_arithmetic_congruence.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_arithmetic_congruence_failure.sat >/dev/null; then
  echo "auto accepted invalid arithmetic congruence" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_arithmetic_congruence.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/simp_locations.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/simp_locations_failure.sat >/dev/null; then
  echo "simp accepted an invalid location or proof" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_simp_locations.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_equality_products.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_equality_products_failure.sat >/dev/null; then
  echo "auto accepted an invalid equality product" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_equality_products.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/spec/auto_structured_guards.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_induction_guards.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_square_bounds.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_square_bounds_failure.sat >/dev/null; then
  echo "auto accepted an invalid square bound" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_square_bounds.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_symbolic_factors.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_symbolic_factors_failure.sat >/dev/null; then
  echo "auto accepted an invalid symbolic factor" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_symbolic_factors.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_normalized_chains.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_normalized_chains_failure.sat >/dev/null; then
  echo "auto accepted an invalid normalized bound chain" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_normalized_chains.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_affine_chains.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_affine_chains_failure.sat >/dev/null; then
  echo "auto accepted an invalid affine bound chain" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_affine_chains.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/auto_bound_chains.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_bound_chains_failure.sat >/dev/null; then
  echo "auto accepted an invalid bound chain" >&2
  exit 1
fi
"$bin" check --no-cache bits/tungsten-satori/examples/compact_bound_chains.sat >/dev/null

for kind in nat int rat real; do
  "$bin" check --no-cache "bits/tungsten-satori/spec/auto_powers_${kind}.sat" >/dev/null
  if "$bin" check --no-cache "bits/tungsten-satori/spec/auto_powers_${kind}_failure.sat" >/dev/null; then
    echo "auto accepted an invalid power bound for $kind" >&2
    exit 1
  fi
done
"$bin" check --no-cache bits/tungsten-satori/examples/compact_powers.sat >/dev/null

for kind in nat int rat real; do
  "$bin" check --no-cache "bits/tungsten-satori/spec/auto_minmax_${kind}.sat" >/dev/null
  # Compare behavior after writing and then reloading the typed module cache.
  "$bin" check "bits/tungsten-satori/spec/auto_minmax_${kind}.sat" >/dev/null
  "$bin" check "bits/tungsten-satori/spec/auto_minmax_${kind}.sat" >/dev/null
  if "$bin" check --no-cache "bits/tungsten-satori/spec/auto_minmax_${kind}_failure.sat" >/dev/null; then
    echo "auto accepted an invalid min/max bound for $kind" >&2
    exit 1
  fi
done
"$bin" check --no-cache bits/tungsten-satori/examples/compact_minmax.sat >/dev/null

for kind in rat real; do
  "$bin" check --no-cache "bits/tungsten-satori/spec/auto_division_${kind}.sat" >/dev/null
  if "$bin" check --no-cache "bits/tungsten-satori/spec/auto_division_${kind}_failure.sat" >/dev/null; then
    echo "auto accepted an invalid quotient for $kind" >&2
    exit 1
  fi
done
"$bin" check --no-cache bits/tungsten-satori/examples/compact_division.sat >/dev/null

for kind in int rat real; do
  "$bin" check --no-cache "bits/tungsten-satori/spec/auto_abs_${kind}.sat" >/dev/null
  if "$bin" check --no-cache "bits/tungsten-satori/spec/auto_abs_${kind}_failure.sat" >/dev/null; then
    echo "auto accepted an invalid absolute-value bound for $kind" >&2
    exit 1
  fi
done
"$bin" check --no-cache bits/tungsten-satori/examples/compact_abs.sat >/dev/null

"$bin" check --no-cache bits/tungsten-satori/spec/square_matching.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/square_matching_failure.sat >/dev/null; then
  echo "square matching escaped a factor, sign, guard or binder" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_roots.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_roots_failure.sat >/dev/null; then
  echo "auto accepted an invalid root sign, domain or bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_log_exp.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_analysis.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_log_exp_failure.sat >/dev/null; then
  echo "auto accepted an invalid logarithmic/exponential bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_polymorphic_facts.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_polymorphic_facts_failure.sat >/dev/null; then
  echo "polymorphic hint facts escaped a type, guard or instance" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_hint_facts.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_hints.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_hint_facts_failure.sat >/dev/null; then
  echo "auto hint facts escaped a guard, instance or branch" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_quadratic_premises.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_quadratic_premises_failure.sat >/dev/null; then
  echo "auto accepted an invalid quadratic side condition" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/projection_matching.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/spec/projection_matching_guards.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_complex.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/projection_matching_failure.sat >/dev/null; then
  echo "projection matching accepted an invalid field, constructor or bound" >&2
  exit 1
fi
if "$bin" check --no-cache bits/tungsten-satori/spec/projection_matching_guards_failure.sat >/dev/null; then
  echo "projection matching silently used an unrelated axiom" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_head_aliases.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_head_aliases_failure.sat >/dev/null; then
  echo "auto aliases accepted an invalid bound, definition or scope" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_cauchy.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/spec/auto_euclidean.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_norms.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_cauchy_failure.sat >/dev/null; then
  echo "auto Cauchy accepted an invalid sign, form or bound" >&2
  exit 1
fi
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_euclidean_failure.sat >/dev/null; then
  echo "auto norm bounds accepted an invalid sign, vector or strict bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/implicit_induction.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_induction.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/implicit_induction_failure.sat >/dev/null; then
  echo "implicit induction accepted an invalid target, scope or proof" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/bare_proofs.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_logic.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/bare_proofs_failure.sat >/dev/null; then
  echo "bare proofs accepted invalid terms, syntax or scope" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/successor_arith.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/successor_arith_failure.sat >/dev/null; then
  echo "successor arithmetic accepted an invalid offset, guard or index" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/indent_proofs.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/indent_proofs_failure.sat >/dev/null; then
  echo "indented proofs ignored code or escaped a parent goal" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_forward_arith.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_forward_arith_failure.sat >/dev/null; then
  echo "auto arithmetic accepted an invalid guard, bound or branch" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_sums.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_sums.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_sums_failure.sat >/dev/null; then
  echo "auto sums accepted an invalid range, formula or circular assumption" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_geometric.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_geometric_failure.sat >/dev/null; then
  echo "auto geometric mean accepted an invalid sign, vector or bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_defaults.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_defaults_failure.sat >/dev/null; then
  echo "plain auto accepted an invalid bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_iff.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_iff_failure.sat >/dev/null; then
  echo "auto iff accepted an invalid guard, binder or direction" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/auto_hints.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_auto.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/auto_hints_failure.sat >/dev/null; then
  echo "auto hints accepted an invalid or malformed proof" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/entropy.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/entropy_failure.sat >/dev/null; then
  echo "entropy accepted an invalid sign, normalization or strictness" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/strict_jensen.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/strict_jensen_failure.sat >/dev/null; then
  echo "strict Jensen accepted an invalid sign, mean, equality or direction" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/sqrt_distance.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/sqrt_distance_failure.sat >/dev/null; then
  echo "square-gap/root distance accepted an invalid sign or bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/geometric_mean.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/geometric_mean_failure.sat >/dev/null; then
  echo "geometric mean accepted an invalid sign, vector or strict bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/reciprocal_sqrt.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/reciprocal_sqrt_failure.sat >/dev/null; then
  echo "fraction/root comparison accepted an invalid sign or strictness" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/convex_instances.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/spec/exp_convex_import.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/convex_instances_failure.sat >/dev/null; then
  echo "convexity accepted an invalid sign, mean or direction" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/jensen.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/jensen_failure.sat >/dev/null; then
  echo "Jensen accepted an invalid domain, mean or maximizer" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/absolute_layout.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/spec/euclidean.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/euclidean_failure.sat >/dev/null; then
  echo "Euclidean bounds accepted an invalid sign, vector or strict bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/cauchy.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/cauchy_failure.sat >/dev/null; then
  echo "Cauchy accepted an invalid sign, form or bound" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_univariate.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_univariate_failure.sat >/dev/null; then
  echo "univariate arithmetic accepted an invalid inequality" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_cross_squares.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_cross_squares_failure.sat >/dev/null; then
  echo "completed-square arithmetic accepted an invalid inequality" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_squares.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_squares_failure.sat >/dev/null; then
  echo "square arithmetic accepted an invalid inequality" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_cubic.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/nlinarith_cubic_failure.sat >/dev/null; then
  echo "cubic arithmetic accepted an invalid inequality" >&2
  exit 1
fi

"$bin" check --no-cache bits/tungsten-satori/spec/linear2.sat >/dev/null
if "$bin" check --no-cache bits/tungsten-satori/spec/linear2_failure.sat >/dev/null; then
  echo "two-equation rules accepted an invalid premise" >&2
  exit 1
fi

# Keep the compact library recipes executable.
"$bin" check --no-cache bits/tungsten-satori/examples/compact_sums.sat >/dev/null
"$bin" check --no-cache bits/tungsten-satori/examples/compact_inequalities.sat >/dev/null

reject() {
  if "$bin" "$@" >/dev/null 2>&1; then
    echo "unexpected success: $*" >&2
    exit 1
  fi
}

reject check
reject stats --no-cache
reject check -j
reject check --only
reject check -j 0 "$fixture"
reject check -j 2x "$fixture"
reject check --only -1 "$fixture"
"$bin" check "$fixture" >/dev/null
"$bin" check -j 1 "$fixture" >/dev/null
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out=$tmp/output
for jobs in 0 2; do
  set -- check --no-cache
  if test "$jobs" != 0; then set -- "$@" -j "$jobs"; fi
  if SATORI_BIN="$bin" "$bin" "$@" bits/tungsten-satori/spec/auto_strict_feedback_split.sat >"$out"; then
    echo "strict feedback closed an unproved goal" >&2
    exit 1
  fi
  test "$(grep -E '^  (proved|need|witness) ' "$out")" = "  proved score a ≤ a
  need score a ≠ a
  witness a
  proved score a ≤ a
  need valid a
  proved a ≤ b
  need a ≠ b
  proved score a ≤ a
  need valid a
  proved score d = d"
done
# Warm and replay a user module, then use its unregistered induction lemma.
cp bits/tungsten-satori/examples/premise_selection.sat "$tmp/lamps.sat"
cat >"$tmp/select.sat" <<'EOF'
import lamps

+ imported_lamp (x : ℕ) (h : lit 0) (s : ∀ k : ℕ, lit k → lit (succ k)) : lit x := by auto
EOF
for run in cold warm; do
  "$bin" check "$tmp/select.sat" >"$out"
  grep -q '^✓ imported_lamp : .*lit x$' "$out"
done
SATORI_BIN="$bin" "$bin" check --no-cache -j 1 "$tmp/select.sat" >"$out"
grep -q '^✓ imported_lamp : .*lit x$' "$out"
for jobs in 0 1; do
  set -- check --no-cache
  if test "$jobs" != 0; then set -- "$@" -j "$jobs"; fi
  if SATORI_BIN="$bin" "$bin" "$@" bits/tungsten-satori/spec/auto_selection_failure.sat >"$out"; then
    echo "untrusted premise selected" >&2
    exit 1
  fi
  for theorem in excluded_axiom excluded_sorry unfinished excluded_failure; do
    grep -q "^✗ .*theorem $theorem).*auto failed" "$out"
  done
done
for jobs in 0 1; do
  set -- check --no-cache
  if test "$jobs" != 0; then set -- "$@" -j "$jobs"; fi
  if SATORI_BIN="$bin" "$bin" "$@" bits/tungsten-satori/spec/split_auto_dependencies.sat >"$out"; then
    echo "accepted an untrusted auto registration" >&2
    exit 1
  fi
  grep -q '^✗ .*forbidden.*auto registration excludes axiom:permission' "$out"
  grep -q '^✗ .*unfinished_rule.*auto registration excludes sorry' "$out"
  grep -q '^✓ scaling .*\[oracle:arith\]$' "$out"
  test "$(grep -E '^  (proved|need) ' "$out")" = "  proved a ≤ b
  need 0 ≤ c"
  if test "$jobs" != 0; then
    grep -q '^✓ downstream .*uses-failed:forbidden' "$out"
  fi
done
printf '%s\n' '#axioms missing_theorem' >"$tmp/missing-axioms.sat"
if "$bin" check --no-cache "$tmp/missing-axioms.sat" >"$out"; then
  echo "axiom query accepted an unknown theorem" >&2
  exit 1
fi
grep -q "unknown theorem 'missing_theorem'" "$out"
cat >"$tmp/old-worker" <<'EOF'
#!/bin/sh
printf '%s\n' '⋯ split old' '── input: OK'
EOF
chmod +x "$tmp/old-worker"
if SATORI_BIN="$tmp/old-worker" "$bin" check -j 1 "$fixture" >"$out"; then
  echo "split check accepted an incompatible worker" >&2
  exit 1
fi
grep -q 'split worker is incompatible or failed to start' "$out"

# Every theorem worker, as well as the inventory worker, must honor --no-cache.
cat >"$tmp/cache-flag-worker" <<'SH'
#!/bin/sh
if test "$1" != --no-cache; then
  echo 'split worker lost --no-cache' >&2
  exit 1
fi
exec "$SATORI_TEST_BIN" "$@"
SH
chmod +x "$tmp/cache-flag-worker"
SATORI_TEST_BIN="$bin" SATORI_BIN="$tmp/cache-flag-worker" "$bin" check --no-cache -j 2 "$fixture" >"$out"
if SATORI_BIN="$bin" "$bin" check -j 1 bits/tungsten-satori/spec/split_elaboration_failure.sat >"$out"; then
  echo "split check accepted an invalid theorem" >&2
  exit 1
fi
test "$(grep -c '^✗ line 1 ' "$out")" -eq 1
grep -q '^✓ good : ' "$out"
grep -q '^✓ follows : ' "$out"
grep -q 'FAILED (1)' "$out"
SATORI_BIN="$bin" "$bin" check -j 2 bits/tungsten-satori/spec/split_redefinition.sat >"$out"
test "$(grep -c '^✓ same : 1 = 1   \[axiom:dubious\]$' "$out")" -eq 1
test "$(grep -c '^✓ same : 1 = 1$' "$out")" -eq 1
grep -q '^✓ before : 1 = 1   \[axiom:dubious\]$' "$out"
grep -q '^✓ after : 1 = 1$' "$out"
grep -q '^dubious depends on: axiom:dubious$' "$out"
grep -q '^same depends on: axiom:dubious$' "$out"
grep -q '^same depends only on the foundational kernel$' "$out"
if SATORI_BIN="$bin" "$bin" check -j 2 bits/tungsten-satori/spec/split_redefinition_failure.sat >"$out"; then
  echo "split check accepted a failed redefined theorem" >&2
  exit 1
fi
grep -q '^✓ before : 1 = 2   \[uses-failed:same\]$' "$out"
grep -q '^before depends on: uses-failed:same$' "$out"
grep -q '^same depends only on the foundational kernel$' "$out"
grep -q '^✓ same : 1 = 1$' "$out"
grep -q '^✓ after : 1 = 1$' "$out"
grep -q 'FAILED (1)' "$out"
"$bin" check bits/tungsten-satori/spec/auto_forward.sat >"$out"
"$bin" check --no-cache bits/tungsten-satori/spec/application_types.sat >"$out"
for name in flip_forward flip_backward flip_tactic flip_saved predicate_forward relation_forward exists_backward quantified_forward closed_then_applied map_forward nested_application; do
  grep -q "^✓ $name : " "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/application_types_failure.sat >"$out"; then
  echo "polymorphic application accepted a changed variable or type" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 8
"$bin" check --no-cache bits/tungsten-satori/spec/sum_support.sat >"$out"
for kind in real rat int nat; do
  for name in constant bounded_zero bounded_terms bounded_positive bounded_witness bounded_find list_zero list_terms list_witness list_find empty repeated; do
    grep -q "^✓ ${kind}_${name} : " "$out"
  done
done
if "$bin" check --no-cache bits/tungsten-satori/spec/sum_support_failure.sat >"$out"; then
  echo "sum support accepted an invalid index, sign or total" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 30
"$bin" check --no-cache bits/tungsten-satori/spec/sum_squares.sat >"$out"
for kind in real rat int nat; do
  for name in nonneg terms zero weighted_nonneg weighted_terms weighted_zero powers empty repeated zero_weights; do
    grep -q "^✓ ${kind}_${name} : " "$out"
  done
done
if "$bin" check --no-cache bits/tungsten-satori/spec/sum_squares_failure.sat >"$out"; then
  echo "sum of squares accepted an invalid weight, member or total" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 30
"$bin" check --no-cache bits/tungsten-satori/spec/linear_combination.sat >"$out"
for name in scaled_int scaled_rat scaled_real scaled_nat sum_int subtract_int reverse_int cancel_nat difference_nat reverse_nat nested_real scaled_twice fraction_rat cast_coefficient opaque_coefficient projection beta_eta coefficient_beta under_binder identity identity_nat large_coefficient lc_identity applied_theorem local_coefficient centred_squares blaschke_modulus koebe_q_circle; do
  grep -q "^✓ $name : " "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/linear_combination_failure.sat >"$out"; then
  echo "linear combination accepted an invalid certificate" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 26
"$bin" check --no-cache bits/tungsten-satori/spec/simpa.sat >"$out"
for name in unchanged simplify_goal simplify_proof simplify_both close_true close_assumption only_rule reverse_rule all_hypotheses empty_rules empty_no_using explicit_default unfold_alias under_forall under_exists beta_eta function_rule function_rule_binder function_rule_chain function_rule_lambda proof_projection application inferred_argument conditional_rule bound_names zero_add closed_using; do
  grep -q "^✓ $name : " "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/simpa_failure.sat >"$out"; then
  echo "simpa accepted an invalid proof or left a goal unfinished" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 16
grep -q "unknown hypothesis or theorem 'unknown_proof'" "$out"
grep -q 'simpa did not close the goal' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/progression.sat >"$out"
for kind in real rat int nat; do
  for name in direct_linear direct_square shift_linear shift_square constant empty_shift; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for name in real_index_sums nq_eq sum_id sum_sq cnt_eq csum_closed c2sum_closed; do
  grep -q "^✓ $name .*\[oracle:ring\]$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/progression_failure.sat >"$out"; then
  echo "progression accepted an invalid length, base, summand or shift" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 24
"$bin" check --no-cache bits/tungsten-satori/spec/forcing_recurrence.sat >"$out"
for kind in real rat int nat; do
  for name in zero_first zero_later unit_rate; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for kind in real rat int; do
  for name in negative_rate mixed_rates forcing_zero_rate negative_sum empty_sum; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for name in nat_nonzero_initial kmuls_closed bfly_closed gsum_closed geometric; do
  grep -q "^✓ $name .*\[oracle:ring\]$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/forcing_recurrence_failure.sat >"$out"; then
  echo "forcing recurrence accepted an invalid step, initial value or index" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 18
"$bin" check --no-cache bits/tungsten-satori/spec/polynomial_recurrence.sat >"$out"
for kind in real rat int nat; do
  for name in linear quadratic cubic constant; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for name in plen_closed kr_closed kexp_closed sj_closed sj2_closed; do
  grep -q "^✓ $name .*\[oracle:ring\]$" "$out"
done
for name in cr_closed cexp_closed; do
  grep -q "^✓ $name : ∀ j, .* j = j$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/polynomial_recurrence_failure.sat >"$out"; then
  echo "polynomial recurrence accepted an invalid base or increment" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 18
"$bin" check --no-cache bits/tungsten-satori/spec/affine_recurrence.sat >"$out"
for kind in real rat int nat; do
  for name in zero_rate unit_rate zero_scale; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for kind in real rat int; do
  for name in negative_rate nonzero_initial zero_initial; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:ring\]$" "$out"
  done
done
for name in dd_closed ep_closed chacon_closed; do
  grep -q "^✓ ${name} .*\[oracle:ring\]$" "$out"
done
grep -q '^✓ gsum_closed .*\[oracle:arith, oracle:ring\]$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/affine_recurrence_failure.sat >"$out"; then
  echo "affine recurrence accepted an invalid balance, initial value or step" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 15
"$bin" check --no-cache bits/tungsten-satori/spec/geometric.sat >"$out"
for kind in real rat int; do
  grep -q "^✓ ${kind}_zero_rate .*\[oracle:ring\]$" "$out"
  grep -q "^✓ ${kind}_unit_rate .*\[oracle:arith\]$" "$out"
  for name in signed_weights empty_bound zero_weight; do
    grep -q "^✓ ${kind}_${name} .*\[oracle:arith, oracle:ring\]$" "$out"
  done
done
grep -q '^✓ geom_step .*\[oracle:arith, oracle:ring\]$' "$out"
for name in mass_closed entropy_closed; do
  grep -q "^✓ $name .*\[oracle:arith\]$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/geometric_failure.sat >"$out"; then
  echo "geometric bounds accepted an invalid premise" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 9
"$bin" check --no-cache bits/tungsten-satori/spec/recurrence.sat >"$out"
for name in real_drift real_negative_bound real_geometric_lower faa_recurrence real_equal_rates rational_zero_rate rational_negative_drift rational_signed_forcing rational_unit_rate rational_zero_forcing integer_falling integer_lower_zero integer_forcing natural_drift natural_geometric natural_zero_rate; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in integer_oscillation natural_exact; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/recurrence_failure.sat >"$out"; then
  echo "recurrence rules accepted an invalid rate or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (12)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/sequence_order.sat >"$out"
"$bin" check --no-cache bits/tungsten-satori/spec/comparison.sat >"$out.comparison"
test "$(grep -c '^✓ ' "$out.comparison")" -eq 19
if "$bin" check --no-cache bits/tungsten-satori/spec/comparison_failure.sat >"$out.comparison"; then
  echo "recurrence comparison accepted an invalid premise" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out.comparison")" -eq 19
rm -f "$out.comparison"
"$bin" check --no-cache bits/tungsten-satori/spec/descent.sat >"$out.descent"
test "$(grep -c '^✓ ' "$out.descent")" -eq 9
if "$bin" check --no-cache bits/tungsten-satori/spec/descent_failure.sat >"$out.descent"; then
  echo "natural descent accepted an invalid premise" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out.descent")" -eq 6
rm -f "$out.descent"
for name in interval_constant interval_empty real_local real_global_down real_negative_prefix real_equal_endpoints rational_local_down rational_global rational_sum_tail rational_empty rational_cycle integer_local integer_global_down integer_sum_singleton integer_plateau natural_local_down natural_global cum_mono natural_zero_tail; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/sequence_order_failure.sat >"$out"; then
  echo "sequence order accepted an invalid interval or premise" >&2
  exit 1
fi
grep -q 'FAILED (11)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/amortized.sat >"$out"
for name in allowed_equivalent final_equivalent total_equivalent; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in finite_telescope finite_ratio finite_ratio_empty finite_ratio_positive_start real_growth real_potential integer_signed; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in rational_scaled real_scaled integer_scaled; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/amortized_failure.sat >"$out"; then
  echo "amortized costs accepted an invalid order, domain or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (9)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/sequence.sat >"$out"
for name in orbit_property recurrence_origin toggle_period; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in natural_progress countdown_settled countdown_small countdown_unreachable toggle_far toggle_tail toggle_run empty_run periodic_lists; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/sequence_failure.sat >"$out"; then
  echo "sequence patterns accepted a wrong bound or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (10)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/finite_range.sat >"$out"
for name in php php_inclusive empty_injection encoding_size five_into_two inclusive_collision singleton_target empty_target missing_last empty_missing permutation_preimage permutation_endpoint; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/finite_range_failure.sat >"$out"; then
  echo "finite-range patterns accepted invalid bounds or missing premises" >&2
  exit 1
fi
grep -q 'FAILED (10)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/nat_witness.sat >"$out"
for name in witness zero_witness strong_zero_and_step reverse_zero finite_prefix measure_descent; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/nat_witness_examples.sat >"$out"
for name in yslices_disjoint least_below slices_cover descent_bound descent_drop consecutive_eq; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
grep -q '^every_level depends on: axiom:base_case, axiom:induction_step, oracle:arith$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/nat_witness_failure.sat >"$out"; then
  echo "natural patterns accepted an invalid bound or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (12)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/function_iterate.sat >"$out"
grep -q '^iterate_facet depends only on the foundational kernel$' "$out"
grep -q '^iterate_map depends only on the foundational kernel$' "$out"
grep -q '^iterate_fixed depends only on the foundational kernel$' "$out"
grep -q '^iterate_add depends only on the foundational kernel$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/list_fold.sat >"$out"
for name in left_history right_swap left_projection right_unchanged left_fixed paired_right; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/fold_transfer.sat >"$out"
grep -q '^run_inv depends on: oracle:arith$' "$out"
grep -q '^run_equivalent depends only on the foundational kernel$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/list_fold_failure.sat >"$out"; then
  echo "list folds accepted an invalid order or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (10)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/predicate_shapes.sat >"$out"
for name in lambda_nested lambda_tuple lambda_obtain_witness; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/predicate_shapes_failure.sat >"$out"; then
  echo "applied predicates accepted a mismatched or unproved premise" >&2
  exit 1
fi
grep -q 'FAILED (6)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/clamp_lipschitz.sat >"$out"
grep -q '^clamp_test depends on: oracle:arith, oracle:ring$' "$out"
grep -q '^ramp_lipschitz_test depends on: oracle:arith, oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/weighted_variance.sat >"$out"
grep -q '^variance_split depends on: oracle:arith, oracle:ring$' "$out"
grep -q '^rational_gap depends on: oracle:arith, oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/int_cases.sat >"$out"
grep -q '^degree_cases depends on: oracle:arith$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/minmax_distance.sat >"$out"
grep -q '^min_abs_identity depends on: oracle:arith, oracle:ring$' "$out"
grep -q '^integer_distance depends on: oracle:arith, oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/indicator.sat >"$out"
grep -q '^real_union_bound depends only on the foundational kernel$' "$out"
grep -q '^integer_union_identity depends only on the foundational kernel$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/list_sum_patterns.sat >"$out"
grep -q '^vector_sum_le depends on: oracle:arith$' "$out"
grep -q '^vector_sum_scale depends on: oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/sum_linearity.sat >"$out"
for name in memberwise_sum_eq map_composed; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in natural_addition integer_difference rational_negation real_append sum_dot_expand comb_dot; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/sum_range.sat >"$out"
for name in range_congruence real_strict_witness real_negative_band real_empty integer_equal_rest natural_strict natural_empty; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in rational_negative rational_singleton integer_lower; do
  grep -q "^$name depends on: oracle:arith, oracle:ring$" "$out"
done
for name in real_split rational_split integer_split natural_split real_front_empty rational_front integer_front_negative natural_front_singleton; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
grep -q '^local_total_eq depends only on the foundational kernel$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/sum_range_examples.sat >"$out"
for name in sum_split sum_scaled sum_split.real sum_cst; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
for name in sum_lo sum_hi; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
grep -q '^sum_lt_const depends on: oracle:arith, oracle:ring$' "$out"
grep -q '^alt_telescope depends on: oracle:ring$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/sum_range_failure.sat >"$out"; then
  echo "finite sums accepted an invalid range, witness or bound" >&2
  exit 1
fi
grep -q 'FAILED (16)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/rewrite_functions.sat >"$out"
for name in eta_rewrite eta_under_binder eta_conditional eta_simp; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
grep -q '^eta_linear depends on: oracle:arith$' "$out"
grep -q '^eta_ring depends on: oracle:ring$' "$out"
for name in bare_unfold bare_unfold_binary bare_unfold_under_binder; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in bare_unfold_bound bare_unfold_hyp; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/rewrite_functions_failure.sat >"$out"; then
  echo "function normalization accepted a captured variable or missing premise" >&2
  exit 1
fi
grep -q 'FAILED (11)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/weighted_sum.sat >"$out"
for name in weighted_comparison natural_comparison; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in integer_lower rational_upper different_index_types natural_double duplicate_members empty_outer empty_inner comb_lower comb_upper angle_algebra; do
  grep -q "^$name depends on: oracle:arith, oracle:ring$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/weighted_sum_failure.sat >"$out"; then
  echo "weighted sum bounds accepted an invalid premise or list" >&2
  exit 1
fi
grep -q 'FAILED (7)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/natural_nlinarith.sat >"$out"
for name in natural_scale natural_function_weight natural_product_weight natural_sub_weight natural_product_mono dimension_gap; do
  grep -q "^$name depends on: oracle:arith, oracle:ring$" "$out"
done
grep -q '^signed_scale depends on: oracle:arith$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/natural_nlinarith_failure.sat >"$out"; then
  echo "natural nonlinear arithmetic accepted an invalid goal" >&2
  exit 1
fi
grep -q 'FAILED (8)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/quadratic_bounds.sat >"$out"
for name in remove_square remove_strict_square signed_square_order product_lower negative_bound negative_factors product_upper opposite_factors_upper zero_weight; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in natural_square_order natural_product_lower natural_product_upper; do
  grep -q "^$name depends on: oracle:arith, oracle:ring$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/quadratic_bounds_failure.sat >"$out"; then
  echo "quadratic bounds accepted an invalid sign, bound or weight" >&2
  exit 1
fi
grep -q 'FAILED (8)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/polymorphic_pattern.sat >"$out"
for name in nil_generic cons_generic product_nil_generic literal_rat; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/list_product_patterns.sat >"$out"
for name in memberwise_product product_map multiplicative_invariant real_nonnegative; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in rational_comparison integer_unit_bound real_bernoulli integer_bernoulli prod_ge_one_add_sum; do
  grep -q "^$name depends on: oracle:arith$" "$out"
done
for name in natural_comparison natural_bernoulli; do
  grep -q "^$name depends on: oracle:arith, oracle:ring$" "$out"
done
for name in append_product multiply_products; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/list_product_equivalence.sat >"$out"
for name in old_nonneg_members old_sum old_product; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/list_product_patterns_failure.sat >"$out"; then
  echo "list products accepted an invalid sign, identity or member premise" >&2
  exit 1
fi
grep -q 'FAILED (8)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/sum_linearity_failure.sat >"$out"; then
  echo "sum linearity accepted an invalid equality" >&2
  exit 1
fi
grep -q 'FAILED (4)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/polymorphic_pattern_failure.sat >"$out"; then
  echo "polymorphic equations accepted an invalid branch" >&2
  exit 1
fi
grep -q 'FAILED (3)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/sum_closure.sat >"$out"
for name in invariant_sum invariant_naturals; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
for name in sum_multiple zero_multiple negative_multiple empty_multiple; do
  grep -q "^$name depends on: oracle:ring$" "$out"
done
grep -q '^weighted_divisible depends on: oracle:arith, oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/application_lambda.sat >"$out"
for name in lambda_infer_from_proof lambda_nested_type lambda_exists exposed_implication exposed_negation exposed_forall exposed_apply_open exposed_apply_true exposed_twice partial_unused alias_under_exists alias_under_forall alias_proof_argument alias_projection_argument alias_quantified_argument stored_implication stored_forall stored_negation; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/sum_closure_failure.sat >"$out"; then
  echo "sum closure accepted a missing premise or changed multiplier" >&2
  exit 1
fi
grep -q 'FAILED (5)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/application_lambda_failure.sat >"$out"; then
  echo "lambda application accepted a mismatched or unproved premise" >&2
  exit 1
fi
grep -q 'FAILED (21)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/list_patterns.sat >"$out"
for name in all_mem predicate_from_members bounded_transform mapped_predicate append_predicate append_members; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
grep -q '^orbit_sizes_divisible depends on: oracle:ring$' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/rewrite_binders.sat >"$out"
for name in exists_rewrite avoid_rhs_capture repeated_rewrite; do
  grep -q "^$name depends only on the foundational kernel$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/list_patterns_failure.sat >"$out"; then
  echo "list predicates accepted missing or reversed premises" >&2
  exit 1
fi
grep -q 'FAILED (4)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/rewrite_binders_failure.sat >"$out"; then
  echo "binder rewriting captured a variable or escaped a quantifier" >&2
  exit 1
fi
grep -q 'FAILED (3)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/list_sum_patterns_failure.sat >"$out"; then
  echo "list sum accepted a missing membership or nonnegativity condition" >&2
  exit 1
fi
grep -q 'FAILED (3)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/indicator_failure.sat >"$out"; then
  echo "indicator checks accepted a false value or reversed monotonicity" >&2
  exit 1
fi
grep -q 'FAILED (2)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/minmax_distance_failure.sat >"$out"; then
  echo "min/max proof accepted the wrong sign" >&2
  exit 1
fi
grep -q 'FAILED (1)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/int_cases_failure.sat >"$out"; then
  echo "integer cases accepted an invalid sign" >&2
  exit 1
fi
grep -q 'FAILED (2)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/weighted_variance_failure.sat >"$out"; then
  echo "weighted variance accepted a missing denominator condition" >&2
  exit 1
fi
grep -q 'FAILED (1)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/clamp_lipschitz_failure.sat >"$out"; then
  echo "clamp proof accepted a false strict inequality" >&2
  exit 1
fi
grep -q 'FAILED (1)' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/function_iterate_failure.sat >"$out"; then
  echo "iteration lemmas accepted an invalid application" >&2
  exit 1
fi
grep -q 'FAILED (3)' "$out"
if "$bin" check bits/tungsten-satori/spec/auto_forward_failure.sat >"$out"; then
  echo "auto accepted an implication without its premise" >&2
  exit 1
fi
grep -q 'FAILED (13)' "$out"
if grep -q '^✓ invalid' "$out"; then
  echo "auto accepted an invalid implication" >&2
  exit 1
fi
python3 bits/tungsten-satori/spec/auto_truth_table.py "$bin"
echo "Satori CLI checks passed"

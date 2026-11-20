#!/bin/sh
# Pass a freshly built Satori binary as the first argument.
set -eu
bin=${1:?usage: cli_spec.sh SATORI_BINARY}
fixture=bits/tungsten-satori/examples/hello.sat

sh bits/tungsten-satori/spec/find_spec.sh "$bin"
sh bits/tungsten-satori/spec/transfer_spec.sh "$bin"

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
  proved score d = d
  proved score a ≤ a
  need score a ≠ a"
done
# A displayed arithmetic counterexample must also satisfy the local premises
# and explicit hints. Uninterpreted predicates cannot certify a candidate.
for jobs in 0 1; do
  set -- check --no-cache
  if test "$jobs" = 1; then set -- "$@" -j 1; fi
  if SATORI_BIN="$bin" "$bin" "$@" bits/tungsten-satori/spec/polynomial_feedback_failure.sat >"$out"; then
    echo "polynomial feedback accepted an invalid goal" >&2
    exit 1
  fi
  test "$(grep -c '^✗ ' "$out")" -eq 8
  grep -q '^✓ excluded : ' "$out"
  test "$(grep '^  counterexample ' "$out")" = "  counterexample t = 1/4 (0 ≤ -3/4 is false)
  counterexample t = 1/2 (0 ≤ -1 is false)
  counterexample n = 7 (49 < 49 is false)
  counterexample t = 1 (2 ≤ 1 is false)
  counterexample t = 3/4 (0 ≤ -3/4 is false)"
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
serial=bits/tungsten-satori/spec/list_evidence.sat
SATORI_BIN="$bin" "$bin" check --no-cache -j 1 "$serial" >"$out"
grep -Fxq 'assembled depends on: oracle:ring' "$out"
grep -Fxq 'named_hint depends on: axiom:seed' "$out"
grep -Fq ", $(grep -c '^+ ' "$serial") theorem processes, 1 at a time" "$out"
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
for name in flip_forward flip_backward flip_tactic flip_saved predicate_forward relation_forward exists_backward quantified_forward closed_then_applied map_forward nested_application inferred_witness repeated_witness chosen_witness inferred_shared inferred_pair inferred_value pair_value pair_field pair_witness iff_value iff_field pair_constructor ordinary_iff; do
  grep -q "^✓ $name : " "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/application_types_failure.sat >"$out"; then
  echo "polymorphic application accepted a changed variable or type" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 16
for name in pair_missing invalid_field wrong_direction; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
grep -q '^✗ .* (theorem mismatched_witnesses): .*cannot infer argument x of the theorem$' "$out"
grep -q '^✗ .* (theorem ambiguous_value): .*cannot infer argument y of the theorem$' "$out"
grep -q '^✗ .* (theorem ambiguous_pair): .*cannot infer argument x of the theorem$' "$out"
grep -q '^✗ .* (theorem ambiguous_witness): .*cannot infer argument x of the theorem$' "$out"
"$bin" check --no-cache bits/tungsten-satori/prelude/real.sat >"$out"
grep -q '^✓ monotone_bounded_converges : ' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/principal.sat >"$out"
grep -q '^✓ mixed_polynomial : .*\[oracle:ring\]$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/principal_failure.sat >"$out"; then
  echo "auto accepted an invalid polynomial substitution" >&2
  exit 1
fi
for name in wrong_generator unrelated_function changed_exponent missing_factor invalid_zero; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/finite_bounds.sat >"$out"
grep -q '^✓ uniform_samples : .*\[axiom:samples_eventual, axiom:samples_positive, oracle:arith\]$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/finite_bounds_failure.sat >"$out"; then
  echo "auto accepted an invalid uniform lower bound" >&2
  exit 1
fi
for name in weak_prefix missing_tail missing_prefix other_sequence nonpositive_cap named_tail_only; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
grep -A2 '(theorem named_tail_only):' "$out" | grep -q '^  need ∀ i, 1 ≤ i → 0 < samples i$'
"$bin" check --no-cache bits/tungsten-satori/spec/series.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/series_failure.sat >"$out"; then
  echo "auto accepted an invalid convergence argument" >&2
  exit 1
fi
for name in signed_comparison reversed_comparison bounded_terms missing_monotonicity wrong_limit; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/supremum.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/supremum_failure.sat >"$out"; then
  echo "auto accepted an invalid supremum claim" >&2
  exit 1
fi
for name in unattained unbounded_range missing_member different_ranges; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/choice.sat >"$out"
grep -Fxq 'marked depends on: axiom:candidate' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/choice_failure.sat >"$out"; then
  echo "choice accepted an unsupported witness" >&2
  exit 1
fi
for name in no_witness other_predicate ambiguous varies empty_value; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/heat_path.sat >"$out"
grep -Fxq 'calibrated depends on: axiom:calibration, oracle:ring' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/heat_path_failure.sat >"$out"; then
  echo "heat path accepted an invalid rate or boundary condition" >&2
  exit 1
fi
for name in missing_derivative wrong_product missing_outlet reversed_gradient backwards different_predicate wrong_coordinate truncated; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/continuity.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/continuity_failure.sat >"$out"; then
  echo "continuity accepted a missing hypothesis" >&2
  exit 1
fi
for name in jump wrong_point missing_factor zero_radius; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/polyline_curve.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/polyline_curve_failure.sat >"$out"; then
  echo "global polyline accepted an unsupported prefix or slope" >&2
  exit 1
fi
for name in too_short future_reversal wrong_slope downward_piece; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/polyline.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/polyline_failure.sat >"$out"; then
  echo "polyline accepted an invalid increment or knot" >&2
  exit 1
fi
for name in future crossed_corner unordered missing_step outside_cover; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
grep -Fq '  need ∀ i < 2, h (i + 1) - h i = m i * (t (i + 1) - t i)' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/interval_slope.sat >"$out"
grep -q '^✓ measured : .*\[axiom:measured_deriv, oracle:arith, oracle:ring\]$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/interval_slope_failure.sat >"$out"; then
  echo "interval slope accepted an invalid derivative or interval bound" >&2
  exit 1
fi
for name in wrong_derivative too_steep reversed endpoint_jump missing_piece; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/limits.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/limits_failure.sat >"$out"; then
  echo "auto accepted an invalid sequence limit" >&2
  exit 1
fi
for name in wrong_shift wrong_constant reversed_bound finite_prefix; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/limit_order.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/limit_order_failure.sat >"$out"; then
  echo "auto accepted an invalid limit comparison" >&2
  exit 1
fi
for name in reversed_scale strict_limit prefix_order upper_only overshoot; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/laplacian.sat >"$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/laplacian_failure.sat >"$out"; then
  echo "auto accepted a harmonic maximum with a missing premise" >&2
  exit 1
fi
for name in missing_max missing_harmonic missing_edge missing_path backward_path; do
  grep -q "^✗ .* (theorem $name): .*auto failed$" "$out"
done
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
for suite in closure finite_cover pointwise_conjunct predicate_transfer auto_sum_ring weak_derivative auto_polynomial_cases ring_congruence quadratic_form quadratic_roots polynomial_sign polynomial_witness darboux gronwall integral_calculus integral_parameter quadrature heat_interval heat_source wave_interval finite_l2 symplectic_character interpolation threshold sobolev binomial spectrum dual_number derivation localized_derivation localization affine_gluing record_ext list_evidence local_binding power_bound power_tangent fatou positive_functional; do
  case "$suite" in
    list_evidence)
      accepted='assembled local_items known_tail literal_tail empty_list named_hint'
      rejected='hidden_axiom hidden_sorry repeated_gap two_gaps missing_tail wrong_list' ;;
    record_ext)
      accepted='all_fields inferred rebuild right_rebuild concrete functions vacuous callback nested marked tuple_eta tuples global_field declared_name'
      rejected='missing swapped leftover distinct binder tuple_missing misspelled_projection' ;;
    local_binding)
      accepted='typed_number nested_values symbolic unfold_value beneath_binder quantified_value branch_scope let_keeps_outer set_keeps_outer unique_keeps_outer function_value under_substitution named_term identity_term term_argument statement_let block_let'
      rejected='sibling wrong_type missing_rhs missing_eq_name false_value inner_capture quantified_capture comprehension_capture renamed_capture' ;;
    positive_functional)
      accepted='signed_scale signed_sum atomic_support atomic_signed atomic_mass point_value constant_on'
      rejected='missing_unit missing_add missing_support negative_weight empty_mass' ;;
    fatou)
      accepted='simple_limit moving_tail pointwise point_mass point_laws scaled zero_scale sparse_bounds point_cap line_limit profile_bound'
      rejected='reverse_limit strict_limit wrong_point negative_scale one_index missing_volume_law zero_profile' ;;
    power_tangent)
      accepted='shifted tangent repeated clipped loss complement geometric_bound rational_bound two_weights empty_mean marked'
      rejected='negative_base zero_exponent strict_at_equality missing_mean signed_factors wrong_weight' ;;
    power_bound)
      accepted='start_negative real_cutoff empty_chain rounded zero_exponent'
      rejected='no_positive_scale rounded_up negative_base lost_strictness missing_start' ;;
    spectrum)
      accepted='product_open integer_cover positive_power two_avoids_three two_contains_six pullback_open generated_closed quotient_point'
      rejected='union_for_product composite_prime exponent_zero nonunit_cover missing_surjection' ;;
    localization)
      accepted='open_points extend_map recover first_factor lost_factor image_equality first_factor_away unique_extension two_has_no_retraction'
      rejected='cancel_without_unit any_prime_lifts any_map_lifts injective_localization' ;;
    affine_gluing)
      accepted='compatible_sections product_sections from_overlap torsion_on_overlap one_chart_misses_section make_cover'
      rejected='missing_overlap missing_cover wrong_sections' ;;
    localized_derivation)
      accepted='chart_direction ordinary quotient unit_jet fraction_exists quotient_at_two lost_direction'
      rejected='arbitrary_quotient moving_denominator nonunit' ;;
    derivation)
      accepted='power_at lift_at directional tangent_at_two at_zero inverse_density divergence_at_one point_values_agree unweighted_at_one'
      rejected='missing_tangent_factor point_inverse missing_weight' ;;
    dual_number)
      accepted='infinitesimal every_prime open_of_constant_part tangent_product image_of_epsilon'
      rejected='nilpotent_is_zero scalar_part_determines_value missing_nilpotence' ;;
    polynomial_witness)
      accepted='dipping at_minimum two_conditions negative_integer'
      rejected='strict_minimum wrong_interval disjoint no_integer' ;;
    polynomial_sign)
      accepted='tenth_degree shifted_box left_tail right_tail open_ends closed_ends interior_minimum whole_ray reflected_ray whole_line open_after_cut integer_cuts quartic_gap outside_roots two_guards open_fourth_root between_squares positive_root cubic_threshold guarded_hint'
      rejected='endpoint_zero negative_inside absent_upper unrelated_bound integer_division at_cut inside_leaf wrong_ray negative_farther_out shared_root negative_root opposite_guard independent_axis division_guard between_rational_squares' ;;
    quadratic_roots)
      accepted='real_root irrational repeated separated everywhere_pos necessary negative_leading above no_real_root collapsed explicit_negative'
      rejected='zero_scale flat imaginary double_count wrong_sign constant wrong_function at_boundary' ;;
    quadratic_form)
      accepted='neck hessian_at_max hessian_at_min singular_allowed odd_cross ellipticity positive_energy integer_minors shifted_pointwise'
      rejected='missing_diagonal missing_determinant singular_strict zero_vector wrong_cross extra_linear single_direction switched_coordinates' ;;
    closure)
      accepted='endpoint left_endpoint perturbation density local_window upper_endpoint relative open_interval observation'
      rejected='jump strict gap empty_interval far_set one_side punctured' ;;
    finite_cover)
      accepted='three_opens integers_glue arbitrary_sections same_section empty_cover_int axes_cover axes_agree axes_glue cleared_only restrict_and_glue incompatible_sections'
      rejected='missing_cover missing_denominator diagonal_only omitted_chart raw_cross empty_int' ;;
    auto_sum_ring)
      accepted='weighted weighted_list natural length_and_scalar'
      rejected='wrong_bound changed_list wrong_coefficient product_of_sums truncated wrong_length' ;;
    predicate_transfer)
      accepted='restrict_interval restrict_profiles at_profile apply_at_profile interior'
      rejected='wider changed_property wrong_order missing_guard unsupplied' ;;
    pointwise_conjunct)
      accepted='guarded interleaved subtree provenance'
      rejected='missing_guard changed_domain swapped_indices lost_inner_guard reversed_implication' ;;
    weak_derivative)
      accepted='corner moment radial_smooth endpoint_test joined soft_flux heat_flux wave_flux endpoint_values mismatched_traces'
      rejected='one_trace one_endpoint jump point_values interior_change missing_net' ;;
    auto_polynomial_cases)
      accepted='paired_nat shifted swapped opaque_arm bounds common_guard branch_product marked_roots'
      rejected='missing_sum unswapped missing_roots wrong_root open_branch truncated unsupported_flag' ;;
    ring_congruence)
      accepted='integrands eta nested opaque_application vector'
      rejected='capture swapped wrong_head underflow' ;;
    darboux)
      accepted='restricted_constant degenerate two_values average_bound two_rectangles opposite join split_at sum_values'
      rejected='backwards wrong_area endpoints_only wrong_sign gap different_integrands outside sum_mixed_intervals' ;;
    integral_parameter)
      accepted='differentiate right_endpoint'
      rejected='pointwise_only reversed_slice' ;;
    quadrature)
      accepted='square_mean tilted unsampled_mass even_moment legendre_energy polynomial_area oriented reverse_interval point_interval two_means mean_as_integral arbitrary_degree'
      rejected='nodes_only bad_weights false_moment wrong_orientation unordered_certificate unknown_integrand reciprocal missing_term' ;;
    gronwall)
      accepted='growth zero_energy no_crossing comparison negative_endpoint'
      rejected='missing_sign strict_growth missing_order' ;;
    heat_source)
      accepted='boundary_work dissipative_input balanced_input damped_heat source_stability matched_flux net_input uniform_heating increases_with_insulation'
      rejected='ignored_source missing_flux source_only left_flux_only' ;;
    binomial)
      accepted='shifted successor weighted_rows positive_inside outside_row empty_product four_steps symbolic_step four_factors count_range'
      rejected='no_weight missing_bound lost_factor wrong_start' ;;
    sobolev)
      accepted='rougher across_zero same_bound origin order_zero mode_zero mode_one exact_energy lost_budget'
      rejected='reversed different_profile different_volume strict_at_origin' ;;
    threshold)
      accepted='witness limit_bound open_range closed_range at_boundary open_endpoint'
      rejected='lost_strictness missing_monotonicity zero_scale reversed_scale one_error unrelated_bound at_open_cutoff' ;;
    interpolation)
      accepted='exact_chord strict_strip closed_boundary both_ends interior_pair tilted_convex strict_boundary'
      rejected='lost_strictness extrapolation zero_width below_line' ;;
    symplectic_character)
      accepted='packed_bits two_words block_order sharp empty_minor seven'
      rejected='repeated_words missing_size outside_row dropped_factor' ;;
    finite_l2)
      accepted='rectangular cube_energy attenuation trace off_diagonal signed_diagonal zero_bits'
      rejected='missing_orthogonality wrong_scale unchecked_multiplier ordinary_trace' ;;
    wave_interval)
      accepted='boundary_work balanced_ends transport travelling travelling_work reflecting_ends'
      rejected='missing_flux one_closed_end reversed_work wrong_rate' ;;
    heat_interval)
      accepted='two_endpoints insulated_profile neumann_decay warming warming_gains_energy same_temperature zero_at_endpoint distance_contracts'
      rejected='dropped_left unchecked_boundary uninsulated missing_flux point_domain missing_initial' ;;
    integral_calculus)
      accepted='square_primitive negative_multiple linear_exponential first_moment reversed zero_flux value_bound'
      rejected='zero_slope wrong_increment missing_order missing_boundary arbitrary_operator' ;;
  esac
  "$bin" check --no-cache "bits/tungsten-satori/spec/$suite.sat" >"$out"
  for name in $accepted; do
    grep -q "^✓ $name : " "$out"
  done
  if test "$suite" = positive_functional; then
    grep -Fxq 'signed_scale depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'constant_on depends on: axiom:add, axiom:mass, axiom:pos, oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = fatou; then
    grep -Fxq 'moving_tail depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'pointwise depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'point_laws depends only on the foundational kernel' "$out"
    grep -Fxq 'line_limit depends on: axiom:line_laws, oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = power_tangent; then
    grep -Fxq 'geometric_bound depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'marked depends on: axiom:weights, oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = quadrature; then
    for name in unsampled_mass legendre_energy; do
      grep -Fxq "$name depends on: oracle:arith, oracle:ring" "$out"
    done
  fi
  if test "$suite" = closure; then
    grep -Fxq 'observation depends on: axiom:nearby, axiom:regular, oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = finite_cover; then
    grep -Fxq 'restrict_and_glue depends on: oracle:arith' "$out"
    grep -Fxq 'axes_glue depends on: oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = auto_sum_ring; then
    grep -Fxq 'weighted depends on: oracle:ring' "$out"
    grep -Fxq 'weighted_list depends on: oracle:ring' "$out"
  fi
  if test "$suite" = predicate_transfer; then
    grep -Fxq 'restrict_profiles depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'interior depends on: axiom:initial_interval, oracle:arith' "$out"
  fi
  if test "$suite" = pointwise_conjunct; then
    grep -Fxq 'provenance depends on: axiom:evidence' "$out"
  fi
  if test "$suite" = localized_derivation; then
    for name in chart_direction ordinary quotient unit_jet; do
      grep -Fxq "$name depends only on the foundational kernel" "$out"
    done
  fi
  if test "$suite" = derivation; then
    for name in power_at lift_at; do
      grep -Fxq "$name depends only on the foundational kernel" "$out"
    done
    "$bin" check --no-cache bits/tungsten-satori/examples/coordinate_bracket.sat >"$out"
    for name in bracket_coefficients divergence_at; do
      grep -Fxq "$name depends on: oracle:ring" "$out"
    done
  fi
  if test "$suite" = weak_derivative; then
    for name in corner moment soft_flux; do
      grep -Fxq "$name depends on: oracle:arith, oracle:ring" "$out"
    done
  fi
  if test "$suite" = affine_gluing; then
    for name in compatible_sections from_overlap make_cover; do
      grep -Fxq "$name depends only on the foundational kernel" "$out"
    done
  fi
  if test "$suite" = binomial; then
    grep -Fxq 'weighted_rows depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'four_steps depends only on the foundational kernel' "$out"
  fi
  if test "$suite" = auto_polynomial_cases; then
    grep -Fxq 'marked_roots depends on: axiom:supplied_roots, oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = polynomial_sign; then
    grep -Fxq 'guarded_hint depends on: axiom:supplied_quartic, oracle:arith' "$out"
  fi
  if test "$suite" = quadratic_roots; then
    grep -Fxq 'separated depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'no_real_root depends on: oracle:arith' "$out"
    grep -Fxq 'explicit_negative depends on: axiom:excludes' "$out"
  fi
  if test "$suite" = sobolev; then
    grep -Fxq 'rougher depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'lost_budget depends on: oracle:arith' "$out"
  fi
  if test "$suite" = threshold; then
    grep -Fxq 'closed_range depends on: oracle:arith, oracle:ring' "$out"
    grep -Fxq 'limit_bound depends on: oracle:arith' "$out"
  fi
  if test "$suite" = interpolation; then
    grep -Fxq 'interior_pair depends on: oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = finite_l2; then
    grep -Fxq 'trace depends on: oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = wave_interval; then
    grep -Fxq 'travelling_work depends on: oracle:arith, oracle:ring' "$out"
  fi
  if test "$suite" = heat_source; then
    for name in damped_heat dissipative_input balanced_input; do
      grep -Fxq "$name depends on: oracle:arith, oracle:ring" "$out"
    done
  fi
  if test "$suite" = record_ext; then
    grep -Fxq 'inferred depends only on the foundational kernel' "$out"
    grep -Fxq 'marked depends on: axiom:label_agrees' "$out"
  fi
  if test "$suite" = list_evidence; then
    grep -Fxq 'assembled depends on: oracle:ring' "$out"
    grep -Fxq 'named_hint depends on: axiom:seed' "$out"
  fi
  if "$bin" check --no-cache "bits/tungsten-satori/spec/${suite}_failure.sat" >"$out"; then
    echo "$suite accepted an invalid claim" >&2
    exit 1
  fi
  for name in $rejected; do
    grep -q "^✗ .* (theorem $name):" "$out"
  done
  if test "$suite" = closure; then
    grep -Fxq '  need continuous_at f 0' "$out"
    grep -Fxq '  need f x ≠ g x' "$out"
  fi
  if test "$suite" = finite_cover; then
    grep -Fxq '  need localization.principal_cover R f ids' "$out"
    grep -Fxq '  need ∀ i ∈ ids, ring_ops.powers R (f i) (d i)' "$out"
    grep -Fxq '  need ∀ i ∈ ids, ∀ j ∈ ids, r i j (u i) = s i j (u j)' "$out"
  fi
  if test "$suite" = weak_derivative; then
    grep -Fxq '  need p 2 = 0' "$out"
  fi
  if test "$suite" = polynomial_sign; then
    grep -Fxq '  counterexample x = 1 (0 < 0 is false)' "$out"
    grep -Fxq '  counterexample x = 3/2 (3/2 < 0 is false)' "$out"
  fi
  if test "$suite" = derivation; then
    grep -Fxq '  need ring_ops.monomial R t 5 g = ring_ops.one R' "$out"
  fi
  if test "$suite" = interpolation; then
    grep -Fxq '  proved 1 ≤ 2 * z + 3 * s' "$out"
    grep -Fxq '  need 1 ≠ 2 * z + 3 * s' "$out"
  fi
  if test "$suite" = threshold; then
    grep -Fxq '  proved a ≤ s' "$out"
    test "$(grep -Fxc '  need a ≠ s' "$out")" -eq 1
    grep -Fxq '  need a < s' "$out"
  fi
  if test "$suite" = symplectic_character; then
    grep -Fxq '  need L + 1 = 4 ^ s' "$out"
    grep -Fxq '  need u < L' "$out"
    grep -Fxq '  need ∀ u < 2, ∀ v < 2, (∀ i < 3, word u i = word v i) → u = v' "$out"
  fi
  if test "$suite" = finite_l2; then
    grep -Fxq '  need finite_l2.orthogonal 2 3 K 5' "$out"
    grep -Fxq '  need ∀ i < n, w i * w i ≤ 1' "$out"
  fi
  if test "$suite" = heat_source; then
    grep -A2 '(theorem ignored_source):' "$out" | grep -Fxq '  need ∀ t, 0 ≤ t → t ≤ 1 → heat_interval.work u f 0 1 t ≤ heat_interval.energy q 0 1 t'
    grep -A2 '(theorem source_only):' "$out" | grep -Fxq '  need ∀ t, 0 ≤ t → t ≤ 1 → q t 0 = q t 1'
    grep -Fxq '  need ∀ t, 0 ≤ t → t ≤ 2 → q t 0 = p t 0 ∧ q t 1 = p t 1' "$out"
    grep -A2 '(theorem left_flux_only):' "$out" | grep -Fxq '  need ∀ t, 0 ≤ t → t ≤ 2 → q t 1 = p t 1'
  fi
  if test "$suite" = wave_interval; then
    grep -Fxq '  need ∀ t, 0 ≤ t → t ≤ 2 → wave_interval.flux c v q t 1 = wave_interval.flux c v q t 0' "$out"
  fi
  if test "$suite" = record_ext; then
    grep -Fxq '  need twin.b x = twin.b y' "$out"
    grep -Fxq '  need snd p = snd q' "$out"
  fi
  if test "$suite" = list_evidence; then
    test "$(grep -Fxc '  need marked 2' "$out")" -eq 2
    test "$(grep -Fxc '  need all P xs' "$out")" -eq 2
  fi
  if test "$suite" = affine_gluing; then
    test "$(grep -Fxc '  need r u = s v' "$out")" -eq 2
    grep -Fxq '  need localization.two_open_cover i j r s' "$out"
  fi
done
"$bin" check --no-cache bits/tungsten-satori/examples/symplectic_sign.sat >"$out"
grep -Fxq 'nonzero_matrix depends on: oracle:arith, oracle:ring' "$out"
grep -Fxq 'row_count depends on: oracle:arith, oracle:ring' "$out"
"$bin" check --no-cache bits/tungsten-satori/examples/hadamard_parity.sat >"$out"
grep -Fxq 'three_bits depends on: oracle:arith, oracle:ring' "$out"
"$bin" check --no-cache bits/tungsten-satori/examples/gepner_barrier.sat >"$out"
grep -q '^✓ gepner.no_early_zero : ' "$out"
"$bin" check --no-cache bits/tungsten-satori/examples/rounded_power.sat >"$out"
grep -q '^✓ edge_constant : ' "$out"
"$bin" check --no-cache bits/tungsten-satori/examples/localized_chart.sat >"$out"
grep -q '^✓ chart_unique : ' "$out"
grep -q '^✓ chart_on_cover : ' "$out"
grep -q '^✓ chart_on_finite_cover : ' "$out"
grep -Fxq 'chart_fibre_tangent depends only on the foundational kernel' "$out"
grep -q '^✓ chart_at_zero_branches : ' "$out"
"$bin" check --no-cache bits/tungsten-satori/spec/ring_conjunction.sat >"$out"
for name in mixed repeated_argument combination_pair numeric_pair; do
  grep -q "^✓ $name : .*\[oracle:ring\]$" "$out"
done
if "$bin" check --no-cache bits/tungsten-satori/spec/ring_conjunction_failure.sat >"$out"; then
  echo "ring accepted an unproved conjunct" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 5
for leaf in 'x + 1 = x' 'x * x = x' 'x = y' '0 ≤ x' 'n - m + m = n'; do
  grep -Fxq "  failed conjunct $leaf" "$out"
done
"$bin" check --no-cache bits/tungsten-satori/spec/arithmetic_conjunction.sat >"$out"
grep -q '^✓ cast_bounds : .*\[axiom:lower, axiom:upper, oracle:arith\]$' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/arithmetic_conjunction_failure.sat >"$out"; then
  echo "arithmetic accepted an unproved conjunct" >&2
  exit 1
fi
test "$(grep -c '^✗ ' "$out")" -eq 4
for leaf in 'x < b' 'c * a ≤ c * b' 'a - b + b = a' '0 < x ^ 2'; do
  grep -Fxq "  failed conjunct $leaf" "$out"
done
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
"$bin" check --no-cache bits/tungsten-satori/spec/interval_cases.sat >"$out"
grep -Fxq 'from_hint depends on: axiom:index_bound, oracle:arith' "$out"
grep -Fxq 'unused_hint depends on: oracle:arith' "$out"
grep -Fxq 'unused_after_subst depends only on the foundational kernel' "$out"
if "$bin" check --no-cache bits/tungsten-satori/spec/interval_cases_failure.sat >"$out"; then
  echo "interval_cases accepted an incomplete range" >&2
  exit 1
fi
grep -Fxq '  open case i = 2' "$out"
grep -Fxq '  open case i = 0' "$out"
for name in missing_lower missing_upper dense wide forgot_last unsupported_middle branches open_endpoint; do
  grep -q "^✗ .* (theorem $name):" "$out"
done
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

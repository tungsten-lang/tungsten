#!/usr/bin/env bash
# Harness contract for spec-lane classification by convention.
#
# Drives the shipped classifier (scripts/spec-lanes.sh) without compiling:
# tracked specs classify cleanly; an untagged *_spec.w runs on both engines;
# malformed `# spec:` headers fail closed; a folder-lane spec rejects lane
# words; skips carry reasons; untracked scratch specs never join the suite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFY="$ROOT/scripts/spec-lanes.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-spec-classify.XXXXXX")"
UNTRACKED="$ROOT/spec/zz_untracked_scratch_spec.w"
PARITY_SCRATCH="$ROOT/spec/parity/zz_lane_word_scratch_spec.w"
trap 'rm -rf "$TMP"; rm -f "$UNTRACKED" "$PARITY_SCRATCH"' EXIT INT TERM

cd "$ROOT"

if [[ ! -x "$CLASSIFY" ]]; then
  echo "missing classifier: $CLASSIFY" >&2
  exit 1
fi

expect_ok() {
  local label="$1"; shift
  if ! "$CLASSIFY" "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: $label was rejected" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
  echo "ok: $label"
}

expect_reject() {
  local label="$1" message="$2"; shift 2
  if "$CLASSIFY" "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: $label was accepted" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! grep -Fq "$message" "$TMP/err"; then
    echo "FAIL: $label did not report: $message" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
  echo "ok: $label fails closed"
}

LANES=(compiled interpreter core metal compiled-priority fast-compiled fast-interp)
dump_lanes() {
  # One classifier run per lane, saved to files: piping the classifier into
  # `grep -q` would race SIGPIPE against pipefail.
  local lane
  for lane in "${LANES[@]}"; do
    "$CLASSIFY" --print-lane "$lane" >"$TMP/lane.$lane"
  done
}

lane_of() {
  # Print the lanes FILE lands in, as "compiled interpreter ...".
  local file="$1" lane found=()
  for lane in "${LANES[@]}"; do
    if grep -Fxq "$file" "$TMP/lane.$lane"; then
      found+=("$lane")
    fi
  done
  echo "${found[*]:-}"
}

# --- every tracked spec classifies --------------------------------------------
expect_ok "tracked discovery"
grep -q '^spec lanes: .* classified, .* skipped$' "$TMP/out"
cat "$TMP/out"

"$CLASSIFY" --print-default >"$TMP/default.list"
if [[ ! -s "$TMP/default.list" ]]; then
  echo "FAIL: --print-default emitted no default-lane spec paths" >&2
  exit 1
fi
default_paths=()
while IFS= read -r path; do
  [[ -n "$path" ]] && default_paths+=("$path")
done <"$TMP/default.list"
expect_ok "default-lane file list" --files "${default_paths[@]}"

# --- an untagged spec runs compiled and interpreted ---------------------------
printf '<< 1\n' >"$TMP/untagged_spec.w"
expect_ok "untagged spec" --files "$TMP/untagged_spec.w"
grep -q '^spec lanes: 1 classified, 0 skipped$' "$TMP/out"

# --- malformed headers fail closed --------------------------------------------
printf '# spec: skip\n<< 1\n' >"$TMP/skip_no_reason_spec.w"
expect_reject "skip without a reason" "skip needs text after --" \
  --files "$TMP/skip_no_reason_spec.w"

printf '# spec: compiledd\n<< 1\n' >"$TMP/typo_spec.w"
expect_reject "unknown word" "unknown # spec: word compiledd" \
  --files "$TMP/typo_spec.w"

printf '# spec: skip compiled -- both\n<< 1\n' >"$TMP/skip_combo_spec.w"
expect_reject "skip combined with a lane" "skip cannot combine with compiled" \
  --files "$TMP/skip_combo_spec.w"

printf '# spec: interpreter slow\n<< 1\n' >"$TMP/slow_interp_spec.w"
expect_reject "slow without the compiled wave" "slow only applies to the compiled wave" \
  --files "$TMP/slow_interp_spec.w"

printf '# spec: compiled-rejects\n<< 1\n' >"$TMP/reject_no_text_spec.w"
expect_reject "rejects without expected text" "compiled-rejects needs text after --" \
  --files "$TMP/reject_no_text_spec.w"

# --- a tag below the header is ordinary code, not a directive -----------------
printf '<< 1\n# spec: skip\n' >"$TMP/late_tag_spec.w"
expect_ok "tag after the header block" --files "$TMP/late_tag_spec.w"

# --- folder lanes reject lane words -------------------------------------------
printf '# spec: compiled\n<< 1\n' >"$PARITY_SCRATCH"
expect_reject "lane word on a parity spec" "the parity folder decides this lane" \
  --files "spec/parity/$(basename "$PARITY_SCRATCH")"
rm -f "$PARITY_SCRATCH"

# --- skips carry their reasons ------------------------------------------------
"$CLASSIFY" --print-skips >"$TMP/skips"
if awk -F'\t' 'NF < 2 || $2 == "" { bad = 1 } END { exit !bad }' "$TMP/skips"; then
  echo "FAIL: a skipped spec has no reason" >&2
  exit 1
fi
echo "ok: $(grep -c . "$TMP/skips" || true) skips, each with a reason"

# --- known lanes still derive from tags ----------------------------------------
dump_lanes
check_lanes() {
  local file="$1" want="$2" got
  got="$(lane_of "$file")"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $file lanes [$got], expected [$want]" >&2
    exit 1
  fi
  echo "ok: $file -> $want"
}
check_lanes spec/compiler/date_invalid_constructor.w ""
check_lanes compiler/test/regex_features.w "compiled interpreter compiled-priority"

# --- git-style discovery ignores an untracked scratch spec --------------------
printf '<< "untracked scratch must not change the suite"\n' >"$UNTRACKED"
if git ls-files --error-unmatch "$UNTRACKED" >/dev/null 2>&1; then
  echo "FAIL: scratch spec is tracked; discovery test is invalid" >&2
  exit 1
fi
"$CLASSIFY" --print-lane compiled >"$TMP/compiled.list"
if grep -Fq "zz_untracked_scratch_spec.w" "$TMP/compiled.list"; then
  echo "FAIL: untracked scratch spec changed discovery" >&2
  exit 1
fi
echo "ok: untracked scratch spec ignored"

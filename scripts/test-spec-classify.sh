#!/usr/bin/env bash
# Harness contract for spec-lane classification.
#
# Drives the shipped classifier (scripts/spec-lanes.sh) without compiling:
# every current default-lane spec/**/*_spec.w is classified; one extra
# unlisted *_spec.w is unclassified and fails closed; git-style discovery
# ignores an untracked scratch spec.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFY="$ROOT/scripts/spec-lanes.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-spec-classify.XXXXXX")"
UNTRACKED="$ROOT/spec/zz_untracked_scratch_spec.w"
trap 'rm -rf "$TMP"; rm -f "$UNTRACKED"' EXIT INT TERM

cd "$ROOT"

if [[ ! -x "$CLASSIFY" ]]; then
  echo "missing classifier: $CLASSIFY" >&2
  exit 1
fi

# --- supplied file list: every current default-lane path is classified -----
"$CLASSIFY" --print-default >"$TMP/default.list"
if [[ ! -s "$TMP/default.list" ]]; then
  echo "FAIL: --print-default emitted no default-lane spec paths" >&2
  exit 1
fi
# The classifier must accept the list as arguments (not only via discovery).
# bash 3.2 has no mapfile; load the paths explicitly.
default_paths=()
while IFS= read -r path; do
  [[ -n "$path" ]] && default_paths+=("$path")
done <"$TMP/default.list"
"$CLASSIFY" --files "${default_paths[@]}" >"$TMP/default.out" 2>"$TMP/default.err"
if [[ -s "$TMP/default.err" ]]; then
  echo "FAIL: default-lane file list reported unclassified paths" >&2
  cat "$TMP/default.err" >&2
  exit 1
fi
grep -q '^spec lanes: .* classified$' "$TMP/default.out"
echo "default-lane files: $(wc -l <"$TMP/default.list" | tr -d ' ')"
cat "$TMP/default.out"

# --- one extra unlisted *_spec.w fails closed ------------------------------
printf '<< 1\n' >"$TMP/extra_unlisted_spec.w"
set +e
"$CLASSIFY" --files "${default_paths[@]}" "$TMP/extra_unlisted_spec.w" \
  >"$TMP/extra.out" 2>"$TMP/extra.err"
extra_status=$?
set -e
if [[ "$extra_status" -eq 0 ]]; then
  echo "FAIL: extra unlisted *_spec.w was classified" >&2
  cat "$TMP/extra.out" >&2
  exit 1
fi
grep -q '^unclassified specs:$' "$TMP/extra.err"
grep -Fq "$TMP/extra_unlisted_spec.w" "$TMP/extra.err"
grep -q 'classify each as a default lane, an opt-in gate, or an explicit exclude' \
  "$TMP/extra.err"
echo "extra unlisted exit=$extra_status"
cat "$TMP/extra.err"

# --- git-style discovery ignores an untracked scratch spec -----------------
printf '<< "untracked scratch must not change the suite"\n' >"$UNTRACKED"
if git ls-files --error-unmatch "$UNTRACKED" >/dev/null 2>&1; then
  echo "FAIL: scratch spec is tracked; discovery test is invalid" >&2
  exit 1
fi
"$CLASSIFY" >"$TMP/discover.out" 2>"$TMP/discover.err"
if [[ -s "$TMP/discover.err" ]]; then
  echo "FAIL: tracked discovery reported unclassified specs" >&2
  cat "$TMP/discover.err" >&2
  exit 1
fi
if grep -Fq "zz_untracked_scratch_spec.w" "$TMP/discover.out" \
   || grep -Fq "zz_untracked_scratch_spec.w" "$TMP/discover.err"; then
  echo "FAIL: untracked scratch spec changed discovery" >&2
  exit 1
fi
grep -q '^spec lanes: .* classified$' "$TMP/discover.out"
echo "discovery ignored untracked $UNTRACKED"
cat "$TMP/discover.out"

echo "spec-classify: PASS"

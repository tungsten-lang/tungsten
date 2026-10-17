#!/usr/bin/env bash
# Spec lanes by convention: a spec's folder and its own header decide where
# it runs. There is no central list.
#
# Discovery is tracked-only, so uncommitted scratch specs never change the
# suite. A spec is any tracked spec/**/*_spec.w, any tracked
# bits/tungsten-{wassat,wrat}/spec/*_spec.w, or any other tracked .w file
# whose header carries a `# spec:` line.
#
# Folders:
#   spec/parity/                cross-engine transcript diff (scripts/parity.sh)
#   spec/api/                   API contract lane (RUN_API_SPECS=1)
#   bits/tungsten-wassat/spec/  wassat lane (rake spec:bits)
#   bits/tungsten-wrat/spec/    wrat lane (rake spec:bits)
#   everything else             compiled and interpreted
#
# Header lines, anywhere in the comment block at the top of the file:
#   # spec: skip -- REASON                  never runs; the reason is required
#   # spec: compiled [-- why]               compiled only
#   # spec: interpreter [-- why]            interpreted only
#   # spec: core                            compiled, opt-in (RUN_CORE_SPECS=1)
#   # spec: metal                           Metal hardware, opt-in (RUN_METAL_SPECS=1)
#   # spec: cuda-emit | wgsl-emit | cuda-reject   GPU dialect emission checks
#   # spec: compiled-rejects -- TEXT        compiled run must fail with TEXT
#   # spec: interpreter-rejects -- TEXT     interpreted run must fail with TEXT
#   # spec: slow                            schedule first in the compiled wave
#   # spec: fast                            also in the FAST=1 slice, per engine
# Lane words combine, as in `# spec: core interpreter`. Classification fails
# closed on an unknown word, a skip without a reason, or a lane word on a spec
# whose folder already decides its lane.
#
# Usage:
#   scripts/spec-lanes.sh                    validate every tracked spec
#   scripts/spec-lanes.sh --files PATH...    validate the given files
#   scripts/spec-lanes.sh --print-default
#   scripts/spec-lanes.sh --print-lane LANE
#   scripts/spec-lanes.sh --print-skips      skipped specs and their reasons

spec_normalize_path() {
  local path="$1"
  local root="${SPEC_LANES_ROOT:-}"
  path="${path#./}"
  if [[ -n "$root" && "$path" == "$root/"* ]]; then
    path="${path#"$root"/}"
  fi
  printf '%s\n' "$path"
}

spec_discover_tracked() {
  {
    git ls-files -- 'spec/*_spec.w' \
      'bits/tungsten-wassat/spec/*_spec.w' 'bits/tungsten-wrat/spec/*_spec.w'
    # Header-tagged files elsewhere; spec_scan drops any whose match is not in
    # the leading comment block.
    git grep -l -E '^#[[:space:]]*spec:' -- '*.w' 2>/dev/null || true
  } | LC_ALL=C sort -u
}

# Read each file's leading comment block and print one row per lane:
#   PATH<TAB>LANE[<TAB>TEXT]
# LANE is a lane name, `exclude` (TEXT = reason), or `!` (TEXT = error).
spec_scan() {
  local path
  local -a files=()
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      files+=("$path")
    else
      printf '%s\t!\tfile not found\n' "$path"
    fi
  done
  [[ ${#files[@]} -eq 0 ]] && return 0
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function reset() {
      split("", has); err = ""; skip_reason = ""; crej = ""; irej = ""
      tagged = 0; in_header = 1
    }
    function fail(msg) { if (err == "") err = msg }
    function emit(lane, text) {
      if (text == "") printf "%s\t%s\n", path, lane
      else printf "%s\t%s\t%s\n", path, lane, text
    }
    function flush(   folder, w, nlanes, lanes_compiled, lanes_interp) {
      if (path == "") return
      if (path !~ /_spec\.w$/ && !tagged) return
      folder = ""
      if (path ~ /^spec\/parity\//) folder = "parity"
      else if (path ~ /^spec\/api\//) folder = "api"
      else if (path ~ /^bits\/tungsten-wassat\/spec\//) folder = "wassat"
      else if (path ~ /^bits\/tungsten-wrat\/spec\//) folder = "wrat"
      if (err != "") { emit("!", err); return }
      if ("skip" in has) {
        for (w in has) if (w != "skip") { emit("!", "skip cannot combine with " w); return }
        emit("exclude", skip_reason); return
      }
      if (folder != "") {
        for (w in has) { emit("!", "the " folder " folder decides this lane; remove " w); return }
        emit(folder, ""); return
      }
      nlanes = 0
      if ("compiled" in has)            { emit("compiled", ""); nlanes++; lanes_compiled = 1 }
      if ("interpreter" in has)         { emit("interpreter", ""); nlanes++; lanes_interp = 1 }
      if ("core" in has)                { emit("core", ""); nlanes++ }
      if ("metal" in has)               { emit("metal", ""); nlanes++ }
      if ("cuda-emit" in has)           { emit("cuda-emit", ""); nlanes++ }
      if ("wgsl-emit" in has)           { emit("wgsl-emit", ""); nlanes++ }
      if ("cuda-reject" in has)         { emit("cuda-reject", ""); nlanes++ }
      if ("compiled-rejects" in has)    { emit("compiled-reject", ""); nlanes++ }
      if ("interpreter-rejects" in has) { emit("interpreter-reject", ""); nlanes++ }
      if (nlanes == 0) {
        emit("compiled", ""); emit("interpreter", "")
        lanes_compiled = 1; lanes_interp = 1
      }
      if ("slow" in has) {
        if (lanes_compiled) emit("compiled-priority", "")
        else emit("!", "slow only applies to the compiled wave")
      }
      if ("fast" in has) {
        if (lanes_compiled) emit("fast-compiled", "")
        if (lanes_interp) emit("fast-interp", "")
        if (!lanes_compiled && !lanes_interp) emit("!", "fast needs a compiled or interpreted lane")
      }
    }
    FNR == 1 { flush(); path = FILENAME; reset() }
    !in_header { next }
    !/^[ \t]*(#|$)/ { in_header = 0; next }
    /^#[ \t]*spec:/ {
      tagged = 1
      v = $0; sub(/^#[ \t]*spec:[ \t]*/, "", v)
      text = ""
      p = index(v, "--")
      if (p > 0) { text = trim(substr(v, p + 2)); v = substr(v, 1, p - 1) }
      n = split(v, words, " ")
      if (n == 0) { fail("empty # spec: line"); next }
      takes_text = 0; needs_text = ""
      for (i = 1; i <= n; i++) {
        w = words[i]
        if (w !~ /^(skip|compiled|interpreter|core|metal|cuda-emit|wgsl-emit|cuda-reject|compiled-rejects|interpreter-rejects|slow|fast)$/) {
          fail("unknown # spec: word " w); next
        }
        has[w] = 1
        if (w == "skip" || w ~ /-rejects$/) needs_text = w
        if (w == "skip" || w == "compiled" || w == "interpreter" || w ~ /-rejects$/) takes_text = 1
      }
      if (needs_text != "" && text == "") { fail(needs_text " needs text after --"); next }
      if (needs_text ~ /-rejects$/ && n != 1) { fail(needs_text " must be alone on its line"); next }
      if (text != "" && !takes_text) { fail("text after -- only follows skip, compiled, interpreter, or a -rejects word"); next }
      if (needs_text == "skip") skip_reason = text
      if (needs_text == "compiled-rejects") crej = text
      if (needs_text == "interpreter-rejects") irej = text
    }
    END { flush() }
  ' "${files[@]}"
}

# Text after `--` on a file's `# spec: WORD -- TEXT` line, such as the
# expected diagnostic of a -rejects spec.
spec_header_text() {
  local path="$1" word="$2"
  awk -v want="$word" '
    !/^[ \t]*(#|$)/ { exit }
    /^#[ \t]*spec:/ {
      v = $0; sub(/^#[ \t]*spec:[ \t]*/, "", v)
      p = index(v, "--"); if (p == 0) next
      w = substr(v, 1, p - 1); gsub(/[ \t]+/, "", w)
      if (w != want) next
      t = substr(v, p + 2); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      print t; exit
    }
  ' "$path"
}

spec_reset_lanes() {
  compiled_specs=(); compiled_priority_specs=(); compiled_reject_specs=()
  cuda_emit_specs=(); wgsl_emit_specs=(); cuda_reject_specs=()
  interpreter_specs=(); interpreter_reject_specs=()
  core_specs=(); metal_specs=(); api_specs=(); parity_specs=()
  wassat_specs=(); wrat_specs=(); fast_compiled=(); fast_interp=()
  exclude_specs=(); spec_skip_rows=(); spec_errors=()
}

# Fill the lane arrays from scan rows on stdin.
spec_load_rows() {
  local path lane text
  while IFS=$'\t' read -r path lane text; do
    case "$lane" in
      compiled) compiled_specs+=("$path") ;;
      compiled-priority) compiled_priority_specs+=("$path") ;;
      compiled-reject) compiled_reject_specs+=("$path") ;;
      cuda-emit) cuda_emit_specs+=("$path") ;;
      wgsl-emit) wgsl_emit_specs+=("$path") ;;
      cuda-reject) cuda_reject_specs+=("$path") ;;
      interpreter) interpreter_specs+=("$path") ;;
      interpreter-reject) interpreter_reject_specs+=("$path") ;;
      core) core_specs+=("$path") ;;
      metal) metal_specs+=("$path") ;;
      api) api_specs+=("$path") ;;
      parity) parity_specs+=("$path") ;;
      wassat) wassat_specs+=("$path") ;;
      wrat) wrat_specs+=("$path") ;;
      fast-compiled) fast_compiled+=("$path") ;;
      fast-interp) fast_interp+=("$path") ;;
      exclude) exclude_specs+=("$path"); spec_skip_rows+=("$path"$'\t'"$text") ;;
      '!') spec_errors+=("$path: $text") ;;
    esac
  done
}

spec_build_tracked_lanes() {
  local -a tracked=()
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] && tracked+=("$path")
  done < <(spec_discover_tracked)
  spec_reset_lanes
  spec_load_rows < <(spec_scan ${tracked[@]+"${tracked[@]}"})
}

spec_emit_classified_paths() {
  local path
  for path in \
    "${compiled_specs[@]+"${compiled_specs[@]}"}" \
    "${compiled_reject_specs[@]+"${compiled_reject_specs[@]}"}" \
    "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" \
    "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" \
    "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" \
    "${interpreter_specs[@]+"${interpreter_specs[@]}"}" \
    "${interpreter_reject_specs[@]+"${interpreter_reject_specs[@]}"}" \
    "${core_specs[@]+"${core_specs[@]}"}" \
    "${metal_specs[@]+"${metal_specs[@]}"}" \
    "${api_specs[@]+"${api_specs[@]}"}" \
    "${parity_specs[@]+"${parity_specs[@]}"}" \
    "${wassat_specs[@]+"${wassat_specs[@]}"}" \
    "${wrat_specs[@]+"${wrat_specs[@]}"}" \
    "${exclude_specs[@]+"${exclude_specs[@]}"}"
  do
    printf '%s\n' "$path"
  done
}

spec_emit_default_spec_w() {
  local path
  for path in \
    "${compiled_specs[@]+"${compiled_specs[@]}"}" \
    "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" \
    "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" \
    "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" \
    "${interpreter_specs[@]+"${interpreter_specs[@]}"}"
  do
    case "$path" in
      spec/*_spec.w) printf '%s\n' "$path" ;;
    esac
  done
}

spec_print_lane() {
  local lane="$1"
  case "$lane" in
    compiled)
      printf '%s\n' "${compiled_specs[@]+"${compiled_specs[@]}"}" ;;
    compiled-priority)
      printf '%s\n' "${compiled_priority_specs[@]+"${compiled_priority_specs[@]}"}" ;;
    compiled-reject)
      printf '%s\n' "${compiled_reject_specs[@]+"${compiled_reject_specs[@]}"}" ;;
    cuda|cuda-emit)
      printf '%s\n' "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" ;;
    wgsl|wgsl-emit)
      printf '%s\n' "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" ;;
    cuda-reject)
      printf '%s\n' "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" ;;
    interpreter|interp)
      printf '%s\n' "${interpreter_specs[@]+"${interpreter_specs[@]}"}" ;;
    interpreter-reject|interp-reject)
      printf '%s\n' "${interpreter_reject_specs[@]+"${interpreter_reject_specs[@]}"}" ;;
    core)
      printf '%s\n' "${core_specs[@]+"${core_specs[@]}"}" ;;
    metal)
      printf '%s\n' "${metal_specs[@]+"${metal_specs[@]}"}" ;;
    api)
      printf '%s\n' "${api_specs[@]+"${api_specs[@]}"}" ;;
    parity)
      printf '%s\n' "${parity_specs[@]+"${parity_specs[@]}"}" ;;
    wassat)
      printf '%s\n' "${wassat_specs[@]+"${wassat_specs[@]}"}" ;;
    wrat)
      printf '%s\n' "${wrat_specs[@]+"${wrat_specs[@]}"}" ;;
    exclude)
      printf '%s\n' "${exclude_specs[@]+"${exclude_specs[@]}"}" ;;
    skips)
      printf '%s\n' "${spec_skip_rows[@]+"${spec_skip_rows[@]}"}" ;;
    fast-compiled)
      printf '%s\n' "${fast_compiled[@]+"${fast_compiled[@]}"}" ;;
    fast-interp)
      printf '%s\n' "${fast_interp[@]+"${fast_interp[@]}"}" ;;
    default)
      spec_emit_default_spec_w | LC_ALL=C sort -u ;;
    *)
      echo "unknown spec lane: $lane" >&2
      return 2
      ;;
  esac
}

spec_report() {
  local count="$1"
  if [[ ${#spec_errors[@]} -gt 0 ]]; then
    echo "spec headers with errors:" >&2
    printf '  %s\n' "${spec_errors[@]}" >&2
    echo 'fix each `# spec:` line; see the top of scripts/spec-lanes.sh' >&2
    return 1
  fi
  printf 'spec lanes: %s classified, %s skipped\n' "$count" "${#exclude_specs[@]}"
}

# Validate PATH..., or report on the tracked lanes already built.
spec_classify_files() {
  local path count
  local -a paths=()
  if [[ $# -eq 0 ]]; then
    spec_classify_tracked
    return
  fi
  for path in "$@"; do
    paths+=("$(spec_normalize_path "$path")")
  done
  spec_reset_lanes
  spec_load_rows < <(spec_scan "${paths[@]}")
  count="$(spec_emit_classified_paths | LC_ALL=C sort -u | grep -c . || true)"
  spec_report "$count"
}

spec_classify_tracked() {
  local count
  count="$(spec_emit_classified_paths | LC_ALL=C sort -u | grep -c . || true)"
  spec_report "$count"
}

spec_lanes_main() {
  case "${1:-}" in
    --files)
      shift
      spec_classify_files "$@"
      ;;
    --print-default)
      spec_print_lane default
      ;;
    --print-lane)
      shift
      spec_print_lane "${1:-}"
      ;;
    --print-skips)
      spec_print_lane skips
      ;;
    --help|-h)
      echo "Usage: spec-lanes.sh [--files PATH...] [--print-default] [--print-lane LANE] [--print-skips]"
      ;;
    "")
      spec_classify_tracked
      ;;
    *)
      echo "Usage: spec-lanes.sh [--files PATH...] [--print-default] [--print-lane LANE] [--print-skips]" >&2
      return 2
      ;;
  esac
}

# Sourcing builds the tracked lanes unless SPEC_LANES_SKIP_BUILD=1, which
# loads only the functions (test-specs.sh workers need spec_header_text).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  SPEC_LANES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$SPEC_LANES_ROOT"
  spec_build_tracked_lanes
  spec_lanes_main "$@"
elif [[ "${SPEC_LANES_SKIP_BUILD:-0}" != "1" ]]; then
  spec_build_tracked_lanes
fi

#!/usr/bin/env bash

# Print the complete source set that can affect the stage-1 compiler. Its lexer
# imports helpers from languages/tungsten/lexers, and its loader can lazily
# autoload pure-Tungsten core classes. Computing a narrower core closure would
# require loading/parsing before the cache lookup that this list supports.
bootstrap_stage1_source_inputs() {
  local root="$1"
  local compiler_w="$2"
  local lex64_table="$3"

  printf '%s\n' "$compiler_w" "$lex64_table"
  find "$root/compiler/lib" -type f -name '*.w' -print | LC_ALL=C sort
  find "$root/core" -type f -name '*.w' -print | LC_ALL=C sort
  find "$root/languages/tungsten/lexers" \
    -type f -name '*.w' -print | LC_ALL=C sort
}

# Hash all stage-1 sources in one utility invocation. Besides being
# deterministic, this avoids paying one process launch per core source on every
# cache lookup.
bootstrap_stage1_source_manifest() {
  local root="$1"
  local compiler_w="$2"
  local lex64_table="$3"
  local source_path
  local inputs=()
  local relative_inputs=()
  local external_inputs=()

  while IFS= read -r source_path; do inputs+=("$source_path"); done < <(
    bootstrap_stage1_source_inputs "$root" "$compiler_w" "$lex64_table"
  )
  for source_path in "${inputs[@]}"; do
    case "$source_path" in
      "$root"/*) relative_inputs+=("${source_path#"$root"/}") ;;
      *)
        # Env overrides (e.g. TUNGSTEN_LEX64_TABLE) may legitimately point
        # outside the repository. Content-hash them under a stable
        # `external:` label instead of failing; a missing file still errors.
        if [ ! -f "$source_path" ]; then
          printf 'error: stage-1 source does not exist: %s\n' \
            "$source_path" >&2
          return 1
        fi
        external_inputs+=("$source_path")
        ;;
    esac
  done

  (
    cd "$root"
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "${relative_inputs[@]}"
    elif command -v sha256sum >/dev/null 2>&1; then
      sha256sum "${relative_inputs[@]}"
    else
      openssl dgst -sha256 "${relative_inputs[@]}"
    fi
  )
  # bash 3.2 (the macOS system shell) errors on "${arr[@]}" for an empty array
  # under `set -u`; guard the expansion so an empty external set is not fatal.
  for source_path in ${external_inputs[@]+"${external_inputs[@]}"}; do
    if command -v shasum >/dev/null 2>&1; then
      printf 'external:%s:%s\n' "$(basename "$source_path")" \
        "$(shasum -a 256 "$source_path" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
      printf 'external:%s:%s\n' "$(basename "$source_path")" \
        "$(sha256sum "$source_path" | awk '{print $1}')"
    else
      printf 'external:%s:%s\n' "$(basename "$source_path")" \
        "$(openssl dgst -sha256 "$source_path" | awk '{print $NF}')"
    fi
  done
}

# A successful compiler process is not enough: callers need an executable
# artifact before publishing it into the bootstrap cache.
bootstrap_require_executable() {
  local artifact="$1"
  local log_path="$2"
  local label="${3:-command}"

  if [ -x "$artifact" ]; then
    return 0
  fi

  if [ -f "$log_path" ]; then
    cat "$log_path" >&2
  else
    printf '(no log was written at %s)\n' "$log_path" >&2
  fi
  printf 'error: %s returned success but produced no executable at %s (log: %s)\n' \
    "$label" "$artifact" "$log_path" >&2
  return 1
}

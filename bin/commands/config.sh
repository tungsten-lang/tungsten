#!/usr/bin/env bash

# Minimal, dependency-free reader for ~/.tungsten/config. The format is the
# INI/TOML-compatible subset Tungsten documents: [section] followed by
# key = value pairs. Keeping this in shell lets doctor/bootstrap work on a
# fresh clone without Ruby, Python, jq, or a compiled Tungsten binary.

tungsten_config_path() {
  if [ -n "${TUNGSTEN_CONFIG:-}" ]; then
    printf '%s\n' "$TUNGSTEN_CONFIG"
  elif [ -n "${HOME:-}" ]; then
    printf '%s/.tungsten/config\n' "$HOME"
  fi
}

tungsten_config_get() {
  local wanted_section="$1" wanted_key="$2" config_path
  config_path="$(tungsten_config_path)"
  [ -n "$config_path" ] && [ -f "$config_path" ] || return 1

  awk -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*\[/ {
      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*([#;].*)?$/, "", section)
      section = trim(section)
      next
    }
    section == wanted_section && index($0, "=") > 0 {
      key = substr($0, 1, index($0, "=") - 1)
      key = trim(key)
      if (key != wanted_key) next
      value = substr($0, index($0, "=") + 1)
      sub(/[[:space:]]+[#;].*$/, "", value)
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$config_path"
}

tungsten_load_build_config() {
  if [ -z "${TUNGSTEN_CPU:-}" ]; then
    tungsten_config_cpu="$(tungsten_config_get build cpu 2>/dev/null || true)"
    if [ -n "$tungsten_config_cpu" ]; then
      export TUNGSTEN_CPU="$tungsten_config_cpu"
    fi
    unset tungsten_config_cpu
  fi
  if [ -z "${TUNGSTEN_CC:-}" ]; then
    tungsten_config_cc="$(tungsten_config_get build cc 2>/dev/null || true)"
    if [ -n "$tungsten_config_cc" ]; then
      export TUNGSTEN_CC="$tungsten_config_cc"
    fi
    unset tungsten_config_cc
  fi
}

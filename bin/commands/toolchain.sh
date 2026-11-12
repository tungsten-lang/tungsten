#!/usr/bin/env bash
# bin/commands/toolchain.sh: which C compiler builds Tungsten's C (the
# runtime, the stage-0 VM) and links its programs, for the parts of the
# toolchain written in shell or run before a compiler exists: bootstrap,
# doctor, and bin/commands/build.w (which asks this script). The compiler
# applies the same rule to every program it links (host_c_compiler in
# compiler/lib/target.w); scripts/test-host-cc-rule.sh keeps the two in step,
# so the compiler's own runtime and user programs are built by one clang.
#
# The rule:
#   1. TUNGSTEN_CC when set (bin/tungsten exports ~/.tungsten/config's
#      [build] cc into it);
#   2. otherwise the first LLVM clang of major version 22 or newer among
#        clang-N on PATH, highest N first (apt.llvm.org, distro packages),
#        Homebrew's llvm (its newest LLVM),
#        Homebrew's versioned llvm@N, highest N first;
#      Apple's clang numbers its versions differently and never counts;
#   3. otherwise plain `clang`.
#
# Usage:
#   toolchain.sh cc        print the selected C compiler
#   toolchain.sh major CC  print CC's LLVM major version (empty if unknown)
# Sourced, it only defines the functions.

# Highest clang-N probed on PATH (the same constant as host_c_compiler's). A
# newer one is still found through Homebrew or TUNGSTEN_CC.
TUNGSTEN_CLANG_NEWEST_MAJOR=40
TUNGSTEN_CLANG_MIN_MAJOR=22

# LLVM major version of a clang, from its --version banner ("clang version
# 23.1.5", "Ubuntu clang version 22.1.8"); empty for Apple clang or anything
# unrecognised.
tungsten_clang_major() {
  local banner
  banner="$("$1" --version 2>/dev/null | head -n 1)" || return 0
  case "$banner" in
    Apple*|"") return 0 ;;
  esac
  printf '%s\n' "$banner" | sed -n 's/.*clang version \([0-9][0-9]*\)\..*/\1/p'
}

tungsten_clang_ok() {
  local major
  major="$(tungsten_clang_major "$1")"
  case "$major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$major" -ge "$TUNGSTEN_CLANG_MIN_MAJOR" ]
}

tungsten_select_cc() {
  local v candidate prefix brew_root dir
  if [ -n "${TUNGSTEN_CC:-}" ]; then
    printf '%s\n' "$TUNGSTEN_CC"
    return 0
  fi
  v="$TUNGSTEN_CLANG_NEWEST_MAJOR"
  while [ "$v" -ge "$TUNGSTEN_CLANG_MIN_MAJOR" ]; do
    candidate="$(command -v "clang-$v" 2>/dev/null || true)"
    if [ -n "$candidate" ] && tungsten_clang_ok "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    v=$((v - 1))
  done
  if command -v brew >/dev/null 2>&1; then
    prefix="$(brew --prefix llvm 2>/dev/null || true)"
    if [ -n "$prefix" ] && [ -x "$prefix/bin/clang" ] && tungsten_clang_ok "$prefix/bin/clang"; then
      printf '%s\n' "$prefix/bin/clang"
      return 0
    fi
    brew_root="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$brew_root" ]; then
      for dir in $(ls -d "$brew_root"/opt/llvm@* 2>/dev/null | sed 's/.*llvm@//' | grep -E '^[0-9]+$' | sort -rn); do
        candidate="$brew_root/opt/llvm@$dir/bin/clang"
        if [ -x "$candidate" ] && tungsten_clang_ok "$candidate"; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
    fi
  fi
  printf 'clang\n'
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  case "${1:-}" in
    cc) tungsten_select_cc ;;
    major) tungsten_clang_major "${2:?usage: toolchain.sh major CC}" ;;
    *)
      printf 'usage: toolchain.sh cc | major CC\n' >&2
      exit 2
      ;;
  esac
fi

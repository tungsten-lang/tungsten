#!/usr/bin/env bash
# bin/commands/store.sh: the build store, for the parts of the toolchain that
# run before any compiler exists (the launcher, the worktree hook, bootstrap,
# doctor, the cache sweep). The compiled side implements the same policy in
# compiler/lib/driver/link.w (compiler_cache_dir) and bin/commands/build.w.
#
# One store is shared by every checkout, worktree and installed toolchain of
# a user, so identical work is done once:
#
#   TUNGSTEN_BUILD_STORE   the store root, when set
#   TUNGSTEN_HOME/build    otherwise
#   HOME/.tungsten/build   otherwise (the toolchain root stands in for a
#                          missing HOME, as bin/tungsten's TUNGSTEN_HOME does)
#
#   <store>/compile/       the compiler's incremental artifacts; exactly this
#                          directory is replaced by TUNGSTEN_CACHE_DIR
#   <store>/stages/        stage-0 VMs, stage compilers, build runtime archives
#   <store>/compilers/     finished compilers, their images, by-source/ index
#   <store>/bits/          bit executables
#
# Usage:
#   store.sh dir [ROOT]                   print the store root
#   store.sh cache-dir [ROOT]             print the compiler cache directory
#   store.sh compiler-fingerprint ROOT    print the fingerprint of the sources
#                                         ROOT's compiler is built from
#   store.sh install-compiler ROOT        if ROOT has no compiler of its own,
#                                         install the one the store holds for
#                                         exactly its sources (never another)
#   store.sh tuning-environment           print the TUNGSTEN_* switches in the
#                                         environment that change what a build
#                                         produces (part of every shared key)
#   store.sh clear-cache [ROOT]           what `tungsten --clear-cache` does
#   store.sh wipe [ROOT]                  what `tungsten cleanup --all` does
# Sourced, it only defines the functions.

tungsten_store_dir() {
  if [ -n "${TUNGSTEN_BUILD_STORE:-}" ]; then
    printf '%s\n' "$TUNGSTEN_BUILD_STORE"
  elif [ -n "${TUNGSTEN_HOME:-}" ]; then
    printf '%s/build\n' "$TUNGSTEN_HOME"
  elif [ -n "${HOME:-}" ]; then
    printf '%s/.tungsten/build\n' "$HOME"
  else
    printf '%s/.tungsten/build\n' "${1:-.}"
  fi
}

tungsten_cache_dir() {
  if [ -n "${TUNGSTEN_CACHE_DIR:-}" ]; then
    printf '%s\n' "$TUNGSTEN_CACHE_DIR"
  else
    printf '%s/compile\n' "$(tungsten_store_dir "${1:-.}")"
  fi
}

tungsten_store_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    openssl dgst -sha256 -r "$@"
  fi
}

# Every source the compiler and its images are built from, by content under
# its checkout-relative name: the compiler and its driver and image wrappers,
# core, the lexers and their table, the unit data, the C runtime it links, and
# the stage-0 VM that starts the bootstrap. Two checkouts print the same
# fingerprint exactly when all of those files are identical, wherever the
# checkouts are. `tungsten build` records the compiler it verified under this
# fingerprint; install-compiler looks a checkout's fingerprint up.
tungsten_compiler_fingerprint() {
  local root="$1"
  (
    cd "$root" 2>/dev/null || exit 1
    [ -f compiler/tungsten.w ] && [ -f core/tungsten.w ] || exit 1
    {
      find compiler -maxdepth 1 -type f -name '*.w' -print
      find compiler/lib core languages/tungsten/lexers -type f -name '*.w' -print 2>/dev/null
      find runtime -path runtime/tests -prune -o -type f \
        \( -name '*.c' -o -name '*.h' -o -name '*.inc' -o -name '*.m' \) -print
      find implementations/c/src implementations/c/include -type f \
        \( -name '*.c' -o -name '*.h' -o -name '*.inc' \) -print 2>/dev/null
      for path in implementations/c/Makefile languages/tungsten/tungsten.lex64 \
                  data/unit_names.txt data/units.tsv; do
        if [ -f "$path" ]; then printf '%s\n' "$path"; fi
      done
    } | LC_ALL=C sort | tr '\n' '\0' | xargs -0 sh -c '
        if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
        elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
        else openssl dgst -sha256 -r "$@"; fi' sh |
      { printf 'tungsten-compiler-source-v1 %s\n' "$(uname -sm)"; cat; } |
      tungsten_store_sha256 | awk '{print $1}'
  )
}

# Copy a store entry into a checkout: a clone where the filesystem makes one
# (APFS `cp -c`), else a plain copy; through a temp file and a rename, so a
# running destination keeps its inode and a reader never sees part of a file.
tungsten_store_copy() {
  local src="$1" dst="$2" tmp
  tmp="$dst.$$.tmp"
  if { cp -c -p "$src" "$tmp" 2>/dev/null || cp -p "$src" "$tmp"; } && mv -f "$tmp" "$dst"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# A fresh worktree has no compiler: bin/tungsten-compiler is not tracked. This
# gives it the one the store holds for exactly its sources, with that
# compiler's images, or nothing (then `bin/tungsten build` or `bootstrap`
# builds it and adds it to the store). It replaces the old hook that linked
# whatever compiler another worktree had, whatever sources that was built
# from. A compiler already installed as a real file is never touched; a
# symlink left by the old hook is replaced when the store has a match.
tungsten_install_store_compiler() {
  local root="$1" dest store fp record id src kind key image field
  dest="$root/bin/tungsten-compiler"
  if [ -x "$dest" ] && [ ! -L "$dest" ]; then
    return 0
  fi
  fp="$(tungsten_compiler_fingerprint "$root")" || return 0
  [ -n "$fp" ] || return 0
  store="$(tungsten_store_dir "$root")"
  record="$store/compilers/by-source/$fp"
  [ -f "$record" ] || return 0
  [ "$(head -n 1 "$record")" = "tungsten-compiler-record-v1" ] || return 0
  id="$(sed -n 's/^compiler=//p' "$record" | head -n 1)"
  case "$id" in
    ''|*[!0-9a-f]*) return 0 ;;
  esac
  src="$store/compilers/$id"
  [ -f "$src" ] && [ -x "$src" ] || return 0
  if [ ! -f "$src.sidemap" ] && [ ! -f "$src.sidemap.missing" ]; then
    return 0
  fi

  mkdir -p "$root/bin" "$root/build/compiler-images" || return 0
  tungsten_store_copy "$src" "$dest" || return 0
  # Newer than anything built here with a previous compiler.
  chmod 755 "$dest" 2>/dev/null || true
  touch "$dest" 2>/dev/null || true
  if [ -f "$src.sidemap" ]; then
    tungsten_store_copy "$src.sidemap" "$dest.sidemap" || true
  else
    rm -f "$dest.sidemap"
  fi
  for kind in repl metal; do
    key="$(sed -n "s/^$kind=//p" "$record" | head -n 1)"
    case "$key" in
      ''|*[!0-9a-f]*) continue ;;
    esac
    image="$store/compilers/image-$kind-$key"
    if [ -x "$image" ] && { [ -f "$image.sidemap" ] || [ -f "$image.sidemap.missing" ]; }; then
      tungsten_store_copy "$image" "$root/build/compiler-images/tungsten-$kind" || continue
      if [ -f "$image.sidemap" ]; then
        tungsten_store_copy "$image.sidemap" "$root/build/compiler-images/tungsten-$kind.sidemap" || true
      else
        rm -f "$root/build/compiler-images/tungsten-$kind.sidemap"
      fi
      touch "$image" 2>/dev/null || true
    fi
  done
  # The record of what is installed here (bin/commands/build.w reads it).
  {
    printf 'tungsten-compiler-build-v1\n'
    printf 'compiler_sha256=%s\n' "$(tungsten_store_sha256 "$dest" | awk '{print $1}')"
    printf 'installable=0\nverified=1\n'
    for field in release cpu debug pgo; do
      printf '%s=%s\n' "$field" "$(sed -n "s/^$field=//p" "$record" | head -n 1)"
    done
    printf 'source=%s\nfrom_store=%s\n' "$fp" "$id"
  } > "$root/build/compiler-build.profile.$$.tmp" &&
    mv -f "$root/build/compiler-build.profile.$$.tmp" "$root/build/compiler-build.profile"
  # In use: keep the sweep away from it.
  touch "$src" "$record" 2>/dev/null || true
  if [ "${TUNGSTEN_STORE_VERBOSE:-0}" = 1 ]; then
    printf 'tungsten: installed the compiler for these sources from the build store (%s)\n' "$src" >&2
  fi
  return 0
}

# The compiler has dozens of TUNGSTEN_* switches that change what it emits
# (TUNGSTEN_FREE, TUNGSTEN_PARAM_INFER, TUNGSTEN_DEFINES, the BIGINT and cache
# toggles, ...), and a build inherits them from whoever starts it. In a
# checkout's own cache a compiler built under TUNGSTEN_FREE=0 only fooled its
# owner; in a store every checkout shares, it would be handed to all of them.
# This prints, sorted, every TUNGSTEN_* variable that is set, except the ones
# that only say where things are or how to run (locations, the store, GC and
# test-harness knobs) and the ones the build keys already hash by value
# (CPU, C toolchain, probe results, clang optimisation, sanitizer). A plain
# environment prints nothing, so plain builds share one key; anything else
# gets a key of its own. New switches need no entry here: unknown names are
# printed, which is the safe direction.
tungsten_tuning_environment() {
  env | LC_ALL=C sort | awk -F= -v skip=" TUNGSTEN_ROOT TUNGSTEN_HOME TUNGSTEN_BUILD_STORE TUNGSTEN_CONFIG TUNGSTEN_VERSION TUNGSTEN_BOOTSTRAP TUNGSTEN_BOOTSTRAP_HANDOFF TUNGSTEN_BUILD_MANIFEST TUNGSTEN_BUILD_JOBS TUNGSTEN_LEX64_TABLE TUNGSTEN_LL_PATH TUNGSTEN_LL_DIR TUNGSTEN_LL_DONE_MARKER TUNGSTEN_DEPFILE TUNGSTEN_STORE_VERBOSE TUNGSTEN_POLYGLOT TUNGSTEN_PREFLIGHT TUNGSTEN_BIN TUNGSTEN_REPO TUNGSTEN_BACKTRACE TUNGSTEN_INCREMENTAL TUNGSTEN_COMPILER_IMAGE TUNGSTEN_MARCH_ARGS TUNGSTEN_CPU TUNGSTEN_CC TUNGSTEN_AR TUNGSTEN_RANLIB TUNGSTEN_OS TUNGSTEN_ZSTD_CFLAGS TUNGSTEN_ZSTD_LDFLAGS TUNGSTEN_HTTP2_LDFLAGS TUNGSTEN_CLANG_OPT TUNGSTEN_BITS_CLANG_OPT TUNGSTEN_C_FAST_PARSE TUNGSTEN_COMPILER TUNGSTEN_SANITIZE " '
    /^TUNGSTEN_/ {
      if ($1 ~ /^TUNGSTEN_(CACHE|SPECS)_/) next
      if (index(skip, " " $1 " ")) next
      print
    }'
}

# `tungsten --clear-cache`: remove every entry of the compiler cache that
# rests on trust in file times or tool identities, so the next build redoes
# the work. Removing an entry is always safe: a build that finds one gone
# recompiles, and a process that already opened one keeps reading it.
#   - incremental binaries (irbin-*) and compiled-run binaries (run/*.wc):
#     in the shared store only those made by THIS toolchain root (their
#     identity names the compiler executable and TUNGSTEN_ROOT), so other
#     checkouts keep their warm caches; in an isolated TUNGSTEN_CACHE_DIR,
#     all of them;
#   - link results, parsed sources, lowered Core/library snapshots, function
#     text, target probes and Ruby-host ASTs (linkbin-*, loader-parse-*,
#     core-wire-*, library-wire-*, core-render-*, target-probe-*,
#     native-arm-cpu-*, *.memo): all of them, because their names are
#     digests that say nothing about who made them.
# Runtime archives and companion objects are named by the content of their
# sources and are kept; `tungsten cleanup --all` empties the whole store.
tungsten_clear_cache() {
  local root="$1" dir count=0 f slot manifest id
  dir="$(tungsten_cache_dir "$root")"
  if [ -d "$dir" ]; then
    while IFS= read -r -d '' f; do
      rm -f -- "$f" && count=$((count + 1))
    done < <(find "$dir" -maxdepth 1 -type f \( -name '*.memo' -o -name 'linkbin-*' \
               -o -name 'loader-parse-*' -o -name 'core-wire-*' -o -name 'library-wire-*' \
               -o -name 'core-render-*' -o -name 'target-probe-*' -o -name 'native-arm-cpu-*' \) -print0 2>/dev/null)
    if [ -n "${TUNGSTEN_CACHE_DIR:-}" ]; then
      while IFS= read -r -d '' f; do
        rm -f -- "$f" && count=$((count + 1))
      done < <({ find "$dir" -maxdepth 1 -type f -name 'irbin-*' -print0
                 find "$dir/run" -maxdepth 1 -type f \( -name '*.wc' -o -name '*.wc.id' -o -name '*.wc.sidemap' \) -print0; } 2>/dev/null)
    else
      # A manifest's first line (and a run binary's .id) is the build
      # identity, which names the compiler executable and TUNGSTEN_ROOT.
      while IFS= read -r manifest; do
        slot="${manifest%.manifest}"
        for f in "$slot.manifest" "$slot.bin" "$slot.sidemap"; do
          if [ -f "$f" ]; then rm -f -- "$f" && count=$((count + 1)); fi
        done
      done < <(find "$dir" -maxdepth 1 -type f -name 'irbin-*.manifest' -print0 2>/dev/null |
                 xargs -0 awk -v a="|$root|" -v b="|$root/" \
                   'FNR == 1 { if (index($0, a) || index($0, b)) print FILENAME; nextfile }' 2>/dev/null)
      while IFS= read -r id; do
        slot="${id%.id}"
        for f in "$slot.id" "$slot" "$slot.sidemap"; do
          if [ -f "$f" ]; then rm -f -- "$f" && count=$((count + 1)); fi
        done
      done < <(find "$dir/run" -maxdepth 1 -type f -name '*.wc.id' -print0 2>/dev/null |
                 xargs -0 awk -v a="|$root|" -v b="|$root/" \
                   'FNR == 1 { if (index($0, a) || index($0, b)) print FILENAME; nextfile }' 2>/dev/null)
    fi
  fi
  if [ "$count" -eq 1 ]; then
    printf 'Cleared 1 cache file (%s)\n' "$dir"
  else
    printf 'Cleared %s cache files (%s)\n' "$count" "$dir"
  fi
}

# `tungsten cleanup --all`: empty the store (or an isolated cache directory).
# Everything in it is reproducible; a build running at the same time may fail
# and has to be run again, so this is for a quiet machine.
tungsten_wipe_store() {
  local root="$1" store part
  if [ -n "${TUNGSTEN_CACHE_DIR:-}" ]; then
    case "$TUNGSTEN_CACHE_DIR" in ''|/) return 2 ;; esac
    find "$TUNGSTEN_CACHE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    printf 'Emptied %s\n' "$TUNGSTEN_CACHE_DIR"
    return 0
  fi
  store="$(tungsten_store_dir "$root")"
  case "$store" in ''|/) return 2 ;; esac
  for part in compile stages compilers bits; do
    rm -rf -- "$store/$part"
  done
  printf 'Emptied %s (compile, stages, compilers, bits)\n' "$store"
}

# Run as a command (not sourced).
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  set -u
  command="${1:-}"
  here_root="$(cd "$(dirname "$0")/../.." && pwd)"
  case "$command" in
    dir)
      tungsten_store_dir "${2:-$here_root}"
      ;;
    cache-dir)
      tungsten_cache_dir "${2:-$here_root}"
      ;;
    compiler-fingerprint)
      tungsten_compiler_fingerprint "${2:-$here_root}"
      ;;
    install-compiler)
      tungsten_install_store_compiler "${2:-$here_root}"
      ;;
    tuning-environment)
      tungsten_tuning_environment
      ;;
    clear-cache)
      tungsten_clear_cache "${2:-$here_root}"
      ;;
    wipe)
      tungsten_wipe_store "${2:-$here_root}"
      ;;
    *)
      printf 'usage: store.sh dir|cache-dir|compiler-fingerprint|install-compiler|tuning-environment|clear-cache|wipe [ROOT]\n' >&2
      exit 2
      ;;
  esac
fi

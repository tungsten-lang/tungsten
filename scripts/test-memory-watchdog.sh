#!/usr/bin/env bash
# Check the compiled runtime's optional per-process watchdog limit.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-memory-watch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/watch.w" <<'EOF'
z = ccall("usleep", 500000)
<< "watchdog test completed"
EOF
"$root/bin/tungsten" -o "$tmp/watch" "$tmp/watch.w" >"$tmp/build.out" 2>&1

env -u TUNGSTEN_MEMORY_LIMIT "$tmp/watch" >"$tmp/default.out" 2>"$tmp/default.err"
grep -q 'watchdog test completed' "$tmp/default.out"
env TUNGSTEN_MEMORY_LIMIT=off "$tmp/watch" >"$tmp/off.out" 2>"$tmp/off.err"
grep -q 'watchdog test completed' "$tmp/off.out"
env TUNGSTEN_MEMORY_LIMIT=invalid "$tmp/watch" >"$tmp/invalid.out" 2>"$tmp/invalid.err"
grep -q 'no per-process limit is set' "$tmp/invalid.err"

set +e
env TUNGSTEN_MEMORY_LIMIT=1M "$tmp/watch" >"$tmp/limited.out" 2>"$tmp/limited.err"
status=$?
set -e
if [ "$status" -ne 137 ] || ! grep -q 'memory limit exceeded' "$tmp/limited.err"; then
  printf 'FAIL: explicit watchdog limit returned %s\n' "$status" >&2
  cat "$tmp/limited.err" >&2
  exit 1
fi
printf 'PASS: optional memory watchdog limit\n'

if [ "$(uname -s)" = Darwin ]; then
  # Exercise the real watchdog with synthetic process readings. Neither this
  # process nor the host needs to allocate a GiB or approach memory pressure.
  cat >"$tmp/pressure.c" <<'EOF'
#include <errno.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

extern int memorystatus_get_level(int *);
static int sample_level(int *out) {
    if (getenv("TEST_USE_SYSCTL")) { errno = ENOSYS; return -1; }
    *out = atoi(getenv("TEST_AVAILABLE_PCT"));
    return 0;
}
static int sample_sysctl(const char *name, void *out, size_t *len, void *in, size_t size) {
    if (strcmp(name, "kern.memorystatus_level") != 0)
        return sysctlbyname(name, out, len, in, size);
    if (!getenv("TEST_USE_SYSCTL")) { errno = EPERM; return -1; }
    *(int *)out = atoi(getenv("TEST_AVAILABLE_PCT"));
    *len = sizeof(int);
    return 0;
}
static kern_return_t sample_task(task_name_t task, task_flavor_t flavor,
                                 task_info_t out, mach_msg_type_number_t *count) {
    kern_return_t result = task_info(task, flavor, out, count);
    if (result == KERN_SUCCESS && flavor == TASK_VM_INFO)
        ((task_vm_info_t)out)->phys_footprint = (uint64_t)9 << 30;
    return result;
}
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } samples[] = {
    {sample_level, memorystatus_get_level}, {sample_task, task_info}, {sample_sysctl, sysctlbyname}
};
EOF
  "$("$root/bin/commands/toolchain.sh" cc)" -dynamiclib "$tmp/pressure.c" -o "$tmp/pressure.dylib"
  run_pressure() {
    local expected="$1" observed=0
    shift
    env -u TUNGSTEN_MEMORY_LIMIT -u TEST_USE_SYSCTL DYLD_INSERT_LIBRARIES="$tmp/pressure.dylib" \
      "$@" "$tmp/watch" >"$tmp/pressure.out" 2>"$tmp/pressure.err" || observed=$?
    if [ "$observed" != "$expected" ]; then
      printf 'FAIL: expected %s, got %s for %s\n' "$expected" "$observed" "$*" >&2
      cat "$tmp/pressure.err" >&2
      exit 1
    fi
    if [ "$expected" = 137 ]; then
      grep -q 'system memory nearly exhausted (4% available)' "$tmp/pressure.err"
    else
      grep -q 'watchdog test completed' "$tmp/pressure.out"
    fi
  }
  run_pressure 137 TEST_AVAILABLE_PCT=4
  # Above the former 8 GiB ceiling, system headroom alone permits this run.
  run_pressure 0 TEST_AVAILABLE_PCT=5
  run_pressure 137 TEST_AVAILABLE_PCT=4 TEST_USE_SYSCTL=1
  printf 'PASS: macOS memory pressure with restricted and fallback queries\n'
fi

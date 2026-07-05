#!/usr/bin/env bash
# Measure the three REPL eval backends on a compute kernel.
# Run from the repo root after `bin/tungsten build`.
set -euo pipefail
cd "$(dirname "$0")/../.."

K=benchmarks/eval-backends/kernel.w
RT=/tmp/tungsten-runtime.a
now() { python3 -c 'import time;print(time.time())'; }
ms()  { python3 -c "print(f'{($2-$1)*1000:.0f} ms')"; }

echo "== Interpreter (tree-walk) =="
t0=$(now); ./bin/tungsten run "$K" >/dev/null; t1=$(now)
echo "  $(ms "$t0" "$t1")"

echo "== Native (compiled once, run) =="
./bin/tungsten -o /tmp/eb_kernel "$K" >/dev/null 2>&1
t0=$(now); /tmp/eb_kernel >/dev/null; t1=$(now)
echo "  $(ms "$t0" "$t1")  (includes ~277ms process startup)"

echo "== JIT per-line compile latency =="
printf -- '-> jit_line\n  6 * 7\n' > /tmp/eb_snip.w
./bin/tungsten --ll /tmp/eb_snip.w 2>/dev/null | sed -n '/^;/,$p' > /tmp/eb_snip.ll
# Warm min over a few runs — the first clang invocation pays a cold cache that
# the per-line REPL number (many warm compiles) never sees.
warmclang() { python3 -c "
import subprocess,time
xs=[]
for _ in range(4):
 a=time.time(); subprocess.run($1,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); xs.append((time.time()-a)*1000)
print(f'{min(xs):.0f} ms')"; }
echo "  clang -c (in-mem):    $(warmclang "['clang','-O2','-c','/tmp/eb_snip.ll','-o','/tmp/eb_snip.o']")  (object only — loaded by w_jit_load_object, no dlopen)"
echo "  clang -dynamiclib:    $(warmclang "['clang','-O2','/tmp/eb_snip.ll','-dynamiclib','-undefined','dynamic_lookup','-o','/tmp/eb_snip.dylib']")  (old path — then pays the dlopen floor below)"
echo "  fat dylib (oldest):   $(warmclang "['clang','-O2','/tmp/eb_snip.ll','$RT','-dynamiclib','-undefined','dynamic_lookup','-o','/tmp/eb_snip_fat.dylib']")  (relinks the 1.4MB runtime.a)"

echo "== End-to-end REPL per-line latency (in-memory JIT vs interpreter) =="
COMPILER=bin/tungsten-compiler
if [ -x "$COMPILER" ]; then
  perline() {  # $1 = flag, $2 = n lines; prints wall ms for n " i + i " lines
    local flag=$1 n=$2 body=""
    for ((i=0;i<n;i++)); do body+="$i + $i"$'\n'; done
    t0=$(now); printf '%s' "$body" | "$COMPILER" "$flag" >/dev/null 2>&1; t1=$(now)
    python3 -c "print(f'{($t1-$t0)*1000:.0f}')"
  }
  j5=$(perline --jit 5); j25=$(perline --jit 25)
  python3 -c "print(f'  --jit per-line: {($j25-$j5)/20:.0f} ms  (in-memory Mach-O loader; was ~170 ms via dlopen)')"
else
  echo "  (build first: bin/tungsten build — needs bin/tungsten-compiler for w_jit_load_object)"
fi

echo "== dlopen floor (the dominant per-line cost on macOS) =="
echo 'long ___ebf(void){return 1;}' > /tmp/eb_triv.c
# distinct trivial dylibs — each pays the dyld closure build
for i in 1 2 3; do clang -O2 -dynamiclib /tmp/eb_triv.c -o /tmp/eb_triv_$i.dylib 2>/dev/null; done
cat > /tmp/eb_dl.c <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
#include <time.h>
static double ms(struct timespec a){struct timespec b;clock_gettime(CLOCK_MONOTONIC,&b);return (b.tv_sec-a.tv_sec)*1e3+(b.tv_nsec-a.tv_nsec)/1e6;}
int main(int c,char**v){for(int i=1;i<c;i++){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);dlopen(v[i],RTLD_NOW|RTLD_LOCAL);printf("  dlopen %d: %.0f ms\n",i,ms(t));}return 0;}
EOF
clang -O2 /tmp/eb_dl.c -o /tmp/eb_dl
/tmp/eb_dl /tmp/eb_triv_1.dylib /tmp/eb_triv_2.dylib /tmp/eb_triv_3.dylib
echo "  ^ each fresh dylib pays the macOS dyld closure build — the ~120ms floor"

echo
echo "See README.md for the analysis, the interpreter-vs-native ~93x gap, and the"
echo "per-command latency breakdown. The in-memory Mach-O loader (w_jit_load_object)"
echo "removed the ~120ms dlopen floor: ~170 -> ~59 ms/line (now emit ~45 + clang -c ~14)."

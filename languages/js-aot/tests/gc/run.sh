#!/bin/sh
# Collector stress test: 10M short-lived objects, arrays and closures must run under a
# 200 MB memory cap with the collector on. Usage: run.sh <runner binary> (e.g. a build of jsrun.w)
R="$1"
D="$(dirname "$0")"
want="0,1000000,2000000,3000000,4000000,5000000,6000000,7000000,8000000,9000000 10"
got=$(BLADE_JS_GC=1 TUNGSTEN_MEMORY_LIMIT=200M $R "$D/stress.js" 2>&1 | tail -1)
if [ "$got" = "$want" ]; then echo "gc stress: ok"; else echo "gc stress: FAIL [$got]"; exit 1; fi
# the survivors test with a collection every 50 allocations
got=$(BLADE_JS_GC=1 BLADE_JS_GC_EVERY=50 $R "$D/../regress/gc_survivors.js" 2>&1 | tr '\n' '|' | sed 's/|$//')
if [ "$got" = "true 2 3 6 6|pv 7" ]; then echo "gc survivors: ok"; else echo "gc survivors: FAIL [$got]"; exit 1; fi

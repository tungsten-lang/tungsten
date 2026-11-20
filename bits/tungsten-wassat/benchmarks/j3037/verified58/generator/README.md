The offline generator searches whole schedules. It reads the two price tables bundled under replay and emits one byte per visited event node. The checked artifact contains a trace for every entry in cases.json. Mode indices in that file run from 0 through 2. Run the following from the bundle root to regenerate the smallest branch.

```sh
c++ -std=c++17 -O3 generator/prove.cpp -o /tmp/j3037-prove
SCHEDULE_TRACE=/tmp/branch-c.trace /tmp/j3037-prove activities.txt replay/selprice58.txt replay/selcap58.txt 360 2 2
cmp traces/branch-c.trace /tmp/branch-c.trace
```

The time limit bounds generation. Only a generator exit with an explicit exhausted result and a successful independent replay establishes a refutation. The search and verifier here use the resource dimensions of this project. The corresponding portfolio correctness fix and its signed-equivalence regression are in the Wassat checkout.

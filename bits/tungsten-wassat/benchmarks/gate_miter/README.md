# Gate miter proof experiment

The normal Wassat solve command now includes a native gate-miter sweep. [Native results and certificate](../../docs/sc2026-sqrt-mitern168.md)

This optional comparison driver uses CaDiCaL to prove internal gate relations and Wassat to refute the augmented original CNF. It checks their combined DRAT proof against the original input before reporting a specialist UNSAT result. Wassat's regular entry point and build have no dependency on this experiment.

## Run

Build a release Wassat executable. With CaDiCaL 3.0.1 installed, compile the worker against its headers and static library. For example, on macOS with Homebrew:

```sh
d=bits/tungsten-wassat/benchmarks/gate_miter
prefix=$(brew --prefix cadical)
c++ -std=c++17 -O3 -I"$prefix/include" "$d/sweep.cpp" "$prefix/lib/libcadical.a" -o /tmp/wassat-gate-sweep
python3 "$d/run.py" input.cnf --drat result.drat \
  --wassat /path/to/release/wassat --worker /tmp/wassat-gate-sweep \
  --checker /path/to/drat-trim
python3 "$d/test_gate_miter.py"
```

The driver expects competition-style exit codes 10 for SAT and 20 for UNSAT. When the input falls outside the specialist's scope, the proof check fails, or the specialist exhausts its time budget, the driver executes Wassat on the original file. Use an external timeout for a total portfolio budget. The default 60 seconds covers the specialist attempt, including final checking. The fallback has Wassat's usual runtime. The standalone Python entry adds startup time on fallback inputs.

## Recognition and proof

The reader expects contiguous gate definitions with the output literal first in each clause. The first definition must be a two-input XOR or XNOR. The program enumerates each local truth table and checks that every assignment to up to four inputs gives exactly one output. It checks the cone is acyclic, the comparator output is asserted, and other units constrain primary inputs. Unrecognized layouts delegate to Wassat. The default admission budget is 16,384 gates and can be set with `--max-gates`.

The driver simulates 1,024 input assignments with a fixed seed and groups signals with equal or complementary signatures. A proposed relation must connect exclusive parts of the two comparator cones for the specialist to run. Coincident signatures only nominate candidates. The incremental worker omits the comparator assertion and uses two assumption queries to prove each equality. Every successful direction has its own clause and proof. An interrupted or satisfiable query contributes no implication.

By default the comparator operands are excluded as a pair. Wassat receives the original formula plus certified internal implications and conducts the final search. The optional `--prove-output` experiment also queries the comparator operands. All specialist results follow the same original-CNF proof check.

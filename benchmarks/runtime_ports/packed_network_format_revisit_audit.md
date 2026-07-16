# Packed-network `to_s` relaxed-gate audit

Status: **retained** on 2026-07-15. The exact semantic/WIRE/LLVM gate and two
independently rebuilt 10-observation campaigns passed for all five strata.

Both isolated trees are detached at
`f62869bff0fc22fdc0a3179c82fb5da158d987d6`, then overlaid with the same
snapshot of the current integrated `compiler/`, `core/`, and `runtime/` state:

- baseline: `/tmp/tungsten-packed-network-format-baseline`
- candidate: `/tmp/tungsten-packed-network-format-candidate`

The static runner compares the trees directly. Their only production
difference must be `runtime/runtime.c`; `core/ipv4.w`, `core/ipv6.w`, and
`core/mac.w` are required to be byte-identical.

## Exact candidate transition

Each baseline network table has two rows using the same generic handler:

```c
{0, w_ic_value_to_s}, /* to_s */
{0, w_ic_value_to_s}, /* inspect */
```

The candidate removes only the `to_s` row for IPv4, IPv6, and MAC. It shifts
the retained `inspect` row to index zero, updates its name initializer, and
keeps the class resolver key and shared handler. Thus this candidate removes
exactly three native rows, not six.

The three core classes already contain the cheapest exact source body:

```tungsten
-> to_s
  ccall("w_to_s", self)
```

No formatter implementation is duplicated in Tungsten. The canonical C
representation boundary remains `w_to_s`, which selects the packed IPv4
formatter or heap-backed IPv6/MAC formatter. The already-retained
`IPv4#octets` source port must remain intact in both roots.

## Why `inspect` is not in this candidate

Removing `inspect` is not sound at an untyped native-return boundary. A
program can receive IPv4, IPv6, or MAC from an arbitrary `ccall`, then call
only `inspect`; the loader cannot infer a class from an undeclared native
return type. The native IC row currently makes that program work even when no
network class AST is loaded.

The superficially simple alternatives are worse:

- gating full network classes on the spelling `inspect` loads IPv4, IPv6, and
  MAC algorithms into ubiquitous matcher/assertion code;
- a small file reopening those exact class names still triggers the loader's
  class-definition force-autoload path and pulls in the full definitions;
- facade classes with different names do not preserve exact class identity or
  tree-walker dispatch.

A viable facade would require loader support that distinguishes designated
facade AST nodes from ordinary reopens, plus compile-time and binary-size
measurement. Until that mechanism is designed and measured, the three
`inspect` rows stay native. Their dormant `self.to_s` source bodies also stay
unchanged.

`to_s` does not share this blocker. The runtime has a universal fallback:

```c
if (name == WN_to_s) return w_to_s(recv);
```

So an otherwise-untyped network receiver still formats correctly after its
class-specific `to_s` row is removed. Existing literal and exact-native-result
autoload routes are nevertheless pinned to prove that normal calls reach the
source wrapper. No broad `inspect` loader gate is added.

## Correctness surface

`packed_network_format_public.w` has no core imports and is compiled unchanged
in both roots. Its migrated `to_s` checks cover:

- packed IPv4 literals, parse/of/native-factory values, boundary addresses,
  the no-prefix sentinel, and every prefix 0..32;
- heap IPv6 literals, compressed/uppercase/embedded-IPv4 parse forms, direct
  storage factories, boundary byte patterns, no prefix, and every prefix
  0..128;
- heap MAC colon, hyphen, Cisco-dot, uppercase, broadcast, multicast, direct
  parse, and deterministic native-factory forms;
- exact text, direct `w_to_s` parity, receiver-bit identity, WNetAddr field
  fingerprints, and one or three surplus arguments.

The public correctness fixture also calls `inspect` as an unchanged native
control; it is not timed and its source body is not claimed by this port.

The separate no-import fixture isolates all supported literal and exact
native-result autoload routes using `to_s`. The tree-walker fixture checks the
three source wrappers, representation stability, surplus arguments, and its
established ignored-block behavior. Native lowering instead rewrites a block
on a no-block method to implicit result-`each`; three bounded subprocess
probes require baseline/candidate status and output parity.

WIRE and LLVM gates require the three source methods to contain one direct
`w_to_s` call and no nested method dispatch. The three hot public callers must
remain byte-identical at WIRE level between matched roots.

## Timing protocol and retention rule

`run_packed_network_format_revisit.sh` defaults to `STATIC_ONLY=1`. The
exclusive benchmark lane was used as follows:

1. `STATIC_ONLY=0 CHECK_ONLY=1` builds one fresh matched compiler pair and runs
   exact behavior, WIRE, LLVM, no-import autoload, interpreter, and block gates.
2. `STATIC_ONLY=0 CHECK_ONLY=0` runs two independently rebuilt campaigns.
3. Each campaign takes 10 balanced ABBA/BAAB observations per stratum, with
   two native and two source legs averaged per observation.
4. Only `CLOCK_THREAD_CPUTIME_ID` inside the workload is measured.
5. Each public result is consumed by a constant-time string signature and
   compared with a canonical signature prepared outside the timed region; the
   checksum must equal the iteration count.
6. A method is retained only when every relevant stratum has median
   source/native `<= 1.10` in both campaigns. Pair maxima are diagnostics, not
   the gate.

There are five strata: plain and CIDR IPv4 `to_s`, plain and CIDR IPv6 `to_s`,
and MAC `to_s`. Default timing is two million calls per leg after a 100,000
call warmup.

## Results

The first check run found a benchmark-fixture ABI ambiguity before any timing:
raw `-1` has the same bits as a reserved packed WValue, so the mixed-ABI
support function could not distinguish a raw negative literal from a duration.
The no-prefix fixture was corrected to pass boxed `nil`, which the support
function maps to `-1`; both measured sides consumed the same corrected input.
The rebuilt semantic run then passed exact formatting, all prefixes, receiver
stability, surplus arguments, no-import autoload, trailing blocks,
interpreter behavior, WIRE shape, and LLVM shape.

Median source/native ratios were:

```text
campaign 1: IPv4 plain 0.990, IPv4 CIDR 0.989,
            IPv6 plain 0.987, IPv6 CIDR 0.990, MAC 0.991
campaign 2: IPv4 plain 0.986, IPv4 CIDR 0.999,
            IPv6 plain 0.989, IPv6 CIDR 0.985, MAC 1.008
```

Every median is below the fixed 1.10 gate, so IPv4, IPv6, and MAC `to_s` are
retained as source wrappers. Their three native `inspect` rows remain.

## Artifact hashes

These hashes identify the retained benchmark inputs and runner.

```text
8cd6260ed3b2016dac38e495e3f246fa84618ccc97d18030bb7579512edd320f  packed_network_format_public.w
551456e8a68342efa934a9feb84b8a259ca7d5fc24e03aa7514006fe63266ae6  packed_network_format_ref.c
dfeb8430aea03edfd1ebcdc5d65869bd03970f2bea929abccd79c9655c04ed60  packed_network_format_autoload.w
4f09fb7c3614fd6589bd3a339ff7e9755fa53689dcda408702fd9c73a251bcc4  packed_network_format_interpreter.w
b315f9ffda48a4735845b9c119516f127e36b053a2278f70ea626bfb51bf7da4  run_packed_network_format_revisit.sh
```

## Integration note

The shared worktree was updated narrowly against its current table layout:
only the three class-specific `to_s` rows were removed and the three retained
`inspect` rows were shifted to slot zero. No isolated production file was
copied wholesale. Integrated fixed-point/full-suite verification remains part
of the end-of-loop gate.

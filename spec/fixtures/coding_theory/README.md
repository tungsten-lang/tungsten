# Coding-theory semantic fixtures

`canonical_v1.w` is a hand-authored oracle for Tungsten's version-1,
protocol-neutral semantic records. It fixes these conventions:

- finite-field coordinates and polynomial coefficients are low-degree first;
- ordered-domain coordinates remain in caller order;
- interleaved messages are lane-major;
- interleaved codewords are position-major and lane-minor;
- every extension-field element has exactly `field.degree` power-basis
  coordinates.

The asymmetric F8 modulus `[1, 1, 0, 1]` pins the modulus coefficient order;
the F4 polynomial alone is palindromic and could not detect reversal.

The fixture is deliberately not JSON and does not define a byte or network
format. Its provenance fields say `tungsten-self-hosted`, external status
`planned`, and compatibility claim `none`.

An external compatibility tranche should add fixtures produced independently
by a pinned version/commit of each target system, record its field-element and
domain-order conventions, then verify both directions without changing this
v1 fixture. Candidate convention profiles include ArkLib-style degree-bound
saturation, Proximity affine-line ordering, and IRS floor-budget interleaving.
Core should accept an adapter for a stable semantic boundary only after those
fixtures match; protocol defaults, theorem artifacts, proof witnesses, and
wire encodings remain outside Core.

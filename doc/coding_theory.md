# Exact coding theory

`use coding_theory` loads protocol-neutral coding-theory foundations over
Core's exact `FiniteField` and `Polynomial` implementations. The current
surface provides ordered evaluation domains, affine-line combinations,
Reed-Solomon encoding, interleaved Reed-Solomon encoding, exact Hamming and
agreement metrics, numerical Johnson-radius transforms, and versioned
in-process semantic records.

It does not provide a decoder, list-decoding algorithm, protocol profile,
proof kernel, or theorem certificate.

```w
use coding_theory

field = FiniteField.new(5)
domain = CodingTheory.evaluation_domain(field, [0, 1, 2, 3, 4])
code = CodingTheory.reed_solomon(domain, 3)
word = code.encode([1, 2, 1])

word.to_a                 # [1, 4, 4, 1, 0]
code.dimension            # 3
code.minimum_distance     # 3
code.rate                 # 3/5
```

The message is the coefficient vector for
`1 + 2*x + x^2`. Coefficients are always in ascending degree order, and the
codeword follows the caller's domain order.

## Finite-field elements: external values and `_raw` values

The initial coding-theory surface deliberately accepts `FiniteField`, not an
arbitrary `Field` or `SimpleExtensionField`. A `FiniteField` element is stored
internally as an Integer in `[0, field.order)`. For an extension field this is
the packed base-`p` representation of its power-basis coefficients.

The documented paired entry points without a `_raw` suffix accept external
scalar syntax and call `field.coerce`:

- an Integer embeds through the prime subfield and is reduced modulo the
  characteristic;
- an Array supplies power-basis coefficients for an extension element;
- a `Rational` is embedded when its denominator is invertible.

Methods ending in `_raw` instead accept the packed Integer representation of
an already-normalized field element. They require
`0 <= value < field.order` and do not reinterpret the Integer as a scalar.
Methods prefixed `__` and extra constructor arities used by factory methods
are implementation details; Tungsten does not yet enforce private methods.

This distinction matters as soon as the extension degree exceeds one:

```w
use coding_theory

field = FiniteField.new(2, [1, 1, 1]) # F_4 = F_2[a]/(a^2+a+1)
a = field.generator                   # packed element 2
domain = FiniteFieldEvaluationDomain.raw(field, [0, 1, a])
code = ReedSolomonCode.new(domain, 2)

code.encode([1, a]).to_a       # [1, 1, 1]: external Integer 2 embeds as 0
code.encode_raw([1, a]).to_a   # [1, 3, 2]: raw 2 denotes a

line = AffineLineGenerator.new(field)
line.coordinates(a)            # [1, 0]
line.coordinates_raw(a)        # [1, 2]
```

Use the non-raw surface for mathematical literals and coefficient Arrays. Use
the raw surface when values came from `FiniteField` arithmetic, a prior raw
coding-theory result, `element_from_index`, or
`CodingTheoryInterchange`. Coding-theory encoders return raw normalized field
elements inside owned codeword objects.

The distinction applies consistently to domain construction and lookup,
codeword construction, affine-line operations, Reed-Solomon messages, and
interleaved messages:

```text
external                         raw
FiniteFieldEvaluationDomain.new  FiniteFieldEvaluationDomain.raw
from_points / include?           from_raw_points / include_raw?
index_of / affine_image          index_of_raw / affine_image_raw
FiniteFieldCodeword.new          FiniteFieldCodeword.raw
InterleavedCodeword.new          InterleavedCodeword.raw
coordinates / combine            coordinates_raw / combine_raw
combine_words                    combine_words_raw
encode / message_polynomial      encode_raw / message_polynomial_raw
encode_columns                   encode_columns_raw
encode_lane_major                encode_lane_major_raw
codeword                         codeword_raw
element_to_coefficients          element_to_coefficients_raw
reed_solomon_message_to_record  reed_solomon_message_to_record_raw
interleaved_message_to_record   interleaved_message_to_record_raw
```

## Ordered evaluation domains

`FiniteFieldEvaluationDomain` owns a nonempty Array of distinct points. Input
order is semantic: it determines codeword coordinate order and is never
sorted. Construction copies the Array, `points` and `to_a` return copies, and
duplicates are rejected after external coercion or raw validation.

```w
field = FiniteField.new(7)
domain = FiniteFieldEvaluationDomain.new(field, [3, 1, 6])

domain.size                 # 3
domain.at(0)                # 3
domain.index_of(1)          # 1
domain.include?(5)          # false
domain.to_a                 # [3, 1, 6]

shifted = domain.affine_image(2, 3)
shifted.to_a                # [4, 5, 6], preserving parameter order
```

`FiniteFieldEvaluationDomain.canonical(field, count)` uses the deterministic
packed-element sequence `0, 1, ..., count-1`. This is a representation order;
it does not assert that the points are an NTT domain, a multiplicative
subgroup, or ordered by any field-theoretic relation. `count` must be positive
and no larger than `field.order`. An affine image requires a nonzero direction.

Construction is expected `O(n)` time and memory because packed elements are
Integer hash keys. Indexed access is `O(1)`, expected membership lookup is
`O(1)`, and copying or taking an affine image is `O(n)`.

## Codewords and affine lines

`FiniteFieldCodeword` is an owned scalar word. `InterleavedCodeword` is an
owned position-major word whose row at each position contains its lanes in
increasing lane order. Their `symbols`, `rows`, `row`, and `to_a` methods
return copies rather than exposing internal Arrays.

Interleaving lanes are ordered, so this surface does not use
`SymmetricTuple`: exchanging two lanes changes the message and its component
interpretation.

`AffineLineGenerator` implements the ordered generator

\[
G(z) = (1,z)
\]

and the induced combination `base + z*direction` through the finite-field
protocol:

```w
field = FiniteField.new(5)
line = AffineLineGenerator.new(field)

line.coordinates(3)         # [1, 3]
line.combine(1, 2, 3)       # 2, since 1 + 3*2 = 2 in F_5

left = FiniteFieldCodeword.new(field, [1, 2, 3])
right = FiniteFieldCodeword.new(field, [2, 4, 1])
line.combine_words(left, right, 3).to_a # [2, 4, 1]
```

`combine_words` also accepts two compatible `InterleavedCodeword` values and
operates lane by lane. Both words must have the same representation, field,
length, and width. Scalar combination is `O(1)`; word combination is linear
in the number of stored field elements.

## Reed-Solomon evaluation codes

For an ordered distinct domain
`D = [alpha_0, ..., alpha_(n-1)]`, `ReedSolomonCode.new(D, k)` represents

\[
RS(D,k) = \{(f(alpha_0),\ldots,f(alpha_{n-1})) : \deg(f) < k\}.
\]

The constructor calls the second argument `degree_bound` deliberately. It may
exceed the block length. The exact metadata is:

```text
length              = n
degree_bound        = k
dimension           = min(k, n)
encoder_injective?  = (k <= n)
minimum_distance    = 0                         when dimension = 0
                      n - min(k, n) + 1         otherwise
rate                = dimension / n             as Rational
```

When `k > n`, evaluation remains well-defined but the message-to-codeword map
is not injective: the code has saturated to dimension `n`. The API reports
that state rather than silently renaming the degree bound as a dimension.

```w
field = FiniteField.new(5)
domain = FiniteFieldEvaluationDomain.new(field, [0, 1, 2, 3, 4])
saturated = ReedSolomonCode.new(domain, 7)

saturated.degree_bound       # 7
saturated.dimension          # 5
saturated.encoder_injective? # false
saturated.minimum_distance   # 1
```

`encode` and `encode_raw` require exactly `degree_bound` coefficients in
ascending degree order, including trailing zero coefficients. They evaluate
with Horner's rule and return a `FiniteFieldCodeword`. Encoding takes
`O(n*k)` field operations and `O(n)` output memory.

For repeated work over a small extension field, callers may opt into the
existing `field.prepare_arithmetic!` multiplication table before constructing
the code. Its default cutoff is field order 256 and its memory cost is
quadratic in the field order; coding-theory constructors do not allocate that
table implicitly.

`message_polynomial` and `message_polynomial_raw` construct a univariate
Core `Polynomial` over the same field. Conversely, `encode_polynomial`
accepts a univariate `Polynomial` over that field and rejects a nonzero
polynomial whose degree reaches the code's bound. It evaluates using raw field
elements at the domain points.

`contains?` (also `include?`) tests exact Reed-Solomon membership. For an
unsaturated nonzero code it interpolates the first `k` coordinates with
Newton divided differences and checks every remaining coordinate. Its cost is
`O(k^2 + (n-k)*k)` field operations with `O(k)` workspace. The zero code
accepts only the all-zero word; when `k >= n`, every ambient word is a member.

`codeword` and `codeword_raw` construct an owned word and require that it is a
member. They raise for a correctly shaped nonmember. Use
`FiniteFieldCodeword.new` or `.raw` directly for a received/noisy ambient word
that will be passed to a metric or future decoder. There is currently no
syndrome computation, systematic encoder, erasure decoder, unique decoder, or
list decoder.

## Interleaved Reed-Solomon codes

`InterleavedReedSolomonCode.new(domain, K, s)` follows the explicit
dimension-budget convention used by the referenced interleaved construction.
For positive interleaving `s`, each lane receives

\[
k_0 = \lfloor K/s \rfloor
\]

coefficients and is encoded by `RS(domain, k_0)`. If the domain length is
`n`, the metadata is:

```text
dimension_budget / requested_dimension = K
interleaving                            = s
lane_degree_bound                       = floor(K / s)
component_dimension                     = min(floor(K / s), n)
message_size                            = s * floor(K / s)
dimension                               = s * component_dimension
floor_remainder                         = K - message_size
saturation_loss                         = message_size - dimension
unrepresented_budget                    = floor_remainder + saturation_loss
budget_exact?                           = (unrepresented_budget == 0)
encoder_injective?                      = (lane_degree_bound <= n)
```

Thus `dimension_budget` is not necessarily the actual dimension. A nonzero
`floor_remainder` records loss because `s` does not divide `K`; a nonzero
`saturation_loss` records loss because each lane's degree bound exceeds the
domain length.

Messages are lane-major. `encode_columns` receives one coefficient Array per
lane, with coefficients in ascending degree order. The returned codeword is
position-major: `word.at(position, lane)` is the selected lane's value at the
selected domain point.

```w
field = FiniteField.new(5)
domain = FiniteFieldEvaluationDomain.new(field, [0, 1, 2])
code = InterleavedReedSolomonCode.new(domain, 5, 2)

word = code.encode_columns([[1, 1], [2, 1]])
word.to_a                         # [[1, 2], [2, 3], [3, 4]]

code.lane_degree_bound            # 2
code.message_size                 # 4
code.dimension                    # 4
code.floor_remainder              # 1
code.saturation_loss              # 0
code.unrepresented_budget         # 1
code.budget_exact?                # false
code.encoder_injective?           # true
code.minimum_distance             # 2
code.rate                         # 2/3, in interleaved alphabet symbols
```

`encode_lane_major([1, 1, 2, 1])` produces the same word. Its flat input
length is `message_size`, not `dimension_budget`, so a floor remainder is
never silently consumed. The first `lane_degree_bound` entries belong to lane
zero, followed by lane one, and so on.

Encoding takes `O(n*s*k_0)` field operations and stores `O(n*s)` field
elements. A zero lane degree bound produces the zero code with minimum
distance zero. Interleaving provides independent component encoders; it does
not add a decoder or correlated-error recovery algorithm.

`contains?` and `include?` test each ordered lane against its component
Reed-Solomon code. `codeword` and `codeword_raw` enforce that membership.
For unsaturated lanes, validation costs `s` times the scalar membership cost;
generic `InterleavedCodeword` values remain available for received words.

## Hamming distance and agreement

`CodingTheoryMetrics` operates on compatible owned codewords:

```w
distance = CodingTheoryMetrics.hamming_distance(left, right)
agreement = CodingTheoryMetrics.agreement_count(left, right)
relative = CodingTheoryMetrics.relative_distance(left, right)
fraction = CodingTheoryMetrics.agreement_fraction(left, right)
indices = CodingTheoryMetrics.agreement_indices(left, right)
inside = CodingTheoryMetrics.within_errors?(left, right, maximum_errors)
```

The two ratios are exact `Rational` values and require nonempty words.
Agreement indices are returned in increasing position order.

For interleaved words, the default Hamming metric is the block metric: a
position contributes one disagreement when any lane differs. Use
`component_hamming_distance(left, right, lane)` to inspect one lane.

```w
field = FiniteField.new(5)
domain = FiniteFieldEvaluationDomain.new(field, [0, 1, 2])
code = InterleavedReedSolomonCode.new(domain, 4, 2)
left = code.encode_columns([[1, 1], [2, 1]])
right = code.encode_columns([[1, 1], [2, 2]])

CodingTheoryMetrics.hamming_distance(left, right)              # 2
CodingTheoryMetrics.component_hamming_distance(left, right, 0) # 0
CodingTheoryMetrics.component_hamming_distance(left, right, 1) # 2
CodingTheoryMetrics.agreement_indices(left, right)              # [0]
```

`enumerated_ball_count(candidates, received, maximum_errors)`
counts the supplied Array entries within a closed Hamming ball. Duplicate
entries count more than once. It neither enumerates a code nor establishes a
mathematical list-size bound. Its cost is linear in the total candidate data.

The `CodingTheory` facade provides short entry points for `hamming_distance`,
`agreement_count`, `agreement_fraction`, and `enumerated_ball_count`.

## Numerical Johnson-radius transforms

`JohnsonBound` provides four approximate floating-point transforms:

```text
capacity_radius(delta)
  = 1 - sqrt(1 - delta)

q_ary_radius(q, delta)
  = (1 - 1/q) * (1 - sqrt(1 - (q/(q-1))*delta))

finite_list_radius(q, ell, delta)
  = (1 - 1/q)
      * (1 - sqrt(1 - (q/(q-1))*((ell-1)/ell)*delta))

mds_asymptotic_radius(rate)
  = 1 - sqrt(rate)
```

The implementation evaluates algebraically equivalent rationalized forms near
zero, so small positive radii are not lost to subtractive cancellation.

```w
JohnsonBound.capacity_radius(~0.5)          # about 0.2928932188
JohnsonBound.q_ary_radius(2, ~0.5)          # 0.5
JohnsonBound.finite_list_radius(5, 4, ~0.5) # about 0.2169048105
JohnsonBound.mds_asymptotic_radius(~0.5)    # about 0.2928932188
```

Distances and rates accept real numeric values, must be finite, and must lie
in `[0,1]`; `q` must be an integer at least two;
`ell` must be at least two; and the selected formula's square-root radicand
must be nonnegative. Invalid inputs raise rather than being clamped.

These methods return approximate `Float` values. They do not choose an
integer decoding radius, construct a decoder, compute a finite list, or prove
a list-size theorem. In particular, the asymptotic MDS rate expression is not
identical to applying `capacity_radius` to a finite Reed-Solomon code's
relative minimum distance, which contains the finite-length `1/n` correction.

## Affine-line alignment thresholds

`AffineLineAlignmentThresholds` records only the cardinality arithmetic from
an affine-line alignment theorem contract. For block length `n`, error budget
`e`, and exceptional limit `a`, it reports:

```text
minimum_challenge_count          = a + 1   # a < |S|
minimum_projection_size          = n - e   # |A_z| >= n-e
minimum_aligned_challenge_count  = e + 2   # e+1 < |T|
```

```w
thresholds = AffineLineAlignmentThresholds.new(100, 7, 3)

thresholds.minimum_challenge_count          # 4
thresholds.minimum_projection_size          # 93
thresholds.minimum_aligned_challenge_count  # 9
thresholds.premise_cardinalities_met?(
  4, [93, 94, 95, 96])                     # true
```

The constructor requires `n > 0`, `0 <= e <= n`, and `a >= 0`.
`challenge_count_met?`, `projection_size_met?`, and
`aligned_challenge_count_met?` check individual counts.
`projection_size_met?` also rejects a cardinality greater than `n`, since a
coordinate subset cannot exceed the block length.

This class is not a proof object, witness, certificate, or theorem checker.
It does not verify projected-code membership, affine equalities, existence of
global codewords, subset relations, or universally quantified assumptions.
Passing its numerical checks does not establish an affine-line alignment
theorem.

## Versioned semantic records

`CodingTheoryInterchange` converts exact coding-theory values to validated,
versioned plain-Tungsten records. Every record carries:

```text
"format"         = "tungsten-coding-theory"
"schema_version" = 1
"kind"           = a value-specific tag
```

Field elements are represented by exactly `field.degree` canonical
power-basis coefficients in ascending degree order. Records preserve the
field characteristic and an explicitly low-degree-first monic modulus,
domain order, low-degree-first message order, interleaving metadata, and
position-major/lane-minor codeword layout.
Deserializers recompute and validate redundant size and dimension metadata.

Available adapters cover:

- finite fields and field elements;
- ordered evaluation domains;
- Reed-Solomon and interleaved parameter descriptors;
- Reed-Solomon and lane-major interleaved messages;
- scalar and position-major interleaved codewords.

```w
field = FiniteField.new(5)
domain = FiniteFieldEvaluationDomain.new(field, [0, 1, 2])
code = ReedSolomonCode.new(domain, 2)
word = code.encode([1, 2])

record = CodingTheoryInterchange.reed_solomon_codeword_to_record(code, word)
restored = CodingTheoryInterchange.reed_solomon_codeword_from_record(record)

record["format"]          # "tungsten-coding-theory"
record["schema_version"]  # 1
record["layout"]          # "domain-order"
restored == word           # true
```

Unsuffixed message record writers accept external values, consistently with
the encoders. Their `_raw` variants accept already-normalized packed field
elements. Codeword writers and readers validate exact code membership.

The short `*_from_record` message loaders return normalized raw elements.
For extension-field or longer-lived interchange, prefer the corresponding
`*_bundle_from_record` loader. It returns a String-keyed Hash containing both
the reconstructed `"code"` and `"message"`, so packed Integers never become
detached from their field and ordered domain. Codeword bundle loaders likewise
return `"code"` and the membership-validated `"codeword"`:

```w
bundle = CodingTheoryInterchange.reed_solomon_message_bundle_from_record(
  message_record)
restored_code = bundle["code"]
restored_message = bundle["message"]

word_bundle = CodingTheoryInterchange.reed_solomon_codeword_bundle_from_record(
  record)
word_bundle["code"].contains?(word_bundle["codeword"]) # true
```

These records are an in-process semantic stability seam. They are not a JSON
format, byte-level wire format, persistence promise, ArkLib/Lean interchange
format, or protocol profile. A future external format must separately specify
its container encoding, integer encoding, compatibility policy, resource
limits, and schema migration rules.

## Current limits and deferred work

The current surface is intentionally small:

- only packed exact `FiniteField` values are accepted;
- domains are arbitrary ordered distinct points, not specialized FFT/NTT
  domains;
- encoding uses direct Horner evaluation rather than multipoint/FFT kernels;
- no systematic encoding, syndrome API, erasure decoding, unique decoding,
  list decoding, soft decoding, or streaming encoder is present;
- `enumerated_ball_count` examines an explicitly supplied finite Array and is
  not a decoder or implicit code enumeration;
- Johnson methods are approximate transforms rather than certified bounds;
- alignment support records numeric thresholds only;
- no protocol-specific `IRSProfile`, KoalaBear profile, commitment scheme,
  proximity protocol, Lean bridge, or proof kernel belongs to this module;
- semantic interchange records make no external serialization or binary
  compatibility claim.

Those additions should be introduced only with explicit error models,
resource bounds, layout contracts, and validation against independent
references. Protocol profiles belong in their protocol packages rather than
Core.

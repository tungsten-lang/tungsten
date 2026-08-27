# Protocol-neutral exact coding-theory foundations.
#
# This module owns ordered finite-field evaluation domains, affine-line
# combinations, Reed-Solomon encoders, interleaving, exact agreement metrics,
# numerical radius transforms, and stable semantic records.  It intentionally
# does not own protocol profiles, proof artifacts, decoders, or network/wire
# formats.

use core/math
use core/numeric/rational
use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/coding_theory/support
use core/coding_theory/domain
use core/coding_theory/codeword
use core/coding_theory/affine_line
use core/coding_theory/reed_solomon
use core/coding_theory/interleaved
use core/coding_theory/metrics
use core/coding_theory/bounds
use core/coding_theory/alignment
use core/coding_theory/interchange

+ CodingTheory
  -> .evaluation_domain(field, points)
    FiniteFieldEvaluationDomain.new(field, points)

  -> .evaluation_domain_raw(field, points)
    FiniteFieldEvaluationDomain.raw(field, points)

  -> .canonical_domain(field, count)
    FiniteFieldEvaluationDomain.canonical(field, count)

  -> .reed_solomon(domain, degree_bound)
    ReedSolomonCode.new(domain, degree_bound)

  -> .interleaved_reed_solomon(domain, dimension_budget, interleaving)
    InterleavedReedSolomonCode.new(
      domain, dimension_budget, interleaving)

  -> .hamming_distance(left, right)
    CodingTheoryMetrics.hamming_distance(left, right)

  -> .agreement_count(left, right)
    CodingTheoryMetrics.agreement_count(left, right)

  -> .agreement_fraction(left, right)
    CodingTheoryMetrics.agreement_fraction(left, right)

  -> .enumerated_ball_count(candidates, received, maximum_errors)
    CodingTheoryMetrics.enumerated_ball_count(
      candidates, received, maximum_errors)

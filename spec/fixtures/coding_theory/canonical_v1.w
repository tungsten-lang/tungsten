# Hand-authored schema-v1 semantic fixtures. These are independent expected
# records for Tungsten's in-process interchange seam; they are not JSON bytes,
# external wire fixtures, or evidence of ArkLib/Proximity compatibility.

+ CodingTheoryCanonicalV1Fixture
  -> .metadata
    {
      "producer": "tungsten-self-hosted",
      "external_fixture_status": "planned",
      "compatibility_claim": "none"
    }

  -> .f4_field
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "finite-field",
      "characteristic": 2,
      "degree": 2,
      "element_layout": "power-basis-low-degree-first",
      "modulus_layout": "low-degree-first-monic",
      "modulus": [1, 1, 1]
    }

  # Asymmetric coefficients make a reversed modulus convention detectable.
  -> .f8_field
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "finite-field",
      "characteristic": 2,
      "degree": 3,
      "element_layout": "power-basis-low-degree-first",
      "modulus_layout": "low-degree-first-monic",
      "modulus": [1, 1, 0, 1]
    }

  -> .f4_domain
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "evaluation-domain",
      "field": CodingTheoryCanonicalV1Fixture.f4_field,
      "layout": "ordered-points",
      "size": 4,
      "points": [[0, 1], [0, 0], [1, 1], [1, 0]]
    }

  -> .f4_reed_solomon_parameters
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "reed-solomon-parameters",
      "domain": CodingTheoryCanonicalV1Fixture.f4_domain,
      "dimension_rule": "degree-below-bound",
      "length": 4,
      "degree_bound": 2,
      "dimension": 2,
      "encoder_injective": true
    }

  -> .f4_reed_solomon_message
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "reed-solomon-message",
      "parameters": CodingTheoryCanonicalV1Fixture.f4_reed_solomon_parameters,
      "layout": "low-degree-first",
      "coefficient_count": 2,
      "coefficients": [[1, 0], [0, 1]]
    }

  -> .f4_reed_solomon_codeword
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "reed-solomon-codeword",
      "parameters": CodingTheoryCanonicalV1Fixture.f4_reed_solomon_parameters,
      "layout": "domain-order",
      "symbol_count": 4,
      "symbols": [[0, 1], [1, 0], [0, 0], [1, 1]]
    }

  -> .f7_field
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "finite-field",
      "characteristic": 7,
      "degree": 1,
      "element_layout": "power-basis-low-degree-first",
      "modulus_layout": "low-degree-first-monic",
      "modulus": nil
    }

  -> .f7_domain
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "evaluation-domain",
      "field": CodingTheoryCanonicalV1Fixture.f7_field,
      "layout": "ordered-points",
      "size": 3,
      "points": [[0], [1], [2]]
    }

  -> .f7_interleaved_parameters
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "interleaved-reed-solomon-parameters",
      "domain": CodingTheoryCanonicalV1Fixture.f7_domain,
      "dimension_rule": "s-times-min-floor-K-over-s-and-n",
      "length": 3,
      "dimension_budget": 5,
      "interleaving": 2,
      "lane_degree_bound": 2,
      "component_dimension": 2,
      "message_size": 4,
      "dimension": 4,
      "floor_remainder": 1,
      "saturation_loss": 0,
      "unrepresented_budget": 1,
      "budget_exact": false,
      "encoder_injective": true
    }

  -> .f7_interleaved_message
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "interleaved-reed-solomon-message",
      "parameters": CodingTheoryCanonicalV1Fixture.f7_interleaved_parameters,
      "layout": "lane-major-low-degree-first",
      "column_count": 2,
      "column_length": 2,
      "columns": [[[1], [2]], [[3], [4]]]
    }

  -> .f7_interleaved_codeword
    {
      "format": "tungsten-coding-theory",
      "schema_version": 1,
      "kind": "interleaved-reed-solomon-codeword",
      "parameters": CodingTheoryCanonicalV1Fixture.f7_interleaved_parameters,
      "layout": "position-major-lane-minor",
      "position_count": 3,
      "interleaving": 2,
      "rows": [[[1], [3]], [[3], [0]], [[5], [4]]]
    }

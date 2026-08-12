# A fixed-extent parameter contract feeds the same preflight bounds checker as
# local workgroup/private arrays. The index is computed but constant: 1+3 = 4.

## f32[4]: values
@gpu fn invalid_parameter_index(values)
  values[1 + 3] = 1.0

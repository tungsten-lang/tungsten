# Entry-point threadgroup buffers require host launch metadata that Tungsten's
# current ABI does not expose. Allocate them in the kernel instead.

## f32[] threadgroup: values
@gpu fn invalid_entry_address_space(values)
  values[0] = 1.0

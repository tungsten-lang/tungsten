use ../fleet/refinement_artifacts

-> ffbc_counter(path) (String) i64
  raw = File.read_prefix(path, 32)
  if raw == nil
    return 0
  value = ffw_parse_decimal_i64(raw.strip()) ## i64
  if value < 0 || value > 1000000000000
    return 0
  value

-> ffbc_composition_limit() i64
  raw = env("METAFLIP_COMPOSITION_PENDING")
  if raw != nil && raw != ""
    value = ffw_parse_decimal_i64(raw) ## i64
    if value == 0 || (value >= 1269 && value <= 1000000)
      return value
  4096

# Deferred cursor counts contexts, not recipe tickets; at most 27 per parent.
# A malformed durable counter must not look like an empty queue to a writer.
-> ffmd_count(path) (String) i64
  raw = File.read_prefix(path, 32)
  if raw == nil
    return 0
  value = ffw_parse_decimal_i64(raw.strip()) ## i64
  if value < 0 || value > 27000000000000 || raw != value.to_s() + "\n"
    return 0-1
  value

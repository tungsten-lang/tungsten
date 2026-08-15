# --- BEGIN GENERATED: unit registries ---
use literal_units/unit_ids_a
use literal_units/unit_ids_b
use literal_units/unit_ids_c
use literal_units/signatures_a
use literal_units/signatures_b
use literal_units/signatures_c

-> lookup_unit_id(ctx, raw_unit, node)
  # Materialize lexer slices before the generated switch keys are compared.
  unit = "" + raw_unit
  found = lookup_unit_id_generated_a(unit)
  if found != nil
    return found
  found = lookup_unit_id_generated_b(unit)
  if found != nil
    return found
  found = lookup_unit_id_generated_c(unit)
  if found != nil
    return found
  assign_custom_unit(ctx, unit, node)

-> lookup_unit_static_signature(raw_unit)
  unit = "" + raw_unit
  found = lookup_unit_signature_generated_a(unit)
  if found != nil
    return found
  found = lookup_unit_signature_generated_b(unit)
  if found != nil
    return found
  lookup_unit_signature_generated_c(unit)

# --- END GENERATED: unit registries ---

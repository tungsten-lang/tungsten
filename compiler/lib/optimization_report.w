# Read-only explanation of actual lowered WIRE. This runs only in inspection
# mode, before mid-end/LLVM optimization, and must never change the module.
use core/json

-> optimization_report(mod)
  rows = []
  source = mod[:source_path]
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    path = func[:source_path]
    if path == source || (path != nil && file_expand_path(path) == file_expand_path(source))
      name = func[:source_method]
      if name == nil
        name = "<entry>"
      if func[:source_class] != nil
        name = func[:source_class] + "#" + name
      strings = {}
      bi = 0
      while bi < func[:blocks].size()
        block = func[:blocks][bi]
        line = func[:source_line]
        col = nil
        ii = 0
        while ii < block[:instructions].size()
          inst = block[:instructions][ii]
          kind = wire_kind(inst)
          if kind == :string_i64
            strings[wire_get(inst, :temp)] = mod[:strings][wire_get(inst, :string_id)][:text]
          if kind == :call_loc_set_col
            line = wire_get(inst, :line)
            col = wire_get(inst, :col)
          category = nil
          target = nil
          detail = nil
          advice = nil
          if kind == :call_method_i64
            encoded = wire_get(inst, :method_name_val)
            target = strings[encoded]
            if target == nil && encoded != nil && encoded.starts_with?("u0xfff9")
              # Parse only the 48-bit payload: String#to_i saturates when the
              # full unsigned tag exceeds signed i64. Lowering emits SSO here.
              payload = encoded.slice(7, 12).to_i(16) ## i64
              bits = (w_tag_stringsym + payload) ## i64
              target = wvalue_from_bits(bits)
            if wire_get(inst, :devirt_fn) != nil || wire_get(inst, :construct_fn) != nil
              category = "guarded_dispatch"
              detail = "A direct fast path has a runtime guard and a generic fallback."
              advice = "Profile guard misses before changing this call."
            else
              category = "dynamic_dispatch"
              detail = "Lowering retained runtime method lookup at this call."
              advice = "Check receiver type facts and block/overload constraints; use --tags for overload decisions."
              if mod[:method_tables_locked] != true
                advice = advice + " Method tables remain open, so unconditional devirtualization requires an explicit closed-world contract."
          elsif kind == :call_direct_i64
            target = wire_get(inst, :name)
            if target in ("w_array_to_f32" "w_array_to_f64")
              category = "array_conversion"
              detail = "This helper allocates converted array storage."
              advice = "Create the required element type at the producer, or use a checked borrowed-view contract when no conversion is intended."
            elsif target in ("w_add" "w_sub" "w_mul" "w_div" "w_mod" "w_pow")
              category = "generic_arithmetic"
              detail = "A generic numeric runtime helper remains in this block; it may be a guarded fallback."
              advice = "Inspect operand representations and --tags; a machine-width hint changes overflow semantics and must match the intended contract."
            elsif target in ("w_array_new_empty" "w_array_new" "w_array_new_uninit_sized" "w_array_new_inline_uninit_sized" "w_array_zeros" "w_hash_new")
              category = "allocation_request"
              detail = "Lowering requests storage here; later ownership/LLVM passes may eliminate or reuse it."
              advice = "Measure surviving allocations before introducing caller-owned output or reuse."
          if category != nil
            site_line = wire_get(inst, :src_line)
            site_col = wire_get(inst, :src_col)
            location_kind = "call"
            if site_line == nil
              site_line = line
              site_col = col
              location_kind = col == nil ? "function" : "preceding_location"
            rows.push({category: category, function: name, file: path,
              line: site_line, column: site_col, location_kind: location_kind,
              block: block[:label], instruction: kind.to_s(), target: target,
              explanation: detail, suggestion: advice})
          ii += 1
        bi += 1
    fi += 1
  {schema_version: 1, phase: "lowered_wire_before_mid_end", source: source,
    limitation: "Static sites are not measured hotspots. Guarded paths and allocation requests may be optimized later.", sites: rows}

-> optimization_report_text(report)
  out = StringBuffer(256)
  out << "Optimization report: " << report[:source] << "\n"
  out << report[:limitation] << "\n"
  rows = report[:sites]
  i = 0
  while i < rows.size()
    row = rows[i]
    out << "\n" << row[:file].to_s()
    if row[:line] != nil
      out << ":" << row[:line].to_s()
    if row[:column] != nil
      out << ":" << row[:column].to_s()
    out << "  " << row[:function] << "  " << row[:category] << "  " << row[:target].to_s() << "\n"
    out << "  " << row[:explanation] << "\n  " << row[:suggestion] << "\n"
    i += 1
  if rows.size() == 0
    out << "\nNo covered lowering costs found in the entry source.\n"
  out.to_s()

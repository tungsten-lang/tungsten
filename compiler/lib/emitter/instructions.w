# Emitter instruction dispatcher — keeps opcode-family workers independently
# reviewable while preserving one render_instruction entry point.

-> render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false)
  rendered = render_numeric_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)
  if rendered != nil
    return rendered
  render_runtime_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)

# Single-template generator for the dimension-specialized cal2zone Metal
# workers under lib/metaflip/kernels/{rectangular,generic}.
#
# Every checked-in cal2zone_<tag>.w is a rendering of tools/cal2zone.template
# for one shape.  Geometry is never typed here a second time: CAP, WPG and the
# mask width come from the profile functions the coordinator dispatches with
# (ffrp_gpu_cap / ffrp_gpu_wpg / ffrgb_mask_bytes for rectangles, ffb_* for
# squares), so a worker cannot disagree with its scheduler.  Everything else a
# shape needs (factor bit widths, envelope masks, threadgroup extents, run
# paths) is arithmetic on (n, m, p).  spec/package_layout_test.w re-renders
# every bundled worker and fails on any drift from the template.
#
# Template language (all other lines are copied verbatim):
#   {{NAME}}          substitution; the names are listed in ffgz_bind
#   #@if f1 f2 ...    keep the block only while every listed flag holds
#   #@else / #@end    flags: rect generic wide narrow view calls
#
# `tools/gen_cal2zone.w` is the command-line entry; this module has no
# top-level effects so specs can `use` it directly.

use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/kernels/bundles/generic

# Shape codes pack a family with the dimensions: rectangles are n*100+m*10+p,
# squares add 1000 (the generic kernels live in kernels/generic).
-> ffgz_shapes()
  codes = []
  n = 2
  while n <= 9
    m = 2
    while m <= 9
      p = 2
      while p <= 9
        if ffrgb_supported(n, m, p) == 1
          codes.push(n * 100 + m * 10 + p)
        p += 1
      m += 1
    n += 1
  n = 3
  while n <= 7
    if ffb_supported(n) == 1
      codes.push(1000 + n * 111)
    n += 1
  codes

-> ffgz_family(code) (i64)
  if code >= 1000
    return "generic"
  "rect"

-> ffgz_code_n(code) (i64) i64
  (code % 1000) / 100

-> ffgz_code_m(code) (i64) i64
  (code % 100) / 10

-> ffgz_code_p(code) (i64) i64
  code % 10

-> ffgz_tag(n, m, p) (i64 i64 i64)
  n.to_s() + m.to_s() + p.to_s()

-> ffgz_dir(family) (String)
  if family == "generic"
    return "generic"
  "rectangular"

# Path of a rendered worker relative to lib/metaflip/kernels.
-> ffgz_rel_path(family, n, m, p) (String i64 i64 i64)
  ffgz_dir(family) + "/cal2zone_" + ffgz_tag(n, m, p) + ".w"

-> ffgz_cap(family, n, m, p) (String i64 i64 i64) i64
  if family == "generic"
    return ffb_cap(n)
  ffrgb_cap(n, m, p)

-> ffgz_wpg(family, n, m, p) (String i64 i64 i64) i64
  if family == "generic"
    return ffb_wpg(n)
  ffrgb_wpg(n, m, p)

-> ffgz_mask_bytes(family, n, m, p) (String i64 i64 i64) i64
  if family == "generic"
    return ffb_mask_bytes(n)
  ffrgb_mask_bytes(n, m, p)

# The 7x7x7 worker predates the i64 buffer relays that now carry 49-bit masks
# through metal_buffer_{read,write}_i64 and String#to_i; it keeps typed
# metal_buffer_view relays and a split decimal parse on the host side.  No
# other bundled shape selects that host path.
-> ffgz_view(family, n, m, p) (String i64 i64 i64) i64
  if family == "generic" && n == 7
    return 1
  0

-> ffgz_max3(a, b, c) (i64 i64 i64) i64
  best = a ## i64
  if b > best
    best = b
  if c > best
    best = c
  best

-> ffgz_bits_mask(bits) (i64) i64
  one = 1 ## i64
  (one << bits) - 1

# Fraction of a wide factor domain that two 32-bit permuted draws could cover
# on their own; it only decorates the wide sampler comment.
-> ffgz_fraction_word(excess_bits) (i64)
  if excess_bits == 1
    return "half"
  if excess_bits == 2
    return "quarter"
  if excess_bits == 3
    return "eighth"
  one = 1 ## i64
  (one << excess_bits).to_s() + "th"

-> ffgz_wide_axis(n, m, p) (i64 i64 i64)
  widest = ffgz_max3(n * m, m * p, n * p) ## i64
  if n * m == widest
    return "U"
  if m * p == widest
    return "V"
  "W"

-> ffgz_bind(family, n, m, p, names, values) i64
  cap = ffgz_cap(family, n, m, p) ## i64
  wpg = ffgz_wpg(family, n, m, p) ## i64
  mask_bytes = ffgz_mask_bytes(family, n, m, p) ## i64
  ubits = n * m ## i64
  vbits = m * p ## i64
  wbits = n * p ## i64
  maxbits = ffgz_max3(ubits, vbits, wbits) ## i64
  mask_type = "i32"
  if mask_bytes == 8
    mask_type = "i64"
  names.push("TAG")
  values.push(ffgz_tag(n, m, p))
  names.push("N")
  values.push(n.to_s())
  names.push("M")
  values.push(m.to_s())
  names.push("P")
  values.push(p.to_s())
  names.push("CAP")
  values.push(cap.to_s())
  names.push("WPG")
  values.push(wpg.to_s())
  names.push("SHARED")
  values.push((cap * wpg).to_s())
  names.push("MB")
  values.push(mask_bytes.to_s())
  names.push("MT")
  values.push(mask_type)
  names.push("UBITS")
  values.push(ubits.to_s())
  names.push("VBITS")
  values.push(vbits.to_s())
  names.push("WBITS")
  values.push(wbits.to_s())
  names.push("MAXBITS")
  values.push(maxbits.to_s())
  names.push("ENV")
  values.push(ffgz_bits_mask(maxbits).to_s())
  names.push("UMASK")
  values.push(ffgz_bits_mask(ubits).to_s())
  names.push("VMASK")
  values.push(ffgz_bits_mask(vbits).to_s())
  names.push("WMASK")
  values.push(ffgz_bits_mask(wbits).to_s())
  if maxbits > 32
    names.push("HIGH")
    values.push(ffgz_bits_mask(maxbits - 32).to_s())
    names.push("WIDE_FRACTION")
    values.push(ffgz_fraction_word(maxbits - 32))
    names.push("WIDE_AXIS")
    values.push(ffgz_wide_axis(n, m, p))
  names.size()

-> ffgz_flag(name, family, wide, view) (String String i64 i64) i64
  if name == "rect"
    if family == "rect"
      return 1
    return 0
  if name == "generic"
    if family == "generic"
      return 1
    return 0
  if name == "wide"
    return wide
  if name == "narrow"
    return 1 - wide
  if name == "view"
    return view
  if name == "calls"
    return 1 - view
  0 - 1

# Evaluate one "#@if f1 f2 ..." directive: 1/0, or -1 for an unknown flag.
-> ffgz_condition(directive, family, wide, view) (String String i64 i64) i64
  parts = directive.split(" ")
  if parts.size() < 2
    return 0 - 1
  i = 1
  while i < parts.size()
    if parts[i] != ""
      flag = ffgz_flag(parts[i], family, wide, view) ## i64
      if flag < 0
        return 0 - 1
      if flag == 0
        return 0
    i += 1
  1

-> ffgz_substitute(line, names, values)
  out = line
  i = 0
  while i < names.size()
    out = out.replace("{{" + names[i] + "}}", values[i])
    i += 1
  out

# Render the template for one shape.  Returns "" when the template is
# malformed (unknown flag, unbalanced block, unbound placeholder).
-> ffgz_render(template, family, n, m, p) (String String i64 i64 i64)
  lines = template.split("\n")
  names = []
  values = []
  z = ffgz_bind(family, n, m, p, names, values)
  wide = 0 ## i64
  if ffgz_mask_bytes(family, n, m, p) == 8
    wide = 1
  view = ffgz_view(family, n, m, p) ## i64
  parent_emit = i64[64]
  block_cond = i64[64]
  depth = 0 ## i64
  emitting = 1 ## i64
  rendered_lines = []
  i = 0
  while i < lines.size()
    line = lines[i]
    if line.starts_with?("#@if ")
      cond = ffgz_condition(line, family, wide, view) ## i64
      if cond < 0 || depth >= 64
        return ""
      parent_emit[depth] = emitting
      block_cond[depth] = cond
      depth += 1
      emitting = emitting * cond
    elsif line == "#@else"
      if depth < 1
        return ""
      emitting = parent_emit[depth - 1] * (1 - block_cond[depth - 1])
    elsif line == "#@end"
      if depth < 1
        return ""
      depth -= 1
      emitting = parent_emit[depth]
    elsif line.starts_with?("#@")
      return ""
    elsif i == lines.size() - 1 && line == ""
      z = 0
    elsif emitting == 1
      rendered = ffgz_substitute(line, names, values)
      if rendered.include?("{{")
        return ""
      rendered_lines.push(rendered)
    i += 1
  if depth != 0
    return ""
  rendered_lines.join("\n") + "\n"

# Render every bundled shape under out_root (a kernels directory); returns the
# number of workers written, or 0 on the first failure.
-> ffgz_write_all(template_path, out_root) (String String) i64
  template = read_file(template_path)
  if template == nil
    return 0
  codes = ffgz_shapes()
  written = 0 ## i64
  i = 0
  while i < codes.size()
    code = codes[i] ## i64
    family = ffgz_family(code)
    n = ffgz_code_n(code) ## i64
    m = ffgz_code_m(code) ## i64
    p = ffgz_code_p(code) ## i64
    text = ffgz_render(template, family, n, m, p)
    if text == ""
      return 0
    dir = out_root + "/" + ffgz_dir(family)
    z = system("mkdir -p " + ffrgb_shell_quote(dir))
    if write_file(out_root + "/" + ffgz_rel_path(family, n, m, p), text) == false
      return 0
    written += 1
    i += 1
  written

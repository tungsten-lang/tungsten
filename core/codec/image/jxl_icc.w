# core/codec/image/jxl_icc — rebuilds the ICC profile from JPEG XL's predictive ICC
# encoding (the "UnpredictICC" step that follows the entropy-coded stream).
# jxi_unpredict(enc: u8[], size) → Array of bytes (the ICC profile).

use jxl_ans

JXI_HEADER_PRED = [0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 109, 110, 116, 114, 82, 71, 66, 32, 88, 89, 90, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 97, 99, 115, 112, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 246, 214, 0, 1, 0, 0, 0, 0, 211, 45, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

JXI_TAGS = ["cprt", "wtpt", "bkpt", "rXYZ", "gXYZ", "bXYZ", "kXYZ", "rTRC", "gTRC", "bTRC", "kTRC", "chad", "desc", "chrm", "dmnd", "dmdd", "lumi"]
JXI_TYPES = ["XYZ ", "desc", "text", "mluc", "para", "curv", "sf32", "gbd "]

-> jxi_fail(msg)
  jxl_fail("icc: " + msg)

# [value, newpos]
-> jxi_varint(e, pos, lim)
  v = 0
  i = 0
  while i < 10
    jxi_fail("varint") if pos >= lim
    b = e[pos]
    pos += 1
    v = v | ((b & 127) << (7 * i))
    return [v, pos] if (b & 128) == 0
    i += 1
  jxi_fail("varint too long")

-> jxi_push32(out, v)
  out.push((v >> 24) & 255)
  out.push((v >> 16) & 255)
  out.push((v >> 8) & 255)
  out.push(v & 255)

-> jxi_push_str(out, s)
  i = 0
  while i < 4
    out.push(s.byte_at(i))
    i += 1

-> jxi_shuffle(data, width)
  size = data.size
  height = (size + width - 1) / width
  res = []
  s = 0
  j = 0
  i = 0
  while i < size
    res.push(data[j])
    j += height
    if j >= size
      s += 1
      j = s
    i += 1
  res

-> jxi_pred(p1, p2, p3, order)
  return p1 if order == 0
  return 2 * p1 - p2 if order == 1
  3 * p1 - 3 * p2 + p3

-> jxi_be32(d, pos, size)
  return 0 if pos + 4 > size
  (d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3]

-> jxi_linear_pred(d, start, i, stride, width, order)
  pos = start + i
  if width == 1
    return jxi_pred(d[pos - stride], d[pos - stride * 2], d[pos - stride * 3], order) & 255
  if width == 2
    p = start + ((i >> 1) << 1)
    p1 = (d[p - stride] << 8) + d[p - stride + 1]
    p2 = (d[p - stride * 2] << 8) + d[p - stride * 2 + 1]
    p3 = (d[p - stride * 3] << 8) + d[p - stride * 3 + 1]
    pr = jxi_pred(p1, p2, p3, order) & 0xFFFF
    return (i & 1) == 1 ? (pr & 255) : ((pr >> 8) & 255)
  p = start + ((i >> 2) << 2)
  p1 = jxi_be32(d, p - stride, pos)
  p2 = jxi_be32(d, p - stride * 2, pos)
  p3 = jxi_be32(d, p - stride * 3, pos)
  pr = jxi_pred(p1, p2, p3, order) & 0xFFFFFFFF
  sb = 3 - (i & 3)
  (pr >> (sb * 8)) & 255

-> jxi_unpredict(e, size)
  pos = 0
  r = jxi_varint(e, pos, size)
  osize = r[0]
  pos = r[1]
  r = jxi_varint(e, pos, size)
  csize = r[0]
  pos = r[1]
  cpos = pos
  cend = cpos + csize
  jxi_fail("commands out of bounds") if cend > size
  pos = cend
  header = JXI_HEADER_PRED.dup
  header[0] = (osize >> 24) & 255
  header[1] = (osize >> 16) & 255
  header[2] = (osize >> 8) & 255
  header[3] = osize & 255
  out = []
  i = 0
  while i <= 128
    return out if out.size == osize
    break if i == 128
    # header prediction tweaks
    if i == 8 && out.size >= 8
      header[80] = out[4]
      header[81] = out[5]
      header[82] = out[6]
      header[83] = out[7]
    if i == 41 && out.size >= 41
      if out[40] == 65
        header[41] = 80
        header[42] = 80
        header[43] = 76
      if out[40] == 77
        header[41] = 83
        header[42] = 70
        header[43] = 84
    if i == 42 && out.size >= 42
      if out[40] == 83 && out[41] == 71
        header[42] = 73
        header[43] = 32
      if out[40] == 83 && out[41] == 85
        header[42] = 78
        header[43] = 87
    jxi_fail("header out of bounds") if pos >= size
    out.push((e[pos] + header[i]) & 255)
    pos += 1
    i += 1
  jxi_fail("no tag count") if cpos >= cend
  r = jxi_varint(e, cpos, cend)
  numtags = r[0]
  cpos = r[1]
  if numtags != 0
    numtags -= 1
    jxi_push32(out, numtags)
    pts = 128 + numtags * 12
    psz = 0
    while cpos < cend
      cmd = e[cpos]
      cpos += 1
      tc = cmd & 63
      break if tc == 0
      tag = nil
      if tc == 1
        jxi_fail("tag oob") if pos + 4 > size
        tag = [e[pos], e[pos + 1], e[pos + 2], e[pos + 3]]
        pos += 4
      elsif tc == 2
        tag = "rTRC"
      elsif tc == 3
        tag = "rXYZ"
      else
        jxi_fail("unknown tag code") if tc - 4 >= 17
        tag = JXI_TAGS[tc - 4]
      if tag.is_a?(Array)
        tag.each ->(b)
          out.push(b)
      else
        jxi_push_str(out, tag)
      tsz = psz
      if tag == "rXYZ" || tag == "gXYZ" || tag == "bXYZ" || tag == "kXYZ" || tag == "wtpt" || tag == "bkpt" || tag == "lumi"
        tsz = 20
      tst = 0
      if (cmd & 64) != 0
        r = jxi_varint(e, cpos, cend)
        tst = r[0]
        cpos = r[1]
      else
        tst = pts + psz
      jxi_push32(out, tst)
      if (cmd & 128) != 0
        r = jxi_varint(e, cpos, cend)
        tsz = r[0]
        cpos = r[1]
      jxi_push32(out, tsz)
      pts = tst
      psz = tsz
      if tc == 2
        jxi_push_str(out, "gTRC")
        jxi_push32(out, tst)
        jxi_push32(out, tsz)
        jxi_push_str(out, "bTRC")
        jxi_push32(out, tst)
        jxi_push32(out, tsz)
      if tc == 3
        jxi_push_str(out, "gXYZ")
        jxi_push32(out, tst + tsz)
        jxi_push32(out, tsz)
        jxi_push_str(out, "bXYZ")
        jxi_push32(out, tst + tsz * 2)
        jxi_push32(out, tsz)
  while cpos < cend
    jxi_fail("result too large") if out.size > osize
    cmd = e[cpos]
    cpos += 1
    if cmd == 1
      r = jxi_varint(e, cpos, cend)
      num = r[0]
      cpos = r[1]
      jxi_fail("insert oob") if pos + num > size
      k = 0
      while k < num
        out.push(e[pos + k])
        k += 1
      pos += num
    elsif cmd == 2 || cmd == 3
      r = jxi_varint(e, cpos, cend)
      num = r[0]
      cpos = r[1]
      jxi_fail("shuffle oob") if pos + num > size
      sh = []
      k = 0
      while k < num
        sh.push(e[pos + k])
        k += 1
      sh = jxi_shuffle(sh, cmd == 2 ? 2 : 4)
      sh.each ->(b)
        out.push(b)
      pos += num
    elsif cmd == 4
      jxi_fail("predict oob") if cpos + 2 > cend
      flags = e[cpos]
      cpos += 1
      width = (flags & 3) + 1
      jxi_fail("predict width") if width == 3
      order = (flags & 12) >> 2
      jxi_fail("predict order") if order == 3
      stride = width
      if (flags & 16) != 0
        r = jxi_varint(e, cpos, cend)
        stride = r[0]
        cpos = r[1]
        jxi_fail("stride") if stride < width
      jxi_fail("stride") if out.size == 0 || ((out.size - 1) >> 2) < stride
      r = jxi_varint(e, cpos, cend)
      num = r[0]
      cpos = r[1]
      jxi_fail("predict oob") if pos + num > size
      sh = []
      k = 0
      while k < num
        sh.push(e[pos + k])
        k += 1
      sh = jxi_shuffle(sh, width) if width > 1
      start = out.size
      k = 0
      while k < num
        pv = jxi_linear_pred(out, start, k, stride, width, order)
        out.push((pv + sh[k]) & 255)
        k += 1
      pos += num
    elsif cmd == 10
      jxi_push_str(out, "XYZ ")
      out.push(0)
      out.push(0)
      out.push(0)
      out.push(0)
      jxi_fail("xyz oob") if pos + 12 > size
      k = 0
      while k < 12
        out.push(e[pos + k])
        k += 1
      pos += 12
    elsif cmd >= 16 && cmd < 24
      jxi_push_str(out, JXI_TYPES[cmd - 16])
      out.push(0)
      out.push(0)
      out.push(0)
      out.push(0)
    else
      jxi_fail("unknown command")
  jxi_fail("size mismatch") if out.size != osize
  out

# core/codec/video/h264_intra — H.264 NxN (4x4 / 8x8) intra predictors, shared
# by the H.264 decoder (core/codec/video/h264_mb) and the VP8 video decoder,
# whose B_PRED modes are the same predictors.

# NxN directional prediction (4x4 or 8x8). top[0...2n] = p[x,-1] (top-right
# already substituted), left[0...n] = p[-1,y], tl = p[-1,-1]. avail bit0 left,
# bit1 top (DC only).
-> h264_pred_nxn(dst, d, stride, n, mode, top, left, tl, avail) (u8[] i64 i64 i64 i64 i64[] i64[] i64 i64) i64
  y = 0 ## i64
  if mode == 0
    while y < n
      x = 0 ## i64
      while x < n
        dst[d + y * stride + x] = top[x]
        x += 1
      y += 1
  elsif mode == 1
    while y < n
      x = 0 ## i64
      v = left[y]
      while x < n
        dst[d + y * stride + x] = v
        x += 1
      y += 1
  elsif mode == 2
    s = 0 ## i64
    k = 0 ## i64
    sh = n == 4 ? 2 : 3
    if (avail & 3) == 3
      while k < n
        s += top[k] + left[k]
        k += 1
      s = (s + n) >> (sh + 1)
    elsif (avail & 1) == 1
      while k < n
        s += left[k]
        k += 1
      s = (s + (n >> 1)) >> sh
    elsif (avail & 2) == 2
      while k < n
        s += top[k]
        k += 1
      s = (s + (n >> 1)) >> sh
    else
      s = 128
    while y < n
      x = 0 ## i64
      while x < n
        dst[d + y * stride + x] = s
        x += 1
      y += 1
  else
    # edge e: left bottom..top, tl, top: e[n-1-y] = left[y], e[n] = tl, e[n+1+x] = top[x]
    e = i64[40]
    k = 0 ## i64
    while k < n
      e[n - 1 - k] = left[k]
      k += 1
    e[n] = tl
    k = 0
    while k < 2 * n
      e[n + 1 + k] = top[k]
      k += 1
    while y < n
      x = 0 ## i64
      while x < n
        v = 0 ## i64
        if mode == 3
          if x == n - 1 && y == n - 1
            v = (top[2 * n - 2] + 3 * top[2 * n - 1] + 2) >> 2
          else
            v = (top[x + y] + 2 * top[x + y + 1] + top[x + y + 2] + 2) >> 2
        elsif mode == 4
          # position along the edge: top x-y-1 maps to e[n+1+x-y-1] = e[n+x-y]
          m = n + x - y
          v = (e[m - 1] + 2 * e[m] + e[m + 1] + 2) >> 2
        elsif mode == 5
          z = 2 * x - y
          if z >= 0 && (z & 1) == 0
            m = n + x - (y >> 1)
            v = (e[m] + e[m + 1] + 1) >> 1
          elsif z > 0
            m = n + 1 + x - (y >> 1) - 1
            v = (e[m - 1] + 2 * e[m] + e[m + 1] + 2) >> 2
          elsif z == -1
            v = (left[0] + 2 * tl + top[0] + 2) >> 2
          else
            m = n - 1 - (y - 2 * x - 2)
            v = (e[m + 1] + 2 * e[m] + e[m - 1] + 2) >> 2
        elsif mode == 6
          z = 2 * y - x
          if z >= 0 && (z & 1) == 0
            a = y - (x >> 1) - 1
            if a >= 0
              v = (left[a] + left[y - (x >> 1)] + 1) >> 1
            else
              v = (tl + left[y - (x >> 1)] + 1) >> 1
          elsif z > 0
            m = n - 1 - (y - (x >> 1) - 1)
            v = (e[m - 1] + 2 * e[m] + e[m + 1] + 2) >> 2
          elsif z == -1
            v = (left[0] + 2 * tl + top[0] + 2) >> 2
          else
            m = n + 1 + (x - 2 * y - 2)
            v = (e[m + 1] + 2 * e[m] + e[m - 1] + 2) >> 2
        elsif mode == 7
          i = x + (y >> 1)
          if (y & 1) == 0
            v = (top[i] + top[i + 1] + 1) >> 1
          else
            v = (top[i] + 2 * top[i + 1] + top[i + 2] + 2) >> 2
        else
          z = x + 2 * y
          i = y + (x >> 1)
          if z > 2 * n - 3
            v = left[n - 1]
          elsif z == 2 * n - 3
            v = (left[n - 2] + 3 * left[n - 1] + 2) >> 2
          elsif (z & 1) == 0
            v = (left[i] + left[i + 1] + 1) >> 1
          else
            v = (left[i] + 2 * left[i + 1] + left[i + 2] + 2) >> 2
        dst[d + y * stride + x] = v
        x += 1
      y += 1
  0

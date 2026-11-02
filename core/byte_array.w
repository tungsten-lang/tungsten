# ByteArray
#
# Length-counted, mutable, heap-allocated byte buffer. The dedicated
# WBytes struct was folded into WArray with ebits=8, so a
# `ByteArray` value is identical to `u8[N]` at the binary level.
# The runtime intercepts `ByteArray.new(n)` in dispatch and routes it
# through the WArray constructor with ebits=8.
#
# Stores a 1-byte encoding ID in WArray's header at offset 2 (`_pad[0]`),
# aligned 1-to-1 with CRuby's `Encoding.list` indices (0..102):
#   0      = ASCII-8BIT (BINARY — default for raw byte arrays)
#   1      = UTF-8
#   2      = US-ASCII
#   3      = UTF-16BE
#   4      = UTF-16LE
#   5      = UTF-32BE
#   6      = UTF-32LE
#   7      = UTF-16 (BOM-aware per Unicode Standard D98)
#   8      = UTF-32 (BOM-aware per Unicode Standard D101)
#   9      = UTF8-MAC (macOS NFD UTF-8)
#   15     = CESU-8 (Compatibility Encoding Scheme for UTF-16: 8-Bit)
#   22..36 = ISO-8859-1 .. ISO-8859-16
#   37..38 = KOI8-R, KOI8-U
#   40..45 = Windows-1250 .. Windows-1254, Windows-1257
#   46..63 = IBM437 .. IBM869, CP850, CP852, CP855
#   64     = Windows-1258
#   65     = GB1988
#   66..75 = macCentEuro .. macUkraine (including macRoman at 71)
#   78     = IBM037 (EBCDIC)
#   89..92 = Windows-1256, Windows-1255, TIS-620, Windows-874

+ ByteArray
  - data (WArray)
      u8[2] _header
      u8    encoding_id

  @@tbl_cp932 = nil
  @@tbl_euc_jp = nil
  @@tbl_gb18030 = nil
  @@tbl_big5 = nil
  @@tbl_cp949 = nil
  @@tbl_johab = nil
  @@utf_ebcdic_to_i8 = nil
  @@utf_i8_to_ebcdic = nil

  -> .__load_cjk_table(filename)
    path = nil
    if file?("build/encodings/" + filename)
      path = "build/encodings/" + filename
    if path == nil
      bh = env("BIT_HOME")
      if bh != nil && bh != ""
        cand = bh + "/encodings/" + filename
        if file?(cand)
          path = cand
    if path == nil
      th = env("TUNGSTEN_HOME")
      if th != nil && th != ""
        cand = th + "/encodings/" + filename
        if file?(cand)
          path = cand
    if path == nil
      h = env("HOME")
      if h != nil && h != ""
        cand = h + "/.tungsten/encodings/" + filename
        if file?(cand)
          path = cand
        else
          # Download or synthesize on demand into ~/.tungsten/encodings
          cache_dir = h + "/.tungsten/encodings"
          tbl_key = filename.replace(".bin", "")
          script = "scripts/gen_cjk_encodings.rb"
          if !file?(script)
            root = env("TUNGSTEN_ROOT")
            if root != nil && root != "" && file?(root + "/scripts/gen_cjk_encodings.rb")
              script = root + "/scripts/gen_cjk_encodings.rb"
            elsif file?(h + "/tungsten/scripts/gen_cjk_encodings.rb")
              script = h + "/tungsten/scripts/gen_cjk_encodings.rb"
          if file?(script)
            system("ruby \"" + script + "\" \"" + cache_dir + "\" \"" + tbl_key + "\" >/dev/null 2>&1")
            if file?(cand)
              path = cand
    if path == nil
      raise "missing encoding table " + filename + " (run `bit build` or `ruby scripts/gen_cjk_encodings.rb`)"
    raw = read_file_bytes(path)
    if raw == nil
      raise "could not read encoding table " + path
    if type(raw) == "String"
      return raw.bytes()
    raw

  -> .__cjk_table(enc_id)
    if enc_id == 11 || enc_id == 39 || enc_id == 93 || enc_id == 96 || enc_id == 98 || enc_id == 102
      if @@tbl_cp932 == nil
        @@tbl_cp932 = ByteArray.__load_cjk_table("cp932.bin")
      return @@tbl_cp932
    if enc_id == 10 || (enc_id >= 79 && enc_id <= 82) || (enc_id >= 85 && enc_id <= 88) || enc_id == 99 || enc_id == 100
      if @@tbl_euc_jp == nil
        @@tbl_euc_jp = ByteArray.__load_cjk_table("euc_jp.bin")
      return @@tbl_euc_jp
    if enc_id == 20 || enc_id == 21 || enc_id == 83 || enc_id == 84 || enc_id == 106
      if @@tbl_gb18030 == nil
        @@tbl_gb18030 = ByteArray.__load_cjk_table("gb18030.bin")
      return @@tbl_gb18030
    if enc_id == 12 || enc_id == 13 || enc_id == 14 || enc_id == 76 || enc_id == 77
      if @@tbl_big5 == nil
        @@tbl_big5 = ByteArray.__load_cjk_table("big5.bin")
      return @@tbl_big5
    if enc_id == 16 || enc_id == 18 || enc_id == 107
      if @@tbl_cp949 == nil
        @@tbl_cp949 = ByteArray.__load_cjk_table("cp949.bin")
      return @@tbl_cp949
    if enc_id == 127
      if @@tbl_johab == nil
        @@tbl_johab = ByteArray.__load_cjk_table("johab.bin")
      return @@tbl_johab
    nil

  -> .__b64_val(b, is_imap)
    if b >= 0x41 && b <= 0x5A
      return b - 0x41
    if b >= 0x61 && b <= 0x7A
      return b - 0x61 + 26
    if b >= 0x30 && b <= 0x39
      return b - 0x30 + 52
    if b == 0x2B
      return 62
    if !is_imap && b == 0x2F
      return 63
    if is_imap && b == 0x2C
      return 63
    -1

  -> .__b64_char(v, is_imap)
    if v < 26
      return 0x41 + v
    if v < 52
      return 0x61 + (v - 26)
    if v < 62
      return 0x30 + (v - 52)
    if v == 62
      return 0x2B
    is_imap ? 0x2C : 0x2F

  -> .__utf7_direct?(cp, is_imap)
    if is_imap
      return cp >= 0x20 && cp <= 0x7E && cp != 0x26
    if cp == 0x09 || cp == 0x0A || cp == 0x0D
      return true
    cp >= 0x20 && cp <= 0x7E && cp != 0x2B && cp != 0x5C && cp != 0x7E

  -> encoding_id
    $encoding_id

  -> __set_encoding_id(enc_id)
    $encoding_id = enc_id
    self

  -> encoding
    ByteArray.encoding_name($encoding_id)

  -> force_encoding(enc)
    enc_id = ByteArray.normalize_encoding(enc)
    $encoding_id = enc_id
    self

  # Validate whether this ByteArray is well-formed in `encoding` (or in its
  # own header encoding when called with no argument).
  -> valid_encoding?(encoding = nil)
    enc_id = encoding == nil ? $encoding_id : ByteArray.normalize_encoding(encoding)
    self.__valid_encoding_id?(enc_id)

  -> valid_utf8?
    self.__valid_encoding_id?(1)

  -> valid_ascii?
    self.__valid_encoding_id?(2)

  -> ascii?
    self.__valid_encoding_id?(2)

  -> __valid_encoding_id?(enc_id)
    n = self.size()
    if enc_id == 0 || enc_id == 22 || enc_id == 78 || enc_id == 105 || (enc_id >= 109 && enc_id <= 112) || (enc_id >= 114 && enc_id <= 115) || enc_id == 138 || enc_id == 139 || (enc_id >= 144 && enc_id <= 161) || enc_id == 163
      return true
    if enc_id == 113 || enc_id == 162
      tbl = ByteArray.__ebcdic_table(enc_id)
      i = 0
      while i < n
        if tbl[self[i]] < 0
          return false
        i += 1
      return true
    if enc_id == 129
      return self.__valid_wtf8?()
    if enc_id == 130
      return self.__decode_scsu_checked() != nil
    if enc_id == 131
      return self.__decode_bocu1_checked() != nil
    if enc_id == 132
      return self.__decode_utf_ebcdic_checked() != nil
    if enc_id == 133
      return self.__decode_utf1_checked() != nil
    if enc_id == 134
      return self.__decode_gsm0338_checked() != nil
    if enc_id == 137
      return self.__decode_ansel_checked() != nil
    if enc_id == 164
      return self.__decode_iso2022_cn_checked() != nil
    if enc_id == 1 || enc_id == 9 || enc_id == 95 || enc_id == 97 || enc_id == 101 || enc_id == 128
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0xC2 && b0 <= 0xDF
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if (b1 & 0xC0) != 0x80
            return false
          i += 2
        elsif b0 >= 0xE0 && b0 <= 0xEF
          if i + 2 >= n
            return false
          b1 = self[i + 1]
          b2 = self[i + 2]
          if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80
            return false
          if b0 == 0xE0 && b1 < 0xA0
            return false
          if b0 == 0xED && b1 >= 0xA0
            return false
          i += 3
        elsif b0 >= 0xF0 && b0 <= 0xF4
          if i + 3 >= n
            return false
          b1 = self[i + 1]
          b2 = self[i + 2]
          b3 = self[i + 3]
          if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80
            return false
          if b0 == 0xF0 && b1 < 0x90
            return false
          if b0 == 0xF4 && b1 >= 0x90
            return false
          i += 4
        else
          return false
      return true
    if enc_id == 2 || enc_id == 65
      i = 0
      while i < n
        if self[i] >= 0x80
          return false
        i += 1
      return true
    if enc_id == 15 || enc_id == 104
      i = 0
      while i < n
        b0 = self[i]
        if b0 == 0 && enc_id == 104
          return false
        if b0 < 0x80
          i += 1
        elsif enc_id == 104 && b0 == 0xC0
          if i + 1 >= n || self[i + 1] != 0x80
            return false
          i += 2
        elsif b0 >= 0xC2 && b0 <= 0xDF
          if i + 1 >= n || (self[i + 1] & 0xC0) != 0x80
            return false
          i += 2
        elsif b0 >= 0xE0 && b0 <= 0xEF
          if i + 2 >= n
            return false
          b1 = self[i + 1]
          b2 = self[i + 2]
          if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80
            return false
          if b0 == 0xE0 && b1 < 0xA0
            return false
          if b0 == 0xED && b1 >= 0xA0
            if b1 <= 0xAF
              if i + 5 >= n
                return false
              if self[i + 3] != 0xED || self[i + 4] < 0xB0 || self[i + 4] > 0xBF || (self[i + 5] & 0xC0) != 0x80
                return false
              i += 6
            else
              return false
          else
            i += 3
        else
          return false
      return true
    if enc_id == 94 || enc_id == 103
      is_imap = enc_id == 103
      shift_ch = is_imap ? 0x26 : 0x2B
      in_b64 = false
      bits = 0
      nbits = 0
      pend_hi = 0
      b64_chars = 0
      i = 0
      while i < n
        b = self[i]
        if b >= 0x80
          return false
        if !in_b64
          if b == shift_ch
            in_b64 = true
            bits = 0
            nbits = 0
            pend_hi = 0
            b64_chars = 0
          elsif is_imap && (b < 0x20 || b > 0x7E)
            return false
          i += 1
        else
          v = ByteArray.__b64_val(b, is_imap)
          if v >= 0
            bits = (bits << 6) | v
            nbits += 6
            b64_chars += 1
            if nbits >= 16
              nbits -= 16
              u = (bits >> nbits) & 0xFFFF
              bits = bits & ((1 << nbits) - 1)
              if pend_hi != 0
                if u < 0xDC00 || u > 0xDFFF
                  return false
                pend_hi = 0
              elsif u >= 0xD800 && u <= 0xDBFF
                pend_hi = u
              elsif u >= 0xDC00 && u <= 0xDFFF
                return false
            i += 1
          else
            if pend_hi != 0 || nbits >= 6 || bits != 0
              return false
            if is_imap && b != 0x2D
              return false
            in_b64 = false
            if b == 0x2D
              i += 1
            elsif b64_chars == 0
              return false
      return !in_b64 && pend_hi == 0
    if enc_id == 3 || enc_id == 4 || enc_id == 7
      if (n & 1) != 0
        return false
      le = enc_id == 4
      i = 0
      if enc_id == 7 && n >= 2
        if self[0] == 0xFE && self[1] == 0xFF
          le = false
          i = 2
        elsif self[0] == 0xFF && self[1] == 0xFE
          le = true
          i = 2
      while i < n
        u = le ? (self[i] | (self[i + 1] << 8)) : ((self[i] << 8) | self[i + 1])
        if u >= 0xD800 && u <= 0xDBFF
          if i + 3 >= n
            return false
          u2 = le ? (self[i + 2] | (self[i + 3] << 8)) : ((self[i + 2] << 8) | self[i + 3])
          if u2 < 0xDC00 || u2 > 0xDFFF
            return false
          i += 4
        elsif u >= 0xDC00 && u <= 0xDFFF
          return false
        else
          i += 2
      return true
    if enc_id == 5 || enc_id == 6 || enc_id == 8
      if (n & 3) != 0
        return false
      le = enc_id == 6
      i = 0
      if enc_id == 8 && n >= 4
        if self[0] == 0x00 && self[1] == 0x00 && self[2] == 0xFE && self[3] == 0xFF
          le = false
          i = 4
        elsif self[0] == 0xFF && self[1] == 0xFE && self[2] == 0x00 && self[3] == 0x00
          le = true
          i = 4
      while i < n
        cp = le ? (self[i] | (self[i + 1] << 8) | (self[i + 2] << 16) | (self[i + 3] << 24)) : ((self[i] << 24) | (self[i + 1] << 16) | (self[i + 2] << 8) | self[i + 3])
        if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
          return false
        i += 4
      return true
    if ByteArray.__single_byte_encoding?(enc_id)
      tbl = ByteArray.__single_byte_table(enc_id)
      i = 0
      while i < n
        b = self[i]
        if b >= 0x80 && tbl[b - 0x80] < 0
          return false
        i += 1
      return true
    if enc_id == 11 || enc_id == 39 || enc_id == 93 || enc_id == 96 || enc_id == 98 || enc_id == 102
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0xA1 && b0 <= 0xDF
          i += 1
        elsif (b0 >= 0x81 && b0 <= 0x9F) || (b0 >= 0xE0 && b0 <= (enc_id == 39 ? 0xEF : 0xFC))
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          off = ((b0 << 8) | b1) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
        else
          return false
      return true
    if enc_id == 10 || (enc_id >= 80 && enc_id <= 82)
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 == 0x8E || (b0 >= 0xA1 && b0 <= 0xFE)
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          off = ((b0 << 8) | b1) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
        else
          return false
      return true
    if enc_id == 79 || (enc_id >= 85 && enc_id <= 88) || enc_id == 99 || enc_id == 100
      tbl = ByteArray.__cjk_table(enc_id)
      mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 == 0x1B
          if i + 2 >= n
            return false
          b1 = self[i + 1]
          b2 = self[i + 2]
          if b1 == 0x28 && (b2 == 0x42 || b2 == 0x4A)
            mode = 0
          elsif b1 == 0x28 && b2 == 0x49
            mode = 1
          elsif b1 == 0x24 && (b2 == 0x42 || b2 == 0x40)
            mode = 2
          else
            return false
          i += 3
        elsif mode == 0
          if b0 >= 0x80
            return false
          i += 1
        elsif mode == 1
          if b0 < 0x21 || b0 > 0x5F
            return false
          i += 1
        else
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if b0 < 0x21 || b0 > 0x7E || b1 < 0x21 || b1 > 0x7E
            return false
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
      return mode == 0
    if enc_id == 20 || enc_id == 21 || enc_id == 83 || enc_id == 84
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0x81 && b0 <= 0xFE
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if b1 >= 0x40 && b1 <= 0xFE && b1 != 0x7F
            if enc_id == 83 && (b0 < 0xA1 || b0 > 0xF7 || b1 < 0xA1)
              return false
            off = ((b0 << 8) | b1) << 1
            if (tbl[off] | (tbl[off + 1] << 8)) == 0
              return false
            i += 2
          elsif enc_id == 20 && b1 >= 0x30 && b1 <= 0x39
            if i + 3 >= n
              return false
            b2 = self[i + 2]
            b3 = self[i + 3]
            if b2 < 0x81 || b2 > 0xFE || b3 < 0x30 || b3 > 0x39
              return false
            ptr = ((b0 - 0x81) * 10 + (b1 - 0x30)) * 1260 + (b2 - 0x81) * 10 + (b3 - 0x30)
            if ptr < 39420
              off = 262144 + (ptr << 1)
              if (tbl[off] | (tbl[off + 1] << 8)) == 0
                return false
            elsif ptr < 189000 || ptr > 1237575
              return false
            i += 4
          else
            return false
        else
          return false
      return true
    if enc_id == 12 || enc_id == 13 || enc_id == 14 || enc_id == 76 || enc_id == 77
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0x81 && b0 <= 0xFE
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          off = ((b0 << 8) | b1) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
        else
          return false
      return true
    if enc_id == 16 || enc_id == 18 || enc_id == 127
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= (enc_id == 18 ? 0xA1 : 0x81) && b0 <= 0xFE
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if enc_id == 18 && b1 < 0xA1
            return false
          off = ((b0 << 8) | b1) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
        else
          return false
      return true
    if enc_id == 17
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0x81 && b0 <= 0x8F
          if i + 1 >= n || self[i + 1] < 0xA0
            return false
          i += 2
        elsif b0 >= 0x90 && b0 <= 0x99
          if i + 2 >= n || self[i + 1] < 0xA0 || self[i + 2] < 0xA0
            return false
          i += 3
        else
          return false
      return true
    if enc_id == 19
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          i += 1
        elsif b0 >= 0xA1 && b0 <= 0xFE
          if i + 1 >= n || self[i + 1] < 0xA1 || self[i + 1] > 0xFE
            return false
          i += 2
        elsif b0 == 0x8E
          if i + 3 >= n || self[i + 1] < 0xA1 || self[i + 1] > 0xB0 || self[i + 2] < 0xA1 || self[i + 2] > 0xFE || self[i + 3] < 0xA1 || self[i + 3] > 0xFE
            return false
          i += 4
        else
          return false
      return true
    if enc_id == 106
      tbl = ByteArray.__cjk_table(enc_id)
      hz_mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 >= 0x80
          return false
        if b0 == 0x7E
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if b1 == 0x7B && hz_mode == 0
            hz_mode = 1
          elsif b1 == 0x7D && hz_mode == 1
            hz_mode = 0
          elsif b1 == 0x7E && hz_mode == 0
            hz_mode = 0
          elsif b1 == 0x0A
            hz_mode = hz_mode
          else
            return false
          i += 2
        elsif hz_mode == 0
          i += 1
        else
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if b0 < 0x21 || b0 > 0x77 || b1 < 0x21 || b1 > 0x7E
            return false
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
      return hz_mode == 0
    if enc_id == 107
      tbl = ByteArray.__cjk_table(enc_id)
      kr_mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 >= 0x80
          return false
        if b0 == 0x1B
          if i + 3 >= n || self[i + 1] != 0x24 || self[i + 2] != 0x29 || self[i + 3] != 0x43
            return false
          i += 4
        elsif b0 == 0x0E
          kr_mode = 1
          i += 1
        elsif b0 == 0x0F
          kr_mode = 0
          i += 1
        elsif kr_mode == 0
          i += 1
        else
          if i + 1 >= n
            return false
          b1 = self[i + 1]
          if b0 < 0x21 || b0 > 0x7E || b1 < 0x21 || b1 > 0x7E
            return false
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          if (tbl[off] | (tbl[off + 1] << 8)) == 0
            return false
          i += 2
      return kr_mode == 0
    false

  -> .__encoding_names
    ["ASCII-8BIT", "UTF-8", "US-ASCII", "UTF-16BE", "UTF-16LE", "UTF-32BE", "UTF-32LE", "UTF-16", "UTF-32", "UTF8-MAC", "EUC-JP", "Windows-31J", "Big5", "Big5-HKSCS", "Big5-UAO", "CESU-8", "CP949", "Emacs-Mule", "EUC-KR", "EUC-TW", "GB18030", "GBK", "ISO-8859-1", "ISO-8859-2", "ISO-8859-3", "ISO-8859-4", "ISO-8859-5", "ISO-8859-6", "ISO-8859-7", "ISO-8859-8", "ISO-8859-9", "ISO-8859-10", "ISO-8859-11", "ISO-8859-13", "ISO-8859-14", "ISO-8859-15", "ISO-8859-16", "KOI8-R", "KOI8-U", "Shift_JIS", "Windows-1250", "Windows-1251", "Windows-1252", "Windows-1253", "Windows-1254", "Windows-1257", "IBM437", "IBM720", "IBM737", "IBM775", "CP850", "IBM852", "CP852", "IBM855", "CP855", "IBM857", "IBM860", "IBM861", "IBM862", "IBM863", "IBM864", "IBM865", "IBM866", "IBM869", "Windows-1258", "GB1988", "macCentEuro", "macCroatian", "macCyrillic", "macGreek", "macIceland", "macRoman", "macRomania", "macThai", "macTurkish", "macUkraine", "CP950", "CP951", "IBM037", "stateless-ISO-2022-JP", "eucJP-ms", "CP51932", "EUC-JIS-2004", "GB2312", "GB12345", "ISO-2022-JP", "ISO-2022-JP-2", "CP50220", "CP50221", "Windows-1256", "Windows-1255", "TIS-620", "Windows-874", "MacJapanese", "UTF-7", "UTF8-DoCoMo", "SJIS-DoCoMo", "UTF8-KDDI", "SJIS-KDDI", "ISO-2022-JP-KDDI", "stateless-ISO-2022-JP-KDDI", "UTF8-SoftBank", "SJIS-SoftBank", "UTF-7-IMAP", "MUTF-8", "x-user-defined", "HZ-GB-2312", "ISO-2022-KR", "CP858", "IBM1047", "IBM1140", "IBM500", "IBM273", "IBM424", "IBM875", "IBM1026", "CP720", "CP856", "CP1006", "CP1125", "KOI8-T", "KZ-1048", "HP-Roman8", "macArabic", "macFarsi", "macHebrew", "PalmOS", "Johab", "UTF-8-SIG", "WTF-8", "SCSU", "BOCU-1", "UTF-EBCDIC", "UTF-1", "GSM-03.38", "DEC-MCS", "NeXTSTEP", "ANSEL", "VISCII", "TCVN-5712", "ISCII-91", "GEOSTD8", "ARMSCII-8", "KOI8-RU", "IBM277", "IBM1142", "IBM278", "IBM1143", "IBM280", "IBM1144", "IBM284", "IBM1145", "IBM285", "IBM1146", "IBM297", "IBM1147", "IBM1141", "IBM1148", "IBM871", "IBM1149", "IBM870", "IBM1025", "IBM420", "IBM838", "ISO-2022-CN"]

  -> .encoding_name(enc_id)
    names = ByteArray.__encoding_names()
    if enc_id >= 0 && enc_id < names.size()
      return names[enc_id]
    "UNKNOWN"

  -> .normalize_encoding(enc)
    if enc.is_a?(Int)
      if enc >= 0 && enc <= 164
        return enc
      raise "unknown encoding id: [enc]"
    if enc == :binary || enc == :ascii_8bit
      return 0
    if enc == :utf8 || enc == :utf_8
      return 1
    if enc == :ascii || enc == :us_ascii
      return 2
    if enc == :utf16be || enc == :utf_16be
      return 3
    if enc == :utf16le || enc == :utf_16le
      return 4
    if enc == :utf32be || enc == :utf_32be
      return 5
    if enc == :utf32le || enc == :utf_32le
      return 6
    if enc == :utf16 || enc == :utf_16
      return 7
    if enc == :utf32 || enc == :utf_32
      return 8
    if enc == :latin1 || enc == :iso_8859_1
      return 22
    if enc == :windows_1252 || enc == :cp1252
      return 42
    key = enc.to_s().downcase().replace("-", "").replace("_", "")
    if key == "ascii8bit" || key == "binary"
      return 0
    if key == "cp65001" || key == "utf8"
      return 1
    if key == "646" || key == "ansix3.41968" || key == "ascii" || key == "usascii"
      return 2
    if key == "ucs2be" || key == "utf16be"
      return 3
    if key == "utf16le" || key == "ucs2le"
      return 4
    if key == "utf32be" || key == "ucs4be"
      return 5
    if key == "utf32le" || key == "ucs4le"
      return 6
    if key == "utf16" || key == "ucs2"
      return 7
    if key == "utf32" || key == "ucs4"
      return 8
    if key == "utf8hfs" || key == "utf8mac"
      return 9
    if key == "eucjp"
      return 10
    if key == "pck" || key == "sjis" || key == "cswindows31j" || key == "cp932" || key == "windows31j"
      return 11
    if key == "big5"
      return 12
    if key == "big5hkscs" || key == "big5hkscs:2008"
      return 13
    if key == "big5uao"
      return 14
    if key == "cesu8"
      return 15
    if key == "cp949"
      return 16
    if key == "emacsmule"
      return 17
    if key == "euckr"
      return 18
    if key == "euctw"
      return 19
    if key == "gb18030"
      return 20
    if key == "cp936" || key == "gbk"
      return 21
    if key == "iso88591" || key == "latin1"
      return 22
    if key == "iso88592" || key == "latin2"
      return 23
    if key == "iso88593" || key == "latin3"
      return 24
    if key == "iso88594" || key == "latin4"
      return 25
    if key == "iso88595" || key == "cyrillic"
      return 26
    if key == "iso88596" || key == "arabic"
      return 27
    if key == "iso88597" || key == "greek"
      return 28
    if key == "hebrew" || key == "iso88598" || key == "iso88598i"
      return 29
    if key == "latin5" || key == "iso88599"
      return 30
    if key == "latin6" || key == "iso885910"
      return 31
    if key == "thai" || key == "iso885911"
      return 32
    if key == "iso885913" || key == "latin7"
      return 33
    if key == "latin8" || key == "iso885914"
      return 34
    if key == "latin9" || key == "iso885915"
      return 35
    if key == "latin10" || key == "iso885916"
      return 36
    if key == "koi8r" || key == "cp878"
      return 37
    if key == "koi8u"
      return 38
    if key == "shiftjis"
      return 39
    if key == "cp1250" || key == "windows1250"
      return 40
    if key == "cp1251" || key == "windows1251"
      return 41
    if key == "cp1252" || key == "windows1252"
      return 42
    if key == "cp1253" || key == "windows1253"
      return 43
    if key == "cp1254" || key == "windows1254"
      return 44
    if key == "windows1257" || key == "cp1257"
      return 45
    if key == "cp437" || key == "ibm437"
      return 46
    if key == "ibm720"
      return 47
    if key == "cp720"
      return 116
    if key == "cp737" || key == "ibm737"
      return 48
    if key == "cp775" || key == "ibm775"
      return 49
    if key == "ibm850" || key == "cp850"
      return 50
    if key == "ibm852"
      return 51
    if key == "cp852"
      return 52
    if key == "ibm855"
      return 53
    if key == "cp855"
      return 54
    if key == "ibm857" || key == "cp857"
      return 55
    if key == "ibm860" || key == "cp860"
      return 56
    if key == "ibm861" || key == "cp861"
      return 57
    if key == "cp862" || key == "ibm862"
      return 58
    if key == "cp863" || key == "ibm863"
      return 59
    if key == "ibm864" || key == "cp864"
      return 60
    if key == "cp865" || key == "ibm865"
      return 61
    if key == "cp866" || key == "ibm866"
      return 62
    if key == "cp869" || key == "ibm869"
      return 63
    if key == "cp1258" || key == "windows1258"
      return 64
    if key == "gb1988"
      return 65
    if key == "maccenteuro" || key == "maccentraleurope" || key == "maclatin2"
      return 66
    if key == "maccroatian"
      return 67
    if key == "maccyrillic"
      return 68
    if key == "macgreek"
      return 69
    if key == "maciceland"
      return 70
    if key == "macroman"
      return 71
    if key == "macromania"
      return 72
    if key == "macthai"
      return 73
    if key == "macturkish"
      return 74
    if key == "macukraine"
      return 75
    if key == "cp950"
      return 76
    if key == "cp951"
      return 77
    if key == "cp037" || key == "ibm037" || key == "ebcdiccpus"
      return 78
    if key == "statelessiso2022jp"
      return 79
    if key == "eucjpms"
      return 80
    if key == "cp51932"
      return 81
    if key == "eucjis2004" || key == "eucjisx0213"
      return 82
    if key == "euccn" || key == "gb2312"
      return 83
    if key == "gb12345"
      return 84
    if key == "iso2022jp"
      return 85
    if key == "iso2022jp2"
      return 86
    if key == "cp50220"
      return 87
    if key == "cp50221"
      return 88
    if key == "cp1256" || key == "windows1256"
      return 89
    if key == "cp1255" || key == "windows1255"
      return 90
    if key == "tis620"
      return 91
    if key == "cp874" || key == "windows874"
      return 92
    if key == "macjapan" || key == "macjapanese"
      return 93
    if key == "utf7" || key == "cp65000"
      return 94
    if key == "utf8docomo"
      return 95
    if key == "sjisdocomo"
      return 96
    if key == "utf8kddi"
      return 97
    if key == "sjiskddi"
      return 98
    if key == "iso2022jpkddi"
      return 99
    if key == "statelessiso2022jpkddi"
      return 100
    if key == "utf8softbank"
      return 101
    if key == "sjissoftbank"
      return 102
    if key == "utf7imap" || key == "imaputf7"
      return 103
    if key == "mutf8" || key == "modifiedutf8" || key == "cesu8java"
      return 104
    if key == "xuserdefined" || key == "userdefined"
      return 105
    if key == "hz" || key == "hzgb2312"
      return 106
    if key == "iso2022kr" || key == "csiso2022kr"
      return 107
    if key == "cp858" || key == "ibm858" || key == "ibm00858"
      return 108
    if key == "ibm1047" || key == "cp1047"
      return 109
    if key == "ibm1140" || key == "cp1140" || key == "ibm01140"
      return 110
    if key == "ibm500" || key == "cp500" || key == "ebcdiccpbe" || key == "ebcdiccpch"
      return 111
    if key == "ibm273" || key == "cp273"
      return 112
    if key == "ibm424" || key == "cp424" || key == "ebcdiccphe"
      return 113
    if key == "ibm875" || key == "cp875"
      return 114
    if key == "ibm1026" || key == "cp1026"
      return 115
    if key == "cp856" || key == "ibm856"
      return 117
    if key == "cp1006" || key == "ibm1006"
      return 118
    if key == "cp1125" || key == "ibm1125" || key == "cp866u" || key == "ruscii"
      return 119
    if key == "koi8t"
      return 120
    if key == "kz1048" || key == "ptcp154" || key == "rk1048" || key == "strk10482002"
      return 121
    if key == "hproman8" || key == "roman8" || key == "r8"
      return 122
    if key == "macarabic"
      return 123
    if key == "macfarsi"
      return 124
    if key == "machebrew"
      return 125
    if key == "palmos" || key == "palmlatin1"
      return 126
    if key == "johab" || key == "cp1361" || key == "ksc56011992"
      return 127
    if key == "utf8sig" || key == "utf8bom"
      return 128
    if key == "wtf8"
      return 129
    if key == "scsu" || key == "uts6"
      return 130
    if key == "bocu1" || key == "utn6"
      return 131
    if key == "utfebcdic" || key == "utr16"
      return 132
    if key == "utf1" || key == "iso10646utf1"
      return 133
    if key == "gsm0338" || key == "gsm03.38" || key == "gsm" || key == "gsm7" || key == "3gpp23038"
      return 134
    if key == "decmcs" || key == "dec" || key == "mcs" || key == "vtmcs"
      return 135
    if key == "nextstep" || key == "next" || key == "nextmultinational"
      return 136
    if key == "ansel" || key == "marc8" || key == "iso5426" || key == "gedcom"
      return 137
    if key == "viscii" || key == "csviscii" || key == "vscii"
      return 138
    if key == "tcvn5712" || key == "tcvn" || key == "vscii3"
      return 139
    if key == "iscii91" || key == "iscii" || key == "xiscii91" || key == "isciidev"
      return 140
    if key == "geostd8" || key == "georgianstd"
      return 141
    if key == "armscii8" || key == "armscii"
      return 142
    if key == "koi8ru"
      return 143
    if key == "ibm277" || key == "cp277" || key == "ebcdiccpdk" || key == "ebcdiccpno"
      return 144
    if key == "ibm1142" || key == "cp1142" || key == "ibm01142"
      return 145
    if key == "ibm278" || key == "cp278" || key == "ebcdiccpfi" || key == "ebcdiccpse"
      return 146
    if key == "ibm1143" || key == "cp1143" || key == "ibm01143"
      return 147
    if key == "ibm280" || key == "cp280" || key == "ebcdiccpit"
      return 148
    if key == "ibm1144" || key == "cp1144" || key == "ibm01144"
      return 149
    if key == "ibm284" || key == "cp284" || key == "ebcdiccpes"
      return 150
    if key == "ibm1145" || key == "cp1145" || key == "ibm01145"
      return 151
    if key == "ibm285" || key == "cp285" || key == "ebcdiccpgb"
      return 152
    if key == "ibm1146" || key == "cp1146" || key == "ibm01146"
      return 153
    if key == "ibm297" || key == "cp297" || key == "ebcdiccpfr"
      return 154
    if key == "ibm1147" || key == "cp1147" || key == "ibm01147"
      return 155
    if key == "ibm1141" || key == "cp1141" || key == "ibm01141"
      return 156
    if key == "ibm1148" || key == "cp1148" || key == "ibm01148"
      return 157
    if key == "ibm871" || key == "cp871" || key == "ebcdiccpis"
      return 158
    if key == "ibm1149" || key == "cp1149" || key == "ibm01149"
      return 159
    if key == "ibm870" || key == "cp870" || key == "ebcdiccproece"
      return 160
    if key == "ibm1025" || key == "cp1025"
      return 161
    if key == "ibm420" || key == "cp420" || key == "ebcdiccpar1"
      return 162
    if key == "ibm838" || key == "cp838" || key == "ibmthai"
      return 163
    if key == "iso2022cn" || key == "csiso2022cn"
      return 164
    raise "unknown encoding: [enc]"

  -> .__ebcdic_encoding?(enc_id)
    enc_id == 78 || (enc_id >= 109 && enc_id <= 115) || ByteArray.__extended_ebcdic_encoding?(enc_id)

  -> .__single_byte_encoding?(enc_id)
    (enc_id >= 22 && enc_id <= 38) || (enc_id >= 40 && enc_id <= 75) || enc_id == 78 || (enc_id >= 89 && enc_id <= 92) || enc_id == 108 || (enc_id >= 109 && enc_id <= 126) || ByteArray.__extended_single_byte_encoding?(enc_id) || ByteArray.__extended_ebcdic_encoding?(enc_id)

  -> .__single_byte_table(enc_id)
    if enc_id == 108 # CP858 (CP850 with Euro sign U+20AC at 0xD5)
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 248, 163, 216, 215, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 174, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 193, 194, 192, 169, 9571, 9553, 9559, 9565, 162, 165, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 227, 195, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 240, 208, 202, 203, 200, 8364, 205, 206, 207, 9496, 9484, 9608, 9604, 166, 204, 9600, 211, 223, 212, 210, 245, 213, 181, 254, 222, 218, 219, 217, 253, 221, 175, 180, 173, 177, 8215, 190, 182, 167, 247, 184, 176, 168, 183, 185, 179, 178, 9632, 160]
    if enc_id == 23 # ISO-8859-2
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 260, 728, 321, 164, 317, 346, 167, 168, 352, 350, 356, 377, 173, 381, 379, 176, 261, 731, 322, 180, 318, 347, 711, 184, 353, 351, 357, 378, 733, 382, 380, 340, 193, 194, 258, 196, 313, 262, 199, 268, 201, 280, 203, 282, 205, 206, 270, 272, 323, 327, 211, 212, 336, 214, 215, 344, 366, 218, 368, 220, 221, 354, 223, 341, 225, 226, 259, 228, 314, 263, 231, 269, 233, 281, 235, 283, 237, 238, 271, 273, 324, 328, 243, 244, 337, 246, 247, 345, 367, 250, 369, 252, 253, 355, 729]
    if enc_id == 24 # ISO-8859-3
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 294, 728, 163, 164, -1, 292, 167, 168, 304, 350, 286, 308, 173, -1, 379, 176, 295, 178, 179, 180, 181, 293, 183, 184, 305, 351, 287, 309, 189, -1, 380, 192, 193, 194, -1, 196, 266, 264, 199, 200, 201, 202, 203, 204, 205, 206, 207, -1, 209, 210, 211, 212, 288, 214, 215, 284, 217, 218, 219, 220, 364, 348, 223, 224, 225, 226, -1, 228, 267, 265, 231, 232, 233, 234, 235, 236, 237, 238, 239, -1, 241, 242, 243, 244, 289, 246, 247, 285, 249, 250, 251, 252, 365, 349, 729]
    if enc_id == 25 # ISO-8859-4
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 260, 312, 342, 164, 296, 315, 167, 168, 352, 274, 290, 358, 173, 381, 175, 176, 261, 731, 343, 180, 297, 316, 711, 184, 353, 275, 291, 359, 330, 382, 331, 256, 193, 194, 195, 196, 197, 198, 302, 268, 201, 280, 203, 278, 205, 206, 298, 272, 325, 332, 310, 212, 213, 214, 215, 216, 370, 218, 219, 220, 360, 362, 223, 257, 225, 226, 227, 228, 229, 230, 303, 269, 233, 281, 235, 279, 237, 238, 299, 273, 326, 333, 311, 244, 245, 246, 247, 248, 371, 250, 251, 252, 361, 363, 729]
    if enc_id == 26 # ISO-8859-5
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 173, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 8470, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113, 1114, 1115, 1116, 167, 1118, 1119]
    if enc_id == 27 # ISO-8859-6
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, -1, -1, -1, 164, -1, -1, -1, -1, -1, -1, -1, 1548, 173, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1563, -1, -1, -1, 1567, -1, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593, 1594, -1, -1, -1, -1, -1, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
    if enc_id == 28 # ISO-8859-7
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 8216, 8217, 163, 8364, 8367, 166, 167, 168, 169, 890, 171, 172, 173, -1, 8213, 176, 177, 178, 179, 900, 901, 902, 183, 904, 905, 906, 187, 908, 189, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, -1, 931, 932, 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, -1]
    if enc_id == 29 # ISO-8859-8
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, -1, 162, 163, 164, 165, 166, 167, 168, 169, 215, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 247, 187, 188, 189, 190, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 8215, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, -1, -1, 8206, 8207, -1]
    if enc_id == 30 # ISO-8859-9
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 286, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 304, 350, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 287, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 305, 351, 255]
    if enc_id == 31 # ISO-8859-10
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 260, 274, 290, 298, 296, 310, 167, 315, 272, 352, 358, 381, 173, 362, 330, 176, 261, 275, 291, 299, 297, 311, 183, 316, 273, 353, 359, 382, 8213, 363, 331, 256, 193, 194, 195, 196, 197, 198, 302, 268, 201, 280, 203, 278, 205, 206, 207, 208, 325, 332, 211, 212, 213, 214, 360, 216, 370, 218, 219, 220, 221, 222, 223, 257, 225, 226, 227, 228, 229, 230, 303, 269, 233, 281, 235, 279, 237, 238, 239, 240, 326, 333, 243, 244, 245, 246, 361, 248, 371, 250, 251, 252, 253, 254, 312]
    if enc_id == 32 # ISO-8859-11
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 3585, 3586, 3587, 3588, 3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599, 3600, 3601, 3602, 3603, 3604, 3605, 3606, 3607, 3608, 3609, 3610, 3611, 3612, 3613, 3614, 3615, 3616, 3617, 3618, 3619, 3620, 3621, 3622, 3623, 3624, 3625, 3626, 3627, 3628, 3629, 3630, 3631, 3632, 3633, 3634, 3635, 3636, 3637, 3638, 3639, 3640, 3641, 3642, -1, -1, -1, -1, 3647, 3648, 3649, 3650, 3651, 3652, 3653, 3654, 3655, 3656, 3657, 3658, 3659, 3660, 3661, 3662, 3663, 3664, 3665, 3666, 3667, 3668, 3669, 3670, 3671, 3672, 3673, 3674, 3675, -1, -1, -1, -1]
    if enc_id == 33 # ISO-8859-13
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 8221, 162, 163, 164, 8222, 166, 167, 216, 169, 342, 171, 172, 173, 174, 198, 176, 177, 178, 179, 8220, 181, 182, 183, 248, 185, 343, 187, 188, 189, 190, 230, 260, 302, 256, 262, 196, 197, 280, 274, 268, 201, 377, 278, 290, 310, 298, 315, 352, 323, 325, 211, 332, 213, 214, 215, 370, 321, 346, 362, 220, 379, 381, 223, 261, 303, 257, 263, 228, 229, 281, 275, 269, 233, 378, 279, 291, 311, 299, 316, 353, 324, 326, 243, 333, 245, 246, 247, 371, 322, 347, 363, 252, 380, 382, 8217]
    if enc_id == 34 # ISO-8859-14
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 7682, 7683, 163, 266, 267, 7690, 167, 7808, 169, 7810, 7691, 7922, 173, 174, 376, 7710, 7711, 288, 289, 7744, 7745, 182, 7766, 7809, 7767, 7811, 7776, 7923, 7812, 7813, 7777, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 372, 209, 210, 211, 212, 213, 214, 7786, 216, 217, 218, 219, 220, 221, 374, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 373, 241, 242, 243, 244, 245, 246, 7787, 248, 249, 250, 251, 252, 253, 375, 255]
    if enc_id == 35 # ISO-8859-15
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 8364, 165, 352, 167, 353, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 381, 181, 182, 183, 382, 185, 186, 187, 338, 339, 376, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]
    if enc_id == 36 # ISO-8859-16
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 260, 261, 321, 8364, 8222, 352, 167, 353, 169, 536, 171, 377, 173, 378, 379, 176, 177, 268, 322, 381, 8221, 182, 183, 382, 269, 537, 187, 338, 339, 376, 380, 192, 193, 194, 258, 196, 262, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 272, 323, 210, 211, 212, 336, 214, 346, 368, 217, 218, 219, 220, 280, 538, 223, 224, 225, 226, 259, 228, 263, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 273, 324, 242, 243, 244, 337, 246, 347, 369, 249, 250, 251, 252, 281, 539, 255]
    if enc_id == 37 # KOI8-R
      return [9472, 9474, 9484, 9488, 9492, 9496, 9500, 9508, 9516, 9524, 9532, 9600, 9604, 9608, 9612, 9616, 9617, 9618, 9619, 8992, 9632, 8729, 8730, 8776, 8804, 8805, 160, 8993, 176, 178, 183, 247, 9552, 9553, 9554, 1105, 9555, 9556, 9557, 9558, 9559, 9560, 9561, 9562, 9563, 9564, 9565, 9566, 9567, 9568, 9569, 1025, 9570, 9571, 9572, 9573, 9574, 9575, 9576, 9577, 9578, 9579, 9580, 169, 1102, 1072, 1073, 1094, 1076, 1077, 1092, 1075, 1093, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1103, 1088, 1089, 1090, 1091, 1078, 1074, 1100, 1099, 1079, 1096, 1101, 1097, 1095, 1098, 1070, 1040, 1041, 1062, 1044, 1045, 1060, 1043, 1061, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1071, 1056, 1057, 1058, 1059, 1046, 1042, 1068, 1067, 1047, 1064, 1069, 1065, 1063, 1066]
    if enc_id == 38 # KOI8-U
      return [9472, 9474, 9484, 9488, 9492, 9496, 9500, 9508, 9516, 9524, 9532, 9600, 9604, 9608, 9612, 9616, 9617, 9618, 9619, 8992, 9632, 8729, 8730, 8776, 8804, 8805, 160, 8993, 176, 178, 183, 247, 9552, 9553, 9554, 1105, 1108, 9556, 1110, 1111, 9559, 9560, 9561, 9562, 9563, 1169, 9565, 9566, 9567, 9568, 9569, 1025, 1028, 9571, 1030, 1031, 9574, 9575, 9576, 9577, 9578, 1168, 9580, 169, 1102, 1072, 1073, 1094, 1076, 1077, 1092, 1075, 1093, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1103, 1088, 1089, 1090, 1091, 1078, 1074, 1100, 1099, 1079, 1096, 1101, 1097, 1095, 1098, 1070, 1040, 1041, 1062, 1044, 1045, 1060, 1043, 1061, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1071, 1056, 1057, 1058, 1059, 1046, 1042, 1068, 1067, 1047, 1064, 1069, 1065, 1063, 1066]
    if enc_id == 40 # Windows-1250
      return [8364, -1, 8218, -1, 8222, 8230, 8224, 8225, -1, 8240, 352, 8249, 346, 356, 381, 377, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, 353, 8250, 347, 357, 382, 378, 160, 711, 728, 321, 164, 260, 166, 167, 168, 169, 350, 171, 172, 173, 174, 379, 176, 177, 731, 322, 180, 181, 182, 183, 184, 261, 351, 187, 317, 733, 318, 380, 340, 193, 194, 258, 196, 313, 262, 199, 268, 201, 280, 203, 282, 205, 206, 270, 272, 323, 327, 211, 212, 336, 214, 215, 344, 366, 218, 368, 220, 221, 354, 223, 341, 225, 226, 259, 228, 314, 263, 231, 269, 233, 281, 235, 283, 237, 238, 271, 273, 324, 328, 243, 244, 337, 246, 247, 345, 367, 250, 369, 252, 253, 355, 729]
    if enc_id == 41 # Windows-1251
      return [1026, 1027, 8218, 1107, 8222, 8230, 8224, 8225, 8364, 8240, 1033, 8249, 1034, 1036, 1035, 1039, 1106, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, 1113, 8250, 1114, 1116, 1115, 1119, 160, 1038, 1118, 1032, 164, 1168, 166, 167, 1025, 169, 1028, 171, 172, 173, 174, 1031, 176, 177, 1030, 1110, 1169, 181, 182, 183, 1105, 8470, 1108, 187, 1112, 1029, 1109, 1111, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103]
    if enc_id == 42 # Windows-1252
      return [8364, -1, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, -1, 381, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, -1, 382, 376, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]
    if enc_id == 43 # Windows-1253
      return [8364, -1, 8218, 402, 8222, 8230, 8224, 8225, -1, 8240, -1, 8249, -1, -1, -1, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, -1, 8250, -1, -1, -1, -1, 160, 901, 902, 163, 164, 165, 166, 167, 168, 169, -1, 171, 172, 173, 174, 8213, 176, 177, 178, 179, 900, 181, 182, 183, 904, 905, 906, 187, 908, 189, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, -1, 931, 932, 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, -1]
    if enc_id == 44 # Windows-1254
      return [8364, -1, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, -1, -1, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, -1, -1, 376, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 286, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 304, 350, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 287, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 305, 351, 255]
    if enc_id == 45 # Windows-1257
      return [8364, -1, 8218, -1, 8222, 8230, 8224, 8225, -1, 8240, -1, 8249, -1, 168, 711, 184, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, -1, 8250, -1, 175, 731, -1, 160, -1, 162, 163, 164, -1, 166, 167, 216, 169, 342, 171, 172, 173, 174, 198, 176, 177, 178, 179, 180, 181, 182, 183, 248, 185, 343, 187, 188, 189, 190, 230, 260, 302, 256, 262, 196, 197, 280, 274, 268, 201, 377, 278, 290, 310, 298, 315, 352, 323, 325, 211, 332, 213, 214, 215, 370, 321, 346, 362, 220, 379, 381, 223, 261, 303, 257, 263, 228, 229, 281, 275, 269, 233, 378, 279, 291, 311, 299, 316, 353, 324, 326, 243, 333, 245, 246, 247, 371, 322, 347, 363, 252, 380, 382, 729]
    if enc_id == 46 # IBM437
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 162, 163, 165, 8359, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 8976, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 47 # IBM720
      return [-1, -1, 233, 226, -1, 224, -1, 231, 234, 235, 232, 239, 238, -1, -1, -1, -1, 1617, 1618, 244, 164, 1600, 251, 249, 1569, 1570, 1571, 1572, 163, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 1590, 1591, 1592, 1593, 1594, 1601, 181, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 8801, 1611, 1612, 1613, 1614, 1615, 1616, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 48 # IBM737
      return [913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 931, 932, 933, 934, 935, 936, 937, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 963, 962, 964, 965, 966, 967, 968, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 969, 940, 941, 942, 970, 943, 972, 973, 971, 974, 902, 904, 905, 906, 908, 910, 911, 177, 8805, 8804, 938, 939, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 49 # IBM775
      return [262, 252, 233, 257, 228, 291, 229, 263, 322, 275, 342, 343, 299, 377, 196, 197, 201, 230, 198, 333, 246, 290, 162, 346, 347, 214, 220, 248, 163, 216, 215, 164, 256, 298, 243, 379, 380, 378, 8221, 166, 169, 174, 172, 189, 188, 321, 171, 187, 9617, 9618, 9619, 9474, 9508, 260, 268, 280, 278, 9571, 9553, 9559, 9565, 302, 352, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 370, 362, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 381, 261, 269, 281, 279, 303, 353, 371, 363, 382, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 211, 223, 332, 323, 245, 213, 181, 324, 310, 311, 315, 316, 326, 274, 325, 8217, 173, 177, 8220, 190, 182, 167, 247, 8222, 176, 8729, 183, 185, 179, 178, 9632, 160]
    if enc_id == 50 # CP850
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 248, 163, 216, 215, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 174, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 193, 194, 192, 169, 9571, 9553, 9559, 9565, 162, 165, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 227, 195, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 240, 208, 202, 203, 200, 305, 205, 206, 207, 9496, 9484, 9608, 9604, 166, 204, 9600, 211, 223, 212, 210, 245, 213, 181, 254, 222, 218, 219, 217, 253, 221, 175, 180, 173, 177, 8215, 190, 182, 167, 247, 184, 176, 168, 183, 185, 179, 178, 9632, 160]
    if enc_id == 51 # IBM852
      return [199, 252, 233, 226, 228, 367, 263, 231, 322, 235, 336, 337, 238, 377, 196, 262, 201, 313, 314, 244, 246, 317, 318, 346, 347, 214, 220, 356, 357, 321, 215, 269, 225, 237, 243, 250, 260, 261, 381, 382, 280, 281, 172, 378, 268, 351, 171, 187, 9617, 9618, 9619, 9474, 9508, 193, 194, 282, 350, 9571, 9553, 9559, 9565, 379, 380, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 258, 259, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 273, 272, 270, 203, 271, 327, 205, 206, 283, 9496, 9484, 9608, 9604, 354, 366, 9600, 211, 223, 212, 323, 324, 328, 352, 353, 340, 218, 341, 368, 253, 221, 355, 180, 173, 733, 731, 711, 728, 167, 247, 184, 176, 168, 729, 369, 344, 345, 9632, 160]
    if enc_id == 52 # CP852
      return [199, 252, 233, 226, 228, 367, 263, 231, 322, 235, 336, 337, 238, 377, 196, 262, 201, 313, 314, 244, 246, 317, 318, 346, 347, 214, 220, 356, 357, 321, 215, 269, 225, 237, 243, 250, 260, 261, 381, 382, 280, 281, 172, 378, 268, 351, 171, 187, 9617, 9618, 9619, 9474, 9508, 193, 194, 282, 350, 9571, 9553, 9559, 9565, 379, 380, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 258, 259, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 273, 272, 270, 203, 271, 327, 205, 206, 283, 9496, 9484, 9608, 9604, 354, 366, 9600, 211, 223, 212, 323, 324, 328, 352, 353, 340, 218, 341, 368, 253, 221, 355, 180, 173, 733, 731, 711, 728, 167, 247, 184, 176, 168, 729, 369, 344, 345, 9632, 160]
    if enc_id == 53 # IBM855
      return [1106, 1026, 1107, 1027, 1105, 1025, 1108, 1028, 1109, 1029, 1110, 1030, 1111, 1031, 1112, 1032, 1113, 1033, 1114, 1034, 1115, 1035, 1116, 1036, 1118, 1038, 1119, 1039, 1102, 1070, 1098, 1066, 1072, 1040, 1073, 1041, 1094, 1062, 1076, 1044, 1077, 1045, 1092, 1060, 1075, 1043, 171, 187, 9617, 9618, 9619, 9474, 9508, 1093, 1061, 1080, 1048, 9571, 9553, 9559, 9565, 1081, 1049, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 1082, 1050, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 1083, 1051, 1084, 1052, 1085, 1053, 1086, 1054, 1087, 9496, 9484, 9608, 9604, 1055, 1103, 9600, 1071, 1088, 1056, 1089, 1057, 1090, 1058, 1091, 1059, 1078, 1046, 1074, 1042, 1100, 1068, 8470, 173, 1099, 1067, 1079, 1047, 1096, 1064, 1101, 1069, 1097, 1065, 1095, 1063, 167, 9632, 160]
    if enc_id == 54 # CP855
      return [1106, 1026, 1107, 1027, 1105, 1025, 1108, 1028, 1109, 1029, 1110, 1030, 1111, 1031, 1112, 1032, 1113, 1033, 1114, 1034, 1115, 1035, 1116, 1036, 1118, 1038, 1119, 1039, 1102, 1070, 1098, 1066, 1072, 1040, 1073, 1041, 1094, 1062, 1076, 1044, 1077, 1045, 1092, 1060, 1075, 1043, 171, 187, 9617, 9618, 9619, 9474, 9508, 1093, 1061, 1080, 1048, 9571, 9553, 9559, 9565, 1081, 1049, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 1082, 1050, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 1083, 1051, 1084, 1052, 1085, 1053, 1086, 1054, 1087, 9496, 9484, 9608, 9604, 1055, 1103, 9600, 1071, 1088, 1056, 1089, 1057, 1090, 1058, 1091, 1059, 1078, 1046, 1074, 1042, 1100, 1068, 8470, 173, 1099, 1067, 1079, 1047, 1096, 1064, 1101, 1069, 1097, 1065, 1095, 1063, 167, 9632, 160]
    if enc_id == 55 # IBM857
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 305, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 304, 214, 220, 248, 163, 216, 350, 351, 225, 237, 243, 250, 241, 209, 286, 287, 191, 174, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 193, 194, 192, 169, 9571, 9553, 9559, 9565, 162, 165, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 227, 195, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, 186, 170, 202, 203, 200, -1, 205, 206, 207, 9496, 9484, 9608, 9604, 166, 204, 9600, 211, 223, 212, 210, 245, 213, 181, -1, 215, 218, 219, 217, 236, 255, 175, 180, 173, 177, -1, 190, 182, 167, 247, 184, 176, 168, 183, 185, 179, 178, 9632, 160]
    if enc_id == 56 # IBM860
      return [199, 252, 233, 226, 227, 224, 193, 231, 234, 202, 232, 205, 212, 236, 195, 194, 201, 192, 200, 244, 245, 242, 218, 249, 204, 213, 220, 162, 163, 217, 8359, 211, 225, 237, 243, 250, 241, 209, 170, 186, 191, 210, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 57 # IBM861
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 208, 240, 222, 196, 197, 201, 230, 198, 244, 246, 254, 251, 221, 253, 214, 220, 248, 163, 216, 8359, 402, 225, 237, 243, 250, 193, 205, 211, 218, 191, 8976, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 58 # IBM862
      return [1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, 162, 163, 165, 8359, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 8976, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 59 # IBM863
      return [199, 252, 233, 226, 194, 224, 182, 231, 234, 235, 232, 239, 238, 8215, 192, 167, 201, 200, 202, 244, 203, 207, 251, 249, 164, 212, 220, 162, 163, 217, 219, 402, 166, 180, 243, 250, 168, 184, 179, 175, 206, 8976, 172, 189, 188, 190, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 60 # IBM864
      return [176, 183, 8729, 8730, 9618, 9472, 9474, 9532, 9508, 9516, 9500, 9524, 9488, 9484, 9492, 9496, 946, 8734, 966, 177, 189, 188, 8776, 171, 187, 65271, 65272, -1, -1, 65275, 65276, 65139, 160, 173, 65154, 163, 164, 65156, -1, 8364, 65166, 65167, 65173, 65177, 1548, 65181, 65185, 65189, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641, 65233, 1563, 65201, 65205, 65209, 1567, 162, 65152, 65153, 65155, 65157, 65226, 65163, 65165, 65169, 65171, 65175, 65179, 65183, 65187, 65191, 65193, 65195, 65197, 65199, 65203, 65207, 65211, 65215, 65217, 65221, 65227, 65231, 166, 172, 247, 215, 65225, 1600, 65235, 65239, 65243, 65247, 65251, 65255, 65259, 65261, 65263, 65267, 65213, 65228, 65230, 65229, 65249, 65149, 1617, 65253, 65257, 65260, 65264, 65266, 65232, 65237, 65269, 65270, 65245, 65241, 65265, 9632, -1]
    if enc_id == 61 # IBM865
      return [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 248, 163, 216, 8359, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 8976, 172, 189, 188, 161, 171, 164, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 62 # IBM866
      return [1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 1025, 1105, 1028, 1108, 1031, 1111, 1038, 1118, 176, 8729, 183, 8730, 8470, 164, 9632, 160]
    if enc_id == 63 # IBM869
      return [-1, -1, -1, -1, -1, -1, 902, -1, 183, 172, 166, 8216, 8217, 904, 8213, 905, 906, 938, 908, -1, -1, 910, 939, 169, 911, 178, 179, 940, 163, 941, 942, 943, 970, 912, 972, 973, 913, 914, 915, 916, 917, 918, 919, 189, 920, 921, 171, 187, 9617, 9618, 9619, 9474, 9508, 922, 923, 924, 925, 9571, 9553, 9559, 9565, 926, 927, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 928, 929, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 931, 932, 933, 934, 935, 936, 937, 945, 946, 947, 9496, 9484, 9608, 9604, 948, 949, 9600, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 963, 962, 964, 900, 173, 177, 965, 966, 967, 167, 968, 901, 176, 168, 969, 971, 944, 974, 9632, 160]
    if enc_id == 64 # Windows-1258
      return [8364, -1, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, -1, 8249, 338, -1, -1, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, -1, 8250, 339, -1, -1, 376, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 258, 196, 197, 198, 199, 200, 201, 202, 203, 768, 205, 206, 207, 272, 209, 777, 211, 212, 416, 214, 215, 216, 217, 218, 219, 220, 431, 771, 223, 224, 225, 226, 259, 228, 229, 230, 231, 232, 233, 234, 235, 769, 237, 238, 239, 273, 241, 803, 243, 244, 417, 246, 247, 248, 249, 250, 251, 252, 432, 8363, 255]
    if enc_id == 66 # macCentEuro
      return [196, 256, 257, 201, 260, 214, 220, 225, 261, 268, 228, 269, 262, 263, 233, 377, 378, 270, 237, 271, 274, 275, 278, 243, 279, 244, 246, 245, 250, 282, 283, 252, 8224, 176, 280, 163, 167, 8226, 182, 223, 174, 169, 8482, 281, 168, 8800, 291, 302, 303, 298, 8804, 8805, 299, 310, 8706, 8721, 322, 315, 316, 317, 318, 313, 314, 325, 326, 323, 172, 8730, 324, 327, 8710, 171, 187, 8230, 160, 328, 336, 213, 337, 332, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 333, 340, 341, 344, 8249, 8250, 345, 342, 343, 352, 8218, 8222, 353, 346, 347, 193, 356, 357, 205, 381, 382, 362, 211, 212, 363, 366, 218, 367, 368, 369, 370, 371, 221, 253, 311, 379, 321, 380, 290, 711]
    if enc_id == 67 # macCroatian
      return [196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 8224, 176, 162, 163, 167, 8226, 182, 223, 174, 352, 8482, 180, 168, 8800, 381, 216, 8734, 177, 8804, 8805, 8710, 181, 8706, 8721, 8719, 353, 8747, 170, 186, 8486, 382, 248, 191, 161, 172, 8730, 402, 8776, 262, 171, 268, 8230, 160, 192, 195, 213, 338, 339, 272, 8212, 8220, 8221, 8216, 8217, 247, 9674, -1, 169, 8260, 164, 8249, 8250, 198, 187, 8211, 183, 8218, 8222, 8240, 194, 263, 193, 269, 200, 205, 206, 207, 204, 211, 212, 273, 210, 218, 219, 217, 305, 710, 732, 175, 960, 203, 730, 184, 202, 230, 711]
    if enc_id == 68 # macCyrillic
      return [1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 8224, 176, 162, 163, 167, 8226, 182, 1030, 174, 169, 8482, 1026, 1106, 8800, 1027, 1107, 8734, 177, 8804, 8805, 1110, 181, 8706, 1032, 1028, 1108, 1031, 1111, 1033, 1113, 1034, 1114, 1112, 1029, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 1035, 1115, 1036, 1116, 1109, 8211, 8212, 8220, 8221, 8216, 8217, 247, 8222, 1038, 1118, 1039, 1119, 8470, 1025, 1105, 1103, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 164]
    if enc_id == 69 # macGreek
      return [196, 185, 178, 201, 179, 214, 220, 901, 224, 226, 228, 900, 168, 231, 233, 232, 234, 235, 163, 8482, 238, 239, 8226, 189, 8240, 244, 246, 166, 173, 249, 251, 252, 8224, 915, 916, 920, 923, 926, 928, 223, 174, 169, 931, 938, 167, 8800, 176, 903, 913, 177, 8804, 8805, 165, 914, 917, 918, 919, 921, 922, 924, 934, 939, 936, 937, 940, 925, 172, 927, 929, 8776, 932, 171, 187, 8230, 160, 933, 935, 902, 904, 339, 8211, 8213, 8220, 8221, 8216, 8217, 247, 905, 906, 908, 910, 941, 942, 943, 972, 911, 973, 945, 946, 968, 948, 949, 966, 947, 951, 953, 958, 954, 955, 956, 957, 959, 960, 974, 961, 963, 964, 952, 969, 962, 967, 965, 950, 970, 971, 912, 944, -1]
    if enc_id == 70 # macIceland
      return [196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 221, 176, 162, 163, 167, 8226, 182, 223, 174, 169, 8482, 180, 168, 8800, 198, 216, 8734, 177, 8804, 8805, 165, 181, 8706, 8721, 8719, 960, 8747, 170, 186, 8486, 230, 248, 191, 161, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 192, 195, 213, 338, 339, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 255, 376, 8260, 164, 208, 240, 222, 254, 253, 183, 8218, 8222, 8240, 194, 202, 193, 203, 200, 205, 206, 207, 204, 211, 212, -1, 210, 218, 219, 217, 305, 710, 732, 175, 728, 729, 730, 184, 733, 731, 711]
    if enc_id == 71 # macRoman
      return [196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 8224, 176, 162, 163, 167, 8226, 182, 223, 174, 169, 8482, 180, 168, 8800, 198, 216, 8734, 177, 8804, 8805, 165, 181, 8706, 8721, 8719, 960, 8747, 170, 186, 8486, 230, 248, 191, 161, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 192, 195, 213, 338, 339, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 255, 376, 8260, 164, 8249, 8250, 64257, 64258, 8225, 183, 8218, 8222, 8240, 194, 202, 193, 203, 200, 205, 206, 207, 204, 211, 212, -1, 210, 218, 219, 217, 305, 710, 732, 175, 728, 729, 730, 184, 733, 731, 711]
    if enc_id == 72 # macRomania
      return [196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 8224, 176, 162, 163, 167, 8226, 182, 223, 174, 169, 8482, 180, 168, 8800, 258, 350, 8734, 177, 8804, 8805, 165, 181, 8706, 8721, 8719, 960, 8747, 170, 186, 8486, 259, 351, 191, 161, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 192, 195, 213, 338, 339, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 255, 376, 8260, 164, 8249, 8250, 354, 355, 8225, 183, 8218, 8222, 8240, 194, 202, 193, 203, 200, 205, 206, 207, 204, 211, 212, -1, 210, 218, 219, 217, 305, 710, 732, 175, 728, 729, 730, 184, 733, 731, 711]
    if enc_id == 73 # macThai
      return [171, 187, 8230, 3656, 3657, 3658, 3659, 3660, 3656, 3657, 3658, 3659, 3660, 8220, 8221, 3661, -1, 8226, 3633, 3655, 3636, 3637, 3638, 3639, 3656, 3657, 3658, 3659, 3660, 8216, 8217, -1, 160, 3585, 3586, 3587, 3588, 3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599, 3600, 3601, 3602, 3603, 3604, 3605, 3606, 3607, 3608, 3609, 3610, 3611, 3612, 3613, 3614, 3615, 3616, 3617, 3618, 3619, 3620, 3621, 3622, 3623, 3624, 3625, 3626, 3627, 3628, 3629, 3630, 3631, 3632, 3633, 3634, 3635, 3636, 3637, 3638, 3639, 3640, 3641, 3642, 8288, 8203, 8211, 8212, 3647, 3648, 3649, 3650, 3651, 3652, 3653, 3654, 3655, 3656, 3657, 3658, 3659, 3660, 3661, 8482, 3663, 3664, 3665, 3666, 3667, 3668, 3669, 3670, 3671, 3672, 3673, 174, 169, -1, -1, -1, -1]
    if enc_id == 74 # macTurkish
      return [196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 8224, 176, 162, 163, 167, 8226, 182, 223, 174, 169, 8482, 180, 168, 8800, 198, 216, 8734, 177, 8804, 8805, 165, 181, 8706, 8721, 8719, 960, 8747, 170, 186, 8486, 230, 248, 191, 161, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 192, 195, 213, 338, 339, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 255, 376, 286, 287, 304, 305, 350, 351, 8225, 183, 8218, 8222, 8240, 194, 202, 193, 203, 200, 205, 206, 207, 204, 211, 212, -1, 210, 218, 219, 217, -1, 710, 732, 175, 728, 729, 730, 184, 733, 731, 711]
    if enc_id == 75 # macUkraine
      return [1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 8224, 176, 1168, 163, 167, 8226, 182, 1030, 174, 169, 8482, 1026, 1106, 8800, 1027, 1107, 8734, 177, 8804, 8805, 1110, 181, 1169, 1032, 1028, 1108, 1031, 1111, 1033, 1113, 1034, 1114, 1112, 1029, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 1035, 1115, 1036, 1116, 1109, 8211, 8212, 8220, 8221, 8216, 8217, 247, 8222, 1038, 1118, 1039, 1119, 8470, 1025, 1105, 1103, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 164]
    if enc_id == 89 # Windows-1256
      return [8364, 1662, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 1657, 8249, 338, 1670, 1688, 1672, 1711, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 1705, 8482, 1681, 8250, 339, 8204, 8205, 1722, 160, 1548, 162, 163, 164, 165, 166, 167, 168, 169, 1726, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 1563, 187, 188, 189, 190, 1567, 1729, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 215, 1591, 1592, 1593, 1594, 1600, 1601, 1602, 1603, 224, 1604, 226, 1605, 1606, 1607, 1608, 231, 232, 233, 234, 235, 1609, 1610, 238, 239, 1611, 1612, 1613, 1614, 244, 1615, 1616, 247, 1617, 249, 1618, 251, 252, 8206, 8207, 1746]
    if enc_id == 90 # Windows-1255
      return [8364, -1, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, -1, 8249, -1, -1, -1, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, -1, 8250, -1, -1, -1, -1, 160, 161, 162, 163, 8362, 165, 166, 167, 168, 169, 215, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 247, 187, 188, 189, 190, 191, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465, 1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1520, 1521, 1522, 1523, 1524, -1, -1, -1, -1, -1, -1, -1, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, -1, -1, 8206, 8207, -1]
    if enc_id == 91 # TIS-620
      return [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 3585, 3586, 3587, 3588, 3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599, 3600, 3601, 3602, 3603, 3604, 3605, 3606, 3607, 3608, 3609, 3610, 3611, 3612, 3613, 3614, 3615, 3616, 3617, 3618, 3619, 3620, 3621, 3622, 3623, 3624, 3625, 3626, 3627, 3628, 3629, 3630, 3631, 3632, 3633, 3634, 3635, 3636, 3637, 3638, 3639, 3640, 3641, 3642, -1, -1, -1, -1, 3647, 3648, 3649, 3650, 3651, 3652, 3653, 3654, 3655, 3656, 3657, 3658, 3659, 3660, 3661, 3662, 3663, 3664, 3665, 3666, 3667, 3668, 3669, 3670, 3671, 3672, 3673, 3674, 3675, -1, -1, -1, -1]
    if enc_id == 92 # Windows-874
      return [8364, -1, -1, -1, -1, 8230, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, -1, -1, -1, -1, -1, -1, -1, 160, 3585, 3586, 3587, 3588, 3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599, 3600, 3601, 3602, 3603, 3604, 3605, 3606, 3607, 3608, 3609, 3610, 3611, 3612, 3613, 3614, 3615, 3616, 3617, 3618, 3619, 3620, 3621, 3622, 3623, 3624, 3625, 3626, 3627, 3628, 3629, 3630, 3631, 3632, 3633, 3634, 3635, 3636, 3637, 3638, 3639, 3640, 3641, 3642, -1, -1, -1, -1, 3647, 3648, 3649, 3650, 3651, 3652, 3653, 3654, 3655, 3656, 3657, 3658, 3659, 3660, 3661, 3662, 3663, 3664, 3665, 3666, 3667, 3668, 3669, 3670, 3671, 3672, 3673, 3674, 3675, -1, -1, -1, -1]
    if enc_id == 116 # CP720
      return [128, 129, 233, 226, 132, 224, 134, 231, 234, 235, 232, 239, 238, 141, 142, 143, 144, 1617, 1618, 244, 164, 1600, 251, 249, 1569, 1570, 1571, 1572, 163, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 1590, 1591, 1592, 1593, 1594, 1601, 181, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 8801, 1611, 1612, 1613, 1614, 1615, 1616, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]
    if enc_id == 117 # CP856
      return [1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, -1, 163, -1, 215, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 174, 172, 189, 188, -1, 171, 187, 9617, 9618, 9619, 9474, 9508, -1, -1, -1, 169, 9571, 9553, 9559, 9565, 162, 165, 9488, 9492, 9524, 9516, 9500, 9472, 9532, -1, -1, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 164, -1, -1, -1, -1, -1, -1, -1, -1, -1, 9496, 9484, 9608, 9604, 166, -1, 9600, -1, -1, -1, -1, -1, -1, 181, -1, -1, -1, -1, -1, -1, -1, 175, 180, 173, 177, 8215, 190, 182, 167, 247, 184, 176, 168, 183, 185, 179, 178, 9632, 160]
    if enc_id == 118 # CP1006
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785, 1548, 1563, 173, 1567, 65153, 65165, 65166, 65166, 65167, 65169, 64342, 64344, 65171, 65173, 65175, 64358, 64360, 65177, 65179, 65181, 65183, 64378, 64380, 65185, 65187, 65189, 65191, 65193, 64388, 65195, 65197, 64396, 65199, 64394, 65201, 65203, 65205, 65207, 65209, 65211, 65213, 65215, 65217, 65221, 65225, 65226, 65227, 65228, 65229, 65230, 65231, 65232, 65233, 65235, 65237, 65239, 65241, 65243, 64402, 64404, 65245, 65247, 65248, 65249, 65251, 64414, 65253, 65255, 65157, 65261, 64422, 64424, 64425, 64426, 65152, 65161, 65162, 65163, 65265, 65266, 65267, 64432, 64430, 65148, 65149]
    if enc_id == 119 # CP1125
      return [1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 1025, 1105, 1168, 1169, 1028, 1108, 1030, 1110, 1031, 1111, 183, 8730, 8470, 164, 9632, 160]
    if enc_id == 120 # KOI8-T
      return [1179, 1171, 8218, 1170, 8222, 8230, 8224, 8225, -1, 8240, 1203, 8249, 1202, 1207, 1206, -1, 1178, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, -1, 8250, -1, -1, -1, -1, -1, 1263, 1262, 1105, 164, 1251, 166, 167, -1, -1, -1, 171, 172, 173, 174, -1, 176, 177, 178, 1025, -1, 1250, 182, 183, -1, 8470, -1, 187, -1, -1, -1, 169, 1102, 1072, 1073, 1094, 1076, 1077, 1092, 1075, 1093, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1103, 1088, 1089, 1090, 1091, 1078, 1074, 1100, 1099, 1079, 1096, 1101, 1097, 1095, 1098, 1070, 1040, 1041, 1062, 1044, 1045, 1060, 1043, 1061, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1071, 1056, 1057, 1058, 1059, 1046, 1042, 1068, 1067, 1047, 1064, 1069, 1065, 1063, 1066]
    if enc_id == 121 # KZ-1048
      return [1026, 1027, 8218, 1107, 8222, 8230, 8224, 8225, 8364, 8240, 1033, 8249, 1034, 1178, 1210, 1039, 1106, 8216, 8217, 8220, 8221, 8226, 8211, 8212, -1, 8482, 1113, 8250, 1114, 1179, 1211, 1119, 160, 1200, 1201, 1240, 164, 1256, 166, 167, 1025, 169, 1170, 171, 172, 173, 174, 1198, 176, 177, 1030, 1110, 1257, 181, 182, 183, 1105, 8470, 1171, 187, 1241, 1186, 1187, 1199, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103]
    if enc_id == 122 # HP-Roman8
      return [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 192, 194, 200, 202, 203, 206, 207, 180, 715, 710, 168, 732, 217, 219, 8356, 175, 221, 253, 176, 199, 231, 209, 241, 161, 191, 164, 163, 165, 167, 402, 162, 226, 234, 244, 251, 225, 233, 243, 250, 224, 232, 242, 249, 228, 235, 246, 252, 197, 238, 216, 198, 229, 237, 248, 230, 196, 236, 214, 220, 201, 239, 223, 212, 193, 195, 227, 208, 240, 205, 204, 211, 210, 213, 245, 352, 353, 218, 376, 255, 222, 254, 183, 181, 182, 190, 8212, 188, 189, 170, 186, 171, 9632, 187, 177, -1]
    if enc_id == 123 # macArabic
      return [196, 160, 199, 201, 209, 214, 220, 225, 224, 226, 228, 1722, 171, 231, 233, 232, 234, 235, 237, 8230, 238, 239, 241, 243, 187, 244, 246, 247, 250, 249, 251, 252, 32, 33, 34, 35, 36, 1642, 38, 39, 40, 41, 42, 43, 1548, 45, 46, 47, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641, 58, 1563, 60, 61, 62, 1567, 10058, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593, 1594, 91, 92, 93, 94, 95, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1662, 1657, 1670, 1749, 1700, 1711, 1672, 1681, 123, 124, 125, 1688, 1746]
    if enc_id == 124 # macFarsi
      return [196, 160, 199, 201, 209, 214, 220, 225, 224, 226, 228, 1722, 171, 231, 233, 232, 234, 235, 237, 8230, 238, 239, 241, 243, 187, 244, 246, 247, 250, 249, 251, 252, 32, 33, 34, 35, 36, 1642, 38, 39, 40, 41, 42, 43, 1548, 45, 46, 47, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785, 58, 1563, 60, 61, 62, 1567, 10058, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593, 1594, 91, 92, 93, 94, 95, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1662, 1657, 1670, 1749, 1700, 1711, 1672, 1681, 123, 124, 125, 1688, 1746]
    if enc_id == 125 # macHebrew
      return [196, 64287, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 32, 33, 34, 35, 36, 37, 8362, 39, 41, 40, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 1465, 8222, 63643, 63644, 63645, 63646, 1468, 64331, 64309, 8230, 160, 1464, 1463, 1461, 1462, 1460, 8211, 8212, 8220, 8221, 8216, 8217, 64298, 64299, 1471, 1456, 1458, 1457, 1467, 1465, 63615, 1459, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, 125, 93, 123, 91, 124]
    if enc_id == 126 # PalmOS
      return [8364, 129, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 9830, 9827, 9829, 9824, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 157, 158, 376, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]
    ByteArray.__extended_single_byte_table(enc_id)

  -> .__ibm037_table
    [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 231, 241, 162, 46, 60, 40, 43, 124, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223, 33, 36, 42, 41, 59, 172, 45, 47, 194, 196, 192, 193, 195, 197, 199, 209, 166, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 64, 39, 61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 164, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 221, 222, 174, 94, 163, 165, 183, 169, 167, 182, 188, 189, 190, 91, 93, 175, 168, 180, 215, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 246, 242, 243, 245, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 252, 249, 250, 255, 92, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 214, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 220, 217, 218, 159]

  -> .__ebcdic_table(enc_id)
    if enc_id == 78 # IBM037
      return ByteArray.__ibm037_table()
    if enc_id == 109 # IBM1047
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 231, 241, 162, 46, 60, 40, 43, 124, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223, 33, 36, 42, 41, 59, 94, 45, 47, 194, 196, 192, 193, 195, 197, 199, 209, 166, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 64, 39, 61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 164, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 91, 222, 174, 172, 163, 165, 183, 169, 167, 182, 188, 189, 190, 221, 168, 175, 93, 180, 215, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 246, 242, 243, 245, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 252, 249, 250, 255, 92, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 214, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 220, 217, 218, 159]
    if enc_id == 110 # IBM1140
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 231, 241, 162, 46, 60, 40, 43, 124, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223, 33, 36, 42, 41, 59, 172, 45, 47, 194, 196, 192, 193, 195, 197, 199, 209, 166, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 64, 39, 61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 8364, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 221, 222, 174, 94, 163, 165, 183, 169, 167, 182, 188, 189, 190, 91, 93, 175, 168, 180, 215, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 246, 242, 243, 245, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 252, 249, 250, 255, 92, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 214, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 220, 217, 218, 159]
    if enc_id == 111 # IBM500
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 231, 241, 91, 46, 60, 40, 43, 33, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223, 93, 36, 42, 41, 59, 94, 45, 47, 194, 196, 192, 193, 195, 197, 199, 209, 166, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 64, 39, 61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 164, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 221, 222, 174, 162, 163, 165, 183, 169, 167, 182, 188, 189, 190, 172, 124, 175, 168, 180, 215, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 246, 242, 243, 245, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 252, 249, 250, 255, 92, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 214, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 220, 217, 218, 159]
    if enc_id == 112 # IBM273
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 123, 224, 225, 227, 229, 231, 241, 196, 46, 60, 40, 43, 33, 38, 233, 234, 235, 232, 237, 238, 239, 236, 126, 220, 36, 42, 41, 59, 94, 45, 47, 194, 91, 192, 193, 195, 197, 199, 209, 246, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 167, 39, 61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 164, 181, 223, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 221, 222, 174, 162, 163, 165, 183, 169, 64, 182, 188, 189, 190, 172, 124, 8254, 168, 180, 215, 228, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 166, 242, 243, 245, 252, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 125, 249, 250, 255, 214, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 92, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 93, 217, 218, 159]
    if enc_id == 113 # IBM424
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 162, 46, 60, 40, 43, 124, 38, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 33, 36, 42, 41, 59, 172, 45, 47, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 166, 44, 37, 95, 62, 63, -1, 1514, -1, -1, 160, -1, -1, -1, 8215, 96, 58, 35, 64, 39, 61, 34, -1, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, -1, -1, -1, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, -1, -1, -1, 184, -1, 164, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, -1, -1, -1, -1, -1, 174, 94, 163, 165, 183, 169, 167, 182, 188, 189, 190, 91, 93, 175, 168, 180, 215, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, -1, -1, -1, -1, -1, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, -1, -1, -1, -1, -1, 92, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, -1, -1, -1, -1, -1, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, -1, -1, -1, -1, 159]
    if enc_id == 114 # IBM875
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 913, 914, 915, 916, 917, 918, 919, 920, 921, 91, 46, 60, 40, 43, 33, 38, 922, 923, 924, 925, 926, 927, 928, 929, 931, 93, 36, 42, 41, 59, 94, 45, 47, 932, 933, 934, 935, 936, 937, 938, 939, 124, 44, 37, 95, 62, 63, 168, 902, 904, 905, 160, 906, 908, 910, 911, 96, 58, 35, 64, 39, 61, 34, 901, 97, 98, 99, 100, 101, 102, 103, 104, 105, 945, 946, 947, 948, 949, 950, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 951, 952, 953, 954, 955, 956, 180, 126, 115, 116, 117, 118, 119, 120, 121, 122, 957, 958, 959, 960, 961, 963, 163, 940, 941, 942, 970, 943, 972, 973, 971, 974, 962, 964, 965, 966, 967, 968, 123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 969, 912, 944, 8216, 8213, 125, 74, 75, 76, 77, 78, 79, 80, 81, 82, 177, 189, 26, 903, 8217, 166, 92, 26, 83, 84, 85, 86, 87, 88, 89, 90, 178, 167, 26, 26, 171, 172, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 169, 26, 26, 187, 159]
    if enc_id == 115 # IBM1026
      return [0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19, 157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10, 23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4, 152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 123, 241, 199, 46, 60, 40, 43, 33, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223, 286, 304, 42, 41, 59, 94, 45, 47, 194, 196, 192, 193, 195, 197, 91, 209, 351, 44, 37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 305, 58, 214, 350, 39, 61, 220, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 125, 96, 166, 177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198, 164, 181, 246, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 93, 36, 64, 174, 162, 163, 165, 183, 169, 167, 182, 188, 189, 190, 172, 124, 175, 168, 180, 215, 231, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 126, 242, 243, 245, 287, 74, 75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 92, 249, 250, 255, 252, 247, 83, 84, 85, 86, 87, 88, 89, 90, 178, 212, 35, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 179, 219, 34, 217, 218, 159]
    ByteArray.__extended_ebcdic_table(enc_id)

  -> <=>(other)
    if type(other) != "ByteArray" && type(other) != "Array"
      return nil
    na = self.size()
    nb = other.size()
    lim = na < nb ? na : nb
    i = 0
    while i < lim
      if self[i] < other[i]
        return -1
      if self[i] > other[i]
        return 1
      i += 1
    if na < nb
      return -1
    if na > nb
      return 1
    0

use core/byte_array/extended_encodings
use core/byte_array/transcode

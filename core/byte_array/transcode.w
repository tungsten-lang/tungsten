# ByteArray transcoding, decoding, scrubbing, and chunked/streaming codecs
# (`StreamDecoder` and `StreamEncoder`).

+ ByteArray
  -> __decode_codepoints(enc_id)
    if !self.__valid_encoding_id?(enc_id)
      raise "invalid [ByteArray.encoding_name(enc_id)] byte sequence"
    n = self.size()
    cps = []
    if enc_id == 9
      s = ccall("w_string_from_byte_array", self)
      nfc_s = s.nfc()
      return nfc_s.encode(:utf8).__decode_codepoints(1)
    if enc_id == 129
      return self.__decode_wtf8()
    if enc_id == 130
      return self.__decode_scsu_checked()
    if enc_id == 131
      return self.__decode_bocu1_checked()
    if enc_id == 132
      return self.__decode_utf_ebcdic_checked()
    if enc_id == 133
      return self.__decode_utf1_checked()
    if enc_id == 134
      return self.__decode_gsm0338_checked()
    if enc_id == 137
      return self.__decode_ansel_checked()
    if enc_id == 164
      return self.__decode_iso2022_cn_checked()
    if enc_id == 1 || enc_id == 15 || enc_id == 95 || enc_id == 97 || enc_id == 101 || enc_id == 104 || enc_id == 128
      i = 0
      if enc_id == 128 && n >= 3 && self[0] == 0xEF && self[1] == 0xBB && self[2] == 0xBF
        i = 3
      while i < n
        b0 = self[i]
        if b0 < 0x80
          cps.push(b0)
          i += 1
        elsif enc_id == 104 && b0 == 0xC0 && self[i + 1] == 0x80
          cps.push(0)
          i += 2
        elsif b0 < 0xE0
          cps.push(((b0 & 0x1F) << 6) | (self[i + 1] & 0x3F))
          i += 2
        elsif b0 < 0xF0
          if (enc_id == 15 || enc_id == 104) && b0 == 0xED && self[i + 1] >= 0xA0 && self[i + 1] <= 0xAF
            hi = ((b0 & 0x0F) << 12) | ((self[i + 1] & 0x3F) << 6) | (self[i + 2] & 0x3F)
            lo = ((self[i + 3] & 0x0F) << 12) | ((self[i + 4] & 0x3F) << 6) | (self[i + 5] & 0x3F)
            cps.push(0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00))
            i += 6
          else
            cps.push(((b0 & 0x0F) << 12) | ((self[i + 1] & 0x3F) << 6) | (self[i + 2] & 0x3F))
            i += 3
        else
          cps.push(((b0 & 0x07) << 18) | ((self[i + 1] & 0x3F) << 12) | ((self[i + 2] & 0x3F) << 6) | (self[i + 3] & 0x3F))
          i += 4
      return cps
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
        if !in_b64
          if b == shift_ch
            in_b64 = true
            bits = 0
            nbits = 0
            pend_hi = 0
            b64_chars = 0
          else
            cps.push(b)
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
                cps.push(0x10000 + ((pend_hi - 0xD800) << 10) + (u - 0xDC00))
                pend_hi = 0
              elsif u >= 0xD800 && u <= 0xDBFF
                pend_hi = u
              else
                cps.push(u)
            i += 1
          else
            in_b64 = false
            if b == 0x2D
              if b64_chars == 0
                cps.push(shift_ch)
              i += 1
      return cps
    if enc_id == 0 || enc_id == 2 || enc_id == 17 || enc_id == 19 || enc_id == 22
      i = 0
      while i < n
        if (enc_id == 17 || enc_id == 19) && self[i] >= 0x80
          raise "cannot decode non-ASCII byte in [ByteArray.encoding_name(enc_id)]"
        cps.push(self[i])
        i += 1
      return cps
    if enc_id == 105
      i = 0
      while i < n
        b = self[i]
        cps.push(b < 0x80 ? b : (0xF700 + b))
        i += 1
      return cps
    if enc_id == 65
      i = 0
      while i < n
        b = self[i]
        cps.push(b == 0x24 ? 0x00A5 : (b == 0x7E ? 0x203E : b))
        i += 1
      return cps
    if ByteArray.__ebcdic_encoding?(enc_id)
      tbl = ByteArray.__ebcdic_table(enc_id)
      i = 0
      while i < n
        cps.push(tbl[self[i]])
        i += 1
      return cps
    if ByteArray.__single_byte_encoding?(enc_id)
      tbl = ByteArray.__single_byte_table(enc_id)
      i = 0
      while i < n
        b = self[i]
        cps.push(b < 0x80 ? b : tbl[b - 0x80])
        i += 1
      return cps
    if enc_id == 3 || enc_id == 4 || enc_id == 7
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
          u2 = le ? (self[i + 2] | (self[i + 3] << 8)) : ((self[i + 2] << 8) | self[i + 3])
          cps.push(0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00))
          i += 4
        else
          cps.push(u)
          i += 2
      return cps
    if enc_id == 5 || enc_id == 6 || enc_id == 8
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
        cps.push(cp)
        i += 4
      return cps
    if enc_id == 11 || enc_id == 39 || enc_id == 93 || enc_id == 96 || enc_id == 98 || enc_id == 102
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          cps.push(b0)
          i += 1
        elsif b0 >= 0xA1 && b0 <= 0xDF
          cps.push(0xFF61 + (b0 - 0xA1))
          i += 1
        else
          b1 = self[i + 1]
          code = (b0 << 8) | b1
          off = code << 1
          cp = tbl[off] | (tbl[off + 1] << 8)
          if enc_id == 39
            if code == 0x815C
              cp = 0x2014
            elsif code == 0x8160
              cp = 0x301C
            elsif code == 0x8161
              cp = 0x2016
            elsif code == 0x817C
              cp = 0x2212
            elsif code == 0x8191
              cp = 0x00A2
            elsif code == 0x8192
              cp = 0x00A3
            elsif code == 0x81CA
              cp = 0x00AC
          cps.push(cp)
          i += 2
      return cps
    if enc_id == 10 || (enc_id >= 80 && enc_id <= 82)
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          cps.push(b0)
          i += 1
        else
          b1 = self[i + 1]
          off = ((b0 << 8) | b1) << 1
          cps.push(tbl[off] | (tbl[off + 1] << 8))
          i += 2
      return cps
    if enc_id == 79 || (enc_id >= 85 && enc_id <= 88) || enc_id == 99 || enc_id == 100
      tbl = ByteArray.__cjk_table(enc_id)
      mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 == 0x1B
          b1 = self[i + 1]
          b2 = self[i + 2]
          if b1 == 0x28 && (b2 == 0x42 || b2 == 0x4A)
            mode = 0
          elsif b1 == 0x28 && b2 == 0x49
            mode = 1
          else
            mode = 2
          i += 3
        elsif mode == 0
          cps.push(b0)
          i += 1
        elsif mode == 1
          cps.push(0xFF61 + (b0 - 0x21))
          i += 1
        else
          b1 = self[i + 1]
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          cps.push(tbl[off] | (tbl[off + 1] << 8))
          i += 2
      return cps
    if enc_id == 106
      tbl = ByteArray.__cjk_table(enc_id)
      hz_mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 == 0x7E
          b1 = self[i + 1]
          if b1 == 0x7B
            hz_mode = 1
          elsif b1 == 0x7D
            hz_mode = 0
          elsif b1 == 0x7E
            cps.push(0x7E)
          i += 2
        elsif hz_mode == 0
          cps.push(b0)
          i += 1
        else
          b1 = self[i + 1]
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          cps.push(tbl[off] | (tbl[off + 1] << 8))
          i += 2
      return cps
    if enc_id == 107
      tbl = ByteArray.__cjk_table(enc_id)
      kr_mode = 0
      i = 0
      while i < n
        b0 = self[i]
        if b0 == 0x1B
          i += 4
        elsif b0 == 0x0E
          kr_mode = 1
          i += 1
        elsif b0 == 0x0F
          kr_mode = 0
          i += 1
        elsif kr_mode == 0
          cps.push(b0)
          i += 1
        else
          b1 = self[i + 1]
          off = (((b0 + 0x80) << 8) | (b1 + 0x80)) << 1
          cps.push(tbl[off] | (tbl[off + 1] << 8))
          i += 2
      return cps
    if enc_id == 20 || enc_id == 21 || enc_id == 83 || enc_id == 84
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          cps.push(b0)
          i += 1
        else
          b1 = self[i + 1]
          if b1 >= 0x40
            off = ((b0 << 8) | b1) << 1
            cps.push(tbl[off] | (tbl[off + 1] << 8))
            i += 2
          else
            b2 = self[i + 2]
            b3 = self[i + 3]
            ptr = ((b0 - 0x81) * 10 + (b1 - 0x30)) * 1260 + (b2 - 0x81) * 10 + (b3 - 0x30)
            if ptr < 39420
              off = 262144 + (ptr << 1)
              cps.push(tbl[off] | (tbl[off + 1] << 8))
            else
              cps.push(0x10000 + (ptr - 189000))
            i += 4
      return cps
    if enc_id == 12 || enc_id == 13 || enc_id == 14 || enc_id == 76 || enc_id == 77 || enc_id == 16 || enc_id == 18 || enc_id == 127
      tbl = ByteArray.__cjk_table(enc_id)
      i = 0
      while i < n
        b0 = self[i]
        if b0 < 0x80
          cps.push(b0)
          i += 1
        else
          b1 = self[i + 1]
          off = ((b0 << 8) | b1) << 1
          cps.push(tbl[off] | (tbl[off + 1] << 8))
          i += 2
      return cps
    cps

  -> .__find_table_byte(tbl, cp, offset)
    j = 0
    n = tbl.size()
    while j < n
      if tbl[j] == cp
        return offset + j
      j += 1
    -1

  -> .__encode_utf7(cps, enc_id)
    is_imap = enc_id == 103
    shift_ch = is_imap ? 0x26 : 0x2B
    bytes = []
    in_b64 = false
    bits = 0
    nbits = 0
    ncp = cps.size()
    i = 0
    while i < ncp
      cp = cps[i]
      if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
        raise "invalid Unicode scalar value: [cp]"
      if ByteArray.__utf7_direct?(cp, is_imap)
        if in_b64
          if nbits > 0
            bytes.push(ByteArray.__b64_char((bits << (6 - nbits)) & 0x3F, is_imap))
            bits = 0
            nbits = 0
          bytes.push(0x2D)
          in_b64 = false
        bytes.push(cp)
      elsif cp == shift_ch && !in_b64
        bytes.push(shift_ch)
        bytes.push(0x2D)
      else
        if !in_b64
          bytes.push(shift_ch)
          in_b64 = true
          bits = 0
          nbits = 0
        if cp <= 0xFFFF
          bits = (bits << 16) | cp
          nbits += 16
        else
          s = cp - 0x10000
          hi = 0xD800 + (s >> 10)
          lo = 0xDC00 + (s & 0x3FF)
          bits = (bits << 16) | hi
          nbits += 16
          while nbits >= 6
            nbits -= 6
            bytes.push(ByteArray.__b64_char((bits >> nbits) & 0x3F, is_imap))
            bits = bits & ((1 << nbits) - 1)
          bits = (bits << 16) | lo
          nbits += 16
        while nbits >= 6
          nbits -= 6
          bytes.push(ByteArray.__b64_char((bits >> nbits) & 0x3F, is_imap))
          bits = bits & ((1 << nbits) - 1)
      i += 1
    if in_b64
      if nbits > 0
        bytes.push(ByteArray.__b64_char((bits << (6 - nbits)) & 0x3F, is_imap))
      bytes.push(0x2D)
    nb = bytes.size()
    out = ByteArray.new(nb)
    out.__set_encoding_id(enc_id)
    j = 0
    while j < nb
      out[j] = bytes[j]
      j += 1
    out

  -> .__encode_cjk(cps, enc_id)
    tbl = ByteArray.__cjk_table(enc_id)
    bytes = []
    ncp = cps.size()
    iso_mode = 0
    is_iso2022 = enc_id == 79 || (enc_id >= 85 && enc_id <= 88) || enc_id == 99 || enc_id == 100
    is_hz = enc_id == 106
    is_kr2022 = enc_id == 107
    kr_designed = false
    i = 0
    while i < ncp
      cp = cps[i]
      if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
        raise "invalid Unicode scalar value: [cp]"
      if cp < 0x80
        if is_iso2022 && iso_mode != 0
          bytes.push(0x1B)
          bytes.push(0x28)
          bytes.push(0x42)
          iso_mode = 0
        elsif is_hz && iso_mode != 0
          bytes.push(0x7E)
          bytes.push(0x7D)
          iso_mode = 0
        elsif is_kr2022 && iso_mode != 0
          bytes.push(0x0F)
          iso_mode = 0
        if is_hz && cp == 0x7E
          bytes.push(0x7E)
          bytes.push(0x7E)
        else
          bytes.push(cp)
      elsif cp <= 0xFFFF
        off = 131072 + (cp << 1)
        code = tbl[off] | (tbl[off + 1] << 8)
        if code != 0
          if code < 0x100
            bytes.push(code)
          elsif is_iso2022
            b1 = (code >> 8) & 0xFF
            b2 = code & 0xFF
            if b1 == 0x8E
              if iso_mode != 1
                bytes.push(0x1B)
                bytes.push(0x28)
                bytes.push(0x49)
                iso_mode = 1
              bytes.push(b2 - 0x80)
            else
              if iso_mode != 2
                bytes.push(0x1B)
                bytes.push(0x24)
                bytes.push(0x42)
                iso_mode = 2
              bytes.push(b1 - 0x80)
              bytes.push(b2 - 0x80)
          elsif is_hz
            b1 = (code >> 8) & 0xFF
            b2 = code & 0xFF
            if b1 < 0xA1 || b1 > 0xF7 || b2 < 0xA1
              raise "cannot encode codepoint [cp] to HZ-GB-2312"
            if iso_mode != 1
              bytes.push(0x7E)
              bytes.push(0x7B)
              iso_mode = 1
            bytes.push(b1 - 0x80)
            bytes.push(b2 - 0x80)
          elsif is_kr2022
            b1 = (code >> 8) & 0xFF
            b2 = code & 0xFF
            if b1 < 0xA1 || b2 < 0xA1
              raise "cannot encode codepoint [cp] to ISO-2022-KR"
            if !kr_designed
              bytes.push(0x1B)
              bytes.push(0x24)
              bytes.push(0x29)
              bytes.push(0x43)
              kr_designed = true
            if iso_mode != 1
              bytes.push(0x0E)
              iso_mode = 1
            bytes.push(b1 - 0x80)
            bytes.push(b2 - 0x80)
          else
            b1 = (code >> 8) & 0xFF
            b2 = code & 0xFF
            if (enc_id == 83 && (b1 < 0xA1 || b1 > 0xF7 || b2 < 0xA1)) || (enc_id == 18 && (b1 < 0xA1 || b2 < 0xA1))
              raise "cannot encode codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
            bytes.push(b1)
            bytes.push(b2)
        elsif enc_id == 20
          off4 = 340984 + (cp << 1)
          ptr_plus1 = tbl[off4] | (tbl[off4 + 1] << 8)
          if ptr_plus1 == 0
            raise "cannot encode codepoint [cp] to GB18030"
          ptr = ptr_plus1 - 1
          bytes.push(0x81 + (ptr / 12600))
          rem1 = ptr % 12600
          bytes.push(0x30 + (rem1 / 1260))
          rem2 = rem1 % 1260
          bytes.push(0x81 + (rem2 / 10))
          bytes.push(0x30 + (rem2 % 10))
        else
          raise "cannot encode codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
      elsif enc_id == 20
        ptr = cp - 0x10000 + 189000
        bytes.push(0x81 + (ptr / 12600))
        rem1 = ptr % 12600
        bytes.push(0x30 + (rem1 / 1260))
        rem2 = rem1 % 1260
        bytes.push(0x81 + (rem2 / 10))
        bytes.push(0x30 + (rem2 % 10))
      else
        raise "cannot encode supplementary codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
      i += 1
    if is_iso2022 && iso_mode != 0
      bytes.push(0x1B)
      bytes.push(0x28)
      bytes.push(0x42)
    elsif is_hz && iso_mode != 0
      bytes.push(0x7E)
      bytes.push(0x7D)
    elsif is_kr2022 && iso_mode != 0
      bytes.push(0x0F)
    nb = bytes.size()
    out = ByteArray.new(nb)
    out.__set_encoding_id(enc_id)
    j = 0
    while j < nb
      out[j] = bytes[j]
      j += 1
    out

  -> .encode_codepoints(cps, enc_id)
    if enc_id == 9
      utf8_ba = ByteArray.encode_codepoints(cps, 1)
      s = ccall("w_string_from_byte_array", utf8_ba)
      nfd_s = s.nfd()
      out_nfd = nfd_s.encode(:utf8)
      out_nfd.__set_encoding_id(9)
      return out_nfd
    if enc_id == 94 || enc_id == 103
      return ByteArray.__encode_utf7(cps, enc_id)
    if enc_id == 129
      return ByteArray.__encode_wtf8(cps)
    if enc_id == 130
      return ByteArray.__encode_scsu(cps)
    if enc_id == 131
      return ByteArray.__encode_bocu1(cps)
    if enc_id == 132
      return ByteArray.__encode_utf_ebcdic(cps)
    if enc_id == 133
      return ByteArray.__encode_utf1(cps)
    if enc_id == 134
      return ByteArray.__encode_gsm0338(cps)
    if enc_id == 137
      return ByteArray.__encode_ansel(cps)
    if enc_id == 164
      return ByteArray.__encode_iso2022_cn(cps)
    if ByteArray.__cjk_table(enc_id) != nil
      return ByteArray.__encode_cjk(cps, enc_id)
    ncp = cps.size()
    out_len = 0
    if enc_id == 7 && ncp > 0
      out_len = 2
    elsif enc_id == 8 && ncp > 0
      out_len = 4
    elsif enc_id == 128
      out_len = 3
    sb_tbl = nil
    is_ebcdic = ByteArray.__ebcdic_encoding?(enc_id)
    if is_ebcdic
      sb_tbl = ByteArray.__ebcdic_table(enc_id)
    elsif enc_id != 22 && enc_id != 65 && ByteArray.__single_byte_encoding?(enc_id)
      sb_tbl = ByteArray.__single_byte_table(enc_id)
    i = 0
    while i < ncp
      cp = cps[i]
      if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
        raise "invalid Unicode scalar value: [cp]"
      if enc_id == 1 || enc_id == 95 || enc_id == 97 || enc_id == 101 || enc_id == 128
        if cp < 0x80
          out_len += 1
        elsif cp < 0x800
          out_len += 2
        elsif cp < 0x10000
          out_len += 3
        else
          out_len += 4
      elsif enc_id == 15 || enc_id == 104
        if enc_id == 104 && cp == 0
          out_len += 2
        elsif cp < 0x80
          out_len += 1
        elsif cp < 0x800
          out_len += 2
        elsif cp < 0x10000
          out_len += 3
        else
          out_len += 6
      elsif enc_id == 2 || enc_id == 17 || enc_id == 19
        if cp >= 0x80
          raise "cannot encode non-ASCII codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
        out_len += 1
      elsif enc_id == 0 || enc_id == 22
        if cp >= 0x100
          raise "cannot encode codepoint [cp] above U+00FF to [ByteArray.encoding_name(enc_id)]"
        out_len += 1
      elsif enc_id == 105
        if cp >= 0x80 && (cp < 0xF780 || cp > 0xF7FF)
          raise "cannot encode codepoint [cp] to x-user-defined"
        out_len += 1
      elsif enc_id == 65
        if cp != 0x00A5 && cp != 0x203E && (cp >= 0x80 || cp == 0x24 || cp == 0x7E)
          raise "cannot encode codepoint [cp] to GB1988"
        out_len += 1
      elsif is_ebcdic
        if ByteArray.__find_table_byte(sb_tbl, cp, 0) < 0
          raise "cannot encode codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
        out_len += 1
      elsif sb_tbl != nil
        if cp >= 0x80 && ByteArray.__find_table_byte(sb_tbl, cp, 0x80) < 0
          raise "cannot encode codepoint [cp] to [ByteArray.encoding_name(enc_id)]"
        out_len += 1
      elsif enc_id == 3 || enc_id == 4 || enc_id == 7
        out_len += (cp <= 0xFFFF ? 2 : 4)
      elsif enc_id == 5 || enc_id == 6 || enc_id == 8
        out_len += 4
      else
        raise "unsupported encoding for transcoding: [ByteArray.encoding_name(enc_id)]"
      i += 1
    out = ByteArray.new(out_len)
    out.__set_encoding_id(enc_id)
    k = 0
    if enc_id == 7 && ncp > 0
      out[0] = 0xFE
      out[1] = 0xFF
      k = 2
    elsif enc_id == 8 && ncp > 0
      out[0] = 0x00
      out[1] = 0x00
      out[2] = 0xFE
      out[3] = 0xFF
      k = 4
    elsif enc_id == 128
      out[0] = 0xEF
      out[1] = 0xBB
      out[2] = 0xBF
      k = 3
    i = 0
    while i < ncp
      cp = cps[i]
      if enc_id == 1 || enc_id == 95 || enc_id == 97 || enc_id == 101 || enc_id == 128
        if cp < 0x80
          out[k] = cp
          k += 1
        elsif cp < 0x800
          out[k] = 0xC0 | (cp >> 6)
          out[k + 1] = 0x80 | (cp & 0x3F)
          k += 2
        elsif cp < 0x10000
          out[k] = 0xE0 | (cp >> 12)
          out[k + 1] = 0x80 | ((cp >> 6) & 0x3F)
          out[k + 2] = 0x80 | (cp & 0x3F)
          k += 3
        else
          out[k] = 0xF0 | (cp >> 18)
          out[k + 1] = 0x80 | ((cp >> 12) & 0x3F)
          out[k + 2] = 0x80 | ((cp >> 6) & 0x3F)
          out[k + 3] = 0x80 | (cp & 0x3F)
          k += 4
      elsif enc_id == 15 || enc_id == 104
        if enc_id == 104 && cp == 0
          out[k] = 0xC0
          out[k + 1] = 0x80
          k += 2
        elsif cp < 0x80
          out[k] = cp
          k += 1
        elsif cp < 0x800
          out[k] = 0xC0 | (cp >> 6)
          out[k + 1] = 0x80 | (cp & 0x3F)
          k += 2
        elsif cp < 0x10000
          out[k] = 0xE0 | (cp >> 12)
          out[k + 1] = 0x80 | ((cp >> 6) & 0x3F)
          out[k + 2] = 0x80 | (cp & 0x3F)
          k += 3
        else
          s = cp - 0x10000
          hi = 0xD800 + (s >> 10)
          lo = 0xDC00 + (s & 0x3FF)
          out[k] = 0xE0 | (hi >> 12)
          out[k + 1] = 0x80 | ((hi >> 6) & 0x3F)
          out[k + 2] = 0x80 | (hi & 0x3F)
          out[k + 3] = 0xE0 | (lo >> 12)
          out[k + 4] = 0x80 | ((lo >> 6) & 0x3F)
          out[k + 5] = 0x80 | (lo & 0x3F)
          k += 6
      elsif enc_id == 0 || enc_id == 2 || enc_id == 17 || enc_id == 19 || enc_id == 22
        out[k] = cp
        k += 1
      elsif enc_id == 105
        out[k] = cp < 0x80 ? cp : (cp - 0xF700)
        k += 1
      elsif enc_id == 65
        out[k] = cp == 0x00A5 ? 0x24 : (cp == 0x203E ? 0x7E : cp)
        k += 1
      elsif is_ebcdic
        out[k] = ByteArray.__find_table_byte(sb_tbl, cp, 0)
        k += 1
      elsif sb_tbl != nil
        out[k] = cp < 0x80 ? cp : ByteArray.__find_table_byte(sb_tbl, cp, 0x80)
        k += 1
      elsif enc_id == 4
        if cp <= 0xFFFF
          out[k] = cp & 0xFF
          out[k + 1] = (cp >> 8) & 0xFF
          k += 2
        else
          s = cp - 0x10000
          hi = 0xD800 + (s >> 10)
          lo = 0xDC00 + (s & 0x3FF)
          out[k] = hi & 0xFF
          out[k + 1] = (hi >> 8) & 0xFF
          out[k + 2] = lo & 0xFF
          out[k + 3] = (lo >> 8) & 0xFF
          k += 4
      elsif enc_id == 3 || enc_id == 7
        if cp <= 0xFFFF
          out[k] = (cp >> 8) & 0xFF
          out[k + 1] = cp & 0xFF
          k += 2
        else
          s = cp - 0x10000
          hi = 0xD800 + (s >> 10)
          lo = 0xDC00 + (s & 0x3FF)
          out[k] = (hi >> 8) & 0xFF
          out[k + 1] = hi & 0xFF
          out[k + 2] = (lo >> 8) & 0xFF
          out[k + 3] = lo & 0xFF
          k += 4
      elsif enc_id == 6
        out[k] = cp & 0xFF
        out[k + 1] = (cp >> 8) & 0xFF
        out[k + 2] = (cp >> 16) & 0xFF
        out[k + 3] = (cp >> 24) & 0xFF
        k += 4
      elsif enc_id == 5 || enc_id == 8
        out[k] = (cp >> 24) & 0xFF
        out[k + 1] = (cp >> 16) & 0xFF
        out[k + 2] = (cp >> 8) & 0xFF
        out[k + 3] = cp & 0xFF
        k += 4
      i += 1
    out

  # Transcode this ByteArray into a new ByteArray.
  # - 1-arg `transcode(to_encoding)` uses `$encoding_id` (or UTF-8 if 0/BINARY).
  # - 2-arg `transcode(from_encoding, to_encoding)` explicitly specifies both.
  -> transcode(arg1, arg2 = nil)
    from_id = 1
    to_id = 1
    if arg2 == nil
      cur_id = $encoding_id
      from_id = cur_id == 0 ? 1 : cur_id
      to_id = ByteArray.normalize_encoding(arg1)
    else
      from_id = ByteArray.normalize_encoding(arg1)
      to_id = ByteArray.normalize_encoding(arg2)
    cps = self.__decode_codepoints(from_id)
    ByteArray.encode_codepoints(cps, to_id)

  -> encode(to_encoding, from_encoding = nil)
    if from_encoding == nil
      return self.transcode(to_encoding)
    self.transcode(from_encoding, to_encoding)

  # Decode this ByteArray into a UTF-8 String. When `encoding` is omitted,
  # uses `$encoding_id` (defaulting to UTF-8 when `$encoding_id == 0`).
  -> decode(encoding = nil)
    enc_id = 1
    if encoding == nil
      cur_id = $encoding_id
      enc_id = cur_id == 0 ? 1 : cur_id
    else
      enc_id = ByteArray.normalize_encoding(encoding)
    if enc_id == 1 || enc_id == 2
      if !self.__valid_encoding_id?(enc_id)
        raise "invalid [ByteArray.encoding_name(enc_id)] byte sequence"
      return ccall("w_string_from_byte_array", self)
    if enc_id == 129
      cps = self.__decode_wtf8()
      i = 0
      while i < cps.size()
        if cps[i] >= 0xD800 && cps[i] <= 0xDFFF
          cps[i] = 0xFFFD
        i += 1
      utf8_w = ByteArray.encode_codepoints(cps, 1)
      return ccall("w_string_from_byte_array", utf8_w)
    utf8_bytes = self.transcode(enc_id, 1)
    ccall("w_string_from_byte_array", utf8_bytes)

  -> to_string(encoding = nil)
    self.decode(encoding)

  # Replace invalid byte sequences in this ByteArray's encoding with `replacement`
  # (defaulting to U+FFFD for Unicode encodings or "?" for legacy encodings).
  -> scrub(replacement = nil)
    enc_id = $encoding_id == 0 ? 1 : $encoding_id
    if self.__valid_encoding_id?(enc_id)
      return self
    rep_str = replacement
    if rep_str == nil
      is_unicode = enc_id == 1 || (enc_id >= 3 && enc_id <= 9) || enc_id == 15 || enc_id == 94 || enc_id == 95 || enc_id == 97 || enc_id == 101 || enc_id == 103 || enc_id == 104 || (enc_id >= 128 && enc_id <= 133)
      rep_str = is_unicode ? "\uFFFD" : "?"
    rep_bytes = rep_str.to_s().encode(enc_id)
    n = self.size()
    out_bytes = []
    i = 0
    while i < n
      matched = false
      clen = 1
      while clen <= 4 && i + clen <= n
        probe = ByteArray.new(clen)
        k = 0
        while k < clen
          probe[k] = self[i + k]
          k += 1
        if probe.__valid_encoding_id?(enc_id)
          k = 0
          while k < clen
            out_bytes.push(probe[k])
            k += 1
          i += clen
          matched = true
          break
        clen += 1
      if !matched
        k = 0
        while k < rep_bytes.size()
          out_bytes.push(rep_bytes[k])
          k += 1
        i += 1
    res = ByteArray.new(out_bytes.size())
    res.__set_encoding_id($encoding_id)
    j = 0
    while j < out_bytes.size()
      res[j] = out_bytes[j]
      j += 1
    res

  # Create a stateful chunked/streaming decoder for `encoding`.
  -> .stream_decoder(encoding = :utf8)
    StreamDecoder.new(encoding)

# Stateful chunked/streaming byte-to-String decoder.
# Buffers incomplete trailing multi-byte sequences across `write`/`decode_chunk`
# calls and preserves BOM / shift-state across chunk boundaries.
+ StreamDecoder
  ro :encoding_id

  -> new(encoding = :utf8)
    @encoding_id = ByteArray.normalize_encoding(encoding)
    @pending = []
    @bom_checked = false
    @effective_id = @encoding_id

  -> encoding
    ByteArray.encoding_name(@encoding_id)

  -> pending_size
    @pending.size()

  -> reset
    @pending = []
    @bom_checked = false
    @effective_id = @encoding_id
    self

  -> __drop_pending(k)
    n = @pending.size()
    rem = []
    i = k
    while i < n
      rem.push(@pending[i])
      i += 1
    @pending = rem

  -> __append_chunk(chunk)
    t = type(chunk)
    if t == "ByteArray" || t == "Array"
      i = 0
      n = chunk.size()
      while i < n
        @pending.push(chunk[i] & 0xFF)
        i += 1
    elsif t == "String"
      chunk.each_byte -> (b)
        @pending.push(b)
    else
      raise ArgumentError.new("StreamDecoder expects a ByteArray, Array, or String chunk")

  -> write(chunk)
    self.__append_chunk(chunk)
    n = @pending.size()
    if n == 0
      return ""

    # Handle initial BOM detection for UTF-16 (7), UTF-32 (8), and UTF-8-SIG (128)
    if !@bom_checked
      if @encoding_id == 7
        if n < 2
          return ""
        if @pending[0] == 0xFE && @pending[1] == 0xFF
          @effective_id = 3
          self.__drop_pending(2)
        elsif @pending[0] == 0xFF && @pending[1] == 0xFE
          @effective_id = 4
          self.__drop_pending(2)
        else
          @effective_id = 3
        @bom_checked = true
      elsif @encoding_id == 8
        if n < 4
          return ""
        if @pending[0] == 0x00 && @pending[1] == 0x00 && @pending[2] == 0xFE && @pending[3] == 0xFF
          @effective_id = 5
          self.__drop_pending(4)
        elsif @pending[0] == 0xFF && @pending[1] == 0xFE && @pending[2] == 0x00 && @pending[3] == 0x00
          @effective_id = 6
          self.__drop_pending(4)
        else
          @effective_id = 5
        @bom_checked = true
      elsif @encoding_id == 128
        if n == 1 && @pending[0] == 0xEF
          return ""
        if n == 2 && @pending[0] == 0xEF && @pending[1] == 0xBB
          return ""
        if n >= 3 && @pending[0] == 0xEF && @pending[1] == 0xBB && @pending[2] == 0xBF
          self.__drop_pending(3)
        @effective_id = 1
        @bom_checked = true
      else
        @bom_checked = true

    n = @pending.size()
    if n == 0
      return ""

    # Find the longest prefix (within the last 6 bytes) that is a complete, valid
    # byte sequence in `@effective_id`.
    max_back = n < 6 ? n : 6
    trim = 0
    while trim <= max_back
      cand_len = n - trim
      if cand_len == 0
        return ""
      probe = ByteArray.new(cand_len)
      probe.__set_encoding_id(@effective_id)
      i = 0
      while i < cand_len
        probe[i] = @pending[i]
        i += 1
      if probe.__valid_encoding_id?(@effective_id)
        rem = []
        j = cand_len
        while j < n
          rem.push(@pending[j])
          j += 1
        @pending = rem
        return probe.decode(@effective_id)
      trim += 1

    # If even trimming 6 trailing bytes is not valid, the stream contains a
    # genuinely invalid byte sequence in the middle; let `decode` raise.
    bad = ByteArray.new(n)
    bad.__set_encoding_id(@effective_id)
    i = 0
    while i < n
      bad[i] = @pending[i]
      i += 1
    bad.decode(@effective_id)

  -> <<(chunk)
    self.write(chunk)

  -> push(chunk)
    self.write(chunk)

  -> decode_chunk(chunk, stream: true)
    out = self.write(chunk)
    if !stream
      out = out + self.finish()
    out

  -> finish
    n = @pending.size()
    if n == 0
      self.reset()
      return ""
    rem = ByteArray.new(n)
    rem.__set_encoding_id(@effective_id)
    i = 0
    while i < n
      rem[i] = @pending[i]
      i += 1
    @pending = []
    @bom_checked = false
    rem.decode(@effective_id)

  -> flush
    self.finish()

# Stateful chunked/streaming String-to-ByteArray encoder.
# Emits leading BOMs (for UTF-16, UTF-32, UTF-8-SIG) only once on the first
# non-empty chunk.
+ StreamEncoder
  ro :encoding_id

  -> new(encoding = :utf8)
    @encoding_id = ByteArray.normalize_encoding(encoding)
    @bom_emitted = false

  -> encoding
    ByteArray.encoding_name(@encoding_id)

  -> reset
    @bom_emitted = false
    self

  -> write(str)
    s = str.to_s()
    if s.empty?()
      out = ByteArray.new(0)
      out.__set_encoding_id(@encoding_id)
      return out
    target_id = @encoding_id
    if @bom_emitted
      if @encoding_id == 7
        target_id = 3
      elsif @encoding_id == 8
        target_id = 5
      elsif @encoding_id == 128
        target_id = 1
    else
      @bom_emitted = true
    ba = s.encode(target_id)
    ba.__set_encoding_id(@encoding_id)
    ba

  -> <<(str)
    self.write(str)

  -> push(str)
    self.write(str)

  -> encode_chunk(str)
    self.write(str)

  -> finish
    @bom_emitted = false
    out = ByteArray.new(0)
    out.__set_encoding_id(@encoding_id)
    out

  -> flush
    self.finish()

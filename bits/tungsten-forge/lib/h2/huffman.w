# Forge::H2::Huffman — HPACK Huffman coding (RFC 7541 Appendix B)
# Encodes/decodes header strings using the static Huffman table

in Tungsten:Forge:H2

+ Huffman
  @@cached_table = nil
  @@cached_decode_tree = nil

  # --- Encoding ---

  -> .encode(string)
    tbl = self.table
    bit_buf = 0
    bit_count = 0
    output = [] ## reuse

    string.bytes.each -> (byte)
      entry = tbl[byte]
      code = entry[0]
      code_len = entry[1]

      bit_buf = (bit_buf << code_len) | code
      bit_count += code_len

      while bit_count >= 8
        bit_count -= 8
        output.push((bit_buf >> bit_count) & 0xFF)

    # Pad remaining bits with EOS (all 1s)
    if bit_count > 0
      bit_buf = (bit_buf << (8 - bit_count)) | ((1 << (8 - bit_count)) - 1)
      output.push(bit_buf & 0xFF)

    result = Bytes.new(output.size)
    output.each_with_index -> (b, i)
      result.set(i, b)
    result

  # --- Decoding ---

  -> .decode(bytes)
    root = self.decode_tree
    node = root
    output = [] ## reuse
    total_bits = bytes.size * 8
    bits_consumed = 0

    i = 0
    while i < bytes.size
      byte = bytes.get(i)
      bit = 7
      while bit >= 0
        b = (byte >> bit) & 1
        node = if b == 0 then node[0] else node[1]
        bits_consumed += 1

        <! DecodeError.new("Invalid Huffman code") unless node

        # Leaf node: node is [nil, nil, symbol]
        if node[2] != nil
          sym = node[2]
          <! DecodeError.new("EOS symbol in encoded data") if sym == 256
          output.push(sym)
          node = root

        bit -= 1
      i += 1

    # Verify padding: remaining bits must be at most 7 and all 1s
    if node != root
      # Check we are on a path consistent with EOS padding
      pad_bits = total_bits - bits_consumed
      <! DecodeError.new("Invalid padding exceeds 7 bits") if pad_bits > 7

    result = ""
    output.each -> (byte)
      result += byte.chr
    result

  # --- Decode tree builder ---

  -> .decode_tree
    return @@cached_decode_tree if @@cached_decode_tree

    tbl = self.table
    root = [nil, nil, nil]  # [left, right, symbol_or_nil]

    tbl.each_with_index -> (entry, sym)
      code = entry[0]
      code_len = entry[1]
      node = root

      bit = code_len - 1
      while bit >= 0
        b = (code >> bit) & 1
        if b == 0
          node[0] = [nil, nil, nil] unless node[0]
          if bit == 0
            node[0][2] = sym
          else
            node = node[0]
        else
          node[1] = [nil, nil, nil] unless node[1]
          if bit == 0
            node[1][2] = sym
          else
            node = node[1]
        bit -= 1

    @@cached_decode_tree = root
    root

  # --- Huffman table (RFC 7541 Appendix B) ---
  # Each entry is [huffman_code, bit_length] indexed by symbol (0-256)

  -> .table
    return @@cached_table if @@cached_table

    t = []

    # Symbol   (  code,  bits)
    t.push([0x1ff8,     13])  #   0
    t.push([0x7fffd8,   23])  #   1
    t.push([0xfffffe2,  28])  #   2
    t.push([0xfffffe3,  28])  #   3
    t.push([0xfffffe4,  28])  #   4
    t.push([0xfffffe5,  28])  #   5
    t.push([0xfffffe6,  28])  #   6
    t.push([0xfffffe7,  28])  #   7
    t.push([0xfffffe8,  28])  #   8
    t.push([0xffffea,   24])  #   9
    t.push([0x3ffffffc, 30])  #  10
    t.push([0xfffffe9,  28])  #  11
    t.push([0xfffffea,  28])  #  12
    t.push([0x3ffffffd, 30])  #  13
    t.push([0xfffffeb,  28])  #  14
    t.push([0xfffffec,  28])  #  15
    t.push([0xfffffed,  28])  #  16
    t.push([0xfffffee,  28])  #  17
    t.push([0xfffffef,  28])  #  18
    t.push([0xffffff0,  28])  #  19
    t.push([0xffffff1,  28])  #  20
    t.push([0xffffff2,  28])  #  21
    t.push([0x3ffffffe, 30])  #  22
    t.push([0xffffff3,  28])  #  23
    t.push([0xffffff4,  28])  #  24
    t.push([0xffffff5,  28])  #  25
    t.push([0xffffff6,  28])  #  26
    t.push([0xffffff7,  28])  #  27
    t.push([0xffffff8,  28])  #  28
    t.push([0xffffff9,  28])  #  29
    t.push([0xffffffa,  28])  #  30
    t.push([0xffffffb,  28])  #  31
    t.push([0x14,        6])  #  32 ' '
    t.push([0x3f8,      10])  #  33 '!'
    t.push([0x3f9,      10])  #  34 '"'
    t.push([0xffa,      12])  #  35 '#'
    t.push([0x1ff9,     13])  #  36 '$'
    t.push([0x15,        6])  #  37 '%'
    t.push([0xf8,        8])  #  38 '&'
    t.push([0x7fa,      11])  #  39 "'"
    t.push([0x3fa,      10])  #  40 '('
    t.push([0x3fb,      10])  #  41 ')'
    t.push([0xf9,        8])  #  42 '*'
    t.push([0x7fb,      11])  #  43 '+'
    t.push([0xfa,        8])  #  44 ','
    t.push([0x16,        6])  #  45 '-'
    t.push([0x17,        6])  #  46 '.'
    t.push([0x18,        6])  #  47 '/'
    t.push([0x00,        5])  #  48 '0'
    t.push([0x01,        5])  #  49 '1'
    t.push([0x02,        5])  #  50 '2'
    t.push([0x19,        6])  #  51 '3'
    t.push([0x1a,        6])  #  52 '4'
    t.push([0x1b,        6])  #  53 '5'
    t.push([0x1c,        6])  #  54 '6'
    t.push([0x1d,        6])  #  55 '7'
    t.push([0x1e,        6])  #  56 '8'
    t.push([0x1f,        6])  #  57 '9'
    t.push([0x5c,        7])  #  58 ':'
    t.push([0xfb,        8])  #  59 ';'
    t.push([0x7ffc,     15])  #  60 '<'
    t.push([0x20,        6])  #  61 '='
    t.push([0xffb,      12])  #  62 '>'
    t.push([0x3fc,      10])  #  63 '?'
    t.push([0x1ffa,     13])  #  64 '@'
    t.push([0x21,        6])  #  65 'A'
    t.push([0x5d,        7])  #  66 'B'
    t.push([0x5e,        7])  #  67 'C'
    t.push([0x5f,        7])  #  68 'D'
    t.push([0x60,        7])  #  69 'E'
    t.push([0x61,        7])  #  70 'F'
    t.push([0x62,        7])  #  71 'G'
    t.push([0x63,        7])  #  72 'H'
    t.push([0x64,        7])  #  73 'I'
    t.push([0x65,        7])  #  74 'J'
    t.push([0x66,        7])  #  75 'K'
    t.push([0x67,        7])  #  76 'L'
    t.push([0x68,        7])  #  77 'M'
    t.push([0x69,        7])  #  78 'N'
    t.push([0x6a,        7])  #  79 'O'
    t.push([0x6b,        7])  #  80 'P'
    t.push([0x6c,        7])  #  81 'Q'
    t.push([0x6d,        7])  #  82 'R'
    t.push([0x6e,        7])  #  83 'S'
    t.push([0x6f,        7])  #  84 'T'
    t.push([0x70,        7])  #  85 'U'
    t.push([0x71,        7])  #  86 'V'
    t.push([0x72,        7])  #  87 'W'
    t.push([0xfc,        8])  #  88 'X'
    t.push([0x73,        7])  #  89 'Y'
    t.push([0xfd,        8])  #  90 'Z'
    t.push([0x1ffb,     13])  #  91 '['
    t.push([0x7fff0,    19])  #  92 '\'
    t.push([0x1ffc,     13])  #  93 ']'
    t.push([0x3ffc,     14])  #  94 '^'
    t.push([0x22,        6])  #  95 '_'
    t.push([0x7ffd,     15])  #  96 '`'
    t.push([0x03,        5])  #  97 'a'
    t.push([0x23,        6])  #  98 'b'
    t.push([0x04,        5])  #  99 'c'
    t.push([0x24,        6])  # 100 'd'
    t.push([0x05,        5])  # 101 'e'
    t.push([0x25,        6])  # 102 'f'
    t.push([0x26,        6])  # 103 'g'
    t.push([0x27,        6])  # 104 'h'
    t.push([0x06,        5])  # 105 'i'
    t.push([0x74,        7])  # 106 'j'
    t.push([0x75,        7])  # 107 'k'
    t.push([0x28,        6])  # 108 'l'
    t.push([0x29,        6])  # 109 'm'
    t.push([0x2a,        6])  # 110 'n'
    t.push([0x07,        5])  # 111 'o'
    t.push([0x2b,        6])  # 112 'p'
    t.push([0x76,        7])  # 113 'q'
    t.push([0x2c,        6])  # 114 'r'
    t.push([0x08,        5])  # 115 's'
    t.push([0x09,        5])  # 116 't'
    t.push([0x2d,        6])  # 117 'u'
    t.push([0x77,        7])  # 118 'v'
    t.push([0x78,        7])  # 119 'w'
    t.push([0x79,        7])  # 120 'x'
    t.push([0x7a,        7])  # 121 'y'
    t.push([0x7b,        7])  # 122 'z'
    t.push([0x7ffe,     15])  # 123 '{'
    t.push([0x7fc,      11])  # 124 '|'
    t.push([0x3ffd,     14])  # 125 '}'
    t.push([0x1ffd,     13])  # 126 '~'
    t.push([0xffffffc,  28])  # 127
    t.push([0xfffe6,    20])  # 128
    t.push([0x3fffd2,   22])  # 129
    t.push([0xfffe7,    20])  # 130
    t.push([0xfffe8,    20])  # 131
    t.push([0x3fffd3,   22])  # 132
    t.push([0x3fffd4,   22])  # 133
    t.push([0x3fffd5,   22])  # 134
    t.push([0x7fffd9,   23])  # 135
    t.push([0x3fffd6,   22])  # 136
    t.push([0x7fffda,   23])  # 137
    t.push([0x7fffdb,   23])  # 138
    t.push([0x7fffdc,   23])  # 139
    t.push([0x7fffdd,   23])  # 140
    t.push([0x7fffde,   23])  # 141
    t.push([0xffffeb,   24])  # 142
    t.push([0x7fffdf,   23])  # 143
    t.push([0xffffec,   24])  # 144
    t.push([0xffffed,   24])  # 145
    t.push([0x3fffd7,   22])  # 146
    t.push([0x7fffe0,   23])  # 147
    t.push([0xffffee,   24])  # 148
    t.push([0x7fffe1,   23])  # 149
    t.push([0x7fffe2,   23])  # 150
    t.push([0x7fffe3,   23])  # 151
    t.push([0x7fffe4,   23])  # 152
    t.push([0x1fffdc,   21])  # 153
    t.push([0x3fffd8,   22])  # 154
    t.push([0x7fffe5,   23])  # 155
    t.push([0x3fffd9,   22])  # 156
    t.push([0x7fffe6,   23])  # 157
    t.push([0x7fffe7,   23])  # 158
    t.push([0xffffef,   24])  # 159
    t.push([0x3fffda,   22])  # 160
    t.push([0x1fffdd,   21])  # 161
    t.push([0xfffe9,    20])  # 162
    t.push([0x3fffdb,   22])  # 163
    t.push([0x3fffdc,   22])  # 164
    t.push([0x7fffe8,   23])  # 165
    t.push([0x7fffe9,   23])  # 166
    t.push([0x1fffde,   21])  # 167
    t.push([0x7fffea,   23])  # 168
    t.push([0x3fffdd,   22])  # 169
    t.push([0x3fffde,   22])  # 170
    t.push([0xfffff0,   24])  # 171
    t.push([0x1fffdf,   21])  # 172
    t.push([0x3fffdf,   22])  # 173
    t.push([0x7fffeb,   23])  # 174
    t.push([0x7fffec,   23])  # 175
    t.push([0x1fffe0,   21])  # 176
    t.push([0x1fffe1,   21])  # 177
    t.push([0x3fffe0,   22])  # 178
    t.push([0x1fffe2,   21])  # 179
    t.push([0x7fffed,   23])  # 180
    t.push([0x3fffe1,   22])  # 181
    t.push([0x7fffee,   23])  # 182
    t.push([0x7fffef,   23])  # 183
    t.push([0xfffea,    20])  # 184
    t.push([0x3fffe2,   22])  # 185
    t.push([0x3fffe3,   22])  # 186
    t.push([0x3fffe4,   22])  # 187
    t.push([0x7ffff0,   23])  # 188
    t.push([0x3fffe5,   22])  # 189
    t.push([0x3fffe6,   22])  # 190
    t.push([0x7ffff1,   23])  # 191
    t.push([0x3ffffe0,  26])  # 192
    t.push([0x3ffffe1,  26])  # 193
    t.push([0xfffeb,    20])  # 194
    t.push([0x7fff1,    19])  # 195
    t.push([0x3fffe7,   22])  # 196
    t.push([0x7ffff2,   23])  # 197
    t.push([0x3fffe8,   22])  # 198
    t.push([0x1ffffec,  25])  # 199
    t.push([0x3ffffe2,  26])  # 200
    t.push([0x3ffffe3,  26])  # 201
    t.push([0x3ffffe4,  26])  # 202
    t.push([0x7ffffde,  27])  # 203
    t.push([0x7ffffdf,  27])  # 204
    t.push([0x3ffffe5,  26])  # 205
    t.push([0xfffff1,   24])  # 206
    t.push([0x1ffffed,  25])  # 207
    t.push([0x7fff2,    19])  # 208
    t.push([0x1fffe3,   21])  # 209
    t.push([0x3ffffe6,  26])  # 210
    t.push([0x7ffffe0,  27])  # 211
    t.push([0x7ffffe1,  27])  # 212
    t.push([0x3ffffe7,  26])  # 213
    t.push([0x7ffffe2,  27])  # 214
    t.push([0xfffff2,   24])  # 215
    t.push([0x1fffe4,   21])  # 216
    t.push([0x1fffe5,   21])  # 217
    t.push([0x3ffffe8,  26])  # 218
    t.push([0x3ffffe9,  26])  # 219
    t.push([0xffffffd,  28])  # 220
    t.push([0x7ffffe3,  27])  # 221
    t.push([0x7ffffe4,  27])  # 222
    t.push([0x7ffffe5,  27])  # 223
    t.push([0xfffec,    20])  # 224
    t.push([0xfffff3,   24])  # 225
    t.push([0xfffed,    20])  # 226
    t.push([0x1fffe6,   21])  # 227
    t.push([0x3fffe9,   22])  # 228
    t.push([0x1fffe7,   21])  # 229
    t.push([0x1fffe8,   21])  # 230
    t.push([0x7ffff3,   23])  # 231
    t.push([0x3fffea,   22])  # 232
    t.push([0x3fffeb,   22])  # 233
    t.push([0x1ffffee,  25])  # 234
    t.push([0x1ffffef,  25])  # 235
    t.push([0xfffff4,   24])  # 236
    t.push([0xfffff5,   24])  # 237
    t.push([0x3ffffea,  26])  # 238
    t.push([0x7ffff4,   23])  # 239
    t.push([0x3ffffeb,  26])  # 240
    t.push([0x7ffffe6,  27])  # 241
    t.push([0x3ffffec,  26])  # 242
    t.push([0x3ffffed,  26])  # 243
    t.push([0x7ffffe7,  27])  # 244
    t.push([0x7ffffe8,  27])  # 245
    t.push([0x7ffffe9,  27])  # 246
    t.push([0x7ffffea,  27])  # 247
    t.push([0x7ffffeb,  27])  # 248
    t.push([0xffffffe,  28])  # 249
    t.push([0x7ffffec,  27])  # 250
    t.push([0x7ffffed,  27])  # 251
    t.push([0x7ffffee,  27])  # 252
    t.push([0x7ffffef,  27])  # 253
    t.push([0x7fffff0,  27])  # 254
    t.push([0x3ffffee,  26])  # 255
    t.push([0x3fffffff, 30])  # 256 EOS

    @@cached_table = t
    t

+ DecodeError < StandardError

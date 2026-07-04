# Forge::H2::HPACK — Header compression per RFC 7541
# Encoder and decoder for HPACK header field compression used in HTTP/2

in Tungsten:Forge:H2

+ Decoder
  ro :dynamic_table
  ro :max_size
  ro :current_size

  -> new(max_size: 4096)
    @dynamic_table = []
    @max_size = max_size
    @current_size = 0

  -> decode(bytes)
    headers = []
    offset = 0

    while offset < bytes.size
      byte = bytes.get(offset)

      if (byte & 0x80) != 0
        # Indexed header field (Section 6.1): 1xxxxxxx
        index, offset = self.decode_integer(bytes, offset, 7)
        entry = self.lookup(index)
        <! HPACKError.new("Invalid index: [index]") unless entry
        headers.push([entry[0], entry[1]])

      elsif (byte & 0xC0) == 0x40
        # Literal with incremental indexing (Section 6.2.1): 01xxxxxx
        index, offset = self.decode_integer(bytes, offset, 6)

        if index > 0
          entry = self.lookup(index)
          <! HPACKError.new("Invalid index: [index]") unless entry
          name = entry[0]
        else
          name, offset = self.decode_string(bytes, offset)

        value, offset = self.decode_string(bytes, offset)
        self.add_to_dynamic_table(name, value)
        headers.push([name, value])

      elsif (byte & 0xF0) == 0x00
        # Literal without indexing (Section 6.2.2): 0000xxxx
        index, offset = self.decode_integer(bytes, offset, 4)

        if index > 0
          entry = self.lookup(index)
          <! HPACKError.new("Invalid index: [index]") unless entry
          name = entry[0]
        else
          name, offset = self.decode_string(bytes, offset)

        value, offset = self.decode_string(bytes, offset)
        headers.push([name, value])

      elsif (byte & 0xF0) == 0x10
        # Literal never indexed (Section 6.2.3): 0001xxxx
        index, offset = self.decode_integer(bytes, offset, 4)

        if index > 0
          entry = self.lookup(index)
          <! HPACKError.new("Invalid index: [index]") unless entry
          name = entry[0]
        else
          name, offset = self.decode_string(bytes, offset)

        value, offset = self.decode_string(bytes, offset)
        headers.push([name, value])

      elsif (byte & 0xE0) == 0x20
        # Dynamic table size update (Section 6.3): 001xxxxx
        new_size, offset = self.decode_integer(bytes, offset, 5)
        @max_size = new_size
        self.evict

      else
        <! HPACKError.new("Invalid HPACK byte: 0x[byte.to_s(16)]")

    headers

  # --- Integer decoding (Section 5.1) ---

  -> decode_integer(bytes, offset, prefix_bits)
    prefix_mask = (1 << prefix_bits) - 1
    value = bytes.get(offset) & prefix_mask
    offset += 1

    if value < prefix_mask
      return [value, offset]

    # Multi-byte integer
    m = 0
    loop
      <! HPACKError.new("Unexpected end of integer") if offset >= bytes.size
      byte = bytes.get(offset)
      offset += 1
      value += (byte & 0x7F) << m
      m += 7
      break if (byte & 0x80) == 0

    [value, offset]

  # --- String decoding (Section 5.2) ---

  -> decode_string(bytes, offset)
    huffman = (bytes.get(offset) & 0x80) != 0
    length, offset = self.decode_integer(bytes, offset, 7)

    raw = bytes.slice(offset, length)
    offset += length

    string = if huffman
      Huffman.decode(raw)
    else
      raw.to_s

    [string, offset]

  # --- Table lookup (Section 2.3) ---

  -> lookup(index)
    return nil if index < 1

    # Indices 1-61 are the static table
    static = StaticTable.lookup(index)
    return static if static

    # Indices 62+ map into the dynamic table (62 = first/newest entry)
    dyn_index = index - StaticTable.entries.size - 1
    return nil if dyn_index < 0 || dyn_index >= @dynamic_table.size
    @dynamic_table[dyn_index]

  # --- Dynamic table management (Section 4) ---

  -> add_to_dynamic_table(name, value)
    # Entry size = name octets + value octets + 32 (RFC 7541 Section 4.1)
    entry_size = name.size + value.size + 32

    # Evict if adding this entry would exceed max size
    while @current_size + entry_size > @max_size && @dynamic_table.size > 0
      self.evict_one

    # If the entry itself is larger than the table, clear and don't add
    if entry_size > @max_size
      @dynamic_table = []
      @current_size = 0
      return nil

    # Insert at front (newest first)
    @dynamic_table.unshift([name, value])
    @current_size += entry_size

  -> evict
    while @current_size > @max_size && @dynamic_table.size > 0
      self.evict_one

  -> evict_one
    entry = @dynamic_table.pop
    return nil unless entry
    @current_size -= entry[0].size + entry[1].size + 32


+ Encoder
  ro :dynamic_table
  ro :max_size
  ro :current_size

  -> new(max_size: 4096)
    @dynamic_table = []
    @max_size = max_size
    @current_size = 0

  -> encode(headers)
    output = Bytes.new(0)

    headers.each -> (header)
      name  = header[0]
      value = header[1]
      match = self.find_index(name, value)

      if match && match[1] == :full
        # Fully indexed — emit indexed header field (Section 6.1)
        output = output.concat(self.encode_integer(match[0], 7, 0x80))

      elsif match && match[1] == :name
        # Name match — literal with incremental indexing (Section 6.2.1)
        output = output.concat(self.encode_integer(match[0], 6, 0x40))
        output = output.concat(self.encode_string(value))
        self.add_to_dynamic_table(name, value)

      else
        # No match — literal with incremental indexing, new name (Section 6.2.1)
        prefix = Bytes.new(1)
        prefix.set(0, 0x40)
        output = output.concat(prefix)
        output = output.concat(self.encode_string(name))
        output = output.concat(self.encode_string(value))
        self.add_to_dynamic_table(name, value)

    output

  # --- Integer encoding (Section 5.1) ---

  -> encode_integer(value, prefix_bits, pattern)
    prefix_mask = (1 << prefix_bits) - 1

    if value < prefix_mask
      # Fits in the prefix
      result = Bytes.new(1)
      result.set(0, pattern | value)
      return result

    # Multi-byte: fill prefix with all 1s, encode remainder
    result = Bytes.new(1)
    result.set(0, pattern | prefix_mask)
    value -= prefix_mask

    while value >= 0x80
      continuation = Bytes.new(1)
      continuation.set(0, (value & 0x7F) | 0x80)
      result = result.concat(continuation)
      value = value >> 7

    tail = Bytes.new(1)
    tail.set(0, value)
    result.concat(tail)

  # --- String encoding (Section 5.2) ---

  -> encode_string(string, huffman: false)
    if huffman
      encoded = Huffman.encode(string)
      length_prefix = self.encode_integer(encoded.size, 7, 0x80)
      return length_prefix.concat(encoded)

    # Raw string (no Huffman)
    raw = string.to_bytes
    length_prefix = self.encode_integer(raw.size, 7, 0x00)
    length_prefix.concat(raw)

  # --- Table search ---

  -> find_index(name, value)
    # Check static table first
    static_match = StaticTable.find(name, value)
    return static_match if static_match && static_match[1] == :full

    # Check dynamic table
    name_match = static_match
    @dynamic_table.each_with_index -> (entry, i)
      dyn_index = StaticTable.entries.size + 1 + i
      if entry[0] == name
        if entry[1] == value
          return [dyn_index, :full]
        name_match ||= [dyn_index, :name]

    name_match

  # --- Dynamic table management ---

  -> add_to_dynamic_table(name, value)
    entry_size = name.size + value.size + 32

    while @current_size + entry_size > @max_size && @dynamic_table.size > 0
      self.evict_one

    if entry_size > @max_size
      @dynamic_table = []
      @current_size = 0
      return nil

    @dynamic_table.unshift([name, value])
    @current_size += entry_size

  -> evict_one
    entry = @dynamic_table.pop
    return nil unless entry
    @current_size -= entry[0].size + entry[1].size + 32


+ HPACKError < StandardError

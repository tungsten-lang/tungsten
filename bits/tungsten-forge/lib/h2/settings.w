# Forge::H2::Settings — HTTP/2 settings registry
# RFC 7540 Section 6.5.2: Defined SETTINGS Parameters

in Tungsten:Forge:H2

+ Settings
  # Setting identifiers
  HEADER_TABLE_SIZE      = 0x1
  ENABLE_PUSH            = 0x2
  MAX_CONCURRENT_STREAMS = 0x3
  INITIAL_WINDOW_SIZE    = 0x4
  MAX_FRAME_SIZE         = 0x5
  MAX_HEADER_LIST_SIZE   = 0x6

  # Default values per RFC 7540 Section 6.5.2
  -> .defaults
    settings = {}
    settings[0x1] = 4096      # HEADER_TABLE_SIZE
    settings[0x2] = 1         # ENABLE_PUSH
    settings[0x3] = 100       # MAX_CONCURRENT_STREAMS (server choice)
    settings[0x4] = 65535     # INITIAL_WINDOW_SIZE
    settings[0x5] = 16384     # MAX_FRAME_SIZE
    settings[0x6] = 8192      # MAX_HEADER_LIST_SIZE (advisory)
    settings

  -> .parse(payload)
    # Parse SETTINGS frame payload (6 bytes per setting: 2-byte id + 4-byte value)
    settings = {}
    offset = 0

    while offset + 6 <= payload.size
      # Identifier: 2 bytes big-endian
      id = (payload.get(offset) << 8) | payload.get(offset + 1)

      # Value: 4 bytes big-endian
      b0 = payload.get(offset + 2)
      b1 = payload.get(offset + 3)
      b2 = payload.get(offset + 4)
      b3 = payload.get(offset + 5)
      value = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

      settings[id] = value
      offset += 6

    settings

  -> .encode(settings_hash)
    # Encode settings hash to Bytes payload
    pairs = settings_hash.to_a
    payload = Bytes.new(pairs.size * 6)

    pairs.each_with_index -> (pair, i)
      id    = pair[0]
      value = pair[1]
      offset = i * 6

      # Identifier: 2 bytes big-endian
      payload.set(offset,     (id >> 8) & 0xFF)
      payload.set(offset + 1,  id       & 0xFF)

      # Value: 4 bytes big-endian
      payload.set(offset + 2, (value >> 24) & 0xFF)
      payload.set(offset + 3, (value >> 16) & 0xFF)
      payload.set(offset + 4, (value >> 8)  & 0xFF)
      payload.set(offset + 5,  value        & 0xFF)

    payload

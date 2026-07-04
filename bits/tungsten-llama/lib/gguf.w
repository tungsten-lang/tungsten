# GGUF file loader. Parses header + metadata + tensor info from an
# mmap'd GGUF v3 file. Tensor weight data stays as raw bytes in the
# mmap; callers extract typed views on demand via Tensor accessors
# (P5.2).
#
# Spec: https://github.com/ggml-org/ggml/blob/master/docs/gguf.md
# Tested against qwen3:30b-a3b-q8_0 (32 GB, 579 tensors).

in Tungsten:Llama

use bin_reader
use gguf_types

# Magic for GGUF v1+ — ASCII "GGUF" little-endian.
GGUF_MAGIC = 0x46554747

# A loaded GGUF file. Owns the mmap; metadata + tensor descriptors
# eagerly parsed into in-memory structures. Tensor weight data is NOT
# read until a caller asks for a Tensor view of it.
+ GGUF
  rw :path           # filesystem path, for error messages
  rw :mmap           # File.mmap handle (the byte source)
  rw :version        # GGUF version (we test against v3)
  rw :metadata       # Hash{String name → typed value}
  rw :tensors        # Array of {name, shape, type, offset_in_file}
  rw :data_offset    # absolute byte offset where tensor data starts

  -> new(path)
    @path = path
    @mmap = File.mmap(path)
    @metadata = {}
    @tensors = []
    parse()

  -> close
    @mmap.close

  # Parse header + metadata + tensor info. Leaves @data_offset pointing
  # at the (aligned) start of the weights region.
  -> parse
    reader = BinReader.new(@mmap)
    magic = reader.read_u32()
    if magic != GGUF_MAGIC
      raise "GGUF: bad magic " + magic.to_s + " in " + @path
    @version = reader.read_u32()
    if @version != 3
      raise "GGUF: only v3 supported, got v" + @version.to_s
    tensor_count = reader.read_u64()
    kv_count = reader.read_u64()

    # Metadata KVs — key (gguf string) + type tag (u32) + typed value.
    i = 0
    while i < kv_count
      key = reader.read_gguf_string
      value_type = reader.read_u32()
      value = reader.read_gguf_value(value_type)
      @metadata[key] = value
      i = i + 1

    # Tensor info entries. Layout: name (gguf string), n_dims (u32),
    # dims (u64 × n_dims), type (u32), offset (u64). Offset is relative
    # to the data region (NOT to the file start).
    i = 0
    while i < tensor_count
      name = reader.read_gguf_string
      n_dims = reader.read_u32()
      dims = []
      d = 0
      while d < n_dims
        dims.push(reader.read_u64())
        d = d + 1
      ttype = reader.read_u32()
      offset_in_data = reader.read_u64()
      @tensors.push({
        name: name,
        shape: dims,
        type: ttype,
        type_name: ggml_type_name(ttype),
        offset_in_data: offset_in_data
      })
      i = i + 1

    # Align to 32 bytes (the default GGUF general.alignment).
    align = @metadata["general.alignment"]
    if align == nil
      align = 32
    r = reader.pos % align
    if r != 0
      reader.skip(align - r)
    @data_offset = reader.pos

  # Look up a tensor descriptor by name. Returns nil if missing.
  -> tensor(name)
    i = 0
    while i < @tensors.size()
      if @tensors[i][:name] == name
        return @tensors[i]
      i = i + 1
    nil

  # Absolute file offset of a tensor's first byte.
  -> tensor_file_offset(t)
    @data_offset + t[:offset_in_data]

  # Total bytes occupied by a tensor on disk. Q8_0: N * (K/32) * 34.
  # F32: N * 4. Etc. Uses ggml_type_size + ggml_block_size from
  # gguf_types.w.
  -> tensor_bytes(t)
    elements = 1
    i = 0
    while i < t[:shape].size()
      elements = elements * t[:shape][i]
      i = i + 1
    block_size = ggml_block_size(t[:type])
    type_size = ggml_type_size(t[:type])
    if block_size == 0 || type_size == 0
      raise "GGUF: unsupported type " + t[:type].to_s + " for tensor " + t[:name]
    (elements / block_size) * type_size

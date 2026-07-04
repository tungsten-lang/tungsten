# Tensor — a typed view over a region of an mmap'd GGUF file.
#
# A Tensor doesn't own its bytes; it just knows where they live
# (mmap + byte_offset) and what shape/dtype to interpret them with.
# The actual bytes don't move into Metal buffers until the inference
# loop dispatches a kernel and calls .copy_to_metal_buffer.
#
# Lifetime: the parent GGUF must outlive every Tensor that points
# into it; closing the GGUF unmaps the bytes.

in Tungsten:Llama

use bin_reader

+ Tensor
  rw :gguf            # parent GGUF (for the mmap handle)
  rw :name            # like "blk.0.attn_q.weight"
  rw :shape           # array of dim sizes, GGUF order
  rw :type            # ggml_type tag (int)
  rw :type_name       # human label like "Q8_0", "F16", "F32"
  rw :file_offset     # absolute byte offset of first byte
  rw :byte_length     # total bytes the tensor occupies on disk

  -> new(gguf, descriptor)
    @gguf = gguf
    @name = descriptor[:name]
    @shape = descriptor[:shape]
    @type = descriptor[:type]
    @type_name = descriptor[:type_name]
    @file_offset = gguf.tensor_file_offset(descriptor)
    @byte_length = gguf.tensor_bytes(descriptor)

  # Total scalar elements (product of dims). For Q8_0, this counts
  # the original int8 quants — the on-disk byte count is
  # `(elements / 32) * 34` because each block adds an f16 scale.
  -> element_count
    n = 1
    i = 0
    while i < @shape.size()
      n = n * @shape[i]
      i = i + 1
    n

  # Quick byte read at offset within the tensor — useful for header
  # peeks (Q8_0 first scale, etc.) without copying the whole region.
  -> byte_at(i)
    @gguf.mmap.byte_at(@file_offset + i)

  # Read a u16 (little-endian) at byte offset — Q8_0 scales are u16
  # bit patterns interpreted as f16.
  -> u16_at(i)
    lo = byte_at(i)
    hi = byte_at(i + 1)
    lo | (hi << 8)

  # Read a signed i8 at byte offset — Q8_0 quants are i8.
  -> i8_at(i)
    b = byte_at(i)
    if b >= 128
      b - 256
    else
      b

  # Upload a Q8_0 tensor to two Metal buffers in our cooperative
  # kernel's expected layout: separated f16 scales + i8 quants.
  # Returns {scales: <buf>, quants: <buf>, n_blocks: <int>}.
  # n_blocks = element_count / 32.
  -> upload_q8(device)
    if @type_name != "Q8_0"
      raise "Tensor.upload_q8: " + @name + " is " + @type_name + ", not Q8_0"
    n_blocks = element_count / 32
    scales = metal_buffer(device, n_blocks * 2)
    quants = metal_buffer(device, n_blocks * 32)
    metal_q8_split_blocks(scales, quants, @gguf.mmap, @file_offset, n_blocks)
    {scales: scales, quants: quants, n_blocks: n_blocks}

  # Upload an f32 tensor as a Metal buffer (one bulk memcpy).
  -> upload_f32(device)
    if @type_name != "F32"
      raise "Tensor.upload_f32: " + @name + " is " + @type_name + ", not F32"
    buf = metal_buffer(device, @byte_length)
    metal_buffer_write_from_mmap(buf, 0, @gguf.mmap, @file_offset, @byte_length)
    buf

  # Pretty-print one line for debugging.
  -> to_s
    "Tensor(" + @name + " " + @type_name + " " + @shape.to_s + " @" + @file_offset.to_s + " +" + @byte_length.to_s + "B)"

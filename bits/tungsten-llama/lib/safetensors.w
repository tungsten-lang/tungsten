# Minimal safetensors v0.4 reader.
#
# Format:
#   bytes [0..7]:        little-endian uint64 = JSON header length N
#   bytes [8..8+N):      JSON header — { "tensor_name": { "dtype":..., "shape":..., "data_offsets":[start, end] }, ... }
#   bytes [8+N..end):    raw tensor data (data_offsets are relative to this base)
#
# We hold the file mmap and a hash of tensor descriptors. Callers either
# mmap-copy bytes into Metal buffers (the fast path for big tensors) or
# read individual values (small tensors).

use core/json

in Tungsten:Llama

# Build a one-byte string from a raw byte (0..255). Wraps the runtime
# helper since ccall args don't auto-box from method receivers.
fn safetensors_byte_to_str(b)
  ccall("w_string_from_byte", b)

+ Safetensors
  # Workaround: `rw :foo` triggers an emitter bug — undefined symbol for the
  # generated rw accessor functions. Expanding manually.
  -> mmap
    @mmap
  -> mmap=(value)
    @mmap = value
  -> tensors
    @tensors
  -> tensors=(value)
    @tensors = value
  -> data_offset
    @data_offset
  -> data_offset=(value)
    @data_offset = value

  -> new(path)
    @mmap = File.mmap(path)
    # Read 8-byte little-endian header length
    hl = 0
    i = 0
    while i < 8
      hl = hl | (@mmap.byte_at(i) << (i * 8))
      i = i + 1
    @data_offset = 8 + hl

    # Pull header bytes into a string and parse as JSON
    sb = StringBuffer(hl)
    i = 0
    while i < hl
      sb << safetensors_byte_to_str(@mmap.byte_at(8 + i))
      i = i + 1
    parsed = JSON.parse(sb.to_s)

    @tensors = {}
    keys = parsed.keys
    ki = 0
    while ki < keys.size()
      key = keys[ki]
      if key != "__metadata__"
        desc = parsed[key]
        @tensors[key] = {
          dtype: desc["dtype"],
          shape: desc["shape"],
          byte_offset: @data_offset + desc["data_offsets"][0],
          byte_length: desc["data_offsets"][1] - desc["data_offsets"][0]
        }
      ki = ki + 1

  -> close
    @mmap.close

  # Number of tensors in the file
  -> count
    @tensors.size()

  # Tensor descriptor by name (raises if missing)
  -> tensor(name)
    t = @tensors[name]
    if t == nil
      raise "Safetensors: tensor `" + name + "` not found"
    t

  -> has?(name)
    @tensors[name] != nil

  # Copy raw bytes for `name` into a Metal buffer (zero-copy from mmap)
  -> upload_bytes(name, dst_buf)
    t = tensor(name)
    metal_buffer_write_from_mmap(dst_buf, 0, @mmap, t[:byte_offset], t[:byte_length])

  # Return absolute byte offset of tensor `name` for callers that want
  # to mmap a slice directly without going through a Metal buffer.
  -> byte_offset(name)
    tensor(name)[:byte_offset]

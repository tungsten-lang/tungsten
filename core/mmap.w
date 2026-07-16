# Mmap — borrowed read-only file bytes returned by File.mmap.

# The compiled path recognizes File.mmap directly. This small source facade
# gives the tree walker the same constructor without loading all of core/file.
+ File
  -> .mmap(path)
    ccall("__w_file_mmap", path)

+ Mmap
  # WMmap is a W_SUBTAG_GENERIC object. The view's named C layout accounts for
  # the hidden type discriminator, so `closed` starts at effective byte 1 and
  # the declared size field reaches WMmap.size at byte 16.
  - data (WMmap)
    u8     closed
    u8[6]  pad
    * u8[] data
    i64    size

  # A real mapping length is nonnegative. It fits the immediate signed-i48
  # payload exactly when its arithmetic shift by 47 is zero. Synthetic corrupt
  # or enormous headers retain __w_mmap_length's canonical w_int semantics.
  -> size
    n = $size ## i64
    if (n >> 47) != 0
      return ccall("w_int", n)
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    payload = (n & 0xFFFFFFFFFFFF) ## i64
    wvalue_from_bits((tag | payload) ## i64)

  # byte_at stays native because source dispatch pads a missing argument with
  # nil and thereby changes its dedicated fatal diagnostic. The typed-view
  # leaves pass a compile-time raw i64 element encoding to the lower-level
  # primitive; __w_mmap_as_typed uses an explicit i64 ABI so no boxed/raw width
  # mismatch is hidden at this boundary.
  -> byte_at(i)

  # `[]` and `close` are common spellings on unrelated types. They also retain
  # native ICs because an opaque Mmap parameter/native result cannot soundly
  # autoload their source bodies without loading Mmap into essentially every
  # indexed or closable program.
  -> [](i)

  -> as_u8
    ccall("__w_mmap_as_typed", self, 8)

  -> as_u16
    ccall("__w_mmap_as_typed", self, 16)

  -> as_u32
    ccall("__w_mmap_as_typed", self, 32)

  -> as_u64
    ccall("__w_mmap_as_typed", self, 64)

  -> as_i8
    ccall("__w_mmap_as_typed", self, 108)

  -> as_i16
    ccall("__w_mmap_as_typed", self, 116)

  -> as_i32
    ccall("__w_mmap_as_typed", self, 32)

  -> as_i64
    ccall("__w_mmap_as_typed", self, 64)

  -> as_f32
    ccall("__w_mmap_as_typed", self, -32)

  -> as_f64
    ccall("__w_mmap_as_typed", self, -64)

  # Keep this native. Its old IC performs two unchecked WValue-payload
  # extractions plus exact Symbol/immediate-Integer decoding before entering a
  # mixed WValue/raw/raw/raw primitive. A source wrapper using numeric coercion
  # would accept values the native API rejects, while passing the boxes through
  # would corrupt offsets and counts.
  -> view_at(byte_offset, ebits, n_elements)

  -> close

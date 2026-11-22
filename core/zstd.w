# Zstd — Zstandard (RFC 8878) through the runtime's libzstd.
#
#   Zstd.decompress(data)          # String of compressed bytes → u8[] (ByteArray), or nil
#   Zstd.compress(data, level = 3) # String of bytes → u8[] (one frame, content size recorded), or nil
#
# decompress takes a whole stream (one or more frames, with or without a content size) and
# answers the decoded bytes, or nil when the input is not valid zstd or the runtime was built
# without libzstd. Windows larger than 128 MiB are refused. compress levels run 1 (fastest)
# to 22 (smallest); nil without libzstd.
+ Zstd
  -> .decompress(data)
    ccall("w_zstd_decompress", data)

  -> .compress(data, level = 3)
    ccall("w_zstd_compress", data, level)

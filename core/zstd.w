# Zstd — Zstandard (RFC 8878) decompression through the runtime's libzstd.
#
#   Zstd.decompress(data)   # String of compressed bytes → u8[] (ByteArray), or nil
#
# Takes a whole stream (one or more frames, with or without a content size) and answers
# the decoded bytes, or nil when the input is not valid zstd or the runtime was built
# without libzstd. Windows larger than 128 MiB are refused.
+ Zstd
  -> .decompress(data)
    ccall("w_zstd_decompress", data)

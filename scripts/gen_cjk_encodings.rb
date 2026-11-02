#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates compact lazy-loaded CJK encoding tables in ~/.tungsten/encodings/*.bin:
#   - cp932.bin   (256 KB): Shift_JIS (39), Windows-31J / CP932 (11), MacJapanese (93), SJIS-DoCoMo/KDDI/SoftBank
#   - euc_jp.bin  (256 KB): EUC-JP (10), eucJP-ms (80), CP51932 (81), EUC-JIS-2004 (82), ISO-2022-JP (85)
#   - gb18030.bin (461 KB): GB18030 (20), GBK / CP936 (21), GB2312 / EUC-CN (83), GB12345 (84), HZ-GB-2312 (106)
#   - big5.bin    (256 KB): Big5 (12), Big5-HKSCS (13), Big5-UAO (14), CP950 (76), CP951 (77)
#   - cp949.bin   (256 KB): CP949 (16), EUC-KR (18), ISO-2022-KR (107)
#
# Layout of 256 KB tables:
#   [0 .. 131071]      65536 x u16le: decode[code] -> BMP codepoint (0 if unmapped)
#   [131072 .. 262143] 65536 x u16le: encode[cp]   -> code (b1 << 8 | b2, 0 if unmapped)
#
# Additional sections in gb18030.bin:
#   [262144 .. 340983] 39420 x u16le: decode4[ptr] -> BMP codepoint for 4-byte GB18030 (ptr 0..39419)
#   [340984 .. 472055] 65536 x u16le: encode4[cp]  -> ptr + 1 for 4-byte GB18030 (0 if not 4-byte)

require "fileutils"

default_home = ENV["TUNGSTEN_HOME"]
default_home = File.join(ENV["HOME"] || ".", ".tungsten") if default_home.nil? || default_home.empty?
OUT_DIR = ARGV[0] && !ARGV[0].empty? ? File.expand_path(ARGV[0]) : File.join(default_home, "encodings")
ONLY_TABLE = ARGV[1]
REGISTRY_URL = ARGV[2] || ENV["BIT_REGISTRY"] || "https://bits.tungsten-lang.org"
FileUtils.mkdir_p(OUT_DIR)

def try_download_table(filename)
  return false if REGISTRY_URL.nil? || REGISTRY_URL.empty? || ENV["TUNGSTEN_OFFLINE"] == "1"
  dest = File.join(OUT_DIR, filename)
  if REGISTRY_URL.start_with?("http://", "https://")
    url = "#{REGISTRY_URL.sub(%r{/+\z}, '')}/encodings/#{filename}"
    if system("curl", "-fsSL", "--connect-timeout", "2", "--max-time", "5", "-o", dest, url, err: File::NULL, out: File::NULL)
      return true if File.exist?(dest) && File.size(dest) >= 262_144
    end
  else
    local_dir = REGISTRY_URL.sub(/\Afile:\/\//, "")
    cand = File.join(local_dir, "encodings", filename)
    if File.exist?(cand) && File.size(cand) >= 262_144
      FileUtils.cp(cand, dest)
      return true
    end
  end
  false
end

def build_two_byte_table(primary_enc_name, fallback_enc_name = nil)
  decode = Array.new(65_536, 0)
  encode = Array.new(65_536, 0)

  encs = [Encoding.find(primary_enc_name)]
  encs << Encoding.find(fallback_enc_name) if fallback_enc_name

  encs.each_with_index do |enc, idx|
    (0x80..0xFFFF).each do |cp|
      next if cp >= 0xD800 && cp <= 0xDFFF
      s = [cp].pack("U")
      begin
        b = s.encode(enc).bytes
      rescue Encoding::UndefinedConversionError
        next
      end
      if b.size == 1 && b[0] >= 0x80
        code = b[0]
        decode[code] = cp if decode[code] == 0
        encode[cp] = code if encode[cp] == 0
      elsif b.size == 2
        code = (b[0] << 8) | b[1]
        decode[code] = cp if decode[code] == 0 || idx == 0
        encode[cp] = code if encode[cp] == 0
      end
    end
  end

  # Also scan all 2-byte codes (0x8100..0xFEFF) in primary_enc so any duplicate
  # byte-to-Unicode mappings in the code page are valid during decode.
  primary = encs.first
  (0x81..0xFE).each do |b1|
    (0x40..0xFE).each do |b2|
      code = (b1 << 8) | b2
      next if decode[code] != 0
      raw = [b1, b2].pack("C*").force_encoding(primary)
      next unless raw.valid_encoding?
      begin
        utf8 = raw.encode("UTF-8")
        if utf8.length == 1
          cp = utf8.ord
          decode[code] = cp if cp <= 0xFFFF
        end
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        next
      end
    end
  end

  [decode, encode]
end

# 1. cp932.bin (Shift_JIS + Windows-31J)
if (ONLY_TABLE.nil? || ONLY_TABLE == "cp932") && !try_download_table("cp932.bin")
  decode, encode = build_two_byte_table("Windows-31J", "Shift_JIS")
  File.binwrite(File.join(OUT_DIR, "cp932.bin"), (decode + encode).pack("v*"))
  puts "Wrote cp932.bin (#{File.size(File.join(OUT_DIR, 'cp932.bin'))} bytes)" if ONLY_TABLE.nil?
end

# 2. euc_jp.bin (EUC-JP + CP51932)
if (ONLY_TABLE.nil? || ONLY_TABLE == "euc_jp") && !try_download_table("euc_jp.bin")
  decode, encode = build_two_byte_table("EUC-JP", "CP51932")
  File.binwrite(File.join(OUT_DIR, "euc_jp.bin"), (decode + encode).pack("v*"))
  puts "Wrote euc_jp.bin (#{File.size(File.join(OUT_DIR, 'euc_jp.bin'))} bytes)" if ONLY_TABLE.nil?
end

# 3. big5.bin (CP950 + Big5)
if (ONLY_TABLE.nil? || ONLY_TABLE == "big5") && !try_download_table("big5.bin")
  decode, encode = build_two_byte_table("Big5", "CP950")
  File.binwrite(File.join(OUT_DIR, "big5.bin"), (decode + encode).pack("v*"))
  puts "Wrote big5.bin (#{File.size(File.join(OUT_DIR, 'big5.bin'))} bytes)" if ONLY_TABLE.nil?
end

# 4. cp949.bin (CP949 + EUC-KR)
if (ONLY_TABLE.nil? || ONLY_TABLE == "cp949") && !try_download_table("cp949.bin")
  decode, encode = build_two_byte_table("CP949", "EUC-KR")
  File.binwrite(File.join(OUT_DIR, "cp949.bin"), (decode + encode).pack("v*"))
  puts "Wrote cp949.bin (#{File.size(File.join(OUT_DIR, 'cp949.bin'))} bytes)" if ONLY_TABLE.nil?
end

# 5. gb18030.bin (GBK 2-byte + GB18030 4-byte BMP)
if (ONLY_TABLE.nil? || ONLY_TABLE == "gb18030") && !try_download_table("gb18030.bin")
  decode, encode = build_two_byte_table("GB18030", "GBK")
  decode4 = Array.new(39_420, 0)
  encode4 = Array.new(65_536, 0)
  gb18030 = Encoding.find("GB18030")
  (0x80..0xFFFF).each do |cp|
    next if cp >= 0xD800 && cp <= 0xDFFF
    s = [cp].pack("U")
    b = s.encode(gb18030).bytes
    if b.size == 4
      ptr = ((b[0] - 0x81) * 10 + (b[1] - 0x30)) * 1260 + (b[2] - 0x81) * 10 + (b[3] - 0x30)
      if ptr >= 0 && ptr < 39_420
        decode4[ptr] = cp
        encode4[cp] = ptr + 1
      end
    end
  end
  File.binwrite(File.join(OUT_DIR, "gb18030.bin"), (decode + encode + decode4 + encode4).pack("v*"))
  puts "Wrote gb18030.bin (#{File.size(File.join(OUT_DIR, 'gb18030.bin'))} bytes)" if ONLY_TABLE.nil?
end

# 6. johab.bin (Johab / CP1361 Korean)
if (ONLY_TABLE.nil? || ONLY_TABLE == "johab") && !try_download_table("johab.bin")
  out_path = File.join(OUT_DIR, "johab.bin")
  py = <<~PY
    import sys
    decode = [0] * 65536
    encode = [0] * 65536
    for cp in range(0x80, 0x10000):
        if 0xD800 <= cp <= 0xDFFF:
            continue
        try:
            b = chr(cp).encode("johab")
            if len(b) == 2:
                code = (b[0] << 8) | b[1]
                decode[code] = cp
                encode[cp] = code
        except Exception:
            pass
    import struct
    with open(sys.argv[1], "wb") as f:
        f.write(struct.pack("<131072H", *(decode + encode)))
  PY
  system("python3", "-c", py, out_path)
  puts "Wrote johab.bin (#{File.size(out_path)} bytes)" if ONLY_TABLE.nil? && File.exist?(out_path)
end

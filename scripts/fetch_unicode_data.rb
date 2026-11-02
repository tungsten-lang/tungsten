#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads or synthesizes the versioned Unicode property & normalization table
# (`unicode_data.bin`) into ~/.tungsten/unicode/ (or the target directory).
#
# Usage:
#   ruby scripts/fetch_unicode_data.rb [out_dir] [registry_url]

require "fileutils"
require "open3"

default_home = ENV["TUNGSTEN_HOME"]
default_home = File.join(ENV["HOME"] || ".", ".tungsten") if default_home.nil? || default_home.empty?
OUT_DIR = ARGV[0] && !ARGV[0].empty? ? File.expand_path(ARGV[0]) : File.join(default_home, "unicode")
REGISTRY_URL = ARGV[1] || ENV["BIT_REGISTRY"] || "https://bits.tungsten-lang.org"
FileUtils.mkdir_p(OUT_DIR)

OUT_FILE = File.join(OUT_DIR, "unicode_data.bin")

if !REGISTRY_URL.nil? && !REGISTRY_URL.empty? && ENV["TUNGSTEN_OFFLINE"] != "1"
  if REGISTRY_URL.start_with?("http://", "https://")
    url = "#{REGISTRY_URL.sub(%r{/+\z}, '')}/unicode/unicode_data.bin"
    if system("curl", "-fsSL", "--connect-timeout", "2", "--max-time", "5", "-o", OUT_FILE, url, err: File::NULL, out: File::NULL)
      exit 0 if File.exist?(OUT_FILE) && File.size(OUT_FILE) > 1024
    end
  else
    local_dir = REGISTRY_URL.sub(/\Afile:\/\//, "")
    cand = File.join(local_dir, "unicode", "unicode_data.bin")
    if File.exist?(cand) && File.size(cand) > 1024
      FileUtils.cp(cand, OUT_FILE)
      exit 0
    end
  end
end

# Fallback synthesis using Ruby's built-in Unicode properties and Python's unicodedata
VERSIONS = [
  "1.1", "2.0", "2.1", "3.0", "3.1", "3.2", "4.0", "4.1",
  "5.0", "5.1", "5.2", "6.0", "6.1", "6.2", "6.3", "7.0",
  "8.0", "9.0", "10.0", "11.0", "12.0", "12.1", "13.0",
  "14.0", "15.0", "15.1", "16.0", "17.0"
].freeze

SCRIPTS = [
  "Common", "Inherited", "Latin", "Greek", "Cyrillic", "Armenian", "Hebrew", "Arabic",
  "Syriac", "Thaana", "Devanagari", "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil",
  "Telugu", "Kannada", "Malayalam", "Sinhala", "Thai", "Lao", "Tibetan", "Myanmar",
  "Georgian", "Hangul", "Ethiopic", "Cherokee", "Canadian_Aboriginal", "Ogham", "Runic",
  "Khmer", "Mongolian", "Hiragana", "Katakana", "Bopomofo", "Han", "Yi", "Old_Italic",
  "Gothic", "Deseret", "Tagalog", "Hanunoo", "Buhid", "Tagbanwa", "Limbu", "Tai_Le",
  "Linear_B", "Ugaritic", "Shavian", "Osmanya", "Cypriot", "Braille", "Buginese", "Coptic",
  "New_Tai_Lue", "Glagolitic", "Tifinagh", "Syloti_Nagri", "Old_Persian", "Kharoshthi",
  "Balinese", "Cuneiform", "Phoenician", "Phags_Pa", "Nko", "Sundanese", "Lepcha",
  "Ol_Chiki", "Vai", "Saurashtra", "Kayah_Li", "Rejang", "Lycian", "Carian", "Lydian",
  "Cham", "Tai_Tham", "Tai_Viet", "Avestan", "Egyptian_Hieroglyphs", "Samaritan", "Lisu",
  "Bamum", "Javanese", "Meetei_Mayek", "Imperial_Aramaic", "Old_South_Arabian", "Inscriptional_Parthian",
  "Inscriptional_Pahlavi", "Old_Turkic", "Kaithi", "Batak", "Brahmi", "Mandaic", "Chakma",
  "Meroitic_Cursive", "Meroitic_Hieroglyphs", "Miao", "Sharada", "Sora_Sompeng", "Takri"
].freeze

def build_ranges(arr)
  ranges = []
  cur = arr[0]
  start_cp = 0
  (1..0x10FFFF).each do |cp|
    v = arr[cp]
    if v != cur
      ranges << [start_cp, (cp - 1 << 8) | cur] if cur != 0
      cur = v
      start_cp = cp
    end
  end
  ranges << [start_cp, (0x10FFFF << 8) | cur] if cur != 0
  ranges
end

all_str = ((0...0xD800).to_a + (0xE000..0x10FFFF).to_a).pack("U*")

age_arr = Array.new(0x110000, 0)
VERSIONS.each_with_index do |v, idx|
  vid = idx + 1
  begin
    rx = Regexp.new("\\p{Age=#{v}}+")
  rescue RegexpError
    next
  end
  all_str.scan(rx) do |m|
    m.each_codepoint { |cp| age_arr[cp] = vid if age_arr[cp] == 0 }
  end
end
age_ranges = build_ranges(age_arr)

script_arr = Array.new(0x110000, 0)
SCRIPTS.each_with_index do |sc, idx|
  next if idx == 0 # Common is 0 default
  begin
    rx = Regexp.new("\\p{#{sc}}+")
  rescue RegexpError
    next
  end
  all_str.scan(rx) do |m|
    m.each_codepoint { |cp| script_arr[cp] = idx if script_arr[cp] == 0 }
  end
end
script_ranges = build_ranges(script_arr)

py_script = <<~PYTHON
  import sys, struct, unicodedata

  MAX_CP = 0x110000
  SBASE, SCOUNT = 0xAC00, 11172
  def is_surrogate(cp): return 0xD800 <= cp <= 0xDFFF
  def is_hangul(cp): return SBASE <= cp < SBASE + SCOUNT

  eaw_map = {"N": 0, "Na": 1, "A": 2, "W": 3, "F": 4, "H": 5}
  bidi_names = [
    "L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN",
    "B", "S", "WS", "ON", "LRE", "LRO", "RLE", "RLO", "PDF",
    "LRI", "RLI", "FSI", "PDI"
  ]
  bidi_map = {name: i for i, name in enumerate(bidi_names)}

  ccc_entries = []
  eaw_arr = [0] * MAX_CP
  bidi_arr = [0] * MAX_CP
  nfd_entries = []
  nfkd_entries = []
  pool = []
  pool_cache = {}
  comp_entries = []

  def intern_seq(seq):
    t = tuple(seq)
    if t in pool_cache:
      return pool_cache[t]
    idx = len(pool)
    pool.extend(t)
    pool_cache[t] = idx
    return idx

  for cp in range(MAX_CP):
    if is_surrogate(cp): continue
    ch = chr(cp)
    c = unicodedata.combining(ch)
    if c:
      ccc_entries.append((cp, c))
    eaw_arr[cp] = eaw_map.get(unicodedata.east_asian_width(ch), 0)
    b_cls = bidi_map.get(unicodedata.bidirectional(ch), 0)
    mir = 1 if unicodedata.mirrored(ch) else 0
    bidi_arr[cp] = (mir << 6) | b_cls
    if not is_hangul(cp):
      d = unicodedata.normalize("NFD", ch)
      if d != ch:
        seq = [ord(x) for x in d]
        nfd_entries.append((cp, (intern_seq(seq) << 8) | len(seq)))
      kd = unicodedata.normalize("NFKD", ch)
      if kd != ch:
        seq = [ord(x) for x in kd]
        nfkd_entries.append((cp, (intern_seq(seq) << 8) | len(seq)))
      raw = unicodedata.decomposition(ch)
      if raw and not raw.startswith("<"):
        parts = [int(x, 16) for x in raw.split()]
        if len(parts) == 2:
          a, b = parts
          if unicodedata.normalize("NFC", chr(a) + chr(b)) == ch:
            comp_entries.append((a, b, cp))

  comp_entries.sort()

  def build_ranges(arr):
    out = []
    cur = arr[0]
    start = 0
    for cp in range(1, MAX_CP):
      v = arr[cp]
      if v != cur:
        if cur != 0:
          out.append((start, ((cp - 1) << 8) | cur))
        cur = v
        start = cp
    if cur != 0:
      out.append((start, (0x10FFFF << 8) | cur))
    return out

  eaw_ranges = build_ranges(eaw_arr)
  bidi_ranges = build_ranges(bidi_arr)

  out = []
  out.append(len(ccc_entries))
  for a, b in ccc_entries: out.extend([a, b])
  out.append(len(eaw_ranges))
  for a, b in eaw_ranges: out.extend([a, b])
  out.append(len(bidi_ranges))
  for a, b in bidi_ranges: out.extend([a, b])
  out.append(len(nfd_entries))
  for a, b in nfd_entries: out.extend([a, b])
  out.append(len(nfkd_entries))
  for a, b in nfkd_entries: out.extend([a, b])
  out.append(len(pool))
  out.extend(pool)
  out.append(len(comp_entries))
  for a, b, c in comp_entries: out.extend([a, b, c])

  sys.stdout.buffer.write(struct.pack(f"<{len(out)}I", *out))
PYTHON

py_out, status = Open3.capture2("python3", "-c", py_script, binmode: true)
abort "python3 unicodedata extraction failed" unless status.success?

words = py_out.unpack("V*")
pos = 0
ccc_count = words[pos]; pos += 1
ccc_words = words[pos, ccc_count * 2]; pos += ccc_count * 2

eaw_count = words[pos]; pos += 1
eaw_words = words[pos, eaw_count * 2]; pos += eaw_count * 2

bidi_count = words[pos]; pos += 1
bidi_words = words[pos, bidi_count * 2]; pos += bidi_count * 2

nfd_count = words[pos]; pos += 1
nfd_words = words[pos, nfd_count * 2]; pos += nfd_count * 2

nfkd_count = words[pos]; pos += 1
nfkd_words = words[pos, nfkd_count * 2]; pos += nfkd_count * 2

pool_count = words[pos]; pos += 1
pool_words = words[pos, pool_count]; pos += pool_count

comp_count = words[pos]; pos += 1
comp_words = words[pos, comp_count * 3]; pos += comp_count * 3

age_words = age_ranges.flatten
script_words = script_ranges.flatten

header = Array.new(18, 0)
cur_off = 18

header[0] = cur_off; header[1] = age_ranges.size; cur_off += age_words.size
header[2] = cur_off; header[3] = ccc_count;       cur_off += ccc_words.size
header[4] = cur_off; header[5] = eaw_count;       cur_off += eaw_words.size
header[6] = cur_off; header[7] = bidi_count;      cur_off += bidi_words.size
header[8] = cur_off; header[9] = script_ranges.size; cur_off += script_words.size
header[10] = cur_off; header[11] = nfd_count;     cur_off += nfd_words.size
header[12] = cur_off; header[13] = nfkd_count;    cur_off += nfkd_words.size
header[14] = cur_off; header[15] = pool_count;    cur_off += pool_words.size
header[16] = cur_off; header[17] = comp_count;    cur_off += comp_words.size

all_words = header + age_words + ccc_words + eaw_words + bidi_words + script_words + nfd_words + nfkd_words + pool_words + comp_words
File.binwrite(OUT_FILE, all_words.pack("V*"))

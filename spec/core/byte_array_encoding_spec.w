# ByteArray & String encoding, validation, and transcoding spec.
#
# Run:
#   bin/tungsten spec/core/byte_array_encoding_spec.w
#   bin/tungsten run --interpret spec/core/byte_array_encoding_spec.w
#   bin/tungsten --ruby spec/core/byte_array_encoding_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()

# ---- String & ASCII String underlying encoding and #encode ----
s_utf8 = "hello"
s_ascii = 'hello'
check("String#encoding is UTF-8", s_utf8.encoding == "UTF-8")
check("ASCII literal String#encoding is UTF-8", s_ascii.encoding == "UTF-8")

b_utf8 = s_utf8.encode(:utf8)
b_ascii = s_ascii.encode(:ascii)
check("String#encode returns ByteArray", b_utf8.is_a?(ByteArray) && b_ascii.is_a?(ByteArray))
check("String#encode(:utf8) bytes", b_utf8 == « 68 65 6c 6c 6f »)
check("ASCII String#encode(:ascii) bytes", b_ascii == « 68 65 6c 6c 6f »)
check("ASCII String#encode(:utf16le) bytes", s_ascii.encode(:utf16le) == « 68 00 65 00 6c 00 6c 00 6f 00 »)
check("String#to_byte_array", s_utf8.to_byte_array == « 68 65 6c 6c 6f »)

# ---- WArray header encoding_id (CRuby encindex parity) ----
raw_ba = « 41 42 43 »
check("raw ByteArray defaults to encoding_id 0 (ASCII-8BIT)", raw_ba.encoding_id == 0 && raw_ba.encoding == "ASCII-8BIT")
check("UTF-8 encoded ByteArray has encoding_id 1 (UTF-8)", b_utf8.encoding_id == 1 && b_utf8.encoding == "UTF-8")
check("US-ASCII encoded ByteArray has encoding_id 2 (US-ASCII)", b_ascii.encoding_id == 2 && b_ascii.encoding == "US-ASCII")
check("UTF-16BE encoded ByteArray has encoding_id 3", "A".encode(:utf16be).encoding_id == 3 && "A".encode(:utf16be).encoding == "UTF-16BE")
check("UTF-16LE encoded ByteArray has encoding_id 4", "A".encode(:utf16le).encoding_id == 4 && "A".encode(:utf16le).encoding == "UTF-16LE")
check("UTF-32BE encoded ByteArray has encoding_id 5", "A".encode(:utf32be).encoding_id == 5 && "A".encode(:utf32be).encoding == "UTF-32BE")
check("UTF-32LE encoded ByteArray has encoding_id 6", "A".encode(:utf32le).encoding_id == 6 && "A".encode(:utf32le).encoding == "UTF-32LE")
check("UTF-16 encoded ByteArray has encoding_id 7", "A".encode(:utf16).encoding_id == 7 && "A".encode(:utf16).encoding == "UTF-16")
check("UTF-32 encoded ByteArray has encoding_id 8", "A".encode(:utf32).encoding_id == 8 && "A".encode(:utf32).encoding == "UTF-32")
check("ISO-8859-1 encoded ByteArray has encoding_id 22", "é".encode(:latin1).encoding_id == 22 && "é".encode(:latin1).encoding == "ISO-8859-1")
check("slice preserves header encoding_id", b_utf8.slice(0, 2).encoding_id == 1 && "é".encode(:latin1).slice(0, 1).encoding_id == 22)

# ---- Unicode Standard BOM-aware UTF-16 (7) and UTF-32 (8) ----
u16_bom = "Aé".encode(:utf16)
check("String#encode(:utf16) emits FE FF BOM + BE code units", u16_bom == « fe ff 00 41 00 e9 » && u16_bom.encoding_id == 7)
check("empty String#encode(:utf16) is empty with encoding_id 7", "".encode(:utf16) == « » && "".encode(:utf16).encoding_id == 7)
check("UTF-16 decode with BE BOM", « fe ff 00 41 00 e9 ».decode(:utf16) == "Aé")
check("UTF-16 decode with LE BOM", « ff fe 41 00 e9 00 ».decode(:utf16) == "Aé")
check("UTF-16 decode without BOM defaults to BE per Unicode D98", « 00 41 00 e9 ».decode(:utf16) == "Aé")

u32_bom = "Aé".encode(:utf32)
check("String#encode(:utf32) emits 00 00 FE FF BOM + BE code units", u32_bom == « 00 00 fe ff 00 00 00 41 00 00 00 e9 » && u32_bom.encoding_id == 8)
check("empty String#encode(:utf32) is empty with encoding_id 8", "".encode(:utf32) == « » && "".encode(:utf32).encoding_id == 8)
check("UTF-32 decode with BE BOM", « 00 00 fe ff 00 00 00 41 00 00 00 e9 ».decode(:utf32) == "Aé")
check("UTF-32 decode with LE BOM", « ff fe 00 00 41 00 00 00 e9 00 00 00 ».decode(:utf32) == "Aé")
check("UTF-32 decode without BOM defaults to BE per Unicode D101", « 00 00 00 41 00 00 00 e9 ».decode(:utf32) == "Aé")

# ---- 0-arg #valid_encoding?, 0-arg #decode, 1-arg #transcode using header encoding_id ----
tagged_bad_utf8 = « ff ».force_encoding(:utf8)
check("0-arg valid_encoding? uses header encoding_id", !tagged_bad_utf8.valid_encoding? && « ff ».force_encoding(:binary).valid_encoding?)
check("0-arg decode uses header encoding_id on UTF-16 and Latin-1", u16_bom.decode() == "Aé" && "café".encode(:latin1).decode() == "café")
u16le_from_bom = u16_bom.transcode(:utf16le)
check("1-arg transcode uses header encoding_id and updates target encoding_id", u16le_from_bom == « 41 00 e9 00 » && u16le_from_bom.encoding_id == 4 && u16le_from_bom.decode() == "Aé")

non_ascii_to_ascii_raises = false
begin
  "é".encode(:ascii)
rescue e
  non_ascii_to_ascii_raises = true
check("non-ASCII String#encode(:ascii) raises", non_ascii_to_ascii_raises)

check("String#encode(:latin1)", "é".encode(:latin1) == « e9 » && "é".encode("ISO-8859-1") == « e9 »)

above_latin1_raises = false
begin
  "∞".encode(:latin1)
rescue e
  above_latin1_raises = true
check("String#encode(:latin1) raises for > U+00FF", above_latin1_raises)

mixed = "Aé" + U+1F600.to_s()
check("String#encode(:utf16le)", mixed.encode(:utf16le) == « 41 00 e9 00 3d d8 00 de »)
check("String#encode(:utf16be)", mixed.encode(:utf16be) == « 00 41 00 e9 d8 3d de 00 »)
check("String#encode(:utf32le)", mixed.encode(:utf32le) == « 41 00 00 00 e9 00 00 00 00 f6 01 00 »)
check("String#encode(:utf32be)", mixed.encode(:utf32be) == « 00 00 00 41 00 00 00 e9 00 01 f6 00 »)

# ---- ByteArray#valid_encoding? ----
check("ASCII bytes valid in ascii and utf8", « 41 42 43 ».valid_encoding?(:ascii) && « 41 42 43 ».valid_encoding?(:utf8) && « 41 42 43 ».valid_ascii? && « 41 42 43 ».valid_utf8?)
check("UTF-8 multibyte valid in utf8, invalid in ascii", « c3 a9 ».valid_encoding?(:utf8) && !« c3 a9 ».valid_encoding?(:ascii))
check("invalid UTF-8 single byte 0xFF", !« ff ».valid_encoding?(:utf8) && « ff ».valid_encoding?(:latin1))
check("invalid UTF-8 overlong 0xC0 0x80", !« c0 80 ».valid_encoding?(:utf8))
check("invalid UTF-8 surrogate U+D800", !« ed a0 80 ».valid_encoding?(:utf8))
check("invalid UTF-8 truncated 3-byte", !« e2 82 ».valid_encoding?(:utf8))
check("valid UTF-16LE and UTF-16BE", « 41 00 3d d8 00 de ».valid_encoding?(:utf16le) && « 00 41 d8 3d de 00 ».valid_encoding?(:utf16be))
check("invalid UTF-16 odd length", !« 41 00 42 ».valid_encoding?(:utf16le))
check("invalid UTF-16LE unpaired high surrogate", !« 3d d8 41 00 ».valid_encoding?(:utf16le))
check("invalid UTF-16LE unpaired low surrogate", !« 00 de 41 00 ».valid_encoding?(:utf16le))
check("valid UTF-32LE and UTF-32BE", « 00 f6 01 00 ».valid_encoding?(:utf32le) && « 00 01 f6 00 ».valid_encoding?(:utf32be))
check("invalid UTF-32 non-multiple of 4", !« 41 00 00 ».valid_encoding?(:utf32le))
check("invalid UTF-32LE surrogate", !« 00 d8 00 00 ».valid_encoding?(:utf32le))
check("invalid UTF-32BE out of range > U+10FFFF", !« 00 11 00 00 ».valid_encoding?(:utf32be))

# ---- ByteArray#transcode and #decode ----
orig = « 41 42 »
copy = orig.transcode(:utf8, :utf8)
copy[0] = 90
check("transcode returns a fresh ByteArray", orig[0] == 65 && copy[0] == 90)

latin1_bytes = « 63 61 66 e9 »
utf8_from_latin1 = latin1_bytes.transcode(:latin1, :utf8)
check("transcode latin1 -> utf8", utf8_from_latin1 == « 63 61 66 c3 a9 » && utf8_from_latin1.decode(:utf8) == "café")
check("transcode utf8 -> latin1", utf8_from_latin1.transcode(:utf8, :latin1) == latin1_bytes)

u16le = mixed.encode(:utf16le)
u16be = u16le.transcode(:utf16le, :utf16be)
u32le = u16be.transcode(:utf16be, :utf32le)
u32be = u32le.transcode(:utf32le, :utf32be)
back_utf8 = u32be.transcode(:utf32be, :utf8)
check("multi-hop transcode UTF-16LE -> UTF-16BE -> UTF-32LE -> UTF-32BE -> UTF-8", back_utf8 == mixed.encode(:utf8) && back_utf8.decode() == mixed)
check("ByteArray#decode with explicit encoding", u16le.decode(:utf16le) == mixed && latin1_bytes.decode(:latin1) == "café")

invalid_transcode_raises = false
begin
  « ff ».transcode(:utf8, :utf16le)
rescue e
  invalid_transcode_raises = true
check("transcode raises on invalid source bytes", invalid_transcode_raises)

# ---- UTF8-MAC (9) and CESU-8 (15) ----
u8mac = "é".encode("UTF8-MAC")
check("UTF8-MAC (id 9) decomposes to NFD and decodes back to NFC", u8mac.encoding_id == 9 && u8mac == « 65 cc 81 » && u8mac.decode() == "é")

cesu8 = U+1F600.to_s().encode("CESU-8")
check("CESU-8 (id 15) encodes astral as 6-byte surrogate pair", cesu8.encoding_id == 15 && cesu8 == « ed a0 bd ed b8 80 » && cesu8.valid_encoding? && cesu8.decode() == U+1F600.to_s())
check("CESU-8 rejects 4-byte UTF-8 and unpaired surrogates", !« f0 9f 98 80 ».valid_encoding?(:cesu8) && !« ed a0 bd 41 ».valid_encoding?(:cesu8))

# ---- Single-Byte Encodings (ISO-8859-*, Windows-125*, KOI8-*, IBM*, mac*) ----
w1252 = "€—café".encode(:windows_1252)
check("Windows-1252 / CP1252 (id 42) encode & decode", w1252.encoding_id == 42 && w1252.encoding == "Windows-1252" && w1252 == « 80 97 63 61 66 e9 » && w1252.decode() == "€—café")
check("Windows-1252 rejects undefined byte 0x81", !« 81 ».valid_encoding?(:cp1252))

iso15 = "€Œœ".encode(:iso_8859_15)
check("ISO-8859-15 / Latin-9 (id 35) encode & decode", iso15.encoding_id == 35 && iso15 == « a4 bc bd » && iso15.decode() == "€Œœ")

iso2 = "čšž".encode(:iso_8859_2)
check("ISO-8859-2 / Latin-2 (id 23) round-trip", iso2.encoding_id == 23 && iso2.decode() == "čšž")

w1251 = "Привет".encode(:cp1251)
koi8r = w1251.transcode(:koi8_r)
ibm866 = koi8r.transcode(:ibm866)
check("Cyrillic transcode Windows-1251 (41) -> KOI8-R (37) -> IBM866 (62) -> UTF-8", w1251.encoding_id == 41 && koi8r.encoding_id == 37 && ibm866.encoding_id == 62 && ibm866.decode() == "Привет")

mac_roman = "é©".encode(:mac_roman)
check("macRoman (id 71) round-trip", mac_roman.encoding_id == 71 && mac_roman == « 8e a9 » && mac_roman.decode() == "é©")

ibm437 = "é±".encode(:ibm437)
check("IBM437 / CP437 (id 46) round-trip", ibm437.encoding_id == 46 && ibm437 == « 82 f1 » && ibm437.decode() == "é±")

ibm037 = "AB0".encode(:ibm037)
check("IBM037 EBCDIC (id 78) round-trip", ibm037.encoding_id == 78 && ibm037 == « c1 c2 f0 » && ibm037.decode() == "AB0")

gb1988 = "A¥".encode(:gb1988)
check("GB1988 (id 65) maps ¥ to 0x24", gb1988.encoding_id == 65 && gb1988 == « 41 24 » && gb1988.decode() == "A¥")

check("Full 103 CRuby Encoding.list index alignment", ByteArray.normalize_encoding("Shift_JIS") == 39 && ByteArray.normalize_encoding("GB18030") == 20 && ByteArray.normalize_encoding("EUC-JP") == 10 && ByteArray.normalize_encoding("SJIS-SoftBank") == 102 && ByteArray.encoding_name(102) == "SJIS-SoftBank")

# ---- Algorithmic Encodings: UTF-7 (94), UTF-7-IMAP (103), MUTF-8 (104), x-user-defined (105), ISO-8859-8-I (29) ----
utf7 = ("A+B " + U+65E5.to_s() + U+1F600.to_s()).encode("UTF-7")
check("UTF-7 (id 94) encode & decode with +- and astral surrogates", utf7.encoding_id == 94 && utf7.valid_encoding? && utf7.decode() == "A+B " + U+65E5.to_s() + U+1F600.to_s())

utf7_imap = "A&B 日本".encode("UTF-7-IMAP")
check("UTF-7-IMAP (id 103) encode & decode", utf7_imap.encoding_id == 103 && utf7_imap.valid_encoding? && utf7_imap.decode() == "A&B 日本")

mutf8 = ("A" + U+0000.to_s() + U+1F600.to_s()).encode("MUTF-8")
check("MUTF-8 (id 104) encodes U+0000 as C0 80 and astral as 6-byte surrogates", mutf8.encoding_id == 104 && mutf8 == « 41 c0 80 ed a0 bd ed b8 80 » && mutf8.valid_encoding? && mutf8.decode() == "A" + U+0000.to_s() + U+1F600.to_s())
check("MUTF-8 rejects bare 0x00 byte", !« 41 00 ».valid_encoding?(:mutf8))

xud = ("A" + U+F780.to_s() + U+F7FF.to_s()).encode("x-user-defined")
check("x-user-defined (id 105) maps U+F780..U+F7FF <-> 0x80..0xFF", xud.encoding_id == 105 && xud == « 41 80 ff » && xud.decode() == "A" + U+F780.to_s() + U+F7FF.to_s())
check("ISO-8859-8-I alias maps to ISO-8859-8 (id 29)", ByteArray.normalize_encoding("ISO-8859-8-I") == 29)

# ---- Lazy-Loaded CJK Multi-Byte Encodings ----
sjis = "日本語ｱｲｳ".encode("Shift_JIS")
check("Shift_JIS (id 39) encode & decode (2-byte Kanji + 1-byte halfwidth Katakana)", sjis.encoding_id == 39 && sjis == « 93 fa 96 7b 8c ea b1 b2 b3 » && sjis.valid_encoding? && sjis.decode() == "日本語ｱｲｳ")

cp932 = "日本語①".encode("Windows-31J")
check("Windows-31J / CP932 (id 11) encode & decode", cp932.encoding_id == 11 && cp932.valid_encoding? && cp932.decode() == "日本語①")

euc_jp = sjis.transcode("EUC-JP")
check("Transcode Shift_JIS (39) -> EUC-JP (10)", euc_jp.encoding_id == 10 && euc_jp == « c6 fc cb dc b8 ec 8e b1 8e b2 8e b3 » && euc_jp.valid_encoding? && euc_jp.decode() == "日本語ｱｲｳ")

iso2022jp = "A日本B".encode("ISO-2022-JP")
check("ISO-2022-JP (id 85) 7-bit escape sequence encode & decode", iso2022jp.encoding_id == 85 && iso2022jp == « 41 1b 24 42 46 7c 4b 5c 1b 28 42 42 » && iso2022jp.valid_encoding? && iso2022jp.decode() == "A日本B")

gbk = "中文测试".encode("GBK")
gb2312 = gbk.transcode("GB2312")
check("GBK (id 21) and GB2312 (id 83) encode & decode", gbk.encoding_id == 21 && gb2312.encoding_id == 83 && gb2312 == « d6 d0 ce c4 b2 e2 ca d4 » && gb2312.decode() == "中文测试")

gb18030_str = "A中文é" + U+1F600.to_s()
gb18030 = gb18030_str.encode("GB18030")
check("GB18030 (id 20) 1-byte, 2-byte, 4-byte BMP, and 4-byte astral round-trip", gb18030.encoding_id == 20 && gb18030.valid_encoding? && gb18030.decode() == gb18030_str)

big5 = "繁體中文".encode("Big5")
cp950 = big5.transcode("CP950")
check("Big5 (id 12) and CP950 (id 76) round-trip", big5.encoding_id == 12 && cp950.encoding_id == 76 && cp950.valid_encoding? && cp950.decode() == "繁體中文")

euc_kr = "한국어".encode("EUC-KR")
cp949 = "믜한국어".encode("CP949")
check("EUC-KR (id 18) and CP949 (id 16) Korean Hangul round-trip", euc_kr.encoding_id == 18 && euc_kr.decode() == "한국어" && cp949.encoding_id == 16 && cp949.decode() == "믜한국어")

# ---- Remaining 10 CRuby Encodings (17, 19, 95..102) + HZ-GB-2312 (106), ISO-2022-KR (107), CP858 (108) ----
check("Emacs-Mule (id 17) & EUC-TW (id 19) ASCII transcode & multi-byte validation", "Hello".encode("Emacs-Mule").decode() == "Hello" && "Hello".encode("EUC-TW").decode() == "Hello" && « a1 a1 8e a2 a1 a1 ».valid_encoding?("EUC-TW") && !« 8e ff a1 a1 ».valid_encoding?("EUC-TW"))
check("Carrier UTF-8 variants (95 DoCoMo, 97 KDDI, 101 SoftBank) round-trip", "日本語".encode("UTF8-DoCoMo").decode() == "日本語" && "日本語".encode("UTF8-KDDI").decode() == "日本語" && "日本語".encode("UTF8-SoftBank").decode() == "日本語")
check("Carrier SJIS variants (96 DoCoMo, 98 KDDI, 102 SoftBank) round-trip", "日本語".encode("SJIS-DoCoMo").decode() == "日本語" && "日本語".encode("SJIS-KDDI").decode() == "日本語" && "日本語".encode("SJIS-SoftBank").decode() == "日本語")
check("Carrier ISO-2022-JP-KDDI (99, 100) round-trip", "A日本B".encode("ISO-2022-JP-KDDI").decode() == "A日本B" && "A日本B".encode("stateless-ISO-2022-JP-KDDI").decode() == "A日本B")

hz = "A~中文B".encode("HZ-GB-2312")
check("HZ-GB-2312 (id 106) 7-bit ~{...~} encode & decode", hz.encoding_id == 106 && hz == « 41 7e 7e 7e 7b 56 50 4e 44 7e 7d 42 » && hz.valid_encoding? && hz.decode() == "A~中文B")

iso2022kr = "A한국B".encode("ISO-2022-KR")
check("ISO-2022-KR (id 107) 7-bit ESC $)C SO/SI encode & decode", iso2022kr.encoding_id == 107 && iso2022kr.valid_encoding? && iso2022kr.decode() == "A한국B")

cp858 = "€é".encode("CP858")
check("CP858 (id 108) encodes € at 0xD5", cp858.encoding_id == 108 && cp858 == « d5 82 » && cp858.decode() == "€é")

# ---- Cross-Language Superset Encodings (109..128) ----
check("IBM1047 (109), IBM1140 (110), IBM500 (111), IBM273 (112) EBCDIC round-trip", "Hello!".encode("IBM1047").decode() == "Hello!" && "€100".encode("IBM1140").decode() == "€100" && "ABC".encode("IBM500").decode() == "ABC" && "ÄÖÜß".encode("IBM273").decode() == "ÄÖÜß")
check("IBM424 Hebrew (113), IBM875 Greek (114), IBM1026 Turkish (115) EBCDIC round-trip", "שלום".encode("IBM424").decode() == "שלום" && "Ωμέγα".encode("IBM875").decode() == "Ωμέγα" && "Şğ".encode("IBM1026").decode() == "Şğ")
check("CP720 Arabic (116), CP856 Hebrew (117), CP1006 Urdu (118), CP1125 Ukrainian (119) round-trip", "سلام".encode("CP720").decode() == "سلام" && "שלום".encode("CP856").decode() == "שלום" && "۰۱۲۳".encode("CP1006").decode() == "۰۱۲۳" && "ЇїЄєҐґ".encode("CP1125").decode() == "ЇїЄєҐґ")
check("KOI8-T (120), KZ-1048 (121), HP-Roman8 (122), PalmOS (126) round-trip", "Привет".encode("KOI8-T").decode() == "Привет" && "Қазақ".encode("KZ-1048").decode() == "Қазақ" && "café".encode("HP-Roman8").decode() == "café" && "€café".encode("PalmOS").decode() == "€café")
check("macArabic (123), macFarsi (124), macHebrew (125) round-trip", "سلام".encode("macArabic").decode() == "سلام" && "سلام".encode("macFarsi").decode() == "سلام" && "שלום".encode("macHebrew").decode() == "שלום")

johab = "믜한국어A".encode("Johab")
check("Johab / CP1361 (id 127) Korean round-trip", johab.encoding_id == 127 && johab.valid_encoding? && johab.decode() == "믜한국어A")

u8sig = "café".encode("UTF-8-SIG")
check("UTF-8-SIG / UTF-8-BOM (id 128) prepends EF BB BF on encode and strips BOM on decode", u8sig.encoding_id == 128 && u8sig == « ef bb bf 63 61 66 c3 a9 » && u8sig.decode() == "café")

# ---- Unicode Technical Standards & Algorithmic Encodings (129..133) ----
wtf8_str = "Aé" + U+1F600.to_s()
wtf8 = wtf8_str.encode("WTF-8")
check("WTF-8 (id 129) encodes valid UTF-8 and accepts unpaired surrogates", wtf8.encoding_id == 129 && wtf8.decode() == wtf8_str && « 41 ed a0 80 42 ».valid_encoding?("WTF-8") && !« 41 ed a0 bd ed b8 80 ».valid_encoding?("WTF-8"))
wtf8_surr_cps = ByteArray.encode_codepoints([65, 0xD800, 66], 129)
check("WTF-8 round-trips unpaired surrogate codepoints losslessly and replaces with U+FFFD on String#decode", wtf8_surr_cps == « 41 ed a0 80 42 » && wtf8_surr_cps.__decode_codepoints(129) == [65, 0xD800, 66] && wtf8_surr_cps.decode() == "A\uFFFDB")

scsu_str = "Hello café Москва 日本語 " + U+1F600.to_s()
scsu = scsu_str.encode("SCSU")
check("SCSU (UTS #6, id 130) compresses and round-trips ASCII, Latin, Cyrillic, CJK, and astral", scsu.encoding_id == 130 && scsu.valid_encoding? && scsu.decode() == scsu_str)

bocu_a = "alpha".encode("BOCU-1")
bocu_b = "beta".encode("BOCU-1")
bocu_mix = ("Hello café Москва 日本語 " + U+1F600.to_s()).encode("BOCU-1")
check("BOCU-1 (UTN #6, id 131) round-trips all scripts and preserves codepoint order", bocu_mix.encoding_id == 131 && bocu_mix.valid_encoding? && bocu_mix.decode() == ("Hello café Москва 日本語 " + U+1F600.to_s()) && (bocu_a <=> bocu_b) == -1)

utf_ebcdic_str = "Hello café 日本 " + U+1F600.to_s()
utf_ebcdic = utf_ebcdic_str.encode("UTF-EBCDIC")
check("UTF-EBCDIC (UTR #16, id 132) round-trips ASCII, Latin, CJK, and astral", utf_ebcdic.encoding_id == 132 && utf_ebcdic.valid_encoding? && utf_ebcdic.decode() == utf_ebcdic_str)

utf1_str = "Hello café 日本 " + U+1F600.to_s()
utf1 = utf1_str.encode("UTF-1")
check("UTF-1 (ISO 10646-1 Annex G, id 133) round-trips ASCII, Latin-1, BMP, and astral", utf1.encoding_id == 133 && utf1.valid_encoding? && utf1.decode() == utf1_str)

# ---- Telecom, Terminal & Domain-Specific Standards (134..137) ----
gsm = "Hello @£$¥ €[]{}\\~^| ΔΩ".encode("GSM-03.38")
check("GSM 03.38 (3GPP TS 23.038, id 134) SMS alphabet + 0x1B extension round-trip", gsm.encoding_id == 134 && gsm.valid_encoding? && gsm.decode() == "Hello @£$¥ €[]{}\\~^| ΔΩ")

dec_mcs = "café Œœ".encode("DEC-MCS")
check("DEC-MCS (VT220, id 135) round-trip", dec_mcs.encoding_id == 135 && dec_mcs.valid_encoding? && dec_mcs.decode() == "café Œœ")

nextstep = "café ﬁﬂ".encode("NeXTSTEP")
check("NeXTSTEP (id 136) round-trip", nextstep.encoding_id == 136 && nextstep.valid_encoding? && nextstep.decode() == "café ﬁﬂ")

ansel = "café Łøđ".encode("ANSEL")
check("ANSEL / MARC-8 / GEDCOM (id 137) pre-base combining diacritics round-trip", ansel.encoding_id == 137 && ansel.valid_encoding? && ansel.decode() == "café Łøđ" && ansel == « 63 61 66 e2 65 20 a1 b2 b3 »)

# ---- Regional Single-Byte Scripts (138..143) ----
viscii = "Tiếng Việt".encode("VISCII")
tcvn = "Tiếng Việt".encode("TCVN-5712")
check("VISCII (id 138) and TCVN-5712 (id 139) Vietnamese round-trip", viscii.encoding_id == 138 && viscii.decode() == "Tiếng Việt" && tcvn.encoding_id == 139 && tcvn.decode() == "Tiếng Việt")

iscii = "नमस्ते".encode("ISCII-91")
check("ISCII-91 (id 140) Devanagari round-trip", iscii.encoding_id == 140 && iscii.valid_encoding? && iscii.decode() == "नमस्ते")

geostd8 = "საქართველო".encode("GEOSTD8")
armscii8 = "Հայաստան".encode("ARMSCII-8")
koi8ru = "Привіт".encode("KOI8-RU")
check("GEOSTD8 (141), ARMSCII-8 (142), KOI8-RU (143) + MACCENTRALEUROPE/MACICELAND aliases", geostd8.encoding_id == 141 && geostd8.decode() == "საქართველო" && armscii8.encoding_id == 142 && armscii8.decode() == "Հայաստան" && koi8ru.encoding_id == 143 && koi8ru.decode() == "Привіт" && ByteArray.normalize_encoding("MACCENTRALEUROPE") == 66 && ByteArray.normalize_encoding("MACICELAND") == 70)

# ---- National IBM EBCDIC + Euro (IBM114x) Code Pages + ISO-2022-CN (144..164) ----
check("National EBCDIC + Euro code pages (144..159) round-trip", "ÆØÅ".encode("IBM277").decode() == "ÆØÅ" && "€ÆØÅ".encode("IBM1142").decode() == "€ÆØÅ" && "ÄÖÅ".encode("IBM278").decode() == "ÄÖÅ" && "€ÄÖÅ".encode("IBM1143").decode() == "€ÄÖÅ" && "€àèé".encode("IBM1144").decode() == "€àèé" && "€ñÑ".encode("IBM1145").decode() == "€ñÑ" && "€£".encode("IBM1146").decode() == "€£" && "€çé".encode("IBM1147").decode() == "€çé" && "€ÄÖÜß".encode("IBM1141").decode() == "€ÄÖÜß" && "€ABC".encode("IBM1148").decode() == "€ABC" && "€ÞÐ".encode("IBM1149").decode() == "€ÞÐ")
check("IBM870 Latin-2 (160), IBM1025 Cyrillic (161), IBM420 Arabic (162), IBM838 Thai (163) EBCDIC round-trip", "čšž".encode("IBM870").decode() == "čšž" && "Привет".encode("IBM1025").decode() == "Привет" && "٠١٢٣".encode("IBM420").decode() == "٠١٢٣" && "ไทย".encode("IBM838").decode() == "ไทย")

iso2022cn = "A中文B".encode("ISO-2022-CN")
check("ISO-2022-CN (RFC 1922, id 164) 7-bit escape sequence encode & decode", iso2022cn.encoding_id == 164 && iso2022cn.valid_encoding? && iso2022cn.decode() == "A中文B")

# ---- ByteArray#scrub ----
bad_utf8 = « 41 ff 42 ».force_encoding(:utf8)
scrubbed_utf8 = bad_utf8.scrub()
check("ByteArray#scrub replaces invalid UTF-8 byte with U+FFFD", scrubbed_utf8.valid_encoding? && scrubbed_utf8.decode() == "A\uFFFDB" && bad_utf8.scrub("?").decode() == "A?B")

# ---- Chunked / Streaming Encoding & Decoding (StreamDecoder & StreamEncoder) ----
dec = ByteArray.stream_decoder(:utf8)
# Split 4-byte emoji U+1F600 (F0 9F 98 80) and 2-byte é (C3 A9) across chunk boundaries
part1 = dec.write(« 41 c3 »)
part2 = dec.write(« a9 f0 9f »)
part3 = dec.write(« 98 80 42 »)
part4 = dec.finish()
check("StreamDecoder buffers incomplete multi-byte UTF-8 across chunks", part1 == "A" && part2 == "é" && part3 == U+1F600.to_s() + "B" && part4 == "")

enc_stream = String.stream_encoder(:utf16)
c1 = enc_stream.write("AB")
c2 = enc_stream.write("CD")
check("StreamEncoder(:utf16) emits FE FF BOM only on the first chunk", c1 == « fe ff 00 41 00 42 » && c2 == « 00 43 00 44 »)

dec16 = ByteArray.stream_decoder(:utf16)
d1 = dec16.write(« fe »)
d2 = dec16.write(« ff 00 »)
d3 = dec16.write(« 41 00 42 »)
check("StreamDecoder(:utf16) handles split BOM and split 16-bit code units", d1 == "" && d2 == "" && d3 == "AB" && dec16.finish() == "")

<< "ALL PASS byte_array_encoding_spec ([passed.load()] checks)"

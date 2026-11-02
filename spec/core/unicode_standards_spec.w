# Unicode Standards (UAX #9, #11, #14, #15, #24, #29, #31, #38, #44, UTS #39, #51)
# and multi-version Unicode (1.1.0..17.0.0) conformance spec.
#
# Run:
#   bin/tungsten spec/core/unicode_standards_spec.w
#   bin/tungsten run --interpret spec/core/unicode_standards_spec.w
#   bin/tungsten --ruby spec/core/unicode_standards_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()

# ---- Unicode Version Configuration & Repertoire Validation (1.1.0..17.0.0) ----
check("default Unicode.version is 16.0.0", Unicode.version() == "16.0.0")
check("Unicode.normalize_version accepts 1.1, 3.2.0, 15.1, 16.0.0, 17.0", Unicode.normalize_version("1.1") == "1.1.0" && Unicode.normalize_version("3.2") == "3.2.0" && Unicode.normalize_version("15.1") == "15.1.0" && Unicode.normalize_version("16.0") == "16.0.0")

# U+0041 'A' (1.1), U+20AC '€' (2.1), U+1F600 '😀' (6.1), U+1FAF8 '🫸' (15.0)
euro = "€"
grin = U+1F600.to_s()
push_hand = U+1FAF8.to_s()

check("Codepoint#age reports version introduced", U+0041.age() == "1.1" && U+20AC.age() == "2.1" && U+1F600.age() == "6.1" && U+1FAF8.age() == "15.0")
check("Codepoint#assigned? respects target Unicode version", U+20AC.assigned?("2.0.0") == false && U+20AC.assigned?("2.1.0") == true && U+1F600.assigned?("6.0.0") == false && U+1F600.assigned?("6.1.0") == true)
check("String#valid_unicode? checks version repertoire", euro.valid_unicode?("2.0.0") == false && euro.valid_unicode?("2.1.0") == true && grin.valid_unicode?("6.0.0") == false && grin.valid_unicode?("6.1.0") == true && push_hand.valid_unicode?("14.0.0") == false && push_hand.valid_unicode?("15.0.0") == true)

verify_raised = false
begin
  grin.verify_unicode!("6.0.0")
rescue e
  verify_raised = true
check("String#verify_unicode! raises on codepoint unassigned in target version", verify_raised && grin.verify_unicode!("6.1.0") == grin)

Unicode.set_version("3.2.0")
check("Unicode.set_version sets active default version for valid_unicode?", Unicode.version() == "3.2.0" && euro.valid_unicode?() == true && grin.valid_unicode?() == false)
Unicode.set_version("16.0.0")

# ---- Multi-Version UAX #15 Normalization & Historical Corrigenda ----
# Corrigendum #4 (Five CJK Compatibility Ideographs in Unicode 3.2.0 / 4.0.0):
# U+2F868 canonically decomposed to U+2136A in Unicode 3.2.0, corrected to U+36FC in 4.1.0+
cjk_compat = U+2F868.to_s()
check("UAX #15 Corrigendum #4: U+2F868 normalizes to U+2136A in 3.2.0 and U+36FC in 4.1.0+", cjk_compat.nfc("3.2.0") == U+2136A.to_s() && cjk_compat.nfc("4.1.0") == U+36FC.to_s() && cjk_compat.nfc("16.0.0") == U+36FC.to_s())

# PR-29 (Public Review Issue #29, fixed in Unicode 4.1.0):
# Sequence U+0B47 (ORIYA VOWEL SIGN E) + U+0300 (COMBINING GRAVE) + U+0B3E (ORIYA VOWEL SIGN AA)
# In 3.2.0..4.0.0, U+0B47 and U+0B3E erroneously composed across U+0300 (both ccc=0 -> last_cc != cc was false, wait: U+0300 has ccc=230 and U+0B3E has ccc=0, so last_cc=230 != 0 allowed composition to U+0B4B + U+0300!).
# In 4.1.0+, last_cc < cc (230 < 0 is false) prevents composition across U+0300.
pr29_seq = U+0B47.to_s() + U+0300.to_s() + U+0B3E.to_s()
check("UAX #15 PR-29: U+0B47 U+0300 U+0B3E composes in 3.2.0 and stays uncomposed in 4.1.0+", pr29_seq.nfc("3.2.0") == (U+0B4B.to_s() + U+0300.to_s()) && pr29_seq.nfc("4.1.0") == pr29_seq)

# Hangul syllables (U+AC00..U+D7A3) were introduced in Unicode 2.0.0
check("String#canonicalize verifies version repertoire and returns NFC", ("e" + U+0301.to_s()).canonicalize("3.2.0") == "é")

# UAX #15 §13 Stream-Safe Text Format (inserts U+034F CGJ after 30 non-starters)
many_marks = "a" + (U+0301.to_s() * 35)
ss = many_marks.stream_safe()
check("UAX #15 Stream-Safe Text Format inserts U+034F CGJ when non-starters exceed 30", ss.include?(U+034F.to_s()) && ss.nfc() != many_marks.nfc())

# UAX #15 / UAX #44 NFKC_Casefold
check("String#nfkc_casefold folds case and compatibility decompositions", "ﬁAß".nfkc_casefold() == "fiass")

# ---- Unicode Standard §3.13 Full Case Mapping & D144-D147 Caseless Matching ----
check("Unicode.upcase / titlecase / casefold full mappings", Unicode.upcase("straße ﬁ") == "STRASSE FI" && Unicode.titlecase("straße") == "Straße" && "Straße".casefold() == "strasse")
check("D144 Default Caseless Matching", "Straße".caseless_equal?("STRASSE") && "Straße".caseless_equal?("strasse", :default))
check("D145 Canonical Caseless Matching", ("e" + U+0301.to_s()).caseless_equal?("É", :canonical))
check("D146 Compatibility Caseless Matching", "ﬁ".caseless_equal?("FI", :compatibility))
check("D147 Identifier Caseless Matching", "ﬁ".caseless_equal?("FI", :identifier))

# ---- UAX #11 East Asian Width & Display Width ----
check("UAX #11 East Asian Width on Codepoint and String", U+0041.ea() == "Na" && U+65E5.ea() == "W" && U+FF61.ea() == "H" && U+00A1.ea() == "A")
check("UAX #11 display_width handles ASCII, combining marks, CJK wide, and emoji", "hello".display_width() == 5 && ("e" + U+0301.to_s()).display_width() == 1 && "日本語".display_width() == 6 && U+1F600.to_s().display_width() == 2)

# ---- UAX #9 Bidirectional Algorithm (Bidi) & Trojan Source Safety ----
check("UAX #9 bidi_class, bidi_mirrored?, bidi_mirror, bidi_control?", U+0041.bc() == "L" && U+05D0.bc() == "R" && U+0627.bc() == "AL" && U+0028.bidi_mirrored?() && U+0028.bidi_mirror() == U+0029 && U+202E.bidi_control?())
check("UAX #9 bidi_direction detects LTR, RTL, and neutral", "Hello".bidi_direction() == :ltr && "שלום".bidi_direction() == :rtl && "123".bidi_direction() == :neutral)
check("UAX #9 / UTS #39 bidi_safe? detects unbalanced Bidi overrides", "normal text".bidi_safe?() && !(U+202E.to_s() + "unbalanced").bidi_safe?() && (U+202E.to_s() + "balanced" + U+202C.to_s()).bidi_safe?())

# ---- UAX #24 Script Property & UTS #39 Security Mechanisms ----
check("UAX #24 Script property on Codepoint and String", U+0041.sc() == "Latin" && U+0410.sc() == "Cyrillic" && U+0391.sc() == "Greek" && U+65E5.sc() == "Han" && U+3042.sc() == "Hiragana" && "AБ".scripts() == ["Latin", "Cyrillic"])
check("UTS #39 mixed_script? flags Latin+Cyrillic but allows Japanese Han+Hiragana+Katakana", "pаypal".mixed_script?() && !"日本語テストABC".mixed_script?() && !"pure_latin_123".mixed_script?())
check("UTS #39 confusable? and confusable_skeleton detect Cyrillic/Greek homographs", "pаypal".confusable?("paypal") && "scope".confusable?("ѕсоре") && !"apple".confusable?("orange"))

# ---- UAX #29 Text Segmentation (Graphemes across versions, Words, Sentences) ----
# Devanagari conjunct क्ता (U+0915 + U+094D Virama + U+0924 + U+093E):
# GB9c in Unicode 15.1+ keeps it as 1 grapheme cluster; pre-15.1 splits after Virama into 2 clusters.
conjunct = U+0915.to_s() + U+094D.to_s() + U+0924.to_s() + U+093E.to_s()
check("UAX #29 GB9c versioned graphemes: 1 cluster in 15.1.0+ vs 2 clusters in 15.0.0", conjunct.graphemes("15.1.0").size() == 1 && conjunct.graphemes("15.0.0").size() == 2)
check("UAX #29 words segmentation", "Don't stop! 3.14 is π.".words() == ["Don't", "stop", "3.14", "is", "π"])
check("UAX #29 sentences segmentation", "Hello world! How are you? Fine.".sentences().size() == 3)

# ---- UAX #14 Line Breaking ----
check("UAX #14 line_breaks", "Hello world\nNext-line".line_breaks() == ["Hello ", "world\n", "Next-", "line"])

# ---- UAX #31 Identifier & Pattern Syntax, UAX #38 Unihan, UTS #51 Emoji ----
check("UAX #31 valid_identifier?, pattern_syntax?, pattern_white_space?", "valid_id_1".valid_identifier?() && "αβγ".valid_identifier?() && !"123bad".valid_identifier?() && !"a+b".valid_identifier?() && U+002B.pattern_syntax?() && U+0020.pattern_white_space?())
check("UAX #38 ideographic? and UTS #51 Emoji properties", U+65E5.ideographic?() && !U+0041.ideographic?() && U+1F600.emoji?() && U+1F600.emoji_presentation?() && U+1F600.extended_pictographic?() && U+1F3FB.emoji_modifier?() && U+1F44B.emoji_modifier_base?())
check("Grapheme#emoji? and Grapheme#display_width", Grapheme.new(U+1F600.to_s()).emoji?() && Grapheme.new(U+1F600.to_s()).display_width() == 2 && !Grapheme.new("A").emoji?())

<< "ALL PASS unicode_standards_spec ([passed.load()] checks)"

# spec: compiled -- native CoreText font-file shaping
use ../lib/av
fonts = [
  ["cuneiform", "/System/Library/Fonts/Supplemental/NotoSansCuneiform-Regular.ttf", "𒀀𒀁"],
  ["hieroglyphs", "/System/Library/Fonts/Supplemental/NotoSansEgyptianHieroglyphs-Regular.ttf", "𓀀𓀁"],
  ["Hebrew combining", "/System/Library/Fonts/Supplemental/Arial.ttf", "אְב"]
]
if argv().size > 0
  fonts.push(["Avestan", argv()[0] + "/NotoSansAvestan-Regular.ttf", "𐬀𐬁"])
  fonts.push(["Old Persian", argv()[0] + "/NotoSansOldPersian-Regular.ttf", "𐎠𐎡"])
fonts.each ->(entry)
  if File.file?(entry[1])
    shaped = Av:Text.shape(entry[2], entry[1], 48)
    raise "missing outlines for [entry[0]]" if shaped["paths"].size < 1 || shaped["advance"] <= 0
    << "PASS exact-font native [entry[0]] outlines"

# Strings: UTF-8 byte size vs chars vs graphemes, unicode case mapping.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "size.utf8 [("éx").size]"
<< "chars.utf8 [("éx").chars.size]"
<< "graphemes [("éx").graphemes.size]"
<< "unicode.up [("straße").upcase]"
<< "emoji.size [("👍").size]"
<< "emoji.chars [("👍x").chars.size]"
<< "reverse.utf8 [("héllo").reverse]"
<< "idx.utf8 [("héllo")[1]]"
<< "greek [("αβγ").upcase]"
<< "cjk.size [("日本").size] [("日本").chars.size]"

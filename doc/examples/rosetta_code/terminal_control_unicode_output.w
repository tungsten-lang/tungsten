utf8 = ENV.at("LANG", "LC_ALL", "LC_CTYPE").compact.first.include?("UTF-8")

if utf8
  << "This terminal supports UTF-8 [U+2618]"
else
  <! "This terminal does not support UTF-8"

## expect skip environment-dependent example

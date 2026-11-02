# Explicit grouping permits operations on a ternary's value.
name = "en"
<< (name ? "." + name : "") + ".srt"
<< (true ? [3, 5] : [7])[1]
<< (false ? "wrong" : "right").upcase
<< (true ? 4 : 8) * 3
# A following negative statement stays separate from a bare loop.
i = 0
while i < 1
  i += 1
-1
<< i

# A suffix condition controls the whole assignment, including the ternary.
a = {"codec": "pcm"}
a["codec"] = false ? "aac" : "none" if !a.has_key?("codec")
<< a["codec"]
x = "kept"
x = true ? "changed" : "other" if false
<< x
<< (false ? "a" : "b") if true

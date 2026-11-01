use ../../bits/tungsten-bit/lib/bitfile

-> check(name, ok)
  raise "FAIL [name]" if !ok
  << "PASS [name]"

-> rejected(text)
  begin
    Tungsten:Bit:Bitfile.parse(text, "fixture/Bitfile", ["av"])
  rescue error
    return error.to_s.include?("fixture/Bitfile") || error.to_s.include?("line ")
  false

text = [
  "name \"fixture\"",
  "version \"1.2.3\"",
  "source \"https://example.test\", trusted: true",
  "group :test",
  "bit \"demo\", \"~> 2\", path: \"../demo\"",
  "end",
  "asset \"native\"",
  "av.project \"film\", source: \"input.mov\"",
  "av.video \"master\",",
  "  codec: :h264, rate: \[30000, 1001], data: {nested: \[true, nil, -2.5e-3]}, # note",
  "  title: \"א #𓀀\"",
  "other.job \"preview\", enabled: false"
].join("\n")
manifest = Tungsten:Bit:Bitfile.parse(text, "/project/Bitfile", ["av", "other"])
check("shared package metadata", manifest.name == "fixture" && manifest.version == "1.2.3")
check("source policy", manifest.source_policy().trusted)
check("package groups and paths", manifest.dependencies[0].options[:groups] == ["test"] && manifest.dependencies[0].path == "/project/../demo")
check("package assets", manifest.assets == ["native"])
check("namespace selection", manifest.directives.size == 3 && manifest.directives[2].namespace == "other")
check("directive location", manifest.directives[1].name == "video" && manifest.directives[1].line == 9)
video = manifest.directives[1]
check("multiline literals", video.arguments == ["master"] && video.options["rate"] == [30000, 1001])
check("nested values", video.options["data"]["nested"] == [true, nil, ~-0.0025])
check("unicode and quoted comments", video.options["title"] == "א #𓀀")
legacy = Tungsten:Bit:Bitfile.parse(text, "/project/Bitfile")
check("legacy parser compatibility", legacy.directives.size == 0 && legacy.name == "fixture" && legacy.dependencies.size == 1)
parsed = Tungsten:Bit:Bitfile.literal_arguments("\"line\\nquote\\\"\\\\end\", unicode: \"\\u05d0\\uD80C\\uDC00\"")
check("escaped strings", parsed[0][0] == "line\nquote\"\\end")
check("unicode escapes", parsed[1]["unicode"] == "א𓀀")
check("shared quoted reader compatibility", Tungsten:Bit:Bitfile.new().quoted("\"keep\\nregex\"") == "keep\\nregex")
check("reject executable calls", rejected("av.project Process.exec(\[\"touch\", \"unwanted\"])"))
check("reject duplicate options", rejected("av.project \"x\", source: \"a\", source: \"b\""))
check("reject duplicate nested keys", rejected("av.project \"x\", data: {x: 1, x: 2}"))
check("reject nonfinite numbers", rejected("av.project \"x\", value: 1e999"))
check("reject mismatched delimiters", rejected("av.project \"x\", data: \[1}"))
check("reject unterminated strings", rejected("av.project \"x"))
check("reject invalid Unicode", rejected("av.project \"\\uD800\""))
check("literal nesting bound", rejected("av.project \"x\", data: " + "\[" * 20 + "0" + "]" * 20))
tabs = Tungsten:Bit:Bitfile.parse("av.project\t\"a\tb\"", "fixture/Bitfile", ["av"])
check("tab separator preserves literal tabs", tabs.directives[0].arguments == ["a\tb"])

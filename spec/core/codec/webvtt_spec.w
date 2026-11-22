# WebVTT and SubRip captions (core/codec/text/webvtt): the file parser
# (signature, cue timings and settings, regions, out-of-order cues), the cue
# text parser (tags, classes, voice annotations, entities, timestamps), SRT
# and the active-cue query.
#
#   bin/tungsten spec/core/codec/webvtt_spec.w
#   bin/tungsten run --interpret spec/core/codec/webvtt_spec.w

use core/codec/text/webvtt
use support

NL = "\n"
VTT = "WEBVTT - demo" + NL + NL +
  "REGION" + NL + "id:fred width:40% lines:3 regionanchor:0%,100% viewportanchor:10%,90% scroll:up" + NL + NL +
  "intro" + NL + "00:00:01.000 --> 00:00:04.500 line:10% align:start position:20%,line-left size:50%" + NL + "<v Roger Bingham>We are in New York City" + NL + NL +
  "00:00.500 --> 00:02.000 region:fred" + NL + "<c.loud.red>Hi</c> &amp; <i>bye</i> <00:00:01.000>later" + NL + NL +
  "01:00:00.000 --> 01:00:01.250" + NL + "Line one" + NL + "Line two" + NL

tr = vtt_parse(VTT)
check("ok", tr.ok, true)
check("cue count", tr.cues.size, 3)
check("sorted by start", tr.cues.map(->(c) c.start.to_s).join(" "), "0.5 1 3600")
c0 = tr.cues[0]
c1 = tr.cues[1]
c2 = tr.cues[2]
check("cue id", c1.id, "intro")
check("cue end", c1.end, ~4.5)
check("line", c1.line, ~10.0)
check("align", c1.align, :start)
check("position", c1.position, ~20.0)
check("position align", c1.position_align, :line_left)
check("size", c1.size, ~50.0)
check("voice", c1.nodes.children[0].kind, :v)
check("voice annotation", c1.nodes.children[0].annotation, "Roger Bingham")
check("plain text", c1.plain_text, "We are in New York City")
check("region", c0.region.id, "fred")
check("region width", c0.region.width, ~40.0)
check("region lines", c0.region.lines, 3)
check("classes", c0.nodes.children[0].classes.join("."), "loud.red")
check("entities and tags", c0.plain_text, "Hi & bye later")
check("timestamp node", c0.nodes.children.map(->(n) n.kind.to_s).join(" "), "c text i text timestamp text")
check("multi-line text", c2.text, "Line one" + NL + "Line two")
check("active at 1.2", vtt_active(tr, ~1.2).size, 2)
check("active at 5", vtt_active(tr, ~5.0).size, 0)
check("format time", vtt_format_time(~3661.5), "01:01:01.500")
check("bad signature", vtt_parse("WEBVTX" + NL).ok, false)

SRT = "1" + NL + "00:00:01,000 --> 00:00:02,500" + NL + "<b>Bold</b> line" + NL + NL +
  "2" + NL + "00:00:03,000 --> 00:00:04,000" + NL + "Second" + NL
st = vtt_srt_parse(SRT)
check("srt cues", st.cues.size, 2)
check("srt timing", st.cues[0].start.to_s + " " + st.cues[0].end.to_s, "1 2.5")
check("srt text", st.cues[0].plain_text, "Bold line")
codec_done

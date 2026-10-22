# Timecode and Flicks (core/media/timecode.w): rates as [num, den], SMPTE ST
# 12-1 labels (non-drop and drop-frame, both directions), audio samples per
# frame span, and flicks with the round-half-up snapping rule.
#
# Run:
#   bin/tungsten spec/core/timecode_spec.w
#   bin/tungsten run --interpret spec/core/timecode_spec.w

passed = 0

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> raises?(f)
  begin
    f.call
  rescue e
    return true
  false

ntsc = [30000, 1001]
ntsc60 = [60000, 1001]
film = [24000, 1001]

# ---- rates ----
check("rate from a pair", Timecode.rate([24, 1]) == [24, 1])
check("rate from an Integer", Timecode.rate(25) == [25, 1])
check("rate from a string", Timecode.rate("24000/1001") == [24000, 1001])
check("rate is reduced", Timecode.rate([48000, 2002]) == [24000, 1001])
check("rate rejects zero", raises?(->() Timecode.rate([0, 1])))
check("quanta 23.976 -> 24", Timecode.quanta(film) == 24)
check("quanta 29.97 -> 30", Timecode.quanta(ntsc) == 30)
check("quanta 59.94 -> 60", Timecode.quanta(ntsc60) == 60)
check("quanta 25", Timecode.quanta([25, 1]) == 25)
check("drop-frame at 29.97 and 59.94", Timecode.drop_frame?(ntsc) && Timecode.drop_frame?(ntsc60))
check("non-drop at 23.976, 24, 25, 30", !Timecode.drop_frame?(film) && !Timecode.drop_frame?([24, 1]) && !Timecode.drop_frame?([25, 1]) && !Timecode.drop_frame?([30, 1]))

# ---- non-drop labels ----
check("frame 0", Timecode.to_smpte(0, [24, 1]) == "00:00:00:00")
check("frame 23 at 24", Timecode.to_smpte(23, [24, 1]) == "00:00:00:23")
check("frame 24 at 24", Timecode.to_smpte(24, [24, 1]) == "00:00:01:00")
check("one hour at 24", Timecode.to_smpte(86400, [24, 1]) == "01:00:00:00")
check("the Archimedes master ends at 00:38:53:09", Timecode.to_smpte(56001, [24, 1]) == "00:38:53:09")
check("23.976 counts 24 labels a second", Timecode.to_smpte(86400, film) == "01:00:00:00")
check("25 fps", Timecode.to_smpte(90000, [25, 1]) == "01:00:00:00")
check("labels wrap at 24 hours", Timecode.to_smpte(24 * 86400, [24, 1]) == "00:00:00:00")
check("parse non-drop", Timecode.parse("01:00:00:00", [24, 1]) == 86400)
check("parse 00:38:53:09", Timecode.parse("00:38:53:09", [24, 1]) == 56001)
check("parse rejects frame 24 at 24 fps", raises?(->() Timecode.parse("00:00:00:24", [24, 1])))
check("parse rejects a malformed label", raises?(->() Timecode.parse("0:00:00:00", [24, 1])))
check("negative frames raise", raises?(->() Timecode.to_smpte(0 - 1, [24, 1])))

# ---- drop-frame (29.97: labels 00 and 01 skipped each minute but every tenth) ----
check("29.97 frame 1799", Timecode.to_smpte(1799, ntsc) == "00:00:59;29")
check("29.97 frame 1800 is ;02", Timecode.to_smpte(1800, ntsc) == "00:01:00;02")
check("29.97 frame 17981", Timecode.to_smpte(17981, ntsc) == "00:09:59;29")
check("29.97 frame 17982 is 00:10:00;00", Timecode.to_smpte(17982, ntsc) == "00:10:00;00")
check("29.97 one hour is 107892 frames", Timecode.to_smpte(107892, ntsc) == "01:00:00;00")
check("29.97 non-drop when asked", Timecode.to_smpte(1800, ntsc, false) == "00:01:00:00")
check("parse ;02 after the first minute", Timecode.parse("00:01:00;02", ntsc) == 1800)
check("parse 01:00:00;00", Timecode.parse("01:00:00;00", ntsc) == 107892)
check("parse rejects a dropped label", raises?(->() Timecode.parse("00:01:00;00", ntsc)))
check("parse keeps minute 10's ;00", Timecode.parse("00:10:00;00", ntsc) == 17982)
check("59.94 drops four labels", Timecode.to_smpte(3600, ntsc60) == "00:01:00;04")
check("59.94 one hour is 215784 frames", Timecode.to_smpte(215784, ntsc60) == "01:00:00;00")
check("parse 59.94", Timecode.parse("01:00:00;00", ntsc60) == 215784)

# Round trips: the frames around every minute boundary for three hours, and a
# coarse sweep between them.
-> round_trip?(rate, drop)
  q = Timecode.quanta(rate)
  k = Timecode.dropped_per_minute(rate, drop)
  m = 0
  while m <= 180
    start = m * (q * 60 - k) + (m / 10) * k
    d = 0 - 2
    while d <= 2
      f = start + d
      if f >= 0
        s = Timecode.to_smpte(f, rate, drop)
        if Timecode.parse(s, rate) != f
          << "round trip broke at frame [f]: [s]"
          return false
      d += 1
    m += 1
  f = 0
  while f < q * 3600 * 3
    if Timecode.parse(Timecode.to_smpte(f, rate, drop), rate) != f
      << "round trip broke at frame [f]"
      return false
    f += 997
  true

check("29.97 drop-frame round trip", round_trip?(ntsc, true))
check("59.94 drop-frame round trip", round_trip?(ntsc60, true))
check("24 non-drop round trip", round_trip?([24, 1], false))
check("25 non-drop round trip", round_trip?([25, 1], false))
check("drop-frame labels are consecutive", Timecode.to_smpte(1801, ntsc) == "00:01:00;03" && Timecode.to_smpte(35963, ntsc) == "00:19:59;29" && Timecode.to_smpte(35964, ntsc) == "00:20:00;00")

# ---- audio samples per frame span ----
check("24 fps: 2000 samples a frame", Timecode.samples(1, [24, 1]) == 2000)
check("23.976: 2002 samples a frame", Timecode.samples(1, film) == 2002)
check("25 fps: 1920", Timecode.samples(1, [25, 1]) == 1920)
check("29.97: 5 frames are 8008 samples", Timecode.samples(5, ntsc) == 8008)
check("29.97: 1 frame rounds 1601.6 to 1602", Timecode.samples(1, ntsc) == 1602)
check("the Archimedes master: 56002 frames are 112004000 samples", Timecode.samples(56002, [24, 1]) == 112004000)
check("44.1 kHz", Timecode.samples(24, [24, 1], 44100) == 44100)
check("frame of a sample", Timecode.frame_of_sample(2001, [24, 1]) == 1 && Timecode.frame_of_sample(1999, [24, 1]) == 0)

# ---- flicks ----
check("flicks per second", Flicks.per_second == 705600000)
check("24 fps frame", Flicks.per_frame([24, 1]) == 29400000)
check("23.976 frame", Flicks.per_frame(film) == 29429400)
check("29.97 frame", Flicks.per_frame(ntsc) == 23543520)
check("59.94 frame", Flicks.per_frame(ntsc60) == 11771760)
check("25 fps frame", Flicks.per_frame([25, 1]) == 28224000)
check("48 kHz sample", Flicks.per_sample(48000) == 14700)
check("44.1 kHz sample", Flicks.per_sample(44100) == 16000)
check("10 ms", Flicks.from_ms(10) == 7056000 && Flicks.from_ms(10) == Flicks.from_sample(480))
check("a rate that is not whole flicks raises", raises?(->() Flicks.per_frame([11, 1])))
check("74.334 s snaps to frame 1784", Flicks.to_frame(Flicks.from_ms(74334), [24, 1]) == 1784)
check("half a frame rounds up", Flicks.to_frame(14700000, [24, 1]) == 1)
check("just under half rounds down", Flicks.to_frame(14699999, [24, 1]) == 0)
check("negative half rounds up to 0", Flicks.to_frame(0 - 14700000, [24, 1]) == 0)
check("negative past half goes to -1", Flicks.to_frame(0 - 14700001, [24, 1]) == 0 - 1)
check("frame -> flicks -> frame", Flicks.to_frame(Flicks.from_frame(56001, film), film) == 56001)
check("frame -> flicks -> sample at 23.976", Flicks.to_sample(Flicks.from_frame(1, film)) == 2002)
check("flicks -> ms", Flicks.to_ms(Flicks.from_ms(2333416)) == 2333416)
check("a 39-minute film in flicks fits i64 arithmetic", Flicks.to_frame(Flicks.from_frame(56002, ntsc60), ntsc60) == 56002)

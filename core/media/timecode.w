# Timecode and Flicks — integer time for video: frame rates as [num, den],
# SMPTE ST 12-1 timecode as a presentation of the frame index, and flicks
# (1/705,600,000 s) as the exact common clock for frames and samples.
#
#   rate = Timecode.rate("30000/1001")          # [30000, 1001]
#   Timecode.to_smpte(17982, rate)              # "00:10:00;00" (drop-frame)
#   Timecode.parse("00:10:00;00", rate)         # 17982
#   Timecode.to_smpte(86400, [24, 1])           # "01:00:00:00"
#   Timecode.samples(240, [24000, 1001])        # 480480 (48 kHz audio for 240 frames)
#   Flicks.per_frame([24000, 1001])             # 29429400
#   Flicks.to_frame(Flicks.from_ms(74334), [24, 1])   # 1784 (round half up)
#
# Rates. A rate is a reduced [num, den] pair of frames per second: [24, 1],
# [24000, 1001], [25, 1], [30000, 1001], [50, 1], [60000, 1001]. Timecode.rate
# accepts that pair, an Integer, or a "num/den" String. A frame f starts at
# f x den / num seconds exactly.
#
# Timecode (SMPTE ST 12-1). The nominal frame count per timecode second is the
# rate rounded: 24, 25, 30, 50, 60 ("quanta"). Integer rates and 24000/1001
# count non-drop: HH:MM:SS:FF. 30000/1001 and 60000/1001 count drop-frame by
# default: frame labels 00 and 01 (00-03 at 60000/1001) are skipped at the
# start of every minute except minutes 00, 10, 20, 30, 40 and 50, so the
# label stays within 3.6 ms of wall-clock time per hour; the separator before
# the frames field is ";". Labels wrap at 24 hours, as a tmcd track's
# 24-hour flag says.
#
# Flicks. 705,600,000 per second divides evenly by every common frame and
# audio rate: 24 fps = 29,400,000 per frame, 24000/1001 = 29,429,400,
# 30000/1001 = 23,543,520, 48 kHz = 14,700 per sample, 44.1 kHz = 16,000;
# 10 ms = 7,056,000. Conversions back to frames or samples round half up
# (studio TIMELINE.md section 2): the nearest frame, ties to the later one.

+ Timecode
  # [num, den] reduced, from [num, den], an Integer, or "num/den" / "num".
  -> .rate(r)
    num = 0
    den = 1
    if r.is_a?(Array)
      if r.size != 2
        raise ArgumentError, "rate must be [num, den], got [r]"
      num = r[0].to_i
      den = r[1].to_i
    elsif r.is_a?(Integer)
      num = r
    elsif r.is_a?(String)
      parts = r.split("/")
      if parts.size == 1
        num = parts[0].to_i
      elsif parts.size == 2
        num = parts[0].to_i
        den = parts[1].to_i
      else
        raise ArgumentError, "rate string must be \"num/den\", got \"[r]\""
    else
      raise ArgumentError, "rate must be [num, den], an Integer or \"num/den\", got [r]"
    if num <= 0 || den <= 0
      raise ArgumentError, "rate must be positive, got [num]/[den]"
    g = Timecode.gcd(num, den)
    [num / g, den / g]

  -> .gcd(a, b)
    x = a
    y = b
    while y != 0
      t = x % y
      x = y
      y = t
    x < 0 ? 0 - x : x

  # Floor division (Tungsten's / on integers truncates toward zero).
  -> .fdiv(a, b)
    q = a / b
    if (a % b != 0) && ((a < 0) != (b < 0))
      q -= 1
    q

  # Nominal frames per timecode second: num / den rounded (24000/1001 -> 24).
  -> .quanta(rate)
    r = Timecode.rate(rate)
    (r[0] + r[1] / 2) / r[1]

  # True for the rates that count drop-frame: 30000/1001 and 60000/1001.
  -> .drop_frame?(rate)
    r = Timecode.rate(rate)
    q = Timecode.quanta(r)
    r[1] == 1001 && (q == 30 || q == 60)

  # Frame labels dropped per minute in drop-frame counting (0 when non-drop).
  -> .dropped_per_minute(rate, drop)
    if !drop
      return 0
    q = Timecode.quanta(rate)
    if q % 30 != 0
      raise ArgumentError, "drop-frame timecode needs a 30000/1001 or 60000/1001 rate, got [Timecode.rate(rate)]"
    q / 15

  # The SMPTE label of frame index `frame` (0 = 00:00:00:00). drop: nil picks
  # drop-frame for 30000/1001 and 60000/1001, else non-drop.
  -> .to_smpte(frame, rate, drop = nil)
    if frame < 0
      raise ArgumentError, "timecode of a negative frame ([frame])"
    d = drop == nil ? Timecode.drop_frame?(rate) : drop
    q = Timecode.quanta(rate)
    n = frame
    k = Timecode.dropped_per_minute(rate, d)
    if k > 0
      per10 = q * 600 - k * 9
      per1 = q * 60 - k
      tens = n / per10
      rem = n % per10
      n = n + k * 9 * tens
      if rem >= k
        n = n + k * ((rem - k) / per1)
    day = q * 86400
    n = n % day
    ff = n % q
    ss = (n / q) % 60
    mm = (n / (q * 60)) % 60
    hh = n / (q * 3600)
    sep = d ? ";" : ":"
    Timecode.two(hh) + ":" + Timecode.two(mm) + ":" + Timecode.two(ss) + sep + Timecode.two(ff)

  -> .two(v)
    v.to_s.rjust(2, "0")

  # The frame index of an SMPTE label "HH:MM:SS:FF" (";", "." or "," before
  # FF marks drop-frame). Raises on a label drop-frame counting skips.
  -> .parse(tc, rate)
    s = tc.to_s
    if s.size != 11
      raise ArgumentError, "timecode must be HH:MM:SS:FF, got \"[s]\""
    sep = s[8]
    drop = sep == ";" || sep == "." || sep == ","
    if s[2] != ":" || s[5] != ":" || (sep != ":" && !drop)
      raise ArgumentError, "timecode must be HH:MM:SS:FF, got \"[s]\""
    hh = Timecode.digits(s, 0)
    mm = Timecode.digits(s, 3)
    ss = Timecode.digits(s, 6)
    ff = Timecode.digits(s, 9)
    q = Timecode.quanta(rate)
    if hh > 23 || mm > 59 || ss > 59 || ff >= q
      raise ArgumentError, "timecode \"[s]\" is out of range at [q] frames per second"
    k = Timecode.dropped_per_minute(rate, drop)
    if k > 0 && ss == 0 && ff < k && mm % 10 != 0
      raise ArgumentError, "timecode \"[s]\" does not exist in drop-frame counting (labels 00..[k - 1] are skipped at minute [mm])"
    minutes = hh * 60 + mm
    (hh * 3600 + mm * 60 + ss) * q + ff - k * (minutes - minutes / 10)

  -> .digits(s, i)
    a = s[i].to_i
    b = s[i + 1].to_i
    if !("0123456789".include?(s[i])) || !("0123456789".include?(s[i + 1]))
      raise ArgumentError, "timecode \"[s]\" has a non-digit field"
    a * 10 + b

  # Audio samples spanning `frames` video frames: frames x sr x den / num,
  # rounded half up (exact for 24, 25, 50 and 24000/1001 at 48 kHz).
  -> .samples(frames, rate, sr = 48000)
    r = Timecode.rate(rate)
    Timecode.fdiv(2 * frames * sr * r[1] + r[0], 2 * r[0])

  # The frame whose span contains audio sample `sample` (floor).
  -> .frame_of_sample(sample, rate, sr = 48000)
    r = Timecode.rate(rate)
    Timecode.fdiv(sample * r[0], sr * r[1])


+ Flicks
  -> .per_second
    705600000

  # Flicks per frame; raises when the rate does not divide 705,600,000.
  -> .per_frame(rate)
    r = Timecode.rate(rate)
    if (705600000 * r[1]) % r[0] != 0
      raise ArgumentError, "[r[0]]/[r[1]] fps is not a whole number of flicks per frame"
    705600000 * r[1] / r[0]

  -> .per_sample(sr = 48000)
    if 705600000 % sr != 0
      raise ArgumentError, "[sr] Hz is not a whole number of flicks per sample"
    705600000 / sr

  -> .from_frame(frame, rate)
    frame * Flicks.per_frame(rate)

  -> .from_sample(sample, sr = 48000)
    sample * Flicks.per_sample(sr)

  -> .from_ms(ms)
    ms * 705600

  # The nearest frame start to a flicks time, ties to the later frame:
  # floor((2 flicks num + 705600000 den) / (2 x 705600000 den)).
  -> .to_frame(flicks, rate)
    r = Timecode.rate(rate)
    Timecode.fdiv(2 * flicks * r[0] + 705600000 * r[1], 2 * 705600000 * r[1])

  # The nearest sample to a flicks time, ties to the later sample.
  -> .to_sample(flicks, sr = 48000)
    Timecode.fdiv(2 * flicks * sr + 705600000, 2 * 705600000)

  # Whole milliseconds, rounded half up.
  -> .to_ms(flicks)
    Timecode.fdiv(2 * flicks + 705600, 2 * 705600)

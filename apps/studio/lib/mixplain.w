# studio/mixplain — the "plain" mix: every take and cue placed as it is (no voice chain, de-esser, reverb or
# ducking), each cue cut where its `until` anchor says, then the same loudness stage as lib/audio.w (BS.1770
# integrated loudness, a linear gain to the cut's target, the 4x true-peak limiter), 24-bit WAV exactly as long as
# the picture. For films whose narration is already finished audio (the explainers: clips and pauses, a sting,
# the channel outro). The episode selects it with "mix": {"mode": "plain"}.
#
# Only calls lib/audio.w's DSP; lib/audio.w itself is unchanged.

use base
use audio

+ PlainMixer < Mixer
  # Scratch for the longest take or cue (no voice chains, so no cached takes and no FFT plan).
  -> prepare
    cap = @sr * 4
    @r["tracks"][2]["items"].each ->(it)
      cap = [cap, frames_of(it["src"]) + @sr * 2].max
    @r["tracks"][3]["items"].each ->(c)
      cap = [cap, frames_of(c["src"]) + @sr * 2].max
    @cap = cap
    @l = f64[cap]
    @rr = f64[cap]
    nil

  # One source at a sample offset: n samples (cut to `limit` when given), linear gain, optional fades.
  -> place_plain(src, s0, limit, gain_db, fade_in_ms, fade_out_ms, bus)
    n = load(src, 0)
    n = limit if limit != nil && limit < n
    return nil if n <= 0
    fi = (to_f(fade_in_ms) * @sr / ~1000.0).to_i
    fo = (to_f(fade_out_ms) * @sr / ~1000.0).to_i
    if fi > 0 || fo > 0
      fade_run(@l, n, fi, fo)
      fade_run(@rr, n, fi, fo)
    place_run(bus, @n, @l, @rr, n, s0, db_lin(to_f(gain_db)), @l, 0, ~0.0)
    nil

  -> mix(out)
    t0 = clock_ms()
    prepare()
    n = @n
    bus = f32[n * 2]
    lines = @r["tracks"][2]["items"]
    lines.each ->(it)
      place_plain(it["src"], it["s0"], nil, get(it, "gain_db", 0), 0, 0, bus)
    t1 = clock_ms()
    @r["tracks"][3]["items"].each ->(c)
      lim = nil
      lim = c["s1"] - c["s0"] if c["s1"] != nil
      place_plain(c["src"], c["s0"], lim, get(c, "gain_db", 0), get(c, "fade_in_ms", 0), get(c, "fade_out_ms", 0), bus)
    t2 = clock_ms()
    if get(@mixcfg, "peak_db", nil) != nil
      pk = bus_peak(bus, n * 2)
      lim2 = db_lin(to_f(@mixcfg["peak_db"]))
      bus_scale(bus, n * 2, lim2 / pk) if pk > lim2
    loud = @proj.ep["cuts"][@r["cut"]]["loudness"]
    target = to_f(loud["lufs"])
    ceil = db_lin(to_f(loud["tp"]))
    sub = @sr / 10
    zs = f64[n / sub + 1]
    nb = k_weight_blocks(bus, n, zs, sub)
    before = integrated_lufs(zs, nb)
    gain_db = target - before
    # The limiter takes the peaks back down, so the level can land under the target (narration has high crest
    # factors): a second pass from the unlimited bus adds what the first fell short by.
    orig = f32[n * 2]
    copy_f32(bus, orig, n * 2)
    h = f64[48]
    tp_taps(h)
    g = f32[n]
    w = @sr / 1000 * 2
    rel = ~1.0 - Math.exp((~0.0 - ~1.0) / (~0.1 * @sr))
    tp_pre = ~0.0
    after = ~0.0
    npass = 0
    while npass < 3
      copy_f32(orig, bus, n * 2) if npass > 0
      bus_scale(bus, n * 2, db_lin(gain_db))
      tp_pre = tp_gain(bus, n, h, ceil, g)
      limit_apply(bus, n, g, w, rel)
      nb = k_weight_blocks(bus, n, zs, sub)
      after = integrated_lufs(zs, nb)
      npass += 1
      npass = 3 if (after - target).abs < ~0.05
      gain_db = gain_db + (target - after)
    tp_post = true_peak(bus, n, h, ceil * ~0.5)
    t3 = clock_ms()
    write_wav_s24(out, bus, n, @sr)
    t4 = clock_ms()
    {"samples" => n, "lines" => lines.size, "cues" => @r["tracks"][3]["items"].size, "lufs_premaster" => before,
     "gain_db" => gain_db - (target - after), "lufs" => after, "true_peak_dbtp" => ~20.0 * Math.log(tp_post) * ~0.4342944819032518,
     "true_peak_before_limit_dbtp" => ~20.0 * Math.log(tp_pre) * ~0.4342944819032518,
     "ms" => {"narration" => t1 - t0, "cues" => t2 - t1, "loudness" => t3 - t2, "write" => t4 - t3}}

-> copy_f32(a, b, n) (f32[] f32[] i64) i64
  i = 0
  while i < n
    b[i] = a[i]
    i += 1
  0

# studio mix: the plain mix for episodes that ask for it, else lib/audio.w's chain (cmd_mix).
-> cmd_mix_any(args)
  cut = (args.size > 3 && args[2] == "--cut") ? args[3] : "full"
  p = Project.new(args[1], cut)
  return cmd_mix(args) if get(p.ep["mix"], "mode", "chain") != "plain"
  p.verify_assets(true)
  r = p.resolve
  out = p.out_path("mix.wav")
  # the plain mixer's own version is part of its cache key
  key = sha(mix_key(p, r) + ":plain-mix-2")
  cached = p.build + "/audio/mix_" + key + ".wav"
  if File.exist?(cached) && File.exist?(cached + ".json")
    OS.system("rm -f " + shq(out) + " && ln " + shq(cached) + " " + shq(out))
    write_text(p.out_path("mix_report.json"), File.read(cached + ".json"))
    << "mix: unchanged audio (" + key.slice(0, 12) + "), reused " + cached
    return 0
  m = PlainMixer.new(p, r)
  rep = m.mix(cached)
  write_text(cached + ".json", JSON.encode(rep))
  OS.system("rm -f " + shq(out) + " && ln " + shq(cached) + " " + shq(out))
  write_text(p.out_path("mix_report.json"), JSON.encode(rep))
  << "mix (plain): " + rep["samples"].to_s + " samples (" + timecode(r["frames"], r["rate"][0], r["rate"][1]) + "), " + rep["lines"].to_s + " lines, " + rep["cues"].to_s + " cues; " + fixed6(rep["lufs_premaster"]) + " LUFS + " + fixed6(rep["gain_db"]) + " dB -> " + fixed6(rep["lufs"]) + " LUFS, true peak " + fixed6(rep["true_peak_dbtp"]) + " dBTP -> " + out
  << "mix timing ms: " + JSON.encode(rep["ms"])
  0

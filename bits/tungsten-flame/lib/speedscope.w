# speedscope.w — Export folded stacks as a speedscope.app profile.

use folded

in Tungsten:Flame

+ Speedscope

  # ---- Public entry point ----

  # Folded-stack text → a complete speedscope "sampled" profile JSON
  # document (string).
  -> .export(folded_text, profile_name)
    counts = self.dedupe_counts(folded_text)
    stacks = counts.keys().sort()

    # Frame table + samples (index arrays, root→leaf) + parallel weights + total
    # in a single pass across the sorted stacks.
    frames_json = []
    frame_index = {}
    samples = []
    weights = []
    total = 0
    si = 0
    n_stacks = stacks.size()
    while si < n_stacks
      stack = stacks[si]
      frames = stack.split(";")
      idxs = []
      fi = 0
      n_frames = frames.size()
      while fi < n_frames
        f = frames[fi]
        if frame_index.has_key?(f)
          idx_s = frame_index[f]
        else
          idx_s = frames_json.size().to_s()
          frame_index[f] = idx_s
          frames_json.push("{\"name\":\"" + self.json_escape(f) + "\"}")
        idxs.push(idx_s)
        fi = fi + 1
      c = counts[stack]
      samples.push("\[" + idxs.join(",") + "\]")
      weights.push(c.to_s())
      total = total + c
      si = si + 1

    esc_name = self.json_escape(profile_name)
    out = []
    out.push("{")
    out.push("\"$schema\":\"https://www.speedscope.app/file-format-schema.json\",")
    out.push("\"exporter\":\"tungsten-flame\",")
    out.push("\"name\":\"" + esc_name + "\",")
    out.push("\"activeProfileIndex\":0,")
    out.push("\"shared\":{\"frames\":\[" + frames_json.join(",") + "\]},")
    out.push("\"profiles\":\[{")
    out.push("\"type\":\"sampled\",")
    out.push("\"name\":\"" + esc_name + "\",")
    out.push("\"unit\":\"none\",")
    out.push("\"startValue\":0,")
    out.push("\"endValue\":" + total.to_s() + ",")
    out.push("\"samples\":\[" + samples.join(",") + "\],")
    out.push("\"weights\":\[" + weights.join(",") + "\]")
    out.push("}\]}")
    out.join("")

  # ---- Parsing & Helpers ----

  -> .dedupe_counts(folded_text)
    Tungsten:Flame:Folded.parse(folded_text)[:map]

  -> .json_escape(s)
    Tungsten:Flame:Folded.json_escape(s)

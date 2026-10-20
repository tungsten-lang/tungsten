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

    # Frame table: each unique frame once, indexed in first-seen order
    # across the sorted stacks (deterministic).
    frame_names = []
    frame_index = {}
    si = 0
    while si < stacks.size()
      frames = stacks[si].split(";")
      fi = 0
      while fi < frames.size()
        f = frames[fi]
        if !frame_index.has_key?(f)
          frame_index[f] = frame_names.size()
          frame_names.push(f)
        fi = fi + 1
      si = si + 1

    # Samples (index arrays, root→leaf) + parallel weights + total.
    samples = []
    weights = []
    total = 0
    si = 0
    while si < stacks.size()
      stack = stacks[si]
      frames = stack.split(";")
      idxs = []
      fi = 0
      while fi < frames.size()
        idxs.push(frame_index[frames[fi]].to_s())
        fi = fi + 1
      samples.push("\[" + idxs.join(",") + "\]")
      weights.push(counts[stack].to_s())
      total = total + counts[stack]
      si = si + 1

    # Frame table JSON objects.
    frames_json = []
    fi = 0
    while fi < frame_names.size()
      frames_json.push("{\"name\":\"" + self.json_escape(frame_names[fi]) + "\"}")
      fi = fi + 1

    out = []
    out.push("{")
    out.push("\"$schema\":\"https://www.speedscope.app/file-format-schema.json\",")
    out.push("\"exporter\":\"tungsten-flame\",")
    out.push("\"name\":\"" + self.json_escape(profile_name) + "\",")
    out.push("\"activeProfileIndex\":0,")
    out.push("\"shared\":{\"frames\":\[" + frames_json.join(",") + "\]},")
    out.push("\"profiles\":\[{")
    out.push("\"type\":\"sampled\",")
    out.push("\"name\":\"" + self.json_escape(profile_name) + "\",")
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

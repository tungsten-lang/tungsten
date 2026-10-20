# trace_event.w — Export folded stacks as a chrome://tracing / Perfetto
# Trace Event Format profile.

use folded

in Tungsten:Flame

+ TraceEvent

  # ---- Public entry point ----

  # Folded-stack text -> a complete Trace Event Format JSON document (string).
  -> .export(folded_text, process_name)
    root = self.build_tree(folded_text)
    events = []
    events.push(self.process_meta(process_name))
    events.push(self.thread_meta("samples"))
    self.emit_children(root, 0, events)
    out = []
    out.push("{\"displayTimeUnit\":\"ns\",\"traceEvents\":\[")
    out.push(events.join(","))
    out.push("\]}")
    out.join("")

  # ---- Timeline synthesis ----

  -> .emit_children(node, offset, events)
    kids = self.sort_children(node[:children])
    cur = offset
    i = 0
    while i < kids.size()
      child = kids[i]
      events.push(self.slice_event(child[:name], cur, child[:count]))
      self.emit_children(child, cur, events)
      cur = cur + child[:count]
      i = i + 1

  -> .slice_event(name, ts, dur)
    "{\"name\":\"" + self.json_escape(name) + "\",\"ph\":\"X\",\"ts\":" + ts.to_s() + ",\"dur\":" + dur.to_s() + ",\"pid\":1,\"tid\":1}"

  -> .process_meta(name)
    "{\"name\":\"process_name\",\"ph\":\"M\",\"pid\":1,\"args\":{\"name\":\"" + self.json_escape(name) + "\"}}"

  -> .thread_meta(name)
    "{\"name\":\"thread_name\",\"ph\":\"M\",\"pid\":1,\"tid\":1,\"args\":{\"name\":\"" + self.json_escape(name) + "\"}}"

  # ---- Tree construction & Helpers (delegated to Folded) ----

  -> .build_tree(folded_text)
    Tungsten:Flame:Folded.build_tree(folded_text)

  -> .insert_stack(root, frames, count)
    Tungsten:Flame:Folded.insert_stack(root, frames, count)

  -> .find_child(node, name)
    Tungsten:Flame:Folded.find_child(node, name)

  -> .sort_children(kids)
    Tungsten:Flame:Folded.sort_children(kids)

  -> .json_escape(s)
    Tungsten:Flame:Folded.json_escape(s)

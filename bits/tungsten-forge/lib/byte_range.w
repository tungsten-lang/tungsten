# Forge::ByteRange — HTTP Range request-header parsing (RFC 7233).
#
# Turns the value of a request `Range` header ("bytes=0-499, -100") into
# resolved, satisfiable byte ranges against a known resource length — the
# request-surface half of HTTP 206 Partial Content (resumable downloads,
# media/video streaming, chunked fetches). Before this file the request
# had no way to read a Range header at all: an app that wanted to serve a
# partial representation had to split the header by hand and re-derive the
# satisfiability and clamping rules itself. It is the request-surface
# counterpart to QueryString / Cookie / Multipart / Negotiation; the
# Request delegators are #range_header and #ranges.
#
# Two entry points, split so the pure syntax and the length-dependent
# resolution can each be tested on their own:
#
#   .parse(header)          — a pure syntactic parse; needs no length.
#   .resolve(header, total) — parse + resolve + satisfiability against a
#                             resource of `total` bytes.
#
# `.parse` returns an ordered Array of spec Hashes, or nil. Each spec has
# exactly one shape (absent keys read back as nil via Hash indexing):
#
#   {first: F, last: L}   from "F-L"  — bytes F..L inclusive, F <= L
#   {first: F, last: nil} from "F-"   — byte F to the end of the resource
#   {suffix: N}           from "-N"   — the final N bytes
#
# nil means "ignore the header and serve the full 200 representation": the
# header is absent/empty, names a range unit other than "bytes" (bytes is
# the only unit HTTP defines), or is syntactically invalid — RFC 7233 §3.1
# says a recipient MUST ignore an invalid range-set rather than reject it.
# A range-set is invalid if any of its specs is malformed, including a
# closed range whose first exceeds its last (§2.1). Empty list elements
# (a stray "," per the #rule) are skipped; a value-less range unit still
# needs at least one spec.
#
# `.resolve` returns one of three things, mapping straight onto a response:
#
#   nil            — as above (no/ignored Range): serve 200
#   :unsatisfiable — a valid bytes range-set, but no spec fits the resource
#                    (every first-byte-pos is past the end, or a "-0"
#                    suffix): the caller replies 416 Range Not Satisfiable
#   [ByteRange...] — the satisfiable ranges, in request order: reply 206.
#                    Partially-satisfiable sets keep only the ranges that
#                    fit, per §4.1.
#
# A resolved ByteRange carries inclusive @start/@finish offsets and the
# @total it was resolved against — #length is the byte count and
# #content_range renders the "bytes start-finish/total" value a 206 puts
# in its Content-Range header. Resolution clamps a last-byte-pos at or past
# the end down to total-1, and a suffix larger than the resource down to
# the whole resource, so @start/@finish are always valid indices.
#
# NOTE: no `&.` / safe-navigation and no early-return-from-inside-a-block
# below, mirroring request.w / query_string.w / negotiation.w — the
# self-hosted interpreter implements neither. Digit runs are validated
# explicitly because String#to_i silently yields 0 for non-numeric text.

+ ByteRange
  ro :start
  ro :finish
  ro :total

  -> new(options = {})
    @start  = options[:start]
    @finish = options[:finish]
    @total  = options[:total]

  # Number of bytes this range covers (inclusive, so finish - start + 1).
  -> length
    @finish - @start + 1

  # The Content-Range header value for a 206 carrying this range.
  -> content_range
    "bytes [@start]-[@finish]/[@total]"

  # --- Parsing (RFC 7233 §2.1) ---

  # Pure syntactic parse of a Range header value into an ordered Array of
  # spec Hashes, or nil (absent / non-"bytes" unit / malformed range-set).
  -> .parse(header)
    return nil if header == nil || header.empty?
    eq = header.index("=")
    return nil if eq == nil
    unit = header.slice(0, eq).strip.downcase
    return nil unless unit == "bytes"
    set = header.slice(eq + 1, header.size - eq - 1).strip
    return nil if set.empty?
    specs = []
    ok = true
    set.split(",").each -> (raw)
      part = raw.strip
      if !part.empty?
        spec = self.parse_spec(part)
        if spec == nil
          ok = false
        else
          specs.push(spec)
    return nil if !ok
    return nil if specs.empty?
    specs

  # Parse one range-spec ("0-499", "500-", "-500") into a spec Hash, or nil
  # when it is malformed. A closed range requires first-byte-pos <= last.
  -> .parse_spec(part)
    if part.slice(0, 1) == "-"
      n = self.to_count(part.slice(1, part.size - 1))
      return nil if n == nil
      {suffix: n}
    else
      dash = part.index("-")
      return nil if dash == nil
      first = self.to_count(part.slice(0, dash))
      return nil if first == nil
      rest = part.slice(dash + 1, part.size - dash - 1)
      if rest.empty?
        {first: first, last: nil}
      else
        last = self.to_count(rest)
        return nil if last == nil
        return nil if first > last
        {first: first, last: last}

  # A run of one-or-more ASCII digits as a non-negative Integer, or nil.
  # (String#to_i silently yields 0 for "" / "abc" — this rejects them, the
  # same validity test QueryString#nibble gets from index returning nil.)
  -> .to_count(s)
    return nil if s == nil || s.empty?
    i = 0
    n = s.size
    while i < n
      return nil if "0123456789".index(s.slice(i, 1)) == nil
      i += 1
    s.to_i

  # --- Resolution against a known resource length ---

  # Parse and resolve a Range header against a resource of `total` bytes.
  # Returns nil (serve 200), :unsatisfiable (416), or an Array of
  # satisfiable ByteRanges in request order (206). See the file header.
  -> .resolve(header, total)
    specs = self.parse(header)
    return nil if specs == nil
    return nil if total == nil
    ranges = []
    i = 0
    while i < specs.size
      r = self.resolve_spec(specs[i], total)
      ranges.push(r) if r != nil
      i += 1
    return :unsatisfiable if ranges.empty?
    ranges

  # Resolve one parsed spec against `total`, returning a satisfiable
  # ByteRange or nil when this spec cannot be satisfied.
  -> .resolve_spec(spec, total)
    suffix = spec[:suffix]
    if suffix != nil
      return nil if suffix == 0 || total == 0
      start = total - suffix
      start = 0 if start < 0
      self.new({start: start, finish: total - 1, total: total})
    else
      first = spec[:first]
      return nil if first >= total
      last = spec[:last]
      if last == nil || last >= total
        last = total - 1
      self.new({start: first, finish: last, total: total})

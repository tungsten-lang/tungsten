# Forge::Negotiation — HTTP proactive content negotiation (RFC 7231 §5.3).
#
# Parses the Accept family of request headers — Accept, Accept-Language,
# Accept-Encoding, Accept-Charset — which all share one grammar: a
# comma-separated list of ranges, each optionally carrying a ";q=" quality
# weight (0.0..1.0, default 1.0). A q of 0 means "explicitly NOT
# acceptable". This class turns such a header into ranked, matchable
# entries and picks the server's best offer against them.
#
# Why forge needs it: before this file the only negotiation forge did was
# CompressionMiddleware's naive `accept.include?("gzip")`, which ignores
# q-values entirely (so `Accept-Encoding: gzip;q=0` — an explicit refusal
# — still matched). There was no media-type negotiation at all, so an API
# that can serve both JSON and HTML had no way to honour a client's
# `Accept: text/html,application/json;q=0.9`. This is the request-surface
# counterpart to QueryString/Cookie/Multipart, and the proper foundation
# CompressionMiddleware's check should have been built on.
#
# The Request delegators are #accepts?, #preferred_type,
# #preferred_language, #preferred_encoding and #accepted_media_types.
#
# Matching honours specificity (RFC 7231 §5.3.2): the MOST SPECIFIC range
# that matches an offer determines its quality, even when a broader range
# has a higher q. So `Accept: application/json;q=0, */*` accepts every
# type EXCEPT application/json — the exact ";q=0" wins over the wildcard.
#
# Three matching modes, one per header shape:
#   :media — media ranges: "type/subtype" (3) > "type/*" (2) > "*/*" (1)
#   :lang  — RFC 4647 basic filtering: exact tag (3) > prefix on "-" (2)
#            (range "en" matches tag "en-US") > "*" (1)
#   :token — opaque tokens (encodings/charsets): exact (2) > "*" (1)
#
# A nil / empty header means "no preference": every offer is acceptable
# and #accepts? is always true — an absent Accept is `*/*` per the spec.
#
# NOTE: q is read with String#to_f, which yields 0.0 for a non-numeric
# weight ("q=high") — such a range is treated as not acceptable, the safe
# reading of a malformed weight. No `&.` / safe-navigation, no
# early-return-past-a-block and no comparator-block sort below, mirroring
# request.w / query_string.w — the self-hosted interpreter implements none
# of those. Ranking uses an explicit stable selection sort instead.

+ Negotiation
  # Parse an Accept-style header into an Array of { value:, q: } entries in
  # ORIGINAL header order. `value` is lowercased and trimmed; `q` is a
  # float in 0.0..1.0. Empty / nil header => [].
  -> .parse(header)
    result = []
    if header != nil && !header.empty?
      header.split(",").each -> (raw)
        part = raw.strip
        if !part.empty?
          result.push(self.parse_entry(part))
    result

  # Parse one range entry ("text/html;q=0.9;level=1") into { value:, q: }.
  # The value is the token before the first ";"; q comes from the first
  # "q=" parameter (default 1.0). Other parameters are ignored.
  -> .parse_entry(entry)
    q = 1.0
    value = entry
    semi = entry.index(";")
    if semi != nil
      value = entry.slice(0, semi)
      rest = entry.slice(semi + 1, entry.size - semi - 1)
      rest.split(";").each -> (param)
        p = param.strip
        eq = p.index("=")
        if eq != nil
          name = p.slice(0, eq).strip.downcase
          if name == "q"
            q = self.clamp_q(p.slice(eq + 1, p.size - eq - 1).strip.to_f)
    {value: value.strip.downcase, q: q}

  # Clamp a parsed weight into 0.0..1.0.
  -> .clamp_q(q)
    return 0.0 if q < 0.0
    return 1.0 if q > 1.0
    q

  # The best of the server's `offered` values for this header, or nil when
  # the client accepts none of them. A nil/empty header means "no
  # preference", so the server's first choice (offered[0]) is returned.
  # Ties in quality are broken by `offered` order (server preference),
  # matching Rack/Sinatra.
  -> .best(header, offered, kind)
    return nil if offered == nil || offered.empty?
    entries = self.parse(header)
    return offered[0] if entries.empty?
    best_value = nil
    best_q = 0.0
    i = 0
    while i < offered.size
      candidate = offered[i]
      q = self.resolved_q(entries, candidate, kind)
      if q > best_q
        best_q = q
        best_value = candidate
      i += 1
    best_value

  # Does the client accept `value` for this header? A nil/empty header
  # accepts everything; an explicit ";q=0" on the most specific matching
  # range is a rejection.
  -> .accepts?(header, value, kind)
    entries = self.parse(header)
    return true if entries.empty?
    self.resolved_q(entries, value, kind) > 0.0

  # The acceptable range strings of an Accept-style header, best-first
  # (descending q, ties keep original order). Entries with q == 0
  # (explicit rejections) are dropped. Returns lowercased strings.
  -> .ranked(header)
    entries = self.parse(header)
    kept = []
    i = 0
    while i < entries.size
      kept.push(entries[i]) if entries[i][:q] > 0.0
      i += 1
    # Stable descending selection sort (no comparator block — see header):
    # repeatedly take the highest-q entry, ties resolved by lowest index.
    taken = []
    t = 0
    while t < kept.size
      taken.push(false)
      t += 1
    values = []
    count = 0
    while count < kept.size
      pick = -1
      p = 0
      while p < kept.size
        if !taken[p] && (pick == -1 || kept[p][:q] > kept[pick][:q])
          pick = p
        p += 1
      taken[pick] = true
      values.push(kept[pick][:value])
      count += 1
    values

  # The effective quality of `value` under `entries`: the q of the MOST
  # SPECIFIC matching range (a more specific range wins even when a broader
  # one has a higher q). 0.0 when nothing matches.
  -> .resolved_q(entries, value, kind)
    best_spec = 0
    best_q = 0.0
    i = 0
    while i < entries.size
      entry = entries[i]
      spec = self.specificity(entry[:value], value, kind)
      if spec > best_spec
        best_spec = spec
        best_q = entry[:q]
      elsif spec == best_spec && spec > 0 && entry[:q] > best_q
        best_q = entry[:q]
      i += 1
    best_q

  # Match specificity of `range` against `value` for `kind`; 0 = no match,
  # higher = more specific. `range` is already lowercased by parse.
  -> .specificity(range, value, kind)
    v = value.downcase
    if kind == :media
      self.media_specificity(range, v)
    elsif kind == :lang
      self.lang_specificity(range, v)
    else
      self.token_specificity(range, v)

  -> .media_specificity(range, value)
    return 1 if range == "*/*"
    rslash = range.index("/")
    vslash = value.index("/")
    return 0 if rslash == nil || vslash == nil
    rtype = range.slice(0, rslash)
    rsub  = range.slice(rslash + 1, range.size - rslash - 1)
    vtype = value.slice(0, vslash)
    vsub  = value.slice(vslash + 1, value.size - vslash - 1)
    if rsub == "*"
      return 2 if rtype == vtype
      0
    else
      return 3 if rtype == vtype && rsub == vsub
      0

  -> .lang_specificity(range, value)
    return 1 if range == "*"
    return 3 if range == value
    prefix = range + "-"
    return 2 if value.slice(0, prefix.size) == prefix
    0

  -> .token_specificity(range, value)
    return 1 if range == "*"
    return 2 if range == value
    0

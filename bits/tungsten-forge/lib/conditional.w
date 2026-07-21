# Forge::Conditional — HTTP conditional requests (RFC 7232).
#
# A conditional request carries a precondition header that lets a client
# and server skip redundant work: a browser that already holds a cached
# copy sends If-None-Match / If-Modified-Since and the server answers 304
# Not Modified with no body (the single biggest bandwidth win a static
# server has); an editor sends If-Match / If-Unmodified-Since so a PUT
# fails with 412 Precondition Failed rather than clobbering a concurrent
# edit (optimistic-concurrency "lost update" protection). Before this file
# Forge had no way to evaluate any of it — Static did a single hand-rolled
# `If-None-Match == "\"etag\""` string compare that ignored weak tags, tag
# lists, "*", and every date header outright.
#
# Two pieces, both pure header logic (no clock, no I/O), so both run under
# the interpreter and compiled:
#
#   ETag       — parse an entity-tag or a comma-separated list of them
#                (If-None-Match / If-Match / the ETag response header) and
#                compare two tags under RFC 7232 §2.3.2's strong and weak
#                rules.
#   Conditional — apply the RFC 7232 §6 precedence to a Request plus the
#                 resource's current validators, returning the outcome as
#                 one symbol: :ok / :not_modified / :precondition_failed.
#
# An entity-tag is an opaque quoted string, optionally weak:
#
#     "xyzzy"        strong
#     W/"xyzzy"      weak (may differ across semantically-equivalent bodies)
#
# STRONG comparison (If-Match) requires both tags strong AND their opaque
# forms equal; WEAK comparison (If-None-Match) requires only the opaque
# forms equal. A comma is a legal opaque-tag character (RFC 7232 §2.3), so
# a tag list is split quote-aware, not on bare commas.
#
# NOTE: no `&.` / safe-navigation and no early-return-from-inside-a-block
# below, mirroring the other request-surface parsers. Tags are Strings,
# never Symbols (arbitrary client input).

+ ETag
  # Parse an If-None-Match / If-Match header value. Returns nil (header
  # absent/empty), the symbol :any (the wildcard "*"), or an Array of
  # entry Hashes {weak: <bool>, tag: <opaque string, unquoted>}. A member
  # that is not a well-formed entity-tag is skipped.
  -> .parse(header)
    return nil if header == nil
    s = header.strip
    return nil if s.empty?
    return :any if s == "*"
    out = []
    self.split_tags(s).each -> (raw)
      entry = self.parse_one(raw)
      out.push(entry) if entry != nil
    out

  # Parse a single entity-tag token into {weak:, tag:}, or nil when it is
  # not a quoted opaque-tag. Also used on the ETag response-header value a
  # resource carries as its current validator.
  -> .parse_one(token)
    return nil if token == nil
    t = token.strip
    return nil if t.empty?
    weak = false
    if t.size >= 2 && t.slice(0, 2) == "W/"
      weak = true
      t = t.slice(2, t.size - 2).strip
    n = t.size
    return nil unless n >= 2 && t.slice(0, 1) == "\"" && t.slice(n - 1, 1) == "\""
    {weak: weak, tag: t.slice(1, n - 2)}

  # Does `list` (a parsed If-* value: :any or an Array of entries) match
  # the resource's current tag `res` (a parsed entry, or nil when the
  # resource has no ETag) under the given comparison (:strong / :weak)?
  # "*" matches whenever a representation exists — Conditional only asks
  # while serving one, so it always matches.
  -> .list_matches?(list, res, comparison)
    return true if list == :any
    return false if res == nil
    matched = false
    list.each -> (entry)
      matched = true if self.compare(entry, res, comparison)
    matched

  # Compare two parsed entries (RFC 7232 §2.3.2). Opaque forms must be
  # equal; a strong comparison additionally forbids either tag being weak.
  -> .compare(a, b, comparison)
    return false unless a[:tag] == b[:tag]
    if comparison == :strong
      return false if a[:weak] == true || b[:weak] == true
    true

  # Split a header on the commas that separate entity-tags, honouring the
  # quotes: a comma inside an opaque-tag's DQUOTEs is kept literally (RFC
  # 7232 §2.3 admits it). Returns trimmed, non-empty tokens.
  -> .split_tags(s)
    parts = []
    buf = ""
    in_quote = false
    i = 0
    n = s.size
    while i < n
      ch = s.slice(i, 1)
      if ch == "\""
        buf = buf + ch
        in_quote = !in_quote
      elsif ch == "," && !in_quote
        parts.push(buf)
        buf = ""
      else
        buf = buf + ch
      i += 1
    parts.push(buf)
    out = []
    parts.each -> (p)
      t = p.strip
      out.push(t) unless t.empty?
    out


+ Conditional
  # Evaluate a request's preconditions against a resource's current
  # validators and return the outcome as one symbol:
  #
  #   :ok                  — no precondition failed; serve normally (200).
  #   :not_modified        — the client's cached copy is current; reply 304
  #                          with no body (safe methods only).
  #   :precondition_failed — a guard the client set does not hold; reply
  #                          412 and do NOT perform the method.
  #
  # `etag` is the resource's current ETag *header value* (quoted, e.g.
  # "\"abc\"" or "W/\"abc\""), or nil when it has none; `last_modified` is
  # its modification time as epoch seconds (see HttpDate), or nil. The
  # method is read from the request; only GET/HEAD can yield 304.
  #
  # Precedence is RFC 7232 §6, evaluated in order: If-Match, then (only if
  # If-Match was absent) If-Unmodified-Since, then If-None-Match, then
  # (only if If-None-Match was absent, for safe methods) If-Modified-Since.
  # The resource is assumed to exist — Conditional is consulted while
  # serving a representation.
  -> .evaluate(request, etag, last_modified)
    method = request.method
    safe = method == :GET || method == :HEAD
    res = ETag.parse_one(etag)

    im  = request.if_match
    inm = request.if_none_match
    ims = request.if_modified_since
    ius = request.if_unmodified_since

    # Step 1 / 2: If-Match (strong), else If-Unmodified-Since.
    if im != nil
      return :precondition_failed unless ETag.list_matches?(im, res, :strong)
    elsif ius != nil
      if last_modified != nil && last_modified > ius
        return :precondition_failed

    # Step 3 / 4: If-None-Match (weak), else If-Modified-Since.
    if inm != nil
      if ETag.list_matches?(inm, res, :weak)
        return :not_modified if safe
        return :precondition_failed
    elsif safe && ims != nil
      if last_modified != nil && last_modified <= ims
        return :not_modified

    :ok

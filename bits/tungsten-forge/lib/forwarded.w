# Forge::Forwarded — proxy-forwarding header parsing (client IP + proto).
#
# When Forge runs behind a reverse proxy or load balancer (nginx, HAProxy,
# an ALB, Cloudflare, …) the TCP peer it sees is the PROXY, not the end
# user. `Request#remote_addr` is therefore the proxy's address, and any
# code that reasons about "who is calling" — access logs, per-client rate
# limiting (RateLimitMiddleware keys on remote_addr today), abuse
# blocking, geo lookups, or building an absolute redirect with the right
# scheme — is wrong behind a proxy. Every serious framework exposes the
# forwarded client identity (Rack::Request#ip / #forwarded_for, Express
# `req.ips` / `req.protocol` with `trust proxy`, Go's `X-Forwarded-For`
# handling). Forge had NO way to read it before this file — the raw
# headers were there, but nothing parsed them.
#
# This class parses BOTH conventions and the Request surface composes them:
#
#   - RFC 7239 `Forwarded` — the standardized header:
#       Forwarded: for=192.0.2.60;proto=http;by=203.0.113.43
#       Forwarded: for="[2001:db8:cafe::17]:4711", for=192.0.2.43
#     A comma-separated list of ELEMENTS, each a ";"-separated list of
#     name=value pairs. Names are case-insensitive (for/by/host/proto).
#     Values are a token OR a double-quoted string (IPv6 literals and
#     ports must be quoted). The leftmost element is the originating
#     client; each proxy appends itself to the right (RFC 7239 §7.1).
#
#   - The de-facto `X-Forwarded-*` family (used when `Forwarded` is
#     absent): `X-Forwarded-For: client, proxy1, proxy2` (leftmost =
#     client), `X-Forwarded-Proto: https`, `X-Forwarded-Host`,
#     `X-Forwarded-Port`.
#
# `Forwarded` (RFC 7239) is preferred when present; the `X-Forwarded-*`
# headers are the fallback — this is the precedence proxies themselves
# assume when they emit the standard header.
#
# The Request delegators are #forwarded (the structured RFC 7239
# elements), #forwarded_for (the address chain, client-first), #client_ip,
# #forwarded_proto, #forwarded_host, #forwarded_port, #forwarded_ssl? and
# #via_proxy?.
#
# SECURITY: a client can forge these headers, so the chain is only
# trustworthy for hops added by proxies YOU control. #client_ip returns
# the leftmost (claimed-originating) address; treat it as authoritative
# only when a trusted proxy is known to overwrite/sanitize the inbound
# header. Apps needing stricter handling can walk #forwarded_for
# themselves and apply their own trusted-proxy policy.
#
# NOTE: no `&.` / safe-navigation and no early-return-past-a-block below,
# mirroring request.w / cookie.w / negotiation.w — the self-hosted
# interpreter implements neither. Values are Strings, never Symbols
# (arbitrary client input; interning it is a memory foot-gun).

+ Forwarded
  # Parse an RFC 7239 `Forwarded` header value into an ordered Array of
  # elements, each a Hash of downcased param name => value (quoted values
  # unwrapped). Original header order is preserved (leftmost = client).
  # nil / empty header, or an element with no valid params, yields no
  # entry; an absent header yields [].
  -> .parse(header)
    result = []
    if header != nil && !header.empty?
      self.split_top(header, ",").each -> (element)
        params = {}
        self.split_top(element, ";").each -> (pair)
          eq = pair.index("=")
          if eq != nil
            name  = pair.slice(0, eq).strip.downcase
            value = pair.slice(eq + 1, pair.size - eq - 1).strip
            params[name] = self.unquote(value) unless name.empty?
        result.push(params) unless params.size == 0
    result

  # Split `str` on single-character `delim`, but only at the top level —
  # a delimiter inside a double-quoted string (honouring "\\" escapes) is
  # kept literally. Quote and backslash characters are preserved in each
  # piece so `unquote` can process them afterwards. Always returns at
  # least one (possibly empty) piece.
  -> .split_top(str, delim)
    parts   = []
    buf     = ""
    in_quote = false
    escaped  = false
    i = 0
    n = str.size
    while i < n
      ch = str.slice(i, 1)
      if escaped
        buf = buf + ch
        escaped = false
      elsif in_quote && ch == "\\"
        buf = buf + ch
        escaped = true
      elsif ch == "\""
        buf = buf + ch
        in_quote = !in_quote
      elsif ch == delim && !in_quote
        parts.push(buf)
        buf = ""
      else
        buf = buf + ch
      i += 1
    parts.push(buf)
    parts

  # Strip one surrounding pair of double-quotes and unescape "\\X" -> "X"
  # inside them (RFC 7230 quoted-string). A value that is not quoted is
  # returned unchanged.
  -> .unquote(value)
    n = value.size
    if n >= 2 && value.slice(0, 1) == "\"" && value.slice(n - 1, 1) == "\""
      inner = value.slice(1, n - 2)
      out = ""
      i = 0
      m = inner.size
      while i < m
        ch = inner.slice(i, 1)
        if ch == "\\" && i + 1 < m
          i += 1
          out = out + inner.slice(i, 1)
        else
          out = out + ch
        i += 1
      out
    else
      value

  # Reduce a node identifier from a `for=`/`by=` param (or an
  # X-Forwarded-For entry) to its bare host: strip a bracketed IPv6's
  # brackets ("[2001:db8::1]:4711" -> "2001:db8::1") and an IPv4/host
  # port suffix ("192.0.2.43:47011" -> "192.0.2.43"). A bare IPv6 literal
  # (two or more colons, no brackets) and obfuscated identifiers
  # ("unknown", "_hidden") are returned unchanged.
  -> .node_host(node)
    if node == nil
      nil
    else
      s = node.strip
      if s.empty?
        s
      elsif s.slice(0, 1) == "\["
        close = s.index("\]")
        if close == nil
          s
        else
          s.slice(1, close - 1)
      else
        first = s.index(":")
        if first == nil
          s
        else
          second = s.index(":", first + 1)
          if second == nil
            s.slice(0, first)
          else
            s
  # A bare IPv6 (multiple colons) falls through to `s` above.

  # Split a comma-separated de-facto header (X-Forwarded-For / -Proto /
  # -Host / -Port) into trimmed, non-empty tokens in order. nil / empty
  # header => [].
  -> .split_list(value)
    out = []
    if value != nil && !value.empty?
      value.split(",").each -> (tok)
        t = tok.strip
        out.push(t) unless t.empty?
    out

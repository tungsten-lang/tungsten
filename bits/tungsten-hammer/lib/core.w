# Hammer core — URL parsing, HTTP response framing, and the experimental
# Tungsten HTTP/1.1 engine. Pure library: no top-level side effects, so
# specs (and other bits) can `use hammer/core` without running a benchmark.
# The CLI entry point lives in lib/hammer.w.

+ Hammer
  -> .spawn_worker(host, port, batch, pipeline, duration, worker_conns, total, errors) (string i64 string i64 i64 i64)
    Thread.new -> (_unused)
      i = 0
      while i < worker_conns
        go ->
          Hammer.tungsten_connection(host, port, batch, pipeline, duration, total, errors)
        i += 1
      ccall("w_scheduler_run")

  -> .url_without_scheme(url)
    if url.starts_with?("http://")
      return url.slice(7, url.size - 7)
    if url.starts_with?("https://")
      return url.slice(8, url.size - 8)
    url

  # The authority is the "[userinfo@]host[:port]" segment between the scheme
  # and the path. Strip the path (at the first '/') and any userinfo (through
  # the first '@'); what remains is host[:port], IPv6 hosts still bracketed.
  -> .url_authority(url) (string) string
    rest = url_without_scheme(url)
    slash = rest.index("/")
    if slash != nil
      rest = rest.slice(0, slash)
    at = rest.index("@")
    if at != nil
      rest = rest.slice(at + 1, rest.size - at - 1)
    rest

  # Host from an authority: the bracket-enclosed literal for an IPv6 address
  # ("[::1]:80" -> "::1"), otherwise everything before the port colon.
  -> .authority_host(auth) (string) string
    if auth.starts_with?("\[")
      close = auth.index("\]")
      return auth.slice(1, close - 1) if close != nil
    colon = auth.index(":")
    return auth.slice(0, colon) if colon != nil
    auth

  # Port from an authority, or default_port when none is given. For an IPv6
  # host the delimiting colon is the one after the closing bracket, never a
  # colon inside the address itself.
  -> .authority_port(auth, default_port) (string i64) i64
    if auth.starts_with?("\[")
      close = auth.index("\]")
      return default_port if close == nil
      port_pos = close + 1
      return default_port if port_pos >= auth.size
      return default_port if auth.slice(port_pos, 1) != ":"
      return auth.slice(port_pos + 1, auth.size - port_pos - 1).to_i
    colon = auth.index(":")
    return default_port if colon == nil
    auth.slice(colon + 1, auth.size - colon - 1).to_i

  -> .url_host(url) (string) string
    authority_host(url_authority(url))

  -> .url_port(url) (string) i64
    if url.starts_with?("https://")
      default_port = 443
    else
      default_port = 80
    authority_port(url_authority(url), default_port)

  -> .url_path(url)
    rest = url_without_scheme(url)
    slash = rest.index("/")

    return "/" if slash == nil

    rest.slice(slash, rest.size - slash)

  -> .request_batch(host, path, pipeline) (string string i64) string
    request = "GET [path] HTTP/1.1\r\nHost: [host]\r\nConnection: keep-alive\r\n\r\n"
    out = StringBuffer(request.size * pipeline) ## reuse
    i = 0
    while i < pipeline
      out << request
      i += 1
    out.to_s

  -> .content_length(buf, header_end) (string i64) i64
    pos = buf.index("Content-Length:")
    if pos == nil || pos > header_end
      pos = buf.index("content-length:")
    if pos == nil || pos > header_end
      return 0
    value_start = pos + 15
    line_end = buf.index("\n", value_start)
    if line_end == nil || line_end > header_end
      line_end = header_end
    buf.slice(value_start, line_end - value_start).strip().to_i

  -> .response_length(buf) (string) i64
    response_length_at(buf, 0)

  -> .response_length_at(buf, start) (string i64) i64
    length = ccall_nobox("w_string_byte_length", buf)
    data = ccall_nobox("w_string_byte_ptr", buf)
    response_length_at_raw(data, length, start)

  -> .response_length_at_raw(data, length, start) (i64 i64 i64) i64
    if length - start < 15
      return 0

    crlfcrlf = 0x0A0D0A0D ## i64
    limit = length - 4
    pos = start
    header_end = -1
    while pos <= limit
      if raw_load_u32(data, pos) == crlfcrlf
        header_end = pos
        break
      pos += 1

    if header_end < 0
      return 0

    p = start
    while p < header_end
      c = raw_load_u8(data, p)
      if c in (:-C :-c)
        if header_end - p >= 15
          e = raw_load_u8(data, p + 9)
          if e in (:-E :-e)
            v = p + 15
            loop
              break if v >= header_end
              break if raw_load_u8(data, v) != :-\s
              v += 1
            n = 0
            digit_start = v
            loop
              break if v >= header_end
              d = raw_load_u8(data, v)
              break if d < :-0
              break if d > :-9
              n = n * 10 + d - :-0
              v += 1
            if v > digit_start
              total_len = header_end - start + 4 + n ## i64
              return total_len if length - start >= total_len
              return 0
      loop
        break if p >= header_end
        break if raw_load_u8(data, p) == :-\n
        p += 1
      p++

    # No Content-Length header: a chunked transfer-encoding body is the other
    # framing servers use when the length is not known up front. A real response
    # carries exactly one of the two, so we only pay for this scan when
    # Content-Length is absent. Chunked framing sums the chunk sizes through the
    # terminating zero-length chunk; an incomplete body returns 0 (read more).
    te = raw_find_ci(data, start, header_end, "transfer-encoding:")
    if te >= 0
      value_line_end = raw_line_end(data, te, header_end)
      if raw_find_ci(data, te, value_line_end, "chunked") >= 0
        chunk_end = chunked_length_raw(data, length, header_end + 4)
        return chunk_end - start if chunk_end > 0
        return 0

    header_end - start + 4

  # ---- chunked transfer-encoding framing (RFC 7230 §4.1) ----

  # Case-insensitively compare lit.size bytes at data+pos against lit (which
  # must already be lowercase). Returns 1 on a full match, else 0.
  -> .raw_ci_eq(data, pos, lit) (i64 i64 string) i64
    lit_ptr = ccall_nobox("w_string_byte_ptr", lit)
    lit_len = ccall_nobox("w_string_byte_length", lit) ## i64
    i = 0 ## i64
    while i < lit_len
      b = raw_load_u8(data, pos + i) ## i64
      if b >= :-A && b <= :-Z
        b = b + 32
      return 0 if b != raw_load_u8(lit_ptr, i)
      i += 1
    1

  # Case-insensitive search for lit within data[from, to); index or -1.
  -> .raw_find_ci(data, from, to, lit) (i64 i64 i64 string) i64
    lit_len = ccall_nobox("w_string_byte_length", lit) ## i64
    limit = to - lit_len ## i64
    p = from ## i64
    while p <= limit
      return p if raw_ci_eq(data, p, lit) == 1
      p += 1
    -1

  # Index of the next LF (\n) in data[from, cap), or cap if none is present.
  -> .raw_line_end(data, from, cap) (i64 i64 i64) i64
    p = from ## i64
    while p < cap
      return p if raw_load_u8(data, p) == :-\n
      p += 1
    cap

  # Hex-digit value of byte c, or -1 if c is not a hex digit.
  -> .hex_digit_val(c) (i64) i64
    return c - :-0 if c >= :-0 && c <= :-9
    return c - :-a + 10 if c >= :-a && c <= :-f
    return c - :-A + 10 if c >= :-A && c <= :-F
    -1

  # Total bytes of a chunked body beginning at body_start: the absolute end
  # position one byte past the final terminating CRLF. Returns 0 when the
  # chunked body is not yet complete within data[.., length).
  -> .chunked_length_raw(data, length, body_start) (i64 i64 i64) i64
    pos = body_start ## i64
    loop
      # Parse the chunk-size line (hex digits, stopping at the first non-hex
      # byte — a ';' introducing chunk extensions or the size line's CR).
      size = 0 ## i64
      seen = 0 ## i64
      loop
        break if pos >= length
        hv = hex_digit_val(raw_load_u8(data, pos)) ## i64
        break if hv < 0
        size = size * 16 + hv
        seen += 1
        pos += 1
      return 0 if seen == 0

      # Consume the remainder of the size line up to and including its LF.
      nl = raw_line_end(data, pos, length) ## i64
      return 0 if nl >= length
      pos = nl + 1

      if size == 0
        # Last chunk: skip any trailer header lines, stopping at the blank line
        # (a bare CRLF or LF) that terminates the message.
        loop
          return 0 if pos >= length
          b = raw_load_u8(data, pos) ## i64
          if b == 13
            return 0 if pos + 1 >= length
            return pos + 2 if raw_load_u8(data, pos + 1) == :-\n
          return pos + 1 if b == :-\n
          tnl = raw_line_end(data, pos, length) ## i64
          return 0 if tnl >= length
          pos = tnl + 1

      # Data chunk: consume `size` payload bytes plus the trailing CRLF.
      chunk_end = pos + size + 2 ## i64
      return 0 if chunk_end > length
      pos = chunk_end

  # ---- latency statistics ----
  # Per-request latencies (integer tick/nanosecond counts) are summarized into
  # the distribution a benchmark reports (min/mean/max + p50/p90/p99), which the
  # man page advertises. All of `percentile`, `stat_min`, and `stat_max` take an
  # ALREADY-SORTED ascending sample array; `stat_sum`/`stat_mean` accept any
  # order. Every helper returns 0 for an empty sample so callers need no guard.

  # Nearest-rank percentile (NIST convention, as used by wrk-style reporters):
  # for percentile p in [0,100] over N sorted samples the rank is ceil(p*N/100)
  # and the p-th percentile is the 1-based sample at that rank, clamped to the
  # sample range. p<=0 yields the minimum and p>=100 the maximum. Rank is
  # computed with integer arithmetic — ceil(p*N/100) == (p*N + 99) / 100 — so the
  # result is exact with no floating-point rounding.
  -> .percentile(sorted, p)
    n = sorted.size
    return 0 if n == 0
    return sorted[0] if p <= 0
    return sorted[n - 1] if p >= 100
    rank = (p * n + 99) / 100 ## i64
    rank = 1 if rank < 1
    rank = n if rank > n
    sorted[rank - 1]

  # Smallest sample (first element of an ascending-sorted array).
  -> .stat_min(sorted)
    return 0 if sorted.size == 0
    sorted[0]

  # Largest sample (last element of an ascending-sorted array).
  -> .stat_max(sorted)
    n = sorted.size
    return 0 if n == 0
    sorted[n - 1]

  # Sum of all samples (order-independent).
  -> .stat_sum(samples)
    n = samples.size
    total = 0 ## i64
    i = 0 ## i64
    while i < n
      total += samples[i]
      i += 1
    total

  # Arithmetic mean, truncated to an integer (order-independent).
  -> .stat_mean(samples)
    n = samples.size
    return 0 if n == 0
    stat_sum(samples) / n

  -> .tungsten_connection(host, port, request_batch, pipeline, duration, total, errors) (string i64 string i64 i64)
    deadline_ticks = ccall_nobox("__w_deadline_ticks_after_seconds", duration)
    local_total = 0 ## i64
    local_errors = 0 ## i64
    fd = ccall_nobox("w_socket_connect_fd_until", host, port, deadline_ticks) ## i64
    if fd < 0
      ccall_rawargs("w_atomic_add_raw", errors, 1)
      return nil

    read_buf = ccall_nobox("w_raw_malloc", 65536) ## i64
    buffer_pos = 0 ## i64
    buffer_len = 0 ## i64
    request_ptr = ccall_nobox("w_string_byte_ptr", request_batch) ## i64
    request_len = ccall_nobox("w_string_byte_length", request_batch) ## i64

    while ccall_nobox("__w_clock_ticks_raw") < deadline_ticks
      wrote = ccall_nobox("w_socket_write_fd_until", fd, request_ptr, request_len, deadline_ticks) ## i64
      if wrote < request_len
        if ccall_nobox("__w_clock_ticks_raw") < deadline_ticks
          local_errors += 1
        ccall_rawargs("w_atomic_add_raw", total, local_total)
        ccall_rawargs("w_atomic_add_raw", errors, local_errors)
        ccall_nobox("w_socket_close_fd", fd)
        return nil
      expected = pipeline ## i64

      while expected > 0
        break if ccall_nobox("__w_clock_ticks_raw") >= deadline_ticks
        parsed = response_length_at_raw(read_buf, buffer_len, buffer_pos) ## i64
        while parsed > 0
          break if expected <= 0
          local_total += 1
          expected -= 1
          buffer_pos += parsed
          if buffer_pos >= buffer_len
            buffer_pos = 0
            buffer_len = 0
          if expected > 0
            parsed = response_length_at_raw(read_buf, buffer_len, buffer_pos)
          else
            parsed = 0

        if expected <= 0
          break

        if buffer_pos > 0
          remaining = buffer_len - buffer_pos ## i64
          if remaining > 0
            ccall_nobox("w_raw_memmove", read_buf, read_buf + buffer_pos, remaining)
          buffer_pos = 0
          buffer_len = remaining

        space = 65536 - buffer_len ## i64
        if space <= 0
          local_errors += 1
          ccall_rawargs("w_atomic_add_raw", total, local_total)
          ccall_rawargs("w_atomic_add_raw", errors, local_errors)
          ccall_nobox("w_socket_close_fd", fd)
          return nil

        chunk_len = ccall_nobox("w_socket_read_fd_until", fd, read_buf + buffer_len, space, deadline_ticks) ## i64
        if chunk_len <= 0
          if ccall_nobox("__w_clock_ticks_raw") < deadline_ticks
            local_errors += 1
          ccall_rawargs("w_atomic_add_raw", total, local_total)
          ccall_rawargs("w_atomic_add_raw", errors, local_errors)
          ccall_nobox("w_socket_close_fd", fd)
          return nil
        buffer_len += chunk_len

    ccall_rawargs("w_atomic_add_raw", total, local_total)
    ccall_rawargs("w_atomic_add_raw", errors, local_errors)
    ccall_nobox("w_socket_close_fd", fd)
    nil

  -> .run_tungsten(url, connections, duration, workers, pipeline) (string i64 i64 i64 i64)
    host = url_host(url)
    port = url_port(url)
    path = url_path(url)

    pipeline = 1 if pipeline < 1

    batch = request_batch(host, path, pipeline)

    total  = Atomic.new(0)
    errors = Atomic.new(0)

    started_ticks = ccall_nobox("__w_clock_ticks_raw") ## i64

    workers = 1 if workers < 1

    ccall("w_scheduler_install_debug_signal")
    threads = []
    base_conns = connections / workers ## i64
    extra_conns = connections % workers ## i64

    worker = 0
    while worker < workers
      worker_conns = base_conns ## i64
      if worker < extra_conns
        worker_conns += 1

      thread = spawn_worker(host, port, batch, pipeline, duration, worker_conns, total, errors)
      threads.push(thread)
      worker += 1

    i = 0
    while i < threads.size()
      thread = threads[i]
      thread.join
      i += 1

    elapsed = ccall("__w_elapsed_seconds_since_ticks", started_ticks)
    requests = total.get
    << "Tungsten Hammer experimental engine"
    << "  requests: " + requests.to_s
    << "  errors:   " + errors.get.to_s
    << "  elapsed:  " + elapsed.to_s + "s"
    << "  req/sec:  " + (requests.to_f / elapsed).to_s

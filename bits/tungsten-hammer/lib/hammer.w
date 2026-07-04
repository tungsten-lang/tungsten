# Hammer — High-performance HTTP benchmark tool

use argon

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

  -> .url_host(url)
    rest = url_without_scheme(url)
    slash = rest.index("/")
    if slash != nil
      rest = rest.slice(0, slash)
    colon = rest.index(":")
    if colon != nil
      return rest.slice(0, colon)
    rest

  -> .url_port(url) (string) i64
    if url.starts_with?("https://")
      default_port = 443
    else
      default_port = 80

    rest = url_without_scheme(url)
    slash = rest.index("/")

    if slash != nil
      rest = rest.slice(0, slash)
    colon = rest.index(":")

    return default_port if colon == nil

    rest.slice(colon + 1, rest.size - colon - 1).to_i

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

    header_end - start + 4

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

manpage = read_file(__DIR__ + "/../man/hammer.1.wd")
cli = Argon.new(manpage)
opts = cli.parse(ARGV)

if opts.flag?("help") || opts.flag?("h")
  opts.help!

url = opts.command
if !url
  << "Error: URL required"
  << ""
  opts.help!

connections = opts.get("connections")
duration    = opts.get("duration")
workers     = opts.get("workers")
pipeline    = opts.get("batch")

# Protocol: h10/1.0 → 0, h11/1.1 → 1, h2/2 → 2
proto = opts.get("protocol")
case proto
  when "h10", "1.0" then protocol = 0
  when "h11", "1.1" then protocol = 1
  when "h2", "2"    then protocol = 2
  else
    << "Unknown protocol: " + proto
    << "Supported: h10, h11, h2"
    exit(1)

forge_mode = 0
if opts.flag?("forge")
  forge_mode = 1
  pipeline = 1

max_mode = 0
if opts.flag?("max")
  max_mode = 1

if opts.flag?("tungsten")
  if protocol != 1
    << "--tungsten currently supports HTTP/1.1 only"
    exit(1)
  if forge_mode == 1
    << "--tungsten does not support --forge yet"
    exit(1)
  Hammer.run_tungsten(url, connections, duration, workers, pipeline)
else
  ccall("w_hammer_run", url, connections, duration, workers, protocol, pipeline, forge_mode, max_mode)

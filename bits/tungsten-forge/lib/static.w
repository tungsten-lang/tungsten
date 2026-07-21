# Forge::Static — static file serving with etag/cache-control
# Zero-copy sendfile for performance, automatic content-type detection

+ Static

  -> .serve(request, config)
    return nil unless config.static_dir
    return nil unless request.method == :GET || request.method == :HEAD

    path = self.safe_path(config.static_dir, request.path)
    return nil unless path && File.exist?(path) && File.file?(path)

    last_modified = File.stat(path).mtime.to_i

    etag = nil
    etag_value = nil
    if config.etag
      etag = self.compute_etag(path)
      etag_value = "\"" + etag + "\""

    # Conditional request evaluation (RFC 7232, see lib/conditional.w):
    # 304 Not Modified when the client's cached copy is still current, by
    # If-None-Match (weak comparison, tag lists, "*") or If-Modified-Since.
    if request.preconditions(etag_value, last_modified) == :not_modified
      not_modified = Response.new(status: 304, body: "")
      not_modified.header("Last-Modified", HttpDate.format(last_modified))
      not_modified.etag(etag) if etag != nil
      return not_modified

    # Build response
    response = Response.new(status: 200)
    response.content_type(self.mime_type(path))
    response.header("Last-Modified", HttpDate.format(last_modified))

    if config.cache_control
      response.header("Cache-Control", config.cache_control)

    if etag != nil
      response.etag(etag)

    if request.method == :HEAD
      response.header("Content-Length", File.size(path).to_s)
    else
      # Zero-copy sendfile when available
      response.body = File.read(path)
      response.stream = Sendfile.new(path) if Sendfile.available?

    response

  # --- Path safety ---

  -> .safe_path(root, request_path)
    # Prevent directory traversal
    normalized = File.expand_path(request_path, "/")
    full = File.join(root, normalized)

    # Try index.html for directory paths
    if File.directory?(full)
      full = File.join(full, "index.html")

    # Ensure we haven't escaped the root
    return nil unless full.start_with?(File.expand_path(root))
    full

  # --- Content type detection ---

  -> .mime_type(path)
    ext = File.extname(path).downcase
    case ext
      ".html"  => "text/html; charset=utf-8"
      ".css"   => "text/css; charset=utf-8"
      ".js"    => "application/javascript"
      ".json"  => "application/json"
      ".png"   => "image/png"
      ".jpg"   => "image/jpeg"
      ".jpeg"  => "image/jpeg"
      ".gif"   => "image/gif"
      ".svg"   => "image/svg+xml"
      ".webp"  => "image/webp"
      ".avif"  => "image/avif"
      ".ico"   => "image/x-icon"
      ".woff"  => "font/woff"
      ".woff2" => "font/woff2"
      ".ttf"   => "font/ttf"
      ".otf"   => "font/otf"
      ".pdf"   => "application/pdf"
      ".xml"   => "application/xml"
      ".txt"   => "text/plain"
      ".map"   => "application/json"
      ".wasm"  => "application/wasm"
      => "application/octet-stream"

  # --- ETag computation ---

  -> .compute_etag(path)
    stat = File.stat(path)
    Digest.md5("[stat.size]-[stat.mtime.to_i]")[0..15]

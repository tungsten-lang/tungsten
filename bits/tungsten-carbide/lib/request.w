# Carbide::Request — HTTP request wrapper
# Provides a clean interface over the raw environment hash.

in Tungsten:Carbide

+ Request
  ro :env
  ro :created_at
  ro :request_id { Random.uuid }

  -> new(@env)
    @created_at = Time.now
    @params     = nil
    @session    = nil

  # --- HTTP method ---

  -> method
    @env["REQUEST_METHOD"].to_sym

  -> get?     = method == :GET
  -> post?    = method == :POST
  -> put?     = method == :PUT
  -> patch?   = method == :PATCH
  -> delete?  = method == :DELETE
  -> head?    = method == :HEAD
  -> options? = method == :OPTIONS

  # --- URL components ---

  -> path
    @env["PATH_INFO"] || "/"

  -> query_string
    @env["QUERY_STRING"] || ""

  -> url
    "#{scheme}://#{host}#{path}"

  -> full_url
    qs = query_string
    if qs.empty? then url else "#{url}?#{qs}"

  -> scheme
    @env["HTTPS"] == "on" ? "https" : "http"

  -> host
    @env["HTTP_HOST"] || @env["SERVER_NAME"]

  -> port
    @env["SERVER_PORT"].to_i

  -> ssl?
    scheme == "https"

  # --- Headers ---

  -> headers
    @env.select(k, _v -> k.starts_with?("HTTP_"))
      self.transform_keys(k -> k.sub("HTTP_", "").downcase.gsub("_", "-"))

  -> header(name)
    key = "HTTP_#{name.upcase.gsub('-', '_')}"
    @env[key]

  -> content_type
    @env["CONTENT_TYPE"]

  -> content_length
    @env["CONTENT_LENGTH"]&.to_i

  -> user_agent
    header("User-Agent")

  -> accept
    header("Accept")

  # --- Parameters ---

  -> params
    @params ||= parse_params

  -> merge_params(extra)
    @params = params.merge(extra)

  -> parse_params
    query = QueryParser.parse(query_string)
    body  = case content_type
      /json/   => JSON.parse(body_string)
      /form/   => QueryParser.parse(body_string)
      =>         {}
    query.merge(body)

  -> body_string
    @env["rack.input"]&.read || ""

  -> body
    @env["rack.input"]

  # --- Session & cookies ---

  -> session
    @env["carbide.session"] ||= {}

  -> cookies
    @env["carbide.cookies"] ||= CookieJar.parse(@env["HTTP_COOKIE"] || "")

  -> flash
    @env["carbide.flash"] ||= {}

  # --- Client info ---

  -> ip
    @env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip || @env["REMOTE_ADDR"]

  -> xhr?
    header("X-Requested-With") == "XMLHttpRequest"

  -> format
    case accept
      /json/ => :json
      /xml/  => :xml
      /html/ => :html
      =>       :html

# Forge::ACME::Client — ACME v2 client (RFC 8555)
# Handles Let's Encrypt certificate issuance: directory, account, order, challenge, finalize

in Tungsten:Forge:ACME

+ Client
  ro :directory_url
  ro :directory
  ro :account_key
  ro :account_url
  rw :nonce

  -> new(directory: "https://acme-v02.api.letsencrypt.org/directory")
    @directory_url = directory
    @directory = nil
    @account_key = Crypto.generate_rsa_key(2048)
    @account_url = nil
    @nonce = nil

  -> fetch_directory
    response = HTTPClient.get(@directory_url)
    <! ACMEError.new("Failed to fetch directory: HTTP [response.status]") unless response.ok?

    body = response.body
    @directory = {
      new_nonce:   self.json_get(body, "newNonce"),
      new_account: self.json_get(body, "newAccount"),
      new_order:   self.json_get(body, "newOrder"),
      revoke_cert: self.json_get(body, "revokeCert"),
      key_change:  self.json_get(body, "keyChange")
    }

  -> get_nonce
    if @nonce
      n = @nonce
      @nonce = nil
      return n

    self.fetch_directory unless @directory

    response = HTTPClient.head(@directory[:new_nonce])
    nonce = response.header("replay-nonce")
    <! ACMEError.new("No replay-nonce in HEAD response") unless nonce
    nonce

  -> new_account(terms_of_service_agreed: true)
    self.fetch_directory unless @directory

    payload = "{\"termsOfServiceAgreed\":true}"
    response = self.signed_post(@directory[:new_account], payload)

    unless response.ok?
      <! ACMEError.new("Account registration failed: HTTP [response.status] — [response.body]")

    @account_url = response.header("location")
    <! ACMEError.new("No Location header in account response") unless @account_url

    @account_url

  -> new_order(identifiers:)
    self.fetch_directory unless @directory

    # Build identifiers JSON: [{"type":"dns","value":"example.com"}, ...]
    id_parts = identifiers.map -> (domain)
      "{\"type\":\"dns\",\"value\":\"" + domain + "\"}"
    id_json = "\[" + id_parts.join(",") + "\]"

    payload = "{\"identifiers\":" + id_json + "}"
    response = self.signed_post(@directory[:new_order], payload)

    unless response.ok?
      <! ACMEError.new("Order creation failed: HTTP [response.status] — [response.body]")

    body = response.body
    order_url = response.header("location")

    # Parse authorization URLs from JSON array
    authz_urls = self.json_get_array(body, "authorizations")
    finalize_url = self.json_get(body, "finalize")
    status = self.json_get(body, "status")
    cert_url = self.json_get(body, "certificate")

    Order.new(order_url, status, authz_urls, finalize_url, cert_url, identifiers)

  -> fetch_authorization(url)
    response = self.signed_post(url, "")
    <! ACMEError.new("Authorization fetch failed: HTTP [response.status]") unless response.ok?

    body = response.body
    status = self.json_get(body, "status")

    # Parse challenges array
    challenges = self.parse_challenges(body)

    # Compute key authorizations
    thumbprint = JWS.thumbprint(@account_key)
    challenges.each -> (challenge)
      challenge.set_key_authorization(thumbprint)

    Authorization.new(url, status, challenges)

  -> finalize_order(order, domains:)
    # Generate a CSR for the given domains
    csr_der = Crypto.generate_csr(@account_key, domains)
    csr64 = Base64URL.encode(csr_der)

    payload = "{\"csr\":\"" + csr64 + "\"}"
    response = self.signed_post(order.finalize_url, payload)

    unless response.ok?
      <! ACMEError.new("Order finalization failed: HTTP [response.status] — [response.body]")

    # Poll until order is ready or valid
    order_url = order.url
    status = self.json_get(response.body, "status")

    loop
      break if status == "valid"
      <! ACMEError.new("Order failed: [status]") if status == "invalid"

      Thread.sleep(2)
      poll_response = self.signed_post(order_url, "")
      status = self.json_get(poll_response.body, "status")

    cert_url = self.json_get(response.body, "certificate")
    cert_url = self.json_get(poll_response.body, "certificate") if poll_response && !cert_url

    Order.new(order_url, status, order.authorizations, order.finalize_url, cert_url, order.identifiers)

  -> download_certificate(order)
    <! ACMEError.new("No certificate URL on order") unless order.certificate_url

    response = self.signed_post(order.certificate_url, "")
    <! ACMEError.new("Certificate download failed: HTTP [response.status]") unless response.ok?

    response.body

  # --- Signed POST to ACME endpoint ---

  -> signed_post(url, payload)
    self.fetch_directory unless @directory
    nonce = self.get_nonce

    body = JWS.sign(@account_key, payload, nonce, url, kid: @account_url)
    response = HTTPClient.post(url, body: body, content_type: "application/jose+json")

    # Capture fresh nonce from response
    new_nonce = response.header("replay-nonce")
    @nonce = new_nonce if new_nonce

    response

  # --- JSON helpers (string-based extraction) ---

  -> json_get(json_string, key)
    # Find "key":"value" or "key":value in a JSON string
    return nil unless json_string

    search = "\"" + key + "\":"
    idx = json_string.index(search)
    return nil unless idx

    value_start = idx + search.size

    # Skip whitespace
    value_start += 1 while json_string[value_start] == " "

    char = json_string[value_start]

    if char == "\""
      # String value — find closing quote (handle escaped quotes)
      end_idx = value_start + 1
      loop
        break if end_idx >= json_string.size
        if json_string[end_idx] == "\\"
          end_idx += 2
        elsif json_string[end_idx] == "\""
          break
        else
          end_idx += 1
      json_string[(value_start + 1)...end_idx]
    elsif char == "{"
      # Nested object — skip for now
      nil
    elsif char == "\["
      # Array — skip (use json_get_array instead)
      nil
    else
      # Number, boolean, null — read until comma, brace, or bracket
      end_idx = value_start
      loop
        break if end_idx >= json_string.size
        c = json_string[end_idx]
        break if c == "," || c == "}" || c == "\]"
        end_idx += 1
      raw = json_string[value_start...end_idx].strip
      if raw == "null"
        nil
      elsif raw == "true"
        true
      elsif raw == "false"
        false
      else
        raw

  -> json_get_array(json_string, key)
    # Extract a JSON array of strings: "key":["v1","v2"]
    return [] unless json_string

    search = "\"" + key + "\":"
    idx = json_string.index(search)
    return [] unless idx

    start = json_string.index("\[", idx)
    return [] unless start

    end_idx = json_string.index("\]", start)
    return [] unless end_idx

    inner = json_string[(start + 1)...end_idx]
    return [] if inner.strip.size == 0

    # Split on commas and extract string values
    items = []
    parts = inner.split(",")
    parts.each -> (part)
      trimmed = part.strip
      if trimmed.starts_with?("\"") && trimmed.ends_with?("\"")
        items.push(trimmed[1...(trimmed.size - 1)])
      else
        items.push(trimmed)

    items

  -> parse_challenges(json_string)
    # Extract challenges from authorization JSON body
    # Challenges are in: "challenges":[{...},{...}]
    challenges = []

    search = "\"challenges\":"
    idx = json_string.index(search)
    return challenges unless idx

    # Find the array bounds, accounting for nested objects
    arr_start = json_string.index("\[", idx)
    return challenges unless arr_start

    # Walk through the array splitting on top-level objects
    depth = 0
    obj_start = nil
    pos = arr_start

    loop
      break if pos >= json_string.size
      char = json_string[pos]

      if char == "\["
        depth += 1
      elsif char == "\]"
        depth -= 1
        break if depth == 0
      elsif char == "{" && depth == 1
        obj_start = pos
      elsif char == "}" && depth == 1 && obj_start
        obj_json = json_string[obj_start..(pos)]

        type   = self.json_get(obj_json, "type")
        url    = self.json_get(obj_json, "url")
        token  = self.json_get(obj_json, "token")
        status = self.json_get(obj_json, "status")

        challenges.push(Challenge.new(type, url, token, status)) if type && url && token
        obj_start = nil

      pos += 1

    challenges


+ Order
  ro :url
  ro :status
  ro :authorizations
  ro :finalize_url
  ro :certificate_url
  ro :identifiers

  -> new(@url, @status, @authorizations, @finalize_url, @certificate_url, @identifiers)


+ Authorization
  ro :url
  ro :status
  ro :challenges

  -> new(@url, @status, @challenges)

  -> http01
    @challenges.select(-> (c) c.type == "http-01").first


+ Challenge
  ro :type
  ro :url
  ro :token
  ro :status
  rw :key_authorization

  -> new(@type, @url, @token, @status)
    @key_authorization = nil

  -> set_key_authorization(thumbprint)
    @key_authorization = "[@token].[thumbprint]"

  -> request_validation(client)
    client.signed_post(@url, "{}")


+ ACMEError < StandardError

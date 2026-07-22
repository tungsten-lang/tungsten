in Crypto

# SCRAM-SHA-256 client (RFC 5802 / RFC 7677), no channel binding
# (gs2 header "n,,"; the server must offer plain SCRAM-SHA-256).
#
#   s = Crypto:ScramSha256.new("", password)       # username usually ""
#   send s.client_first                            # → server
#   final = s.client_final(server_first)           # ← server-first, → server
#   s.verify_server_final(server_final)            # ← server-final: MUST be true
#
# The client nonce is injectable (third constructor argument) so the
# RFC 7677 §3 test vector is directly checkable; by default it is 18
# random bytes, base64-encoded. Passwords are used as-is (ASCII;
# SASLprep normalization is not implemented).

+ ScramSha256
  -> new(@username, @password, cnonce = nil)
    @cnonce = cnonce
    @cnonce = Base64.encode(Crypto.random_bytes(18)) if @cnonce == nil
    @gs2 = "n,,"
    @server_signature = ""

  -> client_first
    @gs2 + client_first_bare()

  -> client_first_bare
    "n=" + @username + ",r=" + @cnonce

  # Consumes the server-first-message ("r=...,s=...,i=..."), returns the
  # client-final-message. Raises on a malformed message or a server nonce
  # that does not extend the client nonce (mandatory security check).
  -> client_final(server_first)
    snonce = __attr(server_first, "r")
    salt_b64 = __attr(server_first, "s")
    iters_s = __attr(server_first, "i")
    if snonce == "" || salt_b64 == "" || iters_s == ""
      raise "SCRAM: malformed server-first message"
    if !snonce.starts_with?(@cnonce)
      raise "SCRAM: server nonce does not extend client nonce"
    salted = Crypto:PBKDF2.sha256(@password, Base64.decode(salt_b64), iters_s.to_i, 32)
    client_key = Crypto:HMAC.sha256(salted, "Client Key")
    stored_key = Crypto:SHA256.digest(client_key)
    server_key = Crypto:HMAC.sha256(salted, "Server Key")
    bare = client_first_bare()
    wo_proof = "c=" + Base64.encode(@gs2) + ",r=" + snonce
    auth_message = bare + "," + server_first + "," + wo_proof
    client_sig = Crypto:HMAC.sha256(stored_key, auth_message)
    proof = u8[32]
    j = 0
    while j < 32
      proof[j] = client_key[j] ^ client_sig[j]
      j += 1
    @server_signature = Base64.encode(Crypto:HMAC.sha256(server_key, auth_message))
    wo_proof + ",p=" + Base64.encode(proof)

  # Expected server signature (base64), available after client_final.
  -> server_signature
    @server_signature

  # True iff the server-final-message ("v=...") carries the signature only
  # the real server (holder of the stored credentials) could compute.
  -> verify_server_final(server_final)
    v = __attr(server_final, "v")
    v != "" && v == @server_signature

  # Attribute extraction: split on ',' then strip "name=" — values may
  # themselves contain '=' (base64 padding), so no split on '='.
  -> __attr(msg, name)
    parts = msg.split(",")
    prefix = name + "="
    found = ""
    i = 0
    while i < parts.size
      p = parts[i]
      if found == "" && p.starts_with?(prefix)
        pb = p.bytes
        skip = prefix.bytes.size
        rest = u8[pb.size - skip]
        k = skip
        while k < pb.size
          rest[k - skip] = pb[k]
          k += 1
        found = ccall("w_string_from_byte_array", rest)
      i += 1
    found

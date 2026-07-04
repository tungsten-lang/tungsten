# Forge::ACME::JWS — JSON Web Signature for ACME requests
# Builds JWS objects with RS256 signing for RFC 8555 compliance

in Tungsten:Forge:ACME

+ JWS
  -> .sign(key, payload, nonce, url, kid: nil)
    # Build protected header
    header = "{\"alg\":\"RS256\",\"nonce\":\"" + nonce + "\",\"url\":\"" + url + "\""

    if kid
      header = header + ",\"kid\":\"" + kid + "\""
    else
      jwk = Crypto.rsa_public_jwk(key)
      header = header + ",\"jwk\":" + jwk
    end

    header = header + "}"

    # Base64URL-encode protected header and payload
    protected64 = Base64URL.encode(header)
    payload64 = if payload == "" || payload == nil
      ""
    else
      Base64URL.encode(payload)
    end

    # Sign the message
    signing_input = protected64 + "." + payload64
    signature = Crypto.rsa_sign_sha256(key, signing_input)
    signature64 = Base64URL.encode(signature)

    # Return JWS JSON
    "{\"protected\":\"" + protected64 + "\",\"payload\":\"" + payload64 + "\",\"signature\":\"" + signature64 + "\"}"

  -> .thumbprint(key)
    # Return the key thumbprint (base64url SHA-256 of JWK)
    Crypto.rsa_thumbprint(key)

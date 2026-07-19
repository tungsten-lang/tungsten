# Forge::TLS — TLS configuration and auto-cert (Let's Encrypt)
# TLS 1.3 by default with ALPN negotiation for HTTP/2

+ TLS
  -> .build_context(config, protocols)
    ctx = SSL:Context.new

    # TLS 1.3 minimum
    ctx.min_version = :TLS1_3

    # ALPN protocols for HTTP/2 negotiation
    alpn = []
    alpn.push("h2")       if protocols.include?(:h2)
    alpn.push("http/1.1") if protocols.include?(:http11)
    ctx.alpn_protocols = alpn

    # Certificate configuration
    case config
      {auto: true} =>
        cert = AutoCert.provision(config[:domains] || [])
        ctx.certificate = cert.certificate
        ctx.private_key = cert.private_key
      {cert:, key:} =>
        ctx.certificate = SSL:Certificate.load(config[:cert])
        ctx.private_key = SSL:PrivateKey.load(config[:key])
      {enabled: false} =>
        return nil

    ctx


  # --- Let's Encrypt ACME client ---

  + AutoCert
    @@cache_dir = "tmp/certs"

    -> .cache_dir=(dir)
      @@cache_dir = dir

    -> .provision(domains)
      # Check cache first
      cached = self.load_cached(domains)
      return cached if cached && !cached.expired?

      Logger.info("Provisioning TLS certificate for: [domains.join(", ")]")

      # ACME challenge using real ACME client
      client = ACME:Client.new(
        directory: "https://acme-v02.api.letsencrypt.org/directory"
      )

      client.new_account(
        terms_of_service_agreed: true
      )

      order = client.new_order(identifiers: domains)

      # Process each authorization
      order.authorizations.each -> (auth_url)
        auth = client.fetch_authorization(auth_url)
        challenge = auth.http01
        return nil unless challenge

        # Compute key authorization and serve via challenge store
        challenge.set_key_authorization(ACME:JWS.thumbprint(client.account_key))
        ChallengeStore.set(challenge.token, challenge.key_authorization)

        # Trigger validation
        challenge.request_validation(client)

        # Poll for validation completion
        loop
          # Re-fetch authorization to check status
          auth = client.fetch_authorization(auth_url)
          challenge = auth.http01
          break if challenge.status == "valid"
          <! CertError.new("Challenge failed: [challenge.status]") if challenge.status == "invalid"
          Thread.sleep(2)

      # Finalize with CSR generated from runtime crypto
      order = client.finalize_order(order, domains: domains)

      # Download the certificate
      cert_pem = client.download_certificate(order)

      cert = CertBundle.new(
        certificate: cert_pem,
        private_key: client.account_key,
        expires_at: Time.now + 90.days
      )

      self.cache(domains, cert)
      ChallengeStore.clear
      cert

    -> .load_cached(domains)
      path = "[@@cache_dir]/[domains.first].pem"
      return nil unless File.exist?(path)
      CertBundle.load(path)

    -> .cache(domains, cert)
      Dir.mkdir_p(@@cache_dir)
      path = "[@@cache_dir]/[domains.first].pem"
      cert.save(path)


  + CertBundle
    ro :certificate
    ro :private_key
    ro :expires_at

    -> new(@certificate, @private_key, @expires_at)

    -> expired?
      Time.now > @expires_at - 30.days  # renew 30 days early

    -> save(path)
      File.write(path, self.to_pem)

    -> .load(path)
      pem = File.read(path)
      self.from_pem(pem)

  + CertError < StandardError

  + ChallengeStore
    @@tokens = {}

    -> .set(token, authorization)
      @@tokens[token] = authorization

    -> .get(token)
      @@tokens[token]

    -> .clear
      @@tokens = {}

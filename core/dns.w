# Dns — the operating system's resolver.
#
#   Dns.lookup("example.com")   # => [["93.184.215.14"], ["2606:2800:21f:cb07:6820:80da:af6b:8b2c"], 3600]
#
# lookup(host, timeout_ms = 5000) answers [IPv4 addresses, IPv6 addresses, TTL in seconds]
# (addresses as Strings; TTL 0 when the platform does not report it), [[], [], ttl] for a
# name with no addresses, or nil when no answer came in time or the resolver is
# unavailable. It blocks the calling thread (call it from a Thread to resolve many names
# at once).
#
# On macOS it asks mDNSResponder through DNS-SD over one connection kept open for the
# life of the process, so lookups follow the system's configuration: /etc/hosts, VPN and
# split-DNS scoped resolvers, search domains. Elsewhere it uses getaddrinfo.
+ Dns
  -> .lookup(host, timeout_ms = 5000)
    ccall("w_dns_lookup", host, timeout_ms)

  # Whether lookup can work on this platform (false under wasm).
  -> .available?
    ccall("w_dns_available")

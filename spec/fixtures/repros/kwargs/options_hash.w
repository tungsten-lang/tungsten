# Kwargs against a callee with NO keyword params collapse into ONE trailing
# hash argument (the `options = {}` idiom — forge Config#tls). The compiled
# engine used to strip the labels and pass the bare values positionally:
# tls(auto: true) delivered `true` instead of {auto: true}.
+ Config
  -> new
    @tls_config = {enabled: true, auto: false}
  -> tls(options = {})
    @tls_config = {enabled: true}.merge(options)
  -> tls_config
    @tls_config

c = Config.new
c.tls(auto: true)
<< "auto=" + c.tls_config[:auto].to_s()
<< "enabled=" + c.tls_config[:enabled].to_s()
c.tls(auto: true, port: 8443)
<< "auto2=" + c.tls_config[:auto].to_s()
<< "port2=" + c.tls_config[:port].to_s()

# Plain positional hash args stay untouched (the portable idiom the bits
# converged on must keep working unchanged).
c.tls({auto: false, mode: "manual"})
<< "auto3=" + c.tls_config[:auto].to_s()
<< "mode3=" + c.tls_config[:mode].to_s()

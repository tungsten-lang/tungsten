# TLS — verified client and configured-server transport facade.
#
# The runtime backend is OpenSSL when Tungsten is built with TLS=1 (or
# TUNGSTEN_TLS=1). Without that build option these methods raise a clear
# "not compiled in" error; they never fall back to an unverified connection.

+ TLS
  -> .init
  -> .load_cert(cert_path, key_path)
  -> .client_wrap(socket, hostname)

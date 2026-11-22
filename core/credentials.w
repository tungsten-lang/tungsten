# core/credentials.w — passkeys (WebAuthn) and saved web passwords through
# macOS AuthenticationServices and the Keychain (runtime/credentials.m).
#
# Load with `use core/credentials` (not autoloaded). macOS only: elsewhere
# every call raises. The bridge is linked only into programs that call it,
# and loads AuthenticationServices on the first passkey request.
#
# Passkeys (for a browser; the caller validates the RP ID against the origin
# and checks the client_data_json the system returns):
#
#   t = Credentials.webauthn({op: "get", rp_id: "example.com",
#         origin: "https://example.com", challenge: b64url, ...})
#   r = Credentials.poll(t)          # nil while the system UI is up, then a
#                                    # Hash: {ok: true, raw_id:, client_data_json:,
#                                    # authenticator_data:, signature:, ...} or
#                                    # {ok: false, error: "NotAllowedError", message:}
#   Credentials.cancel(t)
#
#   Request keys (binary values base64url without padding):
#     op            "create" or "get"
#     rp_id origin   the RP ID and the caller's origin (top_origin, cross_origin)
#     challenge
#     user          {id:, name:, display_name:}                       (create)
#     algorithms    COSE algorithm numbers, e.g. [-7, -257]          (create)
#     exclude_credentials / allow_credentials   [{id:, transports: [...]}]
#     user_verification attestation resident_key authenticator_attachment
#     extensions    {prf: {eval: {first:, second:}, eval_by_credential:},
#                    large_blob: {support: | read: | write:}, appid:}
#     immediate     prefer credentials available without other devices
#     conditional   an autofill-chosen get (allow_credentials names it) or a
#                   conditional create (macOS 15+)
#
#   Requests go to the platform provider (passkeys in Passwords / iCloud
#   Keychain and any enabled credential provider extension such as 1Password,
#   plus a phone over hybrid) and to security keys. They need the restricted
#   entitlement com.apple.developer.web-browser.public-key-credential and an
#   application identifier; without them every request answers
#   NotAllowedError at once (see Credentials.status["passkeys_unavailable_because"]).
#
#   Credentials.list_passkeys(rp_id) is a ticket for the passkeys saved for
#   an RP, {ok: true, credentials: [{name:, id:, user_handle:, rp_id:,
#   provider:}]}, for autofill (conditional mediation). The first listing
#   asks the user to let the app use passkeys.
#
# Passwords (Keychain internet passwords, kSecClassInternetPassword with the
# HTML-form authentication type, as browsers save them):
#
#   Credentials.logins("example.com")    # [{account:, server:, label:, ...}]
#                                        # attributes only: no secret, no prompt
#   Credentials.password("example.com", "me@example.com")   # may prompt
#   Credentials.save("example.com", "me@example.com", pw)   # nil, or the error
#   Credentials.forget("example.com", "me@example.com")     # true when removed
#   Credentials.strong_password          # "abcdef-ghijkm-nopqrs" style
#
#   An app with an application identifier saves to the data-protection
#   keychain (synchronizable); an ad hoc signed one to the login keychain.

+ Credentials
  -> .status
    JSON.parse(ccall("w_cred_status"))

  -> .webauthn(request)
    text = request.is_a?(String) ? request : JSON.encode(request)
    ccall("w_cred_webauthn_begin", text)

  -> .list_passkeys(rp_id)
    ccall("w_cred_list_passkeys", rp_id)

  -> .poll(ticket)
    r = ccall("w_cred_poll", ticket)
    return nil if r == nil
    JSON.parse(r)

  -> .cancel(ticket)
    ccall("w_cred_cancel", ticket)
    nil

  -> .logins(server)
    JSON.parse(ccall("w_cred_kc_find", server))

  -> .password(server, account)
    ccall("w_cred_kc_password", server, account)

  -> .save(server, account, password, label = nil, protocol = "https")
    err = ccall("w_cred_kc_save", server, account, password, label == nil ? "" : label, protocol)
    return nil if err == nil || err == ""
    err

  -> .forget(server, account)
    ccall("w_cred_kc_delete", server, account) == true

  -> .strong_password
    ccall("w_cred_strong_password")

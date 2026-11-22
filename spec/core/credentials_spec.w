# spec: compiled -- passkeys and the Keychain go through runtime/credentials.m, linked only into compiled programs
# spec: interpreter-rejects -- credentials is compiled-only
# Credentials (core/credentials.w, runtime/credentials.m): the process's
# passkey status, the refusal an unentitled process gets for a passkey
# request (at once, without UI), strong passwords, and a Keychain internet
# password round trip on a reserved .invalid host (removed again).
#
# Run:
#   bin/tungsten spec/core/credentials_spec.w

use core/credentials

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

st = Credentials.status
check("status is a Hash", st.is_a?(Hash))
check("status names the macOS version", st["macos"].is_a?(String) && st["macos"].split(".").size == 3)
check("status reports the browser entitlement", st["web_browser_entitlement"] == true || st["web_browser_entitlement"] == false)
check("status says why passkeys are unavailable, or nothing", st["passkeys_unavailable_because"].is_a?(String))

# A spec binary is signed ad hoc: no application identifier, so passkeys
# are refused at once with the reason, and nothing is shown.
if st["application_identifier"] == nil
  check("unsigned: the reason names the application identifier", st["passkeys_unavailable_because"].index("application identifier") != nil)
  t = Credentials.webauthn({op: "get", rp_id: "example.com", origin: "https://example.com", challenge: "AAECAwQFBgcICQoLDA0ODw"})
  r = Credentials.poll(t)
  check("unsigned: a get is answered at once", r != nil)
  check("unsigned: it is NotAllowedError", r["ok"] == false && r["error"] == "NotAllowedError")
  check("unsigned: a ticket is answered once", Credentials.poll(t) == nil)
  l = Credentials.list_passkeys("example.com")
  lr = Credentials.poll(l)
  check("unsigned: listing passkeys gives none", lr != nil && lr["ok"] == true && lr["credentials"].size == 0)

bad = Credentials.webauthn("not json")
br = Credentials.poll(bad)
check("a malformed request is a TypeError", br != nil && br["error"] == "TypeError")

pw = Credentials.strong_password
check("strong password has three groups of six", pw.size == 20 && pw.split("-").size == 3)
check("strong passwords differ", Credentials.strong_password != pw)

host = "tungsten-credentials-spec.invalid"
Credentials.forget(host, "spec-user")
check("no login before saving", Credentials.logins(host).size == 0)
check("save succeeds", Credentials.save(host, "spec-user", pw) == nil)
ls = Credentials.logins(host)
check("the saved login is listed", ls.size == 1 && ls[0]["account"] == "spec-user" && ls[0]["server"] == host)
check("the listing carries no secret", ls[0]["password"] == nil && JSON.encode(ls[0]).index(pw) == nil)
check("the password reads back", Credentials.password(host, "spec-user") == pw)
check("saving again updates it", Credentials.save(host, "spec-user", "second-" + pw) == nil)
check("the update reads back", Credentials.password(host, "spec-user") == "second-" + pw)
check("still one login", Credentials.logins(host).size == 1)
check("an unknown account has no password", Credentials.password(host, "nobody") == nil)
check("forget removes it", Credentials.forget(host, "spec-user") == true)
check("nothing left", Credentials.logins(host).size == 0)
check("forget again finds nothing", Credentials.forget(host, "spec-user") == false)

<< passed.get().to_s + " passed"

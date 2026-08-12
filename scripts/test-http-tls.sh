#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN_COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
TUNGSTEN_COMPILE_MODE="${TUNGSTEN_COMPILE_MODE:---no-lto}"
SPEC="$ROOT/spec/core/http_tls_socket_spec.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-http-tls.XXXXXX")"
PORT=39475
SERVER_PID=""

cleanup() {
  rc=$?
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT INT TERM

OPENSSL_BIN="${OPENSSL_BIN:-}"
if [[ -z "$OPENSSL_BIN" ]] && command -v brew >/dev/null 2>&1; then
  prefix="$(brew --prefix openssl@3 2>/dev/null || true)"
  if [[ -x "$prefix/bin/openssl" ]]; then
    OPENSSL_BIN="$prefix/bin/openssl"
  fi
fi
if [[ -z "$OPENSSL_BIN" ]]; then
  OPENSSL_BIN="$(command -v openssl || true)"
fi
if [[ -z "$OPENSSL_BIN" ]]; then
  printf 'http TLS contracts: SKIP (openssl command not found)\n'
  exit 0
fi

"$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >"$TMP/cert.log" 2>&1

TLS=1 "$TUNGSTEN_COMPILER" compile "$TUNGSTEN_COMPILE_MODE" \
  --out "$TMP/http-tls-spec" "$SPEC" \
  >"$TMP/build.log"

"$OPENSSL_BIN" s_server -quiet -www -accept "$PORT" -alpn http/1.1 \
  -cert "$TMP/cert.pem" -key "$TMP/key.pem" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!
sleep 0.25
if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
  cat "$TMP/server.log" >&2
  exit 1
fi

SSL_CERT_FILE="$TMP/cert.pem" "$TMP/http-tls-spec" "$PORT"
printf 'http TLS contracts: PASS\n'

# Naming — LLVM symbol/register transliteration shared by lowering and
# the emitter. Lives in its own module (used by BOTH towers, deduped in
# the full compiler) so `use lib/emitter` standalone — the emitter unit
# specs — is a complete program without dragging in the lowering tower.

use runtime_types

# -- LLVM symbol names --
#
# An unquoted LLVM symbol admits only [-a-zA-Z$._0-9], but a Tungsten
# identifier is UAX#31 and may hold any Unicode — `α`, `β_x`, `μ1`. Emitting
# those raw produces `%α` / `@global.α`, which clang rejects outright.
# Transliterate every character outside the LLVM set to `_uXXXXXX_`, the
# codepoint in six lowercase hex digits (enough for all of U+10FFFF).
#
# Two properties this relies on:
#
#   - Identity on names that are already LLVM-safe. The compiler's own
#     sources are pure ASCII, so stage 1 and stage 2 emit byte-identical
#     IR and the self-host fixed-point check is unaffected.
#   - Idempotent — a mangled name is itself LLVM-safe, so applying this at
#     both the lowering site and the emitter site is harmless. That is what
#     makes it safe to sprinkle at every `"%" + name` construction without
#     tracking which ones a given name already flowed through.
#
# Quoting (`%"α"`) is the other legal spelling, but register names get
# suffixed downstream (`t + ".ltag"` in render_guarded_i48), and
# `%"α".ltag` is not valid LLVM. Transliteration survives suffixing.

-> llvm_safe_char?(ch)
  if ch >= "a" && ch <= "z"
    return true
  if ch >= "A" && ch <= "Z"
    return true
  if ch >= "0" && ch <= "9"
    return true
  ch in ("_" "." "$" "-")

# True when chars[i] starts a literal `_u` + 6 lowercase hex + `_` run --
# the exact shape the escape loop below emits. Such a run in a SOURCE name
# must itself be escaped, or the mangling is not injective: `α` and the
# legal identifier `_u0003b1_` would both lower to `_u0003b1_` (observed as
# a clang "redefinition of global" error, and a silent merge for locals).
-> llvm_escape_marker_at?(chars, i)
  if i + 8 >= chars.size()
    return false
  if chars[i] != "_" || chars[i + 1] != "u"
    return false
  if chars[i + 8] != "_"
    return false
  j = i + 2
  while j < i + 8
    ch = chars[j]
    digit = ch >= "0" && ch <= "9"
    if digit == false && (ch < "a" || ch > "f")
      return false
    j += 1
  true

-> llvm_safe_name(name)
  chars = name.chars()
  i = 0
  clean = true
  while i < chars.size()
    if llvm_safe_char?(chars[i]) == false
      clean = false
      break
    if llvm_escape_marker_at?(chars, i)
      clean = false
      break
    i += 1
  if clean
    return name
  hex_chars = "0123456789abcdef"
  out = StringBuffer(name.size() + 8)
  i = 0
  while i < chars.size()
    ch = chars[i]
    if llvm_escape_marker_at?(chars, i)
      # Escape the run's leading underscore (0x5f) so the literal marker
      # text survives as data. Decoding left-to-right inverts this: the
      # emitted `_u00005f_` consumes the underscore, and the following
      # `uXXXXXX_` no longer parses as a marker.
      out << "_u00005f_"
    elsif llvm_safe_char?(ch)
      out << ch
    else
      code = ch.ord()
      out << "_u"
      shift = 20
      while shift >= 0
        out << hex_chars.slice((code >> shift) & 15, 1)
        shift -= 4
      out << "_"
    i += 1
  out.to_s()

# UTF-8 byte length of a Tungsten string (chars are codepoints).
# Shared by lowering (class-name registration) and the emitter (string
# constants); lives here so neither tower needs the other for it.
-> utf8_byte_length(s)
  n = 0
  i = 0
  chars = s.chars()
  while i < chars.size()
    ch = chars[i]
    code = ch.ord()
    if code < 128
      n += 1
    elsif code < 2048
      n += 2
    elsif code < 65536
      n += 3
    else
      n += 4
    i += 1
  n


# Inline small-string (SSO5) WValue construction — shared by lowering's
# literal/control-flow workers and the emitter.

# Compute SSO-5 WValue for a string ≤5 bytes.
-> sso5_wvalue(text)
  byte_len = utf8_byte_length(text)
  v = w_tag_stringsym + byte_len * 2
  bytes = text.bytes()
  i = 0
  while i < byte_len
    v = v + bytes[i] * (1 << (4 + 8 * i))
    i += 1
  v

# Build a static slab map: string_id → pre-computed WValue.
# SSO-5 strings (≤5 bytes) become inline i64 constants.
# Medium strings (6-61 bytes) get slab slot indices.
# Large strings (>61 bytes) keep the runtime w_string() call.
#
# `no_slab` (REPL/JIT snippets): a snippet's slab slot INDICES are relative to
# the snippet's own slab, but a JIT'd snippet runs against the HOST's already-
# initialized slab (w_slab_init_static is idempotent), so baked indices mis-
# resolve. With no_slab we skip slab assignment for 6-61 byte strings so they
# fall through to the runtime w_string() path — interned into the live host slab
# (or heap if frozen), which is correct regardless of the host's slab layout.
# SSO-5 (inline) and >61 byte (already runtime) strings are unaffected.

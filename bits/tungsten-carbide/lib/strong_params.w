# Carbide::StrongParams — mass-assignment protection for controllers.
#
# Rails' cornerstone controller-security feature: never hand raw request
# params straight to a model, because a client could smuggle in keys the
# action never meant to accept (:id, :admin, :account_id, …). StrongParams
# wraps a params hash and hands back only an explicit allow-list of keys.
#
#   # in a controller action, params = {post: {title: "hi", admin: true}}
#   attrs = strong_params.require(:post).permit([:title, :body])
#   # => {title: "hi"}   — :admin was never allowed, so it is dropped
#   Model.create(Post, attrs)
#
# Rails writes `params.require(:post).permit(:title, :body)`. Carbide takes
# the allow-list as an explicit ARRAY (`permit([:title, :body])`) rather
# than a vararg splat: carbide's whole surface avoids varargs/kwargs so the
# self-hosted interpreter and the compiled binary behave identically (the
# same choice route.w/model.w make with options hashes). `permit` returns a
# plain filtered hash — ready to feed straight into Model.create/update,
# which take attribute hashes — so the sanitized result stays in the same
# hash currency as the rest of carbide, while `require` returns a fresh
# StrongParams so require/permit chains.
#
# Design notes (constraints verified by probe on BOTH engines):
#   - Allow-listing is by key PRESENCE (has_key?), not by non-nil value: a
#     permitted key that is present with a nil/false value is kept, and an
#     absent key is simply omitted (it never becomes an explicit nil). This
#     matches Rails and keeps permit a pure projection of the source keys.
#   - `require(key)` fetches a nested params hash (the model-scoped form
#     Rails expects, e.g. params[:post]). A missing key, or a value that is
#     not a Hash, yields an EMPTY StrongParams rather than raising — no
#     raise/rescue (exception flow diverges between engines), and a
#     following permit then simply returns {}. Callers that must distinguish
#     "absent" can check `key?` first.
#   - Keys are symbols ({post: {...}}). Normalize string keys (e.g. from a
#     JSON body) at the boundary with key.to_sym before wrapping, exactly as
#     Model does with its attributes.
#   - No early `return`, flag-style flow: an early return from a
#     closure-bearing method corrupts the self-hosted interpreter (same
#     caution as controller.w/model.w/route.w).
#
# Top-level (no `in` namespace): namespaced bit classes are unreachable from
# consumers and specs — same convention as route.w / controller.w / model.w.

+ StrongParams
  # The underlying params hash (symbol-keyed).
  ro :to_h

  -> new(source = {})
    seed = source
    if seed == nil
      seed = {}
    @to_h = seed

  # Value for a key (like params[key]); nil when absent.
  -> get(key)
    @to_h[key]

  # Is this key present? (present-with-nil counts as present.)
  -> key?(key)
    @to_h.has_key?(key)

  # require(:post) -> a StrongParams over the nested params hash. A missing
  # key or a non-Hash value yields an EMPTY StrongParams (nil-safe, never
  # raises), so `require(:x).permit([...])` returns {} instead of crashing.
  -> require(key)
    nested = @to_h[key]
    inner = {}
    if type(nested) == "Hash"
      inner = nested
    StrongParams.new(inner)

  # permit([:a, :b]) -> a new hash containing ONLY the allow-listed keys that
  # are present in the source. Every other key (including dangerous ones the
  # client tried to inject) is dropped. This is the sanitized attribute hash
  # to pass to Model.create/update.
  -> permit(keys)
    out = {}
    src = @to_h
    list = keys
    if list == nil
      list = []
    list.each -> (k)
      if src.has_key?(k)
        out[k] = src[k]
    out

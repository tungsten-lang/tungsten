# runtime/proto — the object protocol on any JS object value.
#
# JS arrays are flagged core Arrays (array.w), which cannot carry methods, so code that
# may meet an array calls these instead of the JS:Base methods of the same names. Each
# is the array implementation or the method.

in JS

-> jget(o, k, receiver = JS_HOLE)
  return js_array_get(o, k, receiver) if js_array?(o)
  return JS_DOM_HOOK[0].get(o, k, receiver == JS_HOLE ? o : receiver) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.get(k, receiver == JS_HOLE ? o : receiver)

-> jset(o, k, v, receiver = JS_HOLE)
  if js_array?(o)
    return js_array_proto_set(o, k, v, receiver) if receiver != JS_HOLE && !js_ident?(receiver, o)
    return js_array_set(o, k, v)
  return JS_DOM_HOOK[0].set(o, k, v, receiver == JS_HOLE ? o : receiver) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.set(k, v, receiver == JS_HOLE ? o : receiver)

-> jput(o, k, v)
  if js_array?(o)
    js_array_set(o, k, v)
    return v
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    JS_DOM_HOOK[0].put_own(o, k, v)
    return v
  o.put_own(k, v)

-> jdefine(o, k, v, flags = ATTR_DEFAULT)
  return js_array_define(o, k, v, flags) if js_array?(o)
  return JS_DOM_HOOK[0].define(o, k, v, flags) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.define(k, v, flags)

-> jget_own(o, k)
  return js_array_get_own(o, k) if js_array?(o)
  return JS_DOM_HOOK[0].get_own(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.get_own(k)

-> jhas_own?(o, k)
  return js_array_has_own?(o, k) if js_array?(o)
  return JS_DOM_HOOK[0].has_own?(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.has_own?(k)

-> jown_keys(o)
  return js_array_own_keys(o) if js_array?(o)
  return JS_DOM_HOOK[0].own_keys(o) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.own_keys

-> jdelete(o, k)
  return js_delete(o, k, false) if js_array?(o)
  return JS_DOM_HOOK[0].delete_own(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.delete_own(k)

-> jget_own_property(o, k)
  return js_array_get_own_property(o, k) if js_array?(o)
  return JS_DOM_HOOK[0].get_own_property(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.get_own_property(k)

-> jdefine_own_property(o, k, d)
  return js_array_define_own_property(o, k, d) if js_array?(o)
  return JS_DOM_HOOK[0].define_own_property(o, k, d) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.define_own_property(k, d)

# The prototype as JS sees it (JS_NULL for none).
-> jget_prototype_of(o)
  if js_array?(o)
    p = js_array_proto(o)
    return p == nil ? JS_NULL : p
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    p = JS_DOM_HOOK[0].proto(o)
    return p == nil ? JS_NULL : p
  o.get_prototype_of

-> jproto(o)
  return js_array_proto(o) if js_array?(o)
  return JS_DOM_HOOK[0].proto(o) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.proto

-> jset_prototype_of(o, p)
  return js_array_set_proto(o, p) if js_array?(o)
  return JS_DOM_HOOK[0].set_prototype_of(o, p) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.set_prototype_of(p)

-> jextensible?(o)
  return (js_array_flags(o) & JS_AF_EXT) == 0 || js_array_ext(o, false).is_extensible? if js_array?(o)
  return JS_DOM_HOOK[0].is_extensible?(o) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.is_extensible?

-> jprevent_extensions(o)
  return js_array_ext(o, true).prevent_extensions if js_array?(o)
  return JS_DOM_HOOK[0].prevent_extensions(o) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.prevent_extensions

-> jhas_property?(o, k)
  if js_array?(o)
    return true if js_array_has_own?(o, k)
    p = js_array_proto(o)
    return p != nil && jhas_property?(p, k)
  return JS_DOM_HOOK[0].has_property?(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.has_property?(k)

-> jenumerable?(o, k)
  if js_array?(o)
    d = js_array_get_own_property(o, k)
    return d != nil && d.enumerable == true
  return JS_DOM_HOOK[0].enumerable?(o, k) if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
  o.enumerable?(k)

-> jcallable?(o)
  js_callable?(o)

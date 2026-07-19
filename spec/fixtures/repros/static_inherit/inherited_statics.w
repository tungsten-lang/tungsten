# Inherited class methods (statics): `+ Post < Model` must resolve
# `Post.create(...)` to Model's `-> .create` — compiled AND interpreted —
# with the ORIGINAL receiver as the method's class context, so `class.new`
# inside the inherited body instantiates the subclass the call was made on
# (proven by the overridden instance `tag`). Covers a 2-level chain
# (Comment < Post < Model) and a class-method override (`.kind`).
#
# Compiled resolution: compile-time superclass walk in
# compiler/lib/lowering/method_call.w (known_static_methods walk-up via
# class_super_names) + runtime superclass walk in w_static_method_lookup
# (runtime/runtime.c) for the dynamic-dispatch path.
+ Model
  -> .create(attrs)
    m = class.new
    m.fill(attrs)
    m

  -> .kind
    "model"

  -> fill(attrs)
    @attrs = attrs

  -> describe
    "attrs=" + @attrs.to_s()

  -> tag
    "model-instance"

+ Post < Model
  -> .kind
    "post"

  -> tag
    "post-instance"

+ Comment < Post
  -> tag
    "comment-instance"

p = Post.create("hello")
<< "post:" + p.describe()
<< "post-tag:" + p.tag()
<< "post-kind:" + Post.kind()
<< "model-kind:" + Model.kind()
c = Comment.create("deep")
<< "comment:" + c.describe()
<< "comment-tag:" + c.tag()
<< "comment-kind:" + Comment.kind()

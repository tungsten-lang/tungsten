# Carbide strong-parameter specs — mass-assignment protection.
#
# StrongParams allow-lists request params before they reach a model, the
# Rails discipline of never handing raw client input to Model.create. The
# unit specs cover the StrongParams wrapper directly; the controller specs
# cover the strong_params/permit integration and the create-loop use case
# that makes the feature worth having. Pure logic, no sockets — identical
# on both engines.
# Run: bin/tungsten bits/tungsten-carbide/spec/strong_params_spec.w

use spec
use carbide

# A controller that permits a nested model form (Rails: params.require).
+ AccountsController < Controller
  -> signup
    strong_params.require(:account).permit([:email, :password])

# A controller that allow-lists flat top-level params.
+ WidgetsController < Controller
  -> create_attrs
    permit([:name])

# A bare model to prove permit blocks mass-assignment end to end.
+ Widget < Model
  -> table
    "widgets"

-> mk(klass, params)
  request = Request.new({method: "POST", path: "/x"})
  request.params = params
  klass.new(request)

describe "StrongParams" ->
  describe "permit" ->
    it "keeps only the allow-listed keys that are present" ->
      sp = StrongParams.new({title: "hi", body: "b", id: 9})
      out = sp.permit([:title, :body])
      expect(out[:title]).to eq("hi")
      expect(out[:body]).to eq("b")

    it "drops keys the client tried to inject but were not allow-listed" ->
      sp = StrongParams.new({title: "hi", id: 9, admin: true})
      out = sp.permit([:title])
      expect(out.has_key?(:id)).to eq(false)
      expect(out.has_key?(:admin)).to eq(false)

    it "omits an absent allow-listed key (never fabricates a nil)" ->
      sp = StrongParams.new({title: "hi"})
      out = sp.permit([:title, :body])
      expect(out.has_key?(:body)).to eq(false)

    it "keeps a present allow-listed key even when its value is nil" ->
      sp = StrongParams.new({title: nil, body: "b"})
      out = sp.permit([:title, :body])
      expect(out.has_key?(:title)).to eq(true)

    it "returns an empty hash for a nil keys list" ->
      sp = StrongParams.new({title: "hi"})
      expect(sp.permit(nil).has_key?(:title)).to eq(false)

  describe "require" ->
    it "returns a StrongParams over the nested params hash" ->
      sp = StrongParams.new({post: {title: "hi", secret: "x"}})
      out = sp.require(:post).permit([:title])
      expect(out[:title]).to eq("hi")
      expect(out.has_key?(:secret)).to eq(false)

    it "yields an empty StrongParams for a missing key (nil-safe, no raise)" ->
      sp = StrongParams.new({post: {title: "hi"}})
      out = sp.require(:comment).permit([:title])
      expect(out.has_key?(:title)).to eq(false)

    it "yields an empty StrongParams when the value is not a hash" ->
      sp = StrongParams.new({post: "not-a-hash"})
      out = sp.require(:post).permit([:title])
      expect(out.has_key?(:title)).to eq(false)

  describe "accessors" ->
    it "reads a value with get and reports presence with key?" ->
      sp = StrongParams.new({a: 1})
      expect(sp.get(:a)).to eq(1)
      expect(sp.get(:missing)).to be_nil
      expect(sp.key?(:a)).to eq(true)
      expect(sp.key?(:missing)).to eq(false)

    it "treats a nil source as an empty params hash" ->
      sp = StrongParams.new(nil)
      expect(sp.permit([:x]).has_key?(:x)).to eq(false)
      expect(sp.key?(:x)).to eq(false)

describe "Controller strong parameters" ->
  it "exposes strong_params wrapping the request params" ->
    c = mk(AccountsController, {account: {email: "a@b"}})
    expect(c.strong_params.get(:account)[:email]).to eq("a@b")

  it "permits a nested model form via require(...).permit(...)" ->
    params = {account: {email: "a@b", password: "pw", role: "admin"}, csrf: "t"}
    c = mk(AccountsController, params)
    out = c.signup
    expect(out[:email]).to eq("a@b")
    expect(out[:password]).to eq("pw")
    expect(out.has_key?(:role)).to eq(false)

  it "allow-lists flat top-level params with the controller permit shortcut" ->
    c = mk(WidgetsController, {name: "ok", id: 999})
    out = c.create_attrs
    expect(out[:name]).to eq("ok")
    expect(out.has_key?(:id)).to eq(false)

  it "blocks mass-assignment of injected keys through the create loop" ->
    Model.reset_all
    c = mk(WidgetsController, {name: "ok", id: 999, admin: true})
    widget = Model.create(Widget, c.create_attrs)
    expect(widget.get(:name)).to eq("ok")
    expect(widget.get(:admin)).to be_nil
    expect(widget.get(:id)).to be_nil
    expect(widget.id).to eq(1)
    Model.reset_all

spec_summary

use Tungsten:Spec

describe %class_name%View ->
  let :view, %class_name%View.new

  describe "#view_locals" ->
    it "returns a hash of template data" ->
      locals = view.view_locals
      expect(locals).to be_a(Hash)

  describe "#render" ->
    it "renders the template" ->
      html = view.render
      expect(html).to be_a(String)
      expect(html).to_not be_empty

  describe "with custom locals" ->
    let :view, %class_name%View.new(locals: {custom: "value"})

    it "merges custom locals into view_locals" ->
      expect(view.view_locals[:custom]).to eq("value")

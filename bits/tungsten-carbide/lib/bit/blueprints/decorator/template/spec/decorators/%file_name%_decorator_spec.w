use Tungsten:Spec

describe %class_name%Decorator ->
  let :%file_name%, create(:%file_name%)
  let :decorator, %class_name%Decorator.new(%file_name%)

  describe "#created_date" ->
    it "formats the creation date" ->
      expect(decorator.created_date).to match(/\w+ \d{2}, \d{4}/)

  describe "#summary" ->
    it "truncates long text" ->
      expect(decorator.summary(length: 10).size).to be_lte(14)

  describe "delegation" ->
    it "delegates unknown methods to the wrapped object" ->
      expect(decorator.id).to eq(%file_name%.id)

  describe ".decorate_collection" ->
    it "wraps each item in the collection" ->
      items = create_list(:%file_name%, 3)
      decorated = %class_name%Decorator.decorate_collection(items)
      expect(decorated.size).to eq(3)
      expect(decorated.first).to be_a(%class_name%Decorator)

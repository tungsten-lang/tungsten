use Tungsten:Spec

describe %class_name%Lookup ->
  describe "#call" ->
    it "returns results from the given scope" ->
      scope = MockScope.new([1, 2, 3])
      lookup = %class_name%Lookup.new(scope: scope)
      expect(lookup.call).to_not be_empty

    it "applies pagination when page param is given" ->
      scope = MockScope.new((1..100).to_a)
      lookup = %class_name%Lookup.new(scope: scope, params: {page: 1, per_page: 10})
      results = lookup.call
      expect(results.size).to be_lte(10)

    it "applies ordering when order_by param is given" ->
      scope = MockScope.new([3, 1, 2])
      lookup = %class_name%Lookup.new(scope: scope, params: {order_by: :id, order_dir: :asc})
      results = lookup.call
      expect(results).to eq([1, 2, 3])

  describe ".call" ->
    it "provides a class-level shortcut" ->
      scope = MockScope.new([1, 2])
      results = %class_name%Lookup.call(scope: scope)
      expect(results).to_not be_empty

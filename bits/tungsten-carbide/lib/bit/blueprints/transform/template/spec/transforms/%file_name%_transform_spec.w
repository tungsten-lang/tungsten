use Tungsten:Spec

describe %class_name%Transform ->
  describe "#call" ->
    it "transforms the input data" ->
      input = [{name: "test"}]
      result = %class_name%Transform.new(input).call
      expect(result).to_not be_nil

    it "raises on nil input" ->
      expect ->
        %class_name%Transform.new(nil).call
      self.to raise_error(ArgumentError)

  describe ".call" ->
    it "provides a class-level shortcut" ->
      input = [{name: "test"}]
      result = %class_name%Transform.call(input)
      expect(result).to_not be_nil

  describe "pipeline composition" ->
    it "works with the pipe operator" ->
      input = [{name: "test"}]
      result = input |> %class_name%Transform
      expect(result).to_not be_nil

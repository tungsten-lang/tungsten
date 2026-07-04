use Tungsten:Spec

describe %class_name%Serializer ->
  let :%file_name%, create(:%file_name%)
  let :serializer, %class_name%Serializer.new(%file_name%)

  describe "#as_json" ->
    let :json, serializer.as_json

    it "includes the id" ->
      expect(json[:id]).to eq(%file_name%.id)

    # it "includes declared attributes" ->
    #   expect(json[:name]).to eq(%file_name%.name)

  describe "#to_json" ->
    it "returns a JSON string" ->
      result = serializer.to_json
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed["id"]).to eq(%file_name%.id)

  describe ".serialize" ->
    it "serializes a collection" ->
      items = create_list(:%file_name%, 3)
      json = %class_name%Serializer.serialize(items)
      expect(json.size).to eq(3)
      expect(json.first[:id]).to_not be_nil

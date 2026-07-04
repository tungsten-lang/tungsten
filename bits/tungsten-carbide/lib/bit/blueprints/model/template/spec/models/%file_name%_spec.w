use Tungsten:Spec

describe %class_name% ->
  describe "validations" ->
    it "is valid with valid attributes" ->
      %file_name% = build(:%file_name%)
      expect(%file_name%.valid?).to be_true

    # it "requires a name" ->
    #   %file_name% = build(:%file_name%, name: "")
    #   expect(%file_name%.valid?).to be_false

  describe "associations" ->
    pending "add association specs as needed"

  describe "#save" ->
    it "persists to the database" ->
      %file_name% = build(:%file_name%)
      expect(%file_name%.save).to be_true
      expect(%file_name%.persisted?).to be_true

    it "assigns an id" ->
      %file_name% = create(:%file_name%)
      expect(%file_name%.id).to_not be_nil

  describe ".find" ->
    it "retrieves a record by id" ->
      %file_name% = create(:%file_name%)
      found = %class_name%.find(%file_name%.id)
      expect(found.id).to eq(%file_name%.id)

  describe "#destroy" ->
    it "removes the record" ->
      %file_name% = create(:%file_name%)
      %file_name%.destroy
      expect(%file_name%.persisted?).to be_false

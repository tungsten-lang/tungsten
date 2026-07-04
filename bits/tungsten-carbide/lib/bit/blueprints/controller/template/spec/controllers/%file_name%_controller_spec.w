use Tungsten:Spec
use Tungsten:Spec:Carbide

describe %class_name%Controller ->
  describe "GET #index" ->
    it "returns a successful response" ->
      get "/%name%"
      expect(response.status).to eq(200)

  describe "GET #show" ->
    it "returns the requested %file_name%" ->
      %file_name% = create(:%file_name%)
      get "/%name%/#{%file_name%.id}"
      expect(response.status).to eq(200)

  describe "POST #create" ->
    it "creates a new %file_name% with valid params" ->
      expect ->
        post "/%name%", %file_name%: valid_attributes
      self.to change(%class_name%.count).by(1)

    it "rejects invalid params" ->
      post "/%name%", %file_name%: invalid_attributes
      expect(response.status).to eq(422)

  describe "PATCH #update" ->
    it "updates the %file_name%" ->
      %file_name% = create(:%file_name%)
      patch "/%name%/#{%file_name%.id}", %file_name%: {name: "Updated"}
      expect(%file_name%.reload.name).to eq("Updated")

  describe "DELETE #destroy" ->
    it "removes the %file_name%" ->
      %file_name% = create(:%file_name%)
      expect ->
        delete "/%name%/#{%file_name%.id}"
      self.to change(%class_name%.count).by(-1)

  -> valid_attributes
    {name: "Test %class_name%"}

  -> invalid_attributes
    {name: ""}

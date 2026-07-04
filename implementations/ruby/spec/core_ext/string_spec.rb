require "tungsten/core_ext/string"

describe String do
  describe "#underscore" do
    it "replaces scope operators (::)" do
      expect("Tungsten::AST::String".underscore).to eq "tungsten/ast/string"
    end

    it "handles acryonym prefixes" do
      expect("HTTPClient".underscore).to eq "http_client"
    end

    it "handles prefixes with numbers" do
      expect("SHA256Hash".underscore).to eq "sha256_hash"
    end

    it "handles prefixes which are only numbers" do
      expect("64Bit".underscore).to eq "64_bit"
    end

    it "handles camel-cased words" do
      expect("isNumber".underscore).to eq "is_number"
    end

    it "handles multiple camel-cased words" do
      expect("componentDidUpdate".underscore).to eq "component_did_update"
    end

    it "replaces hyphens" do
      expect('test-string'.underscore).to eq "test_string"
    end
  end
end

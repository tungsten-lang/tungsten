# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Tungsten::ExampleExpectations do
  describe ".parse" do
    it "parses stdout, stderr, stdin, exit, and timeout directives" do
      source = <<~W
        puts("hello")

        ## expect stdin
        ## alpha
        ## beta
        ## expect stdout
        ## hello
        ## expect stderr
        ## warning
        ## expect exit 3
        ## expect timeout 9
      W

      expectation = described_class.parse(source)

      expect(expectation.stdin).to eq("alpha\nbeta\n")
      expect(expectation.stdout).to eq("hello\n")
      expect(expectation.stderr).to eq("warning\n")
      expect(expectation.exit_status).to eq(3)
      expect(expectation.timeout_seconds).to eq(9)
    end

    it "parses skip directives" do
      source = <<~W
        puts("hello")

        ## expect skip external dependency
      W

      expectation = described_class.parse(source)
      expect(expectation.skip?).to eq(true)
      expect(expectation.skip_reason).to eq("external dependency")
    end

    it "raises when the trailer is missing" do
      expect { described_class.parse("puts(1)\n") }.to raise_error(Tungsten::ExampleExpectations::ParseError, /missing/)
    end
  end

  describe ".output_mismatch" do
    it "accepts exact output matches" do
      expect(described_class.output_mismatch("alpha\nbeta\n", "alpha\nbeta\n")).to be_nil
    end

    it "lets a standalone ellipsis absorb intermediate lines" do
      expected = <<~OUT
        alpha
        ...
        omega
      OUT

      actual = <<~OUT
        alpha
        beta
        gamma
        omega
      OUT

      expect(described_class.output_mismatch(expected, actual)).to be_nil
    end

    it "treats blank lines adjacent to ellipsis as formatting only" do
      expected = <<~OUT
        alpha

        ...

        omega
      OUT

      actual = <<~OUT
        alpha
        beta

        gamma
        omega
      OUT

      expect(described_class.output_mismatch(expected, actual)).to be_nil
    end

    it "fails when the post-ellipsis anchor never appears" do
      mismatch = described_class.output_mismatch("alpha\n...\nomega\n", "alpha\nbeta\ngamma\n")

      expect(mismatch).to include("expected output to match embedded expectation")
    end
  end
end

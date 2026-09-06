# frozen_string_literal: true

require "tungsten"

RSpec.describe "Hash freezing" do
  it "freezes aliases and nested hashes, including cycles through arrays" do
    expect(Tungsten.run(<<~W)).to eq(true)
      child = {"x" => 1}
      h = {"children" => [child]}
      alias_h = h
      h["self"] = h
      h.freeze()
      alias_h.frozen?() && child.frozen?()
    W
  end

  it "rejects overwrites and no-op mutations" do
    ["h[\"x\"] = 2", "h.delete(\"absent\")", "h.merge!({})"].each do |mutation|
      expect { Tungsten.run("h = {\"x\" => 1}\nh.freeze()\n#{mutation}") }.to raise_error(Tungsten::Error, /frozen/)
    end
  end

  it "allows Tungsten rescue blocks to catch frozen mutations" do
    expect(Tungsten.run(<<~W)).to eq(true)
      h = {"x" => 1}
      h.freeze()
      begin
        h["x"] = 2
      rescue error
        error.include?("frozen")
    W
  end
end

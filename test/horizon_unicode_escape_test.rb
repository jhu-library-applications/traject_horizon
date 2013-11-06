# Encoding: UTF-8

require 'test_helper'

require 'traject'
require 'traject/horizon_reader'

describe "turning weird Horizon escape sequences into unicode" do
  describe "convert_text" do
    before do
      @reader = Traject::HorizonReader.new(nil, {"horizon.host" => "example.com", "horizon.user" => "dummy"})
    end

    it "converts" do
      converted = @reader.convert_text!("A hangul character: <U+1112>, okay<!> U+1000>", org.marc4j.ErrorHandler.new)
      assert_equal "A hangul character: ᄒ, okay<!> U+1000>", converted
    end

    it "converts rlm" do
      converted = @reader.convert_text!("Weird &#x200F; but these aren't changed #x2000; &#200F etc.", org.marc4j.ErrorHandler.new)
      assert_equal "Weird \u200F but these aren't changed #x2000; &#200F etc.", converted
    end

  end

end
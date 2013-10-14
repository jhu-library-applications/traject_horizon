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
      converted = @reader.convert_text!("A hangul character: <U+1112>, okay<!>", org.marc4j.ErrorHandler.new)
      assert_equal "A hangul character: ᄒ, okay<!>", converted
    end

  end

end
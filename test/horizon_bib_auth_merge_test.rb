# Encoding: ASCII-8BIT

require 'test_helper'

require 'traject'
require 'traject/horizon_bib_auth_merge'

describe "HorizonBibAuthMerge" do
  HzMerge = Traject::HorizonBibAuthMerge # shortcut

  it "does simple example" do
    assert_equal "aOsmoregulationvCongresses.", HzMerge.new("650", "a v.", "aOsmoregulationvCongresses.").merge!
  end

  it "adds on simple trailing punctuation" do
    assert_equal "aHomeostasisvCongresses.", HzMerge.new("650", "a v.", "aHomeostasisvCongresses").merge!
  end

  it "handles weirder punctuation" do
    assert_equal "aEastaugh, Steven R.,d1952-", HzMerge.new("100", "a.,d-", "aEastaugh, Steven R.,d1952-").merge!
  end

  it "merges non-controlled values" do
    assert_equal "aNational League for Nursing publication ;vno. 52-1870.", HzMerge.new("830", "a ;vno. 52-1870.", "aNational League for Nursing publication ;").merge!
  end

  it "handles multiple templated subfield with same code" do
    assert_equal "aMedical carexUtilizationzMarylandzBaltimore.", HzMerge.new("650", "a x z z.", "aMedical carexUtilizationzMarylandzBaltimore.").merge!
  end

  it "handles tag 240 weirdness" do
    assert_equal "aProblemy radiaÙtýsionnoµi genetiki.lEnglish", HzMerge.new("240", "a.l ", "aDubinin, Nikolaµi Petrovich,d1907-1998.tProblemy radiaÙtýsionnoµi genetiki.lEnglish").merge!
  end

  it "preserves space before semi-colon in 830" do
    # this is actually something Alpha-G's HznExportMarc does differently
    # than HIP/Horizon -- we try to stick with HIP/Horizon, not entirely
    # sure if this is a bug in HIP we're reproducing, maybe there shouldn't
    # be space before the semi-colon? 
    assert_equal "aActa ophthalmologica.pSupplementum ;v81.", HzMerge.new("830", "a.p ;v81.", "aActa ophthalmologica.pSupplementum").merge!
  end

  it "handles non-matching ending punct" do
    # Yes, current HIP behavior, as well as marcout and HznMarcOut, ends in
    # period. I don't know if it's really right, but we'll match current behavior.
    assert_equal "aWessel, Rosa,d1897.", HzMerge.new("100", "a,d.", "aWessel, Rosa,d1897-").merge!
  end

  it "a weird non-matching ending punct" do
    # in this one, HIP and Alpha-G HznMarcOut actually didn't match! We go with HIP.
    assert_equal "aGreat Britain.bParliament.tPapers by Command ;vCd. 4671.", HzMerge.new("810", "a.b.t ;vCd. 4671.", "aGreat Britain.bParliament.tPapers by Command.").merge!
  end

  it "handles weird internal multi punct with spaces" do
    assert_equal "aMiscellaneous publications (Pan American Sanitary Bureau) ;vno. 79.", HzMerge.new("830", "a) ;vno. 79.", "aMiscellaneous publications (Pan American Sanitary Bureau) ;").merge!
  end

  it "handles extra literals in authtext" do
    assert_equal "aKapsperger, Giovanni Girolamo,d1580-1651.tArie passeggiate.nlibro 1.pUltimi miei sospiri.", 
      HzMerge.new("700", "a,d.t.", "aKapsperger, Giovanni Girolamo,d1580-1651.tArie passeggiate,nlibro 1.pUltimi miei sospiri.").merge!
  end

end
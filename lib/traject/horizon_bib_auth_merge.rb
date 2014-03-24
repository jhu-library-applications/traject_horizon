module Traject

  # Merges 'bib text' and 'auth text' lines from Horizon, using bib text as
  # template when neccesary.
  #
  #     merged_str = HorizonBibAuthMerge.new(tag, bib_text_str, auth_text_str).merge!
  #
  # Strings passed in may be mutated for efficiency. So you can only call merge! once, it's just
  # utility.
  class HorizonBibAuthMerge
    attr_reader :bibtext, :authtext, :tag

    # Pass in bibtext and authtext as String -- you probably need to get
    # column values from JDBC as bytes and then use String.from_java_bytes
    # to avoid messing up possible Marc8 encoding.
    #
    # bibtext is either text or longtext column from fullbib, preferring
    # longtext.  authtext is either xref_text or xref_longtext from fullbib,
    # preferring xref_longtext.
    def initialize(tag, bibtext, authtext)
      @merged = false

      @tag      = tag
      @bibtext  = bibtext
      @authtext = authtext

      # remove terminal MARC Field Terminator if present.
      @bibtext.chomp!("\x1E") if @bibtext
      @authtext.chomp!("\x1E") if @authtext
    end

    # Returns merged string, composed of a marc 'field', with subfields
    # seperated by seperator control chars. Does not include terminal
    # MARC Field Seperator.
    #
    # Will mutate bibtext and authtext for efficiency.
    def merge!
      raise Exception.new("Can only call `merge!` once, already called.") if @merged
      @merged = true

      # just one? (Or neither?) Just return it.
      return authtext if bibtext.nil?
      return bibtext  if authtext.nil?



      # We need to do a crazy combination of template in text with values in authtext.
      # horizon, you so crazy. text template is like:
      #"\x1Fa.\x1Fp ;\x1Fv81."
      # which means each subfield after the \x1F, merge in
      # the subfield value from the auth record if it's present,
      # otherwise don't.
      #
      # plus some weird as hell stuff with punctuation and spaces, I can't
      # even explain it, just trial and error'd it comparing to marcout.
      bibtext.gsub!(/\x1F([^\x1F\x1E])( ?)([[:punct:] ]*)/) do

        subfield       = $1
        space          = $2
        maybe_punct    = $3


        # okay this is crazy hacky reverse engineering, I don't really
        # know what's going on but for 240 and 243, 'a' in template
        # is filled by 't' in auth tag.
        auth_subfield = if subfield == "a" && (tag == "240" || tag == "243")
          "t"
        else
          subfield
        end

        # Find substitute fill-in value from authtext, if it can
        # be found -- first subfield indicated. Then we REMOVE
        # it from authtext, so next time this subfield is asked for,
        # subsequent subfield with that code will be used.
        substitute = nil
        authtext.sub!(/\x1F#{Regexp.escape auth_subfield}([^\x1F\x1E]*)/) do
          substitute = $1
          ''
        end

        if substitute


          # Dealing with punctuation is REALLY CONFUSING -- reverse engineering
          # HIP/Horizon, which does WEIRD THINGS.
          # But we seem to have arrived at something that appears to match all cases
          # we can find of what HIP/Horizon does.
          #
          # If the auth value already ends up with the same punctuation from the template,
          # _leave it alone_ -- including preserving all spaces near the punct in the auth
          # value.
          #
          # Otherwise, remove all punct from the auth value, then add in the punct from the template,
          # along with any spaces before the punct in the template.
          if maybe_punct && maybe_punct.length > 0
            # remove all punctuation from end of auth value? to use punct from template instead?
            # But preserve initial spaces from template? Unless it already ends
            # with the punctuation, in which case don't touch it, to avoid
            # messing up spaces? WEIRD, yeah.
            unless substitute.end_with? maybe_punct
              substitute.gsub!(/[[:punct:]]+\Z/, "")
              # This adding the #{space} back in, is consistent with what HIP does.
              # I have no idea if it's right or a bug in HIP, but being consistent.
              # neither leaving it in nor taking it out is exactly consistent with HznExportMarc,
              # which seems to have bugs.
              substitute << "#{space}#{maybe_punct}"
            end
          end

          "\x1F#{subfield}#{substitute}"
        else # just keep original, which has no maybe_punct
          "\x1F#{subfield}"
        end
      end

      # We mutated bibtext to fill in template, now just return it.
      return bibtext
    end



  end
end
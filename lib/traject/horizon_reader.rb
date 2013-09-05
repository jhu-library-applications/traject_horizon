require 'traject'
require 'traject/util'
require 'traject/indexer/settings'

require 'traject/horizon_bib_auth_merge'

require 'marc'

module Traject
  #
  # = Settings
  #
  # == Connection
  #
  # [horizon.jdbc_url]  JDBC connection URL using jtds. Should include username, but not password.
  #                     See `horizon.jdbc_password` setting, kept seperate so we can try to suppress
  #                     it from logging. Eg: "jdbc:jtds:sybase://horizon.lib.univ.edu:2025/dbname;user=dbuser"
  #                     * In command line, you'll have to use quotes: -s 'horizon.jdbc_url=jdbc:jtds:sybase://horizon.lib.univ.edu:2025/dbname;user=dbuser'
  #
  # [horizon.jdbc_password] Password to use for JDBC connection. We'll try to suppress it from being logged.
  #
  # == What to export
  #
  # Normally exports the entire horizon database, for diagnostic or batch purposes you
  # can export just one bib, or a range of bibs instead.
  #
  # [horizon.first_bib] Greater than equal to this bib number. Can be combined with horizon.last_bib
  # [horizon.last_bib]  Less than or equal to this bib number. Can be combined with horizon.first_bib
  # [horizon.only_bib]  Only this single bib number.
  #
  # You can also control whether to export staff-only bibs, copies, and items.
  #
  # [horizon.public_only] Default true. If set to true, only includes bibs that are NOT staff_only,
  #                       also only include copy/item that are not staff-only if including copy/item.
  #
  # You can also exclude certain tags:
  #
  # [horizon.exclude_tags] Default nil. A comma-seperated string (so easy to supply on command line)
  #                   of tag names to exclude from export. You probably want to at least include the tags
  #                   you are using for horizon.item_tag and horizon.copy_tag, to avoid collision
  #                   from tags already in record.
  #
  # == Item/Copy Inclusion
  #
  # The HorizonReader can export MARC with holdings information (horizon items and copies) included
  # in the MARC. Each item or copy record will be represented as one marc field -- the tags
  # used are configurable.  You can configure how individual columns from item or copy tables
  # map to MARC subfields in that field -- and also include columns from other tables joined
  # to item or copy.
  #
  # [horizon.include_holdings]  * false, nil, or empty string: Do not include holdings. (DEFAULT)
  #                             * all: include copies and items
  #                             * items: only include items
  #                             * copies: only include copies
  #                             * direct: only include copies OR items, but not both; if bib has
  #                               include copies, otherwise include items if present.
  #
  # Each item or copy will be one marc field, you can configure what tags these fields
  # will have.
  #
  # [horizon.item_tag]  Default "991".
  # [horizon.copy_tag]  Default "937"
  #
  # Which columns from item or copy tables will be mapped to which subfields in those
  # fields is controlled by hashes in settings, hash from column name (with table prefix)
  # to subfield code. There are defaults, see HorizonReader.default_settings. Example for
  # item_map default:
  #
  # "horizon.item_map"          => {
  #         "item.call_reconstructed"   => "a",
  #         "collection.call_type"      => "b",
  #         "item.copy_reconstructed"   => "c",
  #         "call_type.processor"       => "f",
  #         "item.item#"                => "i",
  #         "item.collection"           => "l",
  #         "item.location"             => "m",
  #         "item.notes"                => "n",
  #         "item.staff_only"           => "q"
  #       }
  #
  # [horizon.item_map]
  # [horizon.copy_map]
  #
  # The column-to-subfield maps can include columns from other tables
  # joined in, with a join clause configured in settings too.
  # By default both item and copy join to: collection, and call_type --
  # using some clever SQL to join to call_type on the item/copy fk, OR the
  # associated collection fk if no specific item/copy one is defined.
  #
  # [horizon.item_join_clause]
  # [horizon.copy_join_clause]
  #
  # == Character Encoding
  #
  # The HorizonReader can convert from Marc8 to UTF8. By default `horizon.source_encoding` is set to "MARC8"
  # and `horizon.destination_encoding` is set to "UTF8", which will make it do that conversion, as well
  # as set the leader byte for char encoding properly.
  #
  # Any other configuration of those settings, and no transcoding will take place, HorizonReader
  # is not currently capable of doing any other transcoding. Set
  # or `horizon.destination_encoding` to nil if you don't want any transcoding to happen --
  # you'd only want this for diagnostic purposes, or if your horizon db is already utf8 (is
  # that possible? We don't know.)
  #
  # [horizon.codepoint_translate] translates from Horizon's weird <U+nnnn> unicode
  #   codepoint escaping to actual UTF-8 bytes. Defaults to true. Will be ignored
  #   unless horizon.destination_encoding is UTF8 though.
  #
  # == Misc
  #
  # [horizon.batch_size] Batch size to use for fetching item/copy info on each bib. Default 400.
  # [debug_ascii_progress]  if true, will output a "<" and a ">" to stderr around every copy/item
  #           subsidiary fetch. See description of this setting in docs/settings.md
  #
  # [jtds.jar_path]  Normally we'll use a distribution of jtds bundled with this gem.
  #                  But specify a filepath of a directory containing jtds jar(s),
  #                  and all jars in that dir will be loaded instead of our bundled jtds.
  #
  #
  # Note: Could probably make this even faster by using a thread pool -- the bottleneck
  # is probably processing into MARC, not the database query and streaming. But it's a
  # bit tricky to refactor for concurrency there. Perhaps pull all the raw
  # row values out and batch them in groups by bib#, then feed those lists
  # to a threadpool. And then we'd just be fighting for CPU time with the
  # threadpool for mapping, not sure if overall throughput increase would happen, would
  # depend on exact environment.
  class HorizonReader
    attr_reader :settings
    attr_reader :things_to_close

    # We ignore the iostream even though we get one, we're gonna
    # read from a Horizon DB!
    def initialize(iostream, settings)
      # we ignore the iostream, we're fetching from Horizon db

      @settings = Traject::Indexer::Settings.new( self.class.default_settings).merge(settings)

      require_jars!
    end

    # Requires marc4j and jtds, and java_import's some classes.
    def require_jars!
        Traject::Util.jruby_ensure_init!("Traject::HorizonReader")

        Traject::Util.require_marc4j_jars(settings)

        # For some reason we seem to need to java_import it, and use
        # a string like this. can't just refer to it by full
        # qualified name, not sure why, but this seems to work.
        java_import "org.marc4j.converter.impl.AnselToUnicode"

        unless defined? Java::net.sourceforge.jtds.jdbc.Driver
          jtds_jar_dir = settings["jtds.jar_path"] || File.expand_path("../../vendor/jtds", File.dirname(__FILE__))

          Dir.glob("#{jtds_jar_dir}/*.jar") do |x|
            require x
          end

          # For confusing reasons, in normal Java need to
          # Class.forName("net.sourceforge.jtds.jdbc.Driver")
          # to get the jtds driver to actually be recognized by JDBC.
          #
          # In Jruby, Class.forName doesn't work, but this seems
          # to do the same thing:
          Java::net.sourceforge.jtds.jdbc.Driver
        end

        # So we can refer to these classes as just ResultSet, etc.
        java_import java.sql.ResultSet, java.sql.PreparedStatement, java.sql.Driver
    end

    def fetch_result_set!(conn)
      #fullbib is a view in Horizon, I think it was an SD default view, that pulls
      #in stuff from multiple tables, including authority tables, to get actual
      # text.
      # You might think need an ORDER BY, but doing so makes it incredibly slow
      # to retrieve results, can't do it. We just count on the view returning
      # the rows properly. (ORDER BY bib#, tagord)
      #
      # We start with the fullbib view defined out of the box in Horizon, but
      # need to join in bib_control to have access to the staff_only column.
      #
      sql = <<-EOS
        SELECT b.bib#, b.tagord, b.tag,
         indicators = substring(b.indicators+'  ',1,2)+a.indicators,
         b.text, b.cat_link_type#, b.cat_link_xref#, b.link_type,
         bl.longtext, xref_text     = a.text, xref_longtext = al.longtext,
         b.timestamp, auth_timestamp = a.timestamp,
         bc.staff_only
        FROM bib b
          left join bib_control bc on b.bib# = bc.bib#
          left join bib_longtext bl on b.bib# = bl.bib# and b.tag = bl.tag and b.tagord = bl.tagord
          left join auth a on b.cat_link_xref# = a.auth# and a.tag like '1[0-9][0-9]'
          left join auth_longtext al on b.cat_link_xref# = al.auth# and al.tag like '1[0-9][0-9]'
        WHERE 1 = 1
      EOS

      sql = <<-EOS
        SELECT b.*, bc.staff_only
        FROM fullbib b
        JOIN bib_control bc on b.bib# = bc.bib#
        WHERE 1 = 1
      EOS

      if settings["horizon.public_only"].to_s == "true"
        sql += " AND staff_only != 1"
      end

      # settings should not be coming from untrusted user input not going
      # to bother worrying about sql injection.
      if settings.has_key? "horizon.only_bib"
        sql += " AND b.bib# = #{settings['horizon.only_bib']} "
      elsif settings.has_key?("horizon.first_bib") || settings.has_key?("horizon.last_bib")
        clauses = []
        clauses << " b.bib# >= #{settings['horizon.first_bib']}" if settings['horizon.first_bib']
        clauses << " b.bib# <= #{settings['horizon.last_bib']}" if settings['horizon.last_bib']
        sql += " AND " + clauses.join(" AND ") + " "
      end

      pstmt = conn.prepareStatement(sql);

      # this may be what's neccesary to keep the driver from fetching
      # entire result set into memory.
      pstmt.setFetchSize(10000)


      logger.debug("HorizonReader: Executing query: #{sql}")
      rs = pstmt.executeQuery
      logger.debug("HorizonReader: Executed!")
      return rs
    end

    # Converts from Marc8 to UTF8 if neccesary.
    # Also replaces horizon <U+nnnn> codes if needed.
    def convert_text!(text, error_handler)
      text = AnselToUnicode.new(error_handler, true).convert(text) if convert_marc8_to_utf8?

      # Turn Horizon's weird escaping into UTF8: <U+nnnn> where nnnn is a hex unicode
      # codepoint, turn it UTF8 for that codepoint
      if settings["horizon.codepoint_translate"].to_s == "true" && settings["horizon.destination_encoding"] == "UTF8"
        text.gsub!(/\<U\+([0-9A-F]{4})\>/) do
          [$1.hex].pack("U")
        end
      end

      return text
    end

    # Read rows from horizon database, assemble them into MARC::Record's, and yield each
    # MARC::Record to caller.
    def each
      # Need to close the connection, teh result_set, AND the result_set.getStatement when
      # we're done.
      connection = open_connection!

      # We're going to need to ask for item/copy info while in the
      # middle of streaming our results. JDBC is happier and more performant
      # if we use a seperate connection for this.
      extra_connection = open_connection! if include_some_holdings?

      # We're going to make our marc records in batches, and only yield
      # them to caller in batches, so we can fetch copy/item info in batches
      # for efficiency.
      batch_size = settings["horizon.batch_size"].to_i
      record_batch = []

      exclude_tags = (settings["horizon.exclude_tags"] || "").split(",")


      rs = self.fetch_result_set!(connection)

      current_bib_id = nil
      record = nil
      record_count = 0

      error_handler = org.marc4j.ErrorHandler.new

      while(rs.next)
        bib_id      = rs.getInt("bib#");

        if bib_id != current_bib_id
          record_count += 1

          if settings["debug_ascii_progress"] &&  (record_count % settings["solrj_writer.batch_size"] == 0)
            $stderr.write ","
          end

          # new record! Put old one on batch queue.
          record_batch << record if record

          # prepare and yield batch?
          if (record_count % batch_size == 0)
            enhance_batch!(extra_connection, record_batch)
            record_batch.each do |r|
              # set current_bib_id for error logging
              current_bib_id = r['001'].value
              yield r
            end
            record_batch.clear
          end

          # And start new record we've encountered.
          error_handler = org.marc4j.ErrorHandler.new
          current_bib_id = bib_id
          record = MARC::Record.new
          record.append MARC::ControlField.new("001", bib_id.to_s)
        end


        tagord      = rs.getInt("tagord");
        tag         = rs.getString("tag")

        # just silently skip it, some weird row in the horizon db, it happens.
        # plus any of our exclude_tags.
        next if tag.nil? || tag == "" || exclude_tags.include?(tag)

        numeric_tag = tag.to_i if tag =~ /\A\d+\Z/

        indicators = rs.getString("indicators")

        # a packed byte array could be in various columns, in order of preference...
        # the xref stuff is joined in from the auth table
        # Have to get it as bytes and then convert it to String to avoid JDBC messing
        # up the encoding marc8 grr
        authtext = rs.getBytes("xref_longtext") || rs.getBytes("xref_text")
        if authtext
          authtext = String.from_java_bytes(authtext)
          authtext.force_encoding("binary")
        end

        text     = rs.getBytes("longtext") || rs.getBytes("text")
        if text
          text = String.from_java_bytes(text)
          text.force_encoding("binary")
        end

        text = Traject::HorizonBibAuthMerge.new(tag, text, authtext).merge!

        next if text.nil? # sometimes there's nothing there, skip it.

        # convert from MARC8 to UTF8 if needed
        text = convert_text!(text, error_handler)

        if numeric_tag && numeric_tag == 0
          record.leader = text
          fix_leader!(record.leader)
        elsif numeric_tag && numeric_tag == 1
          # nothing, we add the 001 ourselves first
        elsif numeric_tag && numeric_tag < 10
          # control field
          record.append MARC::ControlField.new(tag, text )
        else
          # data field
          indicator1 = indicators.slice(0)
          indicator2 = indicators.slice(1)

          data_field = MARC::DataField.new(  tag,  indicator1, indicator2 )
          record.append data_field

          subfields  = text.split("\x1F")

          subfields.each do |subfield|
            next if subfield.empty?

            subfield_code = subfield.slice(0)
            subfield_text = subfield.slice(1, subfield.length)

            data_field.append MARC::Subfield.new(subfield_code, subfield_text)
          end
        end
      end
      # last one
      record_batch << record if record

      # yield last batch
      enhance_batch!(extra_connection, record_batch)
      record_batch.each do |r|
        # reset bib_id for error message logging
        current_bib_id = (f = r['001']) && f.value
        yield r
      end
      record_batch.clear

    rescue Exception => e
      logger.fatal "HorizonReader, unexpected exception at bib id:#{current_bib_id}: #{Traject::Util.exception_to_log_message(e)}"
      raise e
    ensure
      logger.info("HorizonReader: Closing all JDBC objects...")

      # have to cancel the statement to keep us from waiting on entire
      # result set when exception is raised in the middle of stream.
      statement = rs && rs.getStatement
      if statement
        statement.cancel
        statement.close
      end

      rs.close if rs

      # shouldn't actually need to close the resultset and statement if we cancel, I think.
      connection.close if connection

      extra_connection.close if extra_connection

      logger.info("HorizonReader: Closed JDBC objects")
    end

    def process_batch(batch)

    end

    # Pass in an array of MARC::Records', adds fields for copy and item
    # info if so configured. Returns record_batch so you can chain if you want.
    def enhance_batch!(conn, record_batch)
      return record_batch if record_batch.nil? || record_batch.empty?

      copy_info = get_joined_table(
        conn, record_batch,
        :table_name  => "copy",
        :column_map  => settings['horizon.copy_map'],
        :join_clause => settings['horizon.copy_join_clause'],
        :public_only => (settings['horizon.public_only'].to_s == "true")
      ) if %w{all copies direct}.include? settings['horizon.include_holdings'].to_s



      item_info = get_joined_table(
        conn, record_batch,
        :table_name  => "item",
        :column_map  => settings['horizon.item_map'],
        :join_clause => settings['horizon.item_join_clause'],
        :public_only => (settings['horizon.public_only'].to_s == "true")
      ) if %w{all items direct}.include? settings['horizon.include_holdings'].to_s



      if item_info || copy_info
        record_batch.each do |record|
          id = record['001'].value.to_s
          record_copy_info = copy_info && copy_info[id]
          record_item_info = item_info && item_info[id]

          record_copy_info.each do |copy_row|
            field = MARC::DataField.new( settings["horizon.copy_tag"] )
            copy_row.each_pair do |subfield, value|
              field.append MARC::Subfield.new(subfield, value)
            end
            record.append field
          end if record_copy_info

          record_item_info.each do |item_row|
            field = MARC::DataField.new( settings["horizon.item_tag"] )
            item_row.each_pair do |subfield, value|
              field.append MARC::Subfield.new(subfield, value)
            end
            record.append field
          end if record_item_info && ((settings['horizon.include_holdings'].to_s != "direct") || record_copy_info.empty?)
        end
      end

      return record_batch
    end

    # Can be used to fetch a batch of subsidiary info from other tables:
    # Used to fetch item or copy information. Can fetch with joins too.
    # Usually called by passing in settings, but a literal call might look something
    # like this for items:
    #
    # get_joined_table(jdbc_conn, array_of_marc_records,
    #    :table_name => "item",
    #    :column_map => {"item.item#" => "i", "call_type.processor" => "k"},
    #    :join_clause => "JOIN call_type ON item.call_type = call_type.call_type"
    # )
    #
    # Returns a hash keyed by bibID, value is an array of hashes of subfield->value, eg:
    #
    # {'343434' => [
    #    {
    #      'i' => "012124" # item.item#
    #      'k' => 'lccn'   # call_type.processor
    #    }
    #   ]
    # }
    #
    # Can also pass in a `:public_only => true` option, will add on a staff_only != 1
    # where clause, assumes primary table has a staff_only column.
    def get_joined_table(conn, batch, options = {})
      table_name  = options[:table_name]  or raise ArgumentError.new("Need a :table_name option")
      column_map  = options[:column_map]  or raise ArgumentError.new("Need a :column_map option")
      join_clause = options[:join_clause] || ""
      public_only = options[:public_only]


      results = Hash.new {|h, k| h[k] = [] }

      bib_ids_joined = batch.collect do |record|
        record['001'].value.to_s
      end.join(",")

      # We include the column name with prefix as an "AS", so we can fetch it out
      # of the result set later just like that.
      columns_clause = column_map.keys.collect {|c| "#{c} AS '#{c}'"}.join(",")
      sql = <<-EOS
        SELECT bib#, #{columns_clause}
        FROM #{table_name}
        #{join_clause}
        WHERE bib# IN (#{bib_ids_joined})
      EOS

      if public_only
        sql += " AND staff_only != 1"
      end

      $stderr.write "<" if settings["debug_ascii_progress"]

      # It might be higher performance to refactor to re-use the same prepared statement
      # for each item/copy fetch... but appears to be no great way to do that in JDBC3
      # where you need to parameterize "IN" values. JDBC4 has got it, but jTDS is just JDBC3.
      pstmt = conn.prepareStatement(sql);
      rs = pstmt.executeQuery


      while (rs.next)
        bib_id = rs.getString("bib#")
        row_hash = {}

        column_map.each_pair do |column, subfield|
          value = rs.getString( column )

          if value
            # Okay, total hack to deal with the fact that holding notes
            # seem to be in UTF8 even though records are in MARC... which
            # ends up causing problems for exporting as marc8, which is
            # handled kind of not very well anyway.
            # I don't even totally understand what I'm doing, after 6 hours working on it,
            # sorry, just a hack.
            value.force_encoding("BINARY") unless  settings["horizon.destination_encoding"] == "UTF8"

            row_hash[subfield] = value
          end
        end

        results[bib_id] << row_hash
      end

      return results
    ensure
      pstmt.cancel if pstmt
      pstmt.close if pstmt
      rs.close if rs
      $stderr.write ">" if settings["debug_ascii_progress"]
    end

    # Mutate string passed in to fix leader bytes for marc21
    def fix_leader!(leader)
      if leader.length < 24
        # pad it to 24 bytes, leader is supposed to be 24 bytes
        leader.replace(  leader.ljust(24, ' ')  )
      end
      # http://www.loc.gov/marc/bibliographic/ecbdldrd.html
      leader[10..11] = '22'
      leader[20..23] = '4500'

      if settings['horizon.destination_encoding'] == "UTF8"
        leader[9] = 'a'
      end
    end

    def include_some_holdings?
      ! [false, nil, ""].include?(settings['horizon.include_holdings'])
    end

    def convert_marc8_to_utf8?
      settings['horizon.source_encoding'] == "MARC8" && settings['horizon.destination_encoding'] == "UTF8"
    end


    def open_connection!
      logger.debug("HorizonReader: Opening JDBC Connection at #{settings["horizon.jdbc_url"]} ...")

      url = settings["horizon.jdbc_url"]
      if settings["horizon.jdbc_password"]
        url += ";password=#{settings['horizon.jdbc_password']}"
      end

      conn =  java.sql.DriverManager.getConnection( url )
      # If autocommit on, fetchSize later has no effect, and JDBC slurps
      # the whole result set into memory, which we can not handle.
      conn.setAutoCommit false
      logger.debug("HorizonReader: Opened JDBC Connection.")
      return conn
    end

    def logger
      settings["logger"] || Yell::Logger.new(STDERR, :level => "gt.fatal") # null logger
    end

    def self.default_settings
      {
        "horizon.batch_size" => 400,

        "horizon.public_only" => true,

        "horizon.source_encoding"      => "MARC8",
        "horizon.destination_encoding" => "UTF8",
        "horizon.codepoint_translate"  => true,

        "horizon.item_tag"          => "991",
        # Crazy isnull() in the call_type join to join to call_type directly on item
        # if specified otherwise calltype on colleciton. Phew!
        "horizon.item_join_clause"  => "LEFT OUTER JOIN collection ON item.collection = collection.collection LEFT OUTER JOIN call_type ON isnull(item.call_type, collection.call_type) = call_type.call_type",
        "horizon.item_map"          => {
          "item.call_reconstructed"   => "a",
          "call_type.processor"       => "f",
          "call_type.call_type"      => "b",
          "item.copy_reconstructed"   => "c",
          "item.staff_only"           => "q",
          "item.item#"                => "i",
          "item.collection"           => "l",
          "item.notes"                => "n",
          "item.location"             => "m"
        },

        "horizon.copy_tag"          => "937",
        # Crazy isnull() in the call_type join to join to call_type directly on item
        # if specified otherwise calltype on colleciton. Phew!
        "horizon.copy_join_clause"  => "LEFT OUTER JOIN collection ON copy.collection = collection.collection LEFT OUTER JOIN call_type ON isnull(copy.call_type, collection.call_type) = call_type.call_type",
        "horizon.copy_map"          => {
          "copy.copy#"           => "8",
          "copy.call"            => "a",
          "copy.copy_number"     => "c",
          "call_type.processor"  => "f",
          "copy.staff_only"      => "q",
          "copy.location"        => "m",
          "copy.collection"      => "l",
          "copy.pac_note"        => "n"
        }
      }
    end
  end
end
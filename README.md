# Traject::Horizon

Export MARC records directly from a Horizon ILS rdbms, either as serialized MARC,
or to then index to Solr.

traject_horizon is a plugin for [traject](http://github.com/jrochkind/traject), and
requires jruby to be installed.

Supports embedding copy/item holdings information in exported MARC.

Fairly high-performance, should have higher throughput than most existing
Horizon MARC export options, including the vendor-supplied Windows-only
'marcout'. There are probably opportunities for increasing performance
yet further with more development of multi-threaded processing.

## Installation

traject_horizon is a plugin for [traject](http://github.com/jrochkind/traject), which
needs to run under jruby. We recommend [chruby](https://github.com/postmodern/chruby)
for managing multiple ruby versions, see it's instructions for installing jruby. 

Then, with jruby active (`$ chruby jruby`), you can install both `traject`
and `traject_horizon` with:

    $ gem install traject traject_horizon

### Or, if using a bundler Gemfile with your traject project

Add this line to your [traject project's Gemfile](https://github.com/jrochkind/traject/blob/master/doc/extending.md#or-with-bundler):

    gem 'traject_horizon'

And then execute:

    $ bundle install

## Usage

I recommend creating a seperate traject configuration file just with
settings for the Horizon export.

~~~ruby
# horizon_conf.rb

# Require traject/horizon to load the gem, including
# the Traject::HorizonReader we'll subsequently
# configure to be used
require 'traject/horizon'

settings do
  store "reader_class_name", "Traject::HorizonReader"

  # JDBC URL starting with "jdbc:jtds", and either "sybase:"
  # or "sqlserver:", including username on the end but not password:
  provide "horizon.jdbc_url", "jdbc:jtds:sybase://horizonserver.university.edu:2025/horizon_db;user=esys"

  # Instead of horizon.jdbc_url, you can also use individual
  # horizon.host, horizon.port, horizon.database, horizon.user

  # DB password in seperate setting
  provide "horizon.jdbc_password", "drilg53"

  # Do you want to include copy/item holdings information?
  # this setting says to include "top-level" holdings,
  # copy or item but not both. Holdings will be included
  # in tags 991 and 937, although the tags and nature
  # of included holdings is configurable.
  provide "horizon.include_holdings", "direct"

  # Would you like to exclude certain tags from
  # your Horizon db?  If you are including holdings,
  # then it's recommended to exclude 991 and 937 to
  # avoid any collision with the tags we add to represent holdings.
  provide "horizon.exclude_tags", "991,937"
end
~~~

There are a variety of additional settings that apply to the HorizonReader,
especially settings for customizing the item/copy holdings information
included. See [HorizonReader] inline comment docs.

Note by default 'staff-only' records are _not_ included in the export,
but this can be changed in settings.

As with all traject settings, string-valued settings can also be supplied
on the traject command line with `-s setting=value`.

### Export MARC records

    $ traject -x marcout -c horizon_conf.rb -o marc_files.marc

That will export your entire horizon database,,
using the connection details and configuration from horizon_conf.rb, exporting
in ISO 2709 binary format to `marc_files.marc`.

You can also specify specific ranges of bib#'s to export:

    $ traject -x marcout -c horizon_conf.rb -o marc_files.marc -s horizon.first_bib=10000 -s horizon.last_bib=10100
    $ traject -x marcout -c horizon_conf.rb -o marc_files.marc -s horizon.only_bib=12345

You can export in MarcXML, or in a human readable format for debuging,
using standard traject `-x marcout` functionality:

    $ traject -x marcout -c horizon_conf.rb -s marcout.type=xml -o marc_files.xml

    # leave off the `-o` argument to write to stdout, and view bib# 12345 in
    # human-readable format:
    $ traject -x marcout -c horizon_conf.rb -s marcout.type=human -s horizon.only_bib=12345

### Indexing records to solr

Traject is primarily a tool for indexing to solr. You can use `traject_horizon` to
export from Horizon and send directly through the indexing pipeline, without
having to serialize MARC to disk first.

You would have one or more additional traject configuration files specifying
your indexing mapping rules, and Solr connection details. See traject
documentation.

Then, simply:

    $ traject -c horizon_conf.rb -c other_traject_conf.rb

## Note on character encodings

By default, traject_horizon assumes the data in your Horizon database is stored
in the Marc8 encoding. (I think this is true of all Horizon databases?). And by
default, traject_horizon will transcode it to UTF-8, marking leader byte 9 in any
exported MARC appropriately (Using the Marc4J AnselConverter class).

If you'd like traject to avoid this transcode, you can set the traject
setting `horizon.destination_encoding` to nil or the empty string, either
on the command line:

    traject -x marcout -s horizon.destination_encoding= -c horizon_conf.rb

Or in your traject configuration file:

    settings do
      #...
      provide "horizon.destination_encoding", nil
    end

You might want to do this with `marcout` use, perhaps for diagnostics, but
it shouldn't ever be appropriate for indexing-to-solr use, as there are limited
facilities for dealing with Marc8 encoding in ruby.

Currently, item/copy information may not be treated entirely consistent here,
there may be edge-case encoding bugs related to non-ascii item/copy notes etc,
and it may not be possible to output them in Marc8. Sorry.

## Challenges

I had to reverse engineer the Horizon database to figure out how to turn it into
MARC records.  I believe I have been succesful, and traject_horizon seems to produce
the same output as Horizon's own marcout.

Hopefully this will remain true in future Horizon versions, I don't think relevant
aspects of Horizon architecture change very much, but it's always a risk.

The two biggest challenges were dealing with character encoding, and dealing
with merging information from the Horizon bib and auth tables.

The translation from Marc8 to UTF8 appears to work properly, _except_
some known issues with item/copy holding information. item/copy holding
information may occasionally not transcode properly, and it may not
be possible to keep item/copy holding info in Marc8.  If these become
an actual problem in practice for anyone, further development can
probably resolve these issues.


## Development

There is only limited test coverage at the moment, sorry. I couldn't
quite figure out how to easily provide test coverage when so much
functionality interacts with a Horizon database.

There is some test coverage of the bib/auth merging routines.

Test are provided with minitest, and can be run with `rake test`.
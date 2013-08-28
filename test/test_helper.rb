gem 'minitest' # I feel like this messes with bundler, but only way to get minitest to shut up
require 'minitest/autorun'
require 'minitest/spec'

require 'traject'
require 'marc'

# keeps things from complaining about "yell-1.4.0/lib/yell/adapters/io.rb:66 warning: syswrite for buffered IO"
# for reasons I don't entirely understand, involving yell using syswrite and tests sometimes
# using $stderr.puts. https://github.com/TwP/logging/issues/31
STDERR.sync = true

# Hacky way to turn off Indexer logging by default, say only
# log things higher than fatal, which is nothing. 
require 'traject/indexer/settings'
Traject::Indexer::Settings.defaults["log.level"] = "gt.fatal"
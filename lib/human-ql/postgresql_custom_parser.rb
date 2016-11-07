#--
# Copyright (c) 2016 David Kellum
#
# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License.  You may
# obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.  See the License for the specific language governing
# permissions and limitations under the License.
#++

require 'human-ql/query_parser'

module HumanQL

  # Extends the generic QueryParser with additional special character
  # filtering so as to avoid syntax errors in PostgreSQL to_tsquery()
  # for any known input.  Note that this is still a parser for the
  # HumanQL query language, not anything implemented in PostgreSQL.
  class PostgreSQLCustomParser < QueryParser

    # Construct given options to set via base clase or as specified
    # below.
    #
    # === Options
    #
    # :pg_version:: A version string ("9.5.5", "9.6.1") or integer
    #               array ( [9,6,1]) indicating the target PostgreSQL
    #               version. Phrase support starts in 9.6 so quoted
    #               phrases are ignored before that.
    #
    def initialize(opts = {})
      opts = opts.dup
      pg_version = opts.delete(:pg_version)
      if pg_version.is_a?( String )
        pg_version = pg_version.split( '.' ).map( &:to_i )
      end
      pg_version ||= []

      super

      # Phrase support starts in 9.6
      if ( pg_version <=> [9,6] ) >= 0
        @term_rejects = /[()|&:*!'<>]/
      else
        # Disable quote tokens and reject DQUOTE as token character
        self.lquote = nil
        self.rquote = nil
        @term_rejects = /[()|&:*!'"<>]/
      end

    end

    # Replace term_rejects characters with '_' which is punctuation
    # (or effectively, whitespace) in tsquery with tested
    # dictionaries.
    def norm_term( t )
      t.gsub( @term_rejects, '_' )
    end
  end

end

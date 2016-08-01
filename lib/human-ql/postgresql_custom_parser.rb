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

  # Extends the generic QueryParser with extra special character and
  # token filtering so as to avoid syntax errors in PostgreSQL
  # to_tsquery() for any known input.  Note that this is still a
  # parser for the HumanQL query language, not anything implemented in
  # PostgreSQL.
  class PostgreSQLCustomParser < QueryParser

    def initialize(opts = {})
      pg_version = opts.delete(:pg_version)
      if pg_version.is_a?( String )
        pg_version = pg_version.split( '.' ).map( &:to_i )
      end
      pg_version ||= []

      super

      # Phrase support starts in 9.6
      if ( pg_version <=> [9,6] ) >= 0
        # Extend the spaces pattern to include all known to_tsquery
        # special characters that aren't already being handled via
        # default QueryParser operators.
        self.spaces = /[[:space:]*:!'<>]+/.freeze
      else
        self.spaces = /[[:space:]*:!'"<>]+/.freeze
        self.lquote = nil
        self.rquote = nil
      end

      # Use by custom #norm_phrase_tokens as a superset of the
      # #lparen, #rparen token patterns removed by default.  In
      # PostgreSQL proximity expressions for phrases, the '|' and '&'
      # still need to be filtered.
      @phrase_token_rejects = /\A[()|&]\z/.freeze
    end

    def norm_phrase_tokens( tokens )
      tokens.reject { |t| @phrase_token_rejects === t }
    end
  end

end

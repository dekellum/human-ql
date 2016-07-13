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

  # Extends the generic QueryParser with extra special character
  # normalization and filtering so as to avoid syntax errors in
  # PostgreSQL to_tsquery() for any known input.  Note that this is
  # still a parser for the HumanQL query language, not any PostgreSQL
  # specific language.
  class PostgreSQLCustomParser < QueryParser
    def initialize(*args)
      super

      # Extend the spaces pattern to include all known to_tsquery
      # special characters that aren't already being handled via
      # default QueryParser operators. Note that ':' is included,
      # since this default/testing parser doesn't define scopes, use
      # norm_scopes which would otherwise handle ':'
      @spaces = /[[:space:]*:!'<>]+/.freeze

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

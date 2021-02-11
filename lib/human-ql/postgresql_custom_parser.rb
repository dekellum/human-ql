# coding: utf-8

#--
# Copyright (c) 2016-2021 David Kellum
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
  # and token filtering so as to avoid syntax errors with to_tsquery()
  # (via PostgreSQLGenerator) for any known input.  Note that this is
  # still a parser for the HumanQL query language, not anything
  # implemented in PostgreSQL.
  class PostgreSQLCustomParser < QueryParser

    # U+2019 RIGHT SINGLE QUOTATION MARK
    RSQMARK = '’'.freeze

    UNDERSCORE = '_'.freeze

    # Construct given options to set via base class or as specified
    # below.
    #
    # === Options
    #
    # :pg_version:: A version string ("9.5.5", "9.6.1") or integer
    #               array ([9,6,1]) indicating the target PostgreSQL
    #               version. Phrase support starts in 9.6 so quoted
    #               phrases are ignored before that. Default: < 9.6
    #
    def initialize(opts = {})
      opts = opts.dup
      pg_version = opts.delete(:pg_version)
      if pg_version.is_a?(String)
        pg_version = pg_version.split('.').map(&:to_i)
      end
      pg_version ||= []

      super

      # Phrase support starts in 9.6
      if (pg_version <=> [9,6]) >= 0
        # Handle what PG-sensitive characters we can early as
        # whitespace. This can't include anything part of HumanQL,
        # e.g. ':' as used for scopes, so deal with the remainder
        # below.
        self.spaces = /[[:space:]*!<>\0\\]+/.freeze
      else
        # Disable quote tokens
        self.lquote = nil
        self.rquote = nil
        # As above but add DQUOTE as well.
        self.spaces = /[[:space:]*!<>\0\\"]+/.freeze
      end

      # Used by custom #norm_phrase_tokens as a super-set of the
      # #lparen, #rparen token patterns removed by default.  In
      # PostgreSQL, the '|' and '&' still need to be filtered. Other
      # freestanding punctuation tokens are best removed entirely.
      @phrase_token_rejects = /\A[()|&':]\z/.freeze

      # SQUOTE is a problem only when at beginning of term.
      @lead_squote = /\A'/.freeze

      # COLON is always a problem, but since its also part of Human QL
      # (scopes) it can't be included earlier in #spaces. Also per
      # scope parsing rules, its not always made a separate token.
      @term_rejects = /:/.freeze
    end

    def norm_phrase_tokens(tokens)
      tokens.
        reject { |t| @phrase_token_rejects === t }.
        map { |t| norm_term(t) }
    end

    # Replace various problem single characters with alt. characters.
    def norm_term(t)
      t.sub(@lead_squote, RSQMARK).
        gsub(@term_rejects, UNDERSCORE)
    end
  end

end

#!/usr/bin/env ruby

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

require_relative 'setup.rb'

require 'human-ql/query_parser'
require 'human-ql/postgresql_generator'

class TestFuzzParser < HumanQL::QueryParser
  def initialize
    super
    @verbose = ARGV.include?( '--verbose' )

    @spaces = /[[:space:]*:!'<>]+/.freeze
    # FIXME: Gets us further, but adding ':' to spaces will disable
    # SCOPEs. Need to make ':' more like an operator.

    @phrase_token_rejects = /\A[()|&]\z/.freeze
  end

  def norm_phrase_tokens( tokens )
    tokens.reject { |t| @phrase_token_rejects === t }
  end
end

class TestPostgresqlFuzz < Minitest::Test
  TC = TestFuzzParser.new
  PG = HumanQL::PostgreSQLGenerator.new

  DB = Sequel.connect( "postgres://localhost/human_ql_test" )

  # Assert that parsing via PG to_tsquery(generated) doesn't fail
  def assert_pg_parse( hq )
    ast = TC.parse( hq )
    if ast
      pg = PG.generate( ast )
      begin
        rt = DB["select to_tsquery(?) as tsquery", pg].first[:tsquery]
        refute_nil( rt, hq )
      rescue Sequel::DatabaseError => e
        fail( "On query #{hq.inspect} -> #{ast.inspect}: #{ e.to_s }" )
      end
    end
  end

  # Starting point query
  GENERIC_Q = 'ape | ( boy -"cat dog" )'.freeze

  # Characters which are likely to cause trouble
  RANDOM_C = '({"\'a !:* ,^#:/-0.123e-9)<>'.freeze

  def test_fuzz
    10000.times do
      s = rand( GENERIC_Q.length )
      l = rand( GENERIC_Q.length * 2 )
      q = GENERIC_Q[s,l]
      20.times do
        if rand(3) == 1
          q[rand(q.length+1)] = fuzz
        end
      end
      assert_pg_parse( q )
    end
  end

  def fuzz
    RANDOM_C[rand(RANDOM_C.length)]
  end

end if defined?( ::Sequel )

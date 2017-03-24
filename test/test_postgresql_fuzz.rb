#!/usr/bin/env ruby

#--
# Copyright (c) 2016-2017 David Kellum
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

require 'human-ql/postgresql_custom_parser'
require 'human-ql/postgresql_generator'
require 'human-ql/tree_normalizer'

class TestPostgresqlFuzz < Minitest::Test
  DB = Sequel.connect( "postgres://localhost/human_ql_test" )

  PG_VERSION =
    begin
      v = DB &&
          DB["select current_setting('server_version') as v"].first[:v]
      v &&= v.split('.').map(&:to_i)
      v || []
    end

  TC = HumanQL::PostgreSQLCustomParser.new( pg_version: PG_VERSION )
  DN = HumanQL::TreeNormalizer.new

  PG = HumanQL::PostgreSQLGenerator.new

  PASSES = if $0 == __FILE__
             100
           else
             1
           end

  # Assert that parsing via PG to_tsquery(generated) doesn't fail
  def assert_pg_parse( hq )
    ast = TC.parse( hq )
    ast = DN.normalize( ast )
    if ast
      pg = PG.generate( ast )
      begin
        rt = DB["select to_tsquery(?) as tsquery", pg].first[:tsquery]
        refute_nil( rt, hq )
      rescue Sequel::DatabaseError => e
        fail( "On query #{hq.inspect} -> #{ast.inspect}: #{ e.to_s }" )
      end
    else
      pass
    end
  end

  # Starting point query
  GENERIC_Q = 'ape | ( boy -"cat dog" )'.freeze

  # Characters which are likely to cause trouble
  RANDOM_C = '({"\'a !:* ,^#:/-0.123e-9)<>\\'.freeze

  PASSES.times do |i|
    define_method( "test_fuzz_#{i}" ) do
      1000.times do
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
  end

  def fuzz
    RANDOM_C[rand(RANDOM_C.length)]
  end

end if defined?( ::Sequel )

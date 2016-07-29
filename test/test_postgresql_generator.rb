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

require 'human-ql/postgresql_custom_parser'
require 'human-ql/postgresql_generator'

class TestPostgresqlGenerator < Minitest::Test
  TC = HumanQL::PostgreSQLCustomParser.new( verbose: ARGV.include?('--verbose') )
  PG = HumanQL::PostgreSQLGenerator.new

  DB = if defined?( ::Sequel )
         Sequel.connect( "postgres://localhost/human_ql_test" )
       end

  def assert_gen( expected_pg, hq )
    ast = TC.parse( hq )
    pg = PG.generate( ast )
    assert_equal( expected_pg, pg, ast )
  end

  # Assert that the round-trip representation via PG
  # to_tsquery(generated) (and back to text) doesn't error and is as
  # expected.
  def assert_tsq( expected, hq )
    if DB
      ast = TC.parse( hq )
      pg = PG.generate( ast )
      rt = DB["select to_tsquery(?) as tsquery", pg].first[:tsquery]
      assert_equal( expected, rt, ast )
    end
  end

  def test_gen_term
    assert_gen( 'ape', 'ape' )
    assert_tsq( "'ape'", 'ape' )
  end

  def test_gen_and
    assert_gen( 'ape & boy', 'ape boy' )
    assert_tsq( "'ape' & 'boy'", 'ape boy' )
  end

  def test_gen_phrase_1
    assert_gen( 'ape', '"ape"' )
    assert_tsq( "'ape'", '"ape"' )
  end

  def test_gen_phrase_2
    assert_gen( 'ape <-> boy', '"ape boy"' )
    assert_tsq( "'ape' <-> 'boy'", '"ape boy"' )
  end

  def test_gen_empty
    assert_gen( nil, '' )
  end

  def test_gen_not
    assert_gen( '!ape', '-ape' )
    assert_tsq( "!'ape'", '-ape' )
  end

  def test_gen_not_stop
    assert_gen( '!the', '-the' )
    assert_tsq( "", '-the' )
  end

  def test_gen_or
    assert_gen( '(ape | boy)', 'ape|boy' )
    assert_tsq( "'ape' | 'boy'", 'ape|boy' )
  end

  def test_gen_or_stop
    assert_gen( '(the | boy)', 'the|boy' )
    assert_tsq( "'boy'", 'the|boy' )
  end

  def test_gen_not_phrase
    assert_gen( '!(ape <-> boy)', '-"ape boy"' )
    assert_tsq( "!( 'ape' <-> 'boy' )", '-"ape boy"' )
  end

  def test_gen_precedence_1
    assert_gen( '(ape | boy) & cat', 'ape | boy cat' )
    assert_tsq( "( 'ape' | 'boy' ) & 'cat'", 'ape | boy cat' )
  end

  def test_gen_precedence_2
    assert_gen( 'ape & (boy | cat)', 'ape boy | cat' )
    assert_tsq( "'ape' & ( 'boy' | 'cat' )", 'ape boy | cat' )
  end

  def test_gen_precedence_3
    assert_gen( '(ape | !boy) & cat', 'ape | - boy cat' )
    assert_tsq( "( 'ape' | !'boy' ) & 'cat'", 'ape | - boy cat' )
  end

  def test_gen_precedence_4
    assert_gen( '(!ape | boy) & cat', '-ape | boy cat' )
    assert_tsq( "( !'ape' | 'boy' ) & 'cat'", '-ape | boy cat' )
  end

  def test_gen_precedence_5
    assert_gen( '(ape | boy) & !cat', 'ape | boy -cat' )
    assert_tsq( "( 'ape' | 'boy' ) & !'cat'", 'ape | boy -cat' )
  end

  def test_gen_precedence_6
    assert_gen( '(ape | boy) & !cat & dog', 'ape | boy -cat dog' )
    assert_tsq( "( 'ape' | 'boy' ) & !'cat' & 'dog'", 'ape | boy -cat dog' )
  end

  def test_funk_1
    assert_gen( "!(, & y)", "-( ,'y -)" )
    assert_tsq( "!'y'",     "-( ,'y -)" )

    assert_gen( "!(, & y) & c3", "|-( ,'y -)c3" )
    assert_tsq( "!'y' & 'c3'", "|-( ,'y -)c3" )
  end

  def test_funk_2
    # This used to crash PG 9.6 beta 1-2. This was fixed in beta 3.
    assert_tsq( "'boy' & 'cat'", "-(a -boy) & cat" )
  end

  def test_gen_or_not
    assert_tsq( "'ape' & ( !'boy' | !'cat' )", "ape & ( -boy | -cat )" )
  end

end

#!/usr/bin/env ruby
# coding: utf-8

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

class TestPostgresqlGenerator < Minitest::Test
  DB = if defined?( ::Sequel )
         Sequel.connect( "postgres://localhost/human_ql_test" )
       end

  PG_VERSION =
    begin
      v = DB &&
          DB["select current_setting('server_version') as v"].first[:v]
      v &&= v.split('.').map(&:to_i)
      v || []
    end

  TC = HumanQL::PostgreSQLCustomParser.new( verbose: ARGV.include?('--verbose'),
                                            pg_version: PG_VERSION )
  PG = HumanQL::PostgreSQLGenerator.new

  def pg_gte_9_6?
    ( PG_VERSION <=> [9,6] ) >= 0
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

  def assert_tsq_match( tsq, text )
    if DB
      rt = DB[ "select to_tsvector(?) @@ to_tsquery(?) as m",
               text, tsq ].first[ :m ]
      assert_equal( true, rt )
    end
  end

  def refute_tsq_match( tsq, text )
    if DB
      rt = DB[ "select to_tsvector(?) @@ to_tsquery(?) as m",
               text, tsq ].first[ :m ]
      assert_equal( false, rt )
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

  def test_gen_phrase
    if pg_gte_9_6?
      assert_gen( 'ape <-> boy', '"ape boy"' )
      assert_tsq( "'ape' <-> 'boy'", '"ape boy"' )
    else
      assert_gen( 'ape & boy', '"ape boy"' )
      assert_tsq( "'ape' & 'boy'", '"ape boy"' )
    end
  end

  def test_phrase_with_danger
    skip( "For postgresql 9.6+" ) unless pg_gte_9_6?
    assert_gen( 'boy', '": boy"' )
    assert_tsq( "'boy'", '": boy"' )
  end

  def test_phrase_or
    skip( "For postgresql 9.6+" ) unless pg_gte_9_6?
    # '<->' has precendence over '|'
    assert_gen( "(ape <-> boy | dog <-> girl)",
                '"ape boy" or "dog girl"' )

    assert_tsq( tsq = "'ape' <-> 'boy' | 'dog' <-> 'girl'",
                '"ape boy" or "dog girl"' )

    refute_tsq_match( tsq, 'boy girl', )
    refute_tsq_match( tsq, 'girl dog', )

    assert_tsq_match( tsq, 'ape boy', )
    assert_tsq_match( tsq, 'ape boy cat', )
    assert_tsq_match( tsq, 'dog girl', )
    assert_tsq_match( tsq, 'ape dog girl', )
  end

  def test_phrase_stopword
    assert_tsq( tsq = "'cat' <2> 'dog'", '"cat _ dog"' )

    assert_tsq_match( tsq, 'cat goose dog' )

    # '<2>' is exact, not up to...
    refute_tsq_match( tsq, 'cat dog', )
    refute_tsq_match( tsq, 'cat girl goose dog', )

    # to_tsvector('cat a dog') -> 'cat':1 'dog':3
    # to_tsvector('cat _ dog') -> 'cat':1 'dog':2

    assert_tsq_match( tsq, 'cat a dog', )
    refute_tsq_match( tsq, 'cat _ dog', )
  end

  def test_phrase_apostrophe
    # As of 9.6.2 this phrase won't match itself.
    assert_gen( "cat's <-> rat", %{"cat's rat"} )
    assert_tsq( tsq = "'cat' <-> 'rat'", %{"cat's rat"} )

    assert_tsq_match( tsq, "cat rat", )

    # to_tsvector('cat''s rat') -> 'cat':1 'rat':3
    refute_tsq_match( tsq, "cat's rat", )
  end

  def test_phrase_and
    assert_gen( "johnson <-> johnson", '"johnson & johnson"' )
    assert_tsq( tsq = "'johnson' <-> 'johnson'", '"johnson & johnson"' )

    # to_tsvector('johnson & johnson') -> 'johnson':1,2
    assert_tsq_match( tsq, "Johnson & Johnson", )

    # to_tsvector('Johnson A Johnson') -> 'johnson':1,3
    refute_tsq_match( tsq, "Johnson A Johnson", )
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
    skip( "For postgresql 9.6+" ) unless pg_gte_9_6?
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
    assert_gen( "!(, & ’y)", "-( , 'y -)" )
    assert_tsq( "!'y'",     "-( ,'y -)" )
    assert_gen( "!(, & ’y) & c3", "|-( , 'y -)c3" )
    assert_tsq( "!'y' & 'c3'", "|-( ,'y -)c3" )
  end

  def test_funk_2
    if ( PG_VERSION <=> [9,6,2] ) >= 0
      assert_tsq( "!!'boy' & 'cat'", "-(a -boy) & cat" )
    elsif pg_gte_9_6?
      # Crashes PG 9.6 beta 1-2, fixed in beta 3.
      assert_tsq( "'boy' & 'cat'", "-(a -boy) & cat" )
    else
      # PG 9.5 doesn't normalize away the double not
      assert_tsq( "!( !'boy' ) & 'cat'", "-(a -boy) & cat" )
    end
  end

  def test_gen_or_not
    assert_tsq( "'ape' & ( !'boy' | !'cat' )", "ape & ( -boy | -cat )" )
  end

end

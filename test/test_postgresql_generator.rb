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

require 'minitest/autorun'

require 'human-ql/query_parser'

require 'human-ql/postgresql_generator'

class TestPostgresqlGenerator < Minitest::Test
  TC = HumanQL::QueryParser.new
  PG = HumanQL::PostgreSQLGenerator.new

  def assert_gen( expected_pg, hq )
    ast = TC.parse( hq )
    assert_equal( expected_pg, PG.generate( ast ), ast )
  end

  def test_gen_term
    assert_gen( 'dog', 'dog' )
  end

  def test_gen_and
    assert_gen( 'dog & boy', 'dog boy' )
  end

  def test_gen_phrase
    assert_gen( 'dog <-> boy', '"dog boy"' )
  end

  def test_gen_empty
    assert_gen( nil, '' )
  end

  def test_gen_not
    assert_gen( '!dog', '-dog' )
  end

  def test_gen_or
    assert_gen( '(dog | boy)', 'dog|boy' )
  end

  def test_gen_not_phrase
    assert_gen( '!(dog <-> boy)', '-"dog boy"' )
  end

  def test_gen_precedence_1
    assert_gen( '(dog | boy) & cat', 'dog | boy cat' )
  end

  def test_gen_precedence_2
    assert_gen( 'dog & (boy | cat)', 'dog boy | cat' )
  end

  def test_gen_precedence_3
    assert_gen( '(dog | !boy) & cat', 'dog | - boy cat' )
  end

  def test_gen_precedence_4
    assert_gen( '(!dog | boy) & cat', '-dog | boy cat' )
  end

  def test_gen_precedence_5
    assert_gen( '(dog | boy) & !cat', 'dog | boy -cat' )
  end

  def test_gen_precedence_6
    assert_gen( '(dog | boy) & !cat & d', 'dog | boy -cat d' )
  end

end

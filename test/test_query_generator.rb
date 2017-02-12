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
require 'human-ql/query_generator'

class TestQueryGenerator < Minitest::Test

  TC = HumanQL::QueryParser.new
  QG = HumanQL::QueryGenerator.new( parser: TC )

  A = 'a'
  B = 'b'
  C = 'c'
  D = 'd'
  E = 'e'
  FOO = 'FOO'

  def assert_gen( expected, ast )
    out = QG.generate( ast )
    assert_equal( expected, out, ast )
  end

  def test_empty
    assert_gen( nil, nil )
  end

  def test_simple
    assert_gen( 'a', A )
  end

  def test_default
    assert_gen( 'a b', [:and, A, B] )
  end

  def test_or
    assert_gen( 'a or b', [:or, A, B] )
  end

  def test_not
    assert_gen( '-a', [:not, A] )
  end

  def test_not_or
    assert_gen( '-(a or b)', [:not, [:or, A, B]] )
  end

  def test_not_and
    assert_gen( '-(a b)', [:not, [:and, A, B]] )
  end

  def test_scope
    assert_gen( 'FOO:a',        [FOO, A] )
    assert_gen( 'FOO:(a or b)', [FOO, [:or, A, B]] )
  end

  def test_complex_1
    assert_gen( 'a or b c or d',
                [:and, [:or, A, B], [:or, C, D]] )
  end

  def test_complex_2
    assert_gen( '"a b" -(c or d)',
                [:and, [:phrase, A, B], [:not, [:or, C, D]]] )
  end

  def test_complex_3
    assert_gen( '-(a b) or (c d) or e',
                [:or, [:not, [:and, A, B]], [:and, C, D], E] )
  end

end

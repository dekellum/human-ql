#!/usr/bin/env ruby

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

require_relative 'setup.rb'

require 'human-ql/query_parser'
require 'human-ql/tree_normalizer'

class TestingQueryParser < HumanQL::QueryParser
  def initialize
    super(scopes: [ 'FOO', ignorecase: true ],
          verbose: ARGV.include?('--verbose'))
  end
end

class TestQueryParser < Minitest::Test
  TC = TestingQueryParser.new
  DN = HumanQL::TreeNormalizer.new(not_scope: true)

  def test_norm_prefix
    assert_equal('-',      TC.norm_prefix('-'))
    assert_equal('- ',     TC.norm_prefix('- '))
    assert_equal('a-b',    TC.norm_prefix('a-b'))
    assert_equal('- a',    TC.norm_prefix('-a'))
    assert_equal('- ab',   TC.norm_prefix('-ab'))
    assert_equal('a - b',  TC.norm_prefix('a -b'))
    assert_equal('a - bc', TC.norm_prefix('a -bc'))
  end

  def test_norm_quote
    assert_equal(' " ',        TC.norm_infix('"'))
    assert_equal(' "  ',       TC.norm_infix('" '))
    assert_equal('a " b',      TC.norm_infix('a"b'))
    assert_equal(' " a',       TC.norm_infix('"a'))
    assert_equal(' " ab " ',   TC.norm_infix('"ab"'))
    assert_equal('a  " b " ',  TC.norm_infix('a "b"'))
    assert_equal('a  " bc " ', TC.norm_infix('a "bc"'))
  end

  def test_norm_parens_split
    assert_equal(' ( ',        TC.norm_infix('('))
    assert_equal(' (  ',       TC.norm_infix('( '))
    assert_equal(' ( a ) ',    TC.norm_infix('(a)'))
    assert_equal(' ( ab ) ',   TC.norm_infix('(ab)'))
    assert_equal('a  ( b ) ',  TC.norm_infix('a (b)'))
    assert_equal('a  ( bc ) ', TC.norm_infix('a (bc)'))
    assert_equal('a ( b ) ',   TC.norm_infix('a(b)'))
  end

  def test_norm_space
    assert_equal('foo', TC.norm_space('foo'))
    assert_equal('foo', TC.norm_space(' foo'))
    assert_equal('foo', TC.norm_space(' foo '))
    assert_equal('foo bar', TC.norm_space(" foo\t bar\r  "))
  end

  def test_norm_scope
    assert_equal('FOO: ', TC.norm_scope('FOO:'))
    assert_equal(' ', TC.norm_scope(':'))
    assert_equal(' ', TC.norm_scope(' :'))
    assert_equal(' after', TC.norm_scope(':after'))
    assert_equal(' after', TC.norm_scope(' :after'))

    assert_equal('FOO: bar', TC.norm_scope('FOO:bar'))
    assert_equal('FOO:  bar', TC.norm_scope('FOO: bar'))
    assert_equal('FOO:  bar', TC.norm_scope('FOO : bar'))

    assert_equal(' FOO: bar', TC.norm_scope(' FOO:bar'))
    assert_equal('a FOO: bar', TC.norm_scope('a FOO:bar'))
  end

  def test_norm_scope_undefined
    assert_equal('other  bar', TC.norm_scope('other : bar'))
    assert_equal('other  bar', TC.norm_scope('other: bar'))
    assert_equal('other bar', TC.norm_scope('other:bar'))

    assert_equal(' other  bar', TC.norm_scope(' other: bar'))
    assert_equal('a other  bar', TC.norm_scope('a other: bar'))
  end

  def test_normalize
    assert_nil(TC.normalize(nil))
    assert_nil(TC.normalize(''))
    assert_nil(TC.normalize(' '))
    assert_equal('a ( bc | d )', TC.normalize('a (bc|d)'))
    assert_equal('- ( a | b )',  TC.normalize('-(a|b)'))
  end

  A = 'a'
  B = 'b'
  C = 'c'
  D = 'd'
  E = 'e'
  FOO = 'FOO'

  def assert_parse(expected_tree, input)
    out = TC.parse(input)
    out = DN.normalize(out)
    if expected_tree.nil?
      assert_nil(out, input)
    else
      assert_equal(expected_tree, out, input)
    end
  end

  def test_parse_basic_1
    assert_parse('a', 'a')
  end

  def test_parse_basic_2
    assert_parse([ :and, A, B ], 'a b')
  end

  def test_parse_scope_basic
    assert_parse([ FOO, A ], 'FOO:a')
    assert_parse([ FOO, A ], 'FOO: a')
    assert_parse([ FOO, A ], 'FOO : a')
    assert_parse([ :and, [ FOO, A ], [ FOO, B ] ], 'FOO : a FOO:b')
    assert_parse([ :or, [ FOO, A ], [ FOO, B ] ], 'FOO : a | FOO:b')
  end

  def test_parse_scope_complex
    assert_parse([ FOO, [ :phrase, A, B ] ], 'FOO:"a b"')
    assert_parse([ FOO, [ :and, A, B ] ], 'FOO:(a b)')
    assert_parse([ FOO, [ :or, A, B ] ], 'FOO:(a|b)')
  end

  def test_parse_scope_not
    assert_parse([ FOO, [ :not, A ] ], 'FOO:-a')
  end

  def test_parse_not_scope_paren
    assert_parse([ :not, [ FOO, A ] ], '-(FOO:a)')
  end

  def test_parse_not_scope
    assert_parse([ FOO, A ], '- FOO:a')
    assert_parse([ :and, [ :not, FOO ], A ], '-FOO:a')
  end

  def test_parse_phrase
    assert_parse([ :phrase, A, B ], '"a b"')
  end

  def test_parse_empty
    assert_parse(nil, '')
  end

  def test_parse_empty_phrase
    assert_parse(nil, '"')
    assert_parse(nil, '""')
  end

  def test_parse_not
    assert_parse([ :not, A ], '-a')
  end

  def test_parse_not_noop
    assert_parse(nil, '-')
  end

  def test_parse_or
    assert_parse([ :or, A, B ], 'a|b')
  end

  def test_parse_or_noop_0
    assert_parse(nil, '|')
    assert_parse(nil, '||')
    assert_parse(nil, '|&')
    assert_parse(nil, '&|')
    assert_parse(nil, '-|')
    assert_parse(nil, '|-')
  end

  def test_noop_trailing_not
    assert_parse(A, 'a -')
  end

  def test_noop_trailing_or
    assert_parse([:and, A, B], 'a b |')
  end

  def test_noop_leading_or
    assert_parse([:and, A, B], '| a b')
  end

  def test_parse_or_noop_1
    assert_parse(A, '|a')
  end

  def test_parse_or_noop_2
    assert_parse(A, 'a|')
  end

  def test_parse_and_noop_1
    assert_parse(A, '&a')
  end

  def test_parse_and_noop_2
    assert_parse(A, 'a&')
  end

  def test_parse_not_phrase
    assert_parse([ :not, [ :phrase, A, B ] ], '-"a b"')
  end

  def test_parse_parens_empty
    assert_parse(nil, '()')
  end

  def test_parse_adj_parens
    assert_parse([:and, A, B], '(a)b')
    assert_parse([:and, [:not, 'a-' ], B], '-(a-)b')
    assert_parse([:and, [:not, A], B], '-(a)b')
  end

  def test_parse_parens_0
    assert_parse(A, '(a)')
  end

  def test_parse_parens_1
    assert_parse([ :and, A, B ], '(a b)')
  end

  def test_parse_parens_2
    assert_parse([ :and, [ :or, A, B ], C ], '(a|b) c')
  end

  def test_parse_parens_3
    assert_parse([ :and, C, [ :or, A, B ] ], 'c (a|b)')
  end

  def test_parse_parens_4
    assert_parse([ :and, D, [ :or, A, B, C ] ], 'd (a|b|c)')
  end

  def test_parse_parens_5
    assert_parse([ :and, [ :or, A, B ], [ :or, C, D ] ], '(a|b) (c|d)')
    assert_parse([ :and, [ :or, A, B ], [ :or, C, D ] ], '((a|b) (c|d))')
  end

  def test_parse_parens_6
    assert_parse([ :or, [ :and, A, B ], [ :and, C, D ] ], '((a&b) | (c&d))')
    assert_parse([ :or, [ :and, A, B ], [ :not, [ :and, C, D ] ] ],
                 '((a&b) | -(c&d))')
    assert_parse([ :or, [ :not, [ :and, A, B ] ], [ :and, C, D ], E ],
                 '(-(a&b) | (c&d) | e )')
  end

  def test_parens_and_quotes
    assert_parse([:phrase, 'a' ], '"(a)"')
    assert_parse([ :or, [ :and, A, B ], [ :and, C, D ] ], '((a&b) |"(c&d))')
    assert_parse([ :or, [ :and, A, B ], [ :and, C, D ] ], '((a&b) |(c&d)")')
    assert_parse([ :and, [ :or, [ :and, A, B ], C ], D ], '((a&b) |(c&"d))')
    assert_parse([ :or, [ :and, A, B ], [ :and, [:phrase, C], D ] ],
                 '((a&b) |("c))"&d))')
  end

  def test_parse_precedence_1
    assert_parse([ :and, [ :or, A, B ], C ], 'a | b c')
  end

  def test_parse_precedence_2
    assert_parse([ :and, A, [ :or, B, C ] ], 'a b | c')
  end

  def test_parse_precedence_3
    assert_parse([ :and, [ :or, A, [ :not, B ] ], C ], 'a | - b c')
  end

  def test_parse_precedence_4_explicit
    assert_parse([ :and, [ :or, [ :not, A ], B ], C ], '-a | b & c')
  end

  def test_parse_precedence_4_implied
    assert_parse([ :and, [ :or, [ :not, A ], B ], C ], '-a | b c')
  end

  def test_parse_precedence_5_explicit
    assert_parse([ :and, [ :or, A, B ], [ :not, C ] ], 'a | b AND -c')
  end

  def test_parse_precedence_5_implied
    assert_parse([ :and, [ :or, A, B ], [ :not, C ] ], 'a | b -c')
  end

  def test_parse_precedence_6
    assert_parse([ :and, [ :or, A, B ], [ :not, C ], D ], 'a | b -c d')
  end

  def test_parse_empty_not
    assert_parse(A, 'a -""')
  end

end

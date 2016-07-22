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

require 'human-ql/tree_normalizer'

class TestTreeNormalizer < Minitest::Test
  DN = HumanQL::TreeNormalizer.new
  UN = HumanQL::TreeNormalizer.new( unconstrained_not: false )

  A = 'a'
  B = 'b'
  C = 'c'
  D = 'd'
  E = 'e'

  S1 = 'S1'
  S2 = 'S2'

  def assert_norm( normalizer, expected, input )
    output = normalizer.normalize( input )
    assert_equal( expected, output, input )
  end

  def assert_norm_identity( normalizer, id )
    assert_norm( normalizer, id, id )
  end

  def test_basic_norm_0
    assert_norm( DN, nil, nil )
    assert_norm( DN, nil, [ :and ] )
  end

  def test_basic_norm_1
    assert_norm( DN, A, A )
  end

  def test_basic_norm_2
    assert_norm( DN, A, [ :or, [ :and ], A ] )
  end

  def test_basic_norm_3
    assert_norm( DN, [ :and, A, B ], [ :and, [ :and, A, B ] ] )
  end

  def test_not
    assert_norm( DN, [ :not, A ], [ :not, A ] )
    assert_norm( DN, [ :not, A ], [ :not, A, B ] )
  end

  def test_nested_not
    assert_norm( DN, nil, [ :not, [ :not, A ] ] )
    assert_norm( DN, [ :not, B], [ :not, [ :and, [ :not, A ], B ] ])
  end

  def test_scope
    assert_norm( DN, [ S1, A ], [ S1, A ] )
    assert_norm( DN, [ S1, A ], [ S1, A, B ] )
  end

  def test_nested_scope
    assert_norm( DN, [ S2, A ], [ S2, [ :and, A, [ S1, B ] ] ] )
    assert_norm( DN, [ S2, [ :or, A, C ] ], [ S2, [ :or, A, [ S1, B ], C ] ] )
  end

  def test_nested_same_scope
    assert_norm( DN, [ S2, [ :and, A,       B ] ],
                     [ S2, [ :and, A, [ S2, B ] ] ] )
  end

  def test_scope_not
    assert_norm_identity( DN, [ S1, [ :not, A ] ] )
  end

  def test_not_scope
    assert_norm( DN, [ :not, [ S1, A ] ], [ :not, [ S1, A ] ] )
  end

  def test_unconstrained_scope_not
    assert_norm( UN, nil, [ S1, [ :not, A ] ] )
  end

  def test_unconstrained_not_scope
    assert_norm( UN, nil, [ :not, [ S1, A ] ] )
  end

  def test_unconstrained_not
    assert_norm( UN, nil, [ :not, A ] )
    assert_norm( UN, B, [ :or, [ :not, A ], B ] )
  end

  def test_unconstrained_not_complex
    assert_norm( UN, nil, [ :and, [ :not, A ], [ :not, A ] ] )
    assert_norm( UN, B, [ :and, [ :not, A ], [ :or, [ :not, A ], B ] ] )
  end

  def test_constrained_not
    assert_norm_identity( UN, [ :and, [ :not, A ], B ] )
    assert_norm_identity( UN, [ :and, A, [ :or, [ :not, B ], [ :not, C ] ] ] )
    assert_norm_identity( UN, [ :and, [ :or, A, D ],
                                      [ :or, [ :not, B ], [ :not, C ] ] ] )
    assert_norm_identity( UN, [ :and, [ :not, A ],
                                      [ :or, [ :and, [ :not, B ], C ], D ] ] )
  end

end

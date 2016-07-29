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

module HumanQL

  # Generate query strings suitable for passing to PostgreSQL's
  # to_tsquery function, from a HumanQL abstract syntax tree (AST).
  #
  # In order to guarantee valid output for any human input, the AST
  # should be created using PostgreSQLCustomParser and normalized via
  # TreeNormalizer (with minimal defaults).
  #
  # Any scope's provided in the parser should have been handled and
  # stripped out of the AST, as PostgreSQL is not expected to have a
  # direct equivalent in tsquery syntax.
  class PostgreSQLGenerator

    #--
    # From https://www.postgresql.org/docs/9.6/static/datatype-textsearch.html
    # > In the absence of parentheses, '!' (NOT) binds most tightly,
    # > and '&' (AND) and '<->' (FOLLOWED BY) both bind more tightly
    # > than | (OR).
    #++

    AND = ' & '.freeze
    OR = ' | '.freeze
    NOT = '!'.freeze
    NEAR = ' <-> '.freeze

    # Given the root node of the AST, return a string in PostgreSQL
    # tsquery syntax.
    def generate( node )
      op,*args = node
      if ! node.is_a?( Array )
        op
      elsif args.empty?
        nil
      else
        case op
        when :and
          terms_join( args, AND )
        when :or
          pwrap( terms_join( args, OR ) )
        when :not
          raise "Weird! #{node.inspect}" unless args.length == 1
          if args[0].is_a?( Array )
            NOT + pwrap( generate( args[0] ) )
          else
            NOT + args[0]
          end
        when :phrase
          terms_join( args, NEAR )
        else
          raise "Unsupported op: #{node.inspect}"
        end
      end
    end

    protected

    def terms_join( args, op )
      args.map { |a| generate( a ) }.join( op )
    end

    def pwrap( inner )
      '(' + inner + ')'
    end

  end

end

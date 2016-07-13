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

  # Reliably generate queries suitable for PostgreSQL's to_tsquery
  # function, from a HumanQL abstract syntax tree AST.
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

    def extra_norm( node, allow_not = true )
      op,*args = node
      if ! node.is_a?( Array )
        op
      elsif args.empty?
        nil
      elsif op == :not && !allow_not
        nil
      else
        a_not = allow_not && ( op == :and )
        out = []
        args.each do |a|
          a = extra_norm( a, a_not )
          if a.is_a?( Array ) && a[0] == op
            out += a[1..-1]
          elsif a # filter nil
            out << a
          end
        end
        if ( op == :and || op == :or ) && out.length < 2
          out[0]
        elsif out.empty?
          nil
        else
          out.unshift( op )
        end
      end
    end

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

    def terms_join( args, op )
      args.map { |a| generate( a ) }.join( op )
    end

    def pwrap( inner )
      '(' + inner + ')'
    end

  end

end

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

module HumanQL

  # Generate a Human Query Language String from an abstract syntax
  # tree (AST). This allows query simplification (e.g. via
  # TreeNormalizer) and re-writing queries.
  class QueryGenerator

    # The AND operator (if not default).
    # Default: ' and '
    attr_accessor :and

    # The OR operator (if not default).
    # Default: ' or '
    attr_accessor :or

    # The NOT operator.
    # Default: '-'
    attr_accessor :not

    # SPACE delimiter.
    # Default: ' '
    attr_accessor :space

    # Left quote character for phrases.
    # Default: '"'
    attr_accessor :lquote

    # Right quote character for phrases.
    # Default: '"'
    attr_accessor :rquote

    # COLON character used a prefix delimiter.
    # Default: ':'
    attr_accessor :colon

    # Left parenthesis character.
    # Default: '('
    attr_accessor :lparen

    # Right parenthesis character.
    # Default: ')'
    attr_accessor :rparen

    # The default operator (:and or :or). If set, will output a :space
    # instead of the operator.
    # Default: nil
    attr_accessor :default_op

    # Hash of operators to precedence integer values, as per
    # QueryParser#precedence. If set, outputs parentheses only when
    # precedence dictates that it is necessary.
    # Default: nil
    attr_accessor :precedence

    # Set #default_op and #precedence from the given QueryParser, as a
    # convenience.
    def parser=(p)
      @default_op = p.default_op
      @precedence = p.precedence
    end

    # Construct given options which are interpreted as attribute names
    # to set.
    def initialize(opts = {})
      @and = ' and '.freeze
      @or = ' or '.freeze
      @not = '-'.freeze
      @space = ' '.freeze
      @lquote = @rquote = '"'.freeze
      @colon = ':'.freeze
      @lparen = '('.freeze
      @rparen = ')'.freeze
      @default_op = nil
      @precedence = nil

      opts.each do |name,val|
        send(name.to_s + '=', val)
      end
    end

    # Given the root node of the AST, return a String in Human Query
    # Language syntax.
    def generate(node)
      op,*args = node
      if ! node.is_a?(Array)
        op
      elsif args.empty?
        nil
      else
        case op
        when :and
          terms_join(args, :and)
        when :or
          terms_join(args, :or)
        when :not
          @not + pwrap_gen(args[0], op)
        when :phrase
          @lquote + args.join(@space) + @rquote
        when String
          op + @colon + pwrap_gen(args[0], op)
        else
          raise "Unsupported op: #{node.inspect}"
        end
      end
    end

    protected

    def terms_join(args, op)
      args = args.map { |a| pwrap_gen(a, op) }
      if op == @default_op
        args.join(@space)
      elsif op == :and
        args.join(@and)
      elsif op == :or
        args.join(@or)
      end
    end

    def pwrap_gen(node, parent_op)
      if node.is_a?(Array)
        op = node[0]
        if precedence_lte?(parent_op, op)
          generate(node)
        else
          pwrap(generate(node))
        end
      else
        node
      end
    end

    def pwrap(inner)
      @lparen + inner + @rparen
    end

    def precedence_lte?(op1, op2)
      if @precedence
        @precedence[op1] <= @precedence[op2]
      else
        false
      end
    end

  end

end

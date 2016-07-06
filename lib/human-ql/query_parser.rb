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

  # Human language, lenient query parser
  #
  # This adapts the infix precedence handling and operator stack of the
  # {Shunting Yard Algorithm}[https://en.wikipedia.org/wiki/Shunting-yard_algorithm]
  # originally described by Edsger Dijkstra.
  #
  # This class serves as a container of various contants. These are
  # always referenced internally via `self::` so that they may be
  # overridden with matching named contants in a derived class.
  # The token matching constants are matched via `===` so that either
  # Regexp or String values may be set.
  class QueryParser

    #--
    # Supported syntax:
    # "a b c" --> " a b c "  --> [ :phrase, a, b, c ]
    # a b c (default :and)   --> [ :and, a, b, c ]
    # a OR b, a|b -> a | b   --> [ :or, a, b ]
    # a AND B, a&B --> a & B --> [ :and, a, b ]
    # a AND ( B OR C )       --> [ :and, a, [ :or, B, C ] ]
    # SCOPE:token            --> [ SCOPE, token ]
    # NOT C, -C -> '- C'     --> [ :not, C ]
    # ALSO '-(A|B)'          --> [ :not, [ :or, A, B] ]
    # ALSO '-"a b"'          --> [ :not, [ :phrase, a b ] ]
    #
    # FIXME, Might add: SCOPE:( parenthetical... ) and SCOPE:"a phrase"
    #
    # FIXME: Additional special characters to be filtered out:
    # ":" when not matching a scope, replace with space
    # "*" to_tsquery significant
    # "!" (Used by Postgresql as not)
    #
    # FIXME: Add support for disabling certain diabolic expressions
    # like top level not, or a not in top-level :or branch, i.e.:
    # "-rare" or "foo|-bar"
    #
    #++

    SP  = "[[:space:]]".freeze
    NSP = "[^#{SP}]".freeze
    SPACES = /#{SP}+/.freeze

    # Lookup Hash for the precedence of supported operators.  To limit
    # user surprise, the DEFAULT_OP should be lowest.
    PRECEDENCE = {
      not: 3,
      or:  2,
      and: 1
    }.freeze

    OR_TOKEN = /\A(OR|\|)\z/i.freeze
    AND_TOKEN = /\A(AND|\&)\z/i.freeze
    NOT_TOKEN = /\A(NOT|\-)\z/i.freeze

    SCOPE = /\A(FOO|BAR):(.+)/.freeze #FIXME

    LQUOTE = '"'.freeze
    RQUOTE = '"'.freeze
    LPAREN = '('.freeze
    RPAREN = ')'.freeze

    INFIX_TOKEN = /[()|&"]/.freeze
    PREFIX_TOKEN = /(?<=\A|#{SP})-(?=#{NSP})/.freeze

    private_constant :PRECEDENCE, :OR_TOKEN, :AND_TOKEN, :NOT_TOKEN,
                     :SCOPE, :LQUOTE, :RQUOTE, :LPAREN, :RPAREN
                     #:SP, :NSP, :SPACES

    attr_reader :default_op, :precedence, :verbose

    def initialize( opts = {} )
      @default_op = :and
      @precedence = PRECEDENCE
      @spaces = SPACES
      @or_token  =  OR_TOKEN
      @and_token = AND_TOKEN
      @not_token = NOT_TOKEN
      @scope = SCOPE
      @lquote = LQUOTE
      @rquote = RQUOTE
      @lparen = LPAREN
      @rparen = RPAREN
      @verbose = false
      @infix_token = INFIX_TOKEN
      @prefix_token = PREFIX_TOKEN

      opts.each do |k,v|
        var = "@#{k}".to_sym
        if instance_variable_defined?( var )
          instance_variable_set( var, v )
        else
          raise "QueryParser unsupported option #{k.inspect}"
        end
      end
    end

    def parse( q )
      q = normalize( q )
      tokens = q ? q.split(' ') : []
      tree_norm( parse_tree( tokens ) )
    end

    def parse_tree( tokens )
      s = ParseState.new( self )
      while ( t = tokens.shift )
        case t
        when @lquote
          rqi = tokens.index { |tt| @rquote === tt }
          if rqi
            s.push_term( [ :phrase, *tokens[0...rqi] ] )
            tokens = tokens[rqi+1..-1]
          end # else ignore
        when @lparen
          rpi = tokens.rindex { |tt| @rparen === tt } #last
          if rpi
            s.push_term( parse_tree( tokens[0...rpi] ) )
            tokens = tokens[rpi+1..-1]
          end # else ignore
        when @rquote
        #ignore
        when @rparen
        #ignore
        when @scope
          s.push_term( [ $1, $2 ] )
        when @or_token
          s.push_op( :or )
        when @and_token
          s.push_op( :and )
        when @not_token
          s.push_op( :not )
        else
          s.push_term( t )
        end
      end
      s.flush_tree
    end

    def tree_norm( node )
      op,*args = node
      if ! node.is_a?( Array )
        op
      elsif args.empty?
        # FIXME: warn "WTF? 1 #{op.inspect}" unless op.is_a?( String )
        nil
      else
        out = []
        args.each do |a|
          a = tree_norm( a )
          if a.is_a?( Array ) && a[0] == op
            out += a[1..-1]
          elsif a # filter nil
            out << a
          end
        end
        if ( op == :and || op == :or ) && out.length < 2
          out[0]
        else
          out.unshift( op )
        end
      end
    end

    # Treat various punctuation form operators as _always_ being
    # seperate tokens.
    # Note: Must always call norm_space _after_ this
    def norm_infix( q )
      q.gsub( @infix_token, ' \0 ' )
    end

    # Split prefixes as seperate tokens
    def norm_prefix( q )
      q.gsub( @prefix_token, '\0 ' )
    end

    def norm_space( q )
      q.gsub(@spaces, ' ').strip
    end

    def normalize( q )
      q ||= ''
      q = norm_infix( q )
      q = norm_prefix( q )
      q = norm_space( q )
      q unless q.empty?
    end

    class ParseState

      def initialize( parser )
        @default_op = parser.default_op
        @precedence = parser.precedence
        @verbose = parser.verbose
        @node = [ @default_op ]
        @ops = []
        @has_op = true
        log
      end

      def log( l = nil )
        $stderr.puts( l ) if @verbose
      end

      def dump( fr )
        if @verbose
          log( "%2s ops: %-12s node: %-30s" %
               [ fr, @ops.inspect, @node.inspect ] )
        end
      end

      def push_term( t )
        unless @has_op
          push_op( @default_op )
        end
        @node << t
        @has_op = false
        dump 'PT'
      end

      def precedence_lte?( op1, op2 )
        @precedence[op1] <= @precedence[op2]
      end

      def push_op( op )
        # Possible special case implied DEFAULT_OP in front of :not
        # FIXME: Guard against DEFAULT_OP being set to not
        if op == :not && !@has_op
          push_op( @default_op )
        end
        loop do
          last = @ops.last
          if last && precedence_lte?( op, last )
            @ops.pop
            op_to_node( last )
            dump 'PL'
          else
            break
          end
        end
        @ops << op
        @has_op = true
        dump 'PO'
      end

      def flush_tree
        while( last = @ops.pop )
          op_to_node( last )
          dump 'FO'
        end
        @node
      end

      def pop_term
        @node.pop if @node.length > 1
      end

      def op_to_node( op )
        o1 = pop_term
        if o1
          if op == :not
            @node << [ :not, o1 ]
          else
            o0 = pop_term
            if o0
              if @node[0] == op
                @node << o0 << o1
              else
                @node << [ op, o0, o1 ]
              end
            else
              if @node[0] == op
                @node << o1
              else
                @node = [ op, @node, o1 ]
              end
            end
          end
        else
          log "No argument to #{op.inspect}, ignoring"
        end
      end
    end

  end

end

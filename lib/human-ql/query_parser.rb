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

module HumanQL

  # Human friendly, lenient query parser. Parses an arbitrary input
  # string and outputs an abstract syntax tree (AST), which uses ruby
  # arrays as S-expressions.
  #
  # === Supported Syntax Summary
  #
  # As per defaults. In the table below, input string variations are shown at
  # left separated by ','; and output AST is shown on the right.
  #
  #    a                        --> 'a'
  #    "a b c"                  --> [ :phrase, 'a', 'b', 'c' ]
  #    a b c                    --> [ :and, 'a', 'b', 'c' ]
  #    a OR b, a|b              --> [ :or, 'a', 'b' ]
  #    a AND b, a&b             --> [ :and, 'a', 'b' ]
  #    a b|c                    --> [ :and, 'a', [:or, 'b', 'c'] ]
  #    (a b) OR (c d)           --> [ :or, [:and, 'a', 'b'], [:and, 'c', 'd'] ]
  #    NOT expr, -expr          --> [ :not, expr ]
  #    SCOPE:expr, SCOPE : expr --> [ 'SCOPE', expr ]
  #
  # Where:
  # * 'expr' may be simple term, phrase, or parenthetical expression.
  # * SCOPEs must be specified. By default, no scopes are
  #   supported.
  #
  # The AST output from #parse may have various no-ops and
  # redundancies. Run it through a TreeNormalizer to avoid seeing or
  # needing to handle these cases.
  #
  # === Customization
  #
  # The lexing and token matching patterns, as well as other
  # attributes used in the parser may be adjusted via constructor
  # options or attribute writer methods. Many of these attributes may
  # either be String constants or Regex patterns supporting multiple
  # values as needed.  Some features may be disabled by setting these
  # values to nil (e.g. match no tokens). While accessors are defined,
  # internally the instance variables are accessed directly for
  # speed. Tests show this is as fast as using constants (which would
  # be harder to modify) and faster than reader method calls.
  #
  # === Implementation Notes
  #
  # The parser implementation adapts the infix precedence handling and
  # operator stack of the
  # {Shunting Yard Algorithm}[https://en.wikipedia.org/wiki/Shunting-yard_algorithm]
  # originally described by Edsger Dijkstra. Attributes #default_op
  # and #precedence control the handling of explicit or implied infix
  # operators.
  class QueryParser

    # String pattern for Unicode spaces
    SP  = "[[:space:]]".freeze

    # String pattern for Unicode non-spaces
    NSP = "[^#{SP}]".freeze

    # Regex for 1-to-many Unicode spaces
    SPACES = /#{SP}+/.freeze

    # Default precedence of supported operators.
    DEFAULT_PRECEDENCE = {
      not: 11,
      or:  2,
      and: 1
    }.freeze

    # The default operator when none is otherwise given between parsed
    # terms.
    # Default: :and
    attr_accessor :default_op

    # Hash of operators to precedence Integer values.  The hash should
    # also provide a default value for unlisted operators like any
    # supported scopes. To limit human surprise, the #default_op
    # should have the lowest precedence.  The default is as per
    # DEFAULT_PRECEDENCE with a default value of 10, thus :not has the
    # highest precedence at 11.
    attr_accessor :precedence

    # Pattern matching one or more characters to treat as white-space.
    # Default: SPACES
    attr_accessor :spaces

    # Pattern used for lexing to treat certain punctuation characters as
    # separate tokens, even if they are not space separated.
    # Default: Pattern matching any characters '(', ')', '|', '&', '"' as used
    # as operator/parenthesis tokens in the defaults below.
    attr_accessor :infix_token

    # Pattern used for lexing to treat certain characters as separate
    # tokens when appearing as a prefix only.
    # Default '-' (as used in default #not_tokens)
    attr_accessor :prefix_token

    # OR operator token pattern. Should match the entire token using
    # the '\A' and '/z' syntax for beginning and end of string.
    # Default: Pattern matching complete tokens 'OR', 'or', or '|'
    attr_accessor :or_token

    # AND operator token pattern. Should match the entire token using
    # the '\A' and '/z' syntax for beginning and end of string.
    # Default: Pattern matching complete tokens 'AND', 'and', or '&'
    attr_accessor :and_token

    # NOT operator token pattern. Should match the entire token using
    # the '\A' and '/z' syntax for beginning and end of string.
    # Default: Pattern matching complete tokens 'NOT', 'not', or '-'
    attr_accessor :not_token

    # Left quote pattern or value
    # Default: '"'
    attr_accessor :lquote

    # Right quote pattern or value. Its fine if this is the same as #lquote.
    # Default: '"'
    attr_accessor :rquote

    # Left parentheses pattern or value
    # Default: '('
    attr_accessor :lparen

    # Right parentheses pattern or value
    # Default: ')'
    attr_accessor :rparen

    # Given one or an Array of scope prefixes, generate the #scope and
    # #scope_token patterns. A trailing hash is interpreted
    # as options, see below.
    #
    # ==== Options
    #
    # :ignorecase:: If true, generate case insensitive regexes and
    #               upcase the scope in AST output (per #scope_upcase)
    def scopes=(scopes)
      scopes = Array(scopes)
      opts = scopes.last.is_a?(Hash) && scopes.pop || {}
      ignorecase = !!(opts[:ignorecase])
      if scopes.empty?
        @scope = nil
        @scope_token = nil
      elsif scopes.length == 1 && !ignorecase
        s = scopes.first
        @scope = (s + ':').freeze
        @scope_token = /((?<=\A|#{SP})(#{s}))?#{SP}*:/.freeze
      else
        opts = ignorecase ? Regexp::IGNORECASE : nil
        s = Regexp.union(*scopes).source
        @scope = Regexp.new('\A(' + s + '):\z', opts).freeze
        @scope_token = Regexp.new("((?<=\\A|#{SP})(#{s}))?#{SP}*:",
                                   opts).freeze
      end
      @scope_upcase = ignorecase
      nil
    end

    # Scope pattern or value matching post-normalized scope token,
    # including trailing ':' but without whitespace.
    # Default: nil -> no scopes
    attr_accessor :scope

    # SCOPE unary operator pattern used for lexing to treat a scope
    # prefix, e.g. 'SCOPE' + ':', with or without internal or trailing
    # whitespace as single token. Used by #norm_scope, where it also
    # treats a non-matching ':' as whitespace. This would normally be
    # set via #scopes=.
    # Default: nil -> no scopes
    attr_accessor :scope_token

    # Should scope tokens be capitalized in the AST? This would imply
    # case-insensitive #scope, and #scope_token as generated via
    # #scopes= with the `ignorecase: true` option.
    # Default: false
    attr_accessor :scope_upcase

    # If true, log parsing progress and state to $stderr.
    # Default: false
    attr_accessor :verbose

    # Construct given options which are interpreted as attribute names
    # to set.
    def initialize(opts = {})
      @default_op = :and

      @precedence = Hash.new(10)
      @precedence.merge!(DEFAULT_PRECEDENCE)
      @precedence.freeze

      @spaces = SPACES
      @infix_token  = /[()|&"]/.freeze
      @prefix_token = /(?<=\A|#{SP})-(?=#{NSP})/.freeze
      @or_token  = /\A(OR|\|)\z/i.freeze
      @and_token = /\A(AND|\&)\z/i.freeze
      @not_token = /\A(NOT|\-)\z/i.freeze
      @lquote = @rquote = '"'.freeze
      @lparen = '('.freeze
      @rparen = ')'.freeze

      @scope = nil
      @scope_token = nil
      @scope_upcase = false

      @verbose = false

      opts.each do |name,val|
        send(name.to_s + '=', val)
      end
    end

    def parse(q)
      unless @default_op == :and || @default_op == :or
        raise("QueryParser#default_op is (#{@default_op.inspect}) " +
               "(should be :and or :or)")
      end
      q = normalize(q)
      tokens = q ? q.split(' ') : []
      log { "Parse: " + tokens.join(' ') }
      ast = parse_tree(tokens)
      log { "AST: " + ast.inspect }
      ast
    end

    def log(l = nil)
      if @verbose
        l = yield if block_given?
        $stderr.puts(l)
      end
    end

    def parse_tree(tokens)
      s = ParseState.new(self)
      while (t = tokens.shift)
        case t
        when @lquote
          rqi = tokens.index { |tt| @rquote === tt }
          if rqi
            s.push_term([ :phrase, *norm_phrase_tokens(tokens[0...rqi]) ])
            tokens = tokens[rqi+1..-1]
          end # else ignore
        when @lparen
          rpi = rparen_index(tokens)
          if rpi
            s.push_term(parse_tree(tokens[0...rpi]))
            tokens = tokens[rpi+1..-1]
          end # else ignore
        when @rquote
        #ignore
        when @rparen
        #ignore
        when @scope
          s.push_op(scope_op(t))
        when @or_token
          s.push_op(:or)
        when @and_token
          s.push_op(:and)
        when @not_token
          s.push_op(:not)
        else
          s.push_term(norm_term(t))
        end
      end
      s.flush_tree
    end

    # Given scope token, return the name (minus trailing ':'),
    # upcased if #scope_upcase.
    def scope_op(token)
      t = token[0...-1]
      t.upcase! if @scope_upcase
      t
    end

    # Find token matching #rparen in remaining tokens.
    def rparen_index(tokens)
      li = 1
      phrase = false
      tokens.index do |tt|
        if phrase
          phrase = false if @rquote === tt
        else
          case tt
          when @rparen
            li -= 1
          when @lparen
            li += 1
          when @lquote
            phrase = true
          end
        end
        (li == 0)
      end
    end

    # Treat various punctuation form operators as _always_ being
    # separate tokens per #infix_token pattern.
    # Note: Must always call norm_space _after_ this.
    def norm_infix(q)
      q.gsub(@infix_token, ' \0 ')
    end

    # Split prefixes as separate tokens per #prefix_token pattern.
    def norm_prefix(q)
      if @prefix_token
        q.gsub(@prefix_token, '\0 ')
      else
        q
      end
    end

    # If #scope_token is specified, normalize scopes as separate
    # 'SCOPE:' tokens.
    # This expects the 2nd capture group of #scope_token to be the
    # actual matching scope name, if present.
    def norm_scope(q)
      if @scope_token
        q.gsub(@scope_token) do
          if $2
            $2 + ': '
          else
            ' '
          end
        end
      else
        q
      end
    end

    # Normalize any whitespace to a single ASCII SPACE character and
    # strip leading/trailing whitespace.
    def norm_space(q)
      q.gsub(@spaces, ' ').strip
    end

    # Runs the suite of initial input norm_* functions. Returns nil if
    # the result is empty.
    def normalize(q)
      q ||= ''
      q = norm_infix(q)
      q = norm_scope(q)
      q = norm_prefix(q)
      q = norm_space(q)
      q unless q.empty?
    end

    # Select which tokens survive in a phrase. Also passes each token
    # though #norm_term. Tokens matching #lparen and #rparen are
    # dropped.
    def norm_phrase_tokens(tokens)
      tokens.
        reject { |t| @lparen === t || @rparen === t }.
        map { |t| norm_term(t) }
    end

    # No-op in this implementation but may be used to replace
    # characters. Should not receive nor return null or empty values.
    def norm_term(t)
      t
    end

    # Internal state keeping
    class ParseState # :nodoc:

      def initialize(parser)
        @default_op = parser.default_op
        @precedence = parser.precedence
        @verbose = parser.verbose
        @node = [ @default_op ]
        @ops = []
        @has_op = true
        @index = 0
        @last_term = -1
      end

      def log(l = nil)
        if @verbose
          l = yield if block_given?
          $stderr.puts(l)
        end
      end

      def dump(fr)
        if @verbose
          log("%2d %2s ops: %-12s node: %-30s" %
               [ @index, fr, @ops.inspect, @node.inspect ])
        end
      end

      def push_term(t)
        if @has_op
          @index += 1
        else
          push_op(@default_op)
        end
        @node << t
        @last_term = @index
        @has_op = false
        dump 'PT'
      end

      def precedence_lte?(op1, op2)
        @precedence[op1] <= @precedence[op2]
      end

      def unary?(op)
        (op == :not || op.is_a?(String))
      end

      def push_op(op)
        @index += 1
        # Possible special case implied DEFAULT_OP in front of :not or
        # :scope.
        if unary?(op)
          push_op(@default_op) unless @has_op
        elsif @node.length < 2 # no proceeding term
          log { "Ignoring leading #{op.inspect} (index #{@index})" }
          return
        end
        loop do
          n, last = @ops.last
          if last && precedence_lte?(op, last)
            @ops.pop
            op_to_node(n, last)
            dump 'PL'
          else
            break
          end
        end
        @ops << [ @index, op ]
        @has_op = true
        dump 'PO'
      end

      def flush_tree
        loop do
          n, last = @ops.pop
          break unless last
          op_to_node(n, last)
          dump 'FO'
        end
        @node
      end

      def pop_term
        @node.pop if @node.length > 1
      end

      def op_to_node(opi, op)
        if opi >= @last_term
          log { "Ignoring trailing #{op.inspect} (index #{opi})" }
          return
        end
        o1 = pop_term
        if o1
          if unary?(op)
            @node << [ op, o1 ]
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
          log { "No argument to #{op.inspect}, ignoring" }
        end
      end
    end

  end

end

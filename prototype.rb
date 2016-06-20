
# Supported syntax:
# "a b c" --> " a b c "  --> [ :phrase, a, b, c ]
# a b c (default :and)   --> [ :and, a, b, c ]
# a OR b, a|b -> a | b   --> [ :or, a, b ]
# a AND B, a&B --> a & B --> [ :and, a, b ]
# a AND ( B OR C )       --> [ :and, a, [ :or, B, C ] ]
# PREFIX:token           --> [ PREFIX, token ]
# NOT C, -C -> '- C'     --> [ :not, C ]
# ALSO '-(A|B)'          --> [ :not, [ :or, A, B] ]
# ALSO '-"a b"'          --> [ :not, [ :phrase, a b ] ]
#
# FIXME, Might add: PREFIX:( parenthetical... ) and PREFIX:"a phrase"
#
# FIXME: Additional special characters to be filtered out:
# ":" when not matching a prefix, replace with space
# "*" to_tsquery significant
#
# FIXME: Add support for disabling certain diabolic expressions like
# top level not or not in top-level or branch, i.e.: "-rare" or "foo|-bar"
#
# Via https://www.postgresql.org/docs/9.5/static/datatype-textsearch.html
#
# In the absence of parentheses, ! (NOT) binds most tightly, and &
# (AND) binds more tightly than | (OR).
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

  # The default operator to use when no (infix) operator is given
  # between terms.
  DEFAULT_OP = :and

  # Lookup Hash for the precedence of supported operators.  To limit
  # user surprise, the DEFAULT_OP should be lowest.
  PRECEDENCE = {
    not: 30,
    or: 20,
    and: 10
  }.freeze

  OR_TOKEN = /\A(OR|\|)\z/i.freeze
  AND_TOKEN = /\A(AND|\&)\z/i.freeze
  NOT_TOKEN = /\A(NOT|\-)\z/i.freeze

  PREFIX = /\A(FOO|BAR):(.+)/.freeze

  LQUOTE = '"'.freeze
  RQUOTE = '"'.freeze
  LPAREN = /\A\(\z/.freeze
  RPAREN = ')'.freeze

  SP  = "[[:space:]]".freeze
  NSP = "[^#{SP}]".freeze
  SPS = /#{SP}+/.freeze

  VERBOSE = false

  def self.parse( q )
    q = normalize( q )
    tokens = q ? q.split(' ') : []
    tree_norm( parse_tree( tokens ) )
  end

  def self.parse_tree( tokens )
    s = ParseState.new( self )
    while ( t = tokens.shift )
      case t
      when self::LQUOTE
        rqi = tokens.index { |tt| self::RQUOTE === tt }
        if rqi
          s.push_term( [ :phrase, *tokens[0...rqi] ] )
          tokens = tokens[rqi+1..-1]
        end # else ignore
      when self::LPAREN
        rpi = tokens.rindex { |tt| self::RPAREN === tt } #last
        if rpi
          s.push_term( parse_tree( tokens[0...rpi] ) )
          tokens = tokens[rpi+1..-1]
        end # else ignore
      when self::RQUOTE
        #ignore
      when self::RPAREN
        #ignore
      when self::PREFIX
        s.push_term( [ $1, $2 ] )
      when self::OR_TOKEN
        s.push_op( :or )
      when self::AND_TOKEN
        s.push_op( :and )
      when self::NOT_TOKEN
        s.push_op( :not )
      else
        s.push_term( t )
      end
    end
    s.flush_tree
  end

  def self.tree_norm( node )
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
        [ op, *out ]
      end
    end
  end

  def self.norm_quote_split( q )
    q.gsub( /(?<=\A|#{SP})"(?=#{NSP}+)/, '" ' ).
      gsub( /(?<=#{NSP})"(?=#{SP}|\z)/, ' "' )
  end

  # Treat various punctuation form operators as _always_ being
  # seperate tokens.
  # Must always call norm_space _after_ this
  def self.norm_opp_split( q )
    q.gsub( /[()|&]/, ' \0 ' )
  end

  # Split leading '-' to separate token
  def self.norm_pre_split( q )
    q.gsub( /(?<=\A|#{SP})\-(?=#{NSP}+)/, '- ' )
  end

  def self.norm_space( q )
    q.gsub(SPS, ' ').strip
  end

  def self.normalize( q )
    q ||= ''
    q = norm_opp_split( q )
    q = norm_pre_split( q )
    q = norm_quote_split( q )
    q = norm_space( q )
    q unless q.empty?
  end

  class ParseState

    def initialize( constants )
      @cm = constants
      @node = [ @cm::DEFAULT_OP ]
      @ops = []
      @has_op = true
      log
    end

    def log( l = nil )
      $stderr.puts( l ) if @cm::VERBOSE
    end

    def dump( fr )
      log( "%2s ops: %-12s node: %-30s" %
           [ fr, @ops.inspect, @node.inspect ] )
    end

    def push_term( t )
      unless @has_op
        push_op( @cm::DEFAULT_OP )
      end
      @node << t
      @has_op = false
      dump 'PT'
    end

    def precedence_lte?( op1, op2 )
      @cm::PRECEDENCE[op1] <= @cm::PRECEDENCE[op2]
    end

    def push_op( op )
      # Possible special case implied DEFAULT_OP in front of :not
      # FIXME: Guard against DEFAULT_OP being set to not
      if op == :not && !@has_op
        push_op( @cm::DEFAULT_OP )
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

require 'minitest/autorun'

class TestingQueryParser < QueryParser
  VERBOSE = ARGV.include?( '--verbose' )
end

class QueryParserTest < Minitest::Test
  TC = TestingQueryParser

  def test_norm_pre_split
    assert_equal( '-',      TC.norm_pre_split( '-' ) )
    assert_equal( '- ',     TC.norm_pre_split( '- ' ) )
    assert_equal( 'a-b',    TC.norm_pre_split( 'a-b' ) )
    assert_equal( '- a',    TC.norm_pre_split( '-a' ) )
    assert_equal( '- ab',   TC.norm_pre_split( '-ab' ) )
    assert_equal( 'a - b',  TC.norm_pre_split( 'a -b' ) )
    assert_equal( 'a - bc', TC.norm_pre_split( 'a -bc' ) )
  end

  def test_norm_quote_split
    assert_equal( '"',        TC.norm_quote_split( '"' ) )
    assert_equal( '" ',       TC.norm_quote_split( '" ' ) )
    assert_equal( 'a"b',      TC.norm_quote_split( 'a"b' ) )
    assert_equal( '" a',      TC.norm_quote_split( '"a' ) )
    assert_equal( '" ab "',   TC.norm_quote_split( '"ab"' ) )
    assert_equal( 'a " b "',  TC.norm_quote_split( 'a "b"' ) )
    assert_equal( 'a " bc "', TC.norm_quote_split( 'a "bc"' ) )
  end

  def test_norm_parens_split
    assert_equal( ' ( ',        TC.norm_opp_split( '(' ) )
    assert_equal( ' (  ',       TC.norm_opp_split( '( ' ) )
    assert_equal( ' ( a ) ',    TC.norm_opp_split( '(a)' ) )
    assert_equal( ' ( ab ) ',   TC.norm_opp_split( '(ab)' ) )
    assert_equal( 'a  ( b ) ',  TC.norm_opp_split( 'a (b)' ) )
    assert_equal( 'a  ( bc ) ', TC.norm_opp_split( 'a (bc)' ) )
    assert_equal( 'a ( b ) ',   TC.norm_opp_split( 'a(b)' ) )
  end

  def test_norm_space
    assert_equal( 'foo', TC.norm_space( 'foo' ) )
    assert_equal( 'foo', TC.norm_space( ' foo' ) )
    assert_equal( 'foo', TC.norm_space( ' foo ' ) )
    assert_equal( 'foo bar', TC.norm_space( " foo\t bar\r  " ) )
  end

  def test_normalize
    assert_equal( nil, TC.normalize( nil ) )
    assert_equal( nil, TC.normalize( '' ) )
    assert_equal( nil, TC.normalize( ' ' ) )
    assert_equal( 'a ( bc | d )', TC.normalize( 'a (bc|d)' ) )
    assert_equal( '- ( a | b )',  TC.normalize( '-(a|b)' ) )
  end

  A = 'a'
  B = 'b'
  C = 'c'
  D = 'd'

  def test_tree_norm_1
    assert_equal( A, TC.tree_norm( [:or, [:and], A ] ) )
  end

  def test_tree_norm_2
    assert_equal( [:and, A, B ], TC.tree_norm( [:and, [:and, A, B ] ] ) )
  end

  def assert_parse( expected_tree, input )
    assert_equal( expected_tree, TC.parse( input ), input )
  end

  def test_parse_basic_1
    assert_parse( 'a', 'a' )
  end

  def test_parse_basic_2
    assert_parse( [ 'FOO', A ], 'FOO:a' )
  end

  def test_parse_basic_3
    assert_parse( [ :and, A, B ], 'a b' )
  end

  def test_parse_phrase
    assert_parse( [ :phrase, A, B ], '"a b"' )
  end

  def test_parse_empty
    assert_parse( nil, '' )
  end

  def test_parse_empty_phrase
    assert_parse( nil, '"' )
    assert_parse( nil, '""' )
  end

  def test_parse_not
    assert_parse( [ :not, A ], '-a' )
  end

  def test_parse_not_noop
    assert_parse( nil, '-' )
  end

  def test_parse_or
    assert_parse( [ :or, A, B ], 'a|b' )
  end

  def test_parse_or_noop_0
    assert_parse( nil, '|' )
    assert_parse( nil, '||' )
    assert_parse( nil, '|&' )
    assert_parse( nil, '&|' )
    assert_parse( nil, '-|' )
    assert_parse( nil, '|-' )
  end

  def test_parse_or_noop_1
    assert_parse( A, '|a' )
  end

  def test_parse_or_noop_2
    assert_parse( A, 'a|' )
  end

  def test_parse_and_noop_1
    assert_parse( A, '&a' )
  end

  def test_parse_and_noop_2
    assert_parse( A, 'a&' )
  end

  def test_parse_not_phrase
    assert_parse( [ :not, [ :phrase, A, B ] ], '-"a b"' )
  end

  def test_parse_parens_empty
    assert_parse( nil, '()' )
  end

  def test_parse_parens_0
    assert_parse( A, '(a)' )
  end

  def test_parse_parens_1
    assert_parse( [ :and, A, B ], '(a b)' )
  end

  def test_parse_parens_2
    assert_parse( [ :and, [ :or, A, B ], C ], '(a|b) c' )
  end

  def test_parse_parens_3
    assert_parse( [ :and, C, [ :or, A, B ] ], 'c (a|b)' )
  end

  def test_parse_parens_4
    assert_parse( [ :and, D, [ :or, A, B, C ] ], 'd (a|b|c)' )
  end

  def test_parse_precedence_1
    assert_parse( [ :and, [ :or, A, B ], C ], 'a | b c' )
  end

  def test_parse_precedence_2
    assert_parse( [ :and, A, [ :or, B, C ] ], 'a b | c' )
  end

  def test_parse_precedence_3
    assert_parse( [ :and, [ :or, A, [ :not, B ] ], C ], 'a | - b c' )
  end

  def test_parse_precedence_4_explicit
    assert_parse( [ :and, [ :or, [ :not, A ], B ], C ], '-a | b & c' )
  end

  def test_parse_precedence_4_implied
    assert_parse( [ :and, [ :or, [ :not, A ], B ], C ], '-a | b c' )
  end

  def test_parse_precedence_5_explicit
    assert_parse( [ :and, [ :or, A, B ], [ :not, C ] ], 'a | b AND -c' )
  end

  def test_parse_precedence_5_implied
    assert_parse( [ :and, [ :or, A, B ], [ :not, C ] ], 'a | b -c' )
  end

  def test_parse_precedence_6
    assert_parse( [ :and, [ :or, A, B ], [ :not, C ], D ], 'a | b -c d' )
  end

end

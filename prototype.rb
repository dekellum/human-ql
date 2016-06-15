
# Supported syntax:
# "a b c" --> " a b c "  --> [ :phrase, a, b, c ]
# a OR b, a|b -> a | b   --> [ :or, a, b ]
# a AND B, a&B --> a & B --> [ :and, a, b ]
# a AND ( B OR C )       --> [ :and, a, [ :or, B, C ] ]
# PREFIX:token           --> [ PREFIX, token ]
# NOT C, -C -> '- C'     --> [ :not, C ]
# ALSO '-(A|B)'          --> [ :not, [ :or, A, B] ]
# ALSO '-"a b"'          --> [ :not, [ :phrase, a b ] ]
# POSSIBLY IN FUTURE: PREFIX:( parenthetical... )

# FIXME: Additional special characters to be filtered out:
# ":" when not matching a prefix, replace with space
# "*" to_tsquery significant

# Via https://www.postgresql.org/docs/9.5/static/datatype-textsearch.html
#
# In the absence of parentheses, ! (NOT) binds most tightly, and &
# (AND) binds more tightly than | (OR).

# FIXME:
# Use an operator stack? Like: https://en.wikipedia.org/wiki/Shunting-yard_algorithm

class QueryParseTree

  DEFAULT_OP = :and

  PRECEDENCE = {
    not: 30,
    or: 20,
    and: 10
  }

  OR_TOKEN = /\A(OR|\|)\z/i
  AND_TOKEN = /\A(AND|\&)\z/i
  NOT_TOKEN = /\A(NOT|\-)\z/i

  PREFIX = /\A(FOO|BAR):(.+)/
  # PREFIX_LPAREN = /\A(FOO|BAR):\(\z/

  LQUOTE = /\A"\z/
  RQUOTE = /\A"\z/
  LPAREN = /\A\(\z/
  RPAREN = /\A\)\z/

  SP  = "[[:space:]]"
  NSP = "[^#{SP}]"
  SPS = /#{SP}+/

  def self.parse( q )
    q = normalize( q )
    tokens = q ? q.split(' ') : []
    tree_norm( parse_tree( tokens ) )
  end

  def initialize
    @node = [ DEFAULT_OP ]
    @terms = []
    @ops = []
    @last_term = false
    $stderr.puts
  end

  def dump( fr )
    $stderr.puts( "%2s terms: %-30s ops: %-12s node: %-30s" %
                  [ fr, @terms.inspect, @ops.inspect, @node.inspect ] )
  end

  def push_term( t )
    if @last_term
      push_op( DEFAULT_OP )
    end
    @terms << t
    @last_term = true
    dump 'PT'
  end

  def push_op( op )
    loop do
      last = @ops.last
      if last && PRECEDENCE[op] <= PRECEDENCE[last]
        @ops.pop
        op_to_node( last )
        dump 'PL'
      else
        break
      end
    end
    @ops << op
    @last_term = false
    dump 'PO'
  end

  def final_tree
    while( last = @ops.pop )
      op_to_node( last )
      dump 'FO'
    end
    while( last = @terms.pop )
      @node << last
      dump 'FT'
    end

    @node
  end

  def op_to_node( op )
    o1 = @terms.pop
    if o1
      if op == :not
        @node << [ :not, o1 ]
      else
        o2 = @terms.pop
        if o2
          if @node[0] == op
            @node << o1 << o2
          else
            @node << [ op, o1, o2 ]
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
      $stderr.puts "No o1?"
    end
  end

  def self.parse_tree( tokens )
    s = new
    while ( t = tokens.shift )
      case t
      when LQUOTE
        rqi = tokens.index { |t| t =~ RQUOTE }
        if rqi
          s.push_term( [ :phrase, *tokens[0...rqi] ] )
          tokens = tokens[rqi+1..-1]
        end # else ignore
      when LPAREN
        rpi = tokens.rindex { |t| t =~ RPAREN } #last
        if rpi
          s.push_term( parse_tree( tokens[0...rpi] ) )
          tokens = tokens[rpi+1..-1]
        end # else ignore
      when RQUOTE
        #ignore
      when RPAREN
        #ignore
      when PREFIX
        s.push_term( [ $1, $2 ] )
      when OR_TOKEN
        s.push_op( :or )
      when AND_TOKEN
        # ignore (DEFAULT)
      when NOT_TOKEN
        s.push_op( :not )
      else
        s.push_term( t )
      end
    end
    s.final_tree
  end

  def self.tree_norm( node )
    op,*args = node
    out = []
    reduced = false
    args.each do |a|
      if a.is_a?( Array )
        if a[0] == op || ( ( a[0] == :and || a[0] == :or ) && a.length < 3 )
          a[1..-1].each do |aa|
            if aa.is_a?( Array )
              out << tree_norm( aa )
            else
              out << aa
            end
          end
          reduced = true
        else
          out << tree_norm( a )
        end
      else
        out << a
      end
    end
    #FIXME: Doesn't reduce itself in length = 2 case?
    n = [ op, *out ]
    if reduced
      tree_norm( n )
    else
      n
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

  # Split leading '-' to sepeate token
  def self.norm_pre_split( q )
    q.gsub( /(?<=\A|#{SP})\-(?=#{NSP}+)/, '- ' )
  end

  def self.norm_space( q )
    q.gsub(SPS, ' ').strip
  end

  def self.normalize( q )
    q ||= ''
    q = norm_quote_split( q )
    q = norm_opp_split( q )
    q = norm_pre_split( q )
    q = norm_space( q )
    q unless q.empty?
  end

end

# QueryParseTree.parse( "a b c")

require 'minitest/autorun'

class QueryParseTest < Minitest::Test
  TC = QueryParseTree

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

  def test_parse_basic
    assert_equal( [ :and, A ], TC.parse( 'a' ) )
    assert_equal( [ :and, [ 'FOO', A ] ], TC.parse( 'FOO:a' ) )
    assert_equal( [ :and, A, B ], TC.parse( 'a b' ) )
  end

  def test_parse_phrase
    assert_equal( [ :and, [ :phrase, A, B ] ], TC.parse( '"a b"' ) ) #FIXME
  end

  def test_parse_empty
    assert_equal( [ :and ], TC.parse( '' ) ) #FIXME
  end

  def test_parse_or
    assert_equal( [ :or, A, B ], TC.parse( 'a|b' ) )
  end

  def test_parse_parens
    assert_equal( [ :and, A, B ], TC.parse( '(a b)' ) )
    assert_equal( [ :and, [ :or, A, B ], C ], TC.parse( '(a|b) c' ) )
    assert_equal( [ :and, C, [ :or, A, B ] ], TC.parse( 'c (a|b)' ) )
    assert_equal( [ :and, 'd', [ :or, A, B, C ] ], TC.parse( 'd (a|b|c)' ) )
  end

  def test_parse_precedence_1
    assert_equal( [ :and, [ :or, A, B ], C ], TC.parse( 'a | b c' ) )
  end

  def test_parse_precedence_2
    assert_equal( [ :and, A, [ :or, B, C ] ], TC.parse( 'a b | c' ) )
  end

  def test_parse_precedence_3
    assert_equal( [ :and, [ :or, A, [ :not, B ] ], C ], TC.parse( 'a | - b c' ) )
  end

end

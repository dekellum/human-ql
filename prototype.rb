
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

# FIXMEAdditional special characters to be filtered out:
# ":" when not matching a prefix, replace with space
# "*" to_tsquery significant



class QueryParseTree

  DEFAULT_OP = :and

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
    tree = parse_tree( tokens )
  end

  def self.parse_tree( tokens )
    node = [ DEFAULT_OP ]
    while ( t = tokens.shift )
      case t
      when LQUOTE
        rqi = tokens.index { |t| t =~ RQUOTE }
        if rqi
          node << [ :phrase, *tokens[0...rqi] ]
          tokens = tokens[rqi+1..-1]
        end # else ignore
      when LPAREN
        rpi = tokens.rindex { |t| t =~ RPAREN } #last
        if rpi
          node << parse_tree( tokens[0...rpi] )
          tokens = tokens[rpi+1..-1]
        end # else ignore
      when RQUOTE
        #ignore
      when RPAREN
        #ignore
      when OR_TOKEN
        if node.length < 3
          node[0] = :or
        elsif node[0] == :and
          or_node = [ :or, node ]
          node = or_node
        end #else ignore
      when AND_TOKEN
        if node.length < 3
          node[0] = :and
        elsif node[0] == :or
          anode = [ :and, node.pop ]
          node << anode
          node = anode
        end #else ignore
      when NOT_TOKEN
        p = []
        nn = [ :not, p ]
        node << nn
        #FIXME
      when PREFIX
        node << [ $1, $2 ]
      else
        node << t
      end
    end
    node
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

  def test_parse
    assert_equal( [ :and ], TC.parse( '' ) )
    assert_equal( [ :and, 'a' ], TC.parse( 'a' ) )
    assert_equal( [ :and, [ 'FOO', 'a' ] ], TC.parse( 'FOO:a' ) )
    assert_equal( [ :and, 'a', 'b' ], TC.parse( 'a b' ) )
    assert_equal( [ :and, [ :phrase, 'a', 'b' ] ], TC.parse( '"a b"' ) )
    assert_equal( [ :and, [ :and, 'a', 'b' ] ], TC.parse( '(a b)' ) )
    assert_equal( [ :and, [ :or, 'a', 'b' ], 'c' ], TC.parse( '(a|b) c' ) )
    assert_equal( [ :and, 'c', [ :or, 'a', 'b' ] ], TC.parse( 'c (a|b)' ) )
    assert_equal( [ :and, 'd', [ :or, 'a', 'b', 'c' ] ], TC.parse( 'd (a|b|c)' ) )
  end

end

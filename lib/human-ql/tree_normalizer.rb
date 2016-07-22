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

  # Normalizes query abstract syntax trees (ASTs) by imposing various
  # limitations.
  class TreeNormalizer

    def initialize( opts = {} )
      @nested_scope = false
      @nested_not = false
      @unconstrained_not = true
      @scope_can_constrain = true
      @not_scope = :invert

      opts.each do |k,v|
        var = "@#{k}".to_sym
        if instance_variable_defined?( var )
          instance_variable_set( var, v )
        else
          raise "TreeNormalizer unsupported option #{k.inspect}"
        end
      end
    end

    def normalize( node )
      _normalize( node, EMPTY_STACK, @unconstrained_not )
    end

    protected

    def scope_can_constrain?( scope )
      @scope_can_constrain
    end

    EMPTY_STACK = [].freeze

    def _normalize( node, ops, constrained )
      op,*args = node
      if ! node.is_a?( Array )
        op
      elsif args.empty?
        nil
      else

        case op
        when :and
          unless constrained
            constrained = args.any? { |a| constraint?( a ) }
          end
        when String #scope
          args = args[0,1] if args.length > 1
          if !@nested_scope
            outer = ops.find { |o| o.is_a?( String ) }
            if outer == op
              return args.first
            elsif outer
              return nil
            end
          end
        when :not
          args = args[0,1] if args.length > 1
          return nil if !constrained || ( !@nested_not && ops.rindex(:not) )
          if @not_scope == :invert
            # [1] For :invert to work, we need to normalize without
            # the :not in ops. Otherwise below not_scope [2] check
            # would delete the scope. The other reason for the
            # _normalize here is to collapse single arg :and, etc.
            # before testing
            na = _normalize( args[0], ops, constrained )
            if na.is_a?( Array ) && na[0].is_a?( String )
              op, na[0] = na[0], op
              return [ op, na ]
            end
          end
        end

        a_ops = ops.dup.push( op )
        out = []
        args.each do |a|
          a = _normalize( a, a_ops, constrained )
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
        # [2] If scope still found below a not, delete it.
        # With :invert, this implies nodes intervening
        elsif @not_scope != true && op.is_a?( String ) && ops.rindex(:not)
          nil
        else
          out.unshift( op )
        end
      end
    end

    # Return true if node is a valid constraint
    def constraint?( node )
      op,*args = node
      if ! node.is_a?( Array )
        true
      elsif args.empty?
        false
      else
        case op
        when :and
          args.any? { |a| constraint?( a ) }
        when :or
          args.all? { |a| constraint?( a ) }
        when String
          scope_can_constrain?( op ) && constraint?( args.first )
        else
          false
        end
      end
    end

  end

end

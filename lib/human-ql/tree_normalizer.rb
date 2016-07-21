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

  class TreeNormalizer

    def initialize( opts = {} )
      @nested_scope = false
      @nested_not = false
      @unconstrained_not = true

      opts.each do |k,v|
        var = "@#{k}".to_sym
        if instance_variable_defined?( var )
          instance_variable_set( var, v )
        else
          raise "TreeNormalizer unsupported option #{k.inspect}"
        end
      end
    end

    EMPTY_STACK = [].freeze

    def normalize( node )
      _normalize( node, EMPTY_STACK )
    end

    def _normalize( node, ops )
      op,*args = node
      if ! node.is_a?( Array )
        op
      elsif args.empty?
        nil
      else

        case op
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
          return nil if !@nested_not && ops.rindex(:not)
          return nil if !@unconstrained_not && !ops.rindex(:and)
          # FIXME: The unconstrained test is incomplete, and can be
          # thwarted, as `-a & -a` would pass
        end

        a_ops = ops.dup.push( op )
        out = []
        args.each do |a|
          a = _normalize( a, a_ops )
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

  end
end

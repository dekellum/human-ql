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

  # Normalizes and imposes various limitations on query abstract
  # syntax trees (ASTs).
  class TreeNormalizer

    # Allow nested scopes?
    # Default: false -> nested scope nodes are removed.
    attr_accessor :nested_scope

    # Allow nested :not (in other words, double negatives)?
    # Default: false -> nested :not nodes are removed.
    attr_accessor :nested_not

    # Allow unconstrained :not?
    # Queries containing an unconstrained :not may be costly to
    # execute. If false the unconstrained :not will be removed.
    #
    # A :not node is considered "constrained" if it has an :and
    # ancestor with at least one constraint argument. A constraint
    # argument is a term, phrase, or :and node matching this same
    # criteria, or an :or node where *all* arguments match this
    # criteria. See also #scope_can_constrain.
    # Default: true
    attr_accessor :unconstrained_not

    # Does a scope count as a constraint?
    # Default: true -> a scope is a constraint if its argument is a
    # constraint.
    # If it depends on the scope, you can override #scope_can_constrain?
    # with this logic.
    attr_accessor :scope_can_constrain

    # Allow SCOPE within :not?
    # * If set to `:invert` normalizes `[:not, ['SCOPE', 'a']]` to
    #   `['SCOPE', [:not, 'a']]`.
    # * If set to `false`, the nested scope node is removed.
    # * For either :invert or false, the scope node is otherwise
    #   removed if found below a :not node.
    # Default: :invert
    attr_accessor :not_scope

    # Allow only scopes combined with :and condition?
    # Default: false
    attr_accessor :scope_and_only

    # Allow scope at root or first level only?
    # Default: false
    attr_accessor :scope_at_top_only

    # Construct given options that are applied via same name setters
    # on self.
    def initialize(opts = {})
      @nested_scope = false
      @nested_not = false
      @unconstrained_not = true
      @scope_can_constrain = true
      @scope_at_top_only = false
      @scope_and_only = false
      @not_scope = :invert

      opts.each do |name,val|
        send(name.to_s + '=', val)
      end
    end

    # Return a new normalized AST from the given AST root node.
    def normalize(node)
      node = normalize_1(node, EMPTY_STACK, @unconstrained_not)
      if (@not_scope != true) || @scope_and_only || @scope_at_top_only
        node = normalize_2(node, EMPTY_STACK)
      end
      node
    end

    protected

    def scope_can_constrain?(scope)
      @scope_can_constrain
    end

    EMPTY_STACK = [].freeze

    # Return true if node is a valid constraint
    def constraint?(node)
      op,*args = node
      if ! node.is_a?(Array)
        true
      elsif args.empty?
        false
      else
        case op
        when :and
          args.any? { |a| constraint?(a) }
        when :or
          args.all? { |a| constraint?(a) }
        when :phrase
          true
        when String
          scope_can_constrain?(op) && constraint?(args.first)
        else
          false
        end
      end
    end

    private

    def normalize_1(node, ops, constrained)
      op,*args = node
      if ! node.is_a?(Array)
        op
      elsif args.empty?
        nil
      else

        case op
        when :and
          unless constrained
            constrained = args.any? { |a| constraint?(a) }
          end
        when String #scope
          args = args[0,1] if args.length > 1
          if !@nested_scope
            outer = ops.find { |o| o.is_a?(String) }
            if outer == op
              return args.first
            elsif outer
              return nil
            end
          end
        when :not
          args = args[0,1] if args.length > 1
          return nil if !constrained || (!@nested_not && ops.rindex(:not))
        end

        a_ops = ops.dup.push(op)
        out = []
        args.each do |a|
          a = normalize_1(a, a_ops, constrained)
          if a.is_a?(Array) && a[0] == op
            out += a[1..-1]
          elsif a # filter nil
            out << a
          end
        end

        if (op == :and || op == :or) && out.length < 2
          out[0]
        elsif out.empty?
          nil
        else
          out.unshift(op)
        end
      end
    end

    def normalize_2(node, ops)
      op,*args = node
      if ! node.is_a?(Array)
        op
      elsif args.empty?
        nil
      else
        case op
        when String #scope
          if @scope_at_top_only && ops.length > 1
            return nil
          end
          if @scope_and_only && !ops.all? { |o| o == :and }
            return nil
          end
        when :not
          if @not_scope == :invert
            na = args[0]
            if na.is_a?(Array) && na[0].is_a?(String)
              op, na[0] = na[0], op
              return [ op, na ]
            end
          end
        end

        a_ops = ops.dup.push(op)
        out = []
        args.each do |a|
          a = normalize_2(a, a_ops)
          if a.is_a?(Array) && a[0] == op
            out += a[1..-1]
          elsif a # filter nil
            out << a
          end
        end

        if (op == :and || op == :or) && out.length < 2
          out[0]
        elsif out.empty?
          nil
        # If scope still found below a :not, remove it. With :invert,
        # this implies nodes intervening
        elsif @not_scope != true && op.is_a?(String) && ops.rindex(:not)
          nil
        else
          out.unshift(op)
        end
      end
    end

  end

end

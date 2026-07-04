require "tungsten/core_ext/module"
require "tungsten/core_ext/string"

module Tungsten::AST
  def self.intern_name(name)
    return nil if name.nil?

    -name.to_s
  end

  def self.intern_name_without_prefix(name, prefix)
    value = name.to_s
    return intern_name(value) unless value.start_with?(prefix)

    caches = @interned_name_prefixes ||= {}
    cache = caches[prefix] ||= {}
    cache[value] ||= -value[prefix.length..]
  end

  class Node
    attr_accessor :parent, :closure_env, :memo_cache, :cache_path
    attr_reader   :doc

    def self.inherited(klass)
      # name = klass.simple_name.underscore

      # Visitor.register(name)
    end

    def ==(other)
      other.class == self.class
    end

    def location
      return @location if @location
      return nil unless @location_row

      @location = Tungsten::Location.new(@location_file, @location_row, @location_col)
    end

    def location=(loc)
      @location = loc
      if loc
        @location_file = loc.file
        @location_row = loc.row
        @location_col = loc.col
      else
        @location_file = nil
        @location_row = nil
        @location_col = nil
      end
    end

    def set_location(file, row, col)
      @location = nil
      @location_file = file
      @location_row = row
      @location_col = col
      self
    end

    def copy_location_from(other)
      if other.location_row
        set_location(other.location_file, other.location_row, other.location_col)
      else
        self.location = other.location
      end
      self
    end

    def location_file
      @location ? @location.file : @location_file
    end

    def location_row
      @location ? @location.row : @location_row
    end

    def location_col
      @location ? @location.col : @location_col
    end

    def at(obj)
      case obj.class
      when Tungsten::Location
        @location = obj
      when Node
        copy_location_from(obj)
        # @end_location = other.end_location
      end

      self
    end

    # Yields each attribute and its name to the block.
    #
    # @source rubinius
    #
    def attributes
      instance_variables.each do |var|
        next if location_instance_var?(var) || var == :@parent

        child = instance_variable_get var
        name = var.to_s[1..-1]
        yield child, name
      end
    end

    def can_assign?
      false
    end

    # Yields each child of this Node to the block. Additionally, for any
    # attribute that is an Array, yields each element that is a Node.
    #
    # @source rubinius
    #
    def children
      instance_variables.each do |var|
        next if location_instance_var?(var) || var == :@parent

        child = instance_variable_get var

        if child.kind_of? Node
          yield child
        elsif child.kind_of? Array
          child.each { |x| yield x if x.kind_of? Node }
        end
      end
    end

    def clone
      node = self.class.allocate
      node.copy_location_from(self)
      node.clone_from self
      node
    end

    def clone_from(other)
      raise NotImplementedError
    end

    # Attaches a doc comment to this node. Must be implemented in subclasses
    def doc=(doc)
      raise NotImplementedError
    end

    def inspect
      vars = instance_variables.reject { |v| v == :@parent || location_instance_var?(v) }
      "#<%s %s>" % [self.class.name.split('::').last, vars.map { |name| "%s=%s" % [name, instance_variable_get(name).inspect] }.join(', ')]
    end

    def name_column
      location_col || 0
    end

    def name_length
      0
    end

    def node_name
      self.class.node_name
    end

    def self.node_name
      @node_name ||= name.gsub(/^.*::/, '').underscore.freeze
    end

    def self.visitor_method
      @visitor_method ||= :"visit_#{node_name}"
    end

    # Called by #transform to update the child of a Node. The
    # default just calls the attr_accessor for the child. However, Node
    # subclasses that must synchronize other internal state can override
    # this method.
    #
    # @source rubinius
    #
    def set_child(name, node)
      send :"#{name}=", node
    end

    # A fixed-point algorithm for transforming an AST with a visitor. The
    # traversal is top-down. The visitor object's method corresponding to
    # each node (see #node_name) is called for each node, passing the node
    # and its parent.
    #
    # To replace a node in the tree, the visitor method should return a
    # new nodde; otherwise, return the existing node. The visitor is free to
    # change values in the node, but substituting a node causes the entire tree
    # to be walked repeatedly until no modifications are made.
    #
    # @source rubinius
    #
    def transform(visitor, parent = nil, state = nil)
      state ||= TransformState.new

      node = visitor.send :"node_#{node_name}", self, parent

      state.change unless equal?(node)

      node.attributes do |attr, name|
        if attr.kind_of? Node
          child = attr.transform visitor, node, state

          unless attr.equal?(child)
            state.change
            node.set_child name, child
          end
        elsif attr.kind_of? Array
          attr.each.with_index do |x, i|
            if x.kind_of? Node
              child = x.transform visitor, node, state

              unless x.equal?(child)
                state.change
                attr[i] = child
              end
            end
          end
        end
      end

      # Repeat the walk until the tree is unchanged.
      if parent.nil? and state.changed?
        state.reset
        node = transform visitor, nil, state
      end

      node
    end

    # Mange the state of the #transform method
    #
    # @source rubinius
    #

    class TransformState
      def initialize() @changed = false end
      def changed?()   @changed         end
      def change()     @changed = true  end
      def reset()      @changed = false end
    end

    # Supports the visitor pattern on a tree of Nodes. The _visitor_ should
    # be an object that responds to methods named after the Node subclasses.
    # The method called is determined by the #node_name method. Passes both
    # the node and its parent so that the visitor can maintain nesting
    # information if desired.
    #
    # The #visit implements a read-only traversal of the tree. To modify the
    # tree, see the #transform method instead.
    #
    # @source rubinius
    #
    def accept(visitor, parent = nil)
      result = visitor.__send__ node_name, self, parent

      # If the visitor returns false, skip children traversal.
      # This lets visitors like Printer control their own traversal order.
      if result != false
        children { |c| c.accept visitor, self }
      end

      visitor.__send__ "#{node_name}_end", self, parent
    end

    # This method implements a sort-of tree iterator, yielding each Node instance
    # to the provided block with the first argument to #walk. If the block returns
    # a non-tree value, the walk is terminated.
    #
    # This method is really an iterator, not a Visitor pattern.
    #
    # @source rubinius
    #
    def walk(arg = true, &block)
      children do |child|
        if a = block.call(arg, child)
          child.walk(a, &block)
        end
      end
    end

    def ast_fingerprint(name_map = {})
      parts = [self.class.name]
      instance_variables.each do |var|
        next if location_instance_var?(var)
        child = instance_variable_get(var)
        case child
        when Node then parts << child.ast_fingerprint(name_map)
        when Array then child.each { |c| parts << (c.is_a?(Node) ? c.ast_fingerprint(name_map) : c.inspect) }
        else
          val = child.is_a?(String) && name_map.key?(child) ? name_map[child] : child
          parts << val.inspect
        end
      end
      parts.join("|")
    end

    def ast_sha(name_map = {})
      require "digest"
      ::Digest::SHA256.hexdigest(ast_fingerprint(name_map))[0, 16]
    end

    # Walk the tree and set @parent on every child node.
    # Call once after parsing to enable upward traversal.
    def set_parents!(parent_node = nil)
      @parent = parent_node
      children { |child| child.set_parents!(self) }
      self
    end

    def to_s
      Tungsten::Printer.print(self)
    end

    def to_sexp
      [:node, self.class.name]
    end

    private

    def location_instance_var?(var)
      var == :@location || var == :@location_file || var == :@location_row || var == :@location_col
    end
  end
end

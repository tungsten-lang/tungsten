# frozen_string_literal: true

module Tungsten
  class Environment
    UNDEFINED = Object.new.freeze
    EMPTY_SHAPE = 0

    attr_reader :parent, :layout_shape

    def initialize(parent = nil, barrier: false, slot_names: nil, undefined_from: nil)
      @parent = parent
      @barrier = barrier
      if slot_names&.any?
        @slot_names = slot_names       # name → index
        @slot_names_owned = false
        @slot_values = Array.new(slot_names.size) # values by index
        if undefined_from
          i = undefined_from
          while i < @slot_values.length
            @slot_values[i] = UNDEFINED
            i += 1
          end
        end
      else
        @slot_names = {}   # name → index
        @slot_names_owned = true
        @slot_values = []  # values by index
      end
      @extra_slot_names = nil
      @layout_shape = self.class.slot_shape(@slot_names)
      @lookup_shape = nil
    end

    def self.next_shape
      @next_shape ||= EMPTY_SHAPE
      @next_shape -= 1
    end

    def self.slot_shape(slot_names)
      return EMPTY_SHAPE unless slot_names&.any?

      slot_names.object_id
    end

    def self.layout_transition(shape, name, index)
      transitions = (@layout_transitions ||= {})
      by_name = (transitions[shape] ||= {})
      by_index = (by_name[name] ||= {})
      by_index[index] ||= next_shape
    end

    def self.lookup_transition(parent_shape, layout_shape)
      transitions = (@lookup_transitions ||= {})
      by_layout = (transitions[parent_shape] ||= {})
      by_layout[layout_shape] ||= next_shape
    end

    def barrier?
      @barrier
    end

    def lookup_shape
      @lookup_shape ||= self.class.lookup_transition(@parent&.lookup_shape || EMPTY_SHAPE, @layout_shape)
    end

    # Returns the slot index for a name in THIS scope, or nil
    def slot_index(name)
      idx = @slot_names[name]
      return idx if idx

      extra = @extra_slot_names
      extra[name] if extra
    end

    def get_slot(index)
      @slot_values[index]
    end

    def set_slot(index, value)
      @slot_values[index] = value
    end

    def get(name)
      env = self
      while env
        idx = env.slot_index(name)
        return env.get_slot(idx) if idx

        env = env.parent
      end

      raise Tungsten::Error, "Undefined variable '#{name}'"
    end

    def set(name, value)
      idx = @slot_names[name]
      idx = @extra_slot_names[name] if !idx && @extra_slot_names
      return @slot_values[idx] = value if idx

      env = self
      while env
        idx = env.slot_index(name)
        return env.set_slot(idx, value) if idx

        if env.instance_variable_get(:@barrier)
          env.define(name, value)
          return value
        end

        env = env.parent
      end

      define(name, value)
      value
    end

    def define(name, value)
      idx = @slot_names[name]
      idx = @extra_slot_names[name] if !idx && @extra_slot_names
      if idx
        @slot_values[idx] = value
      else
        idx = @slot_values.size
        if @slot_names_owned
          @slot_names[name] = idx
        else
          (@extra_slot_names ||= {})[name] = idx
        end
        @slot_values << value
        @layout_shape = self.class.layout_transition(@layout_shape, name, idx)
        @lookup_shape = nil
      end
    end

    def define_slot(name, index, value)
      existing = @slot_names[name]
      existing = @extra_slot_names[name] if !existing && @extra_slot_names
      return @slot_values[index] = value if existing == index

      if @slot_names_owned
        @slot_names[name] = index
      else
        (@extra_slot_names ||= {})[name] = index
      end
      @slot_values[index] = value
      @layout_shape = self.class.layout_transition(@layout_shape, name, index)
      @lookup_shape = nil
    end

    def defined?(name)
      env = self
      while env
        return true if env.defined_locally?(name)

        env = env.parent
      end
      false
    end

    def defined_locally_or_in_scope?(name)
      env = self
      while env
        return true if env.defined_locally?(name)
        break if env.instance_variable_get(:@barrier)

        env = env.parent
      end
      false
    end

    def defined_locally?(name)
      @slot_names.key?(name) || !!@extra_slot_names&.key?(name)
    end

    def fetch(name)
      env = self
      while env
        idx = env.slot_index(name)
        return env.get_slot(idx) if idx

        env = env.parent
      end
      UNDEFINED
    end

    # Compatibility: some code expects bindings as a Hash
    def bindings
      result = @slot_names.each_with_object({}) { |(k, i), h| h[k] = @slot_values[i] }
      @extra_slot_names&.each { |k, i| result[k] = @slot_values[i] }
      result
    end
  end
end

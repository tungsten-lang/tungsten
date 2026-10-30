# frozen_string_literal: true

# Keep stage0 compatibility shims here. This file is intentionally small until
# Spinel tells us exactly which CRuby conveniences the stage0 path still needs.

class Set
  def initialize
    @values = []
  end

  def add(value)
    value = value.to_s
    @values.push(value) unless include?(value)
    self
  end

  def delete(value)
    value = value.to_s
    i = 0
    while i < @values.length
      if @values[i] == value
        @values.delete_at(i)
        return self
      end
      i += 1
    end
    self
  end

  def include?(value)
    value = value.to_s
    i = 0
    while i < @values.length
      return true if @values[i] == value
      i += 1
    end
    false
  end

  def each(&block)
    self
  end
end

class ErrorReporter
  def initialize(color: false)
  end

  def format(error, source: nil, file: nil)
    error.to_s
  end
end

class Literal
  def initialize(value)
  end
end

class ByteArray < Literal
end

class Color < Literal
end

class Currency < Literal
  attr_reader :symbol

  def initialize(value, symbol = nil)
    @symbol = symbol
  end
end

class Percentage < Literal
end

class Quantity < Literal
end

class Key < Literal
  def self.parse(value)
    new(value)
  end
end

class Units
  SUPERSCRIPT_DIGITS = {}

  def self.known?(_name)
    false
  end
end

class StringBuffer
  def initialize(capacity = 0)
    @parts = [""]
    @parts.clear
    @byte_len = 0
  end

  def append(value)
    s = value.to_s
    if s.bytesize > 0
      @parts.push(s)
      @byte_len += s.bytesize
    end
    self
  end

  def <<(value)
    append(value)
  end

  def push(value)
    append(value)
  end

  def push_byte(byte)
    append((byte.to_i & 0xFF).chr)
  end

  def to_s
    return "" if @parts.empty?
    if @parts.length > 1
      joined = @parts.join("")
      @parts.clear
      @parts.push(joined)
      return joined
    end
    @parts[0]
  end

  def length
    to_s.length
  end

  def size
    to_s.length
  end

  def byte_size
    @byte_len
  end

  def byte_length
    @byte_len
  end

  def slice_bytes(start_idx, len)
    to_s.byteslice(start_idx.to_i, len.to_i) || ""
  end

  def [](index)
    to_s[index]
  end

  def clear
    @parts.clear
    @byte_len = 0
    self
  end

  def empty?
    @byte_len == 0
  end

  def include?(sub)
    to_s.include?(sub.to_s)
  end

  def starts_with?(prefix)
    to_s.start_with?(prefix.to_s)
  end

  def start_with?(prefix)
    to_s.start_with?(prefix.to_s)
  end

  def ==(other)
    if other.is_a?(StringBuffer)
      to_s == other.to_s
    elsif other.is_a?(String)
      to_s == other
    else
      false
    end
  end

  def inspect
    "StringBuffer(#{to_s.inspect})"
  end
end

class PackedNode
  attr_accessor :kind, :sc, :offset, :fields, :sparse, :analysis, :ivar_offsets, :ivar_count, :intern_str

  def initialize(kind, sc = 0, offset = 0, intern_str = "")
    @kind = kind.to_i
    @sc = sc.to_i
    @offset = offset.to_i
    @fields = nil
    @sparse = nil
    @analysis = nil
    @ivar_offsets = nil
    @ivar_count = nil
    @intern_str = intern_str.to_s
  end

  def set_field(off, val)
    i = off.to_i
    f = @fields
    if f.nil?
      f = [nil, 0, ""]
      f.clear
      @fields = f
    end
    while f.length <= i
      f.push(nil)
    end
    f[i] = val
    val
  end

  def get_field(off)
    f = @fields
    return nil if f.nil?
    i = off.to_i
    return nil if i < 0 || i >= f.length
    f[i]
  end

  def sparse_sym(key)
    return key if key.is_a?(Symbol)
    key.to_s.to_sym
  end

  def set_sparse(key, val)
    sp = @sparse
    if sp.nil?
      sp = {:__spinel_k__ => nil, :__spinel_i__ => 0, :__spinel_s__ => ""}
      sp.clear
      @sparse = sp
    end
    sp[sparse_sym(key)] = val
    val
  end

  def get_sparse(key)
    sp = @sparse
    return nil if sp.nil?
    sp[sparse_sym(key)]
  end

  def copy_metadata_to(dst)
    sp = @sparse
    unless sp.nil?
      sp.each do |k, v|
        dst.set_sparse(k, v)
      end
    end
    dst.analysis = @analysis
    dst.ivar_offsets = @ivar_offsets
    dst.ivar_count = @ivar_count
    dst
  end

  def to_s
    "[ast]"
  end
end

class WireRecord
  attr_accessor :kind, :keys, :key_syms, :values

  def initialize(kind)
    @kind = kind.to_i
    @keys = [nil, 0, ""]
    @keys.clear
    @key_syms = [:__spinel_sym__]
    @key_syms.clear
    @values = [nil, 0, ""]
    @values.clear
  end

  def sym_key(sym)
    return sym if sym.is_a?(Symbol)
    sym.to_s.to_sym
  end

  def store_at(idx, sym, val)
    i = idx.to_i
    s = sym_key(sym)
    ks = @key_syms
    while ks.length <= i
      ks.push(:__spinel_empty__)
      @keys.push(nil)
      @values.push(nil)
    end
    ks[i] = s
    @keys[i] = sym
    @values[i] = val
    val
  end

  def store(sym, val)
    s = sym_key(sym)
    ks = @key_syms
    n = ks.length
    i = 0
    while i < n
      if ks[i] == s
        @values[i] = val
        return val
      end
      i += 1
    end
    ks.push(s)
    @keys.push(sym)
    @values.push(val)
    val
  end

  def load(sym)
    s = sym_key(sym)
    ks = @key_syms
    n = ks.length
    i = 0
    while i < n
      return @values[i] if ks[i] == s
      i += 1
    end
    nil
  end

  def field_count
    @key_syms.length
  end

  def key_at(idx)
    @keys[idx.to_i]
  end

  def value_at(idx)
    @values[idx.to_i]
  end

  def [](sym)
    load(sym)
  end

  def []=(sym, val)
    store(sym, val)
  end

  def clone_record
    copy = WireRecord.new(@kind)
    n = @key_syms.length
    i = 0
    while i < n
      copy.store_at(i, @keys[i], @values[i])
      i += 1
    end
    copy
  end
end

class WireSequence
  attr_accessor :items

  def initialize
    @items = [nil, 0, ""]
    @items.clear
  end

  def push(val)
    @items.push(val)
    self
  end

  def size
    @items.length
  end

  def length
    @items.length
  end

  def empty?
    @items.empty?
  end

  def [](idx)
    i = idx.to_i
    i < 0 ? @items[@items.length + i] : @items[i]
  end

  def []=(idx, val)
    i = idx.to_i
    return nil if i < 0 || i >= @items.length
    @items[i] = val
  end

  def to_a
    @items
  end

  def clone_sequence
    copy = WireSequence.new
    n = @items.length
    i = 0
    while i < n
      copy.push(@items[i])
      i += 1
    end
    copy
  end
end

class ContentTempMap
  attr_accessor :dense, :fallback, :next_id

  def initialize(cap, start_id)
    @dense = []
    n = cap.to_i
    i = 0
    while i < n
      @dense.push(-1)
      i += 1
    end
    @fallback = {"__spinel_k__" => 0}
    @fallback.clear
    @next_id = start_id.to_i
  end

  def seed(ordinal, name, idx)
    id = idx.to_i
    if ordinal >= 0 && ordinal < @dense.length
      @dense[ordinal] = id
    else
      @fallback[name.to_s] = id
    end
    nil
  end

  def norm(ordinal, name)
    if ordinal >= 0 && ordinal < @dense.length
      out = @dense[ordinal]
      if out < 0
        out = @next_id
        @dense[ordinal] = out
        @next_id = out + 1
      end
      out
    else
      key = name.to_s
      out = @fallback[key]
      if out.nil?
        out = @next_id
        @fallback[key] = out
        @next_id = out + 1
      end
      out
    end
  end
end

class WRange
  attr_accessor :from, :to, :exclusive, :endless

  def initialize(from, to, exclusive, endless = false)
    @from = from.is_a?(String) ? (from.getbyte(0) || 0) : from.to_i
    @to = to.is_a?(String) ? (to.getbyte(0) || 0) : to.to_i
    @exclusive = exclusive ? true : false
    @endless = endless ? true : false
  end

  def include?(val)
    return false if val.nil?
    v = val.is_a?(String) ? (val.getbyte(0) || -1) : val.to_i
    return false if v < @from
    return true if @endless
    @exclusive ? (v < @to) : (v <= @to)
  end

  def to_list
    res = List.new
    return res if @endless
    cur = @from
    lim = @to
    if @exclusive
      while cur < lim
        res.push(cur)
        cur += 1
      end
    else
      while cur <= lim
        res.push(cur)
        cur += 1
      end
    end
    res
  end
end

class PathValue < Literal
end

class Time < Literal
end

class Builtins
  def self.setup(interpreter, sandbox: false)
  end
end

# Lazily reconstruct a requested GF(2) price from pinned exact witnesses,
# block sums, or Kronecker products. Rank numbers alone never yield a scheme.
require_relative 'bud_products'

class MetaflipCheckedPriceLibrary
  B = MetaflipBudProducts
  attr_reader :used_sources

  def initialize(prices, sources, maximum: 32)
    @maximum = maximum
    raise 'invalid maximum' unless maximum.is_a?(Integer) && maximum.between?(2,32)
    @prices = prices.to_h { |shape,rank| [key(shape),rank] }
    raise 'invalid price' unless @prices.values.all? { |r| r.is_a?(Integer) && r.positive? }
    @sources = sources.group_by { |row| key(row.fetch(:shape)) }
    @schemes, @used_sources = {}, {}
  end

  def key(shape)
    raise 'invalid shape' unless shape.is_a?(Array) && shape.length==3 && shape.all? { |d| d.is_a?(Integer) && d.between?(1,@maximum) }
    shape.sort.freeze
  end

  def rank(shape)
    k=key(shape)
    k.include?(1) ? k.inject(:*) : @prices.fetch(k)
  end

  def scheme(shape)
    k=key(shape)
    @schemes[k] ||= construct(k)
    B.orient(@schemes.fetch(k),shape)
  end

  def construct(shape)
    target=rank(shape)
    row=(@sources[shape] || []).find { |r| r.fetch(:rank)==target }
    result=nil
    if row
      path=File.realpath(row.fetch(:path));raw=File.binread(path)
      digest=Digest::SHA256.hexdigest(raw)
      raise 'source hash mismatch' unless digest==row.fetch(:sha256)
      result=B.orient(B::Scheme.new(row.fetch(:shape),raw),shape)
      @used_sources[path]=digest
    elsif target==shape.inject(:*)
      result=B.naive(shape)
    else
      3.times do |axis|
        break if result
        1.upto(shape[axis]/2) do |cut|
          left,right=shape.dup,shape.dup
          left[axis],right[axis]=cut,shape[axis]-cut
          next unless rank(left)+rank(right)==target
          offset=[0,0,0];offset[axis]=cut
          terms=B.embed_block(scheme(left),shape,[0,0,0])+B.embed_block(scheme(right),shape,offset)
          result=B::Scheme.new(shape,B.text(terms));break
        end
      end
      unless result
        divisors=shape.map { |d| (1..d).select { |j| d%j==0 } }
        divisors[0].product(divisors[1],divisors[2]).each do |left|
          next if left==[1,1,1] || left==shape
          right=shape.zip(left).map { |a,b| a/b }
          next unless rank(left)*rank(right)==target
          result=B.tensor_product(scheme(left),scheme(right));break
        end
      end
    end
    raise "price has no checked construction: #{shape.inspect}=#{target}" unless result && result.rank==target
    result
  end

  def verify_sources_unchanged!
    raise 'source changed' unless @used_sources.all? { |path,digest| Digest::SHA256.file(path).hexdigest==digest }
    true
  end
end

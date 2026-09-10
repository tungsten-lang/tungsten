# Lazily reconstruct a requested GF(2) price from pinned exact witnesses,
# block sums, or Kronecker products. Rank numbers alone never yield a scheme.
require_relative 'bud_products'

class MetaflipCheckedPriceLibrary
  B = MetaflipBudProducts
  # Only this failure permits trying another decomposition. Bad source pins,
  # malformed inputs and tensor-identity failures must still abort admission.
  class MissingConstruction < RuntimeError
    attr_reader :shape, :rank
    def initialize(shape, rank)
      @shape, @rank = shape.dup.freeze, rank
      super("price has no checked construction: #{shape.inspect}=#{rank}")
    end
  end
  attr_reader :used_sources

  def initialize(prices, sources, maximum: 32)
    @maximum = maximum
    raise 'invalid maximum' unless maximum.is_a?(Integer) && maximum.between?(2,32)
    @prices = prices.to_h { |shape,rank| [key(shape),rank] }
    raise 'invalid price' unless @prices.values.all? { |r| r.is_a?(Integer) && r.positive? }
    @sources = sources.map do |row|
      { shape:row.fetch(:shape).dup.freeze, rank:row.fetch(:rank),
        path:row.fetch(:path).dup.freeze, sha256:row.fetch(:sha256).dup.freeze }.freeze
    end.group_by { |row| key(row.fetch(:shape)) }
    @schemes, @used_sources, @missing = {}, {}, {}
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
    raise MissingConstruction.new(k,rank(k)) if @missing[k]
    @schemes[k] ||= construct(k)
    B.orient(@schemes.fetch(k),shape)
  rescue MissingConstruction
    # Prices and source membership are fixed for this library instance. All
    # dependencies decrease volume, so failed subproblems can be memoized.
    @missing[k]=true
    raise
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
          begin
            l,r=scheme(left),scheme(right)
          rescue MissingConstruction
            next
          end
          offset=[0,0,0];offset[axis]=cut
          terms=B.embed_block(l,shape,[0,0,0])+B.embed_block(r,shape,offset)
          result=B::Scheme.new(shape,B.text(terms));break
        end
      end
      unless result
        divisors=shape.map { |d| (1..d).select { |j| d%j==0 } }
        divisors[0].product(divisors[1],divisors[2]).each do |left|
          next if left==[1,1,1] || left==shape
          right=shape.zip(left).map { |a,b| a/b }
          next unless rank(left)*rank(right)==target
          begin
            l,r=scheme(left),scheme(right)
          rescue MissingConstruction
            next
          end
          result=B.tensor_product(l,r);break
        end
      end
    end
    raise MissingConstruction.new(shape,target) unless result
    raise 'constructed price mismatch' unless result.rank==target
    result
  end

  def verify_sources_unchanged!
    raise 'source changed' unless @used_sources.all? { |path,digest| Digest::SHA256.file(path).hexdigest==digest }
    true
  end
end

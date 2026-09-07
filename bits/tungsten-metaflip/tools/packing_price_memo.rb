# Reuse a bounded packing solve across proportional leaf-saving profiles.
# This memo belongs to ONE immutable, ordered parent tensor. It does not merge
# tensor states or infer rank dominance from a bucket histogram.
require_relative 'bud_packings'

module MetaflipBudPackings
  class PriceMemo
    DEFAULTS={max_leaf:16,max_vertices:24,max_states:50_000,max_candidates:50_000,
              grids:false,grid_side:2}.freeze
    class Prices
      def initialize(values);@values=values.freeze;end
      def rank(shape);@values.fetch(shape);end
    end

    attr_reader :hits, :misses, :requests
    def initialize(parent,max_entries:256,**options)
      raise 'memo requires an immutable verified parent' unless parent.is_a?(B::Scheme)
      raise 'unknown packing option' unless (options.keys-DEFAULTS.keys).empty?
      raise 'invalid memo capacity' unless max_entries.is_a?(Integer) && max_entries.positive?
      @parent,@options,@max_entries=parent,DEFAULTS.merge(options).freeze,max_entries
      raise 'invalid packing limits' unless %i[max_leaf max_vertices max_states max_candidates].all? do |key|
        @options[key].is_a?(Integer) && @options[key].positive?
      end
      raise 'invalid grid side' unless @options[:grid_side].is_a?(Integer) && @options[:grid_side].between?(2,4)
      @maximum=3.times.map{|a|parent.terms.group_by{|t|t[a]}.values.map(&:size).max}
      @grids=if @options[:grids]
        (2..@options[:grid_side]).flat_map do |h|
          (2..@options[:grid_side]).flat_map{|w|[1,h,w].permutation.to_a}
        end.uniq
      else
        []
      end
      @profile_grids=@grids.to_h{|s|[s,true]}
      @inventory={complete:true,inspected:0,shapes:0}
      unless @grids.empty?
        present={}
        begin
          MetaflipBudPackings.grid_groups(parent,max_side:@options[:grid_side]).each do |group|
            @inventory[:inspected]+=1
            raise Limit if @inventory[:inspected]>@options[:max_candidates]
            present[group.fetch(:elementary_shape)]=true
          end
          @profile_grids=present
        rescue Limit
          # An incomplete inventory cannot justify dropping any grid shape.
          @inventory[:complete]=false
        end
        @inventory[:shapes]=@profile_grids.size
      end
      @cache={};@hits=@misses=@requests=0
    end

    def solve(scale,library)
      raise 'invalid scale' unless scale.is_a?(Array) && scale.size==3 &&
        scale.all?{|n|n.is_a?(Integer) && n.positive?} && scale.max<=@options[:max_leaf]
      # Read each relevant price once so key construction, solve and repricing
      # use the same snapshot even if the caller subsequently updates a table.
      prices={}
      price=lambda do |shape|
        if prices.key?(shape)
          prices.fetch(shape)
        else
          value=library.rank(shape)
          raise 'invalid leaf price' unless value.is_a?(Integer) && value.positive?
          prices[shape.dup.freeze]=value
        end
      end
      single=price.call(scale)
      gains=[]
      3.times do |axis|
        2.upto(@maximum[axis]) do |size|
          leaf=B.leaf_shape(scale,axis,size)
          gains << (leaf.max<=@options[:max_leaf] ? size*single-price.call(leaf) : nil)
        end
      end
      @grids.each do |shape|
        leaf=shape.zip(scale).map{|a,b|a*b}
        gain=leaf.max<=@options[:max_leaf] ? shape.inject(:*)*single-price.call(leaf) : nil
        gains << gain if @profile_grids.key?(shape)
      end
      # Every feasible partition costs rank(parent)*single - sum(group gains).
      # A common positive scaling of ALL gains preserves every comparison and
      # tie, including the deterministic bounded-solver fallback. Negative-gain
      # groups are strictly worse than their singleton replacement and never
      # selected; they can share a sentinel with unavailable groups. Zero-gain
      # groups remain distinct because the pure-axis baseline may choose ties.
      # Absent grid shapes are omitted only after a COMPLETE parent inventory.
      divisor=gains.compact.select(&:positive?).reduce(0){|g,v|g.gcd(v)}
      divisor=1 if divisor.zero?
      key=gains.map{|g|g.nil? || g.negative? ? -1 : g/divisor}.freeze
      snapshot=Prices.new(prices)
      @requests+=1
      if @cache.key?(key)
        @hits+=1
        # Only locally-created Marshal data is read; never external input.
        result=Marshal.load(@cache.fetch(key))
        result[:formula_rank]=B.score(result.fetch(:groups),scale,snapshot)
        B.validate_groups(@parent,result.fetch(:groups))
        result
      else
        @misses+=1
        result=MetaflipBudPackings.solve(@parent,scale,snapshot,**@options)
        @cache[key]=Marshal.dump(result) if @cache.size<@max_entries
        result
      end
    end

    def stats
      {requests:@requests,hits:@hits,misses:@misses,entries:@cache.size,capacity:@max_entries,
       grid_inventory:@inventory.dup}
    end
  end
end

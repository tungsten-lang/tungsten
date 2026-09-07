# Materialize ONLY channel-zero composition recipes. Hypothetical sensitivity
# channels have no witness interface and must never be passed to this class.
require_relative 'checked_price_library'

class MetaflipCompositionRecipeLibrary
  B=MetaflipBudProducts
  attr_reader :snapshots, :recipes, :used_sources

  def initialize(plan, parents, base, root)
    raise 'conditional plan is not a witness' unless plan.fetch('complete') &&
      plan.fetch('field')=='GF(2)' && plan.fetch('record_claim')==false
    @shapes=plan.fetch('model_shapes');@plan=plan.fetch('baseline_recipes')
    raise 'shape/recipe mismatch' unless @shapes.size==@plan.size && @shapes.uniq.size==@shapes.size
    @index=@shapes.each_with_index.to_h
    @parents,@base,@root=parents,base,root
    @schemes,@loaded_parents,@snapshots,@recipes,@used_sources={},{},{},{},{}
  end

  def rank(shape)
    @plan.fetch(@index.fetch(shape.sort)).fetch('rank')
  end

  def scheme(shape)
    key=shape.sort
    @schemes[key] ||= construct(key)
    B.orient(@schemes.fetch(key),shape)
  end

  def construct(shape)
    i=@index.fetch(shape);row=@plan.fetch(i);target=row.fetch('rank')
    raise 'invalid bound' unless target.is_a?(Integer) && target>0
    detail={kind:row.fetch('kind'),shape:shape,planned_rank:target}
    case row.fetch('kind')
    when 'seed'
      result=@base.scheme(shape)
      detail[:source]='checked-price-library'
    when 'naive'
      result=B.naive(shape)
    when 'block'
      ids=row.fetch('inputs');raise 'non-decreasing dependency' unless ids.size==2 && ids.all?{|j|j<i}
      inputs=ids.map{|j|@shapes.fetch(j)}.sort
      chosen=nil
      3.times do |axis|
        1.upto(shape[axis]/2) do |cut|
          left,right=shape.dup,shape.dup;left[axis],right[axis]=cut,shape[axis]-cut
          chosen ||= [axis,cut,left,right] if [left.sort,right.sort].sort==inputs
        end
      end
      raise 'block recipe has no orientation' unless chosen
      axis,cut,left,right=chosen
      l,r=scheme(left),scheme(right);offset=[0,0,0];offset[axis]=cut
      result=B::Scheme.new(shape,B.text(B.embed_block(l,shape,[0,0,0])+B.embed_block(r,shape,offset)))
      detail.merge!(axis:axis,cut:cut,inputs:[snapshot(l),snapshot(r)])
    when 'kronecker'
      ids=row.fetch('inputs');raise 'non-decreasing dependency' unless ids.size==2 && ids.all?{|j|j<i}
      inputs=ids.map{|j|@shapes.fetch(j)}.sort;chosen=nil
      divisors=shape.map{|n|(1..n).select{|d|n%d==0}}
      divisors[0].product(divisors[1],divisors[2]).each do |left|
        next if left==[1,1,1] || left==shape
        right=shape.zip(left).map{|n,d|n/d}
        chosen ||= [left,right] if [left.sort,right.sort].sort==inputs
      end
      raise 'Kronecker recipe has no orientation' unless chosen
      left,right=chosen.map{|s|scheme(s)};result=B.tensor_product(left,right)
      detail[:inputs]=[snapshot(left),snapshot(right)]
    when 'bud', 'mixed_bud'
      id=row.fetch('parent')
      parent=@loaded_parents[id] ||= begin
        entry=@parents.fetch(id);path=File.realpath(entry.fetch('path'));raw=File.binread(path)
        raise 'parent hash mismatch' unless Digest::SHA256.hexdigest(raw)==entry.fetch('sha256')
        @used_sources[path]=entry.fetch('sha256');B::Scheme.new(entry.fetch('shape'),raw)
      end
      scale=row.fetch('scale')
      if row.fetch('kind')=='bud'
        axis=row.fetch('axis');raise 'invalid axis' unless [0,1,2].include?(axis)
        partition=parent.terms.each_index.group_by{|j|parent.terms[j][axis]}.values.map do |ids|
          {axis:axis,indices:ids}
        end
      else
        partition=@parents.fetch(id).fetch('mixed_partitions').fetch(row.fetch('partition')).map do |g|
          raise 'unsupported mixed group' unless [%w[axis indices],%w[elementary_shape indices]].include?(g.keys.sort)
          g.transform_keys(&:to_sym)
        end
        # Validate BEFORE splitting: singleton chunks must not hide an invalid
        # claimed common factor or duplicate/missing parent terms.
        B.validate_groups(parent,partition)
      end
      groups=partition.flat_map do |group|
        if group.key?(:elementary_shape)
          dims=group.fetch(:elementary_shape);ids=group.fetch(:indices)
          tree=row.fetch('grid_plans').fetch(dims.join('x'))
          next grid_tiles(ids,dims,dims,[0,0,0],tree)
        end
        axis=group.fetch(:axis) || 0
        ids=group.fetch(:indices)
        splits=row.fetch('kind')=='bud' ? row.fetch('splits') : row.fetch('splits').fetch(axis)
        chunks=[];ids=ids.dup
        until ids.empty?
          size=splits.fetch(ids.size)
          raise 'invalid bucket partition' unless size.is_a?(Integer) && size.between?(1,ids.size)
          chunks<<{axis:axis,indices:ids.shift(size)}
        end
        chunks
      end
      result,recipe=B.export(File.join(@root,'buds',shape.join('x')),parent,scale,groups,self)
      B.replay(recipe)
      result=B.orient(result,shape)
      detail[:recipe]=recipe.delete_prefix(@root+'/')
    else
      raise 'unknown composition recipe'
    end
    raise 'materialized bound mismatch' unless result.shape==shape && result.rank<=target
    detail[:result]=snapshot(result)
    detail[:rank]=result.rank
    @recipes[shape]=detail
    puts JSON.generate(materialized:shape,rank:result.rank,planned:target,kind:row['kind']);$stdout.flush
    result
  end

  # Method recursion gives each cut its own locals; a closure inside construct
  # would share its left/right bindings with nested recursive calls.
  def grid_tiles(ids,dims,shape,offset,tile)
    case tile.fetch('kind')
    when 'leaf'
      indices=shape[0].times.flat_map do |a|
        shape[1].times.flat_map do |b|
          shape[2].times.map do |c|
            ids.fetch(((a+offset[0])*dims[1]+b+offset[1])*dims[2]+c+offset[2])
          end
        end
      end
      [{elementary_shape:shape,indices:indices}]
    when 'cut'
      axis,cut=tile.fetch('axis'),tile.fetch('at')
      raise 'invalid grid cut' unless axis.is_a?(Integer) && axis.between?(0,2) &&
        cut.is_a?(Integer) && cut.between?(1,shape[axis]-1)
      left,right=shape.dup,shape.dup;left[axis],right[axis]=cut,shape[axis]-cut
      origin=offset.dup;origin[axis]+=cut
      grid_tiles(ids,dims,left,offset,tile.fetch('left'))+grid_tiles(ids,dims,right,origin,tile.fetch('right'))
    else
      raise 'unknown grid plan'
    end
  end

  def snapshot(scheme)
    key=[scheme.shape,scheme.canonical_id]
    @snapshots[key] ||= B.save_snapshot(@root,'tensors',scheme)
  end

  def verify_sources_unchanged!
    @base.verify_sources_unchanged!
    @used_sources.merge!(@base.used_sources)
    raise 'source changed' unless @used_sources.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
    true
  end
end

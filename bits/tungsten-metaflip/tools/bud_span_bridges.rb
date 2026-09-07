# Offline targeted flip words, not a new tensor identity or a rank oracle.
# Expose a common vector in two equal-factor groups, then flip across them.
# Every step is the existing self-inverse GF(2) transvection. A caller must
# fully verify retained matmul schemes and materialize any composed result.
require_relative 'bud_products'

module MetaflipBudSpanBridges
  B=MetaflipBudProducts
  module_function

  def words!(values)
    raise 'invalid binary vectors' unless values.is_a?(Array) && values.size<=256 &&
      values.all?{|v|v.is_a?(Integer) && v>=0 && v.bit_length<=256}
  end

  def combination(values, mask)
    raise 'invalid combination' unless mask.is_a?(Integer) && mask>=0 && mask.bit_length<=values.size
    values.each_with_index.reduce(0){|v,(word,i)|v^(mask[i]==1 ? word : 0)}
  end

  # Basis of the intersection, with exact masks in BOTH original lists.
  # Dependent input columns are permitted; zero relations are discarded.
  def intersection(left, right)
    words!(left);words!(right)
    rows={};common={};result=[]
    (left+right).each_with_index do |word,i|
      value=word;mask=1<<i
      until value.zero?
        p=value.bit_length-1
        break unless rows[p]
        v,c=rows[p];value^=v;mask^=c
      end
      unless value.zero?
        rows[value.bit_length-1]=[value,mask];next
      end
      l=mask&((1<<left.size)-1);r=mask>>left.size
      target=combination(left,l)
      raise 'intersection relation mismatch' unless target==combination(right,r)
      value=target
      until value.zero?
        p=value.bit_length-1
        break unless common[p]
        value^=common[p]
      end
      next if value.zero?
      common[value.bit_length-1]=value
      result<<[target,l,r]
    end
    result
  end

  def flip!(terms, step)
    raise 'invalid flip word' unless step.is_a?(Array) && step.size==4 && step.all?{|v|v.is_a?(Integer)}
    shared,added,source,destination=step
    raise 'invalid flip axes or indices' unless shared.between?(0,2) && added.between?(0,2) && shared!=added &&
      source.between?(0,terms.size-1) && destination.between?(0,terms.size-1) && source!=destination
    raise 'flip requires an equal factor' unless terms[source][shared]==terms[destination][shared]
    paired=3-shared-added
    terms[destination][added]^=terms[source][added]
    terms[source][paired]^=terms[destination][paired]
    terms
  end

  def normalize(terms)
    terms.reject{|t|t.include?(0)}.tally.filter_map{|t,n|t if n.odd?}.sort
  end

  def replay(terms, word, normalize: true)
    raise 'invalid terms' unless terms.is_a?(Array) && terms.all?{|t|t.is_a?(Array) && t.size==3}
    terms.each{|t|words!(t)}
    out=terms.map(&:dup)
    word.each{|step|flip!(out,step)}
    normalize ? self.normalize(out) : out
  end

  def align_word(ids, mask, pivot, shared, added)
    raise 'invalid alignment pivot' unless pivot.between?(0,ids.size-1) && mask[pivot]==1
    ids.each_index.filter_map{|i|[shared,added,ids[i],ids[pivot]] if mask[i]==1 && i!=pivot}
  end

  # Bounded proposal enumeration: basis combinations and pivot choices are
  # capped explicitly. This is NOT exhaustive beyond those bounds. Full term
  # identities are deduplicated; bucket signatures are never state identities.
  def each_bridge(terms, max_group: 32, max_vectors: 15, max_pivots: 2)
    return enum_for(__method__,terms,max_group:max_group,max_vectors:max_vectors,max_pivots:max_pivots) unless block_given?
    raise 'invalid bridge bounds' unless max_group.is_a?(Integer) && max_group.between?(1,32) &&
      max_vectors.is_a?(Integer) && max_vectors.between?(1,255) && max_pivots.is_a?(Integer) && max_pivots.between?(1,32)
    raise 'invalid nonzero terms' unless terms.is_a?(Array) && terms.size.between?(1,256) &&
      terms.all?{|t|t.is_a?(Array) && t.size==3 && t.all?{|v|v.is_a?(Integer) && v>0 && v.bit_length<=256}}
    seen={normalize(terms)=>true}
    3.times do |shared|
      groups=terms.each_index.group_by{|i|terms[i][shared]}.values.select{|ids|ids.size<=max_group}
      groups.combination(2) do |left,right|
        next if left.size==1 && right.size==1
        ((0..2).to_a-[shared]).each do |added|
          basis=intersection(left.map{|i|terms[i][added]},right.map{|i|terms[i][added]})
          1.upto([max_vectors,(1<<basis.size)-1].min) do |mask|
            target,l,r=3.times.map{|j|combination(basis.map{|row|row[j]},mask)}
            lp=left.each_index.select{|i|l[i]==1}.first(max_pivots)
            rp=right.each_index.select{|i|r[i]==1}.first(max_pivots)
            lp.product(rp).each do |i,j|
              prefix=align_word(left,l,i,shared,added)+align_word(right,r,j,shared,added)
              next if prefix.empty? # A direct ordinary flip is not a bridge.
              aligned=replay(terms,prefix,normalize:false)
              raise 'failed to expose common vector' unless aligned[left[i]][added]==target && aligned[right[j]][added]==target
              [[left[i],right[j]],[right[j],left[i]]].each do |from,to|
                word=prefix+[[added,shared,from,to]]
                candidate=normalize(flip!(aligned.map(&:dup),word.last))
                next if seen[candidate]
                seen[candidate]=true
                yield({terms:candidate,word:word,shared_axis:shared,aligned_axis:added,
                  target:target,groups:[left,right],masks:[l,r],intersection_dimension:basis.size})
              end
            end
          end
        end
      end
    end
  end
end

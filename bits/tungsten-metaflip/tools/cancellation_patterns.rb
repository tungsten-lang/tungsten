# Exact offline GF(2) cancellation helpers. These are not rank lower bounds.
# First compress fixed-factor matrices; then search three-term 2x2x2 pencils.
# Full tensor admission is still mandatory before returning a search winner.
require_relative "bud_products"

module MetaflipSharedFactorCompression
  B = MetaflipBudProducts
  module_function
  # Exact rank factorization of sum a_i b_i^T. The factors are bit vectors.
  def factor(pairs, max_bits: 256, reverse_columns: false)
    raise "invalid matrix width limit" unless max_bits.is_a?(Integer) && max_bits.between?(1,4096)
    raise "invalid column ordering" unless [true,false].include?(reverse_columns)
    raise "invalid binary matrix factors" unless pairs.is_a?(Array) && pairs.all? do |pair|
      pair.is_a?(Array) && pair.length==2 && pair.all?{|v|v.is_a?(Integer) && v>=0 && v.bit_length<=max_bits}
    end
    columns=Hash.new(0)
    pairs.each do |left,right|
      MetaflipTensorVerifier.bit_positions(right).each{|j|columns[j]^=left}
    end
    echelon={}; basis=[]; encoded={}
    ordered=columns.sort;ordered.reverse! if reverse_columns
    ordered.each do |j,column|
      remainder=column; coefficients=0
      echelon.keys.sort.reverse_each do |pivot|
        if remainder[pivot]==1
          row,combination=echelon[pivot]
          remainder^=row; coefficients^=combination
        end
      end
      unless remainder.zero?
        bit=1<<basis.length
        basis << column
        echelon[remainder.bit_length-1]=[remainder,coefficients^bit]
        coefficients=bit
      end
      encoded[j]=coefficients
    end
    result=basis.each_with_index.map{|left,i|[left,encoded.sum{|j,c|c[i]<<j}]}
    replay=Hash.new(0)
    result.each{|a,b|MetaflipTensorVerifier.bit_positions(b).each{|j|replay[j]^=a}}
    raise "factorization mismatch" unless replay.reject{|_,c|c.zero?}==columns.reject{|_,c|c.zero?}
    result
  end

  # A tensor-preserving neutral move: replace each fixed-factor matrix by
  # its canonical column-basis factorization even when its rank is unchanged.
  # Complete tensor verification is still required before retaining a winner.
  def refactor_terms(terms, axis:, max_bits: 256, reverse_columns: false)
    raise "invalid axis" unless [0,1,2].include?(axis)
    factor([],max_bits:max_bits,reverse_columns:reverse_columns)
    raise "invalid binary tensor factors" unless terms.is_a?(Array) && terms.all? do |t|
      t.is_a?(Array) && t.length==3 && t.all?{|v|v.is_a?(Integer) && v>0 && v.bit_length<=max_bits}
    end
    other=(0..2).to_a-[axis];changed=[]
    out=terms.group_by{|t|t[axis]}.flat_map do |fixed,group|
      next group if group.size<2
      factors=factor(group.map{|t|other.map{|a|t[a]}},max_bits:max_bits,reverse_columns:reverse_columns)
      replacement=factors.map{|left,right|t=[0,0,0];t[axis]=fixed;t[other[0]]=left;t[other[1]]=right;t}
      changed<<{fixed:fixed,before:group.size,after:replacement.size} unless replacement.sort==group.sort
      replacement
    end
    out=out.tally.filter_map{|t,n|t if n.odd?}
    raise "refactor rank increased" if out.size>terms.size
    [out,changed]
  end

  # Algebra-only helper for proposal scoring. Its caller must validate the
  # input and fully admit any retained scheme; this is not a tensor verifier.
  def compress_terms(terms, max_bits: 256)
    raise "invalid matrix width limit" unless max_bits.is_a?(Integer) && max_bits.between?(1,4096)
    raise "invalid binary tensor factors" unless terms.is_a?(Array) && terms.all? do |term|
      term.is_a?(Array) && term.length==3 && term.all?{|v|v.is_a?(Integer) && v>0 && v.bit_length<=max_bits}
    end
    history=[]
    loop do
      before=terms.length
      3.times do |axis|
        other=(0..2).to_a-[axis]
        terms=terms.group_by{|t|t[axis]}.flat_map do |fixed,group|
          if group.length<2
            group
          elsif group.length==2 && group[0][other[0]]!=group[1][other[0]] &&
              group[0][other[1]]!=group[1][other[1]]
            # Over GF(2), two nonzero rank-one matrix summands have rank two
            # when both pairs of factor vectors are distinct (independent).
            group
          else
            factors=factor(group.map{|t|other.map{|i|t[i]}},max_bits:max_bits)
            if factors.length<group.length
              history << {axis:axis,fixed:fixed,before:group.length,after:factors.length}
              factors.map{|a,b|t=[0,0,0];t[axis]=fixed;t[other[0]]=a;t[other[1]]=b;t}
            else
              group
            end
          end
        end
        terms=terms.tally.filter_map{|t,n|t if n.odd?}
      end
      break if terms.length==before
    end
    [terms,history]
  end

  def compress(scheme, max_bits: 256)
    terms,history=compress_terms(scheme.terms,max_bits:max_bits)
    [B::Scheme.new(scheme.shape,B.text(terms)),history]
  end
end

module MetaflipThreeToTwo
  module_function
  def small_term(a,b,c)
    raise "invalid two-dimensional coordinate" unless [a,b,c].all?{|v|v.is_a?(Integer) && v.between?(0,3)}
    bits=0
    2.times{|i|2.times{|j|2.times{|k|bits^=(a[i]&b[j]&c[k])<<((i*2+j)*2+k)}}}
    bits
  end
  RANK_ONE=(1..3).to_a.repeated_permutation(3).map{|t|[small_term(*t),t]}.freeze
  LOW_RANK=begin
    table={0=>[]}
    RANK_ONE.each{|bits,t|table[bits]=[t]}
    RANK_ONE.combination(2){|(a,x),(b,y)|table[a^b] ||= [x,y]}
    table.freeze
  end
  def replacement(terms)
    raise "expected three nonzero binary terms" unless terms.is_a?(Array) && terms.length==3 && terms.all? do |t|
      t.is_a?(Array) && t.length==3 && t.all?{|v|v.is_a?(Integer) && v>0 && v.bit_length<=256}
    end
    bases=[]; coordinates=[]
    3.times do |axis|
      values=terms.map{|t|t[axis]}
      first=values[0];second=values.find{|v|v!=first}||0
      palette=[0,first,second,first^second]
      labels=values.map{|v|palette.index(v)}
      return nil if labels.include?(nil)
      bases << [first,second];coordinates << labels
    end
    small=3.times.reduce(0){|v,i|v^small_term(*coordinates.map{|axis|axis[i]})}
    row=LOW_RANK[small];return nil unless row
    row.map do |term|
      3.times.map{|axis|bases[axis].each_with_index.reduce(0){|out,(v,i)|out^(term[axis][i]==1 ? v : 0)}}
    end.reject{|term|term.include?(0)}
  end

  # Caller first applies shared-factor matrix compression. The remaining
  # all-three-equal-on-an-axis subsets cannot have matrix rank below three.
  def scan(scheme)
    3.times do |axis|
      other=(0..2).to_a-[axis]
      scheme.terms.group_by{|t|t[axis]}.each_value do |group|
        next if group.length<2
        rank=MetaflipSharedFactorCompression.factor(group.map{|t|other.map{|a|t[a]}}).length
        raise "apply shared-factor matrix compression first" if rank<group.length
      end
    end
    order=(0..2).sort_by{|a|scheme.terms.map{|t|t[a]}.uniq.length}
    terms=scheme.terms.map{|t|order.map{|a|t[a]}}
    groups=terms.each_index.group_by{|i|terms[i][0]}
    pairs=terms.each_index.group_by{|i|terms[i][1,2]}
    triples=terms.each_with_index.to_h{|t,i|[t,i]}
    tested=0;pencils=0
    accept=lambda do |ids|
      tested+=1
      replacement=self.replacement(ids.map{|i|terms[i]})
      if replacement
        restored=replacement.map{|t|r=[0,0,0];order.each_with_index{|a,i|r[a]=t[i]};r}
        return {tested:tested,pencils:pencils,order:order,indices:ids,replacement:restored}
      end
      nil
    end
    groups.each_value do |ids|
      ids.combination(2) do |i,j|
        u,a,b=terms[i];_,c,d=terms[j]
        next if a==c || b==d
        [a,c,a^c].product([b,d,b^d]).each do |v,w|
          (pairs[[v,w]]||[]).each do |k|
            next if terms[k][0]==u
            found=accept.call([i,j,k]);return found if found
          end
        end
      end
    end
    keys=groups.keys.sort
    keys.combination(2) do |left,right|
      third=left^right;next unless groups.key?(third)
      pencils+=1
      groups[left].product(groups[right]).each do |i,j|
        _,a,b=terms[i];_,c,d=terms[j]
        next if a==c || b==d
        [a,c,a^c].product([b,d,b^d]).each do |v,w|
          k=triples[[third,v,w]];next unless k
          eligible=[i,j,k].sort.combination(2).select{|s,t|terms[s][1]!=terms[t][1] && terms[s][2]!=terms[t][2]}
          next unless eligible.first==[i,j].sort
          found=accept.call([i,j,k]);return found if found
        end
      end
    end
    {tested:tested,pencils:pencils,order:order,indices:nil}
  end
end

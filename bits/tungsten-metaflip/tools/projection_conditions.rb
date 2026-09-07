# Offline codimension-one clipping models over GF(2).
# Counts deleted nominal terms, not tensor rank after duplicate cancellation.
# Every resulting candidate must still cross the full tensor admission gate.
require_relative "outer_basis_products"

module MetaflipProjectionClipping
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  module_function

  # A factor is identically zero, can vanish for exactly one kernel line,
  # or cannot vanish under a codimension-one clipping map on this axis.
  def label(outer, allocation, shape, axis, edge, mask, parent_shape)
    row,col = B::EDGES[edge]
    raise "wrong edge" unless [row,col].include?(axis)
    n = shape[axis]
    lines = []
    MetaflipTensorVerifier.bit_positions(outer[edge]).each do |bit|
      i,j = bit.divmod(parent_shape[col])
      keep = [allocation[axis][axis==row ? i : j],n].min
      other = axis == row ? col : row
      extent = [allocation[other][axis==row ? j : i],shape[other]].min
      next if keep.zero? || extent.zero?
      raise "not codimension one" unless keep >= n-1
      extent.times do |k|
        vector = n.times.reduce(0) do |out,d|
          position = axis == row ? d*shape[col]+k : k*shape[col]+d
          out | (mask[position]<<d)
        end
        next if vector.zero?
        return nil if keep == n
        lines << vector
        return nil if lines.uniq.length > 1
      end
    end
    lines.empty? ? :always : lines.first
  end

  def envelope(parent,allocation,leaf,slot,axis)
    raise "invalid projection axis" unless axis.is_a?(Integer) && axis.between?(0,2)
    n = leaf.shape[axis]
    raise "projection dimension exceeds bounded model" unless n.is_a?(Integer) && n.between?(1,10)
    affected = B::EDGES.each_index.select{|edge|B::EDGES[edge].include?(axis)}
    outer = parent.terms[slot]
    fixed = 0
    left,right,both = Hash.new(0),Hash.new(0),Hash.new(0)
    leaf.terms.each do |term|
      untouched = (0..2).find{|edge|!affected.include?(edge)}
      r,c = B::EDGES[untouched]
      if M.embed(term[untouched],outer[untouched],parent.shape[r],parent.shape[c],allocation[r],allocation[c],leaf.shape[r],leaf.shape[c]).zero?
        fixed += 1
        next
      end
      a,b = affected.map{|edge|label(outer,allocation,leaf.shape,axis,edge,term[edge],parent.shape)}
      if a == :always || b == :always
        fixed += 1
      else
        left[a] += 1 if a
        right[b] += 1 if b
        both[[a,b]] += 1 if a && b
      end
    end
    identity = 1<<(n-1)
    baseline = fixed+left[identity]+right[identity]-both[[identity,identity]]
    best,pairs = -1,[]
    parity = (0...(1<<n)).map{|v|v.to_s(2).count("1")%2}
    1.upto((1<<n)-1) do |u|
      1.upto((1<<n)-1) do |v|
        next unless parity[u&v] == 1
        score = fixed+left[u]+right[v]-both[[u,v]]
        if score > best
          best,pairs = score,[[u,v]]
        elsif score == best
          pairs << [u,v]
        end
      end
    end
    {axis:axis,dimension:n,baseline_zero:baseline,maximum_zero:best,maximizers:pairs.length,pairs:pairs}
  end

  def word(n,axis,u,v)
    raise "invalid projection pair" unless [n,axis,u,v].all?{|x|x.is_a?(Integer)} &&
      n.between?(1,10) && axis.between?(0,2) && u.between?(1,(1<<n)-1) && v.between?(1,(1<<n)-1)
    raise "not complementary" unless (u&v).to_s(2).count("1").odd?
    pivot = (0...n).find{|i|v[i]==1}
    columns = (0...n).reject{|i|i==pivot}.map{|i|(1<<i)^(v[i]<<pivot)}+[u]
    rows = n.times.map{|i|columns.each_with_index.reduce(0){|out,(column,j)|out|(column[i]<<j)}}
    moves = []
    add = lambda{|dst,src|rows[dst]^=rows[src]; moves << [axis,dst,src]}
    n.times do |col|
      p = (col...n).find{|i|rows[i][col]==1}
      raise "singular basis" unless p
      if p != col
        add.call(col,p); add.call(p,col); add.call(col,p)
      end
      n.times{|i|add.call(i,col) if i != col && rows[i][col]==1}
    end
    raise "elimination failed" unless rows == n.times.map{|i|1<<i}
    moves
  end
end


module MetaflipDoubleProjectionClipping
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  module_function

  def rank_two_factors(mask,rows,cols)
    raise "invalid binary factor matrix" unless [mask,rows,cols].all?{|x|x.is_a?(Integer)} &&
      rows.between?(1,16) && cols.between?(1,16) && mask.between?(0,(1<<(rows*cols))-1)
    columns = cols.times.map{|j|rows.times.reduce(0){|v,i|v|(mask[i*cols+j]<<i)}}
    basis = []
    columns.each do |v|
      next if v.zero? || basis.include?(v) || (basis.length == 2 && (basis[0]^basis[1]) == v)
      basis << v
      return nil if basis.length > 2
    end
    return [] if basis.empty?
    if basis.length == 1
      [[basis[0],columns.each_with_index.reduce(0){|v,(c,j)|v|((c.zero? ? 0 : 1)<<j)}]]
    else
      a,c = basis
      coefficients = [0,a,c,a^c]
      b = d = 0
      columns.each_with_index do |v,j|
        code = coefficients.index(v)
        b |= (code[0]<<j)
        d |= (code[1]<<j)
      end
      [[a,b],[c,d]]
    end
  end

  def envelope(parent,allocation,leaf,slot,axes,limit:16)
    raise "invalid projection axes" unless axes.is_a?(Array) && axes.length==2 &&
      axes.uniq.length==2 && axes.all?{|a|a.is_a?(Integer) && a.between?(0,2)}
    raise "invalid projection witness limit" unless limit.is_a?(Integer) && limit.between?(1,1024)
    x,y = axes.sort
    nx,ny = leaf.shape.values_at(x,y)
    raise "projection dimensions exceed bounded model" unless [nx,ny].all?{|n|n.is_a?(Integer) && n.between?(1,10)}
    edge = B::EDGES.index([x,y])
    other_x = B::EDGES.each_index.find{|i|i!=edge && B::EDGES[i].include?(x)}
    other_y = B::EDGES.each_index.find{|i|i!=edge && B::EDGES[i].include?(y)}
    outer = parent.terms[slot]
    require_x = require_y = false
    shared_possible,shared_active = true,false
    MetaflipTensorVerifier.bit_positions(outer[edge]).each do |bit|
      i,j = bit.divmod(parent.shape[y])
      a,b = [allocation[x][i],nx].min,[allocation[y][j],ny].min
      next if a.zero? || b.zero?
      shared_active = true
      raise "not codimension one" unless a>=nx-1 && b>=ny-1
      shared_possible = false if a==nx && b==ny
      require_x = true if a<nx && b==ny
      require_y = true if a==nx && b<ny
    end
    left,right,joint,tx,ty = 5.times.map{Hash.new(0)}
    fixed = 0
    leaf.terms.each_with_index do |term,index|
      bit = 1<<index
      a = MetaflipProjectionClipping.label(outer,allocation,leaf.shape,x,other_x,term[other_x],parent.shape)
      b = MetaflipProjectionClipping.label(outer,allocation,leaf.shape,y,other_y,term[other_y],parent.shape)
      if a==:always || b==:always || !shared_active
        fixed |= bit
        next
      end
      tx[a] |= bit if a
      ty[b] |= bit if b
      next unless shared_possible
      factors = rank_two_factors(term[edge],nx,ny)
      next unless factors
      if factors.empty?
        fixed |= bit
      elsif factors.length == 1
        u,v = factors[0]
        if require_x && require_y
          joint[[u,v]] |= bit
        elsif require_x
          left[u] |= bit
        elsif require_y
          right[v] |= bit
        else
          left[u] |= bit
          right[v] |= bit
        end
      elsif !require_x && !require_y
        (a,b),(c,d) = factors
        [[a,d],[c,b],[a^c,b^d]].each{|pair|joint[pair] |= bit}
      end
    end
    count_cache = {}
    pop = lambda{|mask|count_cache[mask] ||= mask.to_s(2).count("1")}
    compatibility = lambda do |n,labels|
      (1...(1<<n)).to_h do |s|
        options = labels.keys.select{|t|(s&t).to_s(2).count("1").odd?}.map{|t|[t,labels[t]]}
        options << [s&-s,0] if options.empty?
        [s,options]
      end
    end
    choices_x,choices_y = compatibility.call(nx,tx),compatibility.call(ny,ty)
    upper_x = choices_x.transform_values{|choices|choices.map{|_,mask|pop.call(mask)}.max}
    upper_y = choices_y.transform_values{|choices|choices.map{|_,mask|pop.call(mask)}.max}
    dx,dy = 1<<(nx-1),1<<(ny-1)
    baseline = pop.call(fixed|left[dx]|right[dy]|joint[[dx,dy]]|tx[dx]|ty[dy])
    best,winners,checks,bounds = baseline,[],0,0
    choices_x.each do |sx,x_choices|
      choices_y.each do |sy,y_choices|
        shared = fixed|left[sx]|right[sy]|joint[[sx,sy]]
        if pop.call(shared)+upper_x[sx]+upper_y[sy] < best
          bounds += 1
          next
        end
        x_choices.each do |cx,mx|
          y_choices.each do |cy,my|
            score = pop.call(shared|mx|my)
            checks += 1
            if score > best
              best,winners = score,[[sx,sy,cx,cy]]
            elsif score == best && winners.length < limit
              winners << [sx,sy,cx,cy]
            end
          end
        end
      end
    end
    {axes:[x,y],baseline_zero:baseline,maximum_zero:best,winners:winners,
      evaluated:checks,bounded_pairs:bounds,zero_masks:count_cache.length,
      complementary_pairs:((1<<nx)-1)*(1<<(nx-1))*((1<<ny)-1)*(1<<(ny-1))}
  end

  def candidate_word(shape,axes,choice)
    raise "invalid projection witness" unless axes.is_a?(Array) && axes.length==2 &&
      axes==axes.sort && axes.uniq.length==2 && axes.all?{|a|a.is_a?(Integer) && a.between?(0,2)} &&
      choice.is_a?(Array) && choice.length==4
    sx,sy,tx,ty = choice
    edge = B::EDGES.index(axes)
    axes.zip([sx,sy],[tx,ty]).flat_map do |axis,s,t|
      first = B::EDGES.each_index.find{|i|B::EDGES[i].include?(axis)}
      u,v = first == edge ? [s,t] : [t,s]
      MetaflipProjectionClipping.word(shape[axis],axis,u,v)
    end
  end
end


module MetaflipProjectionConditions
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  module_function
  def side(axis,edge)
    B::EDGES.each_index.find{|i|B::EDGES[i].include?(axis)} == edge ? "u" : "v"
  end

  def edge_conditions(parent,allocation,leaf,slot,axes,term,edge)
    outer = parent.terms[slot]
    x,y = B::EDGES[edge]
    moving = axes & [x,y]
    if moving.empty?
      zero = M.embed(term[edge],outer[edge],parent.shape[x],parent.shape[y],allocation[x],allocation[y],leaf.shape[x],leaf.shape[y]).zero?
      return zero ? [[]] : []
    elsif moving.length == 1
      axis = moving[0]
      label = MetaflipProjectionClipping.label(outer,allocation,leaf.shape,axis,edge,term[edge],parent.shape)
      return [[]] if label == :always
      return label ? [[[axis,side(axis,edge),label]]] : []
    end
    nx,ny = leaf.shape.values_at(x,y)
    require_x = require_y = false
    active = false
    MetaflipTensorVerifier.bit_positions(outer[edge]).each do |bit|
      i,j = bit.divmod(parent.shape[y])
      a,b = [allocation[x][i],nx].min,[allocation[y][j],ny].min
      next if a.zero? || b.zero?
      active = true
      raise "not codimension one" unless a>=nx-1 && b>=ny-1
      return [] if a==nx && b==ny && !term[edge].zero?
      require_x = true if a<nx && b==ny
      require_y = true if a==nx && b<ny
    end
    return [[]] unless active
    factors = MetaflipDoubleProjectionClipping.rank_two_factors(term[edge],nx,ny)
    return [] unless factors
    return [[]] if factors.empty?
    atom_x = lambda{|v|[x,side(x,edge),v]}
    atom_y = lambda{|v|[y,side(y,edge),v]}
    if factors.length == 1
      a,b = factors[0]
      if require_x && require_y
        [[atom_x.call(a),atom_y.call(b)]]
      elsif require_x
        [[atom_x.call(a)]]
      elsif require_y
        [[atom_y.call(b)]]
      else
        [[atom_x.call(a)],[atom_y.call(b)]]
      end
    elsif require_x || require_y
      []
    else
      (a,b),(c,d) = factors
      [[a,d],[c,b],[a^c,b^d]].map{|u,v|[atom_x.call(u),atom_y.call(v)]}
    end
  end

  def conditions(parent,allocation,leaf,slot,axes)
    raise "invalid projection axes" unless axes.is_a?(Array) && axes.uniq==axes &&
      axes.all?{|axis|axis.is_a?(Integer) && axis.between?(0,2)}
    raise "projection dimension exceeds bounded model" unless axes.all? do |axis|
      n=leaf.shape[axis]
      n.is_a?(Integer) && n.between?(1,10)
    end
    leaf.terms.map do |term|
      (0..2).flat_map{|edge|edge_conditions(parent,allocation,leaf,slot,axes,term,edge)}.uniq
    end
  end

  def evaluate(conditions,assignment)
    conditions.count do |disjunction|
      disjunction.any?{|clause|clause.all?{|axis,side,value|assignment[[axis,side]] == value}}
    end
  end
end

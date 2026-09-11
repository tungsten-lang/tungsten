#!/usr/bin/env ruby
# Bounded exact leaf-representation search for an existing outer recipe.
# Changing a leaf representation can improve truncation/cancellation without
# changing its abstract tensor. This is not an exhaustive rank search.
require "set"
require_relative "outer_basis_products"

module MetaflipOuterLeafPortfolio
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  module_function

  def permute_axes(scheme, permutation)
    raise "invalid axis permutation" unless permutation.sort == [0,1,2]
    shape = permutation.map{|i|scheme.shape[i]}
    terms = scheme.terms.map do |term|
      B::EDGES.map do |edge|
        mapped = edge.map{|i|permutation[i]}
        axis = B::EDGES.index(mapped.sort)
        mapped == mapped.sort ? term[axis] : B.transpose(term[axis],*B::EDGES[axis].map{|i|scheme.shape[i]})
      end
    end
    B::Scheme.new(shape,B.text(terms))
  end

  def permute_indices(scheme, maps)
    raise "invalid coordinate permutations" unless maps.length == 3 &&
      maps.each_with_index.all?{|p,i|p.sort == (0...scheme.shape[i]).to_a}
    caches = Array.new(3){{}}
    terms = scheme.terms.map do |term|
      B::EDGES.each_with_index.map do |(r,c),axis|
        caches[axis][term[axis]] ||= MetaflipTensorVerifier.bit_positions(term[axis]).reduce(0) do |word,bit|
          i,j = bit.divmod(scheme.shape[c])
          word | (1 << (maps[r][i]*scheme.shape[c]+maps[c][j]))
        end
      end
    end
    B::Scheme.new(scheme.shape,B.text(terms))
  end

  def variants(seed, target, shears: true)
    raise "incompatible leaf shape" unless seed.shape.sort == target.sort
    result = {}
    [0,1,2].permutation.each do |perm|
      next unless perm.map{|i|seed.shape[i]} == target
      base = permute_axes(seed,perm)
      8.times do |bits|
        maps = target.each_with_index.map do |n,axis|
          p = (0...n).to_a
          bits[axis] == 1 ? p.reverse : p
        end
        image = permute_indices(base,maps)
        result[image.canonical_id] ||= image
      end
      if shears
        3.times do |axis|
          next if target[axis] < 2
          [[0,target[axis]-1],[target[axis]-1,0]].each do |dst,src|
            image = M.transvection(base,axis,dst,src)
            result[image.canonical_id] ||= image
          end
        end
      end
    end
    result.values
  end

  def mapped_terms(parent, slot, allocation, leaf)
    return Set.new unless leaf
    mapped_terms_from(parent,slot,allocation,leaf.shape,leaf.terms)
  end

  def mapped_terms_from(parent, slot, allocation, shape, terms)
    outer = parent.terms.fetch(slot)
    caches = Array.new(3){{}}
    parity = Set.new
    terms.each do |term|
      mapped = B::EDGES.each_with_index.map do |(r,c),axis|
        caches[axis][term[axis]] ||= M.embed(term[axis],outer[axis],parent.shape[r],parent.shape[c],
          allocation[r],allocation[c],shape[r],shape[c])
      end.freeze
      next if mapped.include?(0)
      parity.include?(mapped) ? parity.delete(mapped) : parity.add(mapped)
    end
    parity
  end

  def delta_score(parity, density, delta, weight)
    rank = parity.length
    delta.each do |term|
      sign = parity.include?(term) ? -1 : 1
      rank += sign
      density += sign*weight.call(term)
    end
    [rank,density]
  end

  def basis_neighbors(leaf, moves: :both)
    raise "invalid basis moves" unless [:shear,:swap,:both].include?(moves)
    return enum_for(__method__,leaf,moves:moves) unless block_given?
    3.times do |axis|
      leaf.shape[axis].times do |dst|
        leaf.shape[axis].times do |src|
          next if dst == src
          if moves != :swap
            yield M.transvection(leaf,axis,dst,src),{kind:"shear",axis:axis,dst:dst,src:src}
          end
          if moves != :shear && dst < src
            maps = leaf.shape.map{|n|(0...n).to_a}
            maps[axis][dst],maps[axis][src] = maps[axis][src],maps[axis][dst]
            yield permute_indices(leaf,maps),{kind:"swap",axis:axis,dst:dst,src:src}
          end
        end
      end
    end
  end

  def eliminate_vector_word(n, axis, vector, deleted)
    raise "invalid kernel vector" unless [n,axis,vector,deleted].all?{|v|v.is_a?(Integer)} &&
      n.between?(1,16) && axis.between?(0,2) && vector.between?(1,(1<<n)-1) && deleted.between?(0,n-1)
    pivot = (0...n).find{|i|vector[i]==1}
    word = []
    if pivot != deleted
      word.concat([[axis,deleted,pivot],[axis,pivot,deleted],[axis,deleted,pivot]])
      vector ^= (1<<pivot)|(1<<deleted) if vector[pivot] != vector[deleted]
    end
    n.times{|i|word << [axis,i,deleted] if i != deleted && vector[i]==1}
    word
  end

  # Direct long-word moves avoid requiring every elementary intermediate to
  # improve the score. Enumerate all nonzero kernel lines for clipped axes of
  # dimension <= maximum, in both dual actions. This is not a full GL orbit.
  def truncation_neighbors(parent, slot, allocation, leaf, maximum: 8)
    raise "invalid kernel dimension bound" unless maximum.is_a?(Integer) && maximum.between?(1,10)
    return enum_for(__method__,parent,slot,allocation,leaf,maximum:maximum) unless block_given?
    truncation_proposals(parent,slot,allocation,leaf,maximum:maximum) do |terms,action|
      yield B::Scheme.new(leaf.shape,B.text(terms)),action
    end
  end

  # These raw representations are not witnesses. Deduplication uses the same
  # complete term-multiset identity as Scheme, not a proxy or a hull.
  def truncation_proposals(parent, slot, allocation, leaf, maximum: 8)
    raise "invalid kernel dimension bound" unless maximum.is_a?(Integer) && maximum.between?(1,10)
    return enum_for(__method__,parent,slot,allocation,leaf,maximum:maximum) unless block_given?
    profiles = M.support_profiles(parent)
    seen = {leaf.canonical_id=>true}
    3.times do |axis|
      n = leaf.shape[axis]
      next if n > maximum
      active = profiles[axis][slot].flatten.uniq
      next unless active.any?{|i|allocation[axis][i]<n}
      deleted = n-1
      1.upto((1<<n)-1) do |vector|
        word = eliminate_vector_word(n,axis,vector,deleted)
        [false,true].each do |dual|
          action = dual ? word.map{|a,d,s|[a,s,d]} : word
          terms = M.transvection_word_terms(leaf,action)
          identity = Digest::SHA256.hexdigest([leaf.shape.join("x"),B.text(terms.sort)].join("\n"))
          next if seen[identity]
          seen[identity] = true
          yield terms,{kind:"kernel",axis:axis,vector:vector,deleted:deleted,dual:dual,word:action}
        end
      end
    end
  end

  # Compose shortlisted kernel words on different axes of the same leaf. The
  # shortlist is a search heuristic, not dominance or exhaustive coverage.
  # As with truncation_proposals, returned terms still require exact admission.
  def kernel_pair_proposals(leaf, pools, seen: Set.new([leaf.canonical_id]))
    raise "invalid kernel pair pools" unless pools.length == 3 && pools.each_with_index.all? do |pool,axis|
      pool.all?{|action|action[:kind] == "kernel" && action[:axis] == axis}
    end
    return enum_for(__method__,leaf,pools,seen:seen) unless block_given?
    (0...3).to_a.combination(2) do |a,b|
      pools[a].product(pools[b]).each do |left,right|
        word = left.fetch(:word)+right.fetch(:word)
        terms = M.transvection_word_terms(leaf,word)
        identity = Digest::SHA256.hexdigest([leaf.shape.join("x"),B.text(terms.sort)].join("\n"))
        next if seen.include?(identity)
        seen.add(identity)
        yield terms,{kind:"kernel_pair",word:word,components:[left,right]}
      end
    end
  end

  def shear_walk(parent, allocation, leaves:, rounds: 4, &progress)
    basis_walk(parent,allocation,leaves:leaves,rounds:rounds,moves: :shear,&progress)
  end

  def basis_walk(parent, allocation, leaves:, rounds: 4, moves: :both, kernel_maximum: 8, verification: :all, kernel_pair_width: 0)
    raise "invalid walk limit" unless rounds.is_a?(Integer) && rounds.between?(1,16)
    raise "invalid basis moves" unless [:shear,:swap,:both,:kernel].include?(moves)
    raise "invalid kernel dimension bound" unless kernel_maximum.is_a?(Integer) && kernel_maximum.between?(1,10)
    raise "invalid verification policy" unless [:all,:winner].include?(verification) && (verification == :all || moves == :kernel)
    raise "invalid kernel pair width" unless kernel_pair_width.is_a?(Integer) && kernel_pair_width.between?(0,32) &&
      (kernel_pair_width.zero? || moves == :kernel)
    baseline, = M.compose(parent,allocation,leaves:leaves)
    current = leaves.dup
    mapped = current.each_with_index.map{|leaf,i|mapped_terms(parent,i,allocation,leaf)}
    parity = mapped.reduce(Set.new){|state,part|state ^ part}
    raise "initial walk mismatch" unless parity == baseline.terms.to_set
    density_cache = {}
    weight = lambda{|term|density_cache[term] ||= term.sum{|v|v.to_s(2).count("1")}}
    density = parity.sum(&weight)
    checks, pair_checks, verified_neighbors, history, completed, settled = 0, 0, 0, [], 0, false
    rounds.times do |round|
      changed = false
      current.each_with_index do |leaf,slot|
        next unless leaf
        best, key = nil, [parity.length,density]
        raw = verification == :winner
        pools = Array.new(3){[]}
        seen = Set.new([leaf.canonical_id])
        neighbors = if verification == :winner
          truncation_proposals(parent,slot,allocation,leaf,maximum:kernel_maximum)
        elsif moves == :kernel
          truncation_neighbors(parent,slot,allocation,leaf,maximum:kernel_maximum)
        else
          basis_neighbors(leaf,moves:moves)
        end
        consider = lambda do |image,action|
          terms = raw ? mapped_terms_from(parent,slot,allocation,leaf.shape,image) : mapped_terms(parent,slot,allocation,image)
          verified_neighbors += 1 unless raw
          score = delta_score(parity,density,mapped[slot]^terms,weight)
          checks += 1
          pair_checks += 1 if action[:kind] == "kernel_pair"
          if kernel_pair_width.positive? && action[:kind] == "kernel"
            identity = raw ? Digest::SHA256.hexdigest([leaf.shape.join("x"),B.text(image.sort)].join("\n")) : image.canonical_id
            seen.add(identity)
            pool = pools.fetch(action.fetch(:axis))
            pool << {score:score,index:checks,action:action}
            pool.sort_by!{|entry|[*entry[:score],entry[:index]]}
            pool.pop if pool.length > kernel_pair_width
          end
          if (score <=> key) == -1
            best = {leaf:raw ? nil : image,raw_leaf:raw ? image : nil,terms:terms,**action}
            key = score
          end
        end
        neighbors.each(&consider)
        if kernel_pair_width.positive?
          kernel_pair_proposals(leaf,pools.map{|pool|pool.map{|entry|entry[:action]}},seen:seen) do |terms,action|
            consider.call(raw ? terms : B::Scheme.new(leaf.shape,B.text(terms)),action)
          end
        end
        next unless best
        unless best[:leaf]
          # Every selected leaf is checked before it changes the current state.
          # The final whole-product check remains unconditional as well.
          best[:leaf] = B::Scheme.new(leaf.shape,B.text(best[:raw_leaf]))
          verified_neighbors += 1
          raise "screened mapping mismatch" unless mapped_terms(parent,slot,allocation,best[:leaf]) == best[:terms]
        end
        parity ^= mapped[slot] ^ best[:terms]
        current[slot],mapped[slot] = best.values_at(:leaf,:terms)
        density = key[1]
        raise "walk delta mismatch" unless key[0] == parity.length
        history << best.slice(:kind,:axis,:dst,:src,:word,:vector,:dual,:deleted,:components).merge(round:round,slot:slot,rank:parity.length,density:density,
          from:leaf.canonical_id,to:current[slot].canonical_id)
        changed = true
      end
      completed += 1
      yield(round:round,checks:checks,rank:parity.length,density:density,accepted:history.length) if block_given?
      unless changed
        settled = true
        break
      end
    end
    result,audit, = M.compose(parent,allocation,leaves:current)
    raise "final walk mismatch" unless result.terms.to_set == parity && result.audit[:density] == density
    raise "non-monotone walk" unless ([result.rank,density] <=> [baseline.rank,baseline.audit[:density]]) <= 0
    {result:result,leaves:current,audit:audit,initial_rank:baseline.rank,initial_density:baseline.audit[:density],
     rank:result.rank,density:density,checks:checks,pair_checks:pair_checks,verified_neighbors:verified_neighbors,verification:verification,
     history:history,rounds:completed,round_limit:rounds,settled:settled,moves:moves,kernel_maximum:kernel_maximum,
     kernel_pair_width:kernel_pair_width}
  end

  def leaf_pools(parent, allocation, leaves, seeds, seed_limit, shears)
    pools, used_sources, variant_cache = [], {}, {}
    leaves.each_with_index do |leaf,slot|
      unless leaf
        pools << []
        next
      end
      eligible = (seeds.fetch(leaf.shape.sort,[])+[leaf]).uniq(&:canonical_id).
        select{|s|s.rank <= leaf.rank}.sort_by{|s|[s.rank,s.audit[:density],s.canonical_id]}.first(seed_limit)
      eligible.each{|s|used_sources[s.canonical_id]=s}
      images = [leaf]+eligible.flat_map do |s|
        variant_cache[[s.canonical_id,leaf.shape]] ||= variants(s,leaf.shape,shears:shears)
      end
      # Identical mapped term sets have identical continuation behavior in
      # this fixed, independent per-slot portfolio; preserve one exact leaf.
      by_image = {}
      images.uniq(&:canonical_id).each do |image|
        terms = mapped_terms(parent,slot,allocation,image)
        key = terms.to_a.sort
        old = by_image[key]
        by_image[key] = {leaf:image,terms:terms} if !old || image.canonical_id < old[:leaf].canonical_id
      end
      pools << by_image.values.sort_by{|r|[r[:terms].length,r[:leaf].canonical_id]}
    end
    [pools,used_sources.values,variant_cache.values.sum(&:length)]
  end

  # Raw scores only order a bounded shortlist. Cleanup returns a tensor, not
  # a score; recheck its complete identity before comparing rank/density.
  # Preserve every assessment (including rank ties) and the raw recipe state.
  # A cache reuses cleanup for identical raw tensors, never prunes leaf states.
  def optimize_cleaned(parent, allocation, leaves:, seeds:, cleanup:, seed_limit: 4,
      rounds: 4, shears: true, pair_width: 0, shortlist: 16, assessment_limit: 65)
    raise "invalid search limits" unless seed_limit.is_a?(Integer) && seed_limit.between?(1,32) &&
      rounds.is_a?(Integer) && rounds.between?(1,32) && pair_width.is_a?(Integer) && pair_width.between?(0,32) &&
      shortlist.is_a?(Integer) && shortlist.between?(1,256) &&
      assessment_limit.is_a?(Integer) && assessment_limit.between?(1,4096)
    raise "missing cleanup callback" unless cleanup.respond_to?(:call)
    baseline, = M.compose(parent,allocation,leaves:leaves)
    pools,sources,verified_variants = leaf_pools(parent,allocation,leaves,seeds,seed_limit,shears)
    current = leaves.dup
    cache, assessments, history, round_audits = {}, [], [], []
    objective = ->(s){[s.rank,s.audit.fetch(:density)]}
    assess = lambda do |state,action|
      raw,audit, = M.compose(parent,allocation,leaves:state)
      raw.freeze
      cached = cache.key?(raw.canonical_id)
      cleaned = cache.fetch(raw.canonical_id) do
        candidate = cleanup.call(raw)
        raise "cleanup must return a same-shape Scheme" unless candidate.is_a?(B::Scheme) && candidate.shape == raw.shape
        checked = B::Scheme.new(raw.shape,B.text(candidate.terms))
        cache[raw.canonical_id] = checked.freeze
      end
      result = (objective.call(cleaned) <=> objective.call(raw)) <= 0 ? cleaned : raw
      entry = {raw:raw,cleaned:cleaned,result:result,leaves:state.dup.freeze,audit:audit,
        action:action,cached:cached,rank:result.rank,density:result.audit[:density]}
      assessments << entry
      entry
    end
    best = assess.call(current,{kind:"baseline"})
    initial = objective.call(best[:result])
    checks, pair_checks = 0, 0
    stop_reason = :round_limit
    rounds.times do |round|
      if assessments.length == assessment_limit
        stop_reason = :assessment_limit
        break
      end
      mapped = current.each_with_index.map{|leaf,i|mapped_terms(parent,i,allocation,leaf)}
      parity = best[:raw].terms.to_set
      density = best[:raw].audit[:density]
      weights = {}
      weight = ->(t){weights[t] ||= t.sum{|v|MetaflipTensorVerifier.bit_positions(v).length}}
      proposals, generated = [], 0
      offer = lambda do |replacements,delta,score|
        next if delta.empty?
        generated += 1
        proposal = {replacements:replacements,score:score,index:generated}
        proposals << proposal
        proposals.sort_by!{|p|[*p[:score],p[:index]]}
        proposals.pop if proposals.length > shortlist
      end
      singles = pools.each_with_index.map do |pool,slot|
        pool.map do |candidate|
          delta = mapped[slot] ^ candidate[:terms]
          score = delta_score(parity,density,delta,weight)
          checks += 1
          offer.call([[slot,candidate]],delta,score)
          {candidate:candidate,delta:delta,score:score}
        end.sort_by{|r|[r[:score],r[:candidate][:leaf].canonical_id]}.first(pair_width)
      end
      if pair_width.positive?
        current.each_index.to_a.combination(2) do |a,b|
          singles[a].product(singles[b]).each do |left,right|
            next if left[:delta].empty? || right[:delta].empty?
            delta = left[:delta] ^ right[:delta]
            score = delta_score(parity,density,delta,weight)
            checks += 1
            pair_checks += 1
            offer.call([[a,left[:candidate]],[b,right[:candidate]]],delta,score)
          end
        end
      end
      evaluated, winner = 0, best
      proposals.each do |proposal|
        break if assessments.length == assessment_limit
        state = current.dup
        replacements = proposal[:replacements]
        action = {kind:replacements.length == 1 ? "single" : "pair",round:round,
          slots:replacements.map(&:first),from:replacements.map{|slot,_|current[slot].canonical_id},
          to:replacements.map{|_,c|c[:leaf].canonical_id},raw_score:proposal[:score]}
        replacements.each{|slot,c|state[slot]=c[:leaf]}
        entry = assess.call(state,action)
        raise "cleanup proposal mismatch" unless objective.call(entry[:raw]) == proposal[:score]
        evaluated += 1
        winner = entry if (objective.call(entry[:result]) <=> objective.call(winner[:result])) == -1
      end
      round_audits << {round:round,generated:generated,shortlisted:proposals.length,evaluated:evaluated,
        unassessed:generated-evaluated}
      if winner.equal?(best)
        stop_reason = if evaluated < proposals.length
          :assessment_limit
        elsif generated.zero?
          :empty_neighborhood
        else
          :no_shortlisted_improvement
        end
        break
      end
      best, current = winner, winner[:leaves].dup
      history << {assessment:assessments.index{|e|e.equal?(winner)},**winner[:action],
        rank:winner[:rank],density:winner[:density]}
    end
    raise "non-monotone cleaned search" unless (objective.call(best[:result]) <=> initial) <= 0
    {result:best[:result],raw:best[:raw],leaves:best[:leaves],audit:best[:audit],
      initial_rank:initial[0],initial_density:initial[1],raw_initial_rank:baseline.rank,
      rank:best[:rank],density:best[:density],checks:checks,pair_checks:pair_checks,
      assessment_count:assessments.length,cleanup_calls:cache.length,assessments:assessments,history:history,
      rounds:round_audits.length,round_audits:round_audits,stop_reason:stop_reason,
      unassessed_proposals:round_audits.sum{|r|r[:unassessed]},
      mapped_pool_sizes:pools.map(&:length),verified_variants:verified_variants,sources:sources,
      seed_limit:seed_limit,round_limit:rounds,shears:shears,pair_width:pair_width,
      shortlist:shortlist,assessment_limit:assessment_limit}
  end

  def optimize(parent, allocation, leaves:, seeds:, seed_limit: 4, rounds: 4, shears: true, pair_width: 0)
    raise "invalid search limits" unless seed_limit.is_a?(Integer) && seed_limit.between?(1,32) &&
      rounds.is_a?(Integer) && rounds.between?(1,32) && pair_width.is_a?(Integer) && pair_width.between?(0,32)
    baseline, = M.compose(parent,allocation,leaves:leaves)
    current = leaves.dup
    mapped = current.each_with_index.map{|leaf,i|mapped_terms(parent,i,allocation,leaf)}
    parity = mapped.reduce(Set.new){|state,part|state ^ part}
    raise "initial parity mismatch" unless parity == baseline.terms.to_set
    density_cache = {}
    weight = lambda{|term|density_cache[term] ||= term.sum{|v|MetaflipTensorVerifier.bit_positions(v).length}}
    current_density = parity.sum(&weight)
    pools,sources,verified_variants = leaf_pools(parent,allocation,leaves,seeds,seed_limit,shears)
    checks, history, settled, completed = 0, [], false, 0
    rounds.times do |round|
      changed = false
      current.each_index do |slot|
        next if current[slot].nil?
        best, best_key = nil, [parity.length,current_density]
        pools[slot].each do |candidate|
          delta = mapped[slot] ^ candidate[:terms]
          key = delta_score(parity,current_density,delta,weight)
          checks += 1
          if (key <=> best_key) == -1
            best, best_key = candidate, key
          end
        end
        next unless best
        from = current[slot].canonical_id
        parity ^= mapped[slot] ^ best[:terms]
        current[slot], mapped[slot] = best[:leaf], best[:terms]
        current_density = best_key[1]
        raise "delta rank mismatch" unless best_key[0] == parity.length
        history << {round:round,slot:slot,from:from,to:current[slot].canonical_id,rank:parity.length,density:current_density}
        changed = true
      end
      completed += 1
      unless changed
        settled = true
        break
      end
    end
    pair_checks = 0
    if pair_width > 0
      # A bounded two-slot move can cross a barrier that neither individual
      # replacement improves. Shortlisting is heuristic, never an exhaustion.
      2.times do |pair_round|
        shortlists = pools.each_with_index.map do |pool,slot|
          pool.map do |candidate|
            delta = mapped[slot] ^ candidate[:terms]
            score = delta_score(parity,current_density,delta,weight)
            checks += 1
            {candidate:candidate,delta:delta,score:score}
          end.sort_by{|r|[r[:score],r[:candidate][:leaf].canonical_id]}.first(pair_width)
        end
        best, best_key = nil, [parity.length,current_density]
        current.each_index.to_a.combination(2) do |a,b|
          shortlists[a].product(shortlists[b]).each do |left,right|
            delta = left[:delta] ^ right[:delta]
            key = delta_score(parity,current_density,delta,weight)
            checks += 1
            pair_checks += 1
            if (key <=> best_key) == -1
              best = {a:a,b:b,left:left[:candidate],right:right[:candidate],delta:delta}
              best_key = key
            end
          end
        end
        break unless best
        a,b = best.values_at(:a,:b)
        from = [current[a].canonical_id,current[b].canonical_id]
        parity ^= best[:delta]
        current[a],mapped[a] = best[:left].values_at(:leaf,:terms)
        current[b],mapped[b] = best[:right].values_at(:leaf,:terms)
        current_density = best_key[1]
        raise "pair delta mismatch" unless parity.length == best_key[0]
        history << {kind:"pair",round:pair_round,slots:[a,b],from:from,
          to:[current[a].canonical_id,current[b].canonical_id],rank:parity.length,density:current_density}
        settled = false # Single-slot stationarity must be rechecked after a pair.
      end
    end
    result,audit, = M.compose(parent,allocation,leaves:current)
    raise "final parity mismatch" unless result.terms.to_set == parity && result.audit[:density] == current_density
    raise "non-monotone search" unless ([result.rank,current_density] <=> [baseline.rank,baseline.audit[:density]]) <= 0
    {result:result,leaves:current,audit:audit,initial_rank:baseline.rank,initial_density:baseline.audit[:density],
     rank:result.rank,density:current_density,checks:checks,pair_checks:pair_checks,rounds:completed,settled:settled,history:history,
     mapped_pool_sizes:pools.map(&:length),verified_variants:verified_variants,
     sources:sources,seed_limit:seed_limit,round_limit:rounds,shears:shears,pair_width:pair_width}
  end
end

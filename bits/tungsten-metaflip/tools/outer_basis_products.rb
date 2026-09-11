#!/usr/bin/env ruby
# Offline support-aware outer-basis search. Exact witnesses, not a rank oracle.
# The actions and embeddings match flipfleet_outer_isotropy/ffbc_compose.
require_relative "bud_products"

module MetaflipOuterBasisProducts
  B = MetaflipBudProducts
  module_function

  def shear(word, rows, cols, dimension, dst, src)
    result = word
    if dimension.zero?
      cols.times { |c| result ^= 1 << (dst*cols+c) if word[src*cols+c] == 1 }
    else
      rows.times { |r| result ^= 1 << (r*cols+dst) if word[r*cols+src] == 1 }
    end
    result
  end

  def transvection(parent, axis, dst, src)
    raise "invalid transvection" unless axis.is_a?(Integer) && axis.between?(0,2) && dst != src &&
      [dst,src].all? { |i| i.is_a?(Integer) && i.between?(0,parent.shape[axis]-1) }
    affected = B::EDGES.each_index.select { |edge| B::EDGES[edge].include?(axis) }
    terms = parent.terms.map do |term|
      result = term.dup
      affected.each_with_index do |edge,index|
        d,s = index.zero? ? [dst,src] : [src,dst]
        r,c = B::EDGES[edge]
        result[edge] = shear(term[edge],parent.shape[r],parent.shape[c],B::EDGES[edge].index(axis),d,s)
      end
      result
    end
    B::Scheme.new(parent.shape,B.text(terms))
  end

  # Execute a whole invertible basis word before one full tensor check.
  # This has the same action as successive transvection calls, without
  # repeatedly validating intermediate representations that are not admitted.
  def transvection_word(parent, word)
    B::Scheme.new(parent.shape,B.text(transvection_word_terms(parent,word)))
  end

  # Unverified proposal terms. Callers must pass an exact admission boundary
  # before exposing a candidate as a tensor witness.
  def transvection_word_terms(parent, word)
    raise "invalid basis word" unless word.is_a?(Array) && word.all? do |move|
      move.is_a?(Array) && move.length == 3 && move.all?{|v|v.is_a?(Integer)} &&
        move[0].between?(0,2) && move[1] != move[2] &&
        move.drop(1).all?{|v|v.between?(0,parent.shape[move[0]]-1)}
    end
    terms = parent.terms.map(&:dup)
    word.each do |axis,dst,src|
      affected = B::EDGES.each_index.select{|edge|B::EDGES[edge].include?(axis)}
      affected.each_with_index do |edge,index|
        d,s = index.zero? ? [dst,src] : [src,dst]
        r,c = B::EDGES[edge]
        dimension = B::EDGES[edge].index(axis)
        cache = {}
        terms.each do |term|
          term[edge] = cache[term[edge]] ||= shear(term[edge],parent.shape[r],parent.shape[c],dimension,d,s)
        end
      end
    end
    terms
  end

  def gl2_image(parent, axis, code)
    words = [[],[[1,0]],[[0,1]],[[1,0],[0,1]],[[0,1],[1,0]],[[1,0],[0,1],[1,0]]]
    raise "invalid GL2 image" unless axis.is_a?(Integer) && axis.between?(0,2) &&
      parent.shape[axis] == 2 && code.is_a?(Integer) && code.between?(0,5)
    words[code].reduce(parent) { |p,(dst,src)| transvection(p,axis,dst,src) }
  end

  def orbit2(parent)
    raise "requires 2x2x2 outer" unless parent.shape == [2,2,2]
    images = {}
    6.times do |i|
      left = gl2_image(parent,0,i)
      6.times do |j|
        middle = gl2_image(left,1,j)
        6.times do |k|
          image = gl2_image(middle,2,k)
          row = images[image.canonical_id] ||= {parent:image,codes:[]}
          row[:codes] << [i,j,k]
        end
      end
    end
    images.values
  end

  def allocations(total, parts, minimum: 1, maximum: 15)
    return [] if parts < 1 || minimum < 0 || maximum < minimum || total < parts*minimum || total > parts*maximum
    return [[total]] if parts == 1
    lo = [minimum,total-(parts-1)*maximum].max
    hi = [maximum,total-(parts-1)*minimum].min
    (lo..hi).flat_map { |v| allocations(total-v,parts-1,minimum:minimum,maximum:maximum).map { |r| [v]+r } }
  end

  def support_profiles(parent)
    3.times.map do |axis|
      parent.terms.map do |term|
        B::EDGES.each_index.filter_map do |edge|
          next unless B::EDGES[edge].include?(axis)
          r,c = B::EDGES[edge]
          MetaflipTensorVerifier.bit_positions(term[edge]).map do |bit|
            B::EDGES[edge].index(axis).zero? ? bit/parent.shape[c] : bit%parent.shape[c]
          end.uniq
        end
      end
    end
  end

  def extents(profiles, allocation)
    profiles.map { |pair| pair.map { |support| support.map { |i| allocation[i] }.max || 0 }.min }
  end

  def leaf_shapes(parent, allocation)
    profiles = support_profiles(parent)
    dimensions = 3.times.map { |axis| extents(profiles[axis],allocation[axis]) }
    parent.rank.times.map { |term| dimensions.map { |d| d[term] } }
  end

  def embed(word, outer_word, rows, cols, row_alloc, col_alloc, local_rows, local_cols)
    row_offsets = [0]
    col_offsets = [0]
    row_alloc.each { |n| row_offsets << row_offsets.last+n }
    col_alloc.each { |n| col_offsets << col_offsets.last+n }
    bits = MetaflipTensorVerifier.bit_positions(word)
    MetaflipTensorVerifier.bit_positions(outer_word).reduce(0) do |result,outer_bit|
      i,j = outer_bit.divmod(cols)
      bits.each do |bit|
        r,c = bit.divmod(local_cols)
        next if r >= row_alloc[i] || c >= col_alloc[j]
        result ^= 1 << ((row_offsets[i]+r)*col_offsets.last+col_offsets[j]+c)
      end
      result
    end
  end

  # Proposal construction only. Returned terms are not a verified witness.
  # Every admitted result must still pass Scheme's full tensor check.
  def compose_terms(parent, allocation, library: nil, leaves: nil)
    raise "invalid allocation" unless allocation.length == 3 && allocation.each_with_index.all? do |a,axis|
      a.length == parent.shape[axis] && a.all? { |v| v.is_a?(Integer) && v >= 0 } && a.sum.positive?
    end
    shapes = leaf_shapes(parent,allocation)
    leaves ||= shapes.map { |shape| shape.include?(0) ? nil : library.scheme(shape) }
    raise "leaf count mismatch" unless leaves.length == parent.rank
    parity = {}
    nominal = zeros = 0
    parent.terms.each_with_index do |outer,index|
      leaf = leaves[index]
      if shapes[index].include?(0)
        raise "unexpected zero-extent leaf" if leaf
        next
      end
      raise "wrong leaf shape" unless leaf && leaf.shape == shapes[index]
      nominal += leaf.rank
      caches = Array.new(3) { {} }
      leaf.terms.each do |local|
        term = B::EDGES.each_with_index.map do |(r,c),edge|
          caches[edge][local[edge]] ||= embed(local[edge],outer[edge],parent.shape[r],parent.shape[c],
            allocation[r],allocation[c],leaf.shape[r],leaf.shape[c])
        end
        if term.include?(0)
          zeros += 1
        else
          parity[term] = !parity.fetch(term,false)
        end
      end
    end
    terms = parity.select { |_,odd| odd }.keys
    [terms,{nominal:nominal,zero_terms:zeros,parity_reduction:nominal-zeros-terms.length},leaves]
  end

  def compose(parent, allocation, library: nil, leaves: nil)
    terms,audit,leaves = compose_terms(parent,allocation,library:library,leaves:leaves)
    [B::Scheme.new(allocation.map(&:sum),B.text(terms)),audit,leaves]
  end

  def export(root, parent, allocation, leaves, target)
    source,audit, = compose(parent,allocation,leaves:leaves)
    result = B.orient(source,target)
    recipe = {schema:1,kind:"outer-basis-block",field:"GF(2)",record_claim:false,
      parent:B.save_snapshot(root,"inputs",parent),allocation:allocation,
      leaves:leaves.map { |leaf| leaf && B.save_snapshot(root,"leaves",leaf) },
      result:B.save_snapshot(root,"candidates",result),exact_rank:result.rank,formula_rank:audit[:nominal],audit:audit}
    path = File.join(root,"#{target.join('x')}.recipe.json")
    File.write(path,JSON.pretty_generate(recipe)+"\n")
    [result,path]
  end

  def replay(path)
    recipe = JSON.parse(File.read(path))
    raise "unsupported recipe" unless recipe.values_at("schema","kind","field") == [1,"outer-basis-block","GF(2)"]
    root = File.dirname(File.expand_path(path))
    read = lambda do |entry|
      target = File.expand_path(entry.fetch("path"),root)
      raise "snapshot escapes recipe" unless target.start_with?(root+"/")
      raise "hash mismatch" unless Digest::SHA256.file(target).hexdigest == entry.fetch("sha256")
      B.load_scheme(target,entry.fetch("shape"))
    end
    parent = read.call(recipe.fetch("parent"))
    leaves = recipe.fetch("leaves").map { |entry| entry && read.call(entry) }
    source,audit, = compose(parent,recipe.fetch("allocation"),leaves:leaves)
    saved = read.call(recipe.fetch("result"))
    result = B.orient(source,saved.shape)
    raise "construction mismatch" unless result.terms == saved.terms && result.rank == recipe.fetch("exact_rank") &&
      audit[:nominal] == recipe.fetch("formula_rank") && audit.transform_keys(&:to_s) == recipe.fetch("audit")
    result.audit
  end

  # Formula-only screening is separate from exact candidate admission.
  # Stream a bounded allocation census across targets, keeping only k prices
  # per canonical shape. These are proposals: cancellation/cleanup can change
  # their ordering, and library ranks need checked witnesses at materialization.
  def width_frontier(images, library, widths: [3,4,5], required_width: nil, per_target: 2, context_limit: 100_000)
    raise "invalid width frontier" unless images.is_a?(Array) && !images.empty? &&
      images.all? { |e| e.is_a?(Hash) && e[:parent].is_a?(B::Scheme) } &&
      widths.is_a?(Array) && !widths.empty? && widths.uniq.length == widths.length &&
      widths.all? { |v| v.is_a?(Integer) && v.between?(1,16) } &&
      (required_width.nil? || (required_width.is_a?(Integer) && widths.include?(required_width))) &&
      per_target.is_a?(Integer) && per_target.positive? &&
      context_limit.is_a?(Integer) && context_limit >= 0
    widths = widths.sort.freeze
    expected = images.sum { |e| widths.length**e[:parent].shape.sum }
    eligible = images.sum do |e|
      parts = e[:parent].shape.sum
      widths.length**parts - (required_width.nil? ? 0 : (widths.length-1)**parts)
    end
    prices = {}
    targets = {}
    visited = scored = 0
    images.each_with_index do |entry,index|
      break if visited >= context_limit
      parent = entry.fetch(:parent)
      profiles = support_profiles(parent)
      widths.repeated_permutation(parent.shape.sum) do |word|
        break if visited >= context_limit
        visited += 1
        next if required_width && !word.include?(required_width)
        offset = 0
        allocation = parent.shape.map { |n| row = word.slice(offset,n).freeze; offset += n; row }.freeze
        dims = 3.times.map { |axis| extents(profiles[axis],allocation[axis]) }
        formula = parent.rank.times.sum do |term|
          shape = dims.map { |d| d[term] }.sort.freeze
          prices.fetch(shape) do
            value = library.rank(shape)
            raise "invalid library rank" unless value.is_a?(Integer) && value.positive?
            prices[shape] = value
          end
        end
        target = allocation.map(&:sum).sort.freeze
        candidate = [formula,index,allocation].freeze
        rows = targets[target] ||= []
        rows << candidate
        rows.sort!
        rows.pop while rows.length > per_target
        yield({index:scored,parent_index:index,allocation:allocation,target:allocation.map(&:sum).freeze,
          formula_rank:formula}.freeze) if block_given?
        scored += 1
      end
    end
    {complete:visited == expected,visited_allocations:visited,expected_allocations:expected,
      scored:scored,expected_contexts:eligible,context_limit:context_limit,widths:widths,required_width:required_width,
      per_target:per_target,selection:"formula shortlist; not exhaustive cleanup minimization",
      targets:targets.sort.map { |shape,rows| {shape:shape,formula_min:rows.first[0],candidates:rows} }}
  end

  def formula_scan(images, target, library, minimum: 1, maximum: 15, slack: 4)
    raise "invalid scan limits" unless [minimum,maximum,slack].all? { |n| n.is_a?(Integer) } &&
      minimum >= 0 && maximum.between?(1,16) && minimum <= maximum && slack >= 0
    raise "invalid target" unless target.is_a?(Array) && target.length == 3 &&
      target.all? { |n| n.is_a?(Integer) && n.between?(1,16) }
    stride = maximum+1
    prices = Array.new(stride**3,0)
    1.upto(maximum) { |n| 1.upto(maximum) { |m| 1.upto(maximum) { |p| prices[(n*stride+m)*stride+p] = library.rank([n,m,p]) } } }
    best = Float::INFINITY
    candidates = []
    scored = 0
    images.each_with_index do |entry,index|
      parent = entry.fetch(:parent)
      profiles = support_profiles(parent)
      target.permutation.to_a.uniq.each do |shape|
        allocations = 3.times.map { |axis| self.allocations(shape[axis],parent.shape[axis],minimum:minimum,maximum:maximum) }
        extents = allocations.each_with_index.map { |rows,axis| rows.map { |row| self.extents(profiles[axis],row) } }
        allocations[0].each_index do |ni|
          ns = extents[0][ni]
          allocations[1].each_index do |mi|
            ms = extents[1][mi]
            allocations[2].each_index do |pi|
              ps = extents[2][pi]
              score = parent.rank.times.sum { |t| prices[(ns[t]*stride+ms[t])*stride+ps[t]] }
              scored += 1
              if score < best
                best = score
                candidates.select! { |r| r[0] <= best+slack }
              end
              if score <= best+slack
                candidates << [score,index,[allocations[0][ni],allocations[1][mi],allocations[2][pi]]]
              end
            end
          end
        end
      end
    end
    raise "no covered allocation" if candidates.empty?
    candidates.sort!
    {formula_min:best,scored:scored,competitive:candidates.length,slack:slack,candidates:candidates}
  end

  # Formula exhaustion, then a bounded cheapest-first materialisation pass.
  # No claim of exhaustive post-cancellation rank minimisation is made.
  def scan(images, target, library, minimum: 1, maximum: 15, slack: 4, materializations: 5000, verification: :all)
    raise "invalid materialization limit" unless materializations.is_a?(Integer) && materializations.positive?
    screened = formula_scan(images,target,library,minimum:minimum,maximum:maximum,slack:slack)
    materialized = materialize(images,screened.fetch(:candidates),library,limit:materializations,verification:verification)
    screened.reject { |key,_| key == :candidates }.merge(materialized)
  end

  def materialize(images, candidates, library, limit: 5000, verification: :all)
    raise "invalid materialization limit" unless limit.is_a?(Integer) && limit.positive?
    raise "invalid verification policy" unless [:all,:winner].include?(verification)
    raise "no candidates" if candidates.empty?
    selected = candidates.first(limit)
    winner = nil
    histogram = Hash.new(0)
    selected.each do |formula,index,allocation|
      if verification == :all
        result,audit,leaves = compose(images[index][:parent],allocation,library:library)
        terms,rank,density = result.terms,result.rank,result.audit[:density]
      else
        terms,audit,leaves = compose_terms(images[index][:parent],allocation,library:library)
        result = nil
        rank = terms.length
        density = terms.sum { |t| t.sum { |v| v.to_s(2).count("1") } }
      end
      raise "formula mismatch" unless audit[:nominal] == formula
      histogram[rank] += 1
      key = [rank,formula,density,index,allocation]
      if !winner || (key <=> winner[:key]) == -1
        winner = {key:key,parent:images[index][:parent],allocation:allocation,leaves:leaves,audit:audit,result:result,raw_terms:terms}
      end
    end
    # No policy bypasses this admission boundary. A malformed winning proposal
    # fails closed; its scalar score is never returned as an exact candidate.
    winner[:result] ||= B::Scheme.new(winner[:allocation].map(&:sum),B.text(winner[:raw_terms]))
    raise "screen/admission mismatch" unless winner[:result].rank == winner[:key][0] && winner[:result].audit[:density] == winner[:key][2]
    winner.delete(:raw_terms)
    {winner:winner,materialized:selected.length,complete_competitive:selected.length == candidates.length,histogram:histogram,
      verification:verification,verified_candidates:verification == :all ? selected.length : 1}
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {maximum:15,slack:4,materializations:5000}
    OptionParser.new do |p|
      %i[parent library output targets replay].each { |k| p.on("--#{k} VALUE") { |v| options[k] = v } }
      %i[maximum slack materializations].each { |k| p.on("--#{k} N",Integer) { |v| options[k] = v } }
      p.on("--screen-before-verify", "Screen raw proposals; fully verify the winning tensor before admission") { options[:verification] = :winner }
    end.parse!
    if options[:replay]
      puts JSON.pretty_generate(MetaflipOuterBasisProducts.replay(options[:replay]))
      exit 0
    end
    %i[parent library output targets].each { |k| raise "missing --#{k}" unless options[k] }
    raise "invalid limits" unless options[:maximum].between?(1,16) && options[:slack].between?(0,100) && options[:materializations].between?(1,100000)
    root = File.expand_path(options[:output])
    raise "output must be new" if File.exist?(root)
    FileUtils.mkdir_p(root)
    b = MetaflipBudProducts
    mod = MetaflipOuterBasisProducts
    parent = b.load_scheme(options[:parent])
    images = mod.orbit2(parent)
    paths = Dir[File.join(options[:library],"matmul_*_gf2.txt")].sort
    raise "empty library" if paths.empty?
    library = b::Library.new(paths.map { |p| b.load_scheme(p) },products:true)
    image_rows = images.map { |r| {codes:r[:codes],snapshot:b.save_snapshot(root,"outers",r[:parent])} }
    rows = []
    options[:targets].split(",").each do |label|
      target = MetaflipTensorVerifier.dimensions(label)
      raise "target outside audit" unless target.all? { |d| d.between?(2,16) }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = mod.scan(images,target,library,**options.select { |k,_| %i[maximum slack materializations verification].include?(k) })
      winner = result.fetch(:winner)
      output,path = mod.export(root,winner[:parent],winner[:allocation],winner[:leaves],target)
      rows << result.reject { |k,_| k==:winner }.merge(target:target,exact_rank:output.rank,recipe:path,
        elapsed_seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)
      report = {schema:1,field:"GF(2)",record_claim:false,options:options,images:image_rows,rows:rows,
        source_sha256:Digest::SHA256.file(__FILE__).hexdigest,
        composer_sha256:Digest::SHA256.file(File.join(__dir__,"bud_products.rb")).hexdigest,
        library_sha256:paths.to_h { |p| [p,Digest::SHA256.file(p).hexdigest] }}
      File.write(File.join(root,"report.json"),JSON.pretty_generate(report)+"\n")
      puts JSON.generate(rows.last.reject { |k,_| k==:histogram })
      $stdout.flush
    end
  rescue StandardError => error
    warn "Outer basis search rejected: #{error.message}"
    exit 1
  end
end

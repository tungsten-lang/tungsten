#!/usr/bin/env ruby
# Bounded exact representation search; never a novelty or optimality oracle.
require_relative "outer_leaf_portfolio"

module MetaflipOuterRepresentationWalk
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  P = MetaflipOuterLeafPortfolio
  module_function

  def replay_history(parent, allocation, leaves, result)
    current = leaves.dup
    result[:history].each do |step|
      slot = step.fetch(:slot)
      raise "history input mismatch" unless current[slot].canonical_id == step.fetch(:from)
      case step.fetch(:kind)
      when "shear"
        current[slot] = M.transvection(current[slot],*step.values_at(:axis,:dst,:src))
      when "kernel", "kernel_pair"
        if step.fetch(:kind) == "kernel_pair"
          components = step.fetch(:components)
          raise "invalid pair history" unless components.length == 2 &&
            components.map{|a|a.fetch(:axis)}.uniq.length == 2 &&
            components.all?{|a|a.fetch(:kind) == "kernel"} &&
            components.flat_map{|a|a.fetch(:word)} == step.fetch(:word)
        end
        current[slot] = M.transvection_word(current[slot],step.fetch(:word))
      when "swap"
        axis,dst,src = step.values_at(:axis,:dst,:src)
        maps = current[slot].shape.map{|n|(0...n).to_a}
        maps[axis][dst],maps[axis][src] = src,dst
        current[slot] = P.permute_indices(current[slot],maps)
      else
        raise "unknown history action"
      end
      raise "history output mismatch" unless current[slot].canonical_id == step.fetch(:to)
      state, = M.compose(parent,allocation,leaves:current)
      raise "history score mismatch" unless [state.rank,state.audit[:density]] == step.values_at(:rank,:density)
    end
    raise "final history mismatch" unless current.map{|s|s&.canonical_id} == result[:leaves].map{|s|s&.canonical_id}
  end

  def main(argv)
    options = {moves: :kernel,rounds:4,kernel_maximum:8,verification: :all,kernel_pair_width:0}
    OptionParser.new do |p|
      p.banner = "Usage: outer_representation_walk.rb --output DIR [--moves shear|swap|both|kernel] RECIPE..."
      p.on("--output DIR"){|v|options[:output]=v}
      p.on("--moves MODE"){|v|options[:moves]=v.to_sym}
      p.on("--rounds N",Integer){|v|options[:rounds]=v}
      p.on("--kernel-maximum N",Integer){|v|options[:kernel_maximum]=v}
      p.on("--kernel-pair-width N",Integer,"Shortlist N single words per axis for bounded paired moves"){|v|options[:kernel_pair_width]=v}
      p.on("--screen-before-verify", "Verify each selected kernel move and the complete final tensor"){options[:verification]=:winner}
    end.parse!(argv)
    raise "need new output and input recipes" unless options[:output] && !argv.empty? && !File.exist?(options[:output])
    raise "invalid limits" unless [:shear,:swap,:both,:kernel].include?(options[:moves]) &&
      options[:rounds].between?(1,16) && options[:kernel_maximum].between?(1,10) &&
      options[:kernel_pair_width].between?(0,32) && (options[:kernel_pair_width].zero? || options[:moves] == :kernel) &&
      (options[:verification] == :all || options[:moves] == :kernel)
    sources = argv.map do |path|
      M.replay(path)
      [File.expand_path(path),JSON.parse(File.read(path))]
    end
    raise "duplicate target" unless sources.map{|_,r|r["result"]["shape"].sort}.uniq.length == sources.length
    root = File.expand_path(options[:output])
    FileUtils.mkdir_p(File.join(root,"tools"))
    tool_names = %w[outer_representation_walk.rb outer_leaf_portfolio.rb outer_basis_products.rb bud_products.rb verify_tensor.rb]
    pins = (sources.map(&:first)+tool_names.map{|n|File.join(__dir__,n)}).to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
    tool_names.each{|n|FileUtils.cp(File.join(__dir__,n),File.join(root,"tools",n))}
    rows = []
    sources.each do |source,recipe|
      base = File.dirname(source)
      parent = B.load_scheme(File.join(base,recipe["parent"]["path"]),recipe["parent"]["shape"])
      leaves = recipe["leaves"].map{|e|e && B.load_scheme(File.join(base,e["path"]),e["shape"])}
      target = recipe["result"]["shape"]
      _,initial = M.export(File.join(root,"initial"),parent,recipe["allocation"],leaves,target)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = P.basis_walk(parent,recipe["allocation"],leaves:leaves,**options.slice(:moves,:rounds,:kernel_maximum,:verification,:kernel_pair_width)) do |progress|
        puts JSON.generate(progress.merge(target:target,elapsed:Process.clock_gettime(Process::CLOCK_MONOTONIC)-start))
        $stdout.flush
      end
      replay_history(parent,recipe["allocation"],leaves,result)
      final,path = M.export(root,parent,recipe["allocation"],result[:leaves],target)
      M.replay(path)
      rows << result.reject{|k,_|[:result,:leaves].include?(k)}.merge(target:target,source:source,
        recipe:File.basename(path),initial_recipe:initial.delete_prefix(root+"/"),
        result_sha256:final.audit[:sha256],history_replayed:true,
        elapsed_seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)
      report = {schema:1,field:"GF(2)",record_claim:false,redistribution_cleared:false,
        options:options,complete:rows.length == sources.length,targets:sources.length,source_sha256:pins,rows:rows}
      File.write(File.join(root,"report.json"),JSON.pretty_generate(report)+"\n")
    end
    raise "sources changed during run" unless pins.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MetaflipOuterRepresentationWalk.main(ARGV)
  rescue StandardError => error
    warn "Representation walk rejected: #{error.message}"
    exit 1
  end
end

# A bounded exact subset oracle. It neither changes the fleet nor supplies
# tensor admission: callers still verify complete literal group covers.
require 'open3'
require 'tmpdir'

module MetaflipComponentDP
  module_function

  def solve_batch(binary,jobs)
    raise 'invalid batch size' unless jobs.is_a?(Array) && jobs.size.between?(1,1024)
    lines=[jobs.size.to_s]
    jobs.each do |job|
      n=job.fetch(:vertices);budget=job.fetch(:max_states);edges=job.fetch(:edges)
      raise 'invalid vertex/state bound' unless n.is_a?(Integer) && n.between?(1,16) &&
        budget.is_a?(Integer) && budget.between?(1,1_000_000_000) && 1<<(n-1)<=budget
      raise 'invalid edges' unless edges.is_a?(Hash) && edges.size<(1<<n) && edges.all? do |mask,gain|
        mask.is_a?(Integer) && mask.between?(1,(1<<n)-1) && gain.is_a?(Integer) && gain.between?(1,1_000_000_000)
      end
      lines<<[n,edges.size,budget].join(' ')
      edges.sort.each{|mask,gain|lines<<[mask,gain].join(' ')}
    end
    text=Dir.mktmpdir('metaflip-component-') do |root|
      path=root+'/batch.txt';File.write(path,lines.join("\n")+"\n")
      output,status=Open3.capture2e(binary,path)
      raise "component oracle failed: #{output}" unless status.success?
      output.lines.map(&:strip)
    end
    results=jobs.each_with_index.map do |job,index|
      header=text.shift
      raise 'missing oracle result' unless header&.start_with?('PACK_JOB ')
      fields=header.split.drop(1).to_h{|part|part.split('=',2)}
      raise 'invalid oracle header' unless fields.keys.sort==%w[gain index selected states transitions] && fields.values.all?{|v|v.match?(/\A\d+\z/)}
      fields.transform_values!{|v|Integer(v,10)}
      raise 'oracle order/state mismatch' unless fields['index']==index && fields['states']==1<<(job[:vertices]-1) && fields['states']<=job[:max_states]
      raise 'invalid selected count' unless fields['selected'].between?(0,job[:vertices])
      used=0;gain=0
      selected=fields['selected'].times.map do
        parts=text.shift&.split
        raise 'invalid selected edge' unless parts&.size==2 && parts.all?{|v|v.match?(/\A\d+\z/)}
        mask,value=parts.map{|v|Integer(v,10)}
        raise 'unrecognized or overlapping edge' unless job[:edges][mask]==value && (used&mask).zero?
        used|=mask;gain+=value;mask
      end
      raise 'oracle witness/gain mismatch' unless gain==fields['gain']
      {gain:gain,states:fields['states'],transitions:fields['transitions'],masks:selected}
    end
    raise 'trailing oracle output' unless text.empty?
    results
  end

  # Returns nil to keep the caller's existing bounded fallback when a dense
  # component is outside this backend's explicit state allowance.
  def solve_component(binary,component,vertices,max_states:)
    n=vertices.size
    return nil unless n.between?(1,16) && 1<<(n-1)<=max_states && component.size>=256
    positions=vertices.each_with_index.to_h
    edges={};original={}
    component.each do |edge|
      mask=edge.fetch(:group).fetch(:indices).reduce(0){|m,i|m|(1<<positions.fetch(i))}
      raise 'duplicate compressed edge' if edges.key?(mask)
      edges[mask]=edge.fetch(:gain);original[mask]=edge
    end
    result=solve_batch(binary,[{vertices:n,max_states:max_states,edges:edges}]).first
    {gain:result[:gain],states:result[:states],transitions:result[:transitions],
     groups:result[:masks].map{|m|original.fetch(m).fetch(:group)}}
  end
end

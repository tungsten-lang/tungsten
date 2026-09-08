#!/usr/bin/env ruby
# Exact offline compression of audited compositions, projections or walks.
# Never admits a rank-only claim.
require 'json'
require 'digest'
require 'fileutils'
require_relative 'cancellation_patterns'

module MetaflipCheckedProductCompression
  B=MetaflipBudProducts
  module_function

  def source_entries(report)
    if report.key?('outputs')
      # A present-but-empty wrapped result is never a flat-output fallback.
      report.fetch('outputs').map do |row|
        raise 'invalid source output' unless row.is_a?(Hash)
        entry=row.key?('result') ? row.fetch('result') : row
        raise 'missing source snapshot' unless entry.is_a?(Hash)
        entry
      end
    else
      # Retain rank winners, context winners AND endpoints, not just leaders.
      report.fetch('rows').flat_map do |row|
        raise 'invalid observer walk' unless row.is_a?(Hash) && row['contexts'].is_a?(Array)
        entries=[row.fetch('source')]+row.fetch('trials').flat_map do |trial|
          [trial.fetch('winner'),trial.fetch('endpoint')]+trial.fetch('observers').map{|o|o.fetch('winner')}
        end
        raise 'invalid walk snapshot' unless entries.all?{|e|e.is_a?(Hash) && e['shape']==row['shape']}
        entries
      end
    end
  end

  def run(source,root)
    source=File.expand_path(source);root=File.expand_path(root)
    raise 'output exists' if File.exist?(root)
    raw=File.binread(File.join(source,'report.json'));report=JSON.parse(raw)
    audit_raw=File.binread(File.join(source,'independent-audit.json'));audit=JSON.parse(audit_raw)
    raise 'unfinished or unverified source' unless report['complete'] && audit['complete'] &&
      report['field']=='GF(2)' && audit['field']=='GF(2)' && !report['record_claim'] &&
      !audit['record_claim'] && audit['report_sha256']==Digest::SHA256.hexdigest(raw)
    references=source_entries(report)
    # Validate every occurrence before deduplication, including aliases and
    # nonwinning endpoints. A duplicate cannot hide a stale path or rank.
    checked={}
    references.each do |e|
      path=File.expand_path(e.fetch('path'),source)
      raise 'source path escapes root' unless path.start_with?(source+File::SEPARATOR)
      raise 'unbound source' unless audit.fetch('source_sha256').fetch(e['path'])==e['sha256']
      checked[path]||=[Digest::SHA256.file(path).hexdigest,File.open(path){|f|Integer(f.readline,10)}]
      hash,rank=checked.fetch(path)
      raise 'source changed' unless hash==e['sha256']
      raise 'source rank mismatch' if e.key?('rank') && (!e['rank'].is_a?(Integer) || e['rank']!=rank)
    end
    entries=references.uniq{|e|[e['shape'],e['sha256']]}
    raise 'duplicate outputs' if report.key?('outputs') && entries.size!=references.size
    raise 'empty source' if entries.empty?
    FileUtils.mkdir_p(root)
    File.binwrite(File.join(root,'source-report.json'),raw)
    File.binwrite(File.join(root,'source-audit.json'),audit_raw)
    pins={}
    %w[compress_checked_products cancellation_patterns bud_products verify_tensor].each do |name|
      path=File.join(__dir__,name+'.rb');pins[path]=Digest::SHA256.file(path).hexdigest
    end
    out={complete:false,field:'GF(2)',record_claim:false,canonical_archive_changed:false,
      redistribution_cleared:false,source_root:source,source_report_sha256:Digest::SHA256.hexdigest(raw),
      source_audit_sha256:Digest::SHA256.hexdigest(audit_raw),tool_sha256:pins,rows:[]}
    entries.each_with_index do |e,i|
      path=File.expand_path(e.fetch('path'),source)
      raise 'source path escapes root' unless path.start_with?(source+File::SEPARATOR)
      body=File.binread(path)
      raise 'source changed' unless Digest::SHA256.hexdigest(body)==e['sha256'] &&
        audit.fetch('source_sha256').fetch(e['path'])==e['sha256']
      input=B::Scheme.new(e['shape'],body)
      if e.key?('rank')
        raise 'source rank mismatch' unless e['rank'].is_a?(Integer) && e['rank']==input.rank
      end
      max_bits=B::EDGES.map{|a,b|input.shape[a]*input.shape[b]}.max
      terms,history=MetaflipSharedFactorCompression.compress_terms(input.terms,max_bits:max_bits)
      raise 'rank increased' if terms.size>input.rank
      row={source:e,input:B.save_snapshot(root,'inputs',input),max_bits:max_bits,
        rank_before:input.rank,rank_after:terms.size,compression:history,result:nil}
      raise 'source is not a canonical snapshot' unless row[:input][:sha256]==e['sha256']
      if terms.size<input.rank
        result=B::Scheme.new(input.shape,B.text(terms))
        row[:result]=B.save_snapshot(root,'results',result)
      else
        raise 'rank-neutral tensor changed' unless terms.sort==input.terms.sort && history.empty?
      end
      out[:rows]<<row
      puts JSON.generate(checked:i+1,total:entries.size,shape:input.shape,before:input.rank,
        after:terms.size,events:history.size);$stdout.flush
    end
    raise 'tool changed during run' unless pins.all?{|path,hash|Digest::SHA256.file(path).hexdigest==hash}
    out[:complete]=true;out[:inputs]=entries.size;out[:changed]=out[:rows].count{|r|r[:result]}
    out[:rank_saved]=out[:rows].sum{|r|r[:rank_before]-r[:rank_after]}
    File.write(File.join(root,'report.json'),JSON.pretty_generate(out)+"\n")
    puts JSON.generate(out.slice(:complete,:inputs,:changed,:rank_saved))
    out
  end
end

if $PROGRAM_NAME==__FILE__
  raise 'usage: compress_checked_products.rb SOURCE_ROOT OUTPUT_ROOT' unless ARGV.size==2
  MetaflipCheckedProductCompression.run(*ARGV)
end

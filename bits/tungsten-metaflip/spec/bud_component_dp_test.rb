require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../tools/bud_component_dp'

class BudComponentDPTest < Minitest::Test
  def setup
    @binary=ENV['METAFLIP_COMPONENT_DP_BINARY']
    skip 'set METAFLIP_COMPONENT_DP_BINARY to the freshly built native oracle' unless @binary
    assert File.executable?(@binary)
  end

  # Independent forward relaxation: append each edge to each already-filled
  # occupied mask. It does not use the native highest-vertex recurrence.
  def reference(n,edges)
    dp=Array.new(1<<n,-1);dp[0]=0
    dp.each_index do |used|
      next if dp[used]<0
      edges.each do |mask,gain|
        next unless (used&mask).zero?
        target=used|mask;dp[target]=[dp[target],dp[used]+gain].max
      end
    end
    dp.max
  end

  def test_random_components_match_independent_relaxation_and_repeat
    rng=Random.new(937907)
    jobs=160.times.map do |i|
      n=1+i%9
      edges=(1...(1<<n)).select{rng.rand(5)==0}.to_h{|mask|[mask,rng.rand(1..200)]}
      {vertices:n,max_states:1<<(n-1),edges:edges}
    end
    actual=MetaflipComponentDP.solve_batch(@binary,jobs)
    assert_equal actual,MetaflipComponentDP.solve_batch(@binary,jobs)
    jobs.zip(actual).each do |job,result|
      assert_equal reference(job[:vertices],job[:edges]),result[:gain]
      assert_equal 1<<(job[:vertices]-1),result[:states]
    end
  end

  def test_dense_sixteen_vertex_component_and_large_gains
    edges=(1...65536).to_h{|m|[m,[m.to_s(2).count('1'),2].min*500_000_000]}
    job={vertices:16,max_states:32768,edges:edges}
    result=MetaflipComponentDP.solve_batch(@binary,[job]).first
    assert_equal 8_000_000_000,result[:gain]
    assert_equal 32768,result[:states]
    assert_operator result[:transitions],:<,8_000_000
    assert_raises(RuntimeError){MetaflipComponentDP.solve_batch(@binary,[job.merge(max_states:32767)])}
  end

  def test_native_rejects_bad_masks_duplicates_budgets_and_trailing_input
    bodies=["","\n","0\n","1\n17 0 100000\n","1\n3 0 3\n","1\n3 1 4\n8 1\n",
      "1\n3 1 4\n0 1\n","1\n3 1 4\n1 -1\n","1\n3 2 4\n1 2\n1 3\n",
      "1\n3 1 4\n1 1000000001\n","1\n3 0 4\ntrailing\n","1\n3 1 4\n"]
    Dir.mktmpdir('component-invalid-') do |root|
      bodies.each_with_index do |body,i|
        path=root+"/#{i}.txt";File.write(path,body)
        _out,status=Open3.capture2e(@binary,path)
        refute status.success?,body
      end
    end
  end

  def test_sparse_or_over_budget_component_keeps_existing_path
    assert_nil MetaflipComponentDP.solve_component(@binary,[],[1,2],max_states:50_000)
    assert_nil MetaflipComponentDP.solve_component(@binary,[],(0...17).to_a,max_states:50_000)
  end
end

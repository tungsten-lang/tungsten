#!/usr/bin/env ruby
require "minitest/autorun"
require_relative "../tools/verify_tensor"

class VerifyTensorTest < Minitest::Test
  def naive(n, m, p)
    rows = n.times.flat_map do |i|
      m.times.flat_map do |j|
        p.times.map { |k| "#{1 << (i * m + j)} #{1 << (j * p + k)} #{1 << (i * p + k)}" }
      end
    end
    ([rows.length.to_s] + rows).join("\n") + "\n"
  end

  def test_asymmetric_shapes_and_wide_words
    [[1, 1, 1], [2, 3, 4], [3, 4, 2], [4, 2, 3], [8, 8, 1], [1, 8, 8]].each do |n, m, p|
      text = naive(n, m, p)
      result = MetaflipTensorVerifier.verify_text(text, n, m, p)
      assert result[:exact]
      assert_equal n * m * p, result[:rank]
      assert_equal 3 * n * m * p, result[:density]
      assert_equal Digest::SHA256.hexdigest(text), result[:sha256]
    end
  end

  def test_curated_rows_and_comments
    text = "# exact naive tensor\n\n" + naive(2, 3, 4).lines.drop(1).map { |line| "R #{line}" }.join
    assert_equal 24, MetaflipTensorVerifier.verify_text(text, 2, 3, 4)[:rank]
  end

  def test_xor_cancellation_is_not_set_union
    lines = naive(2, 3, 4).lines
    lines[0] = "26\n"
    lines << "3 5 7\n" << "3 5 7\n"
    assert_equal 26, MetaflipTensorVerifier.verify_text(lines.join, 2, 3, 4)[:rank]
    lines[0] = "25\n"
    lines.pop
    assert_raises(RuntimeError) { MetaflipTensorVerifier.verify_text(lines.join, 2, 3, 4) }
  end

  def test_corruptions_and_shape_mismatch
    source = naive(2, 3, 4)
    invalid = [source.sub("24\n", "23\n"), source.sub("1 1 1", "1 1 2"),
               source.sub("1 1 1", "0 1 1"), source.sub("1 1 1", "64 1 1"),
               source.sub("1 1 1", "1 4096 1"), source.sub("1 1 1", "1 1 256"),
               source.sub("1 1 1", "-1 1 1"), source.sub("1 1 1", "1 1 1 1"),
               source.sub("1 1 1", "1 1 1junk"), "", "0\n"]
    invalid.each { |text| assert_raises(RuntimeError) { MetaflipTensorVerifier.verify_text(text, 2, 3, 4) } }
    assert_raises(RuntimeError) { MetaflipTensorVerifier.verify_text(source, 3, 2, 4) }
  end

  def test_shape_inference_is_explicit
    assert_equal [2, 3, 4], MetaflipTensorVerifier.dimensions("2x3x4")
    assert_equal "2x3x4", MetaflipTensorVerifier.infer_shape("/tmp/checkpoints/gf2/2x3x4/best.txt")
    assert_raises(RuntimeError) { MetaflipTensorVerifier.dimensions("2x0x4") }
    assert_raises(RuntimeError) { MetaflipTensorVerifier.infer_shape("/tmp/unlabeled.txt") }
  end
end

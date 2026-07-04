# Encoder — categorical encoding transformers
# Convert categorical features into numeric representations for ML.
#
#     enc = Encoder.new(:one_hot, columns: [:color, :size])
#     enc = Encoder.new(:label, columns: [:grade])
#     enc = Encoder.new(:ordinal, columns: [:size], order: { small: 0, medium: 1, large: 2 })
#     enc = Encoder.new(:target, columns: [:category])

in Tungsten:Koala

+ Encoder < Transformer
  ro :kind      # :one_hot, :label, :ordinal, :target, :binary, :frequency
  ro :columns

  -> new(@kind, columns: nil, **options)
    super()
    @columns  = columns&.map(&:to_sym)
    @options  = options
    @mappings = {}

  -> fit(df, target: nil)
    cols = @columns || self.detect_categorical(df)
    cols.each -> (col)
      values = df[col].to_a.uniq.reject(&:nil?).sort

      case @kind
      => :one_hot ->
        @mappings[col] = values
      => :label ->
        @mappings[col] = values.each_with_index.map(-> (v, i) [v, i]).to_h
      => :ordinal ->
        order = @options[:order]
        @mappings[col] = order || values.each_with_index.map(-> (v, i) [v, i]).to_h
      => :target ->
        <! TransformerError, "Target encoding requires a target Series" unless target
        target_vals = target.to_a
        source_vals = df[col].to_a
        group_means = {}
        values.each -> (v)
          indices = source_vals.each_with_index.select(-> (sv, _) sv == v).map(&:last)
          group_means[v] = indices.map(-> (i) target_vals[i]).sum.to_f / indices.size
        @mappings[col] = group_means
      => :binary ->
        @mappings[col] = values.each_with_index.map(-> (v, i) [v, i]).to_h
      => :frequency ->
        counts = df[col].to_a.tally
        total = df[col].count.to_f
        @mappings[col] = counts.map(-> (v, c) [v, c / total]).to_h

    @fitted = true
    self

  -> transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    result = df

    @mappings.each -> (col, mapping)
      case @kind
      => :one_hot ->
        mapping.each -> (val)
          col_name = "[col]_[val]".to_sym
          result = result.assign(**{ col_name => df[col].map(-> (v) v == val ? 1 : 0).to_a })
        result = result.drop(col)
      => :label, :ordinal, :target, :frequency ->
        result = result.transform(col, -> (v) mapping[v])
      => :binary ->
        # Encode as binary digits
        n_bits = Math.log2(mapping.size).ceil.to_i
        n_bits = [n_bits, 1].max
        mapping.each -> (val, idx)
          n_bits.times -> (bit)
            col_name = "[col]_bit[bit]".to_sym
            result = result.assign(**{ col_name => df[col].map(-> (v)
              mapping[v] ? (mapping[v] >> bit) & 1 : 0
            ).to_a }) unless result.columns.include?(col_name)
        result = result.drop(col)

    result

  # Reverse label/ordinal encoding.
  -> inverse_transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    result = df
    @mappings.each -> (col, mapping)
      case @kind
      => :label, :ordinal ->
        reverse = mapping.map(-> (k, v) [v, k]).to_h
        result = result.transform(col, -> (v) reverse[v])
    result

  -> params { kind: @kind, mappings: @mappings }

  [private]

  -> detect_categorical(df)
    df.columns.select -> (col)
      sample = df[col].to_a.reject(&:nil?).first
      sample.is_a?(String) || sample.is_a?(Symbol)

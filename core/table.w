# A 2-dimensional tabular data structure with labeled axes (rows and columns).
#
# A Hash-like container for Series objects.
#
# @learn Index
# @learn Series
#
# @see Record
#
# @see pandas.DataFrame
+ Table
  is Comparable
  is Iterable

  -> new(data, index: nil, columns: nil)

  -> +/1
  -> -/1
  -> */1
  -> //1
  -> %/1

  -> <</1

  -> []/1
  -> []/1
  -> []/*

  -> at/1
  -> at/1
  -> between/2
  -> truncate/2

  -> add/1
  -> divide/1
  -> dot/1
  -> mod/1
  -> multiply/1
  -> subtract/1

  -> align/1
  -> interpolate
  -> reindex
  -> resample/1
  -> shift
  -> squeeze
  -> sort
  -> transpose

  -> all
  -> any

  -> copy
  -> head/1
  -> sample/1
  -> tail/1
  -> uniq

  # cross-section
  -> xs

  -> count
  -> irr
  -> min
  -> max
  -> mean
  -> median
  -> mode
  -> npv
  -> product
  -> quantile
  -> rank
  -> skew
  -> sum
  -> xirr
  -> xnpv

  -> correlation
  -> covariance
  -> cumulative(agg)
  -> kurtosis
  -> variance

  -> load/1
  -> load/1
  -> load/1

  -> to_clipboard
  -> to_csv
  -> to_dense
  -> to_excel

  # Gooble BigQuery table
  -> to_gbq
  -> to_json
  -> to_html
  -> to_records
  -> to_sparse
  -> to_sql
  -> to_s
  -> to_xml

  -> append/1
  -> apply
  -> axes
  -> blank?
  -> covers?/1
  -> describe
  -> diff
  -> dimensions
  -> histogram
  -> index
  -> info
  -> join
  -> keys
  -> mask
  -> pivot
  -> plot
  -> query
  -> replace
  -> size
  -> values

# Optional standard-format bridge. Explicit import; never autoloads Python.
use ../io
use ../json
use ../file
use ../process

+ SciIO
  # Configure an interpreter with h5py (and pyarrow for columnar methods).
  # Process.spawn uses argv directly. Private temporary files are always removed.
  -> .interop_request(request)
    python = env("TUNGSTEN_SCIENCE_PYTHON")
    if python == nil || python == ""
      raise "set TUNGSTEN_SCIENCE_PYTHON to an interpreter with the optional I/O dependencies"
    request[:version] = 1
    input = Tempfile.new("tungsten-science-request")
    begin
      output = Tempfile.new("tungsten-science-response")
      begin
        input.write(JSON.encode(request))
        worker = file_expand_path(__DIR__ + "/../../runtime/science_interop.py")
        child = Process.spawn([python, worker, input.path(), output.path()])
        status = child.wait()
        if status != 0
          raise "scientific I/O worker failed with exit status [status]"
        response = JSON.parse(output.read())
        if response["version"] != 1 || response["ok"] != true
          raise "scientific I/O: [response["error"]]"
        response["result"]
      ensure
        output.close!()
    ensure
      input.close!()

  # Result is a shape/dtype/order/values/attributes record. Values are C-order.
  -> .read_hdf5_dataset(path, dataset)
    SciIO.interop_request({operation: "hdf5_read", path: path, dataset: dataset})

  # Standard HDF5, exclusive create. Existing destinations are never replaced.
  -> .write_hdf5_standard(path, datasets)
    SciIO.interop_request({operation: "hdf5_write", path: path, datasets: datasets})

  -> .read_parquet_standard(path)
    SciIO.interop_request({operation: "parquet_read", path: path})

  -> .write_parquet_standard(path, table)
    SciIO.interop_request({operation: "parquet_write", path: path, table: table})

  -> .read_arrow_ipc(path)
    SciIO.interop_request({operation: "arrow_read", path: path})

  -> .write_arrow_ipc(path, table)
    SciIO.interop_request({operation: "arrow_write", path: path, table: table})

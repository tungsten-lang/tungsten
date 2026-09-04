#!/usr/bin/env python3
"""Optional standards-backed scientific I/O worker. Protocol version 1."""
import json
import math
import os
import re
from pathlib import Path
import sys
import tempfile

MAX_ELEMENTS = 1_000_000
MAX_JSON = 64 * 1024 * 1024
DTYPES = {'float32', 'float64', 'int32', 'int64', 'uint32', 'uint64', 'bool'}


def json_value(value):
    import numpy as np
    if isinstance(value, np.ndarray):
        return json_value(value.tolist())
    if isinstance(value, np.generic):
        return json_value(value.item())
    if isinstance(value, bytes):
        return value.decode('utf-8')
    if isinstance(value, (list, tuple)):
        return [json_value(x) for x in value]
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float) and math.isfinite(value):
        return value
    raise ValueError('protocol v1 requires finite JSON values; unsupported attribute/value type')


def array_from_record(record):
    import numpy as np
    dtype = record['dtype']
    if dtype not in DTYPES:
        raise ValueError('unsupported dtype: ' + str(dtype))
    shape = record['shape']
    if not isinstance(shape, list) or any(type(n) is not int or n < 0 for n in shape):
        raise ValueError('shape must contain nonnegative integer dimensions')
    count = math.prod(shape)
    values = record['values']
    if count > MAX_ELEMENTS or len(values) != count:
        raise ValueError('shape/value count mismatch or one-million-element limit exceeded')
    if dtype.startswith(('int', 'uint')):
        # Core JSON represents large Int values as decimal strings on encode.
        # Accept only canonical decimal integers, then range-check without floats.
        values = [int(v) if isinstance(v, str) and re.fullmatch(r'-?(0|[1-9][0-9]*)', v) else v for v in values]
        limits = np.iinfo(dtype)
        if any(type(v) is not int or not limits.min <= v <= limits.max for v in values):
            raise ValueError('integer values must fit the declared dtype exactly')
    elif dtype == 'bool':
        if any(type(v) is not bool for v in values):
            raise ValueError('bool values must be booleans')
    else:
        if any(type(v) not in (float, int) or not math.isfinite(v) for v in values):
            raise ValueError('floating values must be finite numbers')
    with np.errstate(over='ignore'):
        array = np.asarray(values, dtype=dtype).reshape(shape)
    if array.dtype.kind == 'f' and not np.isfinite(array).all():
        raise ValueError('floating conversion overflow')
    return array


def write_new(path, writer):
    """Publish a complete file without replacing an existing destination."""
    path = Path(path).absolute()
    fd, temporary = tempfile.mkstemp(prefix='.tungsten-interop-', dir=path.parent)
    os.close(fd)
    try:
        writer(temporary)
        os.link(temporary, path)  # atomic no-replace publication on same filesystem
    finally:
        os.unlink(temporary)


def hdf5(request):
    import h5py
    import numpy as np
    if request['operation'] == 'hdf5_read':
        with h5py.File(request['path'], 'r') as file:
            dataset = file[request['dataset']]
            if not isinstance(dataset, h5py.Dataset) or dataset.shape is None:
                raise ValueError('expected a non-null dataset')
            if dataset.dtype.name not in DTYPES or dataset.size > MAX_ELEMENTS:
                raise ValueError('unsupported dtype or one-million-element limit exceeded')
            values = json_value(dataset[()].reshape(-1).tolist())
            return {'dtype': dataset.dtype.name, 'shape': list(dataset.shape), 'order': 'C',
                    'values': values, 'attributes': {k: json_value(v) for k, v in dataset.attrs.items()},
                    'chunks': list(dataset.chunks) if dataset.chunks else None,
                    'compression': dataset.compression}
    records = request['datasets']
    if not isinstance(records, dict) or not records:
        raise ValueError('datasets must be a non-empty name-to-record object')
    prepared = []
    for name, record in records.items():
        if not isinstance(name, str) or not name.strip('/') or any(x in ('', '.', '..') for x in name.strip('/').split('/')):
            raise ValueError('invalid dataset path')
        array = array_from_record(record)
        attributes = record.get('attributes', {})
        if not isinstance(attributes, dict):
            raise ValueError('attributes must be an object')
        compression = record.get('compression')
        if compression not in (None, 'gzip') or (compression and array.ndim == 0):
            raise ValueError('only gzip on non-scalar datasets is supported for writing')
        prepared.append((name, array, attributes, compression))
    def write(path):
        with h5py.File(path, 'w') as file:
            for name, array, attributes, compression in prepared:
                dataset = file.create_dataset(name, data=array, compression=compression)
                for key, value in attributes.items():
                    dataset.attrs[key] = json_value(value)
    write_new(request['path'], write)
    return {'path': request['path'], 'datasets': list(records), 'format': 'hdf5'}


def dispatch(request):
    if request.get('version') != 1:
        raise ValueError('unsupported protocol version')
    if request.get('operation') in ('hdf5_read', 'hdf5_write'):
        return hdf5(request)
    raise ValueError('unsupported operation')


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: science_interop.py REQUEST_JSON RESPONSE_JSON')
    try:
        request_path = Path(sys.argv[1])
        if request_path.stat().st_size > MAX_JSON:
            raise ValueError('request exceeds 64 MiB')
        request = json.loads(request_path.read_text())
        response = {'version': 1, 'ok': True, 'result': dispatch(request)}
    except Exception as error:
        response = {'version': 1, 'ok': False, 'error': str(error), 'error_type': type(error).__name__}
    encoded = json.dumps(response, allow_nan=False)
    if len(encoded.encode()) > MAX_JSON:
        encoded = json.dumps({'version': 1, 'ok': False, 'error': 'response exceeds 64 MiB'})
    Path(sys.argv[2]).write_text(encoded)


if __name__ == '__main__':
    main()

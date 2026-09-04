"""Bounded, read-only WValue summaries. Never evaluate target expressions."""
import json
from pathlib import Path
import shlex
import struct

MASK = (1 << 64) - 1


def decode(bits, read=None, byteorder='little'):
    bits &= MASK
    if bits < 16:
        return {0: 'nil', 1: 'false', 2: 'true', 3: 'undef', 4: '<memo miss>'}.get(bits, '<reserved>')
    tag, payload = bits >> 48, bits & ((1 << 48) - 1)
    if tag == 0xfffa:
        return str(payload - (1 << 48) if payload >> 47 else payload)
    if 0 < bits <= 0xfff1000000000000:
        return repr(struct.unpack('>d', ((bits - (1 << 48)) & MASK).to_bytes(8, 'big'))[0])
    if tag == 0xfff9:
        mode = (bits >> 1) & 7
        prefix = ':' if bits & 1 else ''
        if mode <= 5:
            data = ((payload >> 4) & ((1 << 40) - 1)).to_bytes(5, 'little')[:mode]
            return prefix + json.dumps(data.decode('utf-8', errors='replace'), ensure_ascii=False)
        if mode == 6:
            return prefix + '<slab string index=%d>' % ((payload >> 4) & 0xffffff)
        address = payload & ~15
        if read:
            length = int.from_bytes(read(address, 4), byteorder) & 0x7fffffff
            data = read(address + 4, min(length, 160))
            return prefix + json.dumps(data.decode('utf-8', errors='replace'), ensure_ascii=False) + ('…' if length > 160 else '')
        return prefix + '<heap string @0x%x>' % address
    if tag == 0xfff4:
        address = bits & 0x00007ffffffffff0
        if read:
            header = read(address, 16)
            flags, ebits = header[0], struct.unpack('b', header[1:2])[0]
            if flags & 16:
                return '<BigArray @0x%x>' % address
            size = int.from_bytes(header[8:12], byteorder, signed=True)
            return '<Array size=%d ebits=%d%s @0x%x>' % (size, ebits, ' frozen' if flags & 32 else '', address)
        return '<Array @0x%x>' % address
    if tag == 0:
        name = {0:'object', 1:'atomic', 4:'instance', 5:'hash', 6:'closure', 7:'regex',
                8:'range', 9:'small array', 10:'socket', 11:'StringBuffer', 12:'class',
                13:'uuid', 15:'domain'}.get(bits & 15, 'reserved object')
        return '<%s @0x%x>' % (name, bits & ~15)
    name = {0xfff2:'simd2d', 0xfff3:'simd3d', 0xfff6:'sockaddr', 0xfff8:'instant',
            0xfffb:'BigInt', 0xfffc:'char/token', 0xfffd:'numeric',
            0xfffe:'packed', 0xffff:'duration'}.get(tag, 'reserved')
    return '<%s bits=0x%016x>' % (name, bits)


def reader(process):
    import lldb
    def read(address, size):
        error = lldb.SBError()
        data = process.ReadMemory(address, size, error)
        if error.Fail() or len(data) != size:
            raise ValueError('unreadable target memory at 0x%x' % address)
        return data
    return read


def show(value):
    import lldb
    order = 'little' if value.GetTarget().GetByteOrder() == lldb.eByteOrderLittle else 'big'
    if not value.IsValid() or value.GetError().Fail():
        return '<unavailable>'
    try:
        return decode(value.GetValueAsUnsigned(), reader(value.GetProcess()), order)
    except (ValueError, IndexError) as error:
        return '<%s>' % error


def summary(value, internal_dict):
    return show(value)


def wvalue(debugger, command, result, internal_dict):
    """wvalue HEX | $REGISTER | LOCAL: decode without evaluating target code."""
    args = shlex.split(command)
    if len(args) != 1:
        result.SetError('usage: wvalue 0xBITS | $REGISTER | LOCAL (no expressions)')
        return
    token = args[0]
    target = debugger.GetSelectedTarget()
    frame = target.GetProcess().GetSelectedThread().GetSelectedFrame()
    if token.startswith('0x'):
        try:
            bits = int(token, 16)
            if not 0 <= bits <= MASK:
                raise ValueError('expected 64-bit value')
            import lldb
            order = 'little' if target.GetByteOrder() == lldb.eByteOrderLittle else 'big'
            result.AppendMessage(decode(bits, reader(target.GetProcess()), order))
        except (ValueError, IndexError) as error:
            result.SetError(str(error))
    elif token.startswith('$'):
        result.AppendMessage(show(frame.FindRegister(token[1:])))
    elif token.isidentifier():
        result.AppendMessage(show(frame.FindVariable(token)))
    else:
        result.SetError('only a literal, register, or simple local name is accepted')


def wsource(debugger, command, result, internal_dict):
    """Show all source origins for the selected frame's content-hashed symbol."""
    if command.strip():
        result.SetError('usage: wsource (select the frame first)')
        return
    target = debugger.GetSelectedTarget()
    frame = target.GetProcess().GetSelectedThread().GetSelectedFrame()
    executable = target.GetExecutable()
    path = Path(executable.GetDirectory()) / executable.GetFilename()
    try:
        data = json.loads(Path(str(path) + '.sidemap').read_text())
        if data.get('version') != 1:
            raise ValueError('unsupported sidemap version')
        symbol = frame.GetFunctionName() or frame.GetSymbol().GetName() or ''
        found = False
        for row in data['hashes'].values():
            if row['symbol'].lstrip('_') == symbol.lstrip('_'):
                for origin in row['originals']:
                    result.AppendMessage('%s:%s  %s' % (origin.get('file'), origin.get('line'), origin['symbol']))
                    found = True
        if not found:
            result.AppendMessage('No sidemap origin for ' + symbol)
    except (OSError, ValueError, KeyError, TypeError) as error:
        result.SetError('cannot read adjacent sidemap: ' + str(error))


def wbreak(debugger, command, result, internal_dict):
    """wbreak Class#method | file.w:LINE: set declaration breakpoints via sidemap."""
    token = command.strip()
    target = debugger.GetSelectedTarget()
    executable = target.GetExecutable()
    path = Path(executable.GetDirectory()) / executable.GetFilename()
    try:
        data = json.loads(Path(str(path) + '.sidemap').read_text())
        if data.get('version') != 1:
            raise ValueError('unsupported sidemap version')
        matched = []
        for row in data['hashes'].values():
            for origin in row['originals']:
                location = '%s:%s' % (origin.get('file'), origin.get('line'))
                name = '%s#%s' % (origin.get('class'), origin.get('method'))
                if token == location or token == name:
                    matched.append(row['symbol'])
                    break
        if not matched:
            raise ValueError('no matching declaration; use an exact sidemap path:line or Class#method')
        for symbol in sorted(set(matched)):
            bp = target.BreakpointCreateByName(symbol)
            result.AppendMessage('breakpoint %d: %s (%d locations)' % (bp.GetID(), symbol, bp.GetNumLocations()))
    except (OSError, ValueError, KeyError, TypeError) as error:
        result.SetError(str(error))


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('type summary add -w Tungsten -F tungsten_lldb.summary WValue')
    debugger.HandleCommand('type category enable Tungsten')
    debugger.HandleCommand('command script add -f tungsten_lldb.wvalue wvalue')
    debugger.HandleCommand('command script add -f tungsten_lldb.wsource wsource')
    debugger.HandleCommand('command script add -f tungsten_lldb.wbreak wbreak')

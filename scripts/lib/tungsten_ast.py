"""Read the compiler's byte-length-prefixed canonical AST (no source parsing)."""
import subprocess


def parse(data):
    position = 0
    def sized():
        nonlocal position
        end = data.index(b':', position)
        size = int(data[position:end]); position = end + 1
        value = data[position:position + size]
        if len(value) != size:
            raise ValueError('truncated canonical atom')
        position += size
        return value.decode('utf-8')
    def value():
        nonlocal position
        tag = chr(data[position]); position += 1
        if tag in ('s', 'k', 'y'):
            return sized()
        if tag == 'o':
            return {'atom_type': sized(), 'value': sized()}
        if tag in ('n', 'i', 'b'):
            end = data.index(b';', position); text = data[position:end]; position = end + 1
            if tag == 'n': return None
            if tag == 'b': return text == b'1'
            return int(text)
        if tag == 'a':
            if data[position:position+1] != b'[': raise ValueError('expected array')
            position += 1; result = []
            while data[position:position+1] != b']': result.append(value())
            position += 1; return result
        if tag == 'h':
            if data[position:position+1] != b'{': raise ValueError('expected object')
            position += 1; result = {}
            while data[position:position+1] != b'}':
                key = value(); result[key] = value()
            position += 1; return result
        raise ValueError('unknown canonical tag: ' + tag)
    result = value()
    if data[position:].strip(): raise ValueError('trailing canonical AST bytes')
    return result


def read(compiler, source):
    result = subprocess.run([str(compiler), '--canonical-ast', str(source)], capture_output=True, timeout=60)
    if result.returncode:
        raise ValueError((result.stdout + result.stderr).decode(errors='replace'))
    return parse(result.stdout)


def walk(node):
    if isinstance(node, dict):
        yield node
        for child in node.values(): yield from walk(child)
    elif isinstance(node, list):
        for child in node: yield from walk(child)

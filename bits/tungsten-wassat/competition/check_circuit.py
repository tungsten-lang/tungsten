#!/usr/bin/env python3
"""Check an exhaustive circuit refutation directly against its DIMACS input."""

import argparse
from pathlib import Path

from check_output import parse_cnf


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_certificate(path, variables, clauses):
    units = {c[0] for c in clauses if len(c) == 1}
    with path.open() as stream:
        require(stream.readline().strip() == "wassat-circuit 1", "unknown certificate")
        tag, *fields = stream.readline().split()
        inputs = list(map(int, fields))
        require(tag == "inputs" and len(set(inputs)) == len(inputs) <= 32, "invalid inputs")
        require(all(1 <= v <= variables for v in inputs), "invalid input variable")
        known = set(inputs)
        fixed = {}
        line = stream.readline().split()
        while line and line[0] == "fixed":
            require(len(line) == 2, "invalid constant")
            lit = int(line[1])
            require(lit in units and abs(lit) not in known, "constant lacks an original unit")
            known.add(abs(lit))
            fixed[abs(lit)] = lit > 0
            line = stream.readline().split()
        require(len(line) == 2 and line[0] == "assert", "missing assertion")
        assertion = int(line[1])
        require(assertion in units and abs(assertion) not in known, "invalid assertion")
        gates = []
        for line in stream:
            tag, *fields = line.split()
            v, table, arity, *payload = map(int, fields)
            require(tag == "gate" and 1 <= v <= variables and v not in known, "invalid gate")
            require(0 <= arity <= 4 and len(payload) > arity, "invalid gate width or witnesses")
            args, ids = payload[:arity], payload[arity:]
            require(len(set(args)) == arity and all(a in known for a in args), "unordered inputs")
            require(abs(assertion) not in args, "output predicate used as a wire")
            require(all(1 <= i <= len(clauses) for i in ids), "invalid clause index")
            witnesses = [clauses[i - 1] for i in ids]
            scope = set(args) | fixed.keys() | {v}
            require(all(all(abs(lit) in scope for lit in row) for row in witnesses), "unbound wire")
            derived = 0
            for mask in range(1 << arity):
                assignment = {**fixed, **{a: bool(mask & (1 << i)) for i, a in enumerate(args)}}
                permitted = []
                for bit in (False, True):
                    assignment[v] = bit
                    if all(any(assignment[abs(lit)] == (lit > 0) for lit in row) for row in witnesses):
                        permitted.append(bit)
                if v == abs(assertion):
                    bit = (assertion > 0) in permitted
                else:
                    require(len(permitted) == 1, f"gate {v} lacks a unique value")
                    bit = permitted[0]
                derived |= int(bit) << mask
            require(table == derived, f"gate {v} disagrees with its original clauses")
            gates.append((v, tuple(args), table))
            known.add(v)
        require(abs(assertion) in known, "missing output relation")
        return inputs, fixed, gates, abs(assertion)


def polynomial(args, table):
    """Boolean-ring interpolation. Table bit m uses input j at bit j of m."""
    if not args:
        return "-1" if table else "0"
    half = 1 << (len(args) - 1)
    lo = table & ((1 << half) - 1)
    hi = table >> half
    left = polynomial(args[:-1], lo)
    if lo == hi:
        return left
    x = f"v{args[-1]}"
    delta = polynomial(args[:-1], hi ^ lo)
    term = x if delta == "-1" else f"({x} & {delta})"
    if left == "0":
        return term
    if left == "-1":
        return f"(~{term})"
    return f"({left} ^ {term})"


def verify(inputs, fixed, gates, root):
    # Place frequently used inputs in the packed word. Other inputs form
    # ordinary nested binary loops. A gate is evaluated at the first scope
    # where all its inputs are bound, independently of the solver's Gray walk.
    deps = {v: {v} for v in inputs}
    deps.update({v: set() for v in fixed})
    usage = dict.fromkeys(inputs, 0)
    for v, args, _ in gates:
        deps[v] = set().union(*(deps[a] for a in args))
        for a in deps[v]:
            usage[a] += 1
    order = sorted(inputs, key=usage.get, reverse=True)
    low = min(len(order), 16)
    width = 1 << low
    mask = (1 << width) - 1
    values = [mask // ((1 << (1 << i)) + 1) << (1 << i) for i in range(low)]
    high = order[low:]
    level = {v: i + 1 for i, v in enumerate(high)}
    stages = [[] for _ in range(len(high) + 1)]
    for v, args, table in gates:
        stage = max((level.get(a, 0) for a in deps[v]), default=0)
        stages[stage].append(f"v{v} = {polynomial(args, table)}")

    params = ", ".join(["mask"] + [f"v{v}" for v in order[:low]])
    lines = [f"def check({params}):"]
    indent = " "
    for v, bit in fixed.items():
        lines.append(f"{indent}v{v} = {-int(bit)}")
    for i, assignments in enumerate(stages):
        if i:
            lines.append(f"{indent}for v{high[i-1]} in (0, -1):")
            indent += " "
        lines.extend(indent + assignment for assignment in assignments)
    lines.append(f"{indent}if v{root} & mask: return False")
    lines.append(" return True")
    # Source is constructed exclusively from checked integer wire IDs and
    # Boolean operators emitted by polynomial(). No certificate text is run.
    namespace = {"__builtins__": {}}
    exec("\n".join(lines), namespace)
    require(namespace["check"](mask, *values), "an assignment permits the asserted output")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cnf", type=Path)
    parser.add_argument("certificate", type=Path)
    args = parser.parse_args()
    variables, clauses = parse_cnf(args.cnf)
    inputs, fixed, gates, root = read_certificate(args.certificate, variables, clauses)
    verify(inputs, fixed, gates, root)
    print(f"s VERIFIED UNSAT ({len(gates)} gates, {1 << len(inputs)} assignments)")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(f"certificate rejected: {error}")

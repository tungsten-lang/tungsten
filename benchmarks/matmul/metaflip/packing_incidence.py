"""Bounded exact matching of factor-sharing incidence for packing only.

This deliberately ignores XOR relations and numeric factor names. It is NOT
a tensor isomorphism, flip-state identity, rank oracle or dominance rule.
A returned term permutation preserves all three equality partitions, letting
an already checked shared-bud/grid partition be transported for repricing.
"""
from collections import Counter, defaultdict


def profile(terms):
    terms = tuple(map(tuple, terms))
    if any(len(t) != 3 or any(type(v) is not int or v <= 0 for v in t) for t in terms):
        raise ValueError('invalid factor words')
    groups = [defaultdict(list) for _ in range(3)]
    for i, term in enumerate(terms):
        for axis in range(3):
            groups[axis][term[axis]].append(i)
    colors = [0]*len(terms)
    while terms:
        bucket_colors = [{word: tuple(sorted(Counter(colors[i] for i in indices).items()))
                          for word, indices in axis.items()} for axis in groups]
        features = [(colors[i], *(bucket_colors[a][term[a]] for a in range(3)))
                    for i, term in enumerate(terms)]
        names = {key: i for i, key in enumerate(sorted(set(features)))}
        refined = [names[key] for key in features]
        stable = len(set(refined)) == len(set(colors))
        colors = refined
        if stable:
            break
    signature = (tuple(tuple(sorted(len(indices) for indices in axis.values())) for axis in groups),
                 tuple(sorted(Counter(colors).items())))
    return dict(terms=terms, colors=colors, signature=signature)


def verify_permutation(source, target, permutation):
    if (len(source) != len(target) or len(permutation) != len(source) or
        any(type(i) is not int for i in permutation) or sorted(permutation) != list(range(len(source)))):
        raise ValueError('term map must be a bijection')
    for axis in range(3):
        forward, backward = {}, {}
        for i, j in enumerate(permutation):
            a, b = source[i][axis], target[j][axis]
            if forward.setdefault(a, b) != b or backward.setdefault(b, a) != a:
                raise ValueError('term map does not preserve factor equality in both directions')
    return True


def find_permutation(source, target, max_states=20000, max_terms=256):
    if type(max_states) is not int or max_states < 1 or type(max_terms) is not int or max_terms < 1:
        raise ValueError('invalid matching budget')
    left = source if isinstance(source, dict) else profile(source)
    right = target if isinstance(target, dict) else profile(target)
    source, target = left['terms'], right['terms']
    if len(source) != len(target) or left['signature'] != right['signature']:
        return dict(status='different', complete=True, states=0)
    if len(source) > max_terms:
        return dict(status='term_limit', complete=False, states=0)
    candidates = defaultdict(list)
    for j, color in enumerate(right['colors']):
        candidates[color].append(j)
    forward, backward = [{} for _ in range(3)], [{} for _ in range(3)]
    assignment, used = [-1]*len(source), set()
    states = 0
    class Limit(Exception):
        pass
    def visit():
        nonlocal states
        if len(used) == len(source):
            return assignment.copy()
        if states >= max_states:
            raise Limit
        states += 1
        remaining = [i for i, j in enumerate(assignment) if j < 0]
        i = min(remaining, key=lambda i: (-sum(source[i][a] in forward[a] for a in range(3)),
                                           len(candidates[left['colors'][i]]), i))
        for j in candidates[left['colors'][i]]:
            if j in used:
                continue
            if any(forward[a].get(source[i][a], target[j][a]) != target[j][a] or
                   backward[a].get(target[j][a], source[i][a]) != source[i][a] for a in range(3)):
                continue
            added = []
            for a in range(3):
                if source[i][a] not in forward[a]:
                    forward[a][source[i][a]] = target[j][a]
                    backward[a][target[j][a]] = source[i][a]
                    added.append(a)
            assignment[i] = j; used.add(j)
            answer = visit()
            if answer is not None:
                return answer
            assignment[i] = -1; used.remove(j)
            for a in added:
                del forward[a][source[i][a]]
                del backward[a][target[j][a]]
        return None
    try:
        answer = visit()
    except Limit:
        return dict(status='state_limit', complete=False, states=states)
    if answer is None:
        return dict(status='different', complete=True, states=states)
    verify_permutation(source, target, answer)
    return dict(status='matched', complete=True, states=states, permutation=answer)


def transport(groups, permutation):
    """Map literal term indices only; the caller still checks/reprices groups."""
    return [dict(group, indices=[permutation[i] for i in group['indices']]) for group in groups]
